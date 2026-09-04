local addonName, ns = ...

ns.UI = ns.UI or {}
local UI = ns.UI

--------------------------------------------------------------------------------
-- The library, wrapped once
--------------------------------------------------------------------------------

--[[
This block is the whole of the addon's contact with LibICUI. Everything below it,
and every other UI file, goes through these wrappers, so the style is passed in
one place instead of at two hundred call sites and swapping it is one edit.

Copy this block into a new addon and change the style name.
]]

local ICUI = LibStub("LibICUI-1.0")
UI.Lib = ICUI

local WIDTH, HEIGHT = 720, 560
local TAB_H, ROW_H = 22, 18
local PAGE_INSET = 10

local STYLE = ICUI:Style("ICTemplate", {
    rowHeight = ROW_H,
    headerHeight = 18,
    font = "GameFontHighlightSmall",
    headerFont = "GameFontDisableSmall",
    pageWidth = WIDTH - PAGE_INSET * 2,
})
UI.Style = STYLE

local function Button(parent, text, w, h, opts)
    opts = opts or {}
    opts.style = STYLE
    return ICUI:Button(parent, text, w, h, opts)
end

local function EditBox(parent, w, h, opts)
    opts = opts or {}
    opts.style = STYLE
    return ICUI:EditBox(parent, w, h, opts)
end

local function TextBox(parent, w, h, opts)
    opts = opts or {}
    opts.style = STYLE
    return ICUI:TextBox(parent, w, h, opts)
end

local function CheckBox(parent, label, opts)
    opts = opts or {}
    opts.style = STYLE
    return ICUI:CheckBox(parent, label, opts)
end

-- A plain label. Not from the library, because a FontString is already the right
-- shape; it is here so no page has to remember which font object to ask for.
local function Label(parent, text, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    fs:SetText(text or "")
    fs:SetJustifyH("LEFT")
    return fs
end

function UI.Toolbar(parent, opts)
    opts = opts or {}
    opts.style = STYLE
    return ICUI:Toolbar(parent, opts)
end

function UI.Table(parent, opts)
    opts = opts or {}
    opts.style = STYLE
    return ICUI:Table(parent, opts)
end

function UI.Age(seconds)
    return ICUI:Age(seconds)
end

UI.Button, UI.EditBox, UI.TextBox, UI.CheckBox, UI.Label = Button, EditBox, TextBox, CheckBox, Label
UI.Skin = function(frame, color, border) return ICUI:Skin(frame, color, border) end
UI.Tooltip = function(widget, builder) return ICUI:Tooltip(widget, builder) end

--------------------------------------------------------------------------------
-- Pages
--------------------------------------------------------------------------------

--[[
Pages register themselves, rather than the window keeping a hardcoded list of tab
names next to a parallel array of build functions next to another parallel array
of refreshers, all three of which have to stay index-synced by hand.

Each UI_*.lua calls this at file scope. build(page) does the one-time construction
and RETURNS the function that redraws it. Deleting a UI_ file and its .toc line
removes exactly one tab and touches nothing else -- which is what lets
scripts/new-addon.ps1 strip the gallery out of a copy.
]]
UI.Pages = {}

function UI.RegisterPage(order, name, build)
    UI.Pages[#UI.Pages + 1] = { order = order, name = name, build = build }
    table.sort(UI.Pages, function(a, b) return a.order < b.order end)
end

function UI.Create()
    if UI.frame then return UI.frame end

    local f = ICUI:Window("ICTemplateFrame", {
        style = STYLE, width = WIDTH, height = HEIGHT,
        title = "ICTemplate " .. ns.VERSION,
    })
    UI.frame = f

    local names = {}
    for i, page in ipairs(UI.Pages) do names[i] = page.name end

    f.tabs = ICUI:TabStrip(f.body, {
        style = STYLE, names = names, top = -6, left = PAGE_INSET,
        width = 100, height = TAB_H,
        onSelect = function(_, index) UI.SelectTab(index) end,
    })

    for i, page in ipairs(UI.Pages) do
        local frame = CreateFrame("Frame", nil, f.body)
        frame:SetPoint("TOPLEFT", PAGE_INSET, -(TAB_H + 12))
        frame:SetPoint("BOTTOMRIGHT", -PAGE_INSET, PAGE_INSET)
        frame:Hide()
        page.frame = frame
        -- A page that fails to build must not take the window down with it.
        local ok, refresh = pcall(page.build, frame)
        if ok then
            page.refresh = refresh
        else
            page.refresh = nil
            ns.Printf("|cffff4444the %s page failed to build:|r %s", page.name, tostring(refresh))
            local err = Label(frame, "This page did not build:\n" .. tostring(refresh))
            err:SetPoint("TOPLEFT", 0, 0)
            err:SetWidth(STYLE.pageWidth - 20)
            err:SetTextColor(1, 0.3, 0.3)
        end
    end

    UI.SelectTab(ns.cdb.ui.tab or 1)
    return f
end

function UI.SelectTab(index)
    if index < 1 or index > #UI.Pages then index = 1 end
    for i, page in ipairs(UI.Pages) do
        if page.frame then page.frame:SetShown(i == index) end
    end
    if UI.frame and UI.frame.tabs then
        for i, b in ipairs(UI.frame.tabs.buttons) do b:SetActive(i == index) end
    end
    -- Saved, not session: coming back to a different tab than you left on reads
    -- as the window having forgotten what you were doing.
    ns.cdb.ui.tab = index
    UI.current = index
    UI.Refresh()
end

-- Opens the window on a named tab. /ictpl demo uses it.
function UI.Show(name)
    local f = UI.Create()
    for i, page in ipairs(UI.Pages) do
        if page.name == name then UI.SelectTab(i) end
    end
    f:Show()
    UI.Refresh()
end

function UI.Toggle()
    local f = UI.Create()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
        UI.Refresh()
    end
end

function UI.Refresh()
    local f = UI.frame
    if not f or not f:IsShown() then return end

    local blocked = ns.Pulse.BlockReason(ns.Pulse.ReadState())
    f.status:SetText(string.format("%s  \194\183  pulse %s  \194\183  %s",
        ns.Enabled() and "|cff44ff44running|r" or "|cffff4444disabled|r",
        ns.Util.OnOff(ns.db.settings.pulse.enabled),
        blocked and ("|cffffcc00" .. blocked .. "|r")
            or (ns.Pulse.pending and "|cffffcc00armed|r" or "ready")))

    local page = UI.Pages[UI.current or 1]
    if page and page.refresh then
        -- A page that fails to draw has to say so. Silently showing nothing is the
        -- failure that gets reported as "the addon lost my data".
        local ok, err = pcall(page.refresh)
        if not ok then ns.Printf("|cffff4444UI error on %s:|r %s", page.name, tostring(err)) end
    end
end

--------------------------------------------------------------------------------
-- About
--------------------------------------------------------------------------------

-- Registered here rather than in its own file because it is the page that reports
-- on the addon itself, and it is the last one either way.
UI.RegisterPage(90, "About", function(page)
    local intro = Label(page,
        "ICTemplate is the worked example. Copy this folder, or run\n"
        .. "|cffffcc00scripts/new-addon.ps1 -Name YourAddon -Slash ya|r, and start deleting.")
    intro:SetPoint("TOPLEFT", 0, -2)
    intro:SetWidth(STYLE.pageWidth - 20)
    intro:SetSpacing(3)

    local bar = UI.Toolbar(page, { top = -36 })
    local test = bar:Left(Button(bar, "Run tests", 90, 22, { kind = "accent" }))
    test:SetScript("OnClick", function()
        ns.Tests.Run()
        UI.Refresh()
    end)
    local probe = bar:Left(Button(bar, "Probe to chat", 100, 22))
    probe:SetScript("OnClick", function() ns.Probe.Run() end)

    local status = Label(page, "", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", 0, -64)
    status:SetWidth(STYLE.pageWidth - 20)
    status:SetSpacing(3)

    -- Probe.Status returns six lines today and the block above ends near -151.
    -- The gap is deliberate slack for the seventh.
    local t = UI.Table(page, {
        top = -176,
        columns = {
            { key = "has", label = "", width = 34 },
            { key = "name", label = "Client API", width = 240 },
            { key = "why", label = "What needs it", width = "flex" },
        },
    })

    return function()
        status:SetText(table.concat(ns.Probe.Status(), "\n"))
        t:Render(ns.Probe.Rows(), function(row, item)
            t:Set(row, "has", item.present and "|cff44ff44yes|r" or "|cffff4444no|r")
            t:Set(row, "name", item.name)
            t:Set(row, "why", item.why)
            if not item.present then t:Tint(row, { r = 0.4, g = 0.1, b = 0.1, a = 0.5 }) end
        end)
    end
end)
