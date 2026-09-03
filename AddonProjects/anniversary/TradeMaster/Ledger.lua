local addonName, ns = ...

ns.Ledger = ns.Ledger or {}
local Ledger = ns.Ledger

local MAX_ENTRIES = 500

-- units: { [itemID] = qty } of finished products handed over in the trade.
function Ledger.Record(player, orderID, copper, units, now)
    if not copper or copper == 0 then return end

    ns.db.ledger.entries = ns.db.ledger.entries or {}
    table.insert(ns.db.ledger.entries, 1, {
        at = now, player = player, orderID = orderID, copper = copper, units = units,
        profession = ns.db.activeProfession,
    })
    for i = #ns.db.ledger.entries, MAX_ENTRIES + 1, -1 do
        table.remove(ns.db.ledger.entries, i)
    end

    ns.db.ledger.allTimeCopper = (ns.db.ledger.allTimeCopper or 0) + copper

    local count = 0
    for _, q in pairs(units or {}) do count = count + q end
    ns.db.ledger.allTimeUnits = (ns.db.ledger.allTimeUnits or ns.db.ledger.allTimeGems or 0) + count

    local st = ns.Players.Get(ns.db, player)
    st.lifetimeCopper = (st.lifetimeCopper or 0) + copper
    st.lifetimeOrders = (st.lifetimeOrders or 0) + 1
end

-- A correction to money already recorded, not a new sale: the totals move by the
-- difference and the customer's order count stays where it is. Kept as its own
-- entry so the history says what happened instead of being quietly rewritten.
function Ledger.Adjust(player, orderID, delta, now)
    if not delta or delta == 0 then return end

    ns.db.ledger.entries = ns.db.ledger.entries or {}
    table.insert(ns.db.ledger.entries, 1, {
        at = now, player = player, orderID = orderID, copper = delta,
        adjusted = true, profession = ns.db.activeProfession,
    })
    for i = #ns.db.ledger.entries, MAX_ENTRIES + 1, -1 do
        table.remove(ns.db.ledger.entries, i)
    end

    ns.db.ledger.allTimeCopper = (ns.db.ledger.allTimeCopper or 0) + delta
    local st = ns.Players.Get(ns.db, player)
    st.lifetimeCopper = (st.lifetimeCopper or 0) + delta
end

-- Pure. Sums entries newer than `since`. Accepts the legacy `gems` field.
function Ledger.SumSince(entries, since)
    local copper, units, n = 0, 0, 0
    for _, e in ipairs(entries or {}) do
        if (e.at or 0) >= since then
            copper = copper + (e.copper or 0)
            n = n + 1
            for _, q in pairs(e.units or e.gems or {}) do units = units + q end
        end
    end
    return copper, units, n
end

function Ledger.AllTimeUnits()
    local L = ns.db.ledger
    return L.allTimeUnits or L.allTimeGems or 0
end

function Ledger.Money(copper)
    if GetCoinTextureString then return GetCoinTextureString(copper or 0) end
    return string.format("%dg", math.floor((copper or 0) / 10000))
end

function Ledger.TopCustomers(limit)
    local list = {}
    for name, st in pairs(ns.db.players) do
        if (st.lifetimeCopper or 0) > 0 then
            list[#list + 1] = { name = name, copper = st.lifetimeCopper,
                orders = st.lifetimeOrders or 0 }
        end
    end
    table.sort(list, function(a, b) return a.copper > b.copper end)
    while #list > (limit or 10) do table.remove(list) end
    return list
end

function Ledger.Report()
    local L = ns.db.ledger
    local now = ns.Now()
    local noun = ns.Prof.Current().craftNoun
    local dayCopper, dayUnits = Ledger.SumSince(L.entries, now - 86400)
    local weekCopper = Ledger.SumSince(L.entries, now - 604800)
    local allUnits = Ledger.AllTimeUnits()

    ns.Print("income:")
    ns.Print(string.format("  all time  %s over %d %s", Ledger.Money(L.allTimeCopper or 0), allUnits, noun[2]))
    ns.Print(string.format("  last 24h  %s over %d %s", Ledger.Money(dayCopper), dayUnits, noun[2]))
    ns.Print(string.format("  last 7d   %s", Ledger.Money(weekCopper)))

    local avg = allUnits > 0 and math.floor((L.allTimeCopper or 0) / allUnits) or 0
    ns.Print(string.format("  per %s   %s", noun[1], Ledger.Money(avg)))

    local top = Ledger.TopCustomers(5)
    if #top > 0 then
        ns.Print("top customers:")
        for _, c in ipairs(top) do
            ns.Print(string.format("  %s  %s over %d orders", c.name, Ledger.Money(c.copper), c.orders))
        end
    end
end
