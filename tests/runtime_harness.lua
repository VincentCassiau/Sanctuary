local failures = 0
local assertions = 0
local unpackCompat = table.unpack or unpack

local function fail(message)
    failures = failures + 1
    io.stderr:write("FAIL: " .. message .. "\n")
end

local function check(condition, message)
    assertions = assertions + 1
    if not condition then fail(message) end
end

local function equal(actual, expected, message)
    assertions = assertions + 1
    if actual ~= expected then
        fail(message .. " (expected=" .. tostring(expected) .. ", actual=" .. tostring(actual) .. ")")
    end
end

local function lastDebug(cat, action)
    if not SanctuaryDB or not SanctuaryDB.debugLog then return nil end
    for i = #SanctuaryDB.debugLog, 1, -1 do
        local entry = SanctuaryDB.debugLog[i]
        if entry.cat == cat and (not action or (entry.data and entry.data.action == action)) then
            return entry
        end
    end
    return nil
end

function wipe(tbl)
    for key in pairs(tbl) do tbl[key] = nil end
    return tbl
end

local now = 1000
function GetTime() return now end
function time() return 1700000000 + math.floor(now) end
function date(fmt, value) return "2026-06-20 12:00:00" end
function GetLocale() return "frFR" end
function GetNormalizedRealmName() return "TestRealm" end

UNKNOWNOBJECT = "Unknown"
STATICPOPUP_NUMDIALOGS = 4

local timers = {}
local tickers = {}
C_Timer = {}
function C_Timer.After(delay, callback)
    timers[#timers + 1] = callback
end
function C_Timer.NewTicker(interval, callback)
    tickers[#tickers + 1] = callback
    return { Cancel = function(self) self.cancelled = true end }
end
local function runTimers()
    local pending = timers
    timers = {}
    for _, callback in ipairs(pending) do callback() end
end
local function runTickers()
    for _, callback in ipairs(tickers) do callback() end
end

local guildMembers = {}
local bnetFriends = {}
local charFriends = {}
local groupMembers = {}
local npcName = nil
local inGuild = false
local inGroup = false
local inRaid = false

function IsInGuild() return inGuild end
function GetNumGuildMembers() return #guildMembers end
function GetGuildRosterInfo(index) return guildMembers[index] end
function BNGetNumFriends() return #bnetFriends end
C_BattleNet = {}
function C_BattleNet.GetFriendAccountInfo(index) return bnetFriends[index] end
C_FriendList = {}
function C_FriendList.GetNumFriends() return #charFriends end
function C_FriendList.GetFriendInfoByIndex(index)
    local name = charFriends[index]
    return name and { name = name } or nil
end
function C_FriendList.ShowFriends() end
C_GuildInfo = { GuildRoster = function() end }
C_AddOns = { IsAddOnLoaded = function() return false end }

function IsInGroup() return inGroup end
function IsInRaid() return inRaid end
function GetNumGroupMembers()
    if not inGroup then return 0 end
    return #groupMembers + (inRaid and 0 or 1)
end
function UnitIsUnit(unitA, unitB) return unitA == unitB end
function UnitFullName(unit)
    if unit == "player" then return "Victim", "TestRealm" end
    local index = tonumber(unit:match("%d+"))
    local value = index and groupMembers[index]
    if not value then return nil end
    local name, realm = value:match("^([^-]+)%-(.+)$")
    return name or value, realm
end
function UnitName(unit)
    if unit == "player" then return "Victim", "TestRealm" end
    if unit == "NPC" then return npcName end
    local index = tonumber(unit:match("%d+"))
    local value = index and groupMembers[index]
    if not value then return nil end
    local name, realm = value:match("^([^-]+)%-(.+)$")
    return name or value, realm
end

local chatMessages = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(self, message) chatMessages[#chatMessages + 1] = message end }
ChatFrame1 = DEFAULT_CHAT_FRAME

local muted = {}
local unmuted = {}
local mutedSoundFiles = {}
local playedSounds = {}
SOUNDKIT = {
    IG_PLAYER_INVITE = 880,
    IG_MAINMENU_OPEN = 850,
    IG_MAINMENU_CLOSE = 851,
    IG_MAINMENU_OPTION_CHECKBOX_ON = 852,
    IG_MAINMENU_OPTION_CHECKBOX_OFF = 853,
    IG_CHARACTER_INFO_TAB = 854,
}
local soundFilesByName = {
    igPlayerInvite = 567451,
    [SOUNDKIT.IG_PLAYER_INVITE] = 567451,
    igMainMenuOpen = 567490,
    [SOUNDKIT.IG_MAINMENU_OPEN] = 567490,
    igMainMenuClose = 567464,
    [SOUNDKIT.IG_MAINMENU_CLOSE] = 567464,
}
function MuteSoundFile(id)
    muted[#muted + 1] = id
    mutedSoundFiles[id] = true
end
function UnmuteSoundFile(id)
    unmuted[#unmuted + 1] = id
    mutedSoundFiles[id] = nil
end
function PlaySound(sound)
    local fileID = soundFilesByName[sound]
    if fileID and mutedSoundFiles[fileID] then return end
    playedSounds[#playedSounds + 1] = sound
end

local declinedGroups = 0
local cancelledDuels = 0
local declinedGuilds = 0
local closedTrades = 0
function DeclineGroup() declinedGroups = declinedGroups + 1 end
function CancelDuel() cancelledDuels = cancelledDuels + 1 end
function DeclineGuild() declinedGuilds = declinedGuilds + 1 end
function CloseTrade() closedTrades = closedTrades + 1 end

local forbiddenStaticHides = 0
function StaticPopup_Hide(which)
    forbiddenStaticHides = forbiddenStaticHides + 1
end

local function newPopup(name)
    local popup = {
        name = name,
        shown = false,
        alpha = 1,
        which = nil,
        scripts = {},
    }
    function popup:IsShown() return self.shown end
    function popup:GetAlpha() return self.alpha end
    function popup:SetAlpha(alpha) self.alpha = alpha end
    function popup:HookScript(script, callback)
        local previous = self.scripts[script]
        if previous then
            self.scripts[script] = function(...)
                previous(...)
                callback(...)
            end
        else
            self.scripts[script] = callback
        end
    end
    function popup:Hide()
        if not self.shown then return end
        self.shown = false
        local dialogInfo = StaticPopupDialogs and StaticPopupDialogs[self.which]
        if dialogInfo and dialogInfo.OnHide then
            dialogInfo.OnHide(self, self.data)
        end
        PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
        if self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    return popup
end

local function newSpecialFrame(name)
    local frame = {
        name = name,
        shown = false,
        alpha = 1,
        special = false,
        accepted = nil,
        scripts = {},
    }
    function frame:IsShown() return self.shown end
    function frame:GetAlpha() return self.alpha end
    function frame:SetAlpha(alpha) self.alpha = alpha end
    function frame:HookScript(script, callback)
        local previous = self.scripts[script]
        if previous then
            self.scripts[script] = function(...)
                previous(...)
                callback(...)
            end
        else
            self.scripts[script] = callback
        end
    end
    function frame:Show()
        self.shown = true
        if self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function frame:Hide()
        if not self.shown then return end
        self.shown = false
        if self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    return frame
end

for i = 1, STATICPOPUP_NUMDIALOGS do
    _G["StaticPopup" .. i] = newPopup("StaticPopup" .. i)
end

GuildInviteFrame = newSpecialFrame("GuildInviteFrame")

local popup = StaticPopup1
StaticPopupDialogs = {
    PARTY_INVITE = {
        sound = SOUNDKIT.IG_PLAYER_INVITE,
        OnShow = function(dialog)
            dialog.inviteAccepted = nil
        end,
        OnHide = function(dialog)
            if not dialog.inviteAccepted then
                DeclineGroup()
                dialog:Hide()
            end
        end,
    },
    DUEL_REQUESTED = { sound = SOUNDKIT.IG_PLAYER_INVITE },
}

function StaticPopup_OnShow(dialog)
    local dialogInfo = StaticPopupDialogs and StaticPopupDialogs[dialog.which]
    if dialogInfo and dialogInfo.OnShow then
        dialogInfo.OnShow(dialog, dialog.data)
    end
end

function StaticPopup_Show(which, text_arg1, text_arg2, data)
    if which == "GUILD_INVITE" then
        fail("Retail guild invites must not use StaticPopup_Show(\"GUILD_INVITE\")")
    end
    popup.which = which
    popup.data = data
    popup.shown = true
    popup.alpha = 1
    StaticPopup_OnShow(popup)
    PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
    local dialog = StaticPopupDialogs[which]
    if dialog and dialog.sound then
        PlaySound(dialog.sound)
    end
    return popup
end

function StaticPopupSpecial_Show(dialog)
    dialog.special = true
    if dialog.Show then dialog:Show() end
    return dialog
end

function StaticPopupSpecial_Hide(dialog)
    if not dialog.special then return end
    if dialog.Hide then dialog:Hide() end
end

GuildInviteFrame.scripts.OnHide = function(self)
    if not self.accepted then
        DeclineGuild()
    end
    PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
    StaticPopupSpecial_Hide(self)
end

function hooksecurefunc(target, methodOrHook, maybeHook)
    if type(target) == "table" then
        local methodName = methodOrHook
        local hook = maybeHook
        local original = target[methodName]
        target[methodName] = function(...)
            local results = { original(...) }
            hook(...)
            return unpackCompat(results)
        end
    else
        local name = target
        local hook = methodOrHook
        local original = _G[name]
        _G[name] = function(...)
            local results = { original(...) }
            hook(...)
            return unpackCompat(results)
        end
    end
end

local chatFilters = {}
function ChatFrame_AddMessageEventFilter(event, callback)
    chatFilters[event] = callback
end

local closedChatFrames = {}
function FCF_Close(frame)
    closedChatFrames[#closedChatFrames + 1] = frame
end

local eventFrames = {}
local createdFrames = {}
function CreateFrame(frameType, name, parent, template)
    local frame = { events = {}, scripts = {} }
    function frame:RegisterEvent(event)
        self.events[event] = true
        eventFrames[event] = self
    end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(script, callback) self.scripts[script] = callback end
    createdFrames[#createdFrames + 1] = frame
    return frame
end

SlashCmdList = {}
function geterrorhandler()
    return function(message) error(message, 0) end
end

ERR_INVITED_TO_GROUP_SS = "[%s] vous a invité à rejoindre un groupe."
ERR_INVITED_ALREADY_IN_GROUP_SS = "[%s] vous a invité à rejoindre un groupe, mais vous ne pouviez pas accepter car vous êtes déjà dans un groupe."
ERR_INVITED_TO_GROUP_S = nil
ERR_INVITED_ALREADY_IN_GROUP_S = nil

local ns = {}
local scriptPath = (arg and arg[0]) or "tests/runtime_harness.lua"
local scriptDir = scriptPath:match("^(.*)[/\\][^/\\]+$") or "."
local repoRoot = scriptDir:match("^(.*)[/\\]tests$") or "."

assert(loadfile(repoRoot .. "/Locales.lua"))("Sanctuary", ns)
assert(loadfile(repoRoot .. "/Sanctuary.lua"))("Sanctuary", ns)

local function fire(event, ...)
    local frame = eventFrames[event]
    check(frame ~= nil, "event registered: " .. event)
    if not frame then return end
    frame.scripts.OnEvent(frame, event, ...)
end

local function showGuildInviteFrame(inviter, guildName)
    GuildInviteFrame.inviter = inviter
    GuildInviteFrame.guildName = guildName
    GuildInviteFrame.accepted = nil
    GuildInviteFrame.elapsed = 0
    return StaticPopupSpecial_Show(GuildInviteFrame)
end

local function hideGuildInviteFrameForCleanup()
    GuildInviteFrame.accepted = true
    GuildInviteFrame:Hide()
    GuildInviteFrame.accepted = nil
end

-- Initialize SavedVariables and filters.
fire("ADDON_LOADED", "Sanctuary")
fire("PLAYER_ENTERING_WORLD")
equal(ns.VERSION, "0.3.2", "version exported")
equal(#muted, 0, "no global sound files muted at rest")
equal(StaticPopupDialogs.PARTY_INVITE.sound, nil, "party invite dialog sound suppressed while group filter active")
equal(StaticPopupDialogs.DUEL_REQUESTED.sound, nil, "duel dialog sound suppressed while duel filter active")
equal(ns.getPartyInviteOriginalSound(), 880, "original party invite sound captured")
check(ns.areInviteSoundsMuted(), "invite notification sound guard active at startup")
check(chatFilters.CHAT_MSG_SYSTEM ~= nil, "system filter registered")
check(chatFilters.CHAT_MSG_BN_WHISPER ~= nil, "BNet filter registered")

-- A suspect pattern must override every trust source.
guildMembers = { "Trusted-TestRealm" }
inGuild = true
SanctuaryDB.keywords = { "trust" }
ns.invalidateWhitelist()
local block, reason = ns.getCharacterDecision("Trusted-TestRealm")
check(block, "keyword overrides guild whitelist")
equal(reason, "keyword", "keyword override reason")
SanctuaryDB.keywords = {}
ns.invalidateWhitelist()
block, reason = ns.getCharacterDecision("Trusted-TestRealm")
check(not block, "guild member remains trusted without keyword")

-- Transient IsInGuild=false must not discard an already populated guild roster.
inGuild = false
ns.invalidateWhitelist()
block = ns.getCharacterDecision("Trusted-TestRealm")
check(not block, "populated guild roster trusted during IsInGuild transition")

-- Battle.net whispers are matched by account display name, not character name.
bnetFriends = {
    { accountName = "Battle Friend", gameAccountInfo = { characterName = "Onlinechar" } },
}
ns.invalidateWhitelist()
check(ns.isBNetWhitelisted("Battle Friend"), "BNet account cached")
local filtered = chatFilters.CHAT_MSG_BN_WHISPER(nil, "CHAT_MSG_BN_WHISPER", "hello", "Battle Friend")
check(not filtered, "BNet friend whisper passes")
filtered = chatFilters.CHAT_MSG_BN_WHISPER(nil, "CHAT_MSG_BN_WHISPER", "hello", "Battle Friend")
check(not filtered, "BNet friend whisper remains allowed by cached account name")
filtered = chatFilters.CHAT_MSG_BN_WHISPER(nil, "CHAT_MSG_BN_WHISPER", "hello", "Unknown Battle")
check(filtered, "unknown BNet whisper blocked")

-- Core chat filters: unknown players are blocked only when the relevant filter
-- says so, while suspicious keywords always win and self messages always pass.
filtered = chatFilters.CHAT_MSG_WHISPER(nil, "CHAT_MSG_WHISPER", "hello", "Unknown")
check(filtered, "unknown whisper blocked")
filtered = chatFilters.CHAT_MSG_WHISPER(nil, "CHAT_MSG_WHISPER", "hello", "Trusted-TestRealm")
check(not filtered, "trusted whisper passes")

SanctuaryDB.filters.say = false
filtered = chatFilters.CHAT_MSG_SAY(nil, "CHAT_MSG_SAY", "hello", "Unknown")
check(not filtered, "say filter off lets unknown sender pass")
SanctuaryDB.filters.say = true
filtered = chatFilters.CHAT_MSG_SAY(nil, "CHAT_MSG_SAY", "hello", "Unknown")
check(filtered, "say filter on blocks unknown sender")
filtered = chatFilters.CHAT_MSG_SAY(nil, "CHAT_MSG_SAY", "hello", "Victim-TestRealm")
check(not filtered, "own say message passes")
SanctuaryDB.filters.say = false

SanctuaryDB.filters.channelMode = "none"
filtered = chatFilters.CHAT_MSG_CHANNEL(nil, "CHAT_MSG_CHANNEL", "hello", "Unknown")
check(not filtered, "channel none mode passes unknown sender")
SanctuaryDB.keywords = { "evil" }
SanctuaryDB.filters.channelMode = "keywords"
filtered = chatFilters.CHAT_MSG_CHANNEL(nil, "CHAT_MSG_CHANNEL", "hello", "Veryevil")
check(filtered, "channel keyword mode blocks suspicious sender")
SanctuaryDB.keywords = {}
SanctuaryDB.filters.channelMode = "all"
filtered = chatFilters.CHAT_MSG_CHANNEL(nil, "CHAT_MSG_CHANNEL", "hello", "Unknown")
check(filtered, "channel all mode blocks unknown sender")
SanctuaryDB.filters.channelMode = "none"

-- System messages for invitations rejected because the player is already in a
-- group are suppressed and logged even though PARTY_INVITE_REQUEST never fires.
inGroup = true
groupMembers = { "Dungeonmate-TestRealm" }
local systemMessage = "[Harasser-TestRealm] vous a invité à rejoindre un groupe, mais vous ne pouviez pas accepter car vous êtes déjà dans un groupe."
filtered = chatFilters.CHAT_MSG_SYSTEM(nil, "CHAT_MSG_SYSTEM", systemMessage)
check(filtered, "already-in-group invite system message suppressed")
local beforeLogs = #SanctuaryDB.log
fire("CHAT_MSG_SYSTEM", systemMessage)
equal(#SanctuaryDB.log, beforeLogs + 1, "already-in-group invite logged")
equal(SanctuaryDB.log[#SanctuaryDB.log].type, "groupInvite", "system invite log type")

-- The pure chat filter must not duplicate debug/log side effects when WoW calls
-- it once per destination chat frame.
SanctuaryDB.debugEnabled = true
SanctuaryDB.debugLog = {}
ns.captureDebugSnapshot()
equal(#SanctuaryDB.debugLog, 1, "debug snapshot captured")
equal(SanctuaryDB.debugLog[1].cat, "SNAPSHOT", "debug snapshot category")
equal(SanctuaryDB.debugLog[1].data.version, "0.3.2", "debug snapshot version")
check(SanctuaryDB.debugLog[1].data.groupInviteFilter, "debug snapshot reports group invite filter")
check(SanctuaryDB.debugLog[1].data.partyInviteSoundGuardActive, "debug snapshot reports active invite sound guard")
equal(SanctuaryDB.debugLog[1].data.filters.whisper, true, "debug snapshot reports whisper filter")
equal(SanctuaryDB.debugLog[1].data.filters.channelMode, "none", "debug snapshot reports channel mode")
local beforeDebug = #SanctuaryDB.debugLog
chatFilters.CHAT_MSG_SYSTEM(nil, "CHAT_MSG_SYSTEM", systemMessage)
chatFilters.CHAT_MSG_SYSTEM(nil, "CHAT_MSG_SYSTEM", systemMessage)
equal(#SanctuaryDB.debugLog, beforeDebug, "system filter has no side effects")

local beforeOutputDebug = #SanctuaryDB.debugLog
ChatFrame1:AddMessage(systemMessage)
equal(#SanctuaryDB.debugLog, beforeOutputDebug + 1, "chat output diagnostic logs visible invite text")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].cat, "CHAT_OUTPUT", "chat output diagnostic category")
ns.hookChatOutputDiagnostics()
ChatFrame1:AddMessage(systemMessage)
equal(#SanctuaryDB.debugLog, beforeOutputDebug + 2, "chat output diagnostic hook is not duplicated")

local beforeChatDecisionDebug = #SanctuaryDB.debugLog
fire("CHAT_MSG_WHISPER", "secret", "Unknown")
equal(#SanctuaryDB.debugLog, beforeChatDecisionDebug + 1, "blocked whisper debug decision logged")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].cat, "CHAT_DECISION", "chat decision category")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.kind, "whisper", "whisper decision kind")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.action, "BLOCK_NOT_WHITELISTED", "whisper decision action")

beforeChatDecisionDebug = #SanctuaryDB.debugLog
fire("CHAT_MSG_BN_WHISPER", "hello", "Battle Friend")
equal(#SanctuaryDB.debugLog, beforeChatDecisionDebug + 1, "allowed BNet whisper debug decision logged")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.kind, "bn_whisper", "BNet decision kind")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.action, "ALLOW", "BNet decision action")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.reason, "bnet_whitelist", "BNet decision reason")
check(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.bnetWhitelisted, "BNet decision reports cache hit")
check(tonumber(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.bnetCache) >= 1, "BNet decision reports cache size")

SanctuaryDB.filters.channelMode = "all"
beforeChatDecisionDebug = #SanctuaryDB.debugLog
fire("CHAT_MSG_CHANNEL", "hello", "Unknown")
equal(#SanctuaryDB.debugLog, beforeChatDecisionDebug + 1, "blocked channel debug decision logged")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.kind, "channel", "channel decision kind")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.action, "BLOCK_NOT_WHITELISTED", "channel decision action")
SanctuaryDB.filters.channelMode = "none"

SanctuaryDB.filters.say = true
filtered = chatFilters.CHAT_MSG_SAY(nil, "CHAT_MSG_SAY", "hello", "Victim-OtherRealm")
check(filtered, "same-name sender from another realm is not treated as self")
SanctuaryDB.filters.say = false

SanctuaryDB.filters.yell = true
check(chatFilters.CHAT_MSG_YELL(nil, "CHAT_MSG_YELL", "hello", "Unknown"), "yell filter blocks unknown")
SanctuaryDB.filters.yell = false

SanctuaryDB.filters.emote = true
check(chatFilters.CHAT_MSG_TEXT_EMOTE(nil, "CHAT_MSG_TEXT_EMOTE", "waves", "Unknown"), "text emote filter blocks unknown")
SanctuaryDB.filters.emote = false

SanctuaryDB.debugLog = {}
bnetFriends = { { accountName = "Diag", gameAccountInfo = { characterName = "Diagchar" } } }
fire("BN_FRIEND_INFO_CHANGED")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].cat, "SOCIAL", "BNet social debug logged")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.bnetCN, 1, "BNet character count logged")
bnetFriends = { { accountName = "Battle Friend", gameAccountInfo = { characterName = "Onlinechar" } } }
ns.invalidateWhitelist()

fire("CHAT_MSG_SYSTEM", "invitation group text that does not match localized patterns")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.result, "NO_MATCH", "unmatched invite-like system message diagnosed")

SanctuaryDB.notifications.mode = "minimal"
SanctuaryDB.notifications.minimalIntervalMinutes = 1
SanctuaryCharDB.sessionStats.blockedCount = 2
local beforeMinimalMessages = #chatMessages
runTickers()
equal(#chatMessages, beforeMinimalMessages + 1, "minimal notification printed once")
runTickers()
equal(#chatMessages, beforeMinimalMessages + 1, "minimal notification throttled")
SanctuaryDB.notifications.mode = "silent"

SanctuaryDB.debugLog = {}
for i = 1, 505 do
    ns.debugLog("ROTATE", { i = i })
end
equal(#SanctuaryDB.debugLog, 500, "debug log rotates to 500 entries")
equal(SanctuaryDB.debugLog[1].data.i, 6, "debug log keeps newest entries after rotation")

-- Popup helpers must handle multiple simultaneous StaticPopup frames and
-- restore their original alpha values.
StaticPopup1.shown, StaticPopup1.which, StaticPopup1.alpha = true, "PARTY_INVITE", 0.4
StaticPopup2.shown, StaticPopup2.which, StaticPopup2.alpha = true, "PARTY_INVITE", 0.8
equal(ns.maskVisiblePopup("PARTY_INVITE"), 2, "all visible party popups masked")
equal(StaticPopup1.alpha, 0, "first popup masked")
equal(StaticPopup2.alpha, 0, "second popup masked")
equal(ns.unmaskVisiblePopup("PARTY_INVITE"), 2, "all party popups restored")
equal(StaticPopup1.alpha, 0.4, "first popup alpha restored")
equal(StaticPopup2.alpha, 0.8, "second popup alpha restored")
StaticPopup1:Hide()
StaticPopup2:Hide()

-- Non-target StaticPopup paths such as QUIT/CAMP must stay native. Sanctuary's
-- sound/popup guards only target invite and duel dialogs.
playedSounds = {}
StaticPopup_Show("QUIT")
equal(popup.alpha, 1, "non-target static popup not masked")
equal(#playedSounds, 1, "non-target static popup keeps native open sound")
equal(playedSounds[1], SOUNDKIT.IG_MAINMENU_OPEN, "non-target static popup open sound is not muted")
popup:Hide()
equal(playedSounds[2], SOUNDKIT.IG_MAINMENU_CLOSE, "non-target static popup close sound is not muted")
runTimers()

-- Blizzard-first blocked popup: hook masks before render, event declines, and no
-- direct StaticPopup_Hide is used.
inGroup = false
groupMembers = {}
popup:Hide()
playedSounds = {}
SanctuaryDB.debugLog = {}
local beforeBlockedDeclines = declinedGroups
StaticPopup_Show("PARTY_INVITE", "Harasser vous invite dans un groupe.")
equal(popup.alpha, 0, "unknown party popup masked immediately")
equal(#playedSounds, 0, "unknown party popup native sounds suppressed before decision")
check(ns.areInviteSoundsMuted(), "blocked party invite uses active native sound mute")
fire("PARTY_INVITE_REQUEST", "Harasser", false, false, true, true, false, "Player-1")
equal(popup.alpha, 0, "blocked popup remains masked")
equal(declinedGroups, beforeBlockedDeclines + 1, "blocked group invite declined by Sanctuary handler")
local popupDecision = lastDebug("POPUP_DECISION")
check(popupDecision ~= nil, "blocked party invite logs popup decision")
equal(popupDecision.data.order, "popup_first", "blocked party invite reports popup-first ordering")
equal(popupDecision.data.affected, 1, "blocked party invite reports affected popup count")
local inviteApi = lastDebug("INVITE_API")
check(inviteApi ~= nil, "blocked party invite logs native decline API")
check(inviteApi.data.ok, "blocked party invite native decline API succeeded")
equal(forbiddenStaticHides, 0, "no direct StaticPopup_Hide")
runTimers()
equal(declinedGroups, beforeBlockedDeclines + 1, "blocked group invite silent hide does not decline twice")
check(not popup:IsShown(), "blocked party invite popup hidden after native decline")
equal(#playedSounds, 0, "blocked party invite close sound suppressed")
equal(popup.alpha, 1, "popup alpha restored on silent hide")
check(not mutedSoundFiles[567490], "blocked party invite releases popup-open mute after hide")
check(not mutedSoundFiles[567464], "blocked party invite releases popup-close mute after hide")

-- Blizzard-first trusted popup: it is initially masked and restored in the same
-- event dispatch once the name-based decision is available.
SanctuaryDB.manualWhitelist.friend = { displayName = "Friend" }
ns.invalidateWhitelist()
playedSounds = {}
SanctuaryDB.debugLog = {}
local beforeTrustedDeclines = declinedGroups
StaticPopup_Show("PARTY_INVITE", "Friend vous invite dans un groupe.")
equal(popup.alpha, 0, "trusted popup guarded before event decision")
equal(#playedSounds, 0, "trusted party popup native sounds suppressed before decision")
fire("PARTY_INVITE_REQUEST", "Friend", false, false, true, true, false, "Player-2")
equal(popup.alpha, 1, "trusted popup restored")
equal(declinedGroups, beforeTrustedDeclines, "trusted invite not declined by Sanctuary handler")
equal(#playedSounds, 2, "trusted party invite replays native popup sounds after allow")
equal(playedSounds[1], SOUNDKIT.IG_MAINMENU_OPEN, "trusted party invite replays native popup-open sound first")
equal(playedSounds[2], 880, "trusted party invite replays native Blizzard invite sound second")
local allowedSound = lastDebug("SOUND", "PLAY_ALLOWED_POPUP")
check(allowedSound ~= nil, "trusted popup-first invite logs native sound replay")
equal(allowedSound.data.popupSound, "880", "trusted popup-first invite logs captured native sound")
check(ns.areInviteSoundsMuted(), "trusted party invite restores dialog sound suppression after replay")
check(not mutedSoundFiles[567490], "trusted party invite releases popup-open mute after allow")
check(not mutedSoundFiles[567464], "trusted party invite releases popup-close mute after allow")
popup:Hide()
runTimers()

-- Sanctuary-first ordering: the pending decision is consumed by the later
-- StaticPopup_Show post-hook, avoiding both flash and false blocking.
playedSounds = {}
SanctuaryDB.debugLog = {}
fire("PARTY_INVITE_REQUEST", "Friend", false, false, true, true, false, "Player-3")
popupDecision = lastDebug("POPUP_DECISION")
check(popupDecision ~= nil, "trusted Sanctuary-first invite logs popup decision")
equal(popupDecision.data.order, "event_first", "trusted Sanctuary-first invite reports event-first ordering")
equal(#playedSounds, 0, "Sanctuary-first trusted invite does not synthesize sound before popup")
StaticPopup_Show("PARTY_INVITE", "Friend vous invite dans un groupe.")
equal(popup.alpha, 1, "trusted decision survives Sanctuary-first ordering")
equal(#playedSounds, 2, "Sanctuary-first trusted invite uses native popup sounds")
equal(playedSounds[1], SOUNDKIT.IG_MAINMENU_OPEN, "Sanctuary-first trusted invite native open sound plays")
equal(playedSounds[2], 880, "Sanctuary-first trusted invite native invite sound plays")
popup:Hide()
runTimers()

playedSounds = {}
local beforeSanctuaryFirstBlockedDeclines = declinedGroups
fire("PARTY_INVITE_REQUEST", "Anotherbad", false, false, true, true, false, "Player-4")
StaticPopup_Show("PARTY_INVITE", "Anotherbad vous invite dans un groupe.")
equal(popup.alpha, 0, "blocked decision survives Sanctuary-first ordering")
equal(declinedGroups, beforeSanctuaryFirstBlockedDeclines + 1, "Sanctuary-first blocked invite declined by handler")
runTimers()
check(not popup:IsShown(), "Sanctuary-first blocked invite popup hidden after pending block decision")
equal(declinedGroups, beforeSanctuaryFirstBlockedDeclines + 1, "Sanctuary-first silent hide does not decline twice")
equal(#playedSounds, 0, "Sanctuary-first blocked invite never plays popup sounds")

-- Duel uses a StaticPopup; guild invites use Retail's GuildInviteFrame special
-- popup. Both paths must stay silent for blocked senders.
playedSounds = {}
SanctuaryDB.debugLog = {}
local beforeBlockedDuels = cancelledDuels
StaticPopup_Show("DUEL_REQUESTED", "Duelbad veut vous provoquer en duel.")
equal(popup.alpha, 0, "unknown duel popup masked immediately")
equal(#playedSounds, 0, "blocked duel popup native sounds suppressed before decision")
fire("DUEL_REQUESTED", "Duelbad")
equal(cancelledDuels, beforeBlockedDuels + 1, "blocked duel cancelled")
local duelApi = lastDebug("DUEL_API")
check(duelApi ~= nil, "blocked duel logs native cancel API")
check(duelApi.data.ok, "blocked duel native cancel API succeeded")
runTimers()
check(not popup:IsShown(), "blocked duel popup hidden after native cancel")
equal(cancelledDuels, beforeBlockedDuels + 1, "blocked duel silent hide does not cancel twice")
equal(#playedSounds, 0, "blocked duel popup close sound suppressed")
check(not mutedSoundFiles[567490], "blocked duel releases popup-open mute after hide")
check(not mutedSoundFiles[567464], "blocked duel releases popup-close mute after hide")

playedSounds = {}
SanctuaryDB.debugLog = {}
fire("GUILD_INVITE_REQUEST", "Guildbad", "Bad Guild")
popupDecision = lastDebug("POPUP_DECISION")
check(popupDecision ~= nil, "event-first blocked guild invite logs popup decision")
equal(popupDecision.data.which, "GUILD_INVITE_FRAME", "event-first blocked guild invite uses special frame key")
equal(popupDecision.data.order, "event_first", "event-first blocked guild invite reports event-first ordering")
showGuildInviteFrame("Guildbad", "Bad Guild")
equal(GuildInviteFrame:IsShown(), false, "event-first blocked guild invite frame hidden")
equal(#playedSounds, 0, "event-first blocked guild invite stays silent")
equal(declinedGuilds, 1, "blocked guild invite declined")
local guildApi = lastDebug("GUILD_INVITE_API")
check(guildApi ~= nil, "blocked guild invite logs native decline API")
check(guildApi.data.ok, "blocked guild invite native decline API succeeded")
local guildFrameLog = lastDebug("GUILD_INVITE_FRAME")
check(guildFrameLog ~= nil, "event-first blocked guild invite logs frame handling")
equal(guildFrameLog.data.action, "HIDE_DECIDED_BLOCK", "event-first blocked guild invite hides decided frame")
equal(#playedSounds, 0, "event-first blocked guild invite close sound suppressed")
runTimers()

playedSounds = {}
SanctuaryDB.debugLog = {}
showGuildInviteFrame("GuildbadFrame", "Bad Guild")
equal(GuildInviteFrame:IsShown(), true, "frame-first blocked guild invite waits for event")
equal(GuildInviteFrame.alpha, 0, "frame-first blocked guild invite frame masked immediately")
equal(#playedSounds, 0, "frame-first blocked guild invite has no open sound leak")
fire("GUILD_INVITE_REQUEST", "GuildbadFrame", "Bad Guild")
equal(GuildInviteFrame:IsShown(), false, "frame-first blocked guild invite frame hidden after decision")
equal(#playedSounds, 0, "frame-first blocked guild invite close sound suppressed")
equal(declinedGuilds, 2, "frame-first blocked guild invite declined exactly once")
popupDecision = lastDebug("POPUP_DECISION")
check(popupDecision ~= nil, "frame-first blocked guild invite logs popup decision")
equal(popupDecision.data.order, "popup_first", "frame-first blocked guild invite reports popup-first ordering")
equal(popupDecision.data.affected, 1, "frame-first blocked guild invite reports affected frame")
guildApi = lastDebug("GUILD_INVITE_API")
check(guildApi ~= nil, "frame-first blocked guild invite logs native decline API")
check(guildApi.data.ok, "frame-first blocked guild invite native decline API succeeded")
runTimers()

SanctuaryDB.manualWhitelist.duelfriend = { displayName = "DuelFriend" }
SanctuaryDB.manualWhitelist.guildfriend = { displayName = "GuildFriend" }
ns.invalidateWhitelist()

local beforeDuels = cancelledDuels
playedSounds = {}
StaticPopup_Show("DUEL_REQUESTED", "DuelFriend veut vous provoquer en duel.")
equal(#playedSounds, 0, "trusted duel popup sound guarded before decision")
fire("DUEL_REQUESTED", "DuelFriend")
equal(popup.alpha, 1, "trusted duel popup restored")
equal(cancelledDuels, beforeDuels, "trusted duel not cancelled")
equal(#playedSounds, 2, "trusted duel popup native sounds replayed after allow")
equal(playedSounds[1], SOUNDKIT.IG_MAINMENU_OPEN, "trusted duel replays native popup-open sound first")
equal(playedSounds[2], 880, "trusted duel replays native invite sound second")
popup:Hide()
runTimers()

local beforeGuilds = declinedGuilds
playedSounds = {}
SanctuaryDB.debugLog = {}
showGuildInviteFrame("GuildFriend", "Friendly Guild")
equal(GuildInviteFrame.alpha, 0, "trusted guild frame guarded before event decision")
equal(#playedSounds, 0, "trusted guild frame has no synthetic open sound")
fire("GUILD_INVITE_REQUEST", "GuildFriend", "Friendly Guild")
equal(GuildInviteFrame:IsShown(), true, "trusted guild invite frame stays visible")
equal(GuildInviteFrame.alpha, 1, "trusted guild invite frame restored")
equal(declinedGuilds, beforeGuilds, "trusted guild invite not declined")
equal(#playedSounds, 0, "trusted guild invite does not receive an invented replay sound")
popupDecision = lastDebug("POPUP_DECISION")
check(popupDecision ~= nil, "trusted frame-first guild invite logs popup decision")
equal(popupDecision.data.order, "popup_first", "trusted frame-first guild invite reports popup-first ordering")
hideGuildInviteFrameForCleanup()
runTimers()

beforeGuilds = declinedGuilds
playedSounds = {}
SanctuaryDB.debugLog = {}
fire("GUILD_INVITE_REQUEST", "GuildFriend", "Friendly Guild")
popupDecision = lastDebug("POPUP_DECISION")
check(popupDecision ~= nil, "trusted event-first guild invite logs popup decision")
equal(popupDecision.data.order, "event_first", "trusted event-first guild invite reports event-first ordering")
showGuildInviteFrame("GuildFriend", "Friendly Guild")
equal(GuildInviteFrame:IsShown(), true, "trusted event-first guild invite frame shown")
equal(GuildInviteFrame.alpha, 1, "trusted event-first guild invite frame keeps alpha")
equal(declinedGuilds, beforeGuilds, "trusted event-first guild invite not declined")
equal(#playedSounds, 0, "trusted event-first guild invite has no synthetic open sound")
hideGuildInviteFrameForCleanup()
runTimers()

SanctuaryDB.filters.duel = false
StaticPopup_Show("DUEL_REQUESTED", "Duelbad2 veut vous provoquer en duel.")
equal(popup.alpha, 1, "duel popup unprotected when duel filter disabled")
fire("DUEL_REQUESTED", "Duelbad2")
equal(cancelledDuels, 1, "disabled duel filter does not cancel")
popup:Hide()
runTimers()
SanctuaryDB.filters.duel = true

SanctuaryDB.filters.guildInvite = false
local beforeDisabledGuilds = declinedGuilds
playedSounds = {}
showGuildInviteFrame("Guildbad2", "Bad Guild")
equal(GuildInviteFrame:IsShown(), true, "guild frame stays native when guild filter disabled")
equal(GuildInviteFrame.alpha, 1, "guild frame unprotected when guild filter disabled")
fire("GUILD_INVITE_REQUEST", "Guildbad2", "Bad Guild")
equal(declinedGuilds, beforeDisabledGuilds, "disabled guild filter does not decline")
hideGuildInviteFrameForCleanup()
runTimers()
SanctuaryDB.filters.guildInvite = true

-- Trade detection uses the available NPC/unit label and logs hyphenated realms
-- without allocating a replacement log table during rotation.
SanctuaryDB.logging.maxEntries = 2
SanctuaryDB.log = {}
now = now + 2
ns.logBlock("whisper", "First-Realm-One", "one")
now = now + 2
ns.logBlock("whisper", "Second-Realm-Two", "two")
now = now + 2
ns.logBlock("whisper", "Third-Realm-With-Hyphen", "three")
equal(#SanctuaryDB.log, 2, "block log rotates to configured max entries")
equal(SanctuaryDB.log[1].name, "Second", "log rotation keeps second newest name")
equal(SanctuaryDB.log[1].realm, "Realm-Two", "realm with hyphen parsed after first separator")
equal(SanctuaryDB.log[2].realm, "Realm-With-Hyphen", "multi-hyphen realm preserved")
SanctuaryDB.logging.maxEntries = 5000
SanctuaryDB.log = {}

npcName = "Traderbad-TestRealm"
SanctuaryDB.debugLog = {}
now = now + 2
fire("TRADE_SHOW")
equal(closedTrades, 1, "blocked trade closed")
equal(SanctuaryDB.log[#SanctuaryDB.log].type, "trade", "blocked trade logged")
local tradeApi = lastDebug("TRADE_API")
check(tradeApi ~= nil, "blocked trade logs native close API")
check(tradeApi.data.ok, "blocked trade native close API succeeded")
npcName = nil

SanctuaryDB.manualWhitelist.traderfriend = { displayName = "TraderFriend" }
ns.invalidateWhitelist()
SanctuaryDB.debugLog = {}
npcName = "TraderFriend-TestRealm"
local beforeClosedTrades = closedTrades
local beforeTradeLogs = #SanctuaryDB.log
now = now + 2
fire("TRADE_SHOW")
equal(closedTrades, beforeClosedTrades, "trusted trade not closed")
equal(#SanctuaryDB.log, beforeTradeLogs, "trusted trade not block-logged")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].cat, "TRADE", "trusted trade debug logged")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.action, "ALLOW", "trusted trade debug action")
npcName = nil

-- Refreshing sound state suppresses only the specific dialog sound fields at
-- rest. File-level mutes are transient and only used while an unknown popup is
-- being protected.
SanctuaryDB.debugLog = {}
local beforeMutedRefresh = #muted
ns.refreshInviteSoundMuteState()
equal(#muted, beforeMutedRefresh, "refresh does not add global sound mutes at rest")
check(ns.areInviteSoundsMuted(), "sound state reports active invite sound guard")
equal(StaticPopupDialogs.PARTY_INVITE.sound, nil, "party invite sound field suppressed while filter active")
equal(StaticPopupDialogs.DUEL_REQUESTED.sound, nil, "duel sound field suppressed while filter active")
check(not mutedSoundFiles[567451], "native invite sound file is not globally muted at rest")
check(not mutedSoundFiles[567490], "generic popup open sound is not muted")
check(not mutedSoundFiles[567464], "generic popup close sound is not muted")
SanctuaryDB.filters.groupInvite = false
ns.refreshInviteSoundMuteState()
equal(#muted, beforeMutedRefresh, "disabled group filter keeps existing duel sound guard without duplicate mute")
check(ns.areInviteSoundsMuted(), "duel filter keeps native invite sound guarded")
equal(StaticPopupDialogs.PARTY_INVITE.sound, 880, "disabled group filter restores party invite dialog sound")
equal(StaticPopupDialogs.DUEL_REQUESTED.sound, nil, "disabled group filter leaves duel sound suppressed")
check(type(ns.simulateInvite) == "function", "invite simulator exported")
local disabledSimulation = ns.simulateInvite("Simulatedbad")
check(disabledSimulation.shouldBlock, "disabled invite filter still reports raw block decision")
check(not disabledSimulation.filterEnabled, "disabled invite filter reported by simulator")
check(not disabledSimulation.systemSuppressed, "disabled invite filter does not suppress system message")
equal(disabledSimulation.popupAction, "pass", "disabled invite filter does not protect popup")
SanctuaryDB.filters.groupInvite = true
ns.refreshInviteSoundMuteState()
equal(#muted, beforeMutedRefresh, "enabled invite filter keeps existing invite sound guard without duplicate mute")
check(ns.areInviteSoundsMuted(), "enabled invite filter has active invite sound guard")
equal(StaticPopupDialogs.PARTY_INVITE.sound, nil, "re-enabled group filter suppresses party invite dialog sound")

SanctuaryDB.filters.duel = false
ns.refreshInviteSoundMuteState()
check(ns.areInviteSoundsMuted(), "group filter keeps sound guard active when duel filter disabled")
equal(StaticPopupDialogs.DUEL_REQUESTED.sound, 880, "disabled duel filter restores duel dialog sound")
SanctuaryDB.filters.duel = true
ns.refreshInviteSoundMuteState()
equal(StaticPopupDialogs.DUEL_REQUESTED.sound, nil, "re-enabled duel filter suppresses duel dialog sound")

SanctuaryCharDB.overrides.enabled = false
ns.refreshInviteSoundMuteState()
check(not ns.areInviteSoundsMuted(), "disabled addon releases invite sound guard")
check(not mutedSoundFiles[567451], "disabled addon unmutes native invite sound file")
local addonDisabledSimulation = ns.simulateInvite("Simulatedbad")
check(addonDisabledSimulation.shouldBlock, "disabled addon still reports raw block decision")
check(not addonDisabledSimulation.filterEnabled, "disabled addon disables invite filtering")
check(not addonDisabledSimulation.systemSuppressed, "disabled addon does not suppress system message")
filtered = chatFilters.CHAT_MSG_WHISPER(nil, "CHAT_MSG_WHISPER", "hello", "Unknown")
check(not filtered, "disabled addon lets whisper pass")
SanctuaryCharDB.overrides.enabled = nil
ns.refreshInviteSoundMuteState()
check(ns.areInviteSoundsMuted(), "re-enabled addon restores invite sound guard")
check(not mutedSoundFiles[567451], "re-enabled addon keeps native invite file unmuted at rest")

-- The invite simulator must exercise Sanctuary's decision/filtering path without
-- touching server-side WoW APIs or persistent block logs.
local beforeSimulationDeclines = declinedGroups
local beforeSimulationLogs = #SanctuaryDB.log
local simulation = ns.simulateInvite("Simulatedbad")
check(simulation.shouldBlock, "blocked invite simulation decision")
equal(simulation.reason, "not_whitelisted", "blocked invite simulation reason")
check(simulation.systemSuppressed, "normal invite system message simulated as suppressed")
check(simulation.alreadyGroupSuppressed, "already-group invite system message simulated as suppressed")
equal(simulation.popupAction, "mask", "blocked invite popup simulation action")
equal(declinedGroups, beforeSimulationDeclines, "invite simulation does not decline groups")
equal(#SanctuaryDB.log, beforeSimulationLogs, "invite simulation does not append block logs")

simulation = ns.simulateInvite("Friend")
check(not simulation.shouldBlock, "trusted invite simulation decision")
equal(simulation.reason, "whitelist", "trusted invite simulation reason")
check(not simulation.systemSuppressed, "trusted invite system message simulated as visible")
equal(simulation.popupAction, "show", "trusted invite popup simulation action")

local bnetSimulation = ns.simulateBNetWhisper("Battle Friend")
check(not bnetSimulation.filtered, "BNet friend simulation allowed")
equal(bnetSimulation.reason, "bnet_whitelist", "BNet friend simulation reason")
check(bnetSimulation.bnetWhitelisted, "BNet friend simulation reports cache hit")

SanctuaryDB.debugLog = {}
inGroup = true
groupMembers = { "Onlinechar-TestRealm" }
bnetSimulation = ns.simulateBNetWhisper("Battle Friend")
local bnetGroupLog = lastDebug("BNET_GROUP")
check(bnetGroupLog ~= nil, "BNet group diagnostic logged when account has grouped character")
check(bnetGroupLog.data.accountMatched, "BNet group diagnostic reports account match")
check(bnetGroupLog.data.result, "BNet group diagnostic reports grouped character match")
equal(bnetGroupLog.data.character, "onlinechar", "BNet group diagnostic reports normalized character")
inGroup = false
groupMembers = {}

bnetSimulation = ns.simulateBNetWhisper("Unknown Battle")
check(bnetSimulation.filtered, "unknown BNet simulation blocked")
equal(bnetSimulation.reason, "not_whitelisted", "unknown BNet simulation reason")

bnetSimulation = ns.simulateBNetFriend("1")
check(bnetSimulation.available, "BNet friend-index simulation uses live accountName")
check(not bnetSimulation.filtered, "BNet friend-index simulation allowed")
equal(bnetSimulation.label, "friend #1", "BNet friend-index simulation hides account label")

local originalBNetInfo = C_BattleNet.GetFriendAccountInfo
C_BattleNet.GetFriendAccountInfo = nil
ns.invalidateWhitelist()
bnetSimulation = ns.simulateBNetFriend("1")
check(not bnetSimulation.available, "BNet friend-index simulation reports unavailable API")
equal(bnetSimulation.reason, "bnet_api_unavailable", "BNet unavailable simulation reason")
C_BattleNet.GetFriendAccountInfo = originalBNetInfo
ns.invalidateWhitelist()

ChatFrame3 = { chatType = "BN_WHISPER", chatTarget = "Blocked Battle" }
ChatFrame4 = { chatType = "BN_WHISPER", chatTarget = "Other Battle" }
local beforeClosedBNetTabs = #closedChatFrames
SanctuaryDB.debugLog = {}
fire("CHAT_MSG_BN_WHISPER", "bad", "Blocked Battle")
runTimers()
equal(#closedChatFrames, beforeClosedBNetTabs + 1, "only one BNet whisper tab closed")
equal(closedChatFrames[#closedChatFrames], ChatFrame3, "blocked BNet tab closed exactly")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].cat, "WHISPER_TAB", "BNet tab close debug logged")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.chatType, "BN_WHISPER", "BNet tab close debug type")

local beforeSlashMessages = #chatMessages
SlashCmdList["SANCTUARY"]("simulate Simulatedbad")
check(#chatMessages == beforeSlashMessages + 1, "slash simulation prints one diagnostic line")
check(chatMessages[#chatMessages]:find("Simulation invite", 1, true) ~= nil, "slash simulation output label")
equal(declinedGroups, beforeSimulationDeclines, "slash simulation does not decline groups")

beforeSlashMessages = #chatMessages
SlashCmdList["SANCTUARY"]("simulate bnetfriend 1")
check(#chatMessages == beforeSlashMessages + 1, "slash BNet simulation prints one diagnostic line")
check(chatMessages[#chatMessages]:find("Simulation bnet whisper", 1, true) ~= nil, "slash BNet simulation output label")

beforeSlashMessages = #chatMessages
playedSounds = {}
SanctuaryDB.debugLog = {}
SlashCmdList["SANCTUARY"]("diag sound invite")
check(#chatMessages == beforeSlashMessages + 1, "slash sound diagnostic prints one diagnostic line")
check(chatMessages[#chatMessages]:find("Diagnostic sound invite", 1, true) ~= nil, "slash sound diagnostic output label")
equal(#playedSounds, 2, "slash sound diagnostic plays popup-open plus native invite")
equal(playedSounds[1], SOUNDKIT.IG_MAINMENU_OPEN, "slash sound diagnostic plays native popup-open")
equal(playedSounds[2], 880, "slash sound diagnostic plays native party invite")
local soundTestLog = lastDebug("SOUND_TEST")
check(soundTestLog ~= nil, "slash sound diagnostic logs diagnostic")
equal(soundTestLog.data.inviteSound, "880", "slash sound diagnostic logs native party invite sound")

beforeSlashMessages = #chatMessages
playedSounds = {}
SanctuaryDB.debugLog = {}
SlashCmdList["SANCTUARY"]("diag popup duel")
runTimers()
check(#chatMessages == beforeSlashMessages + 1, "slash duel popup diagnostic prints one diagnostic line")
check(chatMessages[#chatMessages]:find("Diagnostic popup duel", 1, true) ~= nil, "slash duel popup diagnostic output label")
equal(#playedSounds, 0, "slash duel popup diagnostic stays silent")
local popupTestLog = lastDebug("POPUP_TEST")
check(popupTestLog ~= nil, "slash duel popup diagnostic logs diagnostic")
equal(popupTestLog.data.which, "DUEL_REQUESTED", "slash duel popup diagnostic logs popup kind")
check(popupTestLog.data.hidden, "slash duel popup diagnostic hides diagnostic popup")

beforeSlashMessages = #chatMessages
playedSounds = {}
SanctuaryDB.debugLog = {}
local beforeDiagGuilds = declinedGuilds
SlashCmdList["SANCTUARY"]("diag popup guild")
runTimers()
check(#chatMessages == beforeSlashMessages + 1, "slash guild popup diagnostic prints one diagnostic line")
check(chatMessages[#chatMessages]:find("Diagnostic popup guild", 1, true) ~= nil, "slash guild popup diagnostic output label")
equal(#playedSounds, 0, "slash guild popup diagnostic stays silent")
popupTestLog = lastDebug("POPUP_TEST")
check(popupTestLog ~= nil, "slash guild popup diagnostic logs diagnostic")
equal(popupTestLog.data.which, "GUILD_INVITE_FRAME", "slash guild popup diagnostic logs frame key")
equal(popupTestLog.data.frame, "GuildInviteFrame", "slash guild popup diagnostic logs frame kind")
equal(popupTestLog.data.reason, "guild_invite_frame_probe", "slash guild popup diagnostic probes special frame")
check(popupTestLog.data.masked, "slash guild popup diagnostic masks special frame")
check(popupTestLog.data.hidden, "slash guild popup diagnostic hides special frame")
equal(declinedGuilds, beforeDiagGuilds, "slash guild popup diagnostic does not call native decline")

beforeSlashMessages = #chatMessages
SanctuaryDB.debugLog = {}
SlashCmdList["SANCTUARY"]("diag popup list guild")
check(#chatMessages == beforeSlashMessages + 1, "slash popup list diagnostic prints one line")
check(chatMessages[#chatMessages]:find("Diagnostic popup list guild", 1, true) ~= nil, "slash popup list diagnostic output label")
local popupListLog = lastDebug("POPUP_LIST")
check(popupListLog ~= nil, "slash popup list diagnostic logs result")
equal(popupListLog.data.query, "guild", "slash popup list diagnostic logs query")

showGuildInviteFrame("BusyGuild", "Busy Guild")
local busyGuildDiagnostic = ns.runPopupDiagnostic("guild")
check(busyGuildDiagnostic.skipped, "guild popup diagnostic skips an already visible frame")
equal(busyGuildDiagnostic.reason, "guild_invite_frame_busy", "guild popup diagnostic reports busy frame")
check(GuildInviteFrame:IsShown(), "guild popup diagnostic does not hide a busy frame")
hideGuildInviteFrameForCleanup()
runTimers()

local uiToggles = 0
ns.ToggleUI = function() uiToggles = uiToggles + 1 end
SlashCmdList["SANCTUARY"]("")
SlashCmdList["SANCTUARY"]("unknown")
equal(uiToggles, 2, "non-simulation slash commands still open the UI")
ns.ToggleUI = nil

-- Auto-trust tracking must survive a dungeon loading screen.
SanctuaryDB.filters.autoTrust = true
inGroup = true
groupMembers = { "Dungeonmate-TestRealm" }
fire("GROUP_ROSTER_UPDATE")
local trackedAt = SanctuaryCharDB.groupTracker.dungeonmate
check(trackedAt ~= nil, "group member tracking started")
now = now + 30
fire("PLAYER_ENTERING_WORLD")
equal(SanctuaryCharDB.groupTracker.dungeonmate, trackedAt, "group tracker survives loading transition")
now = trackedAt + (SanctuaryDB.temporalGroupTrust.trustThresholdMinutes * 60) + 1
runTickers()
check(SanctuaryDB.manualWhitelist.dungeonmate ~= nil, "auto-trust adds member after threshold")
ns.invalidateWhitelist()
block = ns.getCharacterDecision("Dungeonmate-TestRealm")
check(not block, "auto-trusted member passes whitelist decision")

-- Closing a blocked whisper tab must not close unrelated non-whitelisted tabs.
ChatFrame1 = { chatType = "WHISPER", chatTarget = "Blocked" }
ChatFrame2 = { chatType = "WHISPER", chatTarget = "OtherUnknown" }
ChatFrame1Tab = { Text = { GetText = function() return "Blocked" end } }
ChatFrame2Tab = { Text = { GetText = function() return "OtherUnknown" end } }
local beforeClosedWhisperTabs = #closedChatFrames
SanctuaryDB.debugLog = {}
fire("CHAT_MSG_WHISPER", "bad", "Blocked")
runTimers()
equal(#closedChatFrames, beforeClosedWhisperTabs + 1, "only one whisper tab closed")
equal(closedChatFrames[#closedChatFrames], ChatFrame1, "blocked sender tab closed exactly")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].cat, "WHISPER_TAB", "whisper tab close debug logged")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.chatType, "WHISPER", "whisper tab close debug type")

if failures > 0 then
    io.stderr:write(string.format("%d/%d assertions failed\n", failures, assertions))
    os.exit(1)
end

print(string.format("OK: %d assertions", assertions))
