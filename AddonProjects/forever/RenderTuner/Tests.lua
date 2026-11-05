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
    local FORMATS = { percent = true, percent100 = true, fps = true, nits = true, level = true }
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
        T.True(knob.experimental == nil or knob.experimental == true, name .. " is experimental or says nothing")
        T.True(knob.validated == nil or (knob.validated == true and knob.kind ~= "slider"),
            name .. " is validated only as a toggle or a choice")
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
    T.True(#Catalog.KNOBS > 120, "the catalogue is there")

    local used = {}
    for _, knob in ipairs(Catalog.KNOBS) do used[knob.group] = true end
    for _, group in ipairs(Catalog.GROUPS) do
        T.True(used[group.key], group.key .. " has at least one knob")
        T.True(type(group.note) == "string" and group.note ~= "", group.key .. " says what it is for")
    end
end)

T.Case("Catalog: the quality levels come twice, for the world and for raids, each under a master", function()
    local world, raid, masters = 0, 0, {}
    for _, knob in ipairs(Catalog.KNOBS) do
        if knob.rank == 2 then
            if knob.raid then raid = raid + 1 else world = world + 1 end
            T.Eq(knob.format, "level", knob.cvar .. " reads as a level")
        elseif knob.rank == 1 then
            masters[#masters + 1] = knob.cvar .. (knob.raid and " raid" or "")
        end
    end
    T.Eq(world, raid, "as many raid levels as world levels")
    T.True(world >= 15, "all of them")
    T.Eq(table.concat(masters, ", "), "graphicsQuality, RAIDgraphicsQuality raid", "one master for each set")

    T.Eq(Catalog.LEVELS[1].level, 0, "the lowest quality preset is the game's level 1")
    T.Eq(Catalog.LEVELS[#Catalog.LEVELS].level, 9, "the highest is its level 10")
    for i = 2, #Catalog.LEVELS do
        T.True(Catalog.LEVELS[i].level >= Catalog.LEVELS[i - 1].level, "each as high as the last")
    end
    -- Extreme is Ultra and then some: the same level, with experimental extras.
    local extreme = Catalog.LEVELS[#Catalog.LEVELS]
    T.Eq(extreme.key, "extreme", "the top of the strip")
    T.Eq(extreme.level, Catalog.LEVELS[#Catalog.LEVELS - 1].level, "at Ultra's level")
    T.True(extreme.experimental == true, "marked experimental")
    T.Eq(extreme.also.HDROutput, 1, "HDR output")
    T.Eq(extreme.also.RenderFormat, 3, "a 32-bit float render format, not the 16-bit the client starts at")
end)

T.Case("Catalog: Extreme turns real knobs to the heavy end of their own range", function()
    local extreme = Catalog.LEVELS[#Catalog.LEVELS]
    local byCvar = {}
    for _, knob in ipairs(Catalog.KNOBS) do byCvar[knob.cvar] = knob end
    -- Where more is lighter: these run toward their minimum, or off, as they get heavier.
    local lighter = { lodObjectCullSize = true, lodObjectMinSize = true, reflectionDownscale = true,
        worldBaseMip = true, terrainMipLevel = true, componentTextureLevel = true, unitClutter = true,
        vrsValar = true, vrsValarAlwaysOn = true }
    local count = 0
    for cvar, value in pairs(extreme.also) do
        count = count + 1
        local knob = byCvar[cvar]
        T.True(knob ~= nil, cvar .. " is a knob of the catalogue")
        T.True(knob.group ~= "upscale" and not knob.raid, cvar .. " is neither the render scale's nor the raid set's")
        T.True(knob.rank == nil, cvar .. " is not one of the levels, which Extreme leaves to Ultra")
        if knob.kind == "slider" then
            T.Eq(value, lighter[cvar] and knob.min or knob.max, cvar .. " at its heavy end")
        elseif knob.kind == "toggle" then
            T.Eq(value, lighter[cvar] and 0 or 1, cvar .. " at its heavy end")
        else
            local top = knob.choices[1][1]
            for _, choice in ipairs(knob.choices) do
                if lighter[cvar] then top = math.min(top, choice[1]) else top = math.max(top, choice[1]) end
            end
            T.Eq(value, top, cvar .. " at its heavy end")
        end
    end
    T.True(count >= 40, "it reaches well beyond the two it began with")
end)

T.Case("Catalog: every group is in a cluster, and the presets run from least to most", function()
    local clusters = {}
    for _, cluster in ipairs(Catalog.CLUSTERS) do clusters[cluster.key] = true end
    for _, group in ipairs(Catalog.GROUPS) do
        T.True(clusters[group.cluster], group.key .. " is in a cluster that exists")
    end
    T.True(Catalog.CLUSTERS[#Catalog.CLUSTERS].folded == true, "the last cluster is folded away")
    T.True(Catalog.CLUSTERS[1].folded ~= true, "the first is not")
end)

T.Case("Catalog: the presets run from potato up, and the model can read each", function()
    local limits = Model.Limits(0.33333334, 2)
    T.Eq(Catalog.PRESETS[#Catalog.PRESETS].key, "native", "native last")
    T.Eq(Catalog.PRESETS[#Catalog.PRESETS].scale, 1, "at full scale")
    for i = 2, #Catalog.PRESETS do
        T.True(Catalog.PRESETS[i].scale > Catalog.PRESETS[i - 1].scale, "each larger than the last")
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
local LEVEL = { cvar = "L", label = "Level", kind = "slider", min = 0, max = 9, step = 1, rank = 2, format = "level" }
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

T.Case("Model.Shown, FromShown, ShownRange: the numbers a player reads", function()
    T.Near(Model.Shown(SHARP, 0.2), 1.8, "a reversed slider reads from the other end")
    T.Near(Model.FromShown(SHARP, 1.8), 0.2, "and back")
    T.Eq(Model.Shown(LEVEL, 9), 10, "a quality level counts from 1")
    T.Eq(Model.FromShown(LEVEL, 10), 9, "and back to the variable's count from 0")
    T.Eq(Model.Shown(SLIDER, 0.67), 0.67, "a plain slider is itself")
    local low, high = Model.ShownRange(LEVEL)
    T.Eq(low .. " to " .. high, "1 to 10", "a level's range as shown")
    low, high = Model.ShownRange(SHARP)
    T.Eq(low .. " to " .. high, "0 to 2", "a reversed range keeps its ends in order")
    T.Eq(Model.Format(LEVEL, 0), "1", "a level is written as the game writes it")
    T.Eq(Model.RangeText(LEVEL), "1 to 10", "in its range too")
    T.Eq(Model.RangeText(SHARP), "0 to 2", "a reversed range reads low to high")
    T.Eq(Model.RangeText(CHOICE), "None, Two, Three", "a choice lists its names")
    T.Eq(Model.RangeText(TOGGLE), "on or off", "a toggle")
end)

T.Case("Model.Matches, View: which knobs are in view", function()
    local a = { cvar = "shadowMode", label = "Shadow mode", group = "shadow", kind = "slider", help = "The technique." }
    local b = { cvar = "SSAO", label = "Ambient occlusion", group = "light", kind = "choice",
        help = "Contact shadows in corners." }
    local c = { cvar = "Gamma", label = "Gamma", group = "colour", kind = "slider", help = "Gamma correction." }
    local knobs = { a, b, c }
    local groups = { { key = "shadow", label = "Shadows" }, { key = "light", label = "Lighting and fog" },
        { key = "colour", label = "Colour" } }

    T.True(Model.Matches(a, "SHADOW", "Shadows"), "by name, whatever the case")
    T.True(Model.Matches(b, "ssao", nil), "by console variable")
    T.True(Model.Matches(b, "contact", nil), "by its help")
    T.True(Model.Matches(c, "colour", "Colour"), "by its group")
    T.True(Model.Matches(b, "ambient corner", nil), "every word must be there, in any order")
    T.Eq(Model.Matches(b, "ambient potato", nil), false, "one missing word is no match")
    T.True(Model.Matches(a, "", nil), "nothing typed matches everything")

    local live, saved = { shadowMode = 2, SSAO = 0, Gamma = 1 }, { shadowMode = 4, SSAO = 0, Gamma = 1 }
    local function Names(list)
        local out = {}
        for i, knob in ipairs(list) do out[i] = knob.cvar end
        return table.concat(out, " ")
    end
    T.Eq(Names(Model.View(knobs, { group = "light" }, live, saved, groups)), "SSAO", "a group")
    T.Eq(Names(Model.View(knobs, { changed = true }, live, saved, groups)), "shadowMode", "what differs from saved")
    T.Eq(Names(Model.View(knobs, { search = "shadow" }, live, saved, groups)), "shadowMode SSAO",
        "a search crosses groups, in catalogue order")
    T.Eq(Names(Model.View(knobs, { search = "shadow", group = "colour" }, live, saved, groups)), "shadowMode SSAO",
        "and beats the group picked")
    T.Eq(Names(Model.View(knobs, { search = "  ", group = "colour" }, live, saved, groups)), "Gamma",
        "a blank search is no search")
    T.Eq(#Model.View(knobs, { search = "zzz" }, live, saved, groups), 0, "nothing found")

    T.Eq(Model.LevelOf(4, Catalog.LEVELS).key, "good", "a quality preset by its level")
    T.Eq(Model.LevelOf(5, Catalog.LEVELS), nil, "a level in between is no preset")
    T.Eq(Model.LevelOf(nil, Catalog.LEVELS), nil, "nor is no level")
end)

T.Case("Model.LevelOf, AlsoHeld: Extreme is Ultra with its extras held, and only then", function()
    local extreme = Catalog.LEVELS[#Catalog.LEVELS]
    local function Held() local t = {} for k, v in pairs(extreme.also) do t[k] = v end return t end
    local held = Held()
    T.Eq(Model.LevelOf(9, Catalog.LEVELS).key, "ultra", "without the settings to ask, Ultra")
    T.Eq(Model.LevelOf(9, Catalog.LEVELS, {}).key, "ultra", "and with none of the extras to be seen")
    T.Eq(Model.LevelOf(9, Catalog.LEVELS, held), extreme, "level 10 with the extras on is Extreme")
    local off = Held()
    off.farclip = 7000
    T.Eq(Model.LevelOf(9, Catalog.LEVELS, off).key, "ultra", "one extra off, Ultra")
    T.Eq(Model.LevelOf(6, Catalog.LEVELS, held).key, "high", "the extras alone make no level Extreme")
    T.True(Model.AlsoHeld(extreme, held), "held")
    T.Eq(Model.AlsoHeld(extreme, { HDROutput = 1 }), true, "a setting this client lacks is not held against it")
    T.Eq(Model.AlsoHeld(extreme, {}), false, "none to see is nothing held")
    T.Eq(Model.AlsoHeld(Catalog.LEVELS[1], held), false, "a preset with no extras holds none")

    -- A machine that cannot do ray traced shadows is not held to them.
    local noRt = function(cvar) return cvar == "shadowRt" and "needs ray tracing" or nil end
    local without = Held()
    without.shadowRt = 0
    T.Eq(Model.AlsoHeld(extreme, without), false, "off, where the card could have them: not Extreme")
    T.Eq(Model.AlsoHeld(extreme, without, noRt), true, "off, where it cannot: as far as it goes")
    T.Eq(Model.LevelOf(9, Catalog.LEVELS, without, noRt), extreme, "and Extreme lights")

    local wanted, left = Model.AlsoWanted(extreme, noRt)
    T.Eq(wanted.shadowRt, nil, "the refused one is not asked for")
    T.Eq(wanted.farclip, 10000, "the rest are")
    T.Eq(table.concat(left, ","), "shadowRt", "and it is named")
    T.Eq(next(select(2, Model.AlsoWanted(extreme))), nil, "with nothing refused, nothing is left out")
end)

T.Case("Model.PresetLabel, ParseTyped: the words on a button and the number a player types", function()
    local limits = Model.Limits(0.33333334, 2)
    T.Eq(Model.PresetLabel(Catalog.PRESETS[#Catalog.PRESETS], limits), "Native 100%", "name and share")
    T.Eq(Model.PresetLabel(Catalog.PRESETS[1], limits), "Potato 33%", "clamped and rounded")
    T.Eq(Model.PresetLabel(Catalog.PRESETS[1], Model.Limits(0.5, 2)), "Potato 50%", "to what the client allows")

    T.Near(Model.ParseTyped(SLIDER, "67"), 0.67, "a percentage as it reads")
    T.Near(Model.ParseTyped(SLIDER, " 67% "), 0.67, "with its sign and spaces")
    T.Near(Model.ParseTyped(SLIDER, "0.8"), 0.8, "a fraction as it is")
    T.Near(Model.ParseTyped(SHARP, "1.5"), 0.5, "a reversed knob, from the other end")
    T.Eq(Model.ParseTyped(SLIDER, "fast"), nil, "words are no number")
    T.Eq(Model.ParseTyped(SLIDER, ""), nil, "nor is nothing")
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
    T.Eq(Model.FindPreset(Catalog.PRESETS, "POTATO").key, "potato", "whatever the case")
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

    T.Eq(Model.Preset({ key = "potato", scale = 0.3334 }, Model.Limits(0.5, 2), 3).RenderScale, 0.5,
        "a preset under the client's floor sits on the floor")
    T.Eq(Model.PresetOf(0.8, Catalog.PRESETS, limits), nil, "a scale set by hand is no preset")
    T.Eq(Model.PresetOf(nil, Catalog.PRESETS, limits), nil, "nor is no scale")
end)

T.Case("Model.Label, WARNING: an experimental knob says so wherever it is named", function()
    local risky = { cvar = "X", label = "Ray traced shadows", kind = "toggle", experimental = true }
    T.Eq(Model.Label(risky), "Ray traced shadows |cffff8040experimental|r", "the mark follows the name")
    T.Eq(Model.Label(TOGGLE), "Tog", "a plain knob is only its name")
    T.True(Model.Line(risky, 1, 1):find("experimental", 1, true), "in a listing too")
    T.True(Model.WARNING.body:find("experimental", 1, true), "the warning names the mark")
    T.True(Model.WARNING.body:find("WTF\\Config.wtf", 1, true), "and the way back when the game will not start")

    local marked = 0
    for _, knob in ipairs(Catalog.KNOBS) do
        if knob.experimental then marked = marked + 1 end
    end
    T.True(marked >= 1, "the catalogue marks at least the client's own beta feature")
end)

T.Case("Model.Locked: a knob is locked when the client refuses every value but the live one", function()
    local function Refuse(values)
        return function(_, value) return values[value] end
    end
    T.Eq(Model.Locked(CHOICE, 0, Refuse({ [2] = "needs ray tracing", [3] = "needs more" })), "needs ray tracing",
        "every other choice refused: locked, with the first reason")
    T.Eq(Model.Locked(CHOICE, 0, Refuse({ [3] = "needs more" })), nil, "one other choice allowed: not locked")
    T.Eq(Model.Locked(CHOICE, 2, Refuse({ [2] = "odd" })), nil, "a refusal of the live value locks nothing")
    T.Eq(Model.Locked(TOGGLE, 0, Refuse({ [1] = "no" })), "no", "a toggle that cannot be turned on")
    T.Eq(Model.Locked(TOGGLE, 1, Refuse({ [1] = "no" })), nil, "it can still be turned off")
    T.Eq(Model.Locked(SLIDER, 1, Refuse({ [0] = "no", [1] = "no" })), nil, "a slider is never asked about")
end)

T.Case("Model.AsksFirst: turning an experimental knob on is confirmed, turning it off is not", function()
    local risky = { cvar = "X", label = "Risky", kind = "toggle", experimental = true }
    T.Eq(Model.AsksFirst(risky, 1), true, "on")
    T.Eq(Model.AsksFirst(risky, 0), false, "off")
    T.Eq(Model.AsksFirst(risky, nil), false, "no value")
    T.Eq(Model.AsksFirst(TOGGLE, 1), false, "a plain knob never asks")
end)

T.Case("Model.Line, Status: lines of text", function()
    T.True(Model.Line(SLIDER, 0.67, 0.67):find("Slide |cff888888S|r: 67%", 1, true), "label, variable, value")
    T.Eq(Model.Line(SLIDER, 0.67, 0.67):find("saved", 1, true), nil, "nothing more when it is as saved")
    T.True(Model.Line(SLIDER, 0.67, 1):find("saved: 100%", 1, true), "the saved value when it differs")

    T.Eq(Model.Status("67%", { label = "Quality" }, 0), "render scale 67% (Quality), everything as saved.", "settled")
    T.Eq(Model.Status("80%", nil, 1), "render scale 80%, 1 setting differs from the saved set.", "one change")
    T.Eq(Model.Status("80%", nil, 3), "render scale 80%, 3 settings differ from the saved set.", "several")
    T.Eq(Model.Brief("67%", { label = "Quality" }, 0), "67% Quality", "short, for a title bar")
    T.Eq(Model.Brief("80%", nil, 2), "80%, 2 unsaved", "with what is unsaved")
    T.True(Model.RestartHint("gx"):find("/tuner restart", 1, true), "a restart hint names the command")
    T.Eq(Model.RestartHint(nil), nil, "no need, no hint")
end)

--------------------------------------------------------------------------------
-- Core
--------------------------------------------------------------------------------

T.Case("LoadLines: the version and where things stand", function()
    T.Eq(ns.LoadLines("0.1.0", "render scale 67% (Quality), everything as saved.")[1],
        "v0.1.0 loaded: render scale 67% (Quality), everything as saved. /tuner opens the panel.", "one line")
end)

--------------------------------------------------------------------------------
-- The commands and the panel against a made-up client
--------------------------------------------------------------------------------

-- In game these would change the player's real settings, so they run only under the
-- harness. The client here is a table of console variables that answers the four calls
-- Apply.lua makes.
if IC_HEADLESS then
    local function WithClient(body)
        local cvars, sets = {}, {}
        for _, knob in ipairs(Catalog.KNOBS) do cvars[knob.cvar] = "1" end
        cvars.RenderScale, cvars.ResampleQuality, cvars.ResampleSharpness = "1", "2", "0.2"
        cvars.MSAAQuality = "3,0"

        local real = { C_CVar = C_CVar, min = GetMinRenderScale, max = GetMaxRenderScale, db = ns.db, cdb = ns.cdb,
            supported = IsGraphicsCVarValueSupported, reason = VRN_NEEDS_RT,
            level = GetGraphicsCVarValueForQualityLevel,
            dialogs = StaticPopupDialogs, show = StaticPopup_Show }
        -- This machine has no ray tracing: reason 11 in the client's list, for any value but off.
        IsGraphicsCVarValueSupported = function(name, value)
            return (name == "shadowRt" and value ~= 0) and 11 or 0
        end
        VRN_NEEDS_RT = "Needs ray tracing"
        -- What each level beneath the overall one should be: here, never more than 2.
        GetGraphicsCVarValueForQualityLevel = function(_, level) return math.min(level, 2) end
        GetFramerate = function() return 141.6 end
        -- A confirm dialog that remembers what it was asked and can be answered.
        local asked = {}
        StaticPopupDialogs = {}
        StaticPopup_Show = function(which, text, _, data)
            asked[#asked + 1] = { text = text, yes = function() StaticPopupDialogs[which].OnAccept(nil, data) end }
        end
        ns.Apply.ForgetSupport()
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
        -- The warning has been dismissed for good, except in the case that is about it.
        ns.db = { settings = { debug = false, upscale = { last = "quality" }, skipWarning = true } }
        ns.cdb = { panel = { group = "upscale" } }

        local ok, err = pcall(body, cvars, sets, SlashCmdList.RENDERTUNER, asked)

        if ns.Panel.IsShown() then ns.Panel.Toggle() end
        ns.Panel.ResetWarning()
        C_CVar, GetMinRenderScale, GetMaxRenderScale = real.C_CVar, real.min, real.max
        IsGraphicsCVarValueSupported, VRN_NEEDS_RT = real.supported, real.reason
        GetGraphicsCVarValueForQualityLevel = real.level
        GetFramerate = nil
        StaticPopupDialogs, StaticPopup_Show = real.dialogs, real.show
        ns.Apply.ForgetSupport()
        ns.db, ns.cdb = real.db, real.cdb
        ns.pendingRestart = nil
        if not ok then error(err, 0) end
    end

    T.Case("Commands: presets, set, save, revert and restore against a made-up client", function()
        WithClient(function(cvars, sets, run)
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
            run("status")

            run("defaults")
            T.Eq(cvars.Gamma, "0", "defaults come from the client")
        end)
    end)

    T.Case("Panel: a row for each knob of the group in view, and a control sets its variable", function()
        WithClient(function(cvars, sets, run)
            ns.Baseline()
            run("")
            T.True(ns.Panel.IsShown(), "the bare command opens the panel")
            local made, showing = ns.Panel.Counts()
            T.Eq(showing, 6, "the upscaling group's six knobs")
            T.Eq(made, 6, "and no row for a group not yet looked at")

            -- A slider row: the control reports what the player reads, the variable gets its own.
            local sharp = ns.Panel.Row("ResampleSharpness")
            T.Near(sharp.control:GetValue(), 1.8, "a reversed knob shows from the other end")
            sharp.control.inner:GetScript("OnValueChanged")(sharp.control.inner, 1.5)
            T.Eq(cvars.ResampleSharpness, "0.5", "and sets the variable the right way round")
            T.Eq(sharp.name.icTextRole, "accent", "a row that differs from saved is marked")

            -- The render scale waits for the thumb to be let go.
            local scale = ns.Panel.Row("RenderScale")
            local before = #sets
            scale.control.inner:GetScript("OnMouseDown")(scale.control.inner)
            scale.control.inner:GetScript("OnValueChanged")(scale.control.inner, 0.8)
            T.Eq(#sets, before, "nothing is set while it is held")
            scale.control.inner:GetScript("OnMouseUp")(scale.control.inner)
            T.Eq(cvars.RenderScale, "0.8", "it is set on release")

            -- A toggle and a choice, in groups that are made when first shown.
            ns.Panel.ShowGroup("frame")
            T.Eq(ns.cdb.panel.group, "frame", "the group in view is remembered")
            local vsync = ns.Panel.Row("vsync")
            T.Eq(vsync.control:GetChecked(), true, "a toggle shows what is live")
            vsync.control:GetScript("OnClick")(vsync.control)
            T.Eq(cvars.vsync, "0", "a click sets it")
            T.Eq(ns.pendingRestart, "window", "and what it needs is remembered")

            ns.Panel.ShowGroup("aa")
            local msaa = ns.Panel.Row("MSAAQuality")
            T.Eq(msaa.control:GetValue(), 3, "a choice shows what is live, read as a number")
            T.Eq(msaa.control.label:GetText(), "8x", "by its label")

            -- Every group builds.
            for _, group in ipairs(Catalog.GROUPS) do ns.Panel.ShowGroup(group.key) end
            made = ns.Panel.Counts()
            T.Eq(made, #ns.Apply.Knobs(), "a row for every knob once every group has been seen")

            -- The overall quality level carries the levels beneath it.
            ns.Panel.ShowGroup("quality")
            local overall = ns.Panel.Row("graphicsQuality")
            overall.control.inner:GetScript("OnValueChanged")(overall.control.inner, 7)
            T.Eq(cvars.graphicsQuality, "6", "level 7 as the game counts is 6 in the variable")
            T.Eq(cvars.graphicsShadowQuality, "2", "and each level beneath it is set to what the client says")
            T.Eq(ns.Panel.Row("graphicsShadowQuality").control:GetValue(), 3, "which the rows show, counted from 1")
            T.Eq(cvars.raidGraphicsShadowQuality, "1", "the raid levels are a separate set, and untouched")

            -- A preset brings the settings it changes into view.
            ns.Panel.Preset("performance"):GetScript("OnClick")(ns.Panel.Preset("performance"))
            T.Eq(ns.cdb.panel.group, "upscale", "a preset shows the upscaling group")
            T.Eq(cvars.RenderScale, "0.5", "sets the scale")
            T.Near(ns.Panel.Row("RenderScale").control:GetValue(), 0.5, "and the row shows it")
            T.Eq(ns.Panel.Row("graphicsQuality"):IsShown(), false, "the quality levels are out of view, and untouched")
            T.Eq(cvars.graphicsQuality, "6", "as the variable says")

            run("revert")
            T.Eq(cvars.ResampleSharpness, "0.2", "revert from the command line reaches the same settings")
            ns.Panel.ShowGroup("upscale")
            T.Eq(ns.Panel.Row("ResampleSharpness").name.icTextRole, "text", "and the panel shows it")

            run("")
            T.Eq(ns.Panel.IsShown(), false, "the bare command closes it again")
        end)
    end)

    T.Case("Panel: quality presets, the search box, the Changed view and the ways back", function()
        WithClient(function(cvars, sets, run)
            ns.Baseline()
            run("")
            local frame = ns.Panel.Frame()

            -- A quality preset sets the master level and the levels beneath it, and shows them.
            ns.Panel.Level("high"):GetScript("OnClick")(ns.Panel.Level("high"))
            T.Eq(cvars.graphicsQuality, "6", "High is level 7 of 10")
            T.Eq(cvars.graphicsViewDistance, "2", "with the levels beneath it")
            T.Eq(ns.cdb.panel.group, "quality", "and the quality levels come into view")
            T.Eq(cvars.RenderScale, "1", "upscaling is left alone")
            T.Eq(ns.Panel.Level("high").icKind, "accent", "the preset in use is highlighted")
            T.Eq(frame.head:GetText(), "Quality levels", "the heading names the group")

            run("quality low")
            T.Eq(cvars.graphicsQuality, "0", "the command does the same")
            T.Eq(ns.Panel.Level("low").icKind, "accent", "and the panel follows")
            T.Eq(ns.Panel.Level("high").icKind, "normal", "the other is let go")

            -- The raid master carries the raid levels, not the world's.
            ns.Panel.ShowGroup("raid")
            local raid = ns.Panel.Row("RAIDgraphicsQuality")
            raid.control.inner:GetScript("OnValueChanged")(raid.control.inner, 10)
            T.Eq(cvars.RAIDgraphicsQuality, "9", "the raid master")
            T.Eq(cvars.raidGraphicsViewDistance, "2", "moves the raid levels")
            T.Eq(cvars.graphicsViewDistance, "0", "and not the world's")

            -- Search crosses groups and beats the group picked.
            ns.Panel.Search("sharp")
            local _, showing = ns.Panel.Counts()
            T.True(showing >= 3, "a search finds knobs in more than one group")
            T.True(ns.Panel.Row("ResampleSharpness"):IsShown(), "from upscaling")
            T.True(ns.Panel.Row("CMAA2ExtraSharpness"):IsShown(), "and from anti-aliasing")
            T.Eq(ns.Panel.Row("RAIDgraphicsQuality"):IsShown(), false, "the group that was in view gives way")
            T.Eq(frame.head:GetText(), 'Search: "sharp"', "the heading says what was searched for")
            ns.Panel.Search("no such setting")
            T.Eq(frame.empty:GetText(), "No setting matches.", "nothing found says so")
            ns.Panel.Search("")
            T.True(ns.Panel.Row("RAIDgraphicsQuality"):IsShown(), "clearing the search brings the group back")

            -- A changed row gains an undo, and the heading a way back for all in view.
            ns.Panel.ShowGroup("colour")
            local gamma = ns.Panel.Row("Gamma")
            T.Eq(gamma.undo:IsShown(), false, "no undo on a row that is as saved")
            T.Eq(frame.revertView:IsShown(), false, "and nothing to revert in view")
            gamma.control.inner:GetScript("OnValueChanged")(gamma.control.inner, 1.4)
            T.Eq(cvars.Gamma, "1.4", "changed")
            T.True(gamma.undo:IsShown(), "the undo appears")
            T.True(frame.revertView:IsShown(), "and the way back for the view")
            gamma.undo:GetScript("OnClick")(gamma.undo)
            T.Eq(cvars.Gamma, "1", "undo puts the one setting back")
            T.Eq(gamma.undo:IsShown(), false, "and goes away again")

            -- The Changed view lists what differs, and keeps a row that has been put back.
            ns.Panel.ShowGroup("changed")
            local changedRows = select(2, ns.Panel.Counts())
            T.Eq(changedRows, #ns.Changes(), "one row for each setting that differs from saved")
            T.True(ns.Panel.Row("graphicsQuality"):IsShown(), "the quality level is among them")
            local level = ns.Panel.Row("graphicsQuality")
            level.undo:GetScript("OnClick")(level.undo)
            T.True(level:IsShown(), "put back, it stays in the list while the view is open")
            T.Eq(select(2, ns.Panel.Counts()), changedRows, "so nothing jumps under the pointer")
            frame.revertView:GetScript("OnClick")(frame.revertView)
            T.Eq(#ns.Changes(), 0, "Revert these puts back everything in view")
            ns.Panel.ShowGroup("changed")
            T.Eq(select(2, ns.Panel.Counts()), 0, "and opened afresh, the view is empty")
            T.Eq(frame.empty:GetText(), "Nothing differs from the saved set.", "and says so")

            -- A long group scrolls. The folded cluster open is the roomiest the view gets.
            ns.Panel.SetAdvanced(true)
            ns.Panel.ShowGroup("world")
            frame.scroll:ScrollTo(48)
            T.Eq(frame.scroll:GetOffset(), 0, "a group that fits does not scroll")
            ns.Panel.ShowGroup("quality")
            frame.scroll:ScrollTo(24)
            T.Eq(frame.scroll:GetOffset(), 24, "a long one does")
            ns.Panel.ShowGroup("colour")
            T.Eq(frame.scroll:GetOffset(), 0, "and a new view starts at the top")
        end)
    end)

    T.Case("Panel: the warning comes first, once a session, until its box is ticked", function()
        WithClient(function(cvars, sets, run)
            ns.Baseline()
            ns.db.settings.skipWarning = false
            ns.Panel.ResetWarning()

            run("")
            local notice = ns.Panel.Notice()
            T.True(notice ~= nil and notice:IsShown(), "the first open shows the warning")
            T.Eq(ns.Panel.IsShown(), false, "and not the panel")

            notice.go:GetScript("OnClick")(notice.go)
            T.Eq(notice:IsShown(), false, "understood: the warning goes")
            T.True(ns.Panel.IsShown(), "and the panel opens")
            T.Eq(ns.db.settings.skipWarning, false, "with the box unticked, nothing is remembered for next time")

            run("")
            run("")
            T.True(ns.Panel.IsShown(), "it is not shown twice in a session")
            run("")

            -- A new session: it comes back, and this time the box is ticked.
            ns.Panel.ResetWarning()
            run("")
            T.True(notice:IsShown(), "the next session warns again")
            notice.skip:SetChecked(true)
            notice.go:GetScript("OnClick")(notice.go)
            T.Eq(ns.db.settings.skipWarning, true, "ticked: never again")

            run("")
            ns.Panel.ResetWarning()
            run("")
            T.Eq(notice:IsShown(), false, "not even in a new session")
            T.True(ns.Panel.IsShown(), "the panel opens straight away")
        end)
    end)

    T.Case("Panel: Extreme asks first, sets its extras, and a lower level takes them back", function()
        WithClient(function(cvars, sets, run, asked)
            ns.Baseline()
            run("")
            local button = ns.Panel.Level("extreme")
            -- Where the client's first run left things: well short of the ceilings.
            cvars.HDROutput, cvars.RenderFormat, cvars.farclip, cvars.shadowNumCascades = "0", "2", "7000", "3"
            cvars.MSAAQuality = "0"
            button:GetScript("OnClick")(button)
            T.Eq(#asked, 1, "Extreme is asked about")
            T.Eq(cvars.HDROutput, "0", "and nothing is set until the answer")
            asked[1].yes()
            T.Eq(cvars.HDROutput, "1", "yes: HDR output on")
            T.Eq(cvars.RenderFormat, "3", "the 32-bit float format, past the 16-bit it began at")
            T.Eq(cvars.farclip, "10000", "the draw distance at its ceiling")
            T.Eq(cvars.shadowNumCascades, "4", "the fourth shadow cascade")
            T.Eq(cvars.MSAAQuality, "3", "8x multisampling")
            T.Eq(cvars.shadowRt, "1", "ray traced shadows, which this machine cannot do, left alone")
            T.Eq(cvars.graphicsQuality, "9", "on top of level 10")
            T.Eq(ns.Panel.Level("extreme").icKind, "accent", "Extreme is the one lit")
            T.Eq(ns.Panel.Level("ultra").icKind, "normal", "and Ultra is not")

            -- Once on, pressing it again asks nothing.
            button:GetScript("OnClick")(button)
            T.Eq(#asked, 1, "no second question for what is already on")

            local ultra = ns.Panel.Level("ultra")
            ultra:GetScript("OnClick")(ultra)
            T.Eq(cvars.HDROutput, "0", "Ultra puts HDR back as it was")
            T.Eq(cvars.RenderFormat, "2", "and the render format")
            T.Eq(cvars.farclip, "7000", "and the draw distance")
            T.Eq(cvars.shadowNumCascades, "3", "and the cascades")
            T.Eq(cvars.MSAAQuality, "0", "and the multisampling")
            T.Eq(ns.db.settings.beforeExtras, nil, "the note of what they were is spent")
            T.Eq(ns.Panel.Level("ultra").icKind, "accent", "Ultra is lit again")

            -- A player's own change to one of them means Extreme is no longer in force, so
            -- a lower level leaves the extras to the player.
            button:GetScript("OnClick")(button)
            asked[#asked].yes()
            cvars.farclip = "8000"
            local high = ns.Panel.Level("high")
            high:GetScript("OnClick")(high)
            T.Eq(cvars.MSAAQuality, "3", "tuned by hand, the extras stay")
        end)
    end)

    T.Case("Panel: the strips run low to high and the upscaling buttons carry their share", function()
        WithClient(function(cvars, sets, run)
            ns.Baseline()
            run("")
            T.Eq(ns.Panel.Preset("native").label:GetText(), "Native 100%", "native, on the right")
            T.Eq(ns.Panel.Preset("potato").label:GetText(), "Potato 33%", "potato, on the left")
            T.Eq(ns.Panel.Preset("native").icKind, "accent", "the preset the scale is at is lit")
        end)
    end)

    T.Case("Panel: the folded cluster opens and folds, and never hides the group in view", function()
        WithClient(function(cvars, sets, run)
            ns.Baseline()
            run("")
            local frame = ns.Panel.Frame()
            ns.Panel.SetAdvanced(false)
            T.Eq(ns.Panel.Group("ssao"):IsShown(), false, "folded: its groups are out of the nav")
            T.Eq(ns.Panel.Group("shadow"):IsShown(), true, "the others are not")
            local folded = frame:GetHeight()

            ns.Panel.ShowGroup("raid")
            T.Eq(ns.Panel.Group("raid"):IsShown(), true, "a group in it, picked, opens the cluster")
            T.True(frame:GetHeight() > folded, "and the panel grows to fit")
            ns.Panel.SetAdvanced(false)
            T.Eq(ns.cdb.panel.group, "upscale", "folding it with one of its groups in view moves to the first group")
            T.Eq(ns.Panel.Group("raid"):IsShown(), false, "and hides them again")
            T.Eq(frame:GetHeight(), folded, "at the height it had")
        end)
    end)

    T.Case("Panel: compact folds the body away, peek clears the panel, a held slider half clears it", function()
        WithClient(function(cvars, sets, run)
            ns.Baseline()
            run("")
            local frame = ns.Panel.Frame()
            local full = frame:GetHeight()

            ns.Panel.SetCompact(true)
            T.True(ns.Panel.IsCompact(), "compact")
            T.Eq(frame.body:IsShown(), false, "the body is folded")
            T.Eq(frame.search:IsShown(), false, "and the search with it")
            T.True(frame:GetHeight() < full / 2, "the panel is a fraction of its height")
            T.Eq(ns.cdb.panel.compact, true, "remembered")
            ns.Panel.SetCompact(false)
            T.Eq(frame.body:IsShown(), true, "expanded again")
            T.Eq(frame:GetHeight(), full, "to the same height")

            ns.Panel.Peek(true)
            T.True(frame:GetAlpha() < 0.2, "peek: nearly clear")
            ns.Panel.Peek(false)
            T.Eq(frame:GetAlpha(), 1, "let go: back")

            local scale = ns.Panel.Row("RenderScale")
            scale.control.inner:GetScript("OnMouseDown")(scale.control.inner)
            T.True(frame:GetAlpha() < 1 and frame:GetAlpha() > 0.2, "a held slider half clears it")
            ns.Panel.Peek(true)
            T.True(frame:GetAlpha() < 0.2, "peek wins over it")
            ns.Panel.Peek(false)
            scale.control.inner:GetScript("OnMouseUp")(scale.control.inner)
            T.Eq(frame:GetAlpha(), 1, "let go of the thumb: clear of it")

            frame:Hide()
            ns.Panel.Peek(true)
            T.Eq(frame:GetAlpha(), 1, "peek with the panel shut does nothing")
        end)
    end)

    T.Case("Panel: a number typed into a slider sets the variable", function()
        WithClient(function(cvars, sets, run)
            ns.Baseline()
            run("")
            local scale = ns.Panel.Row("RenderScale")
            local entry = scale.control.entry
            T.True(entry ~= nil, "the render scale can be typed over")
            entry:SetText("75")
            entry:GetScript("OnEnterPressed")(entry)
            T.Eq(cvars.RenderScale, "0.75", "75 is 75 percent")
            entry:SetText("nonsense")
            entry:GetScript("OnEnterPressed")(entry)
            T.Eq(cvars.RenderScale, "0.75", "words change nothing")
        end)
    end)

    T.Case("Panel: a value the client refuses is not set, and an experimental knob asks first", function()
        WithClient(function(cvars, sets, run, asked)
            cvars.shadowRt, cvars.DynamicRenderScale = "0", "0"
            ns.Baseline()
            run("")

            -- Ray traced shadows on a machine without ray tracing.
            ns.Panel.ShowGroup("shadow")
            local rt = ns.Panel.Row("shadowRt")
            T.Eq(rt.locked, "Needs ray tracing", "the row is locked, with the client's reason")
            T.Eq(rt.name.icTextRole, "textDisabled", "and greyed out")
            T.Eq(ns.Panel.Row("shadowSoft").locked, false, "a knob the client is not asked about is left alone")
            local before = #sets
            run("set shadowRt 2")
            T.Eq(#sets, before, "the command refuses it too")
            T.Eq(cvars.shadowRt, "0", "and the variable is untouched")

            -- Dynamic render scale: experimental, so turning it on is asked about.
            ns.Panel.ShowGroup("upscale")
            local dynamic = ns.Panel.Row("DynamicRenderScale")
            dynamic.control:GetScript("OnClick")(dynamic.control)
            T.Eq(cvars.DynamicRenderScale, "0", "a click does not turn it on")
            T.Eq(dynamic.control:GetChecked(), false, "and the box goes back to what is live")
            T.Eq(#asked, 1, "it asks")
            T.True(asked[1].text:find("Dynamic render scale is experimental", 1, true), "naming the knob")
            asked[1].yes()
            T.Eq(cvars.DynamicRenderScale, "1", "yes turns it on")
            T.Eq(dynamic.control:GetChecked(), true, "and the box shows it")

            dynamic.control:GetScript("OnClick")(dynamic.control)
            T.Eq(cvars.DynamicRenderScale, "0", "turning it off is not asked about")
            T.Eq(#asked, 1, "no second question")
        end)
    end)
end
