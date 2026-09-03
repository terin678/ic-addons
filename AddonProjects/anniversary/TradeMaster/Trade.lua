local addonName, ns = ...

ns.Trade = ns.Trade or {}
local Trade = ns.Trade

-- Slots 1 to 6 are traded. Slot 7 is the "will not be traded" slot.
local TRADE_SLOTS = 6

local function ReadSide(getLink, getInfo)
    local items, links = {}, {}
    for i = 1, TRADE_SLOTS do
        local link = getLink(i)
        if link then
            local id = tonumber(link:match("|Hitem:(%d+)"))
            local _, _, qty = getInfo(i)
            if id then
                items[id] = (items[id] or 0) + (qty or 1)
                links[id] = link
            end
        end
    end
    return items, links
end

function Trade.Snapshot()
    local incoming, inLinks = ReadSide(GetTradeTargetItemLink, GetTradeTargetItemInfo)
    local outgoing, outLinks = ReadSide(GetTradePlayerItemLink, GetTradePlayerItemInfo)
    return {
        partner = Trade.partner,
        incoming = incoming, incomingLinks = inLinks,
        outgoing = outgoing, outLinks = outLinks,
        theirMoney = GetTargetTradeMoney and GetTargetTradeMoney() or 0,
        ourMoney = GetPlayerTradeMoney and GetPlayerTradeMoney() or 0,
    }
end

-- Pure. Splits a snapshot's incoming items into raw reagents for this order
-- and finished products, so we can tell a mats handoff from a delivery.
function Trade.Classify(snapshot, book)
    local rawMats, products = {}, {}
    for id, qty in pairs(snapshot.incoming) do
        if book[id] then products[id] = qty else rawMats[id] = qty end
    end
    local delivered = {}
    for id, qty in pairs(snapshot.outgoing) do
        if book[id] then delivered[id] = qty end
    end
    return rawMats, products, delivered
end

local function Commit(snapshot)
    if not ns.Enabled() then return end
    local now = ns.Now()
    local player = snapshot.partner
    if not player then return end

    local net = (snapshot.theirMoney or 0) - (snapshot.ourMoney or 0)
    local order = ns.Orders.Open(player)
    local book = order and ns.Orders.BookFor(order) or ns.Book()
    local profile = order and ns.Prof.ByKey(order.profession) or ns.Prof.Current()
    local nounS, nounP = profile.craftNoun[1], profile.craftNoun[2]

    local rawMats, _, delivered = ns.Trade.Classify(snapshot, book)

    local anyRaw = next(rawMats) ~= nil
    local anyDelivered = next(delivered) ~= nil

    -- Someone who messaged you first, or said nothing at all, can reach the trade
    -- window with no order behind them. Open one here: the mats in the window are
    -- the request, and InferQuantities below reads them. The order takes the active
    -- profession, which is the book this trade was already classified against.
    if not order and (anyRaw or anyDelivered or net > 0) then
        if ns.db.settings.orders.autoFromTrade ~= false then
            order = ns.Orders.Create(player, "trade", "", {}, now, "grouped")
            ns.Print(string.format(
                "|cff44ff44order #%d opened|r for %s: they traded first.", order.id, player))
            if ns.Tracker then ns.Tracker.Refresh() end
        else
            ns.Print(string.format(
                "|cffffcc00%s traded with you and has no open order.|r Use /tm order add %s to start one.",
                player, player))
        end
    end

    if not order then
        if net ~= 0 then ns.Ledger.Record(player, nil, net, delivered, now) end
        return
    end

    if anyRaw then
        for id, qty in pairs(rawMats) do
            order.matsReceived[id] = (order.matsReceived[id] or 0) + qty
        end
        local needsSplit, added = ns.Orders.InferQuantities(
            order, order.matsReceived, book, profile.reagentAmbiguityMax)

        if ns.db.settings.orders.autoAdvanceMats and order.status ~= "done" then
            ns.Orders.SetStatus(order, "mats", now)
        end

        ns.Print(string.format("order #%d: mats received. %s", order.id, ns.Orders.Summarise(order)))
        if #added > 0 then
            ns.Print(string.format("  |cffffcc00added a %s they did not originally ask for.|r", nounS))
        end
        if needsSplit then
            ns.Print(string.format("  |cffff9900ambiguous: those mats fit more than one %s they asked for. Set the split in the Orders tab.|r", nounS))
        end
        for rawID, info in pairs(order.unmatchedMats or {}) do
            local names = {}
            for i = 1, math.min(4, #info.options) do
                local e = book[info.options[i]]
                names[#names + 1] = e and (e.link or e.name) or tostring(info.options[i])
            end
            ns.Print(string.format("  |cffff9900%d x %s could be any of %d %s (%s%s). Add the right one in the Orders tab.|r",
                info.count, snapshot.incomingLinks[rawID] or tostring(rawID), #info.options, nounP,
                table.concat(names, ", "), #info.options > 4 and ", ..." or ""))
        end
    end

    if net ~= 0 then
        order.copperIn = (order.copperIn or 0) + net
        ns.Ledger.Record(player, order.id, net, delivered, now)
        ns.Print(string.format("order #%d: received %s", order.id, ns.Ledger.Money(net)))
    end

    if anyDelivered and ns.db.settings.orders.promptOnDone then
        ns.Print(string.format(
            "|cff44ff44order #%d looks delivered.|r /tm order done %d to close it.", order.id, order.id))
    end

    order.updatedAt = now
end

--------------------------------------------------------------------------------
-- Auto fill
--------------------------------------------------------------------------------

-- Container API moved into C_Container on newer clients. Resolve at call time
-- so this works either way. getInfo also returns the stack count: a stack is
-- usually more than one, and assuming one unit per slot undercounted every
-- stacked craft. (CutMaster 1.1.0)
local function Container()
    local numSlots = GetContainerNumSlots or (C_Container and C_Container.GetContainerNumSlots)
    local useItem = UseContainerItem or (C_Container and C_Container.UseContainerItem)
    local getInfo
    if C_Container and C_Container.GetContainerItemInfo then
        getInfo = function(bag, slot)
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if not info then return nil, 0 end
            return info.hyperlink, info.stackCount or 1
        end
    elseif GetContainerItemInfo then
        getInfo = function(bag, slot)
            local _, count, _, _, _, _, link = GetContainerItemInfo(bag, slot)
            return link, count or 1
        end
    end
    return numSlots, useItem, getInfo
end

local function FreeTradeSlots()
    local used = 0
    for i = 1, TRADE_SLOTS do
        if GetTradePlayerItemLink(i) then used = used + 1 end
    end
    return TRADE_SLOTS - used
end

-- Pure. Bind on pickup is skipped: it cannot be traded, so never queue one.
function Trade.WantedFromOrder(order, book)
    local wanted = {}
    for _, it in ipairs(order.items or {}) do
        local e = book[it.itemID]
        if not e or e.bindType ~= 1 then
            wanted[it.itemID] = (wanted[it.itemID] or 0) + (it.qty or 1)
        end
    end
    return wanted
end

-- Pure. First bag row (from a fresh scan) matching something still wanted.
-- Run against a NEW snapshot every tick rather than one computed before
-- earlier moves: after a slot empties, bags can shift, and stale (bag, slot)
-- coordinates silently dropped every item after the first one or two.
function Trade.NextFillSlot(wanted, bagSnapshot)
    for _, row in ipairs(bagSnapshot) do
        if (wanted[row.itemID] or 0) > 0 then
            return row
        end
    end
    return nil
end

local function BagSnapshot()
    local numSlots, _, getInfo = Container()
    local rows = {}
    if not numSlots or not getInfo then return rows end
    for bag = 0, 4 do
        for slot = 1, (numSlots(bag) or 0) do
            local link, count = getInfo(bag, slot)
            local id = link and tonumber(link:match("|Hitem:(%d+)"))
            if id then
                rows[#rows + 1] = { bag = bag, slot = slot, itemID = id, link = link, count = count or 1 }
            end
        end
    end
    return rows
end

function Trade.StopFill()
    if Trade.fillTicker then
        Trade.fillTicker:Cancel()
        Trade.fillTicker = nil
    end
end

local function ReportFill(order, added, wanted, book)
    if added > 0 then
        ns.Print(string.format("added %d stack%s to the trade for order #%d.",
            added, added == 1 and "" or "s", order.id))
    end
    -- WoW's own 6 slot cap on "you will give" items: an order spanning more
    -- than 6 distinct items genuinely needs a second trade.
    local remaining = {}
    for id, q in pairs(wanted) do
        if q > 0 then
            local e = book[id]
            remaining[#remaining + 1] = (e and (e.link or e.name) or tostring(id)) .. " x" .. q
        end
    end
    if #remaining > 0 then
        ns.Print("|cffff9900more than fits in one trade (6 slot limit): "
            .. table.concat(remaining, ", ")
            .. ". Complete this trade, then open a new one for the rest.|r")
    end
end

function Trade.AutoFill()
    Trade.StopFill()
    if not ns.Enabled() then return end
    if not ns.db.settings.orders.autoFillTrade then return end

    local order = Trade.partner and ns.Orders.Open(Trade.partner)
    if not order then return end

    local book = ns.Orders.BookFor(order)
    local wanted = Trade.WantedFromOrder(order, book)
    local anyWanted = false
    for _, q in pairs(wanted) do if q > 0 then anyWanted = true break end end
    if not anyWanted then return end

    local added = 0

    -- One per tick, re-scanning bags fresh each time. Adding items in a
    -- single frame bugs the trade UI, and a stale scan is what caused the
    -- original "stops after 1 or 2" bug.
    Trade.fillTicker = C_Timer.NewTicker(0.15, function()
        if not TradeFrame or not TradeFrame:IsShown() then
            Trade.StopFill()
            return
        end

        if FreeTradeSlots() <= 0 then
            Trade.StopFill()
            ReportFill(order, added, wanted, book)
            return
        end

        local row = Trade.NextFillSlot(wanted, BagSnapshot())
        if not row then
            Trade.StopFill()
            ReportFill(order, added, wanted, book)
            return
        end

        local _, useItem = Container()
        if useItem then
            useItem(row.bag, row.slot)
            added = added + 1

            local still = wanted[row.itemID] or 0
            if row.count > still then
                -- UseContainerItem moves the whole stack; there is no partial
                -- move. Flagged rather than silently over-delivering.
                ns.Print(string.format(
                    "|cffff9900%s: stack of %d moved, only %d was needed for this order.|r",
                    row.link, row.count, still))
            end
            wanted[row.itemID] = still - row.count
        end
    end)
end

function Trade.OnEvent(event, ...)
    if event == "TRADE_SHOW" then
        Trade.partner = UnitName("NPC") or UnitName("npc")
        Trade.bothAccepted = false
        Trade.pending = nil
        C_Timer.After(0.2, Trade.AutoFill)
    elseif event == "TRADE_ACCEPT_UPDATE" then
        local playerAccepted, targetAccepted = ...
        if playerAccepted == 1 and targetAccepted == 1 then
            Trade.bothAccepted = true
            Trade.pending = Trade.Snapshot()
        end
    elseif event == "TRADE_CLOSED" then
        if Trade.bothAccepted and Trade.pending then
            Commit(Trade.pending)
        end
        Trade.bothAccepted = false
        Trade.pending = nil
        Trade.partner = nil
        Trade.StopFill()
    end
end
