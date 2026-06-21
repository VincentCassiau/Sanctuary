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
function MuteSoundFile(id) muted[#muted + 1] = id end
function UnmuteSoundFile(id) unmuted[#unmuted + 1] = id end

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
        self.shown = false
        if self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    return popup
end

for i = 1, STATICPOPUP_NUMDIALOGS do
    _G["StaticPopup" .. i] = newPopup("StaticPopup" .. i)
end

local popup = StaticPopup1
function StaticPopup_Show(which, text_arg1, text_arg2, data)
    popup.which = which
    popup.shown = true
    popup.alpha = 1
    return popup
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

-- Initialize SavedVariables and filters.
fire("ADDON_LOADED", "Sanctuary")
fire("PLAYER_ENTERING_WORLD")
equal(ns.VERSION, "0.3.2", "version exported")
equal(#muted, 3, "invite sounds muted once at startup")
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
check(SanctuaryDB.debugLog[1].data.inviteSoundsMuted, "debug snapshot reports invite sound mute state")
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

SanctuaryDB.filters.channelMode = "all"
beforeChatDecisionDebug = #SanctuaryDB.debugLog
fire("CHAT_MSG_CHANNEL", "hello", "Unknown")
equal(#SanctuaryDB.debugLog, beforeChatDecisionDebug + 1, "blocked channel debug decision logged")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.kind, "channel", "channel decision kind")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.action, "BLOCK_NOT_WHITELISTED", "channel decision action")
SanctuaryDB.filters.channelMode = "none"

SanctuaryDB.debugLog = {}
for i = 1, 505 do
    ns.debugLog("ROTATE", { i = i })
end
equal(#SanctuaryDB.debugLog, 500, "debug log rotates to 500 entries")
equal(SanctuaryDB.debugLog[1].data.i, 6, "debug log keeps newest entries after rotation")

-- Blizzard-first blocked popup: hook masks before render, event declines, and no
-- direct StaticPopup_Hide is used.
inGroup = false
groupMembers = {}
popup:Hide()
StaticPopup_Show("PARTY_INVITE", "Harasser vous invite dans un groupe.")
equal(popup.alpha, 0, "unknown party popup masked immediately")
fire("PARTY_INVITE_REQUEST", "Harasser", false, false, true, true, false, "Player-1")
equal(popup.alpha, 0, "blocked popup remains masked")
equal(declinedGroups, 1, "blocked group invite declined")
equal(forbiddenStaticHides, 0, "no direct StaticPopup_Hide")
popup:Hide()
equal(popup.alpha, 1, "popup alpha restored on native hide")
runTimers()

-- Blizzard-first trusted popup: it is initially masked and restored in the same
-- event dispatch once the name-based decision is available.
SanctuaryDB.manualWhitelist.friend = { displayName = "Friend" }
ns.invalidateWhitelist()
StaticPopup_Show("PARTY_INVITE", "Friend vous invite dans un groupe.")
equal(popup.alpha, 0, "trusted popup guarded before event decision")
fire("PARTY_INVITE_REQUEST", "Friend", false, false, true, true, false, "Player-2")
equal(popup.alpha, 1, "trusted popup restored")
equal(declinedGroups, 1, "trusted invite not declined")
popup:Hide()
runTimers()

-- Sanctuary-first ordering: the pending decision is consumed by the later
-- StaticPopup_Show post-hook, avoiding both flash and false blocking.
fire("PARTY_INVITE_REQUEST", "Friend", false, false, true, true, false, "Player-3")
StaticPopup_Show("PARTY_INVITE", "Friend vous invite dans un groupe.")
equal(popup.alpha, 1, "trusted decision survives Sanctuary-first ordering")
popup:Hide()
runTimers()

fire("PARTY_INVITE_REQUEST", "Anotherbad", false, false, true, true, false, "Player-4")
StaticPopup_Show("PARTY_INVITE", "Anotherbad vous invite dans un groupe.")
equal(popup.alpha, 0, "blocked decision survives Sanctuary-first ordering")
equal(declinedGroups, 2, "Sanctuary-first blocked invite declined")
popup:Hide()
runTimers()

-- Duel and guild-invite popups use the same mask/native-decline strategy.
StaticPopup_Show("DUEL_REQUESTED", "Duelbad veut vous provoquer en duel.")
equal(popup.alpha, 0, "unknown duel popup masked immediately")
fire("DUEL_REQUESTED", "Duelbad")
equal(cancelledDuels, 1, "blocked duel cancelled")
popup:Hide()
runTimers()

fire("GUILD_INVITE_REQUEST", "Guildbad", "Bad Guild")
StaticPopup_Show("GUILD_INVITE", "Guildbad vous invite dans une guilde.")
equal(popup.alpha, 0, "blocked guild invite popup masked")
equal(declinedGuilds, 1, "blocked guild invite declined")
popup:Hide()
runTimers()

SanctuaryDB.filters.duel = false
StaticPopup_Show("DUEL_REQUESTED", "Duelbad2 veut vous provoquer en duel.")
equal(popup.alpha, 1, "duel popup unprotected when duel filter disabled")
fire("DUEL_REQUESTED", "Duelbad2")
equal(cancelledDuels, 1, "disabled duel filter does not cancel")
popup:Hide()
runTimers()
SanctuaryDB.filters.duel = true

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
now = now + 2
fire("TRADE_SHOW")
equal(closedTrades, 1, "blocked trade closed")
equal(SanctuaryDB.log[#SanctuaryDB.log].type, "trade", "blocked trade logged")
npcName = nil

-- Disabling the invitation filter immediately restores sound state.
SanctuaryDB.filters.groupInvite = false
ns.refreshInviteSoundMuteState()
equal(#unmuted, 3, "invite sounds unmuted when filter disabled")
check(type(ns.simulateInvite) == "function", "invite simulator exported")
local disabledSimulation = ns.simulateInvite("Simulatedbad")
check(disabledSimulation.shouldBlock, "disabled invite filter still reports raw block decision")
check(not disabledSimulation.filterEnabled, "disabled invite filter reported by simulator")
check(not disabledSimulation.systemSuppressed, "disabled invite filter does not suppress system message")
equal(disabledSimulation.popupAction, "pass", "disabled invite filter does not protect popup")
check(not disabledSimulation.inviteSoundsMuted, "disabled invite filter leaves invite sounds unmuted")
SanctuaryDB.filters.groupInvite = true
ns.refreshInviteSoundMuteState()
equal(#muted, 6, "invite sounds muted again when filter enabled")

SanctuaryCharDB.overrides.enabled = false
ns.refreshInviteSoundMuteState()
equal(#unmuted, 6, "invite sounds unmuted when addon disabled")
local addonDisabledSimulation = ns.simulateInvite("Simulatedbad")
check(addonDisabledSimulation.shouldBlock, "disabled addon still reports raw block decision")
check(not addonDisabledSimulation.filterEnabled, "disabled addon disables invite filtering")
check(not addonDisabledSimulation.systemSuppressed, "disabled addon does not suppress system message")
filtered = chatFilters.CHAT_MSG_WHISPER(nil, "CHAT_MSG_WHISPER", "hello", "Unknown")
check(not filtered, "disabled addon lets whisper pass")
SanctuaryCharDB.overrides.enabled = nil
ns.refreshInviteSoundMuteState()
equal(#muted, 9, "invite sounds remuted when addon re-enabled")

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

local beforeSlashMessages = #chatMessages
SlashCmdList["SANCTUARY"]("simulate Simulatedbad")
check(#chatMessages == beforeSlashMessages + 1, "slash simulation prints one diagnostic line")
check(chatMessages[#chatMessages]:find("Simulation invite", 1, true) ~= nil, "slash simulation output label")
equal(declinedGroups, beforeSimulationDeclines, "slash simulation does not decline groups")

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
fire("CHAT_MSG_WHISPER", "bad", "Blocked")
runTimers()
equal(#closedChatFrames, 1, "only one whisper tab closed")
equal(closedChatFrames[1], ChatFrame1, "blocked sender tab closed exactly")

if failures > 0 then
    io.stderr:write(string.format("%d/%d assertions failed\n", failures, assertions))
    os.exit(1)
end

print(string.format("OK: %d assertions", assertions))
