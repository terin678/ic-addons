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

local function StartDrag(panel)
    if panel.icLocked ~= true then panel:StartMoving() end
end

local function StopDrag(panel)
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
    p.icOnMoved = opts.onMoved or false

    function p:SetLocked(on)
        self.icLocked = on and true or false
    end

    if opts.movable then
        p:SetMovable(true)
        p:EnableMouse(true)
        p:SetClampedToScreen(true)
        p:RegisterForDrag("LeftButton")
        p:SetScript("OnDragStart", StartDrag)
        p:SetScript("OnDragStop", StopDrag)
    end

    Track(p, function(self, theme)
        Paint(self, theme.colors[self.icRole], self.icEdge and theme.colors.edge or nil)
    end)
    return p
end

-- A child that drags its panel: a title bar, usually.
function W.DragHandle(handle, panel)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function() StartDrag(panel) end)
    handle:SetScript("OnDragStop", function() StopDrag(panel) end)
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
function W.Tooltip(frame, builder)
    frame.icTip = builder or false
    if frame.icTipHooked == true then return end
    frame.icTipHooked = true
    frame:HookScript("OnEnter", function(self)
        if not self.icTip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
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
