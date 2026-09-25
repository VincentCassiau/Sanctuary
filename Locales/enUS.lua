local _, ns = ...

-- ============================================================================
-- Every string the add-on can show, in English: the reference every other
-- language is held to. Each language has a file of its own in this folder and
-- overrides the keys it translates; Locales\apply.lua, loaded last, builds the
-- table the add-on reads. A value that exists in English only renders in
-- English to everybody else -- readable, so nobody reports it, and it drifts.
-- The harness checks the parity, file by file.
--
-- Every file is plain UTF-8: an accented letter is written as itself, never as
-- escaped bytes.
--
-- One rule of writing, decision 153: NO em dash inside a sentence. Two clauses
-- joined by a long dash reads as machine-written, and a comma, a colon or a
-- full stop says the same thing. The only
-- one left opens a string rather than sitting inside one -- the "- experimental"
-- mention he validated himself. The harness holds every locale to it.
-- ============================================================================

ns.locales = ns.locales or {}
local L = {}
ns.locales.enUS = L

-- General
L["ADDON_LOADED_ACTIVE"] = "Active. Type /sanc to open."
L["ADDON_LOADED_INACTIVE"] = "Inactive."
-- One line per point, printed under the load line for a day after the first
-- login that follows an update. Spelt out one by one on purpose: a line built
-- from a number is a line no translator can find.
L["CHANGELOG_1_1_0_TITLE"] = "New in 1.1.0:"
L["CHANGELOG_1_1_0_MAIL"] = "Mail from filtered people can be deleted."
L["CHANGELOG_1_1_0_SAY_YELL"] = "The /say and /yell options have been merged."
L["CHANGELOG_1_1_0_POLISH"] = "Interface improvements."
L["SANCTUARY_ENABLED"] = "Protection enabled."
L["SANCTUARY_DISABLED"] = "Protection disabled."
L["LOG_CLEARED"] = "Journal cleared."
L["DATE_TIME_FORMAT"] = "%Y-%m-%d %H:%M:%S"
L["SOUND_UNMUTE_FAILED"] = "Sanctuary could not restore the game's panel sounds. Restart the game client to get them back. A reload or a relog will not clear this."

-- Chat notifications
L["BLOCKED_VERBOSE"] = "Blocked: %s from %s"
L["BLOCKED_SESSION"] = "%s interaction(s) blocked this session."

-- Header
L["HEADER_STATE_ON"] = "Protection on"
L["HEADER_STATE_OFF"] = "Protection off"
L["HEADER_TIP_NOTHING"] = "Nothing is being filtered."
L["HEADER_TIP_ALLOWED"] = "%s allowed people."
L["HEADER_TIP_CLICK_OFF"] = "Click to turn Sanctuary off."
L["HEADER_TIP_CLICK_ON"] = "Click to turn Sanctuary on."
L["KIND_GROUP_INVITE"] = "Group invitations"
L["KIND_WHISPER"] = "private messages"
L["KIND_DUEL"] = "duels"
L["KIND_TRADE"] = "trades"
L["KIND_GUILD_INVITE"] = "guild invitations"

-- Tabs
L["TAB_PROTECTION"] = "Protection"
L["TAB_JOURNAL"] = "Journal"
L["TAB_ADVANCED"] = "Advanced"
L["TAB_ABOUT"] = "About"
L["TAB_DIAGNOSTICS"] = "Diagnostics"

-- Question 1 -- who can contact you
L["Q1_TITLE"] = "Who can contact you?"
L["Q1_STRANGERS_TITLE"] = "Only people I know"
L["Q1_STRANGERS_DESC"] = "Your friends, your guild, your group, and the names you allow. Everyone else is blocked."
L["Q1_BLOCKEDONLY_TITLE"] = "Everyone, except the people I block"
L["Q1_BLOCKEDONLY_DESC"] = "Nothing is filtered, apart from your blocked names and your patterns."

-- Question 2 -- what Sanctuary blocks
L["Q2_TITLE"] = "What should Sanctuary block?"
L["Q2_ALL_TITLE"] = "Everything"
L["Q2_ALL_DESC"] = "Group invitations, private messages, duels, trades, guild invitations. Recommended."
L["Q2_CUSTOM_TITLE"] = "I choose"
L["Q2_CUSTOM_DESC"] = "Pick what gets blocked yourself."
L["Q2_COVERED"] = "Nothing to choose here: You have chosen to only filter blocked players."
L["FILTER_GROUP_INVITE"] = "Block group invitations"
-- The mention is part of the label (decision 162e) and it is the one word on the
-- screen drawn in another colour than its own sentence (decision 170b): the
-- orange the state notes wear, `C.orange` of SanctuaryUI, written as the escape
-- the client draws. In the string rather than beside it, because the label folds
-- at the narrow end of the window and a second FontString chasing the end of a
-- folded line is a position nobody can keep right.
L["FILTER_STRICT_GROUP_INVITE_SYSTEM"] = "Enhanced filtering in instances |cffff9933(experimental)|r"
L["FILTER_WHISPER"] = "Block private messages (/w)"
L["FILTER_SAY_YELL"] = "Block /say and /yell"
L["FILTER_EMOTE"] = "Block emote text"
L["FILTER_DUEL"] = "Auto-decline duels"
L["FILTER_TRADE"] = "Auto-close trades"
L["FILTER_GUILD_INVITE"] = "Auto-decline guild invitations"
L["CHANNELS_LABEL"] = "Public channels (/1, /2, /3...)"
L["CHANNEL_NONE"] = "Filter nothing"
L["CHANNEL_KEYWORDS"] = "Filter suspect names"
L["CHANNEL_ALL"] = "Filter everything, except my allowed names"

-- Question 2 -- tooltips
L["TIP_GROUP_INVITE"] = "Blocks and auto-declines group invitations from people who are not allowed.\nThe system message in chat is suppressed too.\n\nExample: a stranger invites you => nothing appears."
L["TIP_WHISPER"] = "Blocks private messages from people who are not allowed.\n\nExample: a stranger sends you a PM => you do not see it."
L["TIP_SAY_YELL"] = "Blocks /say and /yell messages from people who are not allowed.\n\nExample: a stranger speaks near you => their text does not appear."
L["TIP_EMOTE"] = "Hides emote text in chat from people who are not allowed.\nNote: this hides the text only, not the character animation.\n\nExample: a stranger does /dance => the line does not appear in chat, but you still see the animation."
L["TIP_DUEL"] = "Auto-declines duel requests from people who are not allowed."
L["TIP_TRADE"] = "Auto-closes the trade window with someone who is not allowed."
L["TIP_GUILD_INVITE"] = "Auto-declines guild invitations from people who are not allowed."
L["TIP_CHANNEL_NONE"] = "Messages in channels (General, Trade...) are not filtered."
L["TIP_CHANNEL_KEYWORDS"] = "Blocks messages in channels when the sender's name matches one of your patterns."
L["TIP_CHANNEL_ALL"] = "Blocks EVERY message in channels from people who are not allowed.\nWarning: this makes public channels silent."
L["TIP_STRICT_GROUP_INVITE_SYSTEM"] = "Experimental: enable it only if unwanted group invitations still reach you in a dungeon, raid, or PvP match.\n\nWhen WoW locks the chat down (instance boss fights, Mythic+ keys, PvP matches), add-ons can no longer read system messages. With this option on, while you are grouped or in an instance, Sanctuary hides EVERY system message, not only invitations: the game does not let it tell them apart."

-- Question 3 -- the mailbox
L["MAIL_Q_TITLE"] = "And your mail?"
L["MAIL_KEEP_TITLE"] = "Leave it"
L["MAIL_KEEP_DESC"] = "Your mailbox stays exactly as it is."
L["MAIL_DELETE_TITLE"] = "Delete it"
L["MAIL_DELETE_DESC"] = "Mail from a filtered person is gone when you open the mailbox, unread."
L["MAIL_ATTACH_LABEL"] = "If it has items or money in it"
L["MAIL_ATTACH_KEEP"] = "Leave it"
L["MAIL_ATTACH_RETURN"] = "Send it back"
L["MAIL_ATTACH_DELETE"] = "Delete it too"
L["MAIL_ICON_LABEL"] = "Mail icon on the minimap"
L["MAIL_ICON_NORMAL"] = "Normal"
L["MAIL_ICON_FILTERED"] = "Hidden when everything waiting is filtered"
L["MAIL_ICON_NEVER"] = "Never"
L["TIP_MAIL_ICON_FILTERED"] = "The mail icon next to the minimap goes by the sender names. Mail from an NPC can therefore look like mail to filter. When you open the mailbox, it is recognized as coming from an NPC and is not deleted."
L["MAIL_NOTE"] = "Mail arrives before Sanctuary can do anything. It is deleted when you open the mailbox. Mail that did not come from a player is never touched."
L["MAIL_DELETE_CONFIRM"] = "Deleting mail with items or money in it destroys what is inside. Nothing can be recovered. When the game does not allow it, the mail goes back to its sender."
L["MAIL_DELETE_OK"] = "OK"
L["MAIL_DELETE_CANCEL"] = "Cancel"

-- Question 4 -- the anti-spam of the public channels
L["ANTISPAM_Q_TITLE"] = "Should Sanctuary deal with spam in the public channels?"
L["ANTISPAM_YES_TITLE"] = "Yes, hide the repeats"
L["ANTISPAM_YES_DESC"] = "The same message from a stranger appears only once."
L["ANTISPAM_NO_TITLE"] = "No"
L["ANTISPAM_NO_DESC"] = "The channels stay as they are."
L["ANTISPAM_INTERVAL_LABEL"] = "The same message comes back only after"
L["ANTISPAM_COVERED"] = "Already covered: You filter everything in the public channels, spam from strangers never appears there."
L["ANTISPAM_D_5M"] = "5 minutes"
L["ANTISPAM_D_10M"] = "10 minutes"
L["ANTISPAM_D_30M"] = "30 minutes"
L["ANTISPAM_D_1H"] = "1 hour"
L["ANTISPAM_D_2H"] = "2 hours"
L["ANTISPAM_D_4H"] = "4 hours"
L["ANTISPAM_D_12H"] = "12 hours"
L["ANTISPAM_D_24H"] = "24 hours"

-- Question 5 -- what Sanctuary tells you
L["Q4_TITLE"] = "What does Sanctuary tell you in chat?"
L["Q4_SILENT_TITLE"] = "Nothing"
L["Q4_SILENT_DESC"] = "Complete silence. The Journal keeps the record."
L["Q4_MINIMAL_TITLE"] = "A summary"
L["Q4_MINIMAL_DESC"] = "Every 5 minutes, and only if something new was blocked."
L["Q4_VERBOSE_TITLE"] = "Every block"
L["Q4_VERBOSE_DESC"] = "One line as it happens."

-- Question 6 -- your lists
L["Q5_TITLE"] = "Your lists"
L["TILE_ALLOWED"] = "Always allowed"
L["TILE_BLOCKED"] = "Always blocked"
L["TILE_ALLOWED_DETAIL"] = "%s added by you · %s Battle.net friends"
L["TILE_BLOCKED_DETAIL"] = "%s names · %s patterns"
L["TEST_LABEL"] = "Test a name"

-- Name tester
L["TEST_ALWAYS_ALLOWED"] = "%s, always allowed: %s"
L["TEST_ALWAYS_BLOCKED"] = "%s, always blocked: %s"
L["TEST_UNKNOWN_BLOCKED"] = "%s, unknown: blocked, following your answers 1 and 2"
L["TEST_UNKNOWN_ALLOWED"] = "%s, unknown: allowed, you only block your blocked names"
L["LIST_MANUAL"] = "added by you"
L["LIST_TRUST"] = "automatic trust"
L["LIST_GUILD"] = "in your guild"
L["LIST_FRIEND"] = "realm friend"
L["LIST_BNET"] = "Battle.net friend (%s)"
L["LIST_GROUP"] = "in your group right now"
L["LIST_BLOCKED"] = "in your blocked names"
L["LIST_BLOCKED_OVER"] = "in your blocked names (even though %s)"
L["LIST_PATTERN"] = "pattern \"%s\""

-- Panels
L["PANEL_BACK"] = "< Back"
L["PANEL_ADD_BTN"] = "Add"
L["PANEL_ADD_NAME_HINT"] = "Name or Name-Realm"
L["PANEL_ADDED_BY_YOU"] = "Added by you"
L["PANEL_AUTO_TITLE"] = "Allowed automatically"
L["WL_SOURCE_BNET"] = "Battle.net friends"
L["WL_SOURCE_GUILD"] = "Guild"
L["WL_SOURCE_TRUST"] = "Automatic trust"
L["WL_TRUST_HINT"] = "People who stayed 5 minutes in your group or your raid, if you ticked \"Trust people...\" in the Protection tab."
L["WL_GROUP_NOTE"] = "Your current group or raid is allowed too, for as long as the group lasts."
L["WL_BNET_ROW"] = "%s · %s"
L["WL_BNET_OFFLINE"] = "%s (offline)"
L["PANEL_BLOCKED_DESC"] = "Blocked for everything, even if they are in your guild or your group: you will no longer see their messages or their interactions with you."
L["BNET_NOT_BLOCKED"] = "Sanctuary does not block Battle.net friends."
L["BNET_NOT_BLOCKED_HOW"] = "Do it directly on Battle.net."
-- What a refused entry is told, under the field it was typed in. The three
-- sentences say how to write the thing, not that something went wrong: a person
-- who has just been harassed does not need to be told off.
L["REFUSED_NAME"] = "A name is written Name or Name-Realm"
L["REFUSED_PATTERN"] = "A pattern is text: letters only"
-- And what a field says when the entry went in, decision 167c. Same line, same
-- six seconds, green instead of orange. The name is repeated because it is the
-- one the chip will carry, realm and all.
L["ADDED_OK"] = "Added: %s."
L["PANEL_BLOCKED_NAMES"] = "Names"
L["PANEL_BLOCKED_PATTERNS"] = "Patterns"
L["PANEL_PATTERNS_DESC"] = "A pattern is a piece of text: any name containing it is blocked, even in your guild or your group."
L["PANEL_PATTERN_HINT"] = "e.g. \"test\""
L["UNDO_REMOVED"] = "%s removed"
L["UNDO_MOVED"] = "%s removed from \"%s\""
L["UNDO_BTN"] = "Undo"
L["CHIP_ADDED_ON"] = "Added on %s"
L["CHIP_SOURCE_MANUAL"] = "Added by hand"
L["CHIP_SOURCE_MENU"] = "Added by interacting with the name"
L["CHIP_SOURCE_TRUST"] = "Automatic trust"

-- Right-click menu
L["MENU_ALLOW"] = "Sanctuary: always allow"
L["MENU_UNALLOW"] = "Sanctuary: stop allowing"
L["MENU_BLOCK"] = "Sanctuary: always block"
L["MENU_UNBLOCK"] = "Sanctuary: stop blocking"

-- Minimap button
L["MINIMAP_TIP_TITLE"] = "Sanctuary: %s"
L["MINIMAP_TIP_LEFT"] = "Click: open."
L["MINIMAP_TIP_RIGHT"] = "Right click: turn on / off."

-- Journal
L["LOGS_HEADER"] = "Blocked interaction journal"
L["LOGS_COUNT_FULL"] = "%s entries / %s max"
L["LOGS_ENABLE"] = "Record blocked interactions"
L["TIP_LOGS_ENABLE"] = "Keeps a trace of every blocked interaction: who, when, what. Unticked, nothing is recorded. Sanctuary still blocks."
L["LOGS_SHOW_MSG"] = "Show the text of blocked messages"
L["LOGS_EMPTY"] = "No blocked interaction yet."
L["LOGS_CLEAR_BTN"] = "Clear the journal"
L["LOGS_COPY_BTN"] = "Copy the journal"
L["LOGS_EXPAND_ALL"] = "Expand all"
L["LOGS_COLLAPSE_ALL"] = "Collapse all"
L["LOGS_GROUP_HEADER"] = "%s (%d)"
L["LOGS_LAST_ACTIVITY"] = "last: %s"
L["LOGS_CLEAR_CONFIRM"] = "Do you really want to clear the whole journal?\nThis cannot be undone."
L["LOGS_CLEAR_YES"] = "Clear"
L["LOGS_CLEAR_NO"] = "Cancel"
L["LOGS_ALERT_ALMOST_FULL"] = "The journal is nearly full (%d entries out of %d). Clear it, or make it bigger in the Advanced tab."
L["LOGS_ALERT_FULL"] = "The journal is full (%d entries): every new block now erases the oldest one. Clear it, or make it bigger in the Advanced tab."
L["LOGS_SPAM_BADGE"] = " · SPAM ×%d"
L["LOGS_TIME_RANGE"] = "%s – %s"
L["LOG_TYPE_INVITE"] = "Group invitation"
L["LOG_TYPE_WHISPER"] = "Private message"
L["LOG_TYPE_DUEL"] = "Duel"
L["LOG_TYPE_TRADE"] = "Trade"
L["LOG_TYPE_GUILD"] = "Guild invitation"
L["LOG_TYPE_SAY"] = "Say"
L["LOG_TYPE_YELL"] = "Yell"
L["LOG_TYPE_EMOTE"] = "Emote"
L["LOG_TYPE_CHANNEL"] = "Channel"
L["LOG_TYPE_GROUP"] = "Group"
L["LOG_TYPE_MAIL"] = "Mail"

-- Copy window and journal export
L["EXPORT_INSTRUCTIONS"] = "Ctrl+A then Ctrl+C to copy"
L["EXPORT_CLOSE"] = "Close"
L["EXPORT_HEADER"] = "=== Sanctuary - Blocked interaction journal ==="
L["EXPORT_DATE"] = "Exported on %s"
L["EXPORT_TOTAL"] = "Total: %s entries"
L["EXPORT_COLUMNS"] = "Date | Type | Source | Message | Pattern"
L["EXPORT_SUSPECT_TAG"] = "[pattern: %s]"
L["DEBUG_EXPORT_TITLE"] = "Sanctuary report"

-- Advanced
L["FILTER_AUTO_TRUST"] = "Trust people who stay at least 5 minutes in my group or my raid"
L["ADV_TRUST_DESC"] = "After 5 minutes in your group or your raid, a player is added automatically to your \"Always allowed\": they will always be able to contact you again, even after the dungeon. You can take them off the list at any time."
L["ADV_DIAG_TITLE"] = "Diagnostics"
L["DEBUG_ENABLE"] = "Enable debug mode"
L["ADV_DEBUG_DESC"] = "Records technical data about filtered interactions, and about system messages hidden in instances, to help understand a problem. Nothing is sent: you copy and paste."
L["DEBUG_EXPORT_BTN"] = "Export the report"
L["DEBUG_CLEAR_BTN"] = "Clear the debug log"
L["DEBUG_CLEAR_CONFIRM"] = "Erase the debug log (%s entries)?\nThis cannot be undone."
L["DEBUG_CLEARED_MSG"] = "Debug log erased."
L["DEBUG_ENABLED_MSG"] = "Debug mode enabled."
L["DEBUG_DISABLED_MSG"] = "Debug mode disabled. The log is kept."
L["DEBUG_EMPTY"] = "The debug log is empty. Enable debug mode, then play normally."
L["ADV_JOURNAL_TITLE"] = "Journal"
L["ADV_MAXENTRIES"] = "Maximum size"
L["ADV_ENTRIES"] = "entries"
L["ADV_MINIMAP_TITLE"] = "Minimap button"
L["ADV_MINIMAP_SHOW"] = "Show the button around the minimap"
L["ADV_STATUS"] = "Session: %s blocked · Journal: %s / %s · Debug: %s · Build %s · interface %s"
L["ADV_DEBUG_ON"] = "on"
L["ADV_DEBUG_OFF"] = "off"
L["DEBUG_SUMMARY_FILE"] = "The official record is the settings file the game writes when you quit:\nWorld of Warcraft/_retail_/WTF/Account/<ACCOUNT>/SavedVariables/Sanctuary.lua"

-- About
L["ABOUT_VERSION"] = "Version %s"
L["ABOUT_DESC"] = "Anti-harassment protection. Blocks unwanted interactions before you even know about them."
L["ABOUT_AUTHOR"] = "Author: %s"
L["ABOUT_GITHUB"] = "GitHub: %s"

-- Diagnostics tab (debug mode only)
L["DIAG_PANEL_HEADER"] = "Diagnostics: debug mode"
L["DIAG_RUN_ALL"] = "Run them all (except the manual ones)"
L["DIAG_CLEAR"] = "Clear"
L["DIAG_RESULT_EMPTY"] = "No diagnostic run yet."
L["DIAG_SENSITIVE"] = "Writes a real Battle.net account name into the debug log."
L["DIAG_MANUAL"] = "Run this one on its own, and listen."
L["DIAG_UNKNOWN"] = "Unknown diagnostic: %s"
L["DIAG_FAILED"] = "Diagnostic %s: FAILED (%s)"
L["DIAG_LEFT_ON_SCREEN"] = "This window could not be closed: it is still on screen, invisible and clickable. Do not click anywhere."
L["DIAG_RESTORE_BTN"] = "Put the screen back (/reload)"
L["DIAG_SIM_INVITE"] = "Simulate an invitation"
L["DIAG_SIMULATE_SPAM"] = "Simulate channel spam"
L["DIAG_TIP_SPAM"] = "Sends the same line three times through the real path, as a stranger would. Only the copies the filter did not hide appear in the chat. The Journal keeps one entry, in the channel category."
L["DIAG_SPAM_PROBE_MSG"] = "Sanctuary anti-spam test message"
L["DIAG_SPAM_PROBE_LINE"] = "%s: %s"
L["DIAG_SIM_BNET"] = "Simulate a Battle.net whisper"
L["DIAG_SIM_BNETFRIEND"] = "Simulate a real Battle.net friend"
L["DIAG_CHAT_INVITE"] = "Chat diagnostic (invitation)"
L["DIAG_CHAT_LOCKDOWN"] = "Test the masking in an instance"
L["DIAG_SOUND_OPEN"] = "Window opening sound"
L["DIAG_SOUND_INVITE"] = "Group invitation sound"
L["DIAG_POPUP_INVITE"] = "Group invitation window"
L["DIAG_POPUP_DUEL"] = "Duel window"
L["DIAG_POPUP_GUILD"] = "Guild invitation window"
L["DIAG_POPUP_LIST"] = "List the game windows"
L["DIAG_MAIL_SCAN"] = "Scan the mailbox"
L["DIAG_ARG_NAME"] = "name"
L["DIAG_ARG_NAME_OR_INDEX"] = "name or no."
L["DIAG_ARG_FILTER"] = "filter"
L["DIAG_TIP_SOUND"] = "Turn the volume up: this one is checked by ear."
L["DIAG_TIP_POPUP"] = "Watch the screen. Do not run while a real request is pending."
L["DIAG_TIP_MAIL_SCAN"] = "Run this one with a mailbox open. It deletes nothing. It says what Sanctuary would do with each mail."
