local addonName, ns = ...

-- The cases: headless with scripts/run-tests.ps1 -Flavor forever -Addon RenderTuner, and
-- in game with /tuner test. None asks the client anything or touches the saved tables.

local T = ns.Tests
local Probe = ns.Probe

local CVAR, COMMAND = 0, 1

--------------------------------------------------------------------------------
-- Probe
--------------------------------------------------------------------------------

T.Case("Probe.Rows: console variables only, sorted, with what could be read of each", function()
    local commands = {
        { command = "renderscale", help = "Render scale", category = 1, commandType = CVAR },
        { command = "gxRestart", help = "Restart graphics", category = 1, commandType = COMMAND },
        { command = "Gamma", help = "", category = 1, commandType = CVAR },
        { command = "agentUID", help = "The launcher's id", category = 5, commandType = CVAR },
        { command = "hidden", help = "Not for addons", category = 0, commandType = CVAR },
    }
    local known = {
        renderscale = { value = "0.67", default = "1" },
        Gamma = { value = "1", default = "1", locked = false, secure = false, readOnly = false },
        agentUID = { value = "wow", default = "", readOnly = true, secure = true, locked = true },
    }
    local rows = Probe.Rows(commands, function(name) return known[name] end)

    T.Eq(#rows, 4, "the command is left out")
    T.Eq(rows[1].name .. rows[2].name .. rows[3].name .. rows[4].name, "agentUIDGammahiddenrenderscale",
        "sorted without regard to case")

    T.Eq(rows[4].value, "0.67", "the value")
    T.Eq(rows[4].default, "1", "and the default")
    T.Eq(rows[4].help, "Render scale", "the help text")
    T.Eq(rows[4].category, 1, "the category")
    T.Eq(rows[4].locked, nil, "a flag that is not set is not stored")

    T.Eq(rows[2].help, nil, "empty help is not stored")
    T.Eq(rows[2].secure, nil, "nor a flag that is false")
    T.True(rows[1].readOnly and rows[1].secure and rows[1].locked, "set flags are kept")
    T.Eq(rows[3].unreadable, true, "a variable with no answer is marked")
    T.Eq(rows[3].value, nil, "and holds no value")

    T.Eq(#Probe.Rows(nil, nil), 0, "no list, no rows")
end)

T.Case("Probe.Rows: names that differ only in case keep a fixed order", function()
    local commands = {
        { command = "gamma", category = 1, commandType = CVAR },
        { command = "Gamma", category = 1, commandType = CVAR },
    }
    local rows = Probe.Rows(commands, nil)
    T.Eq(rows[1].name, "Gamma", "capital first")
    T.Eq(rows[2].name, "gamma", "then lower")
end)

T.Case("Probe.Summary: counts by category, what is closed to addons, what is missing", function()
    local lines = Probe.Summary({
        build = { version = "1.60.1", build = "70124", interface = 16001 },
        cvars = {
            { name = "a", category = 1, value = "1", default = "1" },
            { name = "b", category = 1, value = "2", default = "1" },
            { name = "c", category = 5, value = "x", default = "x", readOnly = true },
            { name = "d", category = 42, unreadable = true },
        },
        has = { ["C_CVar.SetCVar"] = "function", RestartGx = false },
        templates = { MinimalSliderTemplate = true, OffScreenFrame = "Unknown frame type" },
        values = { GetMinRenderScale = "0.33", GetMaxRenderScale = "2" },
    })
    local text = table.concat(lines, "\n")
    T.True(text:find("1.60.1 (70124), interface 16001", 1, true), "the build")
    T.True(text:find("4 console variables: 2 in Graphics, 2 an addon may not set, 1 off their default", 1, true),
        "the counts")
    T.True(text:find("42 1, Default 1, Graphics 2", 1, true), "a category with no name shows its number")
    T.True(text:find("1 of 2 functions present", 1, true), "what is there")
    T.True(text:find("missing:|r RestartGx", 1, true), "what is not")
    T.True(text:find("frames refused:|r OffScreenFrame", 1, true), "a frame the client would not build")
    T.True(text:find("render scale runs from 0.33 to 2", 1, true), "the render scale's range")
end)

T.Case("Probe.Summary: a list that could not be read says so", function()
    local lines = Probe.Summary({ listError = "not a function", has = {}, templates = {}, values = {} })
    T.True(table.concat(lines, "\n"):find("could not be read:|r not a function", 1, true), "the reason is shown")
end)

T.Case("Probe.CaptureLines: one line for each way tried, saying how far it got", function()
    local lines = Probe.CaptureLines({
        photo = { forbidden = "TakePhoto()" },
        report = { ready = true, seconds = 0.25 },
    })
    T.Eq(#lines, 2, "two ways tried")
    T.True(lines[1]:find("the photo way: the client refused the call to addons (TakePhoto())", 1, true), "refused")
    T.True(lines[2]:find("the report way: a picture came back in 0.25s", 1, true), "worked")

    T.True(Probe.CaptureLines({ report = { callError = "boom" } })[1]:find("the call failed: boom", 1, true), "failed")
    T.True(Probe.CaptureLines({ report = {} })[1]:find("no picture came back", 1, true), "silence")
    T.True(Probe.CaptureLines({ report = { ready = true, applyError = "nope" } })[1]
        :find("could not be put on a texture: nope", 1, true), "taken but not shown")
    T.Eq(#Probe.CaptureLines(nil), 0, "nothing tried, nothing said")
end)

--------------------------------------------------------------------------------
-- Core
--------------------------------------------------------------------------------

T.Case("LoadLines: says what to do first until the client has been probed", function()
    T.True(ns.LoadLines("0.0.1", false)[1]:find("/tuner probe first", 1, true), "before the probe")
    T.True(ns.LoadLines("0.0.1", true)[1]:find("has been probed", 1, true), "after it")
end)
