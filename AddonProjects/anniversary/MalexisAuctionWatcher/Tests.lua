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
