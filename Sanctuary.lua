-- ============================================================================
-- Sanctuary — WoW Anti-Harassment Addon (Whitelist-based protection)
-- Version: 1.0.0 | Interface: 120007 (Midnight)
-- ============================================================================

-- ============================================================================
-- SECTION A: Namespace & Constants
-- ============================================================================

local ADDON_NAME, ns = ...
local L = ns.L
local VERSION = "1.0.0"

-- Build identity. This is NOT a release version and must never be presented as
-- one: it only makes a user-provided debug report attributable to the exact
-- build that produced it. Bump it whenever the diagnostic surface changes so two
-- reports can never be confused. Keep it non-descriptive -- a date and a counter
-- and nothing else: it is printed verbatim in every report, and a report can be
-- handed to a third party, so the identifier must not leak what is being
-- investigated or which internal item it belongs to.
local BUILD_ID = "20260820-8"

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
    -- Bumped to 2 by the 1.0.0 model (scope/preset switches, always-blocked
    -- list). A settings file still carrying schema 1 is not migrated and not
    -- partly kept: it is rebuilt from these defaults, lists included. See
    -- handlers.ADDON_LOADED.
    schemaVersion = 2,

    filters = {
        -- Question 1. "strangers" filters everyone who is not allowed;
        -- "blockedOnly" filters nobody but the always-blocked list.
        scope              = "strangers",  -- "strangers" | "blockedOnly"
        -- Question 2. "all" applies the recommended set and ignores the stored
        -- per-filter values; "custom" applies exactly what is stored.
        preset             = "all",        -- "all" | "custom"
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

    -- Question 3 of the home screen, and a block of its own rather than a line
    -- of `filters`: it decides nothing about who is filtered. It only asks
    -- whether a repeat of a message that was going to show anyway is worth
    -- showing again. Off by default -- it hides something the person would
    -- otherwise read, so it is opted into, never out of.
    antiSpam = {
        enabled = false,
        intervalSeconds = 300,
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
    -- Always blocked, by exact name. [normalized key] = { displayName, addedAt,
    -- source = "manual"|"menu" }. Beats every trust source, in both scopes and
    -- whatever the filters say.
    blockedNames = {},
    log = {},
    keywords = {},  -- suspicious keyword list (e.g., "jetaime", "belle")
    minimap = {
        hide = false,
        angle = 220,
    },
    uiPosition = nil, -- saved window position { point, x, y }
    uiSize = nil,         -- saved window size { width, height }
    uiSettings = {
        -- The journal records the text of a blocked message either way; this
        -- only decides whether the Journal tab prints it on screen. It starts
        -- off: on an addon whose job is to shield someone from harassment, the
        -- cautious default is not to display what was sent to them until they
        -- ask. The "Show the text of blocked messages" box brings it back.
        showMessageColumn = false,
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
    schemaVersion = 2,
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

-- Cached, but only once there is something worth caching. The API answers nil
-- -- and, on some paths, an empty string -- until the world is entered, and an
-- empty string is truthy: caching one froze the realm as "unknown" for the whole
-- session. That used to cost a realm comparison; since 1.0.0 every entry of the
-- blocked list is keyed by realm, so it would have cost the blocked list
-- entirely, in silence, with the panel still showing the names.
local function getPlayerRealm()
    if not playerRealm or playerRealm == "" then
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

-- Retail exposes a chat messaging lockdown state. One reader for everyone --
-- the snapshot, the runtime markers, the masking decision and the diagnostic
-- button -- so they can never publish different answers for the same instant.
-- An unreadable or missing API is unknown, never "not locked down".
local function readChatLockdown()
    if type(C_ChatInfo) ~= "table" or type(C_ChatInfo.InChatMessagingLockdown) ~= "function" then
        return false, false
    end
    local ok, lockdown = pcall(C_ChatInfo.InChatMessagingLockdown)
    if ok and not isRestrictedValue(lockdown) then
        return lockdown and true or false, true
    end
    return false, false
end

ns.readChatLockdown = readChatLockdown

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

    -- The .toc "Interface" field can list several versions; what the client
    -- actually resolved for this addon is the one the AddOns manager grades as
    -- current or "Out of date", and it is the only one worth comparing to the
    -- client's own interface. Read first, because the metadata answer below
    -- falls back on it.
    if type(C_AddOns) == "table" and type(C_AddOns.GetAddOnInterfaceVersion) == "function" then
        local ok, interfaceVersion = pcall(C_AddOns.GetAddOnInterfaceVersion, ADDON_NAME)
        if ok and interfaceVersion ~= nil and not isRestrictedValue(interfaceVersion) then
            data.addonInterface = tonumber(interfaceVersion) or safeText(interfaceVersion, 20, "nil")
        else
            data.addonInterface = "error"
        end
    else
        data.addonInterface = "unavailable"
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

    -- `GetAddOnMetadata` answers for the custom X- fields and a documented
    -- handful of standard ones; "Interface" is not among them on this client and
    -- comes back nil every time, which is what the 23/08 recording published as
    -- `addonMetaInterface=nil` on every snapshot. Retail exposes that value
    -- through `GetAddOnInterfaceVersion` instead, and that is the same question
    -- answered by the API meant for it -- what interface this addon declares.
    -- Derived only where the metadata said nothing: a client that does answer
    -- keeps its own answer, and a real read error stays an error rather than
    -- being papered over by a second source.
    if (data.addonMetaInterface == nil or data.addonMetaInterface == "nil")
        and type(data.addonInterface) == "number" then
        data.addonMetaInterface = tostring(data.addonInterface)
    end

    data.chatLockdown, data.chatLockdownKnown = readChatLockdown()

    return data
end

ns.getClientBuildContext = getClientBuildContext

local addSnapshotFields
do
addSnapshotFields = function(target, fields)
    target = target or {}
    for key, value in pairs(fields or {}) do
        target[key] = value
    end
    return target
end
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

-- The one case fold this add-on has, used everywhere a key is built or compared
-- and nowhere else.
--
-- `string.lower` is byte-by-byte under Lua's C locale: it folds A-Z and nothing
-- more -- the same ASCII-only limit the `%p`/`%d` rule above `ns.addPattern`
-- already documents. Everything a French or Russian player types walked past it.
-- Somebody typed "elodie" in the blocked field, the game handed over
-- "Elodie-TestRealm", the two keys met and the block worked; they typed "élodie"
-- and the two keys differed on exactly the byte `:lower()` cannot fold. The chip
-- appeared, the tile counted it, the tester said "always blocked" -- and nobody
-- was blocked.
--
-- The other direction is the one with no excuse. "élodie" in the ALLOWED field
-- left "Élodie-TestRealm" unknown, so in the default scope a friend the person
-- had just allowed by hand was cut off with no popup, no sound and no chat line.
-- An allowed player keeps WoW's own behaviour: that rule has no exception, and
-- an add-on whose public is French cannot call an accented pseudo an edge case.
--
-- Bounded on purpose, and written by bytes rather than pulled from a library
-- WoW does not ship:
--   * Latin-1 supplement U+00C0-U+00DE except U+00D7, the multiplication sign --
--     in UTF-8 the lead byte 0xC3 with a second byte of 0x80-0x9E except 0x97.
--     The lowercase letter is the same lead byte plus 0x20. ß (U+00DF) is out of
--     the range on purpose: its uppercase is two letters, not one.
--   * Latin Extended-A (U+0100-U+017F) by the explicit pair table below. The
--     arithmetic on that block changes direction twice, so the pairs are written
--     out rather than guessed at.
--   * Cyrillic U+0410-U+042F -> +0x20, plus Ё (U+0401) -> ё (U+0451), which sits
--     outside that run.
-- Anything else comes back byte for byte, so every ASCII name coming out of the
-- game keeps the exact key it has always had.
--
-- What this must never become is a whitelist of accepted letters: the comment
-- above `ns.addPattern` says why -- it would refuse precisely the names this
-- fixes. `os.setlocale` is not an option either; the client's locale is not ours
-- to set, and the answer must not depend on it.
local foldCase
do
    -- Uppercase codepoint -> lowercase codepoint, one line per letter family.
    local LATIN_EXT_A = {
        [0x0100] = 0x0101, [0x0102] = 0x0103, [0x0104] = 0x0105, -- Ā Ă Ą
        [0x0106] = 0x0107, [0x0108] = 0x0109, [0x010A] = 0x010B, [0x010C] = 0x010D, -- Ć Ĉ Ċ Č
        [0x010E] = 0x010F, [0x0110] = 0x0111, -- Ď Đ
        [0x0112] = 0x0113, [0x0114] = 0x0115, [0x0116] = 0x0117, [0x0118] = 0x0119, [0x011A] = 0x011B, -- Ē Ĕ Ė Ę Ě
        [0x011C] = 0x011D, [0x011E] = 0x011F, [0x0120] = 0x0121, [0x0122] = 0x0123, -- Ĝ Ğ Ġ Ģ
        [0x0124] = 0x0125, [0x0126] = 0x0127, -- Ĥ Ħ
        [0x0128] = 0x0129, [0x012A] = 0x012B, [0x012C] = 0x012D, [0x012E] = 0x012F, [0x0132] = 0x0133, -- Ĩ Ī Ĭ Į Ĳ
        [0x0134] = 0x0135, [0x0136] = 0x0137, -- Ĵ Ķ
        [0x0139] = 0x013A, [0x013B] = 0x013C, [0x013D] = 0x013E, [0x013F] = 0x0140, [0x0141] = 0x0142, -- Ĺ Ļ Ľ Ŀ Ł
        [0x0143] = 0x0144, [0x0145] = 0x0146, [0x0147] = 0x0148, [0x014A] = 0x014B, -- Ń Ņ Ň Ŋ
        [0x014C] = 0x014D, [0x014E] = 0x014F, [0x0150] = 0x0151, [0x0152] = 0x0153, -- Ō Ŏ Ő Œ
        [0x0154] = 0x0155, [0x0156] = 0x0157, [0x0158] = 0x0159, -- Ŕ Ŗ Ř
        [0x015A] = 0x015B, [0x015C] = 0x015D, [0x015E] = 0x015F, [0x0160] = 0x0161, -- Ś Ŝ Ş Š
        [0x0162] = 0x0163, [0x0164] = 0x0165, [0x0166] = 0x0167, -- Ţ Ť Ŧ
        [0x0168] = 0x0169, [0x016A] = 0x016B, [0x016C] = 0x016D, [0x016E] = 0x016F, -- Ũ Ū Ŭ Ů
        [0x0170] = 0x0171, [0x0172] = 0x0173, -- Ű Ų
        [0x0174] = 0x0175, [0x0176] = 0x0177, [0x0178] = 0x00FF, -- Ŵ Ŷ Ÿ (Ÿ folds back into Latin-1)
        [0x0179] = 0x017A, [0x017B] = 0x017C, [0x017D] = 0x017E, -- Ź Ż Ž
    }

    -- Every codepoint above lives in U+0080-U+07FF, the two-byte range.
    local function encode(cp)
        return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64)
    end

    -- Built once at load: the fold itself is a table lookup on a byte pair.
    local FOLD = {}
    for upper, lower in pairs(LATIN_EXT_A) do
        FOLD[encode(upper)] = encode(lower)
    end
    -- İ (U+0130) is the one pair whose lowercase leaves the two-byte range: it
    -- folds to a plain one-byte "i". Written out rather than forced through
    -- `encode`, which would emit an overlong sequence for it.
    FOLD["\196\176"] = "i"
    for trail = 0x80, 0x9E do
        if trail ~= 0x97 then
            FOLD[string.char(0xC3, trail)] = string.char(0xC3, trail + 0x20)
        end
    end
    -- А-П stay on lead byte 0xD0; Р-Я cross to 0xD1, where the low half of the
    -- lowercase run lives.
    for trail = 0x90, 0x9F do
        FOLD[string.char(0xD0, trail)] = string.char(0xD0, trail + 0x20)
    end
    for trail = 0xA0, 0xAF do
        FOLD[string.char(0xD0, trail)] = string.char(0xD1, trail - 0x20)
    end
    FOLD[string.char(0xD0, 0x81)] = string.char(0xD1, 0x91)

    -- `gsub` keeps the match untouched when the function answers nil, which is
    -- exactly "this pair is outside the mapped blocks, leave it alone".
    local function foldPair(pair)
        return FOLD[pair]
    end

    foldCase = function(text)
        if type(text) ~= "string" then return text end
        -- ASCII first. `lower` folds A-Z and never touches a byte >= 0x80, so
        -- the two passes cannot tread on each other.
        text = text:lower()
        return (text:gsub("[\194-\223][\128-\191]", foldPair))
    end
end

-- Forward declaration: the one rule that says where a pseudo ends lives further
-- down, next to the always-blocked door, and is assigned there. Declared here so
-- `normalizeName` cuts with it rather than with a rule of its own -- keep the
-- two together whatever else moves. `local function splitCharacterName` down
-- there would shadow this and silently hand `normalizeName` a nil global.
local splitCharacterName

-- The key shape of the AUTOMATIC whitelist sources -- guild, character friends,
-- Battle.net friends, the current group: the pseudo half, lower-cased, no realm.
--
-- Cut by `splitCharacterName`, the same rule the two hand-written lists and the
-- patterns use, so nothing can disagree about where a pseudo ends. Its own rule
-- used to strip spaces instead of cutting on them, and to cut on a hyphen only
-- when a character came first, which wrote exactly the entries `addBlocked`
-- refuses: "Toto Ysondre" was keyed "totoysondre" and "-Toto" was keyed "-toto"
-- -- keys no name coming out of the game ever matches. The person read the label
-- in the panel, saw it counted in the tile, and the friend they had just allowed
-- went on being filtered with no popup, no sound and no chat line. An allowed
-- player keeps WoW's own behaviour: that is the product rule this broke.
--
-- Realm-less on purpose, and only here. What the person types into either panel
-- is keyed by `normalizeCharacterKey` with its realm (decision 119); a roster is
-- not, because a roster answers again every time it changes -- the transfer that
-- strands a typed entry cannot strand it -- and because rosters hand over bare
-- names often enough that demanding a realm would lose friends the add-on is
-- meant to let through. The known residue is stated in the brief: a guild mate's
-- namesake on another realm is covered by the guild entry.
--
-- Answers nil when nothing usable is left ("-", " - "), and every caller refuses
-- the input rather than inventing an entry for it.
local function normalizeName(name)
    -- Parenthesised: `splitCharacterName` answers two values and every caller
    -- here wants the pseudo alone.
    return (splitCharacterName(name))
end

local function normalizeBNetName(name)
    name = stripWoWFormatting(name)
    if not name then return nil end
    -- Battle.net account display names may contain spaces; preserve them.
    name = foldCase((name:gsub("%s+", " ")))
    return name
end

-- The one mark that tells an account from a character. A Battle.net display
-- name carries its tag ("Real Friend#1234"); a WoW pseudo can never carry a
-- "#", on any realm, so a text holding one names an account and nothing else.
--
-- The allowed field takes both, and both used to be keyed by `normalizeName`,
-- which cuts at the first space: "Real Friend#1234" was keyed "real", and the
-- stranger Real-Ysondre -- any Real, on any realm -- walked in silently, chat,
-- invites and all. Cut by `normalizeCharacterKey` it fares no better, only more
-- quietly: "real-friend#1234" is a key no event of the game can ever produce, so
-- the account it names would stop being allowed at all. The person named an
-- account, and this is how we know.
local function isAccountName(name)
    return type(name) == "string" and name:find("#", 1, true) ~= nil
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

local FILTER_STATE_KEYS = {
    "scope",
    "preset",
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

-- The two switches question 1 and question 2 write. Reading them through these
-- helpers rather than through getEffective is what keeps an unset or corrupted
-- value from becoming a third, undefined mode.
local function getScope()
    return getEffective("filters.scope") == "blockedOnly" and "blockedOnly" or "strangers"
end

local function getPreset()
    return getEffective("filters.preset") == "custom" and "custom" or "all"
end

-- The single reading of "is this filter in force right now". Every decision path
-- goes through it; a raw getEffective("filters.…") on a decision path would
-- publish the stored checkbox instead of the mode the person actually chose.
local isFilterOn
do

-- What the recommended preset applies, whatever is stored underneath. The
-- stored values are kept untouched so switching back to "I choose" restores the
-- boxes the person had ticked.
local PRESET_ALL_ON = {
    groupInvite = true, whisper = true, duel = true, trade = true, guildInvite = true,
}
local PRESET_ALL_OFF = { say = true, yell = true, emote = true }

isFilterOn = function(key)
    if key == "autoTrust" then
        -- Advanced setting, outside question 2 and outside the scope switch.
        return getEffective("filters.autoTrust") == true
    end

    if key == "channelMode" then
        if getScope() == "blockedOnly" then return "none" end
        if getPreset() == "all" then return "none" end
        local mode = getEffective("filters.channelMode")
        if mode ~= "keywords" and mode ~= "all" then return "none" end
        return mode
    end

    -- "Everyone except the people I block": nothing about strangers is filtered,
    -- enhanced instance filtering included. Hiding the whole system category for
    -- someone who asked to filter almost nothing would be a regression.
    if getScope() == "blockedOnly" then return false end

    if key == "strictGroupInviteSystemMessages" then
        return getEffective("filters.strictGroupInviteSystemMessages") == true
            and isFilterOn("groupInvite") == true
    end

    if getPreset() == "all" then
        if PRESET_ALL_ON[key] then return true end
        if PRESET_ALL_OFF[key] then return false end
    end
    return getEffective("filters." .. key) == true
end

end

-- Publishes what the core applies, never the raw stored values: a report or a
-- snapshot showing `whisper = false` while whispers are being filtered sends the
-- reader looking for a bug that is not there.
local function getEffectiveFilterState()
    local filters = {}
    for _, key in ipairs(FILTER_STATE_KEYS) do
        if key == "scope" then
            filters.scope = getScope()
        elseif key == "preset" then
            filters.preset = getPreset()
        else
            filters[key] = isFilterOn(key)
        end
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
ns.deepCopy = deepCopy
ns.fillMissingDefaults = fillMissingDefaults
ns.getEffectiveFilterState = getEffectiveFilterState
ns.isFilterOn = isFilterOn
ns.getScope = getScope
ns.getPreset = getPreset

-- ----------------------------------------------------------------------------
-- The anti-spam setting, and the one question the interface asks about it
-- ----------------------------------------------------------------------------

-- Scoped block. Lua caps a chunk at 200 live registers and this file runs close
-- to it, so what the rest of the addon needs from here leaves through `ns`
-- rather than through a chunk local.
do

-- The eight windows the person can pick, in the order the menu shows them.
-- Reading goes through one function and accepts nothing else: a settings file
-- edited by hand, or written by another build, must answer the default rather
-- than a window nobody ever chose.
local ANTISPAM_INTERVALS = { 300, 600, 1800, 3600, 7200, 14400, 43200, 86400 }
local ANTISPAM_DEFAULT_INTERVAL = 300

ns.ANTISPAM_INTERVALS = ANTISPAM_INTERVALS

local function antiSpamStore()
    local stored = SanctuaryDB and SanctuaryDB.antiSpam
    if type(stored) ~= "table" then return nil end
    return stored
end

function ns.isAntiSpamEnabled()
    local stored = antiSpamStore()
    return (stored ~= nil and stored.enabled == true)
end

function ns.getAntiSpamInterval()
    local stored = antiSpamStore()
    local seconds = stored and stored.intervalSeconds
    for _, value in ipairs(ANTISPAM_INTERVALS) do
        if seconds == value then return value end
    end
    return ANTISPAM_DEFAULT_INTERVAL
end

function ns.setAntiSpamEnabled(value)
    local stored = antiSpamStore()
    if not stored then return end
    stored.enabled = value and true or false
end

function ns.setAntiSpamInterval(seconds)
    local stored = antiSpamStore()
    if not stored then return end
    for _, value in ipairs(ANTISPAM_INTERVALS) do
        if seconds == value then
            stored.intervalSeconds = value
            return
        end
    end
end

-- "The public channels are already all filtered, so there is no repeat left to
-- hide." The interface asks this and nothing else -- never `scope`, `preset` or
-- the raw `channelMode` -- so the greyed-out state and the decision below can
-- never disagree about what is covered.
--
-- `isEnabled()` is not decoration: `isFilterOn` never consults it, so a person
-- who turned Sanctuary off while "Filter everything" was still stored would be
-- told the channels were covered while nothing at all was being filtered.
function ns.isChannelSpamCovered()
    return (isEnabled() and isFilterOn("channelMode") == "all") and true or false
end

end

-- ----------------------------------------------------------------------------
-- Where a pseudo ends and a realm begins -- one rule, one place
-- ----------------------------------------------------------------------------

-- A WoW character name carries neither a space nor a hyphen, so the first of the
-- two separates the pseudo from the realm; the realm may hold more of them and
-- keeps them until `normalizeRealm` folds them away. Answers the two halves,
-- pseudo lower-cased, realm exactly as it was handed over (nil when there is
-- none), and third the pseudo spelled the way it was handed over -- what a panel
-- puts on a chip, since a key is folded and a name on screen is not.
--
-- Leading and trailing separators go first. "Toto-" is the hyphen left under the
-- fingers, not a realm: read literally it used to build the key "toto--testrealm",
-- an entry no event in the game can ever produce. And the space is a separator
-- for the same reason the hyphen is -- "Toto Ysondre" used to be squashed into
-- the single pseudo "totoysondre", keyed "totoysondre-testrealm", when it plainly
-- names a character on Ysondre.
--
-- Both entries showed up in the panel, counted in the tile and armed the guards,
-- and blocked nobody: somebody typing a harasser's name under pressure was told
-- nothing and protected from nothing.
--
-- Answers nil when nothing usable is left ("-", " - "), and every caller refuses
-- the input rather than inventing an entry for it.
--
-- Assigns the forward local declared next to `normalizeName`: the allowed list
-- cuts here too. No `local` on this line, or `normalizeName` loses it.
function splitCharacterName(name)
    local clean = stripWoWFormatting(name)
    if not clean then return nil end
    clean = clean:gsub("^[%s%-]+", ""):gsub("[%s%-]+$", "")
    if clean == "" then return nil end
    local namePart, realmPart = clean:match("^([^%s%-]+)[%s%-](.*)$")
    if not namePart then namePart = clean end
    local typedPart = namePart
    namePart = foldCase(namePart)
    if namePart == "" then return nil end
    return namePart, realmPart, typedPart
end

-- The one shape of a pattern, at the write and at the read alike. `addPattern`
-- stores what this answers, `removePattern` looks up what this answers, and
-- `matchesKeyword` below compares against what this answers -- so a pattern can
-- never be stored under one spelling and searched for under another.
--
-- It deliberately refuses nothing on shape: a settings file written by an
-- earlier build can hold "toto-ysondre" or a pasted BattleTag, and the person
-- has to be able to delete it from the panel. `ns.addPattern` is where a new one
-- is refused.
local function normalizePatternText(text)
    if type(text) ~= "string" then return nil end
    local clean = stripWoWFormatting(text)
    if not clean then return nil end
    clean = foldCase((clean:gsub("%s", "")))
    if clean == "" then return nil end
    return clean
end

ns.normalizePatternText = normalizePatternText

-- Keyword blacklist: blocks names containing any suspect keyword.
-- Private on purpose since 1.0.0: isAlwaysBlocked is the only caller, so a
-- pattern and an exact blocked name can never be tested by different code.
--
-- The pseudo half only, cut by the one rule the key builder uses. The panel
-- promises exactly that -- "a pattern is a piece of text: any name containing it
-- is blocked", "text to look for in names" -- and searching the whole string
-- broke the promise in the worst direction. Every name reaching a decision in a
-- random dungeon arrives realm-qualified, so the pattern "illidan" matched
-- "Healer-Illidan" on his realm alone: an allowed player -- a friend, a group
-- member, a dungeon companion -- cut off with no popup, no sound and no chat
-- line, and the always-blocked door beats every allow list, so nothing caught
-- him. A realm is not a pseudo and was never what the person typed a pattern
-- against.
local function matchesKeyword(name)
    if not name or not SanctuaryDB or not SanctuaryDB.keywords then return false, nil end
    local nameOnly = splitCharacterName(name)
    if not nameOnly then return false, nil end

    for _, keyword in ipairs(SanctuaryDB.keywords) do
        -- Read by the same rule that wrote it. The fold and the space strip used
        -- to be copied out here, so the stored spelling and the searched
        -- spelling were two pieces of code that had to agree by hand.
        local cleanKeyword = normalizePatternText(keyword)
        if cleanKeyword and nameOnly:find(cleanKeyword, 1, true) then
            return true, keyword
        end
    end
    return false, nil
end

-- ----------------------------------------------------------------------------
-- The always-blocked door
-- ----------------------------------------------------------------------------

-- One spelling for a realm, whoever hands it over. `GetNormalizedRealmName`
-- already drops spaces and hyphens -- "Azjol-Nerub" comes back "AzjolNerub" --
-- while the realm half of `UnitName` and `gameAccountInfo.realmName` keep them.
-- Two halves of the same key built from two of those sources never met: on a
-- hyphenated realm a blocked character walked straight in, because the lookup
-- spelled his realm one way and his entry the other.
local function normalizeRealm(realm)
    if type(realm) ~= "string" then return nil end
    realm = foldCase((realm:gsub("[%s%-']", "")))
    if realm == "" then return nil end
    return realm
end

-- "Is this the player themselves". One rule, written here because it is made of
-- the two rules directly above it and of nothing else: `splitCharacterName`
-- says where the pseudo ends, `normalizeRealm` says how a realm is spelled.
--
-- It used to carry its own copy of both -- a hand-written pattern that cut on
-- the hyphen alone, so "Toto Ysondre" was compared whole and never recognised,
-- and a second realm fold. Two copies of one rule is the fault this release went
-- looking for everywhere else.
--
-- A realm on the sender is honoured when there is one, so a namesake on another
-- realm is not mistaken for the player; a bare name is the player's own realm,
-- which is what the game hands over when both sides share it.
--
-- Nothing Sanctuary does may touch what the player says to themselves: this is
-- the single site that answers that question, `decideChat` is its only caller
-- in this file, and the right-click menu asks it from the interface file.
--
-- Published on `ns` rather than kept as a chunk local, like the list writers
-- below: Lua caps a chunk at 200 live registers, this one runs at 184, and a
-- rule with one caller does not need to hold one of the sixteen left.
function ns.isSelf(sender)
    local senderName, senderRealm = splitCharacterName(sender)
    if not senderName then return false end

    local playerName, playerRealm
    if UnitFullName then
        playerName, playerRealm = UnitFullName("player")
    end
    playerName = playerName or UnitName("player")
    playerRealm = playerRealm or getPlayerRealm()
    -- Folded by the same rule the keys are built with, so an accented pseudo is
    -- recognised as the player's own on both sides of the comparison.
    if not playerName or senderName ~= foldCase(playerName) then return false end

    local realm = normalizeRealm(senderRealm)
    if not realm then return true end
    return realm == normalizeRealm(playerRealm)
end


-- One key shape for both hand-written lists, and it always carries a realm:
-- "name-realm". A name typed with no realm means the realm the player is on --
-- what WoW itself shows in an invite box when the other player shares it -- so
-- the key says which realm rather than standing for all of them at once.
--
-- The realm is engraved at the write and never read back from the game
-- afterwards (decision 119): "imagine la personne change de serveur, en interne
-- on va re-rooter avec le nouveau serveur, c'est pas bon". An entry names a
-- character on a realm, not "whoever bears that name where I happen to stand".
-- The blocked list has been keyed this way since 1.0.0; the allowed list is the
-- half this rule was generalised for, and there is deliberately no second one.
--
-- Where the two halves come from is `splitCharacterName`, the one rule the
-- pattern test shares: a key and a pattern can never disagree about where a
-- pseudo ends. An entry it refuses -- nothing left but separators -- has no key,
-- so `ns.addBlocked` answers false and writes nothing.
--
-- Answers nil while the player's realm is still unknown, which is only true
-- before the world is entered: no invitation, whisper or name test reaches this
-- code that early, and a key invented then would be an entry no later lookup
-- could match.
local function normalizeCharacterKey(name)
    local namePart, realmPart = splitCharacterName(name)
    if not namePart then return nil end
    local realm = normalizeRealm(realmPart) or normalizeRealm(getPlayerRealm())
    if not realm then return nil end
    return namePart .. "-" .. realm
end

-- One lookup, on the one key shape. Blocking "Toto" blocks the Toto on your own
-- realm -- the one an invitation means when it shows a bare name -- and nobody
-- else. There is no bare-key fallback any more: a bare key answered for every
-- realm at once, so a namesake in your own guild was cut off in silence because
-- somebody else's Toto, on another realm, had been blocked.
local function isBlockedName(name)
    if not SanctuaryDB or type(SanctuaryDB.blockedNames) ~= "table" then return nil end
    local key = normalizeCharacterKey(name)
    if not key then return nil end
    if SanctuaryDB.blockedNames[key] then return key end
    return nil
end

-- Computed rather than cached: `next` answers in constant time, and a cached
-- flag would go stale the moment anything writes SanctuaryDB directly -- which
-- the schema reset, the harness and a hand-edited settings file all do.
local function hasAlwaysBlockedEntries()
    if not SanctuaryDB then return false end
    local blocked = SanctuaryDB.blockedNames
    if type(blocked) == "table" and next(blocked) ~= nil then return true end
    local keywords = SanctuaryDB.keywords
    return type(keywords) == "table" and next(keywords) ~= nil
end

-- Forward declaration: the Battle.net account <-> character map is filled by
-- rebuildWhitelist, further down.
local ensureWhitelistCache

-- "Which Battle.net account is playing this character". Attribution only: it
-- names the account behind a character on screen -- the tester's answer and the
-- allowed panel's line -- and decides nothing. The blocked path asks its own
-- question, `bnetAccountBlockingCharacter` just below, and asks it more strictly
-- than this: a wrong answer here mislabels a line, a wrong answer there refuses
-- somebody the right to block their harasser.
--
-- Two lookups, stopping at the first hit:
--
--   1. the realm-qualified key -- the only one that tells two namesakes apart,
--      and the one a bare name resolves to on the player's own realm;
--   2. the bare name -- what the map holds for a friend whose realm the roster
--      did not give, and what `rebuildWhitelist` neutralises when two friends
--      collide on it.
--
-- Step 2 earns its place because PARTY_INVITE_REQUEST, DUEL_REQUESTED and
-- TRADE_SHOW hand over a name stripped of its realm when the other player
-- shares ours, and an offline friend often has no realm to record. Without it
-- the tester credited a character to whichever namesake the roster happened to
-- list first.
local function bnetAccountForCharacter(name)
    local map = Sanctuary.bnetAccountByCharacter
    if not map then return nil end

    local fullKey = normalizeCharacterKey(name)
    if fullKey then
        local account = map[fullKey]
        if account then return account end
    end

    local bareKey = normalizeName(name)
    if bareKey and bareKey ~= fullKey then
        local account = map[bareKey]
        if account then return account end
    end

    return nil
end

-- "Is this character a Battle.net friend's, closely enough to refuse to block
-- them" -- decision 100, the panel's sentence, and `ns.addBlocked`'s second
-- gate. Deliberately not the function above.
--
-- Attribution can afford to guess: crediting a stranger's character to a friend
-- puts the wrong name on one line of a panel. Refusing cannot. Asked with the
-- tolerant lookup, a harasser who merely shares a pseudo with a friend's
-- character -- on ANOTHER realm -- could not be blocked at all, neither in the
-- field nor from the right-click menu, and the add-on answered with the
-- Battle.net sentence, naming a person the player has never met. That is the
-- residual same-name cross-realm risk PROJECT_MEMORY records; the realm was the
-- way out of it, and closing that door left no way out at all.
--
-- So the realm-qualified key first and always -- the one shape that tells two
-- namesakes apart -- and the bare pseudo only when neither side named a realm:
-- not the roster, which is what the second map holds, and not the person typing,
-- which is what `splitCharacterName` answers. Both halves are needed. Restricting
-- the map alone left the question tolerant: asked through `normalizeName`, which
-- drops whatever realm was typed, one friend the roster had named without a
-- realm made his namesake unblockable everywhere -- "Norealmchar-Hyjal" refused
-- with the Battle.net sentence, naming a person the player has never met, and no
-- spelling left that would take. That is the same door the realm-qualified key
-- was put here to keep open.
--
-- Still failing open: a roster that has not answered yet knows nobody and
-- refuses nobody.
local function bnetAccountBlockingCharacter(name)
    local map = Sanctuary.bnetAccountByCharacter
    if map then
        local fullKey = normalizeCharacterKey(name)
        if fullKey then
            local account = map[fullKey]
            if account then return account end
        end
    end

    local unrealmed = Sanctuary.bnetAccountByCharacterNoRealm
    if unrealmed then
        -- Both halves from the one rule, and a realm read the way the key reads
        -- it: "Toto-" and "Toto " carry no realm any more than "Toto" does.
        local bareKey, realmPart = splitCharacterName(name)
        if bareKey and not normalizeRealm(realmPart) then
            local account = unrealmed[bareKey]
            if account then return account end
        end
    end

    return nil
end

-- The single gate every decision path asks first. It beats every trust source
-- and every filter setting, in both scopes -- that is the whole point of the
-- list.
--
-- It answers about WoW characters and nothing else. See the Battle.net
-- invariant next to `bnetWhisperFilter`: the blocked list and the patterns never
-- reach the Battle.net channel, and no account name is ever resolved into a
-- character here or the other way round. A Battle.net friend whose character is
-- typed into the blocked list is blocked on the WoW paths -- that is that
-- character being blocked, not the account.
local function isAlwaysBlocked(name)
    if name == nil then return false, nil, nil end
    if not hasAlwaysBlockedEntries() then return false, nil, nil end

    local blockedKey = isBlockedName(name)
    if blockedKey then
        local data = SanctuaryDB.blockedNames[blockedKey]
        local label = (type(data) == "table" and data.displayName) or blockedKey
        return true, "blocked_name", label
    end
    local matched, keyword = matchesKeyword(name)
    if matched then return true, "keyword", keyword end
    return false, nil, nil
end

-- The key `ns.addAllowed` would write for this text -- an account keyed whole,
-- a character keyed "pseudo-realm" -- and nil when nothing usable is left.
--
-- One rule, one place, exactly like the blocked side just above -- and since
-- decision 119 it is literally the same rule: a character typed into "Toujours
-- autorises" is keyed with its realm, engraved at the write, just as one typed
-- into "Toujours bloques" is. A bare key stood for the same pseudo on every
-- realm at once, which a server transfer then re-rooted onto whatever realm the
-- player had moved to.
--
-- The account is the one entry with no realm, and there is nothing to engrave:
-- a Battle.net account is not on a realm at all. Keyed whole, the way the
-- account cache keys it -- cut, "Real Friend#1234" became "real" and allowed
-- every Real of every realm without a word.
--
-- On `ns` for the same reason `ns.isSelf` is, one screen up: one caller here,
-- one caller in the interface, and no register to spare.
function ns.findAllowedKey(name)
    local clean = stripWoWFormatting(name)
    if not clean or clean:gsub("%s", "") == "" then return nil end
    return isAccountName(clean) and normalizeBNetName(clean) or normalizeCharacterKey(clean)
end

-- What a character entry reads as on screen: "Pseudo-Royaume", always, whatever
-- the person typed. Decision 119 puts the realm in every key; a panel that then
-- shows "Kadaj" alone tells the reader less than the add-on knows, and after a
-- transfer it would tell them something false -- the entry names a character on
-- the realm it was added from, not on the one they are standing on now.
--
-- Built from the KEY, which is the record, and not from the game: what is on the
-- chip is what the lookup will match. The pseudo keeps the capital the person
-- typed (`splitCharacterName`'s third answer, the folded key being no way to
-- write a name), and the realm is the typed one when there was one, so
-- "Toto-Azjol-Nerub" stays readable rather than coming back "Toto-Azjolnerub".
--
-- Accounts pass through untouched: a BattleTag has no realm to add.
function ns.qualifiedDisplayName(key, displayName)
    local raw = displayName
    if type(raw) ~= "string" or raw:gsub("%s", "") == "" then raw = key end
    if type(raw) ~= "string" then return nil end
    if isAccountName(raw) or (type(key) == "string" and isAccountName(key)) then return raw end

    local _, typedRealm, pseudo = splitCharacterName(raw)
    if not pseudo then return raw end

    local realm = type(key) == "string" and key:match("^[^%-]+%-(.+)$") or nil
    -- The realm as the person wrote it, but only where it is the realm the key
    -- actually holds: a display name and a key that disagree means a settings
    -- file somebody edited by hand, and the key is the half the decision reads.
    if typedRealm and normalizeRealm(typedRealm)
        and (realm == nil or normalizeRealm(typedRealm) == realm) then
        return pseudo .. "-" .. typedRealm
    end
    if not realm then return raw end
    -- The key holds a folded realm. Spelled back the way the client spells it
    -- when it is the player's own -- the common case, a name typed with no realm
    -- -- and otherwise with a capital, since "kadaj-ysondre" on a chip reads as a
    -- bug rather than as a realm. `%l` is ASCII under Lua's C locale, so a
    -- cyrillic realm is left exactly as it is instead of being cut mid-character.
    local own = getPlayerRealm()
    if own ~= "" and normalizeRealm(own) == realm then return pseudo .. "-" .. own end
    local first = realm:match("^%l")
    if first then realm = first:upper() .. realm:sub(2) end
    return pseudo .. "-" .. realm
end

ns.normalizeCharacterKey = normalizeCharacterKey
-- The KEY that answers, not just whether one does: the right-click menu has to
-- remove the entry the lookup actually found, and it asks here rather than
-- deriving the key itself so that the menu and the filters can never disagree
-- about who is blocked.
ns.findBlockedKey = isBlockedName
ns.hasAlwaysBlockedEntries = hasAlwaysBlockedEntries
ns.isAlwaysBlocked = isAlwaysBlocked

-- Armed means "this guard has to be in place", which is not the same as "this
-- filter is ticked": one always-blocked name is enough to require the popup mask
-- and the sound guard even in the mode where nothing else is filtered. Empty
-- lists arm nothing, so a person who blocks nobody keeps WoW's native behaviour
-- down to the sound.
local FILTER_KEY_BY_POPUP = {
    PARTY_INVITE = "groupInvite",
    DUEL_REQUESTED = "duel",
}

local function isProtectionArmed(kind)
    if not isEnabled() then return false end
    local key = FILTER_KEY_BY_POPUP[kind] or kind
    return isFilterOn(key) == true or hasAlwaysBlockedEntries()
end

ns.isProtectionArmed = isProtectionArmed

-- Forward declarations for helpers used before their concrete section.
local debugLog, countBNetWithCharName, captureDebugSnapshot, isBNetSenderInGroup
local getDebugLogStats, resetDebugLog
local chatOutputWrapped
local pendingPopupDecisions
local unmaskVisiblePopup
local capturePartyInviteOriginalSound
-- Declared here rather than with the rest of the sound machinery: the always-
-- blocked writers, far above that section, have to re-post the guards.
local refreshInviteSoundMuteState
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
-- Which of those account keys an ACCOUNT really named: a display name carrying
-- a "#", a Battle.net friend read off the roster. The account cache has a second
-- writer -- the display name of a manual CHARACTER entry, which is how a
-- one-word account name typed into the allowed field lets its whispers through
-- -- and that half must never answer for a WoW character name. `classifyName`
-- is the reader; `isBNetWhitelisted`, which serves CHAT_MSG_BN_WHISPER, is not.
Sanctuary.bnetWhitelistAccountKeys = {}
-- Battle.net identity, both ways. Sanctuary already reads which character each
-- friend is on; recording it here is what lets the always-blocked list and the
-- name tester resolve an account from a character and back.
Sanctuary.bnetCharacterByAccount = {}
Sanctuary.bnetAccountByCharacter = {}
-- The realm-less half of that map, kept apart on purpose: the characters the
-- roster named without a realm, and only those. `bnetAccountBlockingCharacter`
-- is the one reader -- see the comment there for why refusing needs a stricter
-- map than attributing does.
Sanctuary.bnetAccountByCharacterNoRealm = {}
-- The same character, spelled for a reader instead of for a lookup: the realm
-- is what tells two namesakes apart in a key, and noise on a panel line.
Sanctuary.bnetCharacterDisplayByAccount = {}
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
    -- Filled beside `bnetCache`, never merged into it: which keys of that cache
    -- an account really named. Not a flag on the source table, because the
    -- source table is first-writer-wins and either writer can come first -- a
    -- friend whose account name is one word must go on answering whether or not
    -- somebody also typed that word into the allowed field.
    local bnetAccountKeys = {}
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
    local characterByAccount = {}
    local characterDisplayByAccount = {}
    local accountByCharacter = {}

    -- A character name answers with one account, or with nobody. Two Battle.net
    -- friends whose characters share a name on two realms collide on the bare
    -- key, and letting the last one written win means the roster order decides
    -- which account answers for both: in one order the blocked account's
    -- character walks through, in the other an allowed friend is blocked in his
    -- place. Both break a product rule, so an ambiguous key resolves to nobody
    -- and the "Name-Realm" keys, which stay distinct, keep answering.
    local accountKeyByCharacter = {}
    local function noteAccountInto(store, held, key, accountName, accountKey)
        if not key or not accountName or not accountKey then return end
        local seen = held[key]
        if seen == nil then
            held[key] = accountKey
            store[key] = accountName
        elseif seen ~= accountKey then
            held[key] = false
            store[key] = nil
        end
    end
    local function noteAccountForCharacter(key, accountName, accountKey)
        noteAccountInto(accountByCharacter, accountKeyByCharacter,
            key, accountName, accountKey)
    end

    -- The same record, restricted to the characters the roster named without a
    -- realm. Same collision rule, its own store: `bnetAccountBlockingCharacter`
    -- reads it to know when a bare pseudo is all there ever was, rather than
    -- treating every bare pseudo as if it were.
    local accountByCharacterNoRealm = {}
    local accountKeyByCharacterNoRealm = {}
    local function noteUnrealmedCharacter(key, accountName, accountKey)
        noteAccountInto(accountByCharacterNoRealm, accountKeyByCharacterNoRealm,
            key, accountName, accountKey)
    end

    local function noteSource(store, labelStore, key, source, displayName)
        if not key or store[key] then return end
        store[key] = source
        if displayName and displayName ~= key then
            labelStore[key] = displayName
        end
    end

    -- The automatic sources, and only those: a roster name, keyed on its bare
    -- pseudo. The manual entries have their own writer just below.
    --
    -- `bareNameIsOurRealm` says what a roster handing over a pseudo with no
    -- realm means by it. True of the guild, of character friends and of the
    -- group: all three are read on the realm the player stands on, and WoW
    -- qualifies the names that are not. Left unsaid it means "no idea", which
    -- is the only safe default -- see the deduplication below.
    local function addCharacterName(name, source, displayName, bareNameIsOurRealm)
        -- One cut, both halves. The first is what `normalizeName` answers -- the
        -- bare pseudo this cache is keyed on -- and the second is what the
        -- deduplication just below has to know before it trusts a realm.
        local normalized, realmPart = splitCharacterName(name)
        if not normalized then return end
        -- A contact the person also typed by hand keeps their own entry, and
        -- gets one line, not two. First-writer-wins used to do that on its own,
        -- when both halves were keyed the same way; since decision 119 the
        -- manual key carries a realm and the roster key cannot, so the same
        -- person would show up twice -- once under "Added by you", once in the
        -- roster group -- and be counted twice in the tile. Asked on the
        -- qualified key, so a namesake on ANOTHER realm is left alone: he is
        -- not the person who was typed in.
        --
        -- INVARIANT -- only where the two keys are KNOWN to name one person. A
        -- bare pseudo has no realm of its own, so `normalizeCharacterKey` fills
        -- the player's in; the Battle.net roster is the one source for which
        -- that guess is wrong, since it names the realm on the side and a
        -- friend may be playing anywhere. For that friend the bare key is the
        -- only one the WoW channel ever holds: dropped in favour of a
        -- namesake's manual entry, adding him to the allowed list is what takes
        -- him off it -- whisper discarded, invitation and duel refused with no
        -- popup and no sound, while the panel goes on showing him allowed.
        local manualKey = (normalizeRealm(realmPart) or bareNameIsOurRealm)
            and normalizeCharacterKey(name) or nil
        if manualKey and sources[manualKey] then return end
        cache[normalized] = true
        noteSource(sources, sourceLabels, normalized, source,
            displayName or (type(name) == "string" and name or nil))
    end

    -- `namesAnAccount` tells the two writers of this cache apart. True for a
    -- text that names an account and nothing else -- a "#" tag typed into the
    -- allowed field, a friend off the Battle.net roster. False for the display
    -- name of a manual CHARACTER entry, fed in so a one-word account name typed
    -- into that field still lets its whispers through.
    local function addBNetAccountName(name, source, displayName, namesAnAccount)
        local normalized = normalizeBNetName(name)
        if normalized then
            bnetCache[normalized] = true
            if namesAnAccount then bnetAccountKeys[normalized] = true end
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

        -- An entry naming an account never joins the character cache. Cut to
        -- its first word by `normalizeName` it would allow whoever happens to
        -- share that word, on every realm, in silence -- and a settings file
        -- written before `addAllowed` learned to tell the two apart still holds
        -- the cut key with the tagged name beside it, so the display name is
        -- read here too rather than the key alone.
        --
        -- It is still noted as a source, under a key carrying its "#" that no
        -- name coming out of the game can ever equal: the tile counts the
        -- manual entries from this table, and dropping the entry from it would
        -- have taken the account off the count while its chip stayed on the
        -- panel. Allowed it remains -- through the account cache, which is
        -- where an account belongs.
        local accountName = (isAccountName(label) and label)
            or (isAccountName(key) and key)
            or nil
        if accountName then
            noteSource(sources, sourceLabels, normalizeBNetName(accountName), source, label)
            if manualEntryAllowsBNet(data) then
                addBNetAccountName(accountName, source, label, true)
            end
            return
        end

        -- The stored key goes in as it stands, and nothing here derives a second
        -- one. `ns.addAllowed` engraved the realm when the person typed the name
        -- (decision 119); re-cutting the display name at every rebuild would
        -- hand the cache a key built from the realm the player is on NOW, which
        -- is exactly the re-rooting the decision forbids -- the entry would
        -- follow them across a transfer instead of staying on the character it
        -- names. `classifyName` reads this key shape first.
        cache[key] = true
        noteSource(sources, sourceLabels, key, source, label)

        -- The display name still feeds the ACCOUNT cache: typing a one-word
        -- Battle.net account name into the allowed field is the documented way
        -- to let its whispers through, and that half has no realm to engrave.
        --
        -- Fed WITHOUT `namesAnAccount`: nothing here proves the person meant an
        -- account rather than the character they typed. A bare display name
        -- lands under a bare key, and `classifyName` reading that key would
        -- undo decision 119 through the back door -- after a transfer, an entry
        -- engraved "Kadaj-Ysondre" would go on answering for the Kadaj of the
        -- new realm. Only the Battle.net channel reads this half.
        if manualEntryAllowsBNet(data) then
            addBNetAccountName((type(data) == "table" and data.displayName) or key,
                source, label)
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
            -- A guild is read from inside it: a mate the roster names without a
            -- realm shares the player's own.
            if name then addCharacterName(name, "guild", nil, true) end
        end
    end)

    -- Battle.net friends (always whitelisted): cache both the account display
    -- name (used by CHAT_MSG_BN_WHISPER) and the currently visible character.
    pcall(function()
        local numFriends = BNGetNumFriends() or 0
        for i = 1, numFriends do
            local info = getBNetFriendInfo(i)
            if info then
                addBNetAccountName(info.accountName, "bnet", nil, true)
                local gameInfo = info.gameAccountInfo
                if gameInfo and gameInfo.characterName and gameInfo.characterName ~= "" then
                    -- No fourth argument, and that is the point: this roster
                    -- names the realm on the side, in `realmName` just below, so
                    -- the bare pseudo it hands over says nothing about where the
                    -- friend is playing.
                    addCharacterName(gameInfo.characterName, "bnet", info.accountName)
                    -- Keyed on the blocked-list key shape so a character seen on
                    -- any WoW path resolves to its account under one rule, with
                    -- the realm spelled the single way `normalizeRealm` spells
                    -- it -- `gameAccountInfo.realmName` keeps the hyphen of an
                    -- Azjol-Nerub, `GetNormalizedRealmName` does not.
                    local characterName = gameInfo.characterName
                    local realmName = gameInfo.realmName
                    local qualified = nil
                    if characterName:find("-", 1, true) then
                        qualified = characterName
                    elseif type(realmName) == "string" and realmName ~= "" then
                        qualified = characterName .. "-" .. realmName
                    end
                    if qualified then characterName = qualified end
                    local accountKey = normalizeBNetName(info.accountName)
                    -- Both spellings are recorded. The bare one is what a
                    -- same-realm event carries, the qualified one is what tells
                    -- two namesakes apart -- and it is only recorded when the
                    -- roster actually gave a realm, so an offline friend is
                    -- never claimed to be playing on ours.
                    local fullKey = qualified and normalizeCharacterKey(qualified) or nil
                    local bareKey = normalizeName(characterName)
                    if accountKey then
                        characterByAccount[accountKey] = characterName
                        -- What the panel prints. The realm earns its place in
                        -- the key, not on the line: "Bnetchar-Ysondre · Real
                        -- Friend#1234" is the same contact said twice.
                        characterDisplayByAccount[accountKey] = gameInfo.characterName
                        noteAccountForCharacter(fullKey, info.accountName, accountKey)
                        if bareKey ~= fullKey then
                            noteAccountForCharacter(bareKey, info.accountName, accountKey)
                        end
                        -- No realm anywhere for this character: the bare key is
                        -- everything the roster gave, so it is the only key a
                        -- refusal can honestly be built on for this friend.
                        if not fullKey then
                            noteUnrealmedCharacter(bareKey, info.accountName, accountKey)
                        end
                    end
                end
            end
        end
    end)

    -- Character friends (always whitelisted)
    pcall(function()
        local numFriends = C_FriendList.GetNumFriends() or 0
        for i = 1, numFriends do
            local info = C_FriendList.GetFriendInfoByIndex(i)
            -- Character friends are per-character too: no realm means ours.
            if info and info.name then
                addCharacterName(info.name, "friend", nil, true)
            end
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
                    -- `UnitName` gives the realm exactly when it is not ours, so
                    -- what is left bare here is on ours.
                    addCharacterName(name, "group", nil, true)
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
    Sanctuary.bnetWhitelistAccountKeys = bnetAccountKeys
    Sanctuary.bnetCharacterByAccount = characterByAccount
    Sanctuary.bnetCharacterDisplayByAccount = characterDisplayByAccount
    Sanctuary.bnetAccountByCharacter = accountByCharacter
    Sanctuary.bnetAccountByCharacterNoRealm = accountByCharacterNoRealm
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

ensureWhitelistCache = function()
    if Sanctuary.whitelistDirty then
        rebuildWhitelist()
    end
end

-- Which trust source answers for this character, and under which key. Two key
-- shapes share the one cache since decision 119: what the person typed, keyed
-- "pseudo-realm" by `ns.addAllowed` and read back exactly as it was written, and
-- the automatic sources, keyed on the bare pseudo by `normalizeName` because a
-- roster re-answers whenever it changes.
--
-- The qualified key is asked first, and that order is the rule, not a detail: a
-- name the person typed by hand keeps its own label when a roster happens to
-- hold them too, which is what the panel and the tester both promise.
--
-- The bare fallback is what lets the automatic sources answer at all. It cannot
-- widen a typed entry: a manual key always carries its "-realm" and a roster key
-- never can, since `splitCharacterName` cuts the pseudo at the first separator.
-- So a harasser on another realm who shares a pseudo with a name in "Toujours
-- autorises" is not allowed by it -- which is the whole of decision 119.
local function findWhitelistSource(name)
    local sources = Sanctuary.whitelistSources
    if not sources then return nil, nil end
    local fullKey = normalizeCharacterKey(name)
    if fullKey and sources[fullKey] then return sources[fullKey], fullKey end
    local bareKey = normalizeName(name)
    if bareKey and sources[bareKey] then return sources[bareKey], bareKey end
    return nil, nil
end

-- Which of the three tiers a name falls into, and why. The whole 1.0.0 model is
-- this function: always blocked, else always allowed, else unknown -- and only
-- the third tier depends on a setting.
--
-- Attribution when several trust sources allow the same person is not recomputed
-- here: the caches record the first writer, and the manual lists are filled
-- first, so a name the person typed keeps its own label even when they are also
-- in the guild.
local function classifyName(name)
    local blocked, reason, detail = isAlwaysBlocked(name)
    if blocked then
        return { verdict = "always_blocked", list = reason, detail = detail }
    end

    ensureWhitelistCache()

    local source, characterKey = findWhitelistSource(name)
    if source then
        local label = Sanctuary.whitelistLabels[characterKey]
        -- A roster label is keyed on the bare name and keeps its first writer,
        -- which for two Battle.net friends playing a namesake means one account
        -- is printed for both -- and the one printed can be the account the
        -- person has just blocked, shown as the REASON the other one is allowed.
        -- The "Name-Realm" keys stay distinct, so ask the account map instead.
        if source == "bnet" then
            local account = bnetAccountForCharacter(name)
            if account then label = account end
        end
        return { verdict = "always_allowed", list = source, detail = label }
    end

    -- Last resort: the account half. A Battle.net account has no realm, so its
    -- key is the whole display name -- and a name is asked here only when the
    -- character caches above have said nobody.
    --
    -- Restricted to the keys an account really named (`bnetWhitelistAccountKeys`)
    -- and that restriction is the whole of it: the same cache is also fed from
    -- the display name of a manual CHARACTER entry, so that a one-word account
    -- name typed into the allowed field lets its whispers through. Read here
    -- too, that half made a realm-less "Kadaj" answer for an entry engraved
    -- "kadaj-ysondre" -- decision 119's re-rooting, walked around through the
    -- account door, and always in the direction that lets a stranger in. The
    -- Battle.net channel is untouched: `isBNetWhitelisted` reads the cache
    -- itself and knows nothing of this table.
    local accountKey = normalizeBNetName(name)
    local namesAnAccount = accountKey and Sanctuary.bnetWhitelistAccountKeys
        and Sanctuary.bnetWhitelistAccountKeys[accountKey] == true
    local bnetSource = namesAnAccount and Sanctuary.bnetWhitelistSources[accountKey] or nil
    if bnetSource then
        local label = Sanctuary.bnetWhitelistLabels[accountKey] or name
        return { verdict = "always_allowed", list = bnetSource, detail = label }
    end

    return { verdict = "unknown", list = nil, detail = nil }
end

-- Single source of truth for character-name decisions. Signature unchanged --
-- twenty-one call sites read it as (shouldBlock, reason, detail).
local function getCharacterDecision(name)
    local classification = classifyName(name)
    if classification.verdict == "always_blocked" then
        return true, classification.list, classification.detail
    end
    if classification.verdict == "always_allowed" then
        return false, "whitelist", nil
    end
    if getScope() == "blockedOnly" then
        return false, "open_scope", nil
    end
    return true, "not_whitelisted", nil
end

-- ----------------------------------------------------------------------------
-- One decision per interaction, one decision per message
-- ----------------------------------------------------------------------------

-- The one decision order, for every attributable path there is:
--   isAlwaysBlocked(name) -> the gate for this kind -> getCharacterDecision(name)
-- The always-blocked list comes before the gate on purpose: it is what makes it
-- beat a filter the person unticked.
--
-- Answers four values, `(block, reason, detail, gateOpen)`. `gateOpen` is what a
-- debug entry publishes as `filterEnabled`; a caller that wants three reads
-- three, which is what the four interaction handlers do.
--
-- The gate is not the same question for every kind, and this is the only place
-- that knows which:
--   * `group` -- never open. Group, raid and instance chat is filtered for the
--     always-blocked list and nothing else, whatever is ticked.
--   * `channel` -- the three-mode setting, open at "all" alone.
--   * everything else -- the checkbox for that kind, popup names mapped first.
local function decideInteraction(kind, name)
    local gateOpen
    if kind == "group" then
        gateOpen = false
    elseif kind == "channel" then
        gateOpen = isFilterOn("channelMode") == "all"
    else
        gateOpen = isFilterOn(FILTER_KEY_BY_POPUP[kind] or kind) == true
    end

    local blocked, reason, detail = isAlwaysBlocked(name)
    if blocked then return true, reason, detail, gateOpen end
    if not gateOpen then return false, "filter_off", nil, false end
    local shouldBlock, decisionReason, decisionDetail = getCharacterDecision(name)
    return shouldBlock, decisionReason, decisionDetail, true
end

-- What the debug log calls a block. "blocked_name" gets its own word: reading
-- BLOCK_NOT_WHITELISTED on someone the person blocked by hand would send a
-- reader looking through the wrong list.
local function describeBlockAction(shouldBlock, reason)
    if not shouldBlock then return "ALLOW" end
    if reason == "keyword" then return "BLOCK_KEYWORD" end
    if reason == "blocked_name" then return "BLOCK_BLOCKED_NAME" end
    return "BLOCK_NOT_WHITELISTED"
end

-- The log's `keyword` column means "the pattern that matched", nothing else. An
-- exact blocked name is not a pattern and must not be exported as one.
local function keywordOf(reason, detail)
    if reason == "keyword" then return detail end
    return nil
end

-- INVARIANT, and the whole point of this release: `isSelf`, `isAlwaysBlocked`,
-- `getCharacterDecision` and `isFilterOn` are not called on a message path
-- anywhere but in `decideInteraction`, `decideChat` and `decideBNetWhisper`. A
-- new condition is posed in the decision, never in a consumer.
--
-- Every chat message used to be judged twice -- once by the filter, deciding
-- whether the line shows, once by the event handler, deciding what is logged,
-- counted, announced and closed -- and the two copies spelled the same order
-- out. A fix landed on one of the two had one chance in two of landing on the
-- right one; that happened three times in this release, and the last of them
-- was a player's note to themselves swallowed by the handler while the filter
-- let it through. The body where a guard can be forgotten no longer exists:
-- filters and handlers are generated from `CHAT_KINDS`, out of this function.
--
-- `reason` says what happened to callers: "disabled" and "self" mean nothing was
-- decided and nothing at all is to be written, "filter_off" means the gate is
-- shut, anything else is a decision.
local function decideChat(kind, sender)
    if not isEnabled() then return false, "disabled", nil, false end
    -- Whispering yourself is a real thing people do -- a note, a link kept for
    -- later -- and Sanctuary may never touch what the player says to themselves.
    if ns.isSelf(sender) then return false, "self", nil, false end
    return decideInteraction(kind, sender)
end

-- Battle.net whispers use account display names, not character names.
--
-- INVARIANT -- Sanctuary never blocks anyone on Battle.net. The always-blocked
-- list and the patterns are deliberately absent from this path, and from every
-- other Battle.net one. Adding a friend to Battle.net is an act of trust the
-- person already performed, in a client Sanctuary does not own; cutting one is
-- done there too, by removing or blocking the account. An add-on that silently
-- swallowed a Battle.net friend's whisper would leave the person waiting for an
-- answer that never comes, with nothing on screen to explain it -- and no way to
-- undo it from Battle.net, where they would look first.
--
-- So the only question asked here is the whitelist one: is the account a
-- Battle.net friend, or in the current group. The blocked list holds WoW
-- characters, and reaches them on the WoW paths only.
--
-- Answers `(block, reason, info)`. `info` carries everything the debug entry
-- publishes, so the filter and the handler cannot describe one whisper two ways.
-- The sender is resolved before the checkbox is read, which costs one
-- `GetAccountInfoByID` per ChatFrame while the whisper filter is unticked: the
-- price of the two paths asking one function rather than each their own.
local function decideBNetWhisper(sender, ...)
    local bnetSender = resolveBNetWhisperSender(sender, ...)
    local decisionName = bnetSender.accountName or sender
    local info = {
        accountName = decisionName,
        rawSender = bnetSender.rawSenderText,
        bnetSenderID = bnetSender.bnSenderIDState,
        bnetResolvedByID = bnetSender.resolvedByID,
        bnetWhitelisted = false,
        inGroup = false,
    }

    if not isEnabled() then return false, "disabled", info end
    if isFilterOn("whisper") ~= true then return false, "filter_off", info end

    info.bnetWhitelisted = isBNetWhitelisted(decisionName) and true or false
    if info.bnetWhitelisted then return false, "bnet_whitelist", info end

    info.inGroup = (isBNetSenderInGroup and isBNetSenderInGroup(decisionName)) and true or false
    if info.inGroup then return false, "bnet_group", info end

    return true, "not_whitelisted", info
end

ns.classifyName = classifyName
ns.decideChat = decideChat

-- ----------------------------------------------------------------------------
-- Anti-spam of the public channels -- around the decision, never inside it
-- ----------------------------------------------------------------------------

-- The three steps of the core answer "may this person reach me". This block
-- answers a different question, and only once the first has already said yes:
-- "have I just read this exact line from this exact stranger". So it is written
-- around `decideChat`, which is called here unchanged and exactly once.
--
-- WoW hands one message to N consumers: the registered chat filter is invoked
-- once per ChatFrame, and the event handler is invoked once. The filter decides
-- whether the line shows and must stay free of side effects; the handler is the
-- one that journals. Splitting the work that way is what the two functions
-- published here are:
--
--   * `resolveChatDecision` -- pure but for its memo. Every consumer may call it,
--     in any order, and gets the same verdict for the same physical message.
--   * `commitChatDecision` -- the handler alone calls it, once. It is what moves
--     the throttle forward, writes the debug entry and the Journal line.
--
-- Scoped block, published on `ns`: the chunk is close to Lua's 200-register
-- ceiling.
do

-- The memo. Five seconds is far longer than the frame a message is dispatched
-- in and far shorter than any window the person can pick, and sixty-four slots
-- is more physical messages than a frame ever carries.
local SPAM_MEMO_TTL, SPAM_MEMO_SLOTS = 5, 64
-- What the throttle keeps, and for how long: a day is the longest window on
-- offer, so a record older than that can never mask anything again.
local SPAM_THROTTLE_TTL, SPAM_THROTTLE_MAX, SPAM_PURGE_EVERY = 86400, 5000, 200

local memoSlots, memoByKey, memoNext = {}, {}, 1
local lastShown, throttleSenders, throttleWrites = {}, 0, 0

-- The one spelling of "the same message". Trim, and runs of blanks folded to
-- one -- nothing else. Case, punctuation, colour codes and links are kept as
-- they are: a spammer who changes a letter has written another line, and it is
-- not this add-on's business to guess that two different sentences were meant
-- to be one. Shared with the Journal, which merges on the same key.
function ns.normalizeSpamText(text)
    if type(text) ~= "string" then return nil end
    return (text:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " "))
end

local function purgeThrottle(now)
    local kept = 0
    for senderKey, bucket in pairs(lastShown) do
        local empty = true
        for msgKey, record in pairs(bucket) do
            if (now - record.at) >= SPAM_THROTTLE_TTL then
                bucket[msgKey] = nil
            else
                empty = false
            end
        end
        if empty then lastShown[senderKey] = nil else kept = kept + 1 end
    end
    throttleSenders = kept

    -- Last resort, and it has to exist: a city channel can hand over more
    -- identities in an evening than anyone would want to keep, and an
    -- unbounded table in a client that never restarts is a leak. The identity
    -- whose newest record is the oldest goes first.
    while throttleSenders > SPAM_THROTTLE_MAX do
        local oldestKey, oldestAt
        for senderKey, bucket in pairs(lastShown) do
            local newest = 0
            for _, record in pairs(bucket) do
                if record.at > newest then newest = record.at end
            end
            if not oldestAt or newest < oldestAt then oldestKey, oldestAt = senderKey, newest end
        end
        if not oldestKey then break end
        lastShown[oldestKey] = nil
        throttleSenders = throttleSenders - 1
    end
end

-- The whole of the anti-spam verdict, and every condition it rests on, in the
-- order they are asked. Answers nothing at all unless all of them hold.
local function evaluateSpam(decision, msg, sender)
    -- Public channels only (decision 129), and only where the message was
    -- going to show: `filter_off` on a channel means the person is not
    -- filtering the channels, so nothing else in Sanctuary was going to touch
    -- this line. Anything else -- a block, a whitelist, the player themselves,
    -- the add-on switched off -- has already been decided and is left alone.
    if decision.reason ~= "filter_off" then return end
    if not ns.isAntiSpamEnabled() then return end
    if type(sender) ~= "string" or sender == "" then return end
    if type(msg) ~= "string" or msg == "" then return end
    -- Guild, group, raid, Battle.net friends and both hand-written lists are
    -- spared: an allowed person keeps the native behaviour of WoW, repeats
    -- included.
    if classifyName(sender).verdict ~= "unknown" then return end

    local senderKey = normalizeCharacterKey(sender)
    if not senderKey then return end
    local msgKey = ns.normalizeSpamText(msg)
    if not msgKey or msgKey == "" then return end

    decision.senderKey, decision.msgKey = senderKey, msgKey
    decision.sender, decision.msg = sender, msg

    local bucket = lastShown[senderKey]
    local record = bucket and bucket[msgKey]
    -- The window runs from the copy that was SHOWN, and a hidden repeat does
    -- not push it back: a spammer repeating every ten seconds must see the
    -- line reappear on the hour it was promised, not never.
    if record and (GetTime() - record.at) < ns.getAntiSpamInterval() then
        decision.spam = "masked"
        decision.hide = true
        decision.shownEpoch = record.epoch
    else
        decision.spam = "show"
    end
end

local function evaluate(row, msg, sender, lineID)
    local block, reason, detail, gateOpen = decideChat(row.kind, sender)
    local decision = {
        hide = block, reason = reason, detail = detail, gateOpen = gateOpen,
        logType = row.logType,
        lineIDKnown = type(lineID) == "number" and lineID ~= 0,
    }
    if row.kind == "channel" then evaluateSpam(decision, msg, sender) end
    return decision
end

-- What identifies one physical message. `lineID` is the eleventh payload
-- argument of a chat event and is the same number for every consumer of the
-- same message, which is exactly the identity wanted here.
--
-- With no lineID, the fallback keys on sender, text and the current frame time:
-- the dispatch of one event is synchronous, so every consumer of a message
-- reads the same `GetTime()`. Two identical messages from one sender inside a
-- single frame then share a verdict -- which is the honest answer, since
-- nothing in the payload tells them apart.
local function memoKey(row, msg, sender, lineID)
    if type(lineID) == "number" and lineID ~= 0 then
        return row.event .. "\0" .. lineID
    end
    if type(sender) ~= "string" or type(msg) ~= "string" then return nil end
    return row.event .. "\0" .. sender .. "\0" .. msg .. "\0" .. GetTime()
end

local function remember(key, decision, sender, msg)
    local slot = memoSlots[memoNext]
    if slot and memoByKey[slot.key] == slot then memoByKey[slot.key] = nil end
    slot = { key = key, at = GetTime(), sender = sender, msg = msg, decision = decision }
    memoSlots[memoNext] = slot
    memoByKey[key] = slot
    memoNext = memoNext % SPAM_MEMO_SLOTS + 1
end

-- One verdict per physical message, for every consumer and in any order.
--
-- The memo holds anti-spam verdicts and nothing else, and that narrowness is
-- deliberate. Since the throttle only moves at the commit, recomputing before
-- it gives the same answer anyway -- with one exception, which is the whole
-- reason the memo exists: when the handler runs BEFORE a chat filter, the
-- throttle has already been moved, and a filter recomputing then would hide a
-- line the other chat windows have just shown. Everything else is recomputed on
-- every call, so no consumer can ever be handed a verdict that a list edit has
-- since made wrong.
function ns.resolveChatDecision(row, msg, sender, lineID)
    local key = (row.kind == "channel") and memoKey(row, msg, sender, lineID) or nil
    if key then
        local slot = memoByKey[key]
        -- Re-checked against the message it was computed for: a client that
        -- reuses a lineID, or a fallback key that happens to collide, must
        -- recompute rather than answer for somebody else.
        if slot and (GetTime() - slot.at) < SPAM_MEMO_TTL
            and slot.sender == sender and slot.msg == msg then
            return slot.decision
        end
    end

    local decision = evaluate(row, msg, sender, lineID)
    if key and decision.spam then remember(key, decision, sender, msg) end
    return decision
end

-- The handler's half, and the handler's alone: everything with an effect on the
-- world happens here, once per message, so a chat filter stays what Blizzard
-- requires it to be -- a question with no answer of its own.
function ns.commitChatDecision(decision)
    if not decision or decision.committed then return end
    decision.committed = true
    if not decision.spam then return end

    if decision.spam == "show" then
        local bucket = lastShown[decision.senderKey]
        if not bucket then
            bucket = {}
            lastShown[decision.senderKey] = bucket
            throttleSenders = throttleSenders + 1
        end
        bucket[decision.msgKey] = { at = GetTime(), epoch = time() }
        throttleWrites = throttleWrites + 1
        if throttleWrites >= SPAM_PURGE_EVERY or throttleSenders > SPAM_THROTTLE_MAX then
            throttleWrites = 0
            purgeThrottle(GetTime())
        end
        return
    end

    -- Hidden. `lineIDKnown` is what a real recording will settle the lineID
    -- contract with: it is documented, and nobody on this project has yet seen
    -- it in a client.
    debugLog("MASK_SPAM_REPEAT", {
        kind = decision.logType,
        sender = safeText(decision.sender, 200, "nil"),
        normalized = decision.senderKey or "nil",
        msg = safeText(decision.msg, 300, "nil"),
        lineIDKnown = decision.lineIDKnown and true or false,
        channelMode = isFilterOn("channelMode") or "none",
        intervalSeconds = ns.getAntiSpamInterval(),
    })
    -- One writer for the Journal, the same one every block goes through. The
    -- options say what a hidden repeat is not: it is not a new block to count,
    -- and it is not a line to announce.
    if ns.logBlock then
        ns.logBlock(decision.logType, decision.sender, decision.msg, nil, nil, {
            maskedRepeat = true,
            firstEpoch = decision.shownEpoch,
        })
    end
end

end

-- Export whitelist functions to namespace
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
    ensureWhitelistCache()
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
                    local entry = { key = key, label = label }
                    if source == "bnet" then
                        -- The panel shows "Character · Account", or the account
                        -- alone followed by "(offline)". Both halves travel with
                        -- the entry so the interface never has to look the twin
                        -- identity up a second way.
                        entry.account = label
                        entry.character = Sanctuary.bnetCharacterByAccount
                            and Sanctuary.bnetCharacterByAccount[key] or nil
                        -- `character` carries the realm when the roster gave
                        -- one; the panel prints `characterDisplay`, the bare
                        -- name the friend shows.
                        entry.characterDisplay = (Sanctuary.bnetCharacterDisplayByAccount
                            and Sanctuary.bnetCharacterDisplayByAccount[key]) or entry.character
                    end
                    group.entries[#group.entries + 1] = entry
                end
            end
        end
    end

    collect(Sanctuary.whitelistSources, Sanctuary.whitelistLabels, "guild")
    collect(Sanctuary.whitelistSources, Sanctuary.whitelistLabels, "friend")
    collect(Sanctuary.whitelistSources, Sanctuary.whitelistLabels, "group")
    collect(Sanctuary.bnetWhitelistSources, Sanctuary.bnetWhitelistLabels, "bnet")

    -- Online first, then alphabetically. A Battle.net friend the roster can name
    -- a character for is online right now; one it cannot is offline and has no
    -- character at all -- the gap stated in the release notes. Sorted here
    -- rather than in the panel because "who is online" is a property of the data
    -- and not of pixels, and because the panel's own signature reads this order
    -- back. Decision 110: the people you could actually talk to are the ones
    -- worth putting at the top of fifty-six lines.
    for _, group in ipairs(groups) do
        table.sort(group.entries, function(a, b)
            local onlineA, onlineB = a.character ~= nil, b.character ~= nil
            if onlineA ~= onlineB then return onlineA end
            local la, lb = tostring(a.label):lower(), tostring(b.label):lower()
            if la == lb then return a.key < b.key end
            return la < lb
        end)
    end
    return groups
end

-- Answers "which list does this name fall into, and why" for one typed name. It
-- reuses classifyName unchanged, so the answer is the decision itself and not a
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
    local classification = classifyName(name)
    local blockedNow = getCharacterDecision(name)

    -- Someone blocked by name who is also allowed by a trust source is the case
    -- the tester exists for: a guild mate, a realm friend, somebody in the group.
    -- The answer says both -- blocked, even though.
    --
    -- Never Battle.net any more, decision 100. That answer read "toujours bloque
    -- : dans vos bloques (meme si ami Battle.net)", which states the rule and
    -- breaks it in the same sentence, and `ns.addBlocked` now refuses to create
    -- the case at all. An entry a settings file inherited from before that
    -- refusal still blocks the character it names -- the panel shows it and one
    -- click removes it -- but the tester no longer says a thing the add-on has
    -- stopped doing.
    --
    -- The manual allowed list is not excluded here, and must not be. Decision
    -- 104 makes the two lists exclusive at the write -- putting a name in one
    -- takes it out of the other -- and since decision 119 both sides compute
    -- that on the same realm-qualified key, so allowing "Toto" really does
    -- displace the blocked "Toto" of the player's own realm. What the two lists
    -- can still hold at once is a PATTERN matching a name somebody allowed, and
    -- a trust source the person does not administer: this is the line that says
    -- which of the two is in force.
    local overridden, overriddenDetail = nil, nil
    if classification.verdict == "always_blocked" then
        local source, characterKey = findWhitelistSource(name)
        if source and source ~= "bnet" then
            overridden = source
            overriddenDetail = Sanctuary.whitelistLabels[characterKey]
        end
    end

    return {
        valid = true,
        -- What the sentence names, and it is never just what was typed: a
        -- character is said with its realm, the way both panels say it and the
        -- way the key that answered is built (decision 119). Typing "Kadaj" on
        -- Ysondre asks about Kadaj-Ysondre, and the answer says so rather than
        -- letting the reader assume it covered every Kadaj there is.
        display = ns.qualifiedDisplayName(ns.findAllowedKey(name), name),
        normalized = normalized,
        verdict = classification.verdict,
        list = classification.list,
        detail = classification.detail,
        overriddenList = overridden,
        overriddenDetail = overriddenDetail,
        blockedNow = blockedNow and true or false,
        scope = getScope(),
    }
end

-- ----------------------------------------------------------------------------
-- What the interface reads
-- ----------------------------------------------------------------------------

-- The two tiles of question 4. Counted from the caches rather than from the
-- stored tables so the number on screen is the number the decision uses.
function ns.getListCounts()
    ns.ensureWhitelist()

    -- Battle.net friends are counted once, by account, on the account cache:
    -- an online friend is also in the character cache under `bnet`, and counting
    -- both sides would inflate the tile by however many of them happen to be
    -- connected. The current group is not counted at all -- it is temporary, and
    -- the panel says so in a line rather than listing it.
    local allowed = { manual = 0, trust = 0, bnet = 0, friend = 0, guild = 0, total = 0 }
    for _, source in pairs(Sanctuary.whitelistSources or {}) do
        if source ~= "bnet" and allowed[source] ~= nil then
            allowed[source] = allowed[source] + 1
        end
    end
    for _, source in pairs(Sanctuary.bnetWhitelistSources or {}) do
        if source == "bnet" then
            allowed.bnet = allowed.bnet + 1
        end
    end
    allowed.total = allowed.manual + allowed.trust + allowed.bnet
        + allowed.friend + allowed.guild

    local blocked = { names = 0, patterns = 0, total = 0 }
    if SanctuaryDB then
        for _ in pairs(SanctuaryDB.blockedNames or {}) do
            blocked.names = blocked.names + 1
        end
        blocked.patterns = #(SanctuaryDB.keywords or {})
    end
    blocked.total = blocked.names + blocked.patterns

    return { allowed = allowed, blocked = blocked }
end

-- The header tooltip: what is being filtered right now, and for how many people
-- nothing is. `kinds` is resolved, never the stored checkboxes.
do
local PROTECTION_KINDS = { "groupInvite", "whisper", "duel", "trade", "guildInvite" }

function ns.describeProtection()
    local kinds = {}
    for _, key in ipairs(PROTECTION_KINDS) do
        if isFilterOn(key) == true then
            kinds[#kinds + 1] = key
        end
    end
    return {
        enabled = isEnabled(),
        kinds = kinds,
        allowedCount = ns.getListCounts().allowed.total,
    }
end
end

-- The label of a log entry's type lives here, not in the interface, so the tab
-- and the export can never disagree.
do
local LOG_TYPE_KEYS = {
    groupInvite = "LOG_TYPE_INVITE",
    whisper     = "LOG_TYPE_WHISPER",
    say         = "LOG_TYPE_SAY",
    yell        = "LOG_TYPE_YELL",
    emote       = "LOG_TYPE_EMOTE",
    duel        = "LOG_TYPE_DUEL",
    trade       = "LOG_TYPE_TRADE",
    guildInvite = "LOG_TYPE_GUILD",
    channel     = "LOG_TYPE_CHANNEL",
    group       = "LOG_TYPE_GROUP",
}

function ns.getLogEntryDisplayType(entry)
    local blockType = type(entry) == "table" and entry.type or entry
    local key = LOG_TYPE_KEYS[blockType]
    local label = (key and L[key]) or tostring(blockType or "?")
    -- A folded entry wears its badge on the type it already had. `entry.type`
    -- is left exactly as it was written: it is what maps to the label above and
    -- what the export prints, and a "spam" type of its own would be a second
    -- vocabulary for the same thing.
    local count = (type(entry) == "table" and tonumber(entry.count)) or nil
    if count and count >= 2 then
        label = label .. string.format(L["LOGS_SPAM_BADGE"], count)
    end
    return label
end

-- The date column of one entry, for the tab and for the export alike. A folded
-- entry says when it opened and when it was last seen; an entry that never
-- folded says exactly what it always said, so a journal written by an earlier
-- build reads unchanged.
function ns.getLogEntryDisplayDate(entry)
    local stamp = (type(entry) == "table" and entry.d) or "?"
    local last = (type(entry) == "table" and tonumber(entry.t2)) or nil
    if not last then return stamp end
    return string.format(L["LOGS_TIME_RANGE"], stamp, date("%H:%M:%S", last))
end
end

-- ----------------------------------------------------------------------------
-- List writes
-- ----------------------------------------------------------------------------

-- All six return (ok, key, data): "Undo" needs the exact record back to put it
-- where it was, and a caller that only wants to know whether anything changed
-- reads the first value.
--
-- The three writers answer a FOURTH value on the refusals that can be explained
-- in a sentence: "name", "account", "pattern". The rule of what is refused, and
-- why, lives here and only here -- the panel picks its wording from this code
-- and never works the answer out a second time.
--
-- Two refusals stay silent on purpose. An empty or blank field: nothing was
-- typed, so there is nothing to say about it. A duplicate: it answers
-- (false, key, data), and the label is already on screen a few pixels away.

-- Every write to the always-blocked lists goes through this, never through
-- `invalidateWhitelist` alone. `isProtectionArmed` reads those lists, so adding
-- the first name -- or removing the last one -- flips the guards on its own,
-- with no filter touched and no event fired. And the sound guard is posted
-- state, not state derived on read: `StaticPopupDialogs[...].sound` stays at
-- whatever the last refresh left there. Skip this and the two product rules
-- break at once: the first blocked name still plays its invite sound before the
-- popup is masked, and after the last one is removed a stranger's invitation
-- stays mute in the mode where it must sound exactly as WoW plays it.
local function invalidateBlockedLists()
    invalidateWhitelist()
    refreshInviteSoundMuteState()
end

function ns.addAllowed(name, source)
    if not SanctuaryDB then return false end
    local clean = stripWoWFormatting(name)
    if not clean or clean:gsub("%s", "") == "" then return false end
    -- Keyed "pseudo-realm" by the one rule the blocked list uses, and refused
    -- outright when nothing is left of it -- "-" writes here no more than it
    -- writes there. The field is the same on both panels ("Name or Name-Realm"),
    -- so the two sides have no business reading it differently -- and since
    -- decision 119 they no longer do: the realm is engraved here, at the write,
    -- from what was typed or else from the realm the player is on right now, and
    -- never read back from the game afterwards.
    --
    -- Unless what was typed is an account: a "#" is a Battle.net tag and no
    -- pseudo carries one, so such an entry is keyed whole, the way the account
    -- cache keys it. Cut, "Real Friend#1234" became "real" -- an entry that
    -- allowed every Real of every realm without a word, and that two accounts
    -- sharing their first word ("Manual Battle#1111", "Manual Buddy#5678")
    -- collided on, the second of them refused as a duplicate without a word.
    --
    -- Both halves of that rule live in `findAllowedKey`, which the right-click
    -- menu reads too: the key this writes and the key the menu looks up are one
    -- piece of code, not two that have to agree.
    local key = ns.findAllowedKey(clean)
    -- Something was typed and nothing usable is left of it -- "-", " - ".
    if not key then return false, nil, nil, "name" end
    -- Automatic trust never writes over the always-blocked door, decision 104.
    -- The guard stands here, at the one write every path goes through, and not
    -- beside the ticker that calls it: the ticker asks `findBlockedKey`, which
    -- reads `blockedNames` and nothing else, so somebody blocked by a PATTERN
    -- went on being written into "Toujours autorises" with source "trust" --
    -- counted in the tile, listed on the allowed panel -- while `classifyName`
    -- went on answering always_blocked/keyword. One person on both lists at once
    -- is what decision 104 exists to end, and the list of ways to be blocked is
    -- not this function's business to keep in step.
    --
    -- `isAlwaysBlocked` for that reason: it is the gate every decision path asks
    -- first, it covers both ways of being blocked, and it answers on whatever
    -- realm form the tracker hands over.
    --
    -- Restricted to source "trust", so the two hand gestures keep their exact
    -- behaviour: a name typed into "Toujours autorises", or allowed from the
    -- right-click menu, still displaces the blocked entry and still offers the
    -- Annuler that puts the whole gesture back. What is refused here is the
    -- write nobody asked for and nobody sees.
    if source == "trust" and isAlwaysBlocked(clean) then
        return false, key, nil, "blocked"
    end
    SanctuaryDB.manualWhitelist = SanctuaryDB.manualWhitelist or {}
    if SanctuaryDB.manualWhitelist[key] then
        return false, key, SanctuaryDB.manualWhitelist[key]
    end
    -- The two lists are exclusive, decision 104: "on peut a la fois ajouter dans
    -- autorise et dans bloque, c'est pas normal". They were not, and the
    -- reasoning for it -- "the blocked list wins anyway, and deleting a line
    -- somebody typed would be a data loss they never asked for" -- had the cost
    -- backwards: what a person reads is two lists that contradict each other,
    -- with no way to tell from either one which of the two is in force.
    --
    -- What was displaced travels back to the caller rather than vanishing: the
    -- interface says which list the name left, and Annuler puts the whole
    -- gesture back -- this entry out, that one in. Undoing one half alone would
    -- put the two lists back into the state this rule exists to end.
    local displaced = nil
    local blockedKey = normalizeCharacterKey(clean)
    if blockedKey and SanctuaryDB.blockedNames and SanctuaryDB.blockedNames[blockedKey] then
        displaced = {
            list = "blocked", key = blockedKey,
            data = SanctuaryDB.blockedNames[blockedKey],
        }
        SanctuaryDB.blockedNames[blockedKey] = nil
    end
    local data = {
        -- "menu" travels here exactly as it does through `addBlocked`. The chip
        -- tooltip states where a name came from, and a name added from a right
        -- click is not a name somebody typed: dropping the origin made the
        -- tooltip claim a hand entry that never happened.
        --
        -- The raw entry, never the key: `addManualEntry` feeds the Battle.net
        -- cache from `displayName`, and that is the documented way to allow an
        -- account -- "Real Friend#1234" typed here reaches the Battle.net
        -- whisper path through this field alone. Key it here and the account
        -- would stop being allowed the day the key rule changed.
        displayName = clean,
        addedAt = time(),
        source = (source == "trust" or source == "menu") and source or nil,
    }
    SanctuaryDB.manualWhitelist[key] = data
    -- Through the blocked-list path, not `invalidateWhitelist` alone: this write
    -- can have emptied the blocked list, and the guards and the invite sound are
    -- posted state that only that call refreshes.
    invalidateBlockedLists()
    return true, key, data, nil, displaced
end

function ns.removeAllowed(key)
    if not SanctuaryDB or not key then return false end
    local data = SanctuaryDB.manualWhitelist and SanctuaryDB.manualWhitelist[key]
    if not data then return false end
    SanctuaryDB.manualWhitelist[key] = nil
    invalidateWhitelist()
    return true, key, data
end

-- Restores an entry exactly as it was, timestamp and origin included. Undo must
-- not rewrite the date the person added someone.
function ns.restoreAllowed(key, data)
    if not SanctuaryDB or not key or type(data) ~= "table" then return false end
    SanctuaryDB.manualWhitelist = SanctuaryDB.manualWhitelist or {}
    SanctuaryDB.manualWhitelist[key] = data
    invalidateWhitelist()
    return true, key, data
end

function ns.addBlocked(name, source)
    if not SanctuaryDB then return false end
    local clean = stripWoWFormatting(name)
    if not clean or clean:gsub("%s", "") == "" then return false end
    -- A BattleTag names an account, never a character. "Real Friend#1234" read
    -- as a pseudo and a realm built the key "real-friend#1234", which no event
    -- of the game can ever produce: an entry showing in the panel, counted in
    -- the tile and arming the guards while the Battle.net whisper went on
    -- arriving -- as it must, the account channel follows the Battle.net roster
    -- and nothing else. The panel says as much right above this field ("A
    -- Battle.net friend cannot be blocked here: remove them in Battle.net"), and
    -- the code went on doing it anyway, then listing it. Refused, exactly like
    -- "-": nothing written, nothing counted, nothing armed.
    --
    -- Refused on the "#" alone, never on the Battle.net roster: a one-word
    -- account name ("Toto") is spelled like a character, and refusing it would
    -- leave somebody unable to block a harasser who happens to be a namesake.
    -- The assumed residue: an account name with no tag ("Battle Friend") has
    -- exactly the shape of a Pseudo-Realm pair and stays indistinguishable --
    -- typed here it makes a character entry that blocks nobody. Nothing in the
    -- string tells the two apart; the panel's sentence is what covers that case.
    --
    -- Asked of `isAccountName`, the one place that says what an account is. The
    -- test used to be spelled out again here, so "what counts as a BattleTag"
    -- had two answers to keep in step -- while the allowed field, sixty lines
    -- up, was already asking the question the other way round.
    if isAccountName(clean) then return false, nil, nil, "account" end
    -- And the character a Battle.net friend is playing, refused for the same
    -- reason and with the same sentence. Decision 100: "on s'etait dit que si on
    -- voulait bloquer quelqu'un de Battle.net il fallait le faire via Battle.net".
    -- Only the tag was refused before, so the friend's CHARACTER went in without
    -- a word and the tester answered "toujours bloque : dans vos bloques (meme
    -- si ami Battle.net)" -- a sentence that states the rule and breaks it in
    -- the same breath.
    --
    -- Asked of `bnetAccountBlockingCharacter`, not of the tolerant attribution
    -- lookup: on the realm-qualified key, and on the bare pseudo only when
    -- neither the roster nor the person typing named a realm. See the comment
    -- there -- restricting the map was only half of that rule. It fails
    -- open: a roster that has not answered yet knows nobody, so nothing
    -- legitimate is refused on a stale cache -- the wrong way round would be an
    -- add-on that will not let somebody block their harasser.
    ns.ensureWhitelist()
    if bnetAccountBlockingCharacter(clean) then return false, nil, nil, "account" end
    local key = normalizeCharacterKey(clean)
    if not key then return false, nil, nil, "name" end
    SanctuaryDB.blockedNames = SanctuaryDB.blockedNames or {}
    if SanctuaryDB.blockedNames[key] then
        return false, key, SanctuaryDB.blockedNames[key]
    end
    -- Exclusive with the allowed list, decision 104. See `ns.addAllowed` for
    -- what `displaced` is and why the whole gesture has to be undoable at once.
    local displaced = nil
    local allowedKey = ns.findAllowedKey(clean)
    if allowedKey and SanctuaryDB.manualWhitelist and SanctuaryDB.manualWhitelist[allowedKey] then
        displaced = {
            list = "allowed", key = allowedKey,
            data = SanctuaryDB.manualWhitelist[allowedKey],
        }
        SanctuaryDB.manualWhitelist[allowedKey] = nil
    end
    local data = {
        displayName = clean,
        addedAt = time(),
        source = source == "menu" and "menu" or "manual",
    }
    SanctuaryDB.blockedNames[key] = data
    invalidateBlockedLists()
    return true, key, data, nil, displaced
end

function ns.removeBlocked(key)
    if not SanctuaryDB or not key then return false end
    local data = SanctuaryDB.blockedNames and SanctuaryDB.blockedNames[key]
    if not data then return false end
    SanctuaryDB.blockedNames[key] = nil
    invalidateBlockedLists()
    return true, key, data
end

function ns.restoreBlocked(key, data)
    if not SanctuaryDB or not key or type(data) ~= "table" then return false end
    SanctuaryDB.blockedNames = SanctuaryDB.blockedNames or {}
    SanctuaryDB.blockedNames[key] = data
    invalidateBlockedLists()
    return true, key, data
end

-- A pattern is looked for in the pseudo half alone (`matchesKeyword`), and a
-- pseudo is letters: no hyphen, no digit, no "#", no dot. A pattern holding any
-- of those matches nobody, ever, and is refused rather than stored. Stored, it
-- showed in the panel, counted in the tile and armed the guards while blocking
-- no one -- the dead entry the blocked list had just closed, reopened one commit
-- later on the pattern list.
--
-- The realistic one is the tag: somebody pastes their harasser's BattleTag in
-- the pattern field, the chip appears, the tile goes up, nothing is blocked and
-- nothing tells them so. Refused, the field says no and they can put the tag
-- where it works -- the allowed field takes accounts, the blocked field refuses
-- them too, and the pattern list is for a piece of a pseudo.
--
-- Refused, and not cut down to its pseudo half like a name: "Toto-Ysondre" cut
-- to "toto" would block every Toto of every realm, the silent over-block that
-- searching the pseudo alone has just ended. A pattern names a piece of text to
-- look for, not a realm; there is nothing to salvage here, only something to say
-- no to.
--
-- `%p` and `%d` are ASCII under Lua's C locale, so an accented or cyrillic
-- pattern goes through untouched -- "zoé" and "илья" hold no punctuation as far
-- as this rule is concerned. Do not trade it for a whitelist of letters, which
-- would refuse exactly those names.
function ns.addPattern(text)
    if not SanctuaryDB then return false end
    local clean = normalizePatternText(text)
    if not clean then return false end
    if clean:find("[%p%d]") then return false, nil, nil, "pattern" end
    SanctuaryDB.keywords = SanctuaryDB.keywords or {}
    for _, existing in ipairs(SanctuaryDB.keywords) do
        if existing == clean then return false, clean, clean end
    end
    SanctuaryDB.keywords[#SanctuaryDB.keywords + 1] = clean
    invalidateBlockedLists()
    return true, clean, clean
end

function ns.removePattern(text)
    if not SanctuaryDB or not SanctuaryDB.keywords then return false end
    local clean = normalizePatternText(text)
    if not clean then return false end
    for index, existing in ipairs(SanctuaryDB.keywords) do
        if existing == clean then
            table.remove(SanctuaryDB.keywords, index)
            invalidateBlockedLists()
            return true, clean, clean
        end
    end
    return false
end

-- ============================================================================
-- SECTION F: Logging Engine
-- ============================================================================

local logBlock
do
local lastLogKey, lastLogBase = "", ""
local lastLogTime = 0

-- What the Journal merges on.
--
-- The same message, from the same person, on the same day, is ONE entry with a
-- count and a time range -- not four hundred lines pushing everything else off
-- the front of the log, which is what the session of 24/08 found ("journal
-- pollué par le spam /2"). Bounded to the day, decision 125: the same line
-- tomorrow is a new entry, so a range never spans a night and "is this person
-- still at it" stays readable at a glance.
--
-- Two runtime tables, and neither ever reaches SavedVariables: the entry of a
-- key, and the key of an entry. The second is what lets rotation drop exactly
-- the entries it evicted. Emptying the whole index at each rotation would leave
-- it permanently empty on a full journal -- the very case the merge exists for.
local mergeIndex, mergeKeyOf = {}, {}
local indexedLog, indexedCount, indexedDay = nil, 0, nil

-- One alert per level per session. `PLAYER_ENTERING_WORLD` fires at every
-- loading screen, so without a lock the message would come back at each dungeon
-- door.
local journalAlerted = { almost = false, full = false }

local function forgetJournalIndex(log)
    mergeIndex, mergeKeyOf = {}, {}
    indexedLog, indexedCount, indexedDay = log, log and #log or 0, nil
end

-- Three ways the index stops describing the log, read here rather than hooked
-- from everywhere: the table itself was replaced, entries went away behind our
-- back, or the day turned over and yesterday's keys can no longer match.
local function ensureJournalIndex(today)
    local log = SanctuaryDB and SanctuaryDB.log
    if log ~= indexedLog or (log and #log < indexedCount) then
        forgetJournalIndex(log)
    end
    if today ~= indexedDay then
        mergeIndex, mergeKeyOf = {}, {}
        indexedDay = today
    end
end

-- Emptying the journal empties what describes it. Every path that clears the
-- log goes through here -- the interface's confirmation dialog included -- so
-- an index pointing at entries nobody can reach any more is not a state that
-- exists.
function ns.clearJournal()
    if not SanctuaryDB or type(SanctuaryDB.log) ~= "table" then return end
    wipe(SanctuaryDB.log)
    forgetJournalIndex(SanctuaryDB.log)
    -- A journal that has just been emptied is not nearly full any more: the
    -- next loading screen may warn again if it fills up again.
    journalAlerted.almost, journalAlerted.full = false, false
end

-- "Your journal is filling up", once per level per session, at load and at
-- every loading screen (decision 128: 90 %, and the text names the Advanced
-- tab so nobody hunts for a setting). Nothing is said mid-session when the
-- threshold is crossed: that was not asked for, and a warning arriving in the
-- middle of a fight is exactly the kind of noise this add-on exists to remove.
function ns.checkJournalCapacityAlert()
    if not SanctuaryDB or type(SanctuaryDB.log) ~= "table" then return end
    if not isEnabled() then return end
    if not SanctuaryDB.logging or SanctuaryDB.logging.enabled ~= true then return end

    local maxEntries = math.max(1, SanctuaryDB.logging.maxEntries or 5000)
    local count = #SanctuaryDB.log
    if count >= maxEntries then
        if journalAlerted.full then return end
        journalAlerted.full = true
        printMsg(COLOR_WARN .. string.format(L["LOGS_ALERT_FULL"], count) .. COLOR_RESET)
    elseif count >= math.ceil(maxEntries * 0.9) then
        if journalAlerted.almost then return end
        journalAlerted.almost = true
        printMsg(COLOR_WARN .. string.format(L["LOGS_ALERT_ALMOST_FULL"], count, maxEntries) .. COLOR_RESET)
    end
end

-- What a block costs outside the journal: the session counter the five-minute
-- summary reads, and the line the verbose mode prints. A repeat the anti-spam
-- hid pays neither -- it was never a block, only a copy of one that had already
-- been shown -- and those two omissions are the whole of "no visible or audible
-- trace" for it.
local function accountForBlock(blockType, sourceText, maskedRepeat)
    if maskedRepeat then return end
    if SanctuaryCharDB then
        SanctuaryCharDB.sessionStats.blockedCount =
            (SanctuaryCharDB.sessionStats.blockedCount or 0) + 1
        local byType = SanctuaryCharDB.sessionStats.blockedByType
        byType[blockType] = (byType[blockType] or 0) + 1
    end
    if SanctuaryDB.notifications.mode == "verbose" then
        printMsg(string.format(L["BLOCKED_VERBOSE"],
            COLOR_HIGHLIGHT .. blockType .. COLOR_RESET,
            COLOR_HIGHLIGHT .. (sourceText or "?") .. COLOR_RESET))
    end
end

-- `options` carries what only the anti-spam needs: `maskedRepeat`, and
-- `firstEpoch`, the moment the copy that WAS shown arrived. The count reads as
-- the number of times the line arrived (decision 132, Q2), so the first hidden
-- copy opens its entry at two.
logBlock = function(blockType, sourceName, message, guid, keyword, options)
    if not SanctuaryDB then return end
    if not SanctuaryDB.logging.enabled then return end

    local sourceText = safeText(sourceName, nil, nil)
    local messageText = safeText(message, nil, nil)
    local msgKey = ns.normalizeSpamText(messageText) or ""
    local maskedRepeat = type(options) == "table" and options.maskedRepeat == true

    local today = date("%Y-%m-%d")
    ensureJournalIndex(today)

    -- Only an entry carrying both a pseudo and a message can be merged: an
    -- invitation, a duel or a trade has nothing to tell two of them apart, and
    -- counting them together would hide how many times somebody knocked.
    local mergeKey
    local characterKey = sourceText and normalizeCharacterKey(sourceText)
    if characterKey and msgKey ~= "" then
        mergeKey = today .. "\0" .. blockType .. "\0" .. characterKey .. "\0" .. msgKey
    end

    local existing = mergeKey and mergeIndex[mergeKey]
    if existing then
        -- One occurrence more is a counter, not noise: the one-second dedupe
        -- below guards the CREATION of an entry and is never asked about a
        -- merge.
        existing.count = (existing.count or 1) + 1
        existing.t2 = time()
        accountForBlock(blockType, sourceText, maskedRepeat)
        return
    end

    -- Dedup: skip if the same event was logged within 1 second. The message is
    -- part of the key now, so two DIFFERENT lines from one person in the same
    -- second are two entries -- they were two things said. An entry with no
    -- message keeps the old key exactly: nothing distinguishes two of them, and
    -- the popup-backed invitation paths lean on that, one of them writing the
    -- system line and the richer event write following within the second.
    local logKey = blockType .. ":" .. (sourceText or "") .. ":" .. msgKey
    local logBase = blockType .. ":" .. (sourceText or "")
    local now = GetTime()
    if (now - lastLogTime) < 1
        and (logKey == lastLogKey or (msgKey == "" and logBase == lastLogBase)) then
        return
    end
    lastLogKey, lastLogBase = logKey, logBase
    lastLogTime = now

    local playerName = UnitName("player")
    local charRealm = getPlayerRealm()
    local sourceRealm = ""
    local cleanName = sourceText or "Unknown"

    -- Extract realm from "Name-Realm" format. Character names cannot contain
    -- hyphens, so the first hyphen is the unambiguous separator.
    --
    -- The last hand-written cut in the file, and it stays one on purpose --
    -- `splitCharacterName` is not what this wants. Three reasons, all of them
    -- load-bearing: the Journal shows the two halves in two columns, so the
    -- realm has to come back whole and not just be folded away; the pseudo is
    -- displayed and must keep the casing the person will recognise; and this
    -- same function is handed Battle.net account names by the Battle.net whisper
    -- path, which carry spaces the pseudo rule would cut on. This builds a line
    -- to read, not a key to compare.
    local n, r = cleanName:match("^([^-]+)%-(.+)$")
    if n and r then
        cleanName = n
        sourceRealm = r
    end

    -- The first arrival dates the entry. For a hidden repeat that is the copy
    -- the person actually read, which is what makes the range on screen say
    -- something -- it opened when they saw it, not when Sanctuary started
    -- hiding it.
    local firstEpoch = (type(options) == "table" and tonumber(options.firstEpoch)) or time()
    local entry = {
        t     = firstEpoch,
        d     = date("%Y-%m-%d %H:%M:%S", firstEpoch),
        type  = blockType,
        name  = cleanName,
        realm = sourceRealm,
        guid  = guid or "",
        msg   = messageText,
        char  = (playerName or "?") .. "-" .. (charRealm or "?"),
        keyword = keyword or nil,
    }
    -- Two fields an ordinary entry does not carry, so a settings file written
    -- by an earlier build reads exactly as it did: no `count` means one.
    if maskedRepeat then
        entry.count = 2
        entry.t2 = time()
    end

    table.insert(SanctuaryDB.log, entry)
    if mergeKey then
        mergeIndex[mergeKey] = entry
        mergeKeyOf[entry] = mergeKey
    end

    -- Rotation without allocating a second multi-thousand-entry table.
    local maxEntries = math.max(1, SanctuaryDB.logging.maxEntries or 5000)
    local overflow = #SanctuaryDB.log - maxEntries
    if overflow > 0 then
        local oldCount = #SanctuaryDB.log
        -- The evicted entries leave the index with them, and only they do: an
        -- entry that is gone must never be handed one more occurrence, and the
        -- ones that stay must go on merging.
        for i = 1, overflow do
            local evicted = SanctuaryDB.log[i]
            local evictedKey = evicted and mergeKeyOf[evicted]
            if evictedKey then
                mergeKeyOf[evicted] = nil
                if mergeIndex[evictedKey] == evicted then mergeIndex[evictedKey] = nil end
            end
        end
        for i = 1, oldCount - overflow do
            SanctuaryDB.log[i] = SanctuaryDB.log[i + overflow]
        end
        for i = oldCount - overflow + 1, oldCount do
            SanctuaryDB.log[i] = nil
        end
    end
    indexedCount = #SanctuaryDB.log

    accountForBlock(blockType, sourceText, maskedRepeat)
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
        antiSpam = ns.isAntiSpamEnabled(),
        antiSpamInterval = ns.getAntiSpamInterval(),
        channelSpamCovered = ns.isChannelSpamCovered(),
        groupInviteFilter = isFilterOn("groupInvite") == true,
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
    add("GroupInviteFilter: " .. tostring(isFilterOn("groupInvite"))
        .. " | StrictGroupInviteSystemMessages: "
        .. tostring(isFilterOn("strictGroupInviteSystemMessages"))
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
        playerDied = false,
        playerRevived = false,
        -- Strict mode in instances. Counted rather than flagged: the number of
        -- hidden lines is what a recording is read for, and "visible" is the
        -- counter-measurement that says whether the fix took.
        secretSystemSuppressed = 0,
        secretSystemVisible = 0,
        secretSystemEligible = 0,
        strictModeOn = false,
        lockdownArmedInInstance = false,
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
                markers.addonInterface = data.addonInterface
                if type(data.filters) == "table" then
                    markers.strictModeOn =
                        data.filters.strictGroupInviteSystemMessages == true
                end
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
            -- Kept in blocks of their own so a later change to one counter
            -- cannot silently move another.
            elseif cat == "CHAT_OUTPUT" and data.action == "SUPPRESS_SECRET_SYSTEM" then
                markers.secretSystemSuppressed = markers.secretSystemSuppressed + 1
            elseif cat == "CHAT_OUTPUT" and data.action == "SECRET_VALUE"
                and data.isSystemTypeID == true then
                markers.secretSystemVisible = markers.secretSystemVisible + 1
            elseif cat == "SYSTEM_INVITE" and data.result == "STRICT_POLICY_ELIGIBLE" then
                markers.secretSystemEligible = markers.secretSystemEligible + 1
            elseif cat == "CHAT_TEST" and data.kind == "lockdown" then
                if data.armed == true and data.inInstance == true then
                    markers.lockdownArmedInInstance = true
                end
            elseif cat == "POPUP" and data.action == "MASK_AWAITING_EVENT"
                and (tonumber(data.affected) or 0) >= 1 then
                markers.popupMaskAwaitingEvent = true
            elseif cat == "WORLD" and data.inInstance == true then
                markers.worldInInstance = true
            elseif cat == "PLAYER_STATE" then
                -- The scenario is "die, stay a ghost, resurrect", and it takes
                -- both halves. A lone PLAYER_ALIVE proves nothing -- it also
                -- fires at login -- and a lone PLAYER_DEAD proves the character
                -- died, not that the session carried on afterwards. The revival
                -- only counts if it comes after the death, so the login one
                -- cannot stand in for it.
                if data.event == "PLAYER_DEAD" then
                    markers.playerDied = true
                    markers.playerDeathSeq = tonumber(entry.seq) or 0
                elseif data.event == "PLAYER_ALIVE" or data.event == "PLAYER_UNGHOST" then
                    if markers.playerDied
                        and (tonumber(entry.seq) or 0) > (markers.playerDeathSeq or 0) then
                        markers.playerRevived = true
                    end
                end
                markers.playerState = (markers.playerDied and markers.playerRevived) and true or false
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

-- A build has two identities: the constant compiled into this file, and what the
-- client read out of the .toc at runtime. They only disagree when the folder was
-- deployed in halves -- the .lua files replaced but not the .toc, or the other
-- way round -- which is a real hazard for an add-on installed by hand. Same
-- shape as getInstrumentationVerdict, and shared by the in-game summary and the
-- offline check so the two can never disagree about what "the right build" is.
function ns.getDeploymentVerdict(manifest)
    manifest = manifest or (SanctuaryDB and SanctuaryDB.reportManifest)
    if type(manifest) ~= "table" then return "unknown", "no_manifest" end

    local IDENTITY_PAIRS = {
        { code = "build", meta = "addonMetaBuild", label = "build" },
        { code = "version", meta = "addonMetaVersion", label = "version" },
    }
    for _, pair in ipairs(IDENTITY_PAIRS) do
        local codeValue, metaValue = manifest[pair.code], manifest[pair.meta]
        if metaValue == nil or metaValue == "nil" or metaValue == "unavailable"
            or metaValue == "error" then
            return "unknown", pair.label .. "_meta_unreadable"
        end
        -- Absence is graded the same on both sides. An unreadable .toc already
        -- gave `unknown`; a missing code identity used to skip the comparison
        -- and fall through to `ok` -- an unknown turning green on the side
        -- nobody was watching.
        if codeValue == nil or codeValue == "nil" then
            return "unknown", pair.label .. "_code_missing"
        end
        if metaValue ~= codeValue then
            return "partial", pair.label .. " code=" .. tostring(codeValue)
                .. " .toc=" .. tostring(metaValue)
        end
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
        -- The interface version the client actually resolved for this addon.
        -- It is what the AddOns manager grades "Out of date" on, and until now
        -- the recording carried nothing to compare against the client's.
        addonInterface = context.addonInterface,
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
function ns.buildDebugSummaryText(includeFileNote)
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
        .. " interface=" .. escapeExportText(manifest.addonInterface
            or manifest.addonMetaInterface))
    add("Client: " .. escapeExportText(manifest.clientVersion)
        .. " build=" .. escapeExportText(manifest.clientBuild)
        .. " interface=" .. escapeExportText(manifest.clientInterface))

    add("")
    add("--- INSTRUMENTATION ---")
    local deployment, deploymentDetail = ns.getDeploymentVerdict(manifest)
    add("Deploiement: " .. deployment:upper()
        .. (deploymentDetail and (" (" .. deploymentDetail .. ")") or ""))
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
    add("GroupInviteFilter: " .. tostring(isFilterOn("groupInvite"))
        .. " | StrictGroupInviteSystemMessages: "
        .. tostring(isFilterOn("strictGroupInviteSystemMessages"))
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
    add("Instance: masques=" .. tostring(markers.secretSystemSuppressed)
        .. " visibles=" .. tostring(markers.secretSystemVisible)
        .. " eligibles=" .. tostring(markers.secretSystemEligible)
        .. " renforce=" .. yesno(markers.strictModeOn)
        .. " verrouillage=" .. yesno(markers.lockdownArmedInInstance))

    if includeFileNote ~= false then
        add("")
        add("--- RELEVE ---")
        add(L["DEBUG_SUMMARY_FILE"])
    end

    return table.concat(lines, "\n") .. "\n"
end

-- The single "Export the report" button: the summary that says whether the
-- recording is usable, then the recording itself. The file-location note is
-- dropped here -- this text is the transport, so telling the reader to go and
-- find the file instead would contradict the button they just pressed.
function ns.buildExportReportText()
    if not SanctuaryDB then return "" end
    -- Forced, as before: "play, untick debug, export later" is a normal path,
    -- and it used to produce a report whose last snapshot dated from activation.
    captureDebugSnapshot("export")
    return ns.buildDebugSummaryText(false) .. "\n" .. buildDebugReportText()
end

-- ============================================================================
-- SECTION G: Chat Message Filters (PURE functions — NO side effects)
-- ============================================================================

-- Build invite pattern from WoW global string at init
local invitePatterns = {}
local invitePatternKinds = {}

local formatStringToPattern
do
local function escapePattern(s)
    return s:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
end

formatStringToPattern = function(formatString)
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

-- Shared core of the strict-mode predicate. One rule, one place: the filter, the
-- output envelope and the eligibility marker all read it, so they cannot drift.
-- The settings are read on every call, which is what makes the mode reversible
-- without a /reload.
local function evaluateStrictSecretSuppression()
    if not isEnabled() then return false, "addon_disabled" end
    if isFilterOn("groupInvite") ~= true then return false, "filter_off" end
    if isFilterOn("strictGroupInviteSystemMessages") ~= true then return false, "strict_off" end

    local context = getRuntimeContext()
    if not (context.inGroup or context.inRaid or context.inInstance) then
        return false, "no_context"
    end
    return true, "suppressed"
end

local function shouldSuppressSecretGroupInviteSystemMessage(msg)
    if not isRestrictedValue(msg) then return false end
    return (evaluateStrictSecretSuppression())
end

-- The order every attributable decision path follows is `decideInteraction`, up
-- next to `getCharacterDecision`. Nothing in this section spells it out again.

-- System-message filters are invoked once per destination chat frame, so they
-- must stay side-effect free. Logging/debugging happens in CHAT_MSG_SYSTEM.
--
-- The secret predicate stays first and stays apart: a line nobody can read
-- cannot be attributed to anybody, so it is not a decision about a person and
-- has no business inside one.
local function systemMessageFilter(self, event, msg, ...)
    if not isEnabled() then return false end

    if shouldSuppressSecretGroupInviteSystemMessage(msg) then return true end

    local inviterName = extractInviterFromSystemMessage(msg)
    if not inviterName then return false end

    -- Parenthesised, and so is every other filter here: Blizzard's registry
    -- reads a filter's second return value as a replacement for the message
    -- text, so a decision handing back its `reason` would rewrite the line.
    return (decideInteraction("groupInvite", inviterName))
end

-- The Battle.net whisper filter. The decision, the invariant it obeys and every
-- field the handler publishes live in `decideBNetWhisper`, next to the other two
-- decisions: this is one of its two consumers, the CHAT_MSG_BN_WHISPER handler
-- is the other, and neither may ask a question of its own.
local function bnetWhisperFilter(self, event, msg, sender, ...)
    return (decideBNetWhisper(sender, ...))
end

local GROUP_CHAT_EVENTS = {
    "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER",
}

ns.GROUP_CHAT_EVENTS = GROUP_CHAT_EVENTS

-- ----------------------------------------------------------------------------
-- The thirteen character-message events, in one table
-- ----------------------------------------------------------------------------

-- Every chat event whose sender is a WoW character. The filter that decides
-- whether the line shows, the handler that journals and counts it, and the
-- event registration itself are all generated from this table -- so the two
-- halves of one message cannot be given two different orders, and a kind added
-- here reaches all three at once.
--
-- Six filter bodies and four handler bodies used to spell the same order out,
-- twice per kind. That is the shape the whole release went after: three fixes
-- in this mission landed on one of the two copies, and the last one -- a
-- player's whisper to themselves, swallowed by the handler while the filter let
-- it through -- is why the bodies are gone rather than merely aligned.
--
-- Per row:
--   * `kind`       -- what `decideInteraction` gates on;
--   * `logType`    -- the Journal type, the one the person reads;
--   * `quietPass`  -- write nothing at all, not even debug, when the decision is
--                     not a block. Group chat only: it is far too talkative, and
--                     that is what the old handler already did;
--   * `closesTab`  -- close the whisper tab a blocked sender owns;
--   * `debugExtra` -- one extra field on the debug entry.
--
-- CHAT_MSG_SYSTEM and CHAT_MSG_BN_WHISPER are deliberately not here: their
-- senders are not characters, so neither goes through `decideChat`. They keep a
-- named filter and a named handler, registered alongside the loop.
local CHAT_KINDS = {
    { event = "CHAT_MSG_WHISPER",    kind = "whisper", logType = "whisper", closesTab = true },
    { event = "CHAT_MSG_SAY",        kind = "say",     logType = "say" },
    { event = "CHAT_MSG_YELL",       kind = "yell",    logType = "yell" },
    { event = "CHAT_MSG_EMOTE",      kind = "emote",   logType = "emote" },
    { event = "CHAT_MSG_TEXT_EMOTE", kind = "emote",   logType = "emote" },
    { event = "CHAT_MSG_CHANNEL",    kind = "channel", logType = "channel",
      debugExtra = "channelMode" },
}

-- Group, raid and instance chat. The only channels Sanctuary ever touches for
-- anything but a filter, and only for the always-blocked list: never a stranger,
-- never the player, and no setting is consulted -- which is exactly what the
-- `group` gate of `decideInteraction` says. This is the unwanted team-mate case
-- that motivated the list; their /p was the one thing that stayed visible.
for _, event in ipairs(GROUP_CHAT_EVENTS) do
    CHAT_KINDS[#CHAT_KINDS + 1] = {
        event = event, kind = "group", logType = "group", quietPass = true,
    }
end

-- One filter per row, and its whole body is the decision. Parenthesised on
-- purpose: Blizzard's registry reads a filter's second return value as a
-- replacement for the message text, so handing back `reason` alongside the
-- verdict would rewrite what the person reads.
--
-- `select(9, ...)` is the eleventh payload argument, `lineID`: the vararg starts
-- at the third. It names the physical message, so every chat window asking about
-- one message gets one verdict. Nothing is written from here -- a filter is
-- called once per ChatFrame and must stay a question.
for _, row in ipairs(CHAT_KINDS) do
    row.filter = function(self, event, msg, sender, ...)
        return (ns.resolveChatDecision(row, msg, sender, select(9, ...)).hide)
    end
end

ns.CHAT_KINDS = CHAT_KINDS

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

    -- The two whose sender is not a character, by name; every other one from
    -- the table, so a kind can never be given a handler and no filter.
    addFilter("CHAT_MSG_SYSTEM", systemMessageFilter)
    addFilter("CHAT_MSG_BN_WHISPER", bnetWhisperFilter)
    for _, row in ipairs(CHAT_KINDS) do
        addFilter(row.event, row.filter)
    end

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
local describeSecretOutputMessageType
do
local SECRET_OUTPUT_MESSAGE_TYPE_INDEX = 4

describeSecretOutputMessageType = function(...)
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
end

-- Whether a secret line reaching AddMessage must be dropped. Pure: no writes, no
-- logs, no native call, and re-evaluated on every frame of every burst, which is
-- what makes unticking the box take effect on the next line without a /reload.
--
-- There is deliberately no lockdown step. The state is read and recorded, but it
-- cannot refuse the masking: a wrong `false` would cancel the whole fix,
-- silently, in the exact scenario the fix exists for.
local function shouldSuppressSecretSystemOutput(text, described)
    if not isRestrictedValue(text) then return false, "readable" end
    if not described.isSystemTypeIDKnown then return false, "type_unknown" end
    if not described.isSystemTypeID then return false, "type_not_system" end
    return evaluateStrictSecretSuppression()
end

ns.shouldSuppressSecretSystemOutput = shouldSuppressSecretSystemOutput

-- One chat payload is dispatched to every subscribed ChatFrame, so a single
-- secret system line produces one AddMessage call per frame. The tracker answers
-- one question -- "is this a new message?" -- and it answers it whether or not
-- debug mode is on, because the masking decision is taken per frame while the
-- burst identity belongs to the message.
local secretChatOutputBurst = nil

local function trackSecretChatOutput(frameIndex, described)
    local now = GetTime()
    local burst = secretChatOutputBurst

    -- Only a readable message type discriminates two payloads. When the category
    -- is secret or absent the signature degenerates and two distinct messages
    -- landing on different frames within the window would merge into one, so an
    -- unreadable category always counts as a new message and never opens a burst.
    -- A frame index that already belongs to the burst also means a *new* message:
    -- Blizzard dispatches a payload at most once per frame.
    if described.messageTypeIDKnown and burst and burst.signature == described.signature
        and (now - burst.time) < 0.5 and not burst.frames[frameIndex] then
        burst.frames[frameIndex] = true
        burst.frameList[#burst.frameList + 1] = frameIndex
        return false, burst
    end

    if described.messageTypeIDKnown then
        secretChatOutputBurst = {
            signature = described.signature,
            time = now,
            frames = { [frameIndex] = true },
            frameList = { frameIndex },
        }
    else
        secretChatOutputBurst = nil
    end
    return true, secretChatOutputBurst
end

local function recordSecretChatOutput(frameIndex, described, isNewMessage, burst, suppress, reason, argCount)
    if not SanctuaryDB or not SanctuaryDB.debugEnabled then return end

    if not isNewMessage and burst and burst.debugSeq then
        local entry = SanctuaryDB.debugLog and SanctuaryDB.debugLog[#SanctuaryDB.debugLog]
        if entry and entry.seq == burst.debugSeq and entry.data then
            entry.data.frames = table.concat(burst.frameList, ",")
            entry.data.frameCount = #burst.frameList
            return
        end
    end

    local lockdown, lockdownKnown = readChatLockdown()
    debugLog("CHAT_OUTPUT", addRuntimeContext({
        frame = frameIndex,
        frames = burst and table.concat(burst.frameList, ",") or tostring(frameIndex),
        frameCount = burst and #burst.frameList or 1,
        action = suppress and "SUPPRESS_SECRET_SYSTEM" or "SECRET_VALUE",
        reason = reason or "unknown",
        chatLockdown = lockdown,
        chatLockdownKnown = lockdownKnown,
        msg = SECRET_VALUE_PLACEHOLDER,
        messageTypeID = described.messageTypeID,
        messageTypeIDKnown = described.messageTypeIDKnown,
        systemTypeID = described.systemTypeID,
        isSystemTypeID = described.isSystemTypeID,
        isSystemTypeIDKnown = described.isSystemTypeIDKnown,
        argCount = argCount or 0,
        filterEnabled = isEnabled() and isFilterOn("groupInvite") == true,
        strictGroupInviteSystemMessages = isFilterOn("strictGroupInviteSystemMessages") == true,
        soundGuardActive = isStaticPopupSoundSuppressed("PARTY_INVITE"),
    }))

    local entry = SanctuaryDB.debugLog and SanctuaryDB.debugLog[#SanctuaryDB.debugLog]
    if entry and burst then
        burst.debugSeq = entry.seq
    end
end

-- Frames seen but not wrapped are reported once each. A recording showing 11
-- frames seen for 10 wrapped had no way to say which one, or why.
local noteChatOutputWrapSkipped
do
local chatOutputWrapSkipped = setmetatable({}, { __mode = "k" })

noteChatOutputWrapSkipped = function(frameIndex, chatFrame, reason)
    if chatOutputWrapSkipped[chatFrame] == reason then return end
    chatOutputWrapSkipped[chatFrame] = reason
    debugLog("CHAT_OUTPUT", {
        frame = frameIndex,
        action = "WRAP_SKIPPED",
        reason = reason,
    })
end
end

local hookChatOutputDiagnostics
do
-- Chat windows are not all there at load. Retail opens an eleventh frame the
-- moment a whisper conversation or any temporary window is started, and this
-- scan only ever ran at ADDON_LOADED and at PLAYER_ENTERING_WORLD -- so a frame
-- born during the session printed straight past the envelope for the rest of it.
-- Vincent's 23/08 export says it in one line: DEGRADED (chat_frames=10/11).
local chatFrameCreationHooked = false

hookChatOutputDiagnostics = function()
    -- Post-hooks on the two functions that open a chat window, so the frame
    -- exists by the time we look. `hooksecurefunc` never replaces the function,
    -- which is what keeps this clear of Blizzard's taint rules on chat UI, and
    -- the scan below is idempotent -- it does not matter which frame was just
    -- created, or that two hooks fire for one window.
    if not chatFrameCreationHooked and type(hooksecurefunc) == "function" then
        chatFrameCreationHooked = true
        for _, opener in ipairs({ "FCF_OpenTemporaryWindow", "FCF_OpenNewWindow" }) do
            if type(_G[opener]) == "function" then
                pcall(hooksecurefunc, opener, function()
                    hookChatOutputDiagnostics()
                end)
            end
        end
    end

    for i = 1, 20 do
        local chatFrame = _G["ChatFrame" .. i]
        if chatFrame and not chatFrame.AddMessage then
            noteChatOutputWrapSkipped(i, chatFrame, "no_add_message")
        end
        if chatFrame and chatOutputWrapped[chatFrame] ~= chatFrame.AddMessage and chatFrame.AddMessage then
            local frameIndex = i
            local original = chatFrame.AddMessage
            local function wrappedAddMessage(self, text, ...)
                if chatOutputWrapped[self] ~= wrappedAddMessage then
                    return original(self, text, ...)
                end

                if isRestrictedValue(text) then
                    -- A secret system line cannot be read, so it cannot be told
                    -- apart from an invitation. Blizzard's filter registry skips
                    -- addon callbacks entirely on a secret payload, which leaves
                    -- this envelope as the only place the line can be stopped.
                    -- Hiding the whole system category here is a product
                    -- decision, taken knowingly and confined to the opt-in mode:
                    -- the predicate refuses in six other ways first.
                    local described = describeSecretOutputMessageType(...)
                    local suppress, reason = shouldSuppressSecretSystemOutput(text, described)
                    local isNewMessage, burst = trackSecretChatOutput(frameIndex, described)
                    recordSecretChatOutput(frameIndex, described, isNewMessage, burst,
                        suppress, reason, select("#", ...))
                    if suppress then return end
                    return original(self, text, ...)
                end

                local inviterName, patternIndex, patternKind = extractInviterFromSystemMessage(text)
                if inviterName then
                    -- The same decision `systemMessageFilter` takes, from the
                    -- same function -- always blocked first, the gate second.
                    -- This envelope exists because a 2026-06-25 recording showed
                    -- invite lines printed outside the filter registry in raid
                    -- and in instances; it used to spell that order out itself,
                    -- and an earlier spelling read the flag first, which let a
                    -- blocked name print its line in the open mode.
                    local suppress, reason, keyword, filterEnabled = false, "disabled", nil, false
                    if isEnabled() then
                        suppress, reason, keyword, filterEnabled =
                            decideInteraction("groupInvite", inviterName)
                    end
                    -- Which of the two halves decided, read off the reason
                    -- rather than asked a second time.
                    local alwaysBlocked = (reason == "blocked_name" or reason == "keyword")
                    local suppressedBy = alwaysBlocked and "always_blocked"
                        or (suppress and "filter" or "none")
                    local shouldBlock = suppress
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
                        alwaysBlocked = alwaysBlocked,
                        suppressedBy = suppressedBy,
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
                            filterEnabled = isEnabled() and isFilterOn("groupInvite") == true,
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
end

ns.hookChatOutputDiagnostics = hookChatOutputDiagnostics

-- StaticPopup_Show is also used by protected Blizzard UI such as CAMP/QUIT.
-- Retail live testing confirmed that wrapping it globally can break quit/logout
-- flows, so Sanctuary only adjusts the specific invite/duel dialog definitions.
-- Sound-guard machinery. Scoped: two dozen names below are private to it, and
-- a Lua chunk may only hold 200 live locals. What the rest of the file needs is
-- declared here.
local acquireProtectedPopupSoundGuard, guildInviteFrameSoundGuardToken, playAllowedProtectedPopupSounds, protectedPopupSoundGuardDialogs
local releaseGuildInviteFrameSoundGuard, releaseProtectedPopupSoundGuard, releaseProtectedPopupSoundGuards
local releaseStaleProtectedPopupSoundMute, restoreStaticPopupSoundAfterShow

do

local STATIC_POPUP_SOUND_GUARDS = {
    PARTY_INVITE = "groupInvite",
    DUEL_REQUESTED = "duel",
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
protectedPopupSoundGuardDialogs = setmetatable({}, { __mode = "k" })
local staticPopupOnShowGuardHooked = false
guildInviteFrameSoundGuardToken = nil

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

restoreStaticPopupSoundAfterShow = function(which, reason)
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
releaseStaleProtectedPopupSoundMute = function()
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

acquireProtectedPopupSoundGuard = function(which, reason)
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

releaseProtectedPopupSoundGuard = function(token, which, reason)
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

playAllowedProtectedPopupSounds = function(which, reason)
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

refreshInviteSoundMuteState = function()
    installStaticPopupSoundOnShowGuard()
    -- Armed, not "ticked": one always-blocked name is enough to need the guard,
    -- and empty lists with every filter unticked arm nothing at all -- the
    -- native sound then plays exactly as WoW intends.
    for which in pairs(STATIC_POPUP_SOUND_GUARDS) do
        local shouldSuppress = isProtectionArmed(which)
        setStaticPopupSoundSuppressed(which, shouldSuppress, shouldSuppress and "filter_enabled" or "filter_disabled")
    end

    if not isEnabled() then
        releaseProtectedPopupSoundGuards(nil, "filter_disabled")
        releaseGuildInviteFrameSoundGuard("filter_disabled")
        return
    end
    if not isProtectionArmed("DUEL_REQUESTED") then
        releaseProtectedPopupSoundGuards("DUEL_REQUESTED", "filter_disabled")
    end
    if not isProtectionArmed("guildInvite") then
        releaseGuildInviteFrameSoundGuard("filter_disabled")
    end
    if not isProtectionArmed("PARTY_INVITE") then
        releaseProtectedPopupSoundGuards("PARTY_INVITE", "filter_disabled")
        if unmaskVisiblePopup then
            unmaskVisiblePopup("PARTY_INVITE")
        end
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
-- Popup masking and guild-invite frame. Same reason as the block above: only
-- the names declared here leave the section.
local GUILD_INVITE_FRAME_KEY, applyPopupDecision, clearPendingGuildInviteFrameDecision, clearPendingPopupDecision
local consumePendingPopupDecision, countVisiblePopup, getGuildInviteFrame, guildInviteFrameLastHideSerial
local guildInviteFrameLastMaskSerial, hidePopupDialogSilently, hideVisiblePopupSilently, installGuildInviteFrameGuard
local isGuildInviteFrameProtectionActive, isGuildInviteFrameShown, isPopupProtectionActive, maskVisiblePopup
local scheduleVisiblePopupSilentHide, synchronizeGuildInviteFrameDecision, synchronizePopupDecision, unmaskAllInteractionPopups
local unmaskGuildInviteFrame

do

local maskedPopupState = setmetatable({}, { __mode = "k" })
local popupHideHooked = setmetatable({}, { __mode = "k" })
pendingPopupDecisions = {}
local popupDecisionSerial = 0
local POPUP_DECISION_MAX_AGE = 1.0
GUILD_INVITE_FRAME_KEY = "GUILD_INVITE_FRAME"

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

countVisiblePopup = function(which)
    local count = 0
    forEachStaticPopup(function(dialog)
        if dialog.IsShown and dialog:IsShown() and dialog.which == which then
            count = count + 1
        end
    end)
    return count
end

maskVisiblePopup = function(which)
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

unmaskAllInteractionPopups = function()
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

hidePopupDialogSilently = function(dialog, which, reason)
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

hideVisiblePopupSilently = function(which, reason)
    local hidden = 0
    forEachStaticPopup(function(dialog)
        if hidePopupDialogSilently(dialog, which, reason) then
            hidden = hidden + 1
        end
    end)
    return hidden
end

scheduleVisiblePopupSilentHide = function(which, reason)
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

clearPendingPopupDecision = function(which)
    pendingPopupDecisions[which] = nil
end

applyPopupDecision = function(which, shouldBlock)
    if shouldBlock then
        return maskVisiblePopup(which)
    end
    return unmaskVisiblePopup(which)
end

synchronizePopupDecision = function(which, shouldBlock, name, reason)
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

consumePendingPopupDecision = function(which)
    local decision = pendingPopupDecisions[which]
    if not decision then return nil end
    pendingPopupDecisions[which] = nil
    if (GetTime() - decision.at) > POPUP_DECISION_MAX_AGE then
        return nil
    end
    return decision
end

-- Armed on the filter OR on the always-blocked list. Without the second half a
-- blocked name would still flash its window and play its sound as soon as the
-- matching filter is unticked -- which is the nominal path of "everyone except
-- the people I block".
isPopupProtectionActive = function(which)
    if which == "PARTY_INVITE" or which == "DUEL_REQUESTED" then
        return isProtectionArmed(which)
    end
    return false
end

isGuildInviteFrameProtectionActive = function()
    return isProtectionArmed("guildInvite")
end

local guildInviteFrameHooked = false
local guildInviteFrameMaskedState = nil
guildInviteFrameLastMaskSerial = 0
guildInviteFrameLastHideSerial = 0

getGuildInviteFrame = function()
    return _G and _G.GuildInviteFrame or nil
end

isGuildInviteFrameShown = function(frame)
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

synchronizeGuildInviteFrameDecision = function(shouldBlock, inviter, reason)
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

installGuildInviteFrameGuard = function()
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


end

ns.maskVisiblePopup = maskVisiblePopup
ns.unmaskVisiblePopup = unmaskVisiblePopup
ns.unmaskAllInteractionPopups = unmaskAllInteractionPopups
ns.clearPendingPopupDecision = clearPendingPopupDecision
ns.clearPendingGuildInviteFrameDecision = clearPendingGuildInviteFrameDecision
ns.unmaskGuildInviteFrame = unmaskGuildInviteFrame

-- The master switch, in the core rather than in the interface: the header
-- control, the minimap right-click and the harness all flip protection the same
-- way, so none of them can forget to release a guard or to unmask a window.
function ns.setEnabled(enabled)
    if not SanctuaryCharDB then return isEnabled() end
    SanctuaryCharDB.overrides = SanctuaryCharDB.overrides or {}
    SanctuaryCharDB.overrides.enabled = enabled and true or false

    local newState = isEnabled()
    debugLog("TOGGLE", { enabled = newState })
    refreshInviteSoundMuteState()

    if newState then
        printSuccess(L["SANCTUARY_ENABLED"])
    else
        -- At OFF nothing Sanctuary hid may stay hidden: a masked dialog is
        -- invisible and still clickable.
        clearPendingPopupDecision("PARTY_INVITE")
        clearPendingPopupDecision("DUEL_REQUESTED")
        clearPendingGuildInviteFrameDecision()
        unmaskAllInteractionPopups()
        printMsg(COLOR_OFF .. L["SANCTUARY_DISABLED"] .. COLOR_RESET)
    end
    return newState
end

-- ============================================================================
-- SECTION H: Event Handlers (side effects happen HERE, not in filters)
-- ============================================================================

-- `decideInteraction`, `describeBlockAction` and `keywordOf` used to live here,
-- next to their first callers. They now sit under `getCharacterDecision`, with
-- `decideChat` and `decideBNetWhisper`: the chat filters need them too, and they
-- are registered several hundred lines above this section.

-- Which half of isProtectionArmed put the guard in place. In a report, "the
-- window was masked although the filter is off" is only readable with this.
local function describeArmedBy(kind)
    if isFilterOn(FILTER_KEY_BY_POPUP[kind] or kind) == true then return "filter" end
    return "blocked_list"
end

-- PARTY_INVITE_REQUEST: classify the inviter, synchronize with the secure
-- popup post-hook, then use Blizzard's native decline API when blocked.
function handlers.PARTY_INVITE_REQUEST(name, isTank, isHealer, isDamage,
    isNativeRealm, allowMultipleRoles, inviterGUID, questSessionActive)
    if not isProtectionArmed("PARTY_INVITE") then
        clearPendingPopupDecision("PARTY_INVITE")
        unmaskVisiblePopup("PARTY_INVITE")
        refreshInviteSoundMuteState()
        return
    end

    local shouldBlock, reason, detail = decideInteraction("PARTY_INVITE", name)
    local keyword = keywordOf(reason, detail)
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
        keyword = detail or "none",
        action = describeBlockAction(shouldBlock, reason),
        filterEnabled = isFilterOn("groupInvite") == true,
        armedBy = describeArmedBy("PARTY_INVITE"),
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
    if not isProtectionArmed("DUEL_REQUESTED") then
        clearPendingPopupDecision("DUEL_REQUESTED")
        unmaskVisiblePopup("DUEL_REQUESTED")
        releaseProtectedPopupSoundGuards("DUEL_REQUESTED", "filter_disabled_event")
        return
    end

    local shouldBlock, reason, detail = decideInteraction("DUEL_REQUESTED", playerName)
    local keyword = keywordOf(reason, detail)
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
        keyword = detail or "none",
        filterEnabled = isFilterOn("duel") == true,
        armedBy = describeArmedBy("DUEL_REQUESTED"),
        replayedSound = replayedSound and true or false,
        action = describeBlockAction(shouldBlock, reason),
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

    if not isProtectionArmed("guildInvite") then
        clearPendingGuildInviteFrameDecision()
        unmaskGuildInviteFrame()
        releaseGuildInviteFrameSoundGuard("filter_disabled_event")
        return
    end

    local shouldBlock, reason, detail = decideInteraction("guildInvite", inviter)
    local keyword = keywordOf(reason, detail)
    synchronizeGuildInviteFrameDecision(shouldBlock, inviter, reason)
    debugLog("GUILD_INVITE", {
        name = inviter,
        normalized = normalizeName(inviter),
        guild = guildName or "nil",
        reason = reason or "nil",
        keyword = detail or "none",
        filterEnabled = isFilterOn("guildInvite") == true,
        armedBy = describeArmedBy("guildInvite"),
        frameShown = isGuildInviteFrameShown() and true or false,
        frameAlpha = (getGuildInviteFrame() and getGuildInviteFrame().GetAlpha) and tostring(getGuildInviteFrame():GetAlpha()) or "nil",
        soundGuardActive = guildInviteFrameSoundGuardToken and true or false,
        action = describeBlockAction(shouldBlock, reason),
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
    if not isProtectionArmed("trade") then return end

    -- Trade partner detection is limited by the WoW API. Prefer the unit token,
    -- then fall back to the recipient label.
    local tradeName = UnitName("NPC")
        or (TradeFrameRecipientNameText and TradeFrameRecipientNameText:GetText())
        or nil
    if not tradeName or tradeName == "" then
        debugLog("TRADE", { action = "NO_PARTNER_NAME" })
        return
    end

    local shouldBlock, reason, detail = decideInteraction("trade", tradeName)
    local keyword = keywordOf(reason, detail)
    debugLog("TRADE", {
        name = tradeName,
        normalized = normalizeName(tradeName),
        reason = reason or "nil",
        keyword = detail or "none",
        filterEnabled = isFilterOn("trade") == true,
        armedBy = describeArmedBy("trade"),
        action = describeBlockAction(shouldBlock, reason),
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
local debugLogSocial
do
local lastSocialDebugByEvent = {}

debugLogSocial = function(eventName)
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

    if not isEnabled() or not isFilterOn("autoTrust") then
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
                -- Tracked under the name WITH its realm, the shape the blocked
                -- list keys on and the shape the right-click menu writes. The
                -- realm was built one line up and then thrown away by
                -- `normalizeName`, so the tracker held a bare pseudo and the
                -- ticker below asked "is <pseudo> blocked?" of a lookup that
                -- answers for one realm only: the player's own. A dungeon group
                -- is cross-realm by construction, so a harasser blocked as
                -- "Pseudo-AutreRoyaume" was not recognised there, and five
                -- minutes of standing still wrote him into "Toujours autorises"
                -- with source "trust" -- counted on the tile, answered by the
                -- tester -- while his blocked entry was still on the other
                -- panel. Decision 104 exists to make that pair impossible.
                --
                -- Deliberately not "is this pseudo blocked on any realm": that
                -- would take trust away from Cross-Dalaran because somebody
                -- blocked Cross-Hyjal, which is the same namesake mistake the
                -- blocked list dropped its bare-key fallback to end. One person,
                -- one realm, one key.
                --
                -- `normalizeName` still gates it, as the one rule that says what
                -- is left of a name: a roster entry with no pseudo in it ("-")
                -- is no more trackable than it is writable.
                if normalizeName(name) then
                    currentMembers[name] = true
                    if not SanctuaryCharDB.groupTracker[name] then
                        SanctuaryCharDB.groupTracker[name] = GetTime()
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
    if not isProtectionArmed("groupInvite") then return end

    local inviterName, patternIndex, patternKind = extractInviterFromSystemMessage(msg)
    if not inviterName then
        if SanctuaryDB and SanctuaryDB.debugEnabled and isRestrictedValue(msg) then
            -- Confirmed from Retail source: the message-event filter registry
            -- skips addon callbacks when the payload is a secret value, so
            -- strict mode only makes this line *eligible* for suppression here.
            -- SUPPRESS_* stays reserved for a suppression actually applied.
            local strictEligible = shouldSuppressSecretGroupInviteSystemMessage(msg)
            local lockdown, lockdownKnown = readChatLockdown()
            debugLog("SYSTEM_INVITE", addRuntimeContext({
                msg = SECRET_VALUE_PLACEHOLDER,
                result = strictEligible and "STRICT_POLICY_ELIGIBLE" or "SECRET_VALUE",
                filterEnabled = isFilterOn("groupInvite") == true,
                strictGroupInviteSystemMessages = isFilterOn("strictGroupInviteSystemMessages") == true,
                soundGuardActive = isStaticPopupSoundSuppressed("PARTY_INVITE"),
                chatLockdown = lockdown,
                chatLockdownKnown = lockdownKnown,
                argCount = select("#", ...),
            }))
        elseif SanctuaryDB and SanctuaryDB.debugEnabled and type(msg) == "string" then
            local lowerMsg = msg:lower()
            if lowerMsg:find("invit", 1, true) or lowerMsg:find("group", 1, true) then
                debugLog("SYSTEM_INVITE", addRuntimeContext({
                    msg = safeText(msg, 300, "nil"),
                    result = "NO_MATCH",
                    filterEnabled = isFilterOn("groupInvite") == true,
                    soundGuardActive = isStaticPopupSoundSuppressed("PARTY_INVITE"),
                    argCount = select("#", ...),
                }))
            end
        end
        return
    end

    local shouldBlock, reason, detail = decideInteraction("groupInvite", inviterName)
    local keyword = keywordOf(reason, detail)
    local result = "PASS_WHITELISTED"
    if shouldBlock then
        if reason == "keyword" then
            result = "SUPPRESS_KEYWORD"
        elseif reason == "blocked_name" then
            result = "SUPPRESS_BLOCKED_NAME"
        else
            result = "SUPPRESS_NOT_WHITELISTED"
        end
    end
    debugLog("SYSTEM_INVITE", addRuntimeContext({
        msg = safeText(msg, 300, "nil"),
        name = inviterName,
        pattern = patternIndex or "?",
        isWL = reason == "whitelist",
        keyword = detail or "none",
        result = result,
        filterEnabled = isFilterOn("groupInvite") == true,
        armedBy = describeArmedBy("groupInvite"),
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

-- The thirteen character-message handlers, generated from the same table their
-- filters are. `decideChat` has already answered; nothing below asks a question
-- of its own, and the row says what to do with the answer.
--
-- Four handler bodies used to stand here, spelling out the order the six filter
-- bodies had already spelt out. That is where a guard could be forgotten, and
-- where one was: CHAT_MSG_WHISPER had no "is this me" line while its filter did,
-- so a player who had blocked their own name saw their note journalled, counted
-- and announced -- the line itself having been let through.
--
-- The debug entry is written on the allowed path too. Three expectations read an
-- `action == "ALLOW"` entry, and a recording that only ever shows blocks cannot
-- answer "did Sanctuary see this message at all" -- the first question asked of
-- every report. An early return before the debug entry is a defect, not an
-- optimisation.
for _, row in ipairs(CHAT_KINDS) do
    handlers[row.event] = function(msg, sender, ...)
        -- The same verdict the chat filters read, and the only place it is
        -- committed: the throttle moves here, and so do the debug entry and the
        -- Journal line of a hidden repeat.
        local decision = ns.resolveChatDecision(row, msg, sender, select(9, ...))
        ns.commitChatDecision(decision)
        local reason, detail = decision.reason, decision.detail

        -- Nothing at all, not even a debug entry: the add-on is off, or the
        -- player is talking to themselves. Neither decides anything about
        -- anybody, and neither ever did.
        if reason == "disabled" or reason == "self" then return end

        -- A repeat the anti-spam hid. `commitChatDecision` has already written
        -- its own debug entry and its Journal line, and nothing else is due:
        -- no session count, no announcement, no second trace.
        if decision.spam == "masked" then return end

        local extra = { filterEnabled = decision.gateOpen }
        if row.debugExtra == "channelMode" then
            extra.channelMode = isFilterOn("channelMode") or "none"
        end

        if reason == "filter_off" then
            -- Group chat stays quiet on a pass: seven events, every line of a
            -- dungeon run, and the gate it never consults is what "filter_off"
            -- means there. This is what the old group handler already did.
            if row.quietPass then return end
            debugLogChatDecision(row.logType, sender, msg,
                "PASS_FILTER_DISABLED", reason, nil, extra)
            return
        end

        debugLogChatDecision(row.logType, sender, msg,
            describeBlockAction(decision.hide, reason), reason, detail, extra)
        if not decision.hide then return end

        logBlock(row.logType, sender, msg, nil, keywordOf(reason, detail))
        if row.closesTab then closeBlockedWhisperTabs(sender, false) end
    end
end

-- The second consumer of `decideBNetWhisper`, the filter being the first. The
-- decision, the invariant and every field published here come from that one
-- function; nothing is asked again.
function handlers.CHAT_MSG_BN_WHISPER(msg, sender, ...)
    local block, reason, info = decideBNetWhisper(sender, ...)
    if reason == "disabled" then return end

    if reason == "filter_off" then
        debugLogChatDecision("bn_whisper", info.accountName, msg, "PASS_FILTER_DISABLED", reason, nil, {
            filterEnabled = false,
            rawSender = info.rawSender,
            bnetSenderID = info.bnetSenderID,
            bnetResolvedByID = info.bnetResolvedByID,
        })
        return
    end

    debugLogChatDecision("bn_whisper", info.accountName, msg,
        describeBlockAction(block, reason), reason, nil, {
            filterEnabled = true,
            bnetWhitelisted = info.bnetWhitelisted,
            inGroup = info.inGroup,
            bnetCache = ns.getBNetWhitelistCacheSize and ns.getBNetWhitelistCacheSize() or "?",
            rawSender = info.rawSender,
            bnetSenderID = info.bnetSenderID,
            bnetResolvedByID = info.bnetResolvedByID,
        })
    if not block then return end

    -- Journalled under `whisper`, not `bn_whisper`: the Journal shows the person
    -- what was hidden from them, and "a whisper" is what it was. The raw sender
    -- is what closes the tab -- Blizzard keys a Battle.net tab on the token it
    -- handed over, not on the account name we resolved from it.
    logBlock("whisper", info.accountName, msg, nil, keywordOf(reason, nil))
    closeBlockedWhisperTabs(sender, true)
end

-- ============================================================================
-- SECTION I: Slash Command Handler
-- ============================================================================

-- Scoped block. Lua caps a chunk at 200 live locals and this section holds two
-- dozen of them, none of which is read outside it: everything the rest of the
-- addon needs from here is published on `ns` before the block closes.
do

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

    -- The raw tier the name falls into, and only that: the tester's line has to
    -- read "blocked, but the filter is off" rather than a single merged answer,
    -- so this deliberately asks the question the gate does not enter into. It is
    -- a report, never a decision -- the decision is `wouldBlock`, below.
    local shouldBlock, reason, keyword = getCharacterDecision(target)
    local normalMessage = buildInviteSystemMessage(target, false)
    local alreadyGroupMessage = buildInviteSystemMessage(target, true)
    local groupInviteFilterEnabled = isEnabled() and isFilterOn("groupInvite") == true
    -- Armed, not ticked: with a name in the always-blocked list the window is
    -- masked even when the group-invite filter is off, and a simulation that
    -- answered "pass" there would describe a screen nobody will see.
    local popupProtectionActive = isPopupProtectionActive("PARTY_INVITE")
    -- What would actually happen, from the one function that decides it. Spelt
    -- out here, the simulation could describe a screen the add-on would not
    -- produce -- which is the one thing a simulation may not do.
    local wouldBlock = (decideInteraction("groupInvite", target))
    local popupAction = "pass"
    if popupProtectionActive then
        popupAction = wouldBlock and "mask" or "show"
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
        wouldDecline = (popupProtectionActive and wouldBlock) and true or false,
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
    -- No always-blocked probe here either: the Battle.net invariant next to
    -- `bnetWhisperFilter` says the list and the patterns never reach this
    -- channel, and a diagnostic that reported a verdict the filter cannot reach
    -- would be the one place claiming otherwise.
    local filterEnabled = isEnabled() and isFilterOn("whisper") == true
    local bnetWhitelisted = isBNetWhitelisted(decisionName)
    local inGroup = isBNetSenderInGroup and isBNetSenderInGroup(decisionName) or false
    local filtered = bnetWhisperFilter(nil, "CHAT_MSG_BN_WHISPER", "Sanctuary diagnostic", rawSender,
        getBNetWhisperPayloadArgs(rawSender, bnSenderID)) and true or false
    local reason = "not_whitelisted"

    if not isEnabled() then
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
        filterEnabled = filterEnabled,
        bnetWhitelisted = result.bnetWhitelisted,
        inGroup = result.inGroup,
        bnetSenderID = bnetSender.bnSenderIDState,
        bnetResolvedByID = bnetSender.resolvedByID,
    })

    return result
end

-- The argument is a name or a number. Typing a friend's name is how the person
-- checks the contact they actually care about; the index stays because it is the
-- only way to reach a friend whose name is awkward to type.
local function findBNetFriendByName(text)
    local wantedAccount = normalizeBNetName(text)
    local wantedCharacter = normalizeName(text)
    if not wantedAccount and not wantedCharacter then return nil, nil end

    local numFriends = 0
    pcall(function() numFriends = BNGetNumFriends() or 0 end)
    for i = 1, numFriends do
        local candidate = getBNetFriendInfo(i)
        if candidate then
            if wantedAccount and normalizeBNetName(candidate.accountName) == wantedAccount then
                return candidate, i
            end
            local gameInfo = candidate.gameAccountInfo
            local characterName = gameInfo and gameInfo.characterName
            if wantedCharacter and characterName and characterName ~= ""
                and normalizeName(characterName) == wantedCharacter then
                return candidate, i
            end
        end
    end
    return nil, nil
end

local function simulateBNetFriend(argText)
    local text = trimCommandText(argText)
    local friendIndex = tonumber(text)
    local info
    if friendIndex then
        if friendIndex < 1 then friendIndex = 1 end
        info = getBNetFriendInfo(friendIndex)
    elseif text ~= "" then
        info, friendIndex = findBNetFriendByName(text)
    else
        friendIndex = 1
        info = getBNetFriendInfo(1)
    end

    if not info or not info.accountName or info.accountName == "" then
        friendIndex = friendIndex or 1
        local result = {
            kind = "bnet",
            label = "friend #" .. friendIndex,
            friendIndex = friendIndex,
            available = false,
            filtered = true,
            shouldBlock = true,
            reason = "bnet_api_unavailable",
            filterEnabled = isEnabled() and isFilterOn("whisper") == true,
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
    -- No `:keyword` suffix: a pattern can never be the reason on this channel.
    local reason = result.reason or "unknown"

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

-- Answers what the masking predicate would decide right now for a hypothetical
-- secret system line. It writes a CHAT_TEST entry and nothing else: no
-- CHAT_OUTPUT, so a diagnostic can never inflate the instance markers a
-- recording is read on.
local function runChatLockdownDiagnostic()
    local armed, reason = evaluateStrictSecretSuppression()
    local context = getRuntimeContext()
    local lockdown, lockdownKnown = readChatLockdown()
    local health = ns.getInstrumentationHealth()

    local contextLabel = "world"
    if context.inInstance then
        contextLabel = "instance"
    elseif context.inRaid then
        contextLabel = "raid"
    elseif context.inGroup then
        contextLabel = "group"
    end

    local result = {
        available = true,
        kind = "lockdown",
        armed = armed and true or false,
        reason = reason or "unknown",
        strict = isFilterOn("strictGroupInviteSystemMessages") == true,
        filter = isFilterOn("groupInvite") == true,
        context = contextLabel,
        inInstance = context.inInstance and true or false,
        lockdown = lockdownKnown and (lockdown and "true" or "false") or "unknown",
        frames = tostring(health.chatFramesWrapped) .. "/" .. tostring(health.chatFramesSeen),
    }
    debugLog("CHAT_TEST", result)
    return result
end

local function runChatDiagnostic(kind)
    local normalizedKind = trimCommandText(kind):lower()
    if normalizedKind == "" then normalizedKind = "invite" end
    if normalizedKind == "lockdown" then
        return runChatLockdownDiagnostic()
    end
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
    -- The whole decision, gate included, from the one function that takes it.
    -- It used to read the trust decision and the flag separately and multiply
    -- them, which left the always-blocked gate out: a name on the blocked list,
    -- with the group-invite filter unticked, was reported "visible" whether the
    -- envelope had caught it or not -- the diagnostic said nothing was wrong on
    -- exactly the path the blocked list exists for.
    local shouldBlock, reason, _, filterEnabled = false, "disabled", nil, false
    if isEnabled() then
        shouldBlock, reason, _, filterEnabled = decideInteraction("groupInvite", inviterName or target)
    end
    local expectedGuarded = shouldBlock

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
    if result.kind == "lockdown" then
        return string.format(
            "Diagnostic chat lockdown: armed=%s reason=%s strict=%s filter=%s context=%s lockdown=%s frames=%s",
            result.armed and "yes" or "no",
            result.reason or "unknown",
            result.strict and "on" or "off",
            result.filter and "on" or "off",
            result.context or "unknown",
            tostring(result.lockdown),
            tostring(result.frames)
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

-- Split in two since 1.0.0: the single diagnostic played both sounds inside one
-- call, which is precisely the case where nobody can tell whether they heard two
-- sounds or one. Two buttons, one sound each, checked by ear one after the other.
local function runSoundDiagnostic(kind)
    local normalizedKind = trimCommandText(kind):lower()
    if normalizedKind ~= "open" then normalizedKind = "invite" end

    local sound
    if normalizedKind == "open" then
        sound = (SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPEN) or "igMainMenuOpen"
    else
        sound = capturePartyInviteOriginalSound()
    end

    local played = sound and pcall(PlaySound, sound) or false
    local result = {
        kind = normalizedKind,
        sound = sound,
        played = played and true or false,
        guardActive = partyInviteSoundGuardDepth > 0,
    }
    debugLog("SOUND_TEST", {
        kind = normalizedKind,
        sound = tostring(sound or "nil"),
        played = result.played,
        guardActive = result.guardActive,
    })
    return result
end

local function formatSoundDiagnosticResult(result)
    if not result.sound then
        return string.format("Diagnostic sound %s: ERROR (native sound unavailable)",
            result.kind or "unknown")
    end
    return string.format(
        "Diagnostic sound %s: sound=%s played=%s guard=%s",
        result.kind or "unknown",
        tostring(result.sound),
        result.played and "yes" or "no",
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
-- `manual = true` means "run them all" skips it, like `sensitive`: a bulk run
-- must not fire two sounds back to back, since the whole point of splitting them
-- is hearing one, then the other.
ns.DIAGNOSTIC_CATALOG = {
    {
        id = "sim_invite",
        labelKey = "DIAG_SIM_INVITE",
        argKey = "DIAG_ARG_NAME",
        argDefault = "SanctuaryTest",
        run = function(argText)
            return { text = formatSimulationResult(simulateInvite(argText or "")) }
        end,
    },
    {
        id = "sim_bnet",
        labelKey = "DIAG_SIM_BNET",
        run = function(argText)
            return { text = formatBNetSimulationResult(simulateBNetWhisper(argText or "")) }
        end,
    },
    {
        id = "sim_bnetfriend",
        labelKey = "DIAG_SIM_BNETFRIEND",
        argKey = "DIAG_ARG_NAME_OR_INDEX",
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
        run = function()
            return { text = formatChatDiagnosticResult(runChatDiagnostic("invite")) }
        end,
    },
    {
        id = "diag_chat_lockdown",
        labelKey = "DIAG_CHAT_LOCKDOWN",
        run = function()
            return { text = formatChatDiagnosticResult(runChatDiagnostic("lockdown")) }
        end,
    },
    {
        id = "diag_sound_open",
        labelKey = "DIAG_SOUND_OPEN",
        tipKey = "DIAG_TIP_SOUND",
        manual = true,
        run = function()
            return { text = formatSoundDiagnosticResult(runSoundDiagnostic("open")) }
        end,
    },
    {
        id = "diag_sound_invite",
        labelKey = "DIAG_SOUND_INVITE",
        tipKey = "DIAG_TIP_SOUND",
        manual = true,
        run = function()
            return { text = formatSoundDiagnosticResult(runSoundDiagnostic("invite")) }
        end,
    },
    {
        id = "diag_popup_invite",
        labelKey = "DIAG_POPUP_INVITE",
        tipKey = "DIAG_TIP_POPUP",
        popupKind = "invite",
    },
    {
        id = "diag_popup_duel",
        labelKey = "DIAG_POPUP_DUEL",
        tipKey = "DIAG_TIP_POPUP",
        popupKind = "duel",
    },
    {
        id = "diag_popup_guild",
        labelKey = "DIAG_POPUP_GUILD",
        tipKey = "DIAG_TIP_POPUP",
        popupKind = "guild",
    },
    {
        id = "diag_popup_list",
        labelKey = "DIAG_POPUP_LIST",
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

end -- diagnostics scope

-- /sanc and /sanctuary open the window. Nothing else: every diagnostic is a
-- button of the Diagnostics tab, so there is no command list to remember, no
-- argument to mistype, and no way to fire a diagnostic by accident.
SLASH_SANCTUARY1 = "/sanctuary"
SLASH_SANCTUARY2 = "/sanc"
SlashCmdList["SANCTUARY"] = function()
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

-- 1.0.0 changes what a setting means, not only where it is stored: the two
-- switches of questions 1 and 2 now decide what the per-filter values are worth.
-- Carrying a 0.3.x file forward would therefore need a translation table for
-- every combination, and every one of those translations would be a guess about
-- what the person meant. The settings go back to the defaults instead.
--
-- The lists go with them. Keeping them meant a conversion -- the blocked list
-- is keyed by realm in 1.0.0 and was not before -- and a conversion is another
-- guess about what someone meant, written once and lived with forever. There is
-- one user today, she is told, and she types her lists again once.
--
-- Idempotent by construction -- the rebuilt file carries schemaVersion 2, so a
-- second load falls straight through to fillMissingDefaults.
--
-- Two files, two stamps, two independent decisions. The account file is written
-- once per account, the character file once per character: the first character
-- to load 1.0.0 stamps the account file, and every other character still logs in
-- carrying a v1 file of its own. Deciding both from the account stamp would send
-- those characters through `fillMissingDefaults`, which adds what is missing and
-- overwrites nothing -- so an `overrides.enabled = false` written by 0.3.2 (a
-- right-click on the minimap button is the ordinary way to get one) would
-- survive and leave Sanctuary silently off on that character.
local function resetAccountToSchemaV2()
    -- Not a setting, and that is the whole reason it is the one thing that
    -- travels: this flag is the only record `releaseStaleProtectedPopupSoundMute`
    -- can read to lift a MuteSoundFile left behind by the previous session. A
    -- mute survives /reload and relogging -- only a full client restart clears
    -- it -- and the first load of 1.0.0 always goes through this reset. Dropped
    -- here, the game's generic panel sounds stay off with no way out in game,
    -- which is a broken client, not a forgotten preference.
    local carriedPopupSoundMuted = SanctuaryDB and SanctuaryDB.protectedPopupSoundMuted

    SanctuaryDB = deepCopy(ACCOUNT_DEFAULTS)

    if carriedPopupSoundMuted then
        SanctuaryDB.protectedPopupSoundMuted = true
    end
    invalidateWhitelist()
end

local function resetCharacterToSchemaV2()
    SanctuaryCharDB = deepCopy(CHARACTER_DEFAULTS)
    invalidateWhitelist()
end

-- Nothing inside this file needs both halves at once -- ADDON_LOADED decides
-- them one file at a time -- but the whole 1.0.0 reset stays reachable by name.
ns.resetToSchemaV2 = function()
    resetAccountToSchemaV2()
    resetCharacterToSchemaV2()
end

local function needsSchemaReset(store)
    if not store then return false end
    local stored = tonumber(store.schemaVersion)
    return stored == nil or stored < 2
end

function handlers.ADDON_LOADED(addonName)
    if addonName ~= ADDON_NAME then return end

    -- Initialize SavedVariables
    if not SanctuaryDB then
        SanctuaryDB = deepCopy(ACCOUNT_DEFAULTS)
    elseif needsSchemaReset(SanctuaryDB) then
        resetAccountToSchemaV2()
    else
        fillMissingDefaults(SanctuaryDB, ACCOUNT_DEFAULTS)
    end

    if not SanctuaryCharDB then
        SanctuaryCharDB = deepCopy(CHARACTER_DEFAULTS)
    elseif needsSchemaReset(SanctuaryCharDB) then
        resetCharacterToSchemaV2()
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

    -- One line at load, and only one. The Leatrix and BadBoy notices went with
    -- 1.0.0: neither carried any compatibility logic, they were only a message,
    -- and a session that starts with three unexplained lines reads as a fault.
    if isEnabled() then
        printMsg(COLOR_ON .. L["ADDON_LOADED_ACTIVE"] .. COLOR_RESET)
    else
        printMsg(COLOR_OFF .. L["ADDON_LOADED_INACTIVE"] .. COLOR_RESET)
    end

    -- A mute survives /reload and relogging, so one left behind by a previous
    -- session would still be silencing the game's panel sounds right now. No
    -- guard can be active at load, so this is the safe point to lift it.
    releaseStaleProtectedPopupSoundMute()

    -- Keep invite audio suppression aligned with the effective setting.
    refreshInviteSoundMuteState()
    installGuildInviteFrameGuard()

    -- Said once the SavedVariables are in place, and idempotent: this is the
    -- other half of the same call in PLAYER_ENTERING_WORLD, which fires at
    -- every loading screen.
    ns.checkJournalCapacityAlert()

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
    local lockdown, lockdownKnown = readChatLockdown()
    debugLog("WORLD", addRuntimeContext({
        isInGuild = IsInGuild() and true or false,
        isInGroup = IsInGroup() and true or false,
        initial = not hasEnteredWorld,
        chatLockdown = lockdown,
        chatLockdownKnown = lockdownKnown,
    }))

    -- Reset session-only tracking once at login, not on every dungeon/loading
    -- screen transition. The previous behavior restarted the five-minute timer
    -- whenever PLAYER_ENTERING_WORLD fired inside an instance.
    if SanctuaryCharDB and not hasEnteredWorld then
        wipe(SanctuaryCharDB.groupTracker)
    end
    hasEnteredWorld = true
    -- Locked per level per session, so a dungeon run does not repeat it.
    ns.checkJournalCapacityAlert()
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

    local lockdown, lockdownKnown = readChatLockdown()
    debugLog("PLAYER_STATE", addRuntimeContext({
        event = eventName,
        chatLockdown = lockdown,
        chatLockdownKnown = lockdownKnown,
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
    -- The two chat events whose sender is not a character. Every other one is
    -- registered from `CHAT_KINDS` just below, so a kind can never end up with
    -- a filter, a handler and no event to fire it.
    "CHAT_MSG_SYSTEM",
    "CHAT_MSG_BN_WHISPER",
}

for _, row in ipairs(CHAT_KINDS) do
    events[#events + 1] = row.event
end

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
    if not isFilterOn("autoTrust") then return end
    if not SanctuaryCharDB or not SanctuaryCharDB.groupTracker then return end
    if not SanctuaryDB then return end

    local threshold = (SanctuaryDB.temporalGroupTrust.trustThresholdMinutes or 5) * 60
    local now = GetTime()

    for name, joinTime in pairs(SanctuaryCharDB.groupTracker) do
        if (now - joinTime) >= threshold then
            -- Never over the blocked list. `ns.addAllowed` displaces what it
            -- finds there -- decision 104 -- and the two hand gestures that
            -- call it show which list the name left, with an Annuler beside
            -- it. This ticker has no screen: it drops the `displaced` answer on
            -- the floor and prints nothing (decision 78 took the "X ajoute"
            -- line away). So a harasser explicitly put in "Toujours bloques"
            -- only had to stay five minutes in the group to be taken out of it,
            -- written back with source "trust", and let through -- invites,
            -- whispers, sounds -- without a word to the person who blocked
            -- them. Staying in the group was the whole exploit.
            --
            -- Blocked beats every trust source, in both scopes: that is what
            -- the list is for, and `classifyName` already answers that way. The
            -- one place that did not was this write.
            --
            -- Dropped from the tracker as well as skipped, so the same name is
            -- not weighed again every thirty seconds for as long as the group
            -- lasts. Unblocking somebody later starts their five minutes over,
            -- which is the trust this rule is about: freshly earned, not banked
            -- while they were blocked.
            --
            -- `name` carries its realm: `refreshGroupTracker` keys the tracker
            -- that way precisely so this lookup can answer, and so the write
            -- below displaces the right entry. An entry inherited from a build
            -- that keyed the tracker on the bare pseudo still reads as one --
            -- the player's own realm, as it always did -- and the next roster
            -- update replaces it with the qualified form.
            --
            -- What holds the invariant is no longer this line, though: it asks
            -- `findBlockedKey`, which reads the exact names alone, and somebody
            -- caught by a pattern walked past it. `ns.addAllowed` refuses a
            -- source-"trust" write on everything the always-blocked door answers
            -- for, patterns included, so the rule now lives at the write itself.
            -- This test is kept for what it costs -- a lookup instead of a
            -- write -- and because it says out loud, here, what this ticker will
            -- not do.
            if not ns.findBlockedKey(name) then
                -- Goes through the same write the panel and the right-click
                -- menu use, so an automatically trusted contact is an entry
                -- like any other -- shown in its own group, and removable.
                -- Nothing is printed: the panel is where it shows up.
                ns.addAllowed(name, "trust")
            end
            SanctuaryCharDB.groupTracker[name] = nil
        end
    end
end)

-- Minimal notification ticker (for "minimal" mode).
-- "Only if something new was blocked": the count is compared to the last one
-- announced, so an idle session stays silent instead of repeating the same
-- number every five minutes.
C_Timer.NewTicker(60, function()
    if not SanctuaryDB then return end
    if SanctuaryDB.notifications.mode ~= "minimal" then return end
    if not isEnabled() then return end
    if not SanctuaryCharDB then return end

    local stats = SanctuaryCharDB.sessionStats
    local count = stats.blockedCount or 0
    local announced = Sanctuary.lastAnnouncedBlockedCount or 0
    if count > announced then
        local interval = (SanctuaryDB.notifications.minimalIntervalMinutes or 5) * 60
        local now = GetTime()
        if not Sanctuary.lastMinimalNotif or (now - Sanctuary.lastMinimalNotif) >= interval then
            printMsg(string.format(L["BLOCKED_SESSION"], COLOR_WARN .. count .. COLOR_RESET))
            Sanctuary.lastMinimalNotif = now
            Sanctuary.lastAnnouncedBlockedCount = count
        end
    end
end)
