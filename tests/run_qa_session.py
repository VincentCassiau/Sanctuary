#!/usr/bin/env python3
"""Drives one validation session, from the deployment check to the report.

Python 3, standard library only: no install, no pip, nothing to keep working
besides the interpreter the Mac already ships. Lua was the other candidate and
lost on one measurable point -- it has no exclusive file creation, so "never
overwrite a recording" would have been a convention rather than a guarantee.

What it does NOT do, deliberately: it never drives the game, never writes into
the account's SavedVariables, never deletes an old recording, and never
publishes anything. The clipboard is the border.

Usage:
    python3 tests/run_qa_session.py --print-plan
    python3 tests/run_qa_session.py [--wow /Applications/World\\ of\\ Warcraft]
"""

import argparse
import datetime
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)
# The repository root holds the add-on, tests/ and two documents, and nothing
# else. Importing a sibling module would drop a __pycache__ folder in there, so
# bytecode caching is turned off before the import rather than added to the
# ignore file.
sys.dont_write_bytecode = True

import qa_protocol  # noqa: E402

DEFAULT_WOW = "/Applications/World of Warcraft"
DEPLOYED_FILES = ("Sanctuary.toc", "Sanctuary.lua", "SanctuaryUI.lua", "Locales.lua")
STABLE_SECONDS = 3
STABLE_TIMEOUT = 180

ANSWER_DONE = "fait"
ANSWER_SKIPPED = "pas fait"
ANSWER_PROBLEM = "probleme"
ANSWERS = (ANSWER_DONE, ANSWER_SKIPPED, ANSWER_PROBLEM)


# ---------------------------------------------------------------------------
# Reading the repository
# ---------------------------------------------------------------------------

def read_repo_identity(repo=REPO):
    """The version and build the repository itself carries.

    Read, never hard-coded: a build constant frozen in this script is exactly
    how a session ends up certifying the wrong folder.
    """
    toc_version = toc_build = None
    with open(os.path.join(repo, "Sanctuary.toc"), encoding="utf-8") as handle:
        for line in handle:
            if line.startswith("## Version:"):
                toc_version = line.split(":", 1)[1].strip()
            elif line.startswith("## X-Sanctuary-Build:"):
                toc_build = line.split(":", 1)[1].strip()

    code_version = code_build = None
    with open(os.path.join(repo, "Sanctuary.lua"), encoding="utf-8") as handle:
        for line in handle:
            match = re.match(r'^local VERSION = "([^"]+)"', line)
            if match:
                code_version = match.group(1)
            match = re.match(r'^local BUILD_ID = "([^"]+)"', line)
            if match:
                code_build = match.group(1)
            if code_version and code_build:
                break

    return {
        "toc_version": toc_version, "toc_build": toc_build,
        "code_version": code_version, "code_build": code_build,
    }


def identity_problems(identity):
    problems = []
    for key in ("toc_version", "toc_build", "code_version", "code_build"):
        if not identity.get(key):
            problems.append("le depot ne declare pas %s" % key)
    if identity.get("toc_build") and identity.get("code_build") \
            and identity["toc_build"] != identity["code_build"]:
        problems.append("le build du .toc (%s) et celui du code (%s) different"
                        % (identity["toc_build"], identity["code_build"]))
    if identity.get("toc_version") and identity.get("code_version") \
            and identity["toc_version"] != identity["code_version"]:
        problems.append("la version du .toc (%s) et celle du code (%s) different"
                        % (identity["toc_version"], identity["code_version"]))
    return problems


def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def deployment_problems(repo, addon_dir):
    """Identity is not enough: the four files are compared byte for byte.

    "Deploiement: OK" in the report only proves the .toc and the code agree with
    each other, not that the folder on disk is the one that was built.
    """
    problems = []
    if not os.path.isdir(addon_dir):
        return ["le dossier de l'add-on est introuvable"]
    for name in DEPLOYED_FILES:
        source = os.path.join(repo, name)
        target = os.path.join(addon_dir, name)
        if not os.path.isfile(target):
            problems.append("%s manque dans le dossier deploye" % name)
            continue
        if sha256_of(source) != sha256_of(target):
            problems.append("%s deploye differe de celui du depot" % name)
    return problems


# ---------------------------------------------------------------------------
# Finding the account
# ---------------------------------------------------------------------------

def find_accounts(wtf_dir):
    """Only folders that actually hold a Sanctuary recording count.

    WTF/Account also holds a SavedVariables folder that is not an account, and
    the account folder holds .bak files the game writes: the exact name
    Sanctuary.lua is the only target.
    """
    accounts = []
    if not os.path.isdir(wtf_dir):
        return accounts
    for name in sorted(os.listdir(wtf_dir)):
        candidate = os.path.join(wtf_dir, name, "SavedVariables", "Sanctuary.lua")
        if os.path.isfile(candidate):
            accounts.append({
                "name": name,
                "path": candidate,
                "mtime": os.path.getmtime(candidate),
            })
    return accounts


# ---------------------------------------------------------------------------
# Archiving
# ---------------------------------------------------------------------------

def read_manifest_fields(path):
    """build and savedAt out of the recording, without executing it as Lua.

    The recording names itself; the archive is named from what it says, so two
    distinct sessions cannot land on the same file and re-archiving the same one
    is idempotent.
    """
    build = saved_at = None
    with open(path, encoding="utf-8", errors="replace") as handle:
        text = handle.read()
    match = re.search(r'\["build"\]\s*=\s*"([^"]+)"', text)
    if match:
        build = match.group(1)
    match = re.search(r'\["savedAt"\]\s*=\s*"([^"]+)"', text)
    if match:
        saved_at = match.group(1)
    return build, saved_at


def archive_name(protocol_id, build, saved_at):
    """The name is imposed, never typed.

    Both halves come from the recording itself, so two distinct sessions cannot
    collide and re-archiving the same recording lands on the same name.
    """
    stamp = "date-inconnue"
    match = re.match(r"^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})", saved_at or "")
    if match:
        stamp = "%s-%s-%s_%s%s" % match.groups()
    return "%s_build-%s_%s.lua" % (protocol_id, build or "build-inconnu", stamp)


def archive_exclusive(source, destination):
    """Creates the archive, or refuses.

    O_CREAT|O_EXCL is the whole point of the language choice: the guarantee is
    carried by the write, not by the name. Same name and same content is
    "already archived" and the session carries on; same name and different
    content is a hard stop -- never a silent suffix.
    """
    with open(source, "rb") as source_handle:
        payload = source_handle.read()
    try:
        handle = os.open(destination, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644)
    except FileExistsError:
        with open(destination, "rb") as existing_handle:
            existing = existing_handle.read()
        if existing == payload:
            return "deja-archive"
        raise RuntimeError(
            "une archive du meme nom existe avec un contenu different : %s"
            % os.path.basename(destination))
    with os.fdopen(handle, "wb") as out:
        out.write(payload)
    return "archive"


def wait_until_stable(path, stable_seconds=STABLE_SECONDS, timeout=STABLE_TIMEOUT,
                      sleep=time.sleep, now=time.time):
    """Waits for the game to have finished writing the recording.

    The client rewrites this file on every logout, and one recording has already
    been lost by archiving too early.
    """
    deadline = now() + timeout
    last_size, last_change = None, now()
    while now() < deadline:
        try:
            size = os.path.getsize(path)
        except OSError:
            size = None
        if size is not None and size == last_size:
            if now() - last_change >= stable_seconds:
                return True
        else:
            last_size, last_change = size, now()
        sleep(0.5)
    return False


# ---------------------------------------------------------------------------
# The offline check
# ---------------------------------------------------------------------------

def run_checker(recording, since=None, repo=REPO, lua="lua"):
    """Calls tests/check_qa_run.lua and carries its four codes as results.

    A non-zero exit is a business answer, never a crash: 0 complete, 1 blocking,
    2 unusable, 3 reserves. Argument list, never a shell -- the paths contain
    spaces.
    """
    command = [lua, os.path.join(repo, "tests", "check_qa_run.lua")]
    if since:
        command += ["--since", since]
    command.append(recording)
    try:
        completed = subprocess.run(command, capture_output=True, text=True, check=False)
    except OSError as error:
        return "", "impossible de lancer le controleur : %s" % error, 2
    return completed.stdout, completed.stderr, completed.returncode


# ---------------------------------------------------------------------------
# The verdict
# ---------------------------------------------------------------------------

def consolidated_verdict(answers, checker_code, completed, archive_state):
    """One sentence, from the answers and the checker, with no room for wishes."""
    steps_by_id = {step["id"]: step for step in qa_protocol.STEPS}

    if checker_code == 2:
        return "RELEVE INEXPLOITABLE"
    if any(answer.get("state") == ANSWER_PROBLEM for answer in answers.values()):
        return "NON CONFORME"
    if checker_code == 1:
        return "NON CONFORME"

    missing_mandatory = [
        step_id for step_id, answer in answers.items()
        if answer.get("state") == ANSWER_SKIPPED
        and steps_by_id.get(step_id, {}).get("obligatoire")
    ]
    if missing_mandatory or not completed or checker_code == 3 \
            or archive_state not in ("archive", "deja-archive"):
        return "INCOMPLET / AVEC RESERVES"
    return "CONFORME"


# ---------------------------------------------------------------------------
# The report
# ---------------------------------------------------------------------------

def sanitize(text, secrets=()):
    """Removes what the report has no business carrying.

    No absolute path, no account folder name. The recording itself never travels
    -- only its name, its size and its fingerprint.
    """
    if not text:
        return text
    cleaned = text
    for secret in secrets:
        if secret:
            cleaned = cleaned.replace(secret, "<masque>")
    cleaned = re.sub(r'(/[^\s"\']+)+/([A-Za-z0-9_.-]+)', r'\2', cleaned)
    return cleaned


def build_report(context, answers, remark, checker):
    lines = []
    lines.append("# Session de validation -- %s" % context["protocol_id"])
    lines.append("")
    lines.append("- Protocole : `%s`" % context["protocol_id"])
    lines.append("- Build : `%s` (version %s)" % (context["build"], context["version"]))
    lines.append("- Debut : %s" % context["started_at"])
    lines.append("- Fin : %s" % context["finished_at"])
    lines.append("- Etat : %s" % ("terminee" if context["completed"] else "interrompue"))
    lines.append("- Verdict operateur : %s" % context["operator_verdict"])
    lines.append("- Verdict controleur : code %s" % checker["code"])
    lines.append("- **Verdict consolide : %s**" % context["verdict"])
    lines.append("")

    lines.append("## Etapes")
    lines.append("")
    lines.append("| Etape | Phase | Etat | Remarque |")
    lines.append("|---|---|---|---|")
    for step in qa_protocol.played_steps():
        answer = answers.get(step["id"], {})
        state = answer.get("state", "non atteinte")
        if not step["obligatoire"] and state == ANSWER_SKIPPED:
            state = "pas fait (facultative)"
        comment = (answer.get("comment") or "").replace("\n", " ").strip()
        phase = qa_protocol.PHASES.get(step["phase"], "-")
        lines.append("| %s -- %s | %s | %s | %s |"
                     % (step["id"], step["titre"], phase, state, comment or "-"))
    lines.append("")

    lines.append("## Remarque generale")
    lines.append("")
    lines.append((remark or "").strip() or "_(vide)_")
    lines.append("")

    lines.append("## Archive")
    lines.append("")
    lines.append("- Nom : `%s`" % context["archive_name"])
    lines.append("- Etat : %s" % context["archive_state"])
    lines.append("- Taille : %s octets" % context["archive_size"])
    lines.append("- Empreinte SHA-256 : `%s`" % context["archive_sha"])
    lines.append("")

    lines.append("## Controle du releve")
    lines.append("")
    lines.append("Code de sortie : `%s`" % checker["code"])
    lines.append("")
    lines.append("```text")
    lines.append((checker["stdout"] or "").rstrip())
    if checker.get("stderr"):
        lines.append((checker["stderr"] or "").rstrip())
    lines.append("```")
    lines.append("")
    return "\n".join(lines)


def copy_to_clipboard(text):
    try:
        process = subprocess.run(["pbcopy"], input=text, text=True, check=False)
        return process.returncode == 0
    except OSError:
        return False


# ---------------------------------------------------------------------------
# Resume
# ---------------------------------------------------------------------------

def protocol_fingerprint():
    """Changes whenever a step changes.

    A resumed session must not mix two protocols: half the answers would be
    about steps that no longer say the same thing.
    """
    payload = json.dumps(
        [[s["id"], s["kind"], s["phase"], s["titre"], s["action"], s["attendu"],
          s["echec_si"], s["obligatoire"], s["marqueurs"]] for s in qa_protocol.STEPS],
        sort_keys=True, ensure_ascii=True)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()[:16]


def save_state(path, state):
    """Written atomically: an interrupted write must not destroy the answers."""
    temporary = path + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(state, handle, ensure_ascii=False, indent=2)
    os.replace(temporary, path)


def load_state(path):
    if not os.path.isfile(path):
        return None
    try:
        with open(path, encoding="utf-8") as handle:
            state = json.load(handle)
    except (OSError, ValueError):
        return None
    if state.get("fingerprint") != protocol_fingerprint():
        return {"stale": True}
    return state


# ---------------------------------------------------------------------------
# The command line
# ---------------------------------------------------------------------------

def ask(prompt, valid=None, allow_empty=False, reader=input):
    while True:
        answer = reader("%s " % prompt).strip()
        if not answer and allow_empty:
            return ""
        if valid is None and answer:
            return answer
        if valid and answer in valid:
            return answer
        print("Reponse attendue : %s" % (", ".join(valid) if valid else "un texte"))


def play(context, state, state_path, reader=input, printer=print):
    answers = state.setdefault("answers", {})
    remark = state.get("remark")
    steps = qa_protocol.played_steps()
    total_phases = len(qa_protocol.PHASES)

    for index, step in enumerate(steps, start=1):
        if step["id"] in answers:
            continue
        printer("")
        printer("=" * 72)
        printer("phase %d / %d -- %s" % (step["phase"], total_phases,
                                         qa_protocol.PHASES[step["phase"]]))
        printer("etape %d / %d -- %s : %s%s"
                % (index, len(steps), step["id"], step["titre"],
                   "" if step["obligatoire"] else "  (facultative)"))
        printer("")
        printer("A FAIRE   : %s" % step["action"])
        printer("ATTENDU   : %s" % step["attendu"])
        if step["echec_si"]:
            printer("ECHEC SI  : %s" % step["echec_si"])
        printer("")

        if step["kind"] == "remark":
            remark = ask("Votre remarque (Entree pour laisser vide) :",
                         allow_empty=True, reader=reader)
            state["remark"] = remark
            answers[step["id"]] = {"state": ANSWER_DONE, "comment": ""}
            save_state(state_path, state)
            continue

        answer = ask("fait / pas fait / probleme ?", valid=list(ANSWERS), reader=reader)
        comment = ask("Commentaire (Entree pour passer) :", allow_empty=True, reader=reader)
        answers[step["id"]] = {"state": answer, "comment": comment}
        save_state(state_path, state)

        if answer == ANSWER_PROBLEM and step["id"] == "B.1":
            printer("")
            printer("Etape bloquante en echec : la session s'arrete ici.")
            state["completed"] = False
            save_state(state_path, state)
            return answers, remark, False

    state["completed"] = True
    save_state(state_path, state)
    return answers, remark, True


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--print-plan", action="store_true",
                        help="print the readable plan and exit")
    parser.add_argument("--wow", default=DEFAULT_WOW,
                        help="World of Warcraft installation folder")
    parser.add_argument("--lua", default="lua", help="lua interpreter to call")
    args = parser.parse_args(argv)

    if args.print_plan:
        print(qa_protocol.print_plan())
        return 0

    problems = qa_protocol.check()
    if problems:
        for problem in problems:
            print("protocole : %s" % problem, file=sys.stderr)
        return 1

    identity = read_repo_identity()
    problems = identity_problems(identity)
    if problems:
        for problem in problems:
            print("depot : %s" % problem, file=sys.stderr)
        return 1

    retail = os.path.join(args.wow, "_retail_")
    addon_dir = os.path.join(retail, "Interface", "AddOns", "Sanctuary")
    problems = deployment_problems(REPO, addon_dir)
    if problems:
        for problem in problems:
            print("deploiement : %s" % problem, file=sys.stderr)
        print("La session ne demarre pas tant que le dossier deploye n'est pas "
              "celui du depot.", file=sys.stderr)
        return 1

    accounts = find_accounts(os.path.join(retail, "WTF", "Account"))
    if not accounts:
        print("aucun compte ne porte un SavedVariables/Sanctuary.lua", file=sys.stderr)
        return 1
    if len(accounts) == 1:
        account = accounts[0]
    else:
        print("Plusieurs comptes portent un relevé Sanctuary :")
        for index, candidate in enumerate(accounts, start=1):
            when = datetime.datetime.fromtimestamp(candidate["mtime"])
            print("  %d. %s (modifie le %s)" % (index, candidate["name"],
                                                when.strftime("%Y-%m-%d %H:%M")))
        choice = ask("Numero du compte :",
                     valid=[str(i) for i in range(1, len(accounts) + 1)])
        account = accounts[int(choice) - 1]

    runs_dir = os.path.join(REPO, "internal_docs", "qa_runs")
    os.makedirs(runs_dir, exist_ok=True)
    started_at = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    backup = os.path.join(runs_dir, "avant-session_%s.lua"
                          % started_at.replace(":", "").replace(" ", "_"))
    shutil.copyfile(account["path"], backup)

    state_path = os.path.join(runs_dir, ".session-state.json")
    state = load_state(state_path)
    if state and state.get("stale"):
        print("Le protocole a change depuis la passe interrompue : elle ne peut "
              "pas etre reprise. Supprimez %s pour recommencer."
              % os.path.basename(state_path), file=sys.stderr)
        return 1
    if not state:
        state = {"fingerprint": protocol_fingerprint(), "answers": {},
                 "started_at": started_at, "remark": ""}
    started_at = state.get("started_at", started_at)
    save_state(state_path, state)

    print("Protocole %s -- build %s. Jouez les etapes dans l'ordre."
          % (qa_protocol.PROTOCOL_ID, identity["code_build"]))
    answers, remark, completed = play(state, state, state_path)

    print("")
    print("Quittez completement le jeu maintenant : le fichier de reglages est "
          "ecrit a la fermeture.")
    ask("Entree une fois le jeu ferme :", allow_empty=True)
    if not wait_until_stable(account["path"]):
        print("le fichier de reglages continue de changer : le jeu est-il ferme ?",
              file=sys.stderr)

    build, saved_at = read_manifest_fields(account["path"])
    destination = os.path.join(runs_dir,
                               archive_name(qa_protocol.PROTOCOL_ID, build, saved_at))
    try:
        archive_state = archive_exclusive(account["path"], destination)
    except RuntimeError as error:
        print(str(error), file=sys.stderr)
        return 1

    stdout, stderr, code = run_checker(destination, since=started_at, lua=args.lua)

    operator_verdict = "CONFORME"
    if any(answer.get("state") == ANSWER_PROBLEM for answer in answers.values()):
        operator_verdict = "NON CONFORME"
    elif not completed:
        operator_verdict = "INTERROMPUE"

    context = {
        "protocol_id": qa_protocol.PROTOCOL_ID,
        "build": identity["code_build"],
        "version": identity["code_version"],
        "started_at": started_at,
        "finished_at": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "completed": completed,
        "operator_verdict": operator_verdict,
        "archive_name": os.path.basename(destination),
        "archive_state": archive_state,
        "archive_size": os.path.getsize(destination),
        "archive_sha": sha256_of(destination),
    }
    context["verdict"] = consolidated_verdict(answers, code, completed, archive_state)

    checker = {
        "code": code,
        "stdout": sanitize(stdout, secrets=(account["name"], args.wow, REPO)),
        "stderr": sanitize(stderr, secrets=(account["name"], args.wow, REPO)),
    }
    report = build_report(context, answers, remark, checker)

    if copy_to_clipboard(report):
        print("")
        print("Compte rendu copie dans le presse-papiers.")
    else:
        print("")
        print(report)

    os.remove(state_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
