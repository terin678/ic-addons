local addonName, ns = ...

ns.Orders = ns.Orders or {}
local Orders = ns.Orders

Orders.STATUS = { "pending", "grouped", "mats", "done", "cancelled" }

--------------------------------------------------------------------------------
-- Creation and lookup
--------------------------------------------------------------------------------

-- Case-insensitive on purpose. A manually typed name ("wokenough") and the
-- live trade partner's actual casing ("Wokenough") are the same player; an
-- exact match left the order un-credited while the payment landed only in
-- the global ledger. Stored casing is kept, only the comparison is folded.
function Orders.Open(player)
    if not player then return nil end
    local key = player:lower()
    for _, o in ipairs(ns.db.orders) do
        if o.player and o.player:lower() == key
            and o.status ~= "done" and o.status ~= "cancelled" then
            return o
        end
    end
    return nil
end

function Orders.Create(player, source, requestText, matched, now, status, profession)
    local o = {
        id = ns.db.nextOrderID,
        player = player,
        source = source,
        profession = profession or ns.db.activeProfession,
        requestText = ns.Util.StripEscapes(requestText or ""),
        createdAt = now,
        updatedAt = now,
        status = status or "pending",
        items = {},
        matsReceived = {},
        unmatchedMats = {},
        needsSplit = false,
        copperIn = 0,
        transcript = {},
        notes = "",
    }
    ns.db.nextOrderID = ns.db.nextOrderID + 1

    for _, h in ipairs(matched or {}) do
        o.items[#o.items + 1] = {
            itemID = h.itemID,
            qty = h.qtyHint or 1,
            qtySource = h.qtyHint and "text" or "default",
        }
    end

    table.insert(ns.db.orders, 1, o)
    return o
end

-- The book an order's items live in: its own profession's, falling back to
-- the active one for orders created before professions existed.
function Orders.BookFor(o)
    local key = o and o.profession
    if key and ns.db.professions and ns.db.professions[key] then
        return ns.db.professions[key].book or {}
    end
    return ns.Book()
end

-- A repeat request from someone with an order already open updates it rather
-- than creating a second one.
function Orders.Record(player, source, text, matched, now, profession)
    local o = Orders.Open(player)
    if not o then
        o = Orders.Create(player, source, text, matched, now, nil, profession)
        ns.Print(string.format("|cff44ff44order #%d opened|r for %s: %s",
            o.id, player, Orders.Summarise(o)))
        if ns.Tracker then ns.Tracker.Refresh() end
        return o, true
    end

    local added = false
    for _, h in ipairs(matched or {}) do
        local found = false
        for _, it in ipairs(o.items) do
            if it.itemID == h.itemID then found = true break end
        end
        if not found then
            o.items[#o.items + 1] = {
                itemID = h.itemID,
                qty = h.qtyHint or 1,
                qtySource = h.qtyHint and "text" or "default",
            }
            added = true
        end
    end
    o.updatedAt = now
    if added then
        ns.Print(string.format("order #%d updated: %s", o.id, Orders.Summarise(o)))
    end
    return o, false
end

-- Adds a product to an order by hand, or bumps the count when it is already
-- there. Anything typed in is "manual": the mats they hand over still win.
function Orders.AddItem(o, itemID, qty, now)
    qty = math.max(1, math.floor(qty or 1))
    for _, it in ipairs(o.items) do
        if it.itemID == itemID then
            it.qty = (it.qty or 0) + qty
            it.qtySource = "manual"
            o.updatedAt = now
            return it, false
        end
    end
    local it = { itemID = itemID, qty = qty, qtySource = "manual" }
    o.items[#o.items + 1] = it
    o.updatedAt = now
    return it, true
end

function Orders.RemoveItem(o, index, now)
    local it = table.remove(o.items, index)
    if not it then return nil end
    o.updatedAt = now
    -- The split prompt exists because some item's quantity was a guess. Once
    -- that item is gone the prompt is asking about nothing. (CutMaster 1.2.0)
    local stillAmbiguous = false
    for _, other in ipairs(o.items) do
        if other.qtySource == "ambiguous" then
            stillAmbiguous = true
            break
        end
    end
    o.needsSplit = stillAmbiguous
    return it
end

-- Pure. Where an item sits on the order, so callers that know the itemID (the
-- tracker row, a slash command) can use the index-based RemoveItem.
function Orders.IndexOfItem(o, itemID)
    for i, it in ipairs(o.items) do
        if it.itemID == itemID then return i end
    end
    return nil
end

-- Case-insensitive substring match on the item's name: someone typing a slash
-- command has the name in front of them, not the itemID. (CutMaster 1.2.0)
function Orders.FindItemByName(o, text)
    text = ns.Util.Normalize(text or "")
    if text == "" then return nil end
    local book = Orders.BookFor(o)
    for _, it in ipairs(o.items) do
        local e = book[it.itemID]
        if e and e.name and ns.Util.Normalize(e.name):find(text, 1, true) then
            return it.itemID
        end
    end
    return nil
end

-- Pure. Book entries matching what someone typed. An exact name wins on its own;
-- otherwise every entry containing the text, best (shortest, so closest) first.
function Orders.FindInBook(book, text)
    text = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return {} end

    local matches = {}
    for itemID, e in pairs(book or {}) do
        local name = (e.name or ""):lower()
        if name == text then return { { itemID = itemID, entry = e } } end
        if name:find(text, 1, true) then
            matches[#matches + 1] = { itemID = itemID, entry = e }
        end
    end
    table.sort(matches, function(a, b)
        local na, nb = a.entry.name or "", b.entry.name or ""
        if #na ~= #nb then return #na < #nb end
        return na < nb
    end)
    return matches
end

-- Pure. Sets what the customer has paid and reports the difference, so the
-- ledger can be corrected by that much rather than double-counting the sale.
function Orders.SetPaid(o, copper, now)
    copper = math.max(0, math.floor(copper or 0))
    local delta = copper - (o.copperIn or 0)
    o.copperIn = copper
    o.updatedAt = now
    return delta
end

function Orders.AddTranscript(player, dir, text, now)
    local o = Orders.Open(player)
    if not o then return end
    o.transcript[#o.transcript + 1] =
        { at = now, dir = dir, text = ns.Util.StripEscapes(text) }
    o.updatedAt = now
end

function Orders.SetStatus(o, status, now)
    o.status = status
    o.updatedAt = now
    if status == "done" then o.completedAt = now end
end

function Orders.Summarise(o)
    local book = Orders.BookFor(o)
    local parts = {}
    for _, it in ipairs(o.items) do
        local e = book[it.itemID]
        local name = e and (e.link or e.name) or tostring(it.itemID)
        parts[#parts + 1] = string.format("%s x%d%s", name, it.qty,
            it.qtySource == "mats" and "" or "?")
    end
    if #parts == 0 then return "(nothing specified yet)" end
    return table.concat(parts, ", ")
end

--------------------------------------------------------------------------------
-- Quantity inference
--------------------------------------------------------------------------------

-- Pure. Customers rarely state a quantity: they hand over the mats and expect
-- the matching number crafted. So the mats are authoritative and any number
-- parsed from the text is only a hint.
--
-- order.items is mutated in place. Returns needsSplit, addedItems.
--
-- book maps productItemID -> { reagents = { [reagentID] = countPerCraft },
-- numMade = itemsPerCraft }. ambiguityMax caps how many recipes a reagent may
-- feed before "mats for something they never asked for" stops guessing: with
-- gems one raw feeds a handful of cuts, with herbs or cloth it feeds dozens.
function Orders.InferQuantities(order, matsReceived, book, ambiguityMax)
    ambiguityMax = ambiguityMax or 1
    local needsSplit = false
    local added = {}
    order.unmatchedMats = order.unmatchedMats or {}

    for rawID, count in pairs(matsReceived) do
        local candidates = {}
        for _, it in ipairs(order.items) do
            local entry = book[it.itemID]
            if entry and entry.reagents and entry.reagents[rawID] then
                candidates[#candidates + 1] = it
            end
        end

        if #candidates == 1 then
            local entry = book[candidates[1].itemID]
            local per = entry.reagents[rawID] or 1
            candidates[1].qty = math.floor(count / per) * (entry.numMade or 1)
            candidates[1].qtySource = "mats"
            order.unmatchedMats[rawID] = nil
        elseif #candidates > 1 then
            needsSplit = true
            for _, it in ipairs(candidates) do
                it.qtySource = "ambiguous"
            end
        else
            -- Mats for something they never asked for. Add it only when the
            -- reagent points at exactly one thing we can make; otherwise leave
            -- it for the user to resolve rather than guess.
            local options = {}
            for productID, entry in pairs(book) do
                if entry.reagents and entry.reagents[rawID] and entry.bindType ~= 1 and not entry.stale then
                    options[#options + 1] = productID
                end
            end
            table.sort(options)
            if #options >= 1 and #options <= ambiguityMax then
                local productID = options[1]
                local entry = book[productID]
                local per = entry.reagents[rawID] or 1
                local item = {
                    itemID = productID,
                    qty = math.floor(count / per) * (entry.numMade or 1),
                    qtySource = "mats",
                    unrequested = true,
                }
                order.items[#order.items + 1] = item
                added[#added + 1] = item
                order.unmatchedMats[rawID] = nil
            elseif #options > ambiguityMax then
                order.unmatchedMats[rawID] = { count = count, options = options }
            end
        end
    end

    order.needsSplit = needsSplit
    return needsSplit, added
end

--------------------------------------------------------------------------------
-- Maintenance
--------------------------------------------------------------------------------

function Orders.Prune(now, keepDays)
    local cutoff = now - (keepDays * 86400)
    local kept = {}
    for _, o in ipairs(ns.db.orders) do
        if o.status ~= "done" or (o.completedAt or o.updatedAt or now) > cutoff then
            kept[#kept + 1] = o
        end
    end
    ns.db.orders = kept
end

-- Pure. What the Orders tab shows, and how many finished orders it is holding
-- back. Finished orders are never deleted by hiding them: they stay in the saved
-- variables until Prune, and the count is what tells you they are still there.
function Orders.Visible(orders, showFinished)
    local out, hidden = {}, 0
    for _, o in ipairs(orders or {}) do
        local finished = (o.status == "done" or o.status == "cancelled")
        if showFinished or not finished then
            out[#out + 1] = o
        else
            hidden = hidden + 1
        end
    end
    return out, hidden
end

function Orders.OpenList()
    local out = {}
    for _, o in ipairs(ns.db.orders) do
        if o.status == "grouped" or o.status == "mats" then out[#out + 1] = o end
    end
    return out
end

function Orders.ActiveList()
    local out = {}
    for _, o in ipairs(ns.db.orders) do
        if o.status ~= "done" and o.status ~= "cancelled" then out[#out + 1] = o end
    end
    return out
end

-- Not counted as open work, since they may never join, but still worth seeing
-- and still cancellable: the tracker needs something to render for them.
-- (CutMaster 1.2.0)
function Orders.PendingList()
    local out = {}
    for _, o in ipairs(ns.db.orders) do
        if o.status == "pending" then out[#out + 1] = o end
    end
    return out
end

function Orders.PendingCount()
    return #Orders.PendingList()
end

function Orders.ByID(id)
    for _, o in ipairs(ns.db.orders) do
        if o.id == id then return o end
    end
    return nil
end

-- Pure over the order list. A pending order nobody ever joined for is not work
-- in progress: they missed the invite, alt-tabbed, or changed their mind. Left
-- alone it sits in the queue looking like a live customer. Only "pending" is
-- touched -- once someone has actually grouped up, a slow reply is a different
-- problem and cancelling it out from under them would be wrong. (CutMaster 1.2.0)
function Orders.ExpireStale(orders, now, timeoutSec)
    local expired = {}
    -- 0 means the timeout is switched off. Without this the arithmetic below is
    -- "older than nothing", which expires every pending order the moment it is
    -- created -- the exact opposite of what switching it off should do.
    if not timeoutSec or timeoutSec <= 0 then return expired end
    for _, o in ipairs(orders or {}) do
        if o.status == "pending" and (now - (o.createdAt or now)) >= timeoutSec then
            Orders.SetStatus(o, "cancelled", now)
            expired[#expired + 1] = o
        end
    end
    return expired
end

-- Declining is the same thing said out loud: no reason to wait out the timeout
-- once they have answered. (CutMaster 1.2.0)
function Orders.CancelPending(player, now)
    local o = Orders.Open(player)
    if o and o.status == "pending" then
        Orders.SetStatus(o, "cancelled", now)
        return o
    end
    return nil
end

-- Polling every timeout would let one sit for nearly twice the window. A minute
-- is close enough without being wasteful.
local POLL_INTERVAL = 60

function Orders.Poll()
    if not ns.db or not ns.Enabled() then return end
    local timeout = ns.db.settings.orders.pendingTimeoutSec
    if not timeout or timeout <= 0 then return end

    local expired = Orders.ExpireStale(ns.db.orders, ns.Now(), timeout)
    -- A first poll after importing a CutMaster order book can find a whole
    -- backlog at once, and one line each would be a wall of chat.
    if #expired > 3 then
        ns.Print(string.format("|cff888888%d pending orders expired, never joined.|r", #expired))
    else
        for _, o in ipairs(expired) do
            ns.Print(string.format(
                "|cff888888order #%d for %s expired, never joined within %d min.|r",
                o.id, o.player, math.floor(timeout / 60)))
        end
    end
    if #expired > 0 and ns.Tracker then ns.Tracker.Refresh() end
end

function Orders.StartExpiryTicker()
    if Orders.expiryTicker then Orders.expiryTicker:Cancel() end
    Orders.expiryTicker = C_Timer.NewTicker(POLL_INTERVAL, Orders.Poll)
end

-- Promote anyone who has now actually joined the group.
function Orders.PromoteGrouped(now)
    if not ns.Enabled() then return 0 end
    local promoted = 0
    for _, o in ipairs(ns.db.orders) do
        if o.status == "pending" and (UnitInParty(o.player) or UnitInRaid(o.player)) then
            Orders.SetStatus(o, "grouped", now)
            promoted = promoted + 1
            ns.Print(string.format("|cff44ff44%s joined.|r Order #%d is now open: %s",
                o.player, o.id, Orders.Summarise(o)))
        end
    end
    if promoted > 0 and ns.Tracker then ns.Tracker.Notify() end
    return promoted
end
