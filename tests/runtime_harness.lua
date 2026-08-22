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

local function makeSecretValue(label)
    return setmetatable({ __secret = true, label = label }, {
        __tostring = function()
            error("secret value must not be stringified")
        end,
    })
end

local function bnetWhisperPayload(bnSenderID)
    return "", "", "|Kq2|k", "", 0, 0, "", 0, 123, "Player-BNet-0", bnSenderID
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
function issecretvalue(value) return type(value) == "table" and value.__secret == true end

-- Variadic like the real API: Blizzard's filter registry calls canaccessvalue
-- with the whole vararg, so the callback is skipped when *any* argument is
-- secret, not only the first one.
function canaccessvalue(...)
    for i = 1, select("#", ...) do
        if issecretvalue((select(i, ...))) then return false end
    end
    return true
end

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
local function runTimers(rounds)
    for _ = 1, rounds or 1 do
        local pending = timers
        timers = {}
        for _, callback in ipairs(pending) do callback() end
        if #timers == 0 then break end
    end
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
local inInstance = false
local currentInstanceType = "none"
local playerDeadOrGhost = false

function IsInGuild() return inGuild end
function GetNumGuildMembers() return #guildMembers end
function GetGuildRosterInfo(index) return guildMembers[index] end
function BNGetNumFriends() return #bnetFriends end
C_BattleNet = {}
function C_BattleNet.GetFriendAccountInfo(index) return bnetFriends[index] end
function C_BattleNet.GetAccountInfoByID(bnSenderID)
    for _, info in ipairs(bnetFriends) do
        if info.bnetAccountID == bnSenderID then
            return info
        end
    end
    return nil
end
C_FriendList = {}
function C_FriendList.GetNumFriends() return #charFriends end
function C_FriendList.GetFriendInfoByIndex(index)
    local name = charFriends[index]
    return name and { name = name } or nil
end
function C_FriendList.ShowFriends() end
C_GuildInfo = { GuildRoster = function() end }
local addonMetadata = {
    Version = "0.3.2",
    ["X-Sanctuary-Build"] = "20260820-8",
    Interface = "120007",
}
C_AddOns = {
    IsAddOnLoaded = function() return false end,
    GetAddOnMetadata = function(addonName, field)
        if addonName ~= "Sanctuary" then return nil end
        return addonMetadata[field]
    end,
}

function IsInGroup() return inGroup end
function IsInRaid() return inRaid end
function IsInInstance() return inInstance, currentInstanceType end
function UnitIsDeadOrGhost(unit) return unit == "player" and playerDeadOrGhost end
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
local chatMessageArgs = {}
DEFAULT_CHAT_FRAME = {
    AddMessage = function(self, message, ...)
        chatMessages[#chatMessages + 1] = message
        chatMessageArgs[#chatMessageArgs + 1] = { n = select("#", ...), ... }
    end,
}
ChatFrame1 = DEFAULT_CHAT_FRAME

-- Retail passes the chat category as the fifth AddMessage argument
-- (text, r, g, b, messageTypeID). ChatTypeInfo.SYSTEM.id identifies system lines.
ChatTypeInfo = {
    SYSTEM = { r = 1, g = 1, b = 0, id = 42 },
    WHISPER = { r = 1, g = 0.5, b = 1, id = 7 },
}

function GetBuildInfo() return "12.0.7", "62119", "Aug 19 2026", 120007 end

C_ChatInfo = { InChatMessagingLockdown = function() return false end }

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
-- Retail can fail an unmute; the guard's own code already pcall-wraps it and
-- counts failures, so the harness has to be able to produce that branch.
local unmuteFailuresLeft = 0
function UnmuteSoundFile(id)
    if unmuteFailuresLeft > 0 then
        unmuteFailuresLeft = unmuteFailuresLeft - 1
        error("unmute refused")
    end
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
    -- Retail order confirmed by the 2026-08-20 GuildInviteFrame probe: hiding
    -- the frame from inside its own OnShow does not dispatch OnHide right away.
    -- The client runs it once the OnShow handlers have unwound, which is why the
    -- generic close sound plays after anything released inside OnShow. The stub
    -- has to model that or the harness cannot see a sound leak.
    function frame:Show()
        self.shown = true
        self.dispatchingOnShow = true
        if self.scripts.OnShow then self.scripts.OnShow(self) end
        self.dispatchingOnShow = false
        if self.pendingOnHide then
            self.pendingOnHide = nil
            if self.scripts.OnHide then self.scripts.OnHide(self) end
        end
    end
    function frame:Hide()
        if not self.shown then return end
        self.shown = false
        if self.dispatchingOnShow then
            self.pendingOnHide = true
            return
        end
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
local chatFilterRegistrations = 0
function ChatFrame_AddMessageEventFilter(event, callback)
    chatFilterRegistrations = chatFilterRegistrations + 1
    chatFilters[event] = callback
end

-- Retail owns the registry through ChatFrameUtil and keeps the historical
-- global as an alias declared by Blizzard_DeprecatedChatInfo. Model both paths
-- so the availability adapter can be exercised.
ChatFrameUtil = {
    AddMessageEventFilter = function(event, callback)
        chatFilterRegistrations = chatFilterRegistrations + 1
        chatFilters[event] = callback
    end,
}

-- Retail contract, confirmed in Blizzard_ChatFrameBase/Shared/ChatFrameFilters.lua:
-- the registry wraps every addon callback and only invokes it when
-- canaccessvalue() accepts the payload. A secret value therefore never reaches
-- an addon filter, so no addon filter can discard it. Returns the discard
-- decision the registry would produce, plus the path it took.
local function dispatchChatFilter(event, ...)
    local callback = chatFilters[event]
    if not callback then return false, "unregistered" end
    if not canaccessvalue(...) then return false, "skipped" end
    return callback(nil, event, ...) and true or false, "called"
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
-- Question 2 answers "I choose" for the whole legacy suite below: those sections
-- exercise one filter at a time, which is exactly what the custom preset means.
-- The recommended preset ignores the stored per-filter values on purpose, and it
-- gets its own section further down.
SanctuaryDB.filters.preset = "custom"
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
    { bnetAccountID = 101, accountName = "Battle Friend", gameAccountInfo = { characterName = "Onlinechar" } },
}
ns.invalidateWhitelist()
check(ns.isBNetWhitelisted("Battle Friend"), "BNet account cached")
local filtered = chatFilters.CHAT_MSG_BN_WHISPER(nil, "CHAT_MSG_BN_WHISPER", "hello", "Battle Friend")
check(not filtered, "BNet friend whisper passes")
filtered = chatFilters.CHAT_MSG_BN_WHISPER(nil, "CHAT_MSG_BN_WHISPER", "hello", "Battle Friend")
check(not filtered, "BNet friend whisper remains allowed by cached account name")
filtered = chatFilters.CHAT_MSG_BN_WHISPER(nil, "CHAT_MSG_BN_WHISPER", "hello", "|Kq2|k", bnetWhisperPayload(101))
check(not filtered, "BNet friend whisper resolves protected sender token through sender ID")
filtered = chatFilters.CHAT_MSG_BN_WHISPER(nil, "CHAT_MSG_BN_WHISPER", "hello", "Unknown Battle")
check(filtered, "unknown BNet whisper blocked")

-- Manual whitelist entries store a character-normalized key, but BNet account
-- display names may contain spaces or be one-word names. UI/legacy manual
-- entries do not carry source metadata, so they must feed the BNet cache too.
bnetFriends = {}
SanctuaryDB.manualWhitelist.manualbnet = { displayName = "Manual Battle" }
ns.invalidateWhitelist()
check(ns.isBNetWhitelisted("Manual Battle"), "manual displayName cached as BNet account")
filtered = chatFilters.CHAT_MSG_BN_WHISPER(nil, "CHAT_MSG_BN_WHISPER", "hello", "Manual Battle")
check(not filtered, "manual BNet displayName whisper passes")
SanctuaryDB.manualWhitelist.manualbnet = nil
SanctuaryDB.manualWhitelist.onewordbnet = { displayName = "Zephos" }
ns.invalidateWhitelist()
check(ns.isBNetWhitelisted("Zephos"), "one-word manual displayName cached as BNet account")
filtered = chatFilters.CHAT_MSG_BN_WHISPER(nil, "CHAT_MSG_BN_WHISPER", "hello", "Zephos")
check(not filtered, "one-word manual BNet displayName whisper passes")
SanctuaryDB.manualWhitelist.onewordbnet = nil
SanctuaryDB.manualWhitelist.autotrustchar = { displayName = "AutoTrustChar", source = "trust" }
ns.invalidateWhitelist()
check(not ns.isBNetWhitelisted("AutoTrustChar"), "auto-trust character whitelist does not become BNet account")
SanctuaryDB.manualWhitelist.autotrustchar = nil
SanctuaryDB.manualWhitelist.legacycharacter = { displayName = "LegacyCharacter", source = "character" }
ns.invalidateWhitelist()
check(ns.isBNetWhitelisted("LegacyCharacter"), "legacy character-source manual entry still feeds BNet cache")
SanctuaryDB.manualWhitelist.legacycharacter = nil
bnetFriends = {
    { bnetAccountID = 101, accountName = "Battle Friend", gameAccountInfo = { characterName = "Onlinechar" } },
}
ns.invalidateWhitelist()

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
inRaid = true
inInstance = true
currentInstanceType = "raid"
groupMembers = { "Dungeonmate-TestRealm" }
local systemMessage = "[Harasser-TestRealm] vous a invité à rejoindre un groupe, mais vous ne pouviez pas accepter car vous êtes déjà dans un groupe."
filtered = chatFilters.CHAT_MSG_SYSTEM(nil, "CHAT_MSG_SYSTEM", systemMessage)
check(filtered, "already-in-group invite system message suppressed")
SanctuaryDB.debugEnabled = true
SanctuaryDB.debugLog = {}
local beforeLogs = #SanctuaryDB.log
fire("CHAT_MSG_SYSTEM", systemMessage)
equal(#SanctuaryDB.log, beforeLogs + 1, "already-in-group invite logged")
equal(SanctuaryDB.log[#SanctuaryDB.log].type, "groupInvite", "system invite log type")
local systemInviteLog = lastDebug("SYSTEM_INVITE")
check(systemInviteLog ~= nil, "already-in-group invite debug logged")
check(systemInviteLog.data.inRaid, "already-in-group invite debug reports raid context")
check(systemInviteLog.data.inInstance, "already-in-group invite debug reports instance context")
equal(systemInviteLog.data.instanceType, "raid", "already-in-group invite debug reports instance type")
check(not systemInviteLog.data.deadOrGhost, "already-in-group invite debug reports living player state")
check(systemInviteLog.data.deadOrGhostKnown, "already-in-group invite debug reports a readable player state")

-- Field-reported scenario: already-in-group invitations kept arriving while the
-- character was dead in raid. Blizzard instantiates no popup on that path, so
-- CHAT_MSG_SYSTEM is the only place the death correlation can be recorded.
playerDeadOrGhost = true
filtered = chatFilters.CHAT_MSG_SYSTEM(nil, "CHAT_MSG_SYSTEM", systemMessage)
check(filtered, "already-in-group invite stays suppressed while dead")
local beforeDeadInviteDebug = #SanctuaryDB.debugLog
fire("CHAT_MSG_SYSTEM", systemMessage)
equal(#SanctuaryDB.debugLog, beforeDeadInviteDebug + 1, "already-in-group invite while dead is diagnosed once")
systemInviteLog = lastDebug("SYSTEM_INVITE")
equal(systemInviteLog.data.result, "SUPPRESS_NOT_WHITELISTED", "already-in-group invite while dead keeps its decision")
check(systemInviteLog.data.deadOrGhost, "already-in-group invite debug reports dead or ghost state")
check(systemInviteLog.data.deadOrGhostKnown, "already-in-group invite while dead reports a readable player state")
check(systemInviteLog.data.inRaid, "already-in-group invite while dead reports raid context")

fire("PLAYER_DEAD")
local playerStateLog = lastDebug("PLAYER_STATE")
check(playerStateLog ~= nil, "player death state debug logged")
equal(playerStateLog.data.event, "PLAYER_DEAD", "player death state reports event")
check(playerStateLog.data.deadOrGhost, "player death state reports dead or ghost")
playerDeadOrGhost = false
fire("PLAYER_ALIVE")
playerStateLog = lastDebug("PLAYER_STATE")
equal(playerStateLog.data.event, "PLAYER_ALIVE", "player alive state reports event")
check(not playerStateLog.data.deadOrGhost, "player alive state reports living player")
fire("PLAYER_UNGHOST")
playerStateLog = lastDebug("PLAYER_STATE")
equal(playerStateLog.data.event, "PLAYER_UNGHOST", "player unghost state reports event")
playerDeadOrGhost = makeSecretValue("dead-state")
fire("PLAYER_DEAD")
playerStateLog = lastDebug("PLAYER_STATE")
equal(playerStateLog.data.deadOrGhost, false, "restricted player death state never reads as dead")
equal(playerStateLog.data.deadOrGhostKnown, false, "restricted player death state is reported as unreadable")
playerDeadOrGhost = false

local savedUnitIsDeadOrGhost = UnitIsDeadOrGhost
UnitIsDeadOrGhost = nil
fire("PLAYER_DEAD")
playerStateLog = lastDebug("PLAYER_STATE")
equal(playerStateLog.data.deadOrGhost, false, "missing death API never reads as dead")
equal(playerStateLog.data.deadOrGhostKnown, false, "missing death API is reported as unreadable")
UnitIsDeadOrGhost = savedUnitIsDeadOrGhost

-- Popup-backed system messages are filtered from chat but not block-logged from
-- CHAT_MSG_SYSTEM; PARTY_INVITE_REQUEST owns the durable log because it carries
-- the inviter GUID.
inGroup = false
inRaid = false
inInstance = false
currentInstanceType = "none"
local normalSystemMessage = "[Normalbad] vous a invité à rejoindre un groupe."
beforeLogs = #SanctuaryDB.log
filtered = chatFilters.CHAT_MSG_SYSTEM(nil, "CHAT_MSG_SYSTEM", normalSystemMessage)
check(filtered, "popup-backed invite system message suppressed")
fire("CHAT_MSG_SYSTEM", normalSystemMessage)
equal(#SanctuaryDB.log, beforeLogs, "popup-backed system invite does not preempt event log")
fire("PARTY_INVITE_REQUEST", "Normalbad", false, false, true, true, false, "Player-System-1")
equal(#SanctuaryDB.log, beforeLogs + 1, "party invite event logs popup-backed invite")
equal(SanctuaryDB.log[#SanctuaryDB.log].guid, "Player-System-1", "party invite event preserves inviter GUID")
runTimers()

-- The pure chat filter must not duplicate debug/log side effects when WoW calls
-- it once per destination chat frame.
SanctuaryDB.debugEnabled = true
SanctuaryDB.debugLog = {}
ns.captureDebugSnapshot()
equal(#SanctuaryDB.debugLog, 1, "debug snapshot captured")
equal(SanctuaryDB.debugLog[1].cat, "SNAPSHOT", "debug snapshot category")
equal(SanctuaryDB.debugLog[1].data.version, "0.3.2", "debug snapshot version")
equal(SanctuaryDB.debugLog[1].data.build, "20260820-8", "debug snapshot reports the diagnostic build id")
equal(SanctuaryDB.debugLog[1].data.clientVersion, "12.0.7", "debug snapshot reports the client version")
equal(SanctuaryDB.debugLog[1].data.clientBuild, "62119", "debug snapshot reports the client build")
equal(SanctuaryDB.debugLog[1].data.clientInterface, 120007, "debug snapshot reports the client interface number")
equal(SanctuaryDB.debugLog[1].data.addonMetaVersion, "0.3.2", "debug snapshot reports the loaded addon version metadata")
equal(SanctuaryDB.debugLog[1].data.addonMetaBuild, "20260820-8", "debug snapshot reports the loaded addon build metadata")
equal(SanctuaryDB.debugLog[1].data.addonMetaInterface, "120007", "debug snapshot reports the loaded addon interface metadata")
check(SanctuaryDB.debugLog[1].data.chatLockdownKnown, "debug snapshot reports a readable chat messaging lockdown state")
check(not SanctuaryDB.debugLog[1].data.chatLockdown, "debug snapshot reports chat messaging lockdown off")
equal(SanctuaryDB.debugLog[1].data.chatFilterApi, "both", "debug snapshot reports the available chat filter registration paths")
equal(SanctuaryDB.debugLog[1].data.chatFilterApiUsed, "legacy", "debug snapshot reports the registration path actually taken")
equal(SanctuaryDB.debugLog[1].data.systemChatTypeID, 42, "debug snapshot reports ChatTypeInfo.SYSTEM.id")

-- An unreadable lockdown state must never be reported as "not locked down".
local savedChatInfo = C_ChatInfo
C_ChatInfo = { InChatMessagingLockdown = function() return makeSecretValue("lockdown") end }
local lockdownContext = ns.getClientBuildContext()
check(not lockdownContext.chatLockdownKnown, "restricted chat messaging lockdown state is reported as unreadable")
check(not lockdownContext.chatLockdown, "restricted chat messaging lockdown state never reads as locked down")
C_ChatInfo = { InChatMessagingLockdown = function() return true end }
lockdownContext = ns.getClientBuildContext()
check(lockdownContext.chatLockdownKnown, "readable chat messaging lockdown state is reported as readable")
check(lockdownContext.chatLockdown, "active chat messaging lockdown state is reported")
C_ChatInfo = nil
lockdownContext = ns.getClientBuildContext()
check(not lockdownContext.chatLockdownKnown, "missing chat messaging lockdown API is reported as unreadable")
C_ChatInfo = savedChatInfo

-- Every build-identity branch must state its failure. In a report read by a
-- human, a missing key is indistinguishable from a forgotten code path.
local savedGetBuildInfo = GetBuildInfo
GetBuildInfo = nil
local buildContext = ns.getClientBuildContext()
equal(buildContext.clientVersion, "unavailable", "missing GetBuildInfo reports an unavailable client version")
equal(buildContext.clientBuild, "unavailable", "missing GetBuildInfo reports an unavailable client build")
equal(buildContext.clientBuildDate, "unavailable", "missing GetBuildInfo reports an unavailable client build date")
equal(buildContext.clientInterface, "unavailable", "missing GetBuildInfo reports an unavailable client interface")
GetBuildInfo = function() error("client build unavailable") end
buildContext = ns.getClientBuildContext()
equal(buildContext.clientVersion, "error", "failing GetBuildInfo reports an errored client version")
equal(buildContext.clientBuild, "error", "failing GetBuildInfo reports an errored client build")
equal(buildContext.clientBuildDate, "error", "failing GetBuildInfo reports an errored client build date")
equal(buildContext.clientInterface, "error", "failing GetBuildInfo reports an errored client interface")
GetBuildInfo = function() return "12.0.7", "62119", "Aug 19 2026", makeSecretValue("toc") end
buildContext = ns.getClientBuildContext()
equal(buildContext.clientInterface, "<secret>", "a protected interface value is redacted, never converted")
GetBuildInfo = savedGetBuildInfo

local savedAddOnsApi = C_AddOns
C_AddOns = { IsAddOnLoaded = function() return false end }
buildContext = ns.getClientBuildContext()
equal(buildContext.addonMetaVersion, "unavailable", "missing metadata API reports an unavailable addon version")
equal(buildContext.addonMetaBuild, "unavailable", "missing metadata API reports an unavailable addon build")
equal(buildContext.addonMetaInterface, "unavailable", "missing metadata API reports an unavailable addon interface")
C_AddOns = savedAddOnsApi
check(SanctuaryDB.debugLog[1].data.groupInviteFilter, "debug snapshot reports group invite filter")
check(SanctuaryDB.debugLog[1].data.partyInviteSoundGuardActive, "debug snapshot reports active invite sound guard")
equal(SanctuaryDB.debugLog[1].data.chatFramesSeen, 1, "debug snapshot reports chat frames seen")
equal(SanctuaryDB.debugLog[1].data.chatFramesWrapped, 1, "debug snapshot reports wrapped chat frames")
equal(SanctuaryDB.debugLog[1].data.filters.whisper, true, "debug snapshot reports whisper filter")
equal(SanctuaryDB.debugLog[1].data.filters.channelMode, "none", "debug snapshot reports channel mode")
local beforeDebug = #SanctuaryDB.debugLog
chatFilters.CHAT_MSG_SYSTEM(nil, "CHAT_MSG_SYSTEM", systemMessage)
chatFilters.CHAT_MSG_SYSTEM(nil, "CHAT_MSG_SYSTEM", systemMessage)
equal(#SanctuaryDB.debugLog, beforeDebug, "system filter has no side effects")

local beforeOutputDebug = #SanctuaryDB.debugLog
local beforeOutputMessages = #chatMessages
ChatFrame1:AddMessage(systemMessage)
equal(#chatMessages, beforeOutputMessages, "chat output guard suppresses blocked already-in-group invite text")
equal(#SanctuaryDB.debugLog, beforeOutputDebug + 1, "chat output diagnostic logs blocked invite text")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].cat, "CHAT_OUTPUT", "chat output diagnostic category")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.action, "SUPPRESS_BLOCKED_INVITE", "chat output diagnostic reports suppression")
ns.hookChatOutputDiagnostics()
ChatFrame1:AddMessage(systemMessage)
equal(#chatMessages, beforeOutputMessages, "chat output guard remains single after rehook")
equal(#SanctuaryDB.debugLog, beforeOutputDebug + 2, "chat output diagnostic hook is not duplicated")

local trustedOutputMessage = "[Friend] vous a invité à rejoindre un groupe, mais vous ne pouviez pas accepter car vous êtes déjà dans un groupe."
SanctuaryDB.manualWhitelist.chatfriend = { displayName = "Friend" }
ns.invalidateWhitelist()
ns.getCharacterDecision("Friend")
beforeOutputDebug = #SanctuaryDB.debugLog
beforeOutputMessages = #chatMessages
ChatFrame1:AddMessage(trustedOutputMessage)
equal(#chatMessages, beforeOutputMessages + 1, "chat output guard preserves trusted invite text")
equal(#SanctuaryDB.debugLog, beforeOutputDebug + 1, "chat output diagnostic logs trusted invite text")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.action, "ALLOW_INVITE_OUTPUT", "trusted invite output diagnostic reports allow")
SanctuaryDB.manualWhitelist.chatfriend = nil
ns.invalidateWhitelist()
ns.getCharacterDecision("Harasser-TestRealm")

local lateFrameMessages = {}
ChatFrame2 = { AddMessage = function(self, message) lateFrameMessages[#lateFrameMessages + 1] = message end }
ns.hookChatOutputDiagnostics()
beforeOutputDebug = #SanctuaryDB.debugLog
ChatFrame2:AddMessage(systemMessage)
equal(#lateFrameMessages, 0, "late chat frame output guard suppresses blocked invite text")
equal(#SanctuaryDB.debugLog, beforeOutputDebug + 1, "late chat frame blocked output diagnostic logged")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.frame, 2, "late chat frame diagnostic reports frame index")

beforeOutputDebug = #SanctuaryDB.debugLog
local beforeNoMatchMessages = #chatMessages
ChatFrame1:AddMessage("invitation group text that does not match localized patterns")
equal(#chatMessages, beforeNoMatchMessages + 1, "chat output no-match invite-like text stays visible")
equal(#SanctuaryDB.debugLog, beforeOutputDebug + 1, "chat output no-match diagnostic logged")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.action, "NO_MATCH", "chat output no-match diagnostic action")

local sanctuaryWrappedAddMessage = ChatFrame1.AddMessage
local externalWrapperCalls = 0
ChatFrame1.AddMessage = function(self, message, ...)
    externalWrapperCalls = externalWrapperCalls + 1
    return sanctuaryWrappedAddMessage(self, message, ...)
end
ns.hookChatOutputDiagnostics()
SanctuaryDB.manualWhitelist.chatfriend = { displayName = "Friend" }
ns.invalidateWhitelist()
ns.getCharacterDecision("Friend")
beforeOutputDebug = #SanctuaryDB.debugLog
beforeOutputMessages = #chatMessages
externalWrapperCalls = 0
ChatFrame1:AddMessage(trustedOutputMessage)
equal(#chatMessages, beforeOutputMessages + 1, "rewrapped chat output preserves trusted invite text")
equal(externalWrapperCalls, 1, "rewrapped trusted output calls external wrapper once")
equal(#SanctuaryDB.debugLog, beforeOutputDebug + 1, "rewrapped trusted output logs only once")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.action, "ALLOW_INVITE_OUTPUT", "rewrapped trusted output diagnostic reports allow")
SanctuaryDB.manualWhitelist.chatfriend = nil
ns.invalidateWhitelist()
ns.getCharacterDecision("Harasser-TestRealm")
beforeOutputDebug = #SanctuaryDB.debugLog
beforeOutputMessages = #chatMessages
externalWrapperCalls = 0
ChatFrame1:AddMessage(systemMessage)
equal(#chatMessages, beforeOutputMessages, "rewrapped chat output suppresses blocked invite text")
equal(externalWrapperCalls, 0, "rewrapped blocked output stops before external wrapper")
equal(#SanctuaryDB.debugLog, beforeOutputDebug + 1, "rewrapped blocked output logs only once")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.action, "SUPPRESS_BLOCKED_INVITE", "rewrapped blocked output diagnostic reports suppression")

local beforeChatDecisionDebug = #SanctuaryDB.debugLog
fire("CHAT_MSG_WHISPER", "secret", "Unknown")
equal(#SanctuaryDB.debugLog, beforeChatDecisionDebug + 1, "blocked whisper debug decision logged")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].cat, "CHAT_DECISION", "chat decision category")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.kind, "whisper", "whisper decision kind")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.action, "BLOCK_NOT_WHITELISTED", "whisper decision action")

beforeChatDecisionDebug = #SanctuaryDB.debugLog
fire("CHAT_MSG_BN_WHISPER", "hello", "|Kq2|k", bnetWhisperPayload(101))
equal(#SanctuaryDB.debugLog, beforeChatDecisionDebug + 1, "allowed BNet whisper debug decision logged")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.kind, "bn_whisper", "BNet decision kind")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.action, "ALLOW", "BNet decision action")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.reason, "bnet_whitelist", "BNet decision reason")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.sender, "Battle Friend", "BNet decision logs resolved account name")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.rawSender, "|Kq2|k", "BNet decision logs raw protected sender token")
check(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.bnetResolvedByID, "BNet decision reports sender ID resolution")
check(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.bnetWhitelisted, "BNet decision reports cache hit")
check(tonumber(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.bnetCache) >= 1, "BNet decision reports cache size")

beforeChatDecisionDebug = #SanctuaryDB.debugLog
fire("CHAT_MSG_BN_WHISPER", "hello", "|Kq2|k", bnetWhisperPayload(999))
equal(#SanctuaryDB.debugLog, beforeChatDecisionDebug + 1, "unresolved BNet sender ID debug decision logged")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.kind, "bn_whisper", "unresolved BNet decision kind")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.action, "BLOCK_NOT_WHITELISTED", "unresolved BNet decision action")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.reason, "not_whitelisted", "unresolved BNet decision reason")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.bnetSenderID, "present", "unresolved BNet decision reports sender ID presence")
check(not SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.bnetResolvedByID, "unresolved BNet decision reports missing ID resolution")
check(not SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.bnetWhitelisted, "unresolved BNet decision reports cache miss")

SanctuaryDB.filters.channelMode = "all"
beforeChatDecisionDebug = #SanctuaryDB.debugLog
fire("CHAT_MSG_CHANNEL", "hello", "Unknown")
equal(#SanctuaryDB.debugLog, beforeChatDecisionDebug + 1, "blocked channel debug decision logged")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.kind, "channel", "channel decision kind")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.action, "BLOCK_NOT_WHITELISTED", "channel decision action")
SanctuaryDB.filters.channelMode = "none"

local secretChatPayload = makeSecretValue("chat")
beforeChatDecisionDebug = #SanctuaryDB.debugLog
local secretWhisperOk = pcall(function()
    fire("CHAT_MSG_WHISPER", secretChatPayload, "Unknown")
end)
check(secretWhisperOk, "secret whisper payload does not break debug logging")
equal(#SanctuaryDB.debugLog, beforeChatDecisionDebug + 1, "secret whisper debug decision logged")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.msg, "<secret>", "secret whisper payload is redacted")

local secretSender = makeSecretValue("sender")
beforeChatDecisionDebug = #SanctuaryDB.debugLog
local beforeSecretSenderLogs = #SanctuaryDB.log
local secretSenderOk = pcall(function()
    fire("CHAT_MSG_WHISPER", "hello", secretSender)
end)
check(secretSenderOk, "secret whisper sender does not break debug logging")
equal(#SanctuaryDB.debugLog, beforeChatDecisionDebug + 1, "secret whisper sender debug decision logged")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.sender, "<secret>", "secret whisper sender is redacted")
equal(#SanctuaryDB.log, beforeSecretSenderLogs + 1, "secret whisper sender durable block logged")
equal(SanctuaryDB.log[#SanctuaryDB.log].name, "<secret>", "secret whisper sender durable log is redacted")

beforeChatDecisionDebug = #SanctuaryDB.debugLog
local secretBNetSenderOk = pcall(function()
    fire("CHAT_MSG_BN_WHISPER", "hello", secretSender)
end)
check(secretBNetSenderOk, "secret BNet whisper sender does not break debug logging")
equal(#SanctuaryDB.debugLog, beforeChatDecisionDebug + 1, "secret BNet sender debug decision logged")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.kind, "bn_whisper", "secret BNet sender decision kind")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.sender, "<secret>", "secret BNet sender is redacted")

local beforeSecretSystemDebug = #SanctuaryDB.debugLog
inGroup = true
inRaid = true
inInstance = true
currentInstanceType = "raid"
equal(SanctuaryDB.filters.strictGroupInviteSystemMessages, false, "strict secret system invite filter defaults off")
filtered = chatFilters.CHAT_MSG_SYSTEM(nil, "CHAT_MSG_SYSTEM", secretChatPayload)
check(not filtered, "secret system payload stays visible when strict mode is off")
SanctuaryDB.filters.strictGroupInviteSystemMessages = true
filtered = chatFilters.CHAT_MSG_SYSTEM(nil, "CHAT_MSG_SYSTEM", secretChatPayload)
check(filtered, "strict mode marks secret system payload suppressible while grouped in raid")
local beforeStrictSecretSystemDebug = #SanctuaryDB.debugLog
fire("CHAT_MSG_SYSTEM", secretChatPayload, "extra1", "extra2")
equal(#SanctuaryDB.debugLog, beforeStrictSecretSystemDebug + 1, "strict secret system payload is diagnosed once")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.result, "STRICT_POLICY_ELIGIBLE", "strict secret system diagnostic result")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.strictGroupInviteSystemMessages, true, "strict secret system diagnostic reports setting")
playerDeadOrGhost = true
filtered = chatFilters.CHAT_MSG_SYSTEM(nil, "CHAT_MSG_SYSTEM", secretChatPayload)
check(filtered, "strict mode still marks secret system payload suppressible while dead in raid")
beforeStrictSecretSystemDebug = #SanctuaryDB.debugLog
fire("CHAT_MSG_SYSTEM", secretChatPayload, "extra1", "extra2")
equal(#SanctuaryDB.debugLog, beforeStrictSecretSystemDebug + 1, "strict secret system payload while dead is diagnosed once")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.result, "STRICT_POLICY_ELIGIBLE", "strict secret system diagnostic result while dead")
check(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.deadOrGhost, "strict secret system diagnostic reports dead or ghost state")
check(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.deadOrGhostKnown, "strict secret system diagnostic reports a readable player state")
playerDeadOrGhost = false
inGroup = false
inRaid = false
inInstance = false
currentInstanceType = "none"
filtered = chatFilters.CHAT_MSG_SYSTEM(nil, "CHAT_MSG_SYSTEM", secretChatPayload)
check(not filtered, "strict mode leaves secret system payload out of policy outside group or instance")
SanctuaryDB.filters.strictGroupInviteSystemMessages = false
inGroup = true
inRaid = true
inInstance = true
currentInstanceType = "raid"
beforeSecretSystemDebug = #SanctuaryDB.debugLog
local secretSystemOk = pcall(function()
    fire("CHAT_MSG_SYSTEM", secretChatPayload, "extra1", "extra2")
end)
check(secretSystemOk, "secret system payload does not break invite diagnostics")
equal(#SanctuaryDB.debugLog, beforeSecretSystemDebug + 1, "secret system payload is diagnosed once")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.result, "SECRET_VALUE", "secret system diagnostic result")
check(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.inRaid, "secret system diagnostic reports raid context")
check(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.inInstance, "secret system diagnostic reports instance context")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.instanceType, "raid", "secret system diagnostic reports instance type")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.argCount, 2, "secret system diagnostic reports extra arg count")

beforeOutputDebug = #SanctuaryDB.debugLog
beforeOutputMessages = #chatMessages
playerDeadOrGhost = true
local secretOutputOk = pcall(function()
    ChatFrame1:AddMessage(secretChatPayload)
end)
check(secretOutputOk, "secret chat output payload does not break diagnostics")
equal(#chatMessages, beforeOutputMessages + 1, "secret chat output keeps native display path")
equal(#SanctuaryDB.debugLog, beforeOutputDebug + 1, "secret chat output diagnostic logged once")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].cat, "CHAT_OUTPUT", "secret chat output diagnostic category")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.action, "SECRET_VALUE", "secret chat output diagnostic result")
check(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.inRaid, "secret chat output diagnostic reports raid context")
check(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.deadOrGhost, "secret chat output diagnostic reports dead or ghost state")
check(not SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.messageTypeIDKnown, "secret chat output without a message type reports it as unknown")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.messageTypeID, "nil", "secret chat output without a message type records nil")
check(not SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.isSystemTypeIDKnown, "secret chat output without a message type cannot decide the system category")
playerDeadOrGhost = false
inGroup = false
inRaid = false
inInstance = false
currentInstanceType = "none"

-- ---------------------------------------------------------------------------
-- Retail secret-chat contract instrumentation.
--
-- Confirmed from Blizzard_ChatFrameBase/Shared/ChatFrameFilters.lua: the message
-- event filter registry wraps each addon callback in
--   local function ApplyFilter(chatFrame, event, ...)
--       if canaccessvalue(...) then return callback(chatFrame, event, ...) end
--   end
-- so a secret payload skips the addon callback entirely, ProcessFilters reports
-- no discard, and the message reaches AddMessage on every subscribed frame.
-- These tests pin that contract: strict mode can never suppress a secret system
-- line through the filter, whatever the group/instance context.
-- ---------------------------------------------------------------------------
local function expectRegistrySkipsSecret(label)
    local discarded, path = dispatchChatFilter("CHAT_MSG_SYSTEM", secretChatPayload)
    equal(path, "skipped", label .. " skips the addon filter callback")
    check(not discarded, label .. " cannot discard the secret system message")
end

local function expectSecretOutputReachesFrame(label, messageTypeID)
    local before = #chatMessages
    local ok = pcall(function()
        ChatFrame1:AddMessage(secretChatPayload, 1, 1, 0, messageTypeID)
    end)
    check(ok, label .. " does not break the chat output guard")
    equal(#chatMessages, before + 1, label .. " still reaches the original AddMessage")
end

-- The two strict-mode calls below used to assert the opposite: the line reached
-- the frame, because nothing stopped it. That is the defect 0.4.0 fixes, so the
-- assertions are reformulated rather than removed -- and the journal must stay
-- untouched, because a masked system line has no sender and no content to record.
local function expectSecretOutputMasked(label, messageTypeID)
    local beforeMessages = #chatMessages
    local beforeLog = #SanctuaryDB.log
    local ok = pcall(function()
        ChatFrame1:AddMessage(secretChatPayload, 1, 1, 0, messageTypeID)
    end)
    check(ok, label .. " does not break the chat output guard")
    equal(#chatMessages, beforeMessages, label .. " never reaches the original AddMessage")
    equal(#SanctuaryDB.log, beforeLog, label .. " writes nothing to the block journal")
end

-- Five-person group inside a dungeon: the field-reported scenario.
inGroup = true
inRaid = false
inInstance = true
currentInstanceType = "party"
groupMembers = { "Harasser-TestRealm", "A-TestRealm", "B-TestRealm", "C-TestRealm" }
equal(GetNumGroupMembers(), 5, "five-person group modelled")
SanctuaryDB.filters.strictGroupInviteSystemMessages = true
expectRegistrySkipsSecret("strict mode in a five-person dungeon group")
expectSecretOutputMasked("strict mode in a five-person dungeon group", ChatTypeInfo.SYSTEM.id)
SanctuaryDB.filters.strictGroupInviteSystemMessages = false
expectRegistrySkipsSecret("relaxed mode in a five-person dungeon group")
expectSecretOutputReachesFrame("relaxed mode in a five-person dungeon group", ChatTypeInfo.SYSTEM.id)

-- Raid context, both strict states.
inRaid = true
currentInstanceType = "raid"
SanctuaryDB.filters.strictGroupInviteSystemMessages = true
expectRegistrySkipsSecret("strict mode in raid")
expectSecretOutputMasked("strict mode in raid", ChatTypeInfo.SYSTEM.id)
SanctuaryDB.filters.strictGroupInviteSystemMessages = false
expectRegistrySkipsSecret("relaxed mode in raid")
expectSecretOutputReachesFrame("relaxed mode in raid", ChatTypeInfo.SYSTEM.id)

-- Solo, out of instance: same contract, no eligibility either.
inGroup = false
inRaid = false
inInstance = false
currentInstanceType = "none"
groupMembers = {}
SanctuaryDB.filters.strictGroupInviteSystemMessages = true
expectRegistrySkipsSecret("strict mode outside any group")
SanctuaryDB.filters.strictGroupInviteSystemMessages = false

-- A non-secret system payload still reaches the filter and can be discarded.
local blockedDiscarded, blockedPath = dispatchChatFilter("CHAT_MSG_SYSTEM", systemMessage)
equal(blockedPath, "called", "non-secret system payload reaches the addon filter")
check(blockedDiscarded, "non-secret blocked invite text is discarded by the registry")

SanctuaryDB.manualWhitelist.chatfriend = { displayName = "Friend" }
ns.invalidateWhitelist()
local allowedDiscarded, allowedPath = dispatchChatFilter("CHAT_MSG_SYSTEM", trustedOutputMessage)
equal(allowedPath, "called", "trusted system payload reaches the addon filter")
check(not allowedDiscarded, "trusted invite text is not discarded by the registry")
SanctuaryDB.manualWhitelist.chatfriend = nil
ns.invalidateWhitelist()
ns.getCharacterDecision("Harasser-TestRealm")

-- The skip is a registry-wide contract, not a CHAT_MSG_SYSTEM specialty.
local secretWhisperDiscarded, secretWhisperPath = dispatchChatFilter("CHAT_MSG_WHISPER", secretChatPayload, "Unknown")
equal(secretWhisperPath, "skipped", "secret whisper payload skips the addon filter callback")
check(not secretWhisperDiscarded, "secret whisper payload cannot be discarded")

-- The registry passes the whole vararg to canaccessvalue, so a secret argument
-- other than the message also skips the callback. Sanctuary's output
-- instrumentation only triggers on a secret message text, so this class of leak
-- is modelled here but deliberately not yet measured.
local secretSenderDiscarded, secretSenderPath = dispatchChatFilter("CHAT_MSG_WHISPER", "hello", secretSender)
equal(secretSenderPath, "skipped", "a secret sender alone skips the addon filter callback")
check(not secretSenderDiscarded, "a readable message with a secret sender cannot be discarded")

-- Message type instrumentation on the secret output path.
inGroup = true
inRaid = false
inInstance = true
currentInstanceType = "party"
beforeOutputDebug = #SanctuaryDB.debugLog
beforeOutputMessages = #chatMessages
ChatFrame1:AddMessage(secretChatPayload, 1, 1, 0, ChatTypeInfo.SYSTEM.id)
equal(#chatMessages, beforeOutputMessages + 1, "system-typed secret output reaches the original AddMessage")
local forwardedArgs = chatMessageArgs[#chatMessageArgs]
equal(forwardedArgs.n, 4, "secret output forwards every trailing argument untouched")
equal(forwardedArgs[4], ChatTypeInfo.SYSTEM.id, "secret output forwards the original message type to the client")
equal(#SanctuaryDB.debugLog, beforeOutputDebug + 1, "system-typed secret output is diagnosed once")
local secretOutputLog = SanctuaryDB.debugLog[#SanctuaryDB.debugLog]
equal(secretOutputLog.cat, "CHAT_OUTPUT", "system-typed secret output diagnostic category")
equal(secretOutputLog.data.action, "SECRET_VALUE", "system-typed secret output diagnostic action")
equal(secretOutputLog.data.msg, "<secret>", "system-typed secret output never records the payload")
equal(secretOutputLog.data.messageTypeID, 42, "system-typed secret output records the fifth AddMessage argument")
check(secretOutputLog.data.messageTypeIDKnown, "system-typed secret output reports a readable message type")
equal(secretOutputLog.data.systemTypeID, 42, "system-typed secret output records ChatTypeInfo.SYSTEM.id")
check(secretOutputLog.data.isSystemTypeID, "system-typed secret output is recognized as the system category")
check(secretOutputLog.data.isSystemTypeIDKnown, "system-typed secret output reports a decidable system category")
equal(secretOutputLog.data.frames, "1", "system-typed secret output records its frame list")
equal(secretOutputLog.data.frameCount, 1, "system-typed secret output starts at one frame")

-- One payload dispatched to several ChatFrames must collapse into one entry.
ns.hookChatOutputDiagnostics()
beforeOutputDebug = #SanctuaryDB.debugLog
ChatFrame1:AddMessage(secretChatPayload, 1, 1, 0, ChatTypeInfo.SYSTEM.id)
ChatFrame2:AddMessage(secretChatPayload, 1, 1, 0, ChatTypeInfo.SYSTEM.id)
equal(#SanctuaryDB.debugLog, beforeOutputDebug + 1, "secret output burst across chat frames is diagnosed once")
secretOutputLog = SanctuaryDB.debugLog[#SanctuaryDB.debugLog]
equal(secretOutputLog.data.frames, "1,2", "secret output burst records every destination frame")
equal(secretOutputLog.data.frameCount, 2, "secret output burst counts its destination frames")

-- A frame index that repeats is a new message, not another destination.
beforeOutputDebug = #SanctuaryDB.debugLog
ChatFrame1:AddMessage(secretChatPayload, 1, 1, 0, ChatTypeInfo.SYSTEM.id)
equal(#SanctuaryDB.debugLog, beforeOutputDebug + 1, "a repeated frame opens a new secret output diagnostic")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.frameCount, 1, "a new secret output diagnostic restarts its frame count")

-- A different message type is a different signal and must not be collapsed.
beforeOutputDebug = #SanctuaryDB.debugLog
ChatFrame1:AddMessage(secretChatPayload, 1, 1, 0, 99)
equal(#SanctuaryDB.debugLog, beforeOutputDebug + 1, "a different secret message type opens a new diagnostic")
secretOutputLog = SanctuaryDB.debugLog[#SanctuaryDB.debugLog]
equal(secretOutputLog.data.messageTypeID, 99, "non-system secret output records its message type")
check(not secretOutputLog.data.isSystemTypeID, "non-system secret output is not recognized as the system category")
check(secretOutputLog.data.isSystemTypeIDKnown, "non-system secret output still reports a decidable system category")

-- A protected message type must never be read as a number.
beforeOutputDebug = #SanctuaryDB.debugLog
local secretTypeOk = pcall(function()
    ChatFrame1:AddMessage(secretChatPayload, 1, 1, 0, makeSecretValue("messageType"))
end)
check(secretTypeOk, "secret message type does not break the chat output guard")
equal(#SanctuaryDB.debugLog, beforeOutputDebug + 1, "secret message type is diagnosed once")
secretOutputLog = SanctuaryDB.debugLog[#SanctuaryDB.debugLog]
equal(secretOutputLog.data.messageTypeID, "<secret>", "secret message type is redacted")
check(not secretOutputLog.data.messageTypeIDKnown, "secret message type is reported as unreadable")
check(not secretOutputLog.data.isSystemTypeIDKnown, "secret message type cannot decide the system category")

-- ChatTypeInfo may be missing at load time; the guard must degrade, not error.
local savedChatTypeInfo = ChatTypeInfo
ChatTypeInfo = nil
beforeOutputDebug = #SanctuaryDB.debugLog
local missingTypeInfoOk = pcall(function()
    ChatFrame1:AddMessage(secretChatPayload, 1, 1, 0, 42)
end)
check(missingTypeInfoOk, "missing ChatTypeInfo does not break the chat output guard")
equal(#SanctuaryDB.debugLog, beforeOutputDebug + 1, "missing ChatTypeInfo still diagnoses the secret output")
secretOutputLog = SanctuaryDB.debugLog[#SanctuaryDB.debugLog]
equal(secretOutputLog.data.systemTypeID, "unknown", "missing ChatTypeInfo reports an unknown system type")
check(not secretOutputLog.data.isSystemTypeIDKnown, "missing ChatTypeInfo cannot decide the system category")
ChatTypeInfo = savedChatTypeInfo

-- An unreadable category cannot discriminate two payloads, so it must never be
-- collapsed. Reported scenario: a dedicated Whispers tab means a secret system
-- line and a secret whisper land on different frames within the same window;
-- merging them would publish "1 message on 2 frames" instead of 2 messages.
local extraFrameMessages = {}
ChatFrame3 = { AddMessage = function(self, message) extraFrameMessages[#extraFrameMessages + 1] = message end }
ChatFrame4 = { AddMessage = function(self, message) extraFrameMessages[#extraFrameMessages + 1] = message end }
ns.hookChatOutputDiagnostics()

beforeOutputDebug = #SanctuaryDB.debugLog
ChatFrame1:AddMessage(secretChatPayload, 1, 1, 0, makeSecretValue("messageType"))
ChatFrame3:AddMessage(secretChatPayload, 1, 1, 0, makeSecretValue("messageType"))
equal(#SanctuaryDB.debugLog, beforeOutputDebug + 2, "secret message types are never collapsed across frames")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.frameCount, 1, "an unreadable category keeps one entry per message")

beforeOutputDebug = #SanctuaryDB.debugLog
ChatFrame1:AddMessage(secretChatPayload)
ChatFrame3:AddMessage(secretChatPayload)
equal(#SanctuaryDB.debugLog, beforeOutputDebug + 2, "absent message types are never collapsed across frames")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.frameCount, 1, "an absent category keeps one entry per message")

-- An unreadable category must not open a burst a later readable one attaches to.
beforeOutputDebug = #SanctuaryDB.debugLog
ChatFrame3:AddMessage(secretChatPayload, 1, 1, 0, ChatTypeInfo.SYSTEM.id)
equal(#SanctuaryDB.debugLog, beforeOutputDebug + 1, "a readable category after an unreadable one opens its own entry")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.frameCount, 1, "a readable category does not inherit an unreadable burst")

-- Burst window. GetTime() is frozen elsewhere in this harness, so the window is
-- exercised explicitly here and the clock is restored afterwards.
local savedNow = now

-- Beyond the window, the same signature on a new frame starts a new entry.
now = now + 1
beforeOutputDebug = #SanctuaryDB.debugLog
ChatFrame1:AddMessage(secretChatPayload, 1, 1, 0, ChatTypeInfo.SYSTEM.id)
equal(#SanctuaryDB.debugLog, beforeOutputDebug + 1, "burst window test opens a fresh diagnostic")
now = now + 0.6
ChatFrame3:AddMessage(secretChatPayload, 1, 1, 0, ChatTypeInfo.SYSTEM.id)
equal(#SanctuaryDB.debugLog, beforeOutputDebug + 2, "a frame arriving after the burst window opens a new diagnostic")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.frameCount, 1, "an expired burst does not carry over its frame count")

-- The window is measured from the start of the burst, not from its last
-- extension: burst.time is deliberately not refreshed, so a burst is bounded to
-- 0.5s in total rather than being extendable indefinitely.
now = now + 1
beforeOutputDebug = #SanctuaryDB.debugLog
ChatFrame1:AddMessage(secretChatPayload, 1, 1, 0, ChatTypeInfo.SYSTEM.id)
now = now + 0.3
ChatFrame3:AddMessage(secretChatPayload, 1, 1, 0, ChatTypeInfo.SYSTEM.id)
equal(#SanctuaryDB.debugLog, beforeOutputDebug + 1, "a frame inside the burst window still extends the burst")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.frameCount, 2, "an extended burst counts both frames")
now = now + 0.3
ChatFrame4:AddMessage(secretChatPayload, 1, 1, 0, ChatTypeInfo.SYSTEM.id)
equal(#SanctuaryDB.debugLog, beforeOutputDebug + 2, "extending a burst does not restart its window")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.frameCount, 1, "the burst that follows an expired window starts over")

-- Restore the frozen clock for the remaining sections, then close the burst
-- left behind by replaying its own last frame: a repeated frame always opens a
-- new entry, so nothing can attach to a burst stamped in the future.
now = savedNow
beforeOutputDebug = #SanctuaryDB.debugLog
ChatFrame4:AddMessage(secretChatPayload, 1, 1, 0, ChatTypeInfo.SYSTEM.id)
equal(#SanctuaryDB.debugLog, beforeOutputDebug + 1, "restoring the clock leaves no burst open behind it")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.frameCount, 1, "the burst reopened on the restored clock starts at one frame")

inGroup = false
inRaid = false
inInstance = false
currentInstanceType = "none"

-- Filter registry availability: legacy global, ChatFrameUtil namespace, neither.
equal(ns.describeChatFilterApi(), "both", "both chat filter registration paths are available")
local resolvedRegistrar, resolvedApi = ns.resolveChatFilterRegistrar()
equal(resolvedApi, "legacy", "legacy global is preferred while Blizzard still aliases it")
check(resolvedRegistrar == ChatFrame_AddMessageEventFilter, "legacy path resolves to the global alias")
local savedLegacyRegistrar = ChatFrame_AddMessageEventFilter
ChatFrame_AddMessageEventFilter = nil
resolvedRegistrar, resolvedApi = ns.resolveChatFilterRegistrar()
equal(resolvedApi, "chatframeutil", "ChatFrameUtil path is used when the legacy alias is gone")
check(resolvedRegistrar == ChatFrameUtil.AddMessageEventFilter, "ChatFrameUtil path resolves to the namespaced function")
equal(ns.describeChatFilterApi(), "chatframeutil", "availability reports the namespaced path only")
local savedChatFrameUtil = ChatFrameUtil
ChatFrameUtil = nil
resolvedRegistrar, resolvedApi = ns.resolveChatFilterRegistrar()
equal(resolvedRegistrar, nil, "no registrar is resolved when both paths are gone")
equal(resolvedApi, "none", "missing registry is reported as none")
equal(ns.describeChatFilterApi(), "none", "availability reports no registration path")
ChatFrameUtil = savedChatFrameUtil
ChatFrame_AddMessageEventFilter = savedLegacyRegistrar

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
bnetFriends = { { bnetAccountID = 101, accountName = "Battle Friend", gameAccountInfo = { characterName = "Onlinechar" } } }
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
SanctuaryDB.logging.maxEntries = 7
for i = 1, 10 do
    ns.debugLog("ROTATE", { i = i })
end
equal(#SanctuaryDB.debugLog, 7, "debug log rotates to configured max entries")
equal(SanctuaryDB.debugLog[1].data.i, 4, "debug log keeps newest entries after configured rotation")
SanctuaryDB.logging.maxEntries = 5000

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
playerDeadOrGhost = true
StaticPopup_Show("PARTY_INVITE", "Harasser vous invite dans un groupe.")
equal(popup.alpha, 0, "unknown party popup masked immediately")
equal(#playedSounds, 0, "unknown party popup native sounds suppressed before decision")
check(ns.areInviteSoundsMuted(), "blocked party invite uses active native sound mute")
local popupShowLog = lastDebug("POPUP")
check(popupShowLog ~= nil, "blocked party popup show logs runtime state")
check(popupShowLog.data.deadOrGhost, "blocked party popup show reports dead or ghost state")
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
local inviteLog = lastDebug("INVITE")
check(inviteLog ~= nil, "blocked party invite logs invite decision")
equal(inviteLog.data.decisionId, popupDecision.data.decisionId, "invite decision log shares popup decision id")
equal(inviteApi.data.decisionId, popupDecision.data.decisionId, "invite API log shares popup decision id")
check(popupDecision.data.deadOrGhost, "blocked party popup decision reports dead or ghost state")
check(inviteLog.data.deadOrGhost, "blocked party invite reports dead or ghost state")
check(not inviteLog.data.inRaid, "blocked party invite debug reports non-raid context")
check(not inviteLog.data.inInstance, "blocked party invite debug reports non-instance context")
equal(inviteLog.data.instanceType, "none", "blocked party invite debug reports instance type")
equal(forbiddenStaticHides, 0, "no direct StaticPopup_Hide")
runTimers()
equal(declinedGroups, beforeBlockedDeclines + 1, "blocked group invite silent hide does not decline twice")
check(not popup:IsShown(), "blocked party invite popup hidden after native decline")
equal(#playedSounds, 0, "blocked party invite close sound suppressed")
equal(popup.alpha, 1, "popup alpha restored on silent hide")
check(not mutedSoundFiles[567490], "blocked party invite releases popup-open mute after hide")
check(not mutedSoundFiles[567464], "blocked party invite releases popup-close mute after hide")
playerDeadOrGhost = false

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
local trustedInviteLog = lastDebug("INVITE")
check(trustedInviteLog ~= nil, "trusted popup-first invite logs invite decision")
check(trustedInviteLog.data.replayedSound, "trusted popup-first invite reports replayed native sound")
check(tonumber(trustedInviteLog.data.releasedSoundGuards) > 0, "trusted popup-first invite reports released sound guard")
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
trustedInviteLog = lastDebug("INVITE")
check(trustedInviteLog ~= nil, "trusted Sanctuary-first invite logs invite decision")
check(not trustedInviteLog.data.replayedSound, "trusted Sanctuary-first invite does not report replayed sound before popup")
equal(trustedInviteLog.data.releasedSoundGuards, 0, "trusted Sanctuary-first invite reports no released sound guard")
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
-- The frame is hidden from inside its own OnShow, so Retail dispatches OnHide
-- (and its close sound) only after the show handlers unwound. The guard must
-- still be held at that point, and must be released right after.
local silentHide = lastDebug("GUILD_INVITE_FRAME", "HIDE_SILENT")
check(silentHide ~= nil, "event-first blocked guild invite logs the silent hide")
equal(silentHide.data.onHideOrder, "deferred", "event-first blocked guild invite records the deferred OnHide order")
check(silentHide.data.soundGuardActive, "event-first blocked guild invite still holds the sound guard when OnHide is deferred")
check(not mutedSoundFiles[567490], "event-first blocked guild invite releases popup-open mute after hide")
check(not mutedSoundFiles[567464], "event-first blocked guild invite releases popup-close mute after hide")
equal(GuildInviteFrame.accepted, nil, "event-first blocked guild invite restores the accepted flag after OnHide")
runTimers()
check(not mutedSoundFiles[567464], "event-first blocked guild invite leaves no mute behind after the fallback timer")

playedSounds = {}
SanctuaryDB.debugLog = {}
showGuildInviteFrame("GuildbadFrame", "Bad Guild")
equal(GuildInviteFrame:IsShown(), true, "frame-first blocked guild invite waits for event")
equal(GuildInviteFrame.alpha, 0, "frame-first blocked guild invite frame masked immediately")
equal(#playedSounds, 0, "frame-first blocked guild invite has no open sound leak")
fire("GUILD_INVITE_REQUEST", "GuildbadFrame", "Bad Guild")
equal(GuildInviteFrame:IsShown(), false, "frame-first blocked guild invite frame hidden after decision")
equal(#playedSounds, 0, "frame-first blocked guild invite close sound suppressed")
-- Here the hide runs from the event handler, outside any OnShow dispatch, so
-- Retail runs OnHide synchronously. Both orders must end silent.
silentHide = lastDebug("GUILD_INVITE_FRAME", "HIDE_SILENT")
check(silentHide ~= nil, "frame-first blocked guild invite logs the silent hide")
equal(silentHide.data.onHideOrder, "synchronous", "frame-first blocked guild invite records the synchronous OnHide order")
check(not mutedSoundFiles[567464], "frame-first blocked guild invite releases popup-close mute after hide")
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
StaticPopup_Show("PARTY_INVITE", "Guardedbad vous invite dans un groupe.")
check(mutedSoundFiles[567490], "protected party popup mutes generic open sound")
check(mutedSoundFiles[567464], "protected party popup mutes generic close sound")
local afterPartyGuardMutes = #muted
SanctuaryDB.filters.groupInvite = false
ns.refreshInviteSoundMuteState()
check(not mutedSoundFiles[567490], "disabled group filter releases party popup open guard")
check(not mutedSoundFiles[567464], "disabled group filter releases party popup close guard")
equal(popup.alpha, 1, "disabled group filter restores visible party popup")
popup.inviteAccepted = true
popup:Hide()
popup.inviteAccepted = nil
playedSounds = {}
equal(#muted, afterPartyGuardMutes, "disabled group filter releases party guard without duplicate mute")
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
equal(#muted, afterPartyGuardMutes, "enabled invite filter keeps existing invite sound guard without duplicate mute")
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
check(bnetSimulation.resolvedByID, "BNet friend-index simulation resolves through sender ID")

local originalBNetInfoByID = C_BattleNet.GetAccountInfoByID
C_BattleNet.GetAccountInfoByID = function() return nil end
bnetSimulation = ns.simulateBNetFriend("1")
check(bnetSimulation.available, "BNet friend-index simulation still reaches friend API when ID lookup fails")
check(bnetSimulation.filtered, "BNet friend-index simulation blocks unresolved protected sender ID")
equal(bnetSimulation.reason, "not_whitelisted", "BNet unresolved sender ID simulation reason")
check(not bnetSimulation.resolvedByID, "BNet unresolved sender ID simulation reports missing ID resolution")
C_BattleNet.GetAccountInfoByID = originalBNetInfoByID

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

-- Every diagnostic is reached through the catalogue now: there is no command to
-- type, so the tests drive the entry the panel's button drives. What is asserted
-- is unchanged -- the line produced, the debug entry, the sounds, the screen.
local diagLine = ns.runDiagnosticById("sim_invite", "Simulatedbad").text
check(diagLine:find("Simulation invite", 1, true) ~= nil, "the invite simulation names itself")
check(diagLine:find("Simulatedbad", 1, true) ~= nil, "and names the target it was given")
equal(declinedGroups, beforeSimulationDeclines, "the invite simulation does not decline groups")

diagLine = ns.runDiagnosticById("sim_bnetfriend", "1").text
check(diagLine:find("Simulation bnet whisper", 1, true) ~= nil, "the Battle.net friend simulation names itself")

SanctuaryDB.debugLog = {}
diagLine = ns.runDiagnosticById("diag_chat").text
check(diagLine:find("Diagnostic chat invite", 1, true) ~= nil, "the chat diagnostic names itself")
local chatOutputLog = lastDebug("CHAT_OUTPUT")
check(chatOutputLog ~= nil, "the chat diagnostic triggers the chat output guard")
equal(chatOutputLog.data.action, "SUPPRESS_BLOCKED_INVITE", "the chat diagnostic suppresses direct invite output")
local chatTestLog = lastDebug("CHAT_TEST")
check(chatTestLog ~= nil, "the chat diagnostic logs its result")
equal(chatTestLog.data.output, "guarded", "the chat diagnostic reports guarded output")
check(chatTestLog.data.observed, "the chat diagnostic reports the observed guard")

local savedDefaultChatFrame = DEFAULT_CHAT_FRAME
local rawDiagnosticMessages = {}
DEFAULT_CHAT_FRAME = {
    AddMessage = function(self, message)
        rawDiagnosticMessages[#rawDiagnosticMessages + 1] = message
    end,
}
SanctuaryDB.debugLog = {}
local unguardedDiagnostic = ns.runChatDiagnostic("invite")
equal(unguardedDiagnostic.output, "unguarded", "chat diagnostic reports unguarded when wrapper is absent")
check(not unguardedDiagnostic.observed, "chat diagnostic does not fake observation when wrapper is absent")
equal(#rawDiagnosticMessages, 1, "unguarded chat diagnostic would print the probe message")
DEFAULT_CHAT_FRAME = savedDefaultChatFrame

-- The two sounds are separate buttons since 0.4.0: played inside one call, no
-- one could tell whether they had heard two sounds or one.
playedSounds = {}
SanctuaryDB.debugLog = {}
diagLine = ns.runDiagnosticById("diag_sound_open").text
check(diagLine:find("Diagnostic sound open", 1, true) ~= nil, "the window-open sound diagnostic names itself")
equal(#playedSounds, 1, "the window-open sound diagnostic plays exactly one sound")
equal(playedSounds[1], SOUNDKIT.IG_MAINMENU_OPEN, "and it is the native panel-open sound")

playedSounds = {}
SanctuaryDB.debugLog = {}
diagLine = ns.runDiagnosticById("diag_sound_invite").text
check(diagLine:find("Diagnostic sound invite", 1, true) ~= nil, "the invite sound diagnostic names itself")
equal(#playedSounds, 1, "the invite sound diagnostic plays exactly one sound")
equal(playedSounds[1], 880, "and it is the captured native party invite sound")
local soundTestLog = lastDebug("SOUND_TEST")
check(soundTestLog ~= nil, "the sound diagnostic logs its result")
equal(soundTestLog.data.sound, "880", "naming the sound it played")

playedSounds = {}
SanctuaryDB.debugLog = {}
diagLine = ns.runDiagnosticById("diag_popup_duel").text
runTimers()
check(diagLine:find("Diagnostic popup duel", 1, true) ~= nil, "the duel popup diagnostic names itself")
equal(#playedSounds, 0, "the duel popup diagnostic stays silent")
local popupTestLog = lastDebug("POPUP_TEST")
check(popupTestLog ~= nil, "the duel popup diagnostic logs its result")
equal(popupTestLog.data.which, "DUEL_REQUESTED", "the duel popup diagnostic logs the popup kind")
check(popupTestLog.data.hidden, "the duel popup diagnostic hides the dialog it opened")

playedSounds = {}
SanctuaryDB.debugLog = {}
local beforeDiagGuilds = declinedGuilds
diagLine = ns.runDiagnosticById("diag_popup_guild").text
runTimers()
check(diagLine:find("Diagnostic popup guild", 1, true) ~= nil, "the guild popup diagnostic names itself")
equal(#playedSounds, 0, "the guild popup diagnostic stays silent")
popupTestLog = lastDebug("POPUP_TEST")
check(popupTestLog ~= nil, "the guild popup diagnostic logs its result")
equal(popupTestLog.data.which, "GUILD_INVITE_FRAME", "the guild popup diagnostic logs the frame key")
equal(popupTestLog.data.frame, "GuildInviteFrame", "the guild popup diagnostic logs the frame kind")
equal(popupTestLog.data.reason, "guild_invite_frame_probe", "the guild popup diagnostic probes the special frame")
check(popupTestLog.data.masked, "the guild popup diagnostic masks the special frame")
check(popupTestLog.data.hidden, "the guild popup diagnostic hides the special frame")
equal(declinedGuilds, beforeDiagGuilds, "the guild popup diagnostic does not call the native decline")

SanctuaryDB.debugLog = {}
diagLine = ns.runDiagnosticById("diag_popup_list", "guild").text
check(diagLine:find("Diagnostic popup list guild", 1, true) ~= nil, "the popup list diagnostic names itself")
local popupListLog = lastDebug("POPUP_LIST")
check(popupListLog ~= nil, "the popup list diagnostic logs its result")
equal(popupListLog.data.query, "guild", "the popup list diagnostic logs the query")

-- The lockdown diagnostic answers what the masking predicate would decide now.
-- It writes a CHAT_TEST entry and nothing else: no CHAT_OUTPUT, so it can never
-- inflate the very markers a recording is graded on.
SanctuaryDB.debugLog = {}
local beforeLockdownLog = #SanctuaryDB.log
-- Strict mode ticked and no group: the last refusal of the predicate, and the
-- one the maintainer can actually reproduce alone on a trial account.
SanctuaryDB.filters.strictGroupInviteSystemMessages = true
diagLine = ns.runDiagnosticById("diag_chat_lockdown").text
check(diagLine:find("Diagnostic chat lockdown", 1, true) ~= nil, "the lockdown diagnostic names itself")
check(diagLine:find("armed=no", 1, true) ~= nil, "outside any group it is not armed")
check(diagLine:find("reason=no_context", 1, true) ~= nil, "and says which refusal it hit")
equal(#SanctuaryDB.log, beforeLockdownLog, "the lockdown diagnostic writes nothing to the block journal")
local lockdownLog = lastDebug("CHAT_TEST")
check(lockdownLog ~= nil, "the lockdown diagnostic logs a CHAT_TEST entry")
equal(lockdownLog.data.kind, "lockdown", "marked as the lockdown kind")
equal(lastDebug("CHAT_OUTPUT"), nil, "and never a CHAT_OUTPUT entry")
SanctuaryDB.filters.strictGroupInviteSystemMessages = false

showGuildInviteFrame("BusyGuild", "Busy Guild")
local busyGuildDiagnostic = ns.runPopupDiagnostic("guild")
check(busyGuildDiagnostic.skipped, "guild popup diagnostic skips an already visible frame")
equal(busyGuildDiagnostic.reason, "guild_invite_frame_busy", "guild popup diagnostic reports busy frame")
check(GuildInviteFrame:IsShown(), "guild popup diagnostic does not hide a busy frame")
hideGuildInviteFrameForCleanup()
runTimers()

-- /sanc has no sub-commands left: whatever is typed after it, the window opens
-- and nothing is printed.
local uiToggles = 0
local beforeSlashMessages = #chatMessages
ns.ToggleUI = function() uiToggles = uiToggles + 1 end
SlashCmdList["SANCTUARY"]("")
SlashCmdList["SANCTUARY"]("unknown")
SlashCmdList["SANCTUARY"]("diag sound blabla")
equal(uiToggles, 3, "every slash invocation opens the window")
equal(#chatMessages, beforeSlashMessages, "and none of them prints anything")
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

-- Filter registration is retried on PLAYER_ENTERING_WORLD so a client that
-- exposed no registry at load can still be picked up later. The retry must stay
-- idempotent: once registered, a further attempt registers nothing again.
local registrationsBeforeRetry = chatFilterRegistrations
local systemFilterBeforeRetry = chatFilters.CHAT_MSG_SYSTEM
fire("PLAYER_ENTERING_WORLD")
runTimers()
equal(chatFilterRegistrations, registrationsBeforeRetry, "registration retry does not register the filters twice")
equal(chatFilters.CHAT_MSG_SYSTEM, systemFilterBeforeRetry, "registration retry keeps the registered system filter")
check(chatFilters.CHAT_MSG_BN_WHISPER ~= nil, "registration retry keeps the registered BNet filter")

-- ---------------------------------------------------------------------------
-- Debug report rendering
-- ---------------------------------------------------------------------------

-- Model of the client's markup rendering, restricted to the sequences a debug
-- report can carry. What the maintainer copies out of the export EditBox is this
-- rendered text, not the raw buffer, which is why report values are escaped
-- instead of merely displayed.
local function renderClientMarkup(text)
    local out = {}
    local i = 1
    while i <= #text do
        local char = text:sub(i, i)
        if char ~= "|" then
            out[#out + 1] = char
            i = i + 1
        else
            local nextChar = text:sub(i + 1, i + 1)
            if nextChar == "|" then
                out[#out + 1] = "|"
                i = i + 2
            elseif nextChar == "c" then
                i = i + 10
            elseif nextChar == "K" or nextChar == "H" or nextChar == "T" or nextChar == "A" then
                local closeAt = text:find("|" .. nextChar:lower(), i + 2, true)
                i = closeAt and (closeAt + 2) or (#text + 1)
            elseif nextChar == "r" or nextChar == "h" or nextChar == "t"
                or nextChar == "k" or nextChar == "a" or nextChar == "n" then
                i = i + 2
            else
                -- Not a control sequence: the field separators of the report
                -- itself are rendered literally, as the reported export shows.
                out[#out + 1] = "|"
                i = i + 1
            end
        end
    end
    return table.concat(out)
end

-- The model must reproduce the loss seen in the 2026-08-20 export, otherwise it
-- proves nothing: unescaped, the invite global rendered as "[%s]" alone and the
-- name substitution rendered as nothing at all.
equal(renderClientMarkup("|Hplayer:%s|h[%s]|h"), "[%s]",
    "markup model reproduces the hyperlink loss seen in the reported export")
equal(renderClientMarkup("normalized=|Kq2|k | reason=ok"), "normalized= | reason=ok",
    "markup model reproduces the name substitution loss seen in the reported export")

for _, raw in ipairs({
    "|Kq2|k",
    "|Hplayer:Someone|h[Someone]|h vous a invite",
    "|cFFFF0000red|r",
    "|TInterface\\Icons\\x:0|t",
    "plain | separator",
    "^%[(.+)%] a|b",
}) do
    equal(renderClientMarkup(ns.escapeExportText(raw)), raw,
        "escaped report value survives client rendering: " .. raw)
end

SanctuaryDB.debugEnabled = true
SanctuaryDB.logging.maxEntries = 5000
ns.resetDebugLog()
ns.debugLog("CHAT_DECISION", { action = "BLOCK", source = "SanctuaryBNetTest" })
ns.debugLog("CHAT_DECISION", { action = "ALLOW", normalized = "|Kq2|k", reason = "bnet_whitelist" })
local report = ns.buildDebugReportText()
local renderedReport = renderClientMarkup(report)
equal(select(2, renderedReport:gsub("CHAT_DECISION", "")), 2,
    "escaped report keeps both entries after client rendering")
check(renderedReport:find("source=SanctuaryBNetTest", 1, true) ~= nil,
    "escaped report keeps the entry preceding a name substitution")
check(renderedReport:find("normalized=|Kq2|k", 1, true) ~= nil,
    "escaped report restores the raw name substitution")

-- Globals and patterns go through the same escaping: the 2026-08-20 export lost
-- the hyperlink part of ERR_INVITED_TO_GROUP_SS and showed only "[%s]".
ERR_INVITED_TO_GROUP_SS = "|Hplayer:%s|h[%s]|h vous a invite a rejoindre un groupe."
report = ns.buildDebugReportText()
check(renderClientMarkup(report):find("|Hplayer:%s|h[%s]|h", 1, true) ~= nil,
    "escaped report restores the raw invite global")
ERR_INVITED_TO_GROUP_SS = nil

-- ---------------------------------------------------------------------------
-- Debug log retention accounting
-- ---------------------------------------------------------------------------

SanctuaryDB.logging.maxEntries = 3
ns.resetDebugLog()
for i = 1, 5 do
    ns.debugLog("FILLER", { index = i })
end
local debugStats = ns.getDebugLogStats()
equal(#SanctuaryDB.debugLog, 3, "debug log rotation keeps the retention limit")
equal(debugStats.produced, 5, "debug log counts every produced entry")
equal(debugStats.dropped, 2, "debug log counts the entries dropped by rotation")
equal(SanctuaryDB.debugLog[1].seq, 3, "sequence numbers stay unique after rotation")
-- The counters live in SavedVariables, so the numbering survives a UI reload:
-- the log is not cleared by a reload either, and a restarted counter made two
-- entries share a number.
check(SanctuaryDB.debugLogStats == debugStats, "retention counters are stored in SavedVariables")
report = ns.buildDebugReportText()
check(report:find("3 kept / 5 produced / 2 dropped", 1, true) ~= nil,
    "report header states kept, produced and dropped counts")
check(report:find("!!! TRUNCATED", 1, true) ~= nil, "report warns explicitly about truncation")

-- A log recorded by a build without this accounting must not have its existing
-- entries renumbered from 1 when the counters appear.
SanctuaryDB.debugLogStats = nil
SanctuaryDB.debugLog = {
    { seq = 1, ts = "00:00:01", cat = "OLD", data = {} },
    { seq = 2, ts = "00:00:02", cat = "OLD", data = {} },
}
ns.debugLog("MIGRATED", {})
equal(SanctuaryDB.debugLog[3].seq, 3, "existing entries keep their numbers when accounting is introduced")

ns.resetDebugLog()
equal(ns.getDebugLogStats().produced, 0, "clearing the debug log resets the produced counter")
equal(ns.getDebugLogStats().dropped, 0, "clearing the debug log resets the dropped counter")
report = ns.buildDebugReportText()
check(report:find("!!! TRUNCATED", 1, true) == nil, "an untruncated report carries no truncation warning")
SanctuaryDB.logging.maxEntries = 5000

-- ---------------------------------------------------------------------------
-- Snapshot counters that are not ready yet
-- ---------------------------------------------------------------------------

local realGetNumFriends = C_FriendList.GetNumFriends
C_FriendList.GetNumFriends = function() return nil end
ns.resetDebugLog()
ns.captureDebugSnapshot()
local snapshot = lastDebug("SNAPSHOT")
check(snapshot ~= nil, "snapshot captured while the friend list is still loading")
equal(snapshot.data.charFriends, "unavailable",
    "an unloaded friend counter is reported instead of dropping the key")

C_FriendList.GetNumFriends = function() error("api unavailable") end
ns.resetDebugLog()
ns.captureDebugSnapshot()
snapshot = lastDebug("SNAPSHOT")
equal(snapshot.data.charFriends, "error", "a failing friend counter is reported as an error")
C_FriendList.GetNumFriends = realGetNumFriends

ns.resetDebugLog()
ns.captureDebugSnapshot()
snapshot = lastDebug("SNAPSHOT")
equal(snapshot.data.charFriends, 0, "a loaded friend counter is still reported as a number")

-- ---------------------------------------------------------------------------
-- Protected popup sound guard: the files must end up unmuted
-- ---------------------------------------------------------------------------

-- A mute posted by MuteSoundFile survives /reload and relogging, so a failed
-- unmute is not a transient glitch: it silences the game's generic panel sounds
-- until the client is restarted. The release path has to retry.
SanctuaryDB.debugEnabled = true
ns.resetDebugLog()
playedSounds = {}
unmuteFailuresLeft = 2   -- both files fail once on the first release attempt
fire("GUILD_INVITE_REQUEST", "Guildbad", "Bad Guild")
showGuildInviteFrame("Guildbad", "Bad Guild")
check(mutedSoundFiles[567490], "a failed unmute leaves the popup-open file muted for now")
check(mutedSoundFiles[567464], "a failed unmute leaves the popup-close file muted for now")
local guardOff = lastDebug("SOUND", "POPUP_GUARD_OFF")
check(guardOff ~= nil, "the release is still logged when the unmute fails")
equal(guardOff and guardOff.data.failures, 2, "the release reports how many unmutes failed")
equal(guardOff and guardOff.data.stillMuted, 2, "the release reports how many files stay muted")
runTimers(6)
check(not mutedSoundFiles[567490], "the bounded retry unmutes the popup-open file")
check(not mutedSoundFiles[567464], "the bounded retry unmutes the popup-close file")
local retry = lastDebug("SOUND", "POPUP_GUARD_UNMUTE_RETRY")
check(retry ~= nil, "the retry is logged")
equal(retry and retry.data.stillMuted, 0, "the retry reports the files as unmuted")
equal(SanctuaryDB.protectedPopupSoundMuted, nil, "a successful retry clears the persisted mute flag")
hideGuildInviteFrameForCleanup()
runTimers(6)

-- The retry is bounded: it gives up, says so in the log, and tells the person
-- once -- staying silent would leave them with degraded audio and nothing to act
-- on, since neither a reload nor a relog clears it.
ns.resetDebugLog()
local messagesBeforeAbandon = #chatMessages
unmuteFailuresLeft = 1000
fire("GUILD_INVITE_REQUEST", "Guildbad", "Bad Guild")
showGuildInviteFrame("Guildbad", "Bad Guild")
runTimers(12)
local abandoned = lastDebug("SOUND", "POPUP_GUARD_UNMUTE_ABANDONED")
check(abandoned ~= nil, "the bounded retry logs that it gave up")
equal(abandoned and abandoned.data.stillMuted, 2, "the abandon entry says what is still muted")
equal(#chatMessages, messagesBeforeAbandon + 1, "giving up warns the person exactly once")
check(chatMessages[#chatMessages]:find("Sanctuary", 1, true) ~= nil, "the warning is attributable to the addon")
check(SanctuaryDB.protectedPopupSoundMuted, "an abandoned unmute stays recorded in SavedVariables")

-- That recorded flag is what the next load acts on: the mute outlived the code
-- that posted it, and no guard can be active at load.
unmuteFailuresLeft = 0
hideGuildInviteFrameForCleanup()
runTimers(6)
ns.resetDebugLog()
mutedSoundFiles[567490] = true
mutedSoundFiles[567464] = true
SanctuaryDB.protectedPopupSoundMuted = true
fire("ADDON_LOADED", "Sanctuary")
local staleUnmute = lastDebug("SOUND", "POPUP_GUARD_STALE_UNMUTE")
check(staleUnmute ~= nil, "a mute left by a previous session is logged at load")
equal(staleUnmute and staleUnmute.data.stillMuted, 0, "a mute left by a previous session is lifted at load")
check(not mutedSoundFiles[567490], "the stale popup-open mute is lifted at load")
check(not mutedSoundFiles[567464], "the stale popup-close mute is lifted at load")
equal(SanctuaryDB.protectedPopupSoundMuted, nil, "lifting a stale mute clears the flag")
runTimers(6)

-- ---------------------------------------------------------------------------
-- Retention accounting: a legacy log that already rotated
-- ---------------------------------------------------------------------------

-- Counting the kept entries is not enough. A log inherited from a build without
-- accounting can already have rotated, so it holds fewer entries than the
-- numbers it carries, and calibrating on the count reissues numbers that are
-- already in the report.
SanctuaryDB.logging.maxEntries = 5000
SanctuaryDB.debugLogStats = nil
SanctuaryDB.debugLog = {}
for i = 201, 5200 do
    SanctuaryDB.debugLog[#SanctuaryDB.debugLog + 1] =
        { seq = i, ts = "00:00:00", cat = "LEGACY", data = {} }
end
-- The dropped count cannot be reconstructed for a legacy log, but reporting it
-- as zero would publish an impossible header -- 5000 kept out of 5200 produced,
-- 200 unaccounted for, and no truncation warning. A lower bound is honest.
equal(ns.getDebugLogStats().dropped, 200,
    "a rotated legacy log reports at least the entries missing from it")
report = ns.buildDebugReportText()
check(report:find("!!! TRUNCATED", 1, true) ~= nil,
    "a rotated legacy log is flagged as truncated")
ns.debugLog("AFTER_MIGRATION", {})
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].seq, 5201,
    "a rotated legacy log keeps numbering above its highest entry")
equal(ns.getDebugLogStats().produced, 5201,
    "the produced counter resumes above the highest number already issued")
equal(ns.getDebugLogStats().produced - #SanctuaryDB.debugLog, ns.getDebugLogStats().dropped,
    "kept plus dropped accounts for every produced entry")
ns.resetDebugLog()
SanctuaryDB.logging.maxEntries = 5000

-- ---------------------------------------------------------------------------
-- Export snapshot when debug mode is off
-- ---------------------------------------------------------------------------

-- Unticking debug mode keeps the log, so "play, untick, export later" is a
-- normal path. The report has to describe the state it reports on.
SanctuaryDB.debugEnabled = false
ns.resetDebugLog()
ns.captureDebugSnapshot("load")
equal(#SanctuaryDB.debugLog, 0, "a load snapshot stays gated on the debug checkbox")
ns.captureDebugSnapshot("export")
equal(#SanctuaryDB.debugLog, 1, "the export captures a snapshot even when debug mode is off")
snapshot = lastDebug("SNAPSHOT")
equal(snapshot and snapshot.data.trigger, "export", "the export snapshot says the export wrote it")
equal(snapshot and snapshot.data.debugEnabled, false, "the export snapshot records that debug mode was off")
report = ns.buildDebugReportText()
check(report:find("DebugEnabled: false", 1, true) ~= nil,
    "the report states that debug mode was off when it was produced")
SanctuaryDB.debugEnabled = true
ns.resetDebugLog()
ns.captureDebugSnapshot("export")
snapshot = lastDebug("SNAPSHOT")
equal(snapshot and snapshot.data.debugEnabled, true, "the export snapshot records debug mode when it is on")
ns.resetDebugLog()


-- The main chunk is at Lua's 200-local ceiling, so everything added below runs
-- inside a function: it gets its own register budget and reaches the harness
-- helpers as upvalues.
;(function()

-- ===========================================================================
-- SECTION: Diagnostic catalogue (debug panel)
-- ===========================================================================

-- The panel is a rendering of this table. Checking the table is what makes the
-- panel checkable without a game client, and it is what a checklist step now
-- reduces to.
SanctuaryDB.debugEnabled = true
ns.resetDebugLog()

check(type(ns.DIAGNOSTIC_CATALOG) == "table" and #ns.DIAGNOSTIC_CATALOG > 0,
    "the diagnostic catalogue is exported")

local catalogIds = {}
for _, entry in ipairs(ns.DIAGNOSTIC_CATALOG) do
    equal(catalogIds[entry.id], nil, "catalogue id is unique: " .. tostring(entry.id))
    catalogIds[entry.id] = true
    check(type(entry.labelKey) == "string" and type(ns.L[entry.labelKey]) == "string"
        and ns.L[entry.labelKey] ~= "",
        "catalogue entry " .. tostring(entry.id) .. " has a label")
    check(type(entry.run) == "function",
        "catalogue entry " .. tostring(entry.id) .. " is runnable")
end

-- Every diagnostic of the old checklist has a button, the group invitation
-- window -- which had no command at all and was reached through a raw /run --
-- has one too, and so does the lockdown probe that used to be a slash command.
-- No entry names a command any more: there are none left to name.
for _, id in ipairs({ "sim_invite", "sim_bnet", "sim_bnetfriend", "diag_chat",
    "diag_chat_lockdown", "diag_sound_open", "diag_sound_invite",
    "diag_popup_invite", "diag_popup_duel", "diag_popup_guild",
    "diag_popup_list" }) do
    check(ns.getDiagnosticEntry(id) ~= nil, "catalogue covers " .. id)
    equal(ns.getDiagnosticEntry(id).command, nil,
        "catalogue entry " .. id .. " carries no command to type")
end

local unknown = ns.runDiagnosticById("no_such_diagnostic")
check(unknown.failed == true, "an unknown diagnostic id reports a failure")
check(unknown.text ~= "" and unknown.text:find("no_such_diagnostic", 1, true) ~= nil,
    "an unknown diagnostic names what was asked for")

-- A diagnostic that throws must still produce a line in the panel: swallowing
-- it into the error handler is how a checklist step silently passes.
local brokenEntry = { id = "broken", labelKey = "DIAG_SIM_INVITE",
    run = function() error("boom") end }
table.insert(ns.DIAGNOSTIC_CATALOG, brokenEntry)
local broken = ns.runDiagnosticById("broken")
check(broken.failed == true, "a diagnostic that throws is reported, not swallowed")
check(broken.text:find("broken", 1, true) ~= nil, "the failure names the diagnostic")
table.remove(ns.DIAGNOSTIC_CATALOG)

-- Each catalogued diagnostic returns a line. This is the automated form of the
-- twelve command steps the maintainer used to type one by one.
for _, entry in ipairs(ns.DIAGNOSTIC_CATALOG) do
    local result = ns.runDiagnosticById(entry.id, entry.argDefault)
    check(type(result.text) == "string" and result.text ~= "",
        "diagnostic " .. entry.id .. " returns a readable line")
    equal(result.failed, nil, "diagnostic " .. entry.id .. " runs without error")
end

-- The group invitation popup: masked, then put back. The old step left it on
-- screen, invisible and clickable, until a /reload -- that is what disappears.
ns.resetDebugLog()
local inviteResult = ns.runDiagnosticById("diag_popup_invite")
check(inviteResult.text:find("shown=yes", 1, true) ~= nil,
    "the invite popup diagnostic shows the dialog")
check(inviteResult.text:find("masked=yes", 1, true) ~= nil,
    "the invite popup diagnostic observes the mask")
check(inviteResult.text:find("hidden=yes", 1, true) ~= nil,
    "the invite popup diagnostic closes the dialog it opened")
equal(inviteResult.leftOnScreen, false,
    "a popup diagnostic that closed its dialog leaves nothing on screen")
equal(StaticPopup1:IsShown(), false, "no dialog survives the invite popup diagnostic")
local maskEntry = lastDebug("POPUP", "MASK_AWAITING_EVENT")
check(maskEntry ~= nil, "the invite popup diagnostic records the mask it produced")
equal(maskEntry and maskEntry.data.affected, 1,
    "the recorded mask reports the dialog it covered")

-- ... and when it cannot close it, it says so, which is what the panel turns
-- into a way back instead of a rule to remember.
local savedHide = StaticPopup1.Hide
StaticPopup1.Hide = nil
local strandedResult = ns.runDiagnosticById("diag_popup_duel")
equal(strandedResult.leftOnScreen, true,
    "a popup diagnostic that could not close its dialog reports it")
StaticPopup1.Hide = savedHide
StaticPopup1:Hide()

-- Retail's PARTY_INVITE OnHide declines the group when `inviteAccepted` is nil.
-- A probe that closes its own dialog with a raw Hide would therefore call the
-- native decline -- and an invitation the server already had pending would be
-- refused by a diagnostic. The guild probe was already checked for this; the
-- invite probe was not, and did it.
local beforeDiagDeclines = declinedGroups
ns.resetDebugLog()
playedSounds = {}
local declineProbe = ns.runDiagnosticById("diag_popup_invite")
check(declineProbe.text:find("hidden=yes", 1, true) ~= nil,
    "the invite probe still closes the dialog it opened")
equal(declinedGroups, beforeDiagDeclines,
    "and closes it without calling the native decline")
equal(#playedSounds, 0, "and without making a sound")

-- The dangerous shape is not a missing Hide, it is a Hide that exists and does
-- nothing: the dialog stays up at alpha 0, invisible and clickable, while the
-- diagnostic claims it closed it. `hidden` is therefore read back off the
-- screen, never deduced from the call.
StaticPopup1.Hide = function() end
local silentlyStranded = ns.runDiagnosticById("diag_popup_invite")
equal(silentlyStranded.leftOnScreen, true,
    "a Hide that exists but does nothing is still a popup left on screen")
check(silentlyStranded.text:find("hidden=no", 1, true) ~= nil,
    "and the line says hidden=no rather than claiming success")
StaticPopup1.Hide = savedHide
StaticPopup1:Hide()

-- Running the probe over a real pending request would close it without
-- accepting or declining it: StaticPopup_Show reuses the slot of the same
-- `which`. The guild path already refused; this one does too now.
StaticPopup_Show("PARTY_INVITE", "RealInviter")
local busyResult = ns.runDiagnosticById("diag_popup_invite")
check(busyResult.text:find("SKIP (popup_busy)", 1, true) ~= nil,
    "the invite probe refuses to run over a pending request")
equal(busyResult.leftOnScreen, false, "a refused probe leaves nothing behind")
equal(StaticPopup1:IsShown(), true, "and the pending request is still there")
equal(StaticPopup1.which, "PARTY_INVITE", "untouched, on its own slot")
StaticPopup1:Hide()
runTimers()

-- ===========================================================================
-- SECTION: Whitelist readback
-- ===========================================================================

wipe(SanctuaryDB.manualWhitelist)
SanctuaryDB.keywords = { "spammer" }
inGroup, inRaid = false, false
groupMembers = {}
guildMembers = { "Guildmate-TestRealm", "Officer-TestRealm" }
inGuild = true
charFriends = { "Buddy-TestRealm" }
bnetFriends = {
    { accountName = "RealFriend#1234", bnetAccountID = 77,
      gameAccountInfo = { characterName = "Bnetchar" } },
}
SanctuaryDB.manualWhitelist["typedname"] = { displayName = "TypedName", addedAt = 1, source = "manual" }
-- Someone both typed in and in the guild keeps the label they were typed under:
-- the manual list is the one the maintainer can act on.
SanctuaryDB.manualWhitelist["guildmate"] = { displayName = "Guildmate", addedAt = 1, source = "manual" }
ns.invalidateWhitelist()

local groups = ns.getAutoWhitelistGroups()
local groupBySource = {}
for _, group in ipairs(groups) do groupBySource[group.source] = group end
equal(#groups, #ns.AUTO_WHITELIST_SOURCES, "the automatic section has one group per trust source")
equal(groupBySource.guild.total, 1, "a guild member typed in by hand is not counted twice")
equal(groupBySource.guild.entries[1].label, "Officer-TestRealm", "guild members are listed by name")
equal(groupBySource.friend.total, 1, "character friends are grouped on their own")
equal(groupBySource.bnet.total, 1, "Battle.net friends are listed once, by account")
equal(groupBySource.bnet.entries[1].label, "RealFriend#1234",
    "a Battle.net friend is listed under the account the decision is made on")
equal(groupBySource.group.total, 0, "an empty trust source reports zero rather than vanishing")

-- Reading is what refreshes: no button, no timer. This is the whole reason the
-- tab needs neither.
guildMembers = { "Guildmate-TestRealm", "Officer-TestRealm", "Newcomer-TestRealm" }
equal(#ns.getAutoWhitelistGroups()[1].entries, 1,
    "a roster change nobody announced does not appear on its own")
fire("GUILD_ROSTER_UPDATE")
groups = ns.getAutoWhitelistGroups()
for _, group in ipairs(groups) do groupBySource[group.source] = group end
equal(groupBySource.guild.total, 2,
    "opening the list after an invalidation is enough to rebuild it")

-- Volume: 56 accounts are four count lines until asked for, and searchable.
local manyFriends = {}
for i = 1, 56 do
    manyFriends[i] = { accountName = string.format("Friend%02d#%04d", i, 1000 + i),
        bnetAccountID = 1000 + i }
end
bnetFriends = manyFriends
fire("BN_FRIEND_INFO_CHANGED")
groups = ns.getAutoWhitelistGroups()
for _, group in ipairs(groups) do groupBySource[group.source] = group end
equal(groupBySource.bnet.total, 56, "the whole Battle.net list is counted")
equal(#groupBySource.bnet.entries, 56, "an unfiltered group offers every entry")
local filtered = ns.getAutoWhitelistGroups("friend07")
for _, group in ipairs(filtered) do groupBySource[group.source] = group end
equal(#groupBySource.bnet.entries, 1, "a search narrows a group to its matches")
equal(groupBySource.bnet.total, 56, "a search reports how many entries it narrowed from")
equal(#ns.getAutoWhitelistGroups("nobodyhere")[1].entries, 0,
    "a search that matches nothing returns nothing rather than everything")

-- "Test a name" -- the same decision, not a second one. Since 0.4.0 it answers
-- in three tiers, and the eight answers of the validated board are exactly the
-- eight cases below.
local verdict = ns.describeAccessDecision("Officer-TestRealm")
equal(verdict.verdict, "always_allowed", "a guild member is always allowed")
equal(verdict.list, "guild", "and the tester can say which list")
verdict = ns.describeAccessDecision("TypedName")
equal(verdict.list, "manual", "a name typed in by hand is labelled as such")
verdict = ns.describeAccessDecision("Buddy")
equal(verdict.list, "friend", "a friend is labelled as a friend")
verdict = ns.describeAccessDecision("Nobody")
equal(verdict.verdict, "unknown", "a stranger falls in no list")
equal(verdict.blockedNow, true, "and is blocked while question 1 filters strangers")
verdict = ns.describeAccessDecision("Spammerguy")
equal(verdict.verdict, "always_blocked", "a pattern still overrides every trust source")
equal(verdict.list, "keyword", "a pattern match is reported as such")
equal(verdict.detail, "spammer", "the matching pattern is named")
equal(ns.describeAccessDecision("").valid, false, "an empty field asks nothing")
equal(ns.describeAccessDecision("|cFFFFFFFF|r").valid, false, "a name made of formatting is refused")

-- A Battle.net friend is answered on the account, whichever half is typed.
verdict = ns.describeAccessDecision("Friend07#1007")
equal(verdict.verdict, "always_allowed", "a Battle.net tag is answered on the account")
equal(verdict.list, "bnet", "and named as a Battle.net friend")

-- Question 1 in the other mode: the same unknown name, the other answer.
SanctuaryDB.filters.scope = "blockedOnly"
verdict = ns.describeAccessDecision("Nobody")
equal(verdict.verdict, "unknown", "an unknown name is still unknown")
equal(verdict.blockedNow, false, "but nothing blocks it when only blocked names are filtered")
equal(verdict.scope, "blockedOnly", "and the answer says which mode it was given in")
SanctuaryDB.filters.scope = "strangers"

-- The blocked list beats the allowed one, and the answer says so rather than
-- silently dropping the entry the person typed.
ns.addBlocked("Officer-TestRealm")
verdict = ns.describeAccessDecision("Officer-TestRealm")
equal(verdict.verdict, "always_blocked", "a blocked name beats a trust source")
equal(verdict.list, "blocked_name", "named as an exact blocked name")
equal(verdict.overriddenList, "guild", "and the answer still names the list it overrides")
ns.removeBlocked(ns.normalizeBlockedKey("Officer-TestRealm"))

wipe(SanctuaryDB.manualWhitelist)
SanctuaryDB.keywords = {}
guildMembers = {}
charFriends = {}
bnetFriends = {}
inGuild = false
ns.invalidateWhitelist()

-- ===========================================================================
-- SECTION: Report markers, manifest and in-game summary
-- ===========================================================================

-- The five things the closing step used to look for by scrolling the exported
-- text by hand.
local emptyMarkers = ns.getReportMarkers({})
equal(emptyMarkers.chatOutputNoMatch, false, "an empty log carries no marker")
equal(emptyMarkers.snapshots, 0, "an empty log has no snapshot")
equal(select(1, ns.getInstrumentationVerdict(emptyMarkers)), "unknown",
    "a log without a snapshot cannot be graded")

local syntheticLog = {
    { seq = 1, cat = "SNAPSHOT", data = { chatFilterApiUsed = "none", chatFramesSeen = 10,
        chatFramesWrapped = 0, systemChatTypeID = "unknown" } },
    { seq = 2, cat = "CHAT_OUTPUT", data = { action = "NO_MATCH" } },
    { seq = 3, cat = "POPUP", data = { action = "MASK_AWAITING_EVENT", affected = 1 } },
    { seq = 4, cat = "WORLD", data = { inInstance = true, instanceType = "party" } },
    { seq = 5, cat = "PLAYER_STATE", data = { event = "PLAYER_DEAD" } },
    { seq = 5.5, cat = "PLAYER_STATE", data = { event = "PLAYER_UNGHOST" } },
    -- The catch-up the checklist warns about: a later snapshot supersedes an
    -- earlier failure, and only the last one describes how the session ended.
    { seq = 6, cat = "SNAPSHOT", data = { chatFilterApiUsed = "legacy", chatFramesSeen = 10,
        chatFramesWrapped = 10, systemChatTypeID = 90 } },
}
local markers = ns.getReportMarkers(syntheticLog)
equal(markers.chatOutputNoMatch, true, "the chat marker is found")
equal(markers.popupMaskAwaitingEvent, true, "the popup marker is found")
equal(markers.worldInInstance, true, "the instance marker is found")
equal(markers.playerState, true, "the death marker is found")
equal(markers.snapshots, 2, "every snapshot is counted")
equal(markers.chatFilterApiUsed, "legacy", "the last snapshot wins")
equal(select(1, ns.getInstrumentationVerdict(markers)), "ok",
    "a session that caught up is exploitable")

-- The scenario is "die, stay a ghost, resurrect", and it takes both halves.
equal(ns.getReportMarkers({
    { seq = 1, cat = "PLAYER_STATE", data = { event = "PLAYER_ALIVE" } },
    { seq = 2, cat = "PLAYER_STATE", data = { event = "PLAYER_UNGHOST" } },
}).playerState, false, "coming back alive is not proof of having died")
equal(ns.getReportMarkers({
    { seq = 1, cat = "PLAYER_STATE", data = { event = "PLAYER_DEAD" } },
}).playerState, false, "and a death with no return is only half the scenario")
local halfDeath = ns.getReportMarkers({
    { seq = 1, cat = "PLAYER_STATE", data = { event = "PLAYER_DEAD" } },
})
equal(halfDeath.playerDied, true, "the death half is reported on its own")
equal(halfDeath.playerRevived, false, "so the missing half can be named")
equal(ns.getReportMarkers({
    { seq = 1, cat = "PLAYER_STATE", data = { event = "PLAYER_DEAD" } },
    { seq = 2, cat = "PLAYER_STATE", data = { event = "PLAYER_ALIVE" } },
}).playerState, true, "death then return is the scenario")
-- The revival that fires at login cannot stand in for the one that follows the
-- death: order is what separates them.
equal(ns.getReportMarkers({
    { seq = 1, cat = "PLAYER_STATE", data = { event = "PLAYER_ALIVE" } },
    { seq = 2, cat = "PLAYER_STATE", data = { event = "PLAYER_DEAD" } },
}).playerState, false, "a return recorded before the death does not count")

-- A mask that covered nothing is not the marker the step is looking for.
equal(ns.getReportMarkers({
    { seq = 1, cat = "POPUP", data = { action = "MASK_AWAITING_EVENT", affected = 0 } },
}).popupMaskAwaitingEvent, false, "a mask that covered no dialog is not counted")

equal(select(1, ns.getInstrumentationVerdict({ chatFilterApiUsed = "unregistered" })), "blocking",
    "a session that registered no filter is graded blocking")
equal(select(1, ns.getInstrumentationVerdict({ chatFilterApiUsed = "none" })), "blocking",
    "a session with no filter API at all is graded blocking")
equal(select(1, ns.getInstrumentationVerdict({ chatFilterApiUsed = "legacy",
    chatFramesSeen = 10, chatFramesWrapped = 4, systemChatTypeID = 90 })), "degraded",
    "a partially observed chat is graded degraded, not blocking")
equal(select(1, ns.getInstrumentationVerdict({ chatFilterApiUsed = "legacy",
    chatFramesSeen = 10, chatFramesWrapped = 10, systemChatTypeID = "unknown" })), "degraded",
    "an unreadable system message type is graded degraded")

-- The settings file is the record, so it has to say which build wrote it. The
-- text export was the only place that identity existed -- and it is exactly the
-- piece that turned out to be unreliable.
SanctuaryDB.reportManifest = nil
fire("PLAYER_LOGOUT")
local manifest = SanctuaryDB.reportManifest
check(type(manifest) == "table", "logging out stamps a manifest into the settings file")
equal(manifest.trigger, "logout", "the manifest says what wrote it")
equal(manifest.build, "20260820-8", "the manifest carries the build id")
equal(manifest.version, ns.VERSION, "the manifest carries the addon version")
check(manifest.savedAt ~= nil and manifest.savedAt ~= "", "the manifest is dated")
-- The log is the record and nothing clears it on its own. When it was last
-- started for a fresh run travels with the file, so a closing check can say
-- whether it may still hold an earlier passage.
check(SanctuaryDB.debugLogClearedAt ~= nil, "clearing the debug log is dated")
equal(manifest.debugLogClearedAt, SanctuaryDB.debugLogClearedAt,
    "and the manifest carries that date")
check(manifest.verdict ~= nil, "the manifest carries the instrumentation verdict")

-- A settings file has to identify its build even when nothing was recorded.
SanctuaryDB.debugEnabled = false
SanctuaryDB.reportManifest = nil
ns.captureReportManifest("load")
check(type(SanctuaryDB.reportManifest) == "table",
    "the manifest is written even when debug mode is off")
equal(SanctuaryDB.reportManifest.debugEnabled, false,
    "and it says that nothing was being recorded")
SanctuaryDB.debugEnabled = true

-- The summary window: the two questions it is really opened for, and short
-- enough that a rendering defect cannot hide inside it.
ns.resetDebugLog()
ns.captureDebugSnapshot("export")
local summary = ns.buildDebugSummaryText()
check(summary:find("20260820-8", 1, true) ~= nil, "the summary names the build")
check(summary:find("Version: " .. ns.VERSION, 1, true) ~= nil, "the summary names the version")
check(summary:find("ChatFilterApi:", 1, true) ~= nil, "the summary reports the filter API")
check(summary:find("ChatFrames:", 1, true) ~= nil, "the summary reports the observed chat frames")
check(summary:find("SystemChatTypeID:", 1, true) ~= nil, "the summary reports the system message type")
check(summary:find("Verdict:", 1, true) ~= nil, "the summary grades the instrumentation")
check(summary:find("Marqueurs:", 1, true) ~= nil, "the summary reports the five markers")
check(summary:find("SavedVariables/Sanctuary.lua", 1, true) ~= nil,
    "the summary says where the actual record is")
check(#summary < 2000,
    "the summary stays short enough to read on screen (" .. #summary .. " chars)")
check(#ns.buildDebugReportText() > #summary,
    "the full report is still available and is the larger of the two")

-- ---------------------------------------------------------------------------
-- The summary tested on its values, not on its shape
-- ---------------------------------------------------------------------------

-- Every check above asserts that a line EXISTS. None asserts where what it
-- shows comes from, so nine of the ten lines accepted being replaced by a
-- constant without a single assertion falling -- the four marker fields
-- included, which means the summary could have said "no scenario recorded"
-- right after the harness played them all, silently.
--
-- This is the screen the maintainer reads before logging out, to decide whether
-- the session left a trace. One that always says "oui" would send them away on
-- an empty recording.
--
-- The rule below is the one that already anchored `Verdict:`: play the
-- scenarios, then assert the line carries the value that state implies. A
-- constant substituted for any of them makes one of these fall.
SanctuaryDB.debugEnabled = true
ns.resetDebugLog()
ns.debugLog("CHAT_OUTPUT", { action = "NO_MATCH" })
ns.debugLog("POPUP", { action = "MASK_AWAITING_EVENT", affected = 1 })
ns.debugLog("WORLD", { inInstance = true })
ns.debugLog("PLAYER_STATE", { event = "PLAYER_DEAD" })
ns.debugLog("PLAYER_STATE", { event = "PLAYER_ALIVE" })
ns.captureDebugSnapshot("export")

local playedSummary = ns.buildDebugSummaryText()
local playedMarkers = ns.getReportMarkers()
equal(playedMarkers.chatOutputNoMatch, true, "the harness really played the chat scenario")
equal(playedMarkers.playerState, true, "and the death scenario")

-- The four marker fields, each against the state that was actually recorded.
check(playedSummary:find("chat=oui", 1, true) ~= nil,
    "the summary says the chat scenario was recorded, because it was")
check(playedSummary:find("popup=oui", 1, true) ~= nil,
    "the summary says the popup scenario was recorded, because it was")
check(playedSummary:find("instance=oui", 1, true) ~= nil,
    "the summary says the instance scenario was recorded, because it was")
check(playedSummary:find("mort=oui", 1, true) ~= nil,
    "the summary says the death scenario was recorded, because it was")
check(playedSummary:find("snapshots=" .. tostring(playedMarkers.snapshots), 1, true) ~= nil,
    "and counts the snapshots the log actually holds")

-- The same four, from the other side: a log where nothing was played must not
-- claim it was. A constant "oui" passes the block above and fails here.
ns.resetDebugLog()
ns.captureDebugSnapshot("export")
local emptySummary = ns.buildDebugSummaryText()
check(emptySummary:find("chat=NON", 1, true) ~= nil,
    "an empty recording is not reported as having a chat scenario")
check(emptySummary:find("popup=NON", 1, true) ~= nil,
    "nor a popup one")
check(emptySummary:find("instance=NON", 1, true) ~= nil,
    "nor an instance one")
check(emptySummary:find("mort=NON", 1, true) ~= nil,
    "nor a death")

-- The six remaining lines, each against the value its source holds.
local liveHealth = ns.getInstrumentationHealth()
local liveManifest = SanctuaryDB.reportManifest
check(emptySummary:find("ChatFilterApi: " .. tostring(liveHealth.chatFilterApiUsed), 1, true) ~= nil,
    "the summary reports the filter API that is actually in use")
check(emptySummary:find("ChatFrames: " .. tostring(liveHealth.chatFramesWrapped)
    .. " observees / " .. tostring(liveHealth.chatFramesSeen) .. " vues", 1, true) ~= nil,
    "and the chat frames actually observed")
check(emptySummary:find("Build: " .. ns.BUILD_ID, 1, true) ~= nil,
    "and the build the code itself carries")
check(emptySummary:find("Verdict: "
    .. select(1, ns.getInstrumentationVerdict(liveHealth)):upper(), 1, true) ~= nil,
    "and the verdict that health implies")
check(emptySummary:find("Deploiement: "
    .. select(1, ns.getDeploymentVerdict(liveManifest)):upper(), 1, true) ~= nil,
    "and the deployment verdict of the manifest it just wrote")

-- Deployment through the summary, not through a direct call: a direct call
-- proves the rule, not that the screen is wired to it. A desynchronised .toc
-- has to reach the line the maintainer reads.
local savedGetMetadata = C_AddOns.GetAddOnMetadata
C_AddOns.GetAddOnMetadata = function(addon, field)
    if field == "X-Sanctuary-Build" then return "20260820-0" end
    return savedGetMetadata(addon, field)
end
ns.resetDebugLog()
local partialSummary = ns.buildDebugSummaryText()
C_AddOns.GetAddOnMetadata = savedGetMetadata
check(partialSummary:find("Deploiement: PARTIAL", 1, true) ~= nil,
    "a desynchronised .toc reaches the summary the maintainer reads")
check(partialSummary:find("20260820-0", 1, true) ~= nil,
    "and the line names the .toc value it disagrees with")
ns.resetDebugLog()

-- The summary reports live instrumentation, so it must grade live
-- instrumentation. Grading the last SNAPSHOT still in the log instead printed
-- `ChatFilterApi: legacy` under `Verdict: BLOCKING` once the addon had caught
-- up mid-session -- and, in the dangerous direction, `OK` over degraded
-- counters.
ns.resetDebugLog()
SanctuaryDB.debugLog[1] = { seq = 1, ts = "00:00:00", cat = "SNAPSHOT", data = {
    chatFilterApiUsed = "unregistered", chatFramesSeen = 10, chatFramesWrapped = 0,
    systemChatTypeID = "unknown" } }
summary = ns.buildDebugSummaryText()
check(summary:find("Verdict: OK", 1, true) ~= nil,
    "a stale failed snapshot does not condemn a session that caught up")
equal(SanctuaryDB.reportManifest.verdict, "ok",
    "and the manifest records the verdict on the health it carries")

-- The reverse direction is the one that costs a session: a good old snapshot
-- must not vouch for degraded live counters.
local savedAddMessage = ChatFrame1.AddMessage
ChatFrame1.AddMessage = function() end
ns.resetDebugLog()
SanctuaryDB.debugLog[1] = { seq = 1, ts = "00:00:00", cat = "SNAPSHOT", data = {
    chatFilterApiUsed = "legacy", chatFramesSeen = 10, chatFramesWrapped = 10,
    systemChatTypeID = 90 } }
summary = ns.buildDebugSummaryText()
equal(summary:find("Verdict: OK", 1, true), nil,
    "a good old snapshot does not vouch for a chat that is no longer observed")
check(summary:find("Verdict: DEGRADED", 1, true) ~= nil,
    "the summary grades the frames it actually reports")
ChatFrame1.AddMessage = savedAddMessage
ns.resetDebugLog()

-- Opening the summary refreshes the manifest, so the file describes the session
-- rather than the moment the addon loaded.
SanctuaryDB.reportManifest = nil
ns.buildDebugSummaryText()
equal(SanctuaryDB.reportManifest and SanctuaryDB.reportManifest.trigger, "summary",
    "opening the summary restamps the manifest")

-- Pipe escaping still applies to the summary: it is rendered by the same widget
-- that lost two hundred characters of the 2026-08-20 report.
equal(ns.escapeExportText("a|Kb|kc"), "a||Kb||kc", "the summary escapes what the widget would render")

ns.resetDebugLog()


-- ===========================================================================
-- SECTION: the 0.4.0 decision model
-- ===========================================================================

-- One phrase: always blocked, else always allowed, else unknown -- and only the
-- third tier depends on a setting. Everything below proves that phrase, on the
-- paths that carry it.

-- An earlier section clears these globals to exercise the escaping of a nil
-- value, and the invite patterns were rebuilt without them. Put them back and
-- rebuild, or the simulated system line matches no pattern at all.
ERR_INVITED_TO_GROUP_SS = "[%s] vous a invit\195\169 \195\160 rejoindre un groupe."
ERR_INVITED_ALREADY_IN_GROUP_SS = "[%s] vous a invit\195\169 \195\160 rejoindre un groupe, mais vous ne pouviez pas accepter car vous \195\170tes d\195\169j\195\160 dans un groupe."
fire("ADDON_LOADED", "Sanctuary")

local function resetModelState()
    wipe(SanctuaryDB.manualWhitelist)
    wipe(SanctuaryDB.blockedNames)
    SanctuaryDB.keywords = {}
    SanctuaryDB.filters.scope = "strangers"
    SanctuaryDB.filters.preset = "custom"
    SanctuaryDB.filters.groupInvite = true
    SanctuaryDB.filters.whisper = true
    SanctuaryDB.filters.duel = true
    SanctuaryDB.filters.trade = true
    SanctuaryDB.filters.guildInvite = true
    SanctuaryDB.filters.say = false
    SanctuaryDB.filters.yell = false
    SanctuaryDB.filters.emote = false
    SanctuaryDB.filters.channelMode = "none"
    SanctuaryDB.filters.strictGroupInviteSystemMessages = false
    SanctuaryDB.log = {}
    guildMembers = {}
    charFriends = {}
    bnetFriends = {}
    groupMembers = {}
    inGuild = false
    inGroup = false
    inRaid = false
    inInstance = false
    currentInstanceType = "none"
    npcName = nil
    ns.invalidateWhitelist()
    -- This helper wipes the saved tables in place, which is not a path the
    -- add-on itself ever takes: nothing tells the sound guards the lists just
    -- emptied. One refresh here puts every section on the same footing -- and
    -- makes the calls that used to sit in the test bodies unnecessary, which is
    -- what let a missing refresh in `ns.addBlocked` go unnoticed.
    ns.refreshInviteSoundMuteState()
    ns.resetDebugLog()
end

resetModelState()

-- C1 -- a blocked name beats every trust source, and every unticked filter.
guildMembers = { "Nuisance-TestRealm" }
inGuild = true
charFriends = { "Nuisance" }
inGroup = true
groupMembers = { "Nuisance-TestRealm" }
ns.addAllowed("Nuisance-TestRealm")
ns.addBlocked("Nuisance")
ns.invalidateWhitelist()

local blocked, why = ns.getCharacterDecision("Nuisance-TestRealm")
equal(blocked, true, "a blocked name is blocked although guild, friend, group and allowed")
equal(why, "blocked_name", "and the decision names the list that decided")

-- Every filter unticked, and the chat filters still discard them.
SanctuaryDB.filters.whisper = false
SanctuaryDB.filters.say = false
SanctuaryDB.filters.yell = false
SanctuaryDB.filters.emote = false
SanctuaryDB.filters.channelMode = "none"
SanctuaryDB.filters.groupInvite = false
for _, case in ipairs({
    { "CHAT_MSG_WHISPER", "whisper" },
    { "CHAT_MSG_SAY", "say" },
    { "CHAT_MSG_YELL", "yell" },
    { "CHAT_MSG_EMOTE", "emote" },
    { "CHAT_MSG_CHANNEL", "public channel" },
}) do
    equal(dispatchChatFilter(case[1], "hello", "Nuisance-TestRealm"), true,
        "a blocked name is discarded on " .. case[2] .. " with the filter unticked")
end
equal(dispatchChatFilter("CHAT_MSG_SYSTEM",
    string.format(ERR_INVITED_TO_GROUP_SS, "Nuisance", "Nuisance")), true,
    "and on the invite system line")

-- ... and the four interaction handlers refuse them, filters unticked.
local beforeDeclines = declinedGroups
fire("PARTY_INVITE_REQUEST", "Nuisance-TestRealm")
runTimers(3)
equal(declinedGroups, beforeDeclines + 1, "a blocked name's group invite is declined, filter unticked")
local inviteEntry = lastDebug("INVITE")
equal(inviteEntry and inviteEntry.data.action, "BLOCK_BLOCKED_NAME",
    "and the debug entry names the list rather than the whitelist")
equal(inviteEntry and inviteEntry.data.armedBy, "blocked_list",
    "and says which half armed the guard")

SanctuaryDB.filters.duel = false
local beforeDuels = cancelledDuels
fire("DUEL_REQUESTED", "Nuisance-TestRealm")
runTimers(3)
equal(cancelledDuels, beforeDuels + 1, "a blocked name's duel is cancelled, filter unticked")

SanctuaryDB.filters.guildInvite = false
local beforeGuilds = declinedGuilds
fire("GUILD_INVITE_REQUEST", "Nuisance-TestRealm", "Some Guild")
runTimers(3)
equal(declinedGuilds, beforeGuilds + 1, "a blocked name's guild invite is declined, filter unticked")

SanctuaryDB.filters.trade = false
npcName = "Nuisance-TestRealm"
local beforeTrades = closedTrades
fire("TRADE_SHOW")
equal(closedTrades, beforeTrades + 1, "a blocked name's trade is closed, filter unticked")
npcName = nil

-- C2 -- the same, by pattern.
resetModelState()
guildMembers = { "Spammerguy-TestRealm" }
inGuild = true
SanctuaryDB.keywords = { "spammer" }
SanctuaryDB.filters.whisper = false
ns.invalidateWhitelist()
blocked, why = ns.getCharacterDecision("Spammerguy-TestRealm")
equal(blocked, true, "a pattern still beats every trust source")
equal(why, "keyword", "and is still reported as a pattern")
equal(dispatchChatFilter("CHAT_MSG_WHISPER", "hi", "Spammerguy-TestRealm"), true,
    "a pattern discards a whisper with the filter unticked")

-- C3 -- "everyone except the people I block".
resetModelState()
guildMembers = { "Mate-TestRealm" }
inGuild = true
ns.addBlocked("Pest")
SanctuaryDB.filters.scope = "blockedOnly"
ns.invalidateWhitelist()
equal(select(1, ns.getCharacterDecision("Pest")), true, "a blocked name is blocked in the open mode")
local openBlocked, openReason = ns.getCharacterDecision("Stranger")
equal(openBlocked, false, "an unknown name is not blocked in the open mode")
equal(openReason, "open_scope", "and the reason names the mode")
local mateBlocked, mateReason = ns.getCharacterDecision("Mate-TestRealm")
equal(mateBlocked, false, "a guild member is still allowed")
equal(mateReason, "whitelist", "and still for being allowed, not for the mode")
for _, key in ipairs({ "groupInvite", "whisper", "duel", "trade", "guildInvite",
    "say", "yell", "emote", "strictGroupInviteSystemMessages" }) do
    equal(ns.isFilterOn(key), false, "the open mode turns " .. key .. " off")
end
equal(ns.isFilterOn("channelMode"), "none", "and public channels with them")

-- C4 -- the recommended preset ignores what is stored underneath.
resetModelState()
SanctuaryDB.filters.preset = "all"
SanctuaryDB.filters.whisper = false
SanctuaryDB.filters.say = true
SanctuaryDB.filters.channelMode = "all"
equal(ns.isFilterOn("whisper"), true, "the recommended preset filters whispers whatever is stored")
equal(ns.isFilterOn("say"), false, "and leaves /say alone whatever is stored")
equal(ns.isFilterOn("channelMode"), "none", "and public channels alone")
SanctuaryDB.filters.preset = "custom"
equal(ns.isFilterOn("whisper"), false, "\"I choose\" reads the stored value")
equal(ns.isFilterOn("say"), true, "for each key")
equal(ns.isFilterOn("channelMode"), "all", "including the channel mode")
-- The stored values are never rewritten by the switch: that is what makes the
-- round trip lossless.
equal(SanctuaryDB.filters.whisper, false, "the stored value survives a trip through the preset")

-- C5 -- enhanced instance filtering, in the three situations.
resetModelState()
SanctuaryDB.filters.strictGroupInviteSystemMessages = true
SanctuaryDB.filters.preset = "all"
equal(ns.isFilterOn("strictGroupInviteSystemMessages"), true,
    "the enhanced box applies under the recommended preset")
SanctuaryDB.filters.scope = "blockedOnly"
equal(ns.isFilterOn("strictGroupInviteSystemMessages"), false,
    "and never in the open mode")
SanctuaryDB.filters.scope = "strangers"
SanctuaryDB.filters.preset = "custom"
SanctuaryDB.filters.groupInvite = false
equal(ns.isFilterOn("strictGroupInviteSystemMessages"), false,
    "nor with the group-invite filter unticked")
SanctuaryDB.filters.groupInvite = true
equal(ns.isFilterOn("strictGroupInviteSystemMessages"), true, "and again once it is back")

-- C6 -- arming. One blocked name is enough; empty lists arm nothing.
resetModelState()
SanctuaryDB.filters.scope = "blockedOnly"
-- The only manual refresh left in this section, and it is about a *setting*: in
-- game question 1 goes through `setFilter`, which refreshes the guards. Written
-- straight into the table here, so the harness does it once. Nothing below this
-- line refreshes anything -- the list writers have to post the guard themselves.
ns.refreshInviteSoundMuteState()
equal(ns.isProtectionArmed("PARTY_INVITE"), false, "empty lists arm nothing at all")
equal(StaticPopupDialogs.PARTY_INVITE.sound, 880,
    "so the native invite sound is left exactly as WoW plays it")
ns.addBlocked("Pest")
equal(ns.isProtectionArmed("PARTY_INVITE"), true, "one blocked name arms the invite guard")
equal(ns.isProtectionArmed("DUEL_REQUESTED"), true, "and the duel guard")
equal(ns.isProtectionArmed("guildInvite"), true, "and the guild one")
equal(ns.isProtectionArmed("trade"), true, "and the trade one")
-- No manual refresh: `ns.addBlocked` has to post the guard by itself, or the
-- very first blocked invitation plays its sound before being hidden.
equal(StaticPopupDialogs.PARTY_INVITE.sound, nil, "and the sound guard goes back up")

-- And the simulation says so too: answering "pass" here would describe a screen
-- nobody is going to see.
local armedSimulation = ns.simulateInvite("Pest")
equal(armedSimulation.popupAction, "mask",
    "the simulation reports the mask the list armed, filters off")
equal(armedSimulation.wouldDecline, true, "and that the invitation would be declined")

local beforeLog = #SanctuaryDB.log
beforeDeclines = declinedGroups
StaticPopup_Show("PARTY_INVITE", "Pest")
fire("PARTY_INVITE_REQUEST", "Pest")
runTimers(3)
equal(declinedGroups, beforeDeclines + 1, "the invitation is declined although no filter is on")
equal(#SanctuaryDB.log, beforeLog + 1, "and the journal records it")
equal(StaticPopup1:IsShown(), false, "and no dialog is left on screen")

do

-- C6b -- the guard follows the list on its own. Not one line of this section
-- calls refreshInviteSoundMuteState: writing a name (or a pattern) into the
-- always-blocked list is what has to put the guard up, and removing the last one
-- is what has to take it down. Both product rules ride on it -- a blocked
-- invitation that leaves no trace, an allowed one that sounds exactly as WoW
-- plays it -- and the manual calls this section used to make hid the fact that
-- neither happened.
local function blockedInviteIsSilent(name, eventFirst, label)
    playedSounds = {}
    local before = declinedGroups
    if eventFirst then
        fire("PARTY_INVITE_REQUEST", name)
        StaticPopup_Show("PARTY_INVITE", name)
    else
        StaticPopup_Show("PARTY_INVITE", name)
        fire("PARTY_INVITE_REQUEST", name)
    end
    runTimers(3)
    equal(declinedGroups, before + 1, label .. ": the invitation is declined")
    equal(#playedSounds, 0, label .. ": and not one sound is played")
    equal(StaticPopup1:IsShown(), false, label .. ": and no dialog is left on screen")
end

resetModelState()
SanctuaryDB.filters.scope = "blockedOnly"
ns.refreshInviteSoundMuteState()
equal(StaticPopupDialogs.PARTY_INVITE.sound, 880, "an empty list arms nothing")

local addedOk, pestKey = ns.addBlocked("Pest3")
equal(addedOk, true, "a name is blocked")
equal(StaticPopupDialogs.PARTY_INVITE.sound, nil,
    "and that alone puts the invite sound guard up -- no refresh, no event")
blockedInviteIsSilent("Pest3", false, "blocked name, window first")
blockedInviteIsSilent("Pest3", true, "blocked name, event first")

-- A pattern arms exactly the same way: the two lists feed one predicate.
equal(select(1, ns.removeBlocked(pestKey)), true, "the name is taken back out")
equal(StaticPopupDialogs.PARTY_INVITE.sound, 880, "which lowers the guard again")
equal(select(1, ns.addPattern("gold")), true, "a pattern is added instead")
equal(StaticPopupDialogs.PARTY_INVITE.sound, nil, "and puts the guard back up on its own")
blockedInviteIsSilent("Goldseller", false, "matched pattern, window first")
blockedInviteIsSilent("Goldseller", true, "matched pattern, event first")

-- The duel dialog is the second guarded popup and has its own sound field.
equal(StaticPopupDialogs.DUEL_REQUESTED.sound, nil, "the duel guard went up with it")
playedSounds = {}
local beforeDuels = cancelledDuels
StaticPopup_Show("DUEL_REQUESTED", "Goldseller")
fire("DUEL_REQUESTED", "Goldseller")
runTimers(3)
equal(cancelledDuels, beforeDuels + 1, "a blocked duel is cancelled")
equal(#playedSounds, 0, "and plays nothing at all")

-- And the way back: with the last entry gone, an unknown name is native again.
-- This is the half that breaks the other product rule -- an allowed player must
-- keep WoW's own sounds -- and it stayed broken for as long as the guard did.
-- The guard is posted by hand here on purpose: the removal must be the only
-- thing that lowers it, and that cannot be shown against a guard that was never
-- up in the first place.
ns.refreshInviteSoundMuteState()
equal(StaticPopupDialogs.PARTY_INVITE.sound, nil, "with the guard genuinely up")
equal(select(1, ns.removePattern("gold")), true, "the last blocked entry is removed")
equal(ns.isProtectionArmed("PARTY_INVITE"), false, "nothing is armed any more")
equal(StaticPopupDialogs.PARTY_INVITE.sound, 880, "and the invite sound is WoW's own again")
equal(StaticPopupDialogs.DUEL_REQUESTED.sound, 880, "as is the duel one")
playedSounds = {}
local beforeStrangerDeclines = declinedGroups
StaticPopup_Show("PARTY_INVITE", "Stranger3")
fire("PARTY_INVITE_REQUEST", "Stranger3")
runTimers(3)
equal(declinedGroups, beforeStrangerDeclines, "a stranger is not declined in the open mode")
equal(#playedSounds, 2, "and their invitation sounds exactly as WoW plays it")
equal(playedSounds[1], SOUNDKIT.IG_MAINMENU_OPEN, "the panel sound first")
equal(playedSounds[2], 880, "then Blizzard's own invite sound")
StaticPopup1.inviteAccepted = true
StaticPopup1:Hide()
StaticPopup1.inviteAccepted = nil
runTimers(3)

end

-- C7 -- armed by the list, then an allowed invitation arrives.
resetModelState()
SanctuaryDB.filters.scope = "blockedOnly"
ns.addBlocked("Pest")
ns.addAllowed("Welcome")
playedSounds = {}
StaticPopup_Show("PARTY_INVITE", "Welcome")
fire("PARTY_INVITE_REQUEST", "Welcome")
runTimers(3)
local allowEntry = lastDebug("INVITE")
equal(allowEntry and allowEntry.data.action, "ALLOW", "an allowed invitation is allowed")
check((tonumber(allowEntry and allowEntry.data.releasedSoundGuards) or 0) > 0,
    "the guard the list had armed is released for it")
check(allowEntry and allowEntry.data.replayedSound == true,
    "and the native sound is replayed exactly once")
equal(StaticPopup1:GetAlpha(), 1, "with the dialog put back on screen")
StaticPopup1.inviteAccepted = true
StaticPopup1:Hide()
StaticPopup1.inviteAccepted = nil
runTimers(3)

-- C8 -- the seven group, raid and instance channels.
resetModelState()
ns.addBlocked("Pest")
ns.addAllowed("Welcome")
for _, event in ipairs(ns.GROUP_CHAT_EVENTS) do
    equal(dispatchChatFilter(event, "spam", "Pest"), true,
        event .. " hides a blocked name")
    equal(dispatchChatFilter(event, "hello", "Stranger"), false,
        event .. " never hides a stranger")
    equal(dispatchChatFilter(event, "hello", "Welcome"), false,
        event .. " never hides an allowed name")
    equal(dispatchChatFilter(event, "hello", "Victim-TestRealm"), false,
        event .. " never hides the player")
end
SanctuaryCharDB.overrides.enabled = false
equal(dispatchChatFilter("CHAT_MSG_PARTY", "spam", "Pest"), false,
    "and nothing at all while the add-on is off")
SanctuaryCharDB.overrides.enabled = nil

-- One journal entry, one session counter, one verbose line -- like any other
-- blocked interaction.
SanctuaryDB.log = {}
SanctuaryCharDB.sessionStats = { blockedCount = 0, blockedByType = {} }
SanctuaryDB.notifications.mode = "verbose"
chatMessages = {}
now = now + 5
fire("CHAT_MSG_PARTY", "spam", "Pest")
equal(#SanctuaryDB.log, 1, "a hidden group message is journalled")
equal(SanctuaryDB.log[1].type, "group", "under its own type")
equal(SanctuaryCharDB.sessionStats.blockedCount, 1, "and counted in the session")
equal(#chatMessages, 1, "and announced once in verbose mode")
SanctuaryDB.notifications.mode = "silent"

do

-- C8b -- the envelope of last resort. `hookChatOutputDiagnostics` wraps
-- ChatFrame:AddMessage because a 2026-06-25 recording showed invite lines
-- printed outside Blizzard's filter registry, in raid and in an instance. It has
-- to apply order 4.1 like every other path -- always blocked first, the filter
-- flag second -- or a blocked name leaves a visible trace in the open mode,
-- where the group-invite filter is off by definition.
--
-- On its own frame: an earlier section replaced ChatFrame1 with a whisper-tab
-- stub that has no AddMessage at all, so there is nothing left here to wrap.
local printedLines = {}
ChatFrame3 = { AddMessage = function(_, message) printedLines[#printedLines + 1] = message end }
ns.hookChatOutputDiagnostics()
check(ChatFrame3.AddMessage ~= nil, "the envelope is installed on a frame that has one")

resetModelState()
SanctuaryDB.filters.scope = "blockedOnly"
ns.addBlocked("Harasser")
local inviteLine = string.format(ERR_INVITED_TO_GROUP_SS, "Harasser")
equal(dispatchChatFilter("CHAT_MSG_SYSTEM", inviteLine), true,
    "the registry filter hides a blocked name's invite line")
ChatFrame3:AddMessage(inviteLine)
equal(#printedLines, 0, "and so does the envelope, with the filter unticked")
local outputEntry = lastDebug("CHAT_OUTPUT")
equal(outputEntry and outputEntry.data.action, "SUPPRESS_BLOCKED_INVITE",
    "which records that it suppressed the line")
equal(outputEntry and outputEntry.data.suppressedBy, "always_blocked",
    "and says which of the two halves decided")
equal(outputEntry and outputEntry.data.filterEnabled, false, "the filter being off at the time")

-- The control: with the filter ticked the envelope still works, and now names
-- the filter as the decider.
equal(select(1, ns.removeBlocked("harasser")), true, "the name is taken back out")
SanctuaryDB.filters.scope = "strangers"
ChatFrame3:AddMessage(inviteLine)
equal(#printedLines, 0, "an unknown name is still hidden when the filter is ticked")
outputEntry = lastDebug("CHAT_OUTPUT")
equal(outputEntry and outputEntry.data.suppressedBy, "filter", "and the filter is named")

-- And in the open mode a name nobody blocked keeps its line, untouched.
SanctuaryDB.filters.scope = "blockedOnly"
ChatFrame3:AddMessage(inviteLine)
equal(#printedLines, 1, "while the open mode prints a stranger's line as WoW wrote it")
outputEntry = lastDebug("CHAT_OUTPUT")
equal(outputEntry and outputEntry.data.suppressedBy, "none", "with nothing claiming the decision")

ChatFrame3 = nil

end

-- C9 -- Battle.net, resolved both ways.
resetModelState()
bnetFriends = {
    { accountName = "Real Friend#1234", bnetAccountID = 91,
      gameAccountInfo = { characterName = "Bnetchar" } },
    { accountName = "Dash-Friend#5678", bnetAccountID = 92 },
}
SanctuaryDB.filters.whisper = false
ns.addBlocked("Real Friend#1234")
ns.invalidateWhitelist()
equal(dispatchChatFilter("CHAT_MSG_BN_WHISPER", "hi", "|Kq2|k", bnetWhisperPayload(91)), true,
    "a blocked Battle.net account is discarded with the whisper filter unticked")
equal(select(1, ns.getCharacterDecision("Bnetchar")), true,
    "and their known character is blocked on the WoW paths too")
ns.removeBlocked(ns.normalizeBlockedKey("Real Friend#1234"))

ns.addBlocked("Bnetchar")
ns.invalidateWhitelist()
equal(dispatchChatFilter("CHAT_MSG_BN_WHISPER", "hi", "|Kq2|k", bnetWhisperPayload(91)), true,
    "blocking the character blocks the account's whispers as well")
ns.removeBlocked(ns.normalizeBlockedKey("Bnetchar"))

-- The right-click menu writes "Name-Realm" into the blocked list, and
-- `isBlockedName` only ever falls back from the full key to the bare one, never
-- the other way round. So the character has to be recorded with its realm, or
-- the very key the menu produces is the one key nothing matches.
bnetFriends[#bnetFriends + 1] = { accountName = "Realm Friend#4321", bnetAccountID = 93,
    gameAccountInfo = { characterName = "Bnetrealmchar", realmName = "Ysondre" } }
ns.addBlocked("Bnetrealmchar-Ysondre", "menu")
ns.invalidateWhitelist()
equal(select(1, ns.getCharacterDecision("Bnetrealmchar-Ysondre")), true,
    "the menu's key blocks the character on the WoW paths")
equal(dispatchChatFilter("CHAT_MSG_BN_WHISPER", "hi", "|Kq2|k", bnetWhisperPayload(93)), true,
    "and the account's Battle.net whispers with it, filter unticked")
equal(ns.classifyName("Realm Friend#4321").verdict, "always_blocked",
    "and 'Test a name' answers always blocked rather than always allowed")
ns.removeBlocked(ns.normalizeBlockedKey("Bnetrealmchar-Ysondre"))
-- Blocking that same account still reaches the character it plays.
ns.addBlocked("Realm Friend#4321")
ns.invalidateWhitelist()
equal(select(1, ns.getCharacterDecision("Bnetrealmchar-Ysondre")), true,
    "and the other direction still resolves with a realm in the way")
ns.removeBlocked(ns.normalizeBlockedKey("Realm Friend#4321"))

ns.addBlocked("Dash-Friend#5678")
ns.invalidateWhitelist()
equal(dispatchChatFilter("CHAT_MSG_BN_WHISPER", "hi", "|Kq2|k", bnetWhisperPayload(92)), true,
    "an account name carrying a hyphen is found")
-- The one gap, and it is stated in the release notes: an offline friend has no
-- known character, so there is nothing to resolve from.
local offline = ns.classifyName("SomeCharacterOf5678")
equal(offline.verdict, "unknown", "an offline friend's unknown character resolves to nothing")

-- C9b -- two Battle.net friends, two realms, one character name. Keyed on the
-- bare name alone, the second friend read overwrote the first and one account
-- answered for both: in one roster order the blocked account's character walked
-- straight through, in the other an allowed friend was blocked in his place.
-- Played in both orders, because the roster order is exactly what decided it.
for _, order in ipairs({ { "Ysondre", "Hyjal" }, { "Hyjal", "Ysondre" } }) do
    resetModelState()
    local blockedFirst = order[1] == "Ysondre"
    bnetFriends = {
        { accountName = blockedFirst and "Twin One#1111" or "Twin Two#2222",
          bnetAccountID = blockedFirst and 94 or 95,
          gameAccountInfo = { characterName = "Twin", realmName = order[1] } },
        { accountName = blockedFirst and "Twin Two#2222" or "Twin One#1111",
          bnetAccountID = blockedFirst and 95 or 94,
          gameAccountInfo = { characterName = "Twin", realmName = order[2] } },
    }
    -- "Everyone except the people I block": the mode where the blocked list is
    -- the only thing standing between the two of them.
    SanctuaryDB.filters.scope = "blockedOnly"
    ns.addBlocked("Twin One#1111")
    ns.invalidateWhitelist()
    equal(select(1, ns.getCharacterDecision("Twin-Ysondre")), true,
        "the blocked account's character is filtered, whichever friend was read first")
    equal(select(1, ns.getCharacterDecision("Twin-Hyjal")), false,
        "and his namesake on the other realm keeps the native behaviour")
    equal(ns.classifyName("Twin-Ysondre").verdict, "always_blocked",
        "so 'Test a name' names the blocked one for what he is")
    equal(ns.classifyName("Twin-Hyjal").verdict, "always_allowed",
        "and still answers always allowed for the friend")
    ns.removeBlocked(ns.normalizeBlockedKey("Twin One#1111"))
end

-- C10 -- the eight answers of the board, through classifyName.
resetModelState()
guildMembers = { "Guildy-TestRealm" }
inGuild = true
charFriends = { "Palz" }
bnetFriends = { { accountName = "Ioxe26", bnetAccountID = 93,
    gameAccountInfo = { characterName = "Clarage" } } }
inGroup = true
groupMembers = { "Kadaj-TestRealm" }
ns.addAllowed("Toto")
ns.addBlocked("Xxxxxxx")
SanctuaryDB.keywords = { "zzpattern" }
ns.invalidateWhitelist()
local function classificationOf(name)
    local info = ns.classifyName(name)
    return info.verdict .. "/" .. tostring(info.list)
end
equal(classificationOf("Toto"), "always_allowed/manual", "added by you")
equal(classificationOf("Clarage"), "always_allowed/bnet", "Battle.net friend")
equal(ns.classifyName("Clarage").detail, "Ioxe26", "named by the account")
equal(classificationOf("Palz"), "always_allowed/friend", "realm friend")
equal(classificationOf("Guildy-TestRealm"), "always_allowed/guild", "guild member")
equal(classificationOf("Kadaj-TestRealm"), "always_allowed/group", "in the group right now")
equal(classificationOf("Xxxxxxx"), "always_blocked/blocked_name", "in the blocked names")
equal(classificationOf("Superzzpattern"), "always_blocked/keyword", "matched by a pattern")
equal(classificationOf("Zorglub"), "unknown/nil", "and an unknown name is unknown")

-- C11 -- the counts behind the two tiles.
local listCounts = ns.getListCounts()
equal(listCounts.allowed.manual, 1, "one name added by hand")
equal(listCounts.allowed.bnet, 1, "one Battle.net account")
equal(listCounts.allowed.friend, 1, "one realm friend")
equal(listCounts.allowed.guild, 1, "one guild member")
equal(listCounts.allowed.total,
    listCounts.allowed.manual + listCounts.allowed.trust + listCounts.allowed.bnet
    + listCounts.allowed.friend + listCounts.allowed.guild,
    "and the total is their sum -- the current group is not counted")
equal(listCounts.blocked.names, 1, "one blocked name")
equal(listCounts.blocked.patterns, 1, "one pattern")
equal(listCounts.blocked.total, 2, "and the blocked total is their sum")

local protectionInfo = ns.describeProtection()
equal(#protectionInfo.kinds, 5, "\"I choose\" with everything ticked lists five kinds")
SanctuaryDB.filters.preset = "all"
equal(#ns.describeProtection().kinds, 5, "the recommended preset lists the same five")
SanctuaryDB.filters.scope = "blockedOnly"
equal(#ns.describeProtection().kinds, 0, "and the open mode lists none")
SanctuaryDB.filters.scope = "strangers"
SanctuaryDB.filters.preset = "custom"

-- C12 -- the writes.
resetModelState()
equal(select(1, ns.addAllowed("  Toto-Ysondre  ")), true, "a name is added once")
equal(select(1, ns.addAllowed("toto")), false, "and a duplicate is a no-op")
local removedOk, removedKey, removedData = ns.removeAllowed("toto")
equal(removedOk, true, "removing gives the data back")
check(type(removedData) == "table" and removedData.displayName == "Toto-Ysondre",
    "with the name exactly as it was typed")
ns.restoreAllowed(removedKey, removedData)
equal(SanctuaryDB.manualWhitelist.toto.displayName, "Toto-Ysondre",
    "and restoring puts back the same record, date included")
equal(select(1, ns.addBlocked("Toto-Ysondre")), true, "the same name can also be blocked")
check(SanctuaryDB.manualWhitelist.toto ~= nil,
    "and blocking never deletes the allowed entry the person typed")
equal(select(1, ns.getCharacterDecision("Toto-Ysondre")), true, "the decision blocks them")
equal(select(1, ns.addPattern("  Te St ")), true, "a pattern is normalised")
equal(SanctuaryDB.keywords[1], "test", "to lower case with no spaces")
equal(select(1, ns.addPattern("TEST")), false, "and deduplicated")
equal(select(1, ns.removePattern("test")), true, "and removable")
equal(#SanctuaryDB.keywords, 0, "leaving the list empty")

-- C13 -- the protection toggle, in the core.
resetModelState()
ns.addBlocked("Pest")
StaticPopup_Show("PARTY_INVITE", "Pest")
fire("PARTY_INVITE_REQUEST", "Pest")
equal(StaticPopup1:GetAlpha(), 0, "a blocked invitation is masked")
chatMessages = {}
ns.setEnabled(false)
equal(ns.isEnabled(), false, "setEnabled writes the override")
equal(StaticPopup1:GetAlpha(), 1, "and unmasks what was hidden")
equal(#chatMessages, 1, "saying so once in chat")
local toggleEntry = lastDebug("TOGGLE")
equal(toggleEntry and toggleEntry.data.enabled, false, "and recording the flip")
ns.setEnabled(true)
equal(ns.isEnabled(), true, "and back on")
StaticPopup1.inviteAccepted = true
StaticPopup1:Hide()
StaticPopup1.inviteAccepted = nil
runTimers(3)

-- C14 -- the summary only speaks when something new was blocked.
resetModelState()
SanctuaryDB.notifications.mode = "minimal"
SanctuaryCharDB.sessionStats = { blockedCount = 3, blockedByType = {} }
Sanctuary = nil
chatMessages = {}
now = now + 1000
runTickers()
equal(#chatMessages, 1, "three blocks and a tick produce one summary")
chatMessages = {}
now = now + 1000
runTickers()
equal(#chatMessages, 0, "a tick with nothing new produces none")
SanctuaryCharDB.sessionStats.blockedCount = 4
chatMessages = {}
now = now + 1000
runTickers()
equal(#chatMessages, 1, "and one more block produces one again")
SanctuaryDB.notifications.mode = "silent"

-- C15 -- the schema reset.
local carriedWhitelist = { oldfriend = { displayName = "Oldfriend", addedAt = 42 } }
local carriedKeywords = { "oldpattern" }
SanctuaryDB = {
    schemaVersion = 1,
    filters = { groupInvite = false, whisper = false, say = true, channelMode = "all",
        autoTrust = true, strictGroupInviteSystemMessages = true },
    notifications = { mode = "verbose", minimalIntervalMinutes = 5 },
    logging = { enabled = false, maxEntries = 250, rotation = "deleteOldest" },
    manualWhitelist = carriedWhitelist,
    keywords = carriedKeywords,
    log = { { type = "whisper", name = "Someone" } },
    uiSize = { 620, 480 },
    uiPosition = { point = "TOP", x = 5, y = 5 },
    debugEnabled = true,
    debugLog = { { seq = 1, cat = "OLD", data = {} } },
}
SanctuaryCharDB = { schemaVersion = 1, overrides = { enabled = false, filters = {} },
    manualWhitelist = { charfriend = { displayName = "Charfriend" } },
    groupTracker = {}, sessionStats = { blockedCount = 9, blockedByType = {} } }
fire("ADDON_LOADED", "Sanctuary")
equal(SanctuaryDB.schemaVersion, 2, "the reset stamps the new schema")
equal(SanctuaryDB.filters.scope, "strangers", "question 1 goes back to its default")
equal(SanctuaryDB.filters.preset, "all", "question 2 too")
equal(SanctuaryDB.filters.groupInvite, true, "and every per-filter value")
equal(SanctuaryDB.notifications.mode, "silent", "question 3 goes back to silence")
equal(SanctuaryDB.uiSize, nil, "the window size is forgotten")
equal(SanctuaryDB.uiPosition, nil, "and its position")
equal(#SanctuaryDB.log, 0, "the journal is emptied")
equal(SanctuaryDB.logging.maxEntries, 5000, "the retention limit goes back to its default")
equal(SanctuaryDB.debugEnabled, false, "and debug mode is off again")
equal(SanctuaryDB.uiSettings.showMessageColumn, false,
    "the text of blocked messages is not displayed until it is asked for")
equal(SanctuaryDB.manualWhitelist, carriedWhitelist, "the names added by hand are kept")
equal(SanctuaryDB.manualWhitelist.oldfriend.addedAt, 42, "with their dates")
equal(SanctuaryDB.keywords, carriedKeywords, "the patterns are kept")
equal(SanctuaryCharDB.manualWhitelist.charfriend ~= nil, true,
    "and the per-character list too")
equal(next(SanctuaryDB.blockedNames), nil, "the blocked list starts empty")
-- Idempotent: the rebuilt file already carries schema 2, so a second load falls
-- straight through.
SanctuaryDB.filters.scope = "blockedOnly"
SanctuaryDB.logging.maxEntries = 1234
fire("ADDON_LOADED", "Sanctuary")
equal(SanctuaryDB.filters.scope, "blockedOnly", "a second load resets nothing")
equal(SanctuaryDB.logging.maxEntries, 1234, "and keeps what was set since")
SanctuaryDB.filters.scope = "strangers"
SanctuaryDB.logging.maxEntries = 5000
SanctuaryCharDB.overrides.enabled = nil

do

-- C15b -- two files, two stamps. The account file is written once per account
-- and the character file once per character, so the first character to load
-- 0.4.0 stamps the account file and every other character still logs in with a
-- v1 file of its own. Decided from the account stamp alone, those characters go
-- through fillMissingDefaults, which adds what is missing and overwrites
-- nothing: the `overrides.enabled = false` a right-click on the minimap button
-- wrote under 0.3.2 survives, and Sanctuary is silently off on that character.
SanctuaryDB.schemaVersion = 2
SanctuaryCharDB = {
    schemaVersion = 1,
    overrides = { enabled = false, filters = { whisper = false } },
    manualWhitelist = { secondchar = { displayName = "Secondchar" } },
    groupTracker = { oldmate = 1 },
    sessionStats = { blockedCount = 3, blockedByType = {} },
}
fire("ADDON_LOADED", "Sanctuary")
equal(SanctuaryCharDB.schemaVersion, 2, "a second character's v1 file is reset on its own")
equal(SanctuaryCharDB.overrides.enabled, nil, "the override that switched Sanctuary off is gone")
equal(next(SanctuaryCharDB.overrides.filters), nil, "and so are the per-character filter overrides")
equal(next(SanctuaryCharDB.groupTracker), nil, "the group tracker starts empty")
check(SanctuaryCharDB.manualWhitelist.secondchar ~= nil, "its own list of names is kept")
equal(ns.isEnabled(), true, "and Sanctuary is on for that character")
equal(SanctuaryDB.schemaVersion, 2, "the account file, already stamped, is left alone")

-- Idempotent, like the account half: a second load resets nothing more.
SanctuaryCharDB.manualWhitelist.addedsince = { displayName = "Addedsince" }
SanctuaryCharDB.groupTracker.freshmate = 2
fire("ADDON_LOADED", "Sanctuary")
check(SanctuaryCharDB.manualWhitelist.addedsince ~= nil, "a second load keeps what was added since")
check(SanctuaryCharDB.groupTracker.freshmate ~= nil, "and the tracking that started since")

-- C15c -- the one record that is not a setting. A MuteSoundFile survives
-- /reload and relogging; only a full client restart clears it. The flag mirrors
-- it into SavedVariables so the next load can lift what the previous session
-- left behind -- and the first load of 0.4.0 always goes through the reset. The
-- real path: a 0.3.2 session with a sound guard up at /reload, then 0.4.0
-- copied in and reloaded without restarting the client.
local unmutedBeforeStale = #unmuted
SanctuaryDB = { schemaVersion = 1, protectedPopupSoundMuted = true }
SanctuaryCharDB = { schemaVersion = 2, overrides = {}, manualWhitelist = {},
    groupTracker = {}, sessionStats = { blockedCount = 0, blockedByType = {} } }
fire("ADDON_LOADED", "Sanctuary")
equal(#unmuted, unmutedBeforeStale + 2,
    "the flag survives the reset, so the stale mute on both files is lifted")
equal(SanctuaryDB.protectedPopupSoundMuted, nil, "and the record goes once they are")
-- Debug mode is itself a setting and goes back to its default in that same
-- reset, so the POPUP_GUARD_STALE_UNMUTE entry cannot be observed here. The
-- UnmuteSoundFile calls are the thing that matters anyway.

-- Nothing to lift, nothing lifted.
unmutedBeforeStale = #unmuted
SanctuaryDB.schemaVersion = 1
fire("ADDON_LOADED", "Sanctuary")
equal(#unmuted, unmutedBeforeStale, "with no flag stored, no file is touched at load")

end

-- C16 -- the snapshot and the report publish what the core applies.
resetModelState()
SanctuaryDB.filters.preset = "all"
SanctuaryDB.filters.whisper = false
local publishedState = ns.getEffectiveFilterState()
equal(publishedState.whisper, true, "the published state is the resolved one")
equal(publishedState.scope, "strangers", "and carries the scope")
equal(publishedState.preset, "all", "and the preset")
SanctuaryDB.debugEnabled = true
ns.resetDebugLog()
ns.captureDebugSnapshot("test")
local snapshotEntry = lastDebug("SNAPSHOT")
equal(snapshotEntry and snapshotEntry.data.filters.whisper, true,
    "the snapshot publishes the resolved state, never the stored checkbox")
equal(snapshotEntry and snapshotEntry.data.filters.scope, "strangers",
    "with the scope alongside")
check(ns.buildDebugReportText():find("preset=all", 1, true) ~= nil,
    "and the report prints the preset")
SanctuaryDB.filters.preset = "custom"
SanctuaryDB.debugEnabled = false
ns.resetDebugLog()

-- C17 -- one line at load, and only one.
resetModelState()
chatMessages = {}
fire("ADDON_LOADED", "Sanctuary")
equal(#chatMessages, 1, "loading prints exactly one line")
check(chatMessages[1]:find(ns.L["ADDON_LOADED_ACTIVE"], 1, true) ~= nil,
    "and it says the protection is active")
SanctuaryCharDB.overrides.enabled = false
chatMessages = {}
fire("ADDON_LOADED", "Sanctuary")
equal(#chatMessages, 1, "still exactly one when the protection is off")
check(chatMessages[1]:find(ns.L["ADDON_LOADED_INACTIVE"], 1, true) ~= nil,
    "and it says so")
SanctuaryCharDB.overrides.enabled = nil

-- ===========================================================================
-- SECTION: hiding secret system lines during a chat lockdown
-- ===========================================================================

-- The registry cannot help here: a secret payload skips every add-on filter, so
-- the AddMessage envelope is the only place the line can be stopped.

resetModelState()
-- An earlier section replaced ChatFrame1 with a whisper-tab stub. The envelope
-- is what this whole section measures, so the real frame goes back and the
-- wrapper is reinstalled on it.
ChatFrame1 = DEFAULT_CHAT_FRAME
ChatFrame2 = nil
ChatFrame3 = nil
ChatFrame4 = nil
ns.hookChatOutputDiagnostics()
SanctuaryDB.debugEnabled = true
ns.resetDebugLog()
local lockdownPayload = makeSecretValue("lockdown-line")

local function sendSecretLine(messageTypeID)
    local beforeMessages = #chatMessages
    local beforeJournal = #SanctuaryDB.log
    local ok = pcall(function()
        ChatFrame1:AddMessage(lockdownPayload, 1, 1, 0, messageTypeID)
    end)
    return ok, #chatMessages - beforeMessages, #SanctuaryDB.log - beforeJournal
end

local function armStrictInInstance()
    SanctuaryDB.filters.scope = "strangers"
    SanctuaryDB.filters.preset = "custom"
    SanctuaryDB.filters.groupInvite = true
    SanctuaryDB.filters.strictGroupInviteSystemMessages = true
    SanctuaryCharDB.overrides.enabled = nil
    inGroup = true
    inInstance = true
    currentInstanceType = "party"
end

-- H1 -- the seven refusals, one by one. Each lets the line through and says why.
armStrictInInstance()
local REFUSALS = {
    { label = "a readable line", reason = "readable", prepare = function() end,
      readable = true },
    { label = "an unknown category", reason = "type_unknown",
      prepare = function() end },
    { label = "a category that is not system", reason = "type_not_system",
      prepare = function() end, messageTypeID = 99 },
    { label = "the add-on switched off", reason = "addon_disabled",
      prepare = function() SanctuaryCharDB.overrides.enabled = false end,
      messageTypeID = ChatTypeInfo.SYSTEM.id },
    { label = "the group-invite filter unticked", reason = "filter_off",
      prepare = function() SanctuaryDB.filters.groupInvite = false end,
      messageTypeID = ChatTypeInfo.SYSTEM.id },
    { label = "the enhanced box unticked", reason = "strict_off",
      prepare = function() SanctuaryDB.filters.strictGroupInviteSystemMessages = false end,
      messageTypeID = ChatTypeInfo.SYSTEM.id },
    { label = "no group and no instance", reason = "no_context",
      prepare = function() inGroup = false; inInstance = false end,
      messageTypeID = ChatTypeInfo.SYSTEM.id },
}
for _, refusal in ipairs(REFUSALS) do
    armStrictInInstance()
    refusal.prepare()
    ns.resetDebugLog()
    now = now + 5
    if refusal.readable then
        local before = #chatMessages
        ChatFrame1:AddMessage("a plain system line", 1, 1, 0, ChatTypeInfo.SYSTEM.id)
        equal(#chatMessages, before + 1, refusal.label .. " reaches the frame")
    else
        local ok, shown, journalled = sendSecretLine(refusal.messageTypeID)
        check(ok, refusal.label .. " does not break the guard")
        equal(shown, 1, refusal.label .. " lets the line reach the frame")
        equal(journalled, 0, refusal.label .. " writes nothing to the journal")
        local entry = lastDebug("CHAT_OUTPUT")
        equal(entry and entry.data.action, "SECRET_VALUE", refusal.label .. " is recorded as seen")
        equal(entry and entry.data.reason, refusal.reason,
            refusal.label .. " records the refusal it hit")
    end
end

-- H2 -- the nominal case: five-person group in a dungeon, enhanced ticked.
armStrictInInstance()
groupMembers = { "A-TestRealm", "B-TestRealm", "C-TestRealm", "D-TestRealm" }
ns.resetDebugLog()
now = now + 5
local ok, shown, journalled = sendSecretLine(ChatTypeInfo.SYSTEM.id)
check(ok, "the nominal case does not break the guard")
equal(shown, 0, "the line never reaches the frame")
equal(journalled, 0, "and nothing is written to the journal -- there is nothing to record")
local maskEntry = lastDebug("CHAT_OUTPUT")
equal(maskEntry and maskEntry.data.action, "SUPPRESS_SECRET_SYSTEM", "the masking is recorded")
equal(maskEntry and maskEntry.data.reason, "suppressed", "with the reason it went through")
equal(maskEntry and maskEntry.data.frames, "1", "and the frame it was destined for")
equal(maskEntry and maskEntry.data.journaled, nil,
    "and no journalled field: the product journal is not involved at all")

-- H3 -- one message, three frames: one debug entry, three destinations.
ChatFrame2 = { AddMessage = function(self, message) end }
ChatFrame3 = { AddMessage = function(self, message) end }
ns.hookChatOutputDiagnostics()
ns.resetDebugLog()
now = now + 5
for _, frame in ipairs({ ChatFrame1, ChatFrame2, ChatFrame3 }) do
    pcall(function() frame:AddMessage(lockdownPayload, 1, 1, 0, ChatTypeInfo.SYSTEM.id) end)
end
equal(#SanctuaryDB.debugLog, 1, "one message on three frames is one debug entry")
equal(SanctuaryDB.debugLog[1].data.frameCount, 3, "carrying the three destinations")

-- H4 -- three messages on two frames, clock frozen: three entries.
ns.resetDebugLog()
for _ = 1, 3 do
    for _, frame in ipairs({ ChatFrame1, ChatFrame2 }) do
        pcall(function() frame:AddMessage(lockdownPayload, 1, 1, 0, ChatTypeInfo.SYSTEM.id) end)
    end
end
equal(#SanctuaryDB.debugLog, 3, "three messages are three entries even inside one burst window")
for _, entry in ipairs(SanctuaryDB.debugLog) do
    equal(entry.data.frameCount, 2, "each carrying its two destinations")
end

-- H5 -- with debug mode off the masking still happens, silently.
SanctuaryDB.debugEnabled = false
ns.resetDebugLog()
now = now + 5
ok, shown, journalled = sendSecretLine(ChatTypeInfo.SYSTEM.id)
equal(shown, 0, "the line is still masked with debug mode off")
equal(#SanctuaryDB.debugLog, 0, "and nothing at all is recorded")
SanctuaryDB.debugEnabled = true

-- H6 -- the journal option changes nothing either way.
for _, enabled in ipairs({ true, false }) do
    SanctuaryDB.logging.enabled = enabled
    ns.resetDebugLog()
    now = now + 5
    ok, shown, journalled = sendSecretLine(ChatTypeInfo.SYSTEM.id)
    equal(shown, 0, "masked whatever the journal option says")
    equal(journalled, 0, "and the journal is untouched either way")
end
SanctuaryDB.logging.enabled = true

-- H7 -- the lockdown reading is observed, never blocking.
local savedLockdownApi = C_ChatInfo.InChatMessagingLockdown
local LOCKDOWN_CASES = {
    { label = "API absent", api = nil, known = false, value = false },
    { label = "API answering false", api = function() return false end, known = true, value = false },
    { label = "API answering true", api = function() return true end, known = true, value = true },
    { label = "API returning a secret", api = function() return makeSecretValue("l") end,
      known = false, value = false },
    { label = "API raising", api = function() error("nope") end, known = false, value = false },
}
for _, case in ipairs(LOCKDOWN_CASES) do
    C_ChatInfo.InChatMessagingLockdown = case.api
    ns.resetDebugLog()
    now = now + 5
    ok, shown = sendSecretLine(ChatTypeInfo.SYSTEM.id)
    equal(shown, 0, "masked with " .. case.label)
    local entry = lastDebug("CHAT_OUTPUT")
    equal(entry and entry.data.chatLockdownKnown, case.known,
        case.label .. " is reported as known or not")
    equal(entry and entry.data.chatLockdown, case.value, case.label .. " reports its value")
end
C_ChatInfo.InChatMessagingLockdown = savedLockdownApi

-- H8 -- reversible without a /reload, through either store.
ns.resetDebugLog()
SanctuaryDB.filters.strictGroupInviteSystemMessages = false
now = now + 5
ok, shown = sendSecretLine(ChatTypeInfo.SYSTEM.id)
equal(shown, 1, "unticking the box shows the very next line")
SanctuaryDB.filters.strictGroupInviteSystemMessages = true
now = now + 5
ok, shown = sendSecretLine(ChatTypeInfo.SYSTEM.id)
equal(shown, 0, "and ticking it hides the one after")
SanctuaryCharDB.overrides.filters.strictGroupInviteSystemMessages = false
now = now + 5
ok, shown = sendSecretLine(ChatTypeInfo.SYSTEM.id)
equal(shown, 1, "a per-character override works the same way")
SanctuaryCharDB.overrides.filters.strictGroupInviteSystemMessages = nil

-- H9 -- complete silence: no chat line, no counter, no summary.
SanctuaryDB.notifications.mode = "verbose"
SanctuaryCharDB.sessionStats = { blockedCount = 0, blockedByType = {} }
chatMessages = {}
now = now + 5
sendSecretLine(ChatTypeInfo.SYSTEM.id)
equal(#chatMessages, 0, "a masked system line prints nothing, even in verbose mode")
equal(SanctuaryCharDB.sessionStats.blockedCount, 0, "and counts nothing")
SanctuaryDB.notifications.mode = "minimal"
now = now + 1000
chatMessages = {}
runTickers()
equal(#chatMessages, 0, "and produces no summary either")
SanctuaryDB.notifications.mode = "silent"

-- H11 -- the other contexts.
local CONTEXTS = {
    { label = "raid", setup = function() inGroup = true; inRaid = true; inInstance = true
        currentInstanceType = "raid" end, masked = true },
    { label = "a PvP match", setup = function() inGroup = true; inRaid = false; inInstance = true
        currentInstanceType = "pvp" end, masked = true },
    { label = "death in a raid", setup = function() inGroup = true; inRaid = true
        inInstance = true; playerDeadOrGhost = true end, masked = true },
    { label = "solo outside any instance", setup = function() inGroup = false; inRaid = false
        inInstance = false; currentInstanceType = "none"; playerDeadOrGhost = false end,
      masked = false },
}
for _, context in ipairs(CONTEXTS) do
    armStrictInInstance()
    context.setup()
    ns.resetDebugLog()
    now = now + 5
    ok, shown = sendSecretLine(ChatTypeInfo.SYSTEM.id)
    equal(shown, context.masked and 0 or 1, "in " .. context.label ..
        (context.masked and " the line is masked" or " the line is shown"))
end
playerDeadOrGhost = false

-- H13 -- a readable line during a lockdown keeps the existing path.
armStrictInInstance()
ns.addBlocked("Nuisance")
ns.invalidateWhitelist()
equal(dispatchChatFilter("CHAT_MSG_SYSTEM",
    string.format(ERR_INVITED_TO_GROUP_SS, "Nuisance", "Nuisance")), true,
    "a readable blocked invite line is still discarded by the registry")
equal(dispatchChatFilter("CHAT_MSG_SYSTEM", "an ordinary system line"), false,
    "and an ordinary readable line still gets through")
wipe(SanctuaryDB.blockedNames)
ns.invalidateWhitelist()

-- H14 -- the markers a recording is graded on.
armStrictInInstance()
ns.resetDebugLog()
now = now + 5
sendSecretLine(ChatTypeInfo.SYSTEM.id)
now = now + 5
sendSecretLine(99)
ns.captureDebugSnapshot("test")
local instanceMarkers = ns.getReportMarkers()
equal(instanceMarkers.secretSystemSuppressed, 1, "one masked line is counted")
equal(instanceMarkers.secretSystemVisible, 0, "and no system line got through")
equal(instanceMarkers.strictModeOn, true, "the snapshot says the enhanced box was ticked")

-- H19 -- the two switches reach the predicate.
armStrictInInstance()
SanctuaryDB.filters.scope = "blockedOnly"
ns.resetDebugLog()
now = now + 5
ok, shown = sendSecretLine(ChatTypeInfo.SYSTEM.id)
equal(shown, 1, "the open mode never masks a system line")
equal(lastDebug("CHAT_OUTPUT").data.reason, "filter_off", "and says the filter is off")
SanctuaryDB.filters.scope = "strangers"
SanctuaryDB.filters.preset = "all"
SanctuaryDB.filters.groupInvite = false
ns.resetDebugLog()
now = now + 5
ok, shown = sendSecretLine(ChatTypeInfo.SYSTEM.id)
equal(shown, 0, "the recommended preset masks it although groupInvite is stored false")

-- H17 -- the lockdown diagnostic, in an instance.
armStrictInInstance()
ns.resetDebugLog()
local armedLine = ns.formatChatDiagnosticResult(ns.runChatDiagnostic("lockdown"))
check(armedLine:find("armed=yes", 1, true) ~= nil, "in a dungeon the diagnostic reports it armed")
check(armedLine:find("context=instance", 1, true) ~= nil, "and names the context")
equal(ns.getReportMarkers().lockdownArmedInInstance, true,
    "and the recording carries the marker the session step claims")

ChatFrame2 = nil
ChatFrame3 = nil
resetModelState()
SanctuaryDB.filters.preset = "custom"

-- ===========================================================================
-- SECTION UI: the interface file, under a widget mock
-- ===========================================================================

-- Everything above runs without SanctuaryUI.lua, and it stays that way: the
-- interface is loaded here, last, with a richer CreateFrame installed only from
-- this point on. Nothing before this line can be affected by it.
--
-- The point is not to test pixels. It is that the checklist steps which used to
-- read "open the five tabs, check the labels, read the status bar" are checks a
-- machine can make, and every one of them left manual was one more minute the
-- maintainer paid for.

unpack = unpack or table.unpack
tinsert = table.insert
tremove = table.remove
UIParent = { }
ReloadUI = function() end
GameFontNormal, GameFontNormalLarge, GameFontNormalSmall = "GameFontNormal", "GameFontNormalLarge", "GameFontNormalSmall"
GameFontHighlight, GameFontHighlightSmall, ChatFontNormal = "GameFontHighlight", "GameFontHighlightSmall", "ChatFontNormal"
UISpecialFrames = {}
GameTooltip = setmetatable({}, { __index = function(t, k)
    local fn = function() end
    rawset(t, k, fn)
    return fn
end })

local createdWidgets = {}

-- Auto-stubbed methods, but only for keys that look like widget methods --
-- every WoW widget method starts with a capital, and every data field the
-- addon hangs on a frame (`entry.nameLabel`, `btn.label`, `dialog.which`)
-- starts lowercase. Stubbing those too would turn `if not entry.nameLabel` into
-- a permanently false test and quietly break the pooling logic.
local widgetMeta
widgetMeta = {
    __index = function(t, key)
        if type(key) == "string" and key:match("^%u") then
            local stub = function() return nil end
            rawset(t, key, stub)
            return stub
        end
        return nil
    end,
}

local function newWidget(kind, name, parent)
    local w = setmetatable({}, widgetMeta)
    w.__kind = kind
    w.__name = name
    w.__parent = parent
    w.__scripts = {}
    w.__children = {}
    w.__shown = true
    w.__text = ""
    w.__width, w.__height = 620, 480

    function w:GetParent() return self.__parent end
    function w:SetParent(p) self.__parent = p end
    function w:GetName() return self.__name end
    function w:SetSize(width, height) self.__width, self.__height = width, height end
    function w:SetWidth(width) self.__width = width end
    function w:SetHeight(height) self.__height = height end
    function w:GetWidth() return self.__width end
    function w:GetHeight() return self.__height end
    function w:SetText(text) self.__text = text end
    function w:GetText() return self.__text end
    function w:Insert(text) self.__text = (self.__text or "") .. tostring(text) end
    function w:GetStringHeight() return 12 end
    function w:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
    function w:SetChecked(value) self.__checked = value and true or false end
    function w:GetChecked() return self.__checked and true or false end
    function w:IsShown() return self.__shown and true or false end
    function w:SetScript(script, callback) self.__scripts[script] = callback end
    function w:GetScript(script) return self.__scripts[script] end
    function w:HookScript(script, callback) self.__scripts[script] = callback end
    function w:GetAlpha() return self.__alpha or 1 end
    function w:SetAlpha(value) self.__alpha = value end
    function w:RegisterEvent(event)
        self.__events = self.__events or {}
        self.__events[event] = true
    end
    function w:UnregisterEvent(event)
        if self.__events then self.__events[event] = nil end
    end
    function w:Show()
        self.__shown = true
        local onShow = self.__scripts.OnShow
        if onShow then onShow(self) end
    end
    function w:Hide()
        self.__shown = false
        local onHide = self.__scripts.OnHide
        if onHide then onHide(self) end
    end
    function w:CreateFontString(fsName, _, _)
        local fs = newWidget("FontString", fsName, self)
        self.__children[#self.__children + 1] = fs
        return fs
    end
    function w:CreateTexture(texName)
        local tex = newWidget("Texture", texName, self)
        self.__children[#self.__children + 1] = tex
        return tex
    end
    function w:SetScrollChild(child) self.__scrollChild = child end
    function w:GetScrollChild() return self.__scrollChild end
    function w:Click()
        local onClick = self.__scripts.OnClick
        if onClick then onClick(self) end
    end

    if name then _G[name] = w end
    createdWidgets[#createdWidgets + 1] = w
    return w
end

local coreCreateFrame = CreateFrame
function CreateFrame(frameType, name, parent, template)
    local w = newWidget(frameType or "Frame", name, parent)
    if parent and parent.__children then
        parent.__children[#parent.__children + 1] = w
    end
    return w
end

-- The interface registers PLAYER_LOGIN on its own frame; the core frame keeps
-- the events it registered before this mock replaced CreateFrame.
assert(loadfile(repoRoot .. "/SanctuaryUI.lua"))("Sanctuary", ns)
check(type(ns.ToggleUI) == "function", "the interface file exports its toggle")
check(coreCreateFrame ~= nil, "the core CreateFrame mock stays reachable")

-- ---------------------------------------------------------------------------
-- Every localized key the two Lua files ask for actually exists
-- ---------------------------------------------------------------------------

-- Replaces "read every label in the five tabs and check none is empty". A
-- missing key renders as an empty widget in game, which is exactly the kind of
-- defect a human reads past.
local function collectLocaleKeys(path)
    local handle = assert(io.open(path, "r"))
    local source = handle:read("a")
    handle:close()
    local keys = {}
    for key in source:gmatch('L%["([%w_]+)"%]') do
        keys[key] = true
    end
    return keys
end

local usedKeys = {}
for _, file in ipairs({ "/Sanctuary.lua", "/SanctuaryUI.lua" }) do
    for key in pairs(collectLocaleKeys(repoRoot .. file)) do
        usedKeys[key] = true
    end
end

local missingKeys = {}
for key in pairs(usedKeys) do
    local value = ns.L[key]
    if type(value) ~= "string" or value == "" then
        missingKeys[#missingKeys + 1] = key
    end
end
table.sort(missingKeys)
equal(#missingKeys, 0,
    "every L[] key used by the addon resolves to a non-empty string ("
    .. table.concat(missingKeys, ", ") .. ")")

-- ---------------------------------------------------------------------------
-- The French locale covers every key the default locale defines
-- ---------------------------------------------------------------------------

-- The addon ships French as an override block. A key added to the default and
-- forgotten there shows up in English in a French client -- readable, so nobody
-- reports it, and it drifts.
local realGetLocale = GetLocale
local function loadLocale(locale)
    GetLocale = function() return locale end
    local scoped = {}
    assert(loadfile(repoRoot .. "/Locales.lua"))("Sanctuary", scoped)
    GetLocale = realGetLocale
    return scoped.L
end

local defaultLocale = loadLocale("enUS")
local frenchLocale = loadLocale("frFR")
local untranslated = {}
for key, value in pairs(defaultLocale) do
    if frenchLocale[key] == value and usedKeys[key] then
        untranslated[#untranslated + 1] = key
    end
end
table.sort(untranslated)
-- Format strings and a handful of proper nouns are identical in both locales on
-- purpose; the check is that nothing NEW slips through untranslated, so the
-- list is compared against the keys that were already like that.
local KNOWN_IDENTICAL = {
    DATE_FORMAT = true, TAB_SUSPECTS = true, TAB_WHITELIST = true, TAB_LOGS = true,
    GROUP_DEBUG = true, TAB_DIAGNOSTICS = true, LOGS_GROUP_HEADER = true,
    WL_GROUP_ROW = true, DIAG_ARG_FILTER = true,
    -- Already identical before this lot: proper nouns, format strings and words
    -- French borrows unchanged. Listed rather than filtered out so that adding a
    -- new one is a deliberate act.
    ABOUT_VERSION = true, GROUP_COMMUNICATION = true, GROUP_INTERACTIONS = true,
    GROUP_NOTIFICATIONS = true, LOG_TYPE_DUEL = true, LOG_TYPE_EMOTE = true,
    LOG_TYPE_INVITE = true, LOG_TYPE_WHISPER = true, NOTIF_MINIMAL = true,
    -- 0.4.0: proper nouns and format strings that read the same in both
    -- languages. Listed rather than filtered out so adding one is deliberate.
    ADV_DIAG_TITLE = true, ADV_JOURNAL_TITLE = true, EXPORT_COLUMNS = true,
    PANEL_BLOCKED_PATTERNS = true, WL_BNET_ROW = true, TAB_PROTECTION = true,
    TAB_JOURNAL = true, TAB_DIAGNOSTICS = true, KIND_DUEL = true,
    Q3_MINIMAL_TITLE = true, LOG_TYPE_DUEL = true, ABOUT_VERSION = true,
    LOGS_GROUP_HEADER = true, DATE_FORMAT = true, DIAG_ARG_FILTER = true,
}
local unexpected = {}
for _, key in ipairs(untranslated) do
    if not KNOWN_IDENTICAL[key] then unexpected[#unexpected + 1] = key end
end
equal(#unexpected, 0,
    "every used key is translated in frFR (" .. table.concat(unexpected, ", ") .. ")")

-- ---------------------------------------------------------------------------
-- No locale key is dead
-- ---------------------------------------------------------------------------

-- Keys are often looked up by a computed name (L[row.labelKey]), so the check
-- is "does this name appear anywhere in the two Lua files" rather than "is it
-- written as L[...]". A key nobody can reach is a translation nobody will ever
-- read and a line a reviewer has to rule out by hand.
local addonSource = {}
for _, file in ipairs({ "/Sanctuary.lua", "/SanctuaryUI.lua" }) do
    local handle = assert(io.open(repoRoot .. file, "r"))
    addonSource[#addonSource + 1] = handle:read("a")
    handle:close()
end
local joinedSource = table.concat(addonSource, "\n")
local deadKeys = {}
for key in pairs(defaultLocale) do
    if not joinedSource:find(key, 1, true) then deadKeys[#deadKeys + 1] = key end
end
table.sort(deadKeys)
equal(#deadKeys, 0,
    "no locale key is defined without a surface (" .. table.concat(deadKeys, ", ") .. ")")

-- ---------------------------------------------------------------------------
-- No visible value carries the words the interface got rid of
-- ---------------------------------------------------------------------------

-- "Whitelist" and "blacklist" are gone from the screen: the person protecting
-- themselves should not have to learn a vocabulary. And "passer" was banned for
-- being untrue -- a name is never "let through", it is simply not blocked.
local BANNED_WORDS = { "whitelist", "blacklist", " passe" }
local offenders = {}
for _, locale in ipairs({ defaultLocale, frenchLocale }) do
    for key, value in pairs(locale) do
        if type(value) == "string" then
            local lowered = value:lower()
            for _, word in ipairs(BANNED_WORDS) do
                if lowered:find(word, 1, true) then
                    offenders[#offenders + 1] = key .. " (" .. word .. ")"
                end
            end
        end
    end
end
table.sort(offenders)
equal(#offenders, 0,
    "no visible string carries a banned word (" .. table.concat(offenders, ", ") .. ")")

-- ---------------------------------------------------------------------------
-- Every locale value is valid UTF-8
-- ---------------------------------------------------------------------------

-- Accented characters are written as decimal escapes ("\194\176" for a degree
-- sign), and a mistyped second byte produces a broken sequence that the parity
-- check cannot see: the key exists on both sides, only its bytes are wrong. WoW
-- renders such a string with a replacement glyph or truncates it at the bad
-- byte, so the check is on the bytes themselves.
local invalidUtf8 = {}
for _, entry in ipairs({ { "enUS", defaultLocale }, { "frFR", frenchLocale } }) do
    for key, value in pairs(entry[2]) do
        if type(value) == "string" and not utf8.len(value) then
            invalidUtf8[#invalidUtf8 + 1] = entry[1] .. "." .. key
        end
    end
end
table.sort(invalidUtf8)
equal(#invalidUtf8, 0,
    "every locale value is valid UTF-8 (" .. table.concat(invalidUtf8, ", ") .. ")")

-- ---------------------------------------------------------------------------
-- The four tabs open, and the fifth only in debug mode
-- ---------------------------------------------------------------------------

SanctuaryDB.debugEnabled = false
ns.ToggleUI()
local mainFrame = _G.SanctuaryMainFrame
check(mainFrame ~= nil, "the main window is built")
check(mainFrame:IsShown(), "the main window opens on the first toggle")

for _, key in ipairs({ "protection", "journal", "advanced", "about" }) do
    local tab = _G["SanctuaryTab_" .. key]
    check(tab ~= nil and tab:IsShown(), "the " .. key .. " tab is offered")
    tab:Click()
    local content = _G["SanctuaryTabContent_" .. key]
    check(content ~= nil and content:IsShown(), "the " .. key .. " tab opens its content")
end

-- The debug panel is not a user surface: with debug mode off its button is not
-- even laid out, and clicking a stale reference to it does nothing.
local diagTab = _G["SanctuaryTab_diagnostics"]
local diagContent = _G["SanctuaryTabContent_diagnostics"]
check(diagTab ~= nil, "the diagnostics tab button exists")
equal(diagTab:IsShown(), false, "the diagnostics tab stays hidden while debug mode is off")
diagTab:Click()
equal(diagContent:IsShown(), false, "clicking a hidden diagnostics tab opens nothing")

SanctuaryDB.debugEnabled = true
mainFrame:Hide()
mainFrame:Show()
equal(diagTab:IsShown(), true, "ticking debug mode reveals the diagnostics tab")
diagTab:Click()
equal(diagContent:IsShown(), true, "the diagnostics tab opens once debug mode is on")

SanctuaryDB.debugEnabled = false
mainFrame:Hide()
mainFrame:Show()
equal(diagTab:IsShown(), false, "unticking debug mode hides the diagnostics tab again")
equal(diagContent:IsShown(), false, "unticking debug mode closes the panel it was showing")
equal(_G["SanctuaryTabContent_protection"]:IsShown(), true,
    "closing the debug panel falls back to a tab that still exists")

-- ---------------------------------------------------------------------------
-- Question 1: the mode switch, and what it greys out
-- ---------------------------------------------------------------------------

_G["SanctuaryTab_protection"]:Click()
_G.SanctuaryQ1_blockedOnly:Click()
equal(SanctuaryDB.filters.scope, "blockedOnly", "clicking the second card writes the scope")
equal(_G.SanctuaryQ2_all.enabled, false, "question 2 is greyed out with it")
equal(_G.SanctuaryQ2_custom.enabled, false, "both of its cards")
equal(_G.SanctuaryStrictCheck.enabled, false, "and so is the enhanced-instance box")
-- Greyed out, not removed: the answers are still there and come back untouched.
check(_G.SanctuaryQ2_all:IsShown(), "question 2 is greyed out, never removed")
_G.SanctuaryQ1_strangers:Click()
equal(SanctuaryDB.filters.scope, "strangers", "and the first card writes it back")
equal(_G.SanctuaryQ2_all.enabled, true, "question 2 comes back")
equal(_G.SanctuaryStrictCheck.enabled, true, "and so does the enhanced-instance box")

-- ---------------------------------------------------------------------------
-- Question 2: the preset, the boxes, and the box that lives in both modes
-- ---------------------------------------------------------------------------

_G.SanctuaryQ2_custom:Click()
equal(SanctuaryDB.filters.preset, "custom", "\"I choose\" writes the preset")
equal(_G.SanctuaryChoose:IsShown(), true, "and unfolds the detailed boxes")
local storedWhisper = SanctuaryDB.filters.whisper
_G.SanctuaryFilter_whisper:Click()
equal(SanctuaryDB.filters.whisper, not storedWhisper, "a box writes its own key")
_G.SanctuaryFilter_whisper:Click()
equal(SanctuaryDB.filters.whisper, storedWhisper, "and writes it back")
_G.SanctuaryChannel_all:Click()
equal(SanctuaryDB.filters.channelMode, "all", "a channel radio writes the channel mode")
_G.SanctuaryChannel_none:Click()
equal(SanctuaryDB.filters.channelMode, "none", "and the first one writes it back")
check(_G.SanctuaryStrictCheck:IsShown(), "the enhanced-instance box is visible in \"I choose\"")

_G.SanctuaryQ2_all:Click()
equal(SanctuaryDB.filters.preset, "all", "\"Everything\" writes the preset")
equal(_G.SanctuaryChoose:IsShown(), false, "and folds the detailed boxes away")
check(_G.SanctuaryStrictCheck:IsShown(), "the enhanced-instance box stays visible in \"Everything\"")
_G.SanctuaryStrictCheck:Click()
equal(SanctuaryDB.filters.strictGroupInviteSystemMessages, true,
    "it is tickable in the recommended preset too")
equal(ns.isFilterOn("strictGroupInviteSystemMessages"), true, "and the core applies it")
_G.SanctuaryStrictCheck:Click()
equal(SanctuaryDB.filters.strictGroupInviteSystemMessages, false, "and untickable again")

-- ---------------------------------------------------------------------------
-- Question 3
-- ---------------------------------------------------------------------------

_G.SanctuaryQ3_verbose:Click()
equal(SanctuaryDB.notifications.mode, "verbose", "the third card writes the notification mode")
_G.SanctuaryQ3_minimal:Click()
equal(SanctuaryDB.notifications.mode, "minimal", "the second card too")
_G.SanctuaryQ3_silent:Click()
equal(SanctuaryDB.notifications.mode, "silent", "and the first one puts it back to silence")

-- ---------------------------------------------------------------------------
-- Question 4: the tiles, and the name tester
-- ---------------------------------------------------------------------------

guildMembers = { "Guildmate-TestRealm", "Officer-TestRealm" }
inGuild = true
bnetFriends = {
    { accountName = "RealFriend#1234", bnetAccountID = 77,
      gameAccountInfo = { characterName = "Bnetchar" } },
    { accountName = "OfflineFriend#5678", bnetAccountID = 78 },
}
charFriends = {}
ns.addAllowed("Toto")
ns.addBlocked("Xxxxxxx-Ysondre")
-- Not "test": the harness realm is TestRealm, and a pattern is a substring.
ns.addPattern("spam")
fire("GUILD_ROSTER_UPDATE")
ns.refreshUI()

local counts = ns.getListCounts()
equal(counts.allowed.bnet, 2, "both Battle.net accounts are counted once each")
equal(counts.blocked.names, 1, "the blocked names are counted")
equal(counts.blocked.patterns, 1, "and the patterns separately")
equal(_G.SanctuaryTileAllowed.count:GetText(), tostring(counts.allowed.total),
    "the allowed tile shows the count the decision uses")
equal(_G.SanctuaryTileBlocked.count:GetText(), tostring(counts.blocked.total),
    "and so does the blocked tile")
check(_G.SanctuaryTileAllowed.detail:GetText():find("2", 1, true) ~= nil,
    "the allowed tile details its Battle.net half")

-- The eight answers of the validated board, driven the way the field is: one
-- OnTextChanged per keystroke.
local function testAnswerFor(name)
    _G.SanctuaryTestInput:SetText(name)
    _G.SanctuaryTestInput:GetScript("OnTextChanged")(_G.SanctuaryTestInput)
    return _G.SanctuaryTestAnswer:GetText() or ""
end

check(testAnswerFor("Toto"):find(ns.L["LIST_MANUAL"], 1, true) ~= nil,
    "a name added by hand is answered as such")
check(testAnswerFor("Bnetchar"):find("RealFriend#1234", 1, true) ~= nil,
    "a Battle.net friend's character names the account")
check(testAnswerFor("Officer-TestRealm"):find(ns.L["LIST_GUILD"], 1, true) ~= nil,
    "a guild member is answered as a guild member")
check(testAnswerFor("Xxxxxxx-Ysondre"):find(ns.L["LIST_BLOCKED"], 1, true) ~= nil,
    "a blocked name is answered as blocked")
check(testAnswerFor("Superspam"):find("spam", 1, true) ~= nil,
    "a pattern match names the pattern")
check(testAnswerFor("Zorglub"):find(string.format(ns.L["TEST_UNKNOWN_BLOCKED"], "Zorglub"), 1, true) ~= nil,
    "an unknown name is blocked while question 1 filters strangers")
SanctuaryDB.filters.scope = "blockedOnly"
check(testAnswerFor("Zorglub"):find(string.format(ns.L["TEST_UNKNOWN_ALLOWED"], "Zorglub"), 1, true) ~= nil,
    "and allowed in the other mode")
SanctuaryDB.filters.scope = "strangers"
-- The last line of the board: blocked wins over allowed, and the answer names
-- the list it overrides rather than silently dropping it.
ns.addBlocked("Bnetchar")
local overriddenAnswer = testAnswerFor("Bnetchar")
check(overriddenAnswer:find(string.format(ns.L["TEST_ALWAYS_BLOCKED"], "Bnetchar", ""):sub(1, 24), 1, true) ~= nil,
    "a blocked Battle.net friend is answered as blocked even so")
check(overriddenAnswer:find("RealFriend#1234", 1, true) ~= nil,
    "and the answer still names the Battle.net account it overrides")
ns.removeBlocked(ns.normalizeBlockedKey("Bnetchar"))
equal(ns.describeAccessDecision("").valid, false, "an empty field asks nothing")

-- ---------------------------------------------------------------------------
-- The allowed panel
-- ---------------------------------------------------------------------------

local function panelRowTexts(panel)
    local texts = {}
    local function walk(widget)
        for _, childWidget in ipairs(widget.__children or {}) do
            if childWidget.__shown ~= false then
                if childWidget.label then
                    texts[#texts + 1] = tostring(childWidget.label.__text or "")
                end
                if childWidget.__kind == "FontString" then
                    texts[#texts + 1] = tostring(childWidget.__text or "")
                end
                -- Hidden widgets are not walked into: a pooled chip that was put
                -- away still owns a visible FontString, and counting it would
                -- make a removed name look like it is still on screen.
                walk(childWidget)
            end
        end
    end
    walk(panel)
    return table.concat(texts, "\n")
end

ns.OpenPanel("allowed")
local allowedPanel = _G.SanctuaryPanelAllowed
check(allowedPanel ~= nil and allowedPanel:IsShown(), "the allowed panel opens")
local rendered = panelRowTexts(allowedPanel)
check(rendered:find(ns.L["WL_SOURCE_BNET"], 1, true) ~= nil, "it groups the Battle.net friends")
check(rendered:find("Toto", 1, true) ~= nil, "and shows the names added by hand")
check(rendered:find("RealFriend#1234", 1, true) == nil,
    "the automatic groups stay folded, so the panel does not spill a friends list")
check(rendered:find(ns.L["WL_GROUP_NOTE"], 1, true) ~= nil,
    "and the current group is a line, not a list")

-- Unfolding shows "Character . Account" for a connected friend, and the account
-- alone for one who is offline.
local bnetHeader
local function findRow(panel, needle)
    local found
    local function walk(widget)
        for _, childWidget in ipairs(widget.__children or {}) do
            if childWidget.label and tostring(childWidget.label.__text or ""):find(needle, 1, true) then
                found = found or childWidget
            end
            walk(childWidget)
        end
    end
    walk(panel)
    return found
end
bnetHeader = findRow(allowedPanel, ns.L["WL_SOURCE_BNET"])
check(bnetHeader ~= nil, "the Battle.net group header is clickable")
bnetHeader:Click()
rendered = panelRowTexts(allowedPanel)
check(rendered:find("Bnetchar", 1, true) ~= nil, "unfolding lists the connected friend's character")
check(rendered:find("RealFriend#1234", 1, true) ~= nil, "next to the account")
check(rendered:find(string.format(ns.L["WL_BNET_OFFLINE"], "OfflineFriend#5678"), 1, true) ~= nil,
    "and an offline friend by account alone")

-- Adding through the field, removing through the cross, and Undo.
_G.SanctuaryAllowedAddInput:SetText("Titi")
findRow(allowedPanel, ns.L["PANEL_ADD_BTN"]):Click()
check(SanctuaryDB.manualWhitelist.titi ~= nil, "the field adds a name")
ns.refreshUI()
local titiChip = findRow(allowedPanel, "Titi")
check(titiChip ~= nil, "the added name gets a chip")
titiChip.remove:Click()
equal(SanctuaryDB.manualWhitelist.titi, nil, "the cross removes it without asking")
check(_G.SanctuaryUndoLine:IsShown(), "and offers to undo")
_G.SanctuaryUndoLine.button:Click()
check(SanctuaryDB.manualWhitelist.titi ~= nil, "undo puts it back")
equal(_G.SanctuaryUndoLine:IsShown(), false, "and the offer goes away")

-- A removal that is not undone expires instead of coming back.
titiChip = findRow(allowedPanel, "Titi")
titiChip.remove:Click()
equal(SanctuaryDB.manualWhitelist.titi, nil, "removed again")
runTimers(2)
equal(SanctuaryDB.manualWhitelist.titi, nil, "an expired undo offer restores nothing")

do

-- "Added by you" and "Automatically trusted" read the same table: a contact the
-- five-minute group rule added carries source = "trust". Listed in both, the
-- tester sees one name in two places and a counter that credits her with a name
-- she never typed. The 0.3.2 lists the schema reset carries forward are full of
-- them, so this shows on the very first opening.
local function addedCount()
    return tonumber(tostring(allowedPanel.addedSection.count:GetText()):match("%d+"))
end
local addedBefore = addedCount()
local countsBefore = ns.getListCounts()
ns.addAllowed("Handy")
ns.addAllowed("Trusty", "trust")
ns.refreshUI()
local countsAfter = ns.getListCounts()
equal(countsAfter.allowed.manual, countsBefore.allowed.manual + 1,
    "the model counts one more name typed by hand")
equal(countsAfter.allowed.trust, countsBefore.allowed.trust + 1,
    "and one more contact the group rule trusted")
equal(addedCount(), addedBefore + 1,
    "so 'Added by you' gains exactly one label, not two")

-- The home screen tile carries the same sentence as that section -- "%s added
-- by you" -- and was left counting the trusted contacts in with the typed ones,
-- so the two surfaces contradicted each other on the more visible of the two.
local tileDetail = tostring(_G.SanctuaryTileAllowed.detail.__text or "")
equal(tonumber(tileDetail:match("^(%d+)")), addedCount(),
    "and the tile on the home screen says the same number as that section")
rendered = panelRowTexts(allowedPanel)
check(rendered:find("Handy", 1, true) ~= nil, "the name typed by hand has its chip")
check(rendered:find("Trusty", 1, true) == nil,
    "while the trusted contact stays inside its own folded group")

-- And it is really in that group, not lost: unfolding shows it once.
local trustHeader = findRow(allowedPanel, ns.L["WL_SOURCE_TRUST"])
check(trustHeader ~= nil, "the trust group has its header")
check(tostring(trustHeader.label.__text or ""):find("(1)", 1, true) ~= nil,
    "which counts the one trusted contact")
trustHeader:Click()
rendered = panelRowTexts(allowedPanel)
check(rendered:find("Trusty", 1, true) ~= nil, "and unfolding is where it shows up")
trustHeader = findRow(allowedPanel, ns.L["WL_SOURCE_TRUST"])
trustHeader:Click()

ns.removeAllowed("handy")
ns.removeAllowed("trusty")
ns.refreshUI()

end

-- ---------------------------------------------------------------------------
-- The ten-second refresh
-- ---------------------------------------------------------------------------

-- Created when the panel opens, cancelled when it closes: a ticker that outlives
-- its panel rebuilds a list nobody is looking at, for the whole session.
local tickersBefore = #tickers
ns.ClosePanel()
ns.OpenPanel("allowed")
equal(#tickers, tickersBefore + 1, "opening the panel creates its refresh ticker")

_G.SanctuaryAllowedAddInput:SetText("Halftyped")
guildMembers = { "Guildmate-TestRealm", "Officer-TestRealm", "Newcomer-TestRealm" }
fire("GUILD_ROSTER_UPDATE")
local guildHeader = findRow(allowedPanel, ns.L["WL_SOURCE_GUILD"])
guildHeader:Click()
runTickers()
check(panelRowTexts(allowedPanel):find("Newcomer-TestRealm", 1, true) ~= nil,
    "a guild member added mid-session shows up on the tick")
equal(_G.SanctuaryAllowedAddInput:GetText(), "Halftyped",
    "and the text being typed is never touched")

-- A redraw only happens when the model changed: the signature is what the tick
-- compares, so a quiet tick does not repaint under the cursor.
local repaints = 0
local watched = findRow(allowedPanel, "Toto")
local savedSetText = watched.label.SetText
watched.label.SetText = function(self, value)
    repaints = repaints + 1
    return savedSetText(self, value)
end
runTickers()
equal(repaints, 0, "a tick with nothing new repaints nothing")
watched.label.SetText = savedSetText

-- An entry removed by hand is not resurrected by the next tick.
ns.removeAllowed("toto")
runTickers()
check(panelRowTexts(allowedPanel):find("Toto", 1, true) == nil,
    "an entry removed by hand is not put back by the ticker")
ns.addAllowed("Toto")
clearUndoForTests = nil

ns.ClosePanel()
equal(#tickers, tickersBefore + 1, "closing the panel does not create another one")

-- ---------------------------------------------------------------------------
-- The blocked panel
-- ---------------------------------------------------------------------------

ns.OpenPanel("blocked")
local blockedPanel = _G.SanctuaryPanelBlocked
check(blockedPanel ~= nil and blockedPanel:IsShown(), "the blocked panel opens")
check(panelRowTexts(blockedPanel):find("Xxxxxxx-Ysondre", 1, true) ~= nil,
    "it lists the blocked names")
check(panelRowTexts(blockedPanel):find("test", 1, true) ~= nil, "and the patterns")

_G.SanctuaryBlockedAddInput:SetText("Toto")
check(ns.addBlocked("Toto"), "a name already in the allowed list can be blocked")
check(SanctuaryDB.manualWhitelist.toto ~= nil,
    "and blocking it does not silently delete the entry the person typed")
local blockedNow, blockedReason = ns.getCharacterDecision("Toto")
equal(blockedNow, true, "the decision changes immediately")
equal(blockedReason, "blocked_name", "and names the list that decided")
ns.removeBlocked("toto")
equal(select(1, ns.getCharacterDecision("Toto")), false, "removing it changes the decision back")

_G.SanctuaryPatternAddInput:SetText("  Sp Spam ")
check(ns.addPattern("  Sp Spam "), "a pattern is normalised on the way in")
local normalisedPattern = false
for _, value in ipairs(SanctuaryDB.keywords) do
    if value == "spspam" then normalisedPattern = true end
end
check(normalisedPattern, "spaces and case are stripped")
equal(ns.addPattern("SPSPAM"), false, "and a duplicate is a no-op")
ns.ClosePanel()

-- ---------------------------------------------------------------------------
-- The header control
-- ---------------------------------------------------------------------------

local stateButton = _G.SanctuaryStateButton
check(stateButton ~= nil, "the header carries the single state control")
stateButton:Click()
equal(SanctuaryCharDB.overrides.enabled, false, "clicking it turns protection off")
equal(stateButton.label:GetText(), ns.L["HEADER_STATE_OFF"], "and the label says so")
stateButton:Click()
equal(ns.isEnabled(), true, "clicking again turns it back on")
equal(stateButton.label:GetText(), ns.L["HEADER_STATE_ON"], "and the label follows")

-- ---------------------------------------------------------------------------
-- The journal
-- ---------------------------------------------------------------------------

_G["SanctuaryTab_journal"]:Click()
wipe(SanctuaryDB.log)
ns.refreshUI()
local journalContent = _G["SanctuaryTabContent_journal"]
check(panelRowTexts(journalContent):find(ns.L["LOGS_EMPTY"], 1, true) ~= nil,
    "an empty journal says so instead of showing nothing")

SanctuaryDB.log = {
    { t = 100, d = "2026-08-21 20:14:02", type = "groupInvite", name = "Xxxxxxx", realm = "Royaume" },
    { t = 90, d = "2026-08-21 20:13:41", type = "whisper", name = "Xxxxxxx", realm = "Royaume", msg = "slt" },
    { t = 50, d = "2026-08-21 19:02:00", type = "group", name = "Yyyyy", realm = "Royaume" },
}
ns.refreshUI()
rendered = panelRowTexts(journalContent)
check(rendered:find("Xxxxxxx-Royaume", 1, true) ~= nil, "the journal groups by name")
check(rendered:find("(2)", 1, true) ~= nil, "and counts each group")
local groupRow = findRow(journalContent, "Xxxxxxx-Royaume")
groupRow:Click()
rendered = panelRowTexts(journalContent)
check(rendered:find(ns.L["LOG_TYPE_INVITE"], 1, true) ~= nil,
    "unfolding shows the localized type of each entry")
equal(ns.getLogEntryDisplayType({ type = "group" }), ns.L["LOG_TYPE_GROUP"],
    "the group-chat type has a label of its own")

-- The message column starts off. The text is recorded either way -- only the
-- display is withheld: on an addon whose job is to shield someone from
-- harassment, printing what was sent to them is something they ask for.
equal(SanctuaryDB.uiSettings.showMessageColumn, false,
    "the message column is off by default once the file carries schema 2")
equal(_G.SanctuaryJournalShowMessages:GetChecked(), false,
    "and the Journal box reads unticked")
check(rendered:find("slt", 1, true) == nil,
    "an unfolded blocked whisper does not show its text")
_G.SanctuaryJournalShowMessages:Click()
rendered = panelRowTexts(journalContent)
check(rendered:find("slt", 1, true) ~= nil, "ticking the option brings the text out")
_G.SanctuaryJournalShowMessages:Click()
rendered = panelRowTexts(journalContent)
check(rendered:find("slt", 1, true) == nil, "and unticking it hides the text again")

-- Copying opens the window with the journal in it, types localized.
findRow(journalContent, ns.L["LOGS_COPY_BTN"]):Click()
local exportFrame = _G.SanctuaryExportFrame
check(exportFrame ~= nil and exportFrame:IsShown(), "copying the journal opens the copy window")
check(exportFrame.box:GetText():find(ns.L["LOG_TYPE_INVITE"], 1, true) ~= nil,
    "and the copied text carries the same type labels as the tab")
exportFrame:Hide()
wipe(SanctuaryDB.log)

-- ---------------------------------------------------------------------------
-- Advanced
-- ---------------------------------------------------------------------------

SanctuaryDB.debugEnabled = true
mainFrame:Hide()
mainFrame:Show()
_G["SanctuaryTab_advanced"]:Click()
local advancedContent = _G["SanctuaryTabContent_advanced"]

local trustBefore = SanctuaryDB.filters.autoTrust and true or false
_G.SanctuaryAutoTrust:Click()
equal(SanctuaryDB.filters.autoTrust, not trustBefore, "the auto-trust box writes its key")
_G.SanctuaryAutoTrust:Click()
equal(SanctuaryDB.filters.autoTrust, trustBefore, "and writes it back")

-- The report: the summary first, then the recording.
findRow(advancedContent, ns.L["DEBUG_EXPORT_BTN"]):Click()
exportFrame = _G.SanctuaryExportFrame
check(exportFrame:IsShown(), "exporting the report opens the copy window")
local reportText = exportFrame.box:GetText()
local summaryAt = reportText:find("RESUME DE RELEVE", 1, true)
local eventLogAt = reportText:find("EVENT LOG", 1, true)
check(summaryAt ~= nil, "the report opens on the summary")
check(eventLogAt ~= nil, "and carries the event log")
check(summaryAt and eventLogAt and summaryAt < eventLogAt, "in that order")
check(reportText:find(ns.L["DEBUG_SUMMARY_FILE"], 1, true) == nil,
    "and drops the go-and-find-the-file note, since this window IS the transport")
exportFrame:Hide()

-- The copy window scrolls. Its scroll child was sized once at build time, like
-- the diagnostics column, so the range measured zero: the wheel did nothing, the
-- bar never appeared, and everything past the first screenful was unreachable --
-- while step B.1 asks the tester to read the header "then the log after it", and
-- D.6 the same of "Copy the log". Ctrl+A still copied it all; nobody could read
-- it.
-- Scoped: this file is one long function and Lua caps a function at 200 live
-- locals, so a self-contained case declares its own inside a block.
do
    local exportScroll = _G.SanctuaryExportScroll
    check(exportScroll ~= nil, "the copy window has a scroll of its own")
    local longLines = {}
    for i = 1, 200 do longLines[i] = "line " .. i end
    ns.ShowTextWindow("long", table.concat(longLines, "\n"))
    check((exportScroll.child:GetHeight() or 0) > (exportScroll:GetHeight() or 0),
        "200 lines make the content taller than the window")
    equal(exportScroll.bar:IsShown(), true, "so the bar says it scrolls")
    equal(exportFrame.box:GetHeight(), exportScroll.child:GetHeight(),
        "and the box that draws the lines is as tall as the child, so none are clipped")
    ns.ShowTextWindow("short", "one line")
    check((exportScroll.child:GetHeight() or 0) <= (exportScroll:GetHeight() or 0),
        "a short text does not pretend to scroll")
    equal(exportScroll.bar:IsShown(), false, "with no bar left over")
end
exportFrame:Hide()

-- The journal size is clamped on write, so nobody leaves thinking they set 50.
_G.SanctuaryMaxEntriesInput:SetText("50")
_G.SanctuaryMaxEntriesInput:GetScript("OnEnterPressed")(_G.SanctuaryMaxEntriesInput)
equal(SanctuaryDB.logging.maxEntries, 100, "a journal size below the floor is clamped up")
_G.SanctuaryMaxEntriesInput:SetText("999999")
_G.SanctuaryMaxEntriesInput:GetScript("OnEnterPressed")(_G.SanctuaryMaxEntriesInput)
equal(SanctuaryDB.logging.maxEntries, 20000, "and one above the ceiling clamped down")
_G.SanctuaryMaxEntriesInput:SetText("5000")
_G.SanctuaryMaxEntriesInput:GetScript("OnEnterPressed")(_G.SanctuaryMaxEntriesInput)
equal(SanctuaryDB.logging.maxEntries, 5000, "a value in range is taken as typed")

-- ---------------------------------------------------------------------------
-- The minimap button
-- ---------------------------------------------------------------------------

Minimap = { GetCenter = function() return 100, 100 end }
UIParent.GetEffectiveScale = function() return 1 end
GetCursorPosition = function() return 180, 100 end
ns.InitializeUI()
local minimapButton = _G.SanctuaryMinimapButton
check(minimapButton ~= nil, "the minimap button is created at login")
equal(minimapButton:IsShown(), true, "and shown while the setting allows it")

-- The position-to-angle conversion is pure, so it is proved without a mouse.
equal(math.floor(ns.minimapAngleFromPosition(0, 0, 10, 0) + 0.5), 0, "due east is 0 degrees")
equal(math.floor(ns.minimapAngleFromPosition(0, 0, 0, 10) + 0.5), 90, "due north is 90")
equal(math.floor(ns.minimapAngleFromPosition(0, 0, -10, 0) + 0.5), 180, "due west is 180")
minimapButton:GetScript("OnDragStop")(minimapButton)
equal(math.floor(SanctuaryDB.minimap.angle + 0.5), 0, "dragging writes the angle it computes")

local togglesBefore = ns.isEnabled()
minimapButton:GetScript("OnClick")(minimapButton, "RightButton")
equal(ns.isEnabled(), not togglesBefore, "a right click flips the protection")
minimapButton:GetScript("OnClick")(minimapButton, "RightButton")
equal(ns.isEnabled(), togglesBefore, "and flips it back")

SanctuaryDB.minimap.hide = true
_G.SanctuaryMinimapCheck:Click()
equal(SanctuaryDB.minimap.hide, false, "the Advanced box shows the button again")
_G.SanctuaryMinimapCheck:Click()
equal(SanctuaryDB.minimap.hide, true, "and hides it")
equal(minimapButton:IsShown(), false, "the button follows the setting")
_G.SanctuaryMinimapCheck:Click()

-- ---------------------------------------------------------------------------
-- The right-click menu
-- ---------------------------------------------------------------------------

local menuEntries = ns.buildPlayerMenuEntries({ name = "Toto", server = "Ysondre" })
equal(#menuEntries, 2, "a resolved player gets two entries")
check(menuEntries[2].text:find(ns.L["MENU_BLOCK"], 1, true) ~= nil, "one of which blocks")
menuEntries[2].action()
check(SanctuaryDB.blockedNames["toto-ysondre"] ~= nil, "and blocking writes the list")
menuEntries = ns.buildPlayerMenuEntries({ name = "Toto", server = "Ysondre" })
check(menuEntries[2].text:find(ns.L["MENU_UNBLOCK"], 1, true) ~= nil,
    "opened again, the entry offers to stop blocking")
menuEntries[2].action()
equal(SanctuaryDB.blockedNames["toto-ysondre"], nil, "and does")

-- A bare name blocks every realm. The menu searched for the full key alone, so
-- on a character of an already-blocked bare name it offered to block again, and
-- the click wrote a second key: from then on "stop blocking" removed one of the
-- two and left the other blocking.
ns.addBlocked("Bareprobe")
menuEntries = ns.buildPlayerMenuEntries({ name = "Bareprobe", server = "Ysondre" })
check(menuEntries[2].text:find(ns.L["MENU_UNBLOCK"], 1, true) ~= nil,
    "the menu on a character of a bare blocked name offers to stop blocking")
equal(ns.classifyName("Bareprobe-Ysondre").verdict, "always_blocked",
    "which is the truth, since the core already holds him blocked")
menuEntries[2].action()
equal(SanctuaryDB.blockedNames["bareprobe"], nil, "and it removes the key that was found")
equal(SanctuaryDB.blockedNames["bareprobe-ysondre"], nil, "having written no second key")
check(ns.classifyName("Bareprobe-Ysondre").verdict ~= "always_blocked",
    "so one click really does stop blocking him")

equal(#ns.buildPlayerMenuEntries({ name = "Victim" }), 0, "the player themselves gets nothing")
equal(#ns.buildPlayerMenuEntries({}), 0, "an unresolved identity gets nothing")
equal(#ns.buildPlayerMenuEntries({ name = makeSecretValue("secret") }), 0,
    "and a secret name gets nothing")
local savedCombat = InCombatLockdown
InCombatLockdown = function() return true end
equal(#ns.buildPlayerMenuEntries({ name = "Toto", server = "Ysondre" }), 0, "nothing is added in combat")
InCombatLockdown = savedCombat
local savedLockdown = C_ChatInfo.InChatMessagingLockdown
C_ChatInfo.InChatMessagingLockdown = function() return true end
equal(#ns.buildPlayerMenuEntries({ name = "Toto", server = "Ysondre" }), 0,
    "nor during a chat lockdown")
C_ChatInfo.InChatMessagingLockdown = savedLockdown

-- ---------------------------------------------------------------------------
-- The diagnostics panel
-- ---------------------------------------------------------------------------

SanctuaryDB.debugEnabled = true
mainFrame:Hide()
mainFrame:Show()
_G["SanctuaryTab_diagnostics"]:Click()

local listScroll = _G.SanctuaryDiagListScroll
check(listScroll ~= nil, "the diagnostics panel builds its button list")
local listChild = listScroll and listScroll:GetScrollChild()
local rowCount = 0
if listChild then
    for _, childWidget in ipairs(listChild.__children or {}) do
        if childWidget.__kind == "Frame" then rowCount = rowCount + 1 end
    end
end
equal(rowCount, #ns.DIAGNOSTIC_CATALOG,
    "the panel renders exactly one row per catalogued diagnostic")

local function findButtonByLabel(root, wanted)
    for _, childWidget in ipairs(root.__children or {}) do
        if childWidget.label and childWidget.label.__text == wanted then
            return childWidget
        end
        local found = findButtonByLabel(childWidget, wanted)
        if found then return found end
    end
    return nil
end

local resultChild = _G.SanctuaryDiagResultScroll and _G.SanctuaryDiagResultScroll:GetScrollChild()
local resultText = resultChild and resultChild.__children and resultChild.__children[1]
check(resultText ~= nil, "the panel has somewhere to show a result")
equal(resultText and resultText:GetText(), ns.L["DIAG_RESULT_EMPTY"],
    "an untouched panel says so instead of showing a blank box")

-- Anchored on fixed values, never on the catalogue's own flags: a test that
-- branches on the data it is testing cannot notice that data disappearing.
local SENSITIVE_DIAGNOSTIC_ID = "sim_bnetfriend"
local MANUAL_DIAGNOSTIC_IDS = { "diag_sound_open", "diag_sound_invite" }
local BULK_DIAGNOSTIC_IDS = { "sim_invite", "sim_bnet", "diag_chat", "diag_chat_lockdown",
    "diag_popup_invite", "diag_popup_duel", "diag_popup_guild", "diag_popup_list" }

local sensitiveCount, manualCount = 0, 0
for _, entry in ipairs(ns.DIAGNOSTIC_CATALOG) do
    if entry.sensitive then sensitiveCount = sensitiveCount + 1 end
    if entry.manual then manualCount = manualCount + 1 end
end
equal(sensitiveCount, 1, "exactly one diagnostic is marked as naming a real contact")
equal(ns.getDiagnosticEntry(SENSITIVE_DIAGNOSTIC_ID).sensitive, true,
    "and it is " .. SENSITIVE_DIAGNOSTIC_ID)
equal(manualCount, #MANUAL_DIAGNOSTIC_IDS, "exactly two are marked as run-them-by-hand")
for _, id in ipairs(MANUAL_DIAGNOSTIC_IDS) do
    equal(ns.getDiagnosticEntry(id).manual, true, id .. " is one of them")
end
equal(#ns.DIAGNOSTIC_CATALOG, #BULK_DIAGNOSTIC_IDS + #MANUAL_DIAGNOSTIC_IDS + 1,
    "the catalogue is the bulk set plus those three")

local runAllBtn = findButtonByLabel(diagContent, ns.L["DIAG_RUN_ALL"])
check(runAllBtn ~= nil, "the panel offers a single button that runs them all")
runAllBtn:Click()
local shown = resultText:GetText()
local blockCount = select(2, shown:gsub("|cFF88CCFF", ""))
equal(blockCount, #BULK_DIAGNOSTIC_IDS,
    "running them all produces one block per bulk diagnostic")
for _, id in ipairs(BULK_DIAGNOSTIC_IDS) do
    local entry = ns.getDiagnosticEntry(id)
    check(entry ~= nil and shown:find(ns.L[entry.labelKey], 1, true) ~= nil,
        "running them all covers " .. id)
end
equal(shown:find(ns.L[ns.getDiagnosticEntry(SENSITIVE_DIAGNOSTIC_ID).labelKey], 1, true), nil,
    "and never " .. SENSITIVE_DIAGNOSTIC_ID .. ", which names a real contact")
for _, id in ipairs(MANUAL_DIAGNOSTIC_IDS) do
    equal(shown:find(ns.L[ns.getDiagnosticEntry(id).labelKey], 1, true), nil,
        "nor " .. id .. ", which has to be heard on its own")
end

-- Eight blocks stacked into a 300 px column. The child of that scroll used to be
-- sized once, at build time, so RefreshBar measured a range of zero: the wheel
-- scrolled nothing, the bar never appeared, and everything past the first screen
-- was unreachable -- while step C.1 of the session asks the tester to read every
-- block.
local resultScroll = _G.SanctuaryDiagResultScroll
check((resultScroll.child:GetHeight() or 0) > (resultScroll:GetHeight() or 0),
    "after running them all the content is taller than the column")
equal(resultScroll.bar:IsShown(), true, "so the bar is there to say the column scrolls")
findButtonByLabel(diagContent, ns.L["DIAG_CLEAR"]):Click()
check((resultScroll.child:GetHeight() or 0) <= (resultScroll:GetHeight() or 0),
    "and once cleared it does not pretend to scroll")
equal(resultScroll.bar:IsShown(), false, "with no bar left over")
-- Put the panel back the way the rest of this section found it.
runAllBtn:Click()

-- The two sound buttons, one after the other: two distinct sounds.
playedSounds = {}
findButtonByLabel(diagContent, ns.L["DIAG_SOUND_OPEN"]):Click()
equal(#playedSounds, 1, "the window-open button plays one sound")
local firstSound = playedSounds[1]
playedSounds = {}
findButtonByLabel(diagContent, ns.L["DIAG_SOUND_INVITE"]):Click()
equal(#playedSounds, 1, "the invite button plays one sound")
check(playedSounds[1] ~= firstSound, "and it is a different one")

-- A name typed into the Battle.net friend field reaches the same answer as the
-- index does.
local byIndex = ns.runDiagnosticById("sim_bnetfriend", "1").text
local byName = ns.runDiagnosticById("sim_bnetfriend", "RealFriend#1234").text
equal(byName, byIndex, "the friend simulation answers the same for a name and for its index")

local restoreBtn = findButtonByLabel(diagContent, ns.L["DIAG_RESTORE_BTN"])
check(restoreBtn ~= nil, "the way back exists")
equal(restoreBtn:IsShown(), false,
    "and stays hidden while every diagnostic put the screen back")

-- A window left on screen is invisible and clickable. The panel says so and
-- offers the way back, instead of leaving that rule to a note in a checklist.
local panelSavedHide = StaticPopup1.Hide
StaticPopup1.Hide = nil
findButtonByLabel(diagContent, ns.L["DIAG_POPUP_DUEL"]):Click()
StaticPopup1.Hide = panelSavedHide
check(resultText:GetText():find(ns.L["DIAG_LEFT_ON_SCREEN"], 1, true) ~= nil,
    "a stranded popup is reported in the panel")
equal(restoreBtn:IsShown(), true, "and the way back appears")

-- Clearing the results must not clear the screen: the button that is the only
-- way back would disappear while the dialog is still up.
local clearBtn = findButtonByLabel(diagContent, ns.L["DIAG_CLEAR"])
clearBtn:Click()
equal(StaticPopup1:IsShown(), true, "the dialog is still there")
check(resultText:GetText():find(ns.L["DIAG_LEFT_ON_SCREEN"], 1, true) ~= nil,
    "so the warning survives clearing the results")
equal(restoreBtn:IsShown(), true, "and so does the way back")

StaticPopup1:Hide()
runTimers(4)
clearBtn:Click()
equal(resultText:GetText(), ns.L["DIAG_RESULT_EMPTY"], "clearing empties the result box")
equal(restoreBtn:IsShown(), false, "and the way back goes when the dialog does")

-- ---------------------------------------------------------------------------
-- Closing the window drops what was read
-- ---------------------------------------------------------------------------

_G["SanctuaryTab_protection"]:Click()
_G.SanctuaryTestInput:SetText("Halftypedname")
ns.OpenPanel("blocked")
_G.SanctuaryBlockedAddInput:SetText("Someonesname")
mainFrame:Hide()
equal(_G.SanctuaryTestInput:GetText(), "", "closing the window clears the tested name")
equal(_G.SanctuaryTestAnswer:GetText(), "", "and the answer that named them in full")
equal(_G.SanctuaryBlockedAddInput:GetText(), "", "and the half-typed blocked name")
equal(_G.SanctuaryPanelBlocked:IsShown(), false, "and closes the panel that was open")
mainFrame:Show()
_G["SanctuaryTab_diagnostics"]:Click()
findButtonByLabel(diagContent, ns.L["DIAG_SIM_INVITE"]):Click()
check(resultText:GetText():find(ns.L["DIAG_SIM_INVITE"], 1, true) ~= nil,
    "a diagnostic has been run and its result is on screen")
mainFrame:Hide()
mainFrame:Show()
equal(resultText:GetText(), ns.L["DIAG_RESULT_EMPTY"],
    "closing the window clears the diagnostics result box too")

-- ---------------------------------------------------------------------------
-- The window sizes itself to the screen it shows
-- ---------------------------------------------------------------------------

_G["SanctuaryTab_about"]:Click()
local aboutHeight = mainFrame:GetHeight()
_G["SanctuaryTab_protection"]:Click()
local protectionHeight = mainFrame:GetHeight()
check(protectionHeight >= aboutHeight, "the tallest screen is at least as tall as the shortest")
check(protectionHeight <= 700 + 40 + 30, "and the fitted height stays within its bounds")

-- "I choose" unfolded is taller than the fitted bound. The screen must stay
-- reachable: the content area scrolls instead of being cut off.
SanctuaryDB.filters.preset = "custom"
ns.refreshUI()
local chooseScroll = _G.SanctuaryContentScroll
check(chooseScroll ~= nil, "the content area is a scroll")
check((chooseScroll:GetScrollChild():GetHeight() or 0) > (chooseScroll:GetHeight() or 0),
    "and it is taller than the window when the detailed boxes are unfolded")
SanctuaryDB.filters.preset = "all"
ns.refreshUI()
equal(mainFrame:GetWidth(), 780, "the width is fixed")

-- Dragging the grip switches to a remembered size; double-clicking goes back.
SanctuaryDB.uiSize = { 780, 520 }
mainFrame:Hide()
mainFrame:Show()
equal(mainFrame:GetHeight(), 520, "a remembered size is applied on opening")
SanctuaryDB.uiSize = nil
mainFrame:Hide()
mainFrame:Show()

do

-- The grip drives one dimension. The window has no horizontal scrolling at all:
-- the content area and every tab frame are built at 780, so a width remembered
-- from a diagonal drag either truncates the screen or leaves it floating -- and
-- it came back on every refresh and every reopening.
local grip = _G.SanctuaryResizeGrip
check(grip ~= nil, "the resize grip is reachable")
local gripDown = grip:GetScript("OnMouseDown")
local gripUp = grip:GetScript("OnMouseUp")

-- Releasing the grip has to APPLY the size, not just write it down. The content
-- area is anchored on one point with an explicit size and only applyHeight ever
-- resized it, so between the two gestures the session asks for -- "drag the
-- grip, THEN double-click" -- the screen kept its old height: 320 px of content
-- spilling under a shrunken window, over the tab strip, with no bar. This case
-- used to call ns.refreshUI() by hand right after gripUp and hid it.
local viewportOf = function() return _G.SanctuaryContentScroll:GetHeight() end
local expectedViewport = function() return mainFrame:GetHeight() - 40 - 30 end

now = now + 5
gripDown(grip)
mainFrame:SetSize(1240, 560)
gripUp(grip)
equal(SanctuaryDB.uiSize[1], 780, "a diagonal drag records the one width there is")
equal(SanctuaryDB.uiSize[2], 560, "and the height it was actually dragged to")
equal(viewportOf(), expectedViewport(), "and the content area follows on release")
equal(mainFrame:GetWidth(), 780, "releasing puts the window back on that width")
equal(mainFrame:GetHeight(), 560, "while keeping the height that was asked for")

-- Downwards too: shrinking is the direction that spilled content off-screen.
now = now + 5
gripDown(grip)
mainFrame:SetSize(780, 450)
gripUp(grip)
equal(mainFrame:GetHeight(), 450, "a drag downwards is kept")
equal(viewportOf(), expectedViewport(), "and the content area shrinks with it")

-- During the drag, not only on release: the window's own size handler carries
-- the new height to the content area.
mainFrame:SetHeight(600)
mainFrame:GetScript("OnSizeChanged")(mainFrame)
equal(viewportOf(), expectedViewport(), "the content follows while the grip is still down")
now = now + 5
gripDown(grip)
mainFrame:SetSize(780, 560)
gripUp(grip)
mainFrame:Hide()
mainFrame:Show()
equal(mainFrame:GetWidth(), 780, "and reopening does not bring the dragged width back")

-- Double-click: two press/release pairs less than 0.4 s apart. The second
-- OnMouseDown cleared the remembered size -- and the OnMouseUp of that very same
-- click wrote it straight back, so the way back to the fitted mode did not
-- survive the button being released.
now = now + 5
gripDown(grip)
gripUp(grip)
now = now + 0.2
gripDown(grip)
gripUp(grip)
equal(SanctuaryDB.uiSize, nil, "a double-click forgets the remembered size for good")

-- And the fitted mode is really back: the height follows the screen again.
_G["SanctuaryTab_about"]:Click()
equal(mainFrame:GetHeight(), 380 + 40 + 30, "the shortest screen is back to its fitted height")
_G["SanctuaryTab_protection"]:Click()
check(mainFrame:GetHeight() > 380 + 40 + 30, "and a taller screen makes the window taller again")

end


guildMembers = {}
bnetFriends = {}
charFriends = {}
inGuild = false
wipe(SanctuaryDB.manualWhitelist)
wipe(SanctuaryDB.blockedNames)
SanctuaryDB.keywords = {}
ns.invalidateWhitelist()

-- ---------------------------------------------------------------------------
-- The offline check the closing step now delegates to
-- ---------------------------------------------------------------------------

-- The checklist no longer asks anyone to scroll an export looking for five
-- entries: it runs tests/check_qa_run.lua on the settings file. That tool is
-- therefore part of the deliverable, and it is exercised end to end here --
-- including its exit code, which is what makes it usable without reading it.
-- opts.chatFilterApi   value carried by the SNAPSHOT in the log ("" for none)
-- opts.manifestHealth  instrumentation carried by the manifest, or nil
-- opts.scenarios       false to write a log where nothing was played
-- opts.logBuild        build stamped in the SNAPSHOT (defaults to the manifest's)
-- opts.extraBuild      a second build stamped in a second SNAPSHOT
-- opts.neverCleared    true to write a manifest with no debug-log clear date
-- opts.savedAt         when the report was written (defaults to the clear day)
-- opts.deathOnly       true to write a log where the character died and never came back
-- opts.metaBuild       build the client read out of the .toc (defaults to the code build)
local function writeFixture(opts)
    local snapshot = ""
    if opts.chatFilterApi then
        snapshot = ([[
        { ["seq"] = 5, ["cat"] = "SNAPSHOT", ["data"] = { ["chatFilterApiUsed"] = "%s",
            ["build"] = "%s",
            ["chatFramesSeen"] = 10, ["chatFramesWrapped"] = 10, ["systemChatTypeID"] = 90 } },]])
            :format(opts.chatFilterApi, opts.logBuild or "20260820-8")
    end
    if opts.extraBuild then
        snapshot = snapshot .. ([[

        { ["seq"] = 6, ["cat"] = "SNAPSHOT", ["data"] = { ["chatFilterApiUsed"] = "legacy",
            ["build"] = "%s",
            ["chatFramesSeen"] = 10, ["chatFramesWrapped"] = 10, ["systemChatTypeID"] = 90 } },]])
            :format(opts.extraBuild)
    end
    local scenarios = ""
    if opts.deathOnly then
        scenarios = [[
        { ["seq"] = 1, ["cat"] = "CHAT_OUTPUT", ["data"] = { ["action"] = "NO_MATCH" } },
        { ["seq"] = 2, ["cat"] = "POPUP", ["data"] = { ["action"] = "MASK_AWAITING_EVENT", ["affected"] = 1 } },
        { ["seq"] = 3, ["cat"] = "WORLD", ["data"] = { ["inInstance"] = true } },
        { ["seq"] = 4, ["cat"] = "PLAYER_STATE", ["data"] = { ["event"] = "PLAYER_DEAD" } },]]
    elseif opts.scenarios ~= false then
        scenarios = [[
        { ["seq"] = 1, ["cat"] = "CHAT_OUTPUT", ["data"] = { ["action"] = "NO_MATCH" } },
        { ["seq"] = 2, ["cat"] = "POPUP", ["data"] = { ["action"] = "MASK_AWAITING_EVENT", ["affected"] = 1 } },
        { ["seq"] = 3, ["cat"] = "WORLD", ["data"] = { ["inInstance"] = true } },
        { ["seq"] = 4, ["cat"] = "PLAYER_STATE", ["data"] = { ["event"] = "PLAYER_DEAD" } },
        { ["seq"] = 7, ["cat"] = "PLAYER_STATE", ["data"] = { ["event"] = "PLAYER_ALIVE" } },]]
    end
    local health = ""
    if opts.manifestHealth then
        health = ([[ ["chatFilterApiUsed"] = "%s", ["chatFramesSeen"] = 10,
        ["chatFramesWrapped"] = 10, ["systemChatTypeID"] = 90,]]):format(opts.manifestHealth)
    end

    local fixturePath = os.tmpname()
    local handle = assert(io.open(fixturePath, "w"))
    handle:write(([[
SanctuaryDB = {
    ["debugLogStats"] = { ["produced"] = 6, ["dropped"] = 0 },
    ["log"] = {},
    ["reportManifest"] = { ["trigger"] = "logout", ["savedAt"] = "%s",
        ["version"] = "0.3.2", ["addonMetaVersion"] = "0.3.2",
        ["build"] = "20260820-8", ["addonMetaBuild"] = "20260820-8",
        ["addonMetaInterface"] = "120100", ["addonInterface"] = %s,
        ["clientVersion"] = "12.1.0",%s
        ["clientBuild"] = "61234", ["clientInterface"] = 120100,%s%s ["verdict"] = "ok" },
    ["debugLog"] = {
%s
%s
    },
}
]]):format(opts.savedAt or "2026-08-20 18:12:00",
        tostring(opts.addonInterface or 120100),
        opts.metaBuild and (' ["addonMetaBuild"] = "' .. opts.metaBuild .. '",') or "",
        health, opts.neverCleared and "" or ' ["debugLogClearedAt"] = "2026-08-20 17:50:00",',
        scenarios, snapshot))
    handle:close()
    return fixturePath
end

local function runChecker(fixturePath, since)
    local interpreter = (arg and arg[-1]) or "lua"
    local command
    if since then
        command = string.format('%q %q --since %q %q 2>&1', interpreter,
            repoRoot .. "/tests/check_qa_run.lua", since, fixturePath)
    else
        command = string.format('%q %q %q 2>&1', interpreter,
            repoRoot .. "/tests/check_qa_run.lua", fixturePath)
    end
    local pipe = io.popen(command)
    local output = pipe:read("a")
    local _, _, code = pipe:close()
    return output or "", code
end

local function checkFixture(opts)
    local fixturePath = writeFixture(opts)
    local output, code = runChecker(fixturePath, opts.since)
    os.remove(fixturePath)
    return output, code
end

local goodOutput, goodCode = checkFixture({ chatFilterApi = "legacy" })
equal(goodCode, 0, "the checker accepts a complete recording")
check(goodOutput:find("RELEVE COMPLET", 1, true) ~= nil,
    "the checker says so in one line")
check(goodOutput:find("20260820-8", 1, true) ~= nil,
    "the checker reads the build out of the file, so nobody transcribes it")
-- Numbered as the checklist numbers them: C.1 is the panel, F.1 to F.3 are the
-- scenarios. A report blaming "F3" used to send the reader to the wrong step.
for _, marker in ipairs({ "C%.1", "F%.1", "F%.2", "F%.3" }) do
    check(goodOutput:find("%[  ok  %] " .. marker) ~= nil,
        "the checker reports marker " .. marker:gsub("%%", ""))
end

local badOutput, badCode = checkFixture({ chatFilterApi = "unregistered" })
equal(badCode, 1, "the checker fails a recording that filtered nothing")
check(badOutput:find("ECHEC BLOQUANT", 1, true) ~= nil,
    "and says why in terms the checklist can quote")

-- A recording where nothing was played must not exit 0: any caller testing $?
-- would read "conforme" on a session where phase F was skipped entirely.
local emptyOutput, emptyCode = checkFixture({ chatFilterApi = "legacy", scenarios = false })
equal(emptyCode, 3, "a recording with no scenario played exits on its own code")
check(emptyOutput:find("EXPLOITABLE AVEC RESERVES", 1, true) ~= nil,
    "and is named as reserves, not as a complete recording")
check(emptyOutput:find("RELEVE COMPLET", 1, true) == nil,
    "and never as complete")

-- The log rotates; the manifest does not. A recording whose log outlived its
-- last snapshot is still gradeable, and used to be declared unexploitable.
local rotatedOutput, rotatedCode = checkFixture({ manifestHealth = "legacy" })
check(rotatedOutput:find("instrumentation lue dans le manifeste", 1, true) ~= nil,
    "a log that rotated past its last snapshot is graded on the manifest")
check(rotatedOutput:find("%[  ok  %] API de filtrage chat +legacy") ~= nil,
    "reading the instrumentation the manifest actually carries")
check(rotatedOutput:find("%[  ok  %] Frames de chat observees +10 / 10") ~= nil,
    "including the counts the log no longer holds")
check(rotatedOutput:find("ECHEC BLOQUANT", 1, true) == nil,
    "so a usable recording is no longer declared unexploitable")
-- It is still a reserve, and only that: the log did lose entries.
equal(rotatedCode, 3, "a rotated log is a reserve, not a clean recording")
check(rotatedOutput:find("%[ warn %] Snapshots dans le journal") ~= nil,
    "and the missing snapshot is what is flagged")

-- The persistent log survives reloads, relogs and sessions. A complete
-- recording made under an earlier build must never read as a complete recording
-- of this one: that is how a step skipped today gets credited by a passage from
-- last week.
local staleOutput, staleCode = checkFixture({ chatFilterApi = "legacy", logBuild = "20260820-4" })
equal(staleCode, 1, "a log written by another build is refused")
check(staleOutput:find("20260820-4 != 20260820-8", 1, true) ~= nil,
    "and the report names both builds rather than just failing")

local mixedOutput, mixedCode = checkFixture({ chatFilterApi = "legacy", extraBuild = "20260820-4" })
equal(mixedCode, 1, "a log holding two builds is refused")
check(mixedOutput:find("journal melange", 1, true) ~= nil,
    "and says that it is mixed")

-- A log that was never cleared may still hold an earlier passage. That does not
-- void it, but it has to be visible rather than silently credited.
local uncleanedOutput, uncleanedCode = checkFixture({ chatFilterApi = "legacy", neverCleared = true })
equal(uncleanedCode, 3, "a log that was never cleared is a reserve")
check(uncleanedOutput:find("%[ warn %] Journal vide le +jamais") ~= nil,
    "and the report says so on its own line")

-- "Never cleared" was only half the case, and the smaller half. The nominal one
-- is a log cleared during an EARLIER passage: same build, second session, and
-- the build does not change between the maintainer's pass and the tester's. The
-- markers then come from the previous day and credit steps nobody played.
local staleClearOutput, staleClearCode = checkFixture({ chatFilterApi = "legacy",
    savedAt = "2026-08-21 19:04:00" })
equal(staleClearCode, 3, "a log cleared during an earlier passage is a reserve")
check(staleClearOutput:find("releve ecrit le 2026%-08%-21") ~= nil,
    "and the report puts both dates on the line so the gap is one glance")
check(staleClearOutput:find("RELEVE COMPLET", 1, true) == nil,
    "such a recording is never reported as complete")

-- This folder is deployed by hand. A copy where the .lua files were replaced
-- but not the .toc -- or the other way round -- makes the code's own build
-- constant and the build the client reads out of the .toc disagree. The report
-- used to print one and check the other, and certify.
local mixedDeployOutput, mixedDeployCode = checkFixture({ chatFilterApi = "legacy",
    metaBuild = "20260820-4" })
equal(mixedDeployCode, 1, "a partially deployed copy is refused")
check(mixedDeployOutput:find("deploiement partiel", 1, true) ~= nil,
    "and is named for what it is")
check(mixedDeployOutput:find("build code=20260820-8 .toc=20260820-4", 1, true) ~= nil,
    "with both identities on the line")
check(mixedDeployOutput:find("RELEVE COMPLET", 1, true) == nil,
    "such a copy is never reported as complete")
-- The header names the identity of the code that actually ran, so it cannot
-- print one identity while the line below checks the other.
check(mixedDeployOutput:find("Build     : 20260820-8", 1, true) ~= nil,
    "and the header names the build the code itself carries")

-- The twin surface: the in-game summary has the same two identities and used to
-- say nothing about them. It grades through the same rule, so the screen the
-- maintainer reads and the offline check cannot disagree.
equal(select(1, ns.getDeploymentVerdict({ build = "a", addonMetaBuild = "a",
    version = "v", addonMetaVersion = "v" })), "ok", "matching identities pass")
equal(select(1, ns.getDeploymentVerdict({ build = "a", addonMetaBuild = "b",
    version = "v", addonMetaVersion = "v" })), "partial", "a stale .toc build is partial")
-- The version is the twin of the build in the same .toc, and desyncs on its own.
equal(select(1, ns.getDeploymentVerdict({ build = "a", addonMetaBuild = "a",
    version = "v", addonMetaVersion = "w" })), "partial", "so is a stale .toc version")
equal(select(1, ns.getDeploymentVerdict({ build = "a", addonMetaBuild = "unavailable",
    version = "v", addonMetaVersion = "v" })), "unknown", "an unreadable .toc is not a verdict")
SanctuaryDB.debugEnabled = true
ns.resetDebugLog()
local deploySummary = ns.buildDebugSummaryText()
check(deploySummary:find("Deploiement: OK", 1, true) ~= nil,
    "the in-game summary states the deployment, not only the offline check")

-- The third branch of the same check, and the only correctile of the previous
-- round whose mutation did not bite. It is reachable for real:
-- C_AddOns.GetAddOnMetadata unavailable makes the client report the .toc build
-- as "unavailable", which is not a mismatch -- it is a read failure, and a read
-- failure must not pass for agreement.
local unreadableTocOutput, unreadableTocCode = checkFixture({ chatFilterApi = "legacy",
    metaBuild = "unavailable" })
equal(unreadableTocCode, 3, "an unreadable .toc is a reserve, not a pass")
check(unreadableTocOutput:find("%[ warn %] Build du code et du %.toc") ~= nil,
    "and is flagged on its own line")
check(unreadableTocOutput:find("build_meta_unreadable", 1, true) ~= nil,
    "naming which identity could not be read")
check(unreadableTocOutput:find("RELEVE COMPLET", 1, true) == nil,
    "such a recording is never reported as complete")

-- The same absence on the other side. An identity missing from the code used to
-- skip the comparison and fall through to `ok` -- an unknown turning green on
-- the side nobody was watching.
equal(select(1, ns.getDeploymentVerdict({ addonMetaBuild = "a",
    version = "v", addonMetaVersion = "v" })), "unknown",
    "a manifest with no code build is unknown, not ok")
equal(select(1, ns.getDeploymentVerdict({ build = "a", addonMetaBuild = "a",
    addonMetaVersion = "v" })), "unknown",
    "and one with no code version too")

-- "Died and never came back" is a session that ended on a corpse, not the
-- scenario the step asks for.
local deathOnlyOutput, deathOnlyCode = checkFixture({ chatFilterApi = "legacy", deathOnly = true })
equal(deathOnlyCode, 3, "a death with no return stays in reserves")
check(deathOnlyOutput:find("mort sans retour a la vie", 1, true) ~= nil,
    "and the report names the half that is missing")
check(deathOnlyOutput:find("RELEVE COMPLET", 1, true) == nil,
    "it is never reported as complete")

-- Without a manifest AND without a snapshot there is nothing left to grade, and
-- no value may be printed as `ok`.
local blindOutput, blindCode = checkFixture({ scenarios = false })
equal(blindCode, 1, "a recording with neither manifest health nor snapshot is blocking")
check(blindOutput:find("[ warn ] Frames de chat observees", 1, true) ~= nil,
    "and an unknown value is never presented as conforming")

-- ---------------------------------------------------------------------------
-- The freshness rule, the interface comparison and the settings block
-- ---------------------------------------------------------------------------

-- "Cleared today" passed a log cleared at 08:00 for a session played at 18:00,
-- and the markers then come from the morning. With --since the whole timestamp
-- is compared against the moment the session actually started.
local freshOutput, freshCode = checkFixture({ chatFilterApi = "legacy",
    since = "2026-08-20 17:00:00" })
equal(freshCode, 0, "a log cleared after the session started is accepted")
check(freshOutput:find("%[  ok  %] Journal vide le") ~= nil,
    "and the line says so")

local staleSinceOutput, staleSinceCode = checkFixture({ chatFilterApi = "legacy",
    since = "2026-08-20 18:00:00" })
equal(staleSinceCode, 3, "a log cleared before the session started is a reserve")
check(staleSinceOutput:find("session ouverte le 2026%-08%-20 18:00:00") ~= nil,
    "and the report puts both moments on the line")

-- The AddOns manager grades "Out of date" on this comparison; the check does it
-- so the person does not have to know the numbers.
local staleInterfaceOutput, staleInterfaceCode = checkFixture({
    chatFilterApi = "legacy", addonInterface = 110000 })
equal(staleInterfaceCode, 3, "an addon interface below the client's is a reserve")
check(staleInterfaceOutput:find("obsolete", 1, true) ~= nil,
    "and is named for what the game calls it")

-- The settings the session ran under, resolved by the addon's own rule.
check(goodOutput:find("question 1 = strangers", 1, true) ~= nil,
    "the check reports which mode the session ran in")
check(goodOutput:find("question 2 = all", 1, true) ~= nil, "and which preset")
check(goodOutput:find("invitations=true", 1, true) ~= nil,
    "and the resolved filters, not the stored checkboxes")

-- ---------------------------------------------------------------------------
-- The session protocol and the check agree on the markers
-- ---------------------------------------------------------------------------

-- A session that measures something other than what it claims to is worse than
-- no session at all: a disagreement here stops the harness rather than costing
-- Vincent forty-five minutes of the wrong test.
local function readLines(command)
    local pipe = io.popen(command)
    if not pipe then return nil end
    local output = pipe:read("a")
    pipe:close()
    local lines = {}
    for line in tostring(output or ""):gmatch("[^\n]+") do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed ~= "" then lines[#lines + 1] = trimmed end
    end
    return lines
end

local interpreter = (arg and arg[-1]) or "lua"
local checkerMarkers = readLines(string.format('%q %q --markers 2>&1', interpreter,
    repoRoot .. "/tests/check_qa_run.lua"))
check(checkerMarkers ~= nil and #checkerMarkers > 0,
    "the offline check lists the markers it reads")

local protocolMarkers = readLines(string.format('python3 %q --markers 2>&1',
    repoRoot .. "/tests/qa_protocol.py"))
check(protocolMarkers ~= nil and #protocolMarkers > 0,
    "the session protocol lists the markers its steps claim")

if checkerMarkers and protocolMarkers then
    local known = ns.getReportMarkers({})
    local claimed, displayed = {}, {}
    for _, name in ipairs(protocolMarkers) do claimed[name] = true end
    for _, name in ipairs(checkerMarkers) do displayed[name] = true end

    local missingFromCore, missingFromCheck = {}, {}
    for _, name in ipairs(protocolMarkers) do
        if known[name] == nil then missingFromCore[#missingFromCore + 1] = name end
        if not displayed[name] then missingFromCheck[#missingFromCheck + 1] = name end
    end
    equal(#missingFromCore, 0,
        "every marker a step names exists in the addon (" ..
        table.concat(missingFromCore, ", ") .. ")")
    equal(#missingFromCheck, 0,
        "every marker a step names is displayed by the check (" ..
        table.concat(missingFromCheck, ", ") .. ")")

    local unclaimed = {}
    for _, name in ipairs(checkerMarkers) do
        if not claimed[name] then unclaimed[#unclaimed + 1] = name end
    end
    equal(#unclaimed, 0,
        "every marker the check displays is claimed by a step (" ..
        table.concat(unclaimed, ", ") .. ")")
end

check(os.execute(string.format('python3 %q --check >/dev/null 2>&1',
    repoRoot .. "/tests/qa_protocol.py")) == true
    or os.execute(string.format('python3 %q --check >/dev/null 2>&1',
    repoRoot .. "/tests/qa_protocol.py")) == 0,
    "the session protocol passes its own structural check")

-- ---------------------------------------------------------------------------
-- Two more checklist steps the machine can make
-- ---------------------------------------------------------------------------

-- Neither log can be wiped without a confirmation. The step used to be "click
-- the button, then click Cancel" -- which only proves the dialog appeared for
-- the person who clicked.
for _, which in ipairs({ "SANCTUARY_CLEAR_LOG", "SANCTUARY_CLEAR_DEBUG_LOG" }) do
    local dialog = StaticPopupDialogs[which]
    check(type(dialog) == "table", which .. " asks before erasing")
    check(type(dialog.text) == "string" and dialog.text ~= "", which .. " says what is at stake")
    check(type(dialog.button1) == "string" and type(dialog.button2) == "string",
        which .. " offers a way out")
    check(type(dialog.OnAccept) == "function", which .. " only erases on accept")
end

SanctuaryDB.log = { { ts = 1, type = "groupInvite", source = "Someone" } }
ns.resetDebugLog()
ns.debugLog("KEEPME", {})
equal(#SanctuaryDB.log, 1, "showing the clear dialog erases nothing on its own")
equal(#SanctuaryDB.debugLog, 1, "showing the debug clear dialog erases nothing on its own")
StaticPopupDialogs.SANCTUARY_CLEAR_DEBUG_LOG.OnAccept()
-- Read as "the entry that was there is gone", not as "the log is empty": the
-- refresh that follows the clear can itself record a cache rebuild, which is a
-- new entry, not a survivor.
equal(lastDebug("KEEPME"), nil, "accepting is what erases the debug log")
equal(#SanctuaryDB.log, 1, "and it leaves the block log alone")
StaticPopupDialogs.SANCTUARY_CLEAR_LOG.OnAccept()
equal(#SanctuaryDB.log, 0, "accepting is what erases the block log")

-- The master switch: at OFF the verdict on the name is still computed, but
-- nothing is applied. That whole line used to be compared by eye.
--
-- An earlier section clears ERR_INVITED_TO_GROUP_SS to exercise the escaping of
-- a nil global, and a later one reloads the addon -- which rebuilt the invite
-- patterns without it. Put the global back and rebuild, or the simulated
-- message falls back to the unaccented literal and matches no pattern.
ERR_INVITED_TO_GROUP_SS = "[%s] vous a invit\195\169 \195\160 rejoindre un groupe."
fire("ADDON_LOADED", "Sanctuary")
SanctuaryCharDB.overrides.enabled = false
-- Flipping the switch in game also refreshes the sound guard; the simulation
-- reports the guard's actual state, not what the setting implies.
ns.refreshInviteSoundMuteState()
local offLine = ns.formatSimulationResult(ns.simulateInvite("SanctuaryTest"))
check(offLine:find("popup=pass", 1, true) ~= nil, "at OFF no popup is masked")
check(offLine:find("chat=visible", 1, true) ~= nil, "at OFF no chat line is suppressed")
check(offLine:find("would-decline=no", 1, true) ~= nil, "at OFF nothing is declined")
check(offLine:find("sound-guard=no", 1, true) ~= nil, "at OFF no sound is guarded")
SanctuaryCharDB.overrides.enabled = nil
ns.refreshInviteSoundMuteState()
local onLine = ns.formatSimulationResult(ns.simulateInvite("SanctuaryTest"))
check(onLine:find("popup=mask", 1, true) ~= nil, "back at ON the popup is masked again")
check(onLine:find("chat=blocked", 1, true) ~= nil, "back at ON the chat line is suppressed again")
check(onLine:find("sound-guard=yes", 1, true) ~= nil, "back at ON the sound guard is back")
ns.resetDebugLog()

-- Both slash names, and every "unknown argument" path. Four more steps that
-- were four more things to type.
equal(SLASH_SANCTUARY1, "/sanctuary", "the long command name is registered")
equal(SLASH_SANCTUARY2, "/sanc", "the short command name is registered")
check(type(SlashCmdList["SANCTUARY"]) == "function", "both names reach the same handler")

local unknownChat = ns.formatChatDiagnosticResult(ns.runChatDiagnostic("blabla"))
check(unknownChat:find("ERROR (unknown_chat_diagnostic)", 1, true) ~= nil,
    "an unknown chat diagnostic says so rather than running something else")
local unknownPopup = ns.formatPopupDiagnosticResult(ns.runPopupDiagnostic("blabla"))
check(unknownPopup:find("ERROR (unknown_popup_diagnostic)", 1, true) ~= nil,
    "an unknown popup diagnostic says so")
-- An unknown sound kind falls back to the invite sound rather than inventing
-- one: the two kinds are the only two that exist, and a diagnostic that stays
-- silent would be read as a defect in the addon.
local unknownSound = ns.formatSoundDiagnosticResult(ns.runSoundDiagnostic("blabla"))
check(unknownSound:find("Diagnostic sound invite", 1, true) ~= nil,
    "an unknown sound kind answers with the invite sound rather than nothing")
chatMessages = {}
SlashCmdList["SANCTUARY"]("blabla")
equal(#chatMessages, 0, "an unknown command prints nothing and just opens the window")
ns.resetDebugLog()


end)()

if failures > 0 then
    io.stderr:write(string.format("%d/%d assertions failed\n", failures, assertions))
    os.exit(1)
end

print(string.format("OK: %d assertions", assertions))
