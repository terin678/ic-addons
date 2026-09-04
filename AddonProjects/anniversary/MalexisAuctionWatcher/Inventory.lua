-- Inventory.lua - Inventory, Bank, and Auction House counting and caching
local addonName = "MalexisAuctionWatcher"
local MAW = _G.MalexisAuctionWatcher or {}

-- Count items in player inventory (bags only, not bank)
function MAW:CountInventory(itemName)
    local db = self:GetActiveDB()
    local itemID = db.items[itemName] and db.items[itemName].itemID
    if not itemID then
        return 0
    end

    local total = 0
    -- Check all bag slots (0-4, where 0 is backpack)
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == itemID then
                total = total + (info.stackCount or 1)
            end
        end
    end

    return total
end

-- Scan and cache all bank contents
function MAW:ScanBankCache()
    local db = self:GetActiveDB()
    if not db.cache then
        db.cache = { bank = {} }
    end

    -- Clear existing cache
    db.cache.bank = {}

    -- Scan main bank container (Enum.BagIndex.Bank or -1)
    local bankBagID = (Enum and Enum.BagIndex and Enum.BagIndex.Bank) or BANK_CONTAINER or -1
    local numSlots = C_Container.GetContainerNumSlots(bankBagID) or 0
    for slot = 1, numSlots do
        local info = C_Container.GetContainerItemInfo(bankBagID, slot)
        if info and info.itemID then
            local itemID = info.itemID
            local count = info.stackCount or 1
            db.cache.bank[itemID] = (db.cache.bank[itemID] or 0) + count
        end
    end

    -- Scan bank bags (NUM_BAG_SLOTS + 1 through NUM_BAG_SLOTS + 7 in Classic)
    local firstBankBag = (NUM_BAG_SLOTS or 4) + 1
    local numBankBags = NUM_BANKBAGSLOTS or 7  -- Classic/TBC have 7 bank bag slots

    for i = 0, numBankBags - 1 do
        local bag = firstBankBag + i
        numSlots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local itemID = info.itemID
                local count = info.stackCount or 1
                db.cache.bank[itemID] = (db.cache.bank[itemID] or 0) + count
            end
        end
    end

    if self.debugMode then
        MAW.Debug("%s", "Bank cache updated")
    end
end

-- Count items in bank (uses cached data)
function MAW:CountBank(itemName)
    local db = self:GetActiveDB()
    local itemID = db.items[itemName] and db.items[itemName].itemID
    if not itemID then
        return 0
    end

    -- Return cached count
    return db.cache.bank[itemID] or 0
end

-- Scan and cache all auction house listings
function MAW:ScanAuctionHouseCache()
    if not AuctionFrame or not AuctionFrame:IsVisible() then
        return
    end

    local db = self:GetActiveDB()
    if not db.cache then
        db.cache = { bank = {}, auctionHouse = {} }
    end

    -- Clear existing cache
    db.cache.auctionHouse = {}

    local numAuctions = GetNumAuctionItems("owner")

    for i = 1, numAuctions do
        local name, _, stackSize, _, _, _, _, _, _, _, _, _, _, _, _, _, ahItemID = GetAuctionItemInfo("owner", i)
        if ahItemID and stackSize then
            db.cache.auctionHouse[ahItemID] = (db.cache.auctionHouse[ahItemID] or 0) + stackSize
        end
    end

    if self.debugMode then
        MAW.Debug("%s", "Auction house cache updated")
    end
end

-- Count items on auction house (uses cached data)
function MAW:CountAuctionHouse(itemName)
    local db = self:GetActiveDB()
    local itemID = db.items[itemName] and db.items[itemName].itemID
    if not itemID then
        return 0
    end

    -- Return cached count
    return db.cache.auctionHouse[itemID] or 0
end

-- Get all inventory counts for all tracked items
function MAW:GetAllInventoryCounts()
    local db = self:GetActiveDB()
    local counts = {}
    for itemName, _ in pairs(db.items) do
        counts[itemName] = {
            inventory = self:CountInventory(itemName),
            bank = self:CountBank(itemName),
            auctionHouse = self:CountAuctionHouse(itemName)
        }
    end
    return counts
end

_G.MalexisAuctionWatcher = MAW
