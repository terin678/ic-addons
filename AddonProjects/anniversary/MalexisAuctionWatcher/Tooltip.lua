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

-- Pure. One block as one line: "Sat 13:00  1g 45s  in 3d 16h, 12% over now". `m` is
-- what MaturityFor returns; nil when there is no block.
function MAW.WhenText(m, verb)
    if not m then return nil end
    local when = string.format("%s%s %s", m.nextWeek and "next " or "", MAW.WEEKDAY_NAMES[m.wday] or "?",
        m.hour and string.format("%02d:00", m.hour) or (MAW.BLOCK_LABELS[m.block] or "?"))
    return string.format("%s  %s  %s%s", when, MAW:FormatMoney(m.expected),
        m.away or MAW.DescribeAway(m.blocksAway), GainText(verb, m.gain))
end

--[[
Pure. The lines the tooltip gets for one item, as { left, right, color }; nil for an
item that is not tracked (info == nil). A tracked item with no block on either side
gets one dim line saying why, so the tooltip still tells you MAW knows the item.
]]
function MAW.TooltipLines(info)
    if not info then return nil end
    local lines = {}
    if info.sell then lines[#lines + 1] = { "Sell when", MAW.WhenText(info.sell, "sell"), SELL } end
    if info.buy then lines[#lines + 1] = { "Buy when", MAW.WhenText(info.buy, "buy"), BUY } end
    if #lines == 0 then
        lines[1] = { "Week pattern", info.flat and "flat, nothing to time" or "not enough weeks yet", NOTE }
    end
    return lines
end

--------------------------------------------------------------------------------
-- The item's answer, cached briefly
--------------------------------------------------------------------------------

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
MAW.tooltipStats = { path = nil, calls = 0, lastName = nil, lastOutcome = "none yet" }

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
    stats.calls = stats.calls + 1
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

-- Returns whether the hook is in place. Safe to call more than once.
function MAW.InstallTooltip()
    if MAW.tooltipInstalled then return true end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            if tooltip == GameTooltip or tooltip == ItemRefTooltip then OnItem(tooltip, data) end
        end)
        MAW.tooltipStats.path = "TooltipDataProcessor"
    elseif GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetItem", function(tooltip) OnItem(tooltip) end)
        if ItemRefTooltip and ItemRefTooltip.HookScript then
            ItemRefTooltip:HookScript("OnTooltipSetItem", function(tooltip) OnItem(tooltip) end)
        end
        MAW.tooltipStats.path = "OnTooltipSetItem"
    else
        return false
    end
    MAW.tooltipInstalled = true
    return true
end

_G.MalexisAuctionWatcher = MAW
