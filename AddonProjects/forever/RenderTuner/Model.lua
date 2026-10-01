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
    Model.ShownRange(knob)           -> the slider's two ends in those numbers
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
    Model.Label(knob), Model.WARNING
    Model.Locked(knob, live, unsupported)  -> why the client will take no other value, or nil
    Model.AsksFirst(knob, value)           -> whether a change to this value is confirmed first
    Model.Line(knob, live, saved), Model.Status(...), Model.Brief(...)
    Model.Matches(knob, text, groupLabel), Model.View(knobs, view, live, saved, groups)
    Model.RangeText(knob), Model.LevelOf(level, levels)
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

-- The number a player reads is not always the variable's own. A reversed slider reads
-- backwards: the variable's 0 is the strongest setting. A quality level counts from 1,
-- as the game's graphics page shows it, while the variable counts from 0.
function Model.Shown(knob, n)
    if knob.reversed then return knob.max + knob.min - n end
    if knob.format == "level" then return n + 1 end
    return n
end

function Model.FromShown(knob, shown)
    if knob.reversed then return knob.max + knob.min - shown end
    if knob.format == "level" then return shown - 1 end
    return shown
end

-- The two ends of a slider, in the numbers the player reads.
function Model.ShownRange(knob)
    local a, b = Model.Shown(knob, knob.min), Model.Shown(knob, knob.max)
    return math.min(a, b), math.max(a, b)
end

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
    if knob.format == "level" then return string.format("%d", math.floor(shown + 0.5)) end
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

-- A knob's name as it is shown, with the mark an experimental one carries.
function Model.Label(knob)
    if knob.experimental then return knob.label .. " |cffff8040experimental|r" end
    return knob.label
end

Model.WARNING = {
    title = "Before you tune",
    body = "Some of these settings can crash the game.\n\n"
        .. "Anything marked |cffff8040experimental|r can crash your game, or leave it unable to draw the world. "
        .. "They depend on your graphics card and its driver, and the client itself calls some of them beta features.\n\n"
        .. "Save a set that works before you try one: Revert returns to it. "
        .. "If the game will not start afterwards, delete WTF\\Config.wtf in the game folder and it starts with default settings.",
    skip = "Do not show this again",
    go = "I understand",
}

function Model.Line(knob, live, saved)
    local text = string.format("  %s |cff888888%s|r: %s", Model.Label(knob), knob.cvar, Model.Format(knob, live))
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

-- The same, short enough for a title bar: "67% Quality, 2 unsaved".
function Model.Brief(scaleText, preset, changed)
    local text = scaleText
    if preset then text = text .. " " .. preset.label end
    if changed > 0 then text = text .. string.format(", %d unsaved", changed) end
    return text
end

--------------------------------------------------------------------------------
-- What the client will not take, and what is asked about first
--------------------------------------------------------------------------------

-- `unsupported(cvar, value)` is the client's own answer: a reason, or nil when the value
-- is fine. A choice or a toggle is locked when every value but the live one is refused;
-- the reason for the first of them is returned. A slider is never locked here: its
-- values are too many to ask about.
function Model.Locked(knob, live, unsupported)
    local values
    if knob.kind == "toggle" then
        values = { 0, 1 }
    elseif knob.kind == "choice" then
        values = {}
        for _, choice in ipairs(knob.choices) do values[#values + 1] = choice[1] end
    else
        return nil
    end
    local first
    for _, value in ipairs(values) do
        if not Model.Same(value, live) then
            local why = unsupported(knob.cvar, value)
            if not why then return nil end
            first = first or why
        end
    end
    return first
end

-- Turning an experimental knob on is confirmed first. Turning one off never is.
function Model.AsksFirst(knob, value)
    return knob.experimental == true and value ~= nil and not Model.Same(value, 0)
end

--------------------------------------------------------------------------------
-- Which knobs are in view
--------------------------------------------------------------------------------

-- Whether every word of `text` is somewhere in the knob's name, variable, help or group.
function Model.Matches(knob, text, groupLabel)
    local hay = (knob.label .. " " .. knob.cvar .. " " .. (knob.help or "") .. " " .. (groupLabel or "")):lower()
    for word in tostring(text or ""):lower():gmatch("%S+") do
        if not hay:find(word, 1, true) then return false end
    end
    return true
end

-- The knobs a view shows, in catalogue order. A view is one of
--     { search = "text" }      every knob matching the text, whatever its group
--     { changed = true }       every knob that differs from the saved set
--     { group = "key" }        the knobs of one group
-- and is tried in that order, so typing in the search box overrides the group picked.
function Model.View(knobs, view, live, saved, groups)
    local labels = {}
    for _, group in ipairs(groups or {}) do labels[group.key] = group.label end
    local search = Util.Trim(view.search or "")
    local out = {}
    for _, knob in ipairs(knobs) do
        local keep
        if search ~= "" then
            keep = Model.Matches(knob, search, labels[knob.group])
        elseif view.changed then
            keep = live[knob.cvar] ~= nil and saved[knob.cvar] ~= nil and not Model.Same(live[knob.cvar], saved[knob.cvar])
        else
            keep = knob.group == view.group
        end
        if keep then out[#out + 1] = knob end
    end
    return out
end

-- What a knob's tooltip says of its range: "33% to 200%", or the choices by name.
function Model.RangeText(knob)
    if knob.kind == "slider" then
        return Model.Format(knob, knob.reversed and knob.max or knob.min) .. " to "
            .. Model.Format(knob, knob.reversed and knob.min or knob.max)
    elseif knob.kind == "choice" then
        local names = {}
        for _, choice in ipairs(knob.choices) do names[#names + 1] = choice[2] end
        return table.concat(names, ", ")
    end
    return "on or off"
end

-- The overall quality preset a level belongs to, or nil for one in between.
function Model.LevelOf(level, levels)
    for _, preset in ipairs(levels) do
        if Model.Same(preset.level, level) then return preset end
    end
    return nil
end
