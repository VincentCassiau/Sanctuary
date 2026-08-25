# Sanctuary

> Anti-harassment protection for World of Warcraft.

*[Version francaise](README.fr.md)*

## What it does

Sanctuary works both ways: by default, only the players you know can contact you; a second mode lets everyone through, except the players you have decided to block, by name or by pattern.

**Blocked interactions:**
- Group invitations (including system messages and sounds)
- Whispers from WoW characters (Battle.net whispers are never filtered)
- Duels, trades, guild invitations
- /say, /yell, /emote (optional)
- Channel messages (optional)

**Trusted by default:**
- Guild members
- BattleNet friends
- Character friends
- Current group/raid members

In the default mode, everything else is blocked and logged.

## Why Sanctuary?

Most addons that deal with unwanted interactions work on a **blacklist** model: you block specific players and everyone else gets through. Sanctuary offers that model too, but its default is the other one: only explicitly trusted players can interact with you, and everything else is silently blocked.

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

The main screen asks five questions: who can contact you, what Sanctuary blocks, whether to hide the spam of the public channels, what Sanctuary tells you in chat, and your lists. The Journal keeps a trace of everything that was blocked.

Enhanced filtering in instances is an option of the second question. While WoW locks the chat down, add-ons can no longer read system messages, so with this box ticked and while you are grouped or in an instance Sanctuary hides every system message, not only invitations -- the game does not let it tell them apart. Nothing is shown in chat; debug mode keeps a trace. Leave it off unless unwanted invites still reach you during dungeons, raids, or PvP matches.

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

**Battle.net is never filtered by Sanctuary.** Your Battle.net friends are always allowed on Battle.net: neither the blocked list nor the suspect patterns apply to Battle.net whispers. Adding someone to Battle.net is an act of trust Sanctuary does not second-guess -- cutting a Battle.net contact off is done in Battle.net, by removing or blocking the account.

## Compatibility

- **WoW version:** Retail (Midnight)
- **Retail only.** Classic, Cataclysm Classic, Season of Discovery, and other non-retail clients are not supported or tested.
- **LeatrixPlus:** Compatible. Sanctuary adds system message suppression on top of LeatrixPlus's auto-decline.
- **BadBoy:** Compatible. Both addons work independently on their respective filters.
- **No dependencies.** Pure WoW API, no external libraries.

## License

[MIT](LICENSE)
