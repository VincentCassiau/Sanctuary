#!/usr/bin/env python3
"""The validation session, as data.

The steps are not text inside an engine: they are this table. The runner reads
it, the readable Markdown plan is derived from it (--print-plan), and the machine
markers the closing check looks for are declared by the steps that produce them
(--markers). Nothing about a session is written twice, so nothing about a session
can drift.

Usage:
    python3 tests/qa_protocol.py --check        structural validation, exit 0
    python3 tests/qa_protocol.py --markers      the markers the steps claim
    python3 tests/qa_protocol.py --print-plan   the readable plan
"""

import argparse
import sys

PROTOCOL_ID = "sanctuary-1.0.0"

# Seven phases, so the CLI can say "phase 3 / 7" instead of "step 9 / 21". A
# person playing a session needs to know where they are, not how far they have
# counted.
PHASES = {
    1: "Ouverture",
    2: "Questions",
    3: "Listes et testeur",
    4: "Journal et Avance",
    5: "Diagnostics",
    6: "Donjon",
    7: "Cloture",
}

# kind:
#   "runner"  the runner does it, nobody is asked anything
#   "play"    a step played in game, answered fait / pas fait / probleme
#   "remark"  a free remark, mandatory but allowed to be empty
STEPS = [
    dict(
        id="R.0", phase=None, kind="runner",
        titre="Controle de deploiement",
        action="Sauvegarde du Sanctuary.lua du compte, creation de "
               "internal_docs/qa_runs/, controle d'identite de build et "
               "comparaison de contenu des 4 fichiers deposes.",
        attendu="Les quatre fichiers du dossier deploye sont identiques a ceux "
                "du depot, et le build annonce est le meme partout.",
        echec_si="Un ecart de contenu ou d'identite : la session ne demarre pas.",
        obligatoire=True, marqueurs=[],
    ),
    dict(
        id="A.1", phase=1, kind="play",
        titre="Afficher les erreurs Lua",
        action="Taper /console scriptErrors 1",
        attendu="Le client confirme l'activation.",
        echec_si="La commande est refusee.",
        obligatoire=True, marqueurs=[],
    ),
    dict(
        id="A.2", phase=1, kind="play",
        titre="Chargement et rechargement",
        action="Entrer en jeu, lire le chat, puis taper /reload et relire le chat.",
        attendu="Deux fois « [Sanctuary] Actif. Tapez /sanc pour ouvrir. », "
                "une seule ligne a chaque fois, aucune erreur Lua.",
        echec_si="Une deuxieme ligne de Sanctuary, une ligne differente, ou une "
                 "erreur Lua.",
        obligatoire=True, marqueurs=[],
    ),
    dict(
        id="D.1", phase=2, kind="play",
        titre="Les trois questions",
        action="/sanc. Question 1 : passer sur « Tout le monde, sauf ceux que je "
               "bloque » (la question 2 et le filtrage renforce se grisent), puis "
               "revenir. Question 2 : « Je choisis » (les cases se deplient, "
               "survoler « Filtrage renforce en instance »), puis « Tout ». "
               "Question 3 : « Chaque blocage », puis « Rien ». Tirer la poignee "
               "en bas a droite, puis double-cliquer dessus.",
        attendu="Chaque clic change l'ecran tout de suite ; l'infobulle du "
                "filtrage renforce est lisible en entier et non tronquee ; la "
                "poignee redimensionne et le double-clic reajuste. Etat final : "
                "inconnus / Tout / renforce decoche / Rien.",
        echec_si="Un texte tronque, une carte qui ne repond pas, ou un reglage "
                 "qui ne revient pas a l'etat demande.",
        obligatoire=True, marqueurs=[],
    ),
    dict(
        id="D.2", phase=3, kind="play",
        titre="Tester un pseudo",
        action="Dans « Tester un pseudo », taper le personnage d'un ami "
               "Battle.net connecte, puis un pseudo invente. Mettre le pseudo "
               "invente dans Toujours bloques, relire la reponse, puis retirer "
               "l'etiquette et cliquer « Annuler ».",
        attendu="« toujours autorise : ami Battle.net (compte) » ; puis "
                "« inconnu : bloque... » ; puis « toujours bloque : dans vos "
                "bloques » ; la croix affiche « ... retire · Annuler » et Annuler "
                "remet l'etiquette.",
        echec_si="Une reponse fausse, ou Annuler qui ne remet rien.",
        obligatoire=True, marqueurs=[],
    ),
    dict(
        id="D.3", phase=3, kind="play",
        titre="Gerer les toujours autorises",
        action="Ouvrir « Gerer » sur la tuile Toujours autorises et deplier "
               "« Amis Battle.net ».",
        attendu="« Ajoutes par vous » liste vos ajouts ; les amis Battle.net "
                "s'affichent en « Personnage · Compte », un ami hors ligne en "
                "« Compte (hors ligne) » ; les compteurs sont plausibles ; la "
                "tuile dit « N — a ajoutes · b amis Battle.net ».",
        echec_si="Une liste vide alors que vous avez des amis, ou un compteur "
                 "qui ne correspond pas.",
        obligatoire=True, marqueurs=[],
    ),
    dict(
        id="D.4", phase=3, kind="play",
        titre="Clic droit sur un pseudo",
        action="Clic droit sur un pseudo dans un canal public, ou sur un joueur "
               "cible. Choisir « Sanctuary : toujours bloquer », verifier "
               "l'etiquette dans le panneau, puis la retirer.",
        attendu="Deux entrees Sanctuary dans le menu ; le blocage ajoute "
                "l'etiquette ; le retrait l'enleve.",
        echec_si="Aucune entree Sanctuary, ou une erreur Lua a l'ouverture du "
                 "menu. Aucun joueur a portee : repondre « pas fait ».",
        obligatoire=False, marqueurs=[],
    ),
    dict(
        id="D.7", phase=3, kind="play",
        titre="Les trois refus de saisie",
        action="Ouvrir « Gerer » sur la tuile Toujours bloques. Dans le champ "
               "Pseudos : taper « - » et cliquer Ajouter, puis retaper « - » et "
               "valider avec Entree ; coller « Truc#1234 » et faire de meme, une "
               "fois au bouton, une fois a Entree. Dans le champ Patterns : "
               "taper « to.to », une fois au bouton, une fois a Entree. Laisser "
               "la phrase s'effacer entre deux essais.",
        attendu="Une phrase orange sous le champ concerne, et sous lui seul : "
                "« Un pseudo s'ecrit Pseudo ou Pseudo-Royaume » pour « - », la "
                "phrase Battle.net pour « Truc#1234 », « Un pattern est un texte "
                ": des lettres seulement » pour « to.to ». Chaque phrase est "
                "entiere, lisible, ne recouvre pas les etiquettes du dessous ; "
                "rien d'autre ne bouge a l'ecran quand elle apparait ou "
                "s'efface ; elle part seule au bout de quelques secondes. Le "
                "champ se vide et aucune etiquette n'est ajoutee. Le bouton et "
                "la touche Entree donnent le meme resultat.",
        echec_si="Une phrase tronquee, une phrase qui recouvre les etiquettes, "
                 "une phrase sous le mauvais champ, la liste qui saute quand "
                 "elle apparait, une phrase qui reste, ou une difference entre "
                 "le bouton et Entree.",
        obligatoire=True, marqueurs=[],
    ),
    dict(
        id="D.8", phase=3, kind="play",
        titre="La phrase Battle.net, aux deux endroits",
        action="Lire la ligne sous la description dans Toujours bloques, puis "
               "ouvrir « Gerer » sur Toujours autorises et deplier « Amis "
               "Battle.net » pour lire la ligne sous l'en-tete du groupe.",
        attendu="La meme phrase aux deux endroits, mot pour mot, en francais, "
                "entiere et non tronquee : « Sanctuary ne bloque pas les amis "
                "Battle.net. Faites-le directement sur Battle.net. »",
        echec_si="Deux formulations differentes, une phrase en anglais, ou une "
                 "phrase coupee a l'un des deux endroits.",
        obligatoire=True, marqueurs=[],
    ),
    dict(
        id="B.1", phase=4, kind="play",
        titre="Le rapport",
        action="Onglet Avance : cocher le mode debug, cliquer « Vider le debug » "
               "et confirmer, puis cliquer « Exporter le rapport ».",
        attendu="La fenetre s'ouvre sur un en-tete portant Version, Build, "
                "« Deploiement: OK », « Verdict: OK », « ChatFrames: n / n », "
                "puis le journal a la suite.",
        echec_si="Verdict autre que OK, deploiement autre que OK, ChatFrames "
                 "incomplet, ou fenetre vide. Etape bloquante : ne pas continuer.",
        obligatoire=True, marqueurs=[],
    ),
    dict(
        id="D.5", phase=4, kind="play",
        titre="Bouton minimap",
        action="Survoler le bouton autour de la minimap, cliquer, cliquer droit "
               "deux fois, puis le faire glisser autour de la minimap.",
        attendu="L'infobulle nomme l'etat et les deux clics ; le clic gauche "
                "ouvre la fenetre ; le clic droit affiche « Protection "
                "desactivee » et grise l'icone, puis la reactive ; le bouton "
                "suit le curseur autour de la minimap.",
        echec_si="Le bouton est absent, ne bouge pas, ou provoque une erreur Lua.",
        obligatoire=True, marqueurs=[],
    ),
    dict(
        id="D.6", phase=4, kind="play",
        titre="Journal et Avance",
        action="Onglet Journal : lire l'etat vide, cocher et decocher les deux "
               "cases, cliquer « Copier le journal ». Onglet Avance : lire le "
               "trust automatique, la taille du journal, masquer puis reafficher "
               "le bouton minimap, lire la ligne d'etat technique.",
        attendu="« Aucune interaction bloquee pour l'instant. » ; la fenetre de "
                "copie s'ouvre ; les reglages repondent ; la ligne d'etat est "
                "lisible et non tronquee.",
        echec_si="Un texte tronque, un reglage sans effet, ou une erreur Lua.",
        obligatoire=True, marqueurs=[],
    ),
    dict(
        id="C.1", phase=5, kind="play",
        titre="Tout lancer, puis les deux sons",
        action="Onglet Diagnostics : cliquer « Tout lancer », lire les blocs. "
               "Puis cliquer « Son d'ouverture de fenetre », ecouter, puis "
               "« Son d'invitation de groupe », ecouter.",
        attendu="Un bloc par diagnostic, « masked=yes hidden=yes », "
                "« output=guarded », et rien a l'ecran ni a l'oreille pendant le "
                "lot. Les deux boutons de son produisent ensuite deux sons "
                "nettement differents.",
        echec_si="Un flash de fenetre, un son parasite pendant « Tout lancer », "
                 "un « hidden=no », ou deux sons identiques.",
        obligatoire=True, marqueurs=["popupMaskAwaitingEvent"],
    ),
    dict(
        id="C.2", phase=5, kind="play",
        titre="Un vrai ami Battle.net",
        action="Diagnostics : dans « Simuler un vrai ami Battle.net », taper le "
               "pseudo d'un ami connecte et lancer, puis remplacer par 1 et "
               "relancer.",
        attendu="Deux lignes identiques « ALLOW (bnet_whitelist) ».",
        echec_si="Les deux lignes different, ou un ami connu est refuse.",
        obligatoire=False, marqueurs=[],
    ),
    dict(
        id="F.1", phase=5, kind="play",
        titre="Une ligne de chat non filtree",
        action="Taper /run DEFAULT_CHAT_FRAME:AddMessage(\"Test Sanctuary "
               "invitation de groupe\")",
        attendu="La ligne s'affiche dans le chat.",
        echec_si="La ligne n'apparait pas : Sanctuary masquerait un texte qu'il "
                 "ne doit pas toucher.",
        obligatoire=True, marqueurs=["chatOutputNoMatch"],
    ),
    dict(
        id="F.4", phase=5, kind="play",
        titre="Se chuchoter a soi-meme",
        action="Ouvrir un onglet de chuchotement dedie avec soi-meme, puis taper "
               "/w <son propre pseudo> note. Regarder ensuite l'onglet Journal.",
        attendu="La ligne s'affiche comme un chuchotement ordinaire, l'onglet de "
                "chuchotement reste ouvert, aucune ligne « Bloque » n'apparait "
                "dans le chat, et le Journal ne gagne aucune entree.",
        echec_si="La ligne manque, l'onglet de chuchotement se ferme, une ligne "
                 "« Bloque » apparait, ou une entree arrive au Journal.",
        obligatoire=True, marqueurs=[],
    ),
    dict(
        id="F.2", phase=6, kind="play",
        titre="Donjon et masquage en instance",
        action="Entrer seul dans un vieux donjon. Cocher « Filtrage renforce en "
               "instance », puis Diagnostics : « Tester le masquage en "
               "instance ». Decocher. Facultatif : /console "
               "addonChatRestrictionsForced 1, recliquer le bouton, taper /dnd "
               "deux fois avec le renforce coche, observer le chat, puis "
               "/console addonChatRestrictionsForced 0. Ressortir du donjon.",
        attendu="La ligne du diagnostic donne « armed=... reason=... "
                "context=instance lockdown=... ». Aucune erreur Lua a l'entree "
                "ni a la sortie.",
        echec_si="Une erreur Lua, ou « context » qui ne dit pas instance alors "
                 "que vous etes dans le donjon.",
        obligatoire=True,
        marqueurs=["worldInInstance", "lockdownArmedInInstance",
                   "secretSystemSuppressed", "secretSystemVisible",
                   "secretSystemEligible", "strictModeOn"],
    ),
    dict(
        id="F.3", phase=6, kind="play",
        titre="Mort et retour a la vie",
        action="Mourir, rester fantome une dizaine de secondes, puis ressusciter.",
        attendu="Aucune erreur Lua pendant la mort, l'etat fantome ou le retour.",
        echec_si="Une erreur Lua, ou le jeu qui se fige.",
        obligatoire=True, marqueurs=["playerState"],
    ),
    dict(
        id="G.1", phase=7, kind="play",
        titre="Persistance",
        action="Taper /reload, puis se deconnecter et se reconnecter.",
        attendu="Les quatre questions, le mode debug et la position du bouton "
                "minimap sont exactement comme avant.",
        echec_si="Un reglage revenu a sa valeur par defaut, ou le bouton minimap "
                 "revenu a sa place d'origine.",
        obligatoire=True, marqueurs=[],
    ),
    dict(
        id="G.2", phase=7, kind="play",
        titre="Protection desactivee",
        action="Cliquer le controle d'en-tete pour desactiver la protection, "
               "puis Diagnostics : « Simuler une invitation ». Reactiver, et "
               "relancer la simulation.",
        attendu="A l'arret : « popup=pass ... sound-guard=no ». Une fois "
                "reactivee : « popup=mask ».",
        echec_si="« popup=mask » alors que la protection est desactivee.",
        obligatoire=True, marqueurs=[],
    ),
    dict(
        id="G.3", phase=7, kind="play",
        titre="Retirer les donnees de test",
        action="Verifier que le pseudo invente de l'etape D.2 ne figure plus "
               "dans Toujours bloques ni dans Toujours autorises.",
        attendu="Les deux listes sont dans l'etat ou vous les vouliez.",
        echec_si="Une donnee de test reste dans une liste.",
        obligatoire=True, marqueurs=[],
    ),
    dict(
        id="G.4", phase=7, kind="play",
        titre="La version affichee",
        action="Onglet A propos : lire la ligne de version. La comparer a la "
               "ligne « Protocole ... -- build ... » que le runner a affichee au "
               "demarrage de la session.",
        attendu="A propos affiche la version 1.0.0, et le runner a annonce le "
                "protocole « sanctuary-1.0.0 ». Le compte rendu final reprendra "
                "les deux.",
        echec_si="A propos affiche une autre version, ou le protocole annonce "
                 "n'est pas sanctuary-1.0.0.",
        obligatoire=True, marqueurs=[],
    ),
    dict(
        id="R.1", phase=7, kind="remark",
        titre="Remarque libre",
        action="Noter ce que vous voulez sur cette session. Peut rester vide.",
        attendu="La remarque est reprise telle quelle dans le compte rendu.",
        echec_si="",
        obligatoire=True, marqueurs=[],
    ),
    dict(
        id="R.2", phase=None, kind="runner",
        titre="Archivage et controle",
        action="Quitter le jeu. Le runner attend que le fichier de reglages soit "
               "stable, l'archive sans pouvoir ecraser, lance "
               "tests/check_qa_run.lua et met le compte rendu dans le "
               "presse-papiers.",
        attendu="Une archive datee, le verdict du controleur, et un compte rendu "
                "collable tel quel.",
        echec_si="Le controleur rend 1 ou 2, ou l'archive existe deja avec un "
                 "contenu different.",
        obligatoire=True, marqueurs=[],
    ),
]


def played_steps():
    """The steps the person is asked about, in the order they are played."""
    order = {step["id"]: index for index, step in enumerate(STEPS)}
    steps = [s for s in STEPS if s["kind"] != "runner"]
    return sorted(steps, key=lambda s: (s["phase"] or 99, order[s["id"]]))


def claimed_markers():
    """Every machine marker a step says it produces, deduplicated, in order."""
    seen, markers = set(), []
    for step in STEPS:
        for marker in step["marqueurs"]:
            if marker not in seen:
                seen.add(marker)
                markers.append(marker)
    return markers


def check():
    """Structural validation. Returns a list of problems, empty when sound."""
    problems = []
    seen_ids = set()
    for step in STEPS:
        step_id = step["id"]
        if step_id in seen_ids:
            problems.append("identifiant en double : %s" % step_id)
        seen_ids.add(step_id)
        if step["kind"] not in ("runner", "play", "remark"):
            problems.append("%s : type inconnu %r" % (step_id, step["kind"]))
        if step["kind"] == "runner":
            if step["phase"] is not None:
                problems.append("%s : une etape du runner n'a pas de phase" % step_id)
        elif step["phase"] not in PHASES:
            problems.append("%s : phase inconnue %r" % (step_id, step["phase"]))
        for field in ("titre", "action", "attendu"):
            if not step[field].strip():
                problems.append("%s : champ %s vide" % (step_id, field))
        if step["kind"] == "play" and not step["echec_si"].strip():
            problems.append("%s : une etape jouee doit dire quand elle echoue" % step_id)
        if not isinstance(step["marqueurs"], list):
            problems.append("%s : marqueurs doit etre une liste" % step_id)

    played = [s for s in STEPS if s["kind"] == "play"]
    if not played:
        problems.append("aucune etape jouee")
    used_phases = {s["phase"] for s in played}
    for phase in PHASES:
        if phase not in used_phases:
            problems.append("la phase %d (%s) n'a aucune etape" % (phase, PHASES[phase]))
    return problems


def print_plan():
    lines = ["# Session de validation -- %s" % PROTOCOL_ID, ""]
    lines.append("%d etapes jouees, dont %d facultative(s), reparties sur %d phases."
                 % (len([s for s in STEPS if s["kind"] == "play"]),
                    len([s for s in STEPS if s["kind"] == "play" and not s["obligatoire"]]),
                    len(PHASES)))
    lines.append("")

    runner = [s for s in STEPS if s["kind"] == "runner"]
    if runner:
        lines.append("## Porte par le runner")
        lines.append("")
        for step in runner:
            lines.append("- **%s -- %s** : %s" % (step["id"], step["titre"], step["action"]))
        lines.append("")

    current_phase = None
    for step in played_steps():
        if step["phase"] != current_phase:
            current_phase = step["phase"]
            lines.append("## Phase %d / %d -- %s"
                         % (current_phase, len(PHASES), PHASES[current_phase]))
            lines.append("")
        title = "### %s -- %s" % (step["id"], step["titre"])
        if not step["obligatoire"]:
            title += " *(facultative)*"
        lines.append(title)
        lines.append("")
        lines.append("- **Action** : %s" % step["action"])
        lines.append("- **Attendu** : %s" % step["attendu"])
        if step["echec_si"]:
            lines.append("- **Echec si** : %s" % step["echec_si"])
        if step["marqueurs"]:
            lines.append("- **Marqueurs** : %s" % ", ".join(step["marqueurs"]))
        lines.append("")
    return "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true",
                        help="structural validation of the protocol")
    parser.add_argument("--markers", action="store_true",
                        help="the machine markers the steps claim, one per line")
    parser.add_argument("--print-plan", action="store_true",
                        help="the readable plan, derived from the table")
    args = parser.parse_args(argv)

    if args.markers:
        for marker in claimed_markers():
            print(marker)
        return 0

    if args.print_plan:
        print(print_plan())
        return 0

    problems = check()
    if args.check:
        for problem in problems:
            print(problem, file=sys.stderr)
        if problems:
            return 1
        print("protocole %s : %d etapes, %d phases, %d marqueurs -- structure saine"
              % (PROTOCOL_ID, len(STEPS), len(PHASES), len(claimed_markers())))
        return 0

    parser.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main())
