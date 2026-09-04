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
