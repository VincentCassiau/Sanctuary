#!/usr/bin/env python3
"""Tests for the session protocol and its runner.

Standard library only, and no fixture taken from a real recording: a session
file carries an account name and a friends list, and a test suite is not the
place for either. Everything below builds its own tree in a temporary folder.

Usage: python3 tests/test_qa_session.py
"""

import contextlib
import io
import os
import shutil
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)
# The repository root holds the add-on, tests/ and two documents, and nothing
# else. Importing a sibling module would drop a __pycache__ folder in there, so
# bytecode caching is turned off before the import rather than added to the
# ignore file.
sys.dont_write_bytecode = True

import qa_protocol  # noqa: E402
import run_qa_session as runner  # noqa: E402


class ProtocolTests(unittest.TestCase):
    def test_structure_is_sound(self):
        self.assertEqual(qa_protocol.check(), [])

    def test_every_phase_is_played(self):
        phases = {step["phase"] for step in qa_protocol.STEPS if step["kind"] == "play"}
        self.assertEqual(phases, set(qa_protocol.PHASES))

    def test_played_steps_run_in_phase_order(self):
        phases = [step["phase"] for step in qa_protocol.played_steps()]
        self.assertEqual(phases, sorted(phases))

    def test_runner_steps_are_not_played(self):
        for step in qa_protocol.played_steps():
            self.assertNotEqual(step["kind"], "runner")

    def test_markers_are_declared_once_each(self):
        markers = qa_protocol.claimed_markers()
        self.assertEqual(len(markers), len(set(markers)))
        self.assertIn("popupMaskAwaitingEvent", markers)

    def test_plan_names_every_played_step(self):
        plan = qa_protocol.print_plan()
        for step in qa_protocol.played_steps():
            self.assertIn(step["id"], plan)

    def test_minimap_drag_expectation_matches_the_code(self):
        """D.5 asks the tester to watch the button follow the cursor.

        The code used to post a flag on OnDragStart that nothing read, so the
        icon only jumped at the release: the protocol asked for something the
        add-on did not do, and a session would have reported a false failure.
        This ties the two together -- change either side and this test says so.
        """
        step = next(s for s in qa_protocol.STEPS if s["id"] == "D.5")
        self.assertIn("suit le curseur", step["attendu"])
        with open(os.path.join(REPO, "SanctuaryUI.lua"), encoding="utf-8") as handle:
            source = handle.read()
        drag_start = source.index('btn:SetScript("OnDragStart"')
        drag_stop = source.index('btn:SetScript("OnDragStop"', drag_start)
        self.assertIn('SetScript("OnUpdate", dragMinimapButton)', source[drag_start:drag_stop])

    def test_check_reports_a_broken_step(self):
        broken = dict(qa_protocol.STEPS[1])
        broken["titre"] = "  "
        original = qa_protocol.STEPS[1]
        qa_protocol.STEPS[1] = broken
        try:
            problems = qa_protocol.check()
            self.assertTrue(any("titre" in problem for problem in problems))
        finally:
            qa_protocol.STEPS[1] = original


class IdentityTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root)

    def write_repo(self, toc_version="0.3.2", toc_build="B1",
                   code_version="0.3.2", code_build="B1"):
        with open(os.path.join(self.root, "Sanctuary.toc"), "w", encoding="utf-8") as handle:
            handle.write("## Version: %s\n## X-Sanctuary-Build: %s\n"
                         % (toc_version, toc_build))
        with open(os.path.join(self.root, "Sanctuary.lua"), "w", encoding="utf-8") as handle:
            handle.write('local VERSION = "%s"\nlocal BUILD_ID = "%s"\n'
                         % (code_version, code_build))

    def test_reads_both_identities(self):
        self.write_repo()
        identity = runner.read_repo_identity(self.root)
        self.assertEqual(identity["toc_build"], "B1")
        self.assertEqual(identity["code_build"], "B1")
        self.assertEqual(runner.identity_problems(identity), [])

    def test_a_stale_toc_build_is_refused(self):
        self.write_repo(toc_build="B0")
        problems = runner.identity_problems(runner.read_repo_identity(self.root))
        self.assertTrue(any("build" in problem for problem in problems))

    def test_the_real_repository_is_consistent(self):
        identity = runner.read_repo_identity(REPO)
        self.assertEqual(runner.identity_problems(identity), [])


class DeploymentTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root)
        self.repo = os.path.join(self.root, "repo")
        self.addon = os.path.join(self.root, "addon")
        os.makedirs(self.repo)
        os.makedirs(self.addon)
        for name in runner.DEPLOYED_FILES:
            for folder in (self.repo, self.addon):
                with open(os.path.join(folder, name), "w", encoding="utf-8") as handle:
                    handle.write("same content for %s\n" % name)

    def test_identical_folders_pass(self):
        self.assertEqual(runner.deployment_problems(self.repo, self.addon), [])

    def test_a_single_stale_file_is_caught(self):
        with open(os.path.join(self.addon, "SanctuaryUI.lua"), "a", encoding="utf-8") as handle:
            handle.write("stale\n")
        problems = runner.deployment_problems(self.repo, self.addon)
        self.assertEqual(len(problems), 1)
        self.assertIn("SanctuaryUI.lua", problems[0])

    def test_a_missing_file_is_caught(self):
        os.remove(os.path.join(self.addon, "Locales.lua"))
        problems = runner.deployment_problems(self.repo, self.addon)
        self.assertTrue(any("Locales.lua" in problem for problem in problems))

    def test_a_missing_folder_is_caught(self):
        problems = runner.deployment_problems(self.repo, os.path.join(self.root, "nope"))
        self.assertEqual(len(problems), 1)


class AccountTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root)
        self.wtf = os.path.join(self.root, "Account")
        os.makedirs(self.wtf)

    def add_account(self, name, with_recording=True, extra=()):
        folder = os.path.join(self.wtf, name, "SavedVariables")
        os.makedirs(folder, exist_ok=True)
        if with_recording:
            with open(os.path.join(folder, "Sanctuary.lua"), "w", encoding="utf-8") as handle:
                handle.write("SanctuaryDB = {}\n")
        for other in extra:
            with open(os.path.join(folder, other), "w", encoding="utf-8") as handle:
                handle.write("noise\n")

    def test_no_account_at_all(self):
        self.assertEqual(runner.find_accounts(self.wtf), [])

    def test_one_account(self):
        self.add_account("ACCOUNTONE")
        found = runner.find_accounts(self.wtf)
        self.assertEqual(len(found), 1)
        self.assertEqual(found[0]["name"], "ACCOUNTONE")

    def test_several_accounts_are_all_offered(self):
        self.add_account("ACCOUNTONE")
        self.add_account("ACCOUNTTWO")
        self.assertEqual(len(runner.find_accounts(self.wtf)), 2)

    def test_a_folder_without_a_recording_is_not_an_account(self):
        # WTF/Account also holds a SavedVariables folder that is not an account.
        self.add_account("SavedVariables", with_recording=False)
        self.add_account("ACCOUNTONE")
        self.assertEqual([a["name"] for a in runner.find_accounts(self.wtf)], ["ACCOUNTONE"])

    def test_only_the_exact_name_counts(self):
        # The folder also holds .bak files the game writes, and old copies.
        self.add_account("ACCOUNTONE", with_recording=False,
                         extra=("Sanctuary.lua.bak", "Sanctuary-juillet.lua"))
        self.assertEqual(runner.find_accounts(self.wtf), [])


class ArchiveTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root)
        self.source = os.path.join(self.root, "Sanctuary.lua")
        with open(self.source, "w", encoding="utf-8") as handle:
            handle.write('SanctuaryDB = { ["reportManifest"] = { ["build"] = "20260821-1",\n'
                         '    ["savedAt"] = "2026-08-21 20:30:11" } }\n')

    def test_the_name_comes_from_the_recording(self):
        build, saved_at = runner.read_manifest_fields(self.source)
        self.assertEqual(build, "20260821-1")
        name = runner.archive_name("sanctuary-1.0.0", build, saved_at)
        self.assertEqual(name, "sanctuary-1.0.0_build-20260821-1_2026-08-21_2030.lua")

    def test_a_recording_with_no_manifest_still_gets_a_name(self):
        name = runner.archive_name("sanctuary-1.0.0", None, None)
        self.assertIn("build-inconnu", name)
        self.assertIn("date-inconnue", name)

    def test_archiving_twice_is_idempotent(self):
        destination = os.path.join(self.root, "archive.lua")
        self.assertEqual(runner.archive_exclusive(self.source, destination), "archive")
        self.assertEqual(runner.archive_exclusive(self.source, destination), "deja-archive")

    def test_a_collision_with_different_content_is_a_hard_stop(self):
        destination = os.path.join(self.root, "archive.lua")
        with open(destination, "w", encoding="utf-8") as handle:
            handle.write("another session entirely\n")
        with self.assertRaises(RuntimeError):
            runner.archive_exclusive(self.source, destination)
        # And the file that was there is untouched.
        with open(destination, encoding="utf-8") as handle:
            self.assertEqual(handle.read(), "another session entirely\n")

    def test_two_simultaneous_runs_cannot_overwrite_each_other(self):
        # The guarantee is carried by the write, not by the name: the second
        # exclusive create fails even between the check and the write.
        destination = os.path.join(self.root, "archive.lua")
        runner.archive_exclusive(self.source, destination)
        other = os.path.join(self.root, "other.lua")
        with open(other, "w", encoding="utf-8") as handle:
            handle.write("different\n")
        with self.assertRaises(RuntimeError):
            runner.archive_exclusive(other, destination)

    def test_stability_wait_gives_up_rather_than_hanging(self):
        clock = {"now": 0.0}

        def now():
            return clock["now"]

        def sleep(seconds):
            clock["now"] += seconds
            with open(self.source, "a", encoding="utf-8") as handle:
                handle.write("still writing\n")

        self.assertFalse(runner.wait_until_stable(self.source, stable_seconds=2,
                                                  timeout=5, sleep=sleep, now=now))

    def test_stability_wait_returns_once_the_size_settles(self):
        clock = {"now": 0.0}

        def now():
            return clock["now"]

        def sleep(seconds):
            clock["now"] += seconds

        self.assertTrue(runner.wait_until_stable(self.source, stable_seconds=1,
                                                 timeout=30, sleep=sleep, now=now))


class CheckerTests(unittest.TestCase):
    """The runner does not reimplement the checker: it carries its four codes."""

    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root)

    def fake_checker(self, code, output="sortie du controleur"):
        repo = os.path.join(self.root, "repo")
        os.makedirs(os.path.join(repo, "tests"), exist_ok=True)
        script = os.path.join(repo, "tests", "check_qa_run.lua")
        with open(script, "w", encoding="utf-8") as handle:
            handle.write("io.write(%r)\nos.exit(%d)\n" % (output + "\n", code))
        return repo

    def test_each_code_is_carried_through(self):
        for code in (0, 1, 2, 3):
            repo = self.fake_checker(code)
            stdout, _, actual = runner.run_checker("recording.lua", repo=repo)
            self.assertEqual(actual, code)
            self.assertIn("sortie du controleur", stdout)

    def test_a_missing_interpreter_is_a_business_answer_not_a_crash(self):
        repo = self.fake_checker(0)
        _, stderr, code = runner.run_checker("recording.lua", repo=repo,
                                             lua="lua-that-does-not-exist")
        self.assertEqual(code, 2)
        self.assertIn("controleur", stderr)

    def test_the_since_flag_is_passed_as_an_argument(self):
        repo = os.path.join(self.root, "echo")
        os.makedirs(os.path.join(repo, "tests"), exist_ok=True)
        script = os.path.join(repo, "tests", "check_qa_run.lua")
        with open(script, "w", encoding="utf-8") as handle:
            handle.write("for i = 1, #arg do io.write(arg[i], '\\n') end\n")
        stdout, _, _ = runner.run_checker("recording.lua", since="2026-08-21 18:00:00",
                                          repo=repo)
        self.assertIn("--since", stdout)
        self.assertIn("2026-08-21 18:00:00", stdout)

    def test_the_real_checker_answers_on_the_real_recording(self):
        recording = os.path.join(
            REPO, "internal_docs", "qa_runs",
            "CYBE-14_niveau1_build-20260820-8_2026-08-20_2326.lua")
        if not os.path.isfile(recording):
            self.skipTest("no recording in this working copy")
        _, _, code = runner.run_checker(recording)
        self.assertEqual(code, 3)


class VerdictTests(unittest.TestCase):
    def answers(self, **states):
        return {step_id: {"state": state} for step_id, state in states.items()}

    def test_a_clean_pass_is_conforme(self):
        answers = self.answers(**{step["id"]: runner.ANSWER_DONE
                                  for step in qa_protocol.played_steps()})
        self.assertEqual(
            runner.consolidated_verdict(answers, 0, True, "archive"), "CONFORME")

    def test_one_problem_is_non_conforme(self):
        answers = self.answers(**{"A.1": runner.ANSWER_PROBLEM})
        self.assertEqual(
            runner.consolidated_verdict(answers, 0, True, "archive"), "NON CONFORME")

    def test_a_blocking_checker_is_non_conforme(self):
        self.assertEqual(
            runner.consolidated_verdict({}, 1, True, "archive"), "NON CONFORME")

    def test_an_unusable_recording_wins_over_everything(self):
        answers = self.answers(**{"A.1": runner.ANSWER_PROBLEM})
        self.assertEqual(
            runner.consolidated_verdict(answers, 2, True, "archive"),
            "RELEVE INEXPLOITABLE")

    def test_reserves_are_reserves(self):
        self.assertEqual(
            runner.consolidated_verdict({}, 3, True, "archive"),
            "INCOMPLET / AVEC RESERVES")

    def test_a_skipped_mandatory_step_is_reserves(self):
        answers = self.answers(**{"A.1": runner.ANSWER_SKIPPED})
        self.assertEqual(
            runner.consolidated_verdict(answers, 0, True, "archive"),
            "INCOMPLET / AVEC RESERVES")

    def test_a_skipped_optional_step_does_not_fail_the_pass(self):
        answers = self.answers(**{step["id"]: runner.ANSWER_DONE
                                  for step in qa_protocol.played_steps()})
        answers["C.2"] = {"state": runner.ANSWER_SKIPPED}
        answers["D.4"] = {"state": runner.ANSWER_SKIPPED}
        self.assertEqual(
            runner.consolidated_verdict(answers, 0, True, "archive"), "CONFORME")

    def test_an_interrupted_session_is_reserves(self):
        self.assertEqual(
            runner.consolidated_verdict({}, 0, False, "archive"),
            "INCOMPLET / AVEC RESERVES")


class ResumeTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root)
        self.path = os.path.join(self.root, "state.json")

    def test_state_survives_a_round_trip(self):
        state = {"fingerprint": runner.protocol_fingerprint(),
                 "answers": {"A.1": {"state": "fait", "comment": "ligne\nsuivante"}}}
        runner.save_state(self.path, state)
        loaded = runner.load_state(self.path)
        self.assertEqual(loaded["answers"]["A.1"]["comment"], "ligne\nsuivante")

    def test_a_changed_protocol_refuses_the_resume(self):
        runner.save_state(self.path, {"fingerprint": "not-the-one", "answers": {}})
        self.assertEqual(runner.load_state(self.path), {"stale": True})

    def test_no_state_at_all(self):
        self.assertIsNone(runner.load_state(self.path))

    def test_a_corrupt_state_is_not_a_crash(self):
        with open(self.path, "w", encoding="utf-8") as handle:
            handle.write("{ not json")
        self.assertIsNone(runner.load_state(self.path))

    def test_the_fingerprint_changes_with_the_protocol(self):
        first = runner.protocol_fingerprint()
        original = qa_protocol.STEPS[1]
        changed = dict(original)
        changed["attendu"] = original["attendu"] + " et autre chose"
        qa_protocol.STEPS[1] = changed
        try:
            self.assertNotEqual(runner.protocol_fingerprint(), first)
        finally:
            qa_protocol.STEPS[1] = original


class ReportTests(unittest.TestCase):
    def context(self, **overrides):
        base = {
            "protocol_id": qa_protocol.PROTOCOL_ID,
            "build": "20260821-1", "version": "0.3.2",
            "started_at": "2026-08-21 18:00:00",
            "finished_at": "2026-08-21 18:32:00",
            "completed": True, "operator_verdict": "CONFORME",
            "archive_name": "sanctuary-1.0.0_build-20260821-1_2026-08-21_2030.lua",
            "archive_state": "archive", "archive_size": 12345,
            "archive_sha": "deadbeef", "verdict": "CONFORME",
            "stability": runner.STABILITY_OK,
        }
        base.update(overrides)
        return base

    def report(self, answers=None, remark="", checker=None):
        return runner.build_report(
            self.context(), answers or {}, remark,
            checker or {"code": 0, "stdout": "tout va bien", "stderr": ""})

    def test_every_step_has_a_row(self):
        report = self.report()
        for step in qa_protocol.played_steps():
            self.assertIn(step["id"], report)

    def test_an_optional_step_is_named_as_such(self):
        answers = {"C.2": {"state": runner.ANSWER_SKIPPED, "comment": ""}}
        self.assertIn("pas fait (facultative)", self.report(answers))

    def test_a_multiline_comment_stays_on_its_row(self):
        answers = {"A.1": {"state": runner.ANSWER_DONE, "comment": "une ligne\nune autre"}}
        report = self.report(answers)
        for line in report.splitlines():
            if line.startswith("| A.1"):
                self.assertIn("une ligne une autre", line)
                break
        else:
            self.fail("the A.1 row is missing")

    def test_both_verdicts_are_reported_separately(self):
        report = self.report(checker={"code": 3, "stdout": "reserves", "stderr": ""})
        self.assertIn("Verdict operateur", report)
        self.assertIn("Verdict controleur : code 3", report)
        self.assertIn("Verdict consolide", report)

    def test_the_checker_output_travels_verbatim_in_a_block(self):
        report = self.report(checker={"code": 1, "stdout": "ECHEC BLOQUANT", "stderr": "detail"})
        self.assertIn("```text", report)
        self.assertIn("ECHEC BLOQUANT", report)
        self.assertIn("detail", report)

    def test_the_remark_is_carried_and_an_empty_one_is_stated(self):
        self.assertIn("mon retour", self.report(remark="mon retour"))
        self.assertIn("_(vide)_", self.report(remark="   "))

    def test_no_absolute_path_and_no_account_name_reaches_the_report(self):
        checker = {
            "code": 0,
            "stdout": runner.sanitize(
                "Fichier   : /Users/someone/World of Warcraft/_retail_/WTF/Account/"
                "ELITELINKTENCHU/SavedVariables/Sanctuary.lua",
                secrets=("ELITELINKTENCHU",)),
            "stderr": "",
        }
        report = self.report(checker=checker)
        self.assertNotIn("ELITELINKTENCHU", report)
        self.assertNotIn("/Users/someone", report)
        self.assertIn("Sanctuary.lua", report)

    def test_the_recording_itself_never_travels(self):
        report = self.report()
        self.assertIn("Empreinte SHA-256", report)
        self.assertIn("12345 octets", report)
        self.assertNotIn("SanctuaryDB =", report)

    def test_the_report_says_whether_the_file_had_settled(self):
        self.assertIn("Stabilite du fichier : %s" % runner.STABILITY_OK,
                      self.report())


class StabilityGateTests(unittest.TestCase):
    """A recording that is still being written is not archived at all.

    The runner used to print a warning on stderr and carry on: it archived, ran
    the checker and printed a verdict, so a report could announce an answer read
    off a moving file with nothing saying so.
    """

    def confirm(self, results):
        asked = []
        outcomes = list(results)
        ok, note = runner.confirm_recording_stable(
            "/nowhere/Sanctuary.lua",
            ask=lambda prompt, **kwargs: asked.append(prompt) or "",
            wait=lambda path: outcomes.pop(0),
            printer=lambda *args, **kwargs: None)
        return ok, note, asked

    def test_a_file_that_has_settled_asks_nothing(self):
        ok, note, asked = self.confirm([True])
        self.assertTrue(ok)
        self.assertEqual(note, runner.STABILITY_OK)
        self.assertEqual(asked, [])

    def test_a_first_failure_asks_the_operator_and_waits_again(self):
        ok, note, asked = self.confirm([False, True])
        self.assertTrue(ok)
        self.assertEqual(note, runner.STABILITY_RETRY)
        self.assertEqual(len(asked), 1)

    def test_a_second_failure_is_a_refusal(self):
        ok, note, asked = self.confirm([False, False])
        self.assertFalse(ok)
        self.assertEqual(note, runner.STABILITY_FAILED)
        self.assertEqual(len(asked), 1)

    def test_the_runner_stops_before_archiving(self):
        """main() returns non-zero and archive_exclusive is never reached."""
        temp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, temp, True)
        account = os.path.join(temp, "Sanctuary.lua")
        with open(account, "w") as handle:
            handle.write("SanctuaryDB = {}\n")

        def refuse_archive(*args, **kwargs):
            self.fail("the recording was archived despite an unstable file")

        saved = {name: getattr(runner, name) for name in
                 ("REPO", "read_repo_identity", "identity_problems",
                  "deployment_problems", "find_accounts", "play", "ask",
                  "confirm_recording_stable", "archive_exclusive",
                  "read_manifest_fields", "run_checker")}
        try:
            runner.REPO = temp
            runner.read_repo_identity = lambda: {"code_build": "b", "code_version": "v"}
            runner.identity_problems = lambda identity: []
            runner.deployment_problems = lambda repo, addon: []
            runner.find_accounts = lambda root: [
                {"name": "ACCOUNT", "path": account, "mtime": 0}]
            runner.play = lambda *args, **kwargs: ({}, "", True)
            runner.ask = lambda prompt, **kwargs: ""
            runner.confirm_recording_stable = lambda path: (False, runner.STABILITY_FAILED)
            runner.archive_exclusive = refuse_archive
            runner.read_manifest_fields = refuse_archive
            runner.run_checker = refuse_archive
            with contextlib.redirect_stdout(io.StringIO()), \
                    contextlib.redirect_stderr(io.StringIO()):
                code = runner.main(["--wow", temp])
        finally:
            for name, value in saved.items():
                setattr(runner, name, value)
        self.assertNotEqual(code, 0)


if __name__ == "__main__":
    unittest.main(verbosity=1)
