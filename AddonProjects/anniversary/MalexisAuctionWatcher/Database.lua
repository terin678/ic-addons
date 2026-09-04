-- Database.lua - Database initialization and price entry management
local addonName = "MalexisAuctionWatcher"
local MAW = _G.MalexisAuctionWatcher or {}

-- Get the active database based on character-specific mode
function MAW:GetActiveDB()
    if MalexisAuctionWatcherDB and MalexisAuctionWatcherDB.settings and MalexisAuctionWatcherDB.settings.characterSpecific then
        -- Use character-specific database
        return MalexisAuctionWatcherCharDB
    else
        -- Use account-wide database
        return MalexisAuctionWatcherDB
    end
end

-- Copy account-wide data to character-specific
function MAW:CopyAccountDataToCharacter()
    if MalexisAuctionWatcherDB.items and next(MalexisAuctionWatcherDB.items) then
        MalexisAuctionWatcherCharDB.items = MAW.DeepCopy(MalexisAuctionWatcherDB.items)
        MAW.Print("Copied " .. self:CountItems(MalexisAuctionWatcherCharDB.items) .. " items from account-wide to character-specific database")
        return true
    end
    return false
end

-- Count items in a table
function MAW:CountItems(itemsTable)
    local count = 0
    for _ in pairs(itemsTable) do
        count = count + 1
    end
    return count
end

-- The tables themselves are created, defaulted and migrated by LibICCore from the
-- Defaults in Core.lua; MigrateHistory and RepairGemPresetData run from its onLoad.

-- Toggle character-specific mode
function MAW:ToggleCharacterSpecific()
    local wasCharacterSpecific = MalexisAuctionWatcherDB.settings.characterSpecific
    MalexisAuctionWatcherDB.settings.characterSpecific = not wasCharacterSpecific

    -- If switching TO character-specific mode and character DB is empty, offer to copy
    if MalexisAuctionWatcherDB.settings.characterSpecific and not wasCharacterSpecific then
        local charItemCount = self:CountItems(MalexisAuctionWatcherCharDB.items or {})
        local accountItemCount = self:CountItems(MalexisAuctionWatcherDB.items or {})

        if charItemCount == 0 and accountItemCount > 0 then
            -- Show dialog to copy data
            if _G.MalexisAuctionWatcherDialogs then
                _G.MalexisAuctionWatcherDialogs.ShowCopyDataDialog()
            end
            -- Don't refresh yet - wait for user to decide
            return MalexisAuctionWatcherDB.settings.characterSpecific
        end
    end

    local mode = MalexisAuctionWatcherDB.settings.characterSpecific and "character-specific" or "account-wide"
    MAW.Print("Data mode set to " .. mode)

    -- Fire callback to refresh UI
    self:FireCallbacks("onItemAdded")

    return MalexisAuctionWatcherDB.settings.characterSpecific
end

-- Add a price entry for an item
function MAW:AddPriceEntry(itemName, minBid, buyout, stackSize, source)
    local db = self:GetActiveDB()
    if not db.items[itemName] then
        return
    end

    source = source or "scan"
    local priceData = db.items[itemName].prices
    local timestamp = time()

    -- Calculate price per unit
    local minBidPerUnit = minBid / stackSize
    local buyoutPerUnit = buyout > 0 and (buyout / stackSize) or 0

    -- Add new entry
    table.insert(priceData, 1, {
        timestamp = timestamp,
        minBid = minBid,
        buyout = buyout,
        stackSize = stackSize,
        minBidPerUnit = minBidPerUnit,
        buyoutPerUnit = buyoutPerUnit,
        source = source,
        date = date("%Y-%m-%d %H:%M:%S", timestamp)
    })

    -- Trim to max entries
    while #priceData > MalexisAuctionWatcherDB.settings.maxEntries do
        table.remove(priceData)
    end

    -- Long-term history
    if self.RecordHistory then
        local unitPrice = buyoutPerUnit > 0 and buyoutPerUnit or minBidPerUnit
        self:RecordHistory(itemName, unitPrice, source, timestamp)
    end

    -- Fire callback
    self:FireCallbacks("onPriceAdded", itemName)
end

_G.MalexisAuctionWatcher = MAW
