--[[
LibICUI-1.0
List and toolbar widgets for the ic-addons guild addons, so every window follows the
"Window layout" rules in CODING_STANDARDS.md by construction: column headers live outside
the scroll child, rows are a fixed height and never wrap, and toolbars sit above the
headers. TBC Anniversary client.

    local UI = LibStub("LibICUI-1.0")

    UI:Age(seconds)                     -> "now", "42s", "7m", "3h", "2d"
    UI:Style(name, style)               register a look, returns it
    UI:ScrollList(parent, top, bottom, right)
    UI:Toolbar(parent, opts)            -> tb  (tb:Left(w), tb:Right(w))
    UI:Table(parent, opts)              -> t   (t:Render(list, fill), t:Row(i), t:SetSelected(item))

A style is a plain table; missing keys fall back to the default one:
    rowHeight, headerHeight, gap, font, headerFont, bg, altBg, headerBg, hoverBg,
    selectedBg, border  (colours are { r, g, b, a })
]]

local MAJOR, MINOR = "LibICUI-1.0", 1
local Lib = LibStub:NewLibrary(MAJOR, MINOR)
if not Lib then return end

Lib.styles = Lib.styles or {}

local BACKDROP = {
    bgFile = "Interface\\Buildings\\White8x8",
    edgeFile = "Interface\\Buildings\\White8x8",
    edgeSize = 1,
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
    rowHeight = 18,
    headerHeight = 18,
    gap = 6,
    font = "GameFontHighlightSmall",
    headerFont = "GameFontDisableSmall",
    bg = { r = 0.082, g = 0.137, b = 0.200, a = 0 },
    altBg = { r = 1, g = 1, b = 1, a = 0.03 },
    headerBg = { r = 0.098, g = 0.149, b = 0.216, a = 1 },
    hoverBg = { r = 0.25, g = 0.25, b = 0.35, a = 0.4 },
    selectedBg = { r = 0.875, g = 0.612, b = 0.200, a = 0.25 },
    border = { r = 0.3, g = 0.3, b = 0.3, a = 0.8 },
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

local function Paint(f, color)
    if not f.SetBackdrop then return f end
    f:SetBackdrop(BACKDROP)
    f:SetBackdropColor(color.r, color.g, color.b, color.a)
    f:SetBackdropBorderColor(0, 0, 0, 0)
    return f
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
    for k, v in pairs(ToolbarMixin) do tb[k] = v end
    return tb
end

--------------------------------------------------------------------------------
-- Table
--------------------------------------------------------------------------------

local TableMixin = {}

local function MakeCell(row, col, x, style)
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
    for _, col in ipairs(self.columns) do
        row.cells[col.key] = MakeCell(row, col, col.x, style)
    end

    row.buttons = {}
    for _, b in ipairs(self.buttons) do
        local btn = self.makeButton(row, b.label, b.width, self.rowHeight - 2)
        btn:SetPoint("LEFT", row, "LEFT", b.x, 0)
        row.buttons[b.key] = btn
    end

    local t = self
    row:SetScript("OnEnter", function(self)
        if self ~= t.selectedRow then
            self:SetBackdropColor(style.hoverBg.r, style.hoverBg.g, style.hoverBg.b, style.hoverBg.a)
        end
        if t.onEnter and self.item then t.onEnter(self, self.item) end
    end)
    row:SetScript("OnLeave", function(self)
        if self ~= t.selectedRow then
            local c = self.baseColor
            self:SetBackdropColor(c.r, c.g, c.b, c.a)
        end
        if t.onEnter then GameTooltip:Hide() end
    end)
    if self.onClick then
        row:SetScript("OnMouseUp", function(self, button)
            if self.item then t.onClick(self, self.item, button) end
        end)
    end

    self.rows[i] = row
    return row
end

-- Hides every pooled row, then lays out one row per item and calls fill(row, item, i).
function TableMixin:Render(list, fill)
    for _, row in ipairs(self.rows) do row:Hide() end
    self.selectedRow = nil

    for i, item in ipairs(list) do
        local row = self:Row(i)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * self.rowHeight)
        row.item = item
        if fill then fill(row, item, i) end
        if self.selected ~= nil and item == self.selected then
            self.selectedRow = row
            local c = self.style.selectedBg
            row:SetBackdropColor(c.r, c.g, c.b, c.a)
        else
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
                local c = row.baseColor
                row:SetBackdropColor(c.r, c.g, c.b, c.a)
            end
        end
    end
end

-- Sets a text cell, honouring the column's own colour when the caller gives none.
function TableMixin:Set(row, key, text)
    local cell = row.cells[key]
    if cell and cell.SetText then cell:SetText(text or "") end
    return cell
end

--[[
opts = {
    style,                     -- name or table, see Lib:Style
    top, bottom,               -- page coords; or height = N for a fixed-height table
    left, width,               -- default 0 and the parent's width minus the scrollbar
    rowHeight,                 -- defaults to the style's
    makeButton,                -- function(parent, label, w, h) -> button, for the button column
    columns = { { key, label, width | "flex", justify, type, font }, ... },
    buttons = { { key, label, width }, ... },   -- packed against the right edge
    onEnter(row, item), onClick(row, item, button), onHeaderClick(col),
}
Returns t with t.header, t.scroll, t.content, t.rows, t.columns.
]]
function Lib:Table(parent, opts)
    opts = opts or {}
    local style = StyleOf(opts.style)
    local left = opts.left or 0
    local top = opts.top or 0
    local width = opts.width or ((parent:GetWidth() or 700) - 26)
    local rowHeight = opts.rowHeight or style.rowHeight

    local t = {
        style = style, width = width, rowHeight = rowHeight,
        columns = {}, buttons = {}, rows = {},
        onEnter = opts.onEnter, onClick = opts.onClick,
        makeButton = opts.makeButton,
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
            type = col.type, font = col.font, x = x,
            width = (col == flexCol) and math.max(40, width - fixed - buttonWidth - 4) or col.width,
        }
        x = x + c.width
        t.columns[#t.columns + 1] = c
    end

    local bx = width - buttonWidth
    for _, b in ipairs(opts.buttons or {}) do
        t.buttons[#t.buttons + 1] = { key = b.key, label = b.label, width = b.width, x = bx }
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
            hit:SetScript("OnClick", function() opts.onHeaderClick(col) end)
        end
    end
    t.header = header

    local scrollTop = top - style.headerHeight
    local scroll, content
    if opts.height then
        scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", left, scrollTop)
        scroll:SetSize(width, opts.height)
        content = CreateFrame("Frame", nil, scroll)
        content:SetSize(1, 1)
        scroll:SetScrollChild(content)
    else
        scroll, content = Lib:ScrollList(parent, scrollTop, opts.bottom or 0,
            left + width + 26 - (parent:GetWidth() or 700))
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", left, scrollTop)
        scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT",
            left + width + 26 - (parent:GetWidth() or 700), opts.bottom or 0)
    end
    t.scroll, t.content = scroll, content

    return t
end
