--[[
LibICUI-1.0
Window, list and control widgets for the ic-addons guild addons, so every window follows the
"Window layout" rules in CODING_STANDARDS.md by construction: column headers live outside
the scroll child, rows are a fixed height and never wrap, toolbars sit above the headers,
and every control wears the guild palette.

    local UI = LibStub("LibICUI-1.0")

    UI:Age(seconds)                     -> "now", "42s", "7m", "3h", "2d"
    UI:Style(name, style)               register a look, returns it
    UI:Hex(color) / UI:Logo(parent, size, large)

    UI:Window(name, opts)               -> f    (f.body, f.title, f.status)
    UI:TabStrip(parent, opts)           -> strip (strip:Select(name))
    UI:Button(parent, text, w, h, opts) -> b    (b:SetActive(on), b:SetKind(kind))
    UI:EditBox(parent, w, h, opts)
    UI:TextBox(parent, w, h, opts)   -> box  (box:SetText(s), box:SelectAllAndFocus())
    UI:CheckBox(parent, label, opts)    -> cb   (cb.label)
    UI:Panel(parent, opts) / UI:Skin(frame, color, border)
    UI:ScrollList(parent, top, bottom, right)
    UI:Toolbar(parent, opts)            -> tb   (tb:Left(w), tb:Right(w))
    UI:Table(parent, opts)              -> t    (t:Render(list, fill), t:Row(i), t:SetSelected(item))
                                        callbacks get the table as their last argument

A style is a plain table; missing keys fall back to the default one:
    rowHeight, headerHeight, gap, font, headerFont, buttonFont, titleFont,
    bg, altBg, headerBg, hoverBg, selectedBg, border, windowBg, panelBg, editBg,
    buttonBg, buttonHoverBg, buttonBorder, buttonText, accentBg, accentHoverBg,
    accentText, dangerBg, dangerHoverBg, dangerText, disabledText, pageWidth
    (colours are { r, g, b, a })

Set `theme = false` in a style to get plain Blizzard controls instead of the guild palette.
The palette is the default; nothing has to ask for it.
]]

local MAJOR, MINOR = "LibICUI-1.0", 4
local Lib = LibStub:NewLibrary(MAJOR, MINOR)
if not Lib then return end

Lib.styles = Lib.styles or {}

-- Interface\Buildings\White8x8 does not resolve on this client: every frame using it
-- draws with no fill at all. Interface\Buttons\WHITE8x8 is the one that exists.
local BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

--------------------------------------------------------------------------------
-- Guild brand
--------------------------------------------------------------------------------

-- Impulse Control's colours, sampled from the guild mark. Addons in this repo
-- share them so windows look like they belong together.
Lib.Brand = {
    name = "Impulse Control",
    logo = "Interface\\AddOns\\ICLibs\\Textures\\ImpulseControl-64",
    logoLarge = "Interface\\AddOns\\ICLibs\\Textures\\ImpulseControl-128",
    ink = { r = 0.082, g = 0.137, b = 0.200 },   -- #152333 deep navy, window ground
    panel = { r = 0.098, g = 0.149, b = 0.216 }, -- #192637 raised panel
    gold = { r = 0.875, g = 0.612, b = 0.200 },  -- #DF9C33 skull, accents
    flame = { r = 0.765, g = 0.251, b = 0.184 }, -- #C3402F flame, danger
    bone = { r = 0.957, g = 0.898, b = 0.757 },  -- #F4E5C1 lettering, headings
}

-- "|cffdf9c33text|r" for chat and FontStrings that take a colour code.
function Lib:Hex(color)
    return string.format("|cff%02x%02x%02x",
        math.floor(color.r * 255 + 0.5), math.floor(color.g * 255 + 0.5),
        math.floor(color.b * 255 + 0.5))
end

-- Guild mark for a window header. size defaults to 20.
function Lib:Logo(parent, size, large)
    local tex = parent:CreateTexture(nil, "ARTWORK")
    tex:SetSize(size or 20, size or 20)
    tex:SetTexture(large and self.Brand.logoLarge or self.Brand.logo)
    return tex
end

local DEFAULT = {
    theme = true,
    rowHeight = 18,
    headerHeight = 18,
    gap = 6,
    font = "GameFontHighlightSmall",
    headerFont = "GameFontDisableSmall",
    buttonFont = "GameFontNormalSmall",
    titleFont = "GameFontNormal",
    bg = { r = 0.082, g = 0.137, b = 0.200, a = 0 },
    altBg = { r = 1, g = 1, b = 1, a = 0.03 },
    headerBg = { r = 0.098, g = 0.149, b = 0.216, a = 1 },
    hoverBg = { r = 0.25, g = 0.25, b = 0.35, a = 0.4 },
    selectedBg = { r = 0.875, g = 0.612, b = 0.200, a = 0.25 },
    border = { r = 0.3, g = 0.3, b = 0.3, a = 0.8 },
    -- Window chrome and controls
    windowBg = { r = 0.082, g = 0.137, b = 0.200, a = 0.96 },
    windowBorder = { r = 0.32, g = 0.42, b = 0.55, a = 0.9 },
    panelBg = { r = 0.098, g = 0.149, b = 0.216, a = 1 },
    editBg = { r = 0.055, g = 0.094, b = 0.145, a = 1 },
    buttonBg = { r = 0.145, g = 0.208, b = 0.298, a = 1 },
    buttonHoverBg = { r = 0.220, g = 0.302, b = 0.412, a = 1 },
    buttonBorder = { r = 0.32, g = 0.42, b = 0.55, a = 0.9 },
    buttonText = { r = 0.957, g = 0.898, b = 0.757 },
    accentBg = { r = 0.875, g = 0.612, b = 0.200, a = 1 },
    accentHoverBg = { r = 0.949, g = 0.702, b = 0.302, a = 1 },
    accentText = { r = 0.082, g = 0.137, b = 0.200 },
    dangerBg = { r = 0.765, g = 0.251, b = 0.184, a = 1 },
    dangerHoverBg = { r = 0.851, g = 0.341, b = 0.271, a = 1 },
    dangerText = { r = 0.957, g = 0.898, b = 0.757 },
    disabledText = { r = 0.45, g = 0.47, b = 0.50 },
    pageWidth = 700,
}
Lib.styles.default = DEFAULT

-- Registers a look under a name and fills in whatever it leaves out. Call once per addon
-- at load; pass the name (or the table) as opts.style afterwards.
function Lib:Style(name, style)
    local out = {}
    for k, v in pairs(DEFAULT) do out[k] = v end
    for k, v in pairs(style or {}) do out[k] = v end
    self.styles[name] = out
    return out
end

local function StyleOf(style)
    if type(style) == "table" then return style end
    return Lib.styles[style or "default"] or DEFAULT
end

local function Paint(f, color, border)
    if not f.SetBackdrop then return f end
    f:SetBackdrop(BACKDROP)
    f:SetBackdropColor(color.r, color.g, color.b, color.a or 1)
    if border then
        f:SetBackdropBorderColor(border.r, border.g, border.b, border.a or 1)
    else
        f:SetBackdropBorderColor(0, 0, 0, 0)
    end
    return f
end

-- Paints any frame in the palette. Colours are style tables, e.g. style.panelBg.
function Lib:Skin(frame, color, border)
    return Paint(frame, color or DEFAULT.panelBg, border)
end

-- A raised panel, for detail areas and footers.
function Lib:Panel(parent, opts)
    opts = opts or {}
    local style = StyleOf(opts.style)
    local p = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    Paint(p, opts.color or style.panelBg, opts.border or style.border)
    return p
end

--------------------------------------------------------------------------------
-- Relative age
--------------------------------------------------------------------------------

-- Pure. Lists show age, never a raw timestamp; the exact time belongs in a tooltip.
function Lib:Age(seconds)
    if type(seconds) ~= "number" or seconds < 0 then return "-" end
    if seconds < 5 then return "now" end
    if seconds < 60 then return string.format("%ds", seconds) end
    if seconds < 3600 then return string.format("%dm", math.floor(seconds / 60)) end
    if seconds < 86400 then return string.format("%dh", math.floor(seconds / 3600)) end
    return string.format("%dd", math.floor(seconds / 86400))
end

--------------------------------------------------------------------------------
-- Controls
--------------------------------------------------------------------------------

-- Fill and text colour for each button kind, so a toggle can move between them.
local function KindColors(style, kind)
    if kind == "accent" then
        return style.accentBg, style.accentHoverBg, style.accentText
    elseif kind == "danger" then
        return style.dangerBg, style.dangerHoverBg, style.dangerText
    end
    return style.buttonBg, style.buttonHoverBg, style.buttonText
end

local function RepaintButton(b)
    local bg, _, text = KindColors(b.icStyle, b.icKind)
    b:SetBackdropColor(bg.r, bg.g, bg.b, bg.a or 1)
    if b:IsEnabled() then
        b.text:SetTextColor(text.r, text.g, text.b)
    else
        local d = b.icStyle.disabledText
        b.text:SetTextColor(d.r, d.g, d.b)
    end
end

--[[
opts = {
    style,                  -- name or table
    kind = "normal" | "accent" | "danger",
    template,               -- extra frame template, e.g. "SecureActionButtonTemplate"
    font,                   -- font object name, defaults to the style's buttonFont
}
The returned button behaves like a Blizzard one: SetText, GetText, Enable, Disable,
SetEnabled and IsEnabled all work. b:SetActive(true) paints it as a live toggle.
]]
function Lib:Button(parent, text, w, h, opts)
    opts = opts or {}
    local style = StyleOf(opts.style)

    if not style.theme then
        local tmpl = opts.template and (opts.template .. ", UIPanelButtonTemplate")
            or "UIPanelButtonTemplate"
        local b = CreateFrame("Button", nil, parent, tmpl)
        b:SetSize(w or 90, h or 22)
        b:SetText(text or "")
        b.SetActive = function() end
        b.SetKind = function() end
        return b
    end

    local tmpl = BackdropTemplateMixin and "BackdropTemplate" or nil
    if opts.template then
        tmpl = tmpl and (opts.template .. ", " .. tmpl) or opts.template
    end
    local b = CreateFrame("Button", nil, parent, tmpl)
    b:SetSize(w or 90, h or 22)
    b.icStyle = style
    b.icKind = opts.kind or "normal"
    b.icBaseKind = b.icKind

    b.text = b:CreateFontString(nil, "OVERLAY", opts.font or style.buttonFont)
    b.text:SetPoint("CENTER")
    b.text:SetWordWrap(false)
    -- SetFontString is what makes SetText/GetText work on a bare Button.
    b:SetFontString(b.text)

    Paint(b, style.buttonBg, style.buttonBorder)
    b:SetText(text or "")
    RepaintButton(b)

    b:SetScript("OnEnter", function(self)
        if not self:IsEnabled() then return end
        local _, hover = KindColors(self.icStyle, self.icKind)
        self:SetBackdropColor(hover.r, hover.g, hover.b, hover.a or 1)
        if self.icOnEnter then self.icOnEnter(self) end
    end)
    b:SetScript("OnLeave", function(self)
        RepaintButton(self)
        if self.icOnLeave then self.icOnLeave(self) end
    end)
    b:SetScript("OnEnable", RepaintButton)
    b:SetScript("OnDisable", RepaintButton)

    -- Moves the button between kinds, e.g. a filter that goes gold while it is on.
    function b:SetKind(kind)
        self.icKind = kind or "normal"
        RepaintButton(self)
    end

    -- A toggle shows its state: gold when on, plain when off.
    function b:SetActive(on)
        self:SetKind(on and "accent" or self.icBaseKind)
    end

    return b
end

-- A single-line text box in the palette.
function Lib:EditBox(parent, w, h, opts)
    opts = opts or {}
    local style = StyleOf(opts.style)
    local box = CreateFrame("EditBox", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    box:SetSize(w or 200, h or 22)
    box:SetAutoFocus(false)
    box:SetFontObject(opts.font or style.font)
    box:SetTextInsets(6, 6, 0, 0)
    if style.theme then
        Paint(box, style.editBg, style.buttonBorder)
        local t = style.buttonText
        box:SetTextColor(t.r, t.g, t.b)
    else
        Paint(box, DEFAULT.editBg, DEFAULT.border)
    end
    box:SetScript("OnEscapePressed", box.ClearFocus)
    return box
end

--[[
A multi-line text area: a scroll frame wrapping an EditBox, in the palette.
opts = { style, readOnly, maxBytes, font, onChange(text) }

Returns the outer frame with:
    box.scroll              the ScrollFrame, for anything that needs to drive it
    box.edit                the EditBox itself
    box:SetText(s), box:GetText()
    box:SelectAllAndFocus() for a Copy button

There is no clipboard API on this client, so the most an addon can offer is to
select the text and let the player press Ctrl+C. That is also why readOnly puts
the old text back on every change instead of disabling the box: a disabled
EditBox cannot be selected either, and selecting is the whole point of one.
]]
function Lib:TextBox(parent, w, h, opts)
    opts = opts or {}
    local style = StyleOf(opts.style)
    w, h = w or 300, h or 100

    local box = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    box:SetSize(w, h)
    if style.theme then
        Paint(box, style.editBg, style.buttonBorder)
    else
        Paint(box, DEFAULT.editBg, DEFAULT.border)
    end

    -- 26 on the right is the scrollbar's width, the same inset Lib:ScrollList
    -- reserves, so a text box and a table beside it line up.
    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -5)
    scroll:SetPoint("BOTTOMRIGHT", -26, 5)
    box.scroll = scroll

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(opts.font or style.font)
    -- A multi-line EditBox grows its own height to fit its text once it is a
    -- scroll child; the width is ours to set and the initial height only has to
    -- be non-zero, or there is nothing for the scroll frame to show. The viewport
    -- is w minus the 6 on the left and the 26 on the right, so this fills it.
    edit:SetWidth(w - 34)
    edit:SetHeight(h)
    if opts.maxBytes then edit:SetMaxBytes(opts.maxBytes) end
    if style.theme then
        local t = style.buttonText
        edit:SetTextColor(t.r, t.g, t.b)
    end
    edit:SetScript("OnEscapePressed", edit.ClearFocus)
    scroll:SetScrollChild(edit)
    box.edit = edit

    -- Typing past the bottom of the viewport has to bring the caret back into
    -- view, or the player is typing somewhere they cannot see.
    edit:SetScript("OnCursorChanged", function(_, _, y, _, cursorHeight)
        local top = -y
        local offset, view = scroll:GetVerticalScroll(), scroll:GetHeight()
        local want = offset
        if top < offset then
            want = top
        elseif top + cursorHeight > offset + view then
            want = top + cursorHeight - view
        end
        local range = scroll:GetVerticalScrollRange() or 0
        want = math.max(0, math.min(want, range))
        if want ~= offset then scroll:SetVerticalScroll(want) end
    end)

    -- Set while we are the ones changing the text, so our own writes do not come
    -- back round as edits.
    local ours = false
    edit:SetScript("OnTextChanged", function(self, byUser)
        if ours then return end
        if opts.readOnly and byUser then
            ours = true
            self:SetText(box.text or "")
            ours = false
            return
        end
        box.text = self:GetText()
        if opts.onChange then opts.onChange(box.text) end
    end)

    function box:SetText(s)
        self.text = s or ""
        ours = true
        edit:SetText(self.text)
        ours = false
        edit:SetCursorPosition(0)
        scroll:SetVerticalScroll(0)
    end

    function box:GetText()
        return edit:GetText()
    end

    function box:SelectAllAndFocus()
        edit:SetFocus()
        edit:HighlightText()
    end

    -- The EditBox is only as tall as its own text, so on a box with one line in it
    -- everything below that line is dead to the mouse and clicking there puts no
    -- caret anywhere. The frame and its viewport hand the click on.
    local function Focus()
        edit:SetFocus()
    end
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", Focus)
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", Focus)

    box:SetText("")
    return box
end

-- Blizzard's check button with a palette label beside it. cb.label is the FontString.
function Lib:CheckBox(parent, label, opts)
    opts = opts or {}
    local style = StyleOf(opts.style)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(opts.size or 20, opts.size or 20)
    cb.label = cb:CreateFontString(nil, "OVERLAY", opts.font or style.buttonFont)
    cb.label:SetWordWrap(false)
    if opts.labelSide == "LEFT" then
        cb.label:SetPoint("RIGHT", cb, "LEFT", -3, 0)
    else
        cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    end
    cb.label:SetText(label or "")
    if style.theme then
        local t = style.buttonText
        cb.label:SetTextColor(t.r, t.g, t.b)
    end
    return cb
end

--[[
Wires a GameTooltip onto any widget. builder(widget) adds the lines; the owner, the
Show and the Hide are handled here. Pass nil to take a tooltip off again, which is what
a pooled list row needs before it is filled with a different item.

On one of this library's own buttons the tooltip rides alongside the hover paint instead
of replacing it.
]]
function Lib:Tooltip(widget, builder)
    local show = builder and function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        builder(self)
        GameTooltip:Show()
    end
    local hide = builder and function() GameTooltip:Hide() end
    if widget.icStyle then
        widget.icOnEnter, widget.icOnLeave = show, hide
    else
        widget:SetScript("OnEnter", show)
        widget:SetScript("OnLeave", hide)
    end
    return widget
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------

--[[
A movable, escapable window wearing the guild mark.
opts = { width, height, title, style, parent, status = true, close = true, logo = true }
Returns the frame with:
    f.body      the area under the title bar; put tabs and pages in here
    f.title     the title FontString
    f.status    a single-line status FontString (when status is asked for)
    f.titleBar  the strip itself, for anything else that belongs up top
]]
function Lib:Window(name, opts)
    opts = opts or {}
    local style = StyleOf(opts.style)
    local f = CreateFrame("Frame", name, opts.parent or UIParent,
        BackdropTemplateMixin and "BackdropTemplate")
    f:SetSize(opts.width or 720, opts.height or 560)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:SetFrameStrata(opts.strata or "HIGH")
    Paint(f, style.windowBg, style.windowBorder)
    f.icStyle = style

    local barHeight = opts.status ~= false and 46 or 30
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", 0, 0)
    bar:SetHeight(barHeight)
    f.titleBar = bar

    local x = 10
    if opts.logo ~= false then
        local mark = self:Logo(bar, opts.logoSize or 22)
        mark:SetPoint("TOPLEFT", 10, -8)
        f.mark = mark
        x = 38
    end

    f.title = bar:CreateFontString(nil, "OVERLAY", opts.titleFont or style.titleFont)
    f.title:SetPoint("TOPLEFT", x, -10)
    f.title:SetText(opts.title or "")
    f.title:SetWordWrap(false)
    local bone = style.buttonText
    f.title:SetTextColor(bone.r, bone.g, bone.b)

    if opts.status ~= false then
        f.status = bar:CreateFontString(nil, "OVERLAY", style.headerFont)
        f.status:SetPoint("TOPLEFT", x, -30)
        f.status:SetPoint("RIGHT", bar, "RIGHT", -12, 0)
        f.status:SetJustifyH("LEFT")
        f.status:SetWordWrap(false)
    end

    if opts.close ~= false then
        local close = self:Button(bar, "X", 22, 22, { style = style, kind = "danger" })
        close:SetPoint("TOPRIGHT", -8, -8)
        close:SetScript("OnClick", function() f:Hide() end)
        f.closeButton = close
    end

    f.body = CreateFrame("Frame", nil, f)
    f.body:SetPoint("TOPLEFT", 0, -barHeight)
    f.body:SetPoint("BOTTOMRIGHT", 0, 0)

    if name then
        -- A dialog rebuilt on every open would otherwise stack up entries here.
        local listed = false
        for _, n in ipairs(UISpecialFrames) do
            if n == name then listed = true end
        end
        if not listed then tinsert(UISpecialFrames, name) end
    end
    f:Hide()
    return f
end

--------------------------------------------------------------------------------
-- Tab strip
--------------------------------------------------------------------------------

local TabStripMixin = {}

-- Shows which tab is live and tells the caller. Pass a name or an index.
function TabStripMixin:Select(which)
    local index = which
    if type(which) == "string" then
        index = self.indexOf[which]
    end
    if not index then return end
    self.selected = self.names[index]
    for i, b in ipairs(self.buttons) do
        b:SetActive(i == index)
    end
    if self.onSelect then self.onSelect(self.names[index], index) end
end

--[[
opts = { style, names = { "Tab", ... }, top, left, width, height, gap, onSelect(name, index) }
Buttons are laid out left to right; the live one goes gold.
]]
function Lib:TabStrip(parent, opts)
    opts = opts or {}
    local style = StyleOf(opts.style)
    local strip = CreateFrame("Frame", nil, parent)
    strip:SetPoint("TOPLEFT", opts.left or 0, opts.top or 0)
    strip:SetPoint("TOPRIGHT", 0, opts.top or 0)
    strip:SetHeight(opts.height or 24)

    strip.names, strip.buttons, strip.indexOf = {}, {}, {}
    strip.onSelect = opts.onSelect
    for k, v in pairs(TabStripMixin) do strip[k] = v end

    local width = opts.width or 100
    local gap = opts.gap or 4
    for i, name in ipairs(opts.names or {}) do
        local b = self:Button(strip, name, width, opts.height or 24, { style = style })
        b:SetPoint("TOPLEFT", (i - 1) * (width + gap), 0)
        b:SetScript("OnClick", function() strip:Select(i) end)
        strip.names[i] = name
        strip.buttons[i] = b
        strip.indexOf[name] = i
    end
    return strip
end

--------------------------------------------------------------------------------
-- Scrolling list
--------------------------------------------------------------------------------

-- right defaults to -26, the width of the scrollbar, so a header frame given the same
-- inset lines its columns up with the rows underneath.
function Lib:ScrollList(parent, top, bottom, right)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, top or 0)
    scroll:SetPoint("BOTTOMRIGHT", right or -26, bottom or 0)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    return scroll, content
end

--------------------------------------------------------------------------------
-- Toolbar
--------------------------------------------------------------------------------

local ToolbarMixin = {}

-- Appends a widget on the left, after everything already added there.
function ToolbarMixin:Left(widget)
    widget:SetParent(self)
    widget:ClearAllPoints()
    widget:SetPoint("LEFT", self, "LEFT", self.leftX, 0)
    self.leftX = self.leftX + widget:GetWidth() + self.gap
    return widget
end

-- Packs a widget against the right edge, right to left.
function ToolbarMixin:Right(widget)
    widget:SetParent(self)
    widget:ClearAllPoints()
    widget:SetPoint("RIGHT", self, "RIGHT", self.rightX, 0)
    self.rightX = self.rightX - widget:GetWidth() - self.gap
    return widget
end

-- opts = { top, height, style, left, right }. Controls that filter or act on a list go
-- here, above the header row, never over the list itself.
function Lib:Toolbar(parent, opts)
    opts = opts or {}
    local style = StyleOf(opts.style)
    local tb = CreateFrame("Frame", nil, parent)
    tb:SetPoint("TOPLEFT", opts.left or 0, opts.top or 0)
    tb:SetPoint("TOPRIGHT", opts.right or 0, opts.top or 0)
    tb:SetHeight(opts.height or 22)
    tb.height = opts.height or 22
    tb.gap = style.gap
    tb.leftX, tb.rightX = 0, 0
    tb.style = style
    for k, v in pairs(ToolbarMixin) do tb[k] = v end
    return tb
end

--------------------------------------------------------------------------------
-- Table
--------------------------------------------------------------------------------

local TableMixin = {}

local function MakeCell(row, col, x, style)
    if col.type == "custom" and col.make then
        -- The caller builds whatever goes in this column (an arrow cluster, an icon
        -- strip); it is handed the row so its clicks can read row.item.
        return col.make(row, col, x, style)
    end

    if col.type == "texture" then
        local tex = row:CreateTexture(nil, "ARTWORK")
        local size = math.min(col.width, row.rowHeight) - 2
        tex:SetSize(size, size)
        tex:SetPoint("LEFT", row, "LEFT", x + (col.width - size) / 2, 0)
        return tex
    end

    if col.type == "check" then
        local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        cb:SetSize(18, 18)
        cb:SetPoint("LEFT", row, "LEFT", x + (col.width - 18) / 2, 0)
        return cb
    end

    local fs = row:CreateFontString(nil, "OVERLAY", col.font or style.font)
    fs:SetPoint("LEFT", row, "LEFT", x + 2, 0)
    fs:SetWidth(col.width - 4)
    fs:SetJustifyH(col.justify or "LEFT")
    -- A list row is one line. Long values truncate here and live in full in the tooltip.
    fs:SetWordWrap(false)
    if fs.SetMaxLines then fs:SetMaxLines(1) end
    -- The font object's own colour, kept so Render can undo a per-item SetTextColor.
    fs.icBaseColor = { fs:GetTextColor() }
    return fs
end

-- Acquires row i from the pool, building it on first use.
function TableMixin:Row(i)
    local row = self.rows[i]
    if row then return row end

    local style = self.style
    row = CreateFrame("Frame", nil, self.content, BackdropTemplateMixin and "BackdropTemplate")
    row:SetSize(self.width, self.rowHeight)
    row.rowHeight = self.rowHeight
    row:EnableMouse(true)
    Paint(row, (i % 2 == 0) and style.altBg or style.bg)
    row.baseColor = (i % 2 == 0) and style.altBg or style.bg

    row.cells = {}
    row.hit = {}
    for _, col in ipairs(self.columns) do
        row.cells[col.key] = MakeCell(row, col, col.x, style)
        if col.hit then
            -- FontStrings take no scripts, so a hover or clickable cell gets an
            -- invisible button over it. The caller sets its scripts each render.
            local hit = CreateFrame("Button", nil, row)
            hit:SetPoint("LEFT", row, "LEFT", col.x, 0)
            hit:SetSize(col.width, self.rowHeight)
            hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            row.hit[col.key] = hit
        end
    end

    row.buttons = {}
    for _, b in ipairs(self.buttons) do
        local btn = self.makeButton(row, b.label, b.width, self.rowHeight - 2, b)
        btn:SetPoint("LEFT", row, "LEFT", b.x, 0)
        row.buttons[b.key] = btn
    end

    local t = self
    row:SetScript("OnEnter", function(self)
        -- A section heading is not a row you can do anything with, so it does not
        -- light up under the cursor or offer a tooltip.
        if self.isSpan then return end
        if self ~= t.selectedRow then
            self:SetBackdropColor(style.hoverBg.r, style.hoverBg.g, style.hoverBg.b, style.hoverBg.a)
        end
        if t.onEnter and self.item then t.onEnter(self, self.item, t) end
    end)
    row:SetScript("OnLeave", function(self)
        if self.isSpan then return end
        if self ~= t.selectedRow then
            local c = self.tint or self.baseColor
            self:SetBackdropColor(c.r, c.g, c.b, c.a)
        end
        if t.onEnter then GameTooltip:Hide() end
    end)
    if self.onClick then
        row:SetScript("OnMouseUp", function(self, button)
            -- The table goes last so a handler written inside the constructor, where
            -- the caller's own local does not exist yet, can still reach it.
            if self.item and not self.isSpan then t.onClick(self, self.item, button, t) end
        end)
    end

    self.rows[i] = row
    return row
end

-- Turns a row into a full-width label: section titles and separators inside a list.
-- Cells and buttons hide until the next Render puts them back.
function TableMixin:Span(row, text, color)
    if not row.span then
        row.span = row:CreateFontString(nil, "OVERLAY", self.style.headerFont)
        row.span:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.span:SetWidth(self.width - 8)
        row.span:SetJustifyH("LEFT")
        row.span:SetWordWrap(false)
        if row.span.SetMaxLines then row.span:SetMaxLines(1) end
    end
    for _, cell in pairs(row.cells) do
        if cell.Hide then cell:Hide() end
    end
    for _, hit in pairs(row.hit) do hit:Hide() end
    for _, btn in pairs(row.buttons) do btn:Hide() end
    row.isSpan = true
    row.span:SetText(text or "")
    local c = color or self.style.buttonText
    row.span:SetTextColor(c.r, c.g, c.b)
    row.span:Show()
    return row.span
end

-- Colours one row, for a totals or emphasis line. Cleared on the next Render.
function TableMixin:Tint(row, color)
    row.tint = color
    row:SetBackdropColor(color.r, color.g, color.b, color.a or 1)
end

-- Hides every pooled row, then lays out one row per item and calls fill(row, item, i).
function TableMixin:Render(list, fill)
    for _, row in ipairs(self.rows) do row:Hide() end
    self.selectedRow = nil

    for i, item in ipairs(list) do
        local row = self:Row(i)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * self.rowHeight)
        row.item = item
        row.tint = nil
        row.isSpan = nil
        -- Rows come back from the pool as ordinary rows, whatever they were last time:
        -- no span, every built-in cell blank, no tooltip left over from the item that
        -- was here. A "custom" cell and a row button belong to the caller, which sets
        -- their scripts in fill.
        if row.span then row.span:Hide() end
        for _, cell in pairs(row.cells) do
            if cell.Show then cell:Show() end
            if cell.SetText then cell:SetText("") end
            if cell.icBaseColor then cell:SetTextColor(unpack(cell.icBaseColor)) end
            if cell.SetTexture then cell:SetTexture(nil) end
            if cell.SetChecked then cell:SetChecked(false) end
        end
        for _, hit in pairs(row.hit) do
            hit:Show()
            hit:SetScript("OnEnter", nil)
            hit:SetScript("OnLeave", nil)
            hit:SetScript("OnClick", nil)
        end
        for _, btn in pairs(row.buttons) do
            btn:Show()
            btn:Enable()
        end

        if fill then fill(row, item, i) end
        if self.selected ~= nil and item == self.selected then
            self.selectedRow = row
            local c = self.style.selectedBg
            row:SetBackdropColor(c.r, c.g, c.b, c.a)
        elseif not row.tint then
            local c = row.baseColor
            row:SetBackdropColor(c.r, c.g, c.b, c.a)
        end
        row:Show()
    end

    self.content:SetSize(self.width, math.max(1, #list * self.rowHeight))
    self.count = #list
end

-- Marks one item as selected. Call before Render, or on its own to move the highlight.
function TableMixin:SetSelected(item)
    self.selected = item
    for _, row in ipairs(self.rows) do
        if row:IsShown() then
            if row.item == item then
                self.selectedRow = row
                local c = self.style.selectedBg
                row:SetBackdropColor(c.r, c.g, c.b, c.a)
            else
                local c = row.tint or row.baseColor
                row:SetBackdropColor(c.r, c.g, c.b, c.a)
            end
        end
    end
end

-- Sets a text cell, and its colour when one is given.
function TableMixin:Set(row, key, text, color)
    local cell = row.cells[key]
    if cell and cell.SetText then cell:SetText(text or "") end
    if cell and color and cell.SetTextColor then
        cell:SetTextColor(color.r, color.g, color.b)
    end
    return cell
end

-- Moves a table under a new set of columns is not supported: build a second table and
-- hide the first. Column geometry is computed once, here.
--[[
opts = {
    style,                     -- name or table, see Lib:Style
    top, bottom,               -- page coords; or height = N for a fixed-height table
    left, width,               -- default 0 and the parent's width minus the scrollbar
    rowHeight,                 -- defaults to the style's
    makeButton,                -- function(parent, label, w, h, descriptor) -> button
    columns = { { key, label, width | "flex", justify, type, font, hit, make }, ... },
    buttons = { { key, label, width, kind, template }, ... },  -- packed against the right
    onEnter(row, item, t), onClick(row, item, button, t), onHeaderClick(col, t),
}
Returns t with t.header, t.scroll, t.content, t.rows, t.columns.
]]
function Lib:Table(parent, opts)
    opts = opts or {}
    local style = StyleOf(opts.style)
    local left = opts.left or 0
    local top = opts.top or 0
    local width = opts.width
    if not width then
        local pw = parent:GetWidth() or 0
        -- A frame anchored on two sides can report 0 before its first layout.
        if pw < 50 then pw = style.pageWidth or 700 end
        width = pw - 26
    end
    local rowHeight = opts.rowHeight or style.rowHeight

    local t = {
        style = style, width = width, rowHeight = rowHeight,
        columns = {}, buttons = {}, rows = {},
        onEnter = opts.onEnter, onClick = opts.onClick,
        -- Buttons in rows wear the palette unless the caller makes its own.
        makeButton = opts.makeButton or function(row, label, w, h, desc)
            return Lib:Button(row, label, w, h, {
                style = style, kind = desc and desc.kind, template = desc and desc.template,
            })
        end,
    }
    for k, v in pairs(TableMixin) do t[k] = v end

    -- Buttons are packed from the right edge; the columns share what is left, with one
    -- of them allowed to take up the slack.
    local buttonWidth = 0
    for _, b in ipairs(opts.buttons or {}) do buttonWidth = buttonWidth + b.width + 4 end

    local fixed, flexCol = 0, nil
    for _, col in ipairs(opts.columns or {}) do
        if col.width == "flex" then
            assert(not flexCol, "LibICUI: only one flex column allowed")
            flexCol = col
        else
            fixed = fixed + col.width
        end
    end

    local x = 0
    for _, col in ipairs(opts.columns or {}) do
        local c = {
            key = col.key, label = col.label, justify = col.justify,
            type = col.type, font = col.font, x = x, hit = col.hit, make = col.make,
            width = (col == flexCol) and math.max(40, width - fixed - buttonWidth - 4) or col.width,
        }
        x = x + c.width
        t.columns[#t.columns + 1] = c
    end

    local bx = width - buttonWidth
    for _, b in ipairs(opts.buttons or {}) do
        t.buttons[#t.buttons + 1] = {
            key = b.key, label = b.label, width = b.width, x = bx,
            kind = b.kind, template = b.template,
        }
        bx = bx + b.width + 4
    end

    -- Header lives outside the scroll child, so it never scrolls away.
    local header = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    header:SetPoint("TOPLEFT", left, top)
    header:SetSize(width, style.headerHeight)
    Paint(header, style.headerBg)
    header.labels = {}
    for _, col in ipairs(t.columns) do
        local fs = header:CreateFontString(nil, "OVERLAY", style.headerFont)
        fs:SetPoint("LEFT", header, "LEFT", col.x + 2, 0)
        fs:SetWidth(col.width - 4)
        fs:SetJustifyH(col.justify or "LEFT")
        fs:SetWordWrap(false)
        fs:SetText(col.label or "")
        header.labels[col.key] = fs
        if opts.onHeaderClick then
            local hit = CreateFrame("Button", nil, header)
            hit:SetPoint("LEFT", header, "LEFT", col.x, 0)
            hit:SetSize(col.width, style.headerHeight)
            hit:SetScript("OnClick", function() opts.onHeaderClick(col, t) end)
        end
    end
    t.header = header

    -- The scroll frame is exactly as wide as the header and the rows. Its
    -- scrollbar is drawn just outside that width, in the 26px the caller left
    -- for it; making the frame itself wider pushes the bar off the page.
    local scrollTop = top - style.headerHeight
    local parentWidth = parent:GetWidth() or 0
    if parentWidth < 50 then parentWidth = style.pageWidth or 700 end

    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", left, scrollTop)
    if opts.height then
        scroll:SetSize(width, opts.height)
    else
        scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT",
            left + width - parentWidth, opts.bottom or 0)
    end
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    t.scroll, t.content = scroll, content

    return t
end
