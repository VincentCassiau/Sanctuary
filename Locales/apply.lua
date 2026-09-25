local _, ns = ...

-- ============================================================================
-- Builds `ns.L`, the one table the add-on reads a string from: the English
-- reference, then the client's language laid over it, key by key. Loaded after
-- every language file, before the add-on's own files.
--
-- The table is emptied and refilled IN PLACE, never replaced. Sanctuary.lua and
-- SanctuaryUI.lua take `local L = ns.L` the moment they load, and a new table
-- would leave both of them reading the old one.
-- ============================================================================

-- Which file a client locale reads, when it is not its own name. Spain and
-- Latin America share one Spanish file. enGB never gets here: that client
-- answers enUS. A locale with no file at all reads English.
local LOCALE_FILES = { esES = "es", esMX = "es" }

-- German writes every noun with a capital, in the middle of a sentence too: the
-- label of a block keeps its capital in the chat line, where the other languages
-- fold it to lower case.
local KEEPS_LABEL_CASE = { deDE = true }

local L = ns.L or {}
ns.L = L

function ns.applyLocale(code)
    for key in pairs(L) do L[key] = nil end
    local english = ns.locales.enUS
    for key, value in pairs(english) do L[key] = value end
    local overrides = ns.locales[LOCALE_FILES[code] or code]
    if overrides and overrides ~= english then
        for key, value in pairs(overrides) do L[key] = value end
    end
    ns.localeKeepsLabelCase = (overrides and KEEPS_LABEL_CASE[code]) or false
end

-- The languages a player can pick for Sanctuary alone, in the Advanced tab, in
-- the order the menu lists them. Each is named in itself: somebody who cannot
-- read the current language has to be able to find their own.
ns.LOCALE_CHOICES = {
    { code = "enUS", name = "English" },
    { code = "frFR", name = "Français" },
    { code = "deDE", name = "Deutsch" },
    { code = "esES", name = "Español" },
    { code = "ptBR", name = "Português" },
    { code = "ruRU", name = "Русский" },
    { code = "itIT", name = "Italiano" },
}

-- A language can be picked only if its file shipped with this copy.
function ns.isLocaleAvailable(code)
    return ns.locales[LOCALE_FILES[code] or code] ~= nil
end

-- What a saved choice means: "auto" follows the game, a language this copy
-- ships is that language, and anything else -- a code from a later version, a
-- value an editor broke -- is read as "auto" rather than trusted.
function ns.normalizeLocaleChoice(value)
    if type(value) == "string" then
        for _, choice in ipairs(ns.LOCALE_CHOICES) do
            if choice.code == value and ns.isLocaleAvailable(value) then return value end
        end
    end
    return "auto"
end

ns.applyLocale(GetLocale())
