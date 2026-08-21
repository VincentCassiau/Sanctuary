-- Offline check of a QA recording.
--
-- Usage: lua tests/check_qa_run.lua [--since "AAAA-MM-JJ HH:MM:SS"] <SavedVariables/Sanctuary.lua>
--        lua tests/check_qa_run.lua --markers
--
-- Exit codes: 0 complete, 1 blocking failure, 2 unusable input, 3 reserves.
--
-- --markers prints, one per line, the machine markers this check reads. The
-- session protocol names the same ones, and the harness refuses to start if the
-- two lists disagree: a session that measures something other than what it
-- claims to is worse than no session.
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

-- The markers this check reads, declared once. `step` is the protocol step that
-- is supposed to produce it, so a missing marker names the step to replay.
local MARKERS = {
    { key = "popupMaskAwaitingEvent", label = "C.1 fenetre d'invitation masquee", panel = true },
    { key = "chatOutputNoMatch", label = "F.1 ligne chat non filtree" },
    { key = "worldInInstance", label = "F.2 entree en instance" },
    { key = "lockdownArmedInInstance", label = "F.2 verrouillage arme en instance", info = true },
    { key = "playerState", label = "F.3 mort / resurrection", death = true },
    { key = "secretSystemSuppressed", label = "F.2 lignes systeme masquees", info = true, count = true },
    { key = "secretSystemVisible", label = "F.2 lignes systeme visibles", info = true, count = true },
    { key = "secretSystemEligible", label = "F.2 lignes systeme eligibles", info = true, count = true },
    { key = "strictModeOn", label = "F.2 filtrage renforce coche", info = true },
}

local path, since
do
    local index = 1
    while arg and arg[index] do
        local value = arg[index]
        if value == "--markers" then
            for _, marker in ipairs(MARKERS) do print(marker.key) end
            os.exit(0)
        elseif value == "--since" then
            index = index + 1
            since = arg[index]
        else
            path = value
        end
        index = index + 1
    end
end

if not path then
    io.stderr:write("usage: lua tests/check_qa_run.lua [--since \"AAAA-MM-JJ HH:MM:SS\"] <SavedVariables/Sanctuary.lua>\n")
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
-- Read by the addon's own rule: SanctuaryDB is the global Sanctuary.lua looks
-- at, so pointing it at the recording lets getEffectiveFilterState answer for
-- this file. No second implementation of the preset or of the mode.
SanctuaryDB = db
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
        tostring(manifest.version),
        tostring(manifest.addonInterface or manifest.addonMetaInterface)))
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
-- With --since, the runner hands over the exact moment the session started and
-- the whole timestamp is compared. Same-day was the rule a human applied, and it
-- passed a log cleared at 08:00 for a session played at 18:00 -- the markers
-- then come from the morning and credit steps nobody played this evening.
local clearedAt = manifest and manifest.debugLogClearedAt
local savedAt = manifest and manifest.savedAt
local clearedLabel, clearedLevel
if clearedAt == nil then
    clearedLabel, clearedLevel = "jamais", "warn"
elseif since then
    if tostring(clearedAt) < tostring(since) then
        clearedLabel = clearedAt .. " -- session ouverte le " .. tostring(since)
        clearedLevel = "warn"
    else
        clearedLabel, clearedLevel = clearedAt, nil
    end
elseif savedAt == nil then
    clearedLabel, clearedLevel = clearedAt .. " (releve non date)", "warn"
elseif tostring(clearedAt):sub(1, 10) ~= tostring(savedAt):sub(1, 10) then
    clearedLabel = clearedAt .. " -- releve ecrit le " .. tostring(savedAt):sub(1, 10)
    clearedLevel = "warn"
else
    clearedLabel, clearedLevel = clearedAt, nil
end
state("Journal vide le", clearedLabel, clearedLevel)

-- The AddOns manager grades "Out of date" on this comparison. Doing it here
-- takes one more thing off the human, who has no reason to know the numbers.
local addonInterface = tonumber(manifest and manifest.addonInterface)
local clientInterface = tonumber(manifest and manifest.clientInterface)
local interfaceLabel, interfaceLevel
if not addonInterface or not clientInterface then
    interfaceLabel, interfaceLevel = "inconnue", "warn"
elseif addonInterface < clientInterface then
    interfaceLabel = addonInterface .. " < client " .. clientInterface .. " (obsolete)"
    interfaceLevel = "warn"
else
    interfaceLabel, interfaceLevel = tostring(addonInterface), nil
end
state("Interface de l'addon", interfaceLabel, interfaceLevel)

-- The settings the session was played under, resolved by the addon itself.
local filters = ns.getEffectiveFilterState()
line(string.format("Reglages  : question 1 = %s | question 2 = %s | renforce = %s",
    tostring(filters.scope), tostring(filters.preset),
    tostring(filters.strictGroupInviteSystemMessages)))
line(string.format("Filtres   : invitations=%s prives=%s duels=%s echanges=%s guilde=%s canaux=%s",
    tostring(filters.groupInvite), tostring(filters.whisper), tostring(filters.duel),
    tostring(filters.trade), tostring(filters.guildInvite), tostring(filters.channelMode)))
line("")

-- One line per marker, from the table declared at the top. The panel marker is
-- printed first and kept apart: clicking "run them all" writes it, so its
-- presence must never be read as proof that a scenario was played.
--
-- The instance markers are informational: a trial account cannot produce a
-- dungeon run, so their absence is a fact about the session, not a fault.
for _, marker in ipairs(MARKERS) do
    local value = markers[marker.key]
    local label, level
    if marker.count then
        label = tostring(tonumber(value) or 0)
    elseif marker.death then
        -- Both halves, named separately: "died but never came back" is a session
        -- that ended on a corpse, not the scenario the step asks for.
        if markers.playerState then
            label = "presente"
        elseif markers.playerDied then
            label = "mort sans retour a la vie"
        elseif markers.playerRevived then
            label = "retour a la vie sans mort"
        else
            label = "absente"
        end
    else
        label = value and "presente" or "absente"
    end
    if not marker.info and not marker.count and not value then
        level = "warn"
    end
    state(marker.label, label, level)
end
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
