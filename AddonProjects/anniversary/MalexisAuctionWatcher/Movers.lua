-- Movers.lua - What to buy, convert, and list right now, with one-click actions
local addonName = "MalexisAuctionWatcher"
local MAW = _G.MalexisAuctionWatcher or {}

local DEFAULTS = {
    moverBuyPct = 0.25,     -- Today at or below low + 25% of range = buy
    moverSellPct = 0.75,    -- Today at or above low + 75% of range = list
    moverMinMargin = 10,    -- recipe margin percent needed to suggest converting
}

function MAW:MoverSetting(key)
    local s = MalexisAuctionWatcherDB and MalexisAuctionWatcherDB.settings
    local v = s and s[key]
    if type(v) ~= "number" then
        return DEFAULTS[key]
    end
    return v
end

-- Low/high bounds for an item, with where each came from. Used everywhere a bound is read.
-- Priority: custom bound -> TSM averages (lower/higher of 60d and 14d) -> min/max of recorded buyouts.
-- Returns low, high, lowSource, highSource  (sources: "custom", "tsm", "scan")
function MAW:GetPriceBounds(itemName)
    local db = self:GetActiveDB()
    local itemData = db.items[itemName]
    if not itemData then return nil end

    local low, high = itemData.customLow, itemData.customHigh
    local lowSrc, highSrc = low and "custom" or nil, high and "custom" or nil

    if not low or not high then
        local ref = itemData.tsmRef
        local tsmOn = self.sources and self.sources.tsm and self.sources.tsm.available and self:IsSourceEnabled("tsm")
        if tsmOn and ref and (ref.market or ref.historical) then
            local a, b = ref.market or ref.historical, ref.historical or ref.market
            local tLow, tHigh = math.min(a, b), math.max(a, b)
            if not low then low, lowSrc = tLow, "tsm" end
            if not high then high, highSrc = tHigh, "tsm" end
        end
    end

    if not low or not high then
        local minB, maxB
        for _, entry in ipairs(itemData.prices or {}) do
            local u = entry.buyoutPerUnit
            if u and u > 0 then
                if not minB or u < minB then minB = u end
                if not maxB or u > maxB then maxB = u end
            end
        end
        if not low and minB then low, lowSrc = minB, "scan" end
        if not high and maxB then high, highSrc = maxB, "scan" end
    end

    if not low or not high or high <= 0 then return nil end
    -- Keep the pair ordered if a custom bound crosses a derived one
    if low > high then low, high = high, low; lowSrc, highSrc = highSrc, lowSrc end
    return low, high, lowSrc, highSrc
end

-- Position of today's price within the item's range: 0 = at low, 1 = at high. nil without data.
function MAW:GetRangePosition(itemName)
    local today = self:GetUnitPrice(itemName)
    local low, high = self:GetPriceBounds(itemName)
    if not today or not low or not high or high <= low then
        return nil
    end
    return (today - low) / (high - low)
end

local function Owned(self, itemName)
    return (self:CountInventory(itemName) or 0) + (self:CountBank(itemName) or 0)
end

-- Returns { buy = {...}, convert = {...}, sell = {...} }
function MAW:GetMovers()
    local db = self:GetActiveDB()
    local out = { buy = {}, convert = {}, sell = {} }
    local buyPct = self:MoverSetting("moverBuyPct")
    local sellPct = self:MoverSetting("moverSellPct")

    for itemName, itemData in pairs(db.items) do
        local today, source, when = self:GetUnitPrice(itemName)
        local low, high = self:GetPriceBounds(itemName)
        if today and low and high and high > low then
            local pos = (today - low) / (high - low)
            local itemType = itemData.itemType or "material"
            local typeTag = (itemType == "product") and "product" or "material"
            -- Cheap is a buy whatever the type: materials to craft with, products to stock up on
            if pos <= buyPct then
                table.insert(out.buy, {
                    kind = "buy", name = itemName, itemID = itemData.itemID, price = today,
                    low = low, high = high, pos = pos, source = source, when = when, itemType = itemType,
                    reason = string.format("%s at %.0f%% of range (low %s, high %s)", typeTag, pos * 100, self:FormatMoney(low), self:FormatMoney(high)),
                })
            end
            -- Expensive and in hand is a listing whatever the type: spare mats sell too
            if pos >= sellPct then
                local owned = Owned(self, itemName)
                if owned > 0 then
                    table.insert(out.sell, {
                        kind = "sell", name = itemName, itemID = itemData.itemID, price = today,
                        low = low, high = high, pos = pos, owned = owned, source = source, when = when, itemType = itemType,
                        reason = string.format("%s at %.0f%% of range, you hold %d", typeTag, pos * 100, owned),
                    })
                end
            end
        end
    end

    local minMargin = self:MoverSetting("moverMinMargin")
    for _, recipe in ipairs(self:GetRecipes()) do
        local calc = self:ComputeRecipeProfit(recipe)
        if calc.complete and calc.margin and calc.margin >= minMargin and (calc.canMake or 0) >= 1 then
            table.insert(out.convert, {
                kind = "convert", name = recipe.name, recipe = recipe, calc = calc,
                margin = calc.margin, profit = calc.profit, canMake = calc.canMake,
                reason = string.format("%.0f%% margin, %s per batch, can make %d", calc.margin, self:FormatMoney(calc.profit), calc.canMake),
            })
        end
    end

    table.sort(out.buy, function(a, b) return a.pos < b.pos end)
    table.sort(out.sell, function(a, b) return a.pos > b.pos end)
    table.sort(out.convert, function(a, b) return a.margin > b.margin end)
    return out
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------

local function AtAH()
    return AuctionFrame and AuctionFrame:IsShown()
end

-- Buy: open Browse and search the exact name. No automatic buyout.
function MAW:MoverBuy(itemName)
    if not AtAH() then
        print(addonName .. ": Open the auction house first, then click Buy to search for " .. itemName)
        return false
    end
    if AuctionFrameTab1 then AuctionFrameTab1:Click() end
    if BrowseName then
        BrowseName:SetText(itemName)
    end
    if ExactMatchCheckButton then
        ExactMatchCheckButton:SetChecked(true)
    end
    if BrowseMinLevel then BrowseMinLevel:SetText("") end
    if BrowseMaxLevel then BrowseMaxLevel:SetText("") end
    if AuctionFrameBrowse_Search then
        AuctionFrameBrowse_Search()
    elseif BrowseSearchButton then
        BrowseSearchButton:Click()
    end
    return true
end

-- Find the first bag slot holding the item
local function FindInBags(itemID)
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == itemID then
                return bag, slot, info.stackCount or 1
            end
        end
    end
    return nil
end

-- List: switch to Auctions, put the first stack in the sell slot, prefill prices.
function MAW:MoverList(itemName, itemID, unitPrice)
    if not AtAH() then
        print(addonName .. ": Open the auction house first, then click List for " .. itemName)
        return false
    end
    local bag, slot, count = FindInBags(itemID)
    if not bag then
        print(addonName .. ": No " .. itemName .. " in your bags (bank stock does not count)")
        return false
    end
    if AuctionFrameTab3 then AuctionFrameTab3:Click() end
    ClearCursor()
    C_Container.PickupContainerItem(bag, slot)
    if ClickAuctionSellItemButton then
        ClickAuctionSellItemButton()
    end
    ClearCursor()

    if unitPrice and unitPrice > 0 then
        -- Undercut by 1 copper per unit; prices are per stack on the legacy AH
        local perUnit = math.max(1, math.floor(unitPrice) - 1)
        local stackPrice = perUnit * count
        C_Timer.After(0.1, function()
            if StartPrice and MoneyInputFrame_SetCopper then
                MoneyInputFrame_SetCopper(StartPrice, math.floor(stackPrice * 0.95))
            end
            if BuyoutPrice and MoneyInputFrame_SetCopper then
                MoneyInputFrame_SetCopper(BuyoutPrice, stackPrice)
            end
        end)
        print(string.format("%s: %s x%d in the sell slot at %s buyout (%s each). Check the duration and press Create Auction.",
            addonName, itemName, count, self:FormatMoney(stackPrice), self:FormatMoney(perUnit)))
    end
    return true
end

-- Convert is a secure action set on the button itself (see UI). This resolves what to cast/use.
-- Returns attrType ("spell" | "item"), attrValue
function MAW:MoverConvertAction(recipe)
    local mats = recipe.materials or {}
    -- Mote combines are item uses: one material, no profession
    if not recipe.profession and #mats == 1 and mats[1].count == 10 and mats[1].item:match("^Mote of ") then
        return "item", mats[1].item
    end
    -- Everything else is a profession spell named after the recipe
    return "spell", recipe.name
end

_G.MalexisAuctionWatcher = MAW
