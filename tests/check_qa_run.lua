-- Offline check of a QA recording.
--
-- Usage: lua tests/check_qa_run.lua <SavedVariables/Sanctuary.lua>
--
-- Exit codes: 0 complete, 1 blocking failure, 2 unusable input, 3 reserves.
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

-- The instrumentation is graded on the manifest when there is one, and only
-- falls back to the last SNAPSHOT still in the log otherwise. The log rotates
-- at its retention limit and is not guaranteed to still hold a snapshot at the
-- end of a session; the manifest is rewritten at PLAYER_LOGOUT from the live
-- values. Reading the build from one and the instrumentation from the other is
-- how a perfectly usable recording got declared unexploitable.
--
-- The grading rule itself is not duplicated: whichever source is used, the same
-- ns.getInstrumentationVerdict decides.
local instrumentation, instrumentationSource = markers, "journal"
if manifest and manifest.chatFilterApiUsed ~= nil then
    instrumentation = {
        chatFilterApiUsed = manifest.chatFilterApiUsed,
        chatFramesSeen = manifest.chatFramesSeen,
        chatFramesWrapped = manifest.chatFramesWrapped,
        systemChatTypeID = manifest.systemChatTypeID,
    }
    instrumentationSource = "manifeste"
end
local verdict, verdictDetail = ns.getInstrumentationVerdict(instrumentation)

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
    -- `build` first: it is the identity of the code that actually ran. Any
    -- disagreement with the .toc is reported on its own line below rather than
    -- hidden by preferring one of the two here.
    line(string.format("Build     : %s | version %s | interface %s",
        tostring(manifest.build or manifest.addonMetaBuild),
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
line(string.format("Source    : instrumentation lue dans le %s", instrumentationSource))
line("")

-- Instrumentation: the one value that can void a whole session. An unknown
-- verdict marks every line it rests on -- a missing value printed as `ok` in a
-- table read to spot what is wrong works against the reader.
local unknownInstrumentation = (verdict == "unknown") and "warn" or nil
state("API de filtrage chat", tostring(instrumentation.chatFilterApiUsed),
    verdict == "blocking" and "blocking" or unknownInstrumentation)
state("Frames de chat observees",
    tostring(instrumentation.chatFramesWrapped) .. " / " .. tostring(instrumentation.chatFramesSeen),
    ((verdict == "degraded" and (verdictDetail or ""):find("chat_frames", 1, true))
        and "warn") or unknownInstrumentation)
state("Type de message systeme", tostring(instrumentation.systemChatTypeID),
    (instrumentation.systemChatTypeID == nil or instrumentation.systemChatTypeID == "unknown")
        and "warn" or nil)
-- With a manifest, a log holding no snapshot only means it rotated past the
-- last one. Without one, there is nothing left to grade at all.
state("Snapshots dans le journal", markers.snapshots,
    markers.snapshots == 0 and (instrumentationSource == "manifeste" and "warn" or "blocking") or nil)

-- The markers below are read from the whole persistent log, which survives a
-- reload, a relog and a session. Two guards keep them from crediting a step
-- somebody did not play during this run.
--
-- First: the log must be about one build, and that build must be the one the
-- manifest names. A complete recording from a previous build would otherwise
-- read as a complete recording of this one.
local expectedBuild = manifest and (manifest.build or manifest.addonMetaBuild)
local logBuilds = markers.builds or {}
local buildLabel, buildLevel
if #logBuilds == 0 then
    buildLabel, buildLevel = "inconnu (aucun snapshot)", "warn"
elseif #logBuilds > 1 then
    buildLabel, buildLevel = table.concat(logBuilds, " + ") .. " (journal melange)", "blocking"
elseif expectedBuild and logBuilds[1] ~= expectedBuild then
    buildLabel, buildLevel = logBuilds[1] .. " != " .. tostring(expectedBuild), "blocking"
else
    buildLabel, buildLevel = logBuilds[1], nil
end
state("Build du journal", buildLabel, buildLevel)

-- And the two identities of the build must agree. The rule is not written here:
-- ns.getDeploymentVerdict is the same one the in-game summary prints, so this
-- check and that screen can never disagree about what "the right build" is.
local deployment, deploymentDetail = ns.getDeploymentVerdict(manifest)
local metaLabel, metaLevel
if deployment == "partial" then
    metaLabel, metaLevel = (deploymentDetail or "?") .. " (deploiement partiel)", "blocking"
elseif deployment == "unknown" then
    metaLabel, metaLevel = (deploymentDetail or "?"), "warn"
else
    metaLabel, metaLevel = tostring(manifest and manifest.build), nil
end
state("Build du code et du .toc", metaLabel, metaLevel)

-- Second: the log has to have been started for THIS run. It is not cleared by a
-- reload, a relog or a new day, so a log cleared during an earlier passage still
-- holds that passage's scenarios -- and credits steps skipped this time. Testing
-- only for "never cleared" missed the nominal case: a second session on the same
-- build, which is exactly what happens between the maintainer's pass and the
-- tester's, since the build does not change in between.
--
-- The manifest carries both dates, so the comparison is available right here.
-- Same day is the rule the checklist used to ask a human to apply; a session
-- that legitimately crosses midnight lands in reserves rather than being
-- refused outright, and the line prints both dates so that case is one glance
-- to arbitrate.
local clearedAt = manifest and manifest.debugLogClearedAt
local savedAt = manifest and manifest.savedAt
local clearedLabel, clearedLevel
if clearedAt == nil then
    clearedLabel, clearedLevel = "jamais", "warn"
elseif savedAt == nil then
    clearedLabel, clearedLevel = clearedAt .. " (releve non date)", "warn"
elseif tostring(clearedAt):sub(1, 10) ~= tostring(savedAt):sub(1, 10) then
    clearedLabel = clearedAt .. " -- releve ecrit le " .. tostring(savedAt):sub(1, 10)
    clearedLevel = "warn"
else
    clearedLabel, clearedLevel = clearedAt, nil
end
state("Journal vide le", clearedLabel, clearedLevel)
line("")

-- Produced by the diagnostic panel itself, not by a scenario: clicking "run
-- them all" writes this entry. Kept apart from the scenario block so its
-- presence is never read as proof that something was played.
state("C.1 fenetre d'invitation masquee", markers.popupMaskAwaitingEvent and "presente" or "absente",
    not markers.popupMaskAwaitingEvent and "warn" or nil)
line("")

-- Scenario markers, numbered as the checklist numbers them. One line each,
-- instead of four searches through the export.
state("F.1 ligne chat non filtree", markers.chatOutputNoMatch and "presente" or "absente",
    not markers.chatOutputNoMatch and "warn" or nil)
state("F.2 entree en instance", markers.worldInInstance and "presente" or "absente",
    not markers.worldInInstance and "warn" or nil)
-- Both halves, named separately: "died but never came back" is a session that
-- ended on a corpse, not the scenario the step asks for, and reporting it as a
-- plain "absente" hides which half is missing.
local deathLabel
if markers.playerState then
    deathLabel = "presente"
elseif markers.playerDied then
    deathLabel = "mort sans retour a la vie"
elseif markers.playerRevived then
    deathLabel = "retour a la vie sans mort"
else
    deathLabel = "absente"
end
state("F.3 mort / resurrection", deathLabel, not markers.playerState and "warn" or nil)
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

-- Three outcomes, three exit codes. Reserves used to exit 0, so any caller
-- testing $? read "conforme" on a recording where no scenario had been played
-- at all. Only a clean recording exits 0.
--   0 = complete   1 = blocking failure   2 = unusable input   3 = reserves
if blocking > 0 then
    line("VERDICT : ECHEC BLOQUANT -- ce releve n'est pas exploitable.")
    os.exit(1)
elseif warnings > 0 then
    line(string.format("VERDICT : EXPLOITABLE AVEC RESERVES (%d point(s) a signaler).", warnings))
    line("Ce n'est pas un releve complet : remontez les lignes marquees warn avant d'aller plus loin.")
    os.exit(3)
else
    line("VERDICT : RELEVE COMPLET ET EXPLOITABLE.")
end
