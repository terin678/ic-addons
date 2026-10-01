--[[
LibICWidgets-1.0
Layer 2 of ICKit: themed frames. Only what an addon has needed so far, and each one is
drawn from colour textures, so no widget depends on a Blizzard frame template.

    local W = LibStub("LibICWidgets-1.0")

    W.Panel(parent, opts)               a filled, edged frame; movable when asked
    W.DragHandle(handle, panel)         drag the panel by one of its children
    W.Label(parent, text, opts)         a font string in a theme colour
    W.Button(parent, text, w, h, opts)  normal | accent | danger | flat
    W.CheckBox(parent, opts)            a tick box
    W.EditBox(parent, w, h, opts)       one line of text
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

local MAJOR, MINOR = "LibICWidgets-1.0", 1
local W = LibStub:NewLibrary(MAJOR, MINOR)
if not W then return end

local Theme = LibStub("LibICTheme-1.0")

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
    e:SetScript("OnTextChanged", SyncPlaceholder)
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
    { divider = true }
Returns false on a client without the modern menu, so the caller can say so.
]]
function W.Menu(owner, items)
    if type(MenuUtil) ~= "table" or type(MenuUtil.CreateContextMenu) ~= "function" then return false end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        for _, item in ipairs(items or {}) do
            if item.title then
                root:CreateTitle(item.title)
            elseif item.divider then
                root:CreateDivider()
            elseif item.checked then
                root:CreateCheckbox(item.text, item.checked, item.onClick)
            else
                root:CreateButton(item.text, item.onClick)
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
}
button:SetAngle(degrees) moves it. Dragging is the one place a widget runs an OnUpdate,
and only between the drag starting and the button being dropped.
]]
function W.MinimapButton(opts)
    opts = opts or {}
    local b = CreateFrame("Button", nil, Minimap)
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
        PlaceOnMinimap(self)
    end

    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    if opts.onClick then b:SetScript("OnClick", opts.onClick) end

    -- A drag here is the client's drag event on purpose: a press must stay a click, and
    -- the button only goes round the rim once the pointer has really moved.
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function(self)
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
    return b
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
