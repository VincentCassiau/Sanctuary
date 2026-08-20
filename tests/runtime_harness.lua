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
    ["X-Sanctuary-Build"] = "20260820-3",
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
equal(SanctuaryDB.debugLog[1].data.build, "20260820-3", "debug snapshot reports the diagnostic build id")
equal(SanctuaryDB.debugLog[1].data.clientVersion, "12.0.7", "debug snapshot reports the client version")
equal(SanctuaryDB.debugLog[1].data.clientBuild, "62119", "debug snapshot reports the client build")
equal(SanctuaryDB.debugLog[1].data.clientInterface, 120007, "debug snapshot reports the client interface number")
equal(SanctuaryDB.debugLog[1].data.addonMetaVersion, "0.3.2", "debug snapshot reports the loaded addon version metadata")
equal(SanctuaryDB.debugLog[1].data.addonMetaBuild, "20260820-3", "debug snapshot reports the loaded addon build metadata")
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

-- Five-person group inside a dungeon: the field-reported scenario.
inGroup = true
inRaid = false
inInstance = true
currentInstanceType = "party"
groupMembers = { "Harasser-TestRealm", "A-TestRealm", "B-TestRealm", "C-TestRealm" }
equal(GetNumGroupMembers(), 5, "five-person group modelled")
SanctuaryDB.filters.strictGroupInviteSystemMessages = true
expectRegistrySkipsSecret("strict mode in a five-person dungeon group")
expectSecretOutputReachesFrame("strict mode in a five-person dungeon group", ChatTypeInfo.SYSTEM.id)
SanctuaryDB.filters.strictGroupInviteSystemMessages = false
expectRegistrySkipsSecret("relaxed mode in a five-person dungeon group")
expectSecretOutputReachesFrame("relaxed mode in a five-person dungeon group", ChatTypeInfo.SYSTEM.id)

-- Raid context, both strict states.
inRaid = true
currentInstanceType = "raid"
SanctuaryDB.filters.strictGroupInviteSystemMessages = true
expectRegistrySkipsSecret("strict mode in raid")
expectSecretOutputReachesFrame("strict mode in raid", ChatTypeInfo.SYSTEM.id)
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
SanctuaryDB.debugLog = {}
SlashCmdList["SANCTUARY"]("diag chat invite")
check(#chatMessages == beforeSlashMessages + 1, "slash chat diagnostic prints one diagnostic line")
check(chatMessages[#chatMessages]:find("Diagnostic chat invite", 1, true) ~= nil, "slash chat diagnostic output label")
local chatOutputLog = lastDebug("CHAT_OUTPUT")
check(chatOutputLog ~= nil, "slash chat diagnostic triggers chat output guard")
equal(chatOutputLog.data.action, "SUPPRESS_BLOCKED_INVITE", "slash chat diagnostic suppresses direct invite output")
local chatTestLog = lastDebug("CHAT_TEST")
check(chatTestLog ~= nil, "slash chat diagnostic logs result")
equal(chatTestLog.data.output, "guarded", "slash chat diagnostic reports guarded output")
check(chatTestLog.data.observed, "slash chat diagnostic reports observed guard")

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
    check(type(entry.command) == "string" and entry.command:find("/sanc", 1, true) == 1,
        "catalogue entry " .. tostring(entry.id) .. " names the command it replaces")
    check(type(entry.run) == "function",
        "catalogue entry " .. tostring(entry.id) .. " is runnable")
end

-- Every command of the old checklist has a button, and the group invitation
-- window -- which had no command at all and was reached through a raw /run --
-- now has one too.
for _, id in ipairs({ "sim_invite", "sim_bnet", "sim_bnetfriend", "diag_chat",
    "diag_sound", "diag_popup_invite", "diag_popup_duel", "diag_popup_guild",
    "diag_popup_list" }) do
    check(ns.getDiagnosticEntry(id) ~= nil, "catalogue covers " .. id)
end

local unknown = ns.runDiagnosticById("no_such_diagnostic")
check(unknown.failed == true, "an unknown diagnostic id reports a failure")
check(unknown.text ~= "" and unknown.text:find("no_such_diagnostic", 1, true) ~= nil,
    "an unknown diagnostic names what was asked for")

-- A diagnostic that throws must still produce a line in the panel: swallowing
-- it into the error handler is how a checklist step silently passes.
local brokenEntry = { id = "broken", labelKey = "DIAG_SIM_INVITE",
    command = "/sanc broken", run = function() error("boom") end }
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

-- "Does this person get through?" -- the same decision, not a second one.
local verdict = ns.describeAccessDecision("Officer-TestRealm")
equal(verdict.blocked, false, "a guild member gets through")
equal(verdict.source, "guild", "and the tab can say why")
verdict = ns.describeAccessDecision("TypedName")
equal(verdict.source, "manual", "a name typed in by hand is labelled as such")
verdict = ns.describeAccessDecision("Buddy")
equal(verdict.source, "friend", "a friend is labelled as a friend")
verdict = ns.describeAccessDecision("Nobody")
equal(verdict.blocked, true, "a stranger is filtered")
equal(verdict.reason, "not_whitelisted", "and the reason is the decision's own")
verdict = ns.describeAccessDecision("Spammerguy")
equal(verdict.blocked, true, "a suspect pattern still overrides every trust source")
equal(verdict.reason, "keyword", "a pattern match is reported as such")
equal(verdict.keyword, "spammer", "the matching pattern is named")
equal(ns.describeAccessDecision("").valid, false, "an empty field asks nothing")
equal(ns.describeAccessDecision("|cFFFFFFFF|r").valid, false, "a name made of formatting is refused")

-- A Battle.net friend whose current character is unknown is filtered on
-- character name and allowed on Battle.net whispers. Reporting only the first
-- half would read as a bug.
verdict = ns.describeAccessDecision("Friend07#1007")
equal(verdict.blocked, true, "a Battle.net tag is not a character name")
equal(verdict.bnetSource, "bnet", "but the account match is reported alongside")

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
equal(manifest.build, "20260820-3", "the manifest carries the build id")
equal(manifest.version, ns.VERSION, "the manifest carries the addon version")
check(manifest.savedAt ~= nil and manifest.savedAt ~= "", "the manifest is dated")
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
check(summary:find("20260820-3", 1, true) ~= nil, "the summary names the build")
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
    OFF = true, ON = true, SETTINGS_TITLE = true, SUSPECTS_COUNT = true,
}
local unexpected = {}
for _, key in ipairs(untranslated) do
    if not KNOWN_IDENTICAL[key] then unexpected[#unexpected + 1] = key end
end
equal(#unexpected, 0,
    "every used key is translated in frFR (" .. table.concat(unexpected, ", ") .. ")")

-- ---------------------------------------------------------------------------
-- The five tabs open, and the sixth only in debug mode
-- ---------------------------------------------------------------------------

SanctuaryDB.debugEnabled = false
ns.ToggleUI()
local mainFrame = _G.SanctuaryMainFrame
check(mainFrame ~= nil, "the main window is built")
check(mainFrame:IsShown(), "the main window opens on the first toggle")

equal(_G.SanctuaryStatusBar ~= nil, true, "the status bar is built")
local statusText = _G.SanctuaryStatusBar and _G.SanctuaryStatusBar.text
    and _G.SanctuaryStatusBar.text:GetText() or ""
check(statusText:find("/" .. tostring(SanctuaryDB.logging.maxEntries), 1, true) ~= nil,
    "the status bar reports the retention limit in force")

for _, key in ipairs({ "filters", "keywords", "whitelist", "logs", "about" }) do
    local tab = _G["SanctuaryTab_" .. key]
    check(tab ~= nil and tab:IsShown(), "the " .. key .. " tab is offered")
    tab:Click()
    local content = _G["SanctuaryTabContent_" .. key]
    check(content ~= nil and content:IsShown(), "the " .. key .. " tab opens its content")
end

-- The debug panel is not a user surface: with debug mode off its button is not
-- even laid out, and clicking a stale reference to it does nothing. Two locks,
-- because one of them is the answer to "no diagnostic fired by accident".
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

-- And it goes away again with the checkbox, without leaving its panel on screen.
SanctuaryDB.debugEnabled = false
mainFrame:Hide()
mainFrame:Show()
equal(diagTab:IsShown(), false, "unticking debug mode hides the diagnostics tab again")
equal(diagContent:IsShown(), false, "unticking debug mode closes the panel it was showing")
equal(_G["SanctuaryTabContent_filters"]:IsShown(), true,
    "closing the debug panel falls back to a tab that still exists")
SanctuaryDB.debugEnabled = true
mainFrame:Hide()
mainFrame:Show()

-- ---------------------------------------------------------------------------
-- One button per catalogued diagnostic
-- ---------------------------------------------------------------------------

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

-- ---------------------------------------------------------------------------
-- The panel, driven by its own buttons
-- ---------------------------------------------------------------------------

-- This is the step the whole lot exists for: one click instead of twelve
-- commands typed by hand. Clicking it here is what proves the wiring between
-- the catalogue and the buttons, which is the only part the catalogue tests
-- above cannot reach.
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

local runAllBtn = findButtonByLabel(diagContent, ns.L["DIAG_RUN_ALL"])
check(runAllBtn ~= nil, "the panel offers a single button that runs them all")
runAllBtn:Click()
local shown = resultText:GetText()
for _, entry in ipairs(ns.DIAGNOSTIC_CATALOG) do
    if entry.sensitive then
        equal(shown:find(ns.L[entry.labelKey], 1, true), nil,
            "running them all skips " .. entry.id .. ", which names a real contact")
    else
        check(shown:find(ns.L[entry.labelKey], 1, true) ~= nil,
            "running them all covers " .. entry.id)
    end
end

local restoreBtn = findButtonByLabel(diagContent, ns.L["DIAG_RESTORE_BTN"])
check(restoreBtn ~= nil, "the way back exists")
equal(restoreBtn:IsShown(), false,
    "and stays hidden while every diagnostic put the screen back")

-- A popup left on screen is invisible and clickable. The panel says so and
-- offers the way back, instead of leaving that rule to a note in a checklist.
local panelSavedHide = StaticPopup1.Hide
StaticPopup1.Hide = nil
findButtonByLabel(diagContent, ns.L["DIAG_POPUP_DUEL"]):Click()
StaticPopup1.Hide = panelSavedHide
check(resultText:GetText():find(ns.L["DIAG_LEFT_ON_SCREEN"], 1, true) ~= nil,
    "a stranded popup is reported in the panel")
equal(restoreBtn:IsShown(), true, "and the way back appears")
StaticPopup1:Hide()

local clearBtn = findButtonByLabel(diagContent, ns.L["DIAG_CLEAR"])
clearBtn:Click()
equal(resultText:GetText(), ns.L["DIAG_RESULT_EMPTY"], "clearing empties the result box")
equal(restoreBtn:IsShown(), false, "and takes the way back with it")

-- ---------------------------------------------------------------------------
-- The Whitelist tab, driven by its own fields
-- ---------------------------------------------------------------------------

-- The maintainer's own report: this tab was empty while two people were getting
-- through the filter. What follows is that it no longer can be.
guildMembers = { "Guildmate-TestRealm", "Officer-TestRealm" }
inGuild = true
bnetFriends = {
    { accountName = "RealFriend#1234", bnetAccountID = 77,
      gameAccountInfo = { characterName = "Bnetchar" } },
}
fire("GUILD_ROSTER_UPDATE")

local whitelistContent = _G["SanctuaryTabContent_whitelist"]
_G["SanctuaryTab_whitelist"]:Click()
local whitelistChild = _G.SanctuaryWhitelistScrollChild
check(whitelistChild ~= nil, "the whitelist tab builds its list")
check((whitelistChild:GetHeight() or 0) > 1,
    "an empty manual list no longer means an empty tab")

local function whitelistRowTexts()
    local texts = {}
    for _, row in ipairs(whitelistChild.__children or {}) do
        if row.label and row.__shown ~= false then
            texts[#texts + 1] = tostring(row.label.__text or "")
        end
    end
    return table.concat(texts, "\n")
end

local rendered = whitelistRowTexts()
check(rendered:find(ns.L["WL_AUTO_HEADER"], 1, true) ~= nil,
    "the automatic section is shown")
check(rendered:find(ns.L["WL_SOURCE_GUILD"], 1, true) ~= nil,
    "guild members get their own group")
check(rendered:find("Officer-TestRealm", 1, true) == nil,
    "and stay folded until asked for, so the tab does not spill a roster")

-- Expanding is one click, and the search forces the groups it matches open.
local guildRow
for _, row in ipairs(whitelistChild.__children or {}) do
    if row.label and tostring(row.label.__text or ""):find(ns.L["WL_SOURCE_GUILD"], 1, true) then
        guildRow = row
    end
end
check(guildRow ~= nil, "the group header is clickable")
guildRow:Click()
check(whitelistRowTexts():find("Officer-TestRealm", 1, true) ~= nil,
    "expanding a group lists its members")
guildRow:Click()

_G.SanctuaryWhitelistSearchInput:SetText("officer")
_G.SanctuaryWhitelistSearchInput:GetScript("OnTextChanged")(_G.SanctuaryWhitelistSearchInput)
rendered = whitelistRowTexts()
check(rendered:find("Officer-TestRealm", 1, true) ~= nil,
    "a search opens the groups it matches")
check(rendered:find("Guildmate-TestRealm", 1, true) == nil,
    "and shows only what it matched")
_G.SanctuaryWhitelistSearchInput:SetText("")
_G.SanctuaryWhitelistSearchInput:GetScript("OnTextChanged")(_G.SanctuaryWhitelistSearchInput)

-- "Does this person get through?" answered in the tab.
local checkBtn = findButtonByLabel(whitelistContent, ns.L["WL_CHECK_BTN"])
check(checkBtn ~= nil, "the check field has a button")

local function checkAnswerFor(name)
    _G.SanctuaryWhitelistCheckInput:SetText(name)
    checkBtn:Click()
    for _, childWidget in ipairs(whitelistContent.__children or {}) do
        local text = tostring(childWidget.__text or "")
        if childWidget.__kind == "FontString" and text:find(name, 1, true) then
            return text
        end
    end
    return nil
end

local answer = checkAnswerFor("Officer-TestRealm")
check(answer ~= nil and answer:find(ns.L["WL_REASON_GUILD"], 1, true) ~= nil,
    "a guild member is answered with the reason they get through")
answer = checkAnswerFor("Nobodyatall")
check(answer ~= nil and answer:find(ns.L["WL_REASON_NOT_WHITELISTED"], 1, true) ~= nil,
    "a stranger is answered as filtered, with the reason")

guildMembers = {}
bnetFriends = {}
inGuild = false
ns.invalidateWhitelist()

-- ---------------------------------------------------------------------------
-- The offline check the closing step now delegates to
-- ---------------------------------------------------------------------------

-- The checklist no longer asks anyone to scroll an export looking for five
-- entries: it runs tests/check_qa_run.lua on the settings file. That tool is
-- therefore part of the deliverable, and it is exercised end to end here --
-- including its exit code, which is what makes it usable without reading it.
local function writeFixture(chatFilterApi)
    local fixturePath = os.tmpname()
    local handle = assert(io.open(fixturePath, "w"))
    handle:write(([[
SanctuaryDB = {
    ["debugLogStats"] = { ["produced"] = 6, ["dropped"] = 0 },
    ["log"] = {},
    ["reportManifest"] = { ["trigger"] = "logout", ["savedAt"] = "2026-08-20 18:12:00",
        ["version"] = "0.3.2", ["build"] = "20260820-3", ["addonMetaBuild"] = "20260820-3",
        ["addonMetaInterface"] = "120100", ["clientVersion"] = "12.1.0",
        ["clientBuild"] = "61234", ["clientInterface"] = 120100, ["verdict"] = "ok" },
    ["debugLog"] = {
        { ["seq"] = 1, ["cat"] = "CHAT_OUTPUT", ["data"] = { ["action"] = "NO_MATCH" } },
        { ["seq"] = 2, ["cat"] = "POPUP", ["data"] = { ["action"] = "MASK_AWAITING_EVENT", ["affected"] = 1 } },
        { ["seq"] = 3, ["cat"] = "WORLD", ["data"] = { ["inInstance"] = true } },
        { ["seq"] = 4, ["cat"] = "PLAYER_STATE", ["data"] = { ["event"] = "PLAYER_DEAD" } },
        { ["seq"] = 5, ["cat"] = "SNAPSHOT", ["data"] = { ["chatFilterApiUsed"] = "%s",
            ["chatFramesSeen"] = 10, ["chatFramesWrapped"] = 10, ["systemChatTypeID"] = 90 } },
    },
}
]]):format(chatFilterApi))
    handle:close()
    return fixturePath
end

local function runChecker(fixturePath)
    local interpreter = (arg and arg[-1]) or "lua"
    local command = string.format('%q %q %q 2>&1', interpreter,
        repoRoot .. "/tests/check_qa_run.lua", fixturePath)
    local pipe = io.popen(command)
    local output = pipe:read("a")
    local _, _, code = pipe:close()
    return output or "", code
end

local goodFixture = writeFixture("legacy")
local goodOutput, goodCode = runChecker(goodFixture)
os.remove(goodFixture)
equal(goodCode, 0, "the checker accepts a complete recording")
check(goodOutput:find("RELEVE COMPLET", 1, true) ~= nil,
    "the checker says so in one line")
check(goodOutput:find("20260820-3", 1, true) ~= nil,
    "the checker reads the build out of the file, so nobody transcribes it")
for _, marker in ipairs({ "F1", "F2", "F3", "F4" }) do
    check(goodOutput:find("%[  ok  %] " .. marker) ~= nil,
        "the checker reports scenario marker " .. marker)
end

local badFixture = writeFixture("unregistered")
local badOutput, badCode = runChecker(badFixture)
os.remove(badFixture)
equal(badCode, 1, "the checker fails a recording that filtered nothing")
check(badOutput:find("ECHEC BLOQUANT", 1, true) ~= nil,
    "and says why in terms the checklist can quote")

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
equal(#SanctuaryDB.debugLog, 0, "accepting is what erases the debug log")
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
chatMessages = {}
SlashCmdList["SANCTUARY"]("diag sound blabla")
check(#chatMessages > 0 and chatMessages[#chatMessages]:find("/sanc diag sound invite", 1, true) ~= nil,
    "an unknown sound diagnostic names the one that exists")
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
