local ADDON_NAME, ns = ...

local L = {}
ns.L = L

-- ============================================================================
-- English (default)
-- ============================================================================

-- General
L["ADDON_LOADED"] = "Sanctuary loaded -- %s. Type /sanctuary or /sanc to open."
L["ENABLED"] = "enabled"
L["DISABLED"] = "disabled"
L["ON"] = "ON"
L["OFF"] = "OFF"

-- Companion addons
L["LEATRIX_DETECTED"] = "LeatrixPlus detected -- Sanctuary handles system message suppression."
L["BADBOY_DETECTED"] = "BadBoy detected -- both addons work together without conflict."

-- Date formats
L["DATE_FORMAT"] = "%Y-%m-%d"
L["DATE_TIME_FORMAT"] = "%Y-%m-%d %H:%M:%S"

-- Whitelist management
L["WHITELIST_INVALID_NAME"] = "Invalid name."
L["WHITELIST_ADDED"] = "%s added to whitelist."

-- Log
L["LOG_CLEARED"] = "Log cleared."

-- Toggle
L["SANCTUARY_ENABLED"] = "Sanctuary enabled."
L["SANCTUARY_DISABLED"] = "Sanctuary disabled."

-- Verbose notification
L["BLOCKED_VERBOSE"] = "Blocked: %s from %s"

-- Trust auto
L["TRUST_AUTO_ADDED"] = "Auto-trust: %s added to whitelist."

-- Minimal notification
L["BLOCKED_SESSION"] = "%s interaction(s) blocked this session."

-- Suspect pseudo
L["SUSPECT_ADDED"] = "Suspect pseudo added: %s"
L["SUSPECT_DUPLICATE"] = "Suspect pseudo already exists: %s"
L["SUSPECT_REMOVED"] = "Suspect pseudo removed: %s"

-- ============================================================================
-- UI Labels
-- ============================================================================

-- Tab names
L["TAB_FILTERS"] = "Filters"
L["TAB_SUSPECTS"] = "Patterns"
L["TAB_WHITELIST"] = "Whitelist"
L["TAB_LOGS"] = "Logs"
L["TAB_ABOUT"] = "About"

-- About tab
L["ABOUT_VERSION"] = "Version %s"
L["ABOUT_AUTHOR"] = "Author: %s"
L["ABOUT_DESC"] = "Whitelist-based anti-harassment protection. Blocks all interactions from non-authorized players and logs everything."
L["ABOUT_GITHUB"] = "GitHub: %s"
L["ABOUT_THANKS"] = "Thanks to %s for testing."

-- Filter labels
L["FILTER_GROUP_INVITE"] = "Block group invitations"
L["FILTER_WHISPER"] = "Block private messages (whispers)"
L["FILTER_SAY"] = "Block /say"
L["FILTER_YELL"] = "Block /yell"
L["FILTER_EMOTE"] = "Block emotes"
L["FILTER_DUEL"] = "Auto-decline duels"
L["FILTER_TRADE"] = "Auto-close trades"
L["FILTER_GUILD_INVITE"] = "Auto-decline guild invitations"
L["FILTER_STRICT_GROUP_INVITE_SYSTEM"] = "Enhanced filtering in instances"

-- Filter tooltips
L["TIP_GROUP_INVITE"] = "Blocks and auto-declines group invitations from unauthorized players.\nThe system message in chat is also suppressed.\n\nExample: a stranger invites you => nothing appears."
L["TIP_WHISPER"] = "Blocks private messages from unauthorized players.\n\nExample: a stranger sends you a PM => you don't see it."
L["TIP_SAY"] = "Blocks /say messages from unauthorized players.\n\nExample: a stranger speaks near you => their text doesn't appear."
L["TIP_YELL"] = "Blocks /yell messages from unauthorized players."
L["TIP_EMOTE"] = "Hides emote messages in chat from unauthorized players.\nNote: this only hides the text in chat, not the character animation.\n\nExample: a stranger does /dance => the text 'X dances with you' doesn't appear in chat, but you still see the animation."
L["TIP_DUEL"] = "Auto-declines duel requests from unauthorized players."
L["TIP_TRADE"] = "Auto-closes the trade window with unauthorized players."
L["TIP_GUILD_INVITE"] = "Auto-declines guild invitations from unauthorized players."
L["TIP_STRICT_GROUP_INVITE_SYSTEM"] = "Advanced mode: enable only if you still receive unwanted group invites while you are in a dungeon, raid, or instance.\n\nSanctuary will hide protected WoW system messages it cannot read while the group-invite filter is active. This may hide some legitimate system messages."

-- Auto-trust
L["GROUP_AUTO_TRUST"] = "Auto-trust"
L["FILTER_AUTO_TRUST"] = "Auto-trust (add players in group 5+ min)"
L["TIP_AUTO_TRUST"] = "Players who stay in your group for 5+ minutes are automatically and permanently added to your whitelist.\n\nExample: you run a dungeon with someone for 10 min => they are added."

-- Filter group titles
L["GROUP_MAIN_PROTECTION"] = "Main protection"
L["GROUP_COMMUNICATION"] = "Communication"
L["GROUP_INTERACTIONS"] = "Interactions"

-- Channel filtering
L["GROUP_CHANNELS"] = "Channels (/1, /2, /3...)"
L["CHANNEL_NONE"] = "No filtering"
L["CHANNEL_KEYWORDS"] = "Suspect pseudos only"
L["CHANNEL_ALL"] = "Filter all (except whitelist)"
L["TIP_CHANNEL_NONE"] = "Messages in channels (General, Trade...) are not filtered."
L["TIP_CHANNEL_KEYWORDS"] = "Blocks messages in channels if the sender's name contains a suspect pseudo.\nExample: if 'jetaime' is in your suspect list, a player named 'Jetaime' in General chat will be blocked."
L["TIP_CHANNEL_ALL"] = "Blocks ALL messages in channels from unauthorized players.\nWarning: this makes public channels silent."

-- Notifications
L["GROUP_NOTIFICATIONS"] = "Notifications"
L["NOTIF_SILENT"] = "Silent"
L["NOTIF_MINIMAL"] = "Minimal"
L["NOTIF_VERBOSE"] = "Detailed"
L["TIP_NOTIF_SILENT"] = "No messages in chat. Protection works in total silence."
L["TIP_NOTIF_MINIMAL"] = "A periodic summary appears in chat (e.g., '5 interactions blocked this session')."
L["TIP_NOTIF_VERBOSE"] = "Each blocked interaction is reported in chat. Useful for testing."

-- Suspect pseudos tab
L["SUSPECTS_HEADER"] = "Name patterns"
L["SUSPECTS_DESC"] = "Players whose name contains one of these words will be blocked, even if they are in your trusted sources.\nExample: word 'test' => blocks 'ToTuTesT', 'MyTestChar', etc."
L["SUSPECTS_COUNT"] = "%s pattern(s)"
L["SUSPECTS_ADD_BTN"] = "Add"

-- Whitelist tab
L["WL_HEADER"] = "Manual whitelist"
L["WL_ADD_BTN"] = "Add"
L["WL_COUNT"] = "%s player(s)"
L["WL_ADDED_ON"] = "added on %s"

-- Logs tab
L["LOGS_HEADER"] = "Blocked interaction log"
L["LOGS_ENABLE"] = "Enable logs"
L["LOGS_SHOW_MSG"] = "Show messages"
L["LOGS_CLEAR_BTN"] = "Clear log"
L["LOGS_EXPORT_BTN"] = "Export"
L["LOGS_COUNT_FULL"] = "%s entry(ies) / %s max"
L["LOGS_CLEAR_CONFIRM"] = "Are you sure you want to clear the entire log?\nThis action is irreversible."
L["LOGS_CLEAR_YES"] = "Clear"
L["LOGS_CLEAR_NO"] = "Cancel"

-- Log type names
L["LOG_TYPE_INVITE"] = "Invite"
L["LOG_TYPE_WHISPER"] = "Whisper"
L["LOG_TYPE_SAY"] = "Say"
L["LOG_TYPE_YELL"] = "Yell"
L["LOG_TYPE_EMOTE"] = "Emote"
L["LOG_TYPE_DUEL"] = "Duel"
L["LOG_TYPE_TRADE"] = "Trade"
L["LOG_TYPE_GUILD"] = "Guild"
L["LOG_TYPE_CHANNEL"] = "Channel"

-- Logs grouped
L["LOGS_EXPAND_ALL"] = "Expand all"
L["LOGS_COLLAPSE_ALL"] = "Collapse all"
L["LOGS_LAST_ACTIVITY"] = "last: %s"
L["LOGS_GROUP_HEADER"] = "%s (%d)"

-- Export
L["EXPORT_SUSPECT_TAG"] = "[suspect pseudo: %s]"
L["EXPORT_TITLE"] = "Export logs"
L["EXPORT_INSTRUCTIONS"] = "Ctrl+A then Ctrl+C to copy"
L["EXPORT_CLOSE"] = "Close"
L["EXPORT_HEADER"] = "=== Sanctuary - Blocked interaction log ==="
L["EXPORT_DATE"] = "Export date: %s"
L["EXPORT_TOTAL"] = "Total: %s entries"
L["EXPORT_COLUMNS"] = "Date | Type | Source | Message | Suspect pseudo"

-- Settings panel
L["SETTINGS_TITLE"] = "Sanctuary v%s"
L["SETTINGS_DESC"] = "Whitelist-based anti-harassment protection"
L["SETTINGS_OPEN_BTN"] = "Open Sanctuary"

-- Status bar
L["STATUSBAR_SESSION"] = "Session: %s blocked"
L["STATUSBAR_LOG"] = "Log: %s/%s"
L["STATUSBAR_SUSPECTS"] = "Patterns: %s"

-- Debug mode
L["GROUP_DEBUG"] = "Diagnostics"
L["DEBUG_ENABLE"] = "Enable debug mode"
L["TIP_DEBUG"] = "Captures diagnostic data for\nfiltered interactions.\n\nMay contain player names, system\nnotifications, and short excerpts of\nfiltered chat messages.\nNothing is sent -- export is copy-paste.\n\nToggling debug mode keeps the log:\nuse Clear to erase it."
L["DEBUG_EXPORT_BTN"] = "Export debug log"
L["DEBUG_CLEAR_BTN"] = "Clear"
L["DEBUG_EMPTY"] = "Debug log is empty. Enable debug mode, then play normally."
L["DEBUG_EXPORT_TITLE"] = "Debug log export"
L["DEBUG_EXPORT_INSTRUCTIONS"] = "Ctrl+A then Ctrl+C to copy"
L["DEBUG_COUNT"] = "Debug: %s"
L["DEBUG_ENABLED_MSG"] = "Debug mode ON. Play normally, then export."
L["DEBUG_DISABLED_MSG"] = "Debug mode OFF. The log is kept."
L["DEBUG_CLEAR_CONFIRM"] = "Erase the debug log (%s entries)?\nThis cannot be undone."
L["DEBUG_CLEARED_MSG"] = "Debug log erased."
L["SOUND_UNMUTE_FAILED"] = "Sanctuary could not restore the game's panel sounds. Restart the game client to get them back -- a reload or a relog will not clear this."

-- ============================================================================
-- French overrides (frFR)
-- ============================================================================

-- Whitelist readback (Whitelist tab)
L["WL_AUTO_HEADER"] = "Automatically trusted"
L["WL_AUTO_HINT"] = "Read-only. Rebuilt when the tab is opened."
L["WL_AUTO_EMPTY"] = "No automatically trusted contact."
L["WL_AUTO_NO_MATCH"] = "No match for this search."
L["WL_SOURCE_GUILD"] = "Guild members"
L["WL_SOURCE_FRIEND"] = "Friends"
L["WL_SOURCE_BNET"] = "Battle.net friends"
L["WL_SOURCE_GROUP"] = "Current group"
L["WL_GROUP_ROW"] = "%s (%s)"
L["WL_GROUP_ROW_FILTERED"] = "%s (%s shown of %s)"
L["WL_SEARCH_LABEL"] = "Search"
L["WL_CHECK_LABEL"] = "Does this person get through?"
L["WL_CHECK_BTN"] = "Check"
L["WL_CHECK_PASS"] = "%s gets through -- %s"
L["WL_CHECK_BLOCK"] = "%s is filtered -- %s"
L["WL_CHECK_INVALID"] = "Invalid name."
L["WL_CHECK_BNET_ONLY"] = " (Battle.net account allowed: %s)"
L["WL_REASON_MANUAL"] = "manually added"
L["WL_REASON_TRUST"] = "auto-trust"
L["WL_REASON_GUILD"] = "guild member"
L["WL_REASON_FRIEND"] = "friend"
L["WL_REASON_BNET"] = "Battle.net friend"
L["WL_REASON_GROUP"] = "current group"
L["WL_REASON_KEYWORD"] = "suspect pattern: %s"
L["WL_REASON_NOT_WHITELISTED"] = "in none of your lists"

-- Diagnostic panel (debug mode only)
L["TAB_DIAGNOSTICS"] = "Diagnostics"
L["DIAG_PANEL_HEADER"] = "Diagnostics -- debug mode"
L["DIAG_PANEL_INTRO"] = "Same diagnostics as the /sanc commands, one click each. Visible only while debug mode is on."
L["DIAG_RUN_ALL"] = "Run them all (except the sensitive one)"
L["DIAG_CLEAR"] = "Clear"
L["DIAG_RESULT_EMPTY"] = "No diagnostic run yet."
L["DIAG_SENSITIVE"] = "Writes a real Battle.net account name into the debug log."
L["DIAG_UNKNOWN"] = "Unknown diagnostic: %s"
L["DIAG_FAILED"] = "Diagnostic %s: FAILED (%s)"
L["DIAG_LEFT_ON_SCREEN"] = "This popup could not be hidden: it is still on screen, invisible and clickable. Do not click anywhere."
L["DIAG_RESTORE_BTN"] = "Restore the screen (/reload)"
L["DIAG_SIM_INVITE"] = "Simulate an invitation"
L["DIAG_SIM_BNET"] = "Simulate a Battle.net whisper"
L["DIAG_SIM_BNETFRIEND"] = "Simulate a real Battle.net friend"
L["DIAG_CHAT_INVITE"] = "Chat diagnostic (invitation)"
L["DIAG_SOUND_INVITE"] = "Sound diagnostic"
L["DIAG_POPUP_INVITE"] = "Group invitation window"
L["DIAG_POPUP_DUEL"] = "Duel window"
L["DIAG_POPUP_GUILD"] = "Guild invitation window"
L["DIAG_POPUP_LIST"] = "List the game windows"
L["DIAG_ARG_NAME"] = "name"
L["DIAG_ARG_INDEX"] = "no."
L["DIAG_ARG_FILTER"] = "filter"
L["DIAG_TIP_SOUND"] = "Turn the volume up: this one is checked by ear."
L["DIAG_TIP_POPUP"] = "Watch the screen. Do not run while a real request is pending."

-- Report summary
L["DEBUG_SUMMARY_TITLE"] = "Sanctuary -- report summary"
L["DEBUG_SUMMARY_BTN"] = "Report summary"
L["DEBUG_SUMMARY_INSTRUCTIONS"] = "Check at a glance. The record itself is the settings file."
L["DEBUG_SUMMARY_FILE"] = "The official record is the settings file the game writes when you quit:\nWorld of Warcraft/_retail_/WTF/Account/<ACCOUNT>/SavedVariables/Sanctuary.lua\nThis window is a check, not a transport channel."
L["DEBUG_FULL_BTN"] = "Full report"
L["DEBUG_FULL_WARNING"] = "On-screen reading only -- not a record. Use the settings file."

if GetLocale() == "frFR" then

-- General
L["ADDON_LOADED"] = "Sanctuary charg\195\169 -- %s. Tapez /sanctuary ou /sanc pour ouvrir."
L["ENABLED"] = "actif"
L["DISABLED"] = "inactif"

-- Companion addons
L["LEATRIX_DETECTED"] = "LeatrixPlus d\195\169tect\195\169 -- Sanctuary g\195\168re la suppression des messages syst\195\168me en compl\195\169ment."
L["BADBOY_DETECTED"] = "BadBoy d\195\169tect\195\169 -- les deux addons fonctionnent ensemble sans conflit."

-- Date formats
L["DATE_FORMAT"] = "%d/%m/%Y"
L["DATE_TIME_FORMAT"] = "%d/%m/%Y %H:%M:%S"

-- Whitelist
L["WHITELIST_INVALID_NAME"] = "Nom invalide."
L["WHITELIST_ADDED"] = "%s ajout\195\169 \195\160 la whitelist."

-- Log
L["LOG_CLEARED"] = "Log vid\195\169."

-- Toggle
L["SANCTUARY_ENABLED"] = "Sanctuary activ\195\169."
L["SANCTUARY_DISABLED"] = "Sanctuary d\195\169sactiv\195\169."

-- Verbose
L["BLOCKED_VERBOSE"] = "Bloqu\195\169 : %s de %s"

-- Trust
L["TRUST_AUTO_ADDED"] = "Trust automatique : %s ajout\195\169 \195\160 la whitelist."

-- Minimal
L["BLOCKED_SESSION"] = "%s interaction(s) bloqu\195\169e(s) cette session."

-- Suspects
L["SUSPECT_ADDED"] = "Pseudo suspect ajout\195\169 : %s"
L["SUSPECT_DUPLICATE"] = "Pseudo suspect d\195\169j\195\160 pr\195\169sent : %s"
L["SUSPECT_REMOVED"] = "Pseudo suspect supprim\195\169 : %s"

-- Tab names
L["TAB_FILTERS"] = "Filtres"
L["TAB_SUSPECTS"] = "Patterns"
L["TAB_WHITELIST"] = "Whitelist"
L["TAB_LOGS"] = "Logs"
L["TAB_ABOUT"] = "A propos"

-- About tab
L["ABOUT_VERSION"] = "Version %s"
L["ABOUT_AUTHOR"] = "Auteur : %s"
L["ABOUT_DESC"] = "Protection anti-harc\195\168lement par whitelist. Bloque toutes les interactions des joueurs non autoris\195\169s et conserve un historique complet."
L["ABOUT_GITHUB"] = "GitHub : %s"
L["ABOUT_THANKS"] = "Merci \195\160 %s pour les tests."

-- Filter labels
L["FILTER_GROUP_INVITE"] = "Bloquer les invitations de groupe"
L["FILTER_WHISPER"] = "Bloquer les messages priv\195\169s (whispers)"
L["FILTER_SAY"] = "Bloquer le /dire (/say)"
L["FILTER_YELL"] = "Bloquer le /crier (/yell)"
L["FILTER_EMOTE"] = "Bloquer les emotes"
L["FILTER_DUEL"] = "Refuser automatiquement les duels"
L["FILTER_TRADE"] = "Fermer automatiquement les \195\169changes"
L["FILTER_GUILD_INVITE"] = "Refuser automatiquement les invitations de guilde"
L["FILTER_STRICT_GROUP_INVITE_SYSTEM"] = "Filtrage renforce en instance"

-- Filter tooltips
L["TIP_GROUP_INVITE"] = "Bloque et refuse les invitations de groupe des joueurs non autoris\195\169s.\nLe message syst\195\168me dans le chat est aussi supprim\195\169.\n\nExemple : un inconnu vous invite => rien ne s'affiche."
L["TIP_WHISPER"] = "Bloque les messages priv\195\169s des joueurs non autoris\195\169s.\n\nExemple : un inconnu vous envoie un MP => vous ne le voyez pas."
L["TIP_SAY"] = "Bloque les messages /dire des joueurs non autoris\195\169s.\n\nExemple : un inconnu parle pr\195\168s de vous => son texte n'appara\195\174t pas."
L["TIP_YELL"] = "Bloque les messages /crier des joueurs non autoris\195\169s."
L["TIP_EMOTE"] = "Masque les messages d'emotes dans le chat des joueurs non autoris\195\169s.\nAttention : cela ne masque pas l'animation du personnage, seulement le texte dans le chat.\n\nExemple : un inconnu fait /danser => le texte 'X danse avec vous' n'appara\195\174t pas dans le chat, mais vous verrez toujours l'animation."
L["TIP_DUEL"] = "Refuse automatiquement les demandes de duel des joueurs non autoris\195\169s."
L["TIP_TRADE"] = "Ferme automatiquement la fen\195\170tre d'\195\169change avec un joueur non autoris\195\169."
L["TIP_GUILD_INVITE"] = "Refuse automatiquement les invitations de guilde des joueurs non autoris\195\169s."
L["TIP_STRICT_GROUP_INVITE_SYSTEM"] = "Mode avance : a activer seulement si vous recevez quand meme des invitations indesirables en donjon, raid ou instance.\n\nSanctuary masquera certains messages systeme proteges que WoW ne laisse pas lire pendant que le filtre d'invitations de groupe est actif. Cela peut masquer quelques messages systeme WoW legitimes."

-- Auto-trust
L["GROUP_AUTO_TRUST"] = "Trust automatique"
L["FILTER_AUTO_TRUST"] = "Trust automatique (ajoute les joueurs en groupe 5+ min)"
L["TIP_AUTO_TRUST"] = "Les joueurs qui restent dans votre groupe pendant 5+ minutes sont automatiquement et d\195\169finitivement ajout\195\169s \195\160 votre whitelist.\n\nExemple : vous faites un donjon avec quelqu'un pendant 10 min => il est ajout\195\169."

-- Group titles
L["GROUP_MAIN_PROTECTION"] = "Protection principale"
L["GROUP_COMMUNICATION"] = "Communication"
L["GROUP_INTERACTIONS"] = "Interactions"

-- Channels
L["GROUP_CHANNELS"] = "Canaux (/1, /2, /3...)"
L["CHANNEL_NONE"] = "Aucun filtrage"
L["CHANNEL_KEYWORDS"] = "Pseudos suspects uniquement"
L["CHANNEL_ALL"] = "Tout filtrer (sauf whitelist)"
L["TIP_CHANNEL_NONE"] = "Les messages dans les canaux (G\195\169n\195\169ral, Commerce...) ne sont pas filtr\195\169s."
L["TIP_CHANNEL_KEYWORDS"] = "Bloque les messages dans les canaux si le pseudo de l'exp\195\169diteur contient un pseudo suspect.\nExemple : si 'jetaime' est dans vos pseudos suspects, un joueur 'Jetaime' dans le canal G\195\169n\195\169ral sera bloqu\195\169."
L["TIP_CHANNEL_ALL"] = "Bloque TOUS les messages dans les canaux des joueurs non autoris\195\169s.\nAttention : cela rend les canaux publics silencieux."

-- Notifications
L["GROUP_NOTIFICATIONS"] = "Notifications"
L["NOTIF_SILENT"] = "Silencieux"
L["NOTIF_MINIMAL"] = "Minimal"
L["NOTIF_VERBOSE"] = "D\195\169taill\195\169"
L["TIP_NOTIF_SILENT"] = "Aucun message dans le chat. La protection fonctionne en silence total."
L["TIP_NOTIF_MINIMAL"] = "Un r\195\169sum\195\169 p\195\169riodique s'affiche dans le chat (ex: '5 interactions bloqu\195\169es cette session')."
L["TIP_NOTIF_VERBOSE"] = "Chaque interaction bloqu\195\169e est signal\195\169e dans le chat. Utile pour tester."

-- Suspects tab
L["SUSPECTS_HEADER"] = "Patterns de pseudos"
L["SUSPECTS_DESC"] = "Les joueurs dont le pseudo contient un de ces mots seront bloqu\195\169s, m\195\170me s'ils sont dans vos sources de confiance.\nExemple : mot 'test' => bloque 'ToTuTesT', 'MonTestPerso', etc."
L["SUSPECTS_COUNT"] = "%s pattern(s)"
L["SUSPECTS_ADD_BTN"] = "Ajouter"

-- Whitelist tab
L["WL_HEADER"] = "Whitelist manuelle"
L["WL_ADD_BTN"] = "Ajouter"
L["WL_COUNT"] = "%s joueur(s)"
L["WL_ADDED_ON"] = "ajout\195\169 le %s"

-- Logs
L["LOGS_HEADER"] = "Journal des interactions bloqu\195\169es"
L["LOGS_ENABLE"] = "Activer les logs"
L["LOGS_SHOW_MSG"] = "Afficher les messages"
L["LOGS_CLEAR_BTN"] = "Vider le journal"
L["LOGS_EXPORT_BTN"] = "Exporter"
L["LOGS_COUNT_FULL"] = "%s entr\195\169e(s) / %s max"
L["LOGS_CLEAR_CONFIRM"] = "Voulez-vous vraiment supprimer tout le journal ?\nCette action est irr\195\169versible."
L["LOGS_CLEAR_YES"] = "Supprimer"
L["LOGS_CLEAR_NO"] = "Annuler"

-- Log types
L["LOG_TYPE_INVITE"] = "Invite"
L["LOG_TYPE_WHISPER"] = "Whisper"
L["LOG_TYPE_SAY"] = "Dire"
L["LOG_TYPE_YELL"] = "Crier"
L["LOG_TYPE_EMOTE"] = "Emote"
L["LOG_TYPE_DUEL"] = "Duel"
L["LOG_TYPE_TRADE"] = "\195\137change"
L["LOG_TYPE_GUILD"] = "Guilde"
L["LOG_TYPE_CHANNEL"] = "Canal"

-- Logs grouped
L["LOGS_EXPAND_ALL"] = "D\195\169plier tout"
L["LOGS_COLLAPSE_ALL"] = "Replier tout"
L["LOGS_LAST_ACTIVITY"] = "dernier : %s"
L["LOGS_GROUP_HEADER"] = "%s (%d)"

-- Export
L["EXPORT_SUSPECT_TAG"] = "[pseudo suspect : %s]"
L["EXPORT_TITLE"] = "Exporter les logs"
L["EXPORT_INSTRUCTIONS"] = "Ctrl+A puis Ctrl+C pour copier"
L["EXPORT_CLOSE"] = "Fermer"
L["EXPORT_HEADER"] = "=== Sanctuary - Journal des interactions bloqu\195\169es ==="
L["EXPORT_DATE"] = "Export du %s"
L["EXPORT_TOTAL"] = "Total : %s entr\195\169es"
L["EXPORT_COLUMNS"] = "Date | Type | Source | Message | Pseudo suspect"

-- Settings
L["SETTINGS_TITLE"] = "Sanctuary v%s"
L["SETTINGS_DESC"] = "Protection anti-harc\195\168lement par whitelist"
L["SETTINGS_OPEN_BTN"] = "Ouvrir Sanctuary"

-- Status bar
L["STATUSBAR_SESSION"] = "Session : %s bloqu\195\169(s)"
L["STATUSBAR_LOG"] = "Log : %s/%s"
L["STATUSBAR_SUSPECTS"] = "Patterns : %s"

-- Debug mode
L["GROUP_DEBUG"] = "Diagnostics"
L["DEBUG_ENABLE"] = "Activer le mode debug"
L["TIP_DEBUG"] = "Capture des donn\195\169es de diagnostic\npour les interactions filtr\195\169es.\n\nPeut contenir des noms de joueurs,\ndes notifications syst\195\168me et de courts\nextraits de messages filtr\195\169s.\nRien n'est envoy\195\169 -- copier-coller.\n\nActiver ou d\195\169sactiver conserve le log :\nutilisez Vider pour l'effacer."
L["DEBUG_EXPORT_BTN"] = "Exporter le log debug"
L["DEBUG_CLEAR_BTN"] = "Vider"
L["DEBUG_EMPTY"] = "Le log debug est vide. Activez le mode debug, puis jouez normalement."
L["DEBUG_EXPORT_TITLE"] = "Export du log debug"
L["DEBUG_EXPORT_INSTRUCTIONS"] = "Ctrl+A puis Ctrl+C pour copier"
L["DEBUG_COUNT"] = "Debug : %s"
L["DEBUG_ENABLED_MSG"] = "Mode debug activ\195\169. Jouez normalement, puis exportez."
L["DEBUG_DISABLED_MSG"] = "Mode debug d\195\169sactiv\195\169. Le log est conserv\195\169."
L["DEBUG_CLEAR_CONFIRM"] = "Effacer le log debug (%s entr\195\169es) ?\nCette action est irr\195\169versible."
L["DEBUG_CLEARED_MSG"] = "Log debug effac\195\169."
L["SOUND_UNMUTE_FAILED"] = "Sanctuary n'a pas pu r\195\169tablir les sons de panneau du jeu. Red\195\169marrez le client pour les retrouver : un rechargement ou une reconnexion n'y suffira pas."

-- Whitelist readback (onglet Whitelist)
L["WL_AUTO_HEADER"] = "Autoris\195\169s automatiquement"
L["WL_AUTO_HINT"] = "Lecture seule. Reconstruite \195\160 l'ouverture de l'onglet."
L["WL_AUTO_EMPTY"] = "Aucun contact autoris\195\169 automatiquement."
L["WL_AUTO_NO_MATCH"] = "Aucun r\195\169sultat pour cette recherche."
L["WL_SOURCE_GUILD"] = "Membres de la guilde"
L["WL_SOURCE_FRIEND"] = "Amis"
L["WL_SOURCE_BNET"] = "Amis Battle.net"
L["WL_SOURCE_GROUP"] = "Groupe actuel"
L["WL_GROUP_ROW"] = "%s (%s)"
L["WL_GROUP_ROW_FILTERED"] = "%s (%s affich\195\169s sur %s)"
L["WL_SEARCH_LABEL"] = "Rechercher"
L["WL_CHECK_LABEL"] = "Est-ce que cette personne passe ?"
L["WL_CHECK_BTN"] = "V\195\169rifier"
L["WL_CHECK_PASS"] = "%s passe -- %s"
L["WL_CHECK_BLOCK"] = "%s est filtr\195\169 -- %s"
L["WL_CHECK_INVALID"] = "Nom invalide."
L["WL_CHECK_BNET_ONLY"] = " (compte Battle.net autoris\195\169 : %s)"
L["WL_REASON_MANUAL"] = "ajout\195\169 manuellement"
L["WL_REASON_TRUST"] = "trust automatique"
L["WL_REASON_GUILD"] = "membre de la guilde"
L["WL_REASON_FRIEND"] = "ami"
L["WL_REASON_BNET"] = "ami Battle.net"
L["WL_REASON_GROUP"] = "groupe actuel"
L["WL_REASON_KEYWORD"] = "pattern suspect : %s"
L["WL_REASON_NOT_WHITELISTED"] = "dans aucune de vos listes"

-- Panneau de diagnostic (mode debug uniquement)
L["TAB_DIAGNOSTICS"] = "Diagnostics"
L["DIAG_PANEL_HEADER"] = "Diagnostics -- mode debug"
L["DIAG_PANEL_INTRO"] = "Les m\195\170mes diagnostics que les commandes /sanc, en un clic. Visible seulement quand le mode debug est actif."
L["DIAG_RUN_ALL"] = "Tout lancer (sauf le sensible)"
L["DIAG_CLEAR"] = "Effacer"
L["DIAG_RESULT_EMPTY"] = "Aucun diagnostic lanc\195\169 pour l'instant."
L["DIAG_SENSITIVE"] = "\195\137crit le vrai pseudo Battle.net d'un ami dans le journal de debug."
L["DIAG_UNKNOWN"] = "Diagnostic inconnu : %s"
L["DIAG_FAILED"] = "Diagnostic %s : \195\137CHEC (%s)"
L["DIAG_LEFT_ON_SCREEN"] = "Cette fen\195\170tre n'a pas pu \195\170tre referm\195\169e : elle est encore \195\160 l'\195\169cran, invisible et cliquable. Ne cliquez nulle part."
L["DIAG_RESTORE_BTN"] = "Remettre l'\195\169cran \195\160 plat (/reload)"
L["DIAG_SIM_INVITE"] = "Simuler une invitation"
L["DIAG_SIM_BNET"] = "Simuler un chuchotement Battle.net"
L["DIAG_SIM_BNETFRIEND"] = "Simuler un vrai ami Battle.net"
L["DIAG_CHAT_INVITE"] = "Diagnostic chat (invitation)"
L["DIAG_SOUND_INVITE"] = "Diagnostic son"
L["DIAG_POPUP_INVITE"] = "Fen\195\170tre d'invitation de groupe"
L["DIAG_POPUP_DUEL"] = "Fen\195\170tre de duel"
L["DIAG_POPUP_GUILD"] = "Fen\195\170tre d'invitation de guilde"
L["DIAG_POPUP_LIST"] = "Lister les fen\195\170tres du jeu"
L["DIAG_ARG_NAME"] = "nom"
L["DIAG_ARG_INDEX"] = "n\194\176"
L["DIAG_ARG_FILTER"] = "filtre"
L["DIAG_TIP_SOUND"] = "Montez le volume : cette v\195\169rification se fait \195\160 l'oreille."
L["DIAG_TIP_POPUP"] = "Regardez l'\195\169cran. \195\128 ne pas lancer si une vraie demande est en attente."

-- Resume de releve
L["DEBUG_SUMMARY_TITLE"] = "Sanctuary -- r\195\169sum\195\169 de relev\195\169"
L["DEBUG_SUMMARY_BTN"] = "R\195\169sum\195\169 de relev\195\169"
L["DEBUG_SUMMARY_INSTRUCTIONS"] = "Contr\195\180le d'un coup d'oeil. Le relev\195\169 lui-m\195\170me est le fichier de r\195\169glages."
L["DEBUG_SUMMARY_FILE"] = "Le relev\195\169 officiel est le fichier de r\195\169glages que le jeu \195\169crit en quittant :\nWorld of Warcraft/_retail_/WTF/Account/<COMPTE>/SavedVariables/Sanctuary.lua\nCette fen\195\170tre est un contr\195\180le, pas un canal de transport."
L["DEBUG_FULL_BTN"] = "Rapport complet"
L["DEBUG_FULL_WARNING"] = "Lecture \195\160 l'\195\169cran seulement -- ce n'est pas un relev\195\169. Utilisez le fichier de r\195\169glages."

end -- frFR
