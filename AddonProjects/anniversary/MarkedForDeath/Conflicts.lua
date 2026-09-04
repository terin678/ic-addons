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
        what = "its automarker is on, so both addons are marking the same mobs",
        fix = "/mrt, Marks, Auto marks, untick Enable",
        isActive = function()
            return VMRT and VMRT.MarksSimple and VMRT.MarksSimple.autoMarkEnabled and true or false
        end,
    },
    {
        label = "Method Raid Tools",
        what = "its buff mark feature is on, which also places raid icons",
        fix = "/mrt, Marks, Auto marks, untick Buff marks",
        isActive = function()
            return VMRT and VMRT.MarksSimple and VMRT.MarksSimple.buffMarkEnabled and true or false
        end,
    },
    {
        label = "Method Raid Tools",
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

-- ---------------------------------------------------------------- client --

-- Returns the currently active conflicts.
function Conflicts.Detect()
    return Conflicts.Evaluate(Conflicts.KNOWN)
end

-- Prints them, or says there are none. reportClean is false for the automatic
-- login check, which should stay quiet when there is nothing wrong.
function Conflicts.Report(reportClean)
    local lines = Conflicts.Format(Conflicts.Detect())

    if #lines == 0 then
        if reportClean then
            MFD.Print("|cff66ff66no other addon is fighting for raid icons|r")
        end
        return 0
    end

    MFD.Error("another addon is also placing raid icons:")
    for _, line in ipairs(lines) do
        MFD.Print("  |cffff4444" .. line .. "|r")
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
