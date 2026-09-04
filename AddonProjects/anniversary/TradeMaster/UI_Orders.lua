local addonName, ns = ...

-- Orders and Income tabs. Kept out of UI.lua, which owns the frame and tabs.

ns.UI = ns.UI or {}
local UI = ns.UI

local STATUS_COLOR = {
    pending   = "|cffffcc00",
    grouped   = "|cff66ccff",
    mats      = "|cff44ff44",
    done      = "|cff888888",
    cancelled = "|cff888888",
}

local MAX_SPLIT_ROWS = 5
local MAX_UNMATCHED_ROWS = 4
local DETAIL_H = 156

--------------------------------------------------------------------------------
-- Orders
--------------------------------------------------------------------------------

function UI.BuildOrders(page)
    local bar = UI.Toolbar(page, { top = 0 })

    local nameBox = UI.EditBox(bar, 160, 22)

    local function addOrder()
        local who = ns.Util.Trim(nameBox:GetText() or "")
        if who == "" then
            ns.Print("type a player name first.")
            return
        end
        local now = ns.Now()
        if ns.Orders.Open(who) then
            ns.Print(who .. " already has an open order.")
        else
            local o = ns.Orders.Create(who, "manual", "", {}, now, "grouped")
            ns.Print(string.format("order #%d opened for %s. Trade them the mats and it fills itself in.", o.id, who))
        end
        nameBox:SetText("")
        nameBox:ClearFocus()
        UI.RefreshOrders()
    end
    nameBox:SetScript("OnEnterPressed", addOrder)
    bar:Left(nameBox)

    local add = UI.Button(bar, "Add Order", 84, 22)
    add:SetScript("OnClick", addOrder)
    bar:Left(add)

    local showDone = UI.Button(bar, "Finished: hidden", 120, 22)
    showDone:SetScript("OnClick", function()
        local o = ns.db.settings.orders
        o.showFinished = not o.showFinished
        UI.RefreshOrders()
    end)
    bar:Left(showDone)

    -- An empty list must never read as lost data: say how many are held back.
    local hiddenLabel = UI.Label(bar, "", "GameFontDisableSmall")
    hiddenLabel:SetWordWrap(false)
    -- Width before placing it: the toolbar packs left to right on measured width,
    -- and an empty FontString measures zero.
    hiddenLabel:SetWidth(90)
    hiddenLabel:SetJustifyH("LEFT")
    bar:Left(hiddenLabel)

    local prune = UI.Button(bar, "Prune Old", 84, 22)
    prune:SetScript("OnClick", function()
        local before = #ns.db.orders
        ns.Orders.Prune(ns.Now(), ns.db.settings.orders.keepDoneDays)
        ns.Print(string.format("pruned %d finished orders.", before - #ns.db.orders))
        UI.RefreshOrders()
    end)
    bar:Right(prune)

    local track = UI.Button(bar, "Tracker", 76, 22)
    track:SetScript("OnClick", function() ns.Tracker.Toggle() end)
    bar:Right(track)

    --------------------------------------------------------------------------
    -- Detail panel. Anything that would make a row grow lives down here, so
    -- the list itself stays one fixed-height line per order.
    --------------------------------------------------------------------------

    local detail = CreateFrame("Frame", nil, page, BackdropTemplateMixin and "BackdropTemplate")
    detail:SetPoint("BOTTOMLEFT", 0, 0)
    detail:SetPoint("BOTTOMRIGHT", 0, 0)
    detail:SetHeight(DETAIL_H)
    UI.Skin(detail, 0.098, 0.149, 0.216, 0.95)

    local detailHead = UI.Label(detail, "", "GameFontNormalSmall")
    detailHead:SetPoint("TOPLEFT", 8, -6)
    detailHead:SetWidth(660)
    detailHead:SetJustifyH("LEFT")
    detailHead:SetWordWrap(false)

    -- Editing by hand. A customer who adds an item mid-trade, or hands over gold
    -- outside the trade window, should not need the order cancelling and redoing.
    local function Selected()
        return UI.selectedOrderID and ns.Orders.ByID(UI.selectedOrderID) or nil
    end

    -- Set when a typed name matches more than one recipe; the list then offers
    -- the candidates as buttons rather than guessing.
    local addChoices = nil

    local addLabel = UI.Label(detail, "add", "GameFontDisableSmall")
    addLabel:SetPoint("TOPLEFT", 8, -26)

    local addBox = UI.EditBox(detail, 170, 18)
    addBox:SetPoint("TOPLEFT", 32, -22)

    local addBtn = UI.Button(detail, "Add", 44, 18)
    addBtn:SetPoint("TOPLEFT", 208, -22)

    local paidLabel = UI.Label(detail, "paid", "GameFontDisableSmall")
    paidLabel:SetPoint("TOPLEFT", 268, -26)

    local paidBox = UI.EditBox(detail, 90, 18)
    paidBox:SetPoint("TOPLEFT", 296, -22)

    local paidBtn = UI.Button(detail, "Set", 44, 18)
    paidBtn:SetPoint("TOPLEFT", 392, -22)

    local paidNow = UI.Label(detail, "", "GameFontDisableSmall")
    paidNow:SetPoint("TOPLEFT", 444, -26)
    paidNow:SetWidth(210)
    paidNow:SetJustifyH("LEFT")
    paidNow:SetWordWrap(false)

    -- The button and the Enter key take the same path.
    local function TryAdd()
        local o = Selected()
        if not o then return end
        local text = ns.Util.Trim(addBox:GetText() or "")
        if text == "" then return end

        local book = ns.Orders.BookFor(o)
        local profile = (o.profession and ns.Prof.ByKey(o.profession)) or ns.Prof.Current()
        addChoices = nil

        -- A shift-clicked item link says exactly which one, so it skips the search.
        local ids = ns.Util.ExtractItemIDs(text)
        if ids[1] then
            if book[ids[1]] then
                ns.Orders.AddItem(o, ids[1], 1, ns.Now())
                addBox:SetText("")
            else
                ns.Print("that item is not in the " .. profile.name .. " book.")
            end
            UI.RefreshOrders()
            return
        end

        local matches = ns.Orders.FindInBook(book, text)
        if #matches == 0 then
            ns.Print(string.format("nothing in the %s book matches \"%s\".", profile.name, text))
        elseif #matches == 1 then
            ns.Orders.AddItem(o, matches[1].itemID, 1, ns.Now())
            addBox:SetText("")
        else
            addChoices = { orderID = o.id, text = text, options = matches }
        end
        UI.RefreshOrders()
    end
    addBtn:SetScript("OnClick", TryAdd)
    addBox:SetScript("OnEnterPressed", TryAdd)

    -- Correcting the money writes the difference to the ledger, so the Income tab
    -- and the order agree without the sale being counted twice.
    local function TrySetPaid()
        local o = Selected()
        if not o then return end
        local copper = ns.Util.ParseMoney(paidBox:GetText() or "")
        if not copper then
            ns.Print("paid: type an amount like 25g, 25g50s, or 250 for gold.")
            return
        end
        local now = ns.Now()
        local delta = ns.Orders.SetPaid(o, copper, now)
        if delta ~= 0 then
            ns.Ledger.Adjust(o.player, o.id, delta, now)
            -- Money carries its own sign now, so a correction reads "-12g".
            ns.Print(string.format("order #%d paid is now %s (%s%s).", o.id,
                ns.Ledger.Money(o.copperIn), delta > 0 and "+" or "",
                ns.Ledger.Money(delta)))
        end
        paidBox:ClearFocus()
        UI.RefreshOrders()
    end
    paidBtn:SetScript("OnClick", TrySetPaid)
    paidBox:SetScript("OnEnterPressed", TrySetPaid)

    local dScroll, dContent = UI.ScrollList(detail, -46, 6)
    dScroll:SetPoint("TOPLEFT", 8, -46)
    dScroll:SetPoint("BOTTOMRIGHT", -26, 6)

    local detailRows = {}
    local function DetailRow(i)
        local r = detailRows[i]
        if r then return r end
        r = CreateFrame("Frame", nil, dContent)
        r:SetSize(620, 18)
        r.label = UI.Label(r, "", "GameFontHighlightSmall")
        r.label:SetPoint("LEFT", 0, 0)
        r.label:SetWidth(300)
        r.label:SetJustifyH("LEFT")
        r.label:SetWordWrap(false)
        r.minus = UI.Button(r, "-", 20, 16)
        r.minus:SetPoint("LEFT", 306, 0)
        r.count = UI.Label(r, "", "GameFontNormalSmall")
        r.count:SetPoint("LEFT", 332, 0)
        r.plus = UI.Button(r, "+", 20, 16)
        r.plus:SetPoint("LEFT", 350, 0)
        r.action = UI.Button(r, "", 100, 16)
        r.action:SetPoint("LEFT", 378, 0)
        r.remove = UI.Button(r, "x", 18, 16, { kind = "danger" })
        r.remove:SetPoint("LEFT", 486, 0)
        r.picks = {}
        for b = 1, 3 do
            local btn = UI.Button(r, "", 84, 16)
            btn:SetPoint("LEFT", 378 + (b - 1) * 88, 0)
            btn:Hide()
            r.picks[b] = btn
        end
        detailRows[i] = r
        return r
    end

    local function RenderDetail(o)
        for _, r in ipairs(detailRows) do r:Hide() end
        if addChoices and (not o or addChoices.orderID ~= o.id) then addChoices = nil end

        if not o then
            detailHead:SetText("|cff888888select an order to see its items|r")
            paidNow:SetText("")
            paidBox:SetText("")
            dContent:SetSize(620, 1)
            return
        end

        paidNow:SetText((o.copperIn or 0) > 0
            and ("received " .. ns.Ledger.Money(o.copperIn))
            or "|cff888888nothing received yet|r")
        if not paidBox:HasFocus() then
            paidBox:SetText(ns.Util.MoneyText(o.copperIn))
        end

        local book = ns.Orders.BookFor(o)
        local profName = o.profession and ns.Prof.ByKey(o.profession)
            and ns.Prof.ByKey(o.profession).name or ""
        detailHead:SetText(string.format("|cffffffff#%d  %s|r  |cff888888%s|r%s",
            o.id, o.player, profName,
            o.needsSplit and "   |cffff9900mats fit more than one item: set the split below|r" or ""))

        local used, y = 0, 0

        for idx, it in ipairs(o.items) do
            used = used + 1
            local r = DetailRow(used)
            local e = book[it.itemID]
            r.label:SetText(e and (e.link or e.name) or tostring(it.itemID))
            r.count:SetText(string.format("%d%s", it.qty or 0, it.qtySource == "mats" and "" or "?"))
            r.minus:SetScript("OnClick", function()
                it.qty = math.max(0, (it.qty or 0) - 1)
                it.qtySource = "manual"
                r.count:SetText(tostring(it.qty))
                UI.RefreshOrders()
            end)
            r.plus:SetScript("OnClick", function()
                it.qty = (it.qty or 0) + 1
                it.qtySource = "manual"
                r.count:SetText(tostring(it.qty))
                UI.RefreshOrders()
            end)
            r.remove:SetScript("OnClick", function()
                local gone = ns.Orders.RemoveItem(o, idx, ns.Now())
                if gone then
                    local e2 = book[gone.itemID]
                    ns.Print(string.format("order #%d: removed %s", o.id,
                        e2 and (e2.link or e2.name) or tostring(gone.itemID)))
                end
                UI.RefreshOrders()
            end)
            r.minus:Show()
            r.plus:Show()
            r.count:Show()
            r.remove:Show()
            for _, b in ipairs(r.picks) do b:Hide() end
            r.action:Hide()
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, -y)
            r:Show()
            y = y + 18
        end

        if o.needsSplit then
            used = used + 1
            local r = DetailRow(used)
            r.label:SetText("|cffff9900quantities above are a guess|r")
            r.minus:Hide(); r.plus:Hide(); r.count:SetText(""); r.remove:Hide()
            for _, b in ipairs(r.picks) do b:Hide() end
            r.action:SetText("Confirm split")
            r.action:SetScript("OnClick", function()
                for _, it in ipairs(o.items) do
                    if it.qtySource == "ambiguous" then it.qtySource = "manual" end
                end
                o.needsSplit = false
                UI.RefreshOrders()
            end)
            r.action:Show()
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, -y)
            r:Show()
            y = y + 20
        end

        if addChoices and addChoices.orderID == o.id then
            used = used + 1
            local r = DetailRow(used)
            local n = #addChoices.options
            r.label:SetText(string.format("|cffffcc00\"%s\"|r matches %d, pick one:",
                addChoices.text, n))
            r.minus:Hide(); r.plus:Hide(); r.count:SetText(""); r.action:Hide(); r.remove:Hide()
            for b, btn in ipairs(r.picks) do
                local m = addChoices.options[b]
                if m then
                    btn:SetText(m.entry.name or tostring(m.itemID))
                    btn:SetScript("OnClick", function()
                        ns.Orders.AddItem(o, m.itemID, 1, ns.Now())
                        addChoices = nil
                        addBox:SetText("")
                        UI.RefreshOrders()
                    end)
                    btn:Show()
                else
                    btn:Hide()
                end
            end
            if n > #r.picks then
                ns.Print(string.format("%d recipes match \"%s\"; the first %d are offered. "
                    .. "Type more of the name to narrow it.", n, addChoices.text, #r.picks))
            end
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, -y)
            r:Show()
            y = y + 18
        end

        -- Mats that could be for several products: the user picks one.
        local un = 0
        for rawID, info in pairs(o.unmatchedMats or {}) do
            if un >= MAX_UNMATCHED_ROWS then break end
            un = un + 1
            used = used + 1
            local r = DetailRow(used)
            local rawName = GetItemInfo(rawID) or ("item " .. rawID)
            r.label:SetText(string.format("|cffff9900%d x %s|r could be any of %d. Pick:",
                info.count, rawName, #info.options))
            r.minus:Hide(); r.plus:Hide(); r.count:SetText(""); r.action:Hide(); r.remove:Hide()
            for b, btn in ipairs(r.picks) do
                local productID = info.options[b]
                if productID then
                    local e = book[productID]
                    btn:SetText(e and e.name or tostring(productID))
                    btn:SetScript("OnClick", function()
                        local per = e and e.reagents and e.reagents[rawID] or 1
                        o.items[#o.items + 1] = {
                            itemID = productID,
                            qty = math.floor(info.count / per) * ((e and e.numMade) or 1),
                            qtySource = "mats", unrequested = true,
                        }
                        o.unmatchedMats[rawID] = nil
                        UI.RefreshOrders()
                    end)
                    btn:Show()
                else
                    btn:Hide()
                end
            end
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, -y)
            r:Show()
            y = y + 18
        end

        if used == 0 then
            local r = DetailRow(1)
            r.label:SetText("|cff888888nothing on this order yet: trade them the mats, or type a name above|r")
            r.minus:Hide(); r.plus:Hide(); r.count:SetText(""); r.action:Hide(); r.remove:Hide()
            for _, b in ipairs(r.picks) do b:Hide() end
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, 0)
            r:Show()
            y = 18
        end

        dContent:SetSize(620, math.max(1, y))
    end

    --------------------------------------------------------------------------
    -- The list
    --------------------------------------------------------------------------

    -- Declared before the call: a handler written inside the constructor closes over
    -- whatever `t` means at that moment, and `local t = ...` is not in scope until the
    -- assignment finishes. The table is also handed to the callback as its last
    -- argument, which is what the click below uses.
    local t
    t = UI.Table(page, {
        top = -28,
        bottom = DETAIL_H + 6,
        columns = {
            { key = "id", label = "#", width = 32, justify = "RIGHT" },
            { key = "player", label = "Player", width = 100 },
            { key = "status", label = "Status", width = 88 },
            { key = "prof", label = "Prof", width = 66 },
            { key = "items", label = "Items", width = "flex" },
            { key = "paid", label = "Paid", width = 84, justify = "RIGHT" },
        },
        buttons = {
            { key = "ask", label = "Ask", width = 40 },
            { key = "cancel", label = "Cancel", width = 52 },
            { key = "done", label = "Done", width = 48 },
        },
        onClick = function(row, o, button, list)
            UI.selectedOrderID = o.id
            list:SetSelected(o)
            RenderDetail(o)
        end,
        onEnter = function(row, o)
            GameTooltip:SetOwner(row, "ANCHOR_CURSOR")
            GameTooltip:AddLine(string.format("#%d  %s", o.id, o.player), 1, 1, 1)
            GameTooltip:AddLine(ns.Orders.Summarise(o), 1, 1, 1, true)
            if o.requestText and o.requestText ~= "" then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("\"" .. o.requestText .. "\"", 0.7, 0.7, 0.7, true)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("click to open it below", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end,
    })
    UI.orderTable = t

    function UI.RefreshOrders()
        local showFinished = ns.db.settings.orders.showFinished
        local list, hidden = ns.Orders.Visible(ns.db.orders, showFinished)
        showDone:SetText(showFinished and "Finished: shown" or "Finished: hidden")
        hiddenLabel:SetText(hidden > 0 and ("|cff888888" .. hidden .. " hidden|r") or "")

        -- Keep the selection if it is still listed, else take whatever needs
        -- attention first so the panel is never pointing at nothing.
        local selected
        for _, o in ipairs(list) do
            if o.id == UI.selectedOrderID then selected = o end
        end
        if not selected then
            for _, o in ipairs(list) do
                if o.needsSplit or next(o.unmatchedMats or {}) then selected = o break end
            end
            selected = selected or list[1]
            UI.selectedOrderID = selected and selected.id or nil
        end
        t.selected = selected

        t:Render(list, function(row, o)
            local color = STATUS_COLOR[o.status] or "|cffffffff"
            local flag = (o.needsSplit and " |cffff9900split|r")
                or (next(o.unmatchedMats or {}) and " |cffff9900pick|r") or ""
            local profName = o.profession and ns.Prof.ByKey(o.profession)
                and ns.Prof.ByKey(o.profession).name or ""

            t:Set(row, "id", tostring(o.id))
            t:Set(row, "player", o.player)
            t:Set(row, "status", color .. o.status .. "|r" .. flag)
            t:Set(row, "prof", "|cff888888" .. profName .. "|r")
            t:Set(row, "items", ns.Orders.Summarise(o))
            t:Set(row, "paid", (o.copperIn or 0) > 0 and ns.Ledger.Money(o.copperIn) or "")

            row.buttons.done:SetScript("OnClick", function()
                ns.Orders.SetStatus(o, "done", ns.Now())
                UI.RefreshOrders()
            end)
            row.buttons.cancel:SetScript("OnClick", function()
                ns.Orders.SetStatus(o, "cancelled", ns.Now())
                UI.RefreshOrders()
            end)
            row.buttons.ask:SetScript("OnClick", function()
                -- The order's own profession answers, not the active one.
                local pd = o.profession and ns.db.professions and ns.db.professions[o.profession]
                local inv = (pd and pd.settings or ns.PS()).invite
                ns.Inviter.Say(o.player, inv.whisper.templateNoItem, {},
                    o.profession and ns.Prof.ByKey(o.profession) or nil)
            end)
        end)

        RenderDetail(selected)
    end
end

--------------------------------------------------------------------------------
-- Income
--------------------------------------------------------------------------------

function UI.BuildIncome(page)
    local totals = UI.Table(page, {
        top = 0,
        height = 4 * 18,
        width = 674,
        columns = {
            { key = "period", label = "Period", width = 110 },
            { key = "gold", label = "Gold", width = 150, justify = "RIGHT" },
            { key = "units", label = "Items", width = 90, justify = "RIGHT" },
            { key = "note", label = "", width = "flex" },
        },
    })

    local custHead = UI.Label(page, "Top customers", "GameFontNormal")
    custHead:SetPoint("TOPLEFT", 0, -104)

    local customers = UI.Table(page, {
        top = -122, bottom = 22, left = 0, width = 310,
        columns = {
            { key = "rank", label = "#", width = 26, justify = "RIGHT" },
            { key = "name", label = "Customer", width = "flex" },
            { key = "gold", label = "Gold", width = 100, justify = "RIGHT" },
            { key = "orders", label = "Orders", width = 50, justify = "RIGHT" },
        },
    })

    local recentHead = UI.Label(page, "Recent payments", "GameFontNormal")
    recentHead:SetPoint("TOPLEFT", 344, -104)

    local recent = UI.Table(page, {
        top = -122, bottom = 22, left = 344, width = 330,
        columns = {
            { key = "age", label = "Age", width = 40, justify = "RIGHT" },
            { key = "player", label = "Player", width = "flex" },
            { key = "gold", label = "Gold", width = 100, justify = "RIGHT" },
        },
        onEnter = function(row, e)
            GameTooltip:SetOwner(row, "ANCHOR_CURSOR")
            GameTooltip:AddLine(e.player or "?", 1, 1, 1)
            GameTooltip:AddLine(date("%Y-%m-%d %H:%M", e.at or 0), 0.7, 0.7, 0.7)
            if e.orderID then
                GameTooltip:AddDoubleLine("order", "#" .. e.orderID, 0.7, 0.7, 0.7, 1, 1, 1)
            end
            if e.profession then
                GameTooltip:AddDoubleLine("profession", e.profession, 0.7, 0.7, 0.7, 1, 1, 1)
            end
            GameTooltip:Show()
        end,
    })

    local note = UI.Label(page,
        "|cff888888Income is gross across all professions. Mat costs are not deducted.|r",
        "GameFontDisableSmall")
    note:SetPoint("BOTTOMLEFT", 0, 4)

    function UI.RefreshIncome()
        local L = ns.db.ledger
        local now = ns.Now()
        local noun = ns.Prof.Current().craftNoun
        local dayCopper, dayUnits = ns.Ledger.SumSince(L.entries, now - 86400)
        local weekCopper, weekUnits = ns.Ledger.SumSince(L.entries, now - 604800)
        local allUnits = ns.Ledger.AllTimeUnits()
        local avg = allUnits > 0 and math.floor((L.allTimeCopper or 0) / allUnits) or 0

        totals:Render({
            { period = "All time", copper = L.allTimeCopper or 0, units = allUnits },
            { period = "Last 24 hours", copper = dayCopper, units = dayUnits },
            { period = "Last 7 days", copper = weekCopper, units = weekUnits },
            { period = "Per " .. noun[1], copper = avg, units = nil,
              note = "|cff888888average across " .. allUnits .. " " .. noun[2] .. "|r" },
        }, function(row, r)
            totals:Set(row, "period", r.period)
            totals:Set(row, "gold", ns.Ledger.Money(r.copper))
            totals:Set(row, "units", r.units and tostring(r.units) or "")
            totals:Set(row, "note", r.note or "")
        end)

        local top = ns.Ledger.TopCustomers(25)
        customers:Render(top, function(row, c, i)
            customers:Set(row, "rank", tostring(i))
            customers:Set(row, "name", c.name)
            customers:Set(row, "gold", ns.Ledger.Money(c.copper))
            customers:Set(row, "orders", tostring(c.orders))
        end)

        local list = {}
        for i = 1, math.min(50, #(L.entries or {})) do list[i] = L.entries[i] end
        recent:Render(list, function(row, e)
            recent:Set(row, "age", UI.Age(now - (e.at or now)))
            -- A correction sits in the list beside real payments and can be
            -- negative, so it says what it is rather than looking like a refund.
            recent:Set(row, "player", (e.player or "?")
                .. (e.adjusted and " |cff888888(corrected)|r" or ""))
            recent:Set(row, "gold", ns.Ledger.Money(e.copper or 0))
        end)
    end
end
