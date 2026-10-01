local addonName, ns = ...

--[[
The model: every decision the addon makes about values, as pure functions. Nothing here
asks the client anything; what it needs comes in as arguments.

A value is a number throughout. The client hands console variables over as text
("0.670000", "3,0"), so they are normalised on the way in and written as short text on
the way out.

    Model.Norm(knob, raw)            -> number or nil
    Model.Text(n)                    -> the text to set a variable to
    Model.Limits(min, max)           -> render scale limits, rounded inward
    Model.Clamp(knob, n)             -> value, or nil and why
    Model.Shown, Model.FromShown     the number a user reads for a slider, and back
    Model.Format(knob, n)            -> "67%", "CMAA2", "on"
    Model.Same(a, b)
    Model.Snapshot(knobs, get)       -> { [cvar] = number }
    Model.Fill(into, from)           -> how many missing keys were copied
    Model.Diff(from, to, knobs)      -> { { knob, from, to }, ... } in catalogue order
    Model.Plan(target, live, knobs)  -> { { cvar, value, knob }, ... } in the order to set them
    Model.Restart(changes)           -> "client", "gx", "window" or nil
    Model.Find(knobs, text), Model.Group(groups, text), Model.FindPreset(presets, text)
    Model.Preset(preset, limits, fsr) -> target
    Model.PresetOf(scale, presets, limits) -> preset or nil
    Model.Line(knob, live, saved), Model.Status(...)
]]

local Util = LibStub("LibICUtil-1.0")

local Model = {}
ns.Model = Model

local EPSILON = 0.0001

--------------------------------------------------------------------------------
-- Values
--------------------------------------------------------------------------------

function Model.Norm(knob, raw)
    if raw == nil then return nil end
    local n = raw
    if type(n) ~= "number" then
        -- The leading number: "3,0" is multisampling level 3, coverage 0.
        n = tonumber(tostring(raw):match("^%s*(-?%d*%.?%d+)"))
    end
    if not n then return nil end
    if knob.kind == "toggle" then return n ~= 0 and 1 or 0 end
    return n
end

function Model.Text(n)
    local whole = math.floor(n + 0.5)
    if math.abs(n - whole) < EPSILON then return string.format("%d", whole) end
    return (string.format("%.4f", n):gsub("0+$", ""))
end

function Model.Same(a, b)
    return a ~= nil and b ~= nil and math.abs(a - b) < EPSILON
end

-- The client's render scale limits, moved inward to four places: a limit of 0.33333334
-- written back as "0.3333" would be under it.
function Model.Limits(min, max)
    min, max = tonumber(min) or 0.3334, tonumber(max) or 2
    return { min = math.ceil(min * 10000 - EPSILON) / 10000, max = math.floor(max * 10000 + EPSILON) / 10000 }
end

function Model.Clamp(knob, n)
    n = tonumber(n)
    if not n then return nil, "that is not a number" end
    if knob.kind == "toggle" then return n ~= 0 and 1 or 0 end
    if knob.kind == "choice" then
        local offered = {}
        for _, choice in ipairs(knob.choices) do
            if Model.Same(choice[1], n) then return choice[1] end
            offered[#offered + 1] = string.format("%s (%s)", Model.Text(choice[1]), choice[2])
        end
        return nil, "it takes " .. table.concat(offered, ", ")
    end
    -- A slider snaps to whole steps, and its two ends stay reachable whatever the step.
    local snapped = math.floor(n / knob.step + 0.5) * knob.step
    return Util.Clamp(snapped, knob.min, knob.max)
end

-- A reversed slider reads backwards: the variable's 0 is the strongest setting.
function Model.Shown(knob, n)
    if knob.reversed then return knob.max + knob.min - n end
    return n
end
Model.FromShown = Model.Shown

function Model.Format(knob, n)
    if n == nil then return "?" end
    if knob.kind == "toggle" then return n ~= 0 and "on" or "off" end
    if knob.kind == "choice" then
        for _, choice in ipairs(knob.choices) do
            if Model.Same(choice[1], n) then return choice[2] end
        end
        return Model.Text(n)
    end
    local shown = Model.Shown(knob, n)
    if knob.format == "percent" then return string.format("%d%%", math.floor(shown * 100 + 0.5)) end
    if knob.format == "percent100" then return string.format("%d%%", math.floor(shown + 0.5)) end
    if knob.format == "fps" then return string.format("%d fps", math.floor(shown + 0.5)) end
    if knob.format == "nits" then return string.format("%d nits", math.floor(shown + 0.5)) end
    return Model.Text(shown)
end

--------------------------------------------------------------------------------
-- Sets of values
--------------------------------------------------------------------------------

function Model.Snapshot(knobs, get)
    local out = {}
    for _, knob in ipairs(knobs) do
        out[knob.cvar] = Model.Norm(knob, get(knob.cvar))
    end
    return out
end

-- Copies what `into` lacks. A knob added in a later version joins the saved sets with
-- the value it has when first seen.
function Model.Fill(into, from)
    local added = 0
    for cvar, value in pairs(from) do
        if into[cvar] == nil then
            into[cvar] = value
            added = added + 1
        end
    end
    return added
end

function Model.Diff(from, to, knobs)
    local changes = {}
    for _, knob in ipairs(knobs) do
        local a, b = from[knob.cvar], to[knob.cvar]
        if a ~= nil and b ~= nil and not Model.Same(a, b) then
            changes[#changes + 1] = { knob = knob, from = a, to = b }
        end
    end
    return changes
end

-- What to set, and in what order, to turn `live` into `target`. Blizzard's quality levels
-- go first: the client moves the variables beneath a level when the level changes, so
-- those variables have to be set after it or they are overwritten.
function Model.Plan(target, live, knobs)
    local plan = {}
    for index, knob in ipairs(knobs) do
        local want, have = target[knob.cvar], live[knob.cvar]
        if want ~= nil and have ~= nil and not Model.Same(want, have) then
            plan[#plan + 1] = { cvar = knob.cvar, value = Model.Text(want), knob = knob, index = index }
        end
    end
    table.sort(plan, function(a, b)
        local ra, rb = a.knob.rank or 3, b.knob.rank or 3
        if ra ~= rb then return ra < rb end
        return a.index < b.index
    end)
    return plan
end

local WEIGHT = { window = 1, gx = 2, client = 3 }

-- The heaviest restart any of these changes needs. Takes a plan or a diff.
function Model.Restart(changes)
    local worst
    for _, change in ipairs(changes) do
        local need = change.knob.restart
        if need and (worst == nil or WEIGHT[need] > WEIGHT[worst]) then worst = need end
    end
    return worst
end

--------------------------------------------------------------------------------
-- Finding things by what the user typed
--------------------------------------------------------------------------------

function Model.Find(knobs, text)
    local want = Util.Trim(text or ""):lower()
    if want == "" then return nil end
    for _, knob in ipairs(knobs) do
        if knob.cvar:lower() == want then return knob end
    end
    return nil
end

-- A row of `rows` whose key or label is `text`, or the only one either starts with.
local function Pick(rows, text)
    local want = Util.Trim(text or ""):lower()
    if want == "" then return nil end
    local found, count = nil, 0
    for _, row in ipairs(rows) do
        local key, label = row.key:lower(), row.label:lower()
        if key == want or label == want then return row end
        if key:sub(1, #want) == want or label:sub(1, #want) == want then
            found, count = row, count + 1
        end
    end
    return count == 1 and found or nil
end

Model.Group = Pick
Model.FindPreset = Pick

--------------------------------------------------------------------------------
-- Presets
--------------------------------------------------------------------------------

-- What a preset sets. Below 100% the resample filter becomes FSR; at 100% the filter is
-- left alone, since nothing is being upscaled.
function Model.Preset(preset, limits, fsr)
    local scale = Util.Clamp(preset.scale, limits.min, limits.max)
    local target = { RenderScale = scale }
    if scale < 1 - EPSILON then target.ResampleQuality = fsr end
    return target
end

-- The preset a render scale belongs to, or nil for a scale set by hand.
function Model.PresetOf(scale, presets, limits)
    if scale == nil then return nil end
    for _, preset in ipairs(presets) do
        if math.abs(Util.Clamp(preset.scale, limits.min, limits.max) - scale) < 0.005 then return preset end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Lines of text
--------------------------------------------------------------------------------

function Model.Line(knob, live, saved)
    local text = string.format("  %s |cff888888%s|r: %s", knob.label, knob.cvar, Model.Format(knob, live))
    if saved ~= nil and live ~= nil and not Model.Same(live, saved) then
        text = text .. string.format("  |cffffcc00saved: %s|r", Model.Format(knob, saved))
    end
    return text
end

local RESTART_HINT = {
    window = "A change here needs the window refreshed: /tuner restart.",
    gx = "A change here needs the graphics engine restarted: /tuner restart (the screen blinks).",
    client = "A change here needs the game restarted.",
}

function Model.RestartHint(need)
    return RESTART_HINT[need]
end

-- "render scale 67% (Quality), 2 settings differ from the saved set."
function Model.Status(scaleText, preset, changed)
    local text = "render scale " .. scaleText
    if preset then text = text .. " (" .. preset.label .. ")" end
    if changed == 0 then
        return text .. ", everything as saved."
    end
    return string.format("%s, %d %s from the saved set.", text, changed,
        changed == 1 and "setting differs" or "settings differ")
end
