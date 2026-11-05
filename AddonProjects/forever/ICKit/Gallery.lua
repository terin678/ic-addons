local addonName, ns = ...

--[[
/ickit gallery: one of every widget, on screen, in the current theme.

It exists to be looked at. The cases can say a widget constructs and keeps its state; only
a person can say it looks right, drags properly and takes keys the way an edit box should.
It is also the worked example of the widgets: a movable, resizable panel with a title bar
that drags it, tabs that switch pages, a list with its header above the scroll, a text
area, its place and size saved per character as fractions of the screen and pixels.
]]

local Util = LibStub("LibICUtil-1.0")
local Theme = LibStub("LibICTheme-1.0")
local JSON = LibStub("LibICJSON-1.0")
local W = LibStub("LibICWidgets-1.0")

local Gallery = {}
ns.Gallery = Gallery

local WIDTH, HEIGHT = 340, 300        -- the panel's default and least size, in pixels
local TITLE_H = 24
local PAD = 12
local TABS_TOP = TITLE_H + 6          -- from the panel's top to the tab strip
local PAGE_TOP = TABS_TOP + 22 + 6    -- from the panel's top to every page
local FOOT_H = 28                     -- the footer line and the resize grip below the pages
local TOOLBAR_H = 22                  -- the text page's buttons, above its area
local LIST_ROWS = 200                 -- sample rows, enough to scroll

local frame

local function TitleText()
    local _, name = Theme.Current()
    return "ICKit widgets: " .. name
end

-- One tick box per theme; picking one selects and saves it.
local function ThemeItems()
    local items = { { title = "Theme" } }
    for _, name in ipairs(Theme.Names()) do
        items[#items + 1] = {
            text = name,
            checked = function() return select(2, Theme.Current()) == name end,
            onClick = function() ns.SetTheme(name) end,
        }
    end
    return items
end

-- The first page: the widgets that came first, and the eight raid icons.
local function BuildBasics(page)
    local x = 0
    for _, pair in ipairs({ { "Normal", "normal" }, { "Accent", "accent" }, { "Danger", "danger" } }) do
        local b = W.Button(page, pair[1], 86, 22, {
            kind = pair[2],
            onClick = function() ns.Print(pair[1] .. " button clicked.") end,
        })
        b:SetPoint("TOPLEFT", page, "TOPLEFT", x, 0)
        x = x + 95
    end

    -- A line to tick off: the label dims when the box is ticked
    local line
    local box = W.CheckBox(page, {
        onClick = function(checked) line:SetRole(checked and "done" or "text") end,
    })
    box:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -34)
    line = W.Label(page, "A line you can tick off")
    line:SetPoint("LEFT", box, "RIGHT", 8, 0)
    W.Tooltip(box, function(tip) tip:AddLine("Tick it") end)

    local edit = W.EditBox(page, WIDTH - 2 * PAD, 20, {
        maxBytes = 120,
        placeholder = "Type here and press Enter",
        onEnter = function(text, self)
            ns.Print("you typed: " .. Util.Clean(text, 120))
            self:SetText("")
            self:ClearFocus()
        end,
    })
    edit:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -60)

    local themeButton = W.Button(page, "Theme...", 86, 22, {
        onClick = function(self)
            if not W.Menu(self, ThemeItems()) then ns.Print("this client has no context menu.") end
        end,
    })
    themeButton:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -90)

    local confirm = W.Button(page, "Confirm...", 86, 22, {
        onClick = function()
            W.Confirm("Delete this note?\n\n(Nothing is deleted. This is the gallery.)",
                function() ns.Print("confirmed.") end)
        end,
    })
    confirm:SetPoint("LEFT", themeButton, "RIGHT", 9, 0)

    -- A slider, and a choice picked from a menu
    local slider = W.Slider(page, {
        width = WIDTH - 2 * PAD, min = 0.3334, max = 2, step = 0.01, value = 1,
        format = function(value) return string.format("%d%%", math.floor(value * 100 + 0.5)) end,
        onChange = function(value) ns.Debug("slider at " .. value) end,
    })
    slider:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -120)

    local choice = W.Choice(page, 140, 22, {
        choices = { { 0, "None" }, { 1, "Low" }, { 2, "Medium" }, { 3, "High" } }, value = 2,
        onChange = function(value) ns.Print("choice " .. value .. " picked.") end,
    })
    choice:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -148)

    -- The eight raid icons, star to skull, in a row
    for i = 1, 8 do
        local icon = W.RaidIcon(page, i, 18)
        icon:SetPoint("TOPLEFT", page, "TOPLEFT", (i - 1) * 24, -180)
    end
end

-- Sample rows for the list page, and the sort its header clicks change.
local CLASSES = { "Warrior", "Mage", "Priest", "Rogue", "Hunter", "Druid", "Warlock", "Paladin" }
local sortKey, sortUp = "name", true

local function SampleItems()
    local items = {}
    for i = 1, LIST_ROWS do
        items[i] = { n = i, name = "Unit " .. i, class = CLASSES[(i - 1) % #CLASSES + 1], hp = (i * 37) % 100 }
    end
    return items
end

local function Sorted(items)
    table.sort(items, function(a, b)
        local x, y = a[sortKey], b[sortKey]
        if sortKey == "name" then x, y = a.n, b.n end
        if x == y then return a.n < b.n end
        if sortUp then return x < y end
        return x > y
    end)
    return items
end

local function BuildList(page, w, h)
    local chosen
    local list
    list = W.List(page, w, h, {
        columns = {
            { key = "name", label = "Name" },
            { key = "class", label = "Class", width = 80 },
            { key = "hp", label = "Health", width = 60, justify = "RIGHT", tip = "A made-up number, 0 to 99",
                text = function(item)
                    return item.hp .. "%", item.hp < 30 and "danger" or (item.hp < 60 and "accent" or "text")
                end },
        },
        selected = function(item) return item == chosen end,
        onClick = function(item, mouseButton)
            if mouseButton == "RightButton" then
                ns.Print(item.name .. " right-clicked.")
                return
            end
            chosen = item
            list:Refresh()
        end,
        tooltip = function(tip, item)
            tip:AddLine(item.name)
            tip:AddLine(item.class .. ", " .. item.hp .. "% health", 1, 1, 1)
        end,
        onHeader = function(key)
            if key == sortKey then sortUp = not sortUp else sortKey, sortUp = key, true end
            list:SetItems(Sorted(list:GetItems()))
        end,
        empty = "Nothing to show",
    })
    list:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    list:SetItems(Sorted(SampleItems()))
    return list
end

local function BuildText(page, w, h)
    local area = W.TextArea(page, w, h - TOOLBAR_H - 6, {
        text = JSON.Encode({ name = "Sample", marks = { 8, 7, 1 }, note = "Paste or type here." }) or "",
    })
    area:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(TOOLBAR_H + 6))

    local check = W.Button(page, "Read as JSON", 110, TOOLBAR_H, {
        onClick = function()
            local value, why = JSON.Decode(area:GetText())
            if value == nil then ns.Print("not JSON: " .. why) else ns.Print("that is JSON.") end
        end,
    })
    check:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    local all = W.Button(page, "Select all", 86, TOOLBAR_H, { onClick = function() area:SelectAll() end })
    all:SetPoint("LEFT", check, "RIGHT", 9, 0)
    return area
end

-- What every page holds, laid out for a panel `w` by `h`.
local function PageSize(w, h)
    return w - 2 * PAD, h - PAGE_TOP - FOOT_H
end

local function Build(width, height)
    local p = W.Panel(UIParent, {
        width = width, height = height, movable = true, strata = "MEDIUM",
        onMoved = function(self)
            local fx, fy = W.GetPlace(self)
            if fx and ns.cdb then
                ns.cdb.gallery = ns.cdb.gallery or {}
                ns.cdb.gallery.x, ns.cdb.gallery.y = fx, fy
            end
        end,
    })

    local bar = W.Panel(p, { role = "raised", edge = false, height = TITLE_H })
    bar:SetPoint("TOPLEFT", p, "TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", p, "TOPRIGHT", -1, -1)
    W.DragHandle(bar, p)

    p.title = W.Label(bar, TitleText(), { font = "title", color = "accent" })
    p.title:SetPoint("LEFT", bar, "LEFT", 8, 0)

    local close = W.Button(bar, "x", 20, 18, { kind = "flat", onClick = function() p:Hide() end })
    close:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
    W.Tooltip(close, function(tip) tip:AddLine("Close") end)

    -- Three pages, each filling the room between the tabs and the footer
    local pageW, pageH = PageSize(width, height)
    local pages = {}
    for _, key in ipairs({ "basics", "list", "text" }) do
        local page = CreateFrame("Frame", nil, p)
        page:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -PAGE_TOP)
        page:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -PAD, FOOT_H)
        pages[key] = page
    end
    BuildBasics(pages.basics)
    local list = BuildList(pages.list, pageW, pageH)
    local area = BuildText(pages.text, pageW, pageH)

    local tabs = W.Tabs(p, {
        { key = "basics", label = "Basics", page = pages.basics },
        { key = "list", label = "List", page = pages.list },
        { key = "text", label = "Text", page = pages.text },
        { key = "later", label = "Later" },
    }, {
        width = WIDTH - 2 * PAD, tabWidth = 72,
        selected = ns.cdb and ns.cdb.gallery and ns.cdb.gallery.tab,
        onSelect = function(key)
            if ns.cdb then
                ns.cdb.gallery = ns.cdb.gallery or {}
                ns.cdb.gallery.tab = key
            end
        end,
    })
    tabs:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -TABS_TOP)
    tabs:SetDisabled("later", "A disabled tab, to show how one looks")

    local foot = W.Label(p, "Drag the title bar or the corner. Kept per character.", { font = "small", color = "textDim" })
    foot:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", PAD, 10)
    foot:SetPoint("RIGHT", p, "RIGHT", -24, 0)

    W.Resize(p, {
        minWidth = WIDTH, minHeight = HEIGHT,
        onResize = function(w, h)
            local lw, lh = PageSize(w, h)
            list:Resize(lw, lh)
            area:Resize(lw, lh - TOOLBAR_H - 6)
        end,
        onResized = function(w, h)
            if ns.cdb then
                ns.cdb.gallery = ns.cdb.gallery or {}
                ns.cdb.gallery.w, ns.cdb.gallery.h = w, h
            end
        end,
    })

    Theme.OnChange(function() p.title:SetText(TitleText()) end)
    return p
end

function Gallery.Toggle()
    if not frame then
        local saved = ns.cdb and ns.cdb.gallery or {}
        local w = math.max(WIDTH, tonumber(saved.w) or WIDTH)
        local h = math.max(HEIGHT, tonumber(saved.h) or HEIGHT)
        frame = Build(w, h)
        W.SetPlace(frame, saved.x or 0.36, saved.y or 0.28)
        frame:Show()
        return true
    end
    if frame:IsShown() then frame:Hide() else frame:Show() end
    return frame:IsShown()
end
