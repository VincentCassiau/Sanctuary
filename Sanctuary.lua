-- ============================================================================
-- Sanctuary — WoW Anti-Harassment Addon (Whitelist-based protection)
-- Version: 0.3.0 | Interface: 120001 (Midnight)
-- ============================================================================

-- ============================================================================
-- SECTION A: Namespace & Constants
-- ============================================================================

local ADDON_NAME, ns = ...
local L = ns.L
local VERSION = "0.3.0"

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

local function normalizeName(name)
    if not name or name == "" then return nil end
    -- Strip color codes and link formatting
    name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    -- Strip brackets (chat format: [Name-Realm])
    name = name:gsub("%[", ""):gsub("%]", "")
    -- Trim leading/trailing whitespace
    name = name:match("^%s*(.-)%s*$")
    if name == "" then return nil end
    -- Remove ALL internal spaces
    name = name:gsub("%s", "")
    name = name:lower()
    -- Extract NAME ONLY (strip realm if present): "alice-tarrenmill" -> "alice"
    -- This avoids all realm normalization bugs and simplifies cross-realm matching
    local nameOnly = name:match("^(.+)-") or name
    return nameOnly
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
ns.getEffective = getEffective
ns.isEnabled = isEnabled
ns.parseBool = parseBool
ns.deepCopy = deepCopy
ns.fillMissingDefaults = fillMissingDefaults

-- Keyword blacklist: blocks names containing any suspect keyword
local function matchesKeyword(name)
    if not name or not SanctuaryDB or not SanctuaryDB.keywords then return false, nil end
    local lowerName = name:lower():gsub("%s", "")
    for _, keyword in ipairs(SanctuaryDB.keywords) do
        if keyword ~= "" and lowerName:find(keyword:lower(), 1, true) then
            return true, keyword
        end
    end
    return false, nil
end

ns.matchesKeyword = matchesKeyword

-- ============================================================================
-- SECTION E: Whitelist Engine
-- ============================================================================

Sanctuary.whitelistCache = {}
Sanctuary.whitelistDirty = true

local function rebuildWhitelist()
    local cache = {}

    -- Manual whitelist (account-wide)
    if SanctuaryDB and SanctuaryDB.manualWhitelist then
        for key in pairs(SanctuaryDB.manualWhitelist) do
            cache[key] = true
        end
    end

    -- Manual whitelist (per-character)
    if SanctuaryCharDB and SanctuaryCharDB.manualWhitelist then
        for key in pairs(SanctuaryCharDB.manualWhitelist) do
            cache[key] = true
        end
    end

    -- Guild members (always whitelisted)
    if IsInGuild() then
        local ok = pcall(function()
            local numMembers = GetNumGuildMembers()
            for i = 1, numMembers do
                local name = GetGuildRosterInfo(i)
                if name then
                    local normalized = normalizeName(name)
                    if normalized then
                        cache[normalized] = true
                    end
                end
            end
        end)
        if not ok then
            -- Guild API failed, skip silently
        end
    end

    -- Battle.net friends (always whitelisted)
    -- NOTE: BNGetNumFriends() may be deprecated in future; monitor for C_BattleNet replacement
    local ok = pcall(function()
        local numFriends = BNGetNumFriends()
        for i = 1, numFriends do
            local info = C_BattleNet.GetFriendAccountInfo(i)
            if info and info.gameAccountInfo then
                local gameInfo = info.gameAccountInfo
                local charName = gameInfo.characterName
                local realmName = gameInfo.realmName
                -- normalizeName extracts name-only (strips realm), so just pass charName
                if charName and charName ~= "" then
                    local normalized = normalizeName(charName)
                    if normalized then
                        cache[normalized] = true
                    end
                end
            end
        end
    end)
    if not ok then
        -- BNet API failed, skip silently
    end

    -- Character friends (always whitelisted)
    pcall(function()
        local numFriends = C_FriendList.GetNumFriends()
        for i = 1, numFriends do
            local info = C_FriendList.GetFriendInfoByIndex(i)
            if info and info.name then
                local normalized = normalizeName(info.name)
                if normalized then
                    cache[normalized] = true
                end
            end
        end
    end)

    -- Current group/raid members (always whitelisted)
    pcall(function()
        if IsInGroup() then
            local numMembers = GetNumGroupMembers()
            local isRaid = IsInRaid()
            for i = 1, numMembers do
                local unit = isRaid and ("raid" .. i) or ("party" .. i)
                local name, realm = UnitName(unit)
                if name and name ~= UNKNOWNOBJECT then
                    if realm and realm ~= "" then
                        name = name .. "-" .. realm
                    end
                    local normalized = normalizeName(name)
                    if normalized then
                        cache[normalized] = true
                    end
                end
            end
        end
    end)

    Sanctuary.whitelistCache = cache
    Sanctuary.whitelistDirty = false
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

local function invalidateWhitelist()
    Sanctuary.whitelistDirty = true
end

-- Export whitelist functions to namespace
ns.isWhitelisted = isWhitelisted
ns.invalidateWhitelist = invalidateWhitelist

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

    -- Extract realm from "Name-Realm" format
    local n, r = cleanName:match("^(.+)-(.+)$")
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

    -- Rotation
    local maxEntries = SanctuaryDB.logging.maxEntries or 5000
    if #SanctuaryDB.log > maxEntries then
        local overflow = #SanctuaryDB.log - maxEntries
        local newLog = {}
        for i = overflow + 1, #SanctuaryDB.log do
            newLog[#newLog + 1] = SanctuaryDB.log[i]
        end
        SanctuaryDB.log = newLog
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
-- SECTION G: Chat Message Filters (PURE functions — NO side effects)
-- ============================================================================

-- Build invite pattern from WoW global string at init
local invitePatterns = {}

local function escapePattern(s)
    return s:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
end

local function buildInvitePatterns()
    -- Try WoW global strings first
    local globals = {
        "ERR_INVITED_TO_GROUP_SS",
        "ERR_INVITED_TO_GROUP_S",
        "ERR_INVITED_TO_GROUP",
    }
    for _, globalName in ipairs(globals) do
        local globalStr = _G[globalName]
        if globalStr and type(globalStr) == "string" then
            -- Convert "%s" format specifiers to Lua capture patterns
            local escaped = escapePattern(globalStr)
            local pattern = escaped:gsub("%%%%s", "(.+)"):gsub("%%%%d", "%%d+")
            table.insert(invitePatterns, pattern)
        end
    end

    -- Fallback patterns for common locales
    if #invitePatterns == 0 then
        -- French
        table.insert(invitePatterns, "(.+) vous a invit")
        -- English
        table.insert(invitePatterns, "(.+) has invited you to join a group")
    end
end

local function extractInviterFromSystemMessage(msg)
    for _, pattern in ipairs(invitePatterns) do
        local name = msg:match(pattern)
        if name then
            -- Clean the name (remove realm info artifacts, brackets etc)
            name = name:gsub("%[", ""):gsub("%]", "")
            name = name:match("^%s*(.-)%s*$")
            if name ~= "" then
                return name
            end
        end
    end
    return nil
end

-- System message filter: MUST be a PURE function (called 2+ times per message)
local function systemMessageFilter(self, event, msg, ...)
    if not isEnabled() then return false end
    if not getEffective("filters.groupInvite") then return false end

    local inviterName = extractInviterFromSystemMessage(msg)
    if not inviterName then return false end

    -- Whitelisted players are never blocked
    if isWhitelisted(inviterName) then return false end

    -- Keyword blacklist
    local keyMatch = matchesKeyword(inviterName)
    if keyMatch then
        return true -- suppress the message
    end

    return true -- suppress non-whitelisted
end

-- Whisper filter (P1 — active if setting enabled)
local function whisperFilter(self, event, msg, sender, ...)
    if not isEnabled() then return false end
    -- Whitelisted players are never blocked
    if isWhitelisted(sender) then return false end
    -- Keyword blacklist
    local keyMatch = matchesKeyword(sender)
    if keyMatch then return true end
    if not getEffective("filters.whisper") then return false end
    return true -- suppress non-whitelisted
end

-- Never filter the player's own messages
local function isSelf(sender)
    if not sender then return false end
    local playerName = UnitName("player")
    return playerName and normalizeName(sender) == normalizeName(playerName)
end

-- Say filter (P2 — off by default)
local function sayFilter(self, event, msg, sender, ...)
    if not isEnabled() then return false end
    if isSelf(sender) then return false end
    -- Whitelisted players are never blocked
    if isWhitelisted(sender) then return false end
    -- Keyword blacklist
    local keyMatch = matchesKeyword(sender)
    if keyMatch then return true end
    if not getEffective("filters.say") then return false end
    return true -- suppress non-whitelisted
end

-- Yell filter (P2 — off by default)
local function yellFilter(self, event, msg, sender, ...)
    if not isEnabled() then return false end
    if isSelf(sender) then return false end
    -- Whitelisted players are never blocked
    if isWhitelisted(sender) then return false end
    -- Keyword blacklist
    local keyMatch = matchesKeyword(sender)
    if keyMatch then return true end
    if not getEffective("filters.yell") then return false end
    return true -- suppress non-whitelisted
end

-- Emote filter (P2 — off by default)
local function emoteFilter(self, event, msg, sender, ...)
    if not isEnabled() then return false end
    if isSelf(sender) then return false end
    -- Whitelisted players are never blocked
    if isWhitelisted(sender) then return false end
    -- Keyword blacklist
    local keyMatch = matchesKeyword(sender)
    if keyMatch then return true end
    if not getEffective("filters.emote") then return false end
    return true -- suppress non-whitelisted
end

-- Channel filter (/1, /2, /3...) with 3 modes: none, keywords, all
local function channelFilter(self, event, msg, sender, ...)
    if not isEnabled() then return false end
    if isSelf(sender) then return false end
    local mode = getEffective("filters.channelMode") or "none"
    if mode == "none" then return false end
    -- Whitelisted players are never blocked
    if isWhitelisted(sender) then return false end
    -- Keyword blacklist
    local keyMatch = matchesKeyword(sender)
    if keyMatch then return true end
    -- Full whitelist filter only in "all" mode
    if mode == "all" then
        return true -- suppress non-whitelisted
    end
    return false
end

-- Register all filters
local function registerChatFilters()
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", systemMessageFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", whisperFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_BN_WHISPER", whisperFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SAY", sayFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_YELL", yellFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_EMOTE", emoteFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_TEXT_EMOTE", emoteFilter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", channelFilter)
end

-- Mute invite sounds permanently while filtering is active (safe API, no taint)
-- FileDataIDs verified via Wowhead sound database + in-game testing
local INVITE_SOUND_FILES = {
    567451,  -- igPlayerInvite (FileDataID) - the invite notification ding
    567490,  -- igMainMenuOpen (FileDataID) - popup open sound
    567464,  -- igMainMenuClose (FileDataID) - popup close sound
    -- All 3 muted to fully suppress invite audio feedback
}

local function muteInviteSounds()
    for _, fileID in ipairs(INVITE_SOUND_FILES) do
        pcall(MuteSoundFile, fileID)
    end
end

local function unmuteInviteSounds()
    for _, fileID in ipairs(INVITE_SOUND_FILES) do
        pcall(UnmuteSoundFile, fileID)
    end
end

ns.muteInviteSounds = muteInviteSounds
ns.unmuteInviteSounds = unmuteInviteSounds

-- Close whisper/BNet chat tabs opened by blocked senders
-- Scans up to 20 ChatFrames (including non-visible/minimized ones)
local function closeBlockedWhisperTabs()
    C_Timer.After(0, function()
        for i = 1, 20 do
            local frame = _G["ChatFrame" .. i]
            if frame then
                local ct = frame.chatType
                if ct == "WHISPER" or ct == "BN_WHISPER" then
                    local shouldClose = false

                    -- Check chatTarget
                    if frame.chatTarget then
                        if not isWhitelisted(frame.chatTarget) then
                            shouldClose = true
                        end
                    end

                    -- Check tab text as fallback
                    if not shouldClose then
                        local tab = _G["ChatFrame" .. i .. "Tab"]
                        if tab then
                            local tabText = tab.Text and tab.Text:GetText()
                            if tabText then
                                if not isWhitelisted(tabText) then
                                    shouldClose = true
                                end
                            end
                        end
                    end

                    if shouldClose then
                        pcall(FCF_Close, frame)
                    end
                end
            end
        end
    end)
end

-- Check if a BNet whisper sender has a character in the current group
local function isBNetSenderInGroup(senderBNetName)
    if not IsInGroup() then return false end
    -- Try to find the BNet friend and check if their character is in our group
    -- NOTE: BNGetNumFriends() may be deprecated in future; monitor for C_BattleNet replacement
    local numFriends = BNGetNumFriends()
    for i = 1, numFriends do
        local info = C_BattleNet.GetFriendAccountInfo(i)
        if info then
            -- Check if the BNet name matches
            local bnetName = info.accountName
            if bnetName and normalizeName(bnetName) == normalizeName(senderBNetName) then
                -- Found the BNet friend, check if their character is in our group
                if info.gameAccountInfo and info.gameAccountInfo.characterName then
                    local charName = normalizeName(info.gameAccountInfo.characterName)
                    -- Check group members
                    local numMembers = GetNumGroupMembers()
                    local isRaid = IsInRaid()
                    for j = 1, numMembers do
                        local unit = isRaid and ("raid" .. j) or ("party" .. j)
                        local unitName = UnitName(unit)
                        if unitName and normalizeName(unitName) == charName then
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

-- ============================================================================
-- SECTION H: Event Handlers (side effects happen HERE, not in filters)
-- ============================================================================

-- PARTY_INVITE_REQUEST: set flags for raw hooks (the raw hook on StaticPopup_Show
-- handles the actual decline + popup suppression, this handler is a safety net)
function handlers.PARTY_INVITE_REQUEST(name, isTank, isHealer, isDamage,
    isNativeRealm, allowMultipleRoles, inviterGUID, questSessionActive)
    if not isEnabled() then return end
    if not getEffective("filters.groupInvite") then return end

    -- Whitelisted players are never blocked
    if isWhitelisted(name) then
        -- Whitelisted: briefly unmute so the invite sound plays, then re-mute
        unmuteInviteSounds()
        C_Timer.After(0.5, muteInviteSounds)
        return
    end

    -- Keyword blacklist
    local keyMatch, keyWord = matchesKeyword(name)
    if keyMatch then
        DeclineGroup()
        StaticPopup_Hide("PARTY_INVITE")
        C_Timer.After(0.05, function() StaticPopup_Hide("PARTY_INVITE") end)
        logBlock("groupInvite", name, nil, inviterGUID, keyWord)
        return
    end

    -- Block non-whitelisted: decline, hide popup, log (sound already muted permanently)
    DeclineGroup()
    StaticPopup_Hide("PARTY_INVITE")
    C_Timer.After(0.05, function() StaticPopup_Hide("PARTY_INVITE") end)
    logBlock("groupInvite", name, nil, inviterGUID)
end

-- DUEL_REQUESTED: safety net (raw hook on StaticPopup_Show handles the popup)
function handlers.DUEL_REQUESTED(playerName)
    if not isEnabled() then return end
    if not getEffective("filters.duel") then return end

    -- Whitelisted players are never blocked
    if isWhitelisted(playerName) then return end

    -- Keyword blacklist
    local keyMatch, keyWord = matchesKeyword(playerName)
    if keyMatch then
        CancelDuel()
        StaticPopup_Hide("DUEL_REQUESTED")
        logBlock("duel", playerName, nil, nil, keyWord)
        return
    end

    -- Block non-whitelisted
    CancelDuel()
    StaticPopup_Hide("DUEL_REQUESTED")
    logBlock("duel", playerName, nil, nil)
end

function handlers.GUILD_INVITE_REQUEST(inviter, guildName)
    if not isEnabled() then return end
    if not getEffective("filters.guildInvite") then return end

    -- Whitelisted players are never blocked
    if isWhitelisted(inviter) then return end

    -- Keyword blacklist
    local keyMatch, keyWord = matchesKeyword(inviter)
    if keyMatch then
        DeclineGuild()
        StaticPopup_Hide("GUILD_INVITE")
        logBlock("guildInvite", inviter, guildName, nil, keyWord)
        return
    end

    -- Block non-whitelisted
    DeclineGuild()
    StaticPopup_Hide("GUILD_INVITE")
    logBlock("guildInvite", inviter, guildName, nil)
end

-- TRADE_SHOW: auto-close + log (P1)
function handlers.TRADE_SHOW()
    if not isEnabled() then return end
    if not getEffective("filters.trade") then return end

    -- Trade partner detection (imperfect — WoW API limitation)
    local tradeName = UnitName("NPC")
        or (TradeFrameRecipientNameText and TradeFrameRecipientNameText:GetText())
        or nil
    if not tradeName or tradeName == "" then return end

    -- Whitelisted players are never blocked
    if isWhitelisted(tradeName) then return end

    -- Keyword blacklist
    local keyMatch, keyWord = matchesKeyword(tradeName)
    if keyMatch then
        CloseTrade()
        logBlock("trade", tradeName, nil, nil, keyWord)
        return
    end

    -- Block non-whitelisted
    CloseTrade()
    logBlock("trade", tradeName, nil, nil)
end

-- Whitelist refresh events
function handlers.GUILD_ROSTER_UPDATE()
    invalidateWhitelist()
end

function handlers.FRIENDLIST_UPDATE()
    invalidateWhitelist()
end

function handlers.BN_FRIEND_INFO_CHANGED()
    invalidateWhitelist()
end

function handlers.BN_FRIEND_LIST_SIZE_CHANGED()
    invalidateWhitelist()
end

function handlers.GROUP_ROSTER_UPDATE()
    invalidateWhitelist()
    if not isEnabled() then return end
    if not getEffective("filters.autoTrust") then return end
    if not SanctuaryCharDB or not SanctuaryCharDB.groupTracker then return end

    local currentMembers = {}
    if IsInGroup() then
        local numMembers = GetNumGroupMembers()
        local isRaid = IsInRaid()
        for i = 1, numMembers do
            local unit = isRaid and ("raid" .. i) or ("party" .. i)
            local name = UnitName(unit)
            if name and name ~= UnitName("player") and name ~= UNKNOWNOBJECT then
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

-- Whisper event handler for logging + tab closing
function handlers.CHAT_MSG_WHISPER(msg, sender, ...)
    if not isEnabled() then return end
    -- Whitelisted players are never blocked
    if isWhitelisted(sender) then return end
    -- Keyword blacklist
    local keyMatch, keyWord = matchesKeyword(sender)
    if keyMatch then
        logBlock("whisper", sender, msg, nil, keyWord)
        closeBlockedWhisperTabs()
        return
    end
    if not getEffective("filters.whisper") then return end
    -- Block non-whitelisted
    logBlock("whisper", sender, msg, nil)
    closeBlockedWhisperTabs()
end

-- BNet whisper handler: BNet senders use account names, not character names,
-- so we need special group member detection via BNet API
function handlers.CHAT_MSG_BN_WHISPER(msg, sender, ...)
    if not isEnabled() then return end
    -- Whitelisted players are never blocked (check BNet group membership too)
    if isWhitelisted(sender) then return end
    if isBNetSenderInGroup(sender) then return end
    -- Keyword blacklist
    local keyMatch, keyWord = matchesKeyword(sender)
    if keyMatch then
        logBlock("whisper", sender, msg, nil, keyWord)
        closeBlockedWhisperTabs()
        return
    end
    if not getEffective("filters.whisper") then return end
    -- Block non-whitelisted
    logBlock("whisper", sender, msg, nil)
    closeBlockedWhisperTabs()
end

function handlers.CHAT_MSG_SAY(msg, sender, ...)
    if not isEnabled() then return end
    -- Whitelisted players are never blocked
    if isWhitelisted(sender) then return end
    -- Keyword blacklist
    local keyMatch, keyWord = matchesKeyword(sender)
    if keyMatch then
        logBlock("say", sender, msg, nil, keyWord)
        return
    end
    if not getEffective("filters.say") then return end
    -- Block non-whitelisted
    logBlock("say", sender, msg, nil)
end

function handlers.CHAT_MSG_YELL(msg, sender, ...)
    if not isEnabled() then return end
    -- Whitelisted players are never blocked
    if isWhitelisted(sender) then return end
    -- Keyword blacklist
    local keyMatch, keyWord = matchesKeyword(sender)
    if keyMatch then
        logBlock("yell", sender, msg, nil, keyWord)
        return
    end
    if not getEffective("filters.yell") then return end
    -- Block non-whitelisted
    logBlock("yell", sender, msg, nil)
end

function handlers.CHAT_MSG_EMOTE(msg, sender, ...)
    if not isEnabled() then return end
    -- Whitelisted players are never blocked
    if isWhitelisted(sender) then return end
    -- Keyword blacklist
    local keyMatch, keyWord = matchesKeyword(sender)
    if keyMatch then
        logBlock("emote", sender, msg, nil, keyWord)
        return
    end
    if not getEffective("filters.emote") then return end
    -- Block non-whitelisted
    logBlock("emote", sender, msg, nil)
end

-- CHAT_MSG_TEXT_EMOTE: standard emotes (/dance, /wave, etc.) — same logic as custom emotes
handlers.CHAT_MSG_TEXT_EMOTE = handlers.CHAT_MSG_EMOTE

function handlers.CHAT_MSG_CHANNEL(msg, sender, ...)
    if not isEnabled() then return end
    local mode = getEffective("filters.channelMode") or "none"
    if mode == "none" then return end
    -- Whitelisted players are never blocked
    if isWhitelisted(sender) then return end
    -- Keyword blacklist
    local keyMatch, keyWord = matchesKeyword(sender)
    if keyMatch then
        logBlock("channel", sender, msg, nil, keyWord)
        return
    end
    -- Block non-whitelisted in "all" mode
    if mode == "all" then
        logBlock("channel", sender, msg, nil)
    end
end

-- ============================================================================
-- SECTION I: Slash Command Handler
-- ============================================================================

-- /sanc and /sanctuary open the GUI. All configuration is done through the UI.
SLASH_SANCTUARY1 = "/sanctuary"
SLASH_SANCTUARY2 = "/sanc"
SlashCmdList["SANCTUARY"] = function(msg)
    xpcall(function()
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

    -- Register chat message filters
    registerChatFilters()

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

    -- Mute invite sounds permanently while filtering is active
    if isEnabled() and getEffective("filters.groupInvite") then
        muteInviteSounds()
    end

    frame:UnregisterEvent("ADDON_LOADED")
end

function handlers.PLAYER_ENTERING_WORLD()
    invalidateWhitelist()
    -- Clean group tracker on login
    if SanctuaryCharDB then
        SanctuaryCharDB.groupTracker = {}
    end
    -- Request friend/guild data refresh
    pcall(function()
        C_FriendList.ShowFriends()
    end)
    pcall(function()
        if IsInGuild() and C_GuildInfo then
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
    "FRIENDLIST_UPDATE",
    "BN_FRIEND_INFO_CHANGED",
    "BN_FRIEND_LIST_SIZE_CHANGED",
    "GROUP_ROSTER_UPDATE",
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

-- Post-hook on StaticPopup_Show: hide blocked popups immediately after creation
-- Uses hooksecurefunc (safe, no taint) instead of raw hook
hooksecurefunc("StaticPopup_Show", function(which, text_arg1)
    if not isEnabled() then return end

    if which == "PARTY_INVITE" and getEffective("filters.groupInvite") then
        if text_arg1 and not isWhitelisted(text_arg1) then
            StaticPopup_Hide("PARTY_INVITE")
        end
    elseif which == "DUEL_REQUESTED" and getEffective("filters.duel") then
        if text_arg1 and not isWhitelisted(text_arg1) then
            StaticPopup_Hide("DUEL_REQUESTED")
        end
    elseif which == "GUILD_INVITE" and getEffective("filters.guildInvite") then
        if text_arg1 and not isWhitelisted(text_arg1) then
            StaticPopup_Hide("GUILD_INVITE")
        end
    end
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
