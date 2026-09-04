-- Database.lua - Database initialization and price entry management
local addonName = "MalexisAuctionWatcher"
local MAW = _G.MalexisAuctionWatcher or {}

-- Constants
local MAX_PRICE_ENTRIES = 10

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

-- Deep copy table helper
local function DeepCopy(original)
    local copy
    if type(original) == 'table' then
        copy = {}
        for k, v in pairs(original) do
            copy[k] = DeepCopy(v)
        end
    else
        copy = original
    end
    return copy
end

-- Copy account-wide data to character-specific
function MAW:CopyAccountDataToCharacter()
    if MalexisAuctionWatcherDB.items and next(MalexisAuctionWatcherDB.items) then
        MalexisAuctionWatcherCharDB.items = DeepCopy(MalexisAuctionWatcherDB.items)
        print(addonName .. ": Copied " .. self:CountItems(MalexisAuctionWatcherCharDB.items) .. " items from account-wide to character-specific database")
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

-- Initialize SavedVariables
function MAW:InitializeDB()
    -- Initialize account-wide DB
    if not MalexisAuctionWatcherDB then
        MalexisAuctionWatcherDB = {
            items = {},
            settings = {
                autoScan = false,
                maxEntries = MAX_PRICE_ENTRIES,
                characterSpecific = false  -- Default to account-wide
            },
            cache = {
                bank = {},
                auctionHouse = {},
                recipes = {}
            },
            lastScanTime = nil  -- Timestamp of last successful AH scan
        }
    end

    -- Ensure settings exists
    if not MalexisAuctionWatcherDB.settings then
        MalexisAuctionWatcherDB.settings = {
            autoScan = false,
            maxEntries = MAX_PRICE_ENTRIES,
            characterSpecific = false
        }
    end
    if MalexisAuctionWatcherDB.settings.characterSpecific == nil then
        MalexisAuctionWatcherDB.settings.characterSpecific = false
    end
    -- Left nil on purpose: the window shrinks to fit the screen on its first open and
    -- stores what it chose. A default of 1 here would skip that and open oversized.

    -- Ensure cache exists (account-wide)
    if not MalexisAuctionWatcherDB.cache then
        MalexisAuctionWatcherDB.cache = {
            bank = {},
            auctionHouse = {},
            recipes = {}
        }
    end
    if not MalexisAuctionWatcherDB.cache.auctionHouse then
        MalexisAuctionWatcherDB.cache.auctionHouse = {}
    end
    if not MalexisAuctionWatcherDB.cache.recipes then
        MalexisAuctionWatcherDB.cache.recipes = {}
    end

    -- Initialize character-specific DB
    if not MalexisAuctionWatcherCharDB then
        MalexisAuctionWatcherCharDB = {
            items = {},
            cache = {
                bank = {},
                auctionHouse = {},
                recipes = {}
            },
            lastScanTime = nil  -- Timestamp of last successful AH scan
        }
    end

    -- Ensure cache exists (character-specific)
    if not MalexisAuctionWatcherCharDB.cache then
        MalexisAuctionWatcherCharDB.cache = {
            bank = {},
            auctionHouse = {},
            recipes = {}
        }
    end
    if not MalexisAuctionWatcherCharDB.cache.auctionHouse then
        MalexisAuctionWatcherCharDB.cache.auctionHouse = {}
    end
    if not MalexisAuctionWatcherCharDB.cache.recipes then
        MalexisAuctionWatcherCharDB.cache.recipes = {}
    end

    -- History settings and migration
    if not MalexisAuctionWatcherDB.settings.historyDays then
        MalexisAuctionWatcherDB.settings.historyDays = 180
    end
    if not MalexisAuctionWatcherDB.settings.sources then
        MalexisAuctionWatcherDB.settings.sources = {}
    end
    if self.MigrateHistory then
        self:MigrateHistory()
    end
    if self.RepairGemPresetData then
        self:RepairGemPresetData()
    end
end

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
    print(addonName .. ": Data mode set to " .. mode)

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
