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
-- The clock the addon reads dates from. Format-sensitive, because the Journal
-- now asks it two different questions -- which day is it, and what time is it --
-- and merging "the same message from the same person, today" is a rule a test
-- has to be able to walk over midnight to prove.
local harnessDay = "2026-06-20"
local function setHarnessDay(day) harnessDay = day end
function date(fmt, value)
    if fmt == "%Y-%m-%d" then return harnessDay end
    if fmt == "%H:%M:%S" then return "12:00:00" end
    return harnessDay .. " 12:00:00"
end
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
    Version = "1.0.0",
    ["X-Sanctuary-Build"] = "20260820-8",
    Interface = "120007",
}
C_AddOns = {
    IsAddOnLoaded = function() return false end,
    GetAddOnMetadata = function(addonName, field)
        if addonName ~= "Sanctuary" then return nil end
        return addonMetadata[field]
    end,
    -- The API Retail actually answers the .toc's Interface with: a number, and
    -- the one the AddOns manager grades "Out of date" on. `GetAddOnMetadata`
    -- does not serve that field on this client, which is why the recording read
    -- `addonMetaInterface=nil` on every snapshot.
    GetAddOnInterfaceVersion = function(addonName)
        if addonName ~= "Sanctuary" then return nil end
        return tonumber(addonMetadata.Interface)
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
-- Which unit tokens name a player. Anything a case declares here is a player;
-- everything else -- a shopkeeper, a training dummy -- is not, which is the
-- distinction the right-click menu now refuses to write a list entry without.
npcUnits = {}
function UnitIsPlayer(unit) return not npcUnits[unit] end
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
-- The registered callbacks, in registration order. Blizzard keeps a list per
-- event and invokes every one of them once per ChatFrame, so "one message, N
-- consumers" is a shape the harness has to be able to play: the anti-spam rests
-- on every consumer of one message getting one verdict, whatever order they are
-- called in. `chatFilters` stays the single last-registered callback the older
-- sections call directly.
local chatFilterList = {}
local chatFilterRegistrations = 0
local function recordChatFilter(event, callback)
    chatFilterRegistrations = chatFilterRegistrations + 1
    chatFilters[event] = callback
    local list = chatFilterList[event]
    if not list then
        list = {}
        chatFilterList[event] = list
    end
    list[#list + 1] = callback
end

function ChatFrame_AddMessageEventFilter(event, callback)
    recordChatFilter(event, callback)
end

-- Retail owns the registry through ChatFrameUtil and keeps the historical
-- global as an alias declared by Blizzard_DeprecatedChatInfo. Model both paths
-- so the availability adapter can be exercised.
ChatFrameUtil = {
    AddMessageEventFilter = function(event, callback)
        recordChatFilter(event, callback)
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

-- What Retail calls to open a chat window. The temporary one -- a whisper
-- conversation, a Battle.net conversation, a pet battle -- is what makes an
-- eleventh frame appear halfway through a session, and it is the frame the
-- 23/08 recording found unwrapped: DEGRADED (chat_frames=10/11). Modelled here
-- so a frame born after the hooks are in place is a case a check can set up.
temporaryChatWindows = 0
function FCF_OpenTemporaryWindow(chatType, chatTarget)
    temporaryChatWindows = temporaryChatWindows + 1
    local index = 10 + temporaryChatWindows
    local frame = {
        chatType = chatType,
        chatTarget = chatTarget,
        AddMessage = function(self, message, ...)
            chatMessages[#chatMessages + 1] = message
            chatMessageArgs[#chatMessageArgs + 1] = { n = select("#", ...), ... }
        end,
    }
    _G["ChatFrame" .. index] = frame
    return frame, index
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

-- One message, several chat windows, and the order between them is unknown.
-- WoW invokes the registered filter once per ChatFrame and the event handler
-- once, and nothing documents which comes first -- so a test plays all three
-- orders and reads back what every consumer was told. Answers the list of
-- discard verdicts, one per filter call, in the order they were made.
local function deliverChatMessage(order, windows, event, ...)
    windows = windows or 3
    local argCount, args = select("#", ...), { ... }
    local verdicts = {}
    local function runFilters(count)
        for _ = 1, count do
            for _, callback in ipairs(chatFilterList[event] or {}) do
                local discarded = false
                -- The registry skips a callback whose payload holds a secret
                -- value, exactly as `dispatchChatFilter` models it.
                if canaccessvalue(unpackCompat(args, 1, argCount)) then
                    discarded = callback(nil, event, unpackCompat(args, 1, argCount)) and true or false
                end
                verdicts[#verdicts + 1] = discarded
            end
        end
    end
    local function runHandler()
        fire(event, unpackCompat(args, 1, argCount))
    end
    if order == "handler_first" then
        runHandler()
        runFilters(windows)
    elseif order == "handler_between" then
        runFilters(1)
        runHandler()
        runFilters(windows - 1)
    else
        runFilters(windows)
        runHandler()
    end
    return verdicts
end

-- The payload of CHAT_MSG_CHANNEL, down to the eleventh argument. `lineID` is
-- what names one physical message, and the vararg of both a filter and a
-- handler starts at the third argument -- so it is `select(9, ...)` on both
-- sides, and a test that builds the payload by hand is the only way to prove it.
local function channelPayload(message, sender, lineID)
    return message, sender, "", "General", "", "", 0, 1, "General", "", lineID
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
equal(ns.VERSION, "1.0.0", "version exported")
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
-- "Am I the sender" folds the realm by the one rule the blocked list uses, so a
-- realm written with a space, a hyphen or an apostrophe is still the player's
-- own realm. It used to have a second copy of that rule, which is precisely the
-- fault this release hunted down elsewhere.
filtered = chatFilters.CHAT_MSG_SAY(nil, "CHAT_MSG_SAY", "hello", "Victim-Test Realm")
check(not filtered, "own message passes with the realm spelled with a space")
filtered = chatFilters.CHAT_MSG_SAY(nil, "CHAT_MSG_SAY", "hello", "Victim-Test-Realm")
check(not filtered, "and with a hyphen")
filtered = chatFilters.CHAT_MSG_SAY(nil, "CHAT_MSG_SAY", "hello", "Victim-Ysondre")
check(filtered, "while the same name on another realm is not the player")
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
equal(SanctuaryDB.debugLog[1].data.version, "1.0.0", "debug snapshot version")
equal(SanctuaryDB.debugLog[1].data.build, "20260820-8", "debug snapshot reports the diagnostic build id")
equal(SanctuaryDB.debugLog[1].data.clientVersion, "12.0.7", "debug snapshot reports the client version")
equal(SanctuaryDB.debugLog[1].data.clientBuild, "62119", "debug snapshot reports the client build")
equal(SanctuaryDB.debugLog[1].data.clientInterface, 120007, "debug snapshot reports the client interface number")
equal(SanctuaryDB.debugLog[1].data.addonMetaVersion, "1.0.0", "debug snapshot reports the loaded addon version metadata")
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

-- Decision 109: every snapshot of the 23/08 recording carried
-- `addonMetaInterface=nil` while the header read `interface=120100`.
-- `GetAddOnMetadata` answers for the custom X- fields and a documented handful
-- of standard ones; "Interface" is not among them on this client and comes back
-- nil every time. Retail exposes that value through `GetAddOnInterfaceVersion`,
-- which is the API meant for the question, so that is where the answer comes
-- from when the metadata says nothing.
do
    local savedMeta = C_AddOns.GetAddOnMetadata
    C_AddOns.GetAddOnMetadata = function(_, field)
        if field == "Interface" then return nil end
        return savedMeta(_, field)
    end
    local context = ns.getClientBuildContext()
    equal(context.addonMetaInterface, tostring(context.addonInterface),
        "a client that will not hand over the .toc interface still reports one")
    check(context.addonMetaInterface ~= "nil",
        "which is the field that came back nil on every snapshot of the recording")

    -- A real read error is still an error: it is not papered over by a second
    -- source, or a broken metadata API would read as a healthy one.
    C_AddOns.GetAddOnMetadata = function(_, field)
        if field == "Interface" then error("boom") end
        return savedMeta(_, field)
    end
    equal(ns.getClientBuildContext().addonMetaInterface, "error",
        "and a metadata call that fails stays an error")
    C_AddOns.GetAddOnMetadata = savedMeta
end
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

-- A chat window opened DURING the session, decision 106. The scan used to run
-- at load and at PLAYER_ENTERING_WORLD and never again, so the eleventh frame
-- printed straight past the envelope for the rest of the session and the
-- recording graded itself DEGRADED (chat_frames=10/11) with no way to say which
-- frame or why.
do
    local health = ns.getInstrumentationHealth()
    equal(health.chatFramesSeen, health.chatFramesWrapped,
        "every chat frame there is, is wrapped before the new one opens")
    local newFrame = FCF_OpenTemporaryWindow("WHISPER", "Somebody")
    -- The hook fires on the way out of the opener, so by here it is wrapped:
    -- nothing below asks for a rescan.
    health = ns.getInstrumentationHealth()
    equal(health.chatFramesSeen, 2, "the new window is counted")
    equal(health.chatFramesWrapped, 2, "and it is wrapped, with no rescan asked for")
    equal(ns.getInstrumentationVerdict({
        chatFilterApiUsed = health.chatFilterApiUsed,
        chatFramesSeen = health.chatFramesSeen,
        chatFramesWrapped = health.chatFramesWrapped,
        systemChatTypeID = health.systemChatTypeID,
    }), "ok", "so the recording no longer grades itself degraded on chat_frames")

    -- And the envelope really is doing its work on that frame: a blocked invite
    -- line printed to it is suppressed exactly as on ChatFrame1.
    local before = #chatMessages
    newFrame:AddMessage(systemMessage)
    equal(#chatMessages, before, "a blocked invite line is suppressed on the new window too")

    _G.ChatFrame11 = nil
    temporaryChatWindows = 0
end

local trustedOutputMessage = "[Friend] vous a invité à rejoindre un groupe, mais vous ne pouviez pas accepter car vous êtes déjà dans un groupe."
SanctuaryDB.manualWhitelist["friend-testrealm"] = { displayName = "Friend" }
ns.invalidateWhitelist()
ns.getCharacterDecision("Friend")
beforeOutputDebug = #SanctuaryDB.debugLog
beforeOutputMessages = #chatMessages
ChatFrame1:AddMessage(trustedOutputMessage)
equal(#chatMessages, beforeOutputMessages + 1, "chat output guard preserves trusted invite text")
equal(#SanctuaryDB.debugLog, beforeOutputDebug + 1, "chat output diagnostic logs trusted invite text")
equal(SanctuaryDB.debugLog[#SanctuaryDB.debugLog].data.action, "ALLOW_INVITE_OUTPUT", "trusted invite output diagnostic reports allow")
SanctuaryDB.manualWhitelist["friend-testrealm"] = nil
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
SanctuaryDB.manualWhitelist["friend-testrealm"] = { displayName = "Friend" }
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
SanctuaryDB.manualWhitelist["friend-testrealm"] = nil
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
-- the frame, because nothing stopped it. That is the defect 1.0.0 fixes, so the
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

SanctuaryDB.manualWhitelist["friend-testrealm"] = { displayName = "Friend" }
ns.invalidateWhitelist()
local allowedDiscarded, allowedPath = dispatchChatFilter("CHAT_MSG_SYSTEM", trustedOutputMessage)
equal(allowedPath, "called", "trusted system payload reaches the addon filter")
check(not allowedDiscarded, "trusted invite text is not discarded by the registry")
SanctuaryDB.manualWhitelist["friend-testrealm"] = nil
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
SanctuaryDB.manualWhitelist["friend-testrealm"] = { displayName = "Friend" }
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

SanctuaryDB.manualWhitelist["duelfriend-testrealm"] = { displayName = "DuelFriend" }
SanctuaryDB.manualWhitelist["guildfriend-testrealm"] = { displayName = "GuildFriend" }
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

SanctuaryDB.manualWhitelist["traderfriend-testrealm"] = { displayName = "TraderFriend" }
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

-- The two sounds are separate buttons since 1.0.0: played inside one call, no
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
-- Tracked under the name with its realm: the shape the blocked list keys on, so
-- the ticker below can ask about the right person.
local dungeonmateKey = "Dungeonmate-TestRealm"
local trackedAt = SanctuaryCharDB.groupTracker[dungeonmateKey]
check(trackedAt ~= nil, "group member tracking started, realm and all")
now = now + 30
fire("PLAYER_ENTERING_WORLD")
equal(SanctuaryCharDB.groupTracker[dungeonmateKey], trackedAt, "group tracker survives loading transition")
now = trackedAt + (SanctuaryDB.temporalGroupTrust.trustThresholdMinutes * 60) + 1
runTickers()
check(SanctuaryDB.manualWhitelist["dungeonmate-testrealm"] ~= nil, "auto-trust adds member after threshold")
ns.invalidateWhitelist()
block = ns.getCharacterDecision("Dungeonmate-TestRealm")
check(not block, "auto-trusted member passes whitelist decision")

-- Automatic trust never reaches over the blocked list. Staying in the group was
-- all a harasser had to do: `ns.addAllowed` displaces whatever it finds in
-- "Toujours bloques", the ticker prints nothing and throws the `displaced`
-- answer away, so the entry vanished and the name came back allowed with source
-- "trust" -- silently, and exactly against the one list that is supposed to beat
-- every trust source.
do
    local addedBlocked = ns.addBlocked("Stayer-TestRealm")
    check(addedBlocked, "a name is put into the blocked list by hand")
    equal(ns.classifyName("Stayer-TestRealm").verdict, "always_blocked",
        "and it answers always_blocked before the group timer")
    SanctuaryCharDB.groupTracker.stayer = now - 1000
    runTickers()
    check(SanctuaryDB.blockedNames["stayer-testrealm"] ~= nil,
        "five minutes in the group do not take it out of the blocked list")
    equal(SanctuaryDB.manualWhitelist["stayer-testrealm"], nil,
        "and nothing is written on the allowed side")
    ns.invalidateWhitelist()
    local stayer = ns.classifyName("Stayer-TestRealm")
    equal(stayer.verdict, "always_blocked", "the name is still blocked after the ticker")
    equal(stayer.list, "blocked_name", "on the entry the person typed, not on trust")
    equal(SanctuaryCharDB.groupTracker.stayer, nil,
        "and the tracker drops it rather than weighing it again every 30 s")
    ns.removeBlocked("stayer-testrealm")
    ns.invalidateWhitelist()
end

-- The same thing across realms, which is the shape a dungeon group actually has.
-- The tracker used to key its members on the bare pseudo -- the realm was built
-- and then thrown away -- so the ticker asked "is <pseudo> blocked?" of a lookup
-- that answers for one realm only: the player's own. A harasser blocked as
-- "Cross-Hyjal" from the right-click menu, which writes the name with its realm,
-- was not recognised: five minutes of standing in the group wrote him into
-- "Toujours autorises" with source "trust", the tile counted him, and the tester
-- answered "toujours autorise : trust" while the blocked entry was still there.
-- The two lists holding one person at once is what decision 104 exists to end.
do
    inGroup = true
    groupMembers = { "Cross-Hyjal" }
    fire("GROUP_ROSTER_UPDATE")
    check(SanctuaryCharDB.groupTracker["Cross-Hyjal"] ~= nil,
        "a cross-realm member is tracked under the name with its realm")

    local addedBlocked = ns.addBlocked("Cross-Hyjal", "menu")
    check(addedBlocked, "and can be put into the blocked list from the menu")
    local trustBefore = ns.getListCounts().allowed.trust
    -- Aged through whatever key the tracker chose, so this measures the ticker's
    -- decision and not the harness's idea of the key.
    for trackedKey in pairs(SanctuaryCharDB.groupTracker) do
        SanctuaryCharDB.groupTracker[trackedKey] = now - 1000
    end
    runTickers()
    check(SanctuaryDB.blockedNames["cross-hyjal"] ~= nil,
        "five minutes in a cross-realm group do not take him out of the blocked list")
    equal(SanctuaryDB.manualWhitelist["cross-hyjal"], nil,
        "and nothing is written on the allowed side")
    ns.invalidateWhitelist()
    equal(ns.getListCounts().allowed.trust, trustBefore,
        "so the automatic-trust tile does not count him either")
    equal(SanctuaryCharDB.groupTracker["Cross-Hyjal"], nil,
        "the tracker drops him rather than weighing him again every 30 s")

    -- Back to the group the section was playing with, and without a roster
    -- update: the ticker already emptied the tracker, and firing one here would
    -- start tracking a member the cases below never asked about.
    ns.removeBlocked("cross-hyjal")
    groupMembers = { "Dungeonmate-TestRealm" }
    ns.invalidateWhitelist()
end

-- And the other way of being blocked: a PATTERN. The ticker's own guard asks
-- `ns.findBlockedKey`, which reads `SanctuaryDB.blockedNames` and nothing else,
-- so somebody caught by "toxic" walked straight past it: five minutes in the
-- group wrote him into "Toujours autorises" with source "trust", the tile
-- counted him and the panel listed him, while `classifyName` went on answering
-- always_blocked/keyword. One person on both lists at once, which is the pair
-- decision 104 exists to make impossible -- the same symptom as the two cases
-- above, through the door they did not close.
--
-- Both realm shapes, because that is the other half of what the guard has to
-- survive: the player's own realm and somebody else's, which is what a dungeon
-- group is made of. And a member the pattern does not catch stands beside them
-- as the witness: refusing everything would hold the invariant too, and kill the
-- feature without a single test noticing.
do
    inGroup = true
    groupMembers = { "Toxichome-TestRealm", "Toxicguy-Hyjal", "Cleanmate-Hyjal" }
    fire("GROUP_ROSTER_UPDATE")
    check(SanctuaryCharDB.groupTracker["Toxichome-TestRealm"] ~= nil,
        "a member on the player's realm is tracked")
    check(SanctuaryCharDB.groupTracker["Toxicguy-Hyjal"] ~= nil,
        "a member on another realm is tracked")
    check(SanctuaryCharDB.groupTracker["Cleanmate-Hyjal"] ~= nil,
        "and so is the member no pattern catches")

    check(ns.addPattern("toxic"), "a pattern is added instead of an exact name")
    equal(ns.classifyName("Toxichome-TestRealm").list, "keyword",
        "it blocks the member on the player's realm")
    equal(ns.classifyName("Toxicguy-Hyjal").list, "keyword",
        "and the one on another realm, before the group timer")

    local trustBefore = ns.getListCounts().allowed.trust
    -- Aged through whatever key the tracker chose, so this measures the ticker's
    -- decision and not the harness's idea of the key.
    for trackedKey in pairs(SanctuaryCharDB.groupTracker) do
        SanctuaryCharDB.groupTracker[trackedKey] = now - 1000
    end
    runTickers()
    equal(SanctuaryDB.manualWhitelist["toxichome-testrealm"], nil,
        "five minutes do not write a pattern-blocked member into the allowed list")
    equal(SanctuaryDB.manualWhitelist["toxicguy-hyjal"], nil,
        "nor the same case on another realm")
    ns.invalidateWhitelist()
    local toxicHome = ns.classifyName("Toxichome-TestRealm")
    equal(toxicHome.verdict, "always_blocked", "he is still blocked after the ticker")
    equal(toxicHome.list, "keyword", "on the pattern, not on trust")
    local toxicAway = ns.classifyName("Toxicguy-Hyjal")
    equal(toxicAway.verdict, "always_blocked", "and so is the cross-realm one")
    equal(toxicAway.list, "keyword", "on the pattern too")
    equal(SanctuaryCharDB.groupTracker["Toxicguy-Hyjal"], nil,
        "the tracker drops them rather than weighing them again every 30 s")

    -- The witness. Without it this whole block would pass on a correction that
    -- simply stopped granting trust to anybody.
    check(SanctuaryDB.manualWhitelist["cleanmate-hyjal"] ~= nil,
        "the member no pattern catches still earns his automatic trust")
    equal(SanctuaryDB.manualWhitelist["cleanmate-hyjal"].source, "trust",
        "recorded as trust, like any other automatically trusted contact")
    equal(ns.getListCounts().allowed.trust, trustBefore + 1,
        "and the automatic-trust tile counts him and nobody else")

    -- The refusal is the ticker's alone: a name typed by hand, or allowed from
    -- the right-click menu, keeps the behaviour it had -- the pattern still wins
    -- the decision, but the entry is written and the panel shows it.
    equal(select(1, ns.addAllowed("Toxicguy-Hyjal")), true,
        "the same name added by hand is not refused")
    ns.removeAllowed("toxicguy-hyjal")

    ns.removePattern("toxic")
    ns.removeAllowed("cleanmate-hyjal")
    groupMembers = { "Dungeonmate-TestRealm" }
    ns.invalidateWhitelist()
end

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
SanctuaryDB.manualWhitelist["typedname-testrealm"] = { displayName = "TypedName", addedAt = 1, source = "manual" }
-- Someone both typed in and in the guild keeps the label they were typed under:
-- the manual list is the one the maintainer can act on.
SanctuaryDB.manualWhitelist["guildmate-testrealm"] = { displayName = "Guildmate", addedAt = 1, source = "manual" }
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

-- "Test a name" -- the same decision, not a second one. Since 1.0.0 it answers
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
ns.removeBlocked(ns.normalizeCharacterKey("Officer-TestRealm"))

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
-- SECTION: the 1.0.0 decision model
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
    SanctuaryDB.antiSpam = { enabled = false, intervalSeconds = 300 }
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

-- C2a -- a pattern is looked for in the pseudo, and never in the realm. The
-- panel promises exactly that ("any name containing it is blocked", "text to
-- look for in names"); read against the whole string, a pattern matched the
-- realm half instead. In a random dungeon every name arrives realm-qualified, so
-- the pattern "illidan" cut off every companion from Illidan -- allowed players,
-- silenced with no popup, no sound and no chat line, and the always-blocked door
-- beats every allow list, so nothing caught them.
resetModelState()
inGroup = true
inInstance = true
currentInstanceType = "party"
groupMembers = { "Healer-Illidan" }
SanctuaryDB.keywords = { "illidan" }
ns.invalidateWhitelist()

equal(ns.classifyName("Healer-Illidan").verdict, "always_allowed",
    "a dungeon companion FROM Illidan is not somebody the pattern names")
for _, event in ipairs({ "CHAT_MSG_PARTY", "CHAT_MSG_INSTANCE_CHAT" }) do
    equal(dispatchChatFilter(event, "pull now", "Healer-Illidan"), false,
        event .. " leaves his message alone")
end
-- The pseudo half still answers, exactly as the panel says it does.
equal(ns.classifyName("Illidanx-TestRealm").verdict, "always_blocked",
    "while a pseudo containing the pattern is blocked")
equal(select(2, ns.getCharacterDecision("Illidanx-TestRealm")), "keyword",
    "and reported as a pattern")
equal(dispatchChatFilter("CHAT_MSG_PARTY", "spam", "Illidanx-TestRealm"), true,
    "so his group message is the one that goes")

-- And on the invitation path, where being wrong is silent. Both are guild
-- members, so only the pattern can separate them: the one it names is refused,
-- the one whose realm merely spells it is left to WoW.
resetModelState()
guildMembers = { "Healer-Illidan", "Illidanx-TestRealm" }
inGuild = true
SanctuaryDB.keywords = { "illidan" }
ns.invalidateWhitelist()
do
    local before = declinedGroups
    fire("PARTY_INVITE_REQUEST", "Healer-Illidan")
    runTimers(3)
    equal(declinedGroups, before, "an invitation from Illidan is not refused")
    fire("PARTY_INVITE_REQUEST", "Illidanx-TestRealm")
    runTimers(3)
    equal(declinedGroups, before + 1, "while the one the pattern names is")
end

-- C2b -- every entry of the blocked list carries a realm, spelled one way.
-- Two faults lived here. A bare key stood for every realm at once, so blocking
-- one harasser cut off his namesake in the player's own guild -- in silence, the
-- worst way to be wrong. And on a hyphenated realm the two halves of a key came
-- from sources that spell the realm differently -- `GetNormalizedRealmName`
-- drops the hyphen, the realm half of an event keeps it -- so the entry and the
-- lookup never met and the block simply did not happen.
resetModelState()
guildMembers = { "Toto-TestRealm" }
inGuild = true
ns.invalidateWhitelist()

equal(select(2, ns.addBlocked("Toto-Ysondre")), "toto-ysondre",
    "an entry typed with a realm is keyed on that realm")
equal(ns.classifyName("Toto-Ysondre").verdict, "always_blocked",
    "the character the entry names is blocked")
equal(ns.classifyName("Toto-TestRealm").verdict, "always_allowed",
    "while his namesake in the guild is left alone")
equal(dispatchChatFilter("CHAT_MSG_WHISPER", "hi", "Toto-Ysondre"), true,
    "the blocked one's whisper is discarded")
equal(dispatchChatFilter("CHAT_MSG_WHISPER", "hi", "Toto-TestRealm"), false,
    "and the guild member's arrives, exactly as it did before anyone was blocked")

-- The same split on the invitation path, where being wrong is silent: one
-- invite refused, the other left to WoW.
local beforeSplitDeclines = declinedGroups
fire("PARTY_INVITE_REQUEST", "Toto-Ysondre")
runTimers(3)
equal(declinedGroups, beforeSplitDeclines + 1, "the blocked namesake's invite is refused")
fire("PARTY_INVITE_REQUEST", "Toto-TestRealm")
runTimers(3)
equal(declinedGroups, beforeSplitDeclines + 1, "the guild namesake's invite is not")

-- A name typed with no realm means the realm the player is on -- what an invite
-- box shows when the other player shares it -- and not every realm at once.
resetModelState()
equal(select(2, ns.addBlocked("Solo")), "solo-testrealm",
    "a name typed with no realm is stored on the player's own realm")
equal(ns.classifyName("Solo").verdict, "always_blocked",
    "so it answers to the bare name an event carries")
equal(ns.classifyName("Solo-TestRealm").verdict, "always_blocked",
    "and to the same character written out in full")
check(ns.classifyName("Solo-Ysondre").verdict ~= "always_blocked",
    "while the same name on another realm is nobody anyone blocked")

-- A hyphenated realm, spelled both ways. The entry is typed the way the player
-- reads it in game ("Azjol-Nerub"); the lookup arrives with the spelling the
-- game normalises to ("AzjolNerub"). One rule makes the two meet, and it has to
-- hold in both directions, since either side can be the one carrying the hyphen.
resetModelState()
equal(select(2, ns.addBlocked("Hyphen-Azjol-Nerub")), "hyphen-azjolnerub",
    "the first hyphen splits name from realm, the rest of them belong to the realm")
equal(ns.classifyName("Hyphen-AzjolNerub").verdict, "always_blocked",
    "the de-hyphenated spelling finds the entry typed with the hyphen")
equal(dispatchChatFilter("CHAT_MSG_WHISPER", "hi", "Hyphen-Azjol-Nerub"), true,
    "a whisper from that realm is discarded as typed")
equal(dispatchChatFilter("CHAT_MSG_WHISPER", "hi", "Hyphen-AzjolNerub"), true,
    "and as the game hands it over")

equal(select(2, ns.addBlocked("Other-AzjolNerub")), "other-azjolnerub",
    "an entry that already carries the game's spelling is keyed the same way")
equal(ns.classifyName("Other-Azjol-Nerub").verdict, "always_blocked",
    "so the hyphenated spelling finds that one too")
check(ns.classifyName("Hyphen-TestRealm").verdict ~= "always_blocked",
    "and none of this leaks onto the player's own realm")

-- Spaces and apostrophes fold like hyphens, so a realm keeps one spelling
-- whether it comes from the roster, an event or the keyboard.
equal(ns.normalizeCharacterKey("Mixed-Conseil des Ombres"), "mixed-conseildesombres",
    "a realm written with spaces is keyed without them")
equal(ns.normalizeCharacterKey("Mixed-Kil'jaeden"), "mixed-kiljaeden",
    "and one written with an apostrophe without it")

-- C2c -- what the field invites ("Name or Name-Realm"), typed by a keyboard
-- under pressure. The hyphen left under the fingers and the space typed instead
-- of it used to build keys no event in the game ever produces --
-- "toto--testrealm", "totoysondre-testrealm". Those entries showed in the panel,
-- counted in the tile and armed the guards, and blocked nobody: the person
-- typing a harasser's name was told nothing and protected from nothing.
--
-- One invariant, never anything in between: either nothing is written at all, or
-- the entry blocks the character it names -- under the spelling that was typed
-- AND under its canonical one.
resetModelState()
for _, case in ipairs({
    { typed = "Toto-",                canonical = "Toto-TestRealm" },
    { typed = "-Toto",                canonical = "Toto-TestRealm" },
    { typed = "Toto Ysondre",         canonical = "Toto-Ysondre" },
    { typed = "Toto - Ysondre",       canonical = "Toto-Ysondre" },
    { typed = "Toto-Les Sentinelles", canonical = "Toto-LesSentinelles" },
    { typed = "Toto-Azjol-Nerub",     canonical = "Toto-AzjolNerub" },
}) do
    wipe(SanctuaryDB.blockedNames)
    ns.invalidateWhitelist()
    local before = ns.getListCounts().blocked.names
    local added = ns.addBlocked(case.typed)
    local after = ns.getListCounts().blocked.names
    if added then
        equal(after, before + 1, "\"" .. case.typed .. "\" makes one entry")
        equal(ns.classifyName(case.typed).verdict, "always_blocked",
            "and it blocks the character it was typed for")
        equal(ns.classifyName(case.canonical).verdict, "always_blocked",
            "as well as that character written out \"" .. case.canonical .. "\"")
    else
        equal(after, before, "\"" .. case.typed .. "\" was refused and wrote nothing")
    end
end

-- Nothing but separators is nobody: refused outright, so no line the game can
-- never match reaches the panel.
for _, typed in ipairs({ "-", " - ", "--" }) do
    wipe(SanctuaryDB.blockedNames)
    ns.invalidateWhitelist()
    equal(select(1, ns.addBlocked(typed)), false,
        "\"" .. typed .. "\" is not a name and is refused")
    equal(ns.getListCounts().blocked.names, 0, "leaving nothing behind")
end

-- A BattleTag is not a character name and the blocked field refuses it: read as
-- a pseudo and a realm it built "real-friend#1234", an entry no event can ever
-- produce, while the panel's own line above the field says a Battle.net friend
-- cannot be blocked there. The character that friend plays is another matter,
-- and stays blockable.
wipe(SanctuaryDB.blockedNames)
ns.invalidateWhitelist()
equal(select(1, ns.addBlocked("Real Friend#1234")), false,
    "a name carrying a BattleTag is refused")
equal(ns.getListCounts().blocked.names, 0, "writing nothing")
equal(ns.hasAlwaysBlockedEntries(), false, "and arming nothing")
equal(select(1, ns.addBlocked("Bnetchar-Ysondre")), true,
    "while the character a Battle.net friend plays is still blockable")
equal(ns.getListCounts().blocked.names, 1, "and counted")

-- Refused on the tag alone, never on the Battle.net roster: an account name in
-- one word is spelled exactly like a character, and reading the roster here
-- would leave somebody unable to block a harasser who happens to be a namesake.
bnetFriends = { { accountName = "Toto", bnetAccountID = 77 } }
ns.invalidateWhitelist()
equal(select(1, ns.addBlocked("Toto")), true,
    "a name that also spells a Battle.net account is still blockable")
equal(ns.getListCounts().blocked.names, 2, "and written")
bnetFriends = {}
ns.invalidateWhitelist()

-- C2d -- the same field, the same rule, on the allowed side. Both panels invite
-- "Name or Name-Realm", and the allowed list used to read it with a rule of its
-- own: spaces squashed instead of cut, a hyphen honoured only with a character
-- in front. "Toto Ysondre" was keyed "totoysondre" and "-Toto" was keyed
-- "-toto" -- so the friend whose label the person could read in the panel, and
-- see counted in the tile, went on being filtered with no popup, no sound and no
-- line. An allowed player keeps WoW's own behaviour: that is not negotiable.
--
-- Same invariant as the blocked side, on the other list: either nothing is
-- written at all, or the entry allows the character it names -- under the
-- spelling that was typed AND under its canonical one. Realm and all, since
-- decision 119: the realm that was typed when there was one, the player's own
-- when there was not, and nobody of that name on any other realm.
resetModelState()
for _, case in ipairs({
    { typed = "Toto Ysondre", canonical = "Toto-Ysondre", elsewhere = "Toto-TestRealm" },
    { typed = "-Toto", canonical = "Toto-TestRealm", elsewhere = "Toto-Ysondre" },
    { typed = "Toto-", canonical = "Toto-TestRealm", elsewhere = "Toto-Ysondre" },
    { typed = "Toto-Ysondre", canonical = "Toto-Ysondre", elsewhere = "Toto-TestRealm" },
}) do
    wipe(SanctuaryDB.manualWhitelist)
    ns.invalidateWhitelist()
    local before = ns.getListCounts().allowed.manual
    local added = ns.addAllowed(case.typed)
    if added then
        equal(ns.getListCounts().allowed.manual, before + 1,
            "\"" .. case.typed .. "\" makes one entry, and one only")
        equal(ns.classifyName(case.typed).verdict, "always_allowed",
            "which allows the character it was typed for")
        equal(ns.classifyName(case.canonical).verdict, "always_allowed",
            "as well as that character written out \"" .. case.canonical .. "\"")
        -- The half decision 119 added. A bare entry used to stand for the same
        -- pseudo on every realm at once, so a stranger who merely shares a name
        -- with somebody the person allowed walked in -- and a server transfer
        -- moved the whole allowed list onto the new realm behind their back.
        check(ns.classifyName(case.elsewhere).verdict ~= "always_allowed",
            "and nobody of that name on another realm (\"" .. case.elsewhere .. "\")")
    else
        equal(ns.getListCounts().allowed.manual, before,
            "\"" .. case.typed .. "\" was refused and wrote nothing")
    end
end

-- The whisper is the proof, not the panel.
wipe(SanctuaryDB.manualWhitelist)
ns.invalidateWhitelist()
equal(dispatchChatFilter("CHAT_MSG_WHISPER", "hi", "Toto-Ysondre"), true,
    "an unknown name's whisper is dropped in \"only people I know\"")
equal(select(1, ns.addAllowed("Toto Ysondre")), true,
    "the same name typed with a space is allowed")
equal(dispatchChatFilter("CHAT_MSG_WHISPER", "hi", "Toto-Ysondre"), false,
    "and her whisper arrives, exactly as WoW wrote it")

-- Nothing but separators is nobody on this side either.
for _, typed in ipairs({ "-", " - ", "--" }) do
    wipe(SanctuaryDB.manualWhitelist)
    ns.invalidateWhitelist()
    equal(select(1, ns.addAllowed(typed)), false,
        "\"" .. typed .. "\" is not a name and is refused here too")
    equal(ns.getListCounts().allowed.manual, 0, "leaving nothing behind")
end

-- And the documented way to allow a Battle.net account is untouched: the raw
-- entry feeds the account cache, whatever the key rule makes of it.
wipe(SanctuaryDB.manualWhitelist)
ns.invalidateWhitelist()
equal(select(1, ns.addAllowed("Manual Battle")), true,
    "an account display name is still accepted")
check(ns.isBNetWhitelisted("Manual Battle"), "and still reaches the account cache")
equal(select(1, ns.addAllowed("Real Friend#1234")), true, "tag included")
check(ns.isBNetWhitelisted("Real Friend#1234"),
    "which is how an account carrying a tag is allowed")
equal(ns.getListCounts().allowed.manual, 2, "two entries typed, two counted")

-- C2d bis -- an account is not a character, and the "#" is how we know: no WoW
-- pseudo carries one, on any realm. Keyed like a name it was cut at the first
-- space, so "Real Friend#1234" became "real" and every Real of every realm
-- walked in -- whisper, invite and verdict -- with nothing shown and nothing
-- heard. Not the realm-less over-allowance decision 82 accepted: the person
-- named an account, not a character.
equal(ns.classifyName("Real-Ysondre").verdict, "unknown",
    "a stranger sharing the first word of an allowed account stays unknown")
equal(ns.classifyName("Real-Hyjal").verdict, "unknown",
    "on his own realm as on any other")
equal(select(1, ns.getCharacterDecision("Real-Ysondre")), true,
    "the decision blocks him like the stranger he is")
equal(dispatchChatFilter("CHAT_MSG_WHISPER", "hi", "Real-Ysondre"), true,
    "his whisper is discarded")
-- Scoped: this file is one chunk and Lua counts live locals per function.
do
    local before = declinedGroups
    fire("PARTY_INVITE_REQUEST", "Real-Ysondre")
    runTimers(3)
    equal(declinedGroups, before + 1, "and his group invite is refused")
end
check(ns.isBNetWhitelisted("Real Friend#1234"),
    "while the account itself is still allowed on its own channel")
equal(ns.getListCounts().allowed.manual, 2, "and still counted on the tile")

-- Two accounts whose display names start with the same word are two accounts.
-- Cut to that word they shared one key: the second was refused as a duplicate,
-- silently, and only the first one ever got through.
wipe(SanctuaryDB.manualWhitelist)
ns.invalidateWhitelist()
equal(select(1, ns.addAllowed("Manual Battle#1111")), true, "one account is allowed")
equal(select(1, ns.addAllowed("Manual Buddy#5678")), true,
    "and so is another one sharing its first word")
equal(ns.getListCounts().allowed.manual, 2, "both are counted")
equal(dispatchChatFilter("CHAT_MSG_BN_WHISPER", "hello", "Manual Battle#1111"), false,
    "the first one's Battle.net whisper arrives")
equal(dispatchChatFilter("CHAT_MSG_BN_WHISPER", "hello", "Manual Buddy#5678"), false,
    "and so does the second one's")

-- A settings file written before the field could tell the two apart holds the
-- cut key with the tagged name beside it. The entry is read from the name, not
-- from the key, so the stranger it used to let in is shut out on load.
wipe(SanctuaryDB.manualWhitelist)
SanctuaryDB.manualWhitelist.real = { displayName = "Real Friend#1234", addedAt = 1 }
ns.invalidateWhitelist()
equal(ns.classifyName("Real-Ysondre").verdict, "unknown",
    "a legacy account entry allows no character either")
check(ns.isBNetWhitelisted("Real Friend#1234"),
    "and the account it names stays allowed")
equal(ns.getListCounts().allowed.manual, 1, "counted once, as the panel shows it")
wipe(SanctuaryDB.manualWhitelist)
ns.invalidateWhitelist()

-- C2d ter -- the realm, engraved at the write, on BOTH lists. Decision 119:
-- "mettre le royaume dans tous les cas meme si on met juste un pseudo -- imagine
-- la personne change de serveur, en interne on va re-rooter avec le nouveau
-- serveur, c'est pas bon". A key with no realm is not one entry: it is that
-- pseudo on every realm at once, so a stranger who merely shares a name with
-- somebody the person allowed walked in -- chat, invites, sounds and all -- and
-- the day the player transfers, the list they built for the realm they left
-- points at whoever bears those names on the new one.
resetModelState()

-- One shape, and every door writes it.
equal(select(2, ns.addAllowed("Kadaj")), "kadaj-testrealm",
    "the allowed field engraves the player's realm on a name typed without one")
equal(select(2, ns.addAllowed("Kadaj-Ysondre")), "kadaj-ysondre",
    "and honours the realm when one was typed")
equal(select(2, ns.addBlocked("Blokaj")), "blokaj-testrealm",
    "the blocked field does the same with no realm typed")
equal(select(2, ns.addBlocked("Blokaj-Ysondre")), "blokaj-ysondre",
    "and the same with one")
equal(ns.findAllowedKey("Kadaj"), "kadaj-testrealm",
    "and what the right-click menu looks up is that very key")
equal(ns.getListCounts().allowed.manual, 2,
    "two realms, two entries -- neither swallowed as a duplicate of the other")

-- Strict on both sides: an entry covers the character of ITS realm and nobody
-- else's. The allowed list is the half this changes; the blocked one has read
-- that way since 1.0.0 and must not regress.
equal(ns.classifyName("Kadaj").verdict, "always_allowed",
    "a bare name is the player's own realm, which is what an invite box shows")
equal(ns.classifyName("Kadaj-TestRealm").verdict, "always_allowed",
    "the same character written out in full")
equal(ns.classifyName("Kadaj-Ysondre").verdict, "always_allowed",
    "and the entry typed with its own realm answers for that one")
check(ns.classifyName("Kadaj-Hyjal").verdict ~= "always_allowed",
    "while a namesake on a third realm is allowed by neither")
equal(select(1, ns.getCharacterDecision("Kadaj-Hyjal")), true,
    "the decision treats him as the stranger he is")
equal(dispatchChatFilter("CHAT_MSG_WHISPER", "hi", "Kadaj-Hyjal"), true,
    "his whisper is discarded")
equal(dispatchChatFilter("CHAT_MSG_WHISPER", "hi", "Kadaj-Ysondre"), false,
    "while the allowed one's arrives, exactly as WoW wrote it")
equal(ns.classifyName("Blokaj-Ysondre").verdict, "always_blocked",
    "the blocked entry answers for its realm")
check(ns.classifyName("Blokaj-Hyjal").verdict ~= "always_blocked",
    "and for no other")

-- The transfer, which is the whole reason for the decision. The player's realm
-- is a constant of this harness, so the move is played from the other side --
-- the entries are engraved on Ysondre while the player stands on TestRealm --
-- which is the same displacement and the same code: entries written on a realm
-- the person is no longer on.
--
-- What must not happen is a key rebuilt from the display name while the caches
-- are refilled: the entry would land on the realm the player is on NOW and the
-- whole list would follow them across the transfer. The display names here are
-- deliberately bare, so anything re-deriving would have nothing but the current
-- realm to go on and the failure would be visible.
resetModelState()
SanctuaryDB.manualWhitelist["kadaj-ysondre"] = { displayName = "Kadaj", addedAt = 1 }
SanctuaryDB.blockedNames["blokaj-ysondre"] = { displayName = "Blokaj", addedAt = 1 }
ns.invalidateWhitelist()
equal(ns.classifyName("Kadaj-Ysondre").verdict, "always_allowed",
    "an entry goes on answering for the realm it was written on")
check(ns.classifyName("Kadaj-TestRealm").verdict ~= "always_allowed",
    "and does not follow the player onto the realm they are on now")
-- The bare name is the one that has to be asked, because the account cache is
-- the back door onto this decision: a manual CHARACTER entry feeds that cache
-- from its display name -- that is how a one-word account name typed in this
-- field lets its whispers through -- and a bare display name lands there under
-- a bare key. Read by `classifyName`, that key answered for "Kadaj" on every
-- realm, so the transfer this whole section is about was walked around while
-- the qualified lookups above stayed green.
equal(ns.classifyName("Kadaj").verdict, "unknown",
    "a bare name is not let in through the account cache either")
equal(select(1, ns.getCharacterDecision("Kadaj")), true,
    "so the decision keeps him out")
equal(dispatchChatFilter("CHAT_MSG_WHISPER", "hi", "Kadaj"), true,
    "and his WoW whisper is discarded, like the one written out in full")
equal(dispatchChatFilter("CHAT_MSG_WHISPER", "hi", "Kadaj-Ysondre"), false,
    "while the character the entry really names still gets through")
-- Nothing moved on either tile: the account entry a character entry produces was
-- never counted, and still is not.
equal(ns.getListCounts().allowed.manual, 1, "one typed entry, one counted")
equal(ns.getListCounts().allowed.bnet, 0, "and no Battle.net account invented")
equal(ns.getListCounts().blocked.total, 1, "the blocked tile is untouched")
equal(ns.classifyName("Blokaj-Ysondre").verdict, "always_blocked",
    "the blocked side is engraved the same way")
check(ns.classifyName("Blokaj-TestRealm").verdict ~= "always_blocked",
    "and does not follow the player either")
-- A rebuild is where a re-derivation would happen, so ask for several.
for _ = 1, 3 do
    ns.invalidateWhitelist()
    ns.ensureWhitelist()
end
check(ns.classifyName("Kadaj-TestRealm").verdict ~= "always_allowed",
    "and no number of rebuilds moves it")
equal(ns.classifyName("Kadaj-Ysondre").verdict, "always_allowed",
    "nor loses it")

-- Decision 104 on the qualified key, both ways round: moving a name from one
-- list to the other moves that character, and leaves his namesake alone.
resetModelState()
do
    equal(select(1, ns.addBlocked("Movaj-Ysondre")), true, "a harasser is blocked")
    equal(select(1, ns.addBlocked("Movaj")), true,
        "and a namesake on the player's own realm, separately")
    local ok, key, _, _, displaced = ns.addAllowed("Movaj-Ysondre")
    equal(ok, true, "allowing the first one works")
    equal(key, "movaj-ysondre", "under his own realm")
    check(type(displaced) == "table" and displaced.list == "blocked"
        and displaced.key == "movaj-ysondre",
        "and it says which entry it displaced")
    equal(SanctuaryDB.blockedNames["movaj-ysondre"], nil, "which is gone from the blocked list")
    check(SanctuaryDB.blockedNames["movaj-testrealm"] ~= nil,
        "while the namesake on the other realm stays blocked, untouched")
    -- Annuler puts the whole gesture back, both halves at once.
    ns.removeAllowed(key)
    ns.restoreBlocked(displaced.key, displaced.data)
    check(SanctuaryDB.blockedNames["movaj-ysondre"] ~= nil, "undo puts the block back")
    equal(SanctuaryDB.manualWhitelist["movaj-ysondre"], nil, "taking the allowance with it")
end

-- Automatic trust goes through the same door, so it engraves the realm too --
-- and what it writes is the group member, not whoever shares his pseudo at home.
resetModelState()
do
    SanctuaryDB.filters.autoTrust = true
    wipe(SanctuaryCharDB.groupTracker)
    inGroup = true
    groupMembers = { "Trustaj-Hyjal" }
    fire("GROUP_ROSTER_UPDATE")
    for trackedKey in pairs(SanctuaryCharDB.groupTracker) do
        SanctuaryCharDB.groupTracker[trackedKey] = now - 1000
    end
    runTickers()
    check(SanctuaryDB.manualWhitelist["trustaj-hyjal"] ~= nil,
        "five minutes in the group write the member under his own realm")
    equal(SanctuaryDB.manualWhitelist["trustaj-hyjal"].source, "trust",
        "recorded as automatic trust")
    ns.invalidateWhitelist()
    check(ns.classifyName("Trustaj-TestRealm").verdict ~= "always_allowed",
        "and his namesake on the player's realm gets nothing out of it")
    inGroup = false
    groupMembers = {}
    wipe(SanctuaryCharDB.groupTracker)
    ns.removeAllowed("trustaj-hyjal")
    ns.invalidateWhitelist()
end

-- What the panels and the tester put on screen. The realm is in the key, so it
-- belongs on the line: a chip reading "Kadaj" while the entry only covers
-- Kadaj-Ysondre tells the reader something the add-on does not do.
equal(ns.qualifiedDisplayName("kadaj-testrealm", "Kadaj"), "Kadaj-TestRealm",
    "a name typed bare is shown with the realm it was engraved on")
equal(ns.qualifiedDisplayName("kadaj-ysondre", "Kadaj-Ysondre"), "Kadaj-Ysondre",
    "a name typed with its realm is shown as it was typed")
equal(ns.qualifiedDisplayName("kadaj-ysondre", "Kadaj"), "Kadaj-Ysondre",
    "and an entry from another realm keeps that realm, not the player's")
equal(ns.qualifiedDisplayName("kadaj-azjolnerub", "Kadaj-Azjol-Nerub"), "Kadaj-Azjol-Nerub",
    "a hyphenated realm reads the way the player reads it in game")
equal(ns.qualifiedDisplayName("kadaj-hyjal", "Kadaj Hyjal"), "Kadaj-Hyjal",
    "a space typed instead of the hyphen reads as the hyphen it meant")
equal(ns.qualifiedDisplayName("real friend#1234", "Real Friend#1234"), "Real Friend#1234",
    "and an account is left alone: there is no realm to add to one")

-- The account half of the allowed list is untouched by all of this: a Battle.net
-- account is not on a realm at all, so it is keyed whole and shown whole.
resetModelState()
equal(select(2, ns.addAllowed("Real Friend#1234")), "real friend#1234",
    "an account is keyed whole, with no realm bolted on")
check(ns.isBNetWhitelisted("Real Friend#1234"), "and reaches the account cache")
equal(ns.classifyName("Real-Ysondre").verdict, "unknown",
    "while no character is allowed by it, on any realm")
equal(select(4, ns.addBlocked("Real Friend#1234")), "account",
    "and the blocked field still refuses one")
-- The tester answers on the tag, which is the only reader of the account half
-- left: a "#" names an account and nothing else, so it goes on answering.
do
    local tested = ns.describeAccessDecision("Real Friend#1234")
    equal(tested.verdict, "always_allowed", "the tester says the account is allowed")
    equal(tested.list, "manual", "as one the person typed")
    equal(tested.display, "Real Friend#1234", "and says it whole, with no realm added")
end
equal(ns.getListCounts().allowed.manual, 1, "one account typed, one counted")
equal(ns.getListCounts().allowed.bnet, 0, "and none of it lands on the friends tile")

-- The one-word account name, which is where the two readers of the account cache
-- part company. Typed into the allowed field it is indistinguishable from a
-- character, so it is stored as one -- realm engraved, decision 119 -- and its
-- display name feeds the account cache all the same.
--
--   * its Battle.net whisper passes, which is what the field is for;
--   * `classifyName` answers on the CHARACTER key alone, so the entry covers
--     the realm it was engraved on and no other -- no back door onto 119.
resetModelState()
equal(select(2, ns.addAllowed("Zephos")), "zephos-testrealm",
    "a one-word entry is a character entry, realm and all")
check(ns.isBNetWhitelisted("Zephos"),
    "and its display name still reaches the account cache")
equal(dispatchChatFilter("CHAT_MSG_BN_WHISPER", "hello", "Zephos"), false,
    "so the Battle.net whisper of a one-word account typed by hand still arrives")
equal(ns.classifyName("Zephos").verdict, "always_allowed",
    "the character it names is allowed on the player's own realm")
equal(ns.classifyName("Zephos").list, "manual", "as a typed entry, not as an account")
equal(ns.classifyName("Zephos-Ysondre").verdict, "unknown",
    "and his namesake on another realm is not")
equal(dispatchChatFilter("CHAT_MSG_WHISPER", "hi", "Zephos-Ysondre"), true,
    "whose WoW whisper is discarded")
equal(ns.getListCounts().allowed.manual, 1, "one entry typed, one counted")
equal(ns.getListCounts().allowed.bnet, 0, "and nothing added to the friends tile")

-- The same one word off the ROSTER is an account and answers as one: the friend
-- list is where an account name really is one, whatever it is spelled like.
resetModelState()
bnetFriends = { { bnetAccountID = 55, accountName = "Zephos" } }
ns.invalidateWhitelist()
equal(ns.classifyName("Zephos").verdict, "always_allowed",
    "a Battle.net friend whose account name is one word is allowed")
equal(ns.classifyName("Zephos").list, "bnet", "and named as the friend he is")
equal(dispatchChatFilter("CHAT_MSG_BN_WHISPER", "hello", "Zephos"), false,
    "his whisper arrives")
equal(ns.getListCounts().allowed.bnet, 1, "and he is counted once, on the friends tile")
equal(ns.getListCounts().allowed.manual, 0, "with nothing on the typed one")
resetModelState()

-- C2e -- the same invariant on the pattern list. A pattern is looked for in the
-- pseudo half alone, and a pseudo carries no hyphen: one holding a hyphen
-- matches nobody, ever. Stored, it showed in the panel, counted in the tile and
-- armed the guards while blocking no one. Refused, and not cut in two --
-- "Toto-Ysondre" cut down to "toto" would block every Toto of every realm.
resetModelState()
for _, typed in ipairs({ "Toto-Ysondre", "Azjol-Nerub", "-", " - " }) do
    equal(select(1, ns.addPattern(typed)), false,
        "the pattern \"" .. typed .. "\" matches nobody and is refused")
    equal(ns.getListCounts().blocked.patterns, 0, "so nothing is counted")
    equal(ns.hasAlwaysBlockedEntries(), false, "and no guard is armed")
end
-- The same dead entry wears other shapes, and the realistic one is the tag:
-- somebody pastes their harasser's BattleTag in the pattern field. A pseudo
-- carries no "#", no digit and no dot, so the pattern matches nobody -- while
-- the chip appears, the tile goes up and the guards arm themselves. Refused,
-- the field says no.
for _, typed in ipairs({ "toto#1234", "1234", "t.o", "Real Friend#1234" }) do
    equal(select(1, ns.addPattern(typed)), false,
        "the pattern \"" .. typed .. "\" names nobody a pseudo can be and is refused")
    equal(ns.getListCounts().blocked.patterns, 0, "so nothing is counted")
    equal(ns.hasAlwaysBlockedEntries(), false, "and no guard is armed")
end

-- The rule is ASCII punctuation and digits, not "letters we recognise": a
-- pattern written in another script is a pattern like any other.
equal(select(1, ns.addPattern("zoé")), true, "an accented pattern is accepted")
equal(ns.classifyName("Zoé-TestRealm").verdict, "always_blocked",
    "and blocks the name it is part of")
equal(select(1, ns.removePattern("zoé")), true, "and it can be removed again")

equal(select(1, ns.addPattern("illidan")), true, "a pattern with no separator is added")
equal(ns.getListCounts().blocked.patterns, 1, "and counted")
equal(ns.classifyName("Illidanx-TestRealm").verdict, "always_blocked",
    "and it still blocks a name whose pseudo contains it")
equal(ns.classifyName("Illidanx-TestRealm").list, "keyword", "as a pattern")

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
equal(select(1, ns.removeBlocked(ns.normalizeCharacterKey("Harasser"))), true,
    "the name is taken back out")
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

-- C9 -- Battle.net is out of Sanctuary's reach. The blocked list and the
-- patterns hold WoW characters and act on the WoW paths; the Battle.net channel
-- follows the Battle.net roster and nothing else. Cutting a Battle.net friend is
-- done in Battle.net.
resetModelState()
bnetFriends = {
    { accountName = "Real Friend#1234", bnetAccountID = 91,
      gameAccountInfo = { characterName = "Bnetchar", realmName = "Ysondre" } },
    { accountName = "Dash-Friend#5678", bnetAccountID = 92 },
}
ns.invalidateWhitelist()

-- Typing a BattleTag into the blocked field is refused outright: a tag names an
-- account, never a character, and the entry it used to make blocked nobody while
-- claiming the opposite in the panel.
do
    local before = ns.getListCounts().blocked.names
    equal(select(1, ns.addBlocked("Real Friend#1234")), false,
        "a Battle.net account name is refused by the blocked field")
    equal(ns.getListCounts().blocked.names, before, "writing nothing")
    equal(ns.hasAlwaysBlockedEntries(), false, "and arming nothing")
    equal(ns.classifyName("Real Friend#1234").verdict, "always_allowed",
        "the account stays what the Battle.net roster says it is")
    equal(ns.classifyName("Real Friend#1234").list, "bnet", "a Battle.net friend")
end

-- The entry a settings file from an earlier build can still carry, written the
-- way that build wrote it: the account is in the blocked list, and the whisper
-- still arrives.
SanctuaryDB.blockedNames["real-friend#1234"] =
    { displayName = "Real Friend#1234", addedAt = 0, source = "manual" }
ns.invalidateWhitelist()
equal(ns.hasAlwaysBlockedEntries(), true, "the inherited entry is there")
equal(dispatchChatFilter("CHAT_MSG_BN_WHISPER", "hi", "|Kq2|k", bnetWhisperPayload(91)), false,
    "a Battle.net friend whose account is in the blocked list still whispers")
equal(select(1, ns.removeBlocked(ns.normalizeCharacterKey("Real Friend#1234"))), true,
    "and the panel can still delete it")

-- Same for a pattern: it never reaches the Battle.net channel either.
SanctuaryDB.keywords = { "friend" }
ns.invalidateWhitelist()
equal(dispatchChatFilter("CHAT_MSG_BN_WHISPER", "hi", "|Kq2|k", bnetWhisperPayload(91)), false,
    "a pattern matching a Battle.net account name does not block the whisper")
equal(dispatchChatFilter("CHAT_MSG_BN_WHISPER", "hi", "|Kq2|k", bnetWhisperPayload(92)), false,
    "not even on an account name carrying a hyphen")
SanctuaryDB.keywords = {}
ns.invalidateWhitelist()

-- Blocking the CHARACTER a Battle.net friend plays is refused too, decision 100:
-- "on ne bloque pas un ami Battle.net, point". Only the tag used to be refused,
-- so the character went in without a word and the tester answered "toujours
-- bloque : dans vos bloques (meme si ami Battle.net)" -- a sentence that states
-- the rule and breaks it in the same breath.
do
    local ok, _, _, refusal = ns.addBlocked("Bnetchar-Ysondre", "menu")
    equal(ok, false, "the character a Battle.net friend plays cannot be blocked")
    equal(refusal, "account", "and is answered with the Battle.net sentence")
    equal(SanctuaryDB.blockedNames[ns.normalizeCharacterKey("Bnetchar-Ysondre")], nil,
        "and nothing is written")
    equal(ns.classifyName("Bnetchar-Ysondre").verdict, "always_allowed",
        "so the friend stays allowed")
end

-- That refusal is keyed on the realm, and a namesake on another one keeps a way
-- out. Asked on the bare pseudo, it answered for every realm at once: a harasser
-- who merely happens to be called like a friend's character could be blocked
-- nowhere -- not in the field, not from the right-click menu -- and read the
-- Battle.net sentence naming somebody he has never met. The residual same-name
-- cross-realm risk PROJECT_MEMORY records; the realm was the way out of it, and
-- closing that door left none.
do
    local ok, key, _, refusal = ns.addBlocked("Bnetchar-Hyjal")
    equal(ok, true, "a namesake of a friend's character, on another realm, is blockable")
    equal(refusal, nil, "with no Battle.net sentence in the way")
    equal(ns.classifyName("Bnetchar-Hyjal").verdict, "always_blocked",
        "and the entry does block him")
    equal(ns.classifyName("Bnetchar-Ysondre").verdict, "always_allowed",
        "while the friend, on his own realm, is untouched")
    equal(select(1, ns.removeBlocked(key)), true, "removed again")
    ns.invalidateWhitelist()
end

-- The friend the roster names without a realm: a bare pseudo is all it ever
-- gave, so the bare pseudo is what a refusal can honestly answer on -- the case
-- step 2 of the attribution lookup exists for.
--
-- And that map is asked about a bare name only. Restricting it to the realm-less
-- characters was half the rule; the other half is the question. Asked through
-- `normalizeName`, which throws away whatever realm the person typed, one such
-- friend made his namesake unblockable on every realm at once: the add-on
-- refused "Norealmchar-Hyjal" with the Battle.net sentence, naming somebody the
-- player has never met, and left no spelling that would take. That is the way
-- out the realm-qualified key exists to keep open, closed again one function
-- later.
do
    local savedFriends = bnetFriends
    bnetFriends = {
        { accountName = "No Realm#9999", bnetAccountID = 93,
          gameAccountInfo = { characterName = "Norealmchar" } },
    }
    ns.invalidateWhitelist()
    equal(select(4, ns.addBlocked("Norealmchar")), "account",
        "a friend the roster gave no realm for is refused on his bare pseudo")
    local ok, key, _, refusal = ns.addBlocked("Norealmchar-Hyjal")
    equal(ok, true, "while a realm typed after it names a character the roster never claimed")
    equal(refusal, nil, "so no Battle.net sentence stands in the way")
    equal(ns.classifyName("Norealmchar-Hyjal").verdict, "always_blocked",
        "and the entry does block him")
    equal(select(1, ns.removeBlocked(key)), true, "removed again")
    bnetFriends = savedFriends
    ns.invalidateWhitelist()
end

-- A settings file inherited from before that refusal still holds such an entry.
-- It goes on blocking the character it names -- the panel shows it and one click
-- removes it -- but the tester no longer credits the friendship in the same
-- sentence, which is the answer decision 100 called false.
SanctuaryDB.blockedNames[ns.normalizeCharacterKey("Bnetchar-Ysondre")] =
    { displayName = "Bnetchar-Ysondre", addedAt = 0, source = "manual" }
ns.invalidateWhitelist()
equal(select(1, ns.getCharacterDecision("Bnetchar-Ysondre")), true,
    "an inherited entry still blocks on the WoW paths")
equal(ns.describeAccessDecision("Bnetchar-Ysondre").overriddenList, nil,
    "and the tester no longer says 'blocked, even though Battle.net friend'")
equal(dispatchChatFilter("CHAT_MSG_BN_WHISPER", "hi", "|Kq2|k", bnetWhisperPayload(91)), false,
    "while his Battle.net whispers keep arriving")
ns.removeBlocked(ns.normalizeCharacterKey("Bnetchar-Ysondre"))

-- The account itself is answered as a Battle.net friend, and so is the character
-- it plays -- with the account named as the reason.
do
    local verdict = ns.classifyName("Bnetchar-Ysondre")
    equal(verdict.verdict, "always_allowed", "a friend's character is always allowed")
    equal(verdict.list, "bnet", "as a Battle.net friend")
    equal(verdict.detail, "Real Friend#1234", "credited to the account playing it")
end

-- The way out, and the only one: the contact leaves the Battle.net roster.
bnetFriends = {}
ns.invalidateWhitelist()
equal(dispatchChatFilter("CHAT_MSG_BN_WHISPER", "hi", "|Kq2|k", bnetWhisperPayload(91)), true,
    "removed in Battle.net, the same whisper is filtered as a stranger's")

-- The diagnostic reports what the filter does, not what the list says: no
-- always-blocked verdict can appear on this channel.
bnetFriends = {
    { accountName = "Real Friend#1234", bnetAccountID = 91,
      gameAccountInfo = { characterName = "Bnetchar", realmName = "Ysondre" } },
}
SanctuaryDB.keywords = { "friend" }
-- Inherited entry again: the field refuses the tag now, and the diagnostic has
-- to answer for the settings files that already hold one.
SanctuaryDB.blockedNames["real-friend#1234"] =
    { displayName = "Real Friend#1234", addedAt = 0, source = "manual" }
ns.invalidateWhitelist()
do
    local diag = ns.simulateBNetWhisper("Real Friend#1234")
    equal(diag.shouldBlock, false, "the Battle.net diagnostic passes the blocked-and-patterned friend")
    equal(diag.reason, "bnet_whitelist", "for the one reason this channel knows")
    equal(diag.keyword, nil, "and never names a pattern")
end
ns.removeBlocked(ns.normalizeCharacterKey("Real Friend#1234"))
SanctuaryDB.keywords = {}

-- C9b -- two Battle.net friends, two realms, one character name. Nothing is
-- blocked here: what the namesakes decide is the ATTRIBUTION the tester prints.
-- Keyed on the bare name alone, the second friend read overwrote the first and
-- one account answered for both. Played in both roster orders, because the
-- roster order is exactly what decided it.
for _, order in ipairs({ { "Ysondre", "Hyjal" }, { "Hyjal", "Ysondre" } }) do
    resetModelState()
    local firstIsOne = order[1] == "Ysondre"
    bnetFriends = {
        { accountName = firstIsOne and "Twin One#1111" or "Twin Two#2222",
          bnetAccountID = firstIsOne and 94 or 95,
          gameAccountInfo = { characterName = "Twin", realmName = order[1] } },
        { accountName = firstIsOne and "Twin Two#2222" or "Twin One#1111",
          bnetAccountID = firstIsOne and 95 or 94,
          gameAccountInfo = { characterName = "Twin", realmName = order[2] } },
    }
    ns.invalidateWhitelist()

    local ysondre = ns.classifyName("Twin-Ysondre")
    local hyjal = ns.classifyName("Twin-Hyjal")
    equal(ysondre.verdict, "always_allowed", "both namesakes are always allowed")
    equal(hyjal.verdict, "always_allowed", "whichever friend was read first")
    equal(ysondre.detail, "Twin One#1111", "and each is credited to his own account")
    equal(hyjal.detail, "Twin Two#2222", "never to the other one's")
end

-- C9c -- adding somebody to "Toujours autorises" may never be what takes them
-- off it. The WoW paths know a Battle.net friend by the bare pseudo his roster
-- hands over; that roster names his realm on the side, so the same pseudo typed
-- into the allowed field is keyed on the PLAYER's realm -- somebody else
-- entirely as soon as the friend plays elsewhere. Deduplicating the two dropped
-- the roster entry, the only one the WoW channel ever had for him: his whisper
-- was discarded and his invitation and duel refused with no popup, no sound and
-- no system line, while the Battle.net group went on showing him allowed.
-- Silently cutting an allowed player is the side of the error the product
-- forbids, and here it was the act of allowing him that did it.
resetModelState()
bnetFriends = {
    { accountName = "RealFriend#1234", bnetAccountID = 96,
      gameAccountInfo = { characterName = "Bnetchar", realmName = "Hyjal" } },
}
ns.invalidateWhitelist()
-- Scoped: this file is one chunk and Lua counts live locals per function.
do
    equal(ns.classifyName("Bnetchar-Hyjal").verdict, "always_allowed",
        "a Battle.net friend playing on another realm is allowed")
    equal(select(2, ns.addAllowed("Bnetchar")), "bnetchar-testrealm",
        "and his pseudo, typed by hand, is keyed on the realm the player is on")
    equal(ns.classifyName("Bnetchar-Hyjal").verdict, "always_allowed",
        "which leaves the friend allowed, not unknown")
    equal(select(1, ns.getCharacterDecision("Bnetchar-Hyjal")), false,
        "the decision does not block him")
    equal((ns.decideChat("whisper", "Bnetchar-Hyjal")), false,
        "his whisper is not discarded")
    equal(dispatchChatFilter("CHAT_MSG_WHISPER", "hi", "Bnetchar-Hyjal"), false,
        "and it arrives through the registered filter too")

    local beforeDeclines, beforeDuels = declinedGroups, cancelledDuels
    fire("PARTY_INVITE_REQUEST", "Bnetchar-Hyjal")
    runTimers(3)
    equal(declinedGroups, beforeDeclines, "his group invitation is left to WoW")
    fire("DUEL_REQUESTED", "Bnetchar-Hyjal")
    runTimers(3)
    equal(cancelledDuels, beforeDuels, "and so is his duel")

    equal(select(1, ns.removeAllowed("bnetchar-testrealm")), true,
        "while the entry the person typed is still theirs to delete")
end

-- Same friend, roster giving no realm at all: the bare pseudo is everything
-- anyone has for him, so it is the entry that must survive the typing.
resetModelState()
bnetFriends = {
    { accountName = "NoRealm#9999", bnetAccountID = 97,
      gameAccountInfo = { characterName = "Namelesschar" } },
}
ns.invalidateWhitelist()
do
    equal(ns.classifyName("Namelesschar-Hyjal").verdict, "always_allowed",
        "a friend the roster gave no realm for is allowed wherever he is seen")
    equal(select(1, ns.addAllowed("Namelesschar")), true,
        "his pseudo is typed into the allowed field as well")
    equal(ns.classifyName("Namelesschar-Hyjal").verdict, "always_allowed",
        "and he stays allowed")
    equal(select(1, ns.getCharacterDecision("Namelesschar-Hyjal")), false,
        "with nothing blocked on the WoW paths")
    equal((ns.decideChat("whisper", "Namelesschar-Hyjal")), false,
        "and his whisper arriving")
end

-- The deduplication itself stays where it is true. A guild is read from inside
-- it, so a mate the roster names bare is on the player's own realm and the two
-- keys really do name one person: one line, one count, under the label the
-- person gave.
resetModelState()
guildMembers = { "Guildtwin-TestRealm" }
inGuild = true
ns.invalidateWhitelist()
do
    equal(ns.getListCounts().allowed.total, 1, "the guild mate counts once on his own")
    equal(select(1, ns.addAllowed("Guildtwin")), true, "then the person types him in too")
    local counts = ns.getListCounts()
    equal(counts.allowed.total, 1, "and the tile still counts him once")
    equal(counts.allowed.manual, 1, "as the entry they made")
    equal(counts.allowed.guild, 0, "and not a second time as a guild mate")
    local guildGroup
    for _, group in ipairs(ns.getAutoWhitelistGroups()) do
        if group.source == "guild" then guildGroup = group end
    end
    equal(guildGroup and guildGroup.total, 0,
        "the automatic guild group has no second line for him")
    equal(ns.classifyName("Guildtwin-TestRealm").list, "manual",
        "and he is credited to the list the person can act on")
end
inGuild = false

-- And decision 119 is untouched by any of it: a namesake on another realm, in
-- nobody's roster, is not the person who was typed in.
resetModelState()
do
    equal(select(2, ns.addAllowed("Typedonly")), "typedonly-testrealm",
        "a name typed with no realm means the realm the player is on")
    equal(ns.classifyName("Typedonly-TestRealm").verdict, "always_allowed",
        "so the character it names is allowed")
    equal(ns.classifyName("Typedonly-Ysondre").verdict, "unknown",
        "and his namesake on another realm stays a stranger")
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
equal(select(1, ns.addAllowed("toto-ysondre")), false, "and a duplicate is a no-op")
-- The same pseudo on the player's own realm is a different character, and gets
-- its own entry rather than being swallowed as a duplicate (decision 119).
equal(select(1, ns.addAllowed("toto")), true,
    "while the same pseudo on the player's own realm is another entry")
equal(select(1, ns.removeAllowed("toto-testrealm")), true, "removable on its own key")
local removedOk, removedKey, removedData = ns.removeAllowed("toto-ysondre")
equal(removedOk, true, "removing gives the data back")
check(type(removedData) == "table" and removedData.displayName == "Toto-Ysondre",
    "with the name exactly as it was typed")
ns.restoreAllowed(removedKey, removedData)
equal(SanctuaryDB.manualWhitelist["toto-ysondre"].displayName, "Toto-Ysondre",
    "and restoring puts back the same record, date included")
-- The two lists are exclusive, decision 104. Blocking a name takes it out of the
-- allowed list and hands the entry back, so the whole gesture can be undone at
-- once; undoing one half alone would put the two lists back into the state the
-- rule exists to end.
do
    local blockOk, blockKey, _, _, displaced = ns.addBlocked("Toto-Ysondre")
    equal(blockOk, true, "the same name can be blocked instead")
    equal(SanctuaryDB.manualWhitelist["toto-ysondre"], nil, "which takes it out of the allowed list")
    check(type(displaced) == "table" and displaced.list == "allowed",
        "and says which list it came out of")
    check(type(displaced.data) == "table" and displaced.data.displayName == "Toto-Ysondre",
        "handing back the record as it was, date included")
    equal(select(1, ns.getCharacterDecision("Toto-Ysondre")), true, "the decision blocks them")

    -- And the other way round: allowing a blocked name takes it out of the
    -- blocked list, guards and invite sound refreshed with it.
    local allowOk, _, _, _, displacedBack = ns.addAllowed("Toto-Ysondre")
    equal(allowOk, true, "allowing it again works")
    equal(SanctuaryDB.blockedNames[blockKey], nil, "and takes it out of the blocked list")
    check(type(displacedBack) == "table" and displacedBack.list == "blocked",
        "saying which list it came out of")
    equal(ns.hasAlwaysBlockedEntries(), false, "the blocked list is empty again")
    equal(select(1, ns.getCharacterDecision("Toto-Ysondre")), false, "and the decision follows")
end
ns.removeAllowed("toto-ysondre")
ns.restoreAllowed(removedKey, removedData)
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
local oldWhitelist = { oldfriend = { displayName = "Oldfriend", addedAt = 42 } }
local oldKeywords = { "oldpattern" }
SanctuaryDB = {
    schemaVersion = 1,
    filters = { groupInvite = false, whisper = false, say = true, channelMode = "all",
        autoTrust = true, strictGroupInviteSystemMessages = true },
    notifications = { mode = "verbose", minimalIntervalMinutes = 5 },
    logging = { enabled = false, maxEntries = 250, rotation = "deleteOldest" },
    manualWhitelist = oldWhitelist,
    keywords = oldKeywords,
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
-- The lists go back to empty with the settings. Keeping them meant converting
-- them -- the blocked list is keyed by realm in 1.0.0 and was not before -- and
-- a conversion is one more guess about what someone meant. She is told, and she
-- types them again once.
equal(next(SanctuaryDB.manualWhitelist), nil, "the names added by hand go too")
equal(#SanctuaryDB.keywords, 0, "and the patterns")
equal(next(SanctuaryCharDB.manualWhitelist), nil, "and the per-character list")
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
-- 1.0.0 stamps the account file and every other character still logs in with a
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
equal(next(SanctuaryCharDB.manualWhitelist), nil, "its own list of names goes with them")
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
-- left behind -- and the first load of 1.0.0 always goes through the reset. The
-- real path: a 0.3.2 session with a sound guard up at /reload, then 1.0.0
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

-- C18 -- the anti-spam setting, and the one question the interface asks.
do

resetModelState()
equal(ns.ACCOUNT_DEFAULTS.antiSpam.enabled, false, "anti-spam is off on a fresh settings file")
equal(ns.ACCOUNT_DEFAULTS.antiSpam.intervalSeconds, 300, "and its window is five minutes")

-- A 1.0.0 file written before this block existed: the schema is already 2, so
-- ADDON_LOADED completes it rather than rebuilding it, and everything else in
-- it survives.
SanctuaryDB.antiSpam = nil
SanctuaryDB.logging.maxEntries = 1234
SanctuaryDB.filters.scope = "blockedOnly"
fire("ADDON_LOADED", "Sanctuary")
equal(type(SanctuaryDB.antiSpam), "table", "an existing 1.0.0 file gets the block it lacks")
equal(SanctuaryDB.antiSpam.enabled, false, "off, like a fresh one")
equal(SanctuaryDB.antiSpam.intervalSeconds, 300, "with the same window")
equal(SanctuaryDB.logging.maxEntries, 1234, "and nothing else in the file is touched")
equal(SanctuaryDB.filters.scope, "blockedOnly", "including the answer to question 1")
SanctuaryDB.logging.maxEntries = 5000
SanctuaryDB.filters.scope = "strangers"

ns.resetToSchemaV2()
equal(SanctuaryDB.antiSpam.enabled, false, "the 1.0.0 reset rebuilds it off")
equal(SanctuaryDB.antiSpam.intervalSeconds, 300, "at five minutes")
fire("ADDON_LOADED", "Sanctuary")

-- Reading. Eight values are accepted and nothing else is.
for _, seconds in ipairs({ 300, 600, 1800, 3600, 7200, 14400, 43200, 86400 }) do
    SanctuaryDB.antiSpam.intervalSeconds = seconds
    equal(ns.getAntiSpamInterval(), seconds, "the window " .. seconds .. " is read back")
end
for _, bad in ipairs({ 7, 0, -300, 240, 90000 }) do
    SanctuaryDB.antiSpam.intervalSeconds = bad
    equal(ns.getAntiSpamInterval(), 300, "a stored " .. bad .. " answers the default")
end
SanctuaryDB.antiSpam.intervalSeconds = "5"
equal(ns.getAntiSpamInterval(), 300, "a stored string answers the default")
SanctuaryDB.antiSpam.intervalSeconds = nil
equal(ns.getAntiSpamInterval(), 300, "and so does no value at all")
SanctuaryDB.antiSpam = nil
equal(ns.getAntiSpamInterval(), 300, "and so does no block at all")
equal(ns.isAntiSpamEnabled(), false, "which reads as off")
SanctuaryDB.antiSpam = { enabled = false, intervalSeconds = 300 }

-- Writing goes through the same eight.
ns.setAntiSpamInterval(3600)
equal(SanctuaryDB.antiSpam.intervalSeconds, 3600, "a listed window is written")
ns.setAntiSpamInterval(45)
equal(SanctuaryDB.antiSpam.intervalSeconds, 3600, "an unlisted one is refused, not stored")
ns.setAntiSpamInterval(300)
ns.setAntiSpamEnabled(true)
equal(ns.isAntiSpamEnabled(), true, "the switch is written")
ns.setAntiSpamEnabled(false)
equal(ns.isAntiSpamEnabled(), false, "and unwritten")

-- The coverage predicate. "Already covered" means the channels are all filtered
-- for real, which is a question about the mode the core applies -- not about
-- what is stored under it.
local COVERAGE = {
    { scope = "strangers",  preset = "custom", channelMode = "all",      covered = true },
    { scope = "strangers",  preset = "custom", channelMode = "keywords", covered = false },
    { scope = "strangers",  preset = "custom", channelMode = "none",     covered = false },
    { scope = "strangers",  preset = "all",    channelMode = "all",      covered = false },
    { scope = "blockedOnly", preset = "custom", channelMode = "all",     covered = false },
    { scope = "blockedOnly", preset = "all",   channelMode = "all",      covered = false },
}
for _, case in ipairs(COVERAGE) do
    SanctuaryDB.filters.scope = case.scope
    SanctuaryDB.filters.preset = case.preset
    SanctuaryDB.filters.channelMode = case.channelMode
    equal(ns.isChannelSpamCovered(), case.covered,
        "channel coverage for " .. case.scope .. "+" .. case.preset .. "+" .. case.channelMode)
    -- Switched off, nothing is filtered at all, so nothing is covered either --
    -- whatever "Filter everything" is still remembering.
    SanctuaryCharDB.overrides.enabled = false
    equal(ns.isChannelSpamCovered(), false,
        "and nothing is covered while Sanctuary is off (" .. case.channelMode .. ")")
    SanctuaryCharDB.overrides.enabled = nil
end

-- The snapshot publishes it, so a report answers "was the anti-spam on".
resetModelState()
SanctuaryDB.antiSpam.enabled = true
SanctuaryDB.antiSpam.intervalSeconds = 1800
SanctuaryDB.filters.channelMode = "all"
SanctuaryDB.debugEnabled = true
ns.resetDebugLog()
ns.captureDebugSnapshot("test")
local antiSpamSnapshot = lastDebug("SNAPSHOT")
equal(antiSpamSnapshot and antiSpamSnapshot.data.antiSpam, true, "the snapshot publishes the switch")
equal(antiSpamSnapshot and antiSpamSnapshot.data.antiSpamInterval, 1800, "and the window")
equal(antiSpamSnapshot and antiSpamSnapshot.data.channelSpamCovered, true, "and whether it has anything left to do")
SanctuaryDB.debugEnabled = false
ns.resetDebugLog()
resetModelState()
SanctuaryDB.antiSpam.enabled = false
SanctuaryDB.antiSpam.intervalSeconds = 300

end

-- C19 -- the anti-spam of the public channels: one verdict per message.
do

local SPAMMER = "Spammer-TestRealm"
local ORDERS = { "filters_first", "handler_first", "handler_between" }

local channelRow
for _, row in ipairs(ns.CHAT_KINDS) do
    if row.kind == "channel" then channelRow = row end
end
check(channelRow ~= nil, "the channel row of the generated table is reachable")

-- The throttle lives in memory for the whole session, so every case gets a
-- message of its own rather than a clock jump: two cases can then never lean on
-- each other's records.
local caseIndex, lineIndex = 0, 0
local function freshMessage()
    caseIndex = caseIndex + 1
    return "WTS carry run " .. caseIndex
end
local function nextLine()
    lineIndex = lineIndex + 1
    return 700000 + lineIndex
end

local function armAntiSpam(seconds)
    resetModelState()
    SanctuaryDB.antiSpam.enabled = true
    SanctuaryDB.antiSpam.intervalSeconds = seconds or 300
end

local function countDebug(cat)
    local count = 0
    for _, entry in ipairs(SanctuaryDB.debugLog or {}) do
        if entry.cat == cat then count = count + 1 end
    end
    return count
end

-- Answers "was this copy hidden", and fails loudly if the chat windows were not
-- all told the same thing.
local function deliverCopy(order, message, sender, lineID, label)
    local verdicts = deliverChatMessage(order, 3, "CHAT_MSG_CHANNEL",
        channelPayload(message, sender, lineID))
    equal(#verdicts, 3, "three chat windows asked about " .. label)
    for index = 2, #verdicts do
        equal(verdicts[index], verdicts[1],
            "and window " .. index .. " was told the same as the first for " .. label)
    end
    return verdicts[1]
end

-- The three orders, and the same answer in each of them.
for _, order in ipairs(ORDERS) do
    armAntiSpam(300)
    local message = freshMessage()
    equal(deliverCopy(order, message, SPAMMER, nextLine(), "the first copy (" .. order .. ")"),
        false, "the first copy is shown (" .. order .. ")")
    now = now + 10
    equal(deliverCopy(order, message, SPAMMER, nextLine(), "the repeat (" .. order .. ")"),
        true, "and the repeat is hidden (" .. order .. ")")
end

-- One message, one commit: three chat windows and a handler leave exactly one
-- debug entry and one Journal line behind.
for _, order in ipairs(ORDERS) do
    armAntiSpam(300)
    SanctuaryDB.debugEnabled = true
    local message = freshMessage()
    deliverCopy(order, message, SPAMMER, nextLine(), "the shown copy")
    now = now + 10
    ns.resetDebugLog()
    local journalBefore = #SanctuaryDB.log
    deliverCopy(order, message, SPAMMER, nextLine(), "the hidden copy")
    equal(countDebug("MASK_SPAM_REPEAT"), 1,
        "one hidden repeat leaves one debug entry (" .. order .. ")")
    equal(#SanctuaryDB.log - journalBefore, 1,
        "and one Journal line (" .. order .. ")")
    SanctuaryDB.debugEnabled = false
end

-- The debug entry says what a real recording will be read for.
do
    armAntiSpam(1800)
    SanctuaryDB.debugEnabled = true
    local message = freshMessage()
    deliverCopy("filters_first", message, SPAMMER, nextLine(), "the shown copy")
    now = now + 10
    ns.resetDebugLog()
    deliverCopy("filters_first", message, SPAMMER, nextLine(), "the hidden copy")
    local entry = lastDebug("MASK_SPAM_REPEAT")
    check(entry ~= nil, "a hidden repeat is recorded")
    equal(entry and entry.data.lineIDKnown, true, "with whether the client handed a lineID over")
    equal(entry and entry.data.intervalSeconds, 1800, "the window in force")
    equal(entry and entry.data.channelMode, "none", "and what the channels are set to")
    -- And with no lineID, the recording says so rather than staying silent.
    armAntiSpam(300)
    local bare = freshMessage()
    deliverChatMessage("filters_first", 3, "CHAT_MSG_CHANNEL", bare, SPAMMER)
    now = now + 10
    ns.resetDebugLog()
    deliverChatMessage("filters_first", 3, "CHAT_MSG_CHANNEL", bare, SPAMMER)
    local bareEntry = lastDebug("MASK_SPAM_REPEAT")
    check(bareEntry ~= nil, "a message with no lineID is still throttled")
    equal(bareEntry and bareEntry.data.lineIDKnown, false, "and the recording says the lineID was missing")
    SanctuaryDB.debugEnabled = false
end

-- The eight windows, and the fact that the window is fixed rather than sliding:
-- a hidden repeat does not push the reappearance back.
for _, seconds in ipairs(ns.ANTISPAM_INTERVALS) do
    armAntiSpam(seconds)
    local message = freshMessage()
    equal(deliverCopy("filters_first", message, SPAMMER, nextLine(), "the first copy"), false,
        "the first copy is shown at " .. seconds .. "s")
    now = now + seconds - 1
    equal(deliverCopy("filters_first", message, SPAMMER, nextLine(), "a repeat inside the window"), true,
        "a repeat one second short of " .. seconds .. "s is hidden")
    now = now + 2
    equal(deliverCopy("filters_first", message, SPAMMER, nextLine(), "a repeat past the window"), false,
        "and it comes back one second past " .. seconds .. "s, counted from the copy that was shown")
end

-- What is the same message, and what is not.
do
    local SAME = {
        { text = "  WTS   carry   run  ", what = "blanks around it and inside it" },
    }
    for _, case in ipairs(SAME) do
        armAntiSpam(300)
        deliverCopy("filters_first", "WTS carry run", SPAMMER, nextLine(), "the first copy")
        now = now + 10
        equal(deliverCopy("filters_first", case.text, SPAMMER, nextLine(), "the variant"), true,
            "a repeat with " .. case.what .. " is the same message")
    end

    local DIFFERENT = {
        { text = "WTS CARRY RUN", sender = SPAMMER, what = "another case" },
        { text = "WTS carry run!", sender = SPAMMER, what = "one more character" },
        { text = "WTS carry run", sender = "Otherguy-TestRealm", what = "another pseudo" },
        { text = "WTS carry run", sender = "Spammer-Ysondre", what = "the same pseudo on another realm" },
    }
    for _, case in ipairs(DIFFERENT) do
        armAntiSpam(300)
        deliverCopy("filters_first", "WTS carry run", SPAMMER, nextLine(), "the first copy")
        now = now + 10
        equal(deliverCopy("filters_first", case.text, case.sender, nextLine(), "the variant"), false,
            "a line with " .. case.what .. " is another message")
    end
end

-- Nobody who is allowed is ever touched: an allowed person keeps the native
-- behaviour of WoW, repeats included.
do
    local EXEMPT = {
        { what = "a guild mate", name = "Guildie-TestRealm",
          arm = function() guildMembers = { "Guildie-TestRealm" } inGuild = true end },
        { what = "somebody in the group", name = "Teammate-TestRealm",
          arm = function() groupMembers = { "Teammate-TestRealm" } inGroup = true end },
        { what = "somebody in the raid", name = "Raider-TestRealm",
          arm = function() groupMembers = { "Raider-TestRealm" } inGroup = true inRaid = true end },
        { what = "a Battle.net friend", name = "Bnetpal-TestRealm",
          arm = function()
              bnetFriends = { { bnetAccountID = 777, accountName = "Pal#1234",
                  gameAccountInfo = { characterName = "Bnetpal", realmName = "TestRealm",
                      clientProgram = "WoW", isOnline = true } } }
          end },
        { what = "a name added by hand", name = "Byhand-TestRealm",
          arm = function() ns.addAllowed("Byhand") end },
        { what = "somebody trusted automatically", name = "Trustee-TestRealm",
          arm = function() ns.addAllowed("Trustee", "trust") end },
    }
    for _, case in ipairs(EXEMPT) do
        armAntiSpam(300)
        case.arm()
        ns.invalidateWhitelist()
        local message = freshMessage()
        equal(deliverCopy("filters_first", message, case.name, nextLine(), "the first copy"), false,
            "the first line from " .. case.what .. " is shown")
        now = now + 10
        equal(deliverCopy("filters_first", message, case.name, nextLine(), "the repeat"), false,
            "and so is the repeat from " .. case.what)
    end
    resetModelState()
end

-- The player talking to themselves is never reached at all: the decision stops
-- at "self", before anything about spam is asked.
do
    armAntiSpam(300)
    local message = freshMessage()
    equal(deliverCopy("filters_first", message, "Victim-TestRealm", nextLine(), "the player's own line"), false,
        "the player's own line is shown")
    now = now + 10
    equal(deliverCopy("filters_first", message, "Victim-TestRealm", nextLine(), "its repeat"), false,
        "and so is its repeat")
end

-- Switched off, either of the two ways, nothing happens.
do
    armAntiSpam(300)
    SanctuaryCharDB.overrides.enabled = false
    local message = freshMessage()
    equal(deliverCopy("filters_first", message, SPAMMER, nextLine(), "the first copy"), false,
        "with Sanctuary off the first copy is shown")
    now = now + 10
    equal(deliverCopy("filters_first", message, SPAMMER, nextLine(), "the repeat"), false,
        "and so is the repeat")
    SanctuaryCharDB.overrides.enabled = nil

    armAntiSpam(300)
    SanctuaryDB.antiSpam.enabled = false
    message = freshMessage()
    equal(deliverCopy("filters_first", message, SPAMMER, nextLine(), "the first copy"), false,
        "with the anti-spam off the first copy is shown")
    now = now + 10
    equal(deliverCopy("filters_first", message, SPAMMER, nextLine(), "the repeat"), false,
        "and so is the repeat")
end

-- Already covered: the channels are all filtered, so a stranger's line is
-- blocked as a stranger's line and never as a repeat.
do
    armAntiSpam(300)
    SanctuaryDB.filters.channelMode = "all"
    SanctuaryDB.debugEnabled = true
    local message = freshMessage()
    equal(deliverCopy("filters_first", message, SPAMMER, nextLine(), "the first copy"), true,
        "with the channels all filtered the first copy is blocked")
    now = now + 10
    ns.resetDebugLog()
    equal(deliverCopy("filters_first", message, SPAMMER, nextLine(), "the repeat"), true,
        "and so is the repeat")
    equal(countDebug("MASK_SPAM_REPEAT"), 0, "and nothing is recorded as a hidden repeat")
    local entry = lastDebug("CHAT_DECISION")
    equal(entry and entry.data.action, "BLOCK_NOT_WHITELISTED",
        "the repeat is recorded for what it is")
    SanctuaryDB.debugEnabled = false
end

-- The filter answers one value and one only: Blizzard's registry reads a second
-- one as a replacement for the message text.
do
    armAntiSpam(300)
    equal(select("#", channelRow.filter(nil, "CHAT_MSG_CHANNEL",
        channelPayload(freshMessage(), SPAMMER, nextLine()))), 1,
        "the channel filter answers exactly one value")
end

-- The two counter-proofs. Neither needs the interface, and each fails on its own
-- if the shape below is broken.
do
    -- The memo is keyed on the physical message. Keyed on pseudo and text
    -- instead, the second physical message would be handed the first one's
    -- verdict and shown -- which is the defect the whole chantier is about.
    armAntiSpam(300)
    local message = freshMessage()
    local first = ns.resolveChatDecision(channelRow, message, SPAMMER, 990001)
    equal(first.spam, "show", "the first physical message is shown")
    ns.commitChatDecision(first)
    local second = ns.resolveChatDecision(channelRow, message, SPAMMER, 990002)
    equal(second.spam, "masked",
        "a second physical message with the same text is a repeat, not the same message again")

    -- Resolving is pure. Were the throttle moved there instead of at the commit,
    -- the second resolve below would answer "masked" and a chat window that
    -- asked after the handler would hide a line the other windows had shown.
    armAntiSpam(300)
    message = freshMessage()
    local a = ns.resolveChatDecision(channelRow, message, SPAMMER, 990011)
    local b = ns.resolveChatDecision(channelRow, message, SPAMMER, 990012)
    equal(a.spam, "show", "resolving answers shown")
    equal(b.spam, "show", "and resolving again, uncommitted, answers shown too")
    ns.commitChatDecision(a)
    equal(ns.resolveChatDecision(channelRow, message, SPAMMER, 990013).spam, "masked",
        "the commit is the only thing that moves the throttle")

    -- And committing twice is committing once.
    armAntiSpam(300)
    SanctuaryDB.debugEnabled = true
    message = freshMessage()
    local shown = ns.resolveChatDecision(channelRow, message, SPAMMER, 990021)
    ns.commitChatDecision(shown)
    now = now + 10
    ns.resetDebugLog()
    local hidden = ns.resolveChatDecision(channelRow, message, SPAMMER, 990022)
    local journalBefore = #SanctuaryDB.log
    ns.commitChatDecision(hidden)
    ns.commitChatDecision(hidden)
    ns.commitChatDecision(hidden)
    equal(countDebug("MASK_SPAM_REPEAT"), 1, "committing a decision three times records it once")
    equal(#SanctuaryDB.log - journalBefore, 1, "and journals it once")
    SanctuaryDB.debugEnabled = false
end

-- The Diagnostics button. It exists because a solo session cannot ask a
-- stranger to repeat themselves in the Trade channel, and it is only worth
-- anything if it takes the real path: the registered filter, then the event
-- handler, three physical messages.
do
    armAntiSpam(300)
    SanctuaryDB.debugEnabled = true
    ns.resetDebugLog()
    local result = ns.runChannelSpamDiagnostic("SanctuaryTest")
    equal(result.available, true, "the channel path the probe needs is reachable")
    equal(result.shown, 1, "the first copy shows")
    equal(result.hidden, 2, "and the two repeats are hidden")
    equal(result.journalled, 1, "leaving one Journal entry behind")
    equal(countDebug("MASK_SPAM_REPEAT"), 2, "with two hidden-repeat recordings")
    local entry = SanctuaryDB.log[#SanctuaryDB.log]
    equal(entry.type, "channel", "the entry is a channel one")
    equal(entry.count, 3, "counting the three times the line arrived")
    check(ns.getLogEntryDisplayType(entry)
        :find(string.format(ns.L["LOGS_SPAM_BADGE"], 3), 1, true) ~= nil,
        "and it reads on screen as a folded one")
    check(ns.formatChannelSpamDiagnosticResult(result):find("hidden=2", 1, true) ~= nil,
        "the line the panel shows says how many were hidden")

    armAntiSpam(300)
    SanctuaryDB.antiSpam.enabled = false
    local off = ns.runChannelSpamDiagnostic("")
    equal(off.shown, 3, "with the anti-spam off the three copies show")
    equal(off.hidden, 0, "none of them is hidden")
    equal(off.journalled, 0, "and nothing is journalled")
    equal(off.name, "SanctuaryTest", "an empty field falls back to the test pseudo")
    SanctuaryDB.debugEnabled = false
end

-- And the button is only worth clicking if the line reaches the chat. The
-- filter is called outside the dispatch that owns the ChatFrames, so nothing
-- but the diagnostic itself can write the copies it keeps -- which is exactly
-- what "one line appears in the chat" is checked against here, in the three
-- states the button can be clicked in.
do
    local probeText = ns.L["DIAG_SPAM_PROBE_MSG"]
    local function countProbeLines(from)
        local count = 0
        for index = from + 1, #chatMessages do
            local line = chatMessages[index]
            if type(line) == "string" and line:find(probeText, 1, true) then
                count = count + 1
            end
        end
        return count
    end

    -- Anti-spam on: one copy shown, one line written, two repeats that write
    -- nothing at all -- and no block counted for them. The throttle outlives
    -- `resetModelState`, and the block above has just shown this very line, so
    -- the clock is walked past the window first.
    now = now + 400
    armAntiSpam(300)
    local before = #chatMessages
    local blockedBefore = SanctuaryCharDB.sessionStats.blockedCount or 0
    local result = ns.runChannelSpamDiagnostic("SanctuaryTest")
    equal(result.shown, 1, "the anti-spam shows one of the three copies")
    equal(countProbeLines(before), result.shown,
        "and exactly that many probe lines reach the chat")
    equal(#chatMessages - before, 1, "with nothing else printed alongside them")
    equal(result.written, result.shown, "the result says as much")
    equal(SanctuaryCharDB.sessionStats.blockedCount or 0, blockedBefore,
        "and a hidden repeat is still not a block")

    -- Anti-spam off: three copies shown, three lines.
    armAntiSpam(300)
    SanctuaryDB.antiSpam.enabled = false
    before = #chatMessages
    result = ns.runChannelSpamDiagnostic("SanctuaryTest")
    equal(result.shown, 3, "with the anti-spam off the three copies show")
    equal(countProbeLines(before), result.shown, "and all three reach the chat")
    equal(#chatMessages - before, 3, "with nothing else printed alongside them")

    -- Channels all filtered: the three copies are blocked as a stranger's, so
    -- none of them is written.
    armAntiSpam(300)
    SanctuaryDB.filters.channelMode = "all"
    before = #chatMessages
    result = ns.runChannelSpamDiagnostic("SanctuaryTest")
    equal(result.shown, 0, "with the channels all filtered nothing shows")
    equal(countProbeLines(before), result.shown, "and no probe line reaches the chat")
    equal(result.written, 0, "the result says nothing was written")
    resetModelState()
end

-- Clicked twice, the button answers twice. The probe sends the same pseudo and
-- the same line every time, so its own shown copy used to hold the anti-spam
-- window open and the next click was hidden whole -- shown=0, written=0, not a
-- word in the chat. Nothing was broken, but the step promises "one line appears
-- in the chat", so a second click read as a failure of the product. The clock
-- does not move between the first two clicks here, which is the worst the
-- window can be asked about.
do
    local probeText = ns.L["DIAG_SPAM_PROBE_MSG"]
    local function countProbeLines(from)
        local count = 0
        for index = from + 1, #chatMessages do
            local line = chatMessages[index]
            if type(line) == "string" and line:find(probeText, 1, true) then
                count = count + 1
            end
        end
        return count
    end
    local function clickProbe(label)
        local before = #chatMessages
        local blockedBefore = SanctuaryCharDB.sessionStats.blockedCount or 0
        local result = ns.runChannelSpamDiagnostic("SanctuaryTest")
        equal(result.shown, 1, label .. ": one copy shows")
        equal(result.hidden, 2, label .. ": and the two repeats are hidden")
        equal(result.written, 1, label .. ": one line is written")
        equal(countProbeLines(before), 1, label .. ": and exactly one reaches the chat")
        equal(#chatMessages - before, 1, label .. ": with nothing else printed alongside it")
        equal(SanctuaryCharDB.sessionStats.blockedCount or 0, blockedBefore,
            label .. ": a hidden repeat is still not a block")
    end

    armAntiSpam(300)
    clickProbe("first click")
    clickProbe("second click, same clock")
    now = now + 10
    clickProbe("third click, ten seconds later")

    -- The session opens on "run them all", and the probe is clicked right after.
    -- The batch leaves the probe alone now, but whatever it does run must not
    -- leave a record behind that makes the click that follows come back empty.
    armAntiSpam(300)
    for _, entry in ipairs(ns.DIAGNOSTIC_CATALOG) do
        if ns.isBulkDiagnostic(entry) then
            ns.runDiagnosticById(entry.id, entry.argDefault)
        end
    end
    clickProbe("a click right after a bulk run")

    -- A real player's window is not the probe's to move. A stranger whose line
    -- has just been shown is still hidden on the repeat, probe or no probe.
    armAntiSpam(300)
    local spammerLine = freshMessage()
    equal(deliverCopy("filters_first", spammerLine, SPAMMER, nextLine(), "a stranger's copy"),
        false, "a stranger's first copy shows")
    ns.runChannelSpamDiagnostic("SanctuaryTest")
    now = now + 10
    equal(deliverCopy("filters_first", spammerLine, SPAMMER, nextLine(), "the stranger's repeat"),
        true, "and their repeat is still hidden after the probe has run")

    -- Covered: the channels are all filtered, so the three copies are blocked as
    -- a stranger's long before the anti-spam is asked anything, and each of the
    -- three is a block of its own. There is no probe record to forget here, and
    -- the second click says exactly what the first did.
    armAntiSpam(300)
    SanctuaryDB.filters.channelMode = "all"
    local before = #chatMessages
    local blockedBefore = SanctuaryCharDB.sessionStats.blockedCount or 0
    local covered = ns.runChannelSpamDiagnostic("SanctuaryTest")
    equal(covered.covered, true, "the result says the channels already cover it")
    equal(covered.shown, 0, "nothing shows")
    equal(covered.hidden, 3, "the three copies are hidden")
    equal(covered.written, 0, "and none of them is written")
    equal(countProbeLines(before), 0, "no probe line reaches the chat")
    equal(SanctuaryCharDB.sessionStats.blockedCount or 0, blockedBefore + 3,
        "the three are counted as the blocks they are")
    local again = ns.runChannelSpamDiagnostic("SanctuaryTest")
    equal(again.shown, 0, "a second click still shows nothing")
    equal(again.hidden, 3, "with the same three hidden")
    resetModelState()
end

-- The "xN" counts the times the message ARRIVED (decision 132, Q2), and a copy
-- shown again once the window has run out is one of those arrivals. Five
-- arrivals of one line -- shown, hidden, hidden, shown again past the window,
-- hidden -- read as one entry counted five times.
do
    armAntiSpam(300)
    SanctuaryDB.debugEnabled = true
    ns.resetDebugLog()
    local message = freshMessage()
    local logBefore = #SanctuaryDB.log
    local blockedBefore = SanctuaryCharDB.sessionStats.blockedCount or 0

    equal(deliverCopy("filters_first", message, SPAMMER, nextLine(), "the first copy"), false,
        "the first copy is shown")
    equal(#SanctuaryDB.log, logBefore,
        "a shown copy with no entry for the day opens none")

    now = now + 10
    equal(deliverCopy("filters_first", message, SPAMMER, nextLine(), "the first repeat"), true,
        "the first repeat is hidden")
    now = now + 10
    equal(deliverCopy("filters_first", message, SPAMMER, nextLine(), "the second repeat"), true,
        "and so is the second")

    now = now + 281
    equal(deliverCopy("filters_first", message, SPAMMER, nextLine(), "the copy past the window"), false,
        "the copy past the window is shown again")
    now = now + 10
    equal(deliverCopy("filters_first", message, SPAMMER, nextLine(), "the last repeat"), true,
        "and the repeat after it is hidden")

    equal(#SanctuaryDB.log - logBefore, 1, "the five arrivals are one entry")
    local entry = SanctuaryDB.log[#SanctuaryDB.log]
    equal(entry.count, 5, "counted five times, the shown copies included")
    equal(countDebug("MASK_SPAM_REPEAT"), 3, "with one recording per hidden copy, and no more")
    equal(SanctuaryCharDB.sessionStats.blockedCount or 0, blockedBefore,
        "and not one of the five is counted as a block")
    SanctuaryDB.debugEnabled = false
end

-- An entry belongs to the day of its key, and is dated from it. The longest
-- window reaches back across a night: a copy shown before midnight and repeated
-- after it opens an entry filed under the new day, and dating it from the shown
-- copy would print a range spanning the night.
do
    armAntiSpam(86400)
    setHarnessDay("2026-08-24")
    local message = freshMessage()
    deliverCopy("filters_first", message, SPAMMER, nextLine(), "the copy shown before midnight")
    local shownEpoch = time()

    now = now + 100
    setHarnessDay("2026-08-25")
    deliverCopy("filters_first", message, SPAMMER, nextLine(), "the repeat after midnight")
    local entry = SanctuaryDB.log[#SanctuaryDB.log]
    equal(entry.count, 2, "the repeat of the next day opens its own entry")
    equal(entry.t, time(), "dated from the day it was filed under")
    check(entry.t ~= shownEpoch, "and not from the copy shown the day before")

    -- Inside one day nothing changes: the entry still opens on the copy the
    -- person actually read.
    armAntiSpam(86400)
    setHarnessDay("2026-08-25")
    message = freshMessage()
    deliverCopy("filters_first", message, SPAMMER, nextLine(), "the shown copy")
    local sameDayEpoch = time()
    now = now + 100
    deliverCopy("filters_first", message, SPAMMER, nextLine(), "the repeat")
    entry = SanctuaryDB.log[#SanctuaryDB.log]
    equal(entry.t, sameDayEpoch, "a repeat of the same day still dates from the shown copy")
    equal(entry.t2, time(), "and the range runs to the last arrival")
    setHarnessDay("2026-06-20")
end

resetModelState()

end

-- C20 -- the Journal folds the repetitions of one day into one entry.
do

local SPAMMY = "Spammy-TestRealm"

local function clean(day)
    resetModelState()
    ns.clearJournal()
    setHarnessDay(day or "2026-08-24")
    now = now + 5
end

-- Two identical blocks on one day are one line, with a count and a range.
clean()
ns.logBlock("channel", SPAMMY, "buy gold now", nil, nil)
now = now + 5
ns.logBlock("channel", SPAMMY, "buy gold now", nil, nil)
equal(#SanctuaryDB.log, 1, "the same line twice in a day is one entry")
equal(SanctuaryDB.log[1].count, 2, "counted twice")
equal(SanctuaryDB.log[1].t2 - SanctuaryDB.log[1].t, 5, "and dated from the first to the last")
now = now + 5
ns.logBlock("channel", SPAMMY, "buy gold now", nil, nil)
equal(#SanctuaryDB.log, 1, "a third one is still one entry")
equal(SanctuaryDB.log[1].count, 3, "counted three times")
equal(SanctuaryDB.log[1].t2 - SanctuaryDB.log[1].t, 10, "with the range grown to the last one")

-- Tomorrow is another entry: the fold is bounded to the day, decision 125.
setHarnessDay("2026-08-25")
now = now + 5
ns.logBlock("channel", SPAMMY, "buy gold now", nil, nil)
equal(#SanctuaryDB.log, 2, "the same line the next day opens a new entry")
equal(SanctuaryDB.log[2].count, nil, "which counts as one, and says nothing about it")
setHarnessDay("2026-08-24")

-- What is not the same entry.
do
    local DISTINCT = {
        { what = "another type",  type = "say",     name = SPAMMY,             msg = "buy gold now" },
        { what = "another pseudo", type = "channel", name = "Other-TestRealm",  msg = "buy gold now" },
        { what = "another realm",  type = "channel", name = "Spammy-Ysondre",   msg = "buy gold now" },
        { what = "another message", type = "channel", name = SPAMMY,            msg = "buy gold NOW" },
    }
    for _, case in ipairs(DISTINCT) do
        clean()
        ns.logBlock("channel", SPAMMY, "buy gold now", nil, nil)
        now = now + 5
        ns.logBlock(case.type, case.name, case.msg, nil, nil)
        equal(#SanctuaryDB.log, 2, "a block with " .. case.what .. " is its own entry")
    end
end

-- The one-second dedupe, corrected. Two DIFFERENT lines from one person inside a
-- second were two things said; two invitations inside a second are one event
-- seen twice, and that is the behaviour this release inherited and keeps.
clean()
ns.logBlock("channel", SPAMMY, "first thing", nil, nil)
ns.logBlock("channel", SPAMMY, "second thing", nil, nil)
equal(#SanctuaryDB.log, 2, "two different lines in the same second are two entries")

clean()
ns.logBlock("groupInvite", "Knocker-TestRealm", nil, nil, nil)
ns.logBlock("groupInvite", "Knocker-TestRealm", nil, nil, nil)
equal(#SanctuaryDB.log, 1, "two invitations in the same second are one entry")

-- An entry with no message is not folded either: nothing tells two of them
-- apart, so counting them together would hide how often somebody knocked.
clean()
ns.logBlock("duel", "Knocker-TestRealm", nil, nil, nil)
now = now + 5
ns.logBlock("duel", "Knocker-TestRealm", nil, nil, nil)
equal(#SanctuaryDB.log, 2, "two duels a few seconds apart stay two entries")

-- A hidden repeat costs nothing outside the Journal: not a session count, not a
-- verbose line, and so not a five-minute summary either.
do
    local channelRow
    for _, row in ipairs(ns.CHAT_KINDS) do
        if row.kind == "channel" then channelRow = row end
    end
    clean()
    SanctuaryDB.antiSpam.enabled = true
    SanctuaryDB.antiSpam.intervalSeconds = 300
    SanctuaryDB.notifications.mode = "verbose"
    SanctuaryCharDB.sessionStats.blockedCount = 0
    local message = "buy my gold, honestly"
    deliverChatMessage("filters_first", 3, "CHAT_MSG_CHANNEL",
        channelPayload(message, SPAMMY, 810001))
    equal(#SanctuaryDB.log, 0, "the copy that is shown is not journalled")
    now = now + 10
    chatMessages = {}
    deliverChatMessage("filters_first", 3, "CHAT_MSG_CHANNEL",
        channelPayload(message, SPAMMY, 810002))
    equal(#SanctuaryDB.log, 1, "the copy that is hidden opens one entry")
    equal(SanctuaryDB.log[1].type, "channel", "under its own type, untouched")
    equal(SanctuaryDB.log[1].count, 2,
        "counting the times the line arrived, the copy that was shown included")
    equal(SanctuaryCharDB.sessionStats.blockedCount, 0, "and nothing is counted for the session")
    equal(#chatMessages, 0, "nothing is printed in the chat")
    now = now + 10
    deliverChatMessage("filters_first", 3, "CHAT_MSG_CHANNEL",
        channelPayload(message, SPAMMY, 810003))
    equal(#SanctuaryDB.log, 1, "a second hidden copy folds into the same entry")
    equal(SanctuaryDB.log[1].count, 3, "and adds one to the count")
    equal(SanctuaryCharDB.sessionStats.blockedCount, 0, "still counting nothing")
    -- The five-minute summary reads that counter and nothing else, so it stays
    -- silent through the whole thing.
    SanctuaryDB.notifications.mode = "minimal"
    chatMessages = {}
    now = now + 1000
    runTickers()
    equal(#chatMessages, 0, "and the five-minute summary has nothing to say")
    SanctuaryDB.notifications.mode = "silent"

    -- With the Journal switched off nothing is written -- and the anti-spam
    -- goes on hiding, because hiding is not journalling.
    clean()
    SanctuaryDB.antiSpam.enabled = true
    SanctuaryDB.logging.enabled = false
    local quiet = "nothing to record here"
    deliverChatMessage("filters_first", 3, "CHAT_MSG_CHANNEL",
        channelPayload(quiet, SPAMMY, 811001))
    now = now + 10
    local hidden = deliverChatMessage("filters_first", 3, "CHAT_MSG_CHANNEL",
        channelPayload(quiet, SPAMMY, 811002))
    equal(hidden[1], true, "the repeat is still hidden with the Journal off")
    equal(#SanctuaryDB.log, 0, "and nothing is written")
    SanctuaryDB.logging.enabled = true
end

-- A full journal. Rotation drops the oldest entries, and only those leave the
-- index: what stays goes on folding, which is the very case the fold was asked
-- for.
clean()
SanctuaryDB.logging.maxEntries = 3
ns.logBlock("channel", SPAMMY, "line one", nil, nil)
now = now + 5
ns.logBlock("channel", SPAMMY, "line two", nil, nil)
now = now + 5
ns.logBlock("channel", SPAMMY, "line three", nil, nil)
equal(#SanctuaryDB.log, 3, "three entries fill a journal of three")
now = now + 5
ns.logBlock("channel", SPAMMY, "line four", nil, nil)
equal(#SanctuaryDB.log, 3, "a fourth rotates the oldest out")
equal(SanctuaryDB.log[1].msg, "line two", "and it is the oldest that goes")
now = now + 5
ns.logBlock("channel", SPAMMY, "line one", nil, nil)
equal(#SanctuaryDB.log, 3, "the evicted line comes back as a new entry")
equal(SanctuaryDB.log[3].count, nil, "counted once, not folded into an entry nobody can reach")
now = now + 5
ns.logBlock("channel", SPAMMY, "line three", nil, nil)
equal(#SanctuaryDB.log, 3, "and an entry still in the journal goes on folding")
local stillThere
for _, entry in ipairs(SanctuaryDB.log) do
    if entry.msg == "line three" then stillThere = entry end
end
equal(stillThere and stillThere.count, 2, "with one more occurrence on it")
SanctuaryDB.logging.maxEntries = 5000

-- Emptying the journal empties what folds into it.
clean()
ns.logBlock("channel", SPAMMY, "buy gold now", nil, nil)
ns.clearJournal()
now = now + 5
ns.logBlock("channel", SPAMMY, "buy gold now", nil, nil)
equal(#SanctuaryDB.log, 1, "after a clear the same line opens a new entry")
equal(SanctuaryDB.log[1].count, nil, "counted once")

resetModelState()
setHarnessDay("2026-06-20")

end

-- C21 -- "your journal is filling up", once per level per session.
do

resetModelState()
SanctuaryDB.logging.maxEntries = 100

local function fillJournal(count)
    ns.clearJournal()
    for index = 1, count do
        SanctuaryDB.log[index] = { t = index, d = "2026-08-24 00:00:00",
            type = "channel", name = "Filler" .. index }
    end
end

local function said(text)
    local count = 0
    for _, line in ipairs(chatMessages) do
        if line:find(text, 1, true) then count = count + 1 end
    end
    return count
end

local almostAt90 = string.format(ns.L["LOGS_ALERT_ALMOST_FULL"], 90, 100)
local almostAt100 = string.format(ns.L["LOGS_ALERT_ALMOST_FULL"], 100, 100)
local fullAt100 = string.format(ns.L["LOGS_ALERT_FULL"], 100)

fillJournal(89)
chatMessages = {}
fire("PLAYER_ENTERING_WORLD")
equal(#chatMessages, 0, "one entry short of nine tenths, nothing is said")

fillJournal(90)
chatMessages = {}
fire("ADDON_LOADED", "Sanctuary")
equal(said(almostAt90), 1, "at nine tenths the journal says so, once")
fire("PLAYER_ENTERING_WORLD")
fire("PLAYER_ENTERING_WORLD")
fire("PLAYER_ENTERING_WORLD")
equal(said(almostAt90), 1, "and not again at every loading screen")

-- Full. The rotation is kept (decision 132, Q1), so the text says what happens
-- now rather than that recording has stopped -- and the nine-tenths line is not
-- said as well.
fillJournal(100)
chatMessages = {}
fire("PLAYER_ENTERING_WORLD")
equal(said(fullAt100), 1, "a full journal says it is full")
equal(said(almostAt100), 0, "and does not also say it is nearly full")
fire("PLAYER_ENTERING_WORLD")
equal(said(fullAt100), 1, "once, like the other one")

-- Nothing to record, nothing to warn about.
fillJournal(100)
SanctuaryDB.logging.enabled = false
chatMessages = {}
fire("PLAYER_ENTERING_WORLD")
equal(#chatMessages, 0, "with the Journal switched off nothing is said")
SanctuaryDB.logging.enabled = true

fillJournal(100)
SanctuaryCharDB.overrides.enabled = false
chatMessages = {}
fire("PLAYER_ENTERING_WORLD")
equal(#chatMessages, 0, "and with Sanctuary switched off nothing is said either")
SanctuaryCharDB.overrides.enabled = nil

-- Emptying the journal arms it again: it is a different journal now.
fillJournal(100)
chatMessages = {}
fire("PLAYER_ENTERING_WORLD")
equal(said(fullAt100), 1, "a journal that filled up again warns again")

SanctuaryDB.logging.maxEntries = 5000
ns.clearJournal()
resetModelState()

end

-- ===========================================================================
-- SECTION: no dead entry -- what the person typed reaches what the game says
-- ===========================================================================

-- The invariant, stated once for the three fields somebody can type into: when
-- the field answers yes, the name the GAME hands over for that same person must
-- be classified the way they asked. Four rounds of this release closed four
-- different ways of writing an entry that blocked or allowed nobody -- a hyphen,
-- a BattleTag, punctuation, and a case fold that stopped at ASCII -- each one
-- found by somebody reading the code, one at a time, after the panel had already
-- shown the chip and counted the tile. This loop is what is meant to catch the
-- fifth without a fifth round.
--
-- Left column: what somebody types in the panel. Right column: how that same
-- character reaches a decision in game -- realm-qualified, and with the initial
-- in uppercase, because that is what WoW renders.
--
-- The whole section lives in a `do ... end`: the enclosing chunk is at Lua's
-- 200-local ceiling and a new local at its level stops the file compiling.
do

local TYPED_AND_RENDERED = {
    -- The control. If this row ever fails, the fix broke the ASCII names that
    -- always worked and every other row below is noise.
    { typed = "elodie",     piece = "elo", rendered = "Elodie-TestRealm", what = "an ASCII pseudo" },
    { typed = "élodie",     piece = "élo", rendered = "Élodie-TestRealm", what = "an accented initial" },
    { typed = "ÉLODIE",     piece = "ÉLO", rendered = "Élodie-TestRealm", what = "the same name typed in capitals" },
    { typed = "ZOË",        piece = "OË",  rendered = "Zoë-TestRealm",    what = "capitals with the accent inside the pseudo" },
    { typed = "ŒDIPE",      piece = "œdi", rendered = "Œdipe-TestRealm",  what = "a ligature" },
    { typed = "žofia",      piece = "žof", rendered = "Žofia-TestRealm",  what = "a caron" },
    { typed = "илья",       piece = "иль", rendered = "Илья-TestRealm",   what = "a cyrillic pseudo" },
    { typed = "ЁЖИК",       piece = "ёж",  rendered = "Ёжик-TestRealm",   what = "cyrillic Ё, outside the main run" },
    { typed = "toto-éonar", piece = "tot", rendered = "Toto-Éonar",       what = "an accented realm" },
}

for _, case in ipairs(TYPED_AND_RENDERED) do
    -- Blocked: the field said yes, so the person is blocked, and the tile the
    -- panel shows says the same thing the decision does.
    resetModelState()
    equal(ns.addBlocked(case.typed), true,
        "the blocked field accepts " .. case.what .. " (" .. case.typed .. ")")
    equal(ns.getListCounts().blocked.names, 1,
        "and counts it once (" .. case.typed .. ")")
    equal(ns.classifyName(case.rendered).verdict, "always_blocked",
        "and " .. case.rendered .. " is blocked when the game hands the name over")
    equal(ns.describeAccessDecision(case.rendered).blockedNow, true,
        "and the tester says so too (" .. case.rendered .. ")")

    -- Allowed: the harder direction. In the default scope an unknown name is
    -- cut, so a name the person allowed by hand and that stays unknown is a
    -- friend silenced with no popup, no sound and no chat line.
    resetModelState()
    equal(ns.addAllowed(case.typed), true,
        "the allowed field accepts " .. case.what .. " (" .. case.typed .. ")")
    equal(ns.classifyName(case.rendered).verdict, "always_allowed",
        "and " .. case.rendered .. " is allowed when the game hands the name over")
    equal(ns.describeAccessDecision(case.rendered).blockedNow, false,
        "so nothing of theirs is cut (" .. case.rendered .. ")")
    equal(dispatchChatFilter("CHAT_MSG_WHISPER", "hi", case.rendered), false,
        "and their whisper reaches the person (" .. case.rendered .. ")")

    -- Pattern: a piece of the pseudo, looked for in the pseudo alone.
    resetModelState()
    equal(ns.addPattern(case.piece), true,
        "the pattern field accepts " .. case.piece .. " (" .. case.what .. ")")
    equal(ns.getListCounts().blocked.patterns, 1,
        "and counts it once (" .. case.piece .. ")")
    equal(ns.classifyName(case.rendered).verdict, "always_blocked",
        "and " .. case.piece .. " catches " .. case.rendered)
end

-- The fold is bounded, and the boundary is part of the contract: ß has no
-- one-letter uppercase and × is not a letter at all. Neither is folded, so
-- neither turns one name into another.
resetModelState()
equal(ns.addBlocked("Straße"), true, "a name with a sharp s is still a name")
equal(ns.classifyName("Straße-TestRealm").verdict, "always_blocked",
    "and it blocks the person the game names")
equal(ns.classifyName("Strasse-TestRealm").verdict, "unknown",
    "while a different spelling is a different person")

-- Two pseudos that differ by an accent are two people, before and after the
-- fold. Folding case must not fold letters together.
resetModelState()
equal(ns.addBlocked("élodie"), true, "the accented name is blocked")
equal(ns.classifyName("Elodie-TestRealm").verdict, "unknown",
    "and the unaccented namesake is left alone")

-- Same rule on the realm half: an accented realm is its own realm.
resetModelState()
equal(ns.addBlocked("toto-éonar"), true, "the name is blocked on its accented realm")
equal(ns.classifyName("Toto-Eonar").verdict, "unknown",
    "and the same pseudo on another realm walks free")

-- ---------------------------------------------------------------------------
-- Whispering yourself
-- ---------------------------------------------------------------------------

-- People whisper themselves: a note, a link kept for later. It arrives as a
-- CHAT_MSG_WHISPER whose sender is the player, and the whisper filter was the
-- one character filter with no "am I the sender" line -- so somebody who had
-- blocked their own name, or who fell under one of their own patterns, watched
-- their own note disappear. Both spellings the game uses are checked, because
-- only one of them carries a realm.
resetModelState()
ns.addBlocked("Victim")
ns.addPattern("vic")
ns.addBlocked("Spammerguy")
equal(dispatchChatFilter("CHAT_MSG_WHISPER", "note to self", "Victim"), false,
    "a whisper to yourself is delivered, bare name")
equal(dispatchChatFilter("CHAT_MSG_WHISPER", "note to self", "Victim-TestRealm"), false,
    "and realm-qualified")
equal(dispatchChatFilter("CHAT_MSG_WHISPER", "hi", "Spammerguy-TestRealm"), true,
    "while a blocked player's whisper is still discarded")
equal(dispatchChatFilter("CHAT_MSG_WHISPER", "hi", "Nobody-TestRealm"), true,
    "and so is a stranger's")
equal(dispatchChatFilter("CHAT_MSG_WHISPER", "hi", "Victim-Ysondre"), true,
    "and a namesake on another realm is not the player")

-- The same question with an accented player name, which is where "am I the
-- sender" used to compare two spellings of the same person.
do
    local realFullName, realName = UnitFullName, UnitName
    UnitFullName = function(unit)
        if unit == "player" then return "Élodie", "TestRealm" end
        return realFullName(unit)
    end
    UnitName = function(unit)
        if unit == "player" then return "Élodie", "TestRealm" end
        return realName(unit)
    end

    resetModelState()
    -- The say filter is off by default, and an off filter answers "keep it" for
    -- everyone: turn it on, or the line proves nothing about self-recognition.
    SanctuaryDB.filters.say = true
    equal(dispatchChatFilter("CHAT_MSG_WHISPER", "note to self", "Élodie-TestRealm"), false,
        "an accented player still recognises their own whisper")
    equal(dispatchChatFilter("CHAT_MSG_SAY", "hello", "Élodie-TestRealm"), false,
        "and their own say line")
    equal(dispatchChatFilter("CHAT_MSG_SAY", "hello", "Élodie-Ysondre"), true,
        "while their namesake on another realm is a stranger like any other")
    SanctuaryDB.filters.say = false

    UnitFullName, UnitName = realFullName, realName
end

-- The mocks are back: the rest of the file speaks for Victim again.
resetModelState()
equal(dispatchChatFilter("CHAT_MSG_WHISPER", "note to self", "Victim-TestRealm"), false,
    "the player is Victim again for everything that follows")

resetModelState()

end

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
-- Recorded rather than swallowed: a chip's label is cut to the width of its row,
-- so the tooltip is where the whole of a name can be read -- and that makes it a
-- surface the harness has to be able to ask about.
function GameTooltip:SetText(text) rawset(self, "__lastText", text) end

local createdWidgets = {}

-- Auto-stubbed methods, but only for keys that look like widget methods --
-- every WoW widget method starts with a capital, and every data field the
-- addon hangs on a frame (`entry.nameLabel`, `btn.label`, `dialog.which`)
-- starts lowercase. Stubbing those too would turn `if not entry.nameLabel` into
-- a permanently false test and quietly break the pooling logic.
-- `SetBackdrop*` is never auto-stubbed, and that exception is the whole point:
-- in Retail a frame created WITHOUT "BackdropTemplate" has none of the three,
-- and `applyBackdrop` gives up in silence on a frame with no `SetBackdrop`.
-- Auto-stubbed, they exist on every widget, so the harness accepted a backdrop
-- the client never drew -- which is how checkboxes and radios shipped with no
-- box at all and every test stayed green.
local widgetMeta
widgetMeta = {
    __index = function(t, key)
        if key == "SetBackdrop" or key == "SetBackdropColor"
            or key == "SetBackdropBorderColor" then
            return nil
        end
        if type(key) == "string" and key:match("^%u") then
            local stub = function() return nil end
            rawset(t, key, stub)
            return stub
        end
        return nil
    end,
}

local function newWidget(kind, name, parent, template)
    local w = setmetatable({}, widgetMeta)
    w.__kind = kind
    w.__name = name
    w.__parent = parent
    w.__template = template
    -- What "BackdropTemplate" mixes in, and only when it is asked for.
    if type(template) == "string" and template:find("BackdropTemplate", 1, true) then
        function w:SetBackdrop(info) self.__backdrop = info end
        function w:SetBackdropColor(r, g, b, a) self.__backdropColor = { r, g, b, a } end
        function w:SetBackdropBorderColor(r, g, b, a) self.__backdropBorder = { r, g, b, a } end
    end
    w.__scripts = {}
    w.__children = {}
    w.__shown = true
    w.__text = ""
    w.__width, w.__height = 620, 480

    function w:GetParent() return self.__parent end
    function w:SetParent(p) self.__parent = p end
    function w:GetName() return self.__name end
    -- `__widthPosted` marks a width the interface actually asked for. Every
    -- widget answers 620 before anyone sets one, so a sweep that reads
    -- `GetWidth` alone cannot tell "the interface sized this" from "nobody ever
    -- did" -- and 620 happens to fit inside a 780 px window, which is how a
    -- screen full of widths nobody had touched could look measured.
    function w:SetSize(width, height)
        self.__width, self.__height = width, height
        self.__widthPosted = true
    end
    function w:SetWidth(width)
        self.__width = width
        self.__widthPosted = true
    end
    function w:SetHeight(height) self.__height = height end
    function w:GetWidth() return self.__width end
    function w:GetHeight() return self.__height end
    -- Anchors, recorded rather than auto-stubbed. `SetPoint` fell to the
    -- catch-all above, so "where is this widget" was the one question the
    -- harness could not be asked -- and a label anchored 320 px into a 464 px
    -- screen was a defect no check here could reach, whatever it measured. The
    -- six call forms of the real method are normalised to one shape, so a test
    -- reads back the offset the client was actually handed.
    w.__points = {}
    function w:SetPoint(point, a, b, c, d)
        local relativeTo, relativePoint, x, y
        if a == nil then
            relativeTo, relativePoint, x, y = self.__parent, point, 0, 0
        elseif type(a) == "number" then
            -- SetPoint(point, x, y): the parent, on the same point.
            relativeTo, relativePoint, x, y = self.__parent, point, a, b or 0
        elseif type(b) == "string" then
            relativeTo, relativePoint, x, y = a, b, c or 0, d or 0
        else
            -- SetPoint(point, relativeTo[, x, y]): the relative point defaults
            -- to the widget's own.
            relativeTo, relativePoint, x, y = a, point, b or 0, c or 0
        end
        self.__points[#self.__points + 1] = {
            point = point, relativeTo = relativeTo,
            relativePoint = relativePoint, x = x, y = y,
        }
    end
    function w:ClearAllPoints() self.__points = {} end
    function w:GetNumPoints() return #self.__points end
    function w:GetPoint(index)
        local entry = self.__points[index or 1]
        if not entry then return nil end
        return entry.point, entry.relativeTo, entry.relativePoint, entry.x, entry.y
    end
    -- Like the client: the cursor lands after the last character written, and
    -- the view follows the cursor -- which is exactly why a field narrower than
    -- its own value shows the END of it until something sends it back (A.9).
    function w:SetText(text)
        self.__text = text
        self.__cursor = #tostring(text or "")
    end
    function w:GetText() return self.__text end
    function w:Insert(text) self.__text = (self.__text or "") .. tostring(text) end
    -- A stand-in that wraps. A flat 12 answered for a sentence of any length, so
    -- every layout measured from `GetStringHeight` measured one line whatever
    -- the window was -- and the home screen's own height, which the minimum size
    -- of the window is now derived from, is one of them. Newlines are counted,
    -- and a bounded FontString that wraps takes as many lines as its natural
    -- width needs. `GetStringWidth` counts BYTES, so accented French measures
    -- wider than it draws: this over-estimates rather than under-estimates,
    -- which is the safe direction for a height bound.
    function w:GetStringHeight()
        local text = self.__text or ""
        if text == "" then return 12 end
        local lines = 1
        for _ in text:gmatch("\n") do lines = lines + 1 end
        local width = self:GetWidth() or 0
        if width > 0 and self.__wordWrap ~= false then
            lines = lines + math.max(0, math.ceil(self:GetStringWidth() / width) - 1)
        end
        return lines * 12
    end
    -- Recorded, because "which end of its own text a narrow field shows" is what
    -- constat A.9 is about, and a stub that answers nothing cannot say.
    function w:SetCursorPosition(position) self.__cursor = position end
    function w:GetCursorPosition() return self.__cursor or 0 end
    -- A stand-in with one property that matters: it grows with the text. The
    -- chips measure themselves through it, so a name too long for its row is a
    -- case a check can set up rather than a screenshot somebody has to read.
    function w:GetStringWidth() return #(self.__text or "") * 7 end
    function w:SetWordWrap(value) self.__wordWrap = value and true or false end
    -- Recorded, because "does changing screen put the shared frame back at the
    -- top" is a question only the offset can answer (constat G.4).
    function w:SetVerticalScroll(value) self.__verticalScroll = value end
    function w:GetVerticalScroll() return self.__verticalScroll or 0 end
    -- Recorded, because "how big is this text" is a rule the interface is held
    -- to -- nothing visible under 12 px -- and a stub that swallows SetFont
    -- makes it a rule nothing can check.
    function w:SetFont(file, size, flags)
        self.__fontFile, self.__fontSize, self.__fontFlags = file, size, flags
    end
    function w:GetFont()
        return self.__fontFile or "Fonts\\FRIZQT__.TTF", self.__fontSize or 12,
            self.__fontFlags or ""
    end
    -- Recorded rather than stubbed: what a texture is filled with, and whether
    -- it was rounded, is exactly what "the box is invisible" and "the radio is a
    -- square" are made of.
    function w:SetColorTexture(r, g, b, a) self.__colorTexture = { r, g, b, a or 1 } end
    -- Recorded too: which file a texture is pointed at, and whether it is being
    -- cropped, are the two things "the minimap shows the wrong picture" is made
    -- of, and neither leaves any other trace.
    function w:SetTexture(path) self.__texture = path end
    function w:GetTexture() return self.__texture end
    function w:SetTexCoord(...) self.__texCoord = { ... } end
    function w:EnableMouse(value) self.__mouseEnabled = value and true or false end
    -- Kept as four numbers rather than a table: a colour is read back one
    -- component at a time, and "is this line green" is a check the panel's
    -- online / offline split now rests on.
    function w:SetTextColor(r, g, b, a)
        self.__colorR, self.__colorG, self.__colorB, self.__colorA = r, g, b, a
    end
    function w:AddMaskTexture(mask) self.__mask = mask end
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
    -- A real widget method, and one the auto-stub cannot stand in for: it has to
    -- answer an object the caller then calls `SetTexture` on. The stub answers
    -- nil, so the round radios of the mock-up took the interface down at load
    -- the moment they were drawn.
    function w:CreateMaskTexture(maskName)
        local mask = newWidget("MaskTexture", maskName, self)
        self.__children[#self.__children + 1] = mask
        return mask
    end
    function w:SetScrollChild(child) self.__scrollChild = child end
    function w:GetScrollChild() return self.__scrollChild end
    -- Recorded rather than auto-stubbed: what the grip may do to the window is
    -- four numbers the client is handed once and never asked about again, so a
    -- silent stub let the vertical travel go to zero with every test green.
    function w:SetResizeBounds(minWidth, minHeight, maxWidth, maxHeight)
        self.__resizeBounds = { minWidth, minHeight, maxWidth, maxHeight }
    end
    function w:GetResizeBounds()
        local bounds = self.__resizeBounds
        if not bounds then return nil end
        return bounds[1], bounds[2], bounds[3], bounds[4]
    end
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
    local w = newWidget(frameType or "Frame", name, parent, template)
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
    -- 1.0.0: proper nouns and format strings that read the same in both
    -- languages. Listed rather than filtered out so adding one is deliberate.
    ADV_DIAG_TITLE = true, ADV_JOURNAL_TITLE = true, EXPORT_COLUMNS = true,
    PANEL_BLOCKED_PATTERNS = true, WL_BNET_ROW = true, TAB_PROTECTION = true,
    TAB_JOURNAL = true, TAB_DIAGNOSTICS = true, KIND_DUEL = true,
    Q4_MINIMAL_TITLE = true, LOG_TYPE_DUEL = true, ABOUT_VERSION = true,
    LOGS_GROUP_HEADER = true, DATE_FORMAT = true, DIAG_ARG_FILTER = true,
    -- The Journal's badge and its time range: a count, a dash and the word
    -- SPAM, which French borrows unchanged.
    LOGS_SPAM_BADGE = true, LOGS_TIME_RANGE = true,
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
-- No visible string asks the game font for a glyph it does not have
-- ---------------------------------------------------------------------------

-- The window is set in Friz Quadrata, which carries Latin-1 and the Windows-1252
-- additions on top of it -- the typographic quotes, the dashes, the ellipsis,
-- the angle quotes -- and nothing beyond. WoW draws anything else as a white
-- rectangle: "un rectangle blanc dans le menu des durees" was U+25BE, the small
-- down-pointing triangle, written into the duration field as a glyph. It is not
-- a translation problem -- no locale can render it -- so the arrow is drawn now,
-- and this is what keeps the next one from being written instead of drawn.
--
-- Two places a visible glyph can come from here: a locale value, and a string
-- literal in the code written as escaped bytes, which is what the caret was.
do
    local FONT_EXTRA = {}
    for _, code in ipairs({ 0x20AC, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
        0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x017D, 0x2018, 0x2019, 0x201C,
        0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153,
        0x017E, 0x0178 }) do
        FONT_EXTRA[code] = true
    end
    local function outsideFont(text)
        if not utf8.len(text) then return nil end
        for _, code in utf8.codes(text) do
            if code >= 0x100 and not FONT_EXTRA[code] then
                return string.format("U+%04X", code)
            end
        end
        return nil
    end
    local unrenderable = {}
    for _, entry in ipairs({ { "enUS", defaultLocale }, { "frFR", frenchLocale } }) do
        for key, value in pairs(entry[2]) do
            if type(value) == "string" then
                local code = outsideFont(value)
                if code then
                    unrenderable[#unrenderable + 1] = entry[1] .. "." .. key .. " " .. code
                end
            end
        end
    end
    -- And the escaped byte runs in the two code files. A comment cannot hold
    -- one -- accented French in a comment is written as itself -- so a run of
    -- "\226\150\190" is a string literal and nothing else.
    --
    -- A run written as a table KEY (`FOLD["\196\176"]`) is skipped: those are
    -- the case-folding tables, which match on characters the add-on reads and
    -- never draws -- Turkish, Cyrillic, Latin Extended-A. Nothing visible here
    -- is ever a key, so the shape tells the two apart on its own.
    for _, file in ipairs({ "/Sanctuary.lua", "/SanctuaryUI.lua" }) do
        local handle = assert(io.open(repoRoot .. file, "r"))
        local source = handle:read("a")
        handle:close()
        local cursor = 1
        while true do
            local runStart = source:find("\\%d%d?%d?", cursor)
            if not runStart then break end
            local bytes, at = {}, runStart
            while true do
                local _, stop, digits = source:find("^\\(%d%d?%d?)", at)
                if not stop then break end
                bytes[#bytes + 1] = string.char(tonumber(digits) % 256)
                at = stop + 1
            end
            local isKey = source:sub(runStart - 2, runStart - 1) == "[\""
                and source:sub(at, at + 1) == "\"]"
            local code = not isKey and outsideFont(table.concat(bytes)) or nil
            if code then
                unrenderable[#unrenderable + 1] = file:sub(2) .. " " .. code
            end
            cursor = at
        end
    end
    table.sort(unrenderable)
    equal(#unrenderable, 0,
        "no visible string carries a glyph the game font cannot draw ("
        .. table.concat(unrenderable, ", ") .. ")")
end

-- ---------------------------------------------------------------------------
-- No visible sentence is held together by an em dash
-- ---------------------------------------------------------------------------

-- Decision 153: two clauses joined by a long dash is the shape Vincent reads as
-- machine-written ("ca fait tres IA"), and a comma, a colon or a full stop says
-- the same thing without changing the sense. So the rule is about the MIDDLE of
-- a value, not about the character: the one dash left opens a string instead of
-- sitting inside one -- the "experimental" mention beside the enhanced-filtering
-- box, which Vincent wrote that way himself.
--
-- Both spellings are looked for: the em dash itself, and the double hyphen the
-- English block writes it with. The en dash of a time range ("14:00 - 16:00")
-- is not one of them -- it joins two numbers, not two clauses.
do
    local dashed = {}
    for _, entry in ipairs({ { "enUS", defaultLocale }, { "frFR", frenchLocale } }) do
        for key, value in pairs(entry[2]) do
            if type(value) == "string" then
                local body = value:gsub("^\226\128\148 ?", "")
                if body:find("\226\128\148", 1, true) or body:find("%-%-") then
                    dashed[#dashed + 1] = entry[1] .. "." .. key
                end
            end
        end
    end
    table.sort(dashed)
    equal(#dashed, 0,
        "no visible sentence is held together by an em dash ("
        .. table.concat(dashed, ", ") .. ")")
end

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
-- Every box, dot and tab is actually drawn
-- ---------------------------------------------------------------------------

-- The 1.0.0 session's first finding, and the one nothing here could see: an
-- unticked box had NO rendering at all and a ticked one was a bare blue square,
-- because a Retail CheckButton built without "BackdropTemplate" has no
-- `SetBackdrop` and `applyBackdrop` returns in silence. What follows asks the
-- widgets what they were actually given, so the fill and the border are facts
-- rather than intentions.
--
-- A scope of its own: the enclosing function is at Lua's ceiling of 200 locals.
;(function()

_G["SanctuaryTab_protection"]:Click()
_G.SanctuaryQ2_custom:Click()

local CHECK_BG = { 0.149, 0.149, 0.200, 1.00 }
local CHECK_ON = { 0.302, 0.702, 1.000, 1.00 }

local function sameColor(got, want)
    if type(got) ~= "table" then return false end
    for index = 1, 4 do
        if math.abs((got[index] or -1) - want[index]) > 0.001 then return false end
    end
    return true
end

-- Every check the five screens carry, the folded ones included: "même rendu
-- partout" is a promise about all of them, so the list is spelt out and a new
-- box added without one is a box this test does not cover -- which is why the
-- count is asserted too.
local CHECKS = {
    "SanctuaryStrictCheck", "SanctuaryAutoTrust",
    "SanctuaryFilter_groupInvite", "SanctuaryFilter_whisper", "SanctuaryFilter_say",
    "SanctuaryFilter_yell", "SanctuaryFilter_emote", "SanctuaryFilter_duel",
    "SanctuaryFilter_trade", "SanctuaryFilter_guildInvite",
    "SanctuaryJournalEnable", "SanctuaryJournalShowMessages",
    "SanctuaryDebugCheck", "SanctuaryMinimapCheck",
}
for _, name in ipairs(CHECKS) do
    local box = _G[name]
    check(box ~= nil, name .. " exists")
    check(box.__template ~= nil and box.__template:find("BackdropTemplate", 1, true) ~= nil,
        name .. " is built with the template that gives a frame its backdrop")
    check(sameColor(box.__backdropColor, CHECK_BG),
        name .. " is filled with the mock-up's box colour, not the field colour")
    check(box.__backdropBorder ~= nil, name .. " has a border, ticked or not")
    check(sameColor(box.mark and box.mark.__colorTexture, CHECK_ON),
        name .. " marks the ticked state in the mock-up's blue")
end

-- The unticked state is the one that had nothing to show. A box whose fill and
-- border are only applied when it is ticked reads as an empty label.
_G.SanctuaryFilter_say.get = function() return false end
_G.SanctuaryFilter_say:Refresh()
equal(_G.SanctuaryFilter_say.mark:IsShown(), false, "an unticked box shows no mark")
check(sameColor(_G.SanctuaryFilter_say.__backdropColor, CHECK_BG),
    "and is still a drawn box, which is the whole of the defect")

-- The radios are round: three discs and a circular mask, never a backdrop.
for _, mode in ipairs({ "none", "keywords", "all" }) do
    local radio = _G["SanctuaryChannel_" .. mode]
    check(radio ~= nil and radio.rim ~= nil and radio.fill ~= nil and radio.mark ~= nil,
        "the " .. mode .. " radio is drawn as a rim, a fill and a dot")
    equal(radio.__backdropColor, nil, "and never as a square backdrop")
    check(radio.mark.__mask ~= nil, "its dot is rounded by a mask")
    equal(radio:GetWidth(), 18, "and it is the same 18 px as a checkbox")
end
_G.SanctuaryChannel_keywords:Click()
equal(_G.SanctuaryChannel_keywords.mark:IsShown(), true, "the picked channel shows its dot")
equal(_G.SanctuaryChannel_none.mark:IsShown(), false, "and the others do not")
check(sameColor(_G.SanctuaryChannel_keywords.rim.__colorTexture, { 0.4, 0.6, 1.0, 1.0 }),
    "the picked radio's rim answers too")
_G.SanctuaryChannel_none:Click()

-- Decision 135: clicking the TEXT of a box or a dot works the box or the dot.
-- An 18 px square is a small target and every interface a person has used lets
-- them hit the words instead.
do
    -- `say` is the box the block above rewired to answer false for ever; `yell`
    -- is untouched and reads its own stored value.
    local box = _G.SanctuaryFilter_yell
    local hit = box.labelHit
    check(hit ~= nil, "a checkbox's label is a target of its own")
    equal(hit:GetParent(), box, "belonging to the box, so it hides with it")
    -- Anchored on the FontString at both corners: the target is the text and
    -- nothing past it. Given the row's width it would turn the empty half of
    -- the line into a switch nobody meant to touch.
    do
        local point, relativeTo = hit:GetPoint(1)
        equal(point, "TOPLEFT", "pinned to the top-left of the words")
        equal(relativeTo, box.label, "on the label itself")
        local corner, other = hit:GetPoint(2)
        equal(corner, "BOTTOMRIGHT", "and to their bottom-right")
        equal(other, box.label, "so it stops where the text stops")
    end
    local before = SanctuaryDB.filters.yell
    hit:Click()
    equal(SanctuaryDB.filters.yell, not before, "clicking the words works the box")
    hit:Click()
    equal(SanctuaryDB.filters.yell, before, "and works it back")
    -- A disabled box refuses the words exactly as it refuses the square.
    box:SetEnabledState(false)
    hit:Click()
    equal(SanctuaryDB.filters.yell, before, "a greyed box ignores its label too")
    box:SetEnabledState(true)

    local radio = _G.SanctuaryChannel_keywords
    check(radio.labelHit ~= nil, "and a radio's label is a target as well")
    radio.labelHit:Click()
    equal(SanctuaryDB.filters.channelMode, "keywords", "clicking the words picks the dot")
    _G.SanctuaryChannel_none.labelHit:Click()
    equal(SanctuaryDB.filters.channelMode, "none", "and moves it to the next one")
end

-- The tab strip, decision 140: ONE bar the full width of the window, between the
-- title bar and the content, on every screen. The current tab is filled with the
-- accent tint and underlined towards the content; the others carry the strip's
-- own fill. Nothing hangs below the frame any more.
local TAB_ON_FILL = { 0.400, 0.600, 1.000, 0.14 }
local TAB_OFF_FILL = { 0.078, 0.078, 0.141, 0.90 }
local strip = _G.SanctuaryTabBar
check(strip ~= nil, "the strip of tabs is a frame of its own")
equal(strip:GetHeight(), 30, "as tall as the bar the mock-up draws")
do
    local point, relativeTo, relativePoint, _, offsetY = strip:GetPoint()
    equal(point, "TOPLEFT", "hung from the window's top-left corner")
    equal(relativeTo, mainFrame, "on the window itself")
    equal(relativePoint, "TOPLEFT", "corner to corner")
    equal(offsetY, -40, "just under the title bar, not below the frame")
end
local function tabState(key)
    local tab = _G["SanctuaryTab_" .. key]
    return tab:GetHeight(), tab.underline:IsShown(), tab.__backdropColor
end
local currentHeight, currentUnderline, currentFill = tabState("protection")
local otherHeight, otherUnderline, otherFill = tabState("journal")
equal(currentHeight, 30, "every tab is the height of the strip")
equal(otherHeight, 30, "the current one included -- nothing climbs out of it")
equal(currentUnderline, true, "it carries the two-pixel underline")
check(sameColor(currentFill, TAB_ON_FILL), "and the accent tint behind its name")
equal(otherUnderline, false, "a tab that is not current has no underline")
check(sameColor(otherFill, TAB_OFF_FILL), "and stays the colour of the strip")
for _, key in ipairs({ "protection", "journal", "advanced", "about" }) do
    equal(_G["SanctuaryTab_" .. key]:GetParent(), strip,
        "the " .. key .. " tab lives in the strip, not under the window")
end
-- The five screens start BELOW the strip, or the first line of each is drawn
-- under it: 40 of title bar plus 30 of tabs.
do
    local _, _, _, _, offsetY = _G.SanctuaryContentScroll:GetPoint()
    equal(offsetY, -70, "the content area starts under the strip, not under the title bar")
end
_G["SanctuaryTab_journal"]:Click()
local _, journalUnderline = tabState("journal")
local _, protectionUnderline = tabState("protection")
equal(journalUnderline, true, "changing screen moves the underline")
equal(protectionUnderline, false, "and takes it off the one left behind")
_G["SanctuaryTab_protection"]:Click()

-- Decision 143: every card of choice carries a ring -- filled when it is the
-- answer, empty when it is not -- and the convention it settles is that round
-- means an exclusive choice and square means a switch, everywhere, without
-- exception. What was on screen carried the pick in the border alone, which is a
-- meaning in a colour.
do
    local CARDS = { "SanctuaryQ1_strangers", "SanctuaryQ1_blockedOnly",
        "SanctuaryQ2_all", "SanctuaryQ2_custom", "SanctuaryQ3_yes", "SanctuaryQ3_no",
        "SanctuaryQ4_silent", "SanctuaryQ4_minimal", "SanctuaryQ4_verbose" }
    for _, name in ipairs(CARDS) do
        local card = _G[name]
        check(card ~= nil and card.rim ~= nil and card.fill ~= nil and card.mark ~= nil,
            name .. " draws a rim, a fill and a dot")
        check(card.mark.__mask ~= nil, name .. "'s dot is rounded by a mask")
    end
    -- Round is an exclusive choice; square is a switch. A check's mark is a
    -- plain texture with no mask on it, and that difference is the convention.
    check(_G.SanctuaryFilter_duel.mark.__mask == nil,
        "a checkbox's mark stays square -- round is for an exclusive choice")

    -- Filled when picked, empty when not, and it follows the answer rather than
    -- the click: the model is what both cards are drawn from.
    SanctuaryDB.filters.scope = "strangers"
    ns.refreshUI()
    equal(_G.SanctuaryQ1_strangers.mark:IsShown(), true, "the chosen card's ring is filled")
    equal(_G.SanctuaryQ1_blockedOnly.mark:IsShown(), false, "and the other one's is empty")
    check(sameColor(_G.SanctuaryQ1_strangers.rim.__colorTexture, { 0.4, 0.6, 1.0, 1.0 }),
        "the chosen ring's rim answers in the accent too")
    _G.SanctuaryQ1_blockedOnly:Click()
    equal(_G.SanctuaryQ1_blockedOnly.mark:IsShown(), true, "picking the other moves the fill")
    equal(_G.SanctuaryQ1_strangers.mark:IsShown(), false, "and empties the one left behind")
    SanctuaryDB.filters.scope = "strangers"
    ns.refreshUI()
end

-- Decision 139, "B en trait long": a hairline of accent between two questions of
-- the home screen, the full width of the column, and NOWHERE else.
do
    _G["SanctuaryTab_protection"]:Click()
    ns.refreshUI()
    local content = _G.SanctuaryTabContent_protection
    -- Four joins between five questions, so four rules.
    local found = {}
    for _, child in ipairs(content.__children or {}) do
        if child.__kind == "Texture" and child:GetHeight() == 1
            and sameColor(child.__colorTexture, { 0.4, 0.6, 1.0, 0.32 }) then
            found[#found + 1] = child
        end
    end
    equal(#found, 4, "four rules, one between each pair of questions")
    for _, rule in ipairs(found) do
        equal(rule:GetWidth(), _G.SanctuaryMainFrame:GetWidth() - 36,
            "each one runs the whole column, padding aside")
    end
    -- Ordered down the screen, and each of them between the block above and the
    -- block below rather than stacked at one place.
    local previous = 1
    for index, rule in ipairs(found) do
        local _, _, _, _, y = rule:GetPoint()
        check((y or 0) < previous, "rule " .. index .. " sits under the one before it")
        previous = y or 0
    end
    -- And nowhere else in the interface: the other four screens carry none.
    for _, key in ipairs({ "journal", "advanced", "about", "diagnostics" }) do
        local elsewhere = 0
        for _, child in ipairs((_G["SanctuaryTabContent_" .. key] or {}).__children or {}) do
            if child.__kind == "Texture"
                and sameColor(child.__colorTexture, { 0.4, 0.6, 1.0, 0.32 }) then
                elsewhere = elsewhere + 1
            end
        end
        equal(elsewhere, 0, "the " .. key .. " screen carries no rule of its own")
    end
end

-- Decisions 142-143: the tile IS the button. "Gerer" is gone, the whole tile
-- opens the drawer, and what says so is a chevron at the right edge plus the
-- fill lightening under the pointer -- a shape and a colour, not a colour alone.
do
    for _, name in ipairs({ "SanctuaryTileAllowed", "SanctuaryTileBlocked" }) do
        local tile = _G[name]
        check(tile ~= nil, name .. " is on the home screen")
        equal(tile.manage, nil, name .. " has no Manage button left in it")
        check(tile.chevron ~= nil and (tile.chevron.__text or "") ~= "",
            name .. " carries a chevron at its right edge")
        check(type(tile:GetScript("OnClick")) == "function", name .. " is clickable whole")
        check(type(tile:GetScript("OnEnter")) == "function", name .. " lightens under the pointer")
        equal(tile:GetHeight(), 46, name .. " is the thin tile of the mock-up")
    end
    -- The pointer really does change the fill, and puts it back.
    local tile = _G.SanctuaryTileAllowed
    tile:GetScript("OnEnter")(tile)
    check(sameColor(tile.__backdropColor, { 0.4, 0.6, 1.0, 0.12 }),
        "the hovered tile is lit")
    tile:GetScript("OnLeave")(tile)
    check(sameColor(tile.__backdropColor, { 0.078, 0.078, 0.141, 0.60 }),
        "and goes back when the pointer leaves")
    -- And the click opens the drawer it names.
    tile:Click()
    equal(_G.SanctuaryPanelAllowed:IsShown(), true, "clicking the tile opens its list")
    ns.ClosePanel()
    _G.SanctuaryTileBlocked:Click()
    equal(_G.SanctuaryPanelBlocked:IsShown(), true, "and the other tile opens the other")
    ns.ClosePanel()
end

-- Rule 5 of the styles section, on the tiles: what a tile writes is bounded by
-- what the count and the chevron leave it. A FontString with no width draws on
-- one line as far as it needs, and at the far end of this one is the chevron --
-- "12 ajoutes / 5 amis Battle.net" ran under it at the narrow end of the grip.
do
    local kept = SanctuaryDB.uiSize
    SanctuaryDB.uiSize = { 500, 700 }
    ns.refreshUI()
    for _, name in ipairs({ "SanctuaryTileAllowed", "SanctuaryTileBlocked" }) do
        local tile = _G[name]
        -- 12 of margin, the count, 10 to the text, then 8 of air, the chevron
        -- and its own 12: what is left is the column the two lines get.
        local room = tile:GetWidth() - 42 - tile.count:GetStringWidth()
            - tile.chevron:GetStringWidth()
        check((tile.title:GetWidth() or 0) > 0, name .. " gives its title a width of its own")
        check((tile.title:GetWidth() or 0) <= room,
            name .. " keeps the chevron's room outside its title")
        check((tile.detail:GetWidth() or 0) > 0, name .. " bounds its detail too")
        check((tile.detail:GetWidth() or 0) <= room,
            name .. " and leaves the chevron alone with it")
        -- On one line each: the tile is 46 px of exactly two lines, so a third
        -- has nowhere to go and the client cuts the sentence instead.
        equal(tile.title.__wordWrap, false, name .. " writes its title on one line")
        equal(tile.detail.__wordWrap, false, name .. " and its detail on one")
        equal(tile:GetHeight(), 46, name .. " stays the thin tile whatever it holds")
    end
    -- The French detail really is longer than that column: this is the case the
    -- bound is here for, and it is the user's own language.
    local allowed = _G.SanctuaryTileAllowed
    local frenchDetail = string.format(frenchLocale.TILE_ALLOWED_DETAIL, "12", "5")
    local column = allowed:GetWidth() - 42 - allowed.count:GetStringWidth()
        - allowed.chevron:GetStringWidth()
    check(#frenchDetail * 7 > column,
        "the French detail is wider than the room a 500 px tile leaves it ("
        .. (#frenchDetail * 7) .. " against " .. column .. ")")
    -- And the bound follows the lists rather than being a constant: a count of
    -- four digits pushes the two lines along and takes room off them.
    local before = allowed.title:GetWidth()
    allowed.count:SetText("1234")
    allowed:FitText()
    check(allowed.title:GetWidth() < before, "a longer count leaves the two lines less room")
    SanctuaryDB.uiSize = kept
    ns.refreshUI()
end

-- Decision 142: the standing note under question 3 is off the screen, and its
-- key is out of both locales -- a string nobody can reach is a translation
-- nobody will read. What is left under that question is the "already covered"
-- sentence, which is rule 4 of the styles section: a greyed question says why.
do
    equal(defaultLocale.ANTISPAM_NOTE, nil, "ANTISPAM_NOTE is gone from the default locale")
    equal(frenchLocale.ANTISPAM_NOTE, nil, "and from the French one")
    equal(defaultLocale.MANAGE_BTN, nil, "and so is the label of the button that went with the tile")
    equal(frenchLocale.MANAGE_BTN, nil, "in both locales again")
    check((ns.L["ANTISPAM_COVERED"] or "") ~= "", "the covered sentence stays")
    -- Not covered: nothing is written under question 3 at all.
    SanctuaryDB.filters.channelMode = "none"
    SanctuaryDB.filters.scope = "strangers"
    ns.refreshUI()
    equal(_G.SanctuaryAntiSpamNote:GetText(), "",
        "question 3 says nothing while it has something to say")
    -- Covered: the sentence appears.
    SanctuaryDB.filters.channelMode = "all"
    ns.refreshUI()
    equal(_G.SanctuaryAntiSpamNote:GetText(), ns.L["ANTISPAM_COVERED"],
        "and says why it is greyed once the channels are all filtered")
    equal(_G.SanctuaryQ3_yes.enabled, false, "with the cards greyed beside it")
    equal(_G.SanctuaryQ3_yes:GetAlpha(), 0.8, "and dimmed, not only greyed")
    equal(_G.SanctuaryAntiSpamInterval:GetAlpha(), 0.8, "the field beside them too")
    -- Every kind of control answers rule 4 the same way, label included: a box
    -- whose square fades while the words beside it stay bright is half a state.
    _G.SanctuaryFilter_duel:SetEnabledState(false)
    equal(_G.SanctuaryFilter_duel:GetAlpha(), 0.8, "a greyed box dims")
    equal(_G.SanctuaryFilter_duel.label:GetAlpha(), 0.8, "and so do the words beside it")
    _G.SanctuaryFilter_duel:SetEnabledState(true)
    equal(_G.SanctuaryFilter_duel:GetAlpha(), 1, "and both come back")
    equal(_G.SanctuaryFilter_duel.label:GetAlpha(), 1, "together")
    _G.SanctuaryChannel_all:SetEnabledState(false)
    equal(_G.SanctuaryChannel_all:GetAlpha(), 0.8, "a greyed dot dims as well")
    _G.SanctuaryChannel_all:SetEnabledState(true)
    SanctuaryDB.filters.channelMode = "none"
    ns.refreshUI()
end

-- Rule 4 again, on the question it was NOT applied to. Question 2 goes grey in
-- "everyone except the people I block" and used to say nothing about it: the
-- file stated the rule and honoured it under question 3 alone, so somebody who
-- cannot tell two greys apart read a question that had stopped answering and
-- nothing that said why. Decision 153 settles the sentence, in both languages.
do
    SanctuaryDB.filters.scope = "strangers"
    ns.refreshUI()
    equal(_G.SanctuaryQ2Note:GetText(), "",
        "question 2 says nothing while it still has something to ask")
    SanctuaryDB.filters.scope = "blockedOnly"
    ns.refreshUI()
    equal(_G.SanctuaryQ2Note:GetText(), ns.L["Q2_COVERED"],
        "and says why it is greyed once question 1 filters nobody but the blocked")
    equal(_G.SanctuaryQ2_all.enabled, false, "with the cards greyed beside it")
    equal(_G.SanctuaryQ2_all:GetAlpha(), 0.8, "and dimmed, not only greyed")
    check((_G.SanctuaryQ2Note:GetWidth() or 0) > 0,
        "and the sentence is given the width it folds into")
    check((defaultLocale.Q2_COVERED or "") ~= "", "the key is in the default locale")
    check((frenchLocale.Q2_COVERED or "") ~= "", "and in the French one")
    -- The two state notes are written the same way (decision 153): the small
    -- face, muted, and never italic -- the game has no italic face and a font
    -- embedded for two sentences is weight nobody asked for.
    for _, note in ipairs({ _G.SanctuaryQ2Note, _G.SanctuaryAntiSpamNote }) do
        equal(note.__fontSize, 12, "a state note is set on the small face")
        equal(note.__fontFlags, "", "and asks for no italic the game has not got")
        check(sameColor({ note.__colorR, note.__colorG, note.__colorB, note.__colorA },
            { 0.702, 0.702, 0.761, 1.0 }),
            "and is muted, not the orange of a refusal")
    end
    -- The sentences themselves, to the letter: they are texts Vincent validated
    -- and a rewrite is a decision, not a detail.
    equal(frenchLocale.Q2_COVERED,
        "Rien \195\160 choisir ici : Vous avez d\195\169cid\195\169 de ne filtrer que les personnes bloqu\195\169es.",
        "the French sentence under question 2 is the validated one")
    equal(frenchLocale.ANTISPAM_COVERED,
        "D\195\169j\195\160 couvert : Vous filtrez tout sur les canaux publics, le spam des inconnus n'y appara\195\174t jamais.",
        "and so is the one under question 3")
    equal(frenchLocale.STRICT_EXPERIMENTAL, "\226\128\148 exp\195\169rimental",
        "the experimental mention says the word and nothing more")
    SanctuaryDB.filters.scope = "strangers"
    ns.refreshUI()
end

-- Rule 2 of the styles section: nothing visible is set under 12 px. The mock-up
-- drew its descriptions at 11.5 and that is what was refused -- a description is
-- the smallest thing on the screen and the one a person most needs to read.
do
    local tooSmall = {}
    for _, widget in ipairs(createdWidgets) do
        if widget.__kind == "FontString" and widget.__fontSize
            and widget.__fontSize < 12 then
            tooSmall[#tooSmall + 1] = tostring(widget.__text or "?")
                .. " (" .. tostring(widget.__fontSize) .. ")"
        end
    end
    equal(#tooSmall, 0,
        "no visible text is set under 12 px (" .. table.concat(tooSmall, ", ") .. ")")
end

-- Decisions 141-142, the density: 24 px of air between two questions with the
-- rule halfway through it, and a title row of 22. And the cards MEASURE
-- themselves -- a description wraps over two lines at 900 px and four at 500, so
-- a flat height was room booked for the worst case on every screen and text over
-- the edge on the case nobody had measured.
do
    local kept = SanctuaryDB.uiSize
    SanctuaryDB.filters.preset = "all"
    SanctuaryDB.uiSize = { 900, 700 }
    ns.refreshUI()
    local wide = _G.SanctuaryQ1_strangers:GetHeight()
    equal(_G.SanctuaryQ1_blockedOnly:GetHeight(), wide,
        "the two answers to one question are one row, at one height")
    SanctuaryDB.uiSize = { 500, 700 }
    ns.refreshUI()
    local narrow = _G.SanctuaryQ1_strangers:GetHeight()
    check(narrow > wide, "a card grows when its description has less room to wrap in ("
        .. narrow .. " at 500, " .. wide .. " at 900)")
    -- The description itself is given the column it has to fold into, ring and
    -- padding taken off: 11 of padding, a 15 px ring, 9 of gap, 11 again.
    equal(_G.SanctuaryQ1_strangers.desc:GetWidth(),
        _G.SanctuaryQ1_strangers:GetWidth() - 46,
        "and the text it folds is given the column left beside the ring")
    -- Rule 5: the TITLE is bounded in the same column, and that is the defect
    -- this lot closes. Left free it draws on one line as far as it needs, and
    -- "Tout le monde, sauf ceux que je bloque" needs more than the column of a
    -- 500 px window has -- at no width does it fit, so it has to fold.
    equal(_G.SanctuaryQ1_strangers.title:GetWidth(),
        _G.SanctuaryQ1_strangers:GetWidth() - 46,
        "the title folds into the same column as the description")
    -- All nine of them, and not the one that was measured by hand: a card built
    -- somewhere else is a card whose title has no width.
    for _, name in ipairs({ "SanctuaryQ1_strangers", "SanctuaryQ1_blockedOnly",
        "SanctuaryQ2_all", "SanctuaryQ2_custom", "SanctuaryQ3_yes", "SanctuaryQ3_no",
        "SanctuaryQ4_silent", "SanctuaryQ4_minimal", "SanctuaryQ4_verbose" }) do
        local each = _G[name]
        check((each.title:GetWidth() or 0) > 0, name .. " bounds its title")
        equal(each.title:GetWidth(), each:GetWidth() - 46,
            name .. " bounds it to the column beside the ring")
    end
    local card = _G.SanctuaryQ1_blockedOnly
    local column = card:GetWidth() - 46
    local frenchTitle = frenchLocale.Q1_BLOCKEDONLY_TITLE
    check(#frenchTitle * 7 > column,
        "the French title really is wider than that column ("
        .. (#frenchTitle * 7) .. " against " .. column .. ")")
    -- And a folded title is MEASURED: the row grows for it, so nothing under it
    -- climbs over the second line.
    local keptTitle = card.title:GetText()
    card.title:SetText("Court")
    local oneLine = card:NeededHeight()
    card.title:SetText(frenchTitle)
    check(card:NeededHeight() > oneLine,
        "and the card answers a taller height once its title folds ("
        .. card:NeededHeight() .. " against " .. oneLine .. ")")
    card.title:SetText(keptTitle)
    ns.refreshUI()

    -- The air between two questions, measured on the screen itself.
    SanctuaryDB.uiSize = { 780, 700 }
    ns.refreshUI()
    local _, _, _, _, firstCard = _G.SanctuaryQ1_strangers:GetPoint()
    local bottom = firstCard - _G.SanctuaryQ1_strangers:GetHeight()
    local _, _, _, _, secondCard = _G.SanctuaryQ2_all:GetPoint()
    equal(bottom - secondCard, 24 + 22,
        "24 px of air between two questions, then the title row of the next")
    SanctuaryDB.uiSize = kept
    ns.refreshUI()
end

-- Decision 137: the Trust tooltip is a field of explanation, not a second half
-- of its own label -- "un tooltip n'est pas une suite au label". The sentence
-- Vincent validated says what happens, for how long, and how to undo it.
do
    local trust = _G.SanctuaryAutoTrust
    trust:GetScript("OnEnter")(trust)
    local shown = tostring(rawget(GameTooltip, "__lastText") or "")
    equal(shown, ns.L["ADV_TRUST_DESC"], "hovering the box shows the explanation")
    check(shown:find("5 minutes", 1, true) ~= nil, "which says how long it takes")
    check(shown:find(ns.L["TILE_ALLOWED"], 1, true) ~= nil, "where the player ends up")
    check(#shown > 150, "and it is a paragraph, not a trailing clause")
    trust:GetScript("OnLeave")(trust)
    -- The label carries it too, since the label is half the target now.
    trust.labelHit:GetScript("OnEnter")(trust.labelHit)
    equal(tostring(rawget(GameTooltip, "__lastText") or ""), ns.L["ADV_TRUST_DESC"],
        "and so do the words beside it")
    trust.labelHit:GetScript("OnLeave")(trust.labelHit)
end

-- Automatic trust left Advanced for the home screen, decision 103.
check(_G.SanctuaryAutoTrust:GetParent() == _G.SanctuaryTabContent_protection,
    "automatic trust is a row on the home screen")
_G.SanctuaryAutoTrust:Click()
equal(SanctuaryDB.filters.autoTrust, true, "and it still writes its own key")
_G.SanctuaryAutoTrust:Click()
equal(SanctuaryDB.filters.autoTrust, false, "both ways")

end)()

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
-- Question 3: the anti-spam of the public channels
-- ---------------------------------------------------------------------------

do

local yes, no = _G.SanctuaryQ3_yes, _G.SanctuaryQ3_no
local interval, list = _G.SanctuaryAntiSpamInterval, _G.SanctuaryAntiSpamIntervalList
check(yes ~= nil and no ~= nil, "question 3 offers the same two cards as the others")
check(interval ~= nil and list ~= nil, "with a window under them")

-- Out of the box: opted into, never out of, and five minutes.
ns.setAntiSpamEnabled(false)
ns.setAntiSpamInterval(300)
ns.refreshUI()
equal(ns.isAntiSpamEnabled(), false, "the anti-spam starts off")
equal(interval.value:GetText(), ns.L["ANTISPAM_D_5M"], "and its window reads five minutes")
equal(interval.enabled, false, "the window is not clickable while the answer is No")

yes:Click()
equal(SanctuaryDB.antiSpam.enabled, true, "the first card switches the anti-spam on")
equal(interval.enabled, true, "and the window becomes clickable")
no:Click()
equal(SanctuaryDB.antiSpam.enabled, false, "the second card switches it off")
yes:Click()

-- The eight windows, in the order the menu shows them, and clicking one writes
-- it.
equal(#interval.rows, 8, "the menu offers eight windows")
local EXPECTED = { "ANTISPAM_D_5M", "ANTISPAM_D_10M", "ANTISPAM_D_30M", "ANTISPAM_D_1H",
    "ANTISPAM_D_2H", "ANTISPAM_D_4H", "ANTISPAM_D_12H", "ANTISPAM_D_24H" }
for index, key in ipairs(EXPECTED) do
    equal(interval.rows[index].label:GetText(), ns.L[key],
        "window " .. index .. " of the menu is " .. key)
end
equal(list:IsShown(), false, "the menu starts closed")
interval:Click()
equal(list:IsShown(), true, "clicking the field opens it")
interval:Click()
equal(list:IsShown(), false, "and clicking it again closes it")
interval:Click()
interval.rows[4]:Click()
equal(SanctuaryDB.antiSpam.intervalSeconds, 3600, "picking a row writes the window")
equal(list:IsShown(), false, "and closes the menu")
equal(interval.value:GetText(), ns.L["ANTISPAM_D_1H"], "the field shows what was picked")
-- Changing screen takes the list with it: it draws over everything.
interval:Click()
equal(list:IsShown(), true, "the menu is open again")
_G["SanctuaryTab_journal"]:Click()
equal(list:IsShown(), false, "changing tab closes it")
_G["SanctuaryTab_protection"]:Click()

-- Already covered. Nothing is clickable, the note says why, and not one answer
-- is overwritten -- going back finds them exactly as they were.
SanctuaryDB.filters.preset = "custom"
SanctuaryDB.filters.channelMode = "all"
ns.refreshUI()
equal(ns.isChannelSpamCovered(), true, "filtering every channel covers the ground")
equal(yes.enabled, false, "the first card is greyed out")
equal(no.enabled, false, "and so is the second")
equal(interval.enabled, false, "and the window with them")
check((yes.title.__colorR or 1) < 1, "and drawn as one")
yes:Click()
no:Click()
interval:Click()
equal(SanctuaryDB.antiSpam.enabled, true, "a click on a greyed card writes nothing")
equal(SanctuaryDB.antiSpam.intervalSeconds, 3600, "and the window keeps what was chosen")
equal(list:IsShown(), false, "and the menu does not open")

-- And "Everyone except the people I block" does NOT cover it: nothing is
-- filtered in the channels there, so the question has all its meaning.
SanctuaryDB.filters.scope = "blockedOnly"
ns.refreshUI()
equal(ns.isChannelSpamCovered(), false, "blocking only a list covers nothing")
equal(yes.enabled, true, "so question 3 stays live")
SanctuaryDB.filters.scope = "strangers"
SanctuaryDB.filters.channelMode = "none"
ns.refreshUI()
equal(yes.enabled, true, "and it comes back live when the channels are let through")
equal(SanctuaryDB.antiSpam.enabled, true, "with the answer that was given")
equal(interval.value:GetText(), ns.L["ANTISPAM_D_1H"], "and the window that was picked")

-- Five questions, numbered 1 to 5 and stacked in that order. The renumbering is
-- the half of this chantier a later visual pass would otherwise trip on: a
-- screen where "q3" means question 4 sends the next reader to the wrong widget.
do
    local protectionContent = _G["SanctuaryTabContent_protection"]
    local seen = {}
    local function walk(widget)
        for _, child in ipairs(widget.__children or {}) do
            if child.__kind == "FontString" then seen[tostring(child.__text)] = true end
            walk(child)
        end
    end
    walk(protectionContent)
    for _, number in ipairs({ "1", "2", "3", "4", "5" }) do
        check(seen[number], "the screen numbers a question " .. number)
    end
    check(not seen["6"], "and stops at five")

    local previousY
    local ordered = {
        _G.SanctuaryQ1_strangers, _G.SanctuaryQ2_all, _G.SanctuaryQ3_yes,
        _G.SanctuaryQ4_silent, _G.SanctuaryTileAllowed,
    }
    for index, widget in ipairs(ordered) do
        local _, relativeTo, _, _, offset = widget:GetPoint()
        -- The first card of each question is anchored against the screen
        -- itself, so the five offsets are comparable with one another.
        equal(relativeTo, protectionContent,
            "the first card of question " .. index .. " hangs from the screen")
        if previousY then
            check(offset < previousY, "and question " .. index .. " sits under the one before it")
        end
        previousY = offset
    end
end

ns.setAntiSpamEnabled(false)
ns.setAntiSpamInterval(300)
ns.refreshUI()

end

-- ---------------------------------------------------------------------------
-- Question 4
-- ---------------------------------------------------------------------------

_G.SanctuaryQ4_verbose:Click()
equal(SanctuaryDB.notifications.mode, "verbose", "the third card writes the notification mode")
_G.SanctuaryQ4_minimal:Click()
equal(SanctuaryDB.notifications.mode, "minimal", "the second card too")
_G.SanctuaryQ4_silent:Click()
equal(SanctuaryDB.notifications.mode, "silent", "and the first one puts it back to silence")

-- ---------------------------------------------------------------------------
-- Question 5: the tiles, and the name tester
-- ---------------------------------------------------------------------------

guildMembers = { "Guildmate-TestRealm", "Officer-TestRealm" }
inGuild = true
bnetFriends = {
    -- With a realm, because that is the ordinary case and the one that used to
    -- leak: the realm belongs in the key that tells two namesakes apart, never
    -- on the line the panel prints.
    { accountName = "RealFriend#1234", bnetAccountID = 77,
      gameAccountInfo = { characterName = "Bnetchar", realmName = "Ysondre" } },
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
check(testAnswerFor("RealFriend#1234"):find("RealFriend#1234-", 1, true) == nil,
    "while the account itself gets no realm bolted on: an account is on none")
check(testAnswerFor("Officer-TestRealm"):find(ns.L["LIST_GUILD"], 1, true) ~= nil,
    "a guild member is answered as a guild member")
check(testAnswerFor("Xxxxxxx-Ysondre"):find(ns.L["LIST_BLOCKED"], 1, true) ~= nil,
    "a blocked name is answered as blocked")
check(testAnswerFor("Superspam"):find("spam", 1, true) ~= nil,
    "a pattern match names the pattern")
-- Answered on the qualified name, never on the bare one: typing "Zorglub" on
-- TestRealm asks about Zorglub-TestRealm, and decision 119 makes that the only
-- character the answer covers -- so the sentence has to say which one it is.
check(testAnswerFor("Zorglub"):find(string.format(ns.L["TEST_UNKNOWN_BLOCKED"], "Zorglub-TestRealm"), 1, true) ~= nil,
    "an unknown name is blocked while question 1 filters strangers")
SanctuaryDB.filters.scope = "blockedOnly"
check(testAnswerFor("Zorglub"):find(string.format(ns.L["TEST_UNKNOWN_ALLOWED"], "Zorglub-TestRealm"), 1, true) ~= nil,
    "and allowed in the other mode")
SanctuaryDB.filters.scope = "strangers"
-- The last line of the board: blocked wins over a trust source, and the answer
-- names the list it overrides rather than silently dropping it. A guild mate,
-- not a Battle.net friend -- one of those cannot be blocked at all now.
ns.addBlocked("Officer-TestRealm")
do
    local overriddenAnswer = testAnswerFor("Officer-TestRealm")
    check(overriddenAnswer:find(
        string.format(ns.L["TEST_ALWAYS_BLOCKED"], "Officer-TestRealm", ""):sub(1, 24), 1, true) ~= nil,
        "a blocked guild mate is answered as blocked even so")
    check(overriddenAnswer:find(ns.L["LIST_GUILD"], 1, true) ~= nil,
        "and the answer still names the list it overrides")
end
ns.removeBlocked(ns.normalizeCharacterKey("Officer-TestRealm"))
equal(ns.describeAccessDecision("").valid, false, "an empty field asks nothing")

-- The tester answers a question about the lists, so it has to be re-asked every
-- time a list moves. Decision 101: "quand on agit dans un des drawers de gerer,
-- le pseudo teste n'est pas re-teste, on est oblige d'enlever ou ajouter une
-- lettre". The name stays in the field; the answer follows the lists.
testAnswerFor("Freshname")
check(_G.SanctuaryTestAnswer:GetText():find(
    string.format(ns.L["TEST_UNKNOWN_BLOCKED"], "Freshname-TestRealm"), 1, true) ~= nil,
    "an unknown name is answered as unknown")
ns.addAllowed("Freshname")
ns.refreshUI()
equal(_G.SanctuaryTestInput:GetText(), "Freshname", "adding a name leaves the field alone")
check(_G.SanctuaryTestAnswer:GetText():find(ns.L["LIST_MANUAL"], 1, true) ~= nil,
    "and the answer is recomputed without a keystroke")
ns.removeAllowed("freshname-testrealm")
ns.refreshUI()
check(_G.SanctuaryTestAnswer:GetText():find(
    string.format(ns.L["TEST_UNKNOWN_BLOCKED"], "Freshname-TestRealm"), 1, true) ~= nil,
    "and removing it puts the answer back")

-- The cross inside the field, decision 101. It shows only when there is
-- something to clear, and clearing it takes the answer with it.
do
    local testBox = _G.SanctuaryTestInput
    check(testBox.clear ~= nil, "the tester carries a cross of its own")
    equal(testBox.clear:IsShown(), true, "which is offered while the field holds a name")
    testBox.clear:Click()
    equal(testBox:GetText(), "", "clicking it empties the field")
    equal(testBox.clear:IsShown(), false, "and the cross goes with the name")
    equal(_G.SanctuaryTestAnswer:GetText(), "", "and the answer with it")
    -- The three list fields do not get one: they empty themselves on Enter, and
    -- a cross there would answer a question nobody asked.
    equal(_G.SanctuaryBlockedAddInput.clear, nil, "a list field carries no cross")
end

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
-- Folded, the groups are four counts and nothing else: decision 102 took the
-- two paragraphs out from between the headers, and they come back on unfolding.
check(rendered:find(ns.L["BNET_NOT_BLOCKED"], 1, true) == nil,
    "a folded Battle.net group is a count, not a paragraph")
check(rendered:find(ns.L["WL_TRUST_HINT"], 1, true) == nil,
    "and neither is the automatic trust group")

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
check(rendered:find(string.format(ns.L["WL_BNET_ROW"], "Bnetchar", "RealFriend#1234"), 1, true) ~= nil,
    "the line reads 'Character . Account', the way the mock-up draws it")
check(rendered:find("Bnetchar-Ysondre", 1, true) == nil,
    "the realm stays in the lookup key and off the line")
check(rendered:find(string.format(ns.L["WL_BNET_OFFLINE"], "OfflineFriend#5678"), 1, true) ~= nil,
    "and an offline friend by account alone")
-- And the sentence comes back with the list it is about.
check(rendered:find(ns.L["BNET_NOT_BLOCKED"], 1, true) ~= nil,
    "unfolding the group says Sanctuary never blocks on Battle.net")
check(rendered:find(ns.L["BNET_NOT_BLOCKED_HOW"], 1, true) == nil,
    "in its short form: nothing on this panel blocks anybody")

-- Decision 110: the friends who are there right now come first, and in the
-- add-on's own green; the offline ones after, in grey. "OfflineFriend#5678"
-- sorts before "RealFriend#1234" alphabetically, so a list still in name order
-- is a list this check catches.
do
    local group
    for _, candidate in ipairs(ns.getAutoWhitelistGroups()) do
        if candidate.source == "bnet" then group = candidate end
    end
    check(group ~= nil and #group.entries >= 2, "the Battle.net group has both kinds")
    check(group.entries[1].character ~= nil, "an online friend is at the top of the group")
    check(group.entries[#group.entries].character == nil, "and an offline one at the bottom")

    local onlineRow = findRow(allowedPanel, "Bnetchar")
    local offlineRow = findRow(allowedPanel, "OfflineFriend#5678")
    check(onlineRow ~= nil and offlineRow ~= nil, "both lines are on screen")
    equal(onlineRow.label.__colorR, 0.4, "the online line wears the active green")
    equal(onlineRow.label.__colorG, 0.902, "the online line wears the active green")
    check(offlineRow.label.__colorG ~= 0.902, "and the offline line does not")
end

-- Adding through the field, removing through the cross, and Undo.
_G.SanctuaryAllowedAddInput:SetText("Titi")
findRow(allowedPanel, ns.L["PANEL_ADD_BTN"]):Click()
check(SanctuaryDB.manualWhitelist["titi-testrealm"] ~= nil, "the field adds a name")
ns.refreshUI()
local titiChip = findRow(allowedPanel, "Titi")
check(titiChip ~= nil, "the added name gets a chip")
-- Typed bare, shown with its realm. The key carries it (decision 119), so the
-- panel has to say it: a chip reading "Titi" alone would promise a person that
-- every Titi there is has been let through, which is not what was written.
equal(titiChip.label.__text, "Titi-TestRealm", "and the chip names the realm it was engraved on")
titiChip:GetScript("OnEnter")(titiChip)
check(tostring(rawget(GameTooltip, "__lastText") or ""):find("Titi-TestRealm", 1, true) ~= nil,
    "the tooltip repeats it in full, for a chip the row had to cut short")
titiChip.remove:Click()
equal(SanctuaryDB.manualWhitelist["titi-testrealm"], nil, "the cross removes it without asking")
check(_G.SanctuaryUndoLine:IsShown(), "and offers to undo")
_G.SanctuaryUndoLine.button:Click()
check(SanctuaryDB.manualWhitelist["titi-testrealm"] ~= nil, "undo puts it back")
equal(_G.SanctuaryUndoLine:IsShown(), false, "and the offer goes away")

-- A removal that is not undone expires instead of coming back.
titiChip = findRow(allowedPanel, "Titi")
titiChip.remove:Click()
equal(SanctuaryDB.manualWhitelist["titi-testrealm"], nil, "removed again")
runTimers(2)
equal(SanctuaryDB.manualWhitelist["titi-testrealm"], nil, "an expired undo offer restores nothing")

do

-- "Added by you" and "Automatically trusted" read the same table: a contact the
-- five-minute group rule added carries source = "trust". Listed in both, the
-- tester sees one name in two places and a counter that credits her with a name
-- she never typed. Automatic trust fills that table on its own, in group after
-- group, so the miscount appears without anybody typing anything.
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

ns.removeAllowed("handy-testrealm")
ns.removeAllowed("trusty-testrealm")
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

-- A change that moves no count at all still has to reach the panel. The
-- signature carried the manual keys and the totals only, so a guild member
-- replaced at constant strength -- or a friend who logs in and gives his line
-- its character half -- left the tick nothing to compare, and the panel went on
-- showing a roster that no longer existed.
do
    local countsBefore = ns.getListCounts().allowed
    guildMembers = { "Guildmate-TestRealm", "Officer-TestRealm", "Replacement-TestRealm" }
    fire("GUILD_ROSTER_UPDATE")
    equal(ns.getListCounts().allowed.guild, countsBefore.guild,
        "the guild is the same strength as before")
    runTickers()
    local shown = panelRowTexts(allowedPanel)
    check(shown:find("Replacement-TestRealm", 1, true) ~= nil,
        "a guild member replaced at constant strength appears on the tick")
    check(shown:find("Newcomer-TestRealm", 1, true) == nil,
        "and the one he replaced is gone from the list")

    -- Same again on the Battle.net side: the account was already listed, so no
    -- count moves; only the character half of the line is new.
    check(shown:find(string.format(ns.L["WL_BNET_OFFLINE"], "OfflineFriend#5678"), 1, true) ~= nil,
        "the second friend is still listed as offline")
    bnetFriends[2].gameAccountInfo = { characterName = "Offchar", realmName = "Hyjal" }
    fire("BN_FRIEND_INFO_CHANGED")
    equal(ns.getListCounts().allowed.bnet, countsBefore.bnet,
        "a friend logging in adds no account to the count")
    runTickers()
    shown = panelRowTexts(allowedPanel)
    check(shown:find(string.format(ns.L["WL_BNET_ROW"], "Offchar", "OfflineFriend#5678"), 1, true) ~= nil,
        "yet the tick shows the character he just logged in on")
    bnetFriends[2].gameAccountInfo = nil
    fire("BN_FRIEND_INFO_CHANGED")
    runTickers()
end

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
ns.removeAllowed("toto-testrealm")
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
check(panelRowTexts(blockedPanel):find(ns.L["BNET_NOT_BLOCKED"], 1, true) ~= nil,
    "and says a Battle.net friend cannot be blocked from here")
check(panelRowTexts(blockedPanel):find(ns.L["BNET_NOT_BLOCKED_HOW"], 1, true) ~= nil,
    "with the way out, which is the half that matters where somebody is refused")

_G.SanctuaryBlockedAddInput:SetText("Toto")
check(ns.addBlocked("Toto"), "a name already in the allowed list can be blocked")
equal(SanctuaryDB.manualWhitelist["toto-testrealm"], nil,
    "and blocking it takes it out of the allowed list, decision 104")
-- Typed with no realm, listed with one. The blocked list has carried the realm
-- in its key since 1.0.0 and showed the bare pseudo anyway, so the panel read
-- "Toto" over an entry that only ever blocked the Toto of one realm.
ns.refreshUI()
check(panelRowTexts(blockedPanel):find("Toto-TestRealm", 1, true) ~= nil,
    "a blocked name typed bare is listed with the realm it was engraved on")
local blockedNow, blockedReason = ns.getCharacterDecision("Toto")
equal(blockedNow, true, "the decision changes immediately")
equal(blockedReason, "blocked_name", "and names the list that decided")
ns.removeBlocked(ns.normalizeCharacterKey("Toto"))
equal(select(1, ns.getCharacterDecision("Toto")), true,
    "removing it leaves an unknown name, which the strangers mode still filters")
ns.addAllowed("Toto")
equal(select(1, ns.getCharacterDecision("Toto")), false, "allowing it again lets them through")

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
-- A label never runs under the cross, and a hint never runs out of its field
-- ---------------------------------------------------------------------------

-- Decision 99, both halves. The chip width was `24 + #label * 7` clamped to the
-- row: a byte count on a UTF-8 string at a made-up seven pixels a character, so
-- a long pseudo got a chip narrower than its own text and the cross, pinned to
-- the right edge, sat on the letters. The hint was a FontString with no width at
-- all and ran past the field, under the Add button.
--
-- A scope of its own: the enclosing function is at Lua's ceiling of 200 locals.
;(function()

ns.OpenPanel("blocked")
local panel = _G.SanctuaryPanelBlocked

-- Room for the cross is not negotiable, whatever the name measures. The label
-- must be BOUNDED -- a FontString left at width 0 draws at its natural size,
-- which is precisely how a long pseudo ended up written under the cross -- and
-- what it is bounded to must leave the chrome alone.
local function checkChip(label, note)
    local chip = findRow(panel, label)
    check(chip ~= nil, note .. " has a chip")
    if not chip then return end
    local room = chip:GetWidth() - 32
    check((chip.label:GetWidth() or 0) > 0, note .. " gives its label a width of its own")
    check((chip.label:GetWidth() or 0) <= room,
        note .. " keeps the cross's room outside its label")
    check((chip.label:GetWidth() or 0) >= math.min(chip.label:GetStringWidth(), room),
        note .. " still shows as much of itself as the chip can hold")
    check(chip:GetWidth() <= panel:GetWidth() - 40,
        note .. " stays inside the row it is laid out on")
    equal(chip.label.__wordWrap, false, note .. " is written on one line")
end

ns.addBlocked("Ana")
ns.addBlocked("Averylongpseudonameindeed")
ns.refreshUI()
checkChip("Ana", "a short name")
checkChip("Averylongpseudonameindeed", "a long name")

local shortChip = findRow(panel, "Ana")
local longChip = findRow(panel, "Averylongpseudonameindeed")
check(longChip:GetWidth() > shortChip:GetWidth(), "a longer name gets a wider chip")

-- Longer than the row itself: the label is cut, the chip is not overrun.
ns.removeBlocked(ns.normalizeCharacterKey("Averylongpseudonameindeed"))
local huge = string.rep("Verylongname", 12)
ns.addBlocked(huge)
ns.refreshUI()
local hugeChip = findRow(panel, huge)
check(hugeChip ~= nil, "a name longer than the row still gets a chip")
check(hugeChip:GetWidth() <= panel:GetWidth() - 40,
    "and the chip is no wider than the row")
check((hugeChip.label:GetWidth() or 0) > 0
    and hugeChip.label:GetWidth() <= hugeChip:GetWidth() - 32,
    "and the cross still has its room, which is the overlap that was reported")
check(hugeChip.label:GetWidth() < hugeChip.label:GetStringWidth(),
    "the name itself is cut rather than written past the chip")
ns.removeBlocked(ns.normalizeCharacterKey(huge))
ns.removeBlocked(ns.normalizeCharacterKey("Ana"))
ns.refreshUI()

-- The hints. Both fields, both panels: a hint is bounded by the box it sits in.
for _, name in ipairs({ "SanctuaryBlockedAddInput", "SanctuaryPatternAddInput",
    "SanctuaryAllowedAddInput" }) do
    local box = _G[name]
    check(box.hint:GetWidth() > 0 and box.hint:GetWidth() <= box:GetWidth(),
        name .. " keeps its hint inside the field")
    equal(box.hint.__wordWrap, false, name .. " keeps its hint on one line")
end

-- And the pattern hint is short enough to be read whole rather than cut, which
-- is what decision 99 actually asked for.
check(#ns.L["PANEL_PATTERN_HINT"] * 7 <= _G.SanctuaryPatternAddInput.hint:GetWidth(),
    "the pattern hint fits the field it is written in")

ns.ClosePanel()

end)()

-- ---------------------------------------------------------------------------
-- The two lists are exclusive, and the strip says so
-- ---------------------------------------------------------------------------

-- Decision 104. A name written into one list leaves the other, and that removal
-- gets the undo strip naming the list it left. Annuler puts the WHOLE gesture
-- back: undoing half of it would leave the name in both lists again.
--
-- A scope of its own: the enclosing function is at Lua's ceiling of 200 locals.
;(function()

ns.OpenPanel("blocked")
local nameBox = _G.SanctuaryBlockedAddInput
local panel = _G.SanctuaryPanelBlocked
local undo = _G.SanctuaryUndoLine

ns.addAllowed("Bothways")
equal(SanctuaryDB.manualWhitelist["bothways-testrealm"] ~= nil, true, "a name is allowed by hand")

nameBox:SetText("Bothways")
panel.nameBtn:Click()
local blockedKey = ns.normalizeCharacterKey("Bothways")
check(SanctuaryDB.blockedNames[blockedKey] ~= nil, "blocking it writes the blocked entry")
equal(SanctuaryDB.manualWhitelist["bothways-testrealm"], nil, "and takes the allowed one away")
equal(undo:IsShown(), true, "the strip says a name was displaced")
check(undo.label:GetText():find("Bothways-TestRealm", 1, true) ~= nil,
    "naming it, realm and all, like the two panels it moved between")
check(undo.label:GetText():find(ns.L["TILE_ALLOWED"], 1, true) ~= nil,
    "and the list it came out of")
equal(nameBox.note:IsShown(), false, "and nothing was refused")

undo.button:Click()
equal(SanctuaryDB.blockedNames[blockedKey], nil, "Annuler takes the new entry back out")
check(SanctuaryDB.manualWhitelist["bothways-testrealm"] ~= nil, "and puts the old one back")
equal(undo:IsShown(), false, "the offer goes with it")

-- The other direction, through the allowed panel.
ns.ClosePanel()
ns.addBlocked("Otherway")
ns.OpenPanel("allowed")
local allowedBox = _G.SanctuaryAllowedAddInput
allowedBox:SetText("Otherway")
_G.SanctuaryPanelAllowed.addBtn:Click()
check(SanctuaryDB.manualWhitelist["otherway-testrealm"] ~= nil, "allowing a blocked name writes the entry")
equal(SanctuaryDB.blockedNames[ns.normalizeCharacterKey("Otherway")], nil,
    "and takes the blocked one away")
check(undo.label:GetText():find(ns.L["TILE_BLOCKED"], 1, true) ~= nil,
    "the strip names the blocked list this time")
undo.button:Click()
check(SanctuaryDB.blockedNames[ns.normalizeCharacterKey("Otherway")] ~= nil,
    "and Annuler puts the block back")
equal(SanctuaryDB.manualWhitelist["otherway-testrealm"], nil, "taking the allowance away with it")
ns.removeBlocked(ns.normalizeCharacterKey("Otherway"))
ns.removeAllowed("bothways-testrealm")
ns.ClosePanel()

-- The right-click menu writes through the same two functions, so it inherits
-- both rules -- and says what happened, since there is no field to put a
-- sentence under. Decisions 100 and 104.
_G.SanctuaryTab_protection:Click()
ns.addAllowed("Menuboth")
local entries = ns.buildPlayerMenuEntries({ name = "Menuboth", server = "TestRealm" })
equal(#entries, 2, "the menu offers its two entries")
entries[2].action()
equal(SanctuaryDB.manualWhitelist["menuboth-testrealm"], nil,
    "blocking from the menu takes the name out of the allowed list too")
equal(undo:IsShown(), true, "and offers the same undo")
undo.button:Click()
check(SanctuaryDB.manualWhitelist["menuboth-testrealm"] ~= nil, "which puts both halves back")
ns.removeAllowed("menuboth-testrealm")

-- A Battle.net friend refused from the menu says so out loud: nothing is
-- written, and the person is told where to do it instead.
do
    local printed = {}
    local savedPrint = ns.printMsg
    ns.printMsg = function(text) printed[#printed + 1] = text end
    local bnetEntries = ns.buildPlayerMenuEntries({ name = "Bnetchar", server = "Ysondre" })
    bnetEntries[2].action()
    ns.printMsg = savedPrint
    equal(SanctuaryDB.blockedNames[ns.normalizeCharacterKey("Bnetchar-Ysondre")], nil,
        "nothing is written for a Battle.net friend")
    equal(#printed, 1, "and the refusal is said once")
    equal(printed[1], ns.L["BNET_NOT_BLOCKED"] .. " " .. ns.L["BNET_NOT_BLOCKED_HOW"],
        "with the Battle.net sentence, both halves")
end

end)()

-- ---------------------------------------------------------------------------
-- Saying no, and saying why
-- ---------------------------------------------------------------------------

-- A refused entry used to be refused in silence: the field emptied itself and
-- nothing appeared, so the only reading available was "the add-on is broken".
-- The rule of what is refused lives in the three writers, which hand back a
-- fourth value naming the refusal; the panel picks a sentence from that code and
-- never works the answer out a second time.
--
-- A scope of its own: the enclosing function is at Lua's ceiling of 200 locals.
;(function()

-- The three writers, first. Only the refusals that can be explained get a fourth
-- value.
local ok, key, data, refusal = ns.addAllowed("-")
equal(ok, false, "the allowed field refuses a name with nothing left of it")
equal(refusal, "name", "and says which sentence answers it")

ok, key, data, refusal = ns.addBlocked("-")
equal(ok, false, "the blocked field refuses it too")
equal(refusal, "name", "with the same sentence")

ok, key, data, refusal = ns.addBlocked("Real Friend#1234")
equal(ok, false, "the blocked field refuses a BattleTag")
equal(refusal, "account", "with the Battle.net sentence, not the pseudo one")

ok, key, data, refusal = ns.addPattern("to.to")
equal(ok, false, "the pattern field refuses punctuation")
equal(refusal, "pattern", "with the pattern sentence")

-- A BattleTag pasted into the PATTERN field gets the pattern sentence, not the
-- Battle.net one: what is wrong there is the shape of the pattern.
ok, key, data, refusal = ns.addPattern("Toto-Ysondre")
equal(ok, false, "and a name with a realm, which would match nobody")
equal(refusal, "pattern", "with the same sentence")
ok, key, data, refusal = ns.addPattern("Truc#1234")
equal(refusal, "pattern", "and a BattleTag in the pattern field is a pattern problem")

-- The two silent refusals. A duplicate hands the existing record back, the way
-- it always did, and says nothing: the label is already on screen.
ok = ns.addBlocked("Dupprobe")
equal(ok, true, "a name goes in once")
ok, key, data, refusal = ns.addBlocked("Dupprobe")
equal(ok, false, "and not twice")
check(key ~= nil and data ~= nil, "the duplicate still hands back the record it found")
equal(refusal, nil, "and says nothing, the label being on screen already")
ns.removeBlocked(key)

-- A field with nothing in it: nothing was typed, so there is nothing to answer.
ok, key, data, refusal = ns.addBlocked("   ")
equal(ok, false, "a blank field writes nothing")
equal(refusal, nil, "and is answered with silence")
equal(select(4, ns.addAllowed("")), nil, "an empty allowed field too")
equal(select(4, ns.addPattern("   ")), nil, "and an empty pattern field")

-- ... and now the screen. Both ways in: the button and the Enter key. Six
-- bodies used to do this, two per field, which is precisely the shape this
-- release went after.
ns.OpenPanel("blocked")
local panel = _G.SanctuaryPanelBlocked
local nameBox = _G.SanctuaryBlockedAddInput
local patternBox = _G.SanctuaryPatternAddInput
local beforeNames = ns.getListCounts().blocked.names

nameBox:SetText("-")
panel.nameBtn:Click()
equal(nameBox.note:GetText(), ns.L["REFUSED_NAME"], "the button says why a name was refused")
equal(nameBox.note:IsShown(), true, "the sentence is on screen")
equal(nameBox:GetText(), "", "the field is emptied all the same")
equal(ns.getListCounts().blocked.names, beforeNames, "and nothing was written to the list")
check(panelRowTexts(panel):find(ns.L["REFUSED_NAME"], 1, true) ~= nil,
    "and the sentence is under the field it answers")

-- The exact string step D.7b asks for, on the exact gesture it asks for, because
-- that is the one that came back "aucun retour, blocage ou autre": a BattleTag
-- with no space in it, pasted into the Pseudos field, submitted with the button.
nameBox:SetText("Truc#1234")
panel.nameBtn:Click()
equal(nameBox.note:GetText(),
    ns.L["BNET_NOT_BLOCKED"] .. " " .. ns.L["BNET_NOT_BLOCKED_HOW"],
    "the button says why Truc#1234 was refused")
equal(nameBox.note:IsShown(), true, "and the sentence is on screen")
equal(ns.getListCounts().blocked.names, beforeNames, "with nothing written to the list")
check(panelRowTexts(panel):find(ns.L["BNET_NOT_BLOCKED_HOW"], 1, true) ~= nil,
    "and the way out is on screen with it")

nameBox:SetText("Real Friend#1234")
nameBox:GetScript("OnEnterPressed")(nameBox)
-- Both halves where somebody is being refused: the second one is the way out,
-- and a refusal with no way out is half an answer. Decision 102.
equal(nameBox.note:GetText(),
    ns.L["BNET_NOT_BLOCKED"] .. " " .. ns.L["BNET_NOT_BLOCKED_HOW"],
    "the Enter key says why a BattleTag was refused, and what to do instead")
equal(nameBox:GetText(), "", "and empties the field")
equal(ns.getListCounts().blocked.names, beforeNames, "still writing nothing")

patternBox:SetText("to.to")
panel.patternBtn:Click()
equal(patternBox.note:GetText(), ns.L["REFUSED_PATTERN"], "the pattern field answers on the button")
patternBox:SetText("to.to")
patternBox:GetScript("OnEnterPressed")(patternBox)
equal(patternBox.note:GetText(), ns.L["REFUSED_PATTERN"], "and on the Enter key")

-- It goes on its own, after the same six seconds the undo strip keeps.
runTimers(3)
equal(nameBox.note:GetText(), "", "the sentence goes on its own")
equal(nameBox.note:IsShown(), false, "and takes its room back")
equal(patternBox.note:GetText(), "", "both of them")

-- Two refusals a second apart leave two timers running, and the older one must
-- not wipe the sentence the newer one just put up. Timers are caught here rather
-- than run, because running them all at once cannot tell the two apart.
local savedAfter = C_Timer.After
local queued = {}
C_Timer.After = function(_, callback) queued[#queued + 1] = callback end
nameBox:SetText("-")
panel.nameBtn:Click()
nameBox:SetText("Real Friend#1234")
panel.nameBtn:Click()
C_Timer.After = savedAfter
equal(#queued, 2, "two refusals leave two timers behind")
queued[1]()
equal(nameBox.note:GetText(),
    ns.L["BNET_NOT_BLOCKED"] .. " " .. ns.L["BNET_NOT_BLOCKED_HOW"],
    "the older timer leaves the newer sentence alone")
queued[2]()
equal(nameBox.note:GetText(), "", "and its own timer is what clears it")

-- An entry that goes in says nothing at all, and clears whatever was there.
nameBox:SetText("-")
panel.nameBtn:Click()
check(nameBox.note:IsShown(), "a refusal is showing")
nameBox:SetText("Acceptedname")
panel.nameBtn:Click()
equal(nameBox.note:GetText(), "", "an accepted entry says nothing")
equal(nameBox.note:IsShown(), false, "and takes the refusal off the screen")
equal(ns.getListCounts().blocked.names, beforeNames + 1, "having written the name")

-- Closing the window drops the sentence with the text it was about.
nameBox:SetText("-")
panel.nameBtn:Click()
check(nameBox.note:IsShown(), "a refusal is showing again")
mainFrame:Hide()
equal(nameBox.note:GetText(), "", "closing the window clears the refusal")
equal(nameBox.note:IsShown(), false, "sentence and room together")
mainFrame:Show()

-- The width the sentence gets, and the room it is given. A refusal that folds is
-- worse than one that is cut: it comes down over the first row of chips under
-- the field. So the note runs the panel's own text width -- PANEL_WIDTH - 40,
-- the 500 px the descriptions above it already use -- and not the 250 px of the
-- box it hangs from.
ns.OpenPanel("allowed")
local allowedBox = _G.SanctuaryAllowedAddInput
equal(allowedBox.note:GetWidth(), 500, "the allowed field answers at the panel's width")
equal(nameBox.note:GetWidth(), 500, "the blocked names field answers at the panel's width")
equal(patternBox.note:GetWidth(), 500, "and the pattern field too")

-- ... and the six strings measured against it, because the strings are what
-- changes. 6.5 px is a majorant for one character of FONT_BODY in a latin face;
-- characters are counted, not bytes, French being stored as escaped UTF-8. Each
-- field reserves the lines its own worst case needs: one under the two name
-- fields and the pattern field, two under the blocked names, the only field the
-- Battle.net sentence can answer in. This check is what fails the day one of the
-- six sentences grows past the room its field keeps.
local NOTE_PIXELS, NOTE_CHAR_PX = 500, 6.5
local function noteLines(text)
    local characters = select(2, text:gsub("[^\128-\191]", ""))
    return math.ceil(characters * NOTE_CHAR_PX / NOTE_PIXELS)
end
for _, entry in ipairs({ { "enUS", defaultLocale }, { "frFR", frenchLocale } }) do
    local localeName, strings = entry[1], entry[2]
    check(noteLines(strings["REFUSED_NAME"]) <= 1,
        "REFUSED_NAME fits the one line the name fields keep (" .. localeName .. ")")
    check(noteLines(strings["REFUSED_PATTERN"]) <= 1,
        "REFUSED_PATTERN fits the one line the pattern field keeps (" .. localeName .. ")")
    check(noteLines(strings["BNET_NOT_BLOCKED"]) <= 2,
        "BNET_NOT_BLOCKED fits the two lines the blocked names field keeps ("
        .. localeName .. ")")
end

ns.removeBlocked(ns.normalizeCharacterKey("Acceptedname"))
ns.ClosePanel()
runTimers(3)

end)()

-- ---------------------------------------------------------------------------
-- The panels are modal, and as tall as the window
-- ---------------------------------------------------------------------------

-- The brief asks for a right-hand panel with a veil behind it, and the mock-up
-- draws it from the bottom of the title bar to the bottom of the frame. Built at
-- a fixed 400 pixels with no veil at all, it left a band of the Protection
-- screen uncovered underneath -- and Cards and Checks stay clickable, so those
-- were settings changed blind, behind a panel.
do
    local veil = _G.SanctuaryPanelVeil
    local allowedPanelFrame = _G.SanctuaryPanelAllowed
    local blockedPanelFrame = _G.SanctuaryPanelBlocked
    check(veil ~= nil, "the window carries a veil for its panels")
    equal(veil:IsShown(), false, "which stays out of the way while no panel is open")
    check(type(veil:GetScript("OnMouseDown")) == "function",
        "and it swallows the clicks that would land on the screen behind it")
    check(type(veil:GetScript("OnMouseWheel")) == "function", "and the wheel with them")

    -- Both extremes of the window, reached through the stored size, which
    -- `applyHeight` clamps to the bounds: the test asks for an absurd height at
    -- either end and reads back whatever the window settled on, so it does not
    -- have to know the two constants to prove the panel follows them.
    local measured = {}
    for _, asked in ipairs({ 1, 10000 }) do
        SanctuaryDB.uiSize = { 780, asked }
        ns.refreshUI()
        ns.OpenPanel("allowed")
        local frameHeight = mainFrame:GetHeight()
        measured[#measured + 1] = frameHeight
        local band = "at a window " .. tostring(frameHeight) .. " high"
        equal(allowedPanelFrame:GetHeight(), frameHeight - 40,
            "the panel runs from under the header to the bottom of the frame, " .. band)
        equal(veil:GetHeight(), frameHeight - 40, "and the veil covers the same band, " .. band)
        equal(veil:IsShown(), true, "the veil is up as long as the panel is, " .. band)
        -- 40 header, 44 for the panel's own title row, and the bottom margin
        -- that keeps the list clear of the undo strip: the strip is an overlay
        -- pinned 6 above the frame's bottom edge and 22 tall, so a list running
        -- to within 12 of the edge had its last row half covered for the six
        -- seconds the strip was up -- exactly when someone is looking at it to
        -- decide whether to undo.
        local undoTop = 6 + 22
        equal(allowedPanelFrame.scroll:GetHeight(), frameHeight - 40 - 44 - (undoTop + 6),
            "and the list inside is given the room the panel gained, " .. band)
        check(frameHeight - 40 - 44 - allowedPanelFrame.scroll:GetHeight() > undoTop,
            "with its bottom edge clear of the undo strip, " .. band)
    end
    check(measured[1] ~= measured[2],
        "and the two heights measured really were two different windows")

    -- Resizing with a panel already open moves it too: the grip drives
    -- `applyViewport` on every pixel of the drag, panels included.
    SanctuaryDB.uiSize = { 780, 1 }
    ns.refreshUI()
    equal(allowedPanelFrame:GetHeight(), mainFrame:GetHeight() - 40,
        "a window resized under an open panel takes the panel with it")

    -- The tab strip hangs below the frame, where no veil can reach it. Clicking a
    -- tab therefore closes the panel, rather than leaving a list of allowed names
    -- floating over the Journal -- a state the design never had.
    equal(allowedPanelFrame:IsShown(), true, "the panel is still open before the tab is clicked")
    _G["SanctuaryTab_journal"]:Click()
    equal(allowedPanelFrame:IsShown(), false, "clicking a tab closes the panel")
    equal(blockedPanelFrame:IsShown(), false, "and leaves no other panel standing behind it")
    equal(veil:IsShown(), false, "and takes the veil down with it")
    equal(_G["SanctuaryTabContent_journal"]:IsShown(), true, "leaving the Journal alone on screen")

    -- And the veil itself closes it, decision 101: a click anywhere on the
    -- window beside the drawer is the gesture a modal overlay already promises,
    -- and the cross was the only way out of it.
    ns.OpenPanel("blocked")
    equal(blockedPanelFrame:IsShown(), true, "the drawer is open")
    veil:GetScript("OnMouseDown")(veil)
    equal(blockedPanelFrame:IsShown(), false, "clicking the window beside it closes the drawer")
    equal(veil:IsShown(), false, "and the veil goes down with it")

    -- What must NOT close it: a click on the drawer itself. The panel had no
    -- mouse of its own, so every click on an empty part of it fell through to
    -- the veil underneath -- which, now that the veil closes, would shut the
    -- very list the person is reading.
    ns.OpenPanel("blocked")
    equal(blockedPanelFrame.__mouseEnabled, true, "the drawer eats its own clicks")
    equal(blockedPanelFrame:IsShown(), true, "so it stays open under one")
    ns.ClosePanel()

    SanctuaryDB.uiSize = nil
    _G["SanctuaryTab_protection"]:Click()
end

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

-- The veil stops under the header so the close cross stays reachable, which left
-- this control reachable too -- and it is the one that turns the whole
-- protection off, from behind a panel that goes on listing names as if nothing
-- had happened. Refused while a panel is open, and dimmed so the refusal is
-- visible before the click rather than after it.
ns.OpenPanel("allowed")
equal(stateButton:GetAlpha(), 0.35, "an open panel dims the header control")
stateButton:Click()
equal(ns.isEnabled(), true, "and the click behind the panel does nothing")
ns.ClosePanel()
equal(stateButton:GetAlpha(), 1, "closing the panel gives the control back")
stateButton:Click()
equal(ns.isEnabled(), false, "and it works again")
stateButton:Click()
equal(ns.isEnabled(), true, "left as it was found")

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

-- A folded entry, on screen and in the export. The badge rides on the type and
-- the range on the date, both through the core, so the tab and the copy can
-- never say two different things.
equal(ns.getLogEntryDisplayType({ type = "channel" }), ns.L["LOG_TYPE_CHANNEL"],
    "an entry that never folded wears no badge")
equal(ns.getLogEntryDisplayType({ type = "channel", count = 1 }), ns.L["LOG_TYPE_CHANNEL"],
    "and neither does one seen once")
equal(ns.getLogEntryDisplayType({ type = "channel", count = 4 }),
    ns.L["LOG_TYPE_CHANNEL"] .. string.format(ns.L["LOGS_SPAM_BADGE"], 4),
    "a folded entry wears the count it stands for")
equal(ns.getLogEntryDisplayDate({ d = "2026-08-24 14:02:11" }), "2026-08-24 14:02:11",
    "an entry that never folded shows the date it always showed")
equal(ns.getLogEntryDisplayDate({ d = "2026-08-24 14:02:11", t2 = 420 }),
    string.format(ns.L["LOGS_TIME_RANGE"], "2026-08-24 14:02:11", "12:00:00"),
    "and a folded one shows the range it covers")

wipe(SanctuaryDB.log)
SanctuaryDB.log = {
    -- Older by its first occurrence, but still going: it has to sort first.
    { t = 100, t2 = 900, d = "2026-08-24 14:02:11", type = "channel",
      name = "Zzzzz", realm = "Royaume", msg = "buy gold", count = 4 },
    { t = 500, d = "2026-08-24 14:20:00", type = "whisper",
      name = "Wwwww", realm = "Royaume", msg = "slt" },
}
ns.refreshUI()
rendered = panelRowTexts(journalContent)
check(rendered:find("Zzzzz-Royaume (4)", 1, true) ~= nil,
    "a group header counts occurrences, not lines")
do
    -- Read off the anchors: the rows come out of a pool, so where they sit is
    -- the only thing that says which group is on top.
    local _, _, _, _, folded = findRow(journalContent, "Zzzzz-Royaume"):GetPoint()
    local _, _, _, _, plain = findRow(journalContent, "Wwwww-Royaume"):GetPoint()
    check(folded > plain,
        "and a folded entry is as recent as its last occurrence, not its first")
end
findRow(journalContent, "Zzzzz-Royaume"):Click()
rendered = panelRowTexts(journalContent)
check(rendered:find(string.format(ns.L["LOGS_SPAM_BADGE"], 4), 1, true) ~= nil,
    "unfolding shows the badge on the entry itself")
check(rendered:find(ns.getLogEntryDisplayDate(SanctuaryDB.log[1]), 1, true) ~= nil,
    "and the range it covers")
findRow(journalContent, ns.L["LOGS_COPY_BTN"]):Click()
exportFrame = _G.SanctuaryExportFrame
check(exportFrame.box:GetText():find(string.format(ns.L["LOGS_SPAM_BADGE"], 4), 1, true) ~= nil,
    "the export carries the same badge")
check(exportFrame.box:GetText():find(ns.getLogEntryDisplayDate(SanctuaryDB.log[1]), 1, true) ~= nil,
    "and the same range")
exportFrame:Hide()
findRow(journalContent, "Zzzzz-Royaume"):Click()
wipe(SanctuaryDB.log)

-- ---------------------------------------------------------------------------
-- Advanced
-- ---------------------------------------------------------------------------

SanctuaryDB.debugEnabled = true
mainFrame:Hide()
mainFrame:Show()
_G["SanctuaryTab_advanced"]:Click()
local advancedContent = _G["SanctuaryTabContent_advanced"]

-- Automatic trust is no longer here: it went to the home screen with decision
-- 103, and Advanced keeps diagnostics, the journal's size, the minimap button
-- and the technical line.
check(findRow(advancedContent, ns.L["FILTER_AUTO_TRUST"]) == nil,
    "the auto-trust row has left Advanced")

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

-- This field carries a setting, so it keeps showing it. Clearing on Enter the
-- way the "add a name" fields do left the box blank right after a value was
-- saved -- which reads as "no limit".
equal(_G.SanctuaryMaxEntriesInput:GetText(), "5000",
    "and the field still shows it after Enter instead of going blank")
_G.SanctuaryMaxEntriesInput:SetText("50")
_G.SanctuaryMaxEntriesInput:GetScript("OnEnterPressed")(_G.SanctuaryMaxEntriesInput)
equal(_G.SanctuaryMaxEntriesInput:GetText(), "100",
    "a clamped value is shown clamped, not as it was typed")
_G.SanctuaryMaxEntriesInput:SetText("not a number")
_G.SanctuaryMaxEntriesInput:GetScript("OnEnterPressed")(_G.SanctuaryMaxEntriesInput)
equal(SanctuaryDB.logging.maxEntries, 100, "text that is not a number changes nothing")
equal(_G.SanctuaryMaxEntriesInput:GetText(), "100",
    "and the field goes back to the value that is stored")
_G.SanctuaryMaxEntriesInput:SetText("5000")
_G.SanctuaryMaxEntriesInput:GetScript("OnEnterPressed")(_G.SanctuaryMaxEntriesInput)

-- ---------------------------------------------------------------------------
-- The minimap button
-- ---------------------------------------------------------------------------

-- A scale of its own, declared rather than left out: the mock used to have no
-- GetEffectiveScale at all, so whichever frame the drag divided by, the division
-- was a no-op and the test proved nothing about it.
-- A width too: the button's radius is measured on the minimap now, and a stand-in
-- that cannot be measured would prove the fallback rather than the rule.
Minimap = { GetCenter = function() return 100, 100 end,
    GetWidth = function() return 140 end,
    GetEffectiveScale = function() return 1 end }
UIParent.GetEffectiveScale = function() return 1 end
GetCursorPosition = function() return 180, 100 end
ns.InitializeUI()
local minimapButton = _G.SanctuaryMinimapButton
check(minimapButton ~= nil, "the minimap button is created at login")
equal(minimapButton:IsShown(), true, "and shown while the setting allows it")

-- Decisions 147 and 149: the button wears the lantern, not `inv_shield_06`.
--
-- And the file it points at has to be one the client can actually load, which is
-- the part nothing here could see before. The artwork the mission folder carries
-- is a PNG -- a format WoW does not read from an add-on folder -- and every one
-- of its pixels is opaque, so shipping it as it stood would have put a white
-- square inside the tracking ring. What is checked is the shipped file itself:
-- an uncompressed 32-bit TGA, a power of two on both sides, with real
-- transparency in it.
do
    local icon = minimapButton.icon
    check(icon ~= nil, "the button has an icon")
    equal(icon:GetTexture(), "Interface\\AddOns\\Sanctuary\\media\\lanterne",
        "pointed at the add-on's own lantern")
    check(tostring(icon:GetTexture()):find("Icons", 1, true) == nil,
        "and not at a Blizzard icon any more")
    equal(icon.__texCoord, nil,
        "drawn whole: the crop was there to cut a Blizzard icon's border")
    -- No extension in the path: the client resolves .blp or .tga itself, and a
    -- texture is data -- nothing about it belongs in the .toc, which lists only
    -- Lua and XML.
    check(tostring(icon:GetTexture()):find("%.%a+$") == nil,
        "with no extension spelt out in the path")

    local handle = io.open(repoRoot .. "/media/lanterne.tga", "rb")
    check(handle ~= nil, "the file is in the add-on folder, beside the code")
    if handle then
        local header = handle:read(18)
        equal(#header, 18, "and it has a TGA header")
        equal(header:byte(2), 0, "no colour map")
        -- Type 2 is uncompressed true-colour. Type 10 is the RLE variant, which
        -- is what every convert-to-TGA tool writes by default and what the
        -- client does not read.
        equal(header:byte(3), 2, "uncompressed true-colour, not the RLE variant")
        local width = header:byte(13) + header:byte(14) * 256
        local height = header:byte(15) + header:byte(16) * 256
        equal(width, 64, "64 px wide")
        equal(height, 64, "and 64 tall -- a power of two on both sides")
        equal(header:byte(17), 32, "32 bits a pixel, so there is room for an alpha")
        equal(header:byte(18) % 16, 8, "and eight of them are the alpha")
        -- Really transparent, and really drawn: a file that is all background is
        -- an empty button, and one that is all artwork is the white square.
        local body = handle:read("a")
        handle:close()
        equal(#body, width * height * 4, "the pixels are all there")
        local clear, opaque = 0, 0
        for at = 4, #body, 4 do
            local alpha = body:byte(at)
            if alpha == 0 then clear = clear + 1
            elseif alpha > 200 then opaque = opaque + 1 end
        end
        check(clear > width * height / 4,
            "most of the square is see-through (" .. clear .. " px)")
        check(opaque > 200, "and there is a lantern drawn in it (" .. opaque .. " px)")
    end
end

-- The position-to-angle conversion is pure, so it is proved without a mouse.
equal(math.floor(ns.minimapAngleFromPosition(0, 0, 10, 0) + 0.5), 0, "due east is 0 degrees")
equal(math.floor(ns.minimapAngleFromPosition(0, 0, 0, 10) + 0.5), 90, "due north is 90")
equal(math.floor(ns.minimapAngleFromPosition(0, 0, -10, 0) + 0.5), 180, "due west is 180")
-- The four quadrants, and the half of the circle that was missing: in WoW's Lua
-- 5.1 `math.atan` takes ONE argument and drops the second without a word, so
-- everything south of the centre came back as its northern mirror and the button
-- could not be dragged past the horizontal -- "ca ne peut tourner que sur la
-- partie droite (0 a 180 degres)", constat D.5.
equal(math.floor(ns.minimapAngleFromPosition(0, 0, 10, 10) + 0.5), 45, "north east is 45")
equal(math.floor(ns.minimapAngleFromPosition(0, 0, -10, 10) + 0.5), 135, "north west is 135")
equal(math.floor(ns.minimapAngleFromPosition(0, 0, 0, -10) + 0.5), 270, "due south is 270")
equal(math.floor(ns.minimapAngleFromPosition(0, 0, -10, -10) + 0.5), 225, "south west is 225")
equal(math.floor(ns.minimapAngleFromPosition(0, 0, 10, -10) + 0.5), 315, "south east is 315")

-- And the guard the harness cannot get from a test: it runs a modern Lua, where
-- `math.atan(dy, dx)` is correct, so the defect above is green here whichever
-- spelling the source carries. Only reading the source can catch it.
do
    local twoArgumentAtan = {}
    for _, file in ipairs({ "/Sanctuary.lua", "/SanctuaryUI.lua" }) do
        local handle = assert(io.open(repoRoot .. file, "r"))
        -- Comments stripped first: the two spellings have to be nameable in the
        -- note that explains why one of them is banned, and a guard that refuses
        -- its own explanation is a guard nobody can document.
        local text = handle:read("a"):gsub("%-%-[^\n]*", "")
        handle:close()
        local at = 1
        while true do
            local _, stop = text:find("math%.atan%s*%(", at)
            if not stop then break end
            local depth, index, comma = 1, stop + 1, false
            while depth > 0 and index <= #text do
                local char = text:sub(index, index)
                if char == "(" then depth = depth + 1
                elseif char == ")" then depth = depth - 1
                elseif char == "," and depth == 1 then comma = true end
                index = index + 1
            end
            if comma then twoArgumentAtan[#twoArgumentAtan + 1] = file end
            at = stop + 1
        end
    end
    equal(#twoArgumentAtan, 0, "no source calls math.atan with two arguments ("
        .. table.concat(twoArgumentAtan, ", ") .. ")")
end

-- The ring is measured on the minimap, not assumed. A flat 80 is the DEFAULT
-- minimap's own 70 plus a margin; Edit Mode scales the minimap, and on anything
-- larger than the default 80 falls inside the map -- "il est vers l'interieur de
-- la minimap alors qu'avant j'avais souvenir que c'etait l'exterieur".
equal(ns.minimapRadius(140), 80, "the default minimap keeps the radius the button had")
check(ns.minimapRadius(240) > 120, "a minimap enlarged in Edit Mode pushes the button out with it")
equal(ns.minimapRadius(nil), 80, "and a minimap that cannot be measured falls back on the default")
do
    Minimap.GetWidth = function() return 240 end
    SanctuaryDB.minimap.angle = 0
    ns.RefreshMinimapButton()
    local _, _, _, offsetX = minimapButton:GetPoint()
    equal(math.floor((offsetX or 0) + 0.5), 130,
        "and the button is placed on the ring of the minimap it is actually on")
    Minimap.GetWidth = function() return 140 end
    ns.RefreshMinimapButton()
end
minimapButton:GetScript("OnDragStop")(minimapButton)
equal(math.floor(SanctuaryDB.minimap.angle + 0.5), 0, "dragging writes the angle it computes")

-- The session protocol asks the tester to watch the button follow the cursor
-- around the minimap. It only did so at the release: the drag posted a flag
-- nothing read. The angle now moves while the mouse is still down.
do
    local function frame()
        local onUpdate = minimapButton:GetScript("OnUpdate")
        if onUpdate then onUpdate(minimapButton, 0.016) end
    end
    GetCursorPosition = function() return 100, 180 end
    minimapButton:GetScript("OnDragStart")(minimapButton)
    check(minimapButton:GetScript("OnUpdate") ~= nil, "a drag installs the follow")
    frame()
    equal(math.floor(SanctuaryDB.minimap.angle + 0.5), 90,
        "and the button moves to the cursor while the mouse is still down")
    GetCursorPosition = function() return 20, 100 end
    frame()
    equal(math.floor(SanctuaryDB.minimap.angle + 0.5), 180,
        "it keeps following, frame by frame")
    minimapButton:GetScript("OnDragStop")(minimapButton)
    equal(minimapButton:GetScript("OnUpdate"), nil, "and the release takes the follow back off")
    equal(math.floor(SanctuaryDB.minimap.angle + 0.5), 180,
        "leaving it where the cursor let go")
    GetCursorPosition = function() return 180, 100 end
end

-- Step D.5 of the session protocol is "the button follows the cursor around the
-- minimap", and it is not optional. The cursor comes back in screen pixels, the
-- minimap's centre in the minimap's own coordinates: the two only meet through
-- the MINIMAP's effective scale. UIParent's gave the same answer for as long as
-- both were left alone -- resize the minimap in Edit Mode and the button drifted
-- away from the cursor mid-drag, which the tester would have read as a fault of
-- the add-on, at the price of a session he cannot replay.
do
    local restoreUIParentScale = UIParent.GetEffectiveScale
    Minimap.GetEffectiveScale = function() return 2 end
    UIParent.GetEffectiveScale = function() return 4 end

    -- (360, 200) pixels is (180, 100) on a minimap drawn at scale 2: due east of
    -- a centre at (100, 100). Read through UIParent it lands at (90, 50), south
    -- west of the centre, nowhere near the cursor.
    GetCursorPosition = function() return 360, 200 end
    minimapButton:GetScript("OnDragStop")(minimapButton)
    equal(math.floor(SanctuaryDB.minimap.angle + 0.5), 0,
        "an enlarged minimap still puts the button under the cursor, due east")
    GetCursorPosition = function() return 200, 360 end
    minimapButton:GetScript("OnDragStop")(minimapButton)
    equal(math.floor(SanctuaryDB.minimap.angle + 0.5), 90,
        "and a quarter turn round, with the two scales still disagreeing")

    Minimap.GetEffectiveScale = function() return 1 end
    UIParent.GetEffectiveScale = restoreUIParentScale
    GetCursorPosition = function() return 180, 100 end
end

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

-- A name typed with no realm means the player's own realm, and the menu says the
-- same thing as the core about both sides of that: it offers to stop blocking on
-- the character that entry covers, and to block on his namesake elsewhere. The
-- menu asks `findBlockedKey` rather than searching itself, which is what keeps
-- the two answers from drifting apart.
ns.addBlocked("Bareprobe")
equal(SanctuaryDB.blockedNames["bareprobe-testrealm"] ~= nil, true,
    "a name typed with no realm is stored on the player's realm")
menuEntries = ns.buildPlayerMenuEntries({ name = "Bareprobe", server = "TestRealm" })
check(menuEntries[2].text:find(ns.L["MENU_UNBLOCK"], 1, true) ~= nil,
    "the menu on that character offers to stop blocking")
equal(ns.classifyName("Bareprobe-TestRealm").verdict, "always_blocked",
    "which is the truth, since the core already holds him blocked")

menuEntries = ns.buildPlayerMenuEntries({ name = "Bareprobe", server = "Ysondre" })
check(menuEntries[2].text:find(ns.L["MENU_BLOCK"], 1, true) ~= nil,
    "while his namesake on another realm is offered a block, not an unblock")
check(ns.classifyName("Bareprobe-Ysondre").verdict ~= "always_blocked",
    "because nothing blocks that one")

menuEntries = ns.buildPlayerMenuEntries({ name = "Bareprobe", server = "TestRealm" })
menuEntries[2].action()
equal(SanctuaryDB.blockedNames["bareprobe-testrealm"], nil,
    "and one click removes the key that was found")
check(ns.classifyName("Bareprobe-TestRealm").verdict ~= "always_blocked",
    "so one click really does stop blocking him")

-- Where a name came from survives the allowed list too. `addBlocked` kept
-- "menu"; `addAllowed` dropped it, so the chip tooltip of a name added by right
-- click claimed it had been typed in by hand.
do
    menuEntries = ns.buildPlayerMenuEntries({ name = "Menuprobe", server = "Ysondre" })
    check(menuEntries[1].text:find(ns.L["MENU_ALLOW"], 1, true) ~= nil, "the first entry allows")
    menuEntries[1].action()
    local menuKey = ns.findAllowedKey("Menuprobe-Ysondre")
    check(SanctuaryDB.manualWhitelist[menuKey] ~= nil, "the click writes the allowed list")
    equal(SanctuaryDB.manualWhitelist[menuKey].source, "menu",
        "recording that the right-click menu added it")
    ns.addAllowed("Handtyped")
    equal(SanctuaryDB.manualWhitelist["handtyped-testrealm"].source, nil,
        "while a name with no stated origin stays a plain hand entry")
    ns.addAllowed("Menutwo", "menu")
    equal(SanctuaryDB.manualWhitelist["menutwo-testrealm"].source, "menu",
        "and the origin travels on the direct call")
    -- Still counted among the names she added: she did add it, with two clicks
    -- instead of by typing. Only the automatic trust entries stand apart.
    local before = ns.getListCounts().allowed.manual
    ns.removeAllowed("menutwo-testrealm")
    equal(ns.getListCounts().allowed.manual, before - 1,
        "a name added from the menu counts as one she added, not as automatic trust")
    ns.removeAllowed(menuKey)
    ns.removeAllowed("handtyped-testrealm")
end

equal(#ns.buildPlayerMenuEntries({ name = "Victim" }), 0, "the player themselves gets nothing")
equal(#ns.buildPlayerMenuEntries({ name = "Victim", server = "TestRealm" }), 0,
    "spelt with their realm, still nothing")
-- ... and a real stranger who happens to share the player's name gets the two
-- entries the menu exists for. The comparison used to read the bare pseudo and
-- ignore the realm, so the one person on that list somebody is most likely to
-- want blocked -- a namesake, deliberately picked -- was the one the right-click
-- menu had nothing to offer about.
equal(#ns.buildPlayerMenuEntries({ name = "Victim", server = "Ysondre" }), 2,
    "while a namesake on another realm is a stranger like any other")

-- The allowed half asks the core for the key the list is actually written under.
-- A Battle.net account allowed by hand is keyed whole; looked up under its first
-- word alone it read as "not allowed", and the menu offered to allow again
-- somebody who already was -- writing a second entry the first click had made.
ns.addAllowed("Real Friend#1234")
check(SanctuaryDB.manualWhitelist["real friend#1234"] ~= nil,
    "an account allowed by hand is keyed whole")
menuEntries = ns.buildPlayerMenuEntries({ name = "Real Friend#1234" })
check(menuEntries[1].text:find(ns.L["MENU_UNALLOW"], 1, true) ~= nil,
    "and the menu offers to stop allowing it, not to allow it a second time")
menuEntries[1].action()
equal(SanctuaryDB.manualWhitelist["real friend#1234"], nil, "which one click does")

equal(#ns.buildPlayerMenuEntries({}), 0, "an unresolved identity gets nothing")

-- And a PNJ gets nothing either, decision 113: "deja le souci c'est qu'on peut
-- le faire sur les PNJ". Allowing or blocking a shopkeeper writes a dead record
-- into a list and counts it in a tile, about a name no invitation, no whisper
-- and no duel can ever carry.
do
    npcUnits.target = true
    equal(#ns.buildPlayerMenuEntries({ name = "Innkeeper", unit = "target" }), 0,
        "right-clicking a PNJ offers no Sanctuary entry")
    equal(#ns.buildPlayerMenuEntries({ name = "Innkeeper", server = "TestRealm", unit = "target" }), 0,
        "not even one carrying a realm")
    npcUnits.target = nil
    equal(#ns.buildPlayerMenuEntries({ name = "Stranger", unit = "target" }), 2,
        "while a real player still gets the two entries")
    -- No unit at all -- a name right-clicked in the chat or in a roster -- is a
    -- player by construction and must not be caught by the same rule.
    equal(#ns.buildPlayerMenuEntries({ name = "Chatstranger" }), 2,
        "and a name with no unit behind it is still offered both")
end
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
local SKIPPED_DIAGNOSTIC_ID = "sim_channel_spam"
local BULK_DIAGNOSTIC_IDS = { "sim_invite", "sim_bnet", "diag_chat",
    "diag_chat_lockdown", "diag_popup_invite", "diag_popup_duel", "diag_popup_guild",
    "diag_popup_list" }

local sensitiveCount, manualCount, skippedCount = 0, 0, 0
for _, entry in ipairs(ns.DIAGNOSTIC_CATALOG) do
    if entry.sensitive then sensitiveCount = sensitiveCount + 1 end
    if entry.manual then manualCount = manualCount + 1 end
    if entry.skipBulk then skippedCount = skippedCount + 1 end
end
equal(sensitiveCount, 1, "exactly one diagnostic is marked as naming a real contact")
equal(ns.getDiagnosticEntry(SENSITIVE_DIAGNOSTIC_ID).sensitive, true,
    "and it is " .. SENSITIVE_DIAGNOSTIC_ID)
equal(manualCount, #MANUAL_DIAGNOSTIC_IDS, "exactly two are marked as run-them-by-hand")
for _, id in ipairs(MANUAL_DIAGNOSTIC_IDS) do
    equal(ns.getDiagnosticEntry(id).manual, true, id .. " is one of them")
end
equal(skippedCount, 1, "exactly one is kept out of the batch without being a manual one")
equal(ns.getDiagnosticEntry(SKIPPED_DIAGNOSTIC_ID).skipBulk, true,
    "and it is " .. SKIPPED_DIAGNOSTIC_ID .. ", the one that prints into the chat")
equal(ns.getDiagnosticEntry(SKIPPED_DIAGNOSTIC_ID).manual, nil,
    "which is not a manual one: its tooltip has something else to say")
equal(#ns.DIAGNOSTIC_CATALOG, #BULK_DIAGNOSTIC_IDS + #MANUAL_DIAGNOSTIC_IDS + 2,
    "the catalogue is the bulk set plus those four")

-- Being kept out of the batch must not rewrite what the button says on hover:
-- "run this one on its own, and listen" is true of the two sounds and false of
-- the probe, which has three lines of its own to explain.
local function tooltipOf(labelKey)
    local btn = findButtonByLabel(diagContent, ns.L[labelKey])
    check(btn ~= nil, "the panel shows the " .. labelKey .. " button")
    rawset(GameTooltip, "__lastText", nil)
    btn:GetScript("OnEnter")(btn)
    return rawget(GameTooltip, "__lastText")
end
equal(tooltipOf("DIAG_SIMULATE_SPAM"), ns.L["DIAG_TIP_SPAM"],
    "the spam probe still explains itself instead of claiming to be a manual one")
for _, id in ipairs(MANUAL_DIAGNOSTIC_IDS) do
    equal(tooltipOf(ns.getDiagnosticEntry(id).labelKey), ns.L["DIAG_MANUAL"],
        id .. " still says to run it on its own")
end

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
equal(shown:find(ns.L[ns.getDiagnosticEntry(SKIPPED_DIAGNOSTIC_ID).labelKey], 1, true), nil,
    "nor " .. SKIPPED_DIAGNOSTIC_ID .. ", whose answer is printed into the chat")

-- Step C.1 of the session promises nothing on screen and nothing in the ear
-- while the batch runs, and the tester reads the chat right after it. The spam
-- probe is the only diagnostic that answers in the chat instead of the panel,
-- and with the anti-spam armed it drops a channel entry into the Journal on the
-- way: a batch that fires it makes the only person with a client write down a
-- failure that is not one. Both states are pinned -- off is what the session
-- starts on, on is what the step itself asks for.
do
    local savedEnabled = SanctuaryDB.antiSpam.enabled
    local savedInterval = SanctuaryDB.antiSpam.intervalSeconds
    local savedLogging = SanctuaryDB.logging.enabled
    -- The Journal half of the check is only worth something while the Journal
    -- is actually recording.
    SanctuaryDB.logging.enabled = true
    for _, case in ipairs({ { label = "anti-spam off", enabled = false },
                            { label = "anti-spam on", enabled = true } }) do
        SanctuaryDB.antiSpam.enabled = case.enabled
        SanctuaryDB.antiSpam.intervalSeconds = 300
        local chatBefore = #chatMessages
        local journalBefore = #SanctuaryDB.log
        runAllBtn:Click()
        equal(#chatMessages - chatBefore, 0,
            "running them all writes nothing into the chat (" .. case.label .. ")")
        equal(#SanctuaryDB.log - journalBefore, 0,
            "and leaves the Journal exactly as it was (" .. case.label .. ")")
    end
    SanctuaryDB.antiSpam.enabled = savedEnabled
    SanctuaryDB.antiSpam.intervalSeconds = savedInterval
    SanctuaryDB.logging.enabled = savedLogging
end

-- Eight blocks written into the column. The child of that scroll used to be
-- sized once, at build time, so RefreshBar measured a range of zero: the wheel
-- scrolled nothing, the bar never appeared, and everything past the first screen
-- was unreachable -- while step C.1 of the session asks the tester to read every
-- block. The column takes the whole height of the window now (constat C.1), so
-- what proves the resize is that the child FOLLOWS the text, and the bar is
-- proved against a viewport short enough to need one.
local resultScroll = _G.SanctuaryDiagResultScroll
local filledHeight = resultScroll.child:GetHeight() or 0
findButtonByLabel(diagContent, ns.L["DIAG_CLEAR"]):Click()
check((resultScroll.child:GetHeight() or 0) < filledHeight,
    "clearing the results gives the column its height back")
check((resultScroll.child:GetHeight() or 0) <= (resultScroll:GetHeight() or 0),
    "and once cleared it does not pretend to scroll")
equal(resultScroll.bar:IsShown(), false, "with no bar left over")
-- Put the panel back the way the rest of this section found it.
runAllBtn:Click()
check((resultScroll.child:GetHeight() or 0) >= filledHeight,
    "and running them all measures the eight blocks again")
do
    local keptWidth, keptHeight = resultScroll:GetWidth(), resultScroll:GetHeight()
    resultScroll:SetViewportSize(keptWidth, 60)
    check((resultScroll.child:GetHeight() or 0) > 60,
        "eight blocks are taller than a 60 px column")
    equal(resultScroll.bar:IsShown(), true, "so the bar is there to say the column scrolls")
    resultScroll:SetViewportSize(keptWidth, (resultScroll.child:GetHeight() or 0) + 40)
    equal(resultScroll.bar:IsShown(), false, "and goes away when the column is tall enough")
    resultScroll:SetViewportSize(keptWidth, keptHeight)
end

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
check(protectionHeight <= 900 + 40 + 30 + 30, "and the fitted height stays within its bounds")

-- "I choose" unfolds two columns of boxes into the middle of the screen: the
-- window grows for them, and where it cannot -- a size the person dragged it to
-- -- what is under the fold stays reachable through the bar rather than being
-- cut off.
local chooseScroll = _G.SanctuaryContentScroll
check(chooseScroll ~= nil, "the content area is a scroll")
-- Measured in a window the person shrank, so both answers are the screen's own
-- height rather than the viewport they are both floored at.
SanctuaryDB.uiSize = { 780, 520 }
SanctuaryDB.filters.preset = "all"
ns.refreshUI()
local foldedContent = chooseScroll:GetScrollChild():GetHeight() or 0
SanctuaryDB.filters.preset = "custom"
ns.refreshUI()
check((chooseScroll:GetScrollChild():GetHeight() or 0) > foldedContent,
    "unfolding the detailed boxes makes the screen taller")
check((chooseScroll:GetScrollChild():GetHeight() or 0) > (chooseScroll:GetHeight() or 0),
    "and the fold is under the bar rather than cut off")
equal(chooseScroll.bar:IsShown(), true, "which is what the bar is there to say")
SanctuaryDB.uiSize = nil
SanctuaryDB.filters.preset = "all"
ns.refreshUI()
equal(mainFrame:GetWidth(), 780, "the window opens at its design width")

-- Dragging the grip switches to a remembered size; double-clicking goes back.
-- Both slots are read back now, decision 98. Smaller than the height the window
-- OPENS at, on purpose: that is the whole of what the grip is for downwards, and
-- clamping a remembered size to the opening height gave it back on the next
-- opening -- the drag simply did not survive the window being closed.
SanctuaryDB.uiSize = { 640, 520 }
mainFrame:Hide()
mainFrame:Show()
equal(mainFrame:GetHeight(), 520, "a remembered size smaller than the window is applied on opening")
equal(mainFrame:GetWidth(), 640, "its width included")
SanctuaryDB.uiSize = nil
mainFrame:Hide()
mainFrame:Show()

do

-- The grip drives both dimensions, decision 98: "le redimensionnement de la
-- fenetre ne marche qu'a la vertical, pas l'horizontal". There is still no
-- horizontal SCROLLING -- a wider window is wider columns, never a canvas to pan
-- over -- so the content area, the tab frames and the drawer all have to follow
-- the width rather than keep the one they were built at.
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
local widthOf = function() return _G.SanctuaryContentScroll:GetWidth() end
local expectedViewport = function() return mainFrame:GetHeight() - 40 - 30 - 30 end

now = now + 5
gripDown(grip)
mainFrame:SetSize(860, 940)
gripUp(grip)
equal(SanctuaryDB.uiSize[1], 860, "a diagonal drag records the width it was dragged to")
equal(SanctuaryDB.uiSize[2], 940, "and the height")
equal(viewportOf(), expectedViewport(), "and the content area follows on release")
equal(widthOf(), 860, "the content area is as wide as the window")
equal(mainFrame:GetWidth(), 860, "which keeps the width that was asked for")
equal(mainFrame:GetHeight(), 940, "and the height that was asked for")
-- The columns share the extra pixels: "les colonnes se repartissent". Every
-- frame in this window was BUILT at 780 and none of them read a live width, so
-- what the grip moved was the frame alone -- the screen inside it stayed the
-- size it had opened at.
equal(_G.SanctuaryTabContent_protection:GetWidth(), 860, "and so does the screen on show")
do
    local pad, gutter = 18, 10
    local expected = (860 - pad * 2 - gutter) / 2
    for _, name in ipairs({ "SanctuaryQ1_strangers", "SanctuaryQ1_blockedOnly",
        "SanctuaryQ2_all", "SanctuaryQ2_custom",
        "SanctuaryTileAllowed", "SanctuaryTileBlocked" }) do
        equal(_G[name]:GetWidth(), expected, name .. " shares the width the window gained")
    end
    -- And the drawer, which is not inside the content area and answers to the
    -- window on its own pass.
    ns.OpenPanel("blocked")
    local drawer = _G.SanctuaryPanelBlocked
    local drawerWidth = drawer:GetWidth()
    check(_G.SanctuaryPanelBlockedScroll:GetWidth() <= drawerWidth,
        "the drawer's list is no wider than the drawer")
    equal(_G.SanctuaryPanelBlocked.namesSection:GetWidth(), drawerWidth - 40,
        "and its rules span the drawer as it is now, not as it opened")
    ns.ClosePanel()
end

-- Out of bounds in either direction is clamped, not obeyed: 500x380 to 900x700.
now = now + 5
gripDown(grip)
mainFrame:SetSize(1240, 560)
gripUp(grip)
equal(widthOf(), 900, "a drag past the right bound stops at 900")
now = now + 5
gripDown(grip)
mainFrame:SetSize(320, 560)
gripUp(grip)
equal(widthOf(), 500, "and a drag past the left bound stops at 500")
-- The drawer never takes the whole window with it: the strip of veil beside it
-- is what closes it.
ns.OpenPanel("blocked")
check(_G.SanctuaryPanelBlocked:GetWidth() < widthOf(),
    "the drawer leaves something of the window beside it at the narrowest width")
ns.ClosePanel()

-- The two scrolling areas that live inside a screen follow the width too. Built
-- at 780 and never resized, the Journal still measured 744 and the Diagnostics
-- results 404 in a 500 px window -- two of the five screens hanging a couple of
-- hundred pixels outside it, with no horizontal scrolling to reach what was cut
-- off -- and kept those same widths when the window was dragged out to 900. A6
-- asks the columns to share the width between the two bounds.
do
    local content = _G.SanctuaryContentScroll
    local journalScroll = _G.SanctuaryJournalScroll
    local resultScroll = _G.SanctuaryDiagResultScroll
    check(journalScroll ~= nil, "the journal's list is reachable")
    check(resultScroll ~= nil, "and the diagnostics results column")
    -- Their left insets: the journal starts at PAD, the results column at the
    -- far side of the 320 px list of buttons.
    local journalInset, resultInset = 18, 18 + 330
    local narrowJournal = journalScroll:GetWidth()
    local narrowResults = resultScroll:GetWidth()
    check(journalInset + narrowJournal <= content:GetWidth(),
        "at 500 the journal fits inside the content area")
    check(resultInset + narrowResults <= content:GetWidth(),
        "and so does the diagnostics results column")
    now = now + 5
    gripDown(grip)
    mainFrame:SetSize(900, 560)
    gripUp(grip)
    check(journalScroll:GetWidth() > narrowJournal,
        "widening the window widens the journal")
    check(resultScroll:GetWidth() > narrowResults,
        "and the results column with it")
    check(journalInset + journalScroll:GetWidth() <= content:GetWidth(),
        "the journal still fits at 900")
    check(resultInset + resultScroll:GetWidth() <= content:GetWidth(),
        "and so do the results")
end

-- The other three screens, and everything inside all five. The pass above
-- reached the two scrolling areas by name; every other width a screen derived
-- from the window at build time -- a section rule, a wrapped paragraph, the
-- technical line, a Journal row, the fold's two columns -- stayed at the 744 px
-- of a 780 px window for ever. At 500 the room is 464, so those widgets hung up
-- to 280 px outside a window with no horizontal scrolling; at 900 they left
-- 156 px of it empty. Neither a tab change nor a refresh caught them: they are
-- posted once, at build time, and nothing revisited them.
do
    local content = _G.SanctuaryContentScroll
    local SCREEN_KEYS = { "protection", "journal", "advanced", "about", "diagnostics" }

    -- Only the widths the interface actually posted. The stand-in answers 620
    -- for a widget nobody ever sized, and 620 fits inside a 780 px window, so a
    -- sweep reading GetWidth alone would take "never measured" for "measured".
    local function postedWidths(frame, into)
        into = into or {}
        for _, child in ipairs(frame.__children or {}) do
            if child.__widthPosted then into[#into + 1] = child:GetWidth() end
            postedWidths(child, into)
        end
        return into
    end

    -- A section is recognised by the one method only `newSection` gives out,
    -- rather than by its position among the children: what is being checked is
    -- "the rules span the screen", and a rule is what that method resizes.
    -- Read with `rawget`, and that is not a detail: every capitalised name is
    -- auto-stubbed on first access, so asking a widget for the method would
    -- install one and turn all of them into sections -- including the check that
    -- there are exactly three.
    local function sectionsOf(frame, into)
        into = into or {}
        for _, child in ipairs(frame.__children or {}) do
            if rawget(child, "SetSectionWidth") then into[#into + 1] = child end
            sectionsOf(child, into)
        end
        return into
    end

    local function sweep()
        local room = content:GetWidth()
        local report = {}
        for _, key in ipairs(SCREEN_KEYS) do
            local frame = _G["SanctuaryTabContent_" .. key]
            check(frame ~= nil, "the " .. key .. " screen is reachable")
            local widest, overflow = 0, nil
            for _, width in ipairs(postedWidths(frame)) do
                widest = math.max(widest, width)
                -- The screens start at PAD, so PAD plus a posted width is the
                -- earliest right edge it can have: anything past the content
                -- area is cut off with nowhere to scroll to.
                if 18 + width > room then overflow = math.max(overflow or 0, width) end
            end
            equal(overflow, nil, "nothing on the " .. key
                .. " screen is posted wider than the window at " .. tostring(room))
            report[key] = widest
        end
        report.sections = sectionsOf(_G.SanctuaryTabContent_advanced)
        return report
    end

    now = now + 5
    gripDown(grip)
    mainFrame:SetSize(500, 940)
    gripUp(grip)
    equal(content:GetWidth(), 500, "the window is at its narrowest bound")
    local narrow = sweep()
    equal(#narrow.sections, 3, "the Advanced screen has its three section rules")
    for _, section in ipairs(narrow.sections) do
        equal(section:GetWidth(), 500 - 18 * 2, "and each spans the narrow window")
    end

    now = now + 5
    gripDown(grip)
    mainFrame:SetSize(900, 560)
    gripUp(grip)
    equal(content:GetWidth(), 900, "and then at its widest")
    local wide = sweep()
    for _, section in ipairs(wide.sections) do
        equal(section:GetWidth(), 900 - 18 * 2, "the section rules span the wide window too")
    end
    -- The columns share the width in both directions: growing the window has to
    -- grow what is in it, or a correction that merely clamped everything to the
    -- narrow width would pass the check above and leave 156 px of the wide one
    -- empty.
    for _, key in ipairs({ "protection", "journal", "advanced", "diagnostics" }) do
        check(wide[key] > narrow[key],
            "the " .. key .. " screen takes the width the window gained")
    end
    -- Except the presentation paragraph, which is a reading column and says so:
    -- it stops at its own width instead of running the whole of a 900 px window.
    equal(wide.about, narrow.about,
        "the About paragraph keeps its reading width at both bounds")
end

-- What a posted width cannot see: a widget that is small enough and anchored too
-- far to the right. The sweep above reads sizes, and the Journal's second box is
-- 18 px wide wherever it sits, while the label beside it carries no width at all
-- -- `newCheck` never sets one. Anchored at a fixed PAD + 320, at the 500 px
-- bound it started its sentence 346 px into a 464 px screen, and the half that
-- did not fit was cut off by the ScrollFrame with no sideways scrolling to reach
-- it. Read off the anchors the widgets actually carry, now that the stand-in
-- keeps them.
do
    local content = _G.SanctuaryContentScroll
    local enable, showMsg = _G.SanctuaryJournalEnable, _G.SanctuaryJournalShowMessages
    local list = _G.SanctuaryJournalScroll
    check(enable ~= nil and showMsg ~= nil, "the Journal's two boxes are reachable")

    -- Measured from the screen's own left margin, which is where `innerWidth`
    -- starts counting.
    local function inset(box)
        local _, _, _, x = box:GetPoint()
        return (x or 0) - 18
    end
    local function row(box)
        local _, _, _, _, y = box:GetPoint()
        return y
    end
    -- Where the label ends: the box, the 8 px gap `newCheck` leaves, the text.
    local function labelEnd(box)
        return inset(box) + box:GetWidth() + 8 + box.label:GetStringWidth()
    end
    local function listEnd()
        local _, _, _, _, y = list:GetPoint()
        return y - list:GetHeight()
    end

    now = now + 5
    gripDown(grip)
    mainFrame:SetSize(500, 940)
    gripUp(grip)
    local narrowRoom = 500 - 18 * 2
    check(labelEnd(enable) <= narrowRoom,
        "at 500 the first Journal label stays inside the window")
    check(labelEnd(showMsg) <= narrowRoom,
        "and so does the second, which used to run off the right edge")
    check(row(showMsg) < row(enable),
        "because at that width the second box has moved under the first")
    equal(listEnd(), -360,
        "the list gives back what the second row took, so the buttons under it do not move")

    -- And it only moves when it has to: at the design width and at the wide
    -- bound the two boxes read as one row, which is what the screen is drawn as.
    for _, width in ipairs({ 780, 900 }) do
        now = now + 5
        gripDown(grip)
        mainFrame:SetSize(width, 940)
        gripUp(grip)
        equal(row(showMsg), row(enable),
            "at " .. width .. " the two Journal boxes share one row")
        equal(inset(showMsg), 320,
            "the second one back at its designed column at " .. width)
        check(labelEnd(showMsg) <= width - 18 * 2,
            "and its label fits there at " .. width)
        equal(listEnd(), -360, "the list is back at its full height at " .. width)
    end
end

now = now + 5
gripDown(grip)
mainFrame:SetSize(860, 940)
gripUp(grip)

-- Downwards too: shrinking is the direction that spilled content off-screen, and
-- the direction the grip lost when both of its bounds were brought down to the
-- screen. Below the height the window opens at, which is where a drag downwards
-- goes.
now = now + 5
gripDown(grip)
mainFrame:SetSize(780, 520)
gripUp(grip)
equal(mainFrame:GetHeight(), 520, "a drag downwards is kept")
equal(viewportOf(), expectedViewport(), "and the content area shrinks with it")

-- During the drag, not only on release: the window's own size handler carries
-- the new height to the content area.
mainFrame:SetHeight(960)
mainFrame:GetScript("OnSizeChanged")(mainFrame)
equal(viewportOf(), expectedViewport(), "the content follows while the grip is still down")
now = now + 5
gripDown(grip)
mainFrame:SetSize(700, 940)
gripUp(grip)
mainFrame:Hide()
mainFrame:Show()
equal(mainFrame:GetWidth(), 700, "and reopening brings the dragged width back with it")

-- One gesture per zone, decisions 135-136. The grip ONLY drags: a press and a
-- release with nothing moved in between must leave the window exactly as it was
-- -- no write, no switch out of the fitted mode, no jump. That press/release
-- pair used to record the current size unconditionally, which is what
-- "la poignee redimensionne a chaque re-clic" was made of.
now = now + 5
local restingWidth, restingHeight = mainFrame:GetWidth(), mainFrame:GetHeight()
local restingSize = { SanctuaryDB.uiSize[1], SanctuaryDB.uiSize[2] }
gripDown(grip)
gripUp(grip)
equal(mainFrame:GetWidth(), restingWidth, "clicking the grip without moving keeps the width")
equal(mainFrame:GetHeight(), restingHeight, "and the height")
equal(SanctuaryDB.uiSize[1], restingSize[1], "and writes nothing down")
equal(SanctuaryDB.uiSize[2], restingSize[2], "in either dimension")
-- And from the fitted mode, where the defect actually showed: a click on the
-- grip must not switch the window over to the manual mode at all.
SanctuaryDB.uiSize = nil
ns.refreshUI()
local fittedHeight = mainFrame:GetHeight()
now = now + 5
gripDown(grip)
gripUp(grip)
equal(SanctuaryDB.uiSize, nil, "a click on the grip never leaves the fitted mode")
equal(mainFrame:GetHeight(), fittedHeight, "and the window does not move a pixel")
-- Two clicks in a row are still two clicks: the grip has no double-click any
-- more, so nothing here may be read as one.
now = now + 0.2
gripDown(grip)
gripUp(grip)
equal(SanctuaryDB.uiSize, nil, "twice over, and still nothing written")

-- The way back to the default size is a double-click on the TITLE BAR
-- (decision 136): two press/release pairs less than 0.4 s apart, where the title
-- and the on/off control are.
local titleBar = _G.SanctuaryTitleBar
check(titleBar ~= nil, "the title bar is a frame of its own")
local titleDown = titleBar:GetScript("OnMouseDown")
check(type(titleDown) == "function", "and it answers a press")
now = now + 5
gripDown(grip)
mainFrame:SetSize(700, 940)
gripUp(grip)
equal(SanctuaryDB.uiSize[1], 700, "a drag is still recorded")
now = now + 5
titleDown(titleBar, "LeftButton")
now = now + 0.2
titleDown(titleBar, "LeftButton")
equal(SanctuaryDB.uiSize, nil,
    "a double-click on the title bar forgets the remembered size for good")
-- A single click on the title bar is not half a gesture: it does nothing.
now = now + 5
gripDown(grip)
mainFrame:SetSize(700, 940)
gripUp(grip)
now = now + 5
titleDown(titleBar, "LeftButton")
now = now + 2
equal(SanctuaryDB.uiSize[1], 700, "one click on the title bar changes nothing")
now = now + 5
titleDown(titleBar, "LeftButton")
now = now + 0.2
titleDown(titleBar, "LeftButton")
equal(SanctuaryDB.uiSize, nil, "and the pair still counts once the pause is over")

-- The pair is a LEFT one, and a drag is not half of it. Decision 136 gives this
-- bar one gesture; two right clicks are a menu somewhere else in the game, and a
-- flick of the window followed by a click inside the same 0.4 s was a window
-- somebody had just placed going back to its opening size on its own.
now = now + 5
gripDown(grip)
mainFrame:SetSize(700, 940)
gripUp(grip)
equal(SanctuaryDB.uiSize[1], 700, "a drag is recorded once more")
now = now + 5
titleDown(titleBar, "RightButton")
now = now + 0.2
titleDown(titleBar, "RightButton")
equal(SanctuaryDB.uiSize[1], 700, "two right clicks on the title bar change nothing")
now = now + 5
titleDown(titleBar, "LeftButton")
titleBar:GetScript("OnDragStart")(titleBar)
titleBar:GetScript("OnDragStop")(titleBar)
now = now + 0.2
titleDown(titleBar, "LeftButton")
equal(SanctuaryDB.uiSize[1], 700,
    "and a click, a drag and a click are three gestures rather than a double-click")
SanctuaryDB.uiSize = nil
ns.refreshUI()

-- Dragging the title bar moves the window and never resizes it: the two
-- gestures live in two zones and neither does the other's work.
do
    local movedSize = { mainFrame:GetWidth(), mainFrame:GetHeight() }
    titleBar:GetScript("OnDragStart")(titleBar)
    titleBar:GetScript("OnDragStop")(titleBar)
    equal(mainFrame:GetWidth(), movedSize[1], "a title-bar drag leaves the width alone")
    equal(mainFrame:GetHeight(), movedSize[2], "and the height")
    equal(SanctuaryDB.uiSize, nil, "and never writes a manual size")
    check(SanctuaryDB.uiPosition ~= nil, "what it records is where the window is")
end

-- And the fitted mode is really back: the height follows the screen again, and
-- the width goes back to the one the window is designed at.
_G["SanctuaryTab_about"]:Click()
equal(mainFrame:GetHeight(), 740 + 40 + 30 + 30, "the shortest screen is back to its fitted height")
equal(mainFrame:GetWidth(), 780, "and to the design width")
local shortestFitted = mainFrame:GetHeight()
-- Every screen opens in the same window: the height the window asks for is the
-- home screen's, so a shorter screen does not shrink it around itself -- and
-- there is nothing left for the fitted mode to grow for except the one fold
-- there is. What a shorter screen must NOT do is scroll inside that window,
-- which the A.2 block further down measures on the client's own screen.
_G["SanctuaryTab_protection"]:Click()
equal(mainFrame:GetHeight(), shortestFitted,
    "the home screen fits that same window, folded boxes aside")
SanctuaryDB.filters.preset = "custom"
ns.refreshUI()
check(mainFrame:GetHeight() > shortestFitted,
    "and unfolding the detailed boxes makes the window taller again")
SanctuaryDB.filters.preset = "all"
ns.refreshUI()

end

-- ---------------------------------------------------------------------------
-- What the session and the visual pass sent back (chantiers A and B)
-- ---------------------------------------------------------------------------

-- A scope of its own: the enclosing chunk is at Lua's ceiling of 200 locals.
;(function()

-- A.1 -- the undo strip is bounded, and Annuler is never the half that is cut.
do
    local undo = _G.SanctuaryUndoLine
    local longName = "Ombrelune-ConseildesOmbres"
    SanctuaryDB.uiSize = { 500, 0 }
    ns.refreshUI()
    ns.addAllowed(longName)
    ns.OpenPanel("blocked")
    _G.SanctuaryBlockedAddInput:SetText(longName)
    _G.SanctuaryPanelBlocked.nameBtn:Click()
    equal(undo:IsShown(), true, "moving a long name puts the strip up")

    local point, relativeTo = undo.button:GetPoint()
    equal(point, "RIGHT", "Annuler is anchored on the strip's right edge")
    equal(relativeTo, undo, "on the strip itself, not on the end of the sentence")
    -- 8 px at each end, 12 between the sentence and the button. Anchored to the
    -- end of the sentence, a name of any length pushed the button through the
    -- right border and left half an Annuler nobody could click.
    check((undo.label:GetWidth() or 0) + (undo.button:GetWidth() or 0) + 8 * 2 + 12
        <= (undo:GetWidth() or 0) + 1, "and the sentence gets only what is left of the row")
    check((undo.label:GetWidth() or 0) < (undo.label:GetStringWidth() or 0),
        "so a sentence too long for the row is the half that is cut")
    equal(undo.label.__wordWrap, false, "on one line, not folded over the tabs")
    undo:GetScript("OnEnter")(undo)
    check(tostring(rawget(GameTooltip, "__lastText") or ""):find(longName, 1, true) ~= nil,
        "and the whole of it is readable on the tooltip")

    -- The short variant -- "<name> retire" -- answers to the same rule.
    undo.button:Click()
    ns.ClosePanel()
    ns.removeAllowed(ns.normalizeCharacterKey(longName))
    ns.addAllowed(longName)
    ns.OpenPanel("allowed")
    ns.refreshUI()
    local chip
    local function walk(widget)
        for _, childWidget in ipairs(widget.__children or {}) do
            if childWidget.remove and childWidget.label
                and tostring(childWidget.label.__text or ""):find(longName, 1, true) then
                chip = chip or childWidget
            end
            walk(childWidget)
        end
    end
    walk(_G.SanctuaryPanelAllowed)
    check(chip ~= nil, "the long name has a chip to remove")
    chip.remove:Click()
    equal(undo:IsShown(), true, "removing it puts the short sentence up")
    check((undo.label:GetWidth() or 0) + (undo.button:GetWidth() or 0) + 8 * 2 + 12
        <= (undo:GetWidth() or 0) + 1, "bounded the same way")
    undo.button:Click()
    ns.ClosePanel()
    ns.removeAllowed(ns.normalizeCharacterKey(longName))
    ns.removeBlocked(ns.normalizeCharacterKey(longName))
    SanctuaryDB.uiSize = nil
    ns.refreshUI()
end

-- A.3 -- the shared scroll frame goes back to the top when the screen changes.
do
    SanctuaryDB.filters.preset = "custom"
    SanctuaryDB.uiSize = { 500, 0 }
    _G["SanctuaryTab_protection"]:Click()
    ns.refreshUI()
    local scroll = _G.SanctuaryContentScroll
    scroll:GetScript("OnMouseWheel")(scroll, -1)
    check((scroll.offset or 0) > 0, "the unfolded home screen can be scrolled down")
    equal(scroll:GetVerticalScroll(), scroll.offset, "and the frame is where the offset says")
    _G["SanctuaryTab_about"]:Click()
    equal(scroll.offset, 0, "changing screen puts the shared frame back at the top")
    equal(scroll:GetVerticalScroll(), 0, "the frame with it -- About has no bar to come back with")
    equal(scroll.bar:IsShown(), false, "and About does not pretend to scroll")
    -- And unconditionally. A short destination has its offset clamped away by
    -- `RefreshBar` on its own -- that is the About case above -- so the rule
    -- itself is proved on a destination that COULD hold the offset: put the
    -- shared frame where a tall screen would have left it, change screen, and
    -- the home screen still opens at its top rather than half way down.
    scroll.offset = 40
    scroll:SetVerticalScroll(40)
    _G["SanctuaryTab_protection"]:Click()
    equal(scroll.offset, 0, "a screen never opens where another one was read to")
    equal(scroll:GetVerticalScroll(), 0, "the frame with it")
    SanctuaryDB.filters.preset = "all"
    SanctuaryDB.uiSize = nil
    ns.refreshUI()
end

-- A.2 -- the bar on the right is a lift, not a mark. Decision 134 asks for an
-- "ascenseur visible et fonctionnel", and step D.1 of the session sends the
-- tester down the home screen "with the wheel or the bar on the right": what the
-- bar does when it is pulled is a step of a session that costs Vincent three
-- quarters of an hour, so it is proved here and not there. What stood before was
-- one flat frame the height of the window -- the same trait at the top of the
-- screen and at the bottom of it -- and nothing at all happened when it was
-- dragged.
do
    local keptScreen, keptCursor = UIParent.GetHeight, GetCursorPosition
    UIParent.GetHeight = function() return 768 end
    SanctuaryDB.filters.preset = "custom"
    SanctuaryDB.uiSize = { 500, 0 }
    _G["SanctuaryTab_protection"]:Click()
    ns.refreshUI()

    local scroll = _G.SanctuaryContentScroll
    local bar, thumb = scroll.bar, scroll.thumb
    local viewport = scroll:GetHeight() or 0
    local range = (scroll.child:GetHeight() or 0) - viewport
    check(range > 24, "the unfolded home screen is taller than its window at 500 px and 768 units")
    equal(bar:IsShown(), true, "so the bar is there")
    -- The track is the window it stands beside. The content area of the main
    -- window is resized with a plain `SetSize`, so a track that only follows
    -- `SetViewportSize` kept the 820 px it was built at inside a viewport of
    -- 380: four hundred pixels of piste below the bottom edge of the window,
    -- and a thumb travelling down a track a person cannot see the end of.
    equal(bar:GetHeight(), viewport,
        "the track is as tall as the window, not as tall as it was built")
    -- Everything that takes the mouse on this bar is a child of the track, and
    -- the track is hidden the moment the content fits: a screen with nothing to
    -- scroll gives the clicks back to whatever is drawn under it.
    equal(thumb:GetParent(), bar, "the thumb is inside the track")
    equal(bar.pageUp:GetParent(), bar, "the half of the track above it as well")
    equal(bar.pageDown:GetParent(), bar, "and the half below")
    equal(thumb.__mouseEnabled, true, "the thumb takes the mouse")
    check((bar:GetWidth() or 0) <= 10,
        "and the whole column that does stays inside the margin the screens keep "
            .. "clear on their right (" .. tostring(bar:GetWidth()) .. " px)")

    -- The thumb stands for the share of the screen on show, and it starts at
    -- the top of the track because that is where the screen is being read.
    check((thumb:GetHeight() or 0) < (bar:GetHeight() or 0),
        "the thumb is shorter than its track (" .. tostring(thumb:GetHeight())
            .. " of " .. tostring(bar:GetHeight()) .. ")")
    local _, _, _, _, topY = thumb:GetPoint()
    equal(topY, 0, "and it is at the top of it while the screen is read from the top")
    local travel = (bar:GetHeight() or 0) - (thumb:GetHeight() or 0)
    check(travel > 0, "so it has somewhere to travel")

    -- Pulled half way down: the content comes with it, and the two ways of
    -- saying where the view is agree.
    GetCursorPosition = function() return 0, 500 end
    thumb:GetScript("OnMouseDown")(thumb)
    GetCursorPosition = function() return 0, 500 - travel / 2 end
    thumb:GetScript("OnUpdate")(thumb, 0)
    check((scroll.offset or 0) > 0, "pulling the thumb down scrolls the screen down")
    equal(scroll:GetVerticalScroll(), scroll.offset, "and the frame is where the offset says")
    check(math.abs(scroll.offset - range / 2) < 1,
        "half the track is half the screen (" .. tostring(scroll.offset)
            .. " of " .. tostring(range) .. ")")
    local _, _, _, _, halfY = thumb:GetPoint()
    check(math.abs(-halfY - travel / 2) < 1, "and the thumb is half way down its track")

    -- Pulled past the end: the bottom of the screen and the bottom of the track
    -- are the same place, and neither goes further.
    GetCursorPosition = function() return 0, 500 - travel * 4 end
    thumb:GetScript("OnUpdate")(thumb, 0)
    equal(scroll.offset, range, "pulled to the end, the screen is at its bottom")
    equal(scroll:GetVerticalScroll(), range, "the frame with it")
    local _, _, _, _, endY = thumb:GetPoint()
    check(math.abs(-endY - travel) < 0.001, "and the thumb at the bottom of its track")
    thumb:GetScript("OnDragStop")(thumb)
    equal(thumb:GetScript("OnUpdate"), nil, "letting the thumb go stops the follow")

    -- The wheel and the bar are one movement seen twice.
    scroll:GetScript("OnMouseWheel")(scroll, 1)
    equal(scroll.offset, range - 24, "a notch of wheel up is a notch of screen up")
    equal(scroll:GetVerticalScroll(), scroll.offset, "the frame with it")
    local _, _, _, _, wheelY = thumb:GetPoint()
    check(wheelY > endY, "and the thumb came back up the track with it")

    -- And clicking the track pages, from either end.
    scroll:GetScript("OnMouseWheel")(scroll, 40)
    equal(scroll.offset, 0, "the wheel goes back to the top of the screen and stops there")
    local page = math.min(range, math.max(24, viewport - 24))
    bar.pageDown:GetScript("OnMouseDown")(bar.pageDown)
    equal(scroll.offset, page, "a click in the track under the thumb advances a page")
    equal(scroll:GetVerticalScroll(), scroll.offset, "the frame with it")
    bar.pageUp:GetScript("OnMouseDown")(bar.pageUp)
    equal(scroll.offset, 0, "a click above it comes back one")
    equal(scroll:GetVerticalScroll(), 0, "the frame with it")

    GetCursorPosition = keptCursor
    UIParent.GetHeight = keptScreen
    SanctuaryDB.filters.preset = "all"
    SanctuaryDB.uiSize = nil
    ns.refreshUI()
end

-- A.5 -- clicking beside the drawer closes it in silence.
do
    ns.OpenPanel("allowed")
    local veil = _G.SanctuaryPanelVeil
    playedSounds = {}
    veil:GetScript("OnMouseDown")(veil)
    equal(#playedSounds, 0, "closing the drawer from the veil plays nothing")
    equal(_G.SanctuaryPanelAllowed:IsShown(), false, "and the drawer is closed")
    -- The window's own X keeps its sound: that one closes a window, which is the
    -- gesture the sound belongs to.
    local closeBtn = findButtonByLabel(mainFrame, "X")
    check(closeBtn ~= nil, "the window has its X")
    playedSounds = {}
    closeBtn:GetScript("OnClick")(closeBtn)
    equal(#playedSounds, 1, "and closing the window still sounds like closing a window")
    mainFrame:Show()
end


-- B.3 -- realm friends are off the allowed panel, and the mechanism stays.
do
    charFriends = { "Palz" }
    ns.invalidateWhitelist()
    ns.OpenPanel("allowed")
    ns.refreshUI()
    -- A group header is a row that folds: "> Name (n)" or "v Name (n)".
    local headers = {}
    local function walk(widget)
        for _, childWidget in ipairs(widget.__children or {}) do
            local text = childWidget.label and tostring(childWidget.label.__text or "") or ""
            if text:find("^[>v] ") then headers[#headers + 1] = text end
            walk(childWidget)
        end
    end
    walk(_G.SanctuaryPanelAllowed)
    equal(#headers, 3, "three automatic groups on the panel, not four")
    local joined = table.concat(headers, "\n")
    for _, key in ipairs({ "WL_SOURCE_BNET", "WL_SOURCE_GUILD", "WL_SOURCE_TRUST" }) do
        check(joined:find(ns.L[key], 1, true) ~= nil, "and " .. key .. " is one of them")
    end
    ns.ClosePanel()
    -- The mechanism itself is untouched: an old character friend still carries
    -- the native behaviour, and "Test a pseudo" still names it.
    local verdict = ns.describeAccessDecision("Palz")
    equal(verdict.list, "friend", "an old realm friend is still allowed, and still labelled")
    charFriends = {}
    ns.invalidateWhitelist()
    ns.refreshUI()
end


-- A.6 -- "Enhanced filtering in instances" answers to the box above it.
do
    SanctuaryDB.filters.scope = "strangers"
    SanctuaryDB.filters.preset = "custom"
    SanctuaryDB.filters.groupInvite = true
    _G["SanctuaryTab_protection"]:Click()
    ns.refreshUI()
    local strict, parent = _G.SanctuaryStrictCheck, _G.SanctuaryFilter_groupInvite
    local point, relativeTo, relativePoint, offsetX = strict:GetPoint()
    equal(point, "TOPLEFT", "the child hangs from the box it depends on")
    equal(relativeTo, parent, "the group-invite box itself, not a column and a number")
    equal(relativePoint, "BOTTOMLEFT", "on the row under it")
    equal(offsetX, 26, "indented by the sub-row indent of the mock-up")
    equal(strict.enabled, true, "and it can be ticked while its parent is ticked")

    SanctuaryDB.filters.strictGroupInviteSystemMessages = false
    _G.SanctuaryFilter_groupInvite:Click()
    equal(SanctuaryDB.filters.groupInvite, false, "unticking the parent")
    equal(strict.enabled, false, "greys the child")
    strict:GetScript("OnClick")(strict)
    equal(SanctuaryDB.filters.strictGroupInviteSystemMessages, false,
        "and a click on a greyed child changes nothing -- constat D.1")

    _G.SanctuaryFilter_groupInvite:Click()
    equal(strict.enabled, true, "ticking the parent again gives the child back")

    -- In "Everything" there is no parent on screen: the preset blocks group
    -- invitations by definition, so the box answers to question 1 alone.
    SanctuaryDB.filters.preset = "all"
    ns.refreshUI()
    equal(strict.enabled, true, "in Everything the box is live whatever groupInvite holds")
    SanctuaryDB.filters.scope = "blockedOnly"
    ns.refreshUI()
    equal(strict.enabled, false, "and greyed with the rest when nothing is filtered")
    SanctuaryDB.filters.scope = "strangers"
    ns.refreshUI()
end

-- A.7 -- the three add fields carry their labels the same way: below the field,
-- at the same distance. Allowed drew them ABOVE, blocked names at the bottom of
-- the section, patterns further down again -- three answers to one question
-- (constat D.4).
do
    local function rowOf(widget)
        local _, _, _, _, y = widget:GetPoint()
        return y or 0
    end
    -- The label carrying a given name, wherever it is drawn.
    local function chipRow(panel, needle)
        local found
        local function walk(widget)
            for _, childWidget in ipairs(widget.__children or {}) do
                if childWidget.remove and childWidget.label
                    and tostring(childWidget.label.__text or ""):find(needle, 1, true) then
                    found = found or childWidget
                end
                walk(childWidget)
            end
        end
        walk(panel)
        return found and rowOf(found)
    end

    ns.addAllowed("Labelone")
    ns.addBlocked("Labeltwo")
    ns.addPattern("labelthree")

    ns.OpenPanel("allowed")
    ns.refreshUI()
    local allowedInput = rowOf(_G.SanctuaryAllowedAddInput)
    local allowedChip = chipRow(_G.SanctuaryPanelAllowed, "Labelone")
    check(allowedChip ~= nil, "the allowed panel shows the name it was given")
    ns.ClosePanel()

    ns.OpenPanel("blocked")
    ns.refreshUI()
    local nameInput = rowOf(_G.SanctuaryBlockedAddInput)
    local nameChip = chipRow(_G.SanctuaryPanelBlocked, "Labeltwo")
    local patternInput = rowOf(_G.SanctuaryPatternAddInput)
    local patternChip = chipRow(_G.SanctuaryPanelBlocked, "labelthree")
    check(nameChip ~= nil and patternChip ~= nil, "and the blocked panel shows both of its own")

    if allowedChip and nameChip and patternChip then
        check(allowedChip < allowedInput,
            "the allowed labels are UNDER their field now, not above it")
        equal(allowedInput - allowedChip, nameInput - nameChip,
            "at exactly the distance the blocked names keep")
        equal(nameInput - nameChip, patternInput - patternChip,
            "and the patterns keep the same distance again")
    end

    ns.ClosePanel()
    ns.removeAllowed(ns.normalizeCharacterKey("Labelone"))
    ns.removeBlocked(ns.normalizeCharacterKey("Labeltwo"))
    ns.removePattern("labelthree")
end


-- A.8 -- the diagnostics screen takes the whole window (constat C.1).
do
    _G["SanctuaryTab_diagnostics"]:Click()
    for _, height in ipairs({ 0, 940 }) do
        SanctuaryDB.uiSize = { 780, height }
        ns.refreshUI()
        local scroll = _G.SanctuaryContentScroll
        local viewport = scroll:GetHeight() or 0
        local list, results = _G.SanctuaryDiagListScroll, _G.SanctuaryDiagResultScroll
        -- 60 px of header and buttons above the two columns, 18 of padding under
        -- them: everything else is theirs. Built at a flat 300 and never
        -- revisited, they left the bottom half of the window empty and the
        -- reading of eight blocks inside a half-height box.
        equal(list:GetHeight(), viewport - 60 - 18,
            "the catalogue column fills the window it is in")
        equal(results:GetHeight(), list:GetHeight(),
            "and the results column matches it, whatever the window measures")
        equal(scroll.bar:IsShown(), false,
            "so the screen itself never scrolls inside the window")
    end
    SanctuaryDB.uiSize = nil
    ns.refreshUI()
end

-- A.9 -- a field narrower than its own value shows the START of it.
do
    _G["SanctuaryTab_diagnostics"]:Click()
    ns.refreshUI()
    local field = _G.SanctuaryDiagArg_sim_invite
    check(field ~= nil, "the invitation simulation has its field")
    check((field:GetText() or ""):len() > 0, "with a value in it")
    equal(field:GetCursorPosition(), 0,
        "shown from the start of the text, not from its end -- capture 15")
    field:SetText("SanctuaryTestOtherName")
    field:SetCursorPosition(12)
    field:GetScript("OnEditFocusLost")(field)
    equal(field:GetCursorPosition(), 0, "and it goes back there when the field is left")
    field:SetText("SanctuaryTest")
    field:ShowFromStart()
end


-- A.2 -- the home screen scrolls where it has to, and the grip keeps a vertical
-- travel.
--
-- Decision 134: the window opens at the tallest the client's screen allows -- or
-- at what the screen on show asked for, whichever is the smaller -- and where
-- that is not enough, the home screen scrolls under it with a bar that reaches
-- the tester. The height is read off the screen, never off a design constant: a
-- Retail client at the default UI scale measures 768 units.
--
-- The "Compact doux v2" home screen (decisions 141-143) is short enough to fit
-- whole on a tall screen, which it was not before, so scrolling is no longer an
-- invariant of this screen -- what IS an invariant is that the bar shows exactly
-- when there is something under the fold, and that what is under it is reachable.
--
-- The travel is the part nothing was watching. `SetResizeBounds` had no double
-- in this harness, so applying the screen to BOTH bounds -- which collapses them
-- onto the same number on every screen of 954 units or less -- was a green run
-- and a window a person could only widen.
do
    local keptScreen, keptSize = UIParent.GetHeight, SanctuaryDB.uiSize
    SanctuaryDB.filters.preset = "all"
    SanctuaryDB.uiSize = nil
    -- What the window leaves the screen: a breathing edge at each end, and
    -- nothing else. The strip of tabs is INSIDE the frame now (decision 140), so
    -- there is no overhang left to carry twice -- the block further down
    -- measures that the strip really is inside.
    local reserve = 2 * 10
    for _, screen in ipairs({ 600, 768, 900 }) do
        UIParent.GetHeight = function() return screen end
        _G["SanctuaryTab_protection"]:Click()
        ns.refreshUI()
        -- The screen is a ceiling, not an order: a window whose content asks for
        -- less than the screen holds takes what it asked for.
        check(mainFrame:GetHeight() <= screen - reserve,
            "at " .. screen .. " units the window fits inside the screen ("
                .. tostring(mainFrame:GetHeight()) .. ")")

        local minWidth, minHeight, maxWidth, maxHeight = mainFrame:GetResizeBounds()
        equal(minWidth, 500, "the grip keeps its narrowest width at " .. screen)
        equal(maxWidth, 900, "and its widest")
        check(maxHeight <= screen - reserve,
            "the tallest the grip may drag to fits the screen at " .. screen
                .. " (" .. tostring(maxHeight) .. ")")
        check(minHeight < maxHeight, "and the grip still has a vertical travel at "
            .. screen .. " (" .. tostring(minHeight) .. " to " .. tostring(maxHeight) .. ")")

        local scroll = _G.SanctuaryContentScroll
        local child = scroll:GetScrollChild():GetHeight() or 0
        local viewport = scroll:GetHeight() or 0
        -- The bar shows exactly when there is something under the fold, and
        -- never otherwise: a bar beside a screen with nothing to scroll to is
        -- constat G.4, and a screen taller than its window with no bar is the
        -- half of decision 134 that says the home screen may scroll.
        local under = child > viewport
        equal(scroll.bar:IsShown(), under,
            "the bar shows exactly when the home screen runs under the fold at "
                .. screen .. " (" .. child .. " over " .. viewport .. ")")
        if under then
            equal(scroll.bar:GetHeight(), viewport,
                "a track exactly as tall as the window at " .. screen)
            -- And a thumb that says how much of the screen is on show. Whether
            -- it can be pulled, and where it lands, is the A.2 block above; here
            -- it is that a lift exists wherever there is something to lift to.
            check((scroll.thumb:GetHeight() or 0) < (scroll.bar:GetHeight() or 0),
                "with a thumb shorter than its own track at " .. screen
                    .. " (" .. tostring(scroll.thumb:GetHeight()) .. " of "
                    .. tostring(scroll.bar:GetHeight()) .. ")")
        end
        -- The tester is the last row of the screen: what matters now is not that
        -- it is on show, it is that it is inside the height the bar scrolls
        -- through. Its own anchor, plus the padding the tab frames are offset by
        -- and the height of the field itself, against the height of the content.
        local _, _, _, _, testerY = _G.SanctuaryTestInput:GetPoint()
        check(18 - (testerY or 0) + 24 <= child,
            "and the tester is inside the height that scrolls at " .. screen)
    end

    -- The far end of the range: 954 units is the tallest screen on which the two
    -- bounds used to meet, so it is the last one where the travel could be lost
    -- again without anything else moving.
    UIParent.GetHeight = function() return 954 end
    ns.refreshUI()
    local _, tallMin, _, tallMax = mainFrame:GetResizeBounds()
    check(tallMin < tallMax,
        "at 954 units -- the last screen the two bounds used to meet on -- the "
            .. "grip still has a travel (" .. tostring(tallMin) .. " to " .. tostring(tallMax) .. ")")

    -- The other screens are shorter than the window they are given, and a bar
    -- beside a screen with nothing under it is the fault this lot came from
    -- (constat G.4). Measured on the client's own screen, 768 units.
    UIParent.GetHeight = function() return 768 end
    for _, tab in ipairs({ "journal", "advanced", "about", "diagnostics" }) do
        _G["SanctuaryTab_" .. tab]:Click()
        ns.refreshUI()
        local scroll = _G.SanctuaryContentScroll
        equal(scroll.bar:IsShown(), false, tab .. " is shorter than its window and does not scroll")
    end

    -- And where the room IS there, nothing scrolls at all: the whole home screen
    -- fits, bar included, which is what a lowered UI scale buys.
    UIParent.GetHeight = function() return 1200 end
    _G["SanctuaryTab_protection"]:Click()
    ns.refreshUI()
    local scroll = _G.SanctuaryContentScroll
    check((scroll:GetScrollChild():GetHeight() or 0) <= (scroll:GetHeight() or 0),
        "on a screen with the room the whole home screen is in the window")
    equal(scroll.bar:IsShown(), false, "and there is nothing to scroll")

    UIParent.GetHeight = keptScreen
    SanctuaryDB.uiSize = keptSize
    _G["SanctuaryTab_protection"]:Click()
    ns.refreshUI()
end

-- A.2 again, from the other side: a client that says nothing about its screen
-- gets the height that was asked for. `fitToScreen` reads `UIParent:GetHeight`,
-- and a widget that answers nil, 0 or a string is a widget whose answer has to
-- be dropped -- taking it at face value would open the window at the floor of
-- the fit, 300 px, on a client that had simply not been asked yet.
do
    local kept = UIParent.GetHeight
    _G["SanctuaryTab_protection"]:Click()
    ns.refreshUI()
    local asked = mainFrame:GetHeight()
    check(asked >= 740 + 40 + 30 + 30,
        "with no screen to fit, the window is as tall as the home screen asked ("
            .. tostring(asked) .. ")")
    for _, answer in ipairs({ "nil", 0, -100, "tall" }) do
        UIParent.GetHeight = function()
            if answer == "nil" then return nil end
            return answer
        end
        ns.refreshUI()
        equal(mainFrame:GetHeight(), asked,
            "an unusable screen height (" .. tostring(answer) .. ") is dropped, not applied")
    end
    UIParent.GetHeight = kept
    ns.refreshUI()
end

-- A.2, third side: the tester's ANSWER is measured, not reserved.
--
-- The row kept a flat 40 px for a sentence that wraps, and beside the field the
-- sentence had `innerWidth() - 360` to wrap into -- 104 px at the smallest
-- window. A blocked guild mate's verdict ran seven lines and 84 px there, the
-- screen answered a height that had never heard of the other 44, and since the
-- content area is `max(that height, viewport)` there was no travel and no bar
-- either: the answer was simply cut off. The brief asks for the tester AND its
-- answer at the minimum size, so what is checked is the bottom of the sentence,
-- not the top of the field.
do
    local kept = SanctuaryDB.uiSize
    local keptGuild, keptInGuild = guildMembers, inGuild
    guildMembers = { "Ombrelune-ConseildesOmbres" }
    inGuild = true
    ns.invalidateWhitelist()
    ns.addBlocked("Ombrelune-ConseildesOmbres")

    SanctuaryDB.uiSize = { 500, 890 }
    _G["SanctuaryTab_protection"]:Click()
    ns.refreshUI()
    local scroll = _G.SanctuaryContentScroll
    local field, answer = _G.SanctuaryTestInput, _G.SanctuaryTestAnswer

    field:SetText("Ombrelune-ConseildesOmbres")
    field:GetScript("OnTextChanged")(field)
    check((answer:GetText() or ""):find(ns.L["LIST_GUILD"], 1, true) ~= nil,
        "the longest answer the tester has: blocked, over a guild mate")
    check((answer:GetStringHeight() or 0) > 12,
        "and at the smallest width it takes more than one line")

    -- The criterion of the brief, on the bottom of the SENTENCE rather than on
    -- the top of the field: 18 px of padding the tab frames are offset by, the
    -- answer's own anchor, and the height it measures.
    local viewport = scroll:GetHeight() or 0
    local _, _, _, _, answerY = answer:GetPoint()
    local bottom = 18 - (answerY or 0) + (answer:GetStringHeight() or 0)
    check(bottom <= viewport or scroll.bar:IsShown(),
        "the bottom of the answer is inside the window, or there is a bar to "
            .. "reach it with (" .. bottom .. " vs " .. viewport .. ")")

    -- And the mechanism under it. The content area is `max(what the screen
    -- answered, the viewport)` and the answer never goes below the minimum
    -- bound, so on the folded screen the viewport swallows the difference. On
    -- "I choose" unfolded -- taller than either bound, which is why it scrolls
    -- at all -- what the screen answered IS the content area, and the sentence's
    -- lines show up in it. Reserved at a flat 40, these two numbers were equal.
    local keptPreset = SanctuaryDB.filters.preset
    SanctuaryDB.filters.preset = "custom"
    ns.refreshUI()
    local withAnswer = scroll:GetScrollChild():GetHeight() or 0
    field:SetText("")
    field:GetScript("OnTextChanged")(field)
    local withoutAnswer = scroll:GetScrollChild():GetHeight() or 0
    check(withAnswer > withoutAnswer,
        "a wrapping answer makes the screen taller by the lines it takes ("
            .. withAnswer .. " vs " .. withoutAnswer .. ")")
    SanctuaryDB.filters.preset = keptPreset

    ns.removeBlocked(ns.normalizeCharacterKey("Ombrelune-ConseildesOmbres"))
    guildMembers, inGuild = keptGuild, keptInGuild
    ns.invalidateWhitelist()
    SanctuaryDB.uiSize = kept
    ns.refreshUI()
end

-- A.2, fourth side: nothing of the window is outside the window.
--
-- The strip of tabs used to be anchored under the frame's bottom edge, and the
-- window opens centred, so the room left over was split evenly above and below
-- it: a reserve of 20 px in total left 10 px under a window that had 22 px of
-- tabs hanging there, and on a default Retail screen -- 768 units -- the bottom
-- half of every tab was off the screen with its label cut. SetClampedToScreen
-- never caught it: it clamps the frame, which was inside the screen all along.
--
-- Decision 140 took the whole problem away by putting the strip inside the
-- window. This is the check that it stays there: every tab is anchored to the
-- strip, the strip is anchored under the title bar, and the bottom of the tallest
-- one is above the frame's own bottom edge -- so there is nothing left for a
-- reserve to protect and nothing SetClampedToScreen cannot see.
do
    local keptScreen, keptSize = UIParent.GetHeight, SanctuaryDB.uiSize
    SanctuaryDB.uiSize = nil
    UIParent.GetHeight = function() return 768 end
    _G["SanctuaryTab_protection"]:Click()
    ns.refreshUI()
    local strip = _G.SanctuaryTabBar
    local _, _, _, _, stripY = strip:GetPoint()
    for _, key in ipairs({ "protection", "journal", "advanced", "about" }) do
        local tab = _G["SanctuaryTab_" .. key]
        equal(tab:GetParent(), strip, "the " .. key .. " tab hangs from the strip")
        local _, tabRelative, _, _, tabY = tab:GetPoint()
        equal(tabRelative, strip, "and is placed against it, not against the window")
        -- Inside the strip: it starts at the strip's top and is no taller than it.
        equal(tabY, 0, "flush with the top of the strip")
        check((tab:GetHeight() or 0) <= (strip:GetHeight() or 0),
            "and no taller than the strip that holds it")
    end
    -- And the strip itself is inside the frame: it starts below the title bar
    -- and ends well above the bottom edge.
    check(-(stripY or 0) + (strip:GetHeight() or 0) < (mainFrame:GetHeight() or 0),
        "the strip ends inside the window, not under it")

    -- Sideways too, and at the width where it is tightest: five French labels at
    -- the mock-up's padding come to more than the 500 px the grip may drag the
    -- window down to, and a tab hanging off the right edge of a strip is a tab
    -- nobody can click -- there is nowhere for a row of tabs to wrap to.
    for _, width in ipairs({ 500, 640, 900 }) do
        SanctuaryDB.debugEnabled = true
        SanctuaryDB.uiSize = { width, 700 }
        ns.refreshTabBar()
        ns.refreshUI()
        local far = 0
        for _, key in ipairs({ "protection", "journal", "advanced", "about", "diagnostics" }) do
            local tab = _G["SanctuaryTab_" .. key]
            local _, _, _, tabX = tab:GetPoint()
            check(tab:IsShown(), "the " .. key .. " tab is on the strip at " .. width)
            far = math.max(far, (tabX or 0) + (tab:GetWidth() or 0))
        end
        check(far <= width + 1,
            "the five tabs fit the strip at " .. width .. " (" .. far .. " px used)")
    end
    SanctuaryDB.debugEnabled = false
    SanctuaryDB.uiSize = nil
    ns.refreshTabBar()
    ns.refreshUI()
    local spare = (768 - (mainFrame:GetHeight() or 0)) / 2
    check(spare >= 10,
        "and a default Retail screen keeps its breathing edge (" .. spare .. " px)")
    UIParent.GetHeight = keptScreen
    SanctuaryDB.uiSize = keptSize
    ns.refreshUI()
end


end)()


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
-- entries: it runs the offline check on the settings file, and the session
-- protocol and that check have to name the same markers -- a session measuring
-- something other than what it claims to is worse than no session at all.
--
-- Both tools left the repository with 1.0.0 (decisions 112, 114, 116): they only
-- ever serve a session, the add-on never calls them, and they live in
-- internal_docs/qa/, which is ignored. A clone of the published repository does
-- not have them, and there is then nothing here to check -- which is a silence,
-- not a failure. What follows runs only when they are there.
local qaToolsDir = repoRoot .. "/internal_docs/qa"
local function qaTool(name)
    local handle = io.open(qaToolsDir .. "/" .. name, "r")
    if not handle then return nil end
    handle:close()
    return qaToolsDir .. "/" .. name
end
local checkerPath, protocolPath = qaTool("check_qa_run.lua"), qaTool("qa_protocol.py")

if not checkerPath or not protocolPath then
    print("-- outillage de session absent (internal_docs/qa) : controles sautes")
else
;(function()
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
            checkerPath, since, fixturePath)
    else
        command = string.format('%q %q %q 2>&1', interpreter,
            checkerPath, fixturePath)
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

-- A disagreement here stops the harness rather than costing Vincent
-- forty-five minutes of the wrong test.
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
    checkerPath))
check(checkerMarkers ~= nil and #checkerMarkers > 0,
    "the offline check lists the markers it reads")

local protocolMarkers = readLines(string.format('python3 %q --markers 2>&1',
    protocolPath))
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
    protocolPath)) == true
    or os.execute(string.format('python3 %q --check >/dev/null 2>&1',
    protocolPath)) == 0,
    "the session protocol passes its own structural check")

end)()
end

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


-- ===========================================================================
-- SECTION: one decision per message
-- ===========================================================================

-- Every chat message used to be judged twice: once by the filter, deciding
-- whether the line shows, once by the event handler, deciding what is journalled,
-- counted, announced and closed. The two spelt the same order out, so a fix
-- landed on one of them had one chance in two of landing on the right one -- and
-- three fixes in this mission landed on one side only.
--
-- What follows is the guard against that, and it is written as a parity claim
-- rather than as a list of expected verdicts: whatever the add-on decides, the
-- two halves have to decide it together. `discard` is the filter's answer; the
-- journal entry, the session counter, the chat line and the closed whisper tab
-- are the handler's. They rise together or not at all.
--
-- The first block uses nothing but the API the harness already had, so it can be
-- run against the tree before this change: it fails there on the self-whisper
-- lines, on the open defect below and on the chat diagnostic, and nowhere else.
-- The second block reads the new API and only exists after it.
--
-- Each one is a scope of its own rather than a `do ... end`: the enclosing
-- function is at Lua's ceiling of 200 live locals, which is the same reason the
-- section below it is written this way.
;(function()

-- The thirteen character-message events, written out rather than read from
-- `ns.CHAT_KINDS`: this block has to be runnable against a tree that has no such
-- table, and a test that reads its subject's own table proves nothing about it.
local ROWS = {
    { event = "CHAT_MSG_WHISPER",    kind = "whisper", closesTab = true },
    { event = "CHAT_MSG_SAY",        kind = "say" },
    { event = "CHAT_MSG_YELL",       kind = "yell" },
    { event = "CHAT_MSG_EMOTE",      kind = "emote" },
    { event = "CHAT_MSG_TEXT_EMOTE", kind = "emote" },
    { event = "CHAT_MSG_CHANNEL",    kind = "channel" },
}
for _, event in ipairs(ns.GROUP_CHAT_EVENTS) do
    ROWS[#ROWS + 1] = { event = event, kind = "group" }
end

local SENDERS = {
    { label = "the player, bare",            name = "Victim" },
    { label = "the player, realm-qualified", name = "Victim-TestRealm" },
    { label = "a namesake on another realm", name = "Victim-Ysondre" },
    { label = "a name on the blocked list",  name = "Harasser-TestRealm" },
    { label = "a name a pattern catches",    name = "Nastyone-TestRealm" },
    { label = "a name allowed by hand",      name = "Trusted-TestRealm" },
    { label = "a guild member",              name = "Guildie-TestRealm" },
    { label = "a group member",              name = "Teammate-TestRealm" },
    { label = "a stranger",                  name = "Stranger-TestRealm" },
}

-- What "the filter is ticked" means is not the same question for every kind, and
-- the three answers are exactly the three gates the core knows about.
local function setGate(kind, on)
    if kind == "channel" then
        SanctuaryDB.filters.channelMode = on and "all" or "none"
    elseif kind ~= "group" then
        SanctuaryDB.filters[kind] = on
    end
end

-- Chat frames of our own, so the whisper-tab half can be counted. ChatFrame1
-- stays DEFAULT_CHAT_FRAME: it carries the AddMessage envelope the system-line
-- part needs, and it has no `chatType`, so the tab sweep walks past it.
local savedFrames = {}
for i = 1, 20 do savedFrames[i] = _G["ChatFrame" .. i] end
for i = 2, 20 do _G["ChatFrame" .. i] = nil end
local whisperTab = { chatType = "WHISPER", chatTarget = "" }
local bnetTab = { chatType = "BN_WHISPER", chatTarget = "" }
ChatFrame5 = whisperTab
ChatFrame6 = bnetTab
ns.hookChatOutputDiagnostics()

local function prepare()
    resetModelState()
    SanctuaryDB.debugEnabled = false
    SanctuaryDB.logging.enabled = true
    SanctuaryDB.logging.maxEntries = 5000
    SanctuaryDB.notifications.mode = "verbose"
    SanctuaryCharDB.sessionStats = { blockedCount = 0, blockedByType = {} }
    runTimers(3)
end

prepare()
ns.addBlocked("Harasser")
ns.addPattern("nasty")
ns.addAllowed("Trusted")
guildMembers = { "Guildie-TestRealm" }
inGuild = true
groupMembers = { "Teammate-TestRealm" }
inGroup = true
ns.invalidateWhitelist()

local STATES = {
    { label = "filter ticked",   gate = true,  enabled = true },
    { label = "filter unticked", gate = false, enabled = true },
    { label = "add-on off",      gate = true,  enabled = false },
}

for _, state in ipairs(STATES) do
    -- Written straight into the override rather than through `ns.setEnabled`,
    -- which prints a line: the chat line is one of the four things counted here.
    if state.enabled then
        SanctuaryCharDB.overrides.enabled = nil
    else
        SanctuaryCharDB.overrides.enabled = false
    end
    for _, row in ipairs(ROWS) do
        setGate(row.kind, state.gate)
        for _, sender in ipairs(SENDERS) do
            -- `logBlock` drops a repeat of the same type and sender inside one
            -- second, so the clock has to move between two cases.
            now = now + 2
            whisperTab.chatTarget = sender.name
            local label = row.event .. ", " .. sender.label .. ", " .. state.label
            -- Every case sends the same line from the same person, and the
            -- Journal now folds those into one entry with a count. Emptied
            -- between cases, "one interaction, one line" is what it measures
            -- again -- which is the parity this block is about.
            ns.clearJournal()
            local beforeLog = #SanctuaryDB.log
            local beforeCount = SanctuaryCharDB.sessionStats.blockedCount
            local beforeLines = #chatMessages
            local beforeClosed = #closedChatFrames

            local discard = dispatchChatFilter(row.event, "hello", sender.name)
            fire(row.event, "hello", sender.name)
            runTimers(3)

            local expected = discard and 1 or 0
            equal(#SanctuaryDB.log - beforeLog, expected,
                label .. ": the journal follows the filter")
            equal(SanctuaryCharDB.sessionStats.blockedCount - beforeCount, expected,
                label .. ": the session counter follows the filter")
            equal(#chatMessages - beforeLines, expected,
                label .. ": the chat line follows the filter")
            if row.closesTab then
                equal(#closedChatFrames - beforeClosed, expected,
                    label .. ": the whisper tab follows the filter")
            end
        end
    end
end
SanctuaryCharDB.overrides.enabled = nil

-- The open defect this release was sent back to the plan for. A player writing
-- themselves a note gets a CHAT_MSG_WHISPER whose sender is the player; the
-- filter let it through and the handler did not, so the note showed on screen
-- while the Journal recorded it, the session counted it, the chat announced it
-- and the whisper tab was closed under the person's fingers. Nothing Sanctuary
-- does may touch what the player says to themselves -- their own blocked list
-- and their own patterns included.
prepare()
SanctuaryDB.filters.whisper = true
local OWN_LISTS = {
    { label = "with empty lists", apply = function() end },
    { label = "with their own name in their own blocked list",
      apply = function() ns.addBlocked("Victim") end },
    { label = "under one of their own patterns",
      apply = function() ns.addPattern("victi") end },
}
for _, spelling in ipairs({ "Victim", "Victim-TestRealm" }) do
    for _, listState in ipairs(OWN_LISTS) do
        wipe(SanctuaryDB.blockedNames)
        SanctuaryDB.keywords = {}
        listState.apply()
        ns.invalidateWhitelist()
        now = now + 2
        whisperTab.chatTarget = spelling
        local label = "a whisper to oneself as " .. spelling .. ", " .. listState.label
        local beforeLog = #SanctuaryDB.log
        local beforeCount = SanctuaryCharDB.sessionStats.blockedCount
        local beforeLines = #chatMessages
        local beforeClosed = #closedChatFrames

        local discard = dispatchChatFilter("CHAT_MSG_WHISPER", "note to self", spelling)
        fire("CHAT_MSG_WHISPER", "note to self", spelling)
        runTimers(3)

        equal(discard, false, label .. ": the line shows")
        equal(#SanctuaryDB.log, beforeLog, label .. ": nothing is journalled")
        equal(SanctuaryCharDB.sessionStats.blockedCount, beforeCount,
            label .. ": nothing is counted")
        equal(#chatMessages, beforeLines, label .. ": nothing is announced")
        equal(#closedChatFrames, beforeClosed, label .. ": the tab stays open")
    end
end

-- Battle.net. Sanctuary blocks nobody there, so the only question is the
-- whitelist one -- and the filter and the handler have to answer it together,
-- tab included.
prepare()
SanctuaryDB.filters.whisper = true
bnetFriends = {
    { bnetAccountID = 501, accountName = "Battle Friend",
      gameAccountInfo = { characterName = "Onlinechar" } },
}
ns.invalidateWhitelist()
local BNET_CASES = {
    { label = "a Battle.net friend", account = "Battle Friend", filter = true },
    { label = "a Battle.net friend whose character is in the group",
      account = "Battle Friend", filter = true, group = true },
    { label = "an unknown account", account = "Unknown Battle", filter = true },
    { label = "an unknown account, whisper filter unticked",
      account = "Unknown Battle", filter = false },
}
for _, case in ipairs(BNET_CASES) do
    SanctuaryDB.filters.whisper = case.filter
    inGroup = case.group and true or false
    groupMembers = case.group and { "Onlinechar-TestRealm" } or {}
    ns.invalidateWhitelist()
    now = now + 2
    bnetTab.chatTarget = case.account
    local label = "a Battle.net whisper from " .. case.label
    ns.clearJournal()
    local beforeLog = #SanctuaryDB.log
    local beforeClosed = #closedChatFrames

    local discard = dispatchChatFilter("CHAT_MSG_BN_WHISPER", "hello", case.account)
    fire("CHAT_MSG_BN_WHISPER", "hello", case.account)
    runTimers(3)

    local expected = discard and 1 or 0
    equal(#SanctuaryDB.log - beforeLog, expected, label .. ": the journal follows the filter")
    equal(#closedChatFrames - beforeClosed, expected, label .. ": the tab follows the filter")
end
inGroup = false
groupMembers = {}
bnetFriends = {}
ns.invalidateWhitelist()

-- The invite system line. Three readers of one decision: the registry filter,
-- the event handler, and the AddMessage envelope of last resort.
prepare()
ns.addBlocked("Harasser")
ns.addAllowed("Trusted")
ns.invalidateWhitelist()
local SYSTEM_CASES = {
    { label = "a blocked name",                 name = "Harasser", filter = true },
    { label = "a blocked name, filter unticked", name = "Harasser", filter = false },
    { label = "a stranger",                     name = "Stranger", filter = true },
    { label = "a stranger, filter unticked",    name = "Stranger", filter = false },
    { label = "a friend",                       name = "Trusted",  filter = true },
    { label = "a stranger, in a group",         name = "Stranger", filter = true, group = true },
}
for _, case in ipairs(SYSTEM_CASES) do
    SanctuaryDB.filters.groupInvite = case.filter
    inGroup = case.group and true or false
    groupMembers = case.group and { "Teammate-TestRealm" } or {}
    ns.invalidateWhitelist()
    now = now + 2
    local label = "an already-group invite line from " .. case.label
    local message = string.format(ERR_INVITED_ALREADY_IN_GROUP_SS, case.name, case.name)

    local discard = dispatchChatFilter("CHAT_MSG_SYSTEM", message)
    ns.clearJournal()
    local beforeLog = #SanctuaryDB.log
    fire("CHAT_MSG_SYSTEM", message)
    equal(#SanctuaryDB.log - beforeLog, discard and 1 or 0,
        label .. ": the journal follows the filter")

    local beforeLines = #chatMessages
    DEFAULT_CHAT_FRAME:AddMessage(message)
    equal(#chatMessages - beforeLines, discard and 0 or 1,
        label .. ": the envelope withholds exactly what the filter discards")

    local simulated = ns.simulateInvite(case.name)
    equal(simulated.alreadyGroupSuppressed, discard,
        label .. ": the tester describes the same screen")
end
inGroup = false
groupMembers = {}

-- The chat diagnostic. It answers "would a blocked invite line have been
-- stopped", and it used to read the trust decision and the checkbox separately
-- and multiply them -- which left the always-blocked gate out of its answer. A
-- name on the blocked list, with the group-invite filter unticked and no
-- envelope in place, was reported "visible": the diagnostic said nothing was
-- wrong on exactly the path the blocked list exists for.
for _, case in ipairs({
    { label = "a name on the blocked list",
      apply = function() ns.addBlocked("SanctuaryDiagnosticBlocked") end },
    { label = "a name a pattern catches",
      apply = function() ns.addPattern("sanctuarydiagnostic") end },
}) do
    prepare()
    case.apply()
    SanctuaryDB.filters.groupInvite = false
    ns.invalidateWhitelist()
    local savedDefaultFrame = DEFAULT_CHAT_FRAME
    local rawLines = {}
    DEFAULT_CHAT_FRAME = {
        AddMessage = function(_, message) rawLines[#rawLines + 1] = message end,
    }
    local diagnostic = ns.runChatDiagnostic("invite")
    DEFAULT_CHAT_FRAME = savedDefaultFrame
    equal(diagnostic.output, "unguarded",
        "the chat diagnostic reports an unguarded line for " .. case.label
            .. " with the group-invite filter unticked")
    equal(#rawLines, 1, "and the probe line did reach the unwrapped frame for " .. case.label)
end

-- Same scope, the other way round: with the filter unticked and nobody blocked,
-- there is nothing to guard and the diagnostic must not cry wolf.
prepare()
SanctuaryDB.filters.groupInvite = false
local savedDefaultFrame = DEFAULT_CHAT_FRAME
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
equal(ns.runChatDiagnostic("invite").output, "visible",
    "and reports a visible line when nothing would have been stopped")
DEFAULT_CHAT_FRAME = savedDefaultFrame

for i = 1, 20 do _G["ChatFrame" .. i] = savedFrames[i] end
ns.hookChatOutputDiagnostics()
prepare()

end)()

-- ---------------------------------------------------------------------------
-- ... and the structure that makes it true
-- ---------------------------------------------------------------------------

-- The block above proves the two halves agree. This one proves why they cannot
-- disagree: there is one decision function, and the filters and handlers are
-- generated from one table rather than written out.

;(function()

check(type(ns.decideChat) == "function", "the core publishes one decision for chat messages")
check(type(ns.CHAT_KINDS) == "table", "and the table its filters and handlers are generated from")

resetModelState()
SanctuaryDB.debugEnabled = true
SanctuaryDB.filters.whisper = true
SanctuaryDB.filters.say = true
SanctuaryDB.filters.yell = true
SanctuaryDB.filters.emote = true
SanctuaryDB.filters.channelMode = "all"
ns.addBlocked("Harasser")
ns.invalidateWhitelist()

for _, row in ipairs(ns.CHAT_KINDS) do
    check(type(chatFilters[row.event]) == "function", "a filter is registered for " .. row.event)
    ns.resetDebugLog()
    now = now + 2
    fire(row.event, "hello", "Harasser-TestRealm")
    local entry = lastDebug("CHAT_DECISION")
    check(entry ~= nil and entry.data.kind == row.logType,
        "and a handler answers for " .. row.event)
end

-- The two whose sender is not a character keep a filter and a handler of their
-- own, because neither goes through `decideChat`.
for _, event in ipairs({ "CHAT_MSG_SYSTEM", "CHAT_MSG_BN_WHISPER" }) do
    check(type(chatFilters[event]) == "function", "a filter is registered for " .. event)
    check(eventFrames[event] ~= nil, "and " .. event .. " is registered as an event")
end

-- The filter's answer is the decision, with nothing added and nothing lost.
SanctuaryDB.debugEnabled = false
ns.addPattern("nasty")
ns.addAllowed("Trusted")
guildMembers = { "Guildie-TestRealm" }
inGuild = true
groupMembers = { "Teammate-TestRealm" }
inGroup = true
ns.invalidateWhitelist()
for _, row in ipairs(ns.CHAT_KINDS) do
    for _, sender in ipairs({
        "Victim", "Victim-TestRealm", "Victim-Ysondre", "Harasser-TestRealm",
        "Nastyone-TestRealm", "Trusted-TestRealm", "Guildie-TestRealm",
        "Teammate-TestRealm", "Stranger-TestRealm",
    }) do
        equal((ns.decideChat(row.kind, sender)),
            dispatchChatFilter(row.event, "hello", sender),
            "the decision and the registered filter agree on " .. row.event
                .. " from " .. sender)
    end
end
inGuild = false
inGroup = false
guildMembers = {}
groupMembers = {}
resetModelState()

end)()

-- ---------------------------------------------------------------------------
-- The day's fold survives a /reload
-- ---------------------------------------------------------------------------

-- A /reload -- and a reconnection -- rebuilds the Lua state and keeps the
-- SavedVariables: the journal comes back with the day's entries while the merge
-- index comes back empty. Loading the chunk a second time into a fresh namespace,
-- over the same `SanctuaryDB`, IS that. Before the index was read back from the
-- log, the first repeat after a loading screen opened a second line for a
-- message the day was already counting -- three reconnections, three counters,
-- three ranges for one announcement.
--
-- Last in the file on purpose: the second chunk registers its own event frame
-- and its own chat filters, and nothing must be tested through those afterwards.
do

resetModelState()
SanctuaryDB.logging.enabled = true
ns.clearJournal()
setHarnessDay("2026-08-24")

local PSEUDO, LINE = "Reloader-TestRealm", "wts my stuff"

ns.logBlock("channel", PSEUDO, LINE, nil, nil)
now = now + 5
ns.logBlock("channel", PSEUDO, LINE, nil, nil)
equal(#SanctuaryDB.log, 1, "before the reload the day holds one entry")
equal(SanctuaryDB.log[1].count, 2, "counted twice")
local openedAt, openedOn = SanctuaryDB.log[1].t, SanctuaryDB.log[1].d

local reloaded = {}
assert(loadfile(repoRoot .. "/Locales.lua"))("Sanctuary", reloaded)
assert(loadfile(repoRoot .. "/Sanctuary.lua"))("Sanctuary", reloaded)

now = now + 10
reloaded.logBlock("channel", PSEUDO, LINE, nil, nil)
equal(#SanctuaryDB.log, 1, "the first repeat after the reload folds into the same entry")
equal(SanctuaryDB.log[1].count, 3, "and adds one to the count")
equal(SanctuaryDB.log[1].t, openedAt, "the entry still opens where it opened")
equal(SanctuaryDB.log[1].d, openedOn, "and still shows the date it showed")
equal(SanctuaryDB.log[1].t2, time(), "with the range grown to the arrival that came in")

-- The throttle, itself in memory, restarts empty: the next copy is shown again,
-- which is the accepted behaviour. That arrival is one of the ones the "xN"
-- counts (decision 132, Q2), and it now lands on the entry the day already
-- holds instead of on nothing.
now = now + 10
check(reloaded.noteShownArrival("channel", PSEUDO, LINE),
    "a copy shown after the reload finds the day's entry")
equal(SanctuaryDB.log[1].count, 4, "and is counted on it")

-- The day is still the bound: reloading does not make yesterday's line today's.
setHarnessDay("2026-08-25")
now = now + 10
reloaded.logBlock("channel", PSEUDO, LINE, nil, nil)
equal(#SanctuaryDB.log, 2, "the same line the next day still opens a new entry")
equal(SanctuaryDB.log[2].count, nil, "which counts as one, and says nothing about it")

-- Duplicates the current build has already written into somebody's journal: the
-- key keeps the most recent entry, the older ones stop moving, and neither is
-- rewritten -- the one with no `count` reads as one and goes to two.
setHarnessDay("2026-08-26")
reloaded.clearJournal()
SanctuaryDB.log[1] = { t = time(), d = "2026-08-26 12:00:00", type = "channel",
    name = "Twice", realm = "TestRealm", msg = "same old line", count = 3 }
SanctuaryDB.log[2] = { t = time(), d = "2026-08-26 12:00:00", type = "channel",
    name = "Twice", realm = "TestRealm", msg = "same old line" }
now = now + 10
reloaded.logBlock("channel", "Twice-TestRealm", "same old line", nil, nil)
equal(#SanctuaryDB.log, 2, "an inherited duplicate does not open a third entry")
equal(SanctuaryDB.log[1].count, 3, "the older of the two stops moving")
equal(SanctuaryDB.log[2].count, 2, "and the most recent one takes the occurrence, counted from one")

-- Rotation reads back what the walk indexed. An entry handed a key by the walk
-- and then evicted must stop collecting occurrences -- and the ones that stay
-- must go on folding, which is the whole point on a full journal.
setHarnessDay("2026-08-27")
reloaded.clearJournal()
SanctuaryDB.logging.maxEntries = 3
for index, line in ipairs({ "the evicted line", "the next one out", "the surviving line" }) do
    SanctuaryDB.log[index] = { t = time(), d = "2026-08-27 12:00:00", type = "channel",
        name = "Rotator", realm = "TestRealm", msg = line }
end
now = now + 10
reloaded.logBlock("channel", "Rotator-TestRealm", "one line too many", nil, nil)
equal(#SanctuaryDB.log, 3, "a fourth line rotates the oldest of the three read back out")
equal(SanctuaryDB.log[1].msg, "the next one out", "and it is the oldest that goes")
now = now + 10
reloaded.logBlock("channel", "Rotator-TestRealm", "the surviving line", nil, nil)
equal(#SanctuaryDB.log, 3, "a line still in the journal goes on folding after the reload")
equal(SanctuaryDB.log[2].count, 2, "with one more occurrence on it")
now = now + 10
reloaded.logBlock("channel", "Rotator-TestRealm", "the evicted line", nil, nil)
equal(SanctuaryDB.log[3].msg, "the evicted line", "the evicted line comes back")
equal(SanctuaryDB.log[3].count, nil,
    "as a new entry, not one more occurrence of a line nobody can reach")
SanctuaryDB.logging.maxEntries = 5000

-- An entry that carries no message is not indexed by the walk either.
setHarnessDay("2026-08-28")
reloaded.clearJournal()
SanctuaryDB.log[1] = { t = time(), d = "2026-08-28 12:00:00", type = "duel",
    name = "Knocker", realm = "TestRealm" }
now = now + 10
reloaded.logBlock("duel", "Knocker-TestRealm", nil, nil, nil)
equal(#SanctuaryDB.log, 2, "two duels read back from the log stay two entries")

-- Emptying the journal after a reload still empties what folds into it.
reloaded.clearJournal()
now = now + 10
reloaded.logBlock("channel", "Twice-TestRealm", "same old line", nil, nil)
equal(#SanctuaryDB.log, 1, "after a clear the same line opens a new entry")
equal(SanctuaryDB.log[1].count, nil, "counted once")

-- A bare pseudo belongs to the realm it was written on, not to the one the
-- session comes back on. `SanctuaryDB` is account-wide and a sender of the
-- player's own realm is handed over bare, so the ordinary entry stores no realm
-- of its own -- and reconnecting the same day on a character of another realm
-- used to re-index the morning's entries under the evening's realm. A namesake
-- repeating the same line was then counted on somebody else's entry.
setHarnessDay("2026-08-29")
reloaded.clearJournal()
now = now + 10
reloaded.logBlock("channel", "Namesake", "same words twice", nil, nil)
now = now + 5
reloaded.logBlock("channel", "Namesake", "same words twice", nil, nil)
equal(#SanctuaryDB.log, 1, "a bare pseudo folds into one entry on its own realm")
equal(SanctuaryDB.log[1].count, 2, "counted twice")
equal(SanctuaryDB.log[1].realm, "", "and stored bare, the way the game hands it over")

local ownRealm = GetNormalizedRealmName
function GetNormalizedRealmName() return "OtherRealm" end
local elsewhere = {}
assert(loadfile(repoRoot .. "/Locales.lua"))("Sanctuary", elsewhere)
assert(loadfile(repoRoot .. "/Sanctuary.lua"))("Sanctuary", elsewhere)

now = now + 10
elsewhere.logBlock("channel", "Namesake", "same words twice", nil, nil)
equal(#SanctuaryDB.log, 2, "the namesake of the other realm opens his own entry")
equal(SanctuaryDB.log[1].count, 2, "and the entry of the first realm does not move")

-- An entry written before the realm was known never had a merge key -- at the
-- write `normalizeCharacterKey` answered nil for it -- so the walk must not
-- invent one for it now.
setHarnessDay("2026-08-30")
elsewhere.clearJournal()
SanctuaryDB.log[1] = { t = time(), d = "2026-08-30 12:00:00", type = "channel",
    name = "Rootless", realm = "", char = "Victim-", msg = "a line with no realm behind it" }
SanctuaryDB.log[2] = { t = time(), d = "2026-08-30 12:00:00", type = "channel",
    name = "Unknowing", realm = "", char = "?-?", msg = "another one" }
now = now + 10
elsewhere.logBlock("channel", "Rootless", "a line with no realm behind it", nil, nil)
equal(#SanctuaryDB.log, 3, "an entry whose realm was empty collects nothing")
now = now + 10
elsewhere.logBlock("channel", "Unknowing", "another one", nil, nil)
equal(#SanctuaryDB.log, 4, "and neither does one whose realm was written unknown")

-- A Battle.net whisper is journalled under the account name, which has no realm
-- half either -- and must not be handed the character's. It carries a space, and
-- the realm its key was built on is the one behind that space: the entry goes on
-- folding across the very reconnection that changed realms.
setHarnessDay("2026-08-31")
elsewhere.clearJournal()
now = now + 10
elsewhere.logBlock("whisper", "Toto Ysondre", "hey there", nil, nil)
equal(#SanctuaryDB.log, 1, "the account name opens one entry")
now = now + 10
reloaded.logBlock("whisper", "Toto Ysondre", "hey there", nil, nil)
equal(#SanctuaryDB.log, 1, "and folds back into it from a session on another realm")
equal(SanctuaryDB.log[1].count, 2, "counted twice")

GetNormalizedRealmName = ownRealm

setHarnessDay("2026-06-20")
resetModelState()

end

end)()

if failures > 0 then
    io.stderr:write(string.format("%d/%d assertions failed\n", failures, assertions))
    os.exit(1)
end

print(string.format("OK: %d assertions", assertions))
