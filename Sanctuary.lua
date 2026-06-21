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

local function stripWoWFormatting(value)
    if not value or value == "" then return nil end
    value = tostring(value)
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

-- Forward declarations for debug functions (defined in Section F2, used in E and H)
local debugLog, countBNetWithCharName, captureDebugSnapshot, isBNetSenderInGroup
local inviteSoundsMutedBySanctuary = false

-- ============================================================================
-- SECTION E: Whitelist Engine
-- ============================================================================

Sanctuary.whitelistCache = {}
Sanctuary.bnetWhitelistCache = {}
Sanctuary.whitelistDirty = true

local function rebuildWhitelist()
    local cache = {}
    local bnetCache = {}

    local function addCharacterName(name)
        local normalized = normalizeName(name)
        if normalized then
            cache[normalized] = true
        end
    end

    local function addBNetAccountName(name)
        local normalized = normalizeBNetName(name)
        if normalized then
            bnetCache[normalized] = true
        end
    end

    -- Manual whitelist (account-wide)
    if SanctuaryDB and SanctuaryDB.manualWhitelist then
        for key in pairs(SanctuaryDB.manualWhitelist) do
            addCharacterName(key)
        end
    end

    -- Manual whitelist (per-character)
    if SanctuaryCharDB and SanctuaryCharDB.manualWhitelist then
        for key in pairs(SanctuaryCharDB.manualWhitelist) do
            addCharacterName(key)
        end
    end

    -- Guild members (always whitelisted).
    -- Do not gate this on IsInGuild(): during instance/loading transitions WoW can
    -- transiently return false while the roster is still fully populated.
    pcall(function()
        local numMembers = GetNumGuildMembers() or 0
        for i = 1, numMembers do
            local name = GetGuildRosterInfo(i)
            if name then addCharacterName(name) end
        end
    end)

    -- Battle.net friends (always whitelisted): cache both the account display
    -- name (used by CHAT_MSG_BN_WHISPER) and the currently visible character.
    pcall(function()
        local numFriends = BNGetNumFriends() or 0
        for i = 1, numFriends do
            local info = C_BattleNet.GetFriendAccountInfo(i)
            if info then
                addBNetAccountName(info.accountName)
                local gameInfo = info.gameAccountInfo
                if gameInfo and gameInfo.characterName and gameInfo.characterName ~= "" then
                    addCharacterName(gameInfo.characterName)
                end
            end
        end
    end)

    -- Character friends (always whitelisted)
    pcall(function()
        local numFriends = C_FriendList.GetNumFriends() or 0
        for i = 1, numFriends do
            local info = C_FriendList.GetFriendInfoByIndex(i)
            if info and info.name then addCharacterName(info.name) end
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
                    addCharacterName(name)
                end
            end
        end
    end)

    Sanctuary.whitelistCache = cache
    Sanctuary.bnetWhitelistCache = bnetCache
    Sanctuary.whitelistDirty = false

    if SanctuaryDB and SanctuaryDB.debugEnabled then
        local totalSize = 0
        for _ in pairs(cache) do totalSize = totalSize + 1 end
        local bnetSize = 0
        for _ in pairs(bnetCache) do bnetSize = bnetSize + 1 end
        local gm = 0; pcall(function() gm = GetNumGuildMembers() end)
        local bn = 0; pcall(function() bn = BNGetNumFriends() end)
        local cf = 0; pcall(function() cf = C_FriendList.GetNumFriends() end)
        local grp = IsInGroup() and GetNumGroupMembers() or 0
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

-- ============================================================================
-- SECTION F: Logging Engine
-- ============================================================================

local lastLogKey = ""
local lastLogTime = 0

local function logBlock(blockType, sourceName, message, guid, keyword)
    if not SanctuaryDB then return end
    if not SanctuaryDB.logging.enabled then return end

    -- Dedup: skip if same event logged within 1 second
    local logKey = blockType .. ":" .. (sourceName or "")
    local now = GetTime()
    if logKey == lastLogKey and (now - lastLogTime) < 1 then
        return
    end
    lastLogKey = logKey
    lastLogTime = now

    local playerName = UnitName("player")
    local charRealm = getPlayerRealm()
    local sourceRealm = ""
    local cleanName = sourceName or "Unknown"

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
        msg   = message,
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
            COLOR_HIGHLIGHT .. (sourceName or "?") .. COLOR_RESET))
    end
end

-- Export logging to namespace
ns.logBlock = logBlock

-- ============================================================================
-- SECTION F2: Debug Logging Engine
-- ============================================================================

local debugSeq = 0

debugLog = function(cat, data)
    if not SanctuaryDB or not SanctuaryDB.debugEnabled then return end
    if not SanctuaryDB.debugLog then SanctuaryDB.debugLog = {} end

    debugSeq = debugSeq + 1
    table.insert(SanctuaryDB.debugLog, {
        seq = debugSeq,
        t = GetTime(),
        ts = date("%H:%M:%S"),
        cat = cat,
        data = data or {},
    })

    -- Rotation: keep max 500 entries without replacing the SavedVariables
    -- table reference used by the diagnostics UI.
    local overflow = #SanctuaryDB.debugLog - 500
    if overflow > 0 then
        local oldCount = #SanctuaryDB.debugLog
        for i = 1, oldCount - overflow do
            SanctuaryDB.debugLog[i] = SanctuaryDB.debugLog[i + overflow]
        end
        for i = oldCount - overflow + 1, oldCount do
            SanctuaryDB.debugLog[i] = nil
        end
    end
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
        sender = sender or "nil",
        normalized = normalized or "nil",
        action = action or "UNKNOWN",
        reason = reason or "nil",
        keyword = keyword or "none",
        msg = type(msg) == "string" and msg:sub(1, 300) or "nil",
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
            local info = C_BattleNet.GetFriendAccountInfo(i)
            if info and info.gameAccountInfo
                and info.gameAccountInfo.characterName
                and info.gameAccountInfo.characterName ~= "" then
                count = count + 1
            end
        end
    end)
    return count
end

-- Capture a full state snapshot (called on debug enable + ADDON_LOADED)
captureDebugSnapshot = function()
    if not SanctuaryDB or not SanctuaryDB.debugEnabled then return end

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
    local guildN = 0; pcall(function() guildN = GetNumGuildMembers() end)
    local bnetN = 0; pcall(function() bnetN = BNGetNumFriends() end)
    local friendN = 0; pcall(function() friendN = C_FriendList.GetNumFriends() end)

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

    debugLog("SNAPSHOT", {
        version = VERSION,
        locale = GetLocale(),
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
        groupInviteFilter = getEffective("filters.groupInvite") == true,
        inviteSoundsMuted = inviteSoundsMutedBySanctuary and true or false,
    })
end

ns.debugLog = debugLog
ns.captureDebugSnapshot = captureDebugSnapshot
ns.countBNetWithCharName = countBNetWithCharName

-- ============================================================================
-- SECTION G: Chat Message Filters (PURE functions — NO side effects)
-- ============================================================================

-- Build invite pattern from WoW global string at init
local invitePatterns = {}

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
    local seen = {}

    local globals = {
        "ERR_INVITED_TO_GROUP_SS",
        "ERR_INVITED_TO_GROUP_S",
        "ERR_INVITED_TO_GROUP",
        "ERR_INVITED_ALREADY_IN_GROUP_SS",
        "ERR_INVITED_ALREADY_IN_GROUP_S",
    }

    for _, globalName in ipairs(globals) do
        local pattern = formatStringToPattern(_G[globalName])
        if pattern and not seen[pattern] then
            seen[pattern] = true
            invitePatterns[#invitePatterns + 1] = pattern
        end
    end

    -- The client globals are the source of truth. These fallbacks only protect
    -- startup/API edge cases where the localized strings are unexpectedly nil.
    if #invitePatterns == 0 then
        invitePatterns[#invitePatterns + 1] = "^%[(.+)%] vous a invit"
        invitePatterns[#invitePatterns + 1] = "^%[(.+)%] has invited you to join a group"
    end
end

local function extractInviterFromSystemMessage(msg)
    if type(msg) ~= "string" or msg == "" then return nil, nil end
    for idx, pattern in ipairs(invitePatterns) do
        local name = msg:match(pattern)
        if name then
            -- Clean the name (remove realm info artifacts, brackets etc)
            name = name:gsub("%[", ""):gsub("%]", "")
            name = name:match("^%s*(.-)%s*$")
            if name ~= "" then
                return name, idx
            end
        end
    end
    return nil, nil
end

-- System-message filters are invoked once per destination chat frame, so they
-- must stay side-effect free. Logging/debugging happens in CHAT_MSG_SYSTEM.
local function systemMessageFilter(self, event, msg, ...)
    if not isEnabled() then return false end
    if not getEffective("filters.groupInvite") then return false end

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

    local keywordMatch = matchesKeyword(sender)
    if keywordMatch then return true end
    if not getEffective("filters.whisper") then return false end

    if isBNetWhitelisted(sender) then return false end
    if isBNetSenderInGroup and isBNetSenderInGroup(sender) then return false end
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
local function registerChatFilters()
    if chatFiltersRegistered then return end
    chatFiltersRegistered = true

    ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", systemMessageFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", whisperFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_BN_WHISPER", bnetWhisperFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SAY", sayFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_YELL", yellFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_EMOTE", emoteFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_TEXT_EMOTE", emoteFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", channelFilter)
end

-- Diagnostic-only observation of text that actually reaches a chat frame. This
-- does not alter chat output; it lets the next debug report distinguish a
-- Blizzard event-filter miss from another addon re-printing the same message
-- directly through ChatFrame:AddMessage.
local chatOutputHooked = setmetatable({}, { __mode = "k" })
local function hookChatOutputDiagnostics()
    for i = 1, 20 do
        local chatFrame = _G["ChatFrame" .. i]
        if chatFrame and not chatOutputHooked[chatFrame] and chatFrame.AddMessage then
            local frameIndex = i
            local ok = pcall(hooksecurefunc, chatFrame, "AddMessage", function(_, text)
                if not SanctuaryDB or not SanctuaryDB.debugEnabled or type(text) ~= "string" then
                    return
                end

                local inviterName, patternIndex = extractInviterFromSystemMessage(text)
                if inviterName then
                    local shouldBlock, reason, keyword = getCharacterDecision(inviterName)
                    debugLog("CHAT_OUTPUT", {
                        frame = frameIndex,
                        msg = text:sub(1, 300),
                        name = inviterName,
                        pattern = patternIndex or "?",
                        shouldBlock = shouldBlock and true or false,
                        reason = reason or "nil",
                        keyword = keyword or "none",
                    })
                end
            end)
            if ok then
                chatOutputHooked[chatFrame] = true
            end
        end
    end
end

ns.hookChatOutputDiagnostics = hookChatOutputDiagnostics

-- Mute invite sounds permanently while filtering is active (safe API, no taint)
-- FileDataIDs verified via Wowhead sound database + in-game testing
local INVITE_SOUND_FILES = {
    567451,  -- igPlayerInvite (FileDataID) - the invite notification ding
    567490,  -- igMainMenuOpen (FileDataID) - popup open sound
    567464,  -- igMainMenuClose (FileDataID) - popup close sound
    -- All 3 muted to fully suppress invite audio feedback
}

local function muteInviteSounds()
    if inviteSoundsMutedBySanctuary then return end
    for _, fileID in ipairs(INVITE_SOUND_FILES) do
        pcall(MuteSoundFile, fileID)
    end
    inviteSoundsMutedBySanctuary = true
    debugLog("SOUND", {
        action = "MUTE",
        files = #INVITE_SOUND_FILES,
        addonEnabled = isEnabled(),
        groupInviteFilter = getEffective("filters.groupInvite") == true,
    })
end

local function unmuteInviteSounds()
    if not inviteSoundsMutedBySanctuary then return end
    for _, fileID in ipairs(INVITE_SOUND_FILES) do
        pcall(UnmuteSoundFile, fileID)
    end
    inviteSoundsMutedBySanctuary = false
    debugLog("SOUND", {
        action = "UNMUTE",
        files = #INVITE_SOUND_FILES,
        addonEnabled = isEnabled(),
        groupInviteFilter = getEffective("filters.groupInvite") == true,
    })
end

local function refreshInviteSoundMuteState()
    if isEnabled() and getEffective("filters.groupInvite") then
        muteInviteSounds()
    else
        unmuteInviteSounds()
    end
end

ns.muteInviteSounds = muteInviteSounds
ns.unmuteInviteSounds = unmuteInviteSounds
ns.refreshInviteSoundMuteState = refreshInviteSoundMuteState
ns.areInviteSoundsMuted = function()
    return inviteSoundsMutedBySanctuary and true or false
end

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
                        pcall(FCF_Close, chatFrame)
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
    pcall(function()
        local numFriends = BNGetNumFriends() or 0
        for i = 1, numFriends do
            local info = C_BattleNet.GetFriendAccountInfo(i)
            if info and normalizeBNetName(info.accountName) == senderKey then
                local gameInfo = info.gameAccountInfo
                local charName = gameInfo and normalizeName(gameInfo.characterName)
                if charName then
                    local numMembers = GetNumGroupMembers() or 0
                    local isRaid = IsInRaid()
                    for j = 1, numMembers do
                        local unit = isRaid and ("raid" .. j) or ("party" .. j)
                        local unitName = UnitName(unit)
                        if unitName and normalizeName(unitName) == charName then
                            found = true
                            return
                        end
                    end
                end
            end
        end
    end)
    return found
end

-- ============================================================================
-- Popup masking and event-order synchronization
-- ============================================================================
-- StaticPopup_Show runs synchronously inside Blizzard's event handling. A
-- secure post-hook can therefore set alpha to zero before the next rendered
-- frame. The PARTY_INVITE_REQUEST/DUEL_REQUESTED/GUILD_INVITE_REQUEST handler
-- then supplies the trust decision. The small pending-decision bridge supports
-- both possible handler orders: Sanctuary before Blizzard or Blizzard before
-- Sanctuary.
--
-- Native decline APIs remain responsible for closing their own dialogs. Never
-- call StaticPopup_Hide for these interactions: Midnight attaches stateful
-- countdown tickers to some invite dialogs and direct hiding can leave them
-- alive across popup reuse.
local maskedPopupState = setmetatable({}, { __mode = "k" })
local popupHideHooked = setmetatable({}, { __mode = "k" })
local pendingPopupDecisions = {}
local popupDecisionSerial = 0
local POPUP_DECISION_MAX_AGE = 1.0

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

local function unmaskVisiblePopup(which)
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
    unmaskVisiblePopup(nil)
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
    if visible > 0 then
        applyPopupDecision(which, decision.shouldBlock)
    end

    C_Timer.After(0, function()
        if pendingPopupDecisions[which] == decision then
            pendingPopupDecisions[which] = nil
        end
    end)
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
    elseif which == "GUILD_INVITE" then
        return getEffective("filters.guildInvite") == true
    end
    return false
end

ns.maskVisiblePopup = maskVisiblePopup
ns.unmaskVisiblePopup = unmaskVisiblePopup
ns.unmaskAllInteractionPopups = unmaskAllInteractionPopups
ns.clearPendingPopupDecision = clearPendingPopupDecision

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
        return
    end

    local shouldBlock, reason, keyword = getCharacterDecision(name)
    synchronizePopupDecision("PARTY_INVITE", shouldBlock, name, reason)

    debugLog("INVITE", {
        name = name,
        normalized = normalizeName(name),
        guid = inviterGUID or "nil",
        isWL = reason == "whitelist",
        keyword = keyword or "none",
        action = shouldBlock and (reason == "keyword" and "BLOCK_KEYWORD" or "BLOCK_WHITELIST") or "ALLOW",
        filterEnabled = getEffective("filters.groupInvite") == true,
        popupProtectionActive = isPopupProtectionActive("PARTY_INVITE"),
        soundMuted = inviteSoundsMutedBySanctuary and true or false,
        inGroup = IsInGroup() and true or false,
        groupSize = IsInGroup() and GetNumGroupMembers() or 0,
        popupVisible = countVisiblePopup("PARTY_INVITE"),
        wlCache = ns.getWhitelistCacheSize(),
    })

    if not shouldBlock then return end

    -- Keep the dialog invisible and use only Blizzard's native decline path.
    DeclineGroup()
    logBlock("groupInvite", name, nil, inviterGUID, keyword)
end

-- DUEL_REQUESTED follows the same event-order-safe popup path.
function handlers.DUEL_REQUESTED(playerName)
    if not isEnabled() or not getEffective("filters.duel") then
        clearPendingPopupDecision("DUEL_REQUESTED")
        unmaskVisiblePopup("DUEL_REQUESTED")
        return
    end

    local shouldBlock, reason, keyword = getCharacterDecision(playerName)
    synchronizePopupDecision("DUEL_REQUESTED", shouldBlock, playerName, reason)
    debugLog("DUEL", {
        name = playerName,
        action = shouldBlock and (reason == "keyword" and "BLOCK_KEYWORD" or "BLOCK_WHITELIST") or "ALLOW",
    })

    if not shouldBlock then return end

    CancelDuel()
    logBlock("duel", playerName, nil, nil, keyword)
end

function handlers.GUILD_INVITE_REQUEST(inviter, guildName)
    if not isEnabled() or not getEffective("filters.guildInvite") then
        clearPendingPopupDecision("GUILD_INVITE")
        unmaskVisiblePopup("GUILD_INVITE")
        return
    end

    local shouldBlock, reason, keyword = getCharacterDecision(inviter)
    synchronizePopupDecision("GUILD_INVITE", shouldBlock, inviter, reason)
    debugLog("GUILD_INVITE", {
        name = inviter,
        guild = guildName or "nil",
        action = shouldBlock and (reason == "keyword" and "BLOCK_KEYWORD" or "BLOCK_WHITELIST") or "ALLOW",
    })

    if not shouldBlock then return end

    DeclineGuild()
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
    if not shouldBlock then return end

    CloseTrade()
    logBlock("trade", tradeName, nil, nil, keyword)
    debugLog("TRADE", {
        name = tradeName,
        action = reason == "keyword" and "BLOCK_KEYWORD" or "BLOCK_WHITELIST",
    })
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

    local inviterName, patternIndex = extractInviterFromSystemMessage(msg)
    if not inviterName then
        if SanctuaryDB and SanctuaryDB.debugEnabled and msg
            and (msg:lower():find("invit", 1, true) or msg:lower():find("group", 1, true)) then
            debugLog("SYSTEM_INVITE", {
                msg = msg:sub(1, 300),
                result = "NO_MATCH",
            })
        end
        return
    end

    local shouldBlock, reason, keyword = getCharacterDecision(inviterName)
    debugLog("SYSTEM_INVITE", {
        msg = msg:sub(1, 300),
        name = inviterName,
        pattern = patternIndex or "?",
        isWL = reason == "whitelist",
        keyword = keyword or "none",
        result = shouldBlock and (reason == "keyword" and "SUPPRESS_KEYWORD" or "SUPPRESS_NOT_WHITELISTED") or "PASS_WHITELISTED",
        inGroup = IsInGroup() and true or false,
        soundMuted = inviteSoundsMutedBySanctuary and true or false,
    })

    if shouldBlock then
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

    local keywordMatch, keyword = matchesKeyword(sender)
    local filterEnabled = getEffective("filters.whisper") == true
    if not keywordMatch and not filterEnabled then
        debugLogChatDecision("bn_whisper", sender, msg, "PASS_FILTER_DISABLED", "filter_disabled", keyword, {
            filterEnabled = false,
        })
        return
    end

    local action = "BLOCK_NOT_WHITELISTED"
    local reason = "not_whitelisted"
    if keywordMatch then
        action = "BLOCK_KEYWORD"
        reason = "keyword"
    elseif isBNetWhitelisted(sender) then
        action = "ALLOW"
        reason = "bnet_whitelist"
    elseif isBNetSenderInGroup(sender) then
        action = "ALLOW"
        reason = "bnet_group"
    end

    debugLogChatDecision("bn_whisper", sender, msg, action, reason, keyword, {
        filterEnabled = filterEnabled,
    })
    if action == "ALLOW" then return end

    logBlock("whisper", sender, msg, nil, keyword)
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
        inviteSoundsMuted = inviteSoundsMutedBySanctuary and true or false,
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

local function formatSimulationResult(result)
    local action = result.shouldBlock and "BLOCK" or "ALLOW"
    local system = result.systemSuppressed and "blocked" or "visible"
    local alreadyGroup = result.alreadyGroupSuppressed and "blocked" or "visible"
    local wouldDecline = result.wouldDecline and "yes" or "no"
    local soundMute = result.inviteSoundsMuted and "yes" or "no"
    local reason = result.reason
    if result.keyword then
        reason = reason .. ":" .. result.keyword
    end

    return string.format(
        "Simulation invite: %s -> %s (%s) | popup=%s | chat=%s | already-group=%s | would-decline=%s | API=not-called | sound-muted=%s",
        result.name,
        action,
        reason,
        result.popupAction,
        system,
        alreadyGroup,
        wouldDecline,
        soundMute
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

ns.simulateInvite = simulateInvite
ns.formatSimulationResult = formatSimulationResult

-- /sanc and /sanctuary open the GUI. Diagnostic subcommands stay hidden.
SLASH_SANCTUARY1 = "/sanctuary"
SLASH_SANCTUARY2 = "/sanc"
SlashCmdList["SANCTUARY"] = function(msg)
    xpcall(function()
        local command, rest = trimCommandText(msg):match("^(%S+)%s*(.*)$")
        command = command and command:lower() or ""
        if command == "simulate" or command == "sim" then
            local result = simulateInvite(resolveSimulationTarget(rest))
            printMsg(formatSimulationResult(result))
            return
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

    -- Keep invite audio suppression aligned with the effective setting.
    refreshInviteSoundMuteState()

    -- Debug: capture snapshot at load time (if debug was already enabled)
    captureDebugSnapshot()

    frame:UnregisterEvent("ADDON_LOADED")
end

local hasEnteredWorld = false

function handlers.PLAYER_ENTERING_WORLD()
    invalidateWhitelist()
    debugLog("WORLD", {
        isInGuild = IsInGuild() and true or false,
        isInGroup = IsInGroup() and true or false,
        initial = not hasEnteredWorld,
    })

    -- Reset session-only tracking once at login, not on every dungeon/loading
    -- screen transition. The previous behavior restarted the five-minute timer
    -- whenever PLAYER_ENTERING_WORLD fired inside an instance.
    if SanctuaryCharDB and not hasEnteredWorld then
        wipe(SanctuaryCharDB.groupTracker)
    end
    hasEnteredWorld = true
    refreshGroupTracker()
    refreshInviteSoundMuteState()
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

-- Register all events
local events = {
    "ADDON_LOADED",
    "PLAYER_ENTERING_WORLD",
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
    if which ~= "PARTY_INVITE" and which ~= "DUEL_REQUESTED" and which ~= "GUILD_INVITE" then
        return
    end

    if not isPopupProtectionActive(which) then
        clearPendingPopupDecision(which)
        unmaskVisiblePopup(which)
        return
    end

    local decision = consumePendingPopupDecision(which)
    local affected
    local action
    if decision then
        affected = applyPopupDecision(which, decision.shouldBlock)
        action = decision.shouldBlock and "MASK_DECIDED_BLOCK" or "SHOW_DECIDED_ALLOW"
    else
        -- Blizzard ran first: hide immediately; Sanctuary's event handler will
        -- resolve allow/block later in the same synchronous event dispatch.
        affected = maskVisiblePopup(which)
        action = "MASK_AWAITING_EVENT"
    end

    debugLog("POPUP", {
        which = which,
        action = action,
        affected = affected or 0,
        pendingName = decision and decision.name or "nil",
        pendingReason = decision and decision.reason or "nil",
        text_arg1 = tostring(text_arg1 or "nil"):sub(1, 200),
        text_arg2 = tostring(text_arg2 or "nil"):sub(1, 100),
        dataType = type(data),
    })
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
