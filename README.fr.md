# Sanctuary

> Protection anti-harcelement pour World of Warcraft.

*[English version](README.md)*

## Qu'est-ce que Sanctuary ?

Sanctuary fonctionne dans les deux sens : par defaut, seuls les joueurs que vous connaissez peuvent vous contacter ; un second mode laisse tout passer, sauf les joueurs que vous avez decide de bloquer, par pseudo ou par pattern.

**Interactions bloquees :**
- Invitations de groupe (y compris les messages systeme et les sons)
- Les chuchotements des personnages WoW (les chuchotements Battle.net ne sont jamais filtres)
- Duels, echanges, invitations de guilde
- /dire, /crier, /emote (optionnel)
- Messages dans les canaux (optionnel)

**Sources de confiance par defaut :**
- Membres de guilde
- Amis BattleNet
- Amis du personnage
- Membres du groupe/raid en cours

Dans le mode par defaut, tout le reste est bloque et journalise.

## Pourquoi Sanctuary ?

La plupart des addons qui gerent les interactions non souhaitees fonctionnent sur un modele de **blacklist** : vous bloquez des joueurs specifiques et tous les autres passent. Sanctuary propose ce modele aussi, mais son mode par defaut est l'autre : seuls les joueurs explicitement autorises peuvent interagir avec vous, et tout le reste est bloque silencieusement.

Ce qui differencie Sanctuary :
- **Whitelist d'abord** -- Guilde, amis et membres du groupe sont automatiquement autorises. Tous les autres sont bloques par defaut.
- **Suppression totale** -- Pas seulement le refus automatique, mais aussi la suppression des messages systeme et la coupure du son. Rien ne vous parvient.
- **Patterns suspects** -- Detection par mots-cles dans les pseudos qui prime meme sur la whitelist, pour les joueurs qui creent de nouveaux personnages avec des noms reconnaissables.
- **Journalisation complete** -- Chaque interaction bloquee est enregistree avec horodatage, type, source et contenu du message. Exportable.

Sanctuary fonctionne aux cotes d'addons comme LeatrixPlus, BadBoy et Global Ignore List sans conflit.

## Installation

1. Telechargez ou clonez ce depot
2. Copiez le dossier dans `World of Warcraft/_retail_/Interface/AddOns/Sanctuary/`
3. Verifiez que le dossier s'appelle bien `Sanctuary`
4. Relancez WoW ou tapez `/reload`

## Utilisation

Tapez `/sanc` ou `/sanctuary` pour ouvrir la fenetre de configuration.

L'ecran principal pose cinq questions : qui peut vous contacter, ce que Sanctuary bloque, s'il faut masquer le spam des canaux publics, ce que Sanctuary vous dit dans le chat, et vos listes. Le Journal garde la trace de tout ce qui a ete bloque.

Le filtrage renforce en instance (experimental) est une case a part sur l'ecran principal. Elle se grise si vous avez decoche le blocage des invitations de groupe. Quand WoW verrouille le chat (combats de boss d'instance, cles mythiques, matchs JcJ), les add-ons ne peuvent plus lire les messages systeme. En activant cette option, tant que vous etes en groupe ou en instance, Sanctuary masque tous les messages systeme, pas seulement les invitations -- le jeu ne permet pas de les distinguer. Ne l'activez que si des invitations de groupe indesirables vous parviennent encore en donjon, en raid ou en match JcJ.

## Fonctionnement de la whitelist

L'addon maintient une whitelist a partir de plusieurs sources. Toutes les sources sont toujours actives :

| Source | Automatique |
|--------|:-----------:|
| Membres de guilde | Oui |
| Amis BattleNet | Oui |
| Amis du personnage | Oui |
| Membres du groupe/raid | Oui |
| Whitelist manuelle | Vous les ajoutez |
| Auto-trust (optionnel) | Apres 5 min en groupe |

**Les patterns suspects priment sur la whitelist.** Si le pseudo d'un joueur contient un mot-cle suspect, il sera bloque meme s'il est dans votre guilde ou votre liste d'amis.

**Sanctuary ne bloque jamais personne sur Battle.net.** Vos amis Battle.net sont toujours autorises sur Battle.net : ni la liste des bloques ni les patterns suspects ne s'appliquent aux chuchotements Battle.net. Ajouter quelqu'un sur Battle.net est un acte de confiance que Sanctuary ne remet pas en cause -- pour couper un contact Battle.net, retirez-le ou bloquez-le dans Battle.net.

## Compatibilite

- **Version WoW :** Retail (Midnight)
- **Retail uniquement.** Classic, Cataclysm Classic, Season of Discovery et les autres clients non-retail ne sont pas supportes ni testes.
- **LeatrixPlus :** Compatible. Sanctuary ajoute la suppression des messages systeme en complement du refus automatique de LeatrixPlus.
- **BadBoy :** Compatible. Les deux addons fonctionnent ensemble sans conflit.
- **Aucune dependance.** API WoW native uniquement, pas de librairie externe.

## Licence

[MIT](LICENSE)
