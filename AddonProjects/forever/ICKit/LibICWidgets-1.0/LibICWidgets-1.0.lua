--[[
LibICWidgets-1.0
Layer 2 of ICKit: themed frames. Only what an addon has needed so far, and each one is
drawn from colour textures, so no widget depends on a Blizzard frame template. The slider
is the exception: its bar is the client's own.

    local W = LibStub("LibICWidgets-1.0")

    W.Panel(parent, opts)               a filled, edged frame; movable when asked
    W.DragHandle(handle, panel)         drag the panel by one of its children
    W.Label(parent, text, opts)         a font string in a theme colour
    W.Button(parent, text, w, h, opts)  normal | accent | danger | flat
    W.CheckBox(parent, opts)            a tick box
    W.EditBox(parent, w, h, opts)       one line of text
    W.Slider(parent, opts)              a number between two ends, its value beside it
    W.Choice(parent, w, h, opts)        one of a short list, picked from a menu
    W.Scroll(parent, w, h, opts)        a window onto content taller than itself
    W.Tabs(parent, tabs, opts)          a row of tabs, each optionally showing its own page
    W.List(parent, w, h, opts)          column headers above pooled, single-line rows
    W.Resize(frame, opts)               a grip in the corner that resizes the frame
    W.TextArea(parent, w, h, opts)      many lines to paste into, or a copy box
    W.RaidIcon(parent, index, size)     a raid target icon from a plain number, 1 to 8
    W.Tooltip(frame, builder)           builder(GameTooltip, frame) adds the lines
    W.Menu(owner, items)                a context menu from a list
    W.Confirm(text, onAccept)           a yes/no dialog

    W.GetPlace(frame) / W.SetPlace(frame, fx, fy)     where a frame sits, as fractions of
                                                      the screen from its top-left
    W.ToFraction, W.ClampFraction                     the pure half of that
    W.Repaint()                                       redraw everything in the current theme

Every widget repaints itself when the theme changes (LibICTheme-1.0). Nothing here runs an
OnUpdate: a widget does work when it is hovered, clicked, typed in or dragged, and at no
other time.

What the client offers was checked first (Docs/client-reference.md): SetColorTexture is
there, a plain frame has no SetBackdrop, MenuUtil and StaticPopup are the modern ones.

A field that is read before it is set is given a value at construction, always. The
headless stub answers an unset field with a function, and "if not frame.x" would misread it.
]]

local MAJOR, MINOR = "LibICWidgets-1.0", 5
local W = LibStub:NewLibrary(MAJOR, MINOR)
if not W then return end

local Theme = LibStub("LibICTheme-1.0")
local Env = LibStub("LibICEnv-1.0")

--------------------------------------------------------------------------------
-- Painting, and repainting on a theme change
--------------------------------------------------------------------------------

-- widget -> its repaint function. Weak, so the registry never keeps a widget alive.
local live = setmetatable({}, { __mode = "k" })

local function Track(widget, repaint)
    live[widget] = repaint
    repaint(widget, (Theme.Current()))
end

function W.Repaint()
    local theme = Theme.Current()
    for widget, repaint in pairs(live) do
        repaint(widget, theme)
    end
end

Theme.OnChange(function() W.Repaint() end)

-- A fill and four one-pixel edges, made once per frame.
local function Skin(frame)
    local fill = frame:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(frame)
    local edges = {}
    for i = 1, 4 do edges[i] = frame:CreateTexture(nil, "BORDER") end
    edges[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    edges[1]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    edges[1]:SetHeight(1)
    edges[2]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    edges[2]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    edges[2]:SetHeight(1)
    edges[3]:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    edges[3]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    edges[3]:SetWidth(1)
    edges[4]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    edges[4]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    edges[4]:SetWidth(1)
    frame.icFill, frame.icEdges = fill, edges
end

-- fill is a colour, or nil for no fill; edge likewise.
local function Paint(frame, fill, edge)
    if fill then
        frame.icFill:SetColorTexture(fill.r, fill.g, fill.b, fill.a or 1)
        frame.icFill:Show()
    else
        frame.icFill:Hide()
    end
    for _, tex in ipairs(frame.icEdges) do
        if edge then
            tex:SetColorTexture(edge.r, edge.g, edge.b, edge.a or 1)
            tex:Show()
        else
            tex:Hide()
        end
    end
end

--------------------------------------------------------------------------------
-- Pure: where a frame sits
--------------------------------------------------------------------------------

-- A top-left corner, `left` pixels in and `top` pixels down from the parent's own
-- top-left, as fractions of the parent. Fractions survive a change of resolution or
-- interface scale; pixels do not.
function W.ToFraction(left, top, parentW, parentH)
    if not parentW or parentW <= 0 or not parentH or parentH <= 0 then return 0, 0 end
    return (left or 0) / parentW, (top or 0) / parentH
end

-- Holds the whole frame on screen: wFrac and hFrac are its own size as fractions.
function W.ClampFraction(fx, fy, wFrac, hFrac)
    local maxX = math.max(0, 1 - (wFrac or 0))
    local maxY = math.max(0, 1 - (hFrac or 0))
    fx, fy = tonumber(fx) or 0, tonumber(fy) or 0
    if fx < 0 then fx = 0 elseif fx > maxX then fx = maxX end
    if fy < 0 then fy = 0 elseif fy > maxY then fy = maxY end
    return fx, fy
end

-- The frame's top-left as fractions of the screen, or nil before it has a position.
function W.GetPlace(frame)
    local left, top = frame:GetLeft(), frame:GetTop()
    local pw, ph = UIParent:GetWidth(), UIParent:GetHeight()
    if not left or not top then return nil end
    return W.ToFraction(left, ph - top, pw, ph)
end

function W.SetPlace(frame, fx, fy)
    local pw, ph = UIParent:GetWidth(), UIParent:GetHeight()
    if not pw or pw <= 0 or not ph or ph <= 0 then return end
    fx, fy = W.ClampFraction(fx, fy, (frame:GetWidth() or 0) / pw, (frame:GetHeight() or 0) / ph)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", fx * pw, -fy * ph)
end

--------------------------------------------------------------------------------
-- Panel
--------------------------------------------------------------------------------

--[[
A move starts on the press and ends on the release. The client's own drag event
(RegisterForDrag, OnDragStart) is not used: it fires only once the pointer has travelled
the drag threshold, so the frame sits still and then jumps the distance it missed.
]]
local function StartDrag(panel)
    if panel.icLocked == true or panel.icMoving == true then return end
    panel.icMoving = true
    -- A tooltip belonging to the thing being dragged would trail the pointer.
    if GameTooltip then GameTooltip:Hide() end
    panel:StartMoving()
end

local function StopDrag(panel)
    if panel.icMoving ~= true then return end
    panel.icMoving = false
    panel:StopMovingOrSizing()
    -- The client would otherwise remember the position itself, in its layout cache,
    -- and fight the one the addon saves.
    panel:SetUserPlaced(false)
    -- The client may re-anchor a moved frame to whichever screen point is nearest. Pin it
    -- back by its top-left, where W.SetPlace puts it, so it grows right and down when it
    -- is resized and SetPlace and GetPlace stay in step.
    local fx, fy = W.GetPlace(panel)
    if fx then W.SetPlace(panel, fx, fy) end
    if panel.icOnMoved then panel.icOnMoved(panel) end
end

--[[
opts = {
    width, height, strata, name,
    role = "ground" | "raised" | "field",   -- the theme colour it is filled with
    edge = false,                           -- no border
    movable = true, onMoved = fn(panel),    -- drag with the left button; told when dropped
}
panel:SetLocked(true) pins a movable panel where it is.
]]
function W.Panel(parent, opts)
    opts = opts or {}
    local p = CreateFrame("Frame", opts.name, parent or UIParent)
    p:SetSize(opts.width or 200, opts.height or 100)
    if opts.strata then p:SetFrameStrata(opts.strata) end
    Skin(p)
    p.icRole = opts.role or "ground"
    p.icEdge = opts.edge ~= false
    p.icLocked = false
    p.icMoving = false
    p.icOnMoved = opts.onMoved or false

    function p:SetLocked(on)
        self.icLocked = on and true or false
    end

    if opts.movable then
        p:SetMovable(true)
        p:EnableMouse(true)
        p:SetClampedToScreen(true)
        p:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" then StartDrag(self) end
        end)
        p:SetScript("OnMouseUp", function(self, button)
            if button == "LeftButton" then StopDrag(self) end
        end)
        -- Hidden in the middle of a move: let go, or it follows the pointer when shown.
        p:SetScript("OnHide", StopDrag)
    end

    Track(p, function(self, theme)
        Paint(self, theme.colors[self.icRole], self.icEdge and theme.colors.edge or nil)
    end)
    return p
end

-- A child that drags its panel: a title bar, usually. It owns the handle's mouse
-- scripts, so a right-click is asked for here: opts.onRightClick(handle).
function W.DragHandle(handle, panel, opts)
    opts = opts or {}
    handle.icOnRightClick = opts.onRightClick or false
    handle:EnableMouse(true)
    handle:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then StartDrag(panel) end
    end)
    handle:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            StopDrag(panel)
        elseif button == "RightButton" and self.icOnRightClick then
            self.icOnRightClick(self)
        end
    end)
end

--------------------------------------------------------------------------------
-- Label
--------------------------------------------------------------------------------

--[[
opts = { font = "body" | "title" | "small" | "button", color = a colour role,
         justify = "LEFT" | "CENTER" | "RIGHT", wrap = true }
label:SetRole(color) changes its colour role, for a line that has been ticked off.
The font is the theme's at the time the label is made.
]]
function W.Label(parent, text, opts)
    opts = opts or {}
    local theme = Theme.Current()
    local fs = parent:CreateFontString(nil, "OVERLAY", theme.fonts[opts.font or "body"])
    fs:SetJustifyH(opts.justify or "LEFT")
    fs:SetWordWrap(opts.wrap == true)
    fs:SetText(text or "")
    fs.icColor = opts.color or "text"

    local function Repaint(self, current)
        local c = current.colors[self.icColor] or current.colors.text
        self:SetTextColor(c.r, c.g, c.b, c.a or 1)
    end

    function fs:SetRole(color)
        self.icColor = color or "text"
        Repaint(self, (Theme.Current()))
    end

    Track(fs, Repaint)
    return fs
end

--------------------------------------------------------------------------------
-- Button
--------------------------------------------------------------------------------

-- fill, text, edge for a kind and whether the pointer is over it.
local function ButtonColors(theme, kind, hover)
    local c = theme.colors
    if kind == "accent" then
        return hover and c.accentHover or c.accent, c.accentText, c.edge
    elseif kind == "danger" then
        return hover and c.dangerHover or c.danger, c.dangerText, c.edge
    elseif kind == "flat" then
        return hover and c.hover or nil, hover and c.text or c.textDim, nil
    end
    return hover and c.buttonHover or c.button, c.buttonText, c.edge
end

local function RepaintButton(b, theme)
    local fill, text, edge = ButtonColors(theme, b.icKind, b.icHover == true)
    -- A text role of its own outranks the kind's: a list row that is a button keeps the
    -- colour of the thing it shows, hovered or not.
    if b.icTextRole then text = theme.colors[b.icTextRole] or text end
    Paint(b, fill, edge)
    b.label:SetTextColor(text.r, text.g, text.b, text.a or 1)
end

--[[
opts = {
    kind = "normal" | "accent" | "danger" | "flat",
    onClick = fn(button, mouseButton),
    justify = "LEFT",           -- the text hugs the left edge and is cut, not wrapped
    font = a font role,         -- "button" by default
    textRole = a colour role,   -- the text's own colour, whatever the kind says
    onDragStart = fn(button),   -- picked up: the pointer moved while it was held
    onDragStop = fn(button),    -- put down
}
"flat" has no fill or edge until hovered: for a small control inside a title bar, or a
row of a list. b:SetLabel(text), b:SetKind(kind) and b:SetTextRole(role) change it afterwards.
]]
function W.Button(parent, text, w, h, opts)
    opts = opts or {}
    local theme = Theme.Current()
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w or 80, h or 20)
    Skin(b)
    b.icKind = opts.kind or "normal"
    b.icHover = false
    b.icTextRole = opts.textRole or false
    b.label = b:CreateFontString(nil, "OVERLAY", theme.fonts[opts.font or "button"])
    if opts.justify == "LEFT" then
        b.label:SetPoint("LEFT", b, "LEFT", 4, 0)
        b.label:SetPoint("RIGHT", b, "RIGHT", -4, 0)
        b.label:SetJustifyH("LEFT")
        b.label:SetWordWrap(false)
    else
        b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
    end
    b.label:SetText(text or "")

    function b:SetLabel(newText)
        self.label:SetText(newText or "")
    end

    function b:SetKind(kind)
        self.icKind = kind or "normal"
        RepaintButton(self, (Theme.Current()))
    end

    function b:SetTextRole(role)
        self.icTextRole = role or false
        RepaintButton(self, (Theme.Current()))
    end

    b:SetScript("OnEnter", function(self)
        self.icHover = true
        RepaintButton(self, (Theme.Current()))
    end)
    b:SetScript("OnLeave", function(self)
        self.icHover = false
        RepaintButton(self, (Theme.Current()))
    end)
    if opts.onClick then b:SetScript("OnClick", opts.onClick) end

    -- A button that can also be dragged, for a row that is picked up and put down. This
    -- is the client's drag event on purpose: it waits for the pointer to move, which is
    -- what keeps a press a click.
    if opts.onDragStart or opts.onDragStop then
        b.icOnDragStart = opts.onDragStart or false
        b.icOnDragStop = opts.onDragStop or false
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnDragStart", function(self)
            if GameTooltip then GameTooltip:Hide() end
            if self.icOnDragStart then self.icOnDragStart(self) end
        end)
        b:SetScript("OnDragStop", function(self)
            if self.icOnDragStop then self.icOnDragStop(self) end
        end)
    end

    Track(b, RepaintButton)
    return b
end

--------------------------------------------------------------------------------
-- CheckBox
--------------------------------------------------------------------------------

--[[
opts = { size = 14, checked = false, onClick = fn(checked, box) }
box:SetChecked(on) and box:GetChecked(). onClick runs for a click, not for SetChecked.
]]
function W.CheckBox(parent, opts)
    opts = opts or {}
    local size = opts.size or 14
    local box = CreateFrame("Button", nil, parent)
    box:SetSize(size, size)
    Skin(box)
    box.icChecked = false
    box.icOnClick = opts.onClick or false
    box.tick = box:CreateTexture(nil, "ARTWORK")
    box.tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    box.tick:SetPoint("CENTER", box, "CENTER", 0, 0)
    box.tick:SetSize(size + 8, size + 8)

    function box:SetChecked(on)
        self.icChecked = on and true or false
        if self.icChecked then self.tick:Show() else self.tick:Hide() end
    end

    function box:GetChecked()
        return self.icChecked
    end

    box:SetScript("OnClick", function(self)
        self:SetChecked(not self.icChecked)
        if self.icOnClick then self.icOnClick(self.icChecked, self) end
    end)
    box:SetChecked(opts.checked == true)

    Track(box, function(self, theme)
        Paint(self, theme.colors.field, theme.colors.edge)
        local c = theme.colors.check
        self.tick:SetVertexColor(c.r, c.g, c.b)
    end)
    return box
end

--------------------------------------------------------------------------------
-- EditBox
--------------------------------------------------------------------------------

--[[
opts = {
    maxBytes,                       -- the most the box will take
    placeholder = "text",           -- shown dim while the box is empty and unfocused
    onEnter = fn(text, box),        -- Enter; the box keeps focus unless you clear it
    onEscape = fn(box),             -- Escape, after focus is dropped
    onFocusLost = fn(box),
    onTab = fn(box, backwards),     -- Tab, or Shift-Tab with backwards = true
    onChange = fn(text, box),       -- each change the player types, not one made by SetText
}
Escape always drops focus. A box with focus takes every key, movement included, so an
addon drops focus (box:ClearFocus()) when combat starts.
]]
function W.EditBox(parent, w, h, opts)
    opts = opts or {}
    local theme = Theme.Current()
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(w or 120, h or 18)
    Skin(e)
    e:SetAutoFocus(false)
    e:SetFontObject(_G[theme.fonts.body] or theme.fonts.body)
    e:SetTextInsets(4, 4, 0, 0)
    if opts.maxBytes then e:SetMaxBytes(opts.maxBytes + 1) end
    e.icOnEnter = opts.onEnter or false
    e.icOnEscape = opts.onEscape or false
    e.icOnFocusLost = opts.onFocusLost or false
    e.icOnTab = opts.onTab or false
    e.icOnChange = opts.onChange or false
    e.icFocused = false

    e.placeholder = e:CreateFontString(nil, "OVERLAY", theme.fonts.body)
    e.placeholder:SetPoint("LEFT", e, "LEFT", 5, 0)
    e.placeholder:SetText(opts.placeholder or "")

    local function SyncPlaceholder(self)
        if self.icFocused ~= true and (self:GetText() or "") == "" then
            self.placeholder:Show()
        else
            self.placeholder:Hide()
        end
    end

    e:SetScript("OnEnterPressed", function(self)
        if self.icOnEnter then self.icOnEnter(self:GetText() or "", self) end
    end)
    e:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        if self.icOnEscape then self.icOnEscape(self) end
    end)
    e:SetScript("OnEditFocusGained", function(self)
        self.icFocused = true
        SyncPlaceholder(self)
    end)
    e:SetScript("OnEditFocusLost", function(self)
        self.icFocused = false
        SyncPlaceholder(self)
        if self.icOnFocusLost then self.icOnFocusLost(self) end
    end)
    e:SetScript("OnTextChanged", function(self, userInput)
        SyncPlaceholder(self)
        if userInput and self.icOnChange then self.icOnChange(self:GetText() or "", self) end
    end)
    -- Tab, and Shift-Tab as backwards = true, for moving between the boxes of a list.
    e:SetScript("OnTabPressed", function(self)
        if self.icOnTab then
            self.icOnTab(self, (IsShiftKeyDown and IsShiftKeyDown()) and true or false)
        end
    end)
    SyncPlaceholder(e)

    Track(e, function(self, current)
        Paint(self, current.colors.field, current.colors.edge)
        local c, dim = current.colors.text, current.colors.textDim
        self:SetTextColor(c.r, c.g, c.b, 1)
        self.placeholder:SetTextColor(dim.r, dim.g, dim.b, 1)
    end)
    return e
end

--------------------------------------------------------------------------------
-- Slider
--------------------------------------------------------------------------------

-- Pure. The value a slider reports for a raw position: a whole number of steps, except
-- at the two ends, which are min and max themselves even when those are off the step.
-- A render scale that runs from 0.3334 to 2 in steps of 0.01 reads 0.3334, 0.35, 0.36.
function W.SliderValue(raw, min, max, step)
    raw = tonumber(raw) or min
    local snapped = math.floor(raw / step + 0.5) * step
    local first = math.ceil(min / step - 0.0001) * step
    local last = math.floor(max / step + 0.0001) * step
    if snapped <= first + step * 0.0001 then return min end
    if snapped >= last - step * 0.0001 then return max end
    return snapped
end

-- The range the client's slider is given: the whole steps inside min and max.
local function StepRange(min, max, step)
    local first = math.ceil(min / step - 0.0001) * step
    local last = math.floor(max / step + 0.0001) * step
    if last <= first then return min, max end
    return first, last
end

local function SliderText(s)
    if s.icFormat then return s.icFormat(s.icValue) end
    return tostring(s.icValue)
end

local function SliderSend(s)
    if s.icOnChange and s.icValue ~= s.icSent then
        s.icSent = s.icValue
        s.icOnChange(s.icValue, s)
    end
end

-- A plain slider drawn from colour textures, for a client without the template below.
local function PlainSlider(parent)
    local bar = CreateFrame("Slider", nil, parent)
    bar:SetOrientation("HORIZONTAL")
    bar:SetObeyStepOnDrag(true)
    bar:EnableMouse(true)
    bar.icTrack = bar:CreateTexture(nil, "BACKGROUND")
    bar.icTrack:SetPoint("LEFT", bar, "LEFT", 0, 0)
    bar.icTrack:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    bar.icTrack:SetHeight(4)
    bar.icThumb = bar:CreateTexture(nil, "ARTWORK")
    bar.icThumb:SetSize(8, 16)
    bar:SetThumbTexture(bar.icThumb)
    Track(bar, function(self, theme)
        local track, thumb = theme.colors.field, theme.colors.accent
        self.icTrack:SetColorTexture(track.r, track.g, track.b, 1)
        self.icThumb:SetColorTexture(thumb.r, thumb.g, thumb.b, 1)
    end)
    return bar
end

--[[
A slider with its value written beside it. The bar is the client's own slider with its
two steppers (MinimalSliderWithSteppersTemplate), the one widget here built on a Blizzard
template: the modern control, with the client's sounds and narration. Its art is not
themed; the value text is.

opts = {
    width = 220,                    -- the whole widget, value text included
    valueWidth = 56,                -- the share of that the value text takes
    min, max, step, value,
    format = fn(value) -> text,     -- what the value reads as
    live = true,                    -- false: onChange waits until the thumb is let go
    onChange = fn(value, slider),   -- for a drag or a stepper click, not for SetValue
    onType = fn(text, slider),      -- the value can be clicked and typed over; Enter sends the text
    onHold = fn(held),              -- the thumb was picked up (true) or let go (false)
    trough = true,                  -- false: no recessed rim behind the client's track
}
s:SetValue(v) moves it without calling onChange; s:GetValue(). Dragging is handled by the
client's slider, so nothing here runs an OnUpdate. s.hit is the clickable value, when
onType is given.
]]
function W.Slider(parent, opts)
    opts = opts or {}
    local s = CreateFrame("Frame", nil, parent)
    local valueWidth = opts.valueWidth or 56
    s:SetSize(opts.width or 220, 20)
    s.icMin, s.icMax = tonumber(opts.min) or 0, tonumber(opts.max) or 1
    s.icStep = tonumber(opts.step) or 0.1
    s.icValue = math.max(s.icMin, math.min(s.icMax, tonumber(opts.value) or s.icMin))
    s.icSent = s.icValue
    s.icFormat = opts.format or false
    s.icOnChange = opts.onChange or false
    s.icLive = opts.live ~= false
    s.icHeld = false
    s.icQuiet = false

    local first, last = StepRange(s.icMin, s.icMax, s.icStep)
    local steps = math.max(1, math.floor((last - first) / s.icStep + 0.5))

    local made, bar = pcall(CreateFrame, "Frame", nil, s, "MinimalSliderWithSteppersTemplate")
    local inner
    if made and type(bar) == "table" and type(bar.Slider) == "table" and type(bar.Init) == "function" then
        inner = bar.Slider
        bar:Init(math.max(first, math.min(last, s.icValue)), first, last, steps)
    else
        bar = PlainSlider(s)
        inner = bar
        inner:SetMinMaxValues(first, last)
        inner:SetValueStep(s.icStep)
        inner:SetValue(math.max(first, math.min(last, s.icValue)))
    end
    bar:SetPoint("LEFT", s, "LEFT", 0, 0)
    bar:SetPoint("RIGHT", s, "RIGHT", -valueWidth, 0)
    bar:SetHeight(20)
    s.bar, s.inner = bar, inner
    s.icFirst, s.icLast = first, last

    -- The client's track is dark art on a dark panel. A rim behind it, in the theme's field
    -- and edge colours, gives it a floor to sit in.
    if opts.trough ~= false then
        local trough = CreateFrame("Frame", nil, s)
        trough:SetFrameLevel(math.max(0, bar:GetFrameLevel() - 1))
        trough:SetHeight(14)
        trough:SetPoint("LEFT", inner, "LEFT", -2, 0)
        trough:SetPoint("RIGHT", inner, "RIGHT", 2, 0)
        Skin(trough)
        Track(trough, function(self, theme) Paint(self, theme.colors.field, theme.colors.edge) end)
        s.trough = trough
    end

    s.text = W.Label(s, "", { color = "text" })
    s.text:SetPoint("LEFT", bar, "RIGHT", 6, 0)
    s.text:SetPoint("RIGHT", s, "RIGHT", 0, 0)
    s.text:SetText(SliderText(s))
    s.icOnHold = opts.onHold or false

    -- The value, clicked, becomes a box to type into: the exact number, where a drag over
    -- hundreds of steps cannot be.
    if opts.onType then
        local hit = CreateFrame("Button", nil, s)
        hit:SetPoint("LEFT", bar, "RIGHT", 2, 0)
        hit:SetPoint("RIGHT", s, "RIGHT", 0, 0)
        hit:SetHeight(20)
        local box = W.EditBox(s, math.max(40, valueWidth - 2), 18, {
            maxBytes = 12,
            onEnter = function(text, b)
                b:ClearFocus()
                opts.onType(text, s)
            end,
            onFocusLost = function(b) b:Hide() end,
        })
        box:SetPoint("LEFT", bar, "RIGHT", 3, 0)
        box:SetFrameLevel(hit:GetFrameLevel() + 2)
        box:Hide()
        hit:SetScript("OnClick", function()
            -- The number alone: "203 nits" is edited as 203.
            box:SetText(SliderText(s):match("^%s*(-?[%d%.]+)") or "")
            box:Show()
            box:SetFocus()
            box:HighlightText()
        end)
        hit:SetScript("OnEnter", function() s.text:SetRole("accent") end)
        hit:SetScript("OnLeave", function() s.text:SetRole("text") end)
        s.hit, s.entry = hit, box
    end

    inner:HookScript("OnValueChanged", function(_, raw)
        if s.icQuiet == true then return end
        s.icValue = W.SliderValue(raw, s.icMin, s.icMax, s.icStep)
        s.text:SetText(SliderText(s))
        if s.icLive == true or s.icHeld ~= true then SliderSend(s) end
    end)
    inner:HookScript("OnMouseDown", function()
        s.icHeld = true
        if s.icOnHold then s.icOnHold(true) end
    end)
    inner:HookScript("OnMouseUp", function()
        s.icHeld = false
        SliderSend(s)
        if s.icOnHold then s.icOnHold(false) end
    end)

    function s:SetValue(value)
        self.icValue = math.max(self.icMin, math.min(self.icMax, tonumber(value) or self.icMin))
        self.icSent = self.icValue
        self.icQuiet = true
        self.inner:SetValue(math.max(self.icFirst, math.min(self.icLast, self.icValue)))
        self.icQuiet = false
        self.text:SetText(SliderText(self))
    end

    function s:GetValue()
        return self.icValue
    end

    return s
end

--------------------------------------------------------------------------------
-- Choice
--------------------------------------------------------------------------------

-- The client's own down arrow, from the friends list's category rows, tinted to the dim
-- text colour. A client without that atlas gets the letter v, which at least says "open".
local CHEVRON = "friendslist-categorybutton-arrow-down"

local function ChoiceMark(parent)
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(CHEVRON)
    local mark = info and parent:CreateTexture(nil, "OVERLAY")
    if mark and type(mark.SetAtlas) == "function" and (info.width or 0) > 0 and (info.height or 0) > 0 then
        mark:SetAtlas(CHEVRON)
        mark:SetSize(math.floor(9 * info.width / info.height + 0.5), 9)
        Track(mark, function(self, theme)
            local c = theme.colors.textDim
            self:SetVertexColor(c.r, c.g, c.b)
        end)
        return mark
    end
    return W.Label(parent, "v", { font = "small", color = "textDim" })
end

local function ChoiceLabel(c)
    for _, choice in ipairs(c.icChoices) do
        if choice[1] == c.icValue then return choice[2] end
    end
    return tostring(c.icValue)
end

--[[
One of a short list: a button that shows the current choice and opens a menu of them all.

opts = {
    choices = { { value, label }, ... },
    value,
    onChange = fn(value, choice),   -- for a pick from the menu, not for SetValue
    disabled = fn(value) -> reason, -- asked as the menu opens: a reason greys that choice out
}
c:SetValue(v) and c:GetValue().
]]
function W.Choice(parent, w, h, opts)
    opts = opts or {}
    local c
    c = W.Button(parent, "", w or 140, h or 20, {
        justify = "LEFT",
        onClick = function(self)
            local items = {}
            for _, choice in ipairs(self.icChoices) do
                items[#items + 1] = {
                    text = choice[2],
                    disabled = self.icDisabled and self.icDisabled(choice[1]) or nil,
                    radio = function() return self.icValue == choice[1] end,
                    onClick = function()
                        if self.icValue == choice[1] then return end
                        self:SetValue(choice[1])
                        if self.icOnChange then self.icOnChange(choice[1], self) end
                    end,
                }
            end
            W.Menu(self, items)
        end,
    })
    c.icChoices = opts.choices or {}
    c.icValue = opts.value
    c.icOnChange = opts.onChange or false
    c.icDisabled = opts.disabled or false

    -- Room on the right for the mark that says this opens a list.
    c.label:ClearAllPoints()
    c.label:SetPoint("LEFT", c, "LEFT", 4, 0)
    c.label:SetPoint("RIGHT", c, "RIGHT", -16, 0)
    c.mark = ChoiceMark(c)
    c.mark:SetPoint("RIGHT", c, "RIGHT", -5, 0)

    function c:SetValue(value)
        self.icValue = value
        self:SetLabel(ChoiceLabel(self))
    end

    function c:GetValue()
        return self.icValue
    end

    c:SetLabel(ChoiceLabel(c))
    return c
end

--------------------------------------------------------------------------------
-- Scroll
--------------------------------------------------------------------------------

-- Pure. How far down a view of height `viewH` may be scrolled over content of height
-- `contentH`, and `offset` held inside that.
function W.ScrollClamp(offset, contentH, viewH)
    local range = math.max(0, (contentH or 0) - (viewH or 0))
    offset = tonumber(offset) or 0
    if offset < 0 then offset = 0 elseif offset > range then offset = range end
    return offset, range
end

local SCROLL_BAR_W = 8

--[[
A window onto content taller than itself. Put children on s.content and say how tall
they are; the mouse wheel and a thin bar on the right scroll it. The bar is the client's
own slider turned on its side, so dragging it runs no OnUpdate, and it hides itself when
everything fits.

opts = { step = 24,                 -- how far one notch of the wheel moves
         onScroll = fn(offset, s) } -- told after every move, wheel, bar or ScrollTo
s.content                           -- parent your rows to this; it is `w` less the bar wide
s:SetContentHeight(h)               -- call when the rows change
s:SetViewHeight(h)                  -- the window itself became taller or shorter
s:SetViewWidth(w)                   -- or wider or narrower
s:ScrollTo(offset), s:GetOffset()
]]
function W.Scroll(parent, w, h, opts)
    opts = opts or {}
    local s = CreateFrame("ScrollFrame", nil, parent)
    s:SetSize(w, h)
    s.icStep = opts.step or 24
    s.icViewH = h
    s.icContentH = 0
    s.icOffset = 0
    s.icQuiet = false
    s.icOnScroll = opts.onScroll or false

    local content = CreateFrame("Frame", nil, s)
    content:SetSize(w - SCROLL_BAR_W - 4, 1)
    s:SetScrollChild(content)
    s.content = content

    -- Beside the view, not inside it: a scroll frame clips what it holds.
    local bar = CreateFrame("Slider", nil, parent)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(SCROLL_BAR_W)
    -- Above the view it sits beside, so a press on the bar reaches the bar.
    bar:SetFrameLevel((s:GetFrameLevel() or 0) + 5)
    bar:SetPoint("TOPRIGHT", s, "TOPRIGHT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", 0, 0)
    bar:SetMinMaxValues(0, 1)
    bar:SetValueStep(1)
    bar:SetValue(0)
    bar:EnableMouse(true)
    bar.icTrack = bar:CreateTexture(nil, "BACKGROUND")
    bar.icTrack:SetAllPoints(bar)
    bar.icThumb = bar:CreateTexture(nil, "ARTWORK")
    bar.icThumb:SetSize(SCROLL_BAR_W, 30)
    bar:SetThumbTexture(bar.icThumb)
    bar:Hide()
    s.bar = bar

    function s:GetOffset()
        return self.icOffset
    end

    function s:ScrollTo(offset)
        self.icOffset = W.ScrollClamp(offset, self.icContentH, self.icViewH)
        self:SetVerticalScroll(self.icOffset)
        self.icQuiet = true
        self.bar:SetValue(self.icOffset)
        self.icQuiet = false
        if self.icOnScroll then self.icOnScroll(self.icOffset, self) end
    end

    function s:SetContentHeight(height)
        self.icContentH = math.max(0, tonumber(height) or 0)
        self.content:SetHeight(math.max(1, self.icContentH))
        local _, range = W.ScrollClamp(0, self.icContentH, self.icViewH)
        self.icQuiet = true
        self.bar:SetMinMaxValues(0, math.max(1, range))
        self.icQuiet = false
        -- The thumb is as much of the bar as the view is of the content.
        if range > 0 then
            self.bar.icThumb:SetHeight(math.max(20, self.icViewH * self.icViewH / self.icContentH))
        end
        self.bar:SetShown(range > 0)
        self:ScrollTo(self.icOffset)
    end

    -- For a window whose room changes: the view is `height` tall from now on.
    function s:SetViewHeight(height)
        self.icViewH = math.max(1, tonumber(height) or 1)
        self:SetHeight(self.icViewH)
        self:SetContentHeight(self.icContentH)
    end

    function s:SetViewWidth(width)
        width = math.max(SCROLL_BAR_W + 5, tonumber(width) or 0)
        self:SetWidth(width)
        self.content:SetWidth(width - SCROLL_BAR_W - 4)
    end

    bar:SetScript("OnValueChanged", function(_, value)
        if s.icQuiet == true then return end
        s.icOffset = W.ScrollClamp(value, s.icContentH, s.icViewH)
        s:SetVerticalScroll(s.icOffset)
        if s.icOnScroll then s.icOnScroll(s.icOffset, s) end
    end)

    s:EnableMouseWheel(true)
    s:SetScript("OnMouseWheel", function(self, delta)
        self:ScrollTo(self.icOffset - (tonumber(delta) or 0) * self.icStep)
    end)

    Track(bar, function(self, theme)
        local track, thumb = theme.colors.field, theme.colors.edge
        self.icTrack:SetColorTexture(track.r, track.g, track.b, 0.6)
        self.icThumb:SetColorTexture(thumb.r, thumb.g, thumb.b, 1)
    end)
    return s
end

--------------------------------------------------------------------------------
-- Tabs
--------------------------------------------------------------------------------

local TAB_GAP = 2           -- pixels between two tabs
local TAB_W = 96            -- a tab's width when the strip has room
local TAB_H = 22
local TAB_MARK_H = 2        -- the accent line under the selected tab

-- Pure. Where each of `count` tabs sits in a strip `width` wide: { x, w } each, `tabW`
-- wide with TAB_GAP between, all shrunk alike when they would not fit. No width means
-- room for all.
function W.TabLayout(count, width, tabW)
    local out = {}
    if (count or 0) < 1 then return out end
    local w = tabW or TAB_W
    if width and count * w + (count - 1) * TAB_GAP > width then
        w = math.max(1, math.floor((width - (count - 1) * TAB_GAP) / count))
    end
    for i = 1, count do out[i] = { x = (i - 1) * (w + TAB_GAP), w = w } end
    return out
end

local function RepaintTab(b, theme)
    local c = theme.colors
    local text
    if b.icDisabled then
        Paint(b, nil, nil)
        text = c.textDisabled
    elseif b.icSelected then
        Paint(b, c.selected, nil)
        text = c.text
    elseif b.icHover then
        Paint(b, c.hover, nil)
        text = c.text
    else
        Paint(b, c.raised, nil)
        text = c.textDim
    end
    b.label:SetTextColor(text.r, text.g, text.b, text.a or 1)
    local a = c.accent
    b.mark:SetColorTexture(a.r, a.g, a.b, a.a or 1)
    b.mark:SetShown(b.icSelected == true)
end

local function DisabledTip(tip, b)
    tip:AddLine(b.label:GetText() or "")
    tip:AddLine(tostring(b.icDisabled), 1, 1, 1, true)
end

--[[
A row of tabs with one selected. A tab may own a page: selecting the tab shows its page
and hides the others, so a window switches pages with no code of its own.

tabs = { { key = "roles", label = "Roles", page = frame }, ... }   -- page is optional
opts = {
    width,                       -- the strip; tabs shrink alike to fit it
    tabWidth = 96, height = 22,
    selected = key,              -- the first tab otherwise
    onSelect = fn(key, strip),   -- a click on another tab, not Select
}
strip:Select(key)                selects it without calling onSelect; false for no such tab
strip:GetSelected()
strip:SetLabel(key, text)
strip:SetDisabled(key, reason)   a reason greys the tab and says why on hover; nil enables
strip.buttons[key]
]]
function W.Tabs(parent, tabs, opts)
    opts = opts or {}
    tabs = tabs or {}
    local theme = Theme.Current()
    local height = opts.height or TAB_H
    local layout = W.TabLayout(#tabs, opts.width, opts.tabWidth)
    local strip = CreateFrame("Frame", nil, parent)
    local last = layout[#layout]
    strip:SetSize(opts.width or (last and last.x + last.w or 1), height)
    strip.icTabs = tabs
    strip.buttons = {}
    strip.icSelected = false
    strip.icOnSelect = opts.onSelect or false

    function strip:Select(key)
        if not self.buttons[key] then return false end
        self.icSelected = key
        local current = Theme.Current()
        for _, tab in ipairs(self.icTabs) do
            local b = self.buttons[tab.key]
            b.icSelected = tab.key == key
            RepaintTab(b, current)
            if tab.page then tab.page:SetShown(tab.key == key) end
        end
        return true
    end

    function strip:GetSelected()
        return self.icSelected
    end

    function strip:SetLabel(key, text)
        local b = self.buttons[key]
        if b then b.label:SetText(text or "") end
    end

    function strip:SetDisabled(key, reason)
        local b = self.buttons[key]
        if not b then return end
        b.icDisabled = reason or false
        W.Tooltip(b, reason and DisabledTip or nil)
        RepaintTab(b, (Theme.Current()))
    end

    for i, tab in ipairs(tabs) do
        local b = CreateFrame("Button", nil, strip)
        b:SetSize(layout[i].w, height)
        b:SetPoint("TOPLEFT", strip, "TOPLEFT", layout[i].x, 0)
        Skin(b)
        b.icKey = tab.key
        b.icSelected = false
        b.icHover = false
        b.icDisabled = false
        b.label = b:CreateFontString(nil, "OVERLAY", theme.fonts.button)
        b.label:SetPoint("LEFT", b, "LEFT", 4, 0)
        b.label:SetPoint("RIGHT", b, "RIGHT", -4, 0)
        b.label:SetWordWrap(false)
        b.label:SetText(tab.label or tab.key)
        b.mark = b:CreateTexture(nil, "ARTWORK")
        b.mark:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
        b.mark:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
        b.mark:SetHeight(TAB_MARK_H)
        b:SetScript("OnEnter", function(self)
            self.icHover = true
            RepaintTab(self, (Theme.Current()))
        end)
        b:SetScript("OnLeave", function(self)
            self.icHover = false
            RepaintTab(self, (Theme.Current()))
        end)
        b:SetScript("OnClick", function(self)
            if self.icDisabled or self.icKey == strip.icSelected then return end
            strip:Select(self.icKey)
            if strip.icOnSelect then strip.icOnSelect(self.icKey, strip) end
        end)
        strip.buttons[tab.key] = b
        Track(b, RepaintTab)
    end

    if not strip:Select(opts.selected) and tabs[1] then strip:Select(tabs[1].key) end
    return strip
end

--------------------------------------------------------------------------------
-- List
--------------------------------------------------------------------------------

local LIST_ROW_H = 18       -- a row, fixed
local LIST_HEADER_H = 20    -- the column header row above the scroll
local LIST_PAD = 4          -- a cell's inset from its column's left edge
local LIST_GAP = 6          -- between two columns
local LIST_MIN_FILL = 24    -- the narrowest a fill column is squeezed to

-- Pure. Where each column sits in a row `width` wide: { x, w } each. A column with a
-- number `width` keeps it; the first without one fills what is left (at least
-- LIST_MIN_FILL); any further one without a width gets LIST_MIN_FILL.
function W.ColumnLayout(columns, width)
    local out, fixed, fill = {}, 0, nil
    for i, col in ipairs(columns or {}) do
        if type(col.width) == "number" then
            fixed = fixed + col.width
        elseif not fill then
            fill = i
        else
            fixed = fixed + LIST_MIN_FILL
        end
    end
    local n = #(columns or {})
    local rest = (width or 0) - fixed - math.max(0, n - 1) * LIST_GAP
    local x = 0
    for i, col in ipairs(columns or {}) do
        local w = type(col.width) == "number" and col.width or LIST_MIN_FILL
        if i == fill then w = math.max(LIST_MIN_FILL, rest) end
        out[i] = { x = x, w = w }
        x = x + w + LIST_GAP
    end
    return out
end

-- Pure. The items a view shows: rows `rowH` tall, the view `viewH` tall and scrolled
-- `offset` down, over `count` items. Returns first, last (last < first when none).
function W.VisibleRange(offset, rowH, viewH, count)
    count = count or 0
    if count < 1 or not rowH or rowH <= 0 then return 1, 0 end
    local first = math.floor(math.max(0, offset or 0) / rowH) + 1
    local last = math.ceil((math.max(0, offset or 0) + math.max(0, viewH or 0)) / rowH)
    if first > count then first = count end
    if last > count then last = count end
    return first, last
end

local function RepaintRow(row, theme)
    local c = theme.colors
    if row.icSelected then
        Paint(row, c.selected, nil)
    elseif row.icHover then
        Paint(row, c.hover, nil)
    else
        Paint(row, nil, nil)
    end
    for i, cell in ipairs(row.cells) do
        local color = c[row.icRoles[i] or "text"] or c.text
        cell:SetTextColor(color.r, color.g, color.b, color.a or 1)
    end
end

local function RepaintHeader(header, theme)
    Paint(header, theme.colors.raised, nil)
    local dim = theme.colors.textDim
    for _, cell in ipairs(header.cells) do cell.label:SetTextColor(dim.r, dim.g, dim.b, dim.a or 1) end
end

-- A cell's text and colour role for an item: the column's own `text(item)`, else the
-- list's `cell(item, column)`, else the item's field named by the column's key.
local function CellOf(list, item, col)
    if col.text then return col.text(item) end
    if list.icCell then return list.icCell(item, col) end
    local v = type(item) == "table" and item[col.key] or nil
    if v == nil then return "" end
    return tostring(v)
end

local function RowTip(tip, row)
    if not row.icItem or not row.icList.icTooltip then return end
    row.icList.icTooltip(tip, row.icItem)
end

local function FontNoWrap(fs)
    fs:SetWordWrap(false)
    if fs.SetMaxLines then fs:SetMaxLines(1) end
end

--[[
A list: a fixed column header row above a scroll of fixed-height, single-line rows. Only
the rows in view exist; they are pooled and filled again as the list scrolls, so a list of
thousands costs what a screenful does.

columns = { { key, label, width, justify = "LEFT" | "RIGHT" | "CENTER", tip, text = fn(item) }, ... }
    a column with no width fills what is left; tip is the header's hover text
opts = {
    rowHeight = 18, headerHeight = 20,
    cell = fn(item, column) -> text, role     -- every column's text and colour role
    onClick = fn(item, mouseButton, row),     -- left or right click on a row
    tooltip = fn(GameTooltip, item),          -- a row's hover text: the full values go here
    selected = fn(item) -> bool,              -- drawn in the selected colour
    onHeader = fn(key, column),               -- a header was clicked (to sort, say)
    empty = "Nothing here",                   -- shown when there are no items
}
list:SetItems(items)     the rows; the list redraws, keeping its scroll where it can
list:Refresh()           redraws the same items (after a selection or a value changed)
list:Resize(w, h)        the whole list, header included, for a window that resizes
list:ScrollTo(offset), list:GetItems()
list:SetSortMark(key, ascending) an arrow after the sorted column's header; nil clears it
list.header, list.scroll
Every pooled row is filled in full each time: text, colour, selection, item. Nothing of the
item that was there before survives. An item is any value but nil and false; row.icItem is
false on an empty row.
]]
function W.List(parent, w, h, opts)
    opts = opts or {}
    local theme = Theme.Current()
    local list = CreateFrame("Frame", nil, parent)
    list.icColumns = opts.columns or {}
    list.icRowH = opts.rowHeight or LIST_ROW_H
    list.icHeaderH = opts.headerHeight or LIST_HEADER_H
    list.icCell = opts.cell or false
    list.icOnClick = opts.onClick or false
    list.icTooltip = opts.tooltip or false
    list.icSelectedFn = opts.selected or false
    list.icOnHeader = opts.onHeader or false
    list.icItems = {}
    list.icW, list.icH = w, h
    list.rows = {}
    list:SetSize(w, h)

    -- The header: its own frame above the scroll, never inside it.
    local header = CreateFrame("Frame", nil, list)
    header:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
    header:SetSize(w, list.icHeaderH)
    Skin(header)
    header.cells = {}
    for i, col in ipairs(list.icColumns) do
        local cell = CreateFrame("Button", nil, header)
        cell:SetHeight(list.icHeaderH)
        cell.label = cell:CreateFontString(nil, "OVERLAY", theme.fonts.small)
        cell.label:SetPoint("LEFT", cell, "LEFT", LIST_PAD, 0)
        cell.label:SetPoint("RIGHT", cell, "RIGHT", 0, 0)
        cell.label:SetJustifyH(col.justify or "LEFT")
        FontNoWrap(cell.label)
        cell.label:SetText(col.label or "")
        cell.icKey = col.key
        cell.icLabel = col.label or ""
        if list.icOnHeader then
            cell:SetScript("OnClick", function(self) list.icOnHeader(self.icKey, col) end)
        end
        if col.tip then
            W.Tooltip(cell, function(tip) tip:AddLine(col.label or ""); tip:AddLine(col.tip, 1, 1, 1, true) end)
        end
        cell:EnableMouse(list.icOnHeader ~= false or col.tip ~= nil)
        header.cells[i] = cell
    end
    list.header = header

    local scroll = W.Scroll(list, w, math.max(1, h - list.icHeaderH), {
        step = list.icRowH * 3,
        onScroll = function() list:Render() end,
    })
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    list.scroll = scroll

    list.emptyLabel = W.Label(list, opts.empty or "", { font = "small", color = "textDim", justify = "CENTER" })
    list.emptyLabel:SetPoint("TOP", scroll, "TOP", 0, -12)
    list.emptyLabel:Hide()

    -- Row width: the scroll's content, which leaves room for the bar.
    local function RowWidth(self)
        return math.max(1, self.icW - 12)
    end

    local function PlaceCells(self)
        local layout = W.ColumnLayout(self.icColumns, RowWidth(self))
        for i, cell in ipairs(self.header.cells) do
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", self.header, "TOPLEFT", layout[i].x, 0)
            cell:SetWidth(layout[i].w)
        end
        for _, row in ipairs(self.rows) do
            row:SetWidth(RowWidth(self))
            for i, fs in ipairs(row.cells) do
                fs:ClearAllPoints()
                fs:SetPoint("LEFT", row, "LEFT", layout[i].x + LIST_PAD, 0)
                fs:SetWidth(math.max(1, layout[i].w - LIST_PAD))
            end
        end
    end

    local function MakeRow(self)
        local row = CreateFrame("Button", nil, self.scroll.content)
        row:SetHeight(self.icRowH)
        Skin(row)
        row.icList = self
        row.icItem = false
        row.icHover = false
        row.icSelected = false
        row.icRoles = {}
        row.cells = {}
        for i, col in ipairs(self.icColumns) do
            local fs = row:CreateFontString(nil, "OVERLAY", theme.fonts.body)
            fs:SetJustifyH(col.justify or "LEFT")
            FontNoWrap(fs)
            row.cells[i] = fs
        end
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", function(r, mouseButton)
            if r.icItem and self.icOnClick then self.icOnClick(r.icItem, mouseButton, r) end
        end)
        row:SetScript("OnEnter", function(r)
            r.icHover = true
            RepaintRow(r, (Theme.Current()))
        end)
        row:SetScript("OnLeave", function(r)
            r.icHover = false
            RepaintRow(r, (Theme.Current()))
        end)
        W.Tooltip(row, RowTip)
        row:Hide()
        Track(row, RepaintRow)
        self.rows[#self.rows + 1] = row
        return row
    end

    -- Enough rows for a view and one more, for the one cut in half by the scroll.
    local function EnsureRows(self)
        local need = math.ceil(math.max(1, self.icH - self.icHeaderH) / self.icRowH) + 1
        while #self.rows < need do MakeRow(self) end
        PlaceCells(self)
    end

    function list:Render()
        local items = self.icItems
        local offset = self.scroll:GetOffset()
        local first, last = W.VisibleRange(offset, self.icRowH, self.icH - self.icHeaderH, #items)
        local current = Theme.Current()
        for slot, row in ipairs(self.rows) do
            local index = first + slot - 1
            local item = index <= last and items[index] or nil
            if item == nil then
                row.icItem = false
                row:Hide()
            else
                row.icItem = item
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", self.scroll.content, "TOPLEFT", 0, -(index - 1) * self.icRowH)
                for i, col in ipairs(self.icColumns) do
                    local text, role = CellOf(self, item, col)
                    row.cells[i]:SetText(text or "")
                    row.icRoles[i] = role or false
                end
                row.icSelected = self.icSelectedFn and self.icSelectedFn(item) == true or false
                RepaintRow(row, current)
                row:Show()
            end
            -- The wheel refills rows under a pointer that has not moved: a tooltip showing
            -- for this row must follow the item now in it, or go.
            if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(row) then
                if row.icItem and self.icTooltip then
                    GameTooltip:ClearLines()
                    RowTip(GameTooltip, row)
                    GameTooltip:Show()
                else
                    GameTooltip:Hide()
                end
            end
        end
        self.emptyLabel:SetShown(#items == 0)
    end

    -- Marks the column the list is sorted by: an arrow after its header label, up for
    -- ascending. nil clears the mark.
    function list:SetSortMark(key, ascending)
        for _, cell in ipairs(self.header.cells) do
            local text = cell.icLabel
            if key ~= nil and cell.icKey == key then text = text .. (ascending and " ^" or " v") end
            cell.label:SetText(text)
        end
    end

    function list:SetItems(items)
        self.icItems = items or {}
        self.scroll:SetContentHeight(#self.icItems * self.icRowH)
        self:Render()
    end

    function list:GetItems()
        return self.icItems
    end

    function list:Refresh()
        self:Render()
    end

    function list:ScrollTo(offset)
        self.scroll:ScrollTo(offset)
    end

    function list:Resize(width, height)
        self.icW, self.icH = width or self.icW, height or self.icH
        self:SetWidth(self.icW)
        self:SetHeight(self.icH)
        self.header:SetWidth(self.icW)
        self.scroll:SetViewWidth(self.icW)
        self.scroll:SetViewHeight(math.max(1, self.icH - self.icHeaderH))
        EnsureRows(self)
        self:Render()
    end

    Track(header, RepaintHeader)
    EnsureRows(list)
    list:Render()
    return list
end

--------------------------------------------------------------------------------
-- Resize grip
--------------------------------------------------------------------------------

local GRIP = 16             -- the grip's square, in the frame's bottom-right corner
local GRIP_DOT = 2          -- one dot of the grip's mark
local RESIZE_MIN_W, RESIZE_MIN_H = 200, 120

-- Pure. A frame's size after its grip has been dragged `dx` right and `dy` down from
-- where it was `startW` by `startH`, held inside the bounds. A bound that is nil or not
-- a number does not hold.
function W.ResizeSize(startW, startH, dx, dy, minW, minH, maxW, maxH)
    local function Hold(v, lo, hi)
        if type(lo) == "number" and v < lo then v = lo end
        if type(hi) == "number" and v > hi then v = hi end
        return v
    end
    local w = Hold((startW or 0) + (dx or 0), minW, maxW)
    local h = Hold((startH or 0) + (dy or 0), minH, maxH)
    return math.floor(w + 0.5), math.floor(h + 0.5)
end

local function RepaintGrip(grip, theme)
    local c = grip.icHover and theme.colors.accent or theme.colors.edge
    for _, dot in ipairs(grip.dots) do dot:SetColorTexture(c.r, c.g, c.b, c.a or 1) end
end

-- Runs only while the grip is held.
local function FollowGrip(grip)
    local frame = grip.icFrame
    local px, py = GetCursorPosition()
    local scale = frame:GetEffectiveScale() or 1
    if scale <= 0 then scale = 1 end
    local maxW, maxH = grip.icMaxW, grip.icMaxH
    if maxW == false then maxW = UIParent:GetWidth() end
    if maxH == false then maxH = UIParent:GetHeight() end
    local w, h = W.ResizeSize(grip.icStartW, grip.icStartH, (px - grip.icStartX) / scale,
        (grip.icStartY - py) / scale, grip.icMinW, grip.icMinH, maxW, maxH)
    if w == grip.icLastW and h == grip.icLastH then return end
    grip.icLastW, grip.icLastH = w, h
    frame:SetSize(w, h)
    if grip.icOnResize then grip.icOnResize(w, h, frame) end
end

local function StopGrip(grip)
    if grip.icHeld ~= true then return end
    grip.icHeld = false
    grip:SetScript("OnUpdate", nil)
    if grip.icOnResized then grip.icOnResized(grip.icLastW, grip.icLastH, grip.icFrame) end
end

--[[
A grip in a frame's bottom-right corner that resizes it. The frame should be placed by its
top-left corner (W.SetPlace does that), so it grows right and down. While the grip is held,
and only then, it follows the pointer in an OnUpdate, the same as the minimap button.

opts = {
    minWidth = 200, minHeight = 120,
    maxWidth, maxHeight,             -- the screen's size by default
    onResize = fn(w, h, frame),      -- while dragging, each time the size changes
    onResized = fn(w, h, frame),     -- let go: save the size here
}
Returns the grip. Lay out what the frame holds again in onResize: a list's Resize, a
scroll's SetViewHeight.
]]
function W.Resize(frame, opts)
    opts = opts or {}
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(GRIP, GRIP)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    grip:SetFrameLevel((frame:GetFrameLevel() or 0) + 10)
    grip.icFrame = frame
    grip.icMinW = opts.minWidth or RESIZE_MIN_W
    grip.icMinH = opts.minHeight or RESIZE_MIN_H
    grip.icMaxW = opts.maxWidth or false
    grip.icMaxH = opts.maxHeight or false
    grip.icOnResize = opts.onResize or false
    grip.icOnResized = opts.onResized or false
    grip.icHeld = false
    grip.icHover = false
    grip.icStartX, grip.icStartY, grip.icStartW, grip.icStartH = 0, 0, 0, 0
    grip.icLastW, grip.icLastH = 0, 0

    -- Six dots in a triangle against the corner, the usual mark, drawn from colour.
    grip.dots = {}
    for row = 0, 2 do
        for col = 0, 2 - row do
            local dot = grip:CreateTexture(nil, "OVERLAY")
            dot:SetSize(GRIP_DOT, GRIP_DOT)
            dot:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -2 - col * 4, 2 + row * 4)
            grip.dots[#grip.dots + 1] = dot
        end
    end

    grip:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local px, py = GetCursorPosition()
        self.icStartX, self.icStartY = px or 0, py or 0
        self.icStartW, self.icStartH = self.icFrame:GetWidth() or 0, self.icFrame:GetHeight() or 0
        self.icLastW, self.icLastH = self.icStartW, self.icStartH
        self.icHeld = true
        if GameTooltip then GameTooltip:Hide() end
        self:SetScript("OnUpdate", FollowGrip)
    end)
    grip:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then StopGrip(self) end
    end)
    -- Hidden mid-drag (the window closed): let go.
    grip:SetScript("OnHide", StopGrip)
    grip:SetScript("OnEnter", function(self)
        self.icHover = true
        RepaintGrip(self, (Theme.Current()))
    end)
    grip:SetScript("OnLeave", function(self)
        self.icHover = false
        RepaintGrip(self, (Theme.Current()))
    end)
    W.Tooltip(grip, function(tip) tip:AddLine("Drag to resize") end)
    Track(grip, RepaintGrip)
    return grip
end

--------------------------------------------------------------------------------
-- Text area
--------------------------------------------------------------------------------

local AREA_INSET = 4        -- the text's inset from the area's edge

-- Keeps the line with the cursor in view: y is the cursor's top (0 or less, down from the
-- top of the text) and h its height, as OnCursorChanged gives them.
local function FollowCursor(area, y, h)
    local s = area.scroll
    local top = -(tonumber(y) or 0)
    local bottom = top + (tonumber(h) or 0)
    local offset, view = s:GetOffset(), s.icViewH
    if top < offset then
        s:ScrollTo(top)
    elseif bottom > offset + view then
        s:ScrollTo(bottom - view)
    end
end

local function FitText(area)
    local e = area.edit
    local height = math.max(area.scroll.icViewH, (e:GetHeight() or 0) + AREA_INSET)
    area.scroll:SetContentHeight(height)
end

--[[
A box of many lines: somewhere to paste a shared rule set, or a copy box to take an export
from. A multi-line edit box in a themed scroll; the wheel and the bar move it, and the line
being typed on stays in view.

opts = {
    text = "",
    maxBytes,                          -- the most it takes; none by default
    readOnly = true,                   -- a copy box: what is typed is undone, and focus
                                       -- selects everything ready for Ctrl+C
    onChange = fn(text, area),         -- each change the player makes, not SetText's
}
area:SetText(text)                     scrolls back to the top
area:GetText()
area:SelectAll()                       focuses the box and selects everything
area:Resize(w, h)
area.edit, area.scroll
Escape drops focus. A box with focus takes every key, so drop it (area.edit:ClearFocus())
when combat starts.
]]
function W.TextArea(parent, w, h, opts)
    opts = opts or {}
    local theme = Theme.Current()
    local area = CreateFrame("Frame", nil, parent)
    area:SetSize(w, h)
    Skin(area)
    area.icW, area.icH = w, h
    area.icReadOnly = opts.readOnly == true
    area.icOnChange = opts.onChange or false
    area.icText = opts.text or ""

    local scroll = W.Scroll(area, w - 2 * AREA_INSET, h - 2 * AREA_INSET, { step = 42 })
    scroll:SetPoint("TOPLEFT", area, "TOPLEFT", AREA_INSET, -AREA_INSET)
    area.scroll = scroll

    local e = CreateFrame("EditBox", nil, scroll.content)
    e:SetMultiLine(true)
    e:SetAutoFocus(false)
    e:SetFontObject(_G[theme.fonts.body] or theme.fonts.body)
    e:SetPoint("TOPLEFT", scroll.content, "TOPLEFT", 0, 0)
    e:SetWidth(w - 2 * AREA_INSET - SCROLL_BAR_W - 4)
    if opts.maxBytes then e:SetMaxBytes(opts.maxBytes + 1) end
    e:SetText(area.icText)
    area.edit = e

    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEditFocusGained", function(self)
        if area.icReadOnly then self:HighlightText() end
    end)
    e:SetScript("OnTextChanged", function(self, userInput)
        if userInput and area.icReadOnly then
            -- A copy box: put back what it holds and select it again.
            self:SetText(area.icText)
            self:HighlightText()
            return
        end
        FitText(area)
        if userInput then
            area.icText = self:GetText() or ""
            if area.icOnChange then area.icOnChange(area.icText, area) end
        end
    end)
    if e:HasScript("OnCursorChanged") then
        e:SetScript("OnCursorChanged", function(_, _, y, _, cursorH) FollowCursor(area, y, cursorH) end)
    end
    -- A press anywhere in the area, below the last line too, puts the cursor in the box.
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", function() e:SetFocus() end)

    function area:SetText(text)
        self.icText = text or ""
        self.edit:SetText(self.icText)
        FitText(self)
        self.scroll:ScrollTo(0)
    end

    function area:GetText()
        return self.edit:GetText() or ""
    end

    function area:SelectAll()
        self.edit:SetFocus()
        self.edit:HighlightText()
    end

    function area:Resize(width, height)
        self.icW, self.icH = width or self.icW, height or self.icH
        self:SetWidth(self.icW)
        self:SetHeight(self.icH)
        self.scroll:SetViewWidth(self.icW - 2 * AREA_INSET)
        self.scroll:SetViewHeight(math.max(1, self.icH - 2 * AREA_INSET))
        self.edit:SetWidth(math.max(1, self.icW - 2 * AREA_INSET - SCROLL_BAR_W - 4))
        FitText(self)
    end

    Track(area, function(self, current)
        Paint(self, current.colors.field, current.colors.edge)
        local c = current.colors.text
        self.edit:SetTextColor(c.r, c.g, c.b, 1)
    end)
    FitText(area)
    return area
end

--------------------------------------------------------------------------------
-- Raid icon
--------------------------------------------------------------------------------

-- The eight raid target icons, four to a row in one texture: star, circle, diamond,
-- triangle, then moon, square, cross, skull.
local RAID_ICONS = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local RAID_ICON_COUNT = 8

-- Pure. The texcoords (left, right, top, bottom) of raid icon `index` (1 to 8) in the
-- icons' texture, or nil for anything else: a number out of range, a fraction, text, nil.
function W.RaidIconCoords(index)
    if type(index) ~= "number" or index ~= math.floor(index) or index < 1 or index > RAID_ICON_COUNT then
        return nil
    end
    local col, row = (index - 1) % 4, math.floor((index - 1) / 4)
    return col * 0.25, (col + 1) * 0.25, row * 0.25, (row + 1) * 0.25
end

--[[
One raid target icon, from a plain number. The client's own SetRaidTargetIconTexture is not
used: it throws when handed a secret index. Here anything that is not a plain whole number
from 1 to 8, a secret one included, hides the icon instead.

icon = W.RaidIcon(parent, index, size)   size is 16 by default
icon:SetIndex(index)                     returns whether it is showing
icon:GetIndex()                          the index shown, or false
]]
function W.RaidIcon(parent, index, size)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size or 16, size or 16)
    icon:SetTexture(RAID_ICONS)
    icon.icIndex = false

    function icon:SetIndex(i)
        local l, r, t, b
        if not Env.IsSecret(i) then l, r, t, b = W.RaidIconCoords(i) end
        if not l then
            self.icIndex = false
            self:Hide()
            return false
        end
        self.icIndex = i
        self:SetTexCoord(l, r, t, b)
        self:Show()
        return true
    end

    function icon:GetIndex()
        return self.icIndex
    end

    icon:SetIndex(index)
    return icon
end

--------------------------------------------------------------------------------
-- Tooltip, menu, confirm
--------------------------------------------------------------------------------

-- builder(GameTooltip, frame) adds the lines; nil takes the tooltip off again. Hooks
-- rather than replaces the frame's own hover scripts, so a button keeps its highlight.
-- The tooltip sits at the pointer by default. An anchor on the frame's own edge
-- ("ANCHOR_RIGHT") puts it a title bar's width away from where the player is looking.
function W.Tooltip(frame, builder, anchor)
    frame.icTip = builder or false
    frame.icTipAnchor = anchor or "ANCHOR_CURSOR_RIGHT"
    if frame.icTipHooked == true then return end
    frame.icTipHooked = true
    frame:HookScript("OnEnter", function(self)
        if not self.icTip then return end
        GameTooltip:SetOwner(self, self.icTipAnchor)
        self.icTip(GameTooltip, self)
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function(self)
        if self.icTip then GameTooltip:Hide() end
    end)
end

--[[
A context menu at the pointer. items is a list of:
    { title = "Raid prep" }
    { text = "Rename", onClick = fn }
    { text = "Locked", checked = fn() -> bool, onClick = fn }
    { text = "High", radio = fn() -> bool, onClick = fn }     one of several; the menu closes
    { divider = true }
Any item but a title or a divider may carry disabled = true, or disabled = "the reason",
which greys it out and shows the reason in its tooltip.
Returns false on a client without the modern menu, so the caller can say so.
]]
function W.Menu(owner, items)
    if type(MenuUtil) ~= "table" or type(MenuUtil.CreateContextMenu) ~= "function" then return false end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        for _, item in ipairs(items or {}) do
            local made
            if item.title then
                root:CreateTitle(item.title)
            elseif item.divider then
                root:CreateDivider()
            elseif item.checked then
                made = root:CreateCheckbox(item.text, item.checked, item.onClick)
            elseif item.radio then
                made = root:CreateRadio(item.text, item.radio, function()
                    if item.onClick then item.onClick() end
                    return MenuResponse and MenuResponse.Close or nil
                end)
            else
                made = root:CreateButton(item.text, item.onClick)
            end
            if made and item.disabled then
                made:SetEnabled(false)
                if type(item.disabled) == "string" then
                    made:SetTooltip(function(tooltip)
                        GameTooltip_SetTitle(tooltip, item.text)
                        GameTooltip_AddErrorLine(tooltip, item.disabled)
                    end)
                end
            end
        end
    end)
    return true
end

-- A yes/no dialog. onAccept runs on Yes; No and Escape do nothing.
function W.Confirm(text, onAccept)
    if type(StaticPopupDialogs) ~= "table" or type(StaticPopup_Show) ~= "function" then return false end
    if type(StaticPopupDialogs.ICKIT_CONFIRM) ~= "table" then
        StaticPopupDialogs.ICKIT_CONFIRM = {
            text = "%s",
            button1 = YES,
            button2 = NO,
            OnAccept = function(_, data)
                if type(data) == "function" then data() end
            end,
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
        }
    end
    StaticPopup_Show("ICKIT_CONFIRM", text, nil, onAccept)
    return true
end

--------------------------------------------------------------------------------
-- Minimap button
--------------------------------------------------------------------------------

-- Pure. Where a button at `angle` degrees sits, as an offset from the minimap's centre.
-- 0 is due east and the angle grows anticlockwise, as the client's own trigonometry has it.
function W.MinimapOffset(angle, radius)
    local a = math.rad(tonumber(angle) or 0)
    return math.cos(a) * radius, math.sin(a) * radius
end

-- Pure. The angle, in degrees from 0 up to 360, of a pointer at (px, py) seen from a
-- minimap centred on (mx, my).
function W.MinimapAngle(px, py, mx, my)
    local degrees = math.deg(math.atan2(py - my, px - mx))
    if degrees < 0 then degrees = degrees + 360 end
    return degrees
end

local function PlaceOnMinimap(button)
    local radius = (Minimap:GetWidth() or 140) / 2 + 5
    local x, y = W.MinimapOffset(button.icAngle, radius)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Runs only while the button is being dragged round the minimap.
local function FollowPointer(button)
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    if not mx or not px or not scale or scale <= 0 then return end
    button:SetAngle(W.MinimapAngle(px / scale, py / scale, mx, my))
end

--[[
A round button on the minimap's rim, in the client's own minimap art. It is not themed:
it sits among the game's buttons and should look like one of them.

opts = {
    icon = "Interface\\Icons\\...",
    angle = 215,                        -- degrees round the rim; 0 is east, 90 north
    onClick = fn(button, mouseButton),  -- left or right
    onMoved = fn(angle),                -- dragged round the rim and dropped
    tooltip = fn(GameTooltip, button),
    name = "MyAddonMinimapButton",      -- optional global name, below
}
A name lets minimap button collectors (EllesmereUI's flyout, MBB-style bars) gather the
button: they take only named buttons, and skip a name ending in a digit as one of a
numbered set. So the name is letters, digits and underscores, starts with a letter or
underscore and does not end in a digit. A name that breaks that rule, or is already a
global, is not used: the button is made without one and the reason comes back second,
so the addon still gets its button.
A collector reparents the button into its own bar or flyout and places it there. While the
button is not on the Minimap it is the collector's to place: SetAngle only records the
angle, and a drag does nothing (W.OnMinimap(button) says which).
button:SetAngle(degrees) moves it. Dragging is the one place a widget runs an OnUpdate,
and only between the drag starting and the button being dropped.
]]
-- Whether a minimap button is still on the Minimap, rather than taken into a collector.
function W.OnMinimap(button)
    return button:GetParent() == Minimap
end

-- The name a minimap button may take, or nil and why not.
function W.MinimapButtonName(name)
    if name == nil then return nil end
    if type(name) ~= "string" or not name:match("^[%a_][%w_]*$") then
        return nil, "a minimap button name is letters, digits and underscores"
    end
    if name:match("%d$") then
        return nil, "a minimap button name ending in a digit is skipped by collectors"
    end
    if _G[name] ~= nil then return nil, "the name " .. name .. " is taken" end
    return name
end

function W.MinimapButton(opts)
    opts = opts or {}
    local name, refused = W.MinimapButtonName(opts.name)
    local b = CreateFrame("Button", name, Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b.icAngle = tonumber(opts.angle) or 215
    b.icOnMoved = opts.onMoved or false
    b.icDragging = false

    b.back = b:CreateTexture(nil, "BACKGROUND")
    b.back:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    b.back:SetSize(20, 20)
    b.back:SetPoint("TOPLEFT", b, "TOPLEFT", 7, -5)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetTexture(opts.icon)
    b.icon:SetSize(17, 17)
    b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 7, -6)
    b.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)

    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b.border:SetSize(53, 53)
    b.border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)

    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    function b:SetAngle(degrees)
        self.icAngle = (tonumber(degrees) or 0) % 360
        if W.OnMinimap(self) then PlaceOnMinimap(self) end
    end

    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    if opts.onClick then b:SetScript("OnClick", opts.onClick) end

    -- A drag here is the client's drag event on purpose: a press must stay a click, and
    -- the button only goes round the rim once the pointer has really moved.
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function(self)
        if not W.OnMinimap(self) then return end
        self.icDragging = true
        if GameTooltip then GameTooltip:Hide() end
        self:SetScript("OnUpdate", FollowPointer)
    end)
    b:SetScript("OnDragStop", function(self)
        if self.icDragging ~= true then return end
        self.icDragging = false
        self:SetScript("OnUpdate", nil)
        if self.icOnMoved then self.icOnMoved(self.icAngle) end
    end)

    if opts.tooltip then W.Tooltip(b, opts.tooltip, "ANCHOR_LEFT") end
    b:SetAngle(b.icAngle)
    return b, refused
end

--[[
An entry in the Addon Compartment: the client's own button beside the minimap that lists
addons. This is the modern way onto the minimap, and it costs no frame of ours.

opts = {
    text = "Stickies", icon = "Interface\\Icons\\...",
    onClick = fn(mouseButton),              -- "LeftButton", "RightButton", ...
    tooltip = fn(GameTooltip, entry),
}
Returns false on a client without the compartment.
]]
function W.Compartment(opts)
    opts = opts or {}
    local frame = AddonCompartmentFrame
    if type(frame) ~= "table" or type(frame.RegisterAddon) ~= "function" then return false end
    frame:RegisterAddon({
        text = opts.text,
        icon = opts.icon,
        func = function(_, input)
            if opts.onClick then opts.onClick(type(input) == "table" and input.buttonName or "LeftButton") end
        end,
        funcOnEnter = function(entry)
            if not opts.tooltip then return end
            GameTooltip:SetOwner(entry, "ANCHOR_LEFT")
            opts.tooltip(GameTooltip, entry)
            GameTooltip:Show()
        end,
        funcOnLeave = function()
            GameTooltip:Hide()
        end,
    })
    return true
end
