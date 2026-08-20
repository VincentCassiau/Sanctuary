-- ============================================================================
-- Sanctuary — WoW Anti-Harassment Addon (Whitelist-based protection)
-- Version: 0.3.2 | Interface: 120007 (Midnight)
-- ============================================================================

-- ============================================================================
-- SECTION A: Namespace & Constants
-- ============================================================================

local ADDON_NAME, ns = ...
local L = ns.L
local VERSION = "0.3.2"

-- Build identity. This is NOT a release version and must never be presented as
-- one: it only makes a user-provided debug report attributable to the exact
-- build that produced it. Bump it whenever the diagnostic surface changes so two
-- reports can never be confused. Keep it non-descriptive -- a date and a counter
-- and nothing else: it is printed verbatim in every report, and a report can be
-- handed to a third party, so the identifier must not leak what is being
-- investigated or which internal item it belongs to.
local BUILD_ID = "20260820-6"

local PREFIX = "|cFF66CCFF[Sanctuary]|r "
local COLOR_ON = "|cFF00FF00"
local COLOR_OFF = "|cFFFF4444"
local COLOR_WARN = "|cFFFFCC00"
local COLOR_RESET = "|r"
local COLOR_HIGHLIGHT = "|cFFFFFFFF"

local Sanctuary = {}
local handlers = {}

-- Export constants to namespace for UI file
ns.VERSION = VERSION
ns.BUILD_ID = BUILD_ID
ns.PREFIX = PREFIX
ns.COLOR_ON = COLOR_ON
ns.COLOR_OFF = COLOR_OFF
ns.COLOR_WARN = COLOR_WARN
ns.COLOR_RESET = COLOR_RESET
ns.COLOR_HIGHLIGHT = COLOR_HIGHLIGHT

-- ============================================================================
-- SECTION B: SavedVariables Defaults
-- ============================================================================

local ACCOUNT_DEFAULTS = {
    schemaVersion = 1,

    filters = {
        groupInvite        = true,
        whisper            = true,
        duel               = true,
        trade              = true,
        guildInvite        = true,
        say                = false,
        yell               = false,
        emote              = false,
        channelMode        = "none",  -- "none" | "keywords" | "all"
        autoTrust          = false,
        strictGroupInviteSystemMessages = false,
    },

    temporalGroupTrust = {
        trustThresholdMinutes = 5,
    },

    notifications = {
        mode = "silent",
        minimalIntervalMinutes = 5,
    },

    logging = {
        enabled    = true,
        maxEntries = 5000,
        rotation   = "deleteOldest",
    },

    manualWhitelist = {},
    log = {},
    keywords = {},  -- suspicious keyword list (e.g., "jetaime", "belle")
    uiPosition = nil, -- saved window position { point, x, y }
    uiSize = nil,         -- saved window size { width, height }
    uiSettings = {
        showMessageColumn = true,
    },
    debugEnabled = false,
    debugLog = {},
    -- Retention accounting for the debug log. It lives in SavedVariables on
    -- purpose: a reload must not restart the numbering of a log it does not
    -- clear, otherwise a truncated report is unreadable.
    debugLogStats = {
        produced = 0,
        dropped = 0,
    },
}

local CHARACTER_DEFAULTS = {
    schemaVersion = 1,
    overrides = {
        enabled = nil,
        filters = {},
        notificationMode = nil,
    },
    manualWhitelist = {},
    groupTracker = {},
    sessionStats = {
        blockedCount = 0,
        blockedByType = {},
    },
}

-- Export defaults to namespace
ns.ACCOUNT_DEFAULTS = ACCOUNT_DEFAULTS
ns.CHARACTER_DEFAULTS = CHARACTER_DEFAULTS

-- ============================================================================
-- SECTION C: Utilities
-- ============================================================================

local function printMsg(text)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. text)
end

local function printError(text)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. COLOR_OFF .. text .. COLOR_RESET)
end

local function printSuccess(text)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. COLOR_ON .. text .. COLOR_RESET)
end

local playerRealm = nil

local function getPlayerRealm()
    if not playerRealm then
        playerRealm = GetNormalizedRealmName()
    end
    return playerRealm or ""
end

local SECRET_VALUE_PLACEHOLDER = "<secret>"
local UNPRINTABLE_VALUE_PLACEHOLDER = "<unprintable>"

local function isRestrictedValue(value)
    if value == nil then return false end

    if type(canaccessvalue) == "function" then
        local ok, accessible = pcall(canaccessvalue, value)
        if ok and accessible == false then
            return true
        end
    end

    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        if ok and secret == true then
            return true
        end
    end

    return false
end

-- Social counters read right after a login or a reload can answer nil while the
-- friend/guild lists are still loading. Storing that nil removed the key from
-- the serialized snapshot entirely, and in a report an absent key cannot be told
-- apart from a code path that never ran. Same rule as the client build context:
-- every read reports a value, including its own failure.
local function readSocialCount(reader)
    local value
    local ok = pcall(function()
        value = reader()
    end)
    if not ok then return "error" end
    if type(value) ~= "number" then return "unavailable" end
    return value
end

ns.readSocialCount = readSocialCount

local function safeText(value, maxLen, nilText)
    if value == nil then return nilText end
    if isRestrictedValue(value) then return SECRET_VALUE_PLACEHOLDER end

    local valueType = type(value)
    local text
    if valueType == "string" then
        text = value
    else
        local ok, converted = pcall(tostring, value)
        if not ok then return UNPRINTABLE_VALUE_PLACEHOLDER end
        text = converted
    end

    if maxLen and #text > maxLen then
        return text:sub(1, maxLen)
    end
    return text
end

local function getRuntimeContext()
    local inGroupValue = false
    if type(IsInGroup) == "function" then
        local ok, value = pcall(IsInGroup)
        inGroupValue = ok and value and true or false
    end

    local inRaidValue = false
    if type(IsInRaid) == "function" then
        local ok, value = pcall(IsInRaid)
        inRaidValue = ok and value and true or false
    end

    local groupSizeValue = 0
    if inGroupValue and type(GetNumGroupMembers) == "function" then
        local ok, value = pcall(GetNumGroupMembers)
        groupSizeValue = ok and tonumber(value) or 0
    end

    local inInstanceValue = false
    local instanceTypeValue = "none"
    if type(IsInInstance) == "function" then
        local ok, isInstance, instanceType = pcall(IsInInstance)
        if ok then
            inInstanceValue = isInstance and true or false
            instanceTypeValue = safeText(instanceType, 40, "nil") or "nil"
        else
            instanceTypeValue = "error"
        end
    end

    -- Strictly boolean like the other context flags: an unreadable or protected
    -- reading must never look like "dead". deadOrGhostKnown carries that
    -- distinction instead, so diagnostics never confuse unknown with dead.
    local deadOrGhostValue = false
    local deadOrGhostKnownValue = false
    if type(UnitIsDeadOrGhost) == "function" then
        local ok, value = pcall(UnitIsDeadOrGhost, "player")
        if ok and not isRestrictedValue(value) then
            deadOrGhostValue = value and true or false
            deadOrGhostKnownValue = true
        end
    end

    return {
        inGroup = inGroupValue,
        inRaid = inRaidValue,
        groupSize = groupSizeValue,
        inInstance = inInstanceValue,
        instanceType = instanceTypeValue,
        deadOrGhost = deadOrGhostValue,
        deadOrGhostKnown = deadOrGhostKnownValue,
    }
end

local function addRuntimeContext(data)
    data = data or {}
    local context = getRuntimeContext()
    data.inGroup = context.inGroup
    data.inRaid = context.inRaid
    data.groupSize = context.groupSize
    data.inInstance = context.inInstance
    data.instanceType = context.instanceType
    data.deadOrGhost = context.deadOrGhost
    data.deadOrGhostKnown = context.deadOrGhostKnown
    return data
end

-- Retail moved the chat message filter registry to ChatFrameUtil and now keeps
-- the historical global as an alias declared by Blizzard_DeprecatedChatInfo.
-- Resolve whichever path the running client actually exposes so registration
-- survives that alias being retired. This is an availability adapter only: it
-- does not change which messages Sanctuary filters.
local function resolveChatFilterRegistrar()
    if type(ChatFrame_AddMessageEventFilter) == "function" then
        return ChatFrame_AddMessageEventFilter, "legacy"
    end
    if type(ChatFrameUtil) == "table" and type(ChatFrameUtil.AddMessageEventFilter) == "function" then
        return ChatFrameUtil.AddMessageEventFilter, "chatframeutil"
    end
    return nil, "none"
end

local function describeChatFilterApi()
    local legacy = type(ChatFrame_AddMessageEventFilter) == "function"
    local namespaced = type(ChatFrameUtil) == "table"
        and type(ChatFrameUtil.AddMessageEventFilter) == "function"
    if legacy and namespaced then return "both" end
    if legacy then return "legacy" end
    if namespaced then return "chatframeutil" end
    return "none"
end

ns.resolveChatFilterRegistrar = resolveChatFilterRegistrar
ns.describeChatFilterApi = describeChatFilterApi

-- Registration path actually taken at load, kept for the debug snapshot so a
-- user report shows which registry answered rather than which ones existed.
local chatFilterApiUsed = "unregistered"

-- Client/build identity for debug reports. Every read is protected and only
-- returns scalars the client itself publishes; no player-identifying data and
-- no chat payload ever reaches this table.
local function getClientBuildContext()
    local data = {
        build = BUILD_ID,
        chatFilterApi = describeChatFilterApi(),
    }

    -- Every branch sets every key. In a report read by a human, a missing key is
    -- indistinguishable from a forgotten code path, so failures are stated
    -- explicitly rather than left absent.
    local function setClientBuild(version, build, buildDate, interfaceValue)
        data.clientVersion = version
        data.clientBuild = build
        data.clientBuildDate = buildDate
        data.clientInterface = interfaceValue
    end

    if type(GetBuildInfo) == "function" then
        local ok, clientVersion, clientBuild, clientBuildDate, clientTOC = pcall(GetBuildInfo)
        if ok then
            -- Same protection as the message type conversion: a protected value
            -- must never be handed to tonumber.
            local interfaceValue
            if not isRestrictedValue(clientTOC) then
                local okNumber, numeric = pcall(tonumber, clientTOC)
                interfaceValue = okNumber and numeric or nil
            end
            setClientBuild(
                safeText(clientVersion, 40, "nil"),
                safeText(clientBuild, 40, "nil"),
                safeText(clientBuildDate, 40, "nil"),
                interfaceValue or safeText(clientTOC, 40, "nil")
            )
        else
            setClientBuild("error", "error", "error", "error")
        end
    else
        setClientBuild("unavailable", "unavailable", "unavailable", "unavailable")
    end

    local getMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    if type(getMetadata) == "function" then
        local okVersion, metaVersion = pcall(getMetadata, ADDON_NAME, "Version")
        data.addonMetaVersion = okVersion and safeText(metaVersion, 40, "nil") or "error"
        local okBuild, metaBuild = pcall(getMetadata, ADDON_NAME, "X-Sanctuary-Build")
        data.addonMetaBuild = okBuild and safeText(metaBuild, 60, "nil") or "error"
        local okInterface, metaInterface = pcall(getMetadata, ADDON_NAME, "Interface")
        data.addonMetaInterface = okInterface and safeText(metaInterface, 20, "nil") or "error"
    else
        data.addonMetaVersion = "unavailable"
        data.addonMetaBuild = "unavailable"
        data.addonMetaInterface = "unavailable"
    end

    -- Retail exposes a chat messaging lockdown state; treat an unreadable or
    -- missing API as unknown rather than as "not locked down".
    data.chatLockdown = false
    data.chatLockdownKnown = false
    if type(C_ChatInfo) == "table" and type(C_ChatInfo.InChatMessagingLockdown) == "function" then
        local ok, lockdown = pcall(C_ChatInfo.InChatMessagingLockdown)
        if ok and not isRestrictedValue(lockdown) then
            data.chatLockdown = lockdown and true or false
            data.chatLockdownKnown = true
        end
    end

    return data
end

ns.getClientBuildContext = getClientBuildContext

local function addSnapshotFields(target, fields)
    target = target or {}
    for key, value in pairs(fields or {}) do
        target[key] = value
    end
    return target
end

-- ChatTypeInfo.SYSTEM.id is the message type Retail passes as the fifth
-- AddMessage argument for system lines. Reading it must stay protected: the
-- table can be missing at load time and Retail may expose protected fields.
local function readSystemChatTypeID()
    if type(ChatTypeInfo) ~= "table" then return nil end

    local ok, id = pcall(function()
        local info = ChatTypeInfo.SYSTEM
        if type(info) ~= "table" then return nil end
        return info.id
    end)
    if not ok or id == nil or isRestrictedValue(id) then return nil end

    return tonumber(id)
end

ns.readSystemChatTypeID = readSystemChatTypeID

local function sanitizeDebugValue(value, depth)
    if value == nil then return nil end
    if isRestrictedValue(value) then return SECRET_VALUE_PLACEHOLDER end

    local valueType = type(value)
    if valueType == "string" or valueType == "number" or valueType == "boolean" then
        return value
    end

    if valueType == "table" then
        if (depth or 0) >= 3 then return "<table>" end
        local sanitized = {}
        local ok = pcall(function()
            for key, child in pairs(value) do
                local safeKey = sanitizeDebugValue(key, (depth or 0) + 1)
                if safeKey ~= nil then
                    if type(safeKey) == "table" then
                        safeKey = "<table-key>"
                    end
                    sanitized[safeKey] = sanitizeDebugValue(child, (depth or 0) + 1)
                end
            end
        end)
        if not ok then return UNPRINTABLE_VALUE_PLACEHOLDER end
        return sanitized
    end

    return safeText(value, nil, nil)
end

ns.isRestrictedValue = isRestrictedValue

local function stripWoWFormatting(value)
    if value == nil or isRestrictedValue(value) then return nil end
    value = safeText(value, nil, nil)
    if not value or value == "" then return nil end
    -- |Hplayer:Name-Realm:...|h[Name]|h -> [Name]
    value = value:gsub("|H.-|h", "")
    value = value:gsub("|h", "")
    value = value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    value = value:gsub("%[", ""):gsub("%]", "")
    value = value:match("^%s*(.-)%s*$")
    if value == "" then return nil end
    return value
end

local function normalizeName(name)
    name = stripWoWFormatting(name)
    if not name then return nil end
    -- WoW character names never contain spaces.
    name = name:gsub("%s", ""):lower()
    -- Compatibility note: existing SavedVariables use name-only keys. Keep that
    -- behaviour in 0.3.2; realm-aware migration needs a dedicated release.
    local nameOnly = name:match("^([^-]+)-") or name
    return nameOnly
end

local function normalizeBNetName(name)
    name = stripWoWFormatting(name)
    if not name then return nil end
    -- Battle.net account display names may contain spaces; preserve them.
    name = name:gsub("%s+", " "):lower()
    return name
end

local function deepCopy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = deepCopy(v)
    end
    return copy
end

local function fillMissingDefaults(target, defaults)
    if type(defaults) ~= "table" then return end
    for k, v in pairs(defaults) do
        if target[k] == nil then
            target[k] = deepCopy(v)
        elseif type(v) == "table" and type(target[k]) == "table" then
            fillMissingDefaults(target[k], v)
        end
    end
end

-- Resolve effective setting: per-char override > account-wide
local function getEffective(key)
    -- Check per-char overrides first
    if SanctuaryCharDB and SanctuaryCharDB.overrides then
        -- Handle dotted paths like "filters.whisper"
        local section, subkey = key:match("^(%w+)%.(%w+)$")
        if section and subkey then
            local overrides = SanctuaryCharDB.overrides[section]
            if type(overrides) == "table" and overrides[subkey] ~= nil then
                return overrides[subkey]
            end
        elseif SanctuaryCharDB.overrides[key] ~= nil then
            return SanctuaryCharDB.overrides[key]
        end
    end

    -- Fall back to account-wide
    if SanctuaryDB then
        local section, subkey = key:match("^(%w+)%.(%w+)$")
        if section and subkey then
            local tbl = SanctuaryDB[section]
            if type(tbl) == "table" then
                return tbl[subkey]
            end
        else
            return SanctuaryDB[key]
        end
    end
    return nil
end

local function isEnabled()
    local charOverride = SanctuaryCharDB and SanctuaryCharDB.overrides
        and SanctuaryCharDB.overrides.enabled
    if charOverride ~= nil then
        return charOverride
    end
    return true -- enabled by default
end

local function parseBool(str)
    if not str then return nil end
    str = str:lower()
    if str == "on" or str == "true" or str == "yes" or str == "1" then
        return true
    elseif str == "off" or str == "false" or str == "no" or str == "0" then
        return false
    end
    return nil
end

local FILTER_STATE_KEYS = {
    "groupInvite",
    "whisper",
    "duel",
    "trade",
    "guildInvite",
    "say",
    "yell",
    "emote",
    "channelMode",
    "autoTrust",
    "strictGroupInviteSystemMessages",
}

local function getEffectiveFilterState()
    local filters = {}
    for _, key in ipairs(FILTER_STATE_KEYS) do
        filters[key] = getEffective("filters." .. key)
    end
    return filters
end

-- Export utilities to namespace
ns.printMsg = printMsg
ns.printError = printError
ns.printSuccess = printSuccess
ns.normalizeName = normalizeName
ns.normalizeBNetName = normalizeBNetName
ns.getEffective = getEffective
ns.isEnabled = isEnabled
ns.parseBool = parseBool
ns.deepCopy = deepCopy
ns.fillMissingDefaults = fillMissingDefaults
ns.getEffectiveFilterState = getEffectiveFilterState

-- Keyword blacklist: blocks names containing any suspect keyword
local function matchesKeyword(name)
    if not name or not SanctuaryDB or not SanctuaryDB.keywords then return false, nil end
    local cleanName = stripWoWFormatting(name)
    if not cleanName then return false, nil end

    local lowerName = cleanName:lower():gsub("%s", "")
    for _, keyword in ipairs(SanctuaryDB.keywords) do
        local cleanKeyword = tostring(keyword or ""):lower():gsub("%s", "")
        if cleanKeyword ~= "" and lowerName:find(cleanKeyword, 1, true) then
            return true, keyword
        end
    end
    return false, nil
end

ns.matchesKeyword = matchesKeyword

-- Forward declarations for helpers used before their concrete section.
local debugLog, countBNetWithCharName, captureDebugSnapshot, isBNetSenderInGroup
local getDebugLogStats, resetDebugLog
local chatOutputWrapped
local pendingPopupDecisions
local unmaskVisiblePopup
local capturePartyInviteOriginalSound
local partyInviteSoundGuardDepth = 0

-- ============================================================================
-- SECTION E: Whitelist Engine
-- ============================================================================

Sanctuary.whitelistCache = {}
Sanctuary.bnetWhitelistCache = {}
Sanctuary.whitelistSources = {}
Sanctuary.whitelistLabels = {}
Sanctuary.bnetWhitelistSources = {}
Sanctuary.bnetWhitelistLabels = {}
Sanctuary.whitelistDirty = true

local function getBNetFriendInfo(index)
    if not C_BattleNet or type(C_BattleNet.GetFriendAccountInfo) ~= "function" then
        return nil
    end
    local ok, info = pcall(C_BattleNet.GetFriendAccountInfo, index)
    if ok and type(info) == "table" then
        return info
    end
    return nil
end

local function getBNetAccountInfoByID(bnSenderID)
    if not bnSenderID or isRestrictedValue(bnSenderID) then return nil end
    if not C_BattleNet or type(C_BattleNet.GetAccountInfoByID) ~= "function" then
        return nil
    end

    local ok, info = pcall(C_BattleNet.GetAccountInfoByID, bnSenderID)
    if ok and type(info) == "table" then
        return info
    end
    return nil
end

local function rebuildWhitelist()
    local cache = {}
    local bnetCache = {}
    -- Attribution is built alongside the decision cache, never inside it. The
    -- Whitelist tab has to say *why* someone gets through, and rebuilding a
    -- second time to answer that would double the cost of every decision.
    -- First writer wins, and the manual lists are added first, so an entry the
    -- user typed keeps its own label even when they are also in the guild.
    --
    -- Two flat tables of strings rather than one table of records: a rebuild
    -- runs on the first decision after any social event, several times a
    -- minute on a busy Battle.net list, and one small table per contact would
    -- put a few hundred allocations on that path for nothing. The label is only
    -- stored when it differs from the key.
    local sources = {}
    local sourceLabels = {}
    local bnetSources = {}
    local bnetSourceLabels = {}

    local function noteSource(store, labelStore, key, source, displayName)
        if not key or store[key] then return end
        store[key] = source
        if displayName and displayName ~= key then
            labelStore[key] = displayName
        end
    end

    local function addCharacterName(name, source, displayName)
        local normalized = normalizeName(name)
        if normalized then
            cache[normalized] = true
            noteSource(sources, sourceLabels, normalized, source or "manual",
                displayName or (type(name) == "string" and name or nil))
        end
    end

    local function addBNetAccountName(name, source, displayName)
        local normalized = normalizeBNetName(name)
        if normalized then
            bnetCache[normalized] = true
            noteSource(bnetSources, bnetSourceLabels, normalized, source or "manual",
                displayName or (type(name) == "string" and name or nil))
        end
    end

    local function manualEntryAllowsBNet(data)
        if type(data) ~= "table" then return true end
        -- UI/legacy manual entries historically had no source. Treat those as
        -- explicit user trust for character and Battle.net display names; exclude
        -- auto-trust entries, which are known character-only contacts.
        return data.source ~= "trust"
    end

    local function addManualEntry(key, data)
        local source = (type(data) == "table" and data.source == "trust") and "trust" or "manual"
        local label = (type(data) == "table" and data.displayName) or key
        addCharacterName(key, source, label)
        if type(data) == "table" then
            addCharacterName(data.displayName, source, label)
            if manualEntryAllowsBNet(data) then
                addBNetAccountName(data.displayName or key, source, label)
            end
        elseif manualEntryAllowsBNet(data) then
            addBNetAccountName(key, source, label)
        end
    end

    -- Manual whitelist (account-wide)
    if SanctuaryDB and SanctuaryDB.manualWhitelist then
        for key, data in pairs(SanctuaryDB.manualWhitelist) do
            addManualEntry(key, data)
        end
    end

    -- Manual whitelist (per-character)
    if SanctuaryCharDB and SanctuaryCharDB.manualWhitelist then
        for key, data in pairs(SanctuaryCharDB.manualWhitelist) do
            addManualEntry(key, data)
        end
    end

    -- Guild members (always whitelisted).
    -- Do not gate this on IsInGuild(): during instance/loading transitions WoW can
    -- transiently return false while the roster is still fully populated.
    pcall(function()
        local numMembers = GetNumGuildMembers() or 0
        for i = 1, numMembers do
            local name = GetGuildRosterInfo(i)
            if name then addCharacterName(name, "guild") end
        end
    end)

    -- Battle.net friends (always whitelisted): cache both the account display
    -- name (used by CHAT_MSG_BN_WHISPER) and the currently visible character.
    pcall(function()
        local numFriends = BNGetNumFriends() or 0
        for i = 1, numFriends do
            local info = getBNetFriendInfo(i)
            if info then
                addBNetAccountName(info.accountName, "bnet")
                local gameInfo = info.gameAccountInfo
                if gameInfo and gameInfo.characterName and gameInfo.characterName ~= "" then
                    addCharacterName(gameInfo.characterName, "bnet", info.accountName)
                end
            end
        end
    end)

    -- Character friends (always whitelisted)
    pcall(function()
        local numFriends = C_FriendList.GetNumFriends() or 0
        for i = 1, numFriends do
            local info = C_FriendList.GetFriendInfoByIndex(i)
            if info and info.name then addCharacterName(info.name, "friend") end
        end
    end)

    -- Current group/raid members (always whitelisted)
    pcall(function()
        if IsInGroup() then
            local numMembers = GetNumGroupMembers() or 0
            local isRaid = IsInRaid()
            for i = 1, numMembers do
                local unit = isRaid and ("raid" .. i) or ("party" .. i)
                local name, realm = UnitName(unit)
                if name and name ~= UNKNOWNOBJECT then
                    if realm and realm ~= "" then
                        name = name .. "-" .. realm
                    end
                    addCharacterName(name, "group")
                end
            end
        end
    end)

    Sanctuary.whitelistCache = cache
    Sanctuary.bnetWhitelistCache = bnetCache
    Sanctuary.whitelistSources = sources
    Sanctuary.whitelistLabels = sourceLabels
    Sanctuary.bnetWhitelistSources = bnetSources
    Sanctuary.bnetWhitelistLabels = bnetSourceLabels
    Sanctuary.whitelistDirty = false

    if SanctuaryDB and SanctuaryDB.debugEnabled then
        local totalSize = 0
        for _ in pairs(cache) do totalSize = totalSize + 1 end
        local bnetSize = 0
        for _ in pairs(bnetCache) do bnetSize = bnetSize + 1 end
        -- Same nil-counter rule as the snapshot: report the failure, never let
        -- the key disappear from the entry.
        local gm = readSocialCount(GetNumGuildMembers)
        local bn = readSocialCount(BNGetNumFriends)
        local cf = readSocialCount(function() return C_FriendList.GetNumFriends() end)
        local grp = readSocialCount(function()
            return IsInGroup() and GetNumGroupMembers() or 0
        end)
        debugLog("REBUILD", {
            cache = totalSize,
            bnetAccounts = bnetSize,
            isInGuild = IsInGuild() and true or false,
            guild = gm, bnet = bn, friends = cf, group = grp,
        })
    end
end

local function isWhitelisted(name)
    if not name then return false end
    if Sanctuary.whitelistDirty then
        rebuildWhitelist()
    end
    local normalized = normalizeName(name)
    if not normalized then return false end
    return Sanctuary.whitelistCache[normalized] == true
end

local function isBNetWhitelisted(name)
    if not name then return false end
    if Sanctuary.whitelistDirty then
        rebuildWhitelist()
    end
    local normalized = normalizeBNetName(name)
    if not normalized then return false end
    return Sanctuary.bnetWhitelistCache[normalized] == true
end

local function isBNetProtectedPlayerName(sender)
    if isRestrictedValue(sender) then return false end
    local text = safeText(sender, nil, nil)
    return type(text) == "string" and text:match("^|K.-|k$") ~= nil
end

local function getBNetWhisperPayloadSenderID(...)
    -- Retail ChatInfoDocumentation names CHAT_MSG_BN_WHISPER arg13
    -- `bnSenderID`; after `(msg, sender, ...)` that is select(11, ...).
    local bnSenderID = select(11, ...)
    if isRestrictedValue(bnSenderID) then return nil end
    return bnSenderID
end

local function getBNetWhisperPayloadArgs(rawSender, bnSenderID)
    return "", "", rawSender, "", 0, 0, "", 0, 0, "Player-Sanctuary-0", bnSenderID
end

local function resolveBNetWhisperSender(sender, ...)
    local bnSenderID = getBNetWhisperPayloadSenderID(...)
    local accountInfo = getBNetAccountInfoByID(bnSenderID)
    local accountName = accountInfo and accountInfo.accountName
    local resolvedByID = accountName ~= nil and accountName ~= ""

    if not resolvedByID and not isRestrictedValue(sender) and not isBNetProtectedPlayerName(sender) then
        accountName = sender
    end

    return {
        accountName = accountName,
        accountInfo = accountInfo,
        rawSender = sender,
        rawSenderText = safeText(sender, 200, "nil"),
        bnSenderID = bnSenderID,
        bnSenderIDState = bnSenderID ~= nil and "present" or "nil",
        resolvedByID = resolvedByID,
    }
end

local function invalidateWhitelist()
    Sanctuary.whitelistDirty = true
end

-- Single source of truth for character-name decisions. Suspect patterns are
-- intentionally evaluated first: this matches the UI/README contract that a
-- pattern overrides every trust source.
local function getCharacterDecision(name)
    local keywordMatch, keyword = matchesKeyword(name)
    if keywordMatch then
        return true, "keyword", keyword
    end
    if isWhitelisted(name) then
        return false, "whitelist", nil
    end
    return true, "not_whitelisted", nil
end

-- Export whitelist functions to namespace
ns.isWhitelisted = isWhitelisted
ns.isBNetWhitelisted = isBNetWhitelisted
ns.invalidateWhitelist = invalidateWhitelist
ns.getCharacterDecision = getCharacterDecision
ns.getWhitelistCacheSize = function()
    local count = 0
    if Sanctuary.whitelistCache then
        for _ in pairs(Sanctuary.whitelistCache) do count = count + 1 end
    end
    return count
end

ns.getBNetWhitelistCacheSize = function()
    local count = 0
    if Sanctuary.bnetWhitelistCache then
        for _ in pairs(Sanctuary.bnetWhitelistCache) do count = count + 1 end
    end
    return count
end

ns.getBNetFriendInfo = getBNetFriendInfo

-- ----------------------------------------------------------------------------
-- Whitelist readback (Whitelist tab)
-- ----------------------------------------------------------------------------

-- Reading is what refreshes. `invalidateWhitelist` only marks the cache dirty;
-- the rebuild happens on the next read, decision or display alike. Opening the
-- tab is therefore enough to get a current list, which is why the tab has no
-- refresh button and no periodic timer -- and why BN_FRIEND_INFO_CHANGED firing
-- twenty times in half an hour costs nothing while the tab is closed.
function ns.ensureWhitelist()
    if Sanctuary.whitelistDirty then
        rebuildWhitelist()
    end
end

-- Automatic trust sources, in the order the tab shows them. "trust" and
-- "manual" are deliberately absent: those entries live in manualWhitelist and
-- are already listed, and editable, in the section above.
ns.AUTO_WHITELIST_SOURCES = { "guild", "friend", "bnet", "group" }

-- Groups the automatically trusted contacts by why they are trusted. Battle.net
-- friends are listed by account name rather than by their current character:
-- the character changes with every login while the account is the identity the
-- decision is actually made on, and one line per account keeps 56 friends
-- readable instead of doubling them.
function ns.getAutoWhitelistGroups(filterText)
    ns.ensureWhitelist()

    local needle = type(filterText) == "string" and filterText:gsub("^%s+", ""):gsub("%s+$", ""):lower() or ""
    local groups = {}
    local bySource = {}
    for _, source in ipairs(ns.AUTO_WHITELIST_SOURCES) do
        local group = { source = source, total = 0, entries = {} }
        groups[#groups + 1] = group
        bySource[source] = group
    end

    local function collect(store, labels, source)
        local group = bySource[source]
        if not group then return end
        for key, entrySource in pairs(store or {}) do
            if entrySource == source then
                group.total = group.total + 1
                local label = (labels and labels[key]) or key
                if needle == "" or tostring(label):lower():find(needle, 1, true)
                    or key:find(needle, 1, true) then
                    group.entries[#group.entries + 1] = { key = key, label = label }
                end
            end
        end
    end

    collect(Sanctuary.whitelistSources, Sanctuary.whitelistLabels, "guild")
    collect(Sanctuary.whitelistSources, Sanctuary.whitelistLabels, "friend")
    collect(Sanctuary.whitelistSources, Sanctuary.whitelistLabels, "group")
    collect(Sanctuary.bnetWhitelistSources, Sanctuary.bnetWhitelistLabels, "bnet")

    for _, group in ipairs(groups) do
        table.sort(group.entries, function(a, b)
            local la, lb = tostring(a.label):lower(), tostring(b.label):lower()
            if la == lb then return a.key < b.key end
            return la < lb
        end)
    end
    return groups
end

-- Answers "does this person get through, and why" for one typed name. It reuses
-- getCharacterDecision unchanged, so the answer is the decision itself and not a
-- second implementation of it that could drift.
function ns.describeAccessDecision(name)
    if type(name) ~= "string" or name:gsub("%s", "") == "" then
        return { valid = false, reason = "empty" }
    end

    local normalized = normalizeName(name)
    if not normalized then
        return { valid = false, reason = "invalid_name" }
    end

    ns.ensureWhitelist()
    local blocked, reason, keyword = getCharacterDecision(name)

    -- A Battle.net friend whose current character is unknown still gets through
    -- on Battle.net whispers. Saying only "BLOCK" here would read as a bug to
    -- someone who knows that contact passes, so the account match is reported.
    local bnetKey = normalizeBNetName(name)

    return {
        valid = true,
        input = name,
        normalized = normalized,
        blocked = blocked and true or false,
        reason = reason or "unknown",
        keyword = keyword,
        source = Sanctuary.whitelistSources and Sanctuary.whitelistSources[normalized] or nil,
        bnetSource = bnetKey and Sanctuary.bnetWhitelistSources
            and Sanctuary.bnetWhitelistSources[bnetKey] or nil,
    }
end

-- ============================================================================
-- SECTION F: Logging Engine
-- ============================================================================

local lastLogKey = ""
local lastLogTime = 0

local function logBlock(blockType, sourceName, message, guid, keyword)
    if not SanctuaryDB then return end
    if not SanctuaryDB.logging.enabled then return end

    local sourceText = safeText(sourceName, nil, nil)

    -- Dedup: skip if same event logged within 1 second
    local logKey = blockType .. ":" .. (sourceText or "")
    local now = GetTime()
    if logKey == lastLogKey and (now - lastLogTime) < 1 then
        return
    end
    lastLogKey = logKey
    lastLogTime = now

    local playerName = UnitName("player")
    local charRealm = getPlayerRealm()
    local sourceRealm = ""
    local cleanName = sourceText or "Unknown"

    -- Extract realm from "Name-Realm" format. Character names cannot contain
    -- hyphens, so the first hyphen is the unambiguous separator.
    local n, r = cleanName:match("^([^-]+)%-(.+)$")
    if n and r then
        cleanName = n
        sourceRealm = r
    end

    local entry = {
        t     = time(),
        d     = date("%Y-%m-%d %H:%M:%S"),
        type  = blockType,
        name  = cleanName,
        realm = sourceRealm,
        guid  = guid or "",
        msg   = safeText(message, nil, nil),
        char  = (playerName or "?") .. "-" .. (charRealm or "?"),
        keyword = keyword or nil,
    }

    table.insert(SanctuaryDB.log, entry)

    -- Rotation without allocating a second multi-thousand-entry table.
    local maxEntries = math.max(1, SanctuaryDB.logging.maxEntries or 5000)
    local overflow = #SanctuaryDB.log - maxEntries
    if overflow > 0 then
        local oldCount = #SanctuaryDB.log
        for i = 1, oldCount - overflow do
            SanctuaryDB.log[i] = SanctuaryDB.log[i + overflow]
        end
        for i = oldCount - overflow + 1, oldCount do
            SanctuaryDB.log[i] = nil
        end
    end

    -- Session stats
    if SanctuaryCharDB then
        SanctuaryCharDB.sessionStats.blockedCount =
            (SanctuaryCharDB.sessionStats.blockedCount or 0) + 1
        local byType = SanctuaryCharDB.sessionStats.blockedByType
        byType[blockType] = (byType[blockType] or 0) + 1
    end

    -- Verbose notification: print each block in chat
    if SanctuaryDB.notifications.mode == "verbose" then
        printMsg(string.format(L["BLOCKED_VERBOSE"],
            COLOR_HIGHLIGHT .. blockType .. COLOR_RESET,
            COLOR_HIGHLIGHT .. (sourceText or "?") .. COLOR_RESET))
    end
end

-- Export logging to namespace
ns.logBlock = logBlock

-- ============================================================================
-- SECTION F2: Debug Logging Engine
-- ============================================================================

-- Produced/dropped accounting for the debug log. Rotation silently deletes the
-- oldest entries, so a report can look complete while the very incident it was
-- recorded for has already fallen off the front. Both counters are stored in
-- SavedVariables so they survive a UI reload, which the log itself does.
getDebugLogStats = function()
    if not SanctuaryDB then return nil end
    local stats = SanctuaryDB.debugLogStats
    if type(stats) ~= "table" then
        stats = { produced = 0, dropped = 0 }
        SanctuaryDB.debugLogStats = stats
    end
    stats.produced = tonumber(stats.produced) or 0
    stats.dropped = tonumber(stats.dropped) or 0
    -- Migration from a build without accounting, and general invariant: the
    -- produced count can never be lower than the highest number already handed
    -- out, or the next entries would reuse numbers that are already in the
    -- report. Counting the kept entries is not enough: a log inherited from a
    -- build without accounting can already have rotated, so it holds fewer
    -- entries than the numbers it carries.
    local highest = 0
    for _, entry in ipairs(SanctuaryDB.debugLog or {}) do
        local seq = tonumber(entry and entry.seq) or 0
        if seq > highest then highest = seq end
    end
    local kept = SanctuaryDB.debugLog and #SanctuaryDB.debugLog or 0
    if highest < kept then highest = kept end
    if stats.produced < highest then
        stats.produced = highest
    end
    -- Entries a previous build dropped cannot be counted after the fact, but
    -- they must not be reported as zero either: the header would then publish
    -- an impossible arithmetic (5000 kept / 5200 produced / 0 dropped) with no
    -- truncation warning. This is a lower bound, not an exact count -- what is
    -- certain is that produced minus kept went missing.
    local missing = stats.produced - kept
    if stats.dropped < missing then
        stats.dropped = missing
    end
    return stats
end

resetDebugLog = function()
    if not SanctuaryDB then return end
    SanctuaryDB.debugLog = {}
    SanctuaryDB.debugLogStats = { produced = 0, dropped = 0 }
    -- Dated, because the log is the record and it is not cleared by a reload or
    -- a relog. Without this, a closing check has no way to tell a scenario
    -- played during this run from the same scenario played days ago, and would
    -- credit a step that was skipped.
    SanctuaryDB.debugLogClearedAt = date("%Y-%m-%d %H:%M:%S")
end

-- `force` writes the entry even when debug mode is off. It exists for one
-- caller: the export, which must be able to describe the state it is reporting
-- on. Every other caller stays gated on the checkbox.
debugLog = function(cat, data, force)
    if not SanctuaryDB then return end
    if not SanctuaryDB.debugEnabled and not force then return end
    if not SanctuaryDB.debugLog then SanctuaryDB.debugLog = {} end

    -- The sequence number is the produced counter itself, so two entries can
    -- never share a number and a gap always means a dropped entry.
    local stats = getDebugLogStats()
    stats.produced = stats.produced + 1
    table.insert(SanctuaryDB.debugLog, {
        seq = stats.produced,
        t = GetTime(),
        ts = date("%H:%M:%S"),
        cat = cat,
        data = sanitizeDebugValue(data or {}, 0) or {},
    })

    -- Rotation without replacing the SavedVariables table reference used by the
    -- diagnostics UI.
    local maxEntries = math.max(1, SanctuaryDB.logging and SanctuaryDB.logging.maxEntries or 5000)
    local overflow = #SanctuaryDB.debugLog - maxEntries
    if overflow > 0 then
        local oldCount = #SanctuaryDB.debugLog
        for i = 1, oldCount - overflow do
            SanctuaryDB.debugLog[i] = SanctuaryDB.debugLog[i + overflow]
        end
        for i = oldCount - overflow + 1, oldCount do
            SanctuaryDB.debugLog[i] = nil
        end
        stats.dropped = stats.dropped + overflow
    end
end

-- The three values that decide whether a recording session is exploitable at
-- all: which filter API took, how much of the chat is actually observed, and
-- whether the system message type can be read on this client. The snapshot and
-- the in-game summary both read them here so they can never disagree.
function ns.getInstrumentationHealth()
    local chatFramesSeen = 0
    local chatFramesWrapped = 0
    for i = 1, 20 do
        local chatFrame = _G["ChatFrame" .. i]
        if chatFrame then
            chatFramesSeen = chatFramesSeen + 1
            if chatOutputWrapped and chatOutputWrapped[chatFrame] == chatFrame.AddMessage then
                chatFramesWrapped = chatFramesWrapped + 1
            end
        end
    end
    return {
        chatFilterApiUsed = chatFilterApiUsed,
        chatFramesSeen = chatFramesSeen,
        chatFramesWrapped = chatFramesWrapped,
        systemChatTypeID = readSystemChatTypeID() or "unknown",
    }
end

local function debugLogChatDecision(kind, sender, msg, action, reason, keyword, extra)
    if not SanctuaryDB or not SanctuaryDB.debugEnabled then return end

    local normalized
    if kind == "bn_whisper" then
        normalized = normalizeBNetName(sender)
    else
        normalized = normalizeName(sender)
    end

    local data = {
        kind = kind,
        sender = safeText(sender, 200, "nil"),
        normalized = normalized or "nil",
        action = action or "UNKNOWN",
        reason = reason or "nil",
        keyword = safeText(keyword, 200, "none"),
        msg = safeText(msg, 300, "nil"),
    }

    if extra then
        for key, value in pairs(extra) do
            data[key] = value
        end
    end

    debugLog("CHAT_DECISION", data)
end

-- Count BNet friends with characterName populated
countBNetWithCharName = function()
    local count = 0
    pcall(function()
        for i = 1, BNGetNumFriends() do
            local info = ns.getBNetFriendInfo and ns.getBNetFriendInfo(i)
            if info and info.gameAccountInfo
                and info.gameAccountInfo.characterName
                and info.gameAccountInfo.characterName ~= "" then
                count = count + 1
            end
        end
    end)
    return count
end

-- Capture a full state snapshot (debug enable, ADDON_LOADED, report export).
-- `trigger` says which of the three wrote it, so a report with several snapshots
-- can be read without guessing. The export forces the write: since D3, unticking
-- debug mode keeps the log, so "play, untick, export later" is a normal path and
-- it used to produce a report whose last snapshot dated back to the activation.
captureDebugSnapshot = function(trigger)
    if not SanctuaryDB then return end
    local force = trigger == "export"
    if not SanctuaryDB.debugEnabled and not force then return end

    -- Globals
    local globals = {}
    local gNames = {
        "ERR_INVITED_TO_GROUP_SS", "ERR_INVITED_TO_GROUP_S",
        "ERR_INVITED_ALREADY_IN_GROUP_SS", "ERR_INVITED_ALREADY_IN_GROUP_S",
    }
    for _, gName in ipairs(gNames) do
        local val = _G[gName]
        globals[gName] = (type(val) == "string") and val or "nil"
    end

    -- Patterns
    local patternList = {}
    if ns.invitePatterns then
        for i, p in ipairs(ns.invitePatterns) do
            patternList[i] = p
        end
    end

    -- Social data
    local guildN = readSocialCount(GetNumGuildMembers)
    local bnetN = readSocialCount(BNGetNumFriends)
    local friendN = readSocialCount(function() return C_FriendList.GetNumFriends() end)

    -- Whitelist cache sizes
    local cacheSize = 0
    if Sanctuary.whitelistCache then
        for _ in pairs(Sanctuary.whitelistCache) do cacheSize = cacheSize + 1 end
    end
    local bnetCacheSize = 0
    if Sanctuary.bnetWhitelistCache then
        for _ in pairs(Sanctuary.bnetWhitelistCache) do bnetCacheSize = bnetCacheSize + 1 end
    end

    -- Manual whitelist counts
    local manualAccount = 0
    if SanctuaryDB.manualWhitelist then
        for _ in pairs(SanctuaryDB.manualWhitelist) do manualAccount = manualAccount + 1 end
    end
    local manualChar = 0
    if SanctuaryCharDB and SanctuaryCharDB.manualWhitelist then
        for _ in pairs(SanctuaryCharDB.manualWhitelist) do manualChar = manualChar + 1 end
    end
    local health = ns.getInstrumentationHealth()
    local chatFramesSeen = health.chatFramesSeen
    local chatFramesWrapped = health.chatFramesWrapped

    local snapshot = getClientBuildContext()
    snapshot.version = VERSION
    snapshot.locale = GetLocale()
    snapshot.systemChatTypeID = health.systemChatTypeID
    snapshot.chatFilterApiUsed = health.chatFilterApiUsed

    debugLog("SNAPSHOT", addSnapshotFields(snapshot, {
        trigger = trigger or "debug_enable",
        debugEnabled = SanctuaryDB.debugEnabled and true or false,
        addonEnabled = isEnabled(),
        globals = globals,
        patternCount = ns.invitePatterns and #ns.invitePatterns or 0,
        patterns = patternList,
        isInGuild = IsInGuild() and true or false,
        guildMembers = guildN,
        bnetFriends = bnetN,
        bnetWithCharName = countBNetWithCharName(),
        charFriends = friendN,
        whitelistCache = cacheSize,
        bnetWhitelistCache = bnetCacheSize,
        manualWL = manualAccount .. "+" .. manualChar,
        keywords = SanctuaryDB.keywords and #SanctuaryDB.keywords or 0,
        filters = getEffectiveFilterState(),
        groupInviteFilter = getEffective("filters.groupInvite") == true,
        partyInviteOriginalSound = tostring(capturePartyInviteOriginalSound() or "nil"),
        partyInviteSoundGuardActive = partyInviteSoundGuardDepth > 0,
        chatFramesSeen = chatFramesSeen,
        chatFramesWrapped = chatFramesWrapped,
    }), force)
end

ns.debugLog = debugLog
ns.captureDebugSnapshot = captureDebugSnapshot
ns.countBNetWithCharName = countBNetWithCharName
ns.getDebugLogStats = getDebugLogStats
ns.resetDebugLog = resetDebugLog

-- ============================================================================
-- SECTION F3: Debug Report Rendering
-- ============================================================================

-- WoW interprets "|" escape sequences (|c |r |H |h |K |k |T |t) in every widget,
-- the export EditBox included, and what the maintainer copies out of that box is
-- the rendered text, not the raw buffer. An unescaped pipe coming from log data
-- therefore swallows the surrounding characters: the 2026-08-20 report lost a
-- whole entry that way, merged into its neighbour by a "|K...|k" name
-- substitution. Doubling the pipe makes the client render exactly one literal
-- "|" again, so the pasted report is character-for-character the recorded value.
local function escapeExportText(value)
    local text = value
    if type(text) ~= "string" then
        local ok, converted = pcall(tostring, text)
        text = ok and converted or UNPRINTABLE_VALUE_PLACEHOLDER
    end
    return (text:gsub("|", "||"))
end

ns.escapeExportText = escapeExportText

local function serializeDebugData(data)
    if type(data) ~= "table" then return escapeExportText(data) end
    -- Sort keys for consistent, readable output (pairs() order is random in Lua 5.1)
    local keys = {}
    for k in pairs(data) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
        -- Use explicit nil check (not `or`) because false is a valid value in Lua
        local v = data[k]
        if v == nil then v = data[tonumber(k)] end
        if type(v) == "table" then
            local subKeys = {}
            for sk in pairs(v) do subKeys[#subKeys + 1] = tostring(sk) end
            table.sort(subKeys)
            local sub = {}
            for _, sk in ipairs(subKeys) do
                local sv = v[sk]
                if sv == nil then sv = v[tonumber(sk)] end
                sub[#sub + 1] = escapeExportText(sk) .. "=" .. escapeExportText(sv)
            end
            parts[#parts + 1] = escapeExportText(k) .. "={" .. table.concat(sub, ", ") .. "}"
        else
            parts[#parts + 1] = escapeExportText(k) .. "=" .. escapeExportText(v)
        end
    end
    return table.concat(parts, " | ")
end

ns.serializeDebugData = serializeDebugData

-- Builds the whole debug report as plain text. It lives here rather than in the
-- UI file so the escaping and the retention accounting can be tested without a
-- game client; the UI only owns the window that displays it.
local function buildDebugReportText()
    if not SanctuaryDB then return "" end

    local lines = {}
    local function add(text)
        lines[#lines + 1] = text
    end

    add("=== SANCTUARY DEBUG REPORT ===")
    add("Date: " .. date("%Y-%m-%d %H:%M:%S"))
    add("Version: " .. VERSION .. " | Build: " .. BUILD_ID .. " | Locale: " .. (GetLocale() or "?"))
    add("")

    add("--- GLOBALS ---")
    local gNames = {
        "ERR_INVITED_TO_GROUP_SS", "ERR_INVITED_TO_GROUP_S",
        "ERR_INVITED_ALREADY_IN_GROUP_SS", "ERR_INVITED_ALREADY_IN_GROUP_S",
    }
    for _, gName in ipairs(gNames) do
        local val = _G[gName]
        add(gName .. " = " .. escapeExportText(type(val) == "string" and val or "nil"))
    end

    local patternCount = ns.invitePatterns and #ns.invitePatterns or 0
    add("")
    add("--- PATTERNS (" .. patternCount .. ") ---")
    if ns.invitePatterns then
        for i, p in ipairs(ns.invitePatterns) do
            add("[" .. i .. "] " .. escapeExportText(p))
        end
    end

    add("")
    add("--- STATE ---")
    add("AddonEnabled: " .. tostring(isEnabled())
        .. " | DebugEnabled: " .. tostring(SanctuaryDB.debugEnabled and true or false))
    add("IsInGuild: " .. tostring(IsInGuild() and true or false)
        .. " | GuildMembers: " .. tostring(readSocialCount(GetNumGuildMembers)))
    add("BNetFriends: " .. tostring(readSocialCount(BNGetNumFriends))
        .. " | BNetWithCharName: " .. tostring(countBNetWithCharName()))
    add("CharFriends: " .. tostring(readSocialCount(function()
        return C_FriendList.GetNumFriends()
    end)))
    add("GroupInviteFilter: " .. tostring(getEffective("filters.groupInvite"))
        .. " | StrictGroupInviteSystemMessages: "
        .. tostring(getEffective("filters.strictGroupInviteSystemMessages"))
        .. " | PartyInviteSoundGuard: " .. tostring(partyInviteSoundGuardDepth > 0))
    add("Filters: " .. serializeDebugData(getEffectiveFilterState()))

    local manualAccount = 0
    if SanctuaryDB.manualWhitelist then
        for _ in pairs(SanctuaryDB.manualWhitelist) do manualAccount = manualAccount + 1 end
    end
    local manualChar = 0
    if SanctuaryCharDB and SanctuaryCharDB.manualWhitelist then
        for _ in pairs(SanctuaryCharDB.manualWhitelist) do manualChar = manualChar + 1 end
    end
    add("ManualWL: " .. manualAccount .. "+" .. manualChar
        .. " | WhitelistCache: " .. tostring(ns.getWhitelistCacheSize())
        .. " | BNetAccountCache: " .. tostring(ns.getBNetWhitelistCacheSize()))
    add("Keywords: " .. (SanctuaryDB.keywords and #SanctuaryDB.keywords or 0))

    -- Event log. The header states what was produced, not only what survived:
    -- rotation drops the oldest entries silently, so a report can otherwise look
    -- complete while the incident it was recorded for has already fallen off.
    local entries = SanctuaryDB.debugLog or {}
    local stats = getDebugLogStats() or { produced = #entries, dropped = 0 }
    local maxEntries = math.max(1, SanctuaryDB.logging and SanctuaryDB.logging.maxEntries or 5000)
    add("")
    add("--- EVENT LOG (" .. #entries .. " kept / " .. stats.produced .. " produced / "
        .. stats.dropped .. " dropped, limit " .. maxEntries .. ") ---")
    if stats.dropped > 0 then
        add("!!! TRUNCATED: the " .. stats.dropped
            .. " oldest entries were dropped by the retention limit. This report does"
            .. " not start at the beginning of the recording.")
    end
    if #entries == 0 then
        add(L["DEBUG_EMPTY"])
    else
        for _, entry in ipairs(entries) do
            add("#" .. tostring(entry.seq or "?")
                .. " [" .. escapeExportText(entry.ts or "?") .. "] "
                .. escapeExportText(entry.cat or "?") .. " | "
                .. serializeDebugData(entry.data))
        end
    end

    return table.concat(lines, "\n") .. "\n"
end

ns.buildDebugReportText = buildDebugReportText

-- ----------------------------------------------------------------------------
-- SECTION F4: Report markers and in-game summary
-- ----------------------------------------------------------------------------

-- The five things a closing check used to look for by scrolling the exported
-- text by hand. Reading them from the log itself makes the check a single line
-- the maintainer can read in game -- and lets the offline checker run exactly
-- the same rule on the settings file, instead of a second implementation of it.
function ns.getReportMarkers(log)
    log = log or (SanctuaryDB and SanctuaryDB.debugLog) or {}
    local markers = {
        entries = #log,
        chatOutputNoMatch = false,
        popupMaskAwaitingEvent = false,
        worldInInstance = false,
        playerState = false,
        snapshots = 0,
        -- Every distinct build that wrote a snapshot into this log. A recording
        -- is only about one build; more than one means entries from an earlier
        -- one are still in there and could credit a step nobody played.
        builds = {},
    }
    for i = 1, #log do
        local entry = log[i]
        local data = type(entry) == "table" and entry.data or nil
        if type(data) == "table" then
            local cat = entry.cat
            if cat == "SNAPSHOT" then
                -- Last one wins: every reload writes a new snapshot without
                -- erasing the previous ones, and only the most recent describes
                -- the state the session actually ended in.
                markers.snapshots = markers.snapshots + 1
                markers.chatFilterApiUsed = data.chatFilterApiUsed
                markers.chatFramesSeen = data.chatFramesSeen
                markers.chatFramesWrapped = data.chatFramesWrapped
                markers.systemChatTypeID = data.systemChatTypeID
                markers.addonMetaBuild = data.addonMetaBuild
                markers.addonMetaVersion = data.addonMetaVersion
                markers.addonMetaInterface = data.addonMetaInterface
                if data.build ~= nil then
                    local seen = false
                    for _, known in ipairs(markers.builds) do
                        if known == data.build then seen = true end
                    end
                    if not seen then
                        markers.builds[#markers.builds + 1] = data.build
                    end
                end
            elseif cat == "CHAT_OUTPUT" and data.action == "NO_MATCH" then
                markers.chatOutputNoMatch = true
            elseif cat == "POPUP" and data.action == "MASK_AWAITING_EVENT"
                and (tonumber(data.affected) or 0) >= 1 then
                markers.popupMaskAwaitingEvent = true
            elseif cat == "WORLD" and data.inInstance == true then
                markers.worldInInstance = true
            elseif cat == "PLAYER_STATE" and data.event == "PLAYER_DEAD" then
                -- The scenario is "die, stay a ghost, resurrect". A lone
                -- PLAYER_ALIVE or PLAYER_UNGHOST proves none of it, and used to
                -- credit the step anyway.
                markers.playerState = true
            end
        end
    end
    return markers
end

-- Grades the instrumentation from the markers. "blocking" means the session
-- filtered nothing at all and no measurement taken during it means anything;
-- "degraded" means part of the chat was unobserved or the system message type
-- could not be read, which limits what the recording can prove without voiding
-- it. Kept separate from getReportMarkers so both the panel and the offline
-- checker grade identically.
function ns.getInstrumentationVerdict(markers)
    markers = markers or ns.getReportMarkers()
    local api = markers.chatFilterApiUsed
    if api == nil then
        return "unknown", "no_snapshot"
    end
    if api ~= "legacy" and api ~= "chatframeutil" then
        return "blocking", "chat_filter_api=" .. tostring(api)
    end
    local seen = tonumber(markers.chatFramesSeen) or 0
    local wrapped = tonumber(markers.chatFramesWrapped) or 0
    if seen < 1 or wrapped < seen then
        return "degraded", "chat_frames=" .. tostring(wrapped) .. "/" .. tostring(seen)
    end
    if markers.systemChatTypeID == nil or markers.systemChatTypeID == "unknown" then
        return "degraded", "system_chat_type=unknown"
    end
    return "ok", nil
end

-- Stamped into SavedVariables so the file the game writes on exit identifies
-- itself: which build produced it, on which client, and in what state. Before
-- this, that identity only existed in the text export -- which is exactly the
-- piece that turned out to be unreliable.
function ns.captureReportManifest(trigger)
    if not SanctuaryDB then return nil end
    local health = ns.getInstrumentationHealth()
    local context = getClientBuildContext()
    local stats = getDebugLogStats() or { produced = 0, dropped = 0 }
    -- Graded on the health this manifest is about to carry, not on the last
    -- SNAPSHOT still in the log. Grading one and reporting the other let the
    -- summary print `ChatFilterApi: legacy` under `Verdict: BLOCKING` after the
    -- addon caught up mid-session -- and the reverse, `OK` over degraded
    -- counters, which is the dangerous direction.
    local verdict, detail = ns.getInstrumentationVerdict(health)
    local manifest = {
        trigger = trigger or "unknown",
        savedAt = date("%Y-%m-%d %H:%M:%S"),
        version = VERSION,
        build = BUILD_ID,
        locale = GetLocale() or "?",
        addonMetaVersion = context.addonMetaVersion,
        addonMetaBuild = context.addonMetaBuild,
        addonMetaInterface = context.addonMetaInterface,
        clientVersion = context.clientVersion,
        clientBuild = context.clientBuild,
        clientInterface = context.clientInterface,
        addonEnabled = isEnabled(),
        debugEnabled = SanctuaryDB.debugEnabled and true or false,
        chatFilterApiUsed = health.chatFilterApiUsed,
        chatFramesSeen = health.chatFramesSeen,
        chatFramesWrapped = health.chatFramesWrapped,
        systemChatTypeID = health.systemChatTypeID,
        debugLogClearedAt = SanctuaryDB.debugLogClearedAt,
        debugKept = SanctuaryDB.debugLog and #SanctuaryDB.debugLog or 0,
        debugProduced = stats.produced,
        debugDropped = stats.dropped,
        blockLog = SanctuaryDB.log and #SanctuaryDB.log or 0,
        verdict = verdict,
        verdictDetail = detail or "none",
    }
    SanctuaryDB.reportManifest = manifest
    return manifest
end

-- The window that used to carry the whole recording now carries this instead:
-- a short block that answers the two questions it was really opened for -- is
-- this the right build, and is the instrumentation running -- and says where
-- the actual record is. It is short enough that a rendering defect cannot hide
-- inside it, and losing it costs nothing since it transports no data.
function ns.buildDebugSummaryText()
    if not SanctuaryDB then return "" end

    local manifest = ns.captureReportManifest("summary")
    local markers = ns.getReportMarkers()
    local lines = {}
    local function add(text) lines[#lines + 1] = text end
    local function yesno(value) return value and "oui" or "NON" end

    add("=== SANCTUARY - RESUME DE RELEVE ===")
    add("Date: " .. manifest.savedAt)
    add("Version: " .. manifest.version .. " | Build: " .. manifest.build
        .. " | Locale: " .. manifest.locale)
    add("AddonMeta: version=" .. escapeExportText(manifest.addonMetaVersion)
        .. " build=" .. escapeExportText(manifest.addonMetaBuild)
        .. " interface=" .. escapeExportText(manifest.addonMetaInterface))
    add("Client: " .. escapeExportText(manifest.clientVersion)
        .. " build=" .. escapeExportText(manifest.clientBuild)
        .. " interface=" .. escapeExportText(manifest.clientInterface))

    add("")
    add("--- INSTRUMENTATION ---")
    add("Verdict: " .. manifest.verdict:upper()
        .. (manifest.verdictDetail ~= "none" and (" (" .. manifest.verdictDetail .. ")") or ""))
    add("ChatFilterApi: " .. escapeExportText(manifest.chatFilterApiUsed))
    add("ChatFrames: " .. tostring(manifest.chatFramesWrapped) .. " observees / "
        .. tostring(manifest.chatFramesSeen) .. " vues")
    add("SystemChatTypeID: " .. escapeExportText(manifest.systemChatTypeID))

    add("")
    add("--- ETAT ---")
    add("AddonEnabled: " .. tostring(manifest.addonEnabled)
        .. " | DebugEnabled: " .. tostring(manifest.debugEnabled))
    add("GroupInviteFilter: " .. tostring(getEffective("filters.groupInvite"))
        .. " | StrictGroupInviteSystemMessages: "
        .. tostring(getEffective("filters.strictGroupInviteSystemMessages"))
        .. " | PartyInviteSoundGuard: " .. tostring(partyInviteSoundGuardDepth > 0))
    add("Whitelist: " .. tostring(ns.getWhitelistCacheSize()) .. " personnages / "
        .. tostring(ns.getBNetWhitelistCacheSize()) .. " comptes Battle.net")

    add("")
    add("--- JOURNAL ---")
    add("Debug: " .. tostring(manifest.debugKept) .. " gardees / "
        .. tostring(manifest.debugProduced) .. " produites / "
        .. tostring(manifest.debugDropped) .. " perdues")
    add("Blocages: " .. tostring(manifest.blockLog))
    add("Marqueurs: chat=" .. yesno(markers.chatOutputNoMatch)
        .. " popup=" .. yesno(markers.popupMaskAwaitingEvent)
        .. " instance=" .. yesno(markers.worldInInstance)
        .. " mort=" .. yesno(markers.playerState)
        .. " snapshots=" .. tostring(markers.snapshots))

    add("")
    add("--- RELEVE ---")
    add(L["DEBUG_SUMMARY_FILE"])

    return table.concat(lines, "\n") .. "\n"
end

-- ============================================================================
-- SECTION G: Chat Message Filters (PURE functions — NO side effects)
-- ============================================================================

-- Build invite pattern from WoW global string at init
local invitePatterns = {}
local invitePatternKinds = {}

local function escapePattern(s)
    return s:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
end

local function formatStringToPattern(formatString)
    if type(formatString) ~= "string" or formatString == "" then return nil end

    -- Replace printf tokens before escaping the remaining literal text. Numbered
    -- tokens are supported for locales that reorder placeholders.
    local stringToken = "\001"
    local numberToken = "\002"
    local prepared = formatString
        :gsub("%%%d+%$s", stringToken)
        :gsub("%%s", stringToken)
        :gsub("%%%d+%$d", numberToken)
        :gsub("%%d", numberToken)

    local pattern = escapePattern(prepared)
        :gsub(stringToken, "(.+)")
        :gsub(numberToken, "%%d+")
    return "^" .. pattern .. "$"
end

local function buildInvitePatterns()
    wipe(invitePatterns)
    wipe(invitePatternKinds)
    local seen = {}

    local globals = {
        { name = "ERR_INVITED_TO_GROUP_SS", kind = "popup_backed" },
        { name = "ERR_INVITED_TO_GROUP_S", kind = "popup_backed" },
        { name = "ERR_INVITED_TO_GROUP", kind = "popup_backed" },
        { name = "ERR_INVITED_ALREADY_IN_GROUP_SS", kind = "already_group" },
        { name = "ERR_INVITED_ALREADY_IN_GROUP_S", kind = "already_group" },
    }

    for _, globalInfo in ipairs(globals) do
        local pattern = formatStringToPattern(_G[globalInfo.name])
        if pattern and not seen[pattern] then
            seen[pattern] = true
            invitePatterns[#invitePatterns + 1] = pattern
            invitePatternKinds[#invitePatterns] = globalInfo.kind
        end
    end

    -- The client globals are the source of truth. These fallbacks only protect
    -- startup/API edge cases where the localized strings are unexpectedly nil.
    if #invitePatterns == 0 then
        invitePatterns[#invitePatterns + 1] = "^%[(.+)%] vous a invit"
        invitePatternKinds[#invitePatterns] = "unknown"
        invitePatterns[#invitePatterns + 1] = "^%[(.+)%] has invited you to join a group"
        invitePatternKinds[#invitePatterns] = "unknown"
    end
end

local function extractInviterFromSystemMessage(msg)
    if isRestrictedValue(msg) or type(msg) ~= "string" or msg == "" then return nil, nil, nil end
    for idx, pattern in ipairs(invitePatterns) do
        local name = msg:match(pattern)
        if name then
            -- Clean the name (remove realm info artifacts, brackets etc)
            name = name:gsub("%[", ""):gsub("%]", "")
            name = name:match("^%s*(.-)%s*$")
            if name ~= "" then
                return name, idx, invitePatternKinds[idx] or "unknown"
            end
        end
    end
    return nil, nil, nil
end

local function shouldSuppressSecretGroupInviteSystemMessage(msg)
    if not isRestrictedValue(msg) then return false end
    if not isEnabled() or getEffective("filters.groupInvite") ~= true then return false end
    if getEffective("filters.strictGroupInviteSystemMessages") ~= true then return false end

    local context = getRuntimeContext()
    return context.inGroup or context.inRaid or context.inInstance
end

-- System-message filters are invoked once per destination chat frame, so they
-- must stay side-effect free. Logging/debugging happens in CHAT_MSG_SYSTEM.
local function systemMessageFilter(self, event, msg, ...)
    if not isEnabled() then return false end
    if not getEffective("filters.groupInvite") then return false end

    if shouldSuppressSecretGroupInviteSystemMessage(msg) then return true end

    local inviterName = extractInviterFromSystemMessage(msg)
    if not inviterName then return false end

    local shouldBlock = getCharacterDecision(inviterName)
    return shouldBlock
end

-- Whisper filter (P1 — active if setting enabled)
local function whisperFilter(self, event, msg, sender, ...)
    if not isEnabled() then return false end

    local keywordMatch = matchesKeyword(sender)
    if keywordMatch then return true end
    if not getEffective("filters.whisper") then return false end

    local shouldBlock = getCharacterDecision(sender)
    return shouldBlock
end

-- Battle.net whispers use account display names, not character names.
local function bnetWhisperFilter(self, event, msg, sender, ...)
    if not isEnabled() then return false end

    local bnetSender = resolveBNetWhisperSender(sender, ...)
    local decisionName = bnetSender.accountName or sender
    local keywordMatch = matchesKeyword(decisionName)
    if keywordMatch then return true end
    if not getEffective("filters.whisper") then return false end

    if isBNetWhitelisted(decisionName) then return false end
    if isBNetSenderInGroup and isBNetSenderInGroup(decisionName) then return false end
    return true
end

local function normalizeRealmToken(realm)
    if not realm or realm == "" then return nil end
    return realm:lower():gsub("[%s%-']", "")
end

-- Never filter the player's own public messages. Realm information is honored
-- when present so a same-named player on another realm is not mistaken for self.
local function isSelf(sender)
    local clean = stripWoWFormatting(sender)
    if not clean then return false end

    local senderName, senderRealm = clean:match("^([^-]+)%-(.+)$")
    senderName = senderName or clean

    local playerName, playerRealm
    if UnitFullName then
        playerName, playerRealm = UnitFullName("player")
    end
    playerName = playerName or UnitName("player")
    playerRealm = playerRealm or getPlayerRealm()
    if not playerName or senderName:lower() ~= playerName:lower() then
        return false
    end

    if senderRealm and senderRealm ~= "" then
        return normalizeRealmToken(senderRealm) == normalizeRealmToken(playerRealm)
    end
    return true
end

-- Say filter (P2 — off by default)
local function sayFilter(self, event, msg, sender, ...)
    if not isEnabled() then return false end
    if isSelf(sender) then return false end

    local keywordMatch = matchesKeyword(sender)
    if keywordMatch then return true end
    if not getEffective("filters.say") then return false end

    local shouldBlock = getCharacterDecision(sender)
    return shouldBlock
end

-- Yell filter (P2 — off by default)
local function yellFilter(self, event, msg, sender, ...)
    if not isEnabled() then return false end
    if isSelf(sender) then return false end

    local keywordMatch = matchesKeyword(sender)
    if keywordMatch then return true end
    if not getEffective("filters.yell") then return false end

    local shouldBlock = getCharacterDecision(sender)
    return shouldBlock
end

-- Emote filter (P2 — off by default)
local function emoteFilter(self, event, msg, sender, ...)
    if not isEnabled() then return false end
    if isSelf(sender) then return false end

    local keywordMatch = matchesKeyword(sender)
    if keywordMatch then return true end
    if not getEffective("filters.emote") then return false end

    local shouldBlock = getCharacterDecision(sender)
    return shouldBlock
end

-- Channel filter (/1, /2, /3...) with 3 modes: none, keywords, all
local function channelFilter(self, event, msg, sender, ...)
    if not isEnabled() then return false end
    if isSelf(sender) then return false end

    local mode = getEffective("filters.channelMode") or "none"
    if mode == "none" then return false end

    local keywordMatch = matchesKeyword(sender)
    if keywordMatch then return true end
    if mode ~= "all" then return false end

    local shouldBlock = getCharacterDecision(sender)
    return shouldBlock
end

-- Register all filters
local chatFiltersRegistered = false
local isStaticPopupSoundSuppressed
local function registerChatFilters()
    if chatFiltersRegistered then return end

    local addFilter, apiPath = resolveChatFilterRegistrar()
    if not addFilter then
        chatFilterApiUsed = "none"
        debugLog("CHAT_FILTER_REGISTRY", {
            action = "UNAVAILABLE",
            api = apiPath,
        })
        return
    end

    chatFiltersRegistered = true
    chatFilterApiUsed = apiPath

    addFilter("CHAT_MSG_SYSTEM", systemMessageFilter)
    addFilter("CHAT_MSG_WHISPER", whisperFilter)
    addFilter("CHAT_MSG_BN_WHISPER", bnetWhisperFilter)
    addFilter("CHAT_MSG_SAY", sayFilter)
    addFilter("CHAT_MSG_YELL", yellFilter)
    addFilter("CHAT_MSG_EMOTE", emoteFilter)
    addFilter("CHAT_MSG_TEXT_EMOTE", emoteFilter)
    addFilter("CHAT_MSG_CHANNEL", channelFilter)

    debugLog("CHAT_FILTER_REGISTRY", {
        action = "REGISTERED",
        api = apiPath,
        available = describeChatFilterApi(),
    })
end

-- Last-resort guard for invite text printed directly through ChatFrame:AddMessage.
-- The event filter remains the primary path, but Retail/other addons can still
-- print directly to a frame. Keep this wrapper narrow: no native API calls, no
-- sound/popup changes, and only exact localized invite-system text is suppressed.
chatOutputWrapped = setmetatable({}, { __mode = "k" })
local activeChatOutputProbe

-- Retail calls ChatFrame:AddMessage(text, r, g, b, messageTypeID, ...), so the
-- fifth effective argument identifies the chat category the client is printing.
-- The secret payload itself is never read, converted or serialized; only this
-- category is measured, and only to learn whether the leaked lines really are
-- ChatTypeInfo.SYSTEM before any suppression is considered.
local SECRET_OUTPUT_MESSAGE_TYPE_INDEX = 4

local function describeSecretOutputMessageType(...)
    local messageTypeID = select(SECRET_OUTPUT_MESSAGE_TYPE_INDEX, ...)
    local systemTypeID = readSystemChatTypeID()
    local described = {
        messageTypeID = "nil",
        messageTypeIDKnown = false,
        systemTypeID = systemTypeID or "unknown",
        isSystemTypeID = false,
        isSystemTypeIDKnown = false,
    }

    if messageTypeID == nil then
        described.signature = "nil/" .. tostring(described.systemTypeID)
        return described
    end

    if isRestrictedValue(messageTypeID) then
        described.messageTypeID = SECRET_VALUE_PLACEHOLDER
        described.signature = SECRET_VALUE_PLACEHOLDER .. "/" .. tostring(described.systemTypeID)
        return described
    end

    local ok, numeric = pcall(tonumber, messageTypeID)
    if ok and numeric then
        described.messageTypeID = numeric
        described.messageTypeIDKnown = true
        if systemTypeID then
            described.isSystemTypeID = numeric == systemTypeID
            described.isSystemTypeIDKnown = true
        end
    else
        described.messageTypeID = safeText(messageTypeID, 40, "nil")
    end

    described.signature = tostring(described.messageTypeID) .. "/" .. tostring(described.systemTypeID)
    return described
end

-- One chat payload is dispatched to every subscribed ChatFrame, so a single
-- secret system line produces one AddMessage call per frame. Collapse that burst
-- into a single diagnostic carrying the frame list instead of N near-identical
-- entries, otherwise the log volume hides the signal it is meant to measure.
local secretChatOutputBurst = nil

local function recordSecretChatOutput(frameIndex, ...)
    if not SanctuaryDB or not SanctuaryDB.debugEnabled then return end

    local described = describeSecretOutputMessageType(...)
    local now = GetTime()
    local burst = secretChatOutputBurst

    -- Only a readable message type discriminates two payloads. When the category
    -- is secret or absent the signature degenerates and two distinct messages
    -- landing on different frames within the window would merge into one
    -- frameCount, so an unreadable category always gets its own entry.
    -- A frame index that already belongs to the burst means a *new* message,
    -- not another destination for the same one: Blizzard dispatches a payload
    -- at most once per frame. Only a not-yet-seen frame extends the burst.
    if described.messageTypeIDKnown and burst and burst.signature == described.signature
        and (now - burst.time) < 0.5 and not burst.frames[frameIndex] then
        local entry = SanctuaryDB.debugLog and SanctuaryDB.debugLog[#SanctuaryDB.debugLog]
        if entry and entry.seq == burst.seq and entry.data then
            burst.frames[frameIndex] = true
            burst.frameList[#burst.frameList + 1] = frameIndex
            entry.data.frames = table.concat(burst.frameList, ",")
            entry.data.frameCount = #burst.frameList
            return
        end
    end

    debugLog("CHAT_OUTPUT", addRuntimeContext({
        frame = frameIndex,
        frames = tostring(frameIndex),
        frameCount = 1,
        action = "SECRET_VALUE",
        msg = SECRET_VALUE_PLACEHOLDER,
        messageTypeID = described.messageTypeID,
        messageTypeIDKnown = described.messageTypeIDKnown,
        systemTypeID = described.systemTypeID,
        isSystemTypeID = described.isSystemTypeID,
        isSystemTypeIDKnown = described.isSystemTypeIDKnown,
        argCount = select("#", ...),
        filterEnabled = isEnabled() and getEffective("filters.groupInvite") == true,
        strictGroupInviteSystemMessages = getEffective("filters.strictGroupInviteSystemMessages") == true,
        soundGuardActive = isStaticPopupSoundSuppressed("PARTY_INVITE"),
    }))

    local entry = SanctuaryDB.debugLog and SanctuaryDB.debugLog[#SanctuaryDB.debugLog]
    if entry and described.messageTypeIDKnown then
        secretChatOutputBurst = {
            seq = entry.seq,
            signature = described.signature,
            time = now,
            frames = { [frameIndex] = true },
            frameList = { frameIndex },
        }
    else
        -- No burst is opened on an unreadable category: nothing may attach to it.
        secretChatOutputBurst = nil
    end
end

local function hookChatOutputDiagnostics()
    for i = 1, 20 do
        local chatFrame = _G["ChatFrame" .. i]
        if chatFrame and chatOutputWrapped[chatFrame] ~= chatFrame.AddMessage and chatFrame.AddMessage then
            local frameIndex = i
            local original = chatFrame.AddMessage
            local function wrappedAddMessage(self, text, ...)
                if chatOutputWrapped[self] ~= wrappedAddMessage then
                    return original(self, text, ...)
                end

                if isRestrictedValue(text) then
                    -- Instrumentation step only: the secret line still reaches
                    -- the original AddMessage. Suppressing here is not allowed
                    -- until the measured message type proves it can be done
                    -- without hiding a legitimate message.
                    recordSecretChatOutput(frameIndex, ...)
                    return original(self, text, ...)
                end

                local inviterName, patternIndex, patternKind = extractInviterFromSystemMessage(text)
                if inviterName then
                    local shouldBlock, reason, keyword = getCharacterDecision(inviterName)
                    local filterEnabled = isEnabled() and getEffective("filters.groupInvite") == true
                    local suppress = filterEnabled and shouldBlock
                    if activeChatOutputProbe and activeChatOutputProbe.message == text then
                        activeChatOutputProbe.observed = true
                        activeChatOutputProbe.frame = frameIndex
                        activeChatOutputProbe.action = suppress and "SUPPRESS_BLOCKED_INVITE" or "ALLOW_INVITE_OUTPUT"
                        activeChatOutputProbe.suppressed = suppress and true or false
                    end
                    debugLog("CHAT_OUTPUT", addRuntimeContext({
                        frame = frameIndex,
                        action = suppress and "SUPPRESS_BLOCKED_INVITE" or "ALLOW_INVITE_OUTPUT",
                        msg = safeText(text, 300, "nil"),
                        name = inviterName,
                        pattern = patternIndex or "?",
                        patternKind = patternKind or "unknown",
                        shouldBlock = shouldBlock and true or false,
                        reason = reason or "nil",
                        keyword = keyword or "none",
                        filterEnabled = filterEnabled and true or false,
                        soundGuardActive = isStaticPopupSoundSuppressed("PARTY_INVITE"),
                    }))
                    if suppress then
                        return
                    end
                elseif type(text) == "string" and SanctuaryDB and SanctuaryDB.debugEnabled
                    and not text:find("[Sanctuary]", 1, true) then
                    local lowerText = text:lower()
                    if lowerText:find("invit", 1, true) or lowerText:find("group", 1, true) then
                        if activeChatOutputProbe and activeChatOutputProbe.message == text then
                            activeChatOutputProbe.observed = true
                            activeChatOutputProbe.frame = frameIndex
                            activeChatOutputProbe.action = "NO_MATCH"
                            activeChatOutputProbe.suppressed = false
                        end
                        debugLog("CHAT_OUTPUT", addRuntimeContext({
                            frame = frameIndex,
                            action = "NO_MATCH",
                            msg = safeText(text, 300, "nil"),
                            filterEnabled = isEnabled() and getEffective("filters.groupInvite") == true,
                            soundGuardActive = isStaticPopupSoundSuppressed("PARTY_INVITE"),
                        }))
                    end
                end

                return original(self, text, ...)
            end

            local ok, err = pcall(function()
                chatFrame.AddMessage = wrappedAddMessage
            end)
            if ok then
                chatOutputWrapped[chatFrame] = wrappedAddMessage
            else
                debugLog("CHAT_OUTPUT", addRuntimeContext({
                    frame = frameIndex,
                    action = "WRAP_FAILED",
                    error = tostring(err),
                }))
            end
        end
    end
end

ns.hookChatOutputDiagnostics = hookChatOutputDiagnostics

-- StaticPopup_Show is also used by protected Blizzard UI such as CAMP/QUIT.
-- Retail live testing confirmed that wrapping it globally can break quit/logout
-- flows, so Sanctuary only adjusts the specific invite/duel dialog definitions.
local STATIC_POPUP_SOUND_GUARDS = {
    PARTY_INVITE = "filters.groupInvite",
    DUEL_REQUESTED = "filters.duel",
}

local PROTECTED_POPUP_SOUND_FILES = {
    567490,  -- igMainMenuOpen
    567464,  -- igMainMenuClose
}

local partyInviteOriginalSound = nil
local staticPopupSoundGuardStates = {}
partyInviteSoundGuardDepth = 0
local protectedPopupSoundGuardDepth = 0
local protectedPopupSoundGuardSerial = 0
local protectedPopupSoundGuardTokens = {}
local protectedPopupSoundGuardDialogs = setmetatable({}, { __mode = "k" })
local staticPopupOnShowGuardHooked = false
local guildInviteFrameSoundGuardToken = nil
local releaseProtectedPopupSoundGuards
local releaseGuildInviteFrameSoundGuard

capturePartyInviteOriginalSound = function()
    local state = staticPopupSoundGuardStates.PARTY_INVITE
    if state and state.originalSound then
        partyInviteOriginalSound = state.originalSound
    else
        local dialog = StaticPopupDialogs and StaticPopupDialogs.PARTY_INVITE
        if not partyInviteOriginalSound and dialog and dialog.sound then
            partyInviteOriginalSound = dialog.sound
        end
    end
    return partyInviteOriginalSound
end

local function captureStaticPopupSound(which)
    local state = staticPopupSoundGuardStates[which]
    if state and state.originalSound then
        return state.originalSound
    end

    local dialog = StaticPopupDialogs and StaticPopupDialogs[which]
    if not dialog then return nil end

    state = state or {}
    state.originalSound = state.originalSound or dialog.sound
    staticPopupSoundGuardStates[which] = state
    if which == "PARTY_INVITE" and state.originalSound then
        partyInviteOriginalSound = state.originalSound
    end
    return state.originalSound
end

isStaticPopupSoundSuppressed = function(which)
    local state = staticPopupSoundGuardStates[which]
    return state and state.active or false
end

local function resetStaticPopupSoundGuardDepth()
    partyInviteSoundGuardDepth = 0
    for guardedWhich in pairs(STATIC_POPUP_SOUND_GUARDS) do
        if isStaticPopupSoundSuppressed(guardedWhich) then
            partyInviteSoundGuardDepth = partyInviteSoundGuardDepth + 1
        end
    end
end

local function setStaticPopupSoundSuppressed(which, shouldSuppress, reason)
    local dialog = StaticPopupDialogs and StaticPopupDialogs[which]
    if not dialog then
        debugLog("SOUND", {
            action = shouldSuppress and "DIALOG_SOUND_OFF_SKIPPED" or "DIALOG_SOUND_ON_SKIPPED",
            which = which or "nil",
            reason = reason or "unknown",
            skipReason = "dialog_missing",
        })
        return false
    end

    local state = staticPopupSoundGuardStates[which] or {}
    if not state.originalSound and dialog.sound then
        state.originalSound = dialog.sound
    end
    staticPopupSoundGuardStates[which] = state

    if shouldSuppress and not state.active then
        dialog.sound = nil
        state.active = true
    elseif not shouldSuppress and state.active then
        dialog.sound = state.originalSound
        state.active = false
    else
        return false
    end

    resetStaticPopupSoundGuardDepth()

    debugLog("SOUND", {
        action = state.active and "DIALOG_SOUND_OFF" or "DIALOG_SOUND_ON",
        which = which,
        reason = reason or "unknown",
        sound = tostring(state.originalSound or "nil"),
        active = state.active and true or false,
        depth = partyInviteSoundGuardDepth,
    })
    return true
end

local function restoreStaticPopupSoundAfterShow(which, reason)
    local state = staticPopupSoundGuardStates[which]
    if not state or not state.temporarilyRestoredForShow then return false end

    state.temporarilyRestoredForShow = nil
    local dialog = StaticPopupDialogs and StaticPopupDialogs[which]
    if state.active and dialog then
        dialog.sound = nil
    end

    debugLog("SOUND", {
        action = "DIALOG_SOUND_TEMP_OFF",
        which = which or "nil",
        reason = reason or "unknown",
        sound = tostring(state.originalSound or "nil"),
        active = state.active and true or false,
    })
    return true
end

-- A mute posted by MuteSoundFile survives /reload and relogging; only a full
-- client restart clears it. So an unmute that fails is not a transient glitch:
-- it leaves the game's generic panel sounds off, with no way for the person to
-- connect that to Sanctuary or to undo it short of restarting the client. The
-- invariant to hold is "the files end up unmuted", which needs a bounded retry
-- and a record of what is still muted -- not just a reordering of the release.
local PROTECTED_POPUP_SOUND_UNMUTE_RETRY_DELAY = 1
local PROTECTED_POPUP_SOUND_UNMUTE_MAX_ATTEMPTS = 5
local protectedPopupSoundMutedFiles = {}
local protectedPopupSoundUnmuteRetryPending = false
local protectedPopupSoundUnmuteAlerted = false
local scheduleProtectedPopupSoundUnmuteRetry

local function countProtectedPopupSoundMutedFiles()
    local count = 0
    for _, fileID in ipairs(PROTECTED_POPUP_SOUND_FILES) do
        if protectedPopupSoundMutedFiles[fileID] then count = count + 1 end
    end
    return count
end

-- Mirrors the mute state into SavedVariables. The two situations where a mute
-- outlives the code that posted it -- /reload and relogging -- are exactly the
-- two where SavedVariables are written, so this flag is what lets the next load
-- clear a mute this addon left behind. A crashed client loses the flag, but it
-- also loses the mute.
local function rememberProtectedPopupSoundMuteState()
    if not SanctuaryDB then return end
    SanctuaryDB.protectedPopupSoundMuted = countProtectedPopupSoundMutedFiles() > 0 or nil
end

local function muteProtectedPopupSoundFiles()
    local failures = 0
    local firstError = nil
    for _, fileID in ipairs(PROTECTED_POPUP_SOUND_FILES) do
        local ok, err = pcall(MuteSoundFile, fileID)
        if ok then
            protectedPopupSoundMutedFiles[fileID] = true
        else
            failures = failures + 1
            firstError = firstError or tostring(err)
        end
    end
    rememberProtectedPopupSoundMuteState()
    return failures, firstError
end

-- Only unmutes what is still recorded as muted, so a retry never touches a file
-- this addon did not mute.
local function unmuteProtectedPopupSoundFiles()
    local failures = 0
    local firstError = nil
    for _, fileID in ipairs(PROTECTED_POPUP_SOUND_FILES) do
        if protectedPopupSoundMutedFiles[fileID] then
            local ok, err = pcall(UnmuteSoundFile, fileID)
            if ok then
                protectedPopupSoundMutedFiles[fileID] = nil
            else
                failures = failures + 1
                firstError = firstError or tostring(err)
            end
        end
    end
    rememberProtectedPopupSoundMuteState()
    return failures, firstError, countProtectedPopupSoundMutedFiles()
end

scheduleProtectedPopupSoundUnmuteRetry = function(which, reason, attempt)
    if protectedPopupSoundUnmuteRetryPending then return end
    protectedPopupSoundUnmuteRetryPending = true

    C_Timer.After(PROTECTED_POPUP_SOUND_UNMUTE_RETRY_DELAY, function()
        protectedPopupSoundUnmuteRetryPending = false

        -- A new guard took over in the meantime: the files are meant to be muted
        -- right now, and its own release owns the next attempt.
        if protectedPopupSoundGuardDepth > 0 then
            debugLog("SOUND", {
                action = "POPUP_GUARD_UNMUTE_RETRY_SKIPPED",
                which = which or "nil",
                reason = "guard_reacquired",
                attempt = attempt,
                depth = protectedPopupSoundGuardDepth,
                stillMuted = countProtectedPopupSoundMutedFiles(),
            })
            return
        end

        local failures, firstError, stillMuted = unmuteProtectedPopupSoundFiles()
        debugLog("SOUND", {
            action = "POPUP_GUARD_UNMUTE_RETRY",
            which = which or "nil",
            reason = reason or "unknown",
            attempt = attempt,
            failures = failures,
            firstError = firstError or "none",
            stillMuted = stillMuted,
        })

        if stillMuted == 0 then return end

        if attempt < PROTECTED_POPUP_SOUND_UNMUTE_MAX_ATTEMPTS then
            scheduleProtectedPopupSoundUnmuteRetry(which, reason, attempt + 1)
            return
        end

        -- Bounded means it can give up. Staying silent here would leave the
        -- person with degraded game audio and nothing to act on, so say it once
        -- and say what actually clears it.
        debugLog("SOUND", {
            action = "POPUP_GUARD_UNMUTE_ABANDONED",
            which = which or "nil",
            reason = reason or "unknown",
            attempt = attempt,
            stillMuted = stillMuted,
        })
        if not protectedPopupSoundUnmuteAlerted then
            protectedPopupSoundUnmuteAlerted = true
            printError(L["SOUND_UNMUTE_FAILED"])
        end
    end)
end

-- Clears a mute left behind by a previous session. Called at load, where no
-- guard can be active yet, and only for files this addon recorded as muted.
local function releaseStaleProtectedPopupSoundMute()
    if not SanctuaryDB or not SanctuaryDB.protectedPopupSoundMuted then return false end

    for _, fileID in ipairs(PROTECTED_POPUP_SOUND_FILES) do
        protectedPopupSoundMutedFiles[fileID] = true
    end
    local failures, firstError, stillMuted = unmuteProtectedPopupSoundFiles()
    debugLog("SOUND", {
        action = "POPUP_GUARD_STALE_UNMUTE",
        reason = "previous_session",
        failures = failures,
        firstError = firstError or "none",
        stillMuted = stillMuted,
    })
    if stillMuted > 0 then
        scheduleProtectedPopupSoundUnmuteRetry("STALE", "previous_session", 1)
    end
    return true
end

local function acquireProtectedPopupSoundGuard(which, reason)
    protectedPopupSoundGuardSerial = protectedPopupSoundGuardSerial + 1
    local token = protectedPopupSoundGuardSerial
    protectedPopupSoundGuardTokens[token] = true
    protectedPopupSoundGuardDepth = protectedPopupSoundGuardDepth + 1

    local failures = 0
    local firstError = nil
    if protectedPopupSoundGuardDepth == 1 then
        failures, firstError = muteProtectedPopupSoundFiles()
    end

    debugLog("SOUND", {
        action = "POPUP_GUARD_ON",
        which = which or "nil",
        reason = reason or "unknown",
        depth = protectedPopupSoundGuardDepth,
        files = #PROTECTED_POPUP_SOUND_FILES,
        failures = failures,
        firstError = firstError or "none",
    })
    return token
end

local function releaseProtectedPopupSoundGuard(token, which, reason)
    if token and not protectedPopupSoundGuardTokens[token] then return false end
    if token then
        protectedPopupSoundGuardTokens[token] = nil
    end
    if protectedPopupSoundGuardDepth <= 0 then return false end

    -- The depth still drops on failure. Holding it up would keep the guard
    -- nominally active, so the next acquire would re-mute nothing and no path
    -- would ever lift the mute -- the opposite of the invariant. The retry below
    -- is what closes the gap.
    protectedPopupSoundGuardDepth = protectedPopupSoundGuardDepth - 1
    local failures = 0
    local firstError = nil
    local stillMuted = countProtectedPopupSoundMutedFiles()
    if protectedPopupSoundGuardDepth == 0 then
        failures, firstError, stillMuted = unmuteProtectedPopupSoundFiles()
        if stillMuted > 0 then
            scheduleProtectedPopupSoundUnmuteRetry(which, reason, 1)
        end
    end

    debugLog("SOUND", {
        action = "POPUP_GUARD_OFF",
        which = which or "nil",
        reason = reason or "unknown",
        depth = protectedPopupSoundGuardDepth,
        files = #PROTECTED_POPUP_SOUND_FILES,
        failures = failures,
        firstError = firstError or "none",
        stillMuted = stillMuted,
    })
    return true
end

local function playAllowedProtectedPopupSounds(which, reason)
    local openSound = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPEN
    local openOk = true
    local openErr = nil
    if openSound then
        openOk, openErr = pcall(PlaySound, openSound)
    end

    local popupSound = captureStaticPopupSound(which)
    local popupOk = true
    local popupErr = nil
    if popupSound then
        popupOk, popupErr = pcall(PlaySound, popupSound)
    end
    debugLog("SOUND", {
        action = "PLAY_ALLOWED_POPUP",
        which = which or "nil",
        reason = reason or "unknown",
        openSound = tostring(openSound or "nil"),
        openOk = openOk and true or false,
        popupSound = tostring(popupSound or "nil"),
        popupOk = popupOk and true or false,
        error = (openOk and popupOk) and "none" or tostring(openErr or popupErr),
    })
    return (openOk and popupOk) and true or false
end

local function prepareStaticPopupSoundForShow(dialog)
    if not dialog then return end
    local which = dialog.which
    if not STATIC_POPUP_SOUND_GUARDS[which] then return end
    if not isStaticPopupSoundSuppressed(which) then return end

    local decision = pendingPopupDecisions and pendingPopupDecisions[which] or nil
    if decision and not decision.shouldBlock then
        local sound = captureStaticPopupSound(which)
        local dialogInfo = StaticPopupDialogs and StaticPopupDialogs[which]
        if dialogInfo and sound then
            dialogInfo.sound = sound
            local state = staticPopupSoundGuardStates[which] or {}
            state.originalSound = state.originalSound or sound
            state.temporarilyRestoredForShow = true
            staticPopupSoundGuardStates[which] = state
        end
        debugLog("SOUND", {
            action = "DIALOG_SOUND_TEMP_ON",
            which = which,
            reason = "pending_allow",
            sound = tostring(sound or "nil"),
        })
        return
    end

    if protectedPopupSoundGuardDialogs[dialog] then return end

    local token = acquireProtectedPopupSoundGuard(which, decision and "pending_block" or "awaiting_event")
    protectedPopupSoundGuardDialogs[dialog] = {
        token = token,
        which = which,
    }
end

local function installStaticPopupSoundOnShowGuard()
    if staticPopupOnShowGuardHooked then return true end
    if type(hooksecurefunc) ~= "function" or type(StaticPopup_OnShow) ~= "function" then
        debugLog("SOUND", {
            action = "STATICPOPUP_ONSHOW_HOOK_SKIPPED",
            reason = "api_missing",
        })
        return false
    end

    local ok, err = pcall(hooksecurefunc, "StaticPopup_OnShow", prepareStaticPopupSoundForShow)
    if ok then
        staticPopupOnShowGuardHooked = true
        debugLog("SOUND", {
            action = "STATICPOPUP_ONSHOW_HOOKED",
        })
        return true
    end

    debugLog("SOUND", {
        action = "STATICPOPUP_ONSHOW_HOOK_FAILED",
        error = tostring(err),
    })
    return false
end

local function refreshInviteSoundMuteState()
    installStaticPopupSoundOnShowGuard()
    for which, filterPath in pairs(STATIC_POPUP_SOUND_GUARDS) do
        local shouldSuppress = isEnabled() and getEffective(filterPath) == true
        setStaticPopupSoundSuppressed(which, shouldSuppress, shouldSuppress and "filter_enabled" or "filter_disabled")
    end

    if not isEnabled() then
        releaseProtectedPopupSoundGuards(nil, "filter_disabled")
        releaseGuildInviteFrameSoundGuard("filter_disabled")
        return
    end
    if not getEffective("filters.duel") then
        releaseProtectedPopupSoundGuards("DUEL_REQUESTED", "filter_disabled")
    end
    if not getEffective("filters.guildInvite") then
        releaseGuildInviteFrameSoundGuard("filter_disabled")
    end
    if not getEffective("filters.groupInvite") then
        releaseProtectedPopupSoundGuards("PARTY_INVITE", "filter_disabled")
        if unmaskVisiblePopup then
            unmaskVisiblePopup("PARTY_INVITE")
        end
    end
end

ns.getPartyInviteOriginalSound = capturePartyInviteOriginalSound
ns.isStaticPopupSoundSuppressed = isStaticPopupSoundSuppressed
ns.isPartyInviteSoundGuardActive = function()
    return partyInviteSoundGuardDepth > 0
end
ns.areInviteSoundsMuted = ns.isPartyInviteSoundGuardActive
ns.refreshInviteSoundMuteState = refreshInviteSoundMuteState

-- Close only the whisper/BNet tab that belongs to the blocked sender. The old
-- implementation closed every non-whitelisted whisper tab and could destroy an
-- unrelated conversation.
local function closeBlockedWhisperTabs(blockedSender, isBNet)
    if not blockedSender then return end

    local normalizeTarget = isBNet and normalizeBNetName or normalizeName
    local wanted = normalizeTarget(blockedSender)
    if not wanted then return end

    C_Timer.After(0, function()
        for i = 1, 20 do
            local chatFrame = _G["ChatFrame" .. i]
            if chatFrame then
                local expectedType = isBNet and "BN_WHISPER" or "WHISPER"
                if chatFrame.chatType == expectedType then
                    local matches = false
                    if chatFrame.chatTarget then
                        matches = normalizeTarget(chatFrame.chatTarget) == wanted
                    end

                    if not matches then
                        local tab = _G["ChatFrame" .. i .. "Tab"]
                        local tabText = tab and tab.Text and tab.Text:GetText()
                        if tabText then
                            matches = normalizeTarget(tabText) == wanted
                        end
                    end

                    if matches then
                        local ok = pcall(FCF_Close, chatFrame)
                        debugLog("WHISPER_TAB", {
                            action = "CLOSE",
                            ok = ok and true or false,
                            frame = i,
                            chatType = expectedType,
                            target = blockedSender,
                            normalized = wanted,
                        })
                    end
                end
            end
        end
    end)
end

-- Check if a BNet whisper sender has a character in the current group
isBNetSenderInGroup = function(senderBNetName)
    if not IsInGroup() then return false end
    local senderKey = normalizeBNetName(senderBNetName)
    if not senderKey then return false end

    local found = false
    local accountMatched = false
    local normalizedCharacter = nil
    local missingCharacterName = false
    local membersChecked = 0
    local ok, err = pcall(function()
        local numFriends = BNGetNumFriends() or 0
        for i = 1, numFriends do
            local info = ns.getBNetFriendInfo and ns.getBNetFriendInfo(i)
            if info and normalizeBNetName(info.accountName) == senderKey then
                accountMatched = true
                local gameInfo = info.gameAccountInfo
                local charName = gameInfo and normalizeName(gameInfo.characterName)
                normalizedCharacter = charName
                if charName then
                    local numMembers = GetNumGroupMembers() or 0
                    local isRaid = IsInRaid()
                    for j = 1, numMembers do
                        membersChecked = membersChecked + 1
                        local unit = isRaid and ("raid" .. j) or ("party" .. j)
                        local unitName = UnitName(unit)
                        if unitName and normalizeName(unitName) == charName then
                            found = true
                            return
                        end
                    end
                else
                    missingCharacterName = true
                end
            end
        end
    end)
    if accountMatched or not ok then
        debugLog("BNET_GROUP", addRuntimeContext({
            sender = senderBNetName or "nil",
            normalized = senderKey,
            accountMatched = accountMatched and true or false,
            character = normalizedCharacter or "nil",
            missingCharacterName = missingCharacterName and true or false,
            membersChecked = membersChecked,
            result = found and true or false,
            ok = ok and true or false,
            error = ok and "none" or tostring(err),
        }))
    end
    return found
end

-- ============================================================================
-- Popup masking and event-order synchronization
-- ============================================================================
-- StaticPopup_Show runs synchronously inside Blizzard's event handling. A
-- secure post-hook can therefore set alpha to zero before the next rendered
-- frame. The PARTY_INVITE_REQUEST/DUEL_REQUESTED handlers then supply the trust
-- decision. The small pending-decision bridge supports both possible handler
-- orders: Sanctuary before Blizzard or Blizzard before Sanctuary.
--
-- Native decline APIs remain responsible for closing their own dialogs. Never
-- call StaticPopup_Hide for these interactions: Midnight attaches stateful
-- countdown tickers to some invite dialogs and direct hiding can leave them
-- alive across popup reuse.
local maskedPopupState = setmetatable({}, { __mode = "k" })
local popupHideHooked = setmetatable({}, { __mode = "k" })
pendingPopupDecisions = {}
local popupDecisionSerial = 0
local POPUP_DECISION_MAX_AGE = 1.0
local GUILD_INVITE_FRAME_KEY = "GUILD_INVITE_FRAME"
local unmaskGuildInviteFrame
local clearPendingGuildInviteFrameDecision

local function restorePopup(dialog)
    local state = maskedPopupState[dialog]
    if not state then return end
    maskedPopupState[dialog] = nil
    if dialog and dialog.SetAlpha then
        dialog:SetAlpha(state.alpha or 1)
    end
end

local function maskPopupDialog(dialog, which)
    if not dialog or not dialog.IsShown or not dialog:IsShown() then return false end
    if dialog.which ~= which then return false end

    if not maskedPopupState[dialog] then
        maskedPopupState[dialog] = {
            alpha = dialog.GetAlpha and dialog:GetAlpha() or 1,
            which = which,
        }
    end

    if not popupHideHooked[dialog] and dialog.HookScript then
        popupHideHooked[dialog] = true
        dialog:HookScript("OnHide", function(self)
            restorePopup(self)
            local protectedState = protectedPopupSoundGuardDialogs[self]
            if protectedState then
                protectedPopupSoundGuardDialogs[self] = nil
                releaseProtectedPopupSoundGuard(protectedState.token, protectedState.which, "popup_hide")
            end
        end)
    end

    dialog:SetAlpha(0)
    return true
end

local function forEachStaticPopup(callback)
    local count = tonumber(_G.STATICPOPUP_NUMDIALOGS) or 4
    for i = 1, count do
        local dialog = _G["StaticPopup" .. i]
        if dialog then callback(dialog) end
    end
end

local function countVisiblePopup(which)
    local count = 0
    forEachStaticPopup(function(dialog)
        if dialog.IsShown and dialog:IsShown() and dialog.which == which then
            count = count + 1
        end
    end)
    return count
end

local function maskVisiblePopup(which)
    local masked = 0
    forEachStaticPopup(function(dialog)
        if maskPopupDialog(dialog, which) then
            masked = masked + 1
        end
    end)
    return masked
end

unmaskVisiblePopup = function(which)
    local restored = 0
    forEachStaticPopup(function(dialog)
        local state = maskedPopupState[dialog]
        if state and (not which or state.which == which) then
            restorePopup(dialog)
            restored = restored + 1
        end
    end)
    return restored
end

local function unmaskAllInteractionPopups()
    local restored = unmaskVisiblePopup(nil)
    if unmaskGuildInviteFrame then
        restored = restored + (unmaskGuildInviteFrame() or 0)
    end
    return restored
end

releaseProtectedPopupSoundGuards = function(which, reason)
    local released = 0
    forEachStaticPopup(function(dialog)
        local state = protectedPopupSoundGuardDialogs[dialog]
        if state and (not which or state.which == which) then
            protectedPopupSoundGuardDialogs[dialog] = nil
            if releaseProtectedPopupSoundGuard(state.token, state.which, reason) then
                released = released + 1
            end
        end
    end)
    return released
end

local function hidePopupDialogSilently(dialog, which, reason)
    if not dialog or not dialog.IsShown or not dialog:IsShown() then return false end
    if dialog.which ~= which then return false end

    maskPopupDialog(dialog, which)

    if not protectedPopupSoundGuardDialogs[dialog] then
        protectedPopupSoundGuardDialogs[dialog] = {
            token = acquireProtectedPopupSoundGuard(which, reason or "silent_hide"),
            which = which,
        }
    end

    local oldInviteAccepted = dialog.inviteAccepted
    if which == "PARTY_INVITE" then
        -- Retail PARTY_INVITE OnHide calls DeclineGroup() when inviteAccepted is
        -- nil. Sanctuary already declined blocked invites, so mark this concrete
        -- dialog instance only for the silent close. Do not use StaticPopup_Hide.
        dialog.inviteAccepted = true
    end

    local ok, err = pcall(function()
        dialog:Hide()
    end)

    if which == "PARTY_INVITE" then
        dialog.inviteAccepted = oldInviteAccepted
    end

    debugLog("POPUP", {
        which = which,
        action = ok and "HIDE_SILENT" or "HIDE_ERROR",
        reason = reason or "unknown",
        error = ok and "none" or tostring(err),
    })
    return ok and true or false
end

local function hideVisiblePopupSilently(which, reason)
    local hidden = 0
    forEachStaticPopup(function(dialog)
        if hidePopupDialogSilently(dialog, which, reason) then
            hidden = hidden + 1
        end
    end)
    return hidden
end

local function scheduleVisiblePopupSilentHide(which, reason)
    C_Timer.After(0, function()
        local hidden = hideVisiblePopupSilently(which, reason)
        debugLog("POPUP", {
            which = which,
            action = "HIDE_SILENT_DEFERRED",
            reason = reason or "unknown",
            hidden = hidden,
        })
    end)
end

local function clearPendingPopupDecision(which)
    pendingPopupDecisions[which] = nil
end

local function applyPopupDecision(which, shouldBlock)
    if shouldBlock then
        return maskVisiblePopup(which)
    end
    return unmaskVisiblePopup(which)
end

local function synchronizePopupDecision(which, shouldBlock, name, reason)
    popupDecisionSerial = popupDecisionSerial + 1
    local decision = {
        serial = popupDecisionSerial,
        at = GetTime(),
        shouldBlock = shouldBlock and true or false,
        name = name,
        reason = reason,
    }
    pendingPopupDecisions[which] = decision

    -- If Blizzard already showed the popup, resolve it now. If Sanctuary ran
    -- first, the StaticPopup_Show post-hook below consumes this decision later
    -- in the same event dispatch.
    local visible = countVisiblePopup(which)
    local affected = 0
    if visible > 0 then
        affected = applyPopupDecision(which, decision.shouldBlock) or 0
    end
    debugLog("POPUP_DECISION", addRuntimeContext({
        decisionId = decision.serial,
        which = which,
        name = name or "nil",
        normalized = name and (normalizeName(name) or "nil") or "nil",
        shouldBlock = decision.shouldBlock,
        reason = reason or "nil",
        visible = visible,
        affected = affected,
        order = visible > 0 and "popup_first" or "event_first",
    }))

    C_Timer.After(0, function()
        if pendingPopupDecisions[which] == decision then
            pendingPopupDecisions[which] = nil
        end
    end)

    return decision.serial
end

local function consumePendingPopupDecision(which)
    local decision = pendingPopupDecisions[which]
    if not decision then return nil end
    pendingPopupDecisions[which] = nil
    if (GetTime() - decision.at) > POPUP_DECISION_MAX_AGE then
        return nil
    end
    return decision
end

local function isPopupProtectionActive(which)
    if not isEnabled() then return false end
    if which == "PARTY_INVITE" then
        return getEffective("filters.groupInvite") == true
    elseif which == "DUEL_REQUESTED" then
        return getEffective("filters.duel") == true
    end
    return false
end

local function isGuildInviteFrameProtectionActive()
    return isEnabled() and getEffective("filters.guildInvite") == true
end

local guildInviteFrameHooked = false
local guildInviteFrameMaskedState = nil
local guildInviteFrameLastMaskSerial = 0
local guildInviteFrameLastHideSerial = 0

local function getGuildInviteFrame()
    return _G and _G.GuildInviteFrame or nil
end

local function isGuildInviteFrameShown(frame)
    frame = frame or getGuildInviteFrame()
    return frame and frame.IsShown and frame:IsShown() or false
end

local function restoreGuildInviteFrame(frame)
    frame = frame or getGuildInviteFrame()
    if not frame or not guildInviteFrameMaskedState then return 0 end

    local state = guildInviteFrameMaskedState
    guildInviteFrameMaskedState = nil
    if frame.SetAlpha then
        frame:SetAlpha(state.alpha or 1)
    end
    return 1
end

local function maskGuildInviteFrame(frame)
    frame = frame or getGuildInviteFrame()
    if not isGuildInviteFrameShown(frame) then return false end

    if not guildInviteFrameMaskedState then
        guildInviteFrameMaskedState = {
            alpha = frame.GetAlpha and frame:GetAlpha() or 1,
        }
    end
    if frame.SetAlpha then
        frame:SetAlpha(0)
    end
    guildInviteFrameLastMaskSerial = guildInviteFrameLastMaskSerial + 1
    return true
end

local function acquireGuildInviteFrameSoundGuard(reason)
    if guildInviteFrameSoundGuardToken then
        return guildInviteFrameSoundGuardToken
    end
    guildInviteFrameSoundGuardToken = acquireProtectedPopupSoundGuard(GUILD_INVITE_FRAME_KEY, reason)
    return guildInviteFrameSoundGuardToken
end

releaseGuildInviteFrameSoundGuard = function(reason)
    local token = guildInviteFrameSoundGuardToken
    if not token then return false end
    guildInviteFrameSoundGuardToken = nil
    return releaseProtectedPopupSoundGuard(token, GUILD_INVITE_FRAME_KEY, reason)
end

-- Pending state of a silent hide: the accepted flag to put back once Blizzard
-- has actually run OnHide. Restoring it earlier would let Blizzard's OnHide see
-- accepted=nil and decline a second time.
local guildInviteFrameSilentHideState = nil

local function finishGuildInviteFrameSilentHide(reason)
    if guildInviteFrameSilentHideState then
        local state = guildInviteFrameSilentHideState
        guildInviteFrameSilentHideState = nil
        local frame = getGuildInviteFrame()
        if frame and frame == state.frame then
            frame.accepted = state.accepted
        end
    end
    return releaseGuildInviteFrameSoundGuard(reason)
end

local function hideGuildInviteFrameSilently(reason)
    local frame = getGuildInviteFrame()
    if not frame or not frame.Hide then
        return false, "frame_missing"
    end
    if frame.IsShown and not frame:IsShown() then
        return false, "frame_not_shown"
    end

    maskGuildInviteFrame(frame)
    local token = acquireGuildInviteFrameSoundGuard(reason or "guild_invite_hide")
    local oldAccepted = frame.accepted
    -- Confirmed Retail behavior: GuildInviteFrame:OnHide calls DeclineGuild()
    -- when accepted is nil, then plays the generic close sound. Blocked invites
    -- are already declined explicitly, so mark accepted only for this silent
    -- close to avoid a duplicate decline and mute the close sound guard.
    guildInviteFrameSilentHideState = { frame = frame, accepted = oldAccepted }
    frame.accepted = true
    local ok, err = pcall(function()
        frame:Hide()
    end)

    if not ok then
        finishGuildInviteFrameSilentHide("guild_invite_hide_error")
        debugLog("GUILD_INVITE_FRAME", {
            action = "HIDE_ERROR",
            reason = reason or "unknown",
            error = tostring(err),
        })
        return false, tostring(err)
    end

    -- Confirmed on the 2026-08-20 diagnostic session: when Hide() is called from
    -- inside the frame's own OnShow, Retail defers the OnHide dispatch until the
    -- show handlers have unwound. Releasing the guard here would unmute before
    -- Blizzard plays SOUNDKIT.IG_MAINMENU_CLOSE, which is the audible leak the
    -- maintainer heard. The guard is now held until OnHide really runs; the
    -- next-frame timer is only a bound so the mute can never stay on, and a
    -- timer can never fire before the deferred OnHide of the current dispatch.
    local deferred = guildInviteFrameSoundGuardToken == token
    if deferred then
        C_Timer.After(0, function()
            if guildInviteFrameSoundGuardToken == token then
                finishGuildInviteFrameSilentHide("guild_invite_hide_timeout")
            end
        end)
    end

    guildInviteFrameLastHideSerial = guildInviteFrameLastHideSerial + 1
    debugLog("GUILD_INVITE_FRAME", {
        action = "HIDE_SILENT",
        reason = reason or "unknown",
        acceptedWas = oldAccepted and true or false,
        soundGuardActive = guildInviteFrameSoundGuardToken and true or false,
        onHideOrder = deferred and "deferred" or "synchronous",
    })
    return true
end

local function applyGuildInviteFrameDecision(shouldBlock, reason)
    if shouldBlock then
        local masked = maskGuildInviteFrame() and 1 or 0
        local hidden = hideGuildInviteFrameSilently(reason or "decision_block")
        return masked, hidden and true or false
    end
    return unmaskGuildInviteFrame and unmaskGuildInviteFrame() or 0, false
end

local function synchronizeGuildInviteFrameDecision(shouldBlock, inviter, reason)
    popupDecisionSerial = popupDecisionSerial + 1
    local decision = {
        serial = popupDecisionSerial,
        at = GetTime(),
        shouldBlock = shouldBlock and true or false,
        name = inviter,
        reason = reason,
    }
    pendingPopupDecisions[GUILD_INVITE_FRAME_KEY] = decision

    local visible = isGuildInviteFrameShown() and 1 or 0
    local affected = 0
    local hidden = false
    if visible > 0 then
        affected, hidden = applyGuildInviteFrameDecision(decision.shouldBlock, "decision_block")
    end

    debugLog("POPUP_DECISION", {
        decisionId = decision.serial,
        which = GUILD_INVITE_FRAME_KEY,
        frame = "GuildInviteFrame",
        name = inviter or "nil",
        normalized = inviter and (normalizeName(inviter) or "nil") or "nil",
        shouldBlock = decision.shouldBlock,
        reason = reason or "nil",
        visible = visible,
        affected = affected or 0,
        hidden = hidden and true or false,
        order = visible > 0 and "popup_first" or "event_first",
    })

    C_Timer.After(0, function()
        if pendingPopupDecisions[GUILD_INVITE_FRAME_KEY] == decision then
            pendingPopupDecisions[GUILD_INVITE_FRAME_KEY] = nil
        end
    end)

    return decision.serial
end

local function installGuildInviteFrameGuard()
    local frame = getGuildInviteFrame()
    if not frame or guildInviteFrameHooked or not frame.HookScript then
        return frame
    end

    guildInviteFrameHooked = true
    frame:HookScript("OnShow", function(self)
        if not isGuildInviteFrameProtectionActive() then
            clearPendingGuildInviteFrameDecision()
            restoreGuildInviteFrame(self)
            return
        end

        local decision = consumePendingPopupDecision(GUILD_INVITE_FRAME_KEY)
        local action
        local affected = 0
        local hidden = false
        if decision then
            if decision.shouldBlock then
                affected = maskGuildInviteFrame(self) and 1 or 0
                hidden = hideGuildInviteFrameSilently("pending_block")
                action = "HIDE_DECIDED_BLOCK"
            else
                affected = restoreGuildInviteFrame(self)
                action = "SHOW_DECIDED_ALLOW"
            end
        else
            affected = maskGuildInviteFrame(self) and 1 or 0
            action = "MASK_AWAITING_EVENT"
        end

        debugLog("GUILD_INVITE_FRAME", {
            action = action,
            affected = affected or 0,
            hidden = hidden and true or false,
            pendingName = decision and decision.name or "nil",
            pendingReason = decision and decision.reason or "nil",
            shown = isGuildInviteFrameShown(self) and true or false,
            alpha = self.GetAlpha and tostring(self:GetAlpha()) or "nil",
        })
    end)
    frame:HookScript("OnHide", function(self)
        restoreGuildInviteFrame(self)
        -- Runs after Blizzard's own OnHide script, so the close sound has been
        -- played (and muted) and the accepted flag has been read by then.
        finishGuildInviteFrameSilentHide("guild_invite_frame_hide")
    end)
    return frame
end

clearPendingGuildInviteFrameDecision = function()
    clearPendingPopupDecision(GUILD_INVITE_FRAME_KEY)
end

unmaskGuildInviteFrame = function()
    return restoreGuildInviteFrame()
end

ns.maskVisiblePopup = maskVisiblePopup
ns.unmaskVisiblePopup = unmaskVisiblePopup
ns.unmaskAllInteractionPopups = unmaskAllInteractionPopups
ns.clearPendingPopupDecision = clearPendingPopupDecision
ns.clearPendingGuildInviteFrameDecision = clearPendingGuildInviteFrameDecision
ns.unmaskGuildInviteFrame = unmaskGuildInviteFrame

-- ============================================================================
-- SECTION H: Event Handlers (side effects happen HERE, not in filters)
-- ============================================================================

-- PARTY_INVITE_REQUEST: classify the inviter, synchronize with the secure
-- popup post-hook, then use Blizzard's native decline API when blocked.
function handlers.PARTY_INVITE_REQUEST(name, isTank, isHealer, isDamage,
    isNativeRealm, allowMultipleRoles, inviterGUID, questSessionActive)
    if not isEnabled() or not getEffective("filters.groupInvite") then
        clearPendingPopupDecision("PARTY_INVITE")
        unmaskVisiblePopup("PARTY_INVITE")
        refreshInviteSoundMuteState()
        return
    end

    local shouldBlock, reason, keyword = getCharacterDecision(name)
    local decisionId = synchronizePopupDecision("PARTY_INVITE", shouldBlock, name, reason)
    local replayedSound = false
    local releasedSoundGuards = 0
    if not shouldBlock then
        releasedSoundGuards = releaseProtectedPopupSoundGuards("PARTY_INVITE", "allowed_invite")
        if releasedSoundGuards > 0 then
            replayedSound = playAllowedProtectedPopupSounds("PARTY_INVITE", "allowed_invite_after_guard")
        end
    end

    debugLog("INVITE", addRuntimeContext({
        decisionId = decisionId or "nil",
        name = name,
        normalized = normalizeName(name),
        guid = inviterGUID or "nil",
        isWL = reason == "whitelist",
        keyword = keyword or "none",
        action = shouldBlock and (reason == "keyword" and "BLOCK_KEYWORD" or "BLOCK_NOT_WHITELISTED") or "ALLOW",
        filterEnabled = getEffective("filters.groupInvite") == true,
        popupProtectionActive = isPopupProtectionActive("PARTY_INVITE"),
        soundGuardActive = isStaticPopupSoundSuppressed("PARTY_INVITE"),
        replayedSound = replayedSound and true or false,
        releasedSoundGuards = releasedSoundGuards,
        popupVisible = countVisiblePopup("PARTY_INVITE"),
        wlCache = ns.getWhitelistCacheSize(),
    }))

    if not shouldBlock then return end

    -- Keep the dialog invisible and use only Blizzard's native decline path.
    local declineOk, declineErr = pcall(DeclineGroup)
    debugLog("INVITE_API", {
        decisionId = decisionId or "nil",
        api = "DeclineGroup",
        ok = declineOk and true or false,
        error = declineOk and "none" or tostring(declineErr),
    })
    if countVisiblePopup("PARTY_INVITE") > 0 then
        scheduleVisiblePopupSilentHide("PARTY_INVITE", "blocked_invite_declined")
    end
    logBlock("groupInvite", name, nil, inviterGUID, keyword)
end

-- DUEL_REQUESTED follows the same event-order-safe popup path.
function handlers.DUEL_REQUESTED(playerName)
    if not isEnabled() or not getEffective("filters.duel") then
        clearPendingPopupDecision("DUEL_REQUESTED")
        unmaskVisiblePopup("DUEL_REQUESTED")
        releaseProtectedPopupSoundGuards("DUEL_REQUESTED", "filter_disabled_event")
        return
    end

    local shouldBlock, reason, keyword = getCharacterDecision(playerName)
    synchronizePopupDecision("DUEL_REQUESTED", shouldBlock, playerName, reason)
    local replayedSound = false
    if not shouldBlock then
        local releasedGuards = releaseProtectedPopupSoundGuards("DUEL_REQUESTED", "allowed_duel")
        if releasedGuards > 0 then
            replayedSound = playAllowedProtectedPopupSounds("DUEL_REQUESTED", "allowed_duel_after_guard")
        end
    end
    debugLog("DUEL", {
        name = playerName,
        normalized = normalizeName(playerName),
        reason = reason or "nil",
        keyword = keyword or "none",
        filterEnabled = getEffective("filters.duel") == true,
        replayedSound = replayedSound and true or false,
        action = shouldBlock and (reason == "keyword" and "BLOCK_KEYWORD" or "BLOCK_NOT_WHITELISTED") or "ALLOW",
    })

    if not shouldBlock then return end

    local cancelOk, cancelErr = pcall(CancelDuel)
    debugLog("DUEL_API", {
        api = "CancelDuel",
        ok = cancelOk and true or false,
        error = cancelOk and "none" or tostring(cancelErr),
    })
    if countVisiblePopup("DUEL_REQUESTED") > 0 then
        scheduleVisiblePopupSilentHide("DUEL_REQUESTED", "blocked_duel_cancelled")
    end
    logBlock("duel", playerName, nil, nil, keyword)
end

function handlers.GUILD_INVITE_REQUEST(inviter, guildName)
    installGuildInviteFrameGuard()

    if not isEnabled() or not getEffective("filters.guildInvite") then
        clearPendingGuildInviteFrameDecision()
        unmaskGuildInviteFrame()
        releaseGuildInviteFrameSoundGuard("filter_disabled_event")
        return
    end

    local shouldBlock, reason, keyword = getCharacterDecision(inviter)
    synchronizeGuildInviteFrameDecision(shouldBlock, inviter, reason)
    debugLog("GUILD_INVITE", {
        name = inviter,
        normalized = normalizeName(inviter),
        guild = guildName or "nil",
        reason = reason or "nil",
        keyword = keyword or "none",
        filterEnabled = getEffective("filters.guildInvite") == true,
        frameShown = isGuildInviteFrameShown() and true or false,
        frameAlpha = (getGuildInviteFrame() and getGuildInviteFrame().GetAlpha) and tostring(getGuildInviteFrame():GetAlpha()) or "nil",
        soundGuardActive = guildInviteFrameSoundGuardToken and true or false,
        action = shouldBlock and (reason == "keyword" and "BLOCK_KEYWORD" or "BLOCK_NOT_WHITELISTED") or "ALLOW",
    })

    if not shouldBlock then return end

    local declineOk, declineErr = pcall(DeclineGuild)
    debugLog("GUILD_INVITE_API", {
        api = "DeclineGuild",
        ok = declineOk and true or false,
        error = declineOk and "none" or tostring(declineErr),
    })
    logBlock("guildInvite", inviter, guildName, nil, keyword)
end

-- TRADE_SHOW: auto-close + log (P1)
function handlers.TRADE_SHOW()
    if not isEnabled() then return end
    if not getEffective("filters.trade") then return end

    -- Trade partner detection is limited by the WoW API. Prefer the unit token,
    -- then fall back to the recipient label.
    local tradeName = UnitName("NPC")
        or (TradeFrameRecipientNameText and TradeFrameRecipientNameText:GetText())
        or nil
    if not tradeName or tradeName == "" then
        debugLog("TRADE", { action = "NO_PARTNER_NAME" })
        return
    end

    local shouldBlock, reason, keyword = getCharacterDecision(tradeName)
    debugLog("TRADE", {
        name = tradeName,
        normalized = normalizeName(tradeName),
        reason = reason or "nil",
        keyword = keyword or "none",
        filterEnabled = getEffective("filters.trade") == true,
        action = shouldBlock and (reason == "keyword" and "BLOCK_KEYWORD" or "BLOCK_NOT_WHITELISTED") or "ALLOW",
    })

    if not shouldBlock then return end

    local closeOk, closeErr = pcall(CloseTrade)
    debugLog("TRADE_API", {
        api = "CloseTrade",
        ok = closeOk and true or false,
        error = closeOk and "none" or tostring(closeErr),
    })
    logBlock("trade", tradeName, nil, nil, keyword)
end

-- Whitelist refresh events. WoW fires roster events in bursts (and sometimes
-- continuously); keep diagnostics useful by logging only changes or a 60s
-- heartbeat per event type.
local lastSocialDebugByEvent = {}

local function debugLogSocial(eventName)
    if not SanctuaryDB or not SanctuaryDB.debugEnabled then return end

    local gm = 0; pcall(function() gm = GetNumGuildMembers() end)
    local bn = 0; pcall(function() bn = BNGetNumFriends() end)
    local cf = 0; pcall(function() cf = C_FriendList.GetNumFriends() end)
    local bnetCN = countBNetWithCharName()
    local key = gm .. ":" .. bn .. ":" .. cf .. ":" .. bnetCN
    local now = GetTime()
    local previous = lastSocialDebugByEvent[eventName]
    if previous and previous.key == key and (now - previous.time) < 60 then
        return
    end

    lastSocialDebugByEvent[eventName] = { key = key, time = now }
    debugLog("SOCIAL", {
        event = eventName,
        guild = gm,
        bnet = bn,
        friends = cf,
        bnetCN = bnetCN,
    })
end

function handlers.GUILD_ROSTER_UPDATE()
    invalidateWhitelist()
    debugLogSocial("GUILD_ROSTER_UPDATE")
end

function handlers.PLAYER_GUILD_UPDATE()
    invalidateWhitelist()
    debugLogSocial("PLAYER_GUILD_UPDATE")
    pcall(function()
        if C_GuildInfo and C_GuildInfo.GuildRoster then
            C_GuildInfo.GuildRoster()
        end
    end)
end

function handlers.FRIENDLIST_UPDATE()
    invalidateWhitelist()
    debugLogSocial("FRIENDLIST_UPDATE")
end

function handlers.BN_FRIEND_INFO_CHANGED()
    invalidateWhitelist()
    debugLogSocial("BN_FRIEND_INFO_CHANGED")
end

function handlers.BN_FRIEND_LIST_SIZE_CHANGED()
    invalidateWhitelist()
    debugLogSocial("BN_FRIEND_LIST_SIZE_CHANGED")
end

local function refreshGroupTracker()
    invalidateWhitelist()
    if not SanctuaryCharDB or not SanctuaryCharDB.groupTracker then return end

    if not isEnabled() or not getEffective("filters.autoTrust") then
        wipe(SanctuaryCharDB.groupTracker)
        return
    end

    local currentMembers = {}
    if IsInGroup() then
        local numMembers = GetNumGroupMembers() or 0
        local isRaid = IsInRaid()
        for i = 1, numMembers do
            local unit = isRaid and ("raid" .. i) or ("party" .. i)
            local isPlayer = UnitIsUnit and UnitIsUnit(unit, "player")
            local name, realm = UnitName(unit)
            if name and not isPlayer and name ~= UNKNOWNOBJECT then
                if realm and realm ~= "" then
                    name = name .. "-" .. realm
                end
                local normalized = normalizeName(name)
                if normalized then
                    currentMembers[normalized] = true
                    if not SanctuaryCharDB.groupTracker[normalized] then
                        SanctuaryCharDB.groupTracker[normalized] = GetTime()
                    end
                end
            end
        end
    end

    for trackedName in pairs(SanctuaryCharDB.groupTracker) do
        if not currentMembers[trackedName] then
            SanctuaryCharDB.groupTracker[trackedName] = nil
        end
    end
end

function handlers.GROUP_ROSTER_UPDATE()
    refreshGroupTracker()
end

ns.refreshGroupTracker = refreshGroupTracker

-- CHAT_MSG_SYSTEM is also emitted when an invitation cannot create a popup
-- (for example while already grouped/in a dungeon). This handler records that
-- path once; the chat-frame filter above performs the actual suppression.
function handlers.CHAT_MSG_SYSTEM(msg, ...)
    if not isEnabled() or not getEffective("filters.groupInvite") then return end

    local inviterName, patternIndex, patternKind = extractInviterFromSystemMessage(msg)
    if not inviterName then
        if SanctuaryDB and SanctuaryDB.debugEnabled and isRestrictedValue(msg) then
            -- Confirmed from Retail source: the message-event filter registry
            -- skips addon callbacks when the payload is a secret value, so
            -- strict mode only makes this line *eligible* for suppression here.
            -- SUPPRESS_* stays reserved for a suppression actually applied.
            local strictEligible = shouldSuppressSecretGroupInviteSystemMessage(msg)
            debugLog("SYSTEM_INVITE", addRuntimeContext({
                msg = SECRET_VALUE_PLACEHOLDER,
                result = strictEligible and "STRICT_POLICY_ELIGIBLE" or "SECRET_VALUE",
                filterEnabled = getEffective("filters.groupInvite") == true,
                strictGroupInviteSystemMessages = getEffective("filters.strictGroupInviteSystemMessages") == true,
                soundGuardActive = isStaticPopupSoundSuppressed("PARTY_INVITE"),
                argCount = select("#", ...),
            }))
        elseif SanctuaryDB and SanctuaryDB.debugEnabled and type(msg) == "string" then
            local lowerMsg = msg:lower()
            if lowerMsg:find("invit", 1, true) or lowerMsg:find("group", 1, true) then
                debugLog("SYSTEM_INVITE", addRuntimeContext({
                    msg = safeText(msg, 300, "nil"),
                    result = "NO_MATCH",
                    filterEnabled = getEffective("filters.groupInvite") == true,
                    soundGuardActive = isStaticPopupSoundSuppressed("PARTY_INVITE"),
                    argCount = select("#", ...),
                }))
            end
        end
        return
    end

    local shouldBlock, reason, keyword = getCharacterDecision(inviterName)
    debugLog("SYSTEM_INVITE", addRuntimeContext({
        msg = safeText(msg, 300, "nil"),
        name = inviterName,
        pattern = patternIndex or "?",
        isWL = reason == "whitelist",
        keyword = keyword or "none",
        result = shouldBlock and (reason == "keyword" and "SUPPRESS_KEYWORD" or "SUPPRESS_NOT_WHITELISTED") or "PASS_WHITELISTED",
        filterEnabled = getEffective("filters.groupInvite") == true,
        soundGuardActive = isStaticPopupSoundSuppressed("PARTY_INVITE"),
        patternKind = patternKind or "unknown",
        argCount = select("#", ...),
    }))

    -- Normal invite system messages are popup-backed and are followed by
    -- PARTY_INVITE_REQUEST, which carries the GUID. Only the no-popup
    -- already-grouped path block-logs here, otherwise the 1s logBlock dedupe can
    -- discard the later richer event log.
    if shouldBlock and (patternKind == "already_group" or (patternKind == "unknown" and IsInGroup())) then
        logBlock("groupInvite", inviterName, msg, nil, keyword)
    end
end

-- Whisper event handler for logging + exact-tab closing
function handlers.CHAT_MSG_WHISPER(msg, sender, ...)
    if not isEnabled() then return end

    local shouldBlock, reason, keyword = getCharacterDecision(sender)
    local filterEnabled = getEffective("filters.whisper") == true
    if reason ~= "keyword" and not filterEnabled then
        debugLogChatDecision("whisper", sender, msg, "PASS_FILTER_DISABLED", reason, keyword, {
            filterEnabled = false,
        })
        return
    end
    debugLogChatDecision("whisper", sender, msg,
        shouldBlock and (reason == "keyword" and "BLOCK_KEYWORD" or "BLOCK_NOT_WHITELISTED") or "ALLOW",
        reason, keyword, {
            filterEnabled = filterEnabled,
        })
    if not shouldBlock then return end

    logBlock("whisper", sender, msg, nil, keyword)
    closeBlockedWhisperTabs(sender, false)
end

function handlers.CHAT_MSG_BN_WHISPER(msg, sender, ...)
    if not isEnabled() then return end

    local bnetSender = resolveBNetWhisperSender(sender, ...)
    local decisionName = bnetSender.accountName or sender
    local keywordMatch, keyword = matchesKeyword(decisionName)
    local filterEnabled = getEffective("filters.whisper") == true
    if not keywordMatch and not filterEnabled then
        debugLogChatDecision("bn_whisper", decisionName, msg, "PASS_FILTER_DISABLED", "filter_disabled", keyword, {
            filterEnabled = false,
            rawSender = bnetSender.rawSenderText,
            bnetSenderID = bnetSender.bnSenderIDState,
            bnetResolvedByID = bnetSender.resolvedByID,
        })
        return
    end

    local action = "BLOCK_NOT_WHITELISTED"
    local reason = "not_whitelisted"
    local bnetWhitelisted = isBNetWhitelisted(decisionName)
    local bnetGroup = false
    if keywordMatch then
        action = "BLOCK_KEYWORD"
        reason = "keyword"
    elseif bnetWhitelisted then
        action = "ALLOW"
        reason = "bnet_whitelist"
    else
        bnetGroup = isBNetSenderInGroup(decisionName) and true or false
        if bnetGroup then
            action = "ALLOW"
            reason = "bnet_group"
        end
    end

    debugLogChatDecision("bn_whisper", decisionName, msg, action, reason, keyword, {
        filterEnabled = filterEnabled,
        bnetWhitelisted = bnetWhitelisted and true or false,
        inGroup = bnetGroup,
        bnetCache = ns.getBNetWhitelistCacheSize and ns.getBNetWhitelistCacheSize() or "?",
        rawSender = bnetSender.rawSenderText,
        bnetSenderID = bnetSender.bnSenderIDState,
        bnetResolvedByID = bnetSender.resolvedByID,
    })
    if action == "ALLOW" then return end

    logBlock("whisper", decisionName, msg, nil, keyword)
    closeBlockedWhisperTabs(sender, true)
end

function handlers.CHAT_MSG_SAY(msg, sender, ...)
    if not isEnabled() or isSelf(sender) then return end
    local shouldBlock, reason, keyword = getCharacterDecision(sender)
    local filterEnabled = getEffective("filters.say") == true
    if reason ~= "keyword" and not filterEnabled then
        debugLogChatDecision("say", sender, msg, "PASS_FILTER_DISABLED", reason, keyword, {
            filterEnabled = false,
        })
        return
    end
    debugLogChatDecision("say", sender, msg,
        shouldBlock and (reason == "keyword" and "BLOCK_KEYWORD" or "BLOCK_NOT_WHITELISTED") or "ALLOW",
        reason, keyword, {
            filterEnabled = filterEnabled,
        })
    if shouldBlock then logBlock("say", sender, msg, nil, keyword) end
end

function handlers.CHAT_MSG_YELL(msg, sender, ...)
    if not isEnabled() or isSelf(sender) then return end
    local shouldBlock, reason, keyword = getCharacterDecision(sender)
    local filterEnabled = getEffective("filters.yell") == true
    if reason ~= "keyword" and not filterEnabled then
        debugLogChatDecision("yell", sender, msg, "PASS_FILTER_DISABLED", reason, keyword, {
            filterEnabled = false,
        })
        return
    end
    debugLogChatDecision("yell", sender, msg,
        shouldBlock and (reason == "keyword" and "BLOCK_KEYWORD" or "BLOCK_NOT_WHITELISTED") or "ALLOW",
        reason, keyword, {
            filterEnabled = filterEnabled,
        })
    if shouldBlock then logBlock("yell", sender, msg, nil, keyword) end
end

function handlers.CHAT_MSG_EMOTE(msg, sender, ...)
    if not isEnabled() or isSelf(sender) then return end
    local shouldBlock, reason, keyword = getCharacterDecision(sender)
    local filterEnabled = getEffective("filters.emote") == true
    if reason ~= "keyword" and not filterEnabled then
        debugLogChatDecision("emote", sender, msg, "PASS_FILTER_DISABLED", reason, keyword, {
            filterEnabled = false,
        })
        return
    end
    debugLogChatDecision("emote", sender, msg,
        shouldBlock and (reason == "keyword" and "BLOCK_KEYWORD" or "BLOCK_NOT_WHITELISTED") or "ALLOW",
        reason, keyword, {
            filterEnabled = filterEnabled,
        })
    if shouldBlock then logBlock("emote", sender, msg, nil, keyword) end
end

handlers.CHAT_MSG_TEXT_EMOTE = handlers.CHAT_MSG_EMOTE

function handlers.CHAT_MSG_CHANNEL(msg, sender, ...)
    if not isEnabled() or isSelf(sender) then return end
    local mode = getEffective("filters.channelMode") or "none"
    if mode == "none" then
        debugLogChatDecision("channel", sender, msg, "PASS_MODE_NONE", "channel_none", nil, {
            channelMode = mode,
        })
        return
    end

    local shouldBlock, reason, keyword = getCharacterDecision(sender)
    if reason == "keyword" then
        debugLogChatDecision("channel", sender, msg, "BLOCK_KEYWORD", reason, keyword, {
            channelMode = mode,
        })
        logBlock("channel", sender, msg, nil, keyword)
    elseif mode == "all" and shouldBlock then
        debugLogChatDecision("channel", sender, msg, "BLOCK_NOT_WHITELISTED", reason, nil, {
            channelMode = mode,
        })
        logBlock("channel", sender, msg, nil)
    else
        debugLogChatDecision("channel", sender, msg, "ALLOW", reason, keyword, {
            channelMode = mode,
        })
    end
end

-- ============================================================================
-- SECTION I: Slash Command Handler
-- ============================================================================

local function trimCommandText(text)
    if type(text) ~= "string" then return "" end
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function buildInviteSystemMessage(name, alreadyInGroup)
    local template
    if alreadyInGroup then
        template = ERR_INVITED_ALREADY_IN_GROUP_SS or ERR_INVITED_ALREADY_IN_GROUP_S
    else
        template = ERR_INVITED_TO_GROUP_SS or ERR_INVITED_TO_GROUP_S
    end

    if type(template) == "string" and template ~= "" then
        local ok, message = pcall(string.format, template, name, name)
        if ok and type(message) == "string" then
            return message
        end
    end

    if alreadyInGroup then
        return "[" .. name .. "] vous a invite a rejoindre un groupe, mais vous ne pouviez pas accepter car vous etes deja dans un groupe."
    end
    return "[" .. name .. "] vous a invite a rejoindre un groupe."
end

local function simulateInvite(name)
    local target = trimCommandText(name)
    if target == "" then
        target = "SanctuaryTest"
    end

    local shouldBlock, reason, keyword = getCharacterDecision(target)
    local normalMessage = buildInviteSystemMessage(target, false)
    local alreadyGroupMessage = buildInviteSystemMessage(target, true)
    local groupInviteFilterEnabled = isEnabled() and getEffective("filters.groupInvite") == true
    local popupProtectionActive = isPopupProtectionActive("PARTY_INVITE")
    local popupAction = "pass"

    if groupInviteFilterEnabled then
        if shouldBlock then
            popupAction = popupProtectionActive and "mask" or "unprotected"
        else
            popupAction = "show"
        end
    end

    local result = {
        name = target,
        normalized = normalizeName(target),
        shouldBlock = shouldBlock and true or false,
        reason = reason or "unknown",
        keyword = keyword,
        filterEnabled = groupInviteFilterEnabled and true or false,
        popupProtectionActive = popupProtectionActive and true or false,
        popupAction = popupAction,
        systemMessage = normalMessage,
        alreadyGroupMessage = alreadyGroupMessage,
        systemSuppressed = systemMessageFilter(nil, "CHAT_MSG_SYSTEM", normalMessage) and true or false,
        alreadyGroupSuppressed = systemMessageFilter(nil, "CHAT_MSG_SYSTEM", alreadyGroupMessage) and true or false,
        wouldDecline = groupInviteFilterEnabled and shouldBlock and true or false,
        declined = false,
        partyInviteSoundGuardActive = isStaticPopupSoundSuppressed("PARTY_INVITE"),
    }

    debugLog("SIMULATE_INVITE", {
        name = result.name,
        normalized = result.normalized or "nil",
        reason = result.reason,
        keyword = result.keyword or "none",
        action = result.shouldBlock and "BLOCK" or "ALLOW",
        popup = result.popupAction,
        system = result.systemSuppressed and "SUPPRESS" or "PASS",
        alreadyGroup = result.alreadyGroupSuppressed and "SUPPRESS" or "PASS",
        wouldDecline = result.wouldDecline and true or false,
        declined = false,
    })

    return result
end

local function simulateBNetWhisper(sender, sourceLabel, bnSenderID)
    local target = trimCommandText(sender)
    if target == "" then
        target = "SanctuaryBNetTest"
    end

    local rawSender = bnSenderID and "|Ksanctuary|k" or target
    local bnetSender = resolveBNetWhisperSender(rawSender, getBNetWhisperPayloadArgs(rawSender, bnSenderID))
    local decisionName = bnetSender.accountName or (bnSenderID and rawSender) or target
    local keywordMatch, keyword = matchesKeyword(decisionName)
    local filterEnabled = isEnabled() and getEffective("filters.whisper") == true
    local bnetWhitelisted = isBNetWhitelisted(decisionName)
    local inGroup = isBNetSenderInGroup and isBNetSenderInGroup(decisionName) or false
    local filtered = bnetWhisperFilter(nil, "CHAT_MSG_BN_WHISPER", "Sanctuary diagnostic", rawSender,
        getBNetWhisperPayloadArgs(rawSender, bnSenderID)) and true or false
    local reason = "not_whitelisted"

    if keywordMatch then
        reason = "keyword"
    elseif not isEnabled() then
        reason = "addon_disabled"
    elseif not filterEnabled then
        reason = "filter_disabled"
    elseif bnetWhitelisted then
        reason = "bnet_whitelist"
    elseif inGroup then
        reason = "bnet_group"
    end

    local result = {
        kind = "bnet",
        label = sourceLabel or target,
        name = decisionName,
        normalized = normalizeBNetName(decisionName),
        filtered = filtered,
        shouldBlock = filtered,
        reason = reason,
        keyword = keyword,
        filterEnabled = filterEnabled,
        bnetWhitelisted = bnetWhitelisted and true or false,
        inGroup = inGroup and true or false,
        resolvedByID = bnetSender.resolvedByID,
    }

    debugLog("SIMULATE_BNET_WHISPER", {
        source = result.label,
        normalized = result.normalized or "nil",
        action = filtered and "BLOCK" or "ALLOW",
        reason = reason,
        keyword = keyword or "none",
        filterEnabled = filterEnabled,
        bnetWhitelisted = result.bnetWhitelisted,
        inGroup = result.inGroup,
        bnetSenderID = bnetSender.bnSenderIDState,
        bnetResolvedByID = bnetSender.resolvedByID,
    })

    return result
end

local function simulateBNetFriend(indexText)
    local friendIndex = tonumber(trimCommandText(indexText)) or 1
    if friendIndex < 1 then friendIndex = 1 end

    local info = getBNetFriendInfo(friendIndex)
    if not info or not info.accountName or info.accountName == "" then
        local result = {
            kind = "bnet",
            label = "friend #" .. friendIndex,
            friendIndex = friendIndex,
            available = false,
            filtered = true,
            shouldBlock = true,
            reason = "bnet_api_unavailable",
            filterEnabled = isEnabled() and getEffective("filters.whisper") == true,
            bnetWhitelisted = false,
            inGroup = false,
        }
        debugLog("SIMULATE_BNET_WHISPER", {
            source = result.label,
            action = "ERROR",
            reason = result.reason,
            filterEnabled = result.filterEnabled,
        })
        return result
    end

    local result = simulateBNetWhisper(info.accountName, "friend #" .. friendIndex, info.bnetAccountID)
    result.friendIndex = friendIndex
    result.available = true
    return result
end

local function formatSimulationResult(result)
    local action = result.shouldBlock and "BLOCK" or "ALLOW"
    local system = result.systemSuppressed and "blocked" or "visible"
    local alreadyGroup = result.alreadyGroupSuppressed and "blocked" or "visible"
    local wouldDecline = result.wouldDecline and "yes" or "no"
    local soundGuard = result.partyInviteSoundGuardActive and "yes" or "no"
    local reason = result.reason
    if result.keyword then
        reason = reason .. ":" .. result.keyword
    end

    return string.format(
        "Simulation invite: %s -> %s (%s) | popup=%s | chat=%s | already-group=%s | would-decline=%s | API=not-called | sound-guard=%s",
        result.name,
        action,
        reason,
        result.popupAction,
        system,
        alreadyGroup,
        wouldDecline,
        soundGuard
    )
end

local function formatBNetSimulationResult(result)
    if result.available == false then
        return string.format(
            "Simulation bnet whisper: %s -> ERROR (%s) | filter=%s",
            result.label or "friend",
            result.reason or "unknown",
            result.filterEnabled and "on" or "off"
        )
    end

    local action = result.filtered and "BLOCK" or "ALLOW"
    local chat = result.filtered and "blocked" or "visible"
    local reason = result.reason or "unknown"
    if result.keyword then
        reason = reason .. ":" .. result.keyword
    end

    return string.format(
        "Simulation bnet whisper: %s -> %s (%s) | filter=%s | bnet-cache=%s | id=%s | group=%s | chat=%s",
        result.label or result.name or "?",
        action,
        reason,
        result.filterEnabled and "on" or "off",
        result.bnetWhitelisted and "yes" or "no",
        result.resolvedByID and "yes" or "no",
        result.inGroup and "yes" or "no",
        chat
    )
end

local function runChatDiagnostic(kind)
    local normalizedKind = trimCommandText(kind):lower()
    if normalizedKind == "" then normalizedKind = "invite" end
    if normalizedKind ~= "invite" then
        return {
            available = false,
            kind = normalizedKind,
            reason = "unknown_chat_diagnostic",
        }
    end

    local target = "SanctuaryDiagnosticBlocked"
    local message = buildInviteSystemMessage(target, true)
    local inviterName = extractInviterFromSystemMessage(message)
    local shouldBlock, reason = getCharacterDecision(inviterName or target)
    local filterEnabled = isEnabled() and getEffective("filters.groupInvite") == true
    local expectedGuarded = filterEnabled and shouldBlock

    local probe = { message = message }
    local addMessageOk, addMessageErr = false, "missing_default_chat_frame"
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        activeChatOutputProbe = probe
        addMessageOk, addMessageErr = pcall(function()
            DEFAULT_CHAT_FRAME:AddMessage(message)
        end)
        activeChatOutputProbe = nil
    end

    local output = "unavailable"
    if not addMessageOk then
        output = "error"
    elseif probe.suppressed then
        output = "guarded"
    elseif probe.observed then
        output = "visible"
    elseif expectedGuarded then
        output = "unguarded"
    else
        output = "visible"
    end

    local result = {
        available = true,
        kind = "invite",
        filterEnabled = filterEnabled,
        shouldBlock = shouldBlock and true or false,
        reason = reason or "unknown",
        output = output,
        observed = probe.observed and true or false,
        action = probe.action or "none",
        error = addMessageOk and "none" or tostring(addMessageErr),
    }
    debugLog("CHAT_TEST", result)
    return result
end

local function formatChatDiagnosticResult(result)
    if not result.available then
        return string.format("Diagnostic chat %s: ERROR (%s)",
            result.kind or "unknown",
            result.reason or "unknown"
        )
    end
    return string.format(
        "Diagnostic chat invite: output=%s observed=%s filter=%s reason=%s",
        result.output or "unknown",
        result.observed and "yes" or "no",
        result.filterEnabled and "on" or "off",
        result.reason or "unknown"
    )
end

local function runSoundDiagnostic()
    local inviteSound = capturePartyInviteOriginalSound()
    local openSound = (SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPEN) or "igMainMenuOpen"
    local openOk = pcall(PlaySound, openSound)
    local inviteOk = inviteSound and pcall(PlaySound, inviteSound) or false
    debugLog("SOUND_TEST", {
        openSound = tostring(openSound),
        inviteSound = tostring(inviteSound or "nil"),
        openOk = openOk and true or false,
        inviteOk = inviteOk and true or false,
        guardActive = partyInviteSoundGuardDepth > 0,
    })
    return {
        openSound = openSound,
        inviteSound = inviteSound,
        openOk = openOk and true or false,
        inviteOk = inviteOk and true or false,
        guardActive = partyInviteSoundGuardDepth > 0,
    }
end

local function formatSoundDiagnosticResult(result)
    if not result.inviteSound then
        return "Diagnostic sound invite: ERROR (native party invite sound unavailable)"
    end
    return string.format(
        "Diagnostic sound invite: popup-open=%s invite=%s guard=%s",
        result.openOk and "played" or "failed",
        result.inviteOk and tostring(result.inviteSound) or "failed",
        result.guardActive and "active" or "inactive"
    )
end

local POPUP_DIAGNOSTICS = {
    -- The group invitation popup was the one diagnostic with no command: the
    -- checklist reached it through a raw `/run StaticPopup_Show("PARTY_INVITE",
    -- ...)`, which leaves an invisible but clickable Accept button in the middle
    -- of the screen until a `/reload`. Going through the same path as the other
    -- popups hides the dialog as soon as it has been observed, so the dangerous
    -- two-step manipulation is no longer needed to produce that measurement.
    invite = {
        which = "PARTY_INVITE",
        label = "invite",
        text = "SanctuaryDiagnostic",
    },
    duel = {
        which = "DUEL_REQUESTED",
        label = "duel",
        text = "SanctuaryDiagnostic vous provoque en duel.",
    },
    guild = {
        which = GUILD_INVITE_FRAME_KEY,
        label = "guild",
        frame = "GuildInviteFrame",
    },
}

local function collectPopupDialogNames(query)
    local needle = trimCommandText(query):lower()
    local matches = {}
    if type(StaticPopupDialogs) ~= "table" then return matches end

    for key in pairs(StaticPopupDialogs) do
        local text = tostring(key)
        if needle == "" or text:lower():find(needle, 1, true) then
            matches[#matches + 1] = text
        end
    end
    table.sort(matches)
    return matches
end

local function runPopupListDiagnostic(query)
    local normalizedQuery = trimCommandText(query):lower()
    local matches = collectPopupDialogNames(normalizedQuery)
    local preview = {}
    for i = 1, math.min(#matches, 8) do
        preview[#preview + 1] = matches[i]
    end
    local result = {
        query = normalizedQuery ~= "" and normalizedQuery or "all",
        count = #matches,
        preview = table.concat(preview, ", "),
        truncated = #matches > #preview,
    }
    debugLog("POPUP_LIST", result)
    return result
end

local function formatPopupListDiagnosticResult(result)
    if result.count == 0 then
        return string.format("Diagnostic popup list %s: none", result.query)
    end
    return string.format(
        "Diagnostic popup list %s: %s%s",
        result.query,
        result.preview,
        result.truncated and " ..." or ""
    )
end

local function runPopupDiagnostic(kind)
    local normalizedKind = trimCommandText(kind):lower()
    local config = POPUP_DIAGNOSTICS[normalizedKind]
    if not config then
        return {
            available = false,
            kind = normalizedKind ~= "" and normalizedKind or "unknown",
            reason = "unknown_popup_diagnostic",
        }
    end

    if config.frame == "GuildInviteFrame" then
        local frame = installGuildInviteFrameGuard()
        if not frame then
            local result = {
                available = true,
                skipped = true,
                kind = config.label,
                which = config.which,
                frame = config.frame,
                filterEnabled = isGuildInviteFrameProtectionActive() and true or false,
                shown = false,
                masked = false,
                hidden = false,
                specialShow = type(StaticPopupSpecial_Show) == "function",
                reason = "guild_invite_frame_missing",
            }
            debugLog("POPUP_TEST", result)
            return result
        end

        if isGuildInviteFrameShown(frame) then
            local result = {
                available = true,
                skipped = true,
                kind = config.label,
                which = config.which,
                frame = config.frame,
                filterEnabled = isGuildInviteFrameProtectionActive() and true or false,
                shown = true,
                masked = false,
                hidden = false,
                specialShow = type(StaticPopupSpecial_Show) == "function",
                reason = "guild_invite_frame_busy",
            }
            debugLog("POPUP_TEST", result)
            return result
        end

        local protectionActive = isGuildInviteFrameProtectionActive()
        if not protectionActive then
            local result = {
                available = true,
                skipped = true,
                kind = config.label,
                which = config.which,
                frame = config.frame,
                filterEnabled = false,
                shown = false,
                masked = false,
                hidden = false,
                specialShow = type(StaticPopupSpecial_Show) == "function",
                reason = "filter_disabled",
            }
            debugLog("POPUP_TEST", result)
            return result
        end

        local beforeMaskSerial = guildInviteFrameLastMaskSerial
        local beforeHideSerial = guildInviteFrameLastHideSerial
        frame.inviter = "SanctuaryDiagnostic"
        frame.accepted = nil
        frame.elapsed = 0
        synchronizeGuildInviteFrameDecision(true, "SanctuaryDiagnostic", "diagnostic")

        local showOk, showErr
        if type(StaticPopupSpecial_Show) == "function" then
            showOk, showErr = pcall(StaticPopupSpecial_Show, frame)
        elseif frame.Show then
            showOk, showErr = pcall(function()
                frame:Show()
            end)
        else
            showOk, showErr = false, "frame_show_missing"
        end

        -- Read back off the screen, never from the fact that a hide was
        -- attempted: guildInviteFrameLastHideSerial is incremented after a
        -- pcall'd frame:Hide() that merely did not raise, so a Hide that exists
        -- and does nothing reported hidden=yes while the frame was still up at
        -- alpha 0 -- invisible, clickable, and with the way back hidden. Same
        -- defect as the StaticPopup path, on its twin.
        local hidden = not isGuildInviteFrameShown(frame)
        local result = {
            available = true,
            kind = config.label,
            which = config.which,
            frame = config.frame,
            filterEnabled = true,
            shown = showOk and true or false,
            masked = guildInviteFrameLastMaskSerial > beforeMaskSerial,
            hidden = hidden and true or false,
            alpha = frame.GetAlpha and tostring(frame:GetAlpha()) or "nil",
            specialShow = type(StaticPopupSpecial_Show) == "function",
            reason = showOk and "guild_invite_frame_probe" or "guild_invite_frame_show_error",
            error = showOk and "none" or tostring(showErr),
        }
        debugLog("POPUP_TEST", result)
        return result
    end

    if not StaticPopupDialogs or not StaticPopupDialogs[config.which] then
        local result = {
            available = true,
            skipped = true,
            kind = config.label,
            which = config.which,
            filterEnabled = isPopupProtectionActive(config.which) and true or false,
            shown = false,
            masked = false,
            hidden = false,
            reason = "popup_dialog_missing",
        }
        debugLog("POPUP_TEST", result)
        return result
    end

    local protectionActive = isPopupProtectionActive(config.which)
    if not protectionActive then
        local result = {
            available = true,
            skipped = true,
            kind = config.label,
            which = config.which,
            filterEnabled = false,
            shown = false,
            masked = false,
            hidden = false,
            reason = "filter_disabled",
        }
        debugLog("POPUP_TEST", result)
        return result
    end

    -- The guild path already refuses to run over a frame that is already up;
    -- this one did not. StaticPopup_Show reuses the slot of the same `which`,
    -- so probing while a real invitation or duel is pending would close that
    -- request without accepting or declining it, leaving the other player
    -- waiting on a timeout. The checklist warned about it in prose -- which is
    -- exactly the kind of rule this panel exists to take off the operator.
    if countVisiblePopup(config.which) > 0 then
        local result = {
            available = true,
            skipped = true,
            kind = config.label,
            which = config.which,
            filterEnabled = true,
            shown = true,
            masked = false,
            hidden = false,
            reason = "popup_busy",
        }
        debugLog("POPUP_TEST", result)
        return result
    end

    local dialog = StaticPopup_Show(config.which, config.text)
    local shown = dialog and dialog.IsShown and dialog:IsShown() or false
    local alpha = dialog and dialog.GetAlpha and dialog:GetAlpha() or nil
    local masked = alpha == 0

    -- Closed through the silent-hide path, not through a raw dialog:Hide().
    -- Retail's PARTY_INVITE OnHide calls DeclineGroup() when `inviteAccepted`
    -- is nil, so hiding the probe directly could decline an invitation the
    -- server already had pending. hidePopupDialogSilently is the code that
    -- already knows this, and it also mutes the close sound the diagnostic must
    -- not make.
    hideVisiblePopupSilently(config.which, "diagnostic")
    -- Then the screen is read back. Deducing `hidden` from the call having been
    -- made is what made the leftOnScreen guard blind: a Hide that exists but
    -- does nothing reported hidden=yes while an invisible, clickable Accept
    -- button was still under the cursor.
    local hidden = countVisiblePopup(config.which) == 0

    local result = {
        available = true,
        kind = config.label,
        which = config.which,
        filterEnabled = true,
        shown = shown and true or false,
        masked = masked and true or false,
        hidden = hidden and true or false,
        alpha = alpha and tostring(alpha) or "nil",
        reason = "protected_popup_probe",
    }
    debugLog("POPUP_TEST", result)
    return result
end

local function formatPopupDiagnosticResult(result)
    if not result.available then
        return string.format("Diagnostic popup %s: ERROR (%s)",
            result.kind or "unknown", result.reason or "unknown")
    end
    if result.skipped then
        return string.format("Diagnostic popup %s: SKIP (%s)",
            result.kind or "unknown", result.reason or "unknown")
    end
    return string.format(
        "Diagnostic popup %s: shown=%s masked=%s hidden=%s filter=%s",
        result.kind,
        result.shown and "yes" or "no",
        result.masked and "yes" or "no",
        result.hidden and "yes" or "no",
        result.filterEnabled and "on" or "off"
    )
end

local function resolveSimulationTarget(args)
    local text = trimCommandText(args)
    local first, rest = text:match("^(%S+)%s*(.*)$")
    if first and first:lower() == "invite" then
        text = trimCommandText(rest)
    end
    if text == "" then
        text = "SanctuaryTest"
    end
    return text
end

-- ----------------------------------------------------------------------------
-- Diagnostic catalogue (debug panel)
-- ----------------------------------------------------------------------------

-- The list of diagnostics the debug panel turns into buttons. It lives here,
-- next to the diagnostics themselves, rather than in the UI file: a checklist
-- step is exactly one entry of this table, so the list, the labels and the
-- clean-up flags have to be verifiable without a game client. The UI only owns
-- the buttons that render it.
--
-- `run(argText)` returns { text = <line shown to the maintainer>,
-- leftOnScreen = <the diagnostic could not put the screen back> }.
ns.DIAGNOSTIC_CATALOG = {
    {
        id = "sim_invite",
        labelKey = "DIAG_SIM_INVITE",
        command = "/sanc sim <nom>",
        argKey = "DIAG_ARG_NAME",
        argDefault = "SanctuaryTest",
        run = function(argText)
            return { text = formatSimulationResult(simulateInvite(resolveSimulationTarget(argText))) }
        end,
    },
    {
        id = "sim_bnet",
        labelKey = "DIAG_SIM_BNET",
        command = "/sanc sim bnet",
        run = function(argText)
            return { text = formatBNetSimulationResult(simulateBNetWhisper(argText or "")) }
        end,
    },
    {
        id = "sim_bnetfriend",
        labelKey = "DIAG_SIM_BNETFRIEND",
        command = "/sanc sim bnetfriend <n>",
        argKey = "DIAG_ARG_INDEX",
        argDefault = "1",
        -- Writes a real Battle.net account name into the debug log. The panel
        -- says so before the click rather than in a note read afterwards.
        sensitive = true,
        run = function(argText)
            return { text = formatBNetSimulationResult(simulateBNetFriend(argText or "1")) }
        end,
    },
    {
        id = "diag_chat",
        labelKey = "DIAG_CHAT_INVITE",
        command = "/sanc diag chat invite",
        run = function()
            return { text = formatChatDiagnosticResult(runChatDiagnostic("invite")) }
        end,
    },
    {
        id = "diag_sound",
        labelKey = "DIAG_SOUND_INVITE",
        command = "/sanc diag sound invite",
        tipKey = "DIAG_TIP_SOUND",
        run = function()
            return { text = formatSoundDiagnosticResult(runSoundDiagnostic()) }
        end,
    },
    {
        id = "diag_popup_invite",
        labelKey = "DIAG_POPUP_INVITE",
        command = "/sanc diag popup invite",
        tipKey = "DIAG_TIP_POPUP",
        popupKind = "invite",
    },
    {
        id = "diag_popup_duel",
        labelKey = "DIAG_POPUP_DUEL",
        command = "/sanc diag popup duel",
        tipKey = "DIAG_TIP_POPUP",
        popupKind = "duel",
    },
    {
        id = "diag_popup_guild",
        labelKey = "DIAG_POPUP_GUILD",
        command = "/sanc diag popup guild",
        tipKey = "DIAG_TIP_POPUP",
        popupKind = "guild",
    },
    {
        id = "diag_popup_list",
        labelKey = "DIAG_POPUP_LIST",
        command = "/sanc diag popup list <filtre>",
        argKey = "DIAG_ARG_FILTER",
        argDefault = "",
        run = function(argText)
            return { text = formatPopupListDiagnosticResult(runPopupListDiagnostic(argText or "")) }
        end,
    },
}

for _, entry in ipairs(ns.DIAGNOSTIC_CATALOG) do
    if entry.popupKind and not entry.run then
        local kind = entry.popupKind
        entry.run = function()
            local result = runPopupDiagnostic(kind)
            -- A popup that could not be hidden is still on screen, invisible and
            -- clickable. Report it here instead of relying on the maintainer
            -- remembering the rule from the checklist.
            local leftOnScreen = result.available and not result.skipped
                and result.hidden ~= true
            return {
                text = formatPopupDiagnosticResult(result),
                leftOnScreen = leftOnScreen,
                which = result.which,
            }
        end
    end
end

-- The panel asks this before it hides its "put the screen back" button. Storing
-- a boolean instead let "Clear" -- and a bulk run -- take the way back away
-- while the dialog was still up, invisible and clickable.
function ns.isDiagnosticPopupVisible(which)
    if not which then return false end
    if which == GUILD_INVITE_FRAME_KEY then
        return isGuildInviteFrameShown(getGuildInviteFrame()) and true or false
    end
    return countVisiblePopup(which) > 0
end

function ns.getDiagnosticEntry(id)
    for _, entry in ipairs(ns.DIAGNOSTIC_CATALOG) do
        if entry.id == id then return entry end
    end
    return nil
end

-- Runs one catalogue entry and always returns a displayable result: a
-- diagnostic that throws must show its error in the panel, not disappear into
-- the error handler of a button click.
function ns.runDiagnosticById(id, argText)
    local entry = ns.getDiagnosticEntry(id)
    if not entry then
        return { id = tostring(id), text = string.format(L["DIAG_UNKNOWN"], tostring(id)), failed = true }
    end
    local ok, result = pcall(entry.run, argText)
    if not ok then
        debugLog("DIAG_PANEL", { id = entry.id, ok = false, error = safeText(result, 200, "nil") })
        return { id = entry.id, text = string.format(L["DIAG_FAILED"], entry.id, safeText(result, 200, "nil")), failed = true }
    end
    result = result or {}
    result.id = entry.id
    result.text = result.text or ""
    return result
end

ns.simulateInvite = simulateInvite
ns.formatSimulationResult = formatSimulationResult
ns.simulateBNetWhisper = simulateBNetWhisper
ns.simulateBNetFriend = simulateBNetFriend
ns.formatBNetSimulationResult = formatBNetSimulationResult
ns.runChatDiagnostic = runChatDiagnostic
ns.formatChatDiagnosticResult = formatChatDiagnosticResult
ns.runSoundDiagnostic = runSoundDiagnostic
ns.formatSoundDiagnosticResult = formatSoundDiagnosticResult
ns.runPopupDiagnostic = runPopupDiagnostic
ns.formatPopupDiagnosticResult = formatPopupDiagnosticResult
ns.runPopupListDiagnostic = runPopupListDiagnostic
ns.formatPopupListDiagnosticResult = formatPopupListDiagnosticResult

-- /sanc and /sanctuary open the GUI. Diagnostic subcommands stay hidden.
SLASH_SANCTUARY1 = "/sanctuary"
SLASH_SANCTUARY2 = "/sanc"
SlashCmdList["SANCTUARY"] = function(msg)
    xpcall(function()
        local command, rest = trimCommandText(msg):match("^(%S+)%s*(.*)$")
        command = command and command:lower() or ""
        if command == "simulate" or command == "sim" then
            local simKind, simRest = trimCommandText(rest):match("^(%S+)%s*(.*)$")
            simKind = simKind and simKind:lower() or ""
            if simKind == "bnet" then
                local result = simulateBNetWhisper(simRest)
                printMsg(formatBNetSimulationResult(result))
            elseif simKind == "bnetfriend" then
                local result = simulateBNetFriend(simRest)
                printMsg(formatBNetSimulationResult(result))
            else
                local result = simulateInvite(resolveSimulationTarget(rest))
                printMsg(formatSimulationResult(result))
            end
            return
        end

        if command == "diag" then
            local diagKind, diagRest = trimCommandText(rest):match("^(%S+)%s*(.*)$")
            diagKind = diagKind and diagKind:lower() or ""
            diagRest = trimCommandText(diagRest)
            if diagKind == "chat" then
                local chatKind = diagRest:match("^(%S+)") or "invite"
                printMsg(formatChatDiagnosticResult(runChatDiagnostic(chatKind)))
                return
            elseif diagKind == "sound" then
                local soundKind = diagRest:match("^(%S+)") or "invite"
                if soundKind:lower() ~= "invite" then
                    printError("Diagnostic inconnu. Utilisez /sanc diag sound invite.")
                    return
                end
                printMsg(formatSoundDiagnosticResult(runSoundDiagnostic()))
                return
            elseif diagKind == "popup" then
                local popupCommand, popupRest = diagRest:match("^(%S+)%s*(.*)$")
                popupCommand = popupCommand and popupCommand:lower() or ""
                popupRest = trimCommandText(popupRest)
                if popupCommand == "list" then
                    printMsg(formatPopupListDiagnosticResult(runPopupListDiagnostic(popupRest)))
                else
                    printMsg(formatPopupDiagnosticResult(runPopupDiagnostic(diagRest)))
                end
                return
            end
        end

        if ns.ToggleUI then
            ns.ToggleUI()
        end
    end, geterrorhandler())
end

-- ============================================================================
-- SECTION J: Initialization & Event Registration
-- ============================================================================

local frame = CreateFrame("Frame")

function handlers.ADDON_LOADED(addonName)
    if addonName ~= ADDON_NAME then return end

    -- Initialize SavedVariables
    if not SanctuaryDB then
        SanctuaryDB = deepCopy(ACCOUNT_DEFAULTS)
    else
        fillMissingDefaults(SanctuaryDB, ACCOUNT_DEFAULTS)
    end

    if not SanctuaryCharDB then
        SanctuaryCharDB = deepCopy(CHARACTER_DEFAULTS)
    else
        fillMissingDefaults(SanctuaryCharDB, CHARACTER_DEFAULTS)
    end

    -- Build invite message patterns
    buildInvitePatterns()
    ns.invitePatterns = invitePatterns

    -- Register chat message filters and diagnostics observers.
    registerChatFilters()
    hookChatOutputDiagnostics()

    -- Reset session stats
    SanctuaryCharDB.sessionStats = { blockedCount = 0, blockedByType = {} }

    -- Detect companion addons
    local leatrixLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
        and C_AddOns.IsAddOnLoaded("Leatrix_Plus")
    local badBoyLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
        and C_AddOns.IsAddOnLoaded("BadBoy")

    -- Welcome message
    local enabled = isEnabled()
    local statusText = enabled and (COLOR_ON .. L["ENABLED"] .. COLOR_RESET) or (COLOR_OFF .. L["DISABLED"] .. COLOR_RESET)
    printMsg(string.format(L["ADDON_LOADED"], statusText))

    if leatrixLoaded then
        printMsg(L["LEATRIX_DETECTED"])
    end
    if badBoyLoaded then
        printMsg(L["BADBOY_DETECTED"])
    end

    -- A mute survives /reload and relogging, so one left behind by a previous
    -- session would still be silencing the game's panel sounds right now. No
    -- guard can be active at load, so this is the safe point to lift it.
    releaseStaleProtectedPopupSoundMute()

    -- Keep invite audio suppression aligned with the effective setting.
    refreshInviteSoundMuteState()
    installGuildInviteFrameGuard()

    -- Debug: capture snapshot at load time (if debug was already enabled)
    captureDebugSnapshot("load")
    -- The manifest is not gated on debug mode: a settings file has to say which
    -- build wrote it even when nothing was being recorded.
    ns.captureReportManifest("load")

    frame:UnregisterEvent("ADDON_LOADED")
end

local hasEnteredWorld = false

function handlers.PLAYER_ENTERING_WORLD()
    invalidateWhitelist()
    debugLog("WORLD", addRuntimeContext({
        isInGuild = IsInGuild() and true or false,
        isInGroup = IsInGroup() and true or false,
        initial = not hasEnteredWorld,
    }))

    -- Reset session-only tracking once at login, not on every dungeon/loading
    -- screen transition. The previous behavior restarted the five-minute timer
    -- whenever PLAYER_ENTERING_WORLD fired inside an instance.
    if SanctuaryCharDB and not hasEnteredWorld then
        wipe(SanctuaryCharDB.groupTracker)
    end
    hasEnteredWorld = true
    refreshGroupTracker()
    refreshInviteSoundMuteState()
    installGuildInviteFrameGuard()
    -- Both are idempotent. Retrying registration here is what makes the filter
    -- registry adapter meaningful: if no registration path resolved at load,
    -- ADDON_LOADED never fires again and the session would filter nothing.
    registerChatFilters()
    hookChatOutputDiagnostics()

    -- Request social data refresh. Both calls are pcall-wrapped because their
    -- availability/state varies during login and loading transitions.
    pcall(function()
        C_FriendList.ShowFriends()
    end)
    pcall(function()
        if C_GuildInfo and C_GuildInfo.GuildRoster then
            C_GuildInfo.GuildRoster()
        end
    end)
end

local function debugLogPlayerState(eventName)
    if not SanctuaryDB or not SanctuaryDB.debugEnabled then return end

    debugLog("PLAYER_STATE", addRuntimeContext({
        event = eventName,
    }))
end

function handlers.PLAYER_DEAD()
    debugLogPlayerState("PLAYER_DEAD")
end

function handlers.PLAYER_ALIVE()
    debugLogPlayerState("PLAYER_ALIVE")
end

function handlers.PLAYER_UNGHOST()
    debugLogPlayerState("PLAYER_UNGHOST")
end

-- The settings file is the official record, and the client writes it here. The
-- manifest is stamped one last time at this point so the file describes the
-- session it actually ends, whether or not the summary window was ever opened.
function handlers.PLAYER_LOGOUT()
    ns.captureReportManifest("logout")
end

-- Register all events
local events = {
    "ADDON_LOADED",
    "PLAYER_LOGOUT",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_DEAD",
    "PLAYER_ALIVE",
    "PLAYER_UNGHOST",
    "PARTY_INVITE_REQUEST",
    "DUEL_REQUESTED",
    "GUILD_INVITE_REQUEST",
    "TRADE_SHOW",
    "GUILD_ROSTER_UPDATE",
    "PLAYER_GUILD_UPDATE",
    "FRIENDLIST_UPDATE",
    "BN_FRIEND_INFO_CHANGED",
    "BN_FRIEND_LIST_SIZE_CHANGED",
    "GROUP_ROSTER_UPDATE",
    "CHAT_MSG_SYSTEM",
    "CHAT_MSG_WHISPER",
    "CHAT_MSG_BN_WHISPER",
    "CHAT_MSG_SAY",
    "CHAT_MSG_YELL",
    "CHAT_MSG_EMOTE",
    "CHAT_MSG_TEXT_EMOTE",
    "CHAT_MSG_CHANNEL",
}

for _, event in ipairs(events) do
    frame:RegisterEvent(event)
end

frame:SetScript("OnEvent", function(self, event, ...)
    local handler = handlers[event]
    if handler then
        xpcall(handler, geterrorhandler(), ...)
    end
end)

-- Secure post-hook: mask protected interaction popups before the next frame.
-- The event-order bridge above makes this safe for trusted invitations too.
hooksecurefunc("StaticPopup_Show", function(which, text_arg1, text_arg2, data)
    if which ~= "PARTY_INVITE" and which ~= "DUEL_REQUESTED" then
        return
    end

    if not isPopupProtectionActive(which) then
        clearPendingPopupDecision(which)
        unmaskVisiblePopup(which)
        restoreStaticPopupSoundAfterShow(which, "filter_disabled_show")
        return
    end

    local decision = consumePendingPopupDecision(which)
    local affected
    local action
    if decision then
        affected = applyPopupDecision(which, decision.shouldBlock)
        action = decision.shouldBlock and "MASK_DECIDED_BLOCK" or "SHOW_DECIDED_ALLOW"
        if decision.shouldBlock then
            scheduleVisiblePopupSilentHide(which, "pending_block")
        end
    else
        -- Blizzard ran first: hide immediately; Sanctuary's event handler will
        -- resolve allow/block later in the same synchronous event dispatch.
        affected = maskVisiblePopup(which)
        action = "MASK_AWAITING_EVENT"
    end
    local soundRestored = restoreStaticPopupSoundAfterShow(which, "static_popup_show")

    debugLog("POPUP", addRuntimeContext({
        which = which,
        action = action,
        affected = affected or 0,
        soundRestored = soundRestored and true or false,
        pendingName = decision and decision.name or "nil",
        pendingReason = decision and decision.reason or "nil",
        text_arg1 = safeText(text_arg1, 200, "nil"),
        text_arg2 = safeText(text_arg2, 100, "nil"),
        dataType = type(data),
    }))
end)

-- Auto-trust: check if group members passed the threshold
C_Timer.NewTicker(30, function()
    if not isEnabled() then return end
    if not getEffective("filters.autoTrust") then return end
    if not SanctuaryCharDB or not SanctuaryCharDB.groupTracker then return end
    if not SanctuaryDB then return end

    local threshold = (SanctuaryDB.temporalGroupTrust.trustThresholdMinutes or 5) * 60
    local now = GetTime()

    for name, joinTime in pairs(SanctuaryCharDB.groupTracker) do
        if (now - joinTime) >= threshold then
            if not SanctuaryDB.manualWhitelist[name] then
                SanctuaryDB.manualWhitelist[name] = {
                    displayName = name,
                    addedAt = time(),
                    source = "trust",
                }
                invalidateWhitelist()
                printMsg(string.format(L["TRUST_AUTO_ADDED"], name))
            end
            SanctuaryCharDB.groupTracker[name] = nil
        end
    end
end)

-- Minimal notification ticker (for "minimal" mode)
C_Timer.NewTicker(60, function()
    if not SanctuaryDB then return end
    if SanctuaryDB.notifications.mode ~= "minimal" then return end
    if not isEnabled() then return end
    if not SanctuaryCharDB then return end

    local stats = SanctuaryCharDB.sessionStats
    local count = stats.blockedCount or 0
    if count > 0 then
        local interval = (SanctuaryDB.notifications.minimalIntervalMinutes or 5) * 60
        local now = GetTime()
        if not Sanctuary.lastMinimalNotif or (now - Sanctuary.lastMinimalNotif) >= interval then
            printMsg(string.format(L["BLOCKED_SESSION"], COLOR_WARN .. count .. COLOR_RESET))
            Sanctuary.lastMinimalNotif = now
        end
    end
end)
