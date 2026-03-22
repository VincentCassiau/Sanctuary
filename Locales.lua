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

-- Filter labels
L["FILTER_GROUP_INVITE"] = "Block group invitations"
L["FILTER_WHISPER"] = "Block private messages (whispers)"
L["FILTER_SAY"] = "Block /say"
L["FILTER_YELL"] = "Block /yell"
L["FILTER_EMOTE"] = "Block emotes"
L["FILTER_DUEL"] = "Auto-decline duels"
L["FILTER_TRADE"] = "Auto-close trades"
L["FILTER_GUILD_INVITE"] = "Auto-decline guild invitations"

-- Filter tooltips
L["TIP_GROUP_INVITE"] = "Blocks and auto-declines group invitations from unauthorized players.\nThe system message in chat is also suppressed.\n\nExample: a stranger invites you => nothing appears."
L["TIP_WHISPER"] = "Blocks private messages from unauthorized players.\n\nExample: a stranger sends you a PM => you don't see it."
L["TIP_SAY"] = "Blocks /say messages from unauthorized players.\n\nExample: a stranger speaks near you => their text doesn't appear."
L["TIP_YELL"] = "Blocks /yell messages from unauthorized players."
L["TIP_EMOTE"] = "Hides emote messages in chat from unauthorized players.\nNote: this only hides the text in chat, not the character animation.\n\nExample: a stranger does /dance => the text 'X dances with you' doesn't appear in chat, but you still see the animation."
L["TIP_DUEL"] = "Auto-declines duel requests from unauthorized players."
L["TIP_TRADE"] = "Auto-closes the trade window with unauthorized players."
L["TIP_GUILD_INVITE"] = "Auto-declines guild invitations from unauthorized players."

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

-- ============================================================================
-- French overrides (frFR)
-- ============================================================================

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

-- Filter labels
L["FILTER_GROUP_INVITE"] = "Bloquer les invitations de groupe"
L["FILTER_WHISPER"] = "Bloquer les messages priv\195\169s (whispers)"
L["FILTER_SAY"] = "Bloquer le /dire (/say)"
L["FILTER_YELL"] = "Bloquer le /crier (/yell)"
L["FILTER_EMOTE"] = "Bloquer les emotes"
L["FILTER_DUEL"] = "Refuser automatiquement les duels"
L["FILTER_TRADE"] = "Fermer automatiquement les \195\169changes"
L["FILTER_GUILD_INVITE"] = "Refuser automatiquement les invitations de guilde"

-- Filter tooltips
L["TIP_GROUP_INVITE"] = "Bloque et refuse les invitations de groupe des joueurs non autoris\195\169s.\nLe message syst\195\168me dans le chat est aussi supprim\195\169.\n\nExemple : un inconnu vous invite => rien ne s'affiche."
L["TIP_WHISPER"] = "Bloque les messages priv\195\169s des joueurs non autoris\195\169s.\n\nExemple : un inconnu vous envoie un MP => vous ne le voyez pas."
L["TIP_SAY"] = "Bloque les messages /dire des joueurs non autoris\195\169s.\n\nExemple : un inconnu parle pr\195\168s de vous => son texte n'appara\195\174t pas."
L["TIP_YELL"] = "Bloque les messages /crier des joueurs non autoris\195\169s."
L["TIP_EMOTE"] = "Masque les messages d'emotes dans le chat des joueurs non autoris\195\169s.\nAttention : cela ne masque pas l'animation du personnage, seulement le texte dans le chat.\n\nExemple : un inconnu fait /danser => le texte 'X danse avec vous' n'appara\195\174t pas dans le chat, mais vous verrez toujours l'animation."
L["TIP_DUEL"] = "Refuse automatiquement les demandes de duel des joueurs non autoris\195\169s."
L["TIP_TRADE"] = "Ferme automatiquement la fen\195\170tre d'\195\169change avec un joueur non autoris\195\169."
L["TIP_GUILD_INVITE"] = "Refuse automatiquement les invitations de guilde des joueurs non autoris\195\169s."

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

end -- frFR
