local addonName, ns = ...

ns.UI = ns.UI or {}
local UI = ns.UI

local WIDTH, HEIGHT = 720, 560
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
        f:SetBackdropColor(r or 0.06, g or 0.06, b or 0.08, a or 0.95)
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

    local title = Label(f, "TradeMaster", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    UI.title = title

    UI.status = Label(f, "", "GameFontDisableSmall")
    UI.status:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)

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

    UI.tabs, UI.pages = {}, {}
    local names = { "Professions", "Book", "Bark", "Orders", "Income", "Filter", "Log", "Invite" }
    for i, name in ipairs(names) do
        local tab = Button(f, name, 84, 20)
        tab:SetPoint("TOPLEFT", 8 + (i - 1) * 86, -46)
        tab:SetScript("OnClick", function() UI.SelectTab(i) end)
        UI.tabs[i] = tab

        local page = CreateFrame("Frame", nil, f)
        page:SetPoint("TOPLEFT", 10, -72)
        page:SetPoint("BOTTOMRIGHT", -10, 10)
        page:Hide()
        UI.pages[i] = page
    end

    UI.BuildProfessions(UI.pages[1])
    UI.BuildBook(UI.pages[2])
    UI.BuildBark(UI.pages[3])
    UI.BuildOrders(UI.pages[4])
    UI.BuildIncome(UI.pages[5])
    UI.BuildFilter(UI.pages[6])
    UI.BuildLog(UI.pages[7])
    UI.BuildInvite(UI.pages[8])

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

function UI.Refresh()
    if not UI.frame or not UI.frame:IsShown() then return end
    local profile = ns.Prof.Current()
    local s = ns.PS()
    UI.title:SetText("TradeMaster  |cff888888" .. (profile.key ~= "generic" and profile.name or "no active profession") .. "|r")

    if not ns.Enabled() then
        UI.status:SetText("|cffff4444DISABLED|r  |cff888888no invites, whispers, barks or trade filling. Click Enable.|r")
        if UI.enableButton then UI.enableButton.text:SetText("Enable") end
    else
        if UI.enableButton then UI.enableButton.text:SetText("Disable") end
        local n, products, noun = ns.Prof.BookCounts(profile, ns.Book())
        UI.status:SetText(string.format(
            "%d recipes (%d %s)  |  advertising %d  |  %d open orders  |  bark %s  |  invite %s%s",
            n, products, noun, #ns.Barker.AdvertisedEntries(), #ns.Orders.OpenList(),
            onoff(s.bark.enabled), onoff(s.invite.enabled),
            ns.Barker.pending and "  |  |cffffcc00BARK READY|r"
                or (s.bark.enabled and ("  |  next bark in " .. ns.Barker.SecondsUntilDue() .. "s") or "")))
    end

    local refreshers = { UI.RefreshProfessions, UI.RefreshBook, UI.RefreshBark, UI.RefreshOrders,
                         UI.RefreshIncome, UI.RefreshFilter, UI.RefreshLog, UI.RefreshInvite }
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
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, top or 0)
    scroll:SetPoint("BOTTOMRIGHT", -26, bottom or 0)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    return scroll, content
end
UI.ScrollList = ScrollList

--------------------------------------------------------------------------------
-- Professions tab
--------------------------------------------------------------------------------

function UI.BuildProfessions(page)
    local intro = Label(page,
        "Every supported profession window you open is scanned into its own book. "
        .. "One profession is |cff44ff44active|r: only it barks, invites, books orders and fills trades.\n"
        .. "Supported: " .. table.concat(ns.Professions.Order, ", ") .. ". Enchanting is not supported yet.",
        "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", 0, 0)
    intro:SetWidth(680)
    intro:SetJustifyH("LEFT")
    intro:SetSpacing(3)

    UI.profRows = {}

    function UI.RefreshProfessions()
        for _, row in ipairs(UI.profRows) do row:Hide() end
        local y = -56
        for i, key in ipairs(ns.Professions.Order) do
            local p = ns.Prof.ByKey(key)
            local pd = ns.db.professions and ns.db.professions[key]
            local scanned = pd and pd.book and next(pd.book) ~= nil
            local row = UI.profRows[i]
            if not row then
                row = CreateFrame("Frame", nil, page, BackdropTemplateMixin and "BackdropTemplate")
                row:SetSize(680, 30)
                Skin(row, 0.10, 0.10, 0.13, 0.9)
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(22, 22)
                row.icon:SetPoint("LEFT", 6, 0)
                row.text = Label(row, "", "GameFontHighlightSmall")
                row.text:SetPoint("LEFT", 34, 0)
                row.text:SetWidth(500)
                row.text:SetJustifyH("LEFT")
                row.active = Button(row, "Make active", 100, 20)
                row.active:SetPoint("RIGHT", -6, 0)
                UI.profRows[i] = row
            end
            row:SetPoint("TOPLEFT", 0, y)
            row.icon:SetTexture(p.iconPath)
            row.icon:SetDesaturated(not scanned)
            local isActive = key == ns.db.activeProfession
            if scanned then
                pd = ns.Prof.DB(key)
                local n, products, noun = ns.Prof.BookCounts(p, pd.book)
                local age = pd.bookScannedAt > 0 and math.floor((ns.Now() - pd.bookScannedAt) / 60) or -1
                row.text:SetText(string.format("%s%s|r   %d recipes, %d %s   |cff888888scanned %s, %d advertised%s|r",
                    isActive and "|cff44ff44" or "|cffffffff", p.name, n, products, noun,
                    age >= 0 and (age .. " min ago") or "never",
                    #ns.Barker.AdvertisedEntries(pd.book),
                    pd.bookPartial and ", partial" or ""))
                row.active.text:SetText(isActive and "Active" or "Make active")
                row.active:SetScript("OnClick", function()
                    ns.Prof.SetActive(key)
                    ns.Print(p.name .. " is now the active profession.")
                    UI.Refresh()
                end)
                row.active:Show()
            else
                row.text:SetText(string.format("|cff777777%s   not scanned. Open its window once and it will be picked up.|r", p.name))
                row.active:Hide()
            end
            row:Show()
            y = y - 34
        end
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

    local viewBtn = Button(page, "Book: -", 150, 22)
    viewBtn:SetPoint("TOPLEFT", 0, 0)
    viewBtn:SetScript("OnClick", function()
        local known = ns.Prof.Known()
        if #known == 0 then return end
        local cur = ViewedKey()
        local idx = 1
        for i, k in ipairs(known) do if k == cur then idx = i end end
        UI.bookProf = known[(idx % #known) + 1]
        UI.RefreshBook()
    end)
    UI.bookViewButton = viewBtn

    local scanBtn = Button(page, "Scan Book", 80, 22)
    scanBtn:SetPoint("LEFT", viewBtn, "RIGHT", 6, 0)
    scanBtn:SetScript("OnClick", function()
        if ns.Prof.OpenWindow() then
            ns.Scanner.Scan()
        else
            ns.Print("open a profession window, then click Scan Book.")
        end
        UI.Refresh()
    end)

    UI.bulkButtons = {}
    for i = 1, 4 do
        local b = Button(page, "", 60, 22)
        b:SetPoint("LEFT", scanBtn, "RIGHT", 6 + (i - 1) * 62, 0)
        b:Hide()
        UI.bulkButtons[i] = b
    end

    local search = EditBox(page, 150, 22)
    search:SetPoint("TOPRIGHT", 0, 0)
    search:SetScript("OnTextChanged", function(self)
        UI.bookSearch = self:GetText():lower()
        UI.RefreshBook()
    end)

    local scroll, content = ScrollList(page, -28, 0)
    UI.bookContent = content
    UI.bookRows = {}

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
            if not e.stale then
                if not UI.bookSearch or UI.bookSearch == ""
                    or (e.name or ""):lower():find(UI.bookSearch, 1, true) then
                    list[#list + 1] = e
                end
            end
        end
        table.sort(list, function(a, b)
            if (a.header or "") ~= (b.header or "") then
                return (a.header or "") < (b.header or "")
            end
            return (a.name or "") < (b.name or "")
        end)

        for _, row in ipairs(UI.bookRows) do row:Hide() end

        for i, e in ipairs(list) do
            local row = UI.bookRows[i]
            if not row then
                row = CreateFrame("Frame", nil, content)
                row:SetSize(560, ROW_H)
                row.adv = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
                row.adv:SetSize(18, 18)
                row.adv:SetPoint("LEFT", 0, 0)
                row.match = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
                row.match:SetSize(18, 18)
                row.match:SetPoint("LEFT", 26, 0)
                row.label = Label(row, "", "GameFontHighlightSmall")
                row.label:SetPoint("LEFT", 52, 0)
                row.label:SetJustifyH("LEFT")
                UI.bookRows[i] = row
            end
            row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
            row.entry = e
            row.adv:SetChecked(e.advertise and true or false)
            row.match:SetChecked(e.match and true or false)
            row.adv:SetScript("OnClick", function(self)
                row.entry.advertise = self:GetChecked() and true or false
                UI.Refresh()
            end)
            row.match:SetScript("OnClick", function(self)
                row.entry.match = self:GetChecked() and true or false
                ns.Events.RebuildIndex()
            end)
            row.label:SetText(string.format("%s  |cff777777%s|r%s%s",
                e.link or e.name or "?", e.header or "",
                (e.numMade or 1) > 1 and ("  |cff888888x" .. e.numMade .. "|r") or "",
                e.stats and ("  |cff88ccff" .. e.stats .. "|r") or ""))
            row:Show()
        end

        content:SetSize(560, math.max(1, #list * ROW_H))
    end

    local legend = Label(page, "|cff888888left box = advertise, right box = match for invites|r",
        "GameFontDisableSmall")
    legend:SetPoint("BOTTOMLEFT", 0, -2)
end

--------------------------------------------------------------------------------
-- Bark tab
--------------------------------------------------------------------------------

function UI.BuildBark(page)
    local remind = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    remind:SetSize(24, 24)
    remind:SetPoint("TOPLEFT", 0, 0)
    remind:SetScript("OnClick", function(self)
        local s = ns.PS().bark
        s.enabled = self:GetChecked() and true or false
        if s.enabled then ns.Barker.Start(true) else ns.Barker.Stop() end
        UI.Refresh()
    end)

    local remindLbl = Label(page, "Remind me when it's time to bark")
    remindLbl:SetPoint("LEFT", remind, "RIGHT", 4, 0)

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
        remind:SetChecked(s.enabled and true or false)
        slider:SetValue(s.intervalSec)
        _G[slider:GetName() .. "Text"]:SetText("Reminder interval: " .. s.intervalSec .. "s")
        if not tpl:HasFocus() then tpl:SetText(s.template) end
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
    local clear = Button(page, "Clear Flags", 90, 22)
    clear:SetPoint("TOPLEFT", 0, 0)
    clear:SetScript("OnClick", function()
        local n = 0
        for _, st in pairs(ns.db.players) do
            if st.flaggedSeller then st.flaggedSeller = nil; n = n + 1 end
        end
        ns.Print(string.format("cleared the auto seller flag on %d players.", n))
        UI.RefreshLog()
    end)

    local scroll, content = ScrollList(page, -28, 0)
    UI.logRows = {}

    function UI.RefreshLog()
        for _, row in ipairs(UI.logRows) do row:Hide() end
        local entries = ns.Log.Recent(40)
        for i, e in ipairs(entries) do
            local row = UI.logRows[i]
            if not row then
                row = CreateFrame("Frame", nil, content)
                row:SetSize(560, ROW_H * 2)
                row.line = Label(row, "", "GameFontHighlightSmall")
                row.line:SetPoint("TOPLEFT")
                row.line:SetWidth(430)
                row.line:SetJustifyH("LEFT")
                row.never = Button(row, "Never", 56, 18)
                row.never:SetPoint("TOPRIGHT", 0, 0)
                UI.logRows[i] = row
            end
            row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H * 2)
            row.line:SetText(ns.Log.Describe(e) .. "\n" .. ns.Log.DescribeHits(e))
            row.never:SetScript("OnClick", function()
                ns.Players.Get(ns.db, e.player).neverInvite = true
                ns.Print(e.player .. " will never be invited.")
            end)
            row:Show()
        end
        content:SetSize(560, math.max(1, #entries * ROW_H * 2))
    end
end

--------------------------------------------------------------------------------
-- Invite tab
--------------------------------------------------------------------------------

function UI.BuildInvite(page)
    local rows = {
        { "Auto invite from Trade chat", function() return ns.PS().invite.enabled end,
          function(v) ns.PS().invite.enabled = v end },
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
        cb:SetPoint("TOPLEFT", 0, -(i - 1) * 26)
        cb:SetSize(22, 22)
        local lbl = Label(page, r[1])
        lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        cb:SetScript("OnClick", function(self) r[3](self:GetChecked() and true or false) end)
        UI.inviteChecks[i] = { cb = cb, get = r[2] }
    end

    local partyLabel = Label(page, "Stop inviting at party size")
    partyLabel:SetPoint("TOPLEFT", 4, -146)

    local slider = CreateFrame("Slider", "TradeMasterPartySlider", page, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 4, -178)
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
    }

    UI.templateBoxes = {}
    local y = -196
    for _, t in ipairs(templates) do
        local lbl = Label(page, t.label)
        lbl:SetPoint("TOPLEFT", 0, y)

        local box = EditBox(page, 520, 22)
        box:SetPoint("TOPLEFT", 0, y - 16)
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
        reset:SetPoint("TOPLEFT", 528, y - 16)
        reset:SetScript("OnClick", function()
            local d = ns.Prof.Current().templates[t.key]
            ns.PS().invite.whisper[t.key] = d
            box:SetText(d or "")
        end)
        UI.templateBoxes[t.key] = box

        y = y - 35
    end

    local hint = Label(page,
        "|cff888888Press Enter to save a line, Escape to discard. Leave a line empty to send nothing for that case. "
        .. "Templates are per profession.|r", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 0, y - 4)
    hint:SetWidth(660)
    hint:SetJustifyH("LEFT")

    function UI.RefreshInvite()
        for _, c in ipairs(UI.inviteChecks) do c.cb:SetChecked(c.get() and true or false) end
        slider:SetValue(ns.PS().invite.maxParty)
        _G[slider:GetName() .. "Text"]:SetText("Max party: " .. ns.PS().invite.maxParty)
        for key, box in pairs(UI.templateBoxes) do
            if not box:HasFocus() then box:SetText(ns.PS().invite.whisper[key] or "") end
        end
    end
end
