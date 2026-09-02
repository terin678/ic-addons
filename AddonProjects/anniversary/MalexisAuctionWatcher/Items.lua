-- Items.lua - Item management and manipulation
local addonName = "MalexisAuctionWatcher"
local MAW = _G.MalexisAuctionWatcher or {}

-- Get item ID from item name
function MAW:GetItemIDFromName(itemName)
    -- GetItemInfo returns multiple values, itemLink is the 2nd return value
    local _, itemLink = GetItemInfo(itemName)

    if itemLink then
        local itemID = tonumber(itemLink:match("item:(%d+)"))
        return itemID
    end

    -- If item is not in cache yet, return a placeholder and let user know
    return 0
end

-- Add a new item to track
function MAW:AddItem(itemName, itemType)
    if not itemName or itemName == "" then
        print(addonName .. ": Please specify an item name")
        return
    end

    -- Default to "material" if not specified
    itemType = itemType or "material"

    -- Get item ID from name
    local itemID = self:GetItemIDFromName(itemName)
    if not itemID or itemID == 0 then
        print(addonName .. ": Could not find item: " .. itemName)
        print(addonName .. ": Try linking the item in chat, or viewing it in-game to cache it first")
        print(addonName .. ": Example: Shift-click the item, then try /maw add again")
        return
    end

    local db = self:GetActiveDB()
    if db.items[itemName] then
        print(addonName .. ": Already tracking " .. itemName)
        return
    end

    -- Calculate next order index
    local maxOrder = 0
    for _, itemData in pairs(db.items) do
        if itemData.order and itemData.order > maxOrder then
            maxOrder = itemData.order
        end
    end

    db.items[itemName] = {
        itemID = itemID,
        itemType = itemType,  -- "material" or "product"
        prices = {},
        customLow = nil,  -- Custom low price bound (shop buying limit)
        customHigh = nil,  -- Custom high price bound (shop selling limit)
        order = maxOrder + 1  -- Display order
    }
    print(addonName .. ": Now tracking " .. itemName .. " (ID: " .. itemID .. ") as " .. itemType)

    -- Fire callback
    self:FireCallbacks("onItemAdded", itemName)
end

-- Remove an item from tracking
function MAW:RemoveItem(itemName)
    if not itemName or itemName == "" then
        print(addonName .. ": Please specify an item name")
        return
    end

    local db = self:GetActiveDB()
    if not db.items[itemName] then
        print(addonName .. ": Not tracking " .. itemName)
        return
    end

    db.items[itemName] = nil
    print(addonName .. ": Stopped tracking " .. itemName)

    -- Fire callback
    self:FireCallbacks("onItemRemoved", itemName)
end

-- Move item up in display order
function MAW:MoveItemUp(itemName, itemType)
    local db = self:GetActiveDB()
    if not db.items[itemName] then
        return
    end

    -- Ensure all items have an order field
    self:EnsureItemOrders()

    local currentOrder = db.items[itemName].order

    -- Find the item immediately above this one (same type, next lower order)
    local swapItem = nil
    local swapOrder = -1

    for name, data in pairs(db.items) do
        local nameType = data.itemType or "material"
        if nameType == itemType and name ~= itemName then
            local order = data.order
            if order < currentOrder and order > swapOrder then
                swapOrder = order
                swapItem = name
            end
        end
    end

    -- Swap orders
    if swapItem then
        db.items[itemName].order = swapOrder
        db.items[swapItem].order = currentOrder
        if self.debugMode then
            print(addonName .. ": Moved " .. itemName .. " up")
        end
        self:FireCallbacks("onItemAdded")  -- Trigger refresh
    end
end

-- Move item down in display order
function MAW:MoveItemDown(itemName, itemType)
    local db = self:GetActiveDB()
    if not db.items[itemName] then
        return
    end

    -- Ensure all items have an order field
    self:EnsureItemOrders()

    local currentOrder = db.items[itemName].order

    -- Find the item immediately below this one (same type, next higher order)
    local swapItem = nil
    local swapOrder = 999999

    for name, data in pairs(db.items) do
        local nameType = data.itemType or "material"
        if nameType == itemType and name ~= itemName then
            local order = data.order
            if order > currentOrder and order < swapOrder then
                swapOrder = order
                swapItem = name
            end
        end
    end

    -- Swap orders
    if swapItem then
        db.items[itemName].order = swapOrder
        db.items[swapItem].order = currentOrder
        if self.debugMode then
            print(addonName .. ": Moved " .. itemName .. " down")
        end
        self:FireCallbacks("onItemAdded")  -- Trigger refresh
    end
end

-- Ensure all items have an order field (for migration from older versions)
function MAW:EnsureItemOrders()
    local db = self:GetActiveDB()
    local nextOrder = 1
    for _, itemData in pairs(db.items) do
        if not itemData.order then
            itemData.order = nextOrder
            nextOrder = nextOrder + 1
        end
    end
end

_G.MalexisAuctionWatcher = MAW
