-- Turns the game's own combat logging on in a raid and off when you leave, so
-- there is always a WoWCombatLog to upload.
--
-- Same manner as MRT's AutoLogging, including the two details that make it work
-- rather than nearly work. It decides two seconds after the zone event, because
-- GetInstanceInfo is not reliable the instant a loading screen ends. And it
-- only ever switches logging off if it was the one that switched it on, so it
-- cannot stamp on somebody who turned it on by hand or on another addon that
-- wants it running.
local MFD = _G.MarkedForDeath or {}

MFD.CombatLog = MFD.CombatLog or {}
local CombatLog = MFD.CombatLog

-- Seconds to wait after a zone change before asking where we are. MRT uses the
-- same two, and for the same reason.
CombatLog.SETTLE_SECONDS = 2

-- TBC dungeon difficulties, for the optional heroic case. Raids are recognised
-- by zone type instead, which needs no id table and cannot rot.
CombatLog.DIFFICULTY_HEROIC_DUNGEON = 174

-- Should the combat log be running here? Takes what GetInstanceInfo reports and
-- the settings. Pure, which is the only reason this is testable at all: the
-- alternative is zoning into Black Temple to find out.
function CombatLog.ShouldLog(zoneType, difficultyID, settings)
    if not settings or not settings.isEnabled then
        return false
    end

    if zoneType == "raid" then
        return true
    end

    if settings.includeHeroics and zoneType == "party"
        and difficultyID == CombatLog.DIFFICULTY_HEROIC_DUNGEON then
        return true
    end

    return false
end

-- What to do given where we are, whether the game is logging, and whether we
-- are the ones who started it. Returns "start", "stop" or nil. Pure.
--
-- The nil cases are the important ones. Already logging and it is not ours:
-- leave it alone, somebody else wants it. Not logging and we should not be:
-- nothing to do. Doing either of those anyway is how two addons end up fighting
-- over one switch and the log ends up truncated.
function CombatLog.Decide(shouldLog, isLogging, isOurs)
    if shouldLog and not isLogging then
        return "start"
    end

    if not shouldLog and isLogging and isOurs then
        return "stop"
    end

    return nil
end

-- ---------------------------------------------------------------- client --

-- Whether this addon is the one that turned logging on. Not saved: a reload
-- ends our claim, because after it we genuinely do not know who started the
-- file that is currently open.
CombatLog.isOurs = false

local function settings()
    return MFD.db.settings.combatLog
end

function CombatLog.Evaluate()
    if not MFD.db then
        return
    end

    local ok, zoneType, difficultyID = pcall(function()
        local _, kind, difficulty = GetInstanceInfo()
        return kind, difficulty
    end)
    if not ok then
        return
    end

    local shouldLog = CombatLog.ShouldLog(zoneType, difficultyID, settings())

    local isLogging = false
    local readOk, current = pcall(LoggingCombat)
    if readOk then
        isLogging = current and true or false
    end

    local action = CombatLog.Decide(shouldLog, isLogging, CombatLog.isOurs)

    if action == "start" then
        pcall(LoggingCombat, true)
        CombatLog.isOurs = true
        MFD.Print("|cff66ff66combat logging on|r for " .. tostring(zoneType or "here")
            .. ". The file is in Logs\\WoWCombatLog.txt.")
        MFD.Log.Add(MFD.Log.KINDS.LOGGING, "combat logging started in " .. tostring(zoneType))
    elseif action == "stop" then
        pcall(LoggingCombat, false)
        CombatLog.isOurs = false
        MFD.Print("|cff999999combat logging off|r, out of the raid.")
        MFD.Log.Add(MFD.Log.KINDS.LOGGING, "combat logging stopped, left the instance")
    end
end

-- Runs Evaluate after the settle delay, coalescing the burst of zone events a
-- single loading screen produces into one decision.
local pending = false

function CombatLog.Schedule()
    if pending or not C_Timer then
        return
    end
    pending = true

    C_Timer.After(CombatLog.SETTLE_SECONDS, function()
        pending = false
        local ok, err = pcall(CombatLog.Evaluate)
        if not ok then
            MFD.Error("combat logging check failed: " .. tostring(err))
        end
    end)
end

MFD.RegisterInit(function()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

    frame:SetScript("OnEvent", function()
        CombatLog.Schedule()
    end)

    CombatLog.Schedule()
end)

_G.MarkedForDeath = MFD
