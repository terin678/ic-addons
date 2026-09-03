local addonName, ns = ...

ns.UI = ns.UI or {}
local UI = ns.UI

local WIDTH, HEIGHT = 720, 572
local ROW_H = 18

local BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

local function Skin(f, r, g, b, a)
    if f.SetBackdrop then
        f:SetBackdrop(BACKDROP)
        f:SetBackdropColor(r or 0.082, g or 0.137, b or 0.200, a or 0.95)
        f:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
    end
    return f
end

local function Button(parent, text, w, h)
    local b = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    b:SetSize(w or 90, h or 22)
    Skin(b, 0.15, 0.15, 0.18, 1)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("CENTER")
    b.text:SetText(text)
    b:SetScript("OnEnter", function(self) self:SetBackdropColor(0.25, 0.25, 0.3, 1) end)
    b:SetScript("OnLeave", function(self) self:SetBackdropColor(0.15, 0.15, 0.18, 1) end)
    return b
end

local function Label(parent, text, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormalSmall")
    fs:SetText(text)
    return fs
end

local function EditBox(parent, w, h)
    local box = CreateFrame("EditBox", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    box:SetSize(w or 200, h or 22)
    box:SetAutoFocus(false)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetTextInsets(6, 6, 0, 0)
    Skin(box, 0.1, 0.1, 0.12, 1)
    return box
end

-- Shared with UI_Orders.lua and Tracker.lua.
UI.Skin, UI.Button, UI.Label, UI.EditBox = Skin, Button, Label, EditBox

--------------------------------------------------------------------------------
-- Lists and toolbars come from the shared widget library, so every tab gets
-- column headers outside the scroll child and fixed single-line rows. See
-- "Window layout" in CODING_STANDARDS.md.
--------------------------------------------------------------------------------

local ICUI = LibStub("LibICUI-1.0")
UI.Lib = ICUI

local STYLE = ICUI:Style("TradeMaster", {
    rowHeight = ROW_H,
    headerHeight = 18,
    font = "GameFontHighlightSmall",
    headerFont = "GameFontDisableSmall",
})

function UI.Age(seconds) return ICUI:Age(seconds) end

function UI.Toolbar(page, opts)
    opts = opts or {}
    opts.style = STYLE
    return ICUI:Toolbar(page, opts)
end

function UI.Table(page, opts)
    opts = opts or {}
    opts.style = STYLE
    opts.makeButton = opts.makeButton or function(parent, text, w, h)
        return Button(parent, text, w, h)
    end
    return ICUI:Table(page, opts)
end

local function onoff(v)
    return v and "|cff44ff44on|r" or "|cffff4444off|r"
end

--------------------------------------------------------------------------------
-- Main frame
--------------------------------------------------------------------------------

function UI.Create()
    if UI.frame then return UI.frame end

    local f = CreateFrame("Frame", "TradeMasterFrame", UIParent,
        BackdropTemplateMixin and "BackdropTemplate")
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("HIGH")
    Skin(f)
    f:Hide()
    tinsert(UISpecialFrames, "TradeMasterFrame")

    -- Guild mark, then the title. Both addons wear it (see LibICUI's Brand).
    local mark = ICUI:Logo(f, 22)
    mark:SetPoint("TOPLEFT", 10, -8)

    local title = Label(f, "TradeMaster", "GameFontNormal")
    title:SetPoint("TOPLEFT", 38, -10)
    local bone = ICUI.Brand.bone
    title:SetTextColor(bone.r, bone.g, bone.b)
    UI.title = title

    UI.status = Label(f, "", "GameFontDisableSmall")
    UI.status:SetPoint("TOPLEFT", 38, -36)
    UI.status:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    UI.status:SetJustifyH("LEFT")
    UI.status:SetWordWrap(false)

    local close = Button(f, "X", 22, 22)
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() f:Hide() end)

    -- A public chat message can only be sent from a hardware event, so this
    -- click (or the key binding) is the path that actually works.
    local bark = Button(f, "Bark Now", 90, 22)
    bark:SetPoint("TOPRIGHT", close, "TOPLEFT", -6, 0)
    bark:SetScript("OnClick", function()
        local ok, info = ns.Barker.Tick(true)
        if not ok then ns.Print("bark skipped: " .. tostring(info)) end
        UI.Refresh()
    end)
    UI.barkButton = bark

    local power = Button(f, "Disable", 70, 22)
    power:SetPoint("TOPRIGHT", bark, "TOPLEFT", -6, 0)
    power:SetScript("OnClick", function()
        ns.db.settings.enabled = not ns.Enabled()
        if ns.Enabled() then
            if ns.PS().bark.enabled then ns.Barker.Start() end
            ns.Print("|cff44ff44enabled.|r")
        else
            ns.Barker.Stop()
            ns.Print("|cffff4444disabled.|r")
        end
        UI.Refresh()
    end)
    UI.enableButton = power

    -- Two plain on/off switches. Bark belongs to the active profession;
    -- invites cover every scanned book.
    local invites = Button(f, "Invites: ?", 104, 22)
    invites:SetPoint("TOPRIGHT", power, "TOPLEFT", -6, 0)
    invites:SetScript("OnClick", function() ns.SetInvites(ns.db.settings.invites == false) end)
    UI.inviteToggle = invites

    local barkToggle = Button(f, "Bark: ?", 90, 22)
    barkToggle:SetPoint("TOPRIGHT", invites, "TOPLEFT", -6, 0)
    barkToggle:SetScript("OnClick", function() ns.SetBark(not ns.PS().bark.enabled) end)
    UI.barkToggle = barkToggle

    UI.tabs, UI.pages = {}, {}
    local names = { "Professions", "Book", "Bark", "Orders", "Market", "Income", "Filter", "Log", "Invite" }
    for i, name in ipairs(names) do
        local tab = Button(f, name, 74, 20)
        tab:SetPoint("TOPLEFT", 8 + (i - 1) * 78, -58)
        tab:SetScript("OnClick", function() UI.SelectTab(i) end)
        UI.tabs[i] = tab

        local page = CreateFrame("Frame", nil, f)
        page:SetPoint("TOPLEFT", 10, -84)
        page:SetPoint("BOTTOMRIGHT", -10, 10)
        page:Hide()
        UI.pages[i] = page
    end

    UI.BuildProfessions(UI.pages[1])
    UI.BuildBook(UI.pages[2])
    UI.BuildBark(UI.pages[3])
    UI.BuildOrders(UI.pages[4])
    UI.BuildMarket(UI.pages[5])
    UI.BuildIncome(UI.pages[6])
    UI.BuildFilter(UI.pages[7])
    UI.BuildLog(UI.pages[8])
    UI.BuildInvite(UI.pages[9])

    UI.frame = f
    -- Land on Book once something is scanned, on Professions before that.
    UI.SelectTab(#ns.Prof.Known() > 0 and 2 or 1)
    return f
end

function UI.SelectTab(index)
    for i, tab in ipairs(UI.tabs) do
        UI.pages[i]:SetShown(i == index)
        tab:SetBackdropColor(i == index and 0.25 or 0.15,
            i == index and 0.25 or 0.15, i == index and 0.35 or 0.18, 1)
    end
    UI.current = index
    UI.Refresh()
end

function UI.Toggle()
    local f = UI.Create()
    if f:IsShown() then f:Hide() else f:Show(); UI.Refresh() end
end

-- Shared ON/OFF rendering for the toggle buttons.
function UI.State(on)
    return on and "|cff44ff44ON|r" or "|cffff4444OFF|r"
end

function UI.Refresh()
    if not UI.frame or not UI.frame:IsShown() then return end
    local profile = ns.Prof.Current()
    local s = ns.PS()
    UI.title:SetText("TradeMaster  |cff888888" .. (profile.key ~= "generic" and profile.name or "no active profession") .. "|r")
    UI.barkToggle.text:SetText("Bark: " .. UI.State(s.bark.enabled))
    UI.inviteToggle.text:SetText("Invites: " .. UI.State(ns.db.settings.invites ~= false))

    if not ns.Enabled() then
        UI.status:SetText("|cffff4444DISABLED|r  |cff888888no invites, whispers, barks or trade filling. Click Enable.|r")
        if UI.enableButton then UI.enableButton.text:SetText("Enable") end
    else
        if UI.enableButton then UI.enableButton.text:SetText("Disable") end
        local n, products, noun = ns.Prof.BookCounts(profile, ns.Book())
        UI.status:SetText(string.format(
            "%d recipes (%d %s)  |  advertising %d  |  %d open orders%s",
            n, products, noun, #ns.Barker.AdvertisedEntries(), #ns.Orders.OpenList(),
            ns.Barker.pending and "  |  |cffffcc00BARK READY|r"
                or (s.bark.enabled and ("  |  next bark in " .. ns.Barker.SecondsUntilDue() .. "s") or "")))
        if profile.key ~= "generic" then
            UI.status:SetText(UI.status:GetText() .. "  |  "
                .. ns.Market.Summary(ns.db, ns.Now(), profile.key, s.bark.intervalSec))
        end
    end

    local refreshers = { UI.RefreshProfessions, UI.RefreshBook, UI.RefreshBark, UI.RefreshOrders,
                         UI.RefreshMarket, UI.RefreshIncome, UI.RefreshFilter, UI.RefreshLog,
                         UI.RefreshInvite }
    local fn = refreshers[UI.current]
    if fn then
        -- A page that fails to draw must say so, not silently show nothing.
        local ok, err = pcall(fn)
        if not ok then ns.Print("|cffff4444UI error:|r " .. tostring(err)) end
    end
end

--------------------------------------------------------------------------------
-- Scrolling list helper
--------------------------------------------------------------------------------

local function ScrollList(parent, top, bottom)
    return ICUI:ScrollList(parent, top, bottom)
end
UI.ScrollList = ScrollList

--------------------------------------------------------------------------------
-- Professions tab
--------------------------------------------------------------------------------

function UI.BuildProfessions(page)
    -- Two lines exactly, so the table below starts at a known offset.
    local intro = Label(page,
        "Every profession window you open is scanned into its own book. One is |cff44ff44active|r and owns the bark.\n"
        .. "Invites cover every scanned book: the one matching a request handles its order and trade.",
        "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", 0, -2)
    intro:SetWidth(690)
    intro:SetJustifyH("LEFT")
    intro:SetSpacing(3)

    local t = UI.Table(page, {
        top = -36,
        rowHeight = 22,
        columns = {
            { key = "icon", label = "", width = 26, type = "texture" },
            { key = "name", label = "Profession", width = 128 },
            { key = "recipes", label = "Recipes", width = 60, justify = "RIGHT" },
            { key = "products", label = "Products", width = 68, justify = "RIGHT" },
            { key = "scanned", label = "Scanned", width = 62, justify = "RIGHT" },
            { key = "adv", label = "Advertised", width = 70, justify = "RIGHT" },
            { key = "note", label = "", width = "flex" },
        },
        buttons = { { key = "active", label = "Make active", width = 100 } },
    })
    UI.profTable = t

    function UI.RefreshProfessions()
        local now = ns.Now()
        local list = {}
        for _, key in ipairs(ns.Professions.Order) do list[#list + 1] = key end

        t:Render(list, function(row, key)
            local p = ns.Prof.ByKey(key)
            local pd = ns.db.professions and ns.db.professions[key]
            local scanned = pd and pd.book and next(pd.book) ~= nil
            local isActive = key == ns.db.activeProfession

            row.cells.icon:SetTexture(p.iconPath)
            row.cells.icon:SetDesaturated(not scanned)

            local btn = row.buttons.active
            if scanned then
                pd = ns.Prof.DB(key)
                local n, products, noun = ns.Prof.BookCounts(p, pd.book)
                t:Set(row, "name", (isActive and "|cff44ff44" or "|cffffffff") .. p.name .. "|r")
                t:Set(row, "recipes", tostring(n))
                t:Set(row, "products", string.format("%d %s", products, noun))
                t:Set(row, "scanned", pd.bookScannedAt > 0
                    and UI.Age(now - pd.bookScannedAt) or "never")
                t:Set(row, "adv", tostring(#ns.Barker.AdvertisedEntries(pd.book)))
                t:Set(row, "note", pd.bookPartial and "|cffff9900partial scan|r" or "")
                btn.text:SetText(isActive and "|cff44ff44Active|r" or "Make active")
                btn:Show()
                btn:SetScript("OnClick", function()
                    ns.Prof.SetActive(key)
                    ns.Print(p.name .. " is now the active profession.")
                    UI.Refresh()
                end)
            else
                t:Set(row, "name", "|cff777777" .. p.name .. "|r")
                t:Set(row, "recipes", "")
                t:Set(row, "products", "")
                t:Set(row, "scanned", "")
                t:Set(row, "adv", "")
                t:Set(row, "note", "|cff777777not scanned; open its window once|r")
                btn:Hide()
            end
        end)
    end
end

--------------------------------------------------------------------------------
-- Book tab
--------------------------------------------------------------------------------

function UI.BuildBook(page)
    -- Which book is on display. Defaults to the active profession; the button
    -- cycles through every scanned one so idle books can be curated too.
    UI.bookProf = nil
    local function ViewedKey()
        local known = ns.Prof.Known()
        if UI.bookProf and ns.db.professions[UI.bookProf] then return UI.bookProf end
        return ns.db.activeProfession or known[1]
    end
    local function ViewedBook()
        local key = ViewedKey()
        return key and ns.Prof.DB(key).book or {}, key and ns.Prof.ByKey(key) or ns.Professions.Generic
    end

    -- Row one: which book, and the bulk pickers.
    local bar = UI.Toolbar(page, { top = 0 })

    local viewBtn = Button(bar, "Book: -", 150, 22)
    viewBtn:SetScript("OnClick", function()
        local known = ns.Prof.Known()
        if #known == 0 then return end
        local cur = ViewedKey()
        local idx = 1
        for i, k in ipairs(known) do if k == cur then idx = i end end
        UI.bookProf = known[(idx % #known) + 1]
        UI.RefreshBook()
    end)
    bar:Left(viewBtn)
    UI.bookViewButton = viewBtn

    local scanBtn = Button(bar, "Scan Book", 80, 22)
    scanBtn:SetScript("OnClick", function()
        if ns.Prof.OpenWindow() then
            ns.Scanner.Scan()
        else
            ns.Print("open a profession window, then click Scan Book.")
        end
        UI.Refresh()
    end)
    bar:Left(scanBtn)

    UI.bulkButtons = {}
    for i = 1, 4 do
        local b = Button(bar, "", 60, 22)
        bar:Left(b)
        b:Hide()
        UI.bulkButtons[i] = b
    end

    -- Row two: how the list is filtered and ordered, plus the legend.
    local bar2 = UI.Toolbar(page, { top = -26 })

    local legend = Label(bar2, "|cff888888Bark = include in barks.  Invite = invite whoever asks for it.|r",
        "GameFontDisableSmall")
    legend:SetPoint("LEFT", bar2, "LEFT", 0, 0)

    local SORTS = {
        { key = "category",   label = "Category" },
        { key = "name",       label = "Name" },
        { key = "quality",    label = "Quality" },
        { key = "advertised", label = "Advertised" },
    }
    local function SortMode()
        local cur = ns.db.settings and ns.db.settings.bookSort or "category"
        for i, s in ipairs(SORTS) do if s.key == cur then return i, s end end
        return 1, SORTS[1]
    end
    local sortBtn = Button(bar2, "Sort: Category", 120, 22)
    sortBtn:SetScript("OnClick", function()
        local idx = SortMode()
        ns.db.settings.bookSort = SORTS[(idx % #SORTS) + 1].key
        UI.RefreshBook()
    end)
    bar2:Right(sortBtn)

    local search = EditBox(bar2, 150, 22)
    search:SetScript("OnTextChanged", function(self)
        UI.bookSearch = self:GetText():lower()
        UI.RefreshBook()
    end)
    bar2:Right(search)

    local function Tooltip(row, e)
        GameTooltip:SetOwner(row, "ANCHOR_CURSOR")
        if e.link then
            GameTooltip:SetHyperlink(e.link)
        else
            GameTooltip:AddLine(e.name or "?")
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(string.format("Recipe  |cff888888%s|r", e.header or ""), 1, 0.82, 0)
        local any = false
        for id, count in pairs(e.reagents or {}) do
            local rname, _, _, _, _, _, _, _, _, tex = GetItemInfo(id)
            GameTooltip:AddDoubleLine(
                (tex and ("|T" .. tex .. ":14|t ") or "") .. (rname or ("item " .. id)),
                "x" .. count, 1, 1, 1, 1, 0.82, 0)
            any = true
        end
        if not any then GameTooltip:AddLine("no reagent data; rescan the book", 0.6, 0.6, 0.6) end
        local missing = ns.Scanner.MissingBoP(e)
        if #missing > 0 then
            GameTooltip:AddLine("Bind on Pickup reagent you don't hold: "
                .. ns.Scanner.DescribeMissing(missing, true), 1, 0.4, 0.4, true)
            GameTooltip:AddLine("not advertised; requests get the \"not enough\" reply", 0.6, 0.6, 0.6)
        end
        if (e.numMade or 1) > 1 then
            GameTooltip:AddLine(string.format("makes %d per craft", e.numMade), 0.7, 0.9, 1)
        end
        GameTooltip:AddLine(string.format("advertise %s   match %s",
            e.advertise and "|cff44ff44on|r" or "|cffff4444off|r",
            e.match and "|cff44ff44on|r" or "|cffff4444off|r"), 0.6, 0.6, 0.6)
        if e.aliases and #e.aliases > 0 then
            GameTooltip:AddLine("aliases: " .. table.concat(e.aliases, ", "), 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
    end

    local t = UI.Table(page, {
        top = -52,
        columns = {
            { key = "adv", label = "Bark", width = 44, type = "check" },
            { key = "match", label = "Invite", width = 44, type = "check" },
            { key = "name", label = "Recipe", width = "flex" },
            { key = "header", label = "Category", width = 120 },
            { key = "note", label = "", width = 150 },
        },
        onEnter = Tooltip,
    })
    UI.bookTable = t

    function UI.RefreshBook()
        local book, profile = ViewedBook()
        local key = ViewedKey()
        viewBtn.text:SetText("Book: " .. (profile.key ~= "generic" and profile.name or "-")
            .. (key and key == ns.db.activeProfession and " |cff44ff44(active)|r" or ""))

        for _, b in ipairs(UI.bulkButtons) do b:Hide() end
        for i, m in ipairs(profile.bulkFilters or {}) do
            local b = UI.bulkButtons[i]
            if b then
                b.text:SetText(m[1])
                b:SetScript("OnClick", function()
                    ns.Barker.ApplyAdvertiseFilter(book, m[2], profile)
                    UI.Refresh()
                end)
                b:Show()
            end
        end

        local list = {}
        for _, e in pairs(book) do
            -- Bind on Pickup items can't be traded, so they are not listed.
            if not e.stale and e.bindType ~= 1 then
                if not UI.bookSearch or UI.bookSearch == ""
                    or (e.name or ""):lower():find(UI.bookSearch, 1, true) then
                    list[#list + 1] = e
                end
            end
        end

        local _, mode = SortMode()
        sortBtn.text:SetText("Sort: " .. mode.label)
        local function byName(a, b) return (a.name or "") < (b.name or "") end
        local function byQuality(a, b)
            local qa, qb = a.quality or 0, b.quality or 0
            if qa ~= qb then return qa > qb end
            return byName(a, b)
        end
        table.sort(list, function(a, b)
            if mode.key == "name" then return byName(a, b) end
            if mode.key == "quality" then return byQuality(a, b) end
            if mode.key == "advertised" then
                local aa, ab = a.advertise and 1 or 0, b.advertise and 1 or 0
                if aa ~= ab then return aa > ab end
                return byQuality(a, b)
            end
            if (a.header or "") ~= (b.header or "") then
                return (a.header or "") < (b.header or "")
            end
            return byName(a, b)
        end)

        t:Render(list, function(row, e)
            row.cells.adv:SetChecked(e.advertise and true or false)
            row.cells.match:SetChecked(e.match and true or false)
            row.cells.adv:SetScript("OnClick", function(self)
                e.advertise = self:GetChecked() and true or false
                UI.Refresh()
            end)
            row.cells.match:SetScript("OnClick", function(self)
                e.match = self:GetChecked() and true or false
                ns.Events.RebuildIndex()
            end)
            t:Set(row, "name", (e.link or e.name or "?")
                .. ((e.numMade or 1) > 1 and ("  |cff888888x" .. e.numMade .. "|r") or ""))
            t:Set(row, "header", "|cff777777" .. (e.header or "") .. "|r")
            local missing = ns.Scanner.MissingBoP(e)
            t:Set(row, "note", #missing > 0
                and ("|cffff8888needs " .. ns.Scanner.DescribeMissing(missing) .. "|r")
                or (e.stats and ("|cff88ccff" .. e.stats .. "|r") or ""))
        end)
    end
end

--------------------------------------------------------------------------------
-- Bark tab
--------------------------------------------------------------------------------

function UI.BuildBark(page)
    local remind = Button(page, "Bark reminders: ?", 170, 22)
    remind:SetPoint("TOPLEFT", 0, 0)
    remind:SetScript("OnClick", function() ns.SetBark(not ns.PS().bark.enabled) end)

    local remindLbl = Label(page, "|cff888888active profession only; switch it on the Professions tab|r")
    remindLbl:SetPoint("LEFT", remind, "RIGHT", 8, 0)

    local sendNow = Button(page, "Send Now", 90, 22)
    sendNow:SetPoint("TOPLEFT", 0, -28)
    sendNow:SetScript("OnClick", function()
        local ok, info = ns.Barker.Tick(true)
        if not ok then ns.Print("bark skipped: " .. tostring(info)) end
        UI.Refresh()
    end)

    local slider = CreateFrame("Slider", "TradeMasterIntervalSlider", page, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 0, -60)
    slider:SetWidth(260)
    slider:SetMinMaxValues(30, 600)
    slider:SetValueStep(10)
    slider:SetObeyStepOnDrag(true)
    _G[slider:GetName() .. "Low"]:SetText("30s")
    _G[slider:GetName() .. "High"]:SetText("600s")
    slider:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v / 10 + 0.5) * 10
        ns.PS().bark.intervalSec = v
        _G[self:GetName() .. "Text"]:SetText("Reminder interval: " .. v .. "s")
        if ns.PS().bark.enabled then ns.Barker.Start(false) end
    end)

    local market = Label(page, "", "GameFontHighlightSmall")
    market:SetPoint("TOPLEFT", 300, -66)
    market:SetWidth(380)
    market:SetJustifyH("LEFT")
    market:SetSpacing(3)

    local tplLabel = Label(page, "Message template ({items} is required)")
    tplLabel:SetPoint("TOPLEFT", 0, -92)

    local tpl = EditBox(page, 580, 24)
    tpl:SetPoint("TOPLEFT", 0, -110)
    tpl:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        if not text:find("{items}", 1, true) and not text:find("{gems}", 1, true) then
            ns.Print("|cffff4444template must contain {items}.|r")
            self:SetText(ns.PS().bark.template)
        else
            ns.PS().bark.template = text
            ns.Print("template saved.")
        end
        self:ClearFocus()
        UI.Refresh()
    end)

    local preview = Label(page, "", "GameFontHighlightSmall")
    preview:SetPoint("TOPLEFT", 0, -146)
    preview:SetWidth(580)
    preview:SetJustifyH("LEFT")
    preview:SetSpacing(3)

    local note = Label(page,
        "|cffff9900WoW blocks addons from posting to public chat on a timer.|r\n"
        .. "The interval only reminds you. Sending needs a real key or click:\n"
        .. "the Bark Now button, /tm send, or a key bound under\n"
        .. "Options, Key Bindings, TradeMaster. Bark settings are per profession.", "GameFontDisableSmall")
    note:SetPoint("BOTTOMLEFT", 0, 10)
    note:SetJustifyH("LEFT")
    note:SetSpacing(3)

    function UI.RefreshBark()
        local s = ns.PS().bark
        remind.text:SetText("Bark reminders: " .. UI.State(s.enabled))
        slider:SetValue(s.intervalSec)
        _G[slider:GetName() .. "Text"]:SetText("Reminder interval: " .. s.intervalSec .. "s")
        if not tpl:HasFocus() then tpl:SetText(s.template) end
        local key = ns.db.activeProfession
        if key then
            local now = ns.Now()
            local sellers, buyers = ns.Market.Counts(ns.db, now, key, 3600)
            local label = ns.Market.Label(sellers, buyers)
            local suggest = ns.Market.SuggestInterval(s.intervalSec, sellers, buyers)
            market:SetText(string.format("market: %s%s|r, suggested %ds\n|cff888888last hour: %d sellers, %d buyers in Trade|r",
                ns.Market.LabelColor(label), label, suggest, sellers, buyers))
        else
            market:SetText("")
        end

        local msg, _, used = ns.Barker.Preview()
        if msg then
            preview:SetText(string.format("|cff888888next bark, %d %s, %d chars:|r\n%s",
                used, ns.Prof.Current().craftNoun[2], #msg, msg))
        else
            preview:SetText("|cffff4444nothing to advertise. Scan, then pick items in Book.|r")
        end
    end
end

--------------------------------------------------------------------------------
-- Filter tab (editable vocabulary, per profession)
--------------------------------------------------------------------------------

local function JoinList(t)
    return table.concat(t or {}, ", ")
end

local function SplitList(s)
    local out = {}
    for part in (s or ""):gmatch("[^,]+") do
        local v = ns.Util.Trim(part):lower()
        if v ~= "" then out[#out + 1] = v end
    end
    return out
end

local function JoinWeighted(t)
    local parts = {}
    for k, w in pairs(t or {}) do parts[#parts + 1] = k .. ":" .. w end
    table.sort(parts)
    return table.concat(parts, ", ")
end

local function SplitWeighted(s)
    local out = {}
    for part in (s or ""):gmatch("[^,]+") do
        local phrase, w = part:match("^%s*(.-)%s*:%s*(%d+)%s*$")
        if phrase then
            out[ns.Util.Trim(phrase):lower()] = tonumber(w)
        else
            local p = ns.Util.Trim(part):lower()
            if p ~= "" then out[p] = 2 end
        end
    end
    return out
end

function UI.BuildFilter(page)
    local req = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    req:SetPoint("TOPLEFT", 0, 0)
    req:SetSize(22, 22)
    local reqLabel = Label(page, "Require a buying signal in Trade chat")
    reqLabel:SetPoint("LEFT", req, "RIGHT", 4, 0)
    req:SetScript("OnClick", function(self)
        ns.PS().filter.requireBuyerSignal = self:GetChecked() and true or false
    end)

    local slider = CreateFrame("Slider", "TradeMasterThresholdSlider", page, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 4, -46)
    slider:SetWidth(260)
    slider:SetMinMaxValues(1, 10)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    _G[slider:GetName() .. "Low"]:SetText("1 strict")
    _G[slider:GetName() .. "High"]:SetText("10 loose")
    slider:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v + 0.5)
        ns.PS().filter.netThreshold = v
        _G[self:GetName() .. "Text"]:SetText("Net seller threshold: " .. v)
    end)

    local fields = {
        { key = "vetoWords", label = "|cffff8888Hard vetoes|r (never invited, any channel), comma separated", weighted = false },
        { key = "sellerWords", label = "|cffff8888Seller signals|r as phrase:weight", weighted = true },
        { key = "buyerWords", label = "|cff88ff88Buyer signals|r as phrase:weight", weighted = true },
        { key = "professionWords", label = "Asking for the profession itself (no item named)", weighted = false },
        { key = "craftVerbs", label = "Craft verbs (\"can <verb>\" is a seller tell unless guarded)", weighted = false },
    }
    UI.filterBoxes = {}
    local y = -96
    for _, fd in ipairs(fields) do
        local lbl = Label(page, fd.label)
        lbl:SetPoint("TOPLEFT", 0, y)
        local box = EditBox(page, 600, 22)
        box:SetPoint("TOPLEFT", 0, y - 16)
        box:SetScript("OnEnterPressed", function(self)
            local f = ns.PS().filter
            f[fd.key] = fd.weighted and SplitWeighted(self:GetText()) or SplitList(self:GetText())
            ns.Print("filter saved.")
            self:ClearFocus()
        end)
        box:SetScript("OnEscapePressed", function(self)
            UI.RefreshFilter()
            self:ClearFocus()
        end)
        local reset = Button(page, "Reset", 52, 22)
        reset:SetPoint("LEFT", box, "RIGHT", 6, 0)
        reset:SetScript("OnClick", function()
            local d = ns.Prof.DefaultSettings(ns.Prof.Current()).filter
            ns.PS().filter[fd.key] = ns.DeepCopy(d[fd.key])
            UI.RefreshFilter()
        end)
        UI.filterBoxes[fd.key] = { box = box, weighted = fd.weighted }
        y = y - 44
    end

    local hint = Label(page,
        "|cff888888Press Enter to save a line, Escape to discard. Vocabulary is per profession; "
        .. "/tm try <message> tests it. Unweighted phrases default to weight 2.|r",
        "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 0, y - 4)
    hint:SetWidth(660)
    hint:SetJustifyH("LEFT")

    function UI.RefreshFilter()
        local f = ns.PS().filter
        req:SetChecked(f.requireBuyerSignal)
        slider:SetValue(f.netThreshold)
        _G[slider:GetName() .. "Text"]:SetText("Net seller threshold: " .. f.netThreshold)
        for key, fb in pairs(UI.filterBoxes) do
            if not fb.box:HasFocus() then
                fb.box:SetText(fb.weighted and JoinWeighted(f[key]) or JoinList(f[key]))
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Log tab
--------------------------------------------------------------------------------

function UI.BuildLog(page)
    -- Toolbar: what the list shows, and the one bulk action. Nothing sits over the list.
    local bar = UI.Toolbar(page, { top = 0 })

    local clear = Button(bar, "Clear Flags", 90, 22)
    clear:SetScript("OnClick", function()
        local n = 0
        for _, st in pairs(ns.db.players) do
            if st.flaggedSeller then st.flaggedSeller = nil; n = n + 1 end
        end
        ns.Print(string.format("cleared the auto seller flag on %d players.", n))
        UI.RefreshLog()
    end)
    bar:Left(clear)

    local FILTERS = {
        { key = nil, label = "All" },
        { key = "invite", label = "Invited" },
        { key = "vetoed", label = "Vetoed" },
        { key = "lowscore", label = "Low" },
    }
    UI.logFilter = nil
    UI.logFilterButtons = {}
    for i, f in ipairs(FILTERS) do
        local b = Button(bar, f.label, 62, 22)
        b:SetScript("OnClick", function()
            UI.logFilter = f.key
            UI.RefreshLog()
        end)
        b.filterKey = f.key
        b.plainLabel = f.label
        bar:Left(b)
        UI.logFilterButtons[i] = b
    end

    local hint = Label(bar, "|cff888888hover a row for the full message and its signals|r",
        "GameFontDisableSmall")
    hint:SetPoint("RIGHT", bar, "RIGHT", 0, 0)

    local function Tooltip(row, e)
        GameTooltip:SetOwner(row, "ANCHOR_CURSOR")
        GameTooltip:AddLine(e.player or "?", 1, 1, 1)
        GameTooltip:AddLine(string.format("%s  |cff888888%s|r",
            date("%H:%M:%S", e.at or 0), e.profession or ""), 0.6, 0.6, 0.6)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(e.msg or "", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("verdict", (ns.Log.VERDICT_COLOR[e.verdict] or "|cffffffff")
            .. (e.verdict or "?") .. "|r", 0.7, 0.7, 0.7)
        GameTooltip:AddDoubleLine("reason", e.reason or "?", 0.7, 0.7, 0.7, 1, 1, 1)
        if e.blocked then
            GameTooltip:AddDoubleLine("blocked", e.blocked, 0.7, 0.7, 0.7, 1, 0.6, 0.4)
        end
        if e.matchedNames and #e.matchedNames > 0 then
            GameTooltip:AddDoubleLine("matched", table.concat(e.matchedNames, ", "),
                0.7, 0.7, 0.7, 1, 1, 1)
        end
        local hits = ns.Log.SortedHits(e)
        if #hits > 0 then
            GameTooltip:AddLine(" ")
            for _, h in ipairs(hits) do
                GameTooltip:AddDoubleLine(h.sign .. h.name, tostring(h.weight),
                    h.seller and 1 or 0.5, h.seller and 0.5 or 1, 0.5,
                    h.seller and 1 or 0.5, h.seller and 0.5 or 1, 0.5)
            end
        else
            GameTooltip:AddLine("no signals fired", 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
    end

    local t = UI.Table(page, {
        top = -28,
        columns = {
            { key = "age", label = "Age", width = 34, justify = "RIGHT" },
            { key = "verdict", label = "Verdict", width = 54 },
            { key = "player", label = "Player", width = 92 },
            { key = "prof", label = "Prof", width = 58 },
            { key = "reason", label = "Reason", width = 100 },
            { key = "score", label = "S/B", width = 40, justify = "RIGHT" },
            { key = "msg", label = "Message", width = "flex" },
        },
        buttons = { { key = "never", label = "Never", width = 56 } },
        onEnter = Tooltip,
    })
    UI.logTable = t

    function UI.RefreshLog()
        for _, b in ipairs(UI.logFilterButtons) do
            local on = b.filterKey == UI.logFilter
            b.text:SetText(on and ("|cffffcc00" .. b.plainLabel .. "|r") or b.plainLabel)
        end

        local now = ns.Now()
        local entries = ns.Log.Recent(100, UI.logFilter)
        t:Render(entries, function(row, e)
            local color = ns.Log.VERDICT_COLOR[e.verdict] or "|cffffffff"
            t:Set(row, "age", UI.Age(now - (e.at or now)))
            t:Set(row, "verdict", color .. (e.verdict or "?") .. "|r")
            t:Set(row, "player", e.player or "?")
            t:Set(row, "prof", e.profession or "")
            t:Set(row, "reason", e.reason or "")
            t:Set(row, "score", string.format("%d/%d", e.sellerScore or 0, e.buyerScore or 0))
            t:Set(row, "msg", e.msg or "")

            local btn = row.buttons.never
            local st = e.player and ns.db.players[e.player]
            local never = st and st.neverInvite
            btn.text:SetText(never and "|cffff4444Never|r" or "Never")
            btn:SetShown(e.player ~= nil)
            btn:SetScript("OnClick", function()
                local state = ns.Players.Get(ns.db, e.player)
                state.neverInvite = not state.neverInvite or nil
                ns.Print(e.player .. (state.neverInvite and " will never be invited."
                    or " can be invited again."))
                UI.RefreshLog()
            end)
        end)
    end
end

--------------------------------------------------------------------------------
-- Invite tab
--------------------------------------------------------------------------------

function UI.BuildInvite(page)
    local toggle = Button(page, "Invites: ?", 104, 22)
    toggle:SetPoint("TOPLEFT", 0, 0)
    toggle:SetScript("OnClick", function() ns.SetInvites(ns.db.settings.invites == false) end)
    local toggleLbl = Label(page,
        "|cff888888every scanned profession; the book that matches the request handles it|r")
    toggleLbl:SetPoint("LEFT", toggle, "RIGHT", 8, 0)

    local rows = {
        { "Auto invite from whispers", function() return ns.PS().invite.fromWhisper end,
          function(v) ns.PS().invite.fromWhisper = v end },
        { "Whisper them after inviting", function() return ns.PS().invite.whisper.enabled end,
          function(v) ns.PS().invite.whisper.enabled = v end },
        { "Record every Trade message (capture)", function() return ns.db.settings.captureAll end,
          function(v) ns.db.settings.captureAll = v end },
        { "Debug output", function() return ns.db.settings.debug end,
          function(v) ns.db.settings.debug = v end },
    }

    UI.inviteChecks = {}
    for i, r in ipairs(rows) do
        local cb = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 0, -28 - (i - 1) * 24)
        cb:SetSize(22, 22)
        local lbl = Label(page, r[1])
        lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        cb:SetScript("OnClick", function(self) r[3](self:GetChecked() and true or false) end)
        UI.inviteChecks[i] = { cb = cb, get = r[2] }
    end

    local partyLabel = Label(page, "Stop inviting at party size")
    partyLabel:SetPoint("TOPLEFT", 4, -132)

    local slider = CreateFrame("Slider", "TradeMasterPartySlider", page, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 210, -138)
    slider:SetWidth(220)
    slider:SetMinMaxValues(2, 5)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    _G[slider:GetName() .. "Low"]:SetText("2")
    _G[slider:GetName() .. "High"]:SetText("5")
    slider:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v + 0.5)
        ns.PS().invite.maxParty = v
        _G[self:GetName() .. "Text"]:SetText("Max party: " .. v)
    end)

    -- Every whisper the addon can send, editable, per profession.
    local templates = {
        { key = "template", label = "They named an item you have  |cff888888{item} {player}|r" },
        { key = "templateNoItem", label = "They asked for your profession but named nothing  |cff888888{player}|r" },
        { key = "confirmTemplate", label = "They answered with an item you have  |cff888888{item} {player}|r" },
        { key = "suggestTemplate", label = "They asked for an item you lack  |cff888888{items} {player}|r" },
        { key = "partialTemplate", label = "They asked for several, you have some  |cff888888{have} {lack}|r" },
        { key = "noneTemplate", label = "They asked outright and you have nothing close" },
        { key = "askWhichTemplate", label = "They typed half a name  |cff888888{items}|r" },
        { key = "noMatsTemplate", label = "You lack a Bind on Pickup reagent for it  |cff888888{mats} {item}|r" },
    }

    UI.templateBoxes = {}
    local y = -170
    for _, t in ipairs(templates) do
        local lbl = Label(page, t.label)
        lbl:SetPoint("TOPLEFT", 0, y - 4)
        lbl:SetWidth(296)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(false)

        local box = EditBox(page, 300, 22)
        box:SetPoint("TOPLEFT", 302, y)
        box:SetScript("OnEscapePressed", function(self)
            self:SetText(ns.PS().invite.whisper[t.key] or "")
            self:ClearFocus()
        end)
        box:SetScript("OnEnterPressed", function(self)
            ns.PS().invite.whisper[t.key] = self:GetText()
            ns.Print("saved.")
            self:ClearFocus()
        end)

        local reset = Button(page, "Reset", 52, 22)
        reset:SetPoint("TOPLEFT", 608, y)
        reset:SetScript("OnClick", function()
            local d = ns.Prof.Current().templates[t.key]
            ns.PS().invite.whisper[t.key] = d
            box:SetText(d or "")
        end)
        UI.templateBoxes[t.key] = box

        y = y - 28
    end

    local hint = Label(page,
        "|cff888888Press Enter to save a line, Escape to discard. Leave a line empty to send nothing for that case. "
        .. "Templates are per profession.|r", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 0, y - 6)
    hint:SetWidth(690)
    hint:SetJustifyH("LEFT")

    function UI.RefreshInvite()
        toggle.text:SetText("Invites: " .. UI.State(ns.db.settings.invites ~= false))
        for _, c in ipairs(UI.inviteChecks) do c.cb:SetChecked(c.get() and true or false) end
        slider:SetValue(ns.PS().invite.maxParty)
        _G[slider:GetName() .. "Text"]:SetText("Max party: " .. ns.PS().invite.maxParty)
        for key, box in pairs(UI.templateBoxes) do
            if not box:HasFocus() then box:SetText(ns.PS().invite.whisper[key] or "") end
        end
    end
end
