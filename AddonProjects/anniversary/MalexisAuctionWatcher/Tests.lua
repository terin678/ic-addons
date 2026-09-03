-- Tests.lua - Pure-function checks, run in game with /maw test
--
-- Nothing here touches the saved variables or the auction house: every case
-- builds its own input and checks arithmetic that is otherwise only visible as a
-- line on a chart.
local addonName = "MalexisAuctionWatcher"
local MAW = _G.MalexisAuctionWatcher or {}

MAW.Tests = MAW.Tests or {}
local T = MAW.Tests
T.cases = {}

function T.Case(name, fn)
    T.cases[#T.cases + 1] = { name = name, fn = fn }
end

function T.Eq(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected [%s], got [%s]",
            tostring(label or "value"), tostring(expected), tostring(actual)), 2)
    end
end

-- Money is computed in floating point, so equality on a copper value needs slack.
function T.Near(actual, expected, label)
    if type(actual) ~= "number" or math.abs(actual - expected) > 0.001 then
        error(string.format("%s: expected [%s], got [%s]",
            tostring(label or "value"), tostring(expected), tostring(actual)), 2)
    end
end

function T.Run()
    local pass, fail = 0, 0
    for _, c in ipairs(T.cases) do
        local ok, err = pcall(c.fn)
        if ok then
            pass = pass + 1
        else
            fail = fail + 1
            print(string.format("%s: |cffff4444FAIL|r %s => %s", addonName, c.name, tostring(err)))
        end
    end
    print(string.format("%s: tests |cff44ff44%d passed|r, %s%d failed|r",
        addonName, pass, fail > 0 and "|cffff4444" or "|cff44ff44", fail))
    return pass, fail
end

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

_G.MalexisAuctionWatcher = MAW
