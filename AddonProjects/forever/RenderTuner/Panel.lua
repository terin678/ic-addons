local addonName, ns = ...

--[[
The panel: every knob in the catalogue as a control, changed live while the world is in
view behind it.

    +----------------------------------------------------------------+
    | RenderTuner                       67% Quality, 2 unsaved     x |   drag the bar
    | [Native] [Quality] [Balanced] [Performance] [Ultra Perf.]      |   upscaling presets
    | [Save] [Revert] [More...]                  [Restart graphics]  |
    | Upscaling         | Render scale      <---o------->  67%       |
    | Anti-aliasing (1) | Resample filter   [ FSR 1.0      v ]       |
    | ...               | Sharpening        <------o---->  1.8       |
    +----------------------------------------------------------------+

The groups are down the left; the rows on the right are the knobs of the one picked. A
row whose value differs from the saved set is in the accent colour, and so is its group,
with a count. Clicking a row's name offers the way back: its saved value, or the client's
default.

This file decides nothing about a value. It shows what Apply.Live() reads and hands what
the player did to ns.SetKnob and the other actions in Core.lua, which call Refresh() back.
Rows are made the first time their group is shown and kept. Nothing runs while idle.
]]

local W = LibStub("LibICWidgets-1.0")

local Catalog = ns.Catalog
local Model = ns.Model

local Panel = {}
ns.Panel = Panel

local WIDTH = 640
local PAD = 8
local BAR_H = 24
local BUTTON_H = 22
local GROUP_W = 160
local GROUP_H = 22
local ROW_H = 24
local LABEL_W = 230
local ROWS_X = PAD + GROUP_W + PAD
local CONTROL_W = WIDTH - ROWS_X - LABEL_W - PAD
-- Bar, presets, actions, and the gaps between them.
local TOP = BAR_H + PAD + BUTTON_H + PAD + BUTTON_H + PAD + 4

local frame
local notice                -- the warning shown before the panel
local warned = false        -- whether it has been seen this session
local rows = {}             -- cvar -> row
local groupButtons = {}     -- group key -> button
local presetButtons = {}    -- preset key -> button

local function Place()
    return ns.cdb and ns.cdb.panel
end

local function CurrentGroup()
    local place = Place()
    local key = place and place.group
    for _, group in ipairs(Catalog.GROUPS) do
        if group.key == key then return key end
    end
    return Catalog.GROUPS[1].key
end

--------------------------------------------------------------------------------
-- A row
--------------------------------------------------------------------------------

local function RowTip(tip, row)
    local knob = row.knob
    local live, saved = ns.Apply.Live()[knob.cvar], ns.db.saved[knob.cvar]
    tip:AddLine(knob.label)
    tip:AddLine(knob.help, 1, 1, 1, true)
    if knob.experimental then
        tip:AddLine("Experimental: this one can crash the game. Save a set that works first.", 1, 0.5, 0.25, true)
    end
    tip:AddLine(" ")
    tip:AddDoubleLine("Console variable", knob.cvar, 0.7, 0.7, 0.7, 1, 1, 1)
    tip:AddDoubleLine("Now", Model.Format(knob, live), 0.7, 0.7, 0.7, 1, 1, 1)
    if not Model.Same(live, saved) then
        tip:AddDoubleLine("Saved", Model.Format(knob, saved), 0.7, 0.7, 0.7, 1, 0.82, 0)
    end
    local need = Model.RestartHint(knob.restart)
    if need then tip:AddLine(need, 1, 0.5, 0.2, true) end
    tip:AddLine("Click for the saved value or the default", 0.7, 0.7, 0.7)
end

local function RowMenu(row)
    local knob = row.knob
    local saved = ns.db.saved[knob.cvar]
    local default = ns.Apply.Defaults()[knob.cvar]
    local items = { { title = knob.label } }
    if saved ~= nil then
        items[#items + 1] = { text = "Back to saved: " .. Model.Format(knob, saved),
            onClick = function() ns.SetKnob(knob, saved) end }
    end
    if default ~= nil then
        items[#items + 1] = { text = "Client default: " .. Model.Format(knob, default),
            onClick = function() ns.SetKnob(knob, default) end }
    end
    W.Menu(row.name, items)
end

local function BuildRow(knob)
    local row = CreateFrame("Frame", nil, frame)
    row:SetSize(LABEL_W + CONTROL_W, ROW_H)
    row.knob = knob

    row.name = W.Button(row, Model.Label(knob), LABEL_W - 6, ROW_H - 4, {
        kind = "flat", justify = "LEFT", font = "body", textRole = "text",
        onClick = function() RowMenu(row) end,
    })
    row.name:SetPoint("LEFT", row, "LEFT", 0, 0)
    W.Tooltip(row.name, function(tip) RowTip(tip, row) end)

    if knob.kind == "slider" then
        -- The slider works in the numbers the player reads; a reversed knob is turned
        -- round on the way in and out.
        row.control = W.Slider(row, {
            width = CONTROL_W, valueWidth = 64, min = knob.min, max = knob.max, step = knob.step, value = knob.min,
            live = knob.settle ~= true,
            format = function(shown) return Model.Format(knob, Model.FromShown(knob, shown)) end,
            onChange = function(shown) ns.SetKnob(knob, Model.FromShown(knob, shown)) end,
        })
        row.control:SetPoint("LEFT", row, "LEFT", LABEL_W, 0)
    elseif knob.kind == "toggle" then
        row.control = W.CheckBox(row, {
            size = 16,
            onClick = function(checked) ns.SetKnob(knob, checked and 1 or 0) end,
        })
        row.control:SetPoint("LEFT", row, "LEFT", LABEL_W + 2, 0)
    else
        row.control = W.Choice(row, CONTROL_W - 62, ROW_H - 4, {
            choices = knob.choices,
            onChange = function(value) ns.SetKnob(knob, value) end,
        })
        row.control:SetPoint("LEFT", row, "LEFT", LABEL_W, 0)
    end
    return row
end

-- Shows the row what is live, without the control reporting it back as a change.
local function UpdateRow(row, live, saved)
    local knob = row.knob
    local value = live[knob.cvar]
    if knob.kind == "slider" then
        row.control:SetValue(Model.Shown(knob, value or knob.min))
    elseif knob.kind == "toggle" then
        row.control:SetChecked(value == 1)
    else
        row.control:SetValue(value)
    end
    row.name:SetTextRole(Model.Same(value, saved[knob.cvar]) and "text" or "accent")
end

--------------------------------------------------------------------------------
-- The frame
--------------------------------------------------------------------------------

local function MoreMenu(owner)
    W.Menu(owner, {
        { title = "RenderTuner" },
        { text = "Client defaults...", onClick = function()
            W.Confirm("Set every setting here to the client's defaults for this machine?\n\n"
                .. "Revert brings the saved set back.", ns.Defaults)
        end },
        { text = "Back to before RenderTuner...", onClick = function()
            W.Confirm("Go back to the settings from before RenderTuner first ran?\n\n"
                .. "Revert brings the saved set back.", ns.Restore)
        end },
        { divider = true },
        { text = "Restart the graphics engine", onClick = ns.Restart },
    })
end

local function Build()
    local p = W.Panel(UIParent, {
        name = "RenderTunerPanel", width = WIDTH, height = TOP + 200, movable = true, strata = "HIGH",
        onMoved = function(self)
            local fx, fy = W.GetPlace(self)
            if fx and Place() then
                Place().x, Place().y = fx, fy
            end
        end,
    })
    -- Escape closes it, as it does the game's own windows.
    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = "RenderTunerPanel" end

    local bar = W.Panel(p, { role = "raised", edge = false, height = BAR_H })
    bar:SetPoint("TOPLEFT", p, "TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", p, "TOPRIGHT", -1, -1)
    W.DragHandle(bar, p)

    local title = W.Label(bar, "RenderTuner", { font = "title", color = "accent" })
    title:SetPoint("LEFT", bar, "LEFT", PAD, 0)

    local close = W.Button(bar, "x", 20, 18, { kind = "flat", onClick = function() p:Hide() end })
    close:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
    W.Tooltip(close, function(tip) tip:AddLine("Close") end)

    p.status = W.Label(bar, "", { font = "small", color = "textDim", justify = "RIGHT" })
    p.status:SetPoint("RIGHT", close, "LEFT", -6, 0)

    -- Presets, sharing the width
    local gap = 4
    local presetW = (WIDTH - PAD * 2 - gap * (#Catalog.PRESETS - 1)) / #Catalog.PRESETS
    for index, preset in ipairs(Catalog.PRESETS) do
        local b = W.Button(p, preset.label, presetW, BUTTON_H, {
            onClick = function() ns.ApplyPreset(preset) end,
        })
        b:SetPoint("TOPLEFT", p, "TOPLEFT", PAD + (index - 1) * (presetW + gap), -(BAR_H + PAD))
        W.Tooltip(b, function(tip)
            local limits = ns.Apply.Limits()
            local scale = math.max(limits.min, math.min(limits.max, preset.scale))
            tip:AddLine(preset.label)
            tip:AddLine(string.format("Render scale %d%%", math.floor(scale * 100 + 0.5)), 1, 1, 1)
            if preset.scale < 1 then tip:AddLine("Upscaled with FSR 1.0", 1, 1, 1) end
        end)
        presetButtons[preset.key] = b
    end

    -- Actions
    local actionsY = -(BAR_H + PAD + BUTTON_H + PAD)
    p.save = W.Button(p, "Save", 70, BUTTON_H, { onClick = function() ns.Save() end })
    p.save:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, actionsY)
    W.Tooltip(p.save, function(tip)
        tip:AddLine("Save")
        tip:AddLine("Keeps the settings as they are now. Revert returns to them.", 1, 1, 1, true)
    end)

    p.revert = W.Button(p, "Revert", 70, BUTTON_H, { onClick = function() ns.Revert() end })
    p.revert:SetPoint("LEFT", p.save, "RIGHT", gap, 0)
    W.Tooltip(p.revert, function(tip)
        tip:AddLine("Revert")
        tip:AddLine("Puts every setting back to the saved set.", 1, 1, 1, true)
    end)

    local more = W.Button(p, "More...", 70, BUTTON_H, { onClick = function(self) MoreMenu(self) end })
    more:SetPoint("LEFT", p.revert, "RIGHT", gap, 0)

    p.restart = W.Button(p, "Restart graphics", 130, BUTTON_H, { kind = "danger", onClick = function() ns.Restart() end })
    p.restart:SetPoint("TOPRIGHT", p, "TOPRIGHT", -PAD, actionsY)
    W.Tooltip(p.restart, function(tip)
        tip:AddLine("Restart graphics")
        tip:AddLine("A change you made shows only after the graphics engine restarts. The screen blinks.",
            1, 1, 1, true)
    end)
    p.restart:Hide()

    -- Groups, down the left
    for index, group in ipairs(Catalog.GROUPS) do
        local b = W.Button(p, group.label, GROUP_W, GROUP_H, {
            kind = "flat", justify = "LEFT", font = "body",
            onClick = function() Panel.ShowGroup(group.key) end,
        })
        b:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -(TOP + (index - 1) * GROUP_H))
        groupButtons[group.key] = b
    end

    return p
end

--------------------------------------------------------------------------------
-- Showing what is live
--------------------------------------------------------------------------------

function Panel.Refresh()
    if not frame or not frame:IsShown() then return end
    local knobs, live, saved = ns.Apply.Knobs(), ns.Apply.Live(), ns.db.saved
    local current = CurrentGroup()

    -- The rows of the group in view, made on first sight. A row that is already showing
    -- is left showing: hiding it, even for an instant, would drop a slider out of the
    -- player's hand in the middle of a drag, and this runs on every step of one.
    local shown, changedIn = 0, {}
    for _, knob in ipairs(knobs) do
        if not Model.Same(live[knob.cvar], saved[knob.cvar]) then
            changedIn[knob.group] = (changedIn[knob.group] or 0) + 1
        end
        local row = rows[knob.cvar]
        if knob.group == current then
            if not row then
                -- A knob's place in its group never changes, so it is set once.
                row = BuildRow(knob)
                row:SetPoint("TOPLEFT", frame, "TOPLEFT", ROWS_X, -(TOP + shown * ROW_H))
                rows[knob.cvar] = row
            end
            UpdateRow(row, live, saved)
            row:SetShown(true)
            shown = shown + 1
        elseif row then
            row:SetShown(false)
        end
    end

    local changed = 0
    for _, group in ipairs(Catalog.GROUPS) do
        local n = changedIn[group.key] or 0
        changed = changed + n
        local b = groupButtons[group.key]
        b:SetLabel(n > 0 and string.format("%s (%d)", group.label, n) or group.label)
        b:SetKind(group.key == current and "normal" or "flat")
        b:SetTextRole(n > 0 and "accent" or false)
    end

    local preset = Model.PresetOf(live.RenderScale, Catalog.PRESETS, ns.Apply.Limits())
    for _, each in ipairs(Catalog.PRESETS) do
        presetButtons[each.key]:SetKind(each == preset and "accent" or "normal")
    end

    local scale = Model.Find(knobs, "RenderScale")
    frame.status:SetText(Model.Brief(scale and Model.Format(scale, live.RenderScale) or "?", preset, changed))
    frame.save:SetKind(changed > 0 and "accent" or "normal")
    frame.restart:SetShown(ns.pendingRestart == "gx" or ns.pendingRestart == "window")

    local body = math.max(#Catalog.GROUPS * GROUP_H, shown * ROW_H)
    frame:SetHeight(TOP + body + PAD)
end

function Panel.ShowGroup(key)
    if Place() then Place().group = key end
    Panel.Refresh()
end

function Panel.IsShown()
    return frame ~= nil and frame:IsShown() == true
end

local function Open()
    if not frame then
        frame = Build()
        local place = Place()
        W.SetPlace(frame, place and place.x or 0.5, place and place.y or 0.18)
    end
    frame:Show()
    Panel.Refresh()
end

--------------------------------------------------------------------------------
-- The warning
--------------------------------------------------------------------------------

local NOTICE_W, NOTICE_H = 440, 232

local function BuildNotice()
    local words = Model.WARNING
    local n = W.Panel(UIParent, { name = "RenderTunerNotice", width = NOTICE_W, height = NOTICE_H, strata = "DIALOG" })
    n:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    n:EnableMouse(true)

    local title = W.Label(n, words.title, { font = "title", color = "accent" })
    title:SetPoint("TOPLEFT", n, "TOPLEFT", 14, -12)

    local body = W.Label(n, words.body, { wrap = true })
    body:SetPoint("TOPLEFT", n, "TOPLEFT", 14, -36)
    body:SetWidth(NOTICE_W - 28)
    body:SetJustifyV("TOP")

    n.skip = W.CheckBox(n, { size = 16 })
    n.skip:SetPoint("BOTTOMLEFT", n, "BOTTOMLEFT", 14, 14)
    local skipText = W.Label(n, words.skip, { color = "textDim" })
    skipText:SetPoint("LEFT", n.skip, "RIGHT", 8, 0)

    n.go = W.Button(n, words.go, 120, 24, {
        kind = "accent",
        onClick = function()
            warned = true
            if n.skip:GetChecked() then ns.db.settings.skipWarning = true end
            n:Hide()
            Open()
        end,
    })
    n.go:SetPoint("BOTTOMRIGHT", n, "BOTTOMRIGHT", -14, 12)
    return n
end

-- The warning comes before the panel the first time it is opened in a session, until
-- the player ticks the box that says not to.
local function NeedsWarning()
    return warned ~= true and ns.db.settings.skipWarning ~= true
end

function Panel.Notice()
    return notice
end

function Panel.Toggle()
    if frame and frame:IsShown() then
        frame:Hide()
        return false
    end
    if notice and notice:IsShown() then
        notice:Hide()
        return false
    end
    if NeedsWarning() then
        notice = notice or BuildNotice()
        notice:Show()
        return false
    end
    Open()
    return true
end

-- For the cases: forget that the warning was seen.
function Panel.ResetWarning()
    warned = false
    if notice then notice:Hide() end
end

-- For the cases: how many rows have been made, and how many are showing.
function Panel.Counts()
    local made, showing = 0, 0
    for _, row in pairs(rows) do
        made = made + 1
        if row:IsShown() then showing = showing + 1 end
    end
    return made, showing
end

function Panel.Row(cvar)
    return rows[cvar]
end
