local addonName, ns = ...

ns.Demos = ns.Demos or {}
local Demos = ns.Demos

--[[
The catalogue. Data only: every entry is

    { id, group, title, blurb, source }

and `source` is Lua that Snippet.Compile turns into fn(page, ICUI, ns). The
gallery calls that function to build the live widget and shows the same string
underneath it, so there is one artifact and it cannot drift from itself.

A demo gets a container roughly 500 x 175 as `page`, and must anchor everything
inside it. It must not touch a secure frame or the Blizzard dropdown system: a
loadstring chunk is tainted, and taint spreading into those is somebody else's
broken evening.
]]

-- Fixture rows for the table demos, so nothing here needs game state and every
-- demo works at level one in Elwynn.
Demos.rows = {
    { name = "Adamantite Frame",  kind = "Trade Goods", stock = 12, price = 8400,
      icon = "Interface\\Icons\\INV_Ingot_Adamantite", ready = true },
    { name = "Primal Might",      kind = "Trade Goods", stock = 3,  price = 214000,
      icon = "Interface\\Icons\\Spell_Fire_Fire",      ready = false },
    { name = "Felsteel Gloves",   kind = "Armor",       stock = 1,  price = 380000,
      icon = "Interface\\Icons\\INV_Gauntlets_29",     ready = true },
    { name = "Netherweave Cloth", kind = "Trade Goods", stock = 240, price = 1200,
      icon = "Interface\\Icons\\INV_Fabric_Netherweave", ready = true },
    { name = "Khorium Scope",     kind = "Trade Goods", stock = 0,  price = 96000,
      icon = "Interface\\Icons\\INV_Misc_Spyglass_02",  ready = false },
}

Demos.list = {

    ----------------------------------------------------------------- Basics

    { id = "style", group = "Basics", title = "Style and palette",
      blurb = "Register one style per addon and pass it to everything. Missing keys "
           .. "fall back to the default, so a style only names what it changes.",
      source = [[
-- Registered once, at file scope in the real addon, and then handed to every
-- constructor as opts.style. The name is enough after the first call.
local STYLE = ICUI:Style("ICTemplateDemo", {
    rowHeight = 18,
    headerHeight = 18,
    font = "GameFontHighlightSmall",
    headerFont = "GameFontDisableSmall",
    pageWidth = 660,
})

local x = 0
for _, name in ipairs({ "ink", "panel", "gold", "flame", "bone" }) do
    local c = ICUI.Brand[name]
    local swatch = ICUI:Panel(page, { style = STYLE, color = c })
    swatch:SetSize(70, 40)
    swatch:SetPoint("TOPLEFT", x, -4)

    local label = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", x, -48)
    label:SetText(ICUI:Hex(c) .. name .. "|r")
    x = x + 78
end

local note = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
note:SetPoint("TOPLEFT", 0, -70)
note:SetText("theme = false in a style gives plain Blizzard controls instead, "
    .. "without touching a single call site.")
]] },

    { id = "panel", group = "Basics", title = "Panel and Skin",
      blurb = "Panel makes a raised area; Skin paints a frame you already have. "
           .. "Never paint one with literal colour values.",
      source = [[
local panel = ICUI:Panel(page)
panel:SetSize(240, 60)
panel:SetPoint("TOPLEFT", 0, -4)

local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
label:SetPoint("TOPLEFT", 8, -8)
label:SetText("ICUI:Panel(parent, opts) -- a detail area or a footer")

-- Skin takes any frame, including one Blizzard made.
local plain = CreateFrame("Frame", nil, page, BackdropTemplateMixin and "BackdropTemplate")
plain:SetSize(240, 60)
plain:SetPoint("TOPLEFT", 252, -4)
ICUI:Skin(plain, ICUI.Brand.flame, ICUI.Brand.gold)

local other = plain:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
other:SetPoint("TOPLEFT", 8, -8)
other:SetText("ICUI:Skin(frame, color, border)")
]] },

    { id = "age", group = "Basics", title = "Age and Freshness",
      blurb = "Lists show relative age, never a timestamp. Age answers how long ago; "
           .. "the addon's own Freshness also answers whether that is a problem.",
      source = [[
local now = ns.Now()
local samples = { 0, 42, 400, 9000, 200000 }

local y = -4
for _, seconds in ipairs(samples) do
    local label, color = ns.Util.Freshness(now - seconds, now, 3600)
    local fs = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", 0, y)
    fs:SetText(string.format("%7ds ago   ICUI:Age -> %-5s   Freshness -> %s",
        seconds, ICUI:Age(seconds), label))
    fs:SetTextColor(color.r, color.g, color.b)
    y = y - 16
end

local never = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
never:SetPoint("TOPLEFT", 0, y)
never:SetText("nothing stored   ICUI:Age -> -       Freshness -> "
    .. (ns.Util.Freshness(nil, now, 3600)))
]] },

    ---------------------------------------------------------------- Controls

    { id = "button", group = "Controls", title = "Button",
      blurb = "Three kinds, and SetActive for a toggle that shows its own state in "
           .. "its label and its colour.",
      source = [[
local b = ICUI:Button(page, "Normal", 90, 22)
b:SetPoint("TOPLEFT", 0, -4)

local accent = ICUI:Button(page, "Accent", 90, 22, { kind = "accent" })
accent:SetPoint("LEFT", b, "RIGHT", 6, 0)

local danger = ICUI:Button(page, "Danger", 90, 22, { kind = "danger" })
danger:SetPoint("LEFT", accent, "RIGHT", 6, 0)

-- A button that toggles something says which way it is pointing. Both the label
-- and the colour, because one of them is the one the reader happens to look at.
local toggle = ICUI:Button(page, "Capture: off", 110, 22)
toggle:SetPoint("LEFT", danger, "RIGHT", 6, 0)
toggle.on = false
toggle:SetScript("OnClick", function(self)
    self.on = not self.on
    self:SetActive(self.on)
    self:SetText("Capture: " .. (self.on and "on" or "off"))
end)

local off = ICUI:Button(page, "Disabled", 90, 22)
off:SetPoint("TOPLEFT", 0, -32)
off:Disable()
]] },

    { id = "editbox", group = "Controls", title = "EditBox",
      blurb = "One line, in the palette. Escape clears focus; Enter is yours to wire.",
      source = [[
local label = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
label:SetPoint("TOPLEFT", 0, -8)
label:SetText("Search")

local box = ICUI:EditBox(page, 220, 22)
box:SetPoint("TOPLEFT", 52, -4)

local echo = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
echo:SetPoint("TOPLEFT", 0, -34)
echo:SetText("type something")

box:SetScript("OnTextChanged", function(self)
    local text = self:GetText()
    echo:SetText(text == "" and "type something"
        or string.format("%d characters, normalized: %q", #text, ns.Util.Normalize(text)))
end)
box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
]] },

    { id = "textbox", group = "Controls", title = "TextBox",
      blurb = "Multi-line and scrolling. readOnly still selects, which is the only way "
           .. "to copy anything out: this client has no clipboard API.",
      source = [[
local box = ICUI:TextBox(page, 420, 90, { maxBytes = 255 })
box:SetPoint("TOPLEFT", 0, -4)
box:SetText("A message that runs past one line.\n\n"
    .. "maxBytes stops it at 255 here, which is what SendChatMessage accepts.")

local count = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
count:SetPoint("TOPLEFT", 0, -100)

local function Recount(text)
    count:SetText(string.format("%d / 255 bytes", #(text or "")))
end
Recount(box:GetText())
box.edit:SetScript("OnTextChanged", function(self) Recount(self:GetText()) end)

local copy = ICUI:Button(page, "Copy", 70, 22)
copy:SetPoint("TOPLEFT", 430, -4)
copy:SetScript("OnClick", function() box:SelectAllAndFocus() end)
ICUI:Tooltip(copy, function()
    GameTooltip:AddLine("Copy", 1, 1, 1)
    GameTooltip:AddLine("Selects the text so you can press Ctrl+C. No addon can "
        .. "reach the clipboard on this client.", 0.8, 0.8, 0.8, true)
end)
]] },

    { id = "checkbox", group = "Controls", title = "CheckBox",
      blurb = "Blizzard's check button with a palette label. cb.label is the FontString.",
      source = [[
local cb = ICUI:CheckBox(page, "Pause in combat")
cb:SetPoint("TOPLEFT", 0, -4)
cb:SetChecked(true)

local left = ICUI:CheckBox(page, "Label on the left", { labelSide = "LEFT" })
left:SetPoint("TOPLEFT", 260, -4)

local state = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
state:SetPoint("TOPLEFT", 0, -32)
state:SetText("Pause in combat is " .. ns.Util.OnOff(cb:GetChecked()))

cb:SetScript("OnClick", function(self)
    state:SetText("Pause in combat is " .. ns.Util.OnOff(self:GetChecked()))
end)
]] },

    { id = "tooltip", group = "Controls", title = "Tooltip",
      blurb = "builder(widget) adds the lines; owner, Show and Hide are handled. "
           .. "Passing nil takes it off, which is what a pooled row needs.",
      source = [[
local b = ICUI:Button(page, "Hover me", 100, 22)
b:SetPoint("TOPLEFT", 0, -4)
ICUI:Tooltip(b, function()
    GameTooltip:AddLine("A tooltip", 1, 1, 1)
    GameTooltip:AddLine("The long version of a truncated cell goes here, which is "
        .. "why list rows are allowed to be one line.", 0.8, 0.8, 0.8, true)
end)

local off = ICUI:Button(page, "Take it off", 100, 22)
off:SetPoint("LEFT", b, "RIGHT", 6, 0)
off:SetScript("OnClick", function()
    ICUI:Tooltip(b, nil)
    off:SetText("Gone")
end)
]] },

    ------------------------------------------------------------------ Layout

    { id = "window", group = "Layout", title = "Window",
      blurb = "Movable, escapable, wearing the guild mark, and registered in "
           .. "UISpecialFrames. f.body is where tabs and pages go.",
      source = [[
local open = ICUI:Button(page, "Open a window", 130, 22, { kind = "accent" })
open:SetPoint("TOPLEFT", 0, -4)

open:SetScript("OnClick", function()
    -- Named, because UISpecialFrames is a list of names: that is what makes
    -- Escape close it. Built once and reused, or the list grows on every click.
    if not ns.demoWindow then
        ns.demoWindow = ICUI:Window("ICTemplateDemoWindow", {
            width = 320, height = 180, title = "A window",
        })
        ns.demoWindow.status:SetText("f.status is this line")

        local hello = ns.demoWindow.body:CreateFontString(nil, "OVERLAY",
            "GameFontHighlightSmall")
        hello:SetPoint("TOPLEFT", 12, -12)
        hello:SetText("Drag the title bar. Escape closes it.")
    end
    ns.demoWindow:Show()
end)
]] },

    { id = "tabstrip", group = "Layout", title = "TabStrip",
      blurb = "A row of tabs; the live one goes gold. onSelect is told the name and "
           .. "the index, and Select can be called with either.",
      source = [[
local shown = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
shown:SetPoint("TOPLEFT", 0, -36)

local strip = ICUI:TabStrip(page, {
    names = { "First", "Second", "Third" },
    top = -4, width = 90,
    onSelect = function(name, index)
        shown:SetText(string.format("page %d: %s", index, name))
    end,
})
strip:Select(1)

local jump = ICUI:Button(page, "Select by name", 120, 22)
jump:SetPoint("TOPLEFT", 0, -60)
jump:SetScript("OnClick", function() strip:Select("Third") end)
]] },

    { id = "toolbar", group = "Layout", title = "Toolbar",
      blurb = "Controls that act on a list sit above its header, never over the list. "
           .. "Left appends; Right packs from the right edge.",
      source = [[
local bar = ICUI:Toolbar(page, { top = -4 })

bar:Left(ICUI:Button(bar, "Add", 60, 22, { kind = "accent" }))
bar:Left(ICUI:Button(bar, "Remove", 70, 22, { kind = "danger" }))

local filters = {}
for _, name in ipairs({ "All", "Ready", "Waiting" }) do
    local b = ICUI:Button(bar, name, 60, 22)
    b:SetScript("OnClick", function()
        for _, other in ipairs(filters) do other:SetActive(other == b) end
    end)
    filters[#filters + 1] = bar:Left(b)
end
filters[1]:SetActive(true)

-- The count line belongs here too, so a filtered list can say what it is holding
-- back without stealing a pixel from the rows.
local hint = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hint:SetText("|cff8888885 of 5|r")
bar:Right(hint)
]] },

    { id = "scrolllist", group = "Layout", title = "ScrollList",
      blurb = "The plain scroll frame, for content that is not a table. Its scrollbar "
           .. "draws in the 26px on the right that the caller leaves for it.",
      source = [[
local scroll, content = ICUI:ScrollList(page, -4, -8)
content:SetWidth(450)

local y = 0
for i = 1, 30 do
    local fs = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", 4, -y)
    fs:SetText(string.format("line %d -- anything that is not a list of records", i))
    y = y + 14
end
content:SetHeight(y)
]] },

    ------------------------------------------------------------------- Table

    { id = "table-basic", group = "Table", title = "Table: the shape of it",
      blurb = "A header outside the scroll child, fixed-height single-line rows, and a "
           .. "pool that Render reuses. This is how every list in the guild addons is built.",
      source = [[
-- Declared on its own line first. Writing `local t = ICUI:Table(page, { onClick =
-- function() t:... end })` reads a nil global, because t does not exist yet while
-- the constructor argument is being built.
local t
t = ICUI:Table(page, {
    top = -4, height = 110, width = 420,
    columns = {
        { key = "name",  label = "Item",  width = 190 },
        { key = "stock", label = "Stock", width = 60, justify = "RIGHT" },
        { key = "price", label = "Price", width = 120, justify = "RIGHT" },
    },
})

t:Render(ns.Demos.rows, function(row, item)
    t:Set(row, "name", item.name)
    t:Set(row, "stock", tostring(item.stock))
    t:Set(row, "price", GetCoinTextureString(item.price))
end)
]] },

    { id = "table-flex", group = "Table", title = "Table: the flex column",
      blurb = "Exactly one column may take the slack, and the library asserts if two do. "
           .. "It is the one whose content has no natural width.",
      source = [[
local t = ICUI:Table(page, {
    top = -4, height = 110, width = 470,
    columns = {
        { key = "stock", label = "Stock", width = 50, justify = "RIGHT" },
        { key = "kind",  label = "Kind",  width = 90 },
        -- Whatever is left over, and never less than 40.
        { key = "name",  label = "Item",  width = "flex" },
    },
})

t:Render(ns.Demos.rows, function(row, item)
    t:Set(row, "stock", tostring(item.stock))
    t:Set(row, "kind", item.kind)
    t:Set(row, "name", item.name)
end)
]] },

    { id = "table-texture", group = "Table", title = "Table: icons and colours",
      blurb = "A texture column takes a path; Set with a colour tints one cell. Green "
           .. "good, red bad, amber derived, grey missing -- one meaning per colour.",
      source = [[
local GOOD = { r = 0.3, g = 1, b = 0.3 }
local BAD  = { r = 1, g = 0.35, b = 0.35 }
local GREY = { r = 0.55, g = 0.55, b = 0.55 }

local t = ICUI:Table(page, {
    top = -4, height = 110, width = 460, rowHeight = 20,
    columns = {
        { key = "icon",  label = "",      width = 24, type = "texture" },
        { key = "name",  label = "Item",  width = "flex" },
        { key = "stock", label = "Stock", width = 60, justify = "RIGHT" },
    },
})

t:Render(ns.Demos.rows, function(row, item)
    row.cells.icon:SetTexture(item.icon)
    t:Set(row, "name", item.name)
    -- Nothing in stock is missing, not bad: grey, not red.
    local color = GREY
    if item.stock > 5 then color = GOOD elseif item.stock > 0 then color = BAD end
    t:Set(row, "stock", tostring(item.stock), color)
end)
]] },

    { id = "table-check", group = "Table", title = "Table: check cells",
      blurb = "A check column is a real CheckButton. Render clears its script every "
           .. "time, so a pooled row can never fire the previous item's handler.",
      source = [[
local t = ICUI:Table(page, {
    top = -4, height = 110, width = 420,
    columns = {
        { key = "ready", label = "",     width = 30, type = "check" },
        { key = "name",  label = "Item", width = "flex" },
    },
})

local said = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
said:SetPoint("BOTTOMLEFT", 0, 0)

t:Render(ns.Demos.rows, function(row, item)
    row.cells.ready:SetChecked(item.ready)
    row.cells.ready:SetScript("OnClick", function(self)
        item.ready = self:GetChecked() and true or false
        said:SetText(item.name .. " is now " .. ns.Util.OnOff(item.ready))
    end)
    t:Set(row, "name", item.name)
end)
]] },

    { id = "table-buttons", group = "Table", title = "Table: row buttons",
      blurb = "Buttons pack against the right edge and the columns share what is left. "
           .. "Set the script on every render: the row came from a pool.",
      source = [[
local t = ICUI:Table(page, {
    top = -4, height = 110, width = 470,
    columns = {
        { key = "name",  label = "Item",  width = "flex" },
        { key = "stock", label = "Stock", width = 60, justify = "RIGHT" },
    },
    buttons = {
        { key = "take", label = "Take", width = 60 },
        { key = "drop", label = "Drop", width = 60, kind = "danger" },
    },
})

local said = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
said:SetPoint("BOTTOMLEFT", 0, 0)

t:Render(ns.Demos.rows, function(row, item)
    t:Set(row, "name", item.name)
    t:Set(row, "stock", tostring(item.stock))

    row.buttons.take:SetScript("OnClick", function()
        said:SetText("took " .. item.name)
    end)
    -- A button that cannot do anything says so rather than doing nothing.
    row.buttons.drop:SetEnabled(item.stock > 0)
    row.buttons.drop:SetScript("OnClick", function()
        said:SetText("dropped " .. item.name)
    end)
end)
]] },

    { id = "table-hit", group = "Table", title = "Table: a clickable cell",
      blurb = "FontStrings take no scripts, so hit = true puts an invisible Button over "
           .. "the cell. row.hit[key] is yours, and Render clears it first.",
      source = [[
local t = ICUI:Table(page, {
    top = -4, height = 110, width = 420,
    columns = {
        { key = "name",  label = "Item (hover the name)", width = "flex", hit = true },
        { key = "stock", label = "Stock", width = 60, justify = "RIGHT" },
    },
})

t:Render(ns.Demos.rows, function(row, item)
    t:Set(row, "name", item.name)
    t:Set(row, "stock", tostring(item.stock))

    ICUI:Tooltip(row.hit.name, function()
        GameTooltip:AddLine(item.name, 1, 1, 1)
        GameTooltip:AddLine(item.kind, 0.8, 0.8, 0.8)
        GameTooltip:AddLine(GetCoinTextureString(item.price))
    end)
end)
]] },

    { id = "table-span", group = "Table", title = "Table: section rows",
      blurb = "Span turns a row into a full-width heading and hides its cells. A span is "
           .. "not selectable and does not light up: there is nothing to click.",
      source = [[
local t = ICUI:Table(page, {
    top = -4, height = 130, width = 420,
    columns = {
        { key = "name",  label = "Item",  width = "flex" },
        { key = "stock", label = "Stock", width = 60, justify = "RIGHT" },
    },
})

-- Group the fixtures by kind, heading each group. Build the list first: Render
-- walks it once and the pool is sized from it.
local list, seen = {}, {}
for _, item in ipairs(ns.Demos.rows) do
    if not seen[item.kind] then
        seen[item.kind] = true
        list[#list + 1] = { span = item.kind }
        for _, other in ipairs(ns.Demos.rows) do
            if other.kind == item.kind then list[#list + 1] = other end
        end
    end
end

t:Render(list, function(row, item)
    if item.span then
        t:Span(row, item.span)
        return
    end
    t:Set(row, "name", item.name)
    t:Set(row, "stock", tostring(item.stock))
end)
]] },

    { id = "table-tint", group = "Table", title = "Table: tint and totals",
      blurb = "Tint colours one row and Render clears it again. A totals line belongs "
           .. "inside the list, not in a footer strip sharing space with it.",
      source = [[
local t = ICUI:Table(page, {
    top = -4, height = 130, width = 420,
    columns = {
        { key = "name",  label = "Item",  width = "flex" },
        { key = "price", label = "Price", width = 120, justify = "RIGHT" },
    },
})

local list, total = {}, 0
for _, item in ipairs(ns.Demos.rows) do
    list[#list + 1] = item
    total = total + item.price * item.stock
end
list[#list + 1] = { total = total }

t:Render(list, function(row, item)
    if item.total then
        t:Tint(row, ICUI.Brand.gold)
        t:Set(row, "name", "Everything on hand")
        t:Set(row, "price", GetCoinTextureString(item.total))
        return
    end
    t:Set(row, "name", item.name)
    t:Set(row, "price", GetCoinTextureString(item.price))
end)
]] },

    { id = "table-selected", group = "Table", title = "Table: selection",
      blurb = "onClick gets the table as its last argument, so a handler written inside "
           .. "the constructor can still reach it. SetSelected survives a Render.",
      source = [[
local detail = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
detail:SetPoint("BOTTOMLEFT", 0, 0)
detail:SetText("pick a row")

local t = ICUI:Table(page, {
    top = -4, height = 110, width = 420,
    columns = {
        { key = "name", label = "Item", width = "flex" },
        { key = "kind", label = "Kind", width = 100 },
    },
    -- Fourth argument is the table itself. This is why it is there.
    onClick = function(row, item, button, tbl)
        tbl:SetSelected(item)
        detail:SetText(string.format("%s -- %s, %d on hand",
            item.name, item.kind, item.stock))
    end,
})

t:Render(ns.Demos.rows, function(row, item)
    t:Set(row, "name", item.name)
    t:Set(row, "kind", item.kind)
end)
]] },

    { id = "table-headersort", group = "Table", title = "Table: sorting",
      blurb = "onHeaderClick gets the column. Sort a copy, mark the live column in its "
           .. "label, and redraw -- the header is a frame, so it takes clicks.",
      source = [[
local sortKey, descending = "name", false

-- Both are declared before the constructor: `t` because a callback written inside
-- the call cannot see the local it is being assigned to, and `Redraw` because the
-- callback calls it. Assigning to an undeclared name here would make a global.
local t, Redraw

t = ICUI:Table(page, {
    top = -4, height = 110, width = 460,
    columns = {
        { key = "name",  label = "Item",  width = "flex" },
        { key = "stock", label = "Stock", width = 60, justify = "RIGHT" },
        { key = "price", label = "Price", width = 110, justify = "RIGHT" },
    },
    onHeaderClick = function(col)
        -- Clicking the live column reverses it; clicking another moves to it,
        -- ascending, because that is the order a reader expects to land in.
        if sortKey == col.key then
            descending = not descending
        else
            sortKey, descending = col.key, false
        end
        Redraw()
    end,
})

Redraw = function()
    local list = {}
    for _, item in ipairs(ns.Demos.rows) do list[#list + 1] = item end
    table.sort(list, function(a, b)
        local x, y = a[sortKey], b[sortKey]
        if x == y then return a.name < b.name end
        if descending then return x > y end
        return x < y
    end)

    for _, col in ipairs(t.columns) do
        local label = col.label
        if col.key == sortKey then label = label .. (descending and " v" or " ^") end
        t.header.labels[col.key]:SetText(label)
    end

    t:Render(list, function(row, item)
        t:Set(row, "name", item.name)
        t:Set(row, "stock", tostring(item.stock))
        t:Set(row, "price", GetCoinTextureString(item.price))
    end)
end

Redraw()
]] },

    { id = "table-custom", group = "Table", title = "Table: a custom cell",
      blurb = "type = \"custom\" hands you make(row, col, x, style) and whatever it "
           .. "returns becomes row.cells[key]. Here: a bar drawn from a texture.",
      source = [[
local t = ICUI:Table(page, {
    top = -4, height = 110, width = 460,
    columns = {
        { key = "name", label = "Item", width = 180 },
        { key = "bar",  label = "Stock", width = "flex",
          type = "custom",
          make = function(row, col, x, style)
              -- Whatever comes back is row.cells.bar. Render cannot reset a shape
              -- it does not understand, so a custom cell resets itself below.
              local tex = row:CreateTexture(nil, "ARTWORK")
              tex:SetTexture("Interface\\Buttons\\WHITE8x8")
              tex:SetPoint("LEFT", row, "LEFT", x + 2, 0)
              tex:SetHeight(row.rowHeight - 6)
              tex.maxWidth = col.width - 6
              return tex
          end },
    },
})

local most = 0
for _, item in ipairs(ns.Demos.rows) do most = math.max(most, item.stock) end

t:Render(ns.Demos.rows, function(row, item)
    t:Set(row, "name", item.name)
    local bar = row.cells.bar
    local share = most > 0 and (item.stock / most) or 0
    bar:SetWidth(math.max(1, bar.maxWidth * share))
    local c = item.stock > 0 and ICUI.Brand.gold or ICUI.Brand.flame
    bar:SetColorTexture(c.r, c.g, c.b, 0.85)
end)
]] },
}

-- Pure. The demo with this id, or nil.
function Demos.ById(id)
    for _, demo in ipairs(Demos.list) do
        if demo.id == id then return demo end
    end
    return nil
end

-- Pure. Groups in the order they first appear, each with its demos in list order,
-- so the index reads the same on every open.
function Demos.Groups()
    local out, byName = {}, {}
    for _, demo in ipairs(Demos.list) do
        local group = byName[demo.group]
        if not group then
            group = { name = demo.group, demos = {} }
            byName[demo.group] = group
            out[#out + 1] = group
        end
        group.demos[#group.demos + 1] = demo
    end
    return out
end

-- Compiles every demo and caches the function on it. A demo that no longer builds
-- is a log line at load, not a blank pane the next time somebody clicks it.
-- Returns ok, failed.
function Demos.Verify()
    local ok, failed = 0, 0
    for _, demo in ipairs(Demos.list) do
        local fn, err = ns.Snippet.Compile(demo.source, demo.id)
        demo.fn, demo.err = fn, err
        if fn then
            ok = ok + 1
        else
            failed = failed + 1
            ns.Log.Add("err", "Demos", "demo " .. demo.id .. " does not compile", err)
        end
    end
    return ok, failed
end
