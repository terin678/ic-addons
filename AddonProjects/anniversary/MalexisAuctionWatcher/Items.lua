-- Items.lua - Item management and manipulation
local addonName = "MalexisAuctionWatcher"
local MAW = _G.MalexisAuctionWatcher or {}

--[[
Pure. The display name and item id carried by a shift-clicked link, or nil for plain
text. The id is read straight out of the link rather than looked up, because GetItemInfo
returns nothing at all for an item this client has never cached, which is the whole case
this exists for. A recipe or enchant link has a name in brackets but no |Hitem:, so the
id comes back nil and the caller falls back to the name.
]]
function MAW.ParseItemLink(text)
    if type(text) ~= "string" or not text:match("|H") then return nil end
    return text:match("%[(.-)%]"), tonumber(text:match("|Hitem:(%d+)"))
end

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
        MAW.Print("Please specify an item name")
        return
    end

    -- Default to "material" if not specified
    itemType = itemType or "material"

    -- A shift-clicked link reaches here from /maw add, and from the dialog's name box when
    -- one is pasted into it. Take the name and the id out of it before anything else: the
    -- name is what the item is stored and scanned under, and the link's id is the only one
    -- to be had for an item this client has never cached.
    local itemID
    local linkName, linkID = MAW.ParseItemLink(itemName)
    if linkName then itemName, itemID = linkName, linkID end

    -- Get item ID from name
    itemID = itemID or self:GetItemIDFromName(itemName)
    if not itemID or itemID == 0 then
        MAW.Print("Could not find item: " .. itemName)
        if linkName and not linkID then
            -- A link arrived, but a recipe or enchant one: named, with no item id in it.
            MAW.Print("That link is not an item, so it carries no id to track.")
        elseif not linkName then
            -- A typed name, and this client has never cached it. Say so plainly rather
            -- than repeating advice the player has already followed.
            MAW.Print("No item link in that, only text, and this client has no '" .. itemName
                .. "' cached to look up.")
            MAW.Print("Shift-click the item itself so the link carries its id. Auction house")
            MAW.Print("Browse rows link on shift-click; some addon panes do not.")
        end
        return
    end

    local db = self:GetActiveDB()
    if db.items[itemName] then
        MAW.Print("Already tracking " .. itemName)
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
    MAW.Print("Now tracking " .. itemName .. " (ID: " .. itemID .. ") as " .. itemType)

    -- Fire callback
    self:FireCallbacks("onItemAdded", itemName)
    -- Its external figures, quietly, without waiting for the next scan or AH visit
    if self.SchedulePull then self:SchedulePull("added", { itemName }) end
end

-- Remove an item from tracking
function MAW:RemoveItem(itemName)
    if not itemName or itemName == "" then
        MAW.Print("Please specify an item name")
        return
    end

    local db = self:GetActiveDB()
    if not db.items[itemName] then
        MAW.Print("Not tracking " .. itemName)
        return
    end

    db.items[itemName] = nil
    MAW.Print("Stopped tracking " .. itemName)

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
            MAW.Print("Moved " .. itemName .. " up")
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
            MAW.Print("Moved " .. itemName .. " down")
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

-- The auction house category an item sits in, for grouping the History picker.
--
-- Return 6 of GetItemInfo is the localized class name ("Trade Goods", "Gem",
-- "Consumable") and those are exactly the auction house's own headings, so it
-- needs no mapping table and is right in every locale. GetItemInfo answers
-- nothing at all for an item this client has never cached, so the answer is nil
-- rather than wrong; asking also queues the request, which is why an item filed
-- under "Other" moves to its real category once you open the menu again.
-- Cached for the session only. The name is localized, so saving it would keep a
-- character grouping by the last locale it logged in under and never ask again.
local classCache = {}

function MAW:GetItemClass(itemName, itemData)
    itemData = itemData or (self:GetActiveDB().items or {})[itemName]
    local key = (itemData and itemData.itemID) or itemName
    if classCache[key] then return classCache[key] end

    local _, _, _, _, _, class = GetItemInfo(key)
    if not class or class == "" then return nil end
    classCache[key] = class
    return class
end

_G.MalexisAuctionWatcher = MAW
