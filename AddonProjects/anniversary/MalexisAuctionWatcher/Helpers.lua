-- Helpers.lua - Utility functions shared across the addon

local addonName = "MalexisAuctionWatcher"
local MAWHelpers = {}

-- Parse money input from string format (e.g., "10g 5s 20c")
function MAWHelpers.ParseMoneyInput(input)
    if not input or input == "" then
        return nil
    end

    local total = 0

    -- Match gold (format: digits followed by 'g')
    local gold = input:match("(%d+)g")
    if gold then
        total = total + (tonumber(gold) * 10000)
    end

    -- Match silver (format: digits followed by 's')
    local silver = input:match("(%d+)s")
    if silver then
        total = total + (tonumber(silver) * 100)
    end

    -- Match copper (format: digits followed by 'c')
    local copper = input:match("(%d+)c")
    if copper then
        total = total + tonumber(copper)
    end

    return total > 0 and total or nil
end

-- Format money in gold/silver/copper
function MAWHelpers.FormatMoney(copper)
    copper = copper and math.floor(copper + 0.5) or nil
    if not copper or copper == 0 then
        return "0c"
    end

    -- Judged on the size, then the sign put back: a loss of 1g 23s reads "-1.23g",
    -- not the silvers a negative number's rounding used to fall through to.
    local sign, amount = copper < 0 and "-" or "", math.abs(copper)
    local gold = math.floor(amount / 10000)
    local silver = math.floor((amount % 10000) / 100)

    if gold > 0 then
        return sign .. string.format("%.2fg", amount / 10000)
    elseif silver > 0 then
        return sign .. string.format("%.1fs", amount / 100)
    else
        return sign .. string.format("%dc", amount)
    end
end

-- Export to global namespace
_G.MalexisAuctionWatcherHelpers = MAWHelpers
