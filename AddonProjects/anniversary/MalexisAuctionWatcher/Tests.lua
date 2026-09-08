-- Tests.lua - Pure-function checks, run in game with /maw test
--
-- The harness -- Case, Eq, Near, With, Run -- is LibICCore's. Nothing here touches
-- the saved variables or the auction house: every case builds its own input and
-- checks arithmetic that is otherwise only visible as a line on a chart.
local MAW = _G.MalexisAuctionWatcher or {}

local T = MAW.Tests

--------------------------------------------------------------------------------
-- Recipe series
--------------------------------------------------------------------------------

-- A point as MAW:GetSeries emits it. n == 0 is "no data for this slot".
local function pt(label, avg)
    if not avg then return { label = label, n = 0 } end
    return { label = label, low = avg, avg = avg, high = avg, n = 1 }
end

T.Case("Recipe series: a batch is worth the product times the count, less the cut", function()
    local s = MAW.ComposeRecipeSeries({
        count = 1, labels = { "1/1" }, cut = 0.05,
        productName = "Flask", productCount = 2,
        productPoints = { pt("1/1", 100) },
        mats = { { name = "Herb", count = 3, points = { pt("1/1", 10) } } },
    })
    T.Near(s.value[1], 190, "100 each, two of them, five percent gone")
    T.Near(s.cost[1], 30, "three herbs at ten")
    T.Near(s.margin[1], 160, "what is left")
    T.Eq(s.complete, 1, "one priced slot")
    T.Eq(s.best.index, 1, "and it is the best")
end)

T.Case("Recipe series: a missing material leaves a hole, not a zero", function()
    -- An unknown cost drawn as zero reads as a free craft, which is the one
    -- wrong answer this must never give.
    local s = MAW.ComposeRecipeSeries({
        count = 3, labels = { "a", "b", "c" }, cut = 0,
        productName = "Flask", productCount = 1,
        productPoints = { pt("a", 100), pt("b", 100), pt("c", 100) },
        mats = {
            { name = "Herb", count = 1, points = { pt("a", 10), pt("b", 10), pt("c", 10) } },
            { name = "Vial", count = 1, points = { pt("a", 5), pt("b", nil), pt("c", 5) } },
        },
    })
    T.Near(s.cost[1], 15, "both priced")
    T.Eq(s.cost[2], nil, "one material unpriced, so the batch cost is unknown")
    T.Eq(s.margin[2], nil, "and so is the margin")
    T.Near(s.value[2], 100, "the product still has a price")
    T.Near(s.mats[1].values[2], 10, "and so does the material that was scanned")
    T.Eq(s.mats[2].values[2], nil, "the one that was not keeps its own gap")
    T.Eq(s.complete, 2, "two slots fully priced")
end)

T.Case("Recipe series: a vendor material costs the same every slot", function()
    local s = MAW.ComposeRecipeSeries({
        count = 2, labels = { "a", "b" }, cut = 0,
        productName = "Flask", productCount = 1,
        productPoints = { pt("a", 100), pt("b", 100) },
        mats = { { name = "Vial", count = 3, vendor = 5 } },
    })
    T.Near(s.vendorCost, 15, "three at five, fixed")
    T.Near(s.cost[1], 15, "charged in every slot")
    T.Near(s.cost[2], 15, "including the ones with no scan")
    T.Eq(s.mats[1].values, nil, "and never drawn as a line: it would be flat")
end)

T.Case("Recipe series: a bind-on-pickup material is left out, not a hole", function()
    -- Primal Nether is never on the auction house, so a slot with no price for it
    -- is every slot. Treating that as a missing price left every epic craft with
    -- no cost line at all.
    local s = MAW.ComposeRecipeSeries({
        count = 2, labels = { "a", "b" }, cut = 0,
        productName = "Boots", productCount = 1,
        productPoints = { pt("a", 500), pt("b", 500) },
        mats = {
            { name = "Primal Nether", count = 1, bop = true },
            { name = "Primal Fire", count = 4, points = { pt("a", 10), pt("b", 20) },
              tsm = { market = 12 } },
        },
    })
    T.Near(s.cost[1], 40, "the fire alone")
    T.Near(s.cost[2], 80, "in every slot")
    T.Eq(s.complete, 2, "both slots priced")
    T.Eq(s.bop[1], "Primal Nether", "and the nether is named")
    T.Eq(s.mats[1].values, nil, "with no line of its own")
    T.Near(s.tsm.cost.market, 48, "the TSM cost level is without it too")
end)

T.Case("Recipe profit: a bind-on-pickup material is priced around, a missing one is not", function()
    local cost, missing, bop = MAW.SumMaterials({
        { item = "Primal Fire", count = 4, unit = 10 },
        { item = "Imbued Vial", count = 1, unit = 20, vendor = 20 },
        { item = "Primal Nether", count = 1, bop = true },
    })
    T.Near(cost, 60, "fire and vial")
    T.Eq(#missing, 0, "nothing is missing")
    T.Eq(bop[1], "Primal Nether", "the nether is what you bring")

    cost, missing, bop = MAW.SumMaterials({
        { item = "Primal Fire", count = 4 },
        { item = "Primal Nether", count = 1, bop = true },
    })
    T.Near(cost, 0, "nothing priced")
    T.Eq(missing[1], "Primal Fire", "an unpriced tradeable is still missing")
    T.Eq(#bop, 1, "and the nether is still separate from it")

    T.Eq(#select(2, MAW.SumMaterials({})), 0, "no materials is no gaps")

    -- The flag is found once and written onto the material, so recipes saved before
    -- it existed catch up the first time they are priced.
    local nether = { item = "Primal Nether", count = 1 }
    T.Eq(MAW:IsBoPMaterial(nether), true, "known by name when the item cache is cold")
    T.Eq(nether.bop, true, "and remembered on the material")
    T.Eq(MAW:IsBoPMaterial({ item = "Imbued Vial", count = 1, vendor = 20 }), false,
        "a vendor material is never")
    T.Eq(MAW:IsBoPMaterial({ item = "Primal Fire", count = 1, bop = false }), false,
        "and one already resolved is not asked again")
end)

T.Case("Recipe series: best and worst skip the slots with no margin", function()
    local s = MAW.ComposeRecipeSeries({
        count = 4, labels = { "a", "b", "c", "d" }, cut = 0,
        productName = "Flask", productCount = 1,
        productPoints = { pt("a", 50), pt("b", nil), pt("c", 90), pt("d", 70) },
        mats = { { name = "Herb", count = 1, points = { pt("a", 10), pt("b", 10), pt("c", 10), pt("d", 10) } } },
    })
    T.Eq(s.best.index, 3, "the dearest product makes the best batch")
    T.Eq(s.best.label, "c", "labelled by its slot")
    T.Eq(s.worst.index, 1, "and the cheapest the worst")
    T.Eq(s.complete, 3, "the unpriced slot counts for neither")

    T.Eq(MAW.RecipeSlotAt(s, 4), 4, "the slot asked for, when it has a margin")
    T.Eq(MAW.RecipeSlotAt(s, 2), 1, "else the most recent one before it")
    T.Eq(MAW.RecipeSlotAt(s, 99), 4, "an index past the end is clamped")
end)

T.Case("Recipe series: an untracked item is named, not guessed at", function()
    local s = MAW.ComposeRecipeSeries({
        count = 2, labels = { "a", "b" }, cut = 0.05,
        productName = "Flask", productCount = 1,
        productPoints = {},
        mats = { { name = "Herb", count = 1, points = { pt("a", 10), pt("b", 10) } } },
        missing = { "Flask" },
    })
    T.Eq(s.value[1], nil, "no product price anywhere")
    T.Eq(s.margin[1], nil, "so no margin")
    T.Near(s.cost[1], 10, "the materials are still priced")
    T.Eq(s.complete, 0, "nothing is complete")
    T.Eq(s.best, nil, "and there is no best slot to name")
    T.Eq(s.missing[1], "Flask", "the summary can say which item to add")
end)

T.Case("Recipe series: a recipe with no materials at all still prices", function()
    local s = MAW.ComposeRecipeSeries({
        count = 1, labels = { "a" }, cut = 0,
        productName = "Flask", productCount = 1,
        productPoints = { pt("a", 100) },
        mats = {},
    })
    T.Near(s.cost[1], 0, "nothing to buy")
    T.Near(s.margin[1], 100, "so the whole value is margin")
end)

T.Case("Recipe series: nothing tracked at all is empty, not an error", function()
    -- What the History tab passes when the recipe names no item this character
    -- has ever priced. The chart draws its axis and says so.
    local s = MAW.ComposeRecipeSeries({
        count = 0, labels = {}, cut = 0.05,
        productName = "Flask", productCount = 1,
        productPoints = {}, mats = {}, missing = { "Flask", "Herb" },
    })
    T.Eq(s.complete, 0, "no priced slots")
    T.Eq(MAW.RecipeSlotAt(s, 24), nil, "an hour marker on an empty series")
    T.Eq(MAW.RecipeSlotAt(s, nil), nil, "and no marker at all")
end)

T.Case("Recipe series: a TSM average is scaled like the line it belongs to", function()
    -- TSM has no daily history, only these two numbers, so they are levels. To
    -- sit on the same axis as the lines they have to take the same arithmetic:
    -- a batch after the cut, a material times how many the recipe needs.
    local s = MAW.ComposeRecipeSeries({
        count = 1, labels = { "a" }, cut = 0.05,
        productName = "Flask", productCount = 2,
        productPoints = { pt("a", 100) },
        productTsm = { market = 110, historical = 90 },
        mats = {
            { name = "Herb", count = 3, points = { pt("a", 10) },
              tsm = { market = 12, historical = 8 } },
            { name = "Vial", count = 2, vendor = 5 },
        },
    })
    T.Near(s.tsm.value.market, 209, "110 each, two of them, five percent gone")
    T.Near(s.tsm.value.historical, 171, "and the same for the 60 day")
    T.Near(s.mats[1].tsm.market, 36, "three herbs at twelve")
    T.Near(s.tsm.cost.market, 46, "plus the vendor vial, which never moves")

    -- One material without TSM data means the batch cost has no TSM level, the
    -- same rule the cost line itself follows.
    local partial = MAW.ComposeRecipeSeries({
        count = 1, labels = { "a" }, cut = 0,
        productName = "Flask", productCount = 1,
        productPoints = { pt("a", 100) },
        mats = {
            { name = "Herb", count = 1, points = { pt("a", 10) }, tsm = { market = 12 } },
            { name = "Vial", count = 1, points = { pt("a", 5) } },
        },
    })
    T.Eq(partial.tsm.cost, nil, "no level without every material")
    T.Near(partial.mats[1].tsm.market, 12, "the one that has it still draws")
    T.Eq(partial.mats[2].tsm, nil, "the one that does not, does not")
    T.Eq(partial.tsm.value, nil, "and no TSM for the product means no level for the batch")
end)

--------------------------------------------------------------------------------
-- TSM: what is derived from the feed, and what it decides
--------------------------------------------------------------------------------

T.Case("TSM summary: the columns fall back to region figures, and the rest is picked out", function()
    local full = MAW.TsmSummary({
        DBMinBuyout = 90, DBMarket = 100, DBRecent = 95, DBHistorical = 120,
        DBRegionMarketAvg = 110, DBRegionHistorical = 130, DBRegionSaleAvg = 105,
        DBRegionSaleRate = 0.42, DBRegionSoldPerDay = 3.5,
        SmartAvgBuy = 80, AvgBuy = 70, AvgSell = 140, SaleRate = 0.6, NumExpires = 4,
        VendorBuy = 20, MatPrice = 85, Crafting = 60,
    })
    T.Eq(full.market, 100, "the realm market value")
    T.Eq(full.marketKey, "DBMarket", "and which field it was")
    T.Eq(full.historical, 120, "the realm historical")
    T.Eq(full.velocity.rate, 0.42, "region sale rate")
    T.Eq(full.velocity.perDay, 3.5, "sold per day")
    T.Eq(full.velocity.mine, 0.6, "and your own")
    T.Eq(full.paid, 80, "what the copies you hold cost")
    T.Eq(full.paidKey, "SmartAvgBuy", "from the smart average when there is one")
    T.Eq(full.sold, 140, "what you sold for")
    T.Eq(full.expires, 4, "expired since the last sale")
    T.Eq(full.fallback.vendorBuy, 20, "a vendor sells it")
    T.Eq(full.fallback.matPrice, 85, "TSM's material cost")

    -- A realm with no data of its own: the region stands in, and says so.
    local region = MAW.TsmSummary({ DBRegionMarketAvg = 110, DBRegionSaleAvg = 105, AvgBuy = 70 })
    T.Eq(region.market, 110, "region market average")
    T.Eq(region.marketKey, "DBRegionMarketAvg", "named")
    T.Eq(region.historical, 105, "the sale average is the last resort for both columns")
    T.Eq(region.paid, 70, "the plain average when you hold none")
    T.Eq(region.paidKey, "AvgBuy", "and it says which")
    T.Eq(region.velocity.rate, nil, "no rate is no rate")

    local empty = MAW.TsmSummary(nil)
    T.Eq(empty.market, nil, "nothing is nothing")
    T.Eq(type(empty.velocity), "table", "but the shape is always there")
    T.Eq(type(empty.fallback), "table", "for every reader")
end)

T.Case("TSM velocity: a rate is graded against the Convert floor, and none is none", function()
    T.Eq(MAW.VelocityGrade(0.5, 0.1), "sells", "half of auctions selling is a seller")
    T.Eq(MAW.VelocityGrade(0.3, 0.1), "sells", "exactly at the mark")
    T.Eq(MAW.VelocityGrade(0.2, 0.1), "slow", "between the floor and the mark")
    T.Eq(MAW.VelocityGrade(0.1, 0.1), "slow", "exactly at the floor")
    T.Eq(MAW.VelocityGrade(0.05, 0.1), "dead", "under it")
    T.Eq(MAW.VelocityGrade(nil, 0.1), nil, "no data is not a grade")
    T.Eq(MAW.VelocityGrade(0.05, 0), "slow", "with the floor off nothing is dead")
    T.Eq(MAW.VelocityGrade(0.6, 0.1, 0.7), "slow", "and the mark can be moved")
end)

T.Case("TSM convert gate: a product that does not sell is not a conversion", function()
    local function ref(rate) return { velocity = { rate = rate } } end

    T.Eq(MAW.ConvertAllowed(ref(0.4), 0.1, true), true, "sells well enough")
    T.Eq(select(2, MAW.ConvertAllowed(ref(0.4), 0.1, true)), "sells 40%", "and the row says how well")

    local ok, why = MAW.ConvertAllowed(ref(0.05), 0.1, true)
    T.Eq(ok, false, "under the floor")
    T.True(why:find("under the 10%% floor", 1) ~= nil, "with the floor in the reason")

    ok, why = MAW.ConvertAllowed(ref(nil), 0.1, true)
    T.Eq(ok, false, "TSM knows the item and recorded no sales: that is a no")
    T.Eq(why, "no sales recorded region-wide", "said plainly")

    ok, why = MAW.ConvertAllowed(nil, 0.1, true)
    T.Eq(ok, true, "never asked TSM about it: nothing is known against it")
    T.Eq(why, "sale rate unknown", "and the row admits that")
    T.Eq(MAW.ConvertAllowed({ market = 100 }, 0.1, true), true,
        "a reference from before the feed carried velocity is the same as none")

    T.Eq(MAW.ConvertAllowed(ref(nil), 0.1, false), true, "feed off, gate off")
    T.Eq(MAW.ConvertAllowed(ref(nil), 0, true), true, "floor at zero, gate off")
end)

T.Case("TSM fallback: what stands in for a scan, in order", function()
    local ref = { market = 100, historical = 120,
        fallback = { vendorBuy = 20, matPrice = 85, crafting = 60 } }
    local price, key = MAW.FallbackPrice(ref, "material")
    T.Eq(price, 20, "a vendor that sells it settles a material")
    T.Eq(key, "vendorbuy", "and says so")
    T.Eq(MAW.FALLBACK_SOURCES[key], true, "which Movers refuse to act on")

    ref.fallback.vendorBuy = nil
    T.Eq(MAW.FallbackPrice(ref, "material"), 100, "then the market")
    ref.market = nil
    price, key = MAW.FallbackPrice(ref, "material")
    T.Eq(price, 85, "then TSM's own material cost")
    T.Eq(key, "tsmmat", "named as such")
    ref.fallback.matPrice = nil
    T.Eq(select(2, MAW.FallbackPrice(ref, "material")), "tsmcraft", "then what it costs to craft")
    ref.fallback.crafting = nil
    T.Eq(select(2, MAW.FallbackPrice(ref, "material")), "tsm60", "then the long average")

    -- A product is sold, not bought: only the market averages apply.
    local product = { market = 100, historical = 120, fallback = { vendorBuy = 20, matPrice = 85 } }
    price, key = MAW.FallbackPrice(product, "product")
    T.Eq(price, 100, "a product is worth its market value")
    T.Eq(key, "tsm14", "from the 14-day column")
    product.market = nil
    T.Eq(MAW.FallbackPrice(product, "product"), 120, "or the 60-day one")
    product.historical = nil
    T.Eq(MAW.FallbackPrice(product, "product"), nil, "and never a vendor's price")

    T.Eq(MAW.FallbackPrice(nil, "material"), nil, "no reference, no price")
    T.Eq(MAW.FallbackPrice({}, "material"), nil, "an empty one neither")
end)

--------------------------------------------------------------------------------
-- Schedule: the week as a grid
--------------------------------------------------------------------------------

-- Tuesday 8 September 2026, local midnight, and moments relative to it.
local TUE = time({ year = 2026, month = 9, day = 8, hour = 0, min = 0, sec = 0 })
local function at(days, hour) return TUE + days * 86400 + hour * 3600 end

T.Case("Schedule: a moment lands on a weekday, a block and a week that starts on reset day", function()
    local slot, wday, block, week = MAW.ScheduleSlot(at(0, 21), 0, 3)
    T.Eq(wday, 3, "a Tuesday")
    T.Eq(block, 6, "21:00 is the last block")
    T.Eq(slot, 18, "(3 - 1) * 6 + 6")
    T.Eq(select(4, MAW.ScheduleSlot(at(7, 21), 0, 3)), week + 1, "a week later is the next week")
    T.Eq(select(4, MAW.ScheduleSlot(at(6, 21), 0, 3)), week, "Monday night is still this week")
    T.Eq(select(4, MAW.ScheduleSlot(at(-1, 21), 0, 3)), week - 1, "and Monday before it was last week")
    T.Eq(select(4, MAW.ScheduleSlot(at(-1, 21), 0, 2)), week, "unless the week starts on Monday")

    -- The clock offset moves the block, not the data: 21:00 read three hours ahead is
    -- midnight, the first block of Wednesday.
    local s2, w2, b2 = MAW.ScheduleSlot(at(0, 21), 3 * 3600, 3)
    T.Eq(w2, 4, "Wednesday under a clock three hours ahead")
    T.Eq(b2, 1, "in its first block")
    T.Eq(s2, 19, "the next slot along")

    T.Eq(MAW.SlotPosition(18, 3), 6, "Tuesday 20-24 is the sixth block of a week that starts on Tuesday")
    T.Eq(MAW.SlotPosition(1, 3), 5 * 6 + 1, "and Sunday 00-04 is deep in it")
end)

T.Case("Schedule: an expectation is the mean of weekly means, judged week against week", function()
    -- Four completed weeks of a Tuesday-evening scan at 100, 110, 90, 100, a Saturday
    -- afternoon at 300 every week, one Wednesday morning, and this week's Tuesday at 104.
    local obs = {}
    local function add(t, p) obs[#obs + 1] = t; obs[#obs + 1] = p end
    local tue = { 100, 110, 90, 100 }
    for w = 0, 3 do
        add(at(w * 7, 21), tue[w + 1])
        add(at(w * 7, 21.5), tue[w + 1])        -- a second scan the same evening counts once
        add(at(w * 7 + 4, 13), 300)             -- Saturday 12-16
    end
    add(at(1, 9), 120)                          -- Wednesday 08-12, one week only
    add(at(28, 21), 104)                        -- this week's Tuesday
    local now = at(28 + 2, 21)                  -- Thursday evening of the fifth week

    local s = MAW.ComposeSchedule(obs, now, { offset = 0, weeks = 8, tolerancePct = 10, minWeeks = 2, weekStart = 3 })
    local tueSlot = s.slots[18]
    T.Near(tueSlot.expected, 100, "the mean of the four weekly means")
    T.Eq(tueSlot.weeksSeen, 4, "four complete weeks")
    T.Eq(tueSlot.hits, 2, "100 and 100 sit within 10% of the other weeks")
    T.Eq(tueSlot.misses, 2, "110 and 90 do not")
    T.Eq(tueSlot.action, "buy", "the cheap end of the week")
    T.Near(tueSlot.actual.avg, 104, "this week's scan")
    T.Eq(tueSlot.status, "hit", "within 10% of what was expected")

    local satSlot = s.slots[(7 - 1) * 6 + 4]
    T.Near(satSlot.expected, 300, "steady at 300")
    T.Eq(satSlot.action, "sell", "the dear end")
    T.Eq(satSlot.status, "pending", "Saturday is still ahead on Thursday")
    T.Eq(satSlot.hits, 4, "and it held every week")

    local wedSlot = s.slots[(4 - 1) * 6 + 3]
    T.Eq(wedSlot.expected, nil, "one week is not enough for an expectation")
    T.Near(wedSlot.mean, 120, "but the grid can still show what it has")
    T.Eq(wedSlot.status, "noscan", "behind us this week, and nothing scanned")

    T.Eq(s.slots[s.currentSlot].status, "now", "the block we are in")
    T.Near(s.min, 100, "cheap end")
    T.Near(s.max, 300, "dear end")
    T.Eq(s.flat, false, "a real spread")
    T.Eq(s.judged.hits, 6, "hits over the action slots")
    T.Eq(s.judged.misses, 2, "and misses")
    T.Near(s.reliability, 0.75, "three quarters held")

    -- The same price everywhere is a flat week: nothing to schedule.
    local flat = {}
    for w = 0, 3 do
        flat[#flat + 1] = at(w * 7, 21); flat[#flat + 1] = 100
        flat[#flat + 1] = at(w * 7 + 4, 13); flat[#flat + 1] = 102
    end
    local f = MAW.ComposeSchedule(flat, now, { weeks = 8, minWeeks = 2, weekStart = 3 })
    T.Eq(f.flat, true, "two percent apart is flat")
    T.Eq(f.slots[18].action, nil, "so nothing is a buy")

    T.Eq(MAW.ComposeSchedule({}, now, {}).flat, true, "and nothing at all is flat")
    T.Eq(MAW.ComposeSchedule(nil, now, {}).reliability, nil, "with nothing judged")
end)

T.Case("Schedule: the week's plan runs from reset day and sets a failing pattern aside", function()
    local function schedule(actions, hits, misses)
        local sc = { slots = {}, judged = { hits = hits, misses = misses }, currentSlot = 20, flat = false }
        for i = 1, 42 do sc.slots[i] = { hits = 0, misses = 0, weeksSeen = 3, status = "pending" } end
        for slot, action in pairs(actions) do
            sc.slots[slot].action = action
            sc.slots[slot].expected = action == "buy" and 100 or 300
        end
        local j = hits + misses
        if j > 0 then sc.reliability = hits / j end
        return sc
    end
    local items = {
        { name = "Felweed", itemType = "material", schedule = schedule({ [18] = "buy", [40] = "sell" }, 5, 1) },
        { name = "Flask", itemType = "product", schedule = schedule({ [30] = "sell" }, 1, 3) },
        { name = "Steady", itemType = "material", schedule = { flat = true, slots = {}, judged = { hits = 0, misses = 0 } } },
        { name = "New", itemType = "material", schedule = schedule({ [1] = "buy" }, 0, 0) },
    }
    local plan = MAW.WeekPlan(items, { weekStart = 3, minReliabilityPct = 50 })
    T.Eq(plan.days[1].label, "Tue", "the week starts on reset day")
    T.Eq(plan.days[7].label, "Mon", "and ends the night before")
    T.Eq(plan.days[1].rows[1].name, "Felweed", "Tuesday's buy")
    T.Eq(plan.days[1].rows[1].action, "buy", "is a buy")
    T.Eq(plan.days[5].rows[1].name, "Felweed", "Saturday 12-16")
    T.Eq(plan.days[5].rows[1].action, "sell", "is a sell")
    T.Eq(plan.days[6].rows[1].name, "New", "Sunday's unjudged buy is still listed")
    T.Eq(plan.scheduled, 2, "two items on the plan")
    T.Eq(#plan.setAside, 1, "one set aside")
    T.Eq(plan.setAside[1].name, "Flask", "the one that held one week in four")
    T.Eq(plan.days[3].rows[1], nil, "and its Thursday sell is gone from the plan")

    local lenient = MAW.WeekPlan(items, { weekStart = 3, minReliabilityPct = 20 })
    T.Eq(#lenient.setAside, 0, "a lower floor keeps it")
    T.Eq(lenient.days[3].rows[1].name, "Flask", "Thursday 20-24, back on the plan")
end)

T.Case("Schedule: the ring keeps the last weeks and the last few hundred, oldest first", function()
    local obs = { 1, 10, 5, 11, 9, 12 }
    MAW.PruneObs(obs, 5)
    T.Eq(#obs, 4, "the pair before the cutoff is gone")
    T.Eq(obs[1], 5, "and the rest kept their order")
    MAW.PruneObs(obs, 0, 1)
    T.Eq(#obs, 2, "one pair when one is the cap")
    T.Eq(obs[2], 12, "the newest")
    T.Eq(#MAW.PruneObs({}, 5), 0, "nothing is nothing")
    T.Eq(#MAW.PruneObs({ 7 }, 0), 0, "and a dangling timestamp is dropped rather than paired with nothing")

    -- The prices ring is newest first and mixed; the seed is oldest first and clean.
    local seeded = MAW.SeedObs({
        { timestamp = 9, buyoutPerUnit = 12 },
        { timestamp = 5, buyoutPerUnit = 0, minBidPerUnit = 11 },
        { buyoutPerUnit = 99 },
    })
    T.Eq(#seeded, 4, "two usable entries")
    T.Eq(seeded[1] .. "," .. seeded[2] .. "," .. seeded[3] .. "," .. seeded[4], "5,11,9,12", "oldest first, bid where there was no buyout")
end)

T.Case("Window scale: a usable percentage survives, an unusable one is clamped", function()
    local UI = _G.MalexisAuctionWatcherUI
    if not UI or not UI.ClampScale then
        error("UI module not loaded, so the scale clamp cannot be checked", 2)
    end

    T.Near(UI.ClampScale(1), 1, "the default is untouched")
    T.Near(UI.ClampScale(0.75), 0.75, "the 25% reduction the window was asked for")

    -- The command takes a percentage and divides by 100, so a fat-fingered "/maw scale 8"
    -- arrives as 0.08. That must floor, not produce a window nobody can read.
    T.Near(UI.ClampScale(0.08), 0.5, "far too small floors at the minimum")
    T.Near(UI.ClampScale(8), 1.25, "far too large caps at the maximum")
    T.Near(UI.ClampScale(0.5), 0.5, "the minimum itself is allowed")
    T.Near(UI.ClampScale(1.25), 1.25, "and so is the maximum")

    -- Refused rather than coerced: a nil scale would otherwise become the minimum and the
    -- window would silently shrink on a typo.
    T.Eq(UI.ClampScale(nil), nil, "no value is not a scale")
    T.Eq(UI.ClampScale("wide"), nil, "and neither is a word")
end)

_G.MalexisAuctionWatcher = MAW
