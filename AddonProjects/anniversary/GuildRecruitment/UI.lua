local addonName, ns = ...

ns.UI = ns.UI or {}
local UI = ns.UI

--------------------------------------------------------------------------------
-- The library, wrapped once
--------------------------------------------------------------------------------

--[[
This block is the whole of the addon's contact with LibICUI. Everything below it,
and every other UI file, goes through these wrappers, so the style is set in one
place instead of at every call site.
]]

local ICUI = LibStub("LibICUI-1.0")
UI.Lib = ICUI

local WIDTH, HEIGHT = 720, 560
local TAB_H, ROW_H = 22, 18
local PAGE_INSET = 10

local STYLE = ICUI:Style("GuildRecruitment", {
    rowHeight = ROW_H,
    headerHeight = 18,
    font = "GameFontHighlightSmall",
    headerFont = "GameFontDisableSmall",
    pageWidth = WIDTH - PAGE_INSET * 2,
})
UI.Style = STYLE
UI.PAGE_W = WIDTH - PAGE_INSET * 2

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

function UI.Panel(parent, opts)
    opts = opts or {}
    opts.style = STYLE
    return ICUI:Panel(parent, opts)
end

function UI.Age(seconds)
    return ICUI:Age(seconds)
end

UI.Button, UI.EditBox, UI.TextBox, UI.CheckBox, UI.Label = Button, EditBox, TextBox, CheckBox, Label
UI.Tooltip = function(widget, builder) return ICUI:Tooltip(widget, builder) end

-- EditBox has Enable and Disable on every client this repo targets; SetEnabled on
-- one is not something to bet a page on.
function UI.SetEditable(box, on)
    local edit = box.edit or box
    if on then
        if edit.Enable then edit:Enable() end
    else
        if edit.Disable then edit:Disable() end
    end
    return box
end

--[[
Half this addon's controls belong to raid leaders and the rest do not. A greyed
button with nothing to say reads as a broken addon, so this greys it AND hangs
the reason off it.

Anything with a label of its own -- a check box -- gets that greyed too, because
a disabled control whose text is still bright does not look disabled.
]]
function UI.Gate(widget, allowed, reason)
    if widget.SetEnabled then widget:SetEnabled(allowed and true or false) end
    if widget.label then
        local c = allowed and STYLE.buttonText or STYLE.disabledText
        widget.label:SetTextColor(c.r or c[1], c.g or c[2], c.b or c[3])
    end
    UI.Tooltip(widget, (not allowed) and function()
        GameTooltip:AddLine("Not yours to change", 1, 1, 1)
        GameTooltip:AddLine(reason or "Ask a raid leader.", 0.8, 0.8, 0.8, true)
    end or nil)
    return widget
end

--------------------------------------------------------------------------------
-- Pages
--------------------------------------------------------------------------------

UI.Pages = {}

function UI.RegisterPage(order, name, build)
    UI.Pages[#UI.Pages + 1] = { order = order, name = name, build = build }
    table.sort(UI.Pages, function(a, b) return a.order < b.order end)
end

function UI.Create()
    if UI.frame then return UI.frame end

    local f = ICUI:Window("GuildRecruitmentFrame", {
        style = STYLE, width = WIDTH, height = HEIGHT,
        title = "Guild Recruitment " .. ns.VERSION,
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
        local ok, refresh = pcall(page.build, frame)
        if ok then
            page.refresh = refresh
        else
            page.refresh = nil
            ns.Printf("|cffff4444the %s page failed to build:|r %s", page.name, tostring(refresh))
            local err = Label(frame, "This page did not build:\n" .. tostring(refresh))
            err:SetPoint("TOPLEFT", 0, 0)
            err:SetWidth(UI.PAGE_W - 20)
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
    ns.cdb.ui.tab = index
    UI.current = index
    UI.Refresh()
end

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

    local now = ns.Now()
    local sync = ns.Comm.Status()
    f.status:SetText(string.format("%s  \194\183  %s  \194\183  sync %s  \194\183  %s",
        ns.Enabled() and "|cff44ff44running|r" or "|cffff4444disabled|r",
        ns.Doc.Summary(ns.db.doc, now),
        sync.available and "|cff44ff44on|r" or "|cffff4444unavailable|r",
        ns.Roster.ICanAuthor() and "|cff44ff44you may edit the message|r"
            or "|cff888888you can send it, not change it|r"))

    local page = UI.Pages[UI.current or 1]
    if page and page.refresh then
        -- A page that fails to draw has to say so. Silently showing nothing is the
        -- failure that gets reported as "the addon lost my data".
        local ok, err = pcall(page.refresh)
        if not ok then ns.Printf("|cffff4444UI error on %s:|r %s", page.name, tostring(err)) end
    end
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

UI.RegisterPage(90, "Settings", function(page)
    local y = -4

    local function Section(text)
        local fs = Label(page, text, "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", 0, y)
        y = y - 20
        return fs
    end

    local function Row(text)
        local fs = Label(page, text, "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", 0, y)
        fs:SetWidth(360)
        return fs
    end

    Section("Who may do what")

    local authorLabel = Row("")
    local authorDown = Button(page, "-", 24, 20)
    authorDown:SetPoint("TOPLEFT", 380, y + 2)
    local authorUp = Button(page, "+", 24, 20)
    authorUp:SetPoint("TOPLEFT", 408, y + 2)
    y = y - 26

    local barkLabel = Row("")
    local barkDown = Button(page, "-", 24, 20)
    barkDown:SetPoint("TOPLEFT", 380, y + 2)
    local barkUp = Button(page, "+", 24, 20)
    barkUp:SetPoint("TOPLEFT", 408, y + 2)
    y = y - 26

    local rankNote = Label(page, "The guild window numbers ranks from 1; the game reports "
        .. "them from 0, and this uses the game's numbering, so the guild master is 0 here "
        .. "and 1 there. A lower number is a higher rank, and each name below is read off "
        .. "your own roster.
Everyone sets this for themselves, so an officer whose copy "
        .. "disagrees with yours will accept messages yours ignores. The Officers tab shows "
        .. "who is out of step.",
        "GameFontDisableSmall")
    rankNote:SetPoint("TOPLEFT", 0, y)
    rankNote:SetWidth(UI.PAGE_W - 20)
    rankNote:SetSpacing(2)
    y = y - 58

    local function Bump(key, delta)
        return function()
            ns.db.settings[key] = math.max(0, math.min(20, ns.db.settings[key] + delta))
            UI.Refresh()
        end
    end
    authorDown:SetScript("OnClick", Bump("authorRankIndex", -1))
    authorUp:SetScript("OnClick", Bump("authorRankIndex", 1))
    barkDown:SetScript("OnClick", Bump("barkRankIndex", -1))
    barkUp:SetScript("OnClick", Bump("barkRankIndex", 1))

    Section("Sending")

    local timer = CheckBox(page, "Remind me when it is time to recruit")
    timer:SetPoint("TOPLEFT", 0, y)
    timer:SetScript("OnClick", function(self)
        ns.db.settings.bark.enabled = self:GetChecked() and true or false
        ns.Bark.Restart()
        UI.Refresh()
    end)
    y = y - 24

    local combat = CheckBox(page, "Not in combat")
    combat:SetPoint("TOPLEFT", 0, y)
    combat:SetScript("OnClick", function(self)
        ns.db.settings.bark.pauseCombat = self:GetChecked() and true or false
        UI.Refresh()
    end)
    local instance = CheckBox(page, "Not in an instance")
    instance:SetPoint("TOPLEFT", 200, y)
    instance:SetScript("OnClick", function(self)
        ns.db.settings.bark.pauseInstance = self:GetChecked() and true or false
        UI.Refresh()
    end)
    y = y - 24

    local confirm = CheckBox(page, "Make me read a new revision before I send it")
    confirm:SetPoint("TOPLEFT", 0, y)
    confirm:SetScript("OnClick", function(self)
        ns.db.settings.bark.confirmNewRev = self:GetChecked() and true or false
        UI.Refresh()
    end)
    y = y - 28

    local channelLabel = Row("")
    y = y - 22
    local channel = EditBox(page, 200, 22)
    channel:SetPoint("TOPLEFT", 0, y)
    channel:SetScript("OnEnterPressed", function(self)
        local text = ns.Util.Trim(self:GetText())
        ns.db.settings.bark.channel = text ~= "" and text or "auto"
        self:ClearFocus()
        UI.Refresh()
    end)
    local channelHint = Label(page, "Type part of a channel's name and press Enter, "
        .. "or \"auto\" to use the first of LookingForGroup, Trade, General you have joined.",
        "GameFontDisableSmall")
    channelHint:SetPoint("TOPLEFT", 210, y - 2)
    channelHint:SetWidth(UI.PAGE_W - 230)
    channelHint:SetSpacing(2)
    y = y - 34

    Section("Sync")

    local syncOn = CheckBox(page, "Keep in step with the other officers")
    syncOn:SetPoint("TOPLEFT", 0, y)
    syncOn:SetScript("OnClick", function(self)
        ns.db.settings.sync.enabled = self:GetChecked() and true or false
        UI.Refresh()
    end)
    y = y - 28

    local bar = UI.Toolbar(page, { top = y, right = -26 })
    local probe = bar:Left(Button(bar, "Probe client", 100, 22))
    probe:SetScript("OnClick", function() ns.Probe.Run() end)
    local tests = bar:Left(Button(bar, "Run tests", 90, 22))
    tests:SetScript("OnClick", function()
        ns.Tests.Run()
        UI.Refresh()
    end)
    local forget = bar:Left(Button(bar, "Forget peers", 100, 22, { kind = "danger" }))
    UI.Tooltip(forget, function()
        GameTooltip:AddLine("Forget peers", 1, 1, 1)
        GameTooltip:AddLine("Drops what every other officer told us and every bark. "
            .. "The message itself is untouched.", 0.8, 0.8, 0.8, true)
    end)
    forget:SetScript("OnClick", function()
        ns.db.peers, ns.db.barks = {}, {}
        UI.Refresh()
    end)
    y = y - 30

    local status = Label(page, "", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", 0, y)
    status:SetWidth(UI.PAGE_W - 20)
    status:SetSpacing(3)

    return function()
        local s = ns.db.settings
        -- The number on its own is the thing that got read wrong; the guild's own
        -- name for that rank is what makes it unambiguous.
        local function RankLabel(index)
            local named = ns.Roster.RankName(ns.Roster.rows, index)
            if named then return string.format("|cffffcc00%d|r (%s)", index, named) end
            return string.format("|cffffcc00%d|r", index)
        end
        authorLabel:SetText(string.format("Raid leaders: rank %s or better may change "
            .. "the message", RankLabel(s.authorRankIndex)))
        barkLabel:SetText(string.format("Officers: rank %s or better may send it",
            RankLabel(s.barkRankIndex)))

        timer:SetChecked(s.bark.enabled)
        combat:SetChecked(s.bark.pauseCombat)
        instance:SetChecked(s.bark.pauseInstance)
        confirm:SetChecked(s.bark.confirmNewRev)
        syncOn:SetChecked(s.sync.enabled)

        local list = {}
        if type(GetChannelList) == "function" then list = { GetChannelList() } end
        -- s is settings, and the channel lives on settings.bark. The two rank
        -- thresholds beside it really are top level, which is what made reading
        -- s.channel look right.
        local _, name = ns.Bark.Channel(list, s.bark.channel)
        channelLabel:SetText(string.format("Channel: |cffffcc00%s|r  |cff888888%s|r",
            s.bark.channel, name and ("currently " .. name) or "|cffff4444none joined|r"))
        if not channel:HasFocus() then channel:SetText(s.bark.channel) end

        -- Only the guild master should be moving thresholds around, and a greyed
        -- button that says why is better than one that silently does nothing.
        local _, myRank = ns.Roster.Me()
        local gm = myRank == 0
        local why = "Only the guild master sets the rank thresholds."
        for _, b in ipairs({ authorDown, authorUp, barkDown, barkUp }) do
            UI.Gate(b, gm, why)
        end

        status:SetText(table.concat(ns.Probe.Status(), "\n"))
    end
end)
