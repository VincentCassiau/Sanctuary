-- Offline check of a QA recording.
--
-- Usage: lua tests/check_qa_run.lua <SavedVariables/Sanctuary.lua>
--
-- The settings file the game writes on exit is the record. This reads it and
-- applies the closing checks that used to be done by scrolling an exported text
-- by hand: which build produced it, whether the instrumentation was running,
-- and whether each scenario left the entry it was supposed to leave.
--
-- The rules are not reimplemented here. Sanctuary.lua is loaded with the few
-- client globals it touches at load time, and the same getReportMarkers /
-- getInstrumentationVerdict the addon runs in game are applied to the file --
-- so this check and the in-game summary can never disagree.

local path = arg and arg[1]
if not path then
    io.stderr:write("usage: lua tests/check_qa_run.lua <SavedVariables/Sanctuary.lua>\n")
    os.exit(2)
end

local scriptPath = (arg and arg[0]) or "tests/check_qa_run.lua"
local scriptDir = scriptPath:match("^(.*)[/\\][^/\\]+$") or "."
local repoRoot = scriptDir:match("^(.*)[/\\]tests$") or "."

-- ---------------------------------------------------------------------------
-- Load the recording
-- ---------------------------------------------------------------------------

local saved = {}
local chunk, loadErr = loadfile(path, "t", saved)
if not chunk then
    io.stderr:write("cannot read the settings file: " .. tostring(loadErr) .. "\n")
    os.exit(2)
end
local ok, runErr = pcall(chunk)
if not ok then
    io.stderr:write("the settings file is not valid Lua: " .. tostring(runErr) .. "\n")
    os.exit(2)
end
if type(saved.SanctuaryDB) ~= "table" then
    io.stderr:write("no SanctuaryDB in " .. path .. " -- is this the right file?\n")
    os.exit(2)
end

-- ---------------------------------------------------------------------------
-- Load the addon's own rules
-- ---------------------------------------------------------------------------

GetLocale = function() return "frFR" end
GetTime = function() return 0 end
time = function() return 0 end
date = function() return os.date("%Y-%m-%d %H:%M:%S") end
GetNormalizedRealmName = function() return nil end
issecretvalue = function() return false end
canaccessvalue = function() return true end
hooksecurefunc = function() end
C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
CreateFrame = function()
    local frame = {}
    function frame:RegisterEvent() end
    function frame:UnregisterEvent() end
    function frame:SetScript() end
    return frame
end
SlashCmdList = {}
UNKNOWNOBJECT = "Unknown"
STATICPOPUP_NUMDIALOGS = 4
wipe = function(tbl) for key in pairs(tbl) do tbl[key] = nil end return tbl end

local ns = {}
assert(loadfile(repoRoot .. "/Locales.lua"))("Sanctuary", ns)
assert(loadfile(repoRoot .. "/Sanctuary.lua"))("Sanctuary", ns)

local db = saved.SanctuaryDB
local log = db.debugLog or {}
local manifest = db.reportManifest
local markers = ns.getReportMarkers(log)
local verdict, verdictDetail = ns.getInstrumentationVerdict(markers)

-- ---------------------------------------------------------------------------
-- Report
-- ---------------------------------------------------------------------------

local blocking, warnings = 0, 0

local function line(text) print(text) end
local function state(label, value, level)
    local tag = "  ok  "
    if level == "blocking" then
        tag = " FAIL "
        blocking = blocking + 1
    elseif level == "warn" then
        tag = " warn "
        warnings = warnings + 1
    end
    print(string.format("[%s] %-34s %s", tag, label, tostring(value)))
end

line("=== SANCTUARY - CONTROLE DE RELEVE ===")
line("Fichier   : " .. path)

if manifest then
    line(string.format("Build     : %s | version %s | interface %s",
        tostring(manifest.addonMetaBuild or manifest.build),
        tostring(manifest.version), tostring(manifest.addonMetaInterface)))
    line(string.format("Client    : %s build %s interface %s",
        tostring(manifest.clientVersion), tostring(manifest.clientBuild),
        tostring(manifest.clientInterface)))
    line(string.format("Ecrit le  : %s (%s)", tostring(manifest.savedAt),
        tostring(manifest.trigger)))
else
    -- Before this build the settings file carried no identity of its own; the
    -- snapshot in the log is the fallback, and it is worth saying which one was
    -- used so a reader does not take one for the other.
    line("Build     : (pas de manifeste -- releve produit par un build anterieur)")
    line(string.format("Snapshot  : build %s | version %s | interface %s",
        tostring(markers.addonMetaBuild), tostring(markers.addonMetaVersion),
        tostring(markers.addonMetaInterface)))
end
line("")

-- Instrumentation: the one value that can void a whole session.
state("API de filtrage chat", tostring(markers.chatFilterApiUsed),
    verdict == "blocking" and "blocking" or (verdict == "unknown" and "warn" or nil))
state("Frames de chat observees",
    tostring(markers.chatFramesWrapped) .. " / " .. tostring(markers.chatFramesSeen),
    (verdict == "degraded" and (verdictDetail or ""):find("chat_frames", 1, true)) and "warn" or nil)
state("Type de message systeme", tostring(markers.systemChatTypeID),
    (markers.systemChatTypeID == nil or markers.systemChatTypeID == "unknown") and "warn" or nil)
state("Snapshots enregistres", markers.snapshots, markers.snapshots == 0 and "blocking" or nil)
line("")

-- Scenario markers: one line each, instead of five searches through the export.
state("F1 ligne chat non filtree", markers.chatOutputNoMatch and "presente" or "absente",
    not markers.chatOutputNoMatch and "warn" or nil)
state("F2 fenetre d'invitation masquee", markers.popupMaskAwaitingEvent and "presente" or "absente",
    not markers.popupMaskAwaitingEvent and "warn" or nil)
state("F3 entree en instance", markers.worldInInstance and "presente" or "absente",
    not markers.worldInInstance and "warn" or nil)
state("F4 mort / resurrection", markers.playerState and "presente" or "absente",
    not markers.playerState and "warn" or nil)
line("")

-- Retention: a report that looks complete while the incident fell off the front
-- is the failure mode this accounting exists for.
local stats = db.debugLogStats or {}
local produced = tonumber(stats.produced) or #log
local dropped = tonumber(stats.dropped) or 0
state("Entrees de debug", string.format("%d gardees / %d produites / %d perdues",
    #log, produced, dropped), dropped > 0 and "warn" or nil)
state("Journal de blocages", tostring(db.log and #db.log or 0))
line("")

if blocking > 0 then
    line("VERDICT : ECHEC BLOQUANT -- ce releve n'est pas exploitable.")
    os.exit(1)
elseif warnings > 0 then
    line(string.format("VERDICT : EXPLOITABLE AVEC RESERVES (%d point(s) a signaler).", warnings))
else
    line("VERDICT : RELEVE COMPLET ET EXPLOITABLE.")
end
