-- Detects other addons doing the same job, so a fight over raid icons is
-- reported by name instead of appearing as marks that will not stay put.
--
-- Nothing here changes another addon's settings. Reaching into someone else's
-- saved variables to switch off a feature they turned on is not a fix, it is a
-- surprise. This names the addon and the exact click.
local MFD = _G.MarkedForDeath or {}

MFD.Conflicts = MFD.Conflicts or {}
local Conflicts = MFD.Conflicts

-- Each entry describes one thing worth reporting. isActive is called inside a
-- pcall, so an addon changing its own layout can never break our login.
Conflicts.KNOWN = {
    {
        label = "Method Raid Tools",
        topic = "raid icons",
        what = "its automarker is on, so both addons are marking the same mobs",
        fix = "/mrt, Marks, Auto marks, untick Enable",
        isActive = function()
            return VMRT and VMRT.MarksSimple and VMRT.MarksSimple.autoMarkEnabled
                and MarkedForDeathDB and MarkedForDeathDB.settings
                and MarkedForDeathDB.settings.isMarkingEnabled and true or false
        end,
    },
    {
        label = "Method Raid Tools",
        topic = "raid icons",
        what = "its buff mark feature is on, which also places raid icons",
        fix = "/mrt, Marks, Auto marks, untick Buff marks",
        isActive = function()
            return VMRT and VMRT.MarksSimple and VMRT.MarksSimple.buffMarkEnabled
                and MarkedForDeathDB and MarkedForDeathDB.settings
                and MarkedForDeathDB.settings.isMarkingEnabled and true or false
        end,
    },
    {
        label = "Method Raid Tools",
        topic = "combat logging",
        what = "its auto logging is on as well, so two addons are toggling the same combat log",
        fix = "/mrt, Logging, untick Enable, or untick combat logging in /mfd options",
        isActive = function()
            return VMRT and VMRT.Logging and VMRT.Logging.enabled
                and MarkedForDeathDB and MarkedForDeathDB.settings
                and MarkedForDeathDB.settings.combatLog
                and MarkedForDeathDB.settings.combatLog.isEnabled and true or false
        end,
    },
}

-- Takes definitions and returns the ones whose test says they are active. A
-- test that throws is treated as "not active": another addon's internals are
-- not our contract, and guessing wrong must never cost more than a missed
-- warning. Pure apart from calling the supplied tests.
function Conflicts.Evaluate(definitions)
    local found = {}

    for _, definition in ipairs(definitions or {}) do
        local ok, isActive = pcall(definition.isActive)
        if ok and isActive then
            found[#found + 1] = definition
        end
    end

    return found
end

-- Turns found conflicts into one line each. Pure.
function Conflicts.Format(found)
    local lines = {}

    for _, conflict in ipairs(found or {}) do
        lines[#lines + 1] = string.format("%s: %s. Fix: %s", conflict.label, conflict.what, conflict.fix)
    end

    return lines
end

-- The line above the list, naming what the overlap is actually about. Returns
-- nil when there is nothing to report. Pure.
--
-- This used to be hardcoded to raid icons, which stopped being true the moment
-- a combat logging entry joined the table: a fill-in raider with MRT's auto
-- logging on was told in red that something was fighting over raid icons, which
-- was not happening and could not have been, since a raider without assist
-- cannot place an icon at all.
function Conflicts.Headline(found)
    local seen, topics = {}, {}

    for _, conflict in ipairs(found or {}) do
        local topic = conflict.topic or "the same job"
        if not seen[topic] then
            seen[topic] = true
            topics[#topics + 1] = topic
        end
    end

    if #topics == 0 then
        return nil
    end

    local list = topics[1]
    for index = 2, #topics do
        list = list .. (index == #topics and " and " or ", ") .. topics[index]
    end

    return "another addon is also handling " .. list .. ":"
end

-- ---------------------------------------------------------------- client --

-- Returns the currently active conflicts.
function Conflicts.Detect()
    return Conflicts.Evaluate(Conflicts.KNOWN)
end

-- Prints them, or says there are none. reportClean is false for the automatic
-- login check, which should stay quiet when there is nothing wrong.
function Conflicts.Report(reportClean)
    local found = Conflicts.Detect()
    local lines = Conflicts.Format(found)

    if #lines == 0 then
        if reportClean then
            MFD.Print("|cff66ff66no other addon is doing any of the same jobs|r")
        end
        return 0
    end

    -- Printed, not raised. UIErrorsFrame is where the game says you are out of
    -- range, and putting a note about addon settings there is what made a
    -- fill-in raider turn this addon off mid raid. Nothing here is broken and
    -- nothing here is urgent.
    local headline = Conflicts.Headline(found)
    MFD.Print("|cffffcc00" .. headline .. "|r")
    MFD.Log.Add(MFD.Log.KINDS.CONFLICT, headline)

    for _, line in ipairs(lines) do
        MFD.Print("  |cffffcc00" .. line .. "|r")
        -- Logged as well as printed. Only the headline used to be recorded, so
        -- the log said a conflict had been reported without saying which one,
        -- and reading it afterwards meant going into another addon's saved
        -- variables to work out what had actually fired.
        MFD.Log.Add(MFD.Log.KINDS.CONFLICT, line)
    end

    return #lines
end

MFD.RegisterInit(function()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")

    local hasReported = false
    frame:SetScript("OnEvent", function()
        -- Once per session. A conflict that persists is not news every zone.
        if hasReported then
            return
        end
        hasReported = true
        Conflicts.Report(false)
    end)
end)

_G.MarkedForDeath = MFD
