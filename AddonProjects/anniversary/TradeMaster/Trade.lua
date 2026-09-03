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

    if not order then
        if anyRaw or anyDelivered or net > 0 then
            ns.Print(string.format(
                "|cffffcc00%s traded with you and has no open order.|r Use /tm order add %s to start one.",
                player, player))
        end
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

local function Container()
    return
        GetContainerNumSlots or (C_Container and C_Container.GetContainerNumSlots),
        GetContainerItemLink or (C_Container and C_Container.GetContainerItemLink),
        UseContainerItem or (C_Container and C_Container.UseContainerItem)
end

local function FreeTradeSlots()
    local used = 0
    for i = 1, TRADE_SLOTS do
        if GetTradePlayerItemLink(i) then used = used + 1 end
    end
    return TRADE_SLOTS - used
end

-- Bag slots holding the finished items this order is waiting on. Soulbound
-- crafts are skipped: they cannot be traded and would just fail.
function Trade.FindOrderItems(order)
    local numSlots, itemLink = Container()
    if not numSlots or not itemLink then return {} end
    local book = ns.Orders.BookFor(order)

    local wanted = {}
    for _, it in ipairs(order.items or {}) do
        local e = book[it.itemID]
        if not e or e.bindType ~= 1 then
            wanted[it.itemID] = (wanted[it.itemID] or 0) + (it.qty or 1)
        end
    end

    local found = {}
    for bag = 0, 4 do
        for slot = 1, (numSlots(bag) or 0) do
            local link = itemLink(bag, slot)
            local id = link and tonumber(link:match("|Hitem:(%d+)"))
            if id and (wanted[id] or 0) > 0 then
                found[#found + 1] = { bag = bag, slot = slot, itemID = id, link = link }
                wanted[id] = wanted[id] - 1
            end
        end
    end
    return found
end

function Trade.StopFill()
    if Trade.fillTicker then
        Trade.fillTicker:Cancel()
        Trade.fillTicker = nil
    end
    Trade.fillQueue = nil
end

function Trade.AutoFill()
    Trade.StopFill()
    if not ns.Enabled() then return end
    if not ns.db.settings.orders.autoFillTrade then return end

    local order = Trade.partner and ns.Orders.Open(Trade.partner)
    if not order then return end

    local queue = Trade.FindOrderItems(order)
    if #queue == 0 then return end

    local room = FreeTradeSlots()
    while #queue > room do table.remove(queue) end
    if #queue == 0 then return end

    Trade.fillQueue = queue
    local added = 0
    local noun = ns.Prof.Current().craftNoun

    Trade.fillTicker = C_Timer.NewTicker(0.1, function()
        if not TradeFrame or not TradeFrame:IsShown() then
            Trade.StopFill()
            return
        end
        local entry = table.remove(Trade.fillQueue, 1)
        if not entry then
            Trade.StopFill()
            if added > 0 then
                ns.Print(string.format("added %d %s to the trade for order #%d.",
                    added, added == 1 and noun[1] or noun[2], order.id))
            end
            return
        end
        local _, itemLink, useItem = Container()
        if useItem and itemLink(entry.bag, entry.slot) == entry.link then
            useItem(entry.bag, entry.slot)
            added = added + 1
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
