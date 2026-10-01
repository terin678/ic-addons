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
-- Catalog
--------------------------------------------------------------------------------

local Catalog = ns.Catalog
local Model = ns.Model

T.Case("Catalog: every knob is whole, and no variable is offered twice", function()
    local groups = {}
    for _, group in ipairs(Catalog.GROUPS) do groups[group.key] = true end
    local KINDS = { slider = true, toggle = true, choice = true }
    local FORMATS = { percent = true, percent100 = true, fps = true, nits = true }
    local RESTARTS = { gx = true, window = true, client = true }

    local seen = {}
    for _, knob in ipairs(Catalog.KNOBS) do
        local name = tostring(knob.cvar)
        T.True(type(knob.cvar) == "string" and knob.cvar ~= "", "a variable name")
        T.Eq(seen[name:lower()], nil, name .. " appears once")
        seen[name:lower()] = true
        T.True(type(knob.label) == "string" and knob.label ~= "", name .. " has a label")
        T.True(type(knob.help) == "string" and knob.help ~= "", name .. " has help")
        T.True(groups[knob.group], name .. " is in a group that exists")
        T.True(KINDS[knob.kind], name .. " has a kind")
        T.True(knob.format == nil or FORMATS[knob.format], name .. " has a known format")
        T.True(knob.restart == nil or RESTARTS[knob.restart], name .. " has a known restart")
        if knob.kind == "slider" then
            T.True(type(knob.min) == "number" and type(knob.max) == "number" and knob.min < knob.max,
                name .. " has a range")
            T.True(type(knob.step) == "number" and knob.step > 0, name .. " has a step")
        elseif knob.kind == "choice" then
            T.True(type(knob.choices) == "table" and #knob.choices >= 2, name .. " has choices")
            for _, choice in ipairs(knob.choices) do
                T.True(type(choice[1]) == "number" and type(choice[2]) == "string", name .. " choices are value, label")
            end
        end
    end
    T.True(#Catalog.KNOBS > 80, "the catalogue is there")
end)

T.Case("Catalog: the presets run from native down, and the model can read each", function()
    local limits = Model.Limits(0.33333334, 2)
    T.Eq(Catalog.PRESETS[1].key, "native", "native first")
    T.Eq(Catalog.PRESETS[1].scale, 1, "at full scale")
    for i = 2, #Catalog.PRESETS do
        T.True(Catalog.PRESETS[i].scale < Catalog.PRESETS[i - 1].scale, "each smaller than the last")
    end
    for _, preset in ipairs(Catalog.PRESETS) do
        local target = Model.Preset(preset, limits, Catalog.FSR)
        T.Eq(Model.PresetOf(target.RenderScale, Catalog.PRESETS, limits), preset, preset.key .. " is recognised again")
    end
end)

--------------------------------------------------------------------------------
-- Model
--------------------------------------------------------------------------------

local SLIDER = { cvar = "S", label = "Slide", kind = "slider", min = 0.3334, max = 2, step = 0.01, format = "percent" }
local SHARP = { cvar = "R", label = "Sharp", kind = "slider", min = 0, max = 2, step = 0.1, reversed = true }
local TOGGLE = { cvar = "T", label = "Tog", kind = "toggle", restart = "gx" }
local CHOICE = { cvar = "C", label = "Pick", kind = "choice", choices = { { 0, "None" }, { 2, "Two" }, { 3, "Three" } } }
local LEVEL = { cvar = "L", label = "Level", kind = "slider", min = 0, max = 9, step = 1, rank = 2 }
local MASTER = { cvar = "M", label = "Master", kind = "slider", min = 0, max = 9, step = 1, rank = 1,
    restart = "client" }

T.Case("Model.Norm: the client's text becomes a number", function()
    T.Near(Model.Norm(SLIDER, "0.670000"), 0.67, "a decimal")
    T.Eq(Model.Norm(CHOICE, "3,0"), 3, "the leading number of a pair")
    T.Eq(Model.Norm(SLIDER, ".45"), 0.45, "no leading zero")
    T.Eq(Model.Norm(SLIDER, "-1"), -1, "a negative")
    T.Eq(Model.Norm(SLIDER, 1.5), 1.5, "a number passes through")
    T.Eq(Model.Norm(TOGGLE, "1"), 1, "a toggle on")
    T.Eq(Model.Norm(TOGGLE, "0"), 0, "a toggle off")
    T.Eq(Model.Norm(TOGGLE, "2"), 1, "anything but zero is on")
    T.Eq(Model.Norm(SLIDER, "auto"), nil, "text with no number")
    T.Eq(Model.Norm(SLIDER, nil), nil, "no answer")
end)

T.Case("Model.Text: short text, whole numbers without a point", function()
    T.Eq(Model.Text(3), "3", "whole")
    T.Eq(Model.Text(1.0000001), "1", "whole within tolerance")
    T.Eq(Model.Text(0.67), "0.67", "trailing zeros dropped")
    T.Eq(Model.Text(0.3334), "0.3334", "four places kept")
    T.Eq(Model.Text(-1), "-1", "negative")
end)

T.Case("Model.Limits: the client's limits move inward to what can be written back", function()
    local limits = Model.Limits(0.33333334326744, 2)
    T.Eq(limits.min, 0.3334, "the floor rounds up")
    T.Eq(limits.max, 2, "a round ceiling stays")
    T.Eq(Model.Limits(0.5, 1.99999).max, 1.9999, "the ceiling rounds down")
    T.Eq(Model.Limits(0.5, 2).min, 0.5, "a round floor stays")
    T.Eq(Model.Limits(nil, nil).min, 0.3334, "no answer falls back")
end)

T.Case("Model.Clamp: sliders snap and stay in range, choices must be offered", function()
    T.Near(Model.Clamp(SLIDER, 0.674), 0.67, "snapped to the step")
    T.Eq(Model.Clamp(SLIDER, 0.1), 0.3334, "the floor is reachable though it is off the step")
    T.Eq(Model.Clamp(SLIDER, 5), 2, "the ceiling")
    T.Eq(Model.Clamp(TOGGLE, 7), 1, "a toggle is on or off")
    T.Eq(Model.Clamp(CHOICE, 2), 2, "an offered choice")
    local value, why = Model.Clamp(CHOICE, 1)
    T.Eq(value, nil, "a choice not offered is refused")
    T.True(why:find("0 (None), 2 (Two), 3 (Three)", 1, true), "and the reason lists what is")
    local none, reason = Model.Clamp(SLIDER, "fast")
    T.Eq(none, nil, "text is refused")
    T.Eq(reason, "that is not a number", "with a reason")
end)

T.Case("Model.Format: what the user reads", function()
    T.Eq(Model.Format(SLIDER, 0.67), "67%", "a share")
    T.Eq(Model.Format(SLIDER, 0.3334), "33%", "rounded")
    T.Eq(Model.Format(SHARP, 0.2), "1.8", "a reversed slider reads from the other end")
    T.Near(Model.FromShown(SHARP, 1.8), 0.2, "and is set from the other end")
    T.Eq(Model.Format(TOGGLE, 1), "on", "a toggle")
    T.Eq(Model.Format(TOGGLE, 0), "off", "off")
    T.Eq(Model.Format(CHOICE, 2), "Two", "a choice by its label")
    T.Eq(Model.Format(CHOICE, 7), "7", "a value with no label shows itself")
    T.Eq(Model.Format({ kind = "slider", min = 8, max = 200, format = "fps" }, 120), "120 fps", "frames")
    T.Eq(Model.Format({ kind = "slider", min = 80, max = 1000, format = "nits" }, 203), "203 nits", "nits")
    T.Eq(Model.Format({ kind = "slider", min = 10, max = 100, format = "percent100" }, 80), "80%", "a whole percent")
    T.Eq(Model.Format(SLIDER, nil), "?", "no value")
end)

T.Case("Model.Snapshot, Fill, Diff: sets of values", function()
    local knobs = { SLIDER, TOGGLE, CHOICE }
    local client = { S = "0.670000", T = "1", C = "3,0" }
    local live = Model.Snapshot(knobs, function(cvar) return client[cvar] end)
    T.Near(live.S, 0.67, "the slider")
    T.Eq(live.T, 1, "the toggle")
    T.Eq(live.C, 3, "the choice")

    local saved = { S = 1 }
    T.Eq(Model.Fill(saved, live), 2, "two knobs the saved set had not seen")
    T.Eq(saved.S, 1, "what it had is kept")
    T.Eq(saved.C, 3, "what it lacked is taken")

    local changes = Model.Diff(saved, live, knobs)
    T.Eq(#changes, 1, "one differs")
    T.Eq(changes[1].knob, SLIDER, "the slider")
    T.Eq(changes[1].from, 1, "from saved")
    T.Near(changes[1].to, 0.67, "to live")
    T.Eq(#Model.Diff({ S = 0.67000001 }, { S = 0.67 }, knobs), 0, "a rounding difference is no change")
    T.Eq(#Model.Diff({}, live, knobs), 0, "a knob only one side knows is no change")
end)

T.Case("Model.Plan: only what differs, quality levels before the variables beneath them", function()
    local knobs = { SLIDER, TOGGLE, LEVEL, CHOICE, MASTER }
    local live = { S = 1, T = 0, L = 3, C = 0, M = 5 }
    local plan = Model.Plan({ S = 0.67, T = 0, L = 5, C = 3, M = 9 }, live, knobs)
    local order = {}
    for i, step in ipairs(plan) do order[i] = step.cvar .. "=" .. step.value end
    T.Eq(table.concat(order, " "), "M=9 L=5 S=0.67 C=3", "master, then levels, then the rest in catalogue order")

    T.Eq(#Model.Plan({ S = 1 }, live, knobs), 0, "nothing to do when it is already so")
    T.Eq(#Model.Plan({ X = 1 }, live, knobs), 0, "a variable not in the catalogue is ignored")
    T.Eq(#Model.Plan({ S = 0.5 }, {}, knobs), 0, "a variable the client did not answer for is left alone")

    T.Eq(Model.Restart(plan), "client", "the heaviest restart among the changes")
    T.Eq(Model.Restart(Model.Plan({ T = 1 }, live, knobs)), "gx", "a graphics restart")
    T.Eq(Model.Restart(Model.Plan({ S = 0.5 }, live, knobs)), nil, "none")
end)

T.Case("Model.Find, Group, FindPreset: what the user typed", function()
    local knobs = { SLIDER, TOGGLE }
    T.Eq(Model.Find(knobs, " s "), SLIDER, "a variable, whatever the case")
    T.Eq(Model.Find(knobs, "nope"), nil, "not in the catalogue")
    T.Eq(Model.Find(knobs, ""), nil, "nothing typed")

    T.Eq(Model.Group(Catalog.GROUPS, "aa").key, "aa", "a group by key")
    T.Eq(Model.Group(Catalog.GROUPS, "Anti").key, "aa", "by the start of its label")
    T.Eq(Model.Group({ { key = "shadow", label = "Shadows" }, { key = "sharp", label = "Sharpening" } }, "sha"), nil,
        "an ambiguous start finds nothing")

    T.Eq(Model.FindPreset(Catalog.PRESETS, "perf").key, "performance", "a preset by the start of its key")
    T.Eq(Model.FindPreset(Catalog.PRESETS, "Ultra Performance").key, "ultra", "by its label")
    T.Eq(Model.FindPreset(Catalog.PRESETS, "dlss"), nil, "there is no such thing")
end)

T.Case("Model.Preset: upscaling presets set FSR, native leaves the filter alone", function()
    local limits = Model.Limits(0.33333334, 2)
    local quality = Model.Preset({ key = "quality", scale = 0.67 }, limits, 3)
    T.Eq(quality.RenderScale, 0.67, "the scale")
    T.Eq(quality.ResampleQuality, 3, "with the FSR filter")

    local native = Model.Preset({ key = "native", scale = 1 }, limits, 3)
    T.Eq(native.RenderScale, 1, "full scale")
    T.Eq(native.ResampleQuality, nil, "and the filter untouched")

    T.Eq(Model.Preset({ key = "ultra", scale = 0.3334 }, Model.Limits(0.5, 2), 3).RenderScale, 0.5,
        "a preset under the client's floor sits on the floor")
    T.Eq(Model.PresetOf(0.8, Catalog.PRESETS, limits), nil, "a scale set by hand is no preset")
    T.Eq(Model.PresetOf(nil, Catalog.PRESETS, limits), nil, "nor is no scale")
end)

T.Case("Model.Line, Status: lines of text", function()
    T.True(Model.Line(SLIDER, 0.67, 0.67):find("Slide |cff888888S|r: 67%", 1, true), "label, variable, value")
    T.Eq(Model.Line(SLIDER, 0.67, 0.67):find("saved", 1, true), nil, "nothing more when it is as saved")
    T.True(Model.Line(SLIDER, 0.67, 1):find("saved: 100%", 1, true), "the saved value when it differs")

    T.Eq(Model.Status("67%", { label = "Quality" }, 0), "render scale 67% (Quality), everything as saved.", "settled")
    T.Eq(Model.Status("80%", nil, 1), "render scale 80%, 1 setting differs from the saved set.", "one change")
    T.Eq(Model.Status("80%", nil, 3), "render scale 80%, 3 settings differ from the saved set.", "several")
    T.True(Model.RestartHint("gx"):find("/tuner restart", 1, true), "a restart hint names the command")
    T.Eq(Model.RestartHint(nil), nil, "no need, no hint")
end)

--------------------------------------------------------------------------------
-- Core
--------------------------------------------------------------------------------

T.Case("LoadLines: the version and where things stand", function()
    T.Eq(ns.LoadLines("0.1.0", "render scale 67% (Quality), everything as saved.")[1],
        "v0.1.0 loaded: render scale 67% (Quality), everything as saved. /tuner help lists commands.", "one line")
end)

--------------------------------------------------------------------------------
-- The commands against a made-up client
--------------------------------------------------------------------------------

-- In game this would change the player's real settings, so it runs only under the
-- harness. The client here is a table of console variables that answers the four calls
-- Apply.lua makes.
if IC_HEADLESS then
    T.Case("Commands: presets, set, save, revert and restore against a made-up client", function()
        local cvars, sets = {}, {}
        for _, knob in ipairs(Catalog.KNOBS) do cvars[knob.cvar] = "1" end
        cvars.RenderScale, cvars.ResampleQuality, cvars.ResampleSharpness = "1", "2", "0.2"
        cvars.MSAAQuality = "3,0"

        local real = { C_CVar = C_CVar, min = GetMinRenderScale, max = GetMaxRenderScale, db = ns.db }
        C_CVar = {
            GetCVar = function(name) return cvars[name] end,
            GetCVarDefault = function(name) return cvars[name] and "0" or nil end,
            GetCVarInfo = function(name)
                if cvars[name] == nil then return nil end
                -- One variable the client keeps to itself, to see it dropped.
                return cvars[name], "0", false, false, false, name == "ffxNether", false
            end,
            SetCVar = function(name, value)
                cvars[name] = value
                sets[#sets + 1] = name .. "=" .. value
                return true
            end,
        }
        GetMinRenderScale = function() return 0.33333334326744 end
        GetMaxRenderScale = function() return 2 end
        ns.db = { settings = { debug = false, upscale = { last = "quality" } } }

        local run = SlashCmdList.RENDERTUNER
        local ok, err = pcall(function()
            local knobs = ns.Apply.Knobs()
            T.Eq(#knobs, #Catalog.KNOBS - 1, "the secure variable is not offered")
            T.Eq(Model.Find(knobs, "ffxNether"), nil, "by name")
            T.Eq(Model.Find(knobs, "RenderScale").min, 0.3334, "the render scale takes the client's floor")

            ns.Baseline()
            T.Eq(ns.db.original.RenderScale, 1, "the first run records what was live")
            T.Eq(ns.db.saved.MSAAQuality, 3, "in both sets, as numbers")
            T.Eq(#ns.Changes(), 0, "and nothing differs from saved yet")

            run("preset quality")
            T.Eq(cvars.RenderScale, "0.67", "the preset sets the scale")
            T.Eq(cvars.ResampleQuality, "3", "and the FSR filter")
            T.Eq(#sets, 2, "and nothing else")
            T.Eq(#ns.Changes(), 2, "two settings now differ from saved")

            run("off")
            T.Eq(cvars.RenderScale, "1", "off is native")
            T.Eq(cvars.ResampleQuality, "3", "the filter stays where the preset left it")
            run("preset perf")
            T.Eq(ns.db.settings.upscale.last, "performance", "the last upscaling preset is remembered")
            run("off")
            run("on")
            T.Eq(cvars.RenderScale, "0.5", "on returns to it")

            run("set ResampleSharpness 1.5")
            T.Eq(cvars.ResampleSharpness, "0.5", "a reversed slider is set from the end the user reads")
            run("set vsync off")
            T.Eq(cvars.vsync, "0", "a toggle takes on and off")
            T.Eq(ns.pendingRestart, "window", "and a change that needs a refresh is remembered")
            local before = #sets
            run("set ffxAntiAliasingMode 9")
            run("set NoSuchVariable 1")
            run("set RenderScale fast")
            T.Eq(#sets, before, "a value not offered, an unknown variable and a word set nothing")

            run("revert")
            T.Eq(cvars.RenderScale, "1", "revert returns to the saved set")
            T.Eq(cvars.ResampleSharpness, "0.2", "all of it")
            T.Eq(#ns.Changes(), 0, "nothing differs again")

            run("preset balanced")
            run("save")
            T.Eq(ns.db.saved.RenderScale, 0.58, "save records what is live")
            T.Eq(ns.db.original.RenderScale, 1, "and leaves the original alone")
            run("restore")
            T.Eq(cvars.RenderScale, "1", "restore goes back to before the addon")

            -- The commands that only print, for a script error in them.
            run("list")
            run("list upscale")
            run("list changed")
            run("preset")
            run("")

            run("defaults")
            T.Eq(cvars.Gamma, "0", "defaults come from the client")
        end)

        C_CVar, GetMinRenderScale, GetMaxRenderScale, ns.db = real.C_CVar, real.min, real.max, real.db
        ns.pendingRestart = nil
        if not ok then error(err, 0) end
    end)
end
