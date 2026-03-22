# Sanctuary

> Whitelist-based anti-harassment protection for World of Warcraft.

*[Version francaise ci-dessous](#version-francaise)*

## What it does

Sanctuary silently blocks all interactions from players who are not on your whitelist. Unlike blacklist-based addons, nothing gets through unless explicitly authorized.

**Blocked interactions:**
- Group invitations (including system messages and sounds)
- Whispers (regular and BattleNet)
- Duels, trades, guild invitations
- /say, /yell, /emote (optional)
- Channel messages (optional)

**Trusted by default:**
- Guild members
- BattleNet friends
- Character friends
- Current group/raid members

Everything else is blocked and logged.

## Why Sanctuary?

Most addons that deal with unwanted interactions work on a **blacklist** model: you block specific players and everyone else gets through. Sanctuary flips this around with a **whitelist** model: only explicitly trusted players can interact with you. Everything else is silently blocked.

What makes Sanctuary different:
- **Whitelist-first** -- Guild, friends, and group members are trusted automatically. Everyone else is blocked by default.
- **Full suppression** -- Not just auto-decline, but also system message hiding and sound muting. Nothing reaches you.
- **Suspect patterns** -- Keyword-based name matching that overrides even the whitelist, for players who create new characters with recognizable names.
- **Complete logging** -- Every blocked interaction is recorded with timestamp, type, source, and message content. Exportable.

Sanctuary works alongside addons like LeatrixPlus, BadBoy, and Global Ignore List without conflict.

## Installation

1. Download or clone this repository
2. Copy the folder to `World of Warcraft/_retail_/Interface/AddOns/Sanctuary/`
3. Make sure the folder is named `Sanctuary` (not `Sanctuary-main`)
4. Restart WoW or type `/reload`

## Usage

Type `/sanc` or `/sanctuary` to open the configuration window.

The GUI has 4 tabs:
- **Filters** -- Toggle which interactions to block, notification mode, channel filtering
- **Patterns** -- Add suspect name patterns (e.g. "goldbank" blocks any player whose name contains it)
- **Whitelist** -- Manually add trusted players
- **Logs** -- Browse blocked interactions, export logs

## How the whitelist works

The addon maintains a whitelist from multiple sources. All sources are always active:

| Source | Automatic |
|--------|:---------:|
| Guild members | Yes |
| BattleNet friends | Yes |
| Character friends | Yes |
| Group/raid members | Yes |
| Manual whitelist | You add them |
| Auto-trust (optional) | After 5 min in group |

**Suspect patterns override the whitelist.** If a player's name contains a suspect keyword, they are blocked even if they are in your guild or friends list.

## Compatibility

- **WoW version:** Retail (Midnight) -- Interface 120001
- **LeatrixPlus:** Compatible. Sanctuary adds system message suppression on top of LeatrixPlus's auto-decline.
- **BadBoy:** Compatible. Both addons work independently on their respective filters.
- **No dependencies.** Pure WoW API, no external libraries.

## License

[MIT](LICENSE)

---

## Version francaise

> Protection anti-harcelement par whitelist pour World of Warcraft.

### Qu'est-ce que Sanctuary ?

Sanctuary bloque silencieusement toutes les interactions des joueurs qui ne sont pas dans votre whitelist. Contrairement aux addons par liste noire, rien ne passe sauf ce qui est explicitement autorise.

**Interactions bloquees :**
- Invitations de groupe (y compris les messages systeme et les sons)
- Whispers (normaux et BattleNet)
- Duels, echanges, invitations de guilde
- /dire, /crier, /emote (optionnel)
- Messages dans les canaux (optionnel)

**Sources de confiance par defaut :**
- Membres de guilde
- Amis BattleNet
- Amis du personnage
- Membres du groupe/raid en cours

Tout le reste est bloque et journalise.

### Pourquoi Sanctuary ?

La plupart des addons qui gerent les interactions non souhaitees fonctionnent sur un modele de **blacklist** : vous bloquez des joueurs specifiques et tous les autres passent. Sanctuary inverse cette logique avec un modele de **whitelist** : seuls les joueurs explicitement autorises peuvent interagir avec vous. Tout le reste est bloque silencieusement.

Ce qui differencie Sanctuary :
- **Whitelist d'abord** -- Guilde, amis et membres du groupe sont automatiquement autorises. Tous les autres sont bloques par defaut.
- **Suppression totale** -- Pas seulement le refus automatique, mais aussi la suppression des messages systeme et la coupure du son. Rien ne vous parvient.
- **Patterns suspects** -- Detection par mots-cles dans les pseudos qui prime meme sur la whitelist, pour les joueurs qui creent de nouveaux personnages avec des noms reconnaissables.
- **Journalisation complete** -- Chaque interaction bloquee est enregistree avec horodatage, type, source et contenu du message. Exportable.

Sanctuary fonctionne aux cotes d'addons comme LeatrixPlus, BadBoy et Global Ignore List sans conflit.

### Installation

1. Telechargez ou clonez ce depot
2. Copiez le dossier dans `World of Warcraft/_retail_/Interface/AddOns/Sanctuary/`
3. Verifiez que le dossier s'appelle bien `Sanctuary`
4. Relancez WoW ou tapez `/reload`

### Utilisation

Tapez `/sanc` ou `/sanctuary` pour ouvrir la fenetre de configuration.

L'interface comporte 4 onglets :
- **Filtres** -- Activer/desactiver les filtres, mode de notification, filtrage des canaux
- **Patterns** -- Ajouter des mots-cles suspects (ex: "goldbank" bloque tout joueur dont le pseudo contient ce mot)
- **Whitelist** -- Ajouter manuellement des joueurs de confiance
- **Logs** -- Consulter les interactions bloquees, exporter les logs

### Fonctionnement de la whitelist

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

### Compatibilite

- **Version WoW :** Retail (Midnight) -- Interface 120001
- **LeatrixPlus :** Compatible. Sanctuary ajoute la suppression des messages systeme en complement du refus automatique de LeatrixPlus.
- **BadBoy :** Compatible. Les deux addons fonctionnent ensemble sans conflit.
- **Aucune dependance.** API WoW native uniquement, pas de librairie externe.

### Licence

[MIT](LICENSE)
