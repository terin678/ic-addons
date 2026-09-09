-- Tooltip.lua - the next sell and buy blocks on a tracked item's game tooltip
local MAW = _G.MalexisAuctionWatcher or {}

--[[
Hovering a tracked item anywhere -- bags, bank, the auction house, a chat link -- adds a
short block under the other tooltips: when the item is next expected to sell dear and
when it is next expected to be cheap, from the same week profile the Stores tab's "Sell
when" and "Buy when" columns read. Nothing is shown for an item MAW is not tracking.

The client offers two ways in. The modern one is TooltipDataProcessor, a post-call run
once per item tooltip; the older one is the OnTooltipSetItem script. Whichever exists is
used, and the addon says at login when neither does. Answers are cached for a few seconds
because some frames rebuild a tooltip every frame while it is open.
]]

local CACHE_SECONDS = 10
local cache = {}

local HEADER = { r = 0.9, g = 0.7, b = 1 }
local SELL = { r = 0.5, g = 1, b = 0.5 }
local BUY = { r = 1, g = 1, b = 1 }
local NOTE = { r = 0.6, g = 0.6, b = 0.6 }

--------------------------------------------------------------------------------
-- Pure
--------------------------------------------------------------------------------

-- Pure. ", 12% over now" / ", 8% under now", with the words chosen so that a good
-- outcome reads as one: a sell wants to be over today's price, a buy under it.
local function GainText(verb, gain)
    if not gain then return "" end
    local better = gain >= 0
    local word = ((verb == "sell") == better) and "over" or "under"
    return string.format(", %d%% %s now", math.floor(math.abs(gain) * 100 + 0.5), word)
end

-- Pure. One block as one line: "Sat 13:00  1.45g  in 3d 16h, 12% over now". `m` is
-- what MaturityFor returns; nil when there is no block. The target is an average, so
-- it is shown to the silver: nobody times a trade by the copper.
function MAW.WhenText(m, verb)
    if not m then return nil end
    local when = string.format("%s%s %s", m.nextWeek and "next " or "", MAW.WEEKDAY_NAMES[m.wday] or "?",
        m.hour and string.format("%02d:00", m.hour) or (MAW.BLOCK_LABELS[m.block] or "?"))
    return string.format("%s  %s  %s%s", when, MAW:FormatMoneyRound(m.expected),
        m.away or MAW.DescribeAway(m.blocksAway), GainText(verb, m.gain))
end

--------------------------------------------------------------------------------
-- Pure: is the item worth more converted?
--------------------------------------------------------------------------------

local COULD = { r = 1, g = 0.82, b = 0 }
local NOT = { r = 1, g = 0.5, b = 0.5 }
local MAX_CONVERT_LINES = 3

--[[
Pure. Whether a recipe's batch is worth more as the product than as the materials it
eats, from ComputeRecipeProfit's figures: the materials sold as they are net their cost
less the house cut, the product nets `ahNet`. Returns { pct, grade } with grade "does"
(at or over the Movers margin), "could" (over nothing but under it) or "not"; nil while
a price is missing.
]]
function MAW.ConvertVerdict(calc, cut, minMargin)
    if not calc or not calc.complete or not calc.ahNet or not calc.matCost or calc.matCost <= 0 then return nil end
    local asIs = calc.matCost * (1 - (cut or 0))
    if asIs <= 0 then return nil end
    local pct = (calc.ahNet - asIs) / asIs * 100
    local grade = (pct <= 0 and "not") or (pct < (minMargin or 10) and "could") or "does"
    return { pct = pct, grade = grade }
end

-- Pure. "10 Mote of Life", "1 Primal Earth +4 more": what a recipe eats, briefly.
function MAW.MaterialsText(recipe)
    local mats = recipe.materials or {}
    if #mats == 0 then return "?" end
    local first = string.format("%d %s", mats[1].count or 1, mats[1].item)
    if #mats == 1 then return first end
    return string.format("%s +%d more", first, #mats - 1)
end

--[[
Pure. One recipe as one tooltip line, { left, right, color }. `entry` is
{ role = "material" | "product", recipe, verdict, missing }: a material's line says what
converting it would do, a product's says whether it beat its materials.
]]
function MAW.ConvertLine(entry)
    local recipe, v = entry.recipe, entry.verdict
    local left = entry.role == "product" and ("From " .. MAW.MaterialsText(recipe)) or ("Convert to " .. recipe.product)
    if not v then
        local missing = entry.missing and entry.missing[1]
        return { left, missing and ("no price for " .. missing) or "not priced yet", NOTE }
    end
    local pct = string.format("%+.0f%%", v.pct)
    local right, color
    if entry.role == "product" then
        if v.grade == "does" then right, color = pct .. " over its materials", SELL
        elseif v.grade == "could" then right, color = pct .. " over its materials, barely", COULD
        else right, color = pct .. ", the materials fetch more", NOT end
    else
        if v.grade == "does" then right, color = pct .. " over selling as is", SELL
        elseif v.grade == "could" then right, color = pct .. ", barely worth the batch", COULD
        else right, color = pct .. ", sell as is", NOT end
    end
    return { left, right, color }
end

-- Pure. The recipes worth a line, best first, materials before products, at most a few.
function MAW.ConvertLines(entries)
    local sorted = {}
    for _, e in ipairs(entries or {}) do sorted[#sorted + 1] = e end
    table.sort(sorted, function(a, b)
        if a.role ~= b.role then return a.role == "material" end
        local pa, pb = a.verdict and a.verdict.pct or -math.huge, b.verdict and b.verdict.pct or -math.huge
        if pa ~= pb then return pa > pb end
        return (a.recipe.name or "") < (b.recipe.name or "")
    end)
    local lines = {}
    for i = 1, math.min(#sorted, MAX_CONVERT_LINES) do lines[i] = MAW.ConvertLine(sorted[i]) end
    return lines
end

--[[
Pure. The lines the tooltip gets for one item, as { left, right, color }; nil for an
item that is not tracked (info == nil). A tracked item with no block on either side
gets one dim line saying why, so the tooltip still tells you MAW knows the item. Then
one line per recipe the item is part of, saying whether converting pays.
]]
function MAW.TooltipLines(info)
    if not info then return nil end
    local lines = {}
    if info.sell then lines[#lines + 1] = { "Sell when", MAW.WhenText(info.sell, "sell"), SELL } end
    if info.buy then lines[#lines + 1] = { "Buy when", MAW.WhenText(info.buy, "buy"), BUY } end
    if #lines == 0 then
        lines[1] = { "Week pattern", info.flat and "flat, nothing to time" or "not enough weeks yet", NOTE }
    end
    for _, line in ipairs(MAW.ConvertLines(info.convert)) do lines[#lines + 1] = line end
    return lines
end

--------------------------------------------------------------------------------
-- The item's answer, cached briefly
--------------------------------------------------------------------------------

-- Every recipe the item is part of, with its verdict, for ConvertLines.
function MAW:ConvertInfo(itemName)
    local out = {}
    local cut, minMargin = self:GetAHCut(), self:MoverSetting("moverMinMargin")
    for _, recipe in ipairs(self:GetRecipes()) do
        local role
        if recipe.product == itemName then
            role = "product"
        else
            for _, mat in ipairs(recipe.materials or {}) do
                if mat.item == itemName then role = "material" break end
            end
        end
        if role then
            local calc = self:ComputeRecipeProfit(recipe)
            out[#out + 1] = { role = role, recipe = recipe, missing = calc.missing,
                verdict = MAW.ConvertVerdict(calc, cut, minMargin) }
        end
    end
    return out
end

function MAW:TooltipInfo(itemName)
    local db = self:GetActiveDB()
    local itemData = db and db.items and db.items[itemName]
    if not itemData then return nil end

    local now = (GetTime and GetTime()) or time()
    local hit = cache[itemName]
    if hit and now - hit.at < CACHE_SECONDS then return hit.info end

    local price = self:GetUnitPrice(itemName)
    local schedule = self:GetSchedule(itemName)
    local info = { flat = schedule and schedule.flat or false }
    if schedule and not schedule.flat then
        info.sell = self:MaturityFor(itemName, "sell", price, schedule)
        info.buy = self:MaturityFor(itemName, "buy", price, schedule)
    end
    info.convert = self:ConvertInfo(itemName)
    cache[itemName] = { at = now, info = info }
    return info
end

-- Forget the cached answers, for after a scan or a settings change.
function MAW.ClearTooltipCache()
    cache = {}
end

--------------------------------------------------------------------------------
-- The hook
--------------------------------------------------------------------------------

-- What /maw tooltip reports: which hook is in, how many item tooltips it has seen,
-- and what became of the last one.
MAW.tooltipStats = { path = nil, calls = 0, lastTooltip = nil, lastName = nil, lastOutcome = "none yet" }

local function NonEmpty(name)
    if type(name) == "string" and name ~= "" then return name end
    return nil
end

-- The item's name from the ID the processor hands over first (it is cached, the tooltip
-- is showing it), then from the tooltip itself. GetItem can answer "" on this client.
local function DisplayedItemName(tooltip, data)
    if data and data.id then
        local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        if getInfo then
            local name = NonEmpty((getInfo(data.id)))
            if name then return name end
        end
    end
    if tooltip.GetItem then
        local name = NonEmpty((tooltip:GetItem()))
        if name then return name end
    end
    if TooltipUtil and TooltipUtil.GetDisplayedItem then
        return NonEmpty((TooltipUtil.GetDisplayedItem(tooltip)))
    end
    return nil
end

local function OnItem(tooltip, data)
    local stats = MAW.tooltipStats
    if not MAW.db or not MAW.db.settings or MAW.db.settings.tooltip == false then
        stats.lastOutcome = "switched off"
        return
    end
    if tooltip.IsForbidden and tooltip:IsForbidden() then
        stats.lastOutcome = "forbidden tooltip"
        return
    end
    local name = DisplayedItemName(tooltip, data)
    stats.lastName = name
    if not name then
        stats.lastOutcome = "no item name on the tooltip"
        return
    end
    local lines = MAW.TooltipLines(MAW:TooltipInfo(name))
    if not lines then
        stats.lastOutcome = "not a tracked item"
        return
    end
    stats.lastOutcome = string.format("%d line%s added", #lines, #lines == 1 and "" or "s")
    tooltip:AddLine(" ")
    tooltip:AddLine("Malexis Auction Watcher", HEADER.r, HEADER.g, HEADER.b)
    for _, line in ipairs(lines) do
        local c = line[3]
        tooltip:AddDoubleLine(line[1], line[2], 1, 1, 1, c.r, c.g, c.b)
    end
    tooltip:Show()
end

-- Every item tooltip the client reports comes through here: counted, named, and an
-- error inside the handler is kept for /maw tooltip as well as raised.
local function Handle(tooltip, data)
    local stats = MAW.tooltipStats
    stats.calls = stats.calls + 1
    stats.lastTooltip = (tooltip and tooltip.GetName and tooltip:GetName()) or "unnamed"
    if not tooltip or not tooltip.AddLine then
        stats.lastOutcome = "not a tooltip frame"
        return
    end
    local ok, err = pcall(OnItem, tooltip, data)
    if not ok then
        stats.lastOutcome = "error: " .. tostring(err)
        if geterrorhandler then geterrorhandler()(err) end
    end
end

-- Returns whether the hook is in place. Safe to call more than once.
function MAW.InstallTooltip()
    if MAW.tooltipInstalled then return true end
    -- The processor table exists on this client without the C_TooltipInfo backing that
    -- makes tooltips flow through it, so both must be present before it is the way in.
    -- Auctionator, TSM and BagBrother make the same test.
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and C_TooltipInfo
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, Handle)
        MAW.tooltipStats.path = "TooltipDataProcessor"
    elseif GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetItem", function(tooltip) Handle(tooltip) end)
        if ItemRefTooltip and ItemRefTooltip.HookScript then
            ItemRefTooltip:HookScript("OnTooltipSetItem", function(tooltip) Handle(tooltip) end)
        end
        MAW.tooltipStats.path = "OnTooltipSetItem"
    else
        return false
    end
    MAW.tooltipInstalled = true
    return true
end

_G.MalexisAuctionWatcher = MAW
