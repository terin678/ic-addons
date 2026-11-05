local addonName, ns = ...

--[[
The panel: every knob in the catalogue as a control, changed live while the world is in
view behind it.

    +------------------------------------------------------------------------+
    | RenderTuner  142 fps        Quality 67%, 2 unsaved   Peek  Compact   x |  drag the bar
    | Upscaling  [Potato] [Performance] [Balanced] [Quality] [Native]        |  render scale, low to high
    | Quality    [Low] [Fair] [Good] [High] [Ultra] [Extreme]                |  the game's 1 to 10 level
    | [Save] [Revert] [More...]  [Search settings      ]  [Restart graphics] |
    | Changed (2)        | Upscaling   Render scale, the filter...  [Revert] |
    | PICTURE            | Render scale      <---o------->  67%      undo    |
    |   Upscaling (1)    | Resample filter   [ FSR 1.0      v ]              |
    |   Anti-aliasing    | Sharpening        <------o---->  1.8              |
    | DETAIL             |                                                   |
    |   ...              | what the setting under the pointer does           |
    | Advanced +         +---------------------------------------------------+
    +------------------------------------------------------------------------+

Down the left are "Changed" and the groups, in three clusters, the last folded away; the
rows on the right are the knobs of the one picked, or of whatever the search box finds, in a
view that scrolls. A row whose value differs from the saved set is in the accent colour and
gains an undo; its group shows a count. Clicking a row's name offers its saved value and the
client's default; clicking a slider's number types one. The line under the rows says what
the setting under the pointer does.

The panel covers the world it tunes, so it can get out of the way: hold Peek (a key binding
too) and it all but vanishes, Compact folds it to the bar and the two strips, and while a
slider is held it goes half clear.

This file decides nothing about a value. It shows what Apply.Live() reads and hands what
the player did to the actions in Core.lua, which call Refresh() back. Rows are made the
first time they are needed and kept. The only thing that runs on a timer is the frame
rate in the title bar, twice a second, and only while the panel is open.
]]

local Util = LibStub("LibICUtil-1.0")
local W = LibStub("LibICWidgets-1.0")
local Theme = LibStub("LibICTheme-1.0")

local Catalog = ns.Catalog
local Model = ns.Model

local Panel = {}
ns.Panel = Panel

local WIDTH = 720
local PAD = 8
local BAR_H = 24
local BUTTON_H = 22
local STRIP_GAP = 4
local STRIP_LABEL_W = 70
local GROUP_W = 170
local GROUP_H = 21
local CLUSTER_H = 18
local HEAD_H = 26
local HELP_H = 30
local ROW_H = 24
local LABEL_W = 200
local CONTROL_W = 240
local UNDO_W = 44
-- Bar, the two preset strips, the actions, and the gaps between them.
local TOP = BAR_H + PAD + BUTTON_H + STRIP_GAP + BUTTON_H + PAD + BUTTON_H + PAD
local ROWS_X = PAD + GROUP_W + PAD
local ROWS_W = WIDTH - ROWS_X - PAD
local CHANGED = "changed"
local PEEK_ALPHA = 0.08     -- while Peek is held
local HOLD_ALPHA = 0.4      -- while a slider is held
local HINT = "Click a setting's name for its saved value or the default. Click a number to type one."

local frame
local notice                -- the warning shown before the panel
local warned = false        -- whether it has been seen this session
local rows = {}             -- cvar -> row
local groupButtons = {}     -- group key, or CHANGED -> button
local clusterHeads = {}     -- cluster key -> its heading, a label or, when folded, a button
local presetButtons = {}    -- upscaling preset key -> button
local levelButtons = {}     -- quality preset key -> button
local search = ""           -- what is typed in the search box
local stickyChanged         -- the knobs the Changed view opened with, kept while it is in view
local lastView              -- the view the scroll position belongs to
local defaults              -- the client's defaults, read when the panel opens
local ticker                -- the frame rate's timer, alive only while the panel is shown
local peeking = false       -- Peek is held
local holding = false       -- a slider is held
local laidOut               -- which layout Panel.Layout last made

local function Place()
    return ns.cdb and ns.cdb.panel
end

local function ClusterOf(key)
    for _, group in ipairs(Catalog.GROUPS) do
        if group.key == key then return group.cluster end
    end
end

local function Folded(clusterKey)
    for _, cluster in ipairs(Catalog.CLUSTERS) do
        if cluster.key == clusterKey then return cluster.folded == true end
    end
    return false
end

local function CurrentGroup()
    local place = Place()
    local key = place and place.group
    if key == CHANGED then return key end
    for _, group in ipairs(Catalog.GROUPS) do
        if group.key == key then return key end
    end
    return Catalog.GROUPS[1].key
end

-- Whether the folded cluster is open: the player opened it, or the group in view is in it.
local function Unfolded()
    local place = Place()
    return (place and place.advanced == true) or Folded(ClusterOf(CurrentGroup()))
end

local function Compact()
    local place = Place()
    return place ~= nil and place.compact == true
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
    if row.locked then
        tip:AddLine("This client will not change it at the moment: " .. row.locked, 1, 0.3, 0.3, true)
    end
    tip:AddLine(" ")
    tip:AddDoubleLine("Console variable", knob.cvar, 0.7, 0.7, 0.7, 1, 1, 1)
    tip:AddDoubleLine("Now", Model.Format(knob, live), 0.7, 0.7, 0.7, 1, 1, 1)
    if not Model.Same(live, saved) then
        tip:AddDoubleLine("Saved", Model.Format(knob, saved), 0.7, 0.7, 0.7, 1, 0.82, 0)
    end
    if defaults and defaults[knob.cvar] ~= nil then
        tip:AddDoubleLine("Client default", Model.Format(knob, defaults[knob.cvar]), 0.7, 0.7, 0.7, 1, 1, 1)
    end
    tip:AddDoubleLine("Range", Model.RangeText(knob), 0.7, 0.7, 0.7, 1, 1, 1)
    local need = Model.RestartHint(knob.restart)
    if need then tip:AddLine(need, 1, 0.5, 0.2, true) end
    tip:AddLine("Click for the saved value or the default", 0.7, 0.7, 0.7)
end

-- A change from a control. Turning an experimental knob on is asked about first; the
-- control goes back to what is live until the answer is yes.
local function Change(knob, value)
    if Model.AsksFirst(knob, value) then
        W.Confirm(string.format("%s is experimental and can crash the game.\n\nSet it to %s?",
            knob.label, Model.Format(knob, value)), function() ns.SetKnob(knob, value) end)
        Panel.Refresh()
        return
    end
    ns.SetKnob(knob, value)
end

local function RowMenu(row)
    local knob = row.knob
    local saved = ns.db.saved[knob.cvar]
    local default = defaults and defaults[knob.cvar]
    local items = { { title = knob.label } }
    if saved ~= nil then
        items[#items + 1] = { text = "Back to saved: " .. Model.Format(knob, saved),
            onClick = function() Change(knob, saved) end }
    end
    if default ~= nil then
        items[#items + 1] = { text = "Client default: " .. Model.Format(knob, default),
            onClick = function() Change(knob, default) end }
    end
    W.Menu(row.name, items)
end

-- Panel.Peek and the held slider both change one thing: how clear the panel is.
local function ShowAlpha()
    if frame then frame:SetAlpha(peeking and PEEK_ALPHA or (holding and HOLD_ALPHA or 1)) end
end

-- The line under the rows: what the setting under the pointer does, or how to use the rows.
local function ShowHelp(row)
    if not frame then return end
    local knob = row and row.knob
    if not knob then
        frame.help:SetText(HINT)
        return
    end
    local text = knob.help or ""
    if knob.experimental then text = text .. " |cffff8040Experimental: can crash the game.|r" end
    frame.help:SetText(text)
end

-- Under the pointer, a row gets a band and says what it does. Hooked on the name and on the
-- control's own frames, since a row cannot hear the pointer through its children.
local function Hover(row, target)
    if not target or type(target.HookScript) ~= "function" then return end
    target:HookScript("OnEnter", function()
        local c = Theme.Current().colors.hover
        row.band:SetColorTexture(c.r, c.g, c.b, 0.55)
        row.band:Show()
        ShowHelp(row)
    end)
    target:HookScript("OnLeave", function()
        row.band:Hide()
        ShowHelp(nil)
    end)
end

local function BuildRow(knob)
    local row = CreateFrame("Frame", nil, frame.scroll.content)
    row:SetSize(LABEL_W + CONTROL_W + 4 + UNDO_W, ROW_H)
    row.knob = knob
    row.locked = false
    row.icIndex = 0

    row.band = row:CreateTexture(nil, "BACKGROUND")
    row.band:SetAllPoints(row)
    row.band:Hide()

    row.name = W.Button(row, Model.Label(knob), LABEL_W - 6, ROW_H - 4, {
        kind = "flat", justify = "LEFT", font = "body", textRole = "text",
        onClick = function() RowMenu(row) end,
    })
    row.name:SetPoint("LEFT", row, "LEFT", 0, 0)
    W.Tooltip(row.name, function(tip) RowTip(tip, row) end)
    Hover(row, row.name)

    if knob.kind == "slider" then
        -- The slider works in the numbers the player reads; a reversed knob or a
        -- quality level is turned into the variable's own on the way out.
        local low, high = Model.ShownRange(knob)
        row.control = W.Slider(row, {
            width = CONTROL_W, valueWidth = 64, min = low, max = high, step = knob.step, value = low,
            live = knob.settle ~= true,
            format = function(shown) return Model.Format(knob, Model.FromShown(knob, shown)) end,
            onChange = function(shown) Change(knob, Model.FromShown(knob, shown)) end,
            onType = function(text)
                local value = Model.ParseTyped(knob, text)
                if value ~= nil then Change(knob, value) end
            end,
            onHold = function(held)
                holding = held == true
                ShowAlpha()
            end,
        })
        row.control:SetPoint("LEFT", row, "LEFT", LABEL_W, 0)
        Hover(row, row.control.inner)
    elseif knob.kind == "toggle" then
        row.control = W.CheckBox(row, {
            size = 16,
            onClick = function(checked) Change(knob, checked and 1 or 0) end,
        })
        row.control:SetPoint("LEFT", row, "LEFT", LABEL_W + 2, 0)
        Hover(row, row.control)
    else
        row.control = W.Choice(row, CONTROL_W - 64, ROW_H - 4, {
            choices = knob.choices,
            disabled = function(value) return ns.Apply.Unsupported(knob.cvar, value) end,
            onChange = function(value) Change(knob, value) end,
        })
        row.control:SetPoint("LEFT", row, "LEFT", LABEL_W, 0)
        Hover(row, row.control)
    end

    -- The way back for this one setting, shown only while it differs from saved.
    row.undo = W.Button(row, "undo", UNDO_W, ROW_H - 6, {
        kind = "flat", font = "small",
        onClick = function() Change(knob, ns.db.saved[knob.cvar]) end,
    })
    row.undo:SetPoint("LEFT", row, "LEFT", LABEL_W + CONTROL_W + 4, 0)
    W.Tooltip(row.undo, function(tip)
        tip:AddLine("Back to saved")
        tip:AddLine(Model.Format(knob, ns.db.saved[knob.cvar]), 1, 1, 1)
    end)
    return row
end

-- Shows the row what is live, without the control reporting it back as a change.
local function UpdateRow(row, live, saved)
    local knob = row.knob
    local value = live[knob.cvar]
    if knob.kind == "slider" then
        row.control:SetValue(Model.Shown(knob, value or knob.min))
        -- A value outside the slider's range sits on its end; the text still tells the truth.
        if value and (value < knob.min or value > knob.max) then
            row.control.text:SetText(Model.Format(knob, value))
        end
    elseif knob.kind == "toggle" then
        row.control:SetChecked(value == 1)
    else
        row.control:SetValue(value)
    end

    -- A knob the client will take no other value for is greyed out, with the client's
    -- reason in its tooltip.
    local changed = not Model.Same(value, saved[knob.cvar])
    row.locked = Model.Locked(knob, value, ns.Apply.Unsupported) or false
    if knob.kind ~= "slider" then
        row.control:SetEnabled(row.locked == false)
        row.control:SetAlpha(row.locked == false and 1 or 0.4)
    end
    if row.locked then
        row.name:SetTextRole("textDisabled")
    else
        row.name:SetTextRole(changed and "accent" or "text")
    end
    row.undo:SetShown(changed and row.locked == false)
end

--------------------------------------------------------------------------------
-- The frame
--------------------------------------------------------------------------------

local function ClearSearch()
    search = ""
    if frame then frame.search:SetText("") end
end

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

-- A row of buttons sharing the width after a label that says what they are presets of.
-- The names in the upscaling strip are DLSS's, and without the label "Quality" and
-- "Performance" read as overall graphics settings, which they are not. Every strip runs
-- from least to most, left to right.
local function Strip(p, y, label, presets, into, onClick, tooltip)
    local text = W.Label(p, label, { color = "textDim" })
    text:SetPoint("LEFT", p, "TOPLEFT", PAD, y - BUTTON_H / 2)
    local x = PAD + STRIP_LABEL_W
    local gap = 4
    local width = (WIDTH - x - PAD - gap * (#presets - 1)) / #presets
    for index, preset in ipairs(presets) do
        local b = W.Button(p, preset.label, width, BUTTON_H, { onClick = function() onClick(preset) end })
        b:SetPoint("TOPLEFT", p, "TOPLEFT", x + (index - 1) * (width + gap), y)
        W.Tooltip(b, function(tip) tooltip(tip, preset) end)
        into[preset.key] = b
    end
end

local EXTREME_WARNING = "Extreme is Ultra and then every setting beyond the quality levels turned all the way "
    .. "up: how far everything is drawn, shadows and light, water and particles, 8x multisampling, a "
    .. "32-bit float render format, HDR output and ray traced shadows, where this machine has them.\n\n"
    .. "It is heavy, and some of it can crash the game or leave it unable to draw the world. "
    .. "Save a set that works first. Choosing a lower level puts it all back as it was.\n\nTurn it on?"

local function Build()
    local p = W.Panel(UIParent, {
        name = "RenderTunerPanel", width = WIDTH, height = TOP + PAD, movable = true, strata = "HIGH",
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

    p.fps = W.Label(bar, "", { color = "text" })
    p.fps:SetPoint("LEFT", title, "RIGHT", 12, 0)

    local close = W.Button(bar, "x", 20, 18, { kind = "flat", onClick = function() p:Hide() end })
    close:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
    W.Tooltip(close, function(tip) tip:AddLine("Close") end)

    p.compact = W.Button(bar, "Compact", 62, 18, { kind = "flat", onClick = function() Panel.SetCompact(not Compact()) end })
    p.compact:SetPoint("RIGHT", close, "LEFT", -4, 0)
    W.Tooltip(p.compact, function(tip)
        tip:AddLine(Compact() and "Expand" or "Compact")
        tip:AddLine("Folds the panel to this bar and the two rows of presets, to see more of the world.",
            1, 1, 1, true)
    end)

    -- Held, not clicked: the panel is nearly clear for as long as the button is down.
    p.peek = W.Button(bar, "Peek", 42, 18, { kind = "flat" })
    p.peek:SetPoint("RIGHT", p.compact, "LEFT", -4, 0)
    p.peek:HookScript("OnMouseDown", function() Panel.Peek(true) end)
    p.peek:HookScript("OnMouseUp", function() Panel.Peek(false) end)
    p.peek:HookScript("OnLeave", function() Panel.Peek(false) end)
    W.Tooltip(p.peek, function(tip)
        tip:AddLine("Peek")
        tip:AddLine("Hold to see the world behind the panel. It also has a key binding, under AddOns.",
            1, 1, 1, true)
    end)

    p.status = W.Label(bar, "", { font = "small", color = "textDim", justify = "RIGHT" })
    p.status:SetPoint("RIGHT", p.peek, "LEFT", -8, 0)

    -- The two preset strips
    local stripY = -(BAR_H + PAD)
    Strip(p, stripY, "Upscaling", Catalog.PRESETS, presetButtons, function(preset)
        -- Bring the settings a preset changes into view, so the change is seen.
        ClearSearch()
        Panel.ShowGroup("upscale")
        ns.ApplyPreset(preset)
        Panel.Refresh()
    end, function(tip, preset)
        local limits = ns.Apply.Limits()
        local scale = math.max(limits.min, math.min(limits.max, preset.scale))
        tip:AddLine(preset.label .. " upscaling")
        tip:AddLine(string.format("Sets the render scale to %d%%.", math.floor(scale * 100 + 0.5)), 1, 1, 1)
        if preset.scale < 1 then tip:AddLine("Sets the resample filter to FSR 1.0.", 1, 1, 1) end
        tip:AddLine("Changes nothing else: the quality levels stay as they are.", 0.7, 0.7, 0.7, true)
    end)
    Strip(p, stripY - BUTTON_H - STRIP_GAP, "Quality", Catalog.LEVELS, levelButtons, function(preset)
        local function Go()
            ClearSearch()
            Panel.ShowGroup(preset.experimental and "hdr" or "quality")
            ns.ApplyLevel(preset)
            Panel.Refresh()
        end
        -- Extreme turns on things that can crash the game: it is asked about, once it is off.
        local live = ns.Apply.Live()
        if preset.experimental and Model.LevelOf(live.graphicsQuality, Catalog.LEVELS, live, ns.Refused) ~= preset then
            W.Confirm(EXTREME_WARNING, Go)
        else
            Go()
        end
    end, function(tip, preset)
        tip:AddLine(preset.label .. " quality")
        tip:AddLine(string.format("Sets the game's overall quality to level %d of 10, and the levels beneath it.",
            preset.level + 1), 1, 1, 1, true)
        if preset.experimental then
            tip:AddLine("Also turns every setting beyond the levels all the way up: draw distances, shadow "
                .. "cascades and light range, water and particles, 8x multisampling, a 32-bit float render "
                .. "format, HDR output, ray traced shadows. Experimental: it can crash the game.", 1, 0.5, 0.25, true)
        else
            tip:AddLine("Leaves upscaling alone. Puts the extras of Extreme back as they were, if it set them.",
                0.7, 0.7, 0.7, true)
        end
    end)

    -- Actions
    local gap = 4
    local actionsY = stripY - (BUTTON_H + STRIP_GAP) - BUTTON_H - PAD
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

    p.search = W.EditBox(p, 190, BUTTON_H, {
        maxBytes = 40, placeholder = "Search settings",
        onChange = function(text)
            search = Util.Trim(text)
            Panel.Refresh()
        end,
        onEnter = function(_, box) box:ClearFocus() end,
        onEscape = function(box)
            box:SetText("")
            search = ""
            Panel.Refresh()
        end,
    })
    p.search:SetPoint("LEFT", more, "RIGHT", 12, 0)

    p.restart = W.Button(p, "Restart graphics", 130, BUTTON_H, { kind = "danger", onClick = function() ns.Restart() end })
    p.restart:SetPoint("TOPRIGHT", p, "TOPRIGHT", -PAD, actionsY)
    W.Tooltip(p.restart, function(tip)
        tip:AddLine("Restart graphics")
        tip:AddLine("A change you made shows only after the graphics engine restarts. The screen blinks.",
            1, 1, 1, true)
    end)
    p.restart:Hide()

    -- Everything below the actions, in one frame, so Compact can fold it away in one go.
    local body = CreateFrame("Frame", nil, p)
    body:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -TOP)
    body:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
    p.body = body

    -- "Changed", then the groups under their clusters, down the left. Where each goes is
    -- decided by Panel.Layout, since the folded cluster moves everything under it.
    local function GroupButton(key, label)
        local b = W.Button(body, label, GROUP_W - 12, GROUP_H, {
            kind = "flat", justify = "LEFT", font = "body",
            onClick = function() Panel.ShowGroup(key) end,
        })
        groupButtons[key] = b
    end
    groupButtons[CHANGED] = W.Button(body, "Changed", GROUP_W, GROUP_H, {
        kind = "flat", justify = "LEFT", font = "body",
        onClick = function() Panel.ShowGroup(CHANGED) end,
    })
    for _, cluster in ipairs(Catalog.CLUSTERS) do
        if cluster.folded then
            clusterHeads[cluster.key] = W.Button(body, cluster.label, GROUP_W, CLUSTER_H, {
                kind = "flat", justify = "LEFT", font = "small", textRole = "textDim",
                onClick = function() Panel.SetAdvanced(not Unfolded()) end,
            })
            W.Tooltip(clusterHeads[cluster.key], function(tip)
                tip:AddLine(cluster.label)
                tip:AddLine("The fine controls. Most players never need them.", 1, 1, 1, true)
            end)
        else
            clusterHeads[cluster.key] = W.Label(body, cluster.label, { font = "small", color = "textDim" })
        end
    end
    for _, group in ipairs(Catalog.GROUPS) do GroupButton(group.key, group.label) end

    -- The heading over the rows: what is in view, and the way back for all of it
    p.head = W.Label(body, "", { font = "title", color = "accent" })
    p.head:SetPoint("LEFT", p, "TOPLEFT", ROWS_X, -(TOP + HEAD_H / 2 - 2))
    p.note = W.Label(body, "", { font = "small", color = "textDim" })
    p.note:SetPoint("LEFT", p.head, "RIGHT", 10, 0)
    p.revertView = W.Button(body, "Revert these", 96, BUTTON_H - 2, {
        onClick = function()
            if p.icList then ns.RevertKnobs(p.icList, p.head:GetText() or "these") end
        end,
    })
    p.revertView:SetPoint("RIGHT", p, "TOPRIGHT", -PAD, -(TOP + HEAD_H / 2 - 2))
    W.Tooltip(p.revertView, function(tip)
        tip:AddLine("Revert these")
        tip:AddLine("Puts the settings in view back to their saved values.", 1, 1, 1, true)
    end)
    p.icList = false

    p.scroll = W.Scroll(body, ROWS_W, 200, { step = ROW_H * 2 })
    p.scroll:SetPoint("TOPLEFT", p, "TOPLEFT", ROWS_X, -(TOP + HEAD_H))

    p.empty = W.Label(body, "", { color = "textDim" })
    p.empty:SetPoint("TOPLEFT", p, "TOPLEFT", ROWS_X + 6, -(TOP + HEAD_H + 8))

    p.help = W.Label(body, HINT, { font = "small", color = "textDim", wrap = true })
    p.help:SetWidth(ROWS_W - 4)
    p.help:SetJustifyV("TOP")

    -- The frame rate stops being measured when there is nobody looking at it, and the
    -- panel comes back clear the next time it is opened.
    p:HookScript("OnHide", function()
        peeking, holding = false, false
        p:SetAlpha(1)
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
    end)
    return p
end

-- Where the groups, their clusters, the rows and the help line go, and how tall the panel
-- is: the folded cluster opening or closing, and Compact, change all of it.
function Panel.Layout()
    if not frame then return end
    local place = Place()
    -- The group in view is never hidden inside a folded cluster.
    if place and Folded(ClusterOf(CurrentGroup())) then place.advanced = true end
    local open, compact = Unfolded(), Compact()

    -- Every step of a held slider comes through here, and nothing it does moves this.
    local signature = (open and "open" or "folded") .. (compact and "compact" or "full")
    if signature == laidOut then return end
    laidOut = signature

    local y = 0
    groupButtons[CHANGED]:ClearAllPoints()
    groupButtons[CHANGED]:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(TOP + y))
    y = y + GROUP_H
    for _, cluster in ipairs(Catalog.CLUSTERS) do
        local head = clusterHeads[cluster.key]
        head:ClearAllPoints()
        if cluster.folded then
            head:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(TOP + y))
        else
            head:SetPoint("LEFT", frame, "TOPLEFT", PAD + 4, -(TOP + y + CLUSTER_H / 2))
        end
        y = y + CLUSTER_H
        for _, group in ipairs(Catalog.GROUPS) do
            if group.cluster == cluster.key then
                local b = groupButtons[group.key]
                b:ClearAllPoints()
                if not cluster.folded or open then
                    b:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 12, -(TOP + y))
                    b:Show()
                    y = y + GROUP_H
                else
                    b:Hide()
                end
            end
        end
    end

    frame.help:ClearAllPoints()
    frame.help:SetPoint("TOPLEFT", frame, "TOPLEFT", ROWS_X + 2, -(TOP + y - HELP_H + 4))
    frame.scroll:SetViewHeight(y - HEAD_H - HELP_H)

    frame.body:SetShown(not compact)
    frame.search:SetShown(not compact)
    frame.compact:SetLabel(compact and "Expand" or "Compact")
    frame:SetHeight(compact and TOP or (TOP + y + PAD))
end

--------------------------------------------------------------------------------
-- Showing what is live
--------------------------------------------------------------------------------

local function ShowFramerate()
    if frame then frame.fps:SetText(string.format("%d fps", math.floor(ns.Apply.Framerate() + 0.5))) end
end

function Panel.Refresh()
    if not frame or not frame:IsShown() then return end
    local knobs, live, saved = ns.Apply.Knobs(), ns.Apply.Live(), ns.db.saved
    local current = CurrentGroup()

    -- What is in view: a search beats the group picked.
    local list, title, note, viewKey
    if search ~= "" then
        list = Model.View(knobs, { search = search }, live, saved, Catalog.GROUPS)
        title, viewKey = string.format('Search: "%s"', search), "s:" .. search
        note = string.format("%d %s", #list, Util.Plural(#list, "setting"))
    elseif current == CHANGED then
        -- Kept as it was when the view opened: a setting put back to its saved value
        -- stays in the list, rather than vanishing from under the pointer.
        stickyChanged = stickyChanged or Model.View(knobs, { changed = true }, live, saved, Catalog.GROUPS)
        list, title, viewKey = stickyChanged, "Changed since the last save", CHANGED
        note = string.format("%d %s", #list, Util.Plural(#list, "setting"))
    else
        list, viewKey = Model.View(knobs, { group = current }, live, saved, Catalog.GROUPS), current
        for _, group in ipairs(Catalog.GROUPS) do
            if group.key == current then title, note = group.label, group.note end
        end
    end

    -- The rows of the view, made on first sight. A row that is already showing is left
    -- showing and in place: hiding it, even for an instant, would drop a slider out of
    -- the player's hand in the middle of a drag, and this runs on every step of one.
    local inView, viewChanged = {}, 0
    for index, knob in ipairs(list) do
        local row = rows[knob.cvar]
        if not row then
            row = BuildRow(knob)
            rows[knob.cvar] = row
        end
        if row.icIndex ~= index then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", frame.scroll.content, "TOPLEFT", 0, -(index - 1) * ROW_H)
            row.icIndex = index
        end
        UpdateRow(row, live, saved)
        row:SetShown(true)
        inView[knob.cvar] = true
        if not Model.Same(live[knob.cvar], saved[knob.cvar]) then viewChanged = viewChanged + 1 end
    end
    for cvar, row in pairs(rows) do
        if not inView[cvar] then
            row:SetShown(false)
            row.icIndex = 0
        end
    end
    frame.scroll:SetContentHeight(#list * ROW_H)
    if viewKey ~= lastView then
        frame.scroll:ScrollTo(0)
        lastView = viewKey
    end

    frame.icList = list
    frame.head:SetText(title or "")
    frame.note:SetText(note or "")
    frame.revertView:SetShown(viewChanged > 0)
    frame.empty:SetText(#list > 0 and "" or (search ~= "" and "No setting matches." or "Nothing differs from the saved set."))

    -- The groups, each with how many of its knobs differ from saved
    local changedIn, changed = {}, 0
    for _, knob in ipairs(knobs) do
        if not Model.Same(live[knob.cvar], saved[knob.cvar]) then
            changedIn[knob.group] = (changedIn[knob.group] or 0) + 1
            changed = changed + 1
        end
    end
    local function Mark(key, label, n)
        local b = groupButtons[key]
        b:SetLabel(n > 0 and string.format("%s (%d)", label, n) or label)
        b:SetKind((search == "" and key == current) and "normal" or "flat")
        b:SetTextRole(n > 0 and "accent" or false)
    end
    Mark(CHANGED, "Changed", changed)
    local inCluster = {}
    for _, group in ipairs(Catalog.GROUPS) do
        local n = changedIn[group.key] or 0
        Mark(group.key, group.label, n)
        inCluster[group.cluster] = (inCluster[group.cluster] or 0) + n
    end
    -- The folded cluster says what it hides, and still says so when something in it differs.
    local open = Unfolded()
    for _, cluster in ipairs(Catalog.CLUSTERS) do
        if cluster.folded then
            local n = inCluster[cluster.key] or 0
            local head = clusterHeads[cluster.key]
            head:SetLabel(string.format("%s %s%s", cluster.label, open and "-" or "+",
                n > 0 and string.format("  (%d changed)", n) or ""))
            head:SetTextRole(n > 0 and "accent" or "textDim")
        end
    end

    local limits = ns.Apply.Limits()
    local preset = Model.PresetOf(live.RenderScale, Catalog.PRESETS, limits)
    for _, each in ipairs(Catalog.PRESETS) do
        presetButtons[each.key]:SetKind(each == preset and "accent" or "normal")
        presetButtons[each.key]:SetLabel(Model.PresetLabel(each, limits))
    end
    local level = Model.LevelOf(live.graphicsQuality, Catalog.LEVELS, live, ns.Refused)
    for _, each in ipairs(Catalog.LEVELS) do
        local b = levelButtons[each.key]
        b:SetKind(each == level and "accent" or "normal")
        -- The one that can crash the game is orange until it is the chosen one.
        b:SetLabel((each.experimental and each ~= level) and ("|cffff8040" .. each.label .. "|r") or each.label)
    end

    local scale = Model.Find(knobs, "RenderScale")
    frame.status:SetText(Model.Brief(scale and Model.Format(scale, live.RenderScale) or "?", preset, changed))
    frame.save:SetKind(changed > 0 and "accent" or "normal")
    frame.restart:SetShown(ns.pendingRestart == "gx" or ns.pendingRestart == "window")
    Panel.Layout()
end

-- A group's key, or "changed" for everything that differs from saved.
function Panel.ShowGroup(key)
    ClearSearch()
    stickyChanged = nil
    if Place() then
        Place().group = key
        if Folded(ClusterOf(key)) then Place().advanced = true end
    end
    Panel.Refresh()
end

-- Opens or folds the cluster of fine controls. Folding it while one of its groups is in
-- view moves to the first group, rather than leaving the view with no button.
function Panel.SetAdvanced(on)
    local place = Place()
    if not place then return end
    place.advanced = on == true
    if not on and Folded(ClusterOf(CurrentGroup())) then
        place.group = Catalog.GROUPS[1].key
        stickyChanged = nil
    end
    Panel.Refresh()
end

-- Folds the panel to the bar and the presets, or back. Remembered.
function Panel.SetCompact(on)
    local place = Place()
    if place then place.compact = on == true end
    if frame then
        Panel.Layout()
        if on then frame.search:ClearFocus() end
    end
end

-- Holds the panel nearly clear, for a look at the world behind it, until let go.
function Panel.Peek(down)
    peeking = down == true and frame ~= nil and frame:IsShown() == true
    ShowAlpha()
end

-- What the search box would do, for the cases and for a command.
function Panel.Search(text)
    search = Util.Trim(text or "")
    if frame then frame.search:SetText(search) end
    Panel.Refresh()
end

function Panel.DropFocus()
    if frame then frame.search:ClearFocus() end
end

function Panel.IsShown()
    return frame ~= nil and frame:IsShown() == true
end

local function Open()
    if not frame then
        frame = Build()
        -- Tucked toward the left edge until the player moves it: the world they are
        -- tuning is mostly in the middle.
        local place = Place()
        W.SetPlace(frame, place and place.x or 0.02, place and place.y or 0.16)
    end
    -- What the client supports, and its defaults, are asked afresh each time the panel opens.
    ns.Apply.ForgetSupport()
    defaults = ns.Apply.Defaults()
    stickyChanged = nil
    frame:Show()
    Panel.Refresh()
    ShowFramerate()
    if not ticker then ticker = C_Timer.NewTicker(0.5, ShowFramerate) end
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

--------------------------------------------------------------------------------
-- For the cases
--------------------------------------------------------------------------------

-- Forget that the warning was seen.
function Panel.ResetWarning()
    warned = false
    if notice then notice:Hide() end
end

-- How many rows have been made, and how many are showing.
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

function Panel.Preset(key)
    return presetButtons[key]
end

function Panel.Level(key)
    return levelButtons[key]
end

function Panel.Group(key)
    return groupButtons[key]
end

function Panel.Cluster(key)
    return clusterHeads[key]
end

function Panel.IsCompact()
    return Compact()
end

function Panel.Frame()
    return frame
end
