local addonName, ns = ...

-- The harness is LibICCore's, run in game with /ast test. Only the pure parts are
-- here: the judgement and the column rearrangement. What reads Auctionator's frames
-- is checked by posting something.

local T = ns.Tests

T.Case("Guard: a price far under the market is asked about, one near it is not", function()
    local v = ns.Guard.Judge(1000, 10000, 40)
    T.True(v ~= nil, "a tenth of the cheapest listing")
    T.Eq(v.underPct, 90, "is ninety percent under")
    T.Eq(v.ref, 10000, "against that listing")

    T.Eq(ns.Guard.Judge(7000, 10000, 40), nil, "thirty percent under is inside a forty percent floor")
    T.Eq(ns.Guard.Judge(6000, 10000, 40), nil, "exactly at the floor is not over it")
    T.Eq(ns.Guard.Judge(5999, 10000, 40).underPct, 40, "one copper past it is, and rounds to the floor")
    T.Eq(ns.Guard.Judge(5000, 10000, 60), nil, "a looser floor lets a half-price post through")
    T.Eq(ns.Guard.Judge(12000, 10000, 40), nil, "over the market is never asked about")
    T.Eq(ns.Guard.Judge(10000, 10000, 40), nil, "and neither is matching it")

    T.Eq(ns.Guard.Judge(1000, 0, 40), nil, "no listing and no last price is nothing to compare")
    T.Eq(ns.Guard.Judge(1000, nil, 40), nil, "nor is a missing one")
    T.Eq(ns.Guard.Judge(0, 10000, 40), nil, "a zero price is Auctionator's to refuse")
    T.Eq(ns.Guard.Judge("1000", "10000", 40).underPct, 90, "numbers as strings are numbers")
end)

T.Case("Guard: the floor is a percentage that stays useful", function()
    T.Eq(ns.Guard.ClampFloor(40), 40, "the default passes through")
    T.Eq(ns.Guard.ClampFloor(0), 1, "zero would ask about every undercut")
    T.Eq(ns.Guard.ClampFloor(150), 90, "and past ninety nothing would ever ask")
    T.Eq(ns.Guard.ClampFloor(33.7), 33, "whole percent")
    T.Eq(ns.Guard.ClampFloor("abc"), 40, "nonsense is the default")
end)

T.Case("Columns: Expiry lands before You?, and a changed layout is left alone", function()
    local original = {
        { headerText = "Price", headerParameters = { "unitPrice" } },
        { headerText = "You?", headerParameters = { "isOwnedText" }, width = 70 },
        { headerText = "Time Left", headerParameters = { "timeLeft" }, width = 90, defaultHide = true },
    }
    local out = ns.Columns.Rearranged(original)
    T.Eq(#out, 3, "the same number of columns")
    T.Eq(out[1].headerText, "Price", "price first, untouched")
    T.Eq(out[2].headerText, "Expiry", "then the expiry")
    T.Eq(out[2].defaultHide, nil, "shown by default")
    T.Eq(out[3].headerText, "You?", "then you")
    T.Eq(out[3].width, 44, "narrowed")
    T.Eq(original[2].width, 70, "and Auctionator's own table is unchanged")

    local renamed = { { headerText = "Price", headerParameters = { "unitPrice" } } }
    T.Eq(ns.Columns.Rearranged(renamed), renamed, "with nothing to move, the original comes back")
end)
