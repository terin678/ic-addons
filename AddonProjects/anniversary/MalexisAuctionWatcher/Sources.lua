-- Sources.lua - Optional price feeds from Auctionator and TradeSkillMaster
local addonName = "MalexisAuctionWatcher"
local MAW = _G.MalexisAuctionWatcher or {}

local CALLER_ID = "MalexisAuctionWatcher"
local PULL_DEBOUNCE = 2      -- seconds
local EXTERNAL_ENTRY_MIN_AGE = 3600  -- don't add a main-table entry more often than hourly per item

-- Auctionator's day zero (its history days count from this)
local ATR_SCAN_DAY_0 = time({ year = 2020, month = 1, day = 1, hour = 0 })

MAW.sources = MAW.sources or {
    auctionator = { available = false },
    tsm = { available = false },
}

local pullPending = false
local atrRegistered = false

local function SourceSettings()
    if not MalexisAuctionWatcherDB then
        return {}
    end
    MalexisAuctionWatcherDB.settings = MalexisAuctionWatcherDB.settings or {}
    MalexisAuctionWatcherDB.settings.sources = MalexisAuctionWatcherDB.settings.sources or {}
    return MalexisAuctionWatcherDB.settings.sources
end

function MAW:IsSourceEnabled(key)
    local s = SourceSettings()
    if s[key] == nil then
        return true
    end
    return s[key]
end

function MAW:SetSourceEnabled(key, enabled)
    local s = SourceSettings()
    s[key] = enabled and true or false
end

-- Detect what is loaded. Safe to call more than once.
function MAW:DetectSources()
    local atr = _G.Auctionator
    self.sources.auctionator.available = (atr and atr.API and atr.API.v1
        and type(atr.API.v1.GetAuctionPriceByItemID) == "function") and true or false

    local tsm = _G.TSM_API
    self.sources.tsm.available = (tsm and type(tsm.GetCustomPriceValue) == "function"
        and type(tsm.ToItemString) == "function") and true or false

    if self.sources.auctionator.available and not atrRegistered
        and type(atr.API.v1.RegisterForDBUpdate) == "function" then
        local ok = pcall(atr.API.v1.RegisterForDBUpdate, CALLER_ID, function()
            MAW:SchedulePull("auctionator")
        end)
        atrRegistered = ok
    end
end

-- Coalesce bursts of update callbacks into one pull
function MAW:SchedulePull(reason)
    if pullPending then
        return
    end
    pullPending = true
    C_Timer.After(PULL_DEBOUNCE, function()
        pullPending = false
        MAW:PullExternalPrices(reason)
    end)
end

-- True if we already have a "scan" entry for this item within the current hour
local function HasRecentScanEntry(itemData)
    local latest = itemData.prices and itemData.prices[1]
    if not latest or not latest.timestamp then
        return false
    end
    if (latest.source or "scan") ~= "scan" then
        return false
    end
    return (time() - latest.timestamp) < EXTERNAL_ENTRY_MIN_AGE
end

local function NewestEntryAge(itemData)
    local latest = itemData.prices and itemData.prices[1]
    if not latest or not latest.timestamp then
        return math.huge
    end
    return time() - latest.timestamp
end

MAW.SOURCE_LABELS = { scan = "Scan", atr = "Auctionator", tsm = "TSM", ext = "External", custom = "Custom bound", tsm14 = "TSM 14d", tsm60 = "TSM 60d", vendor = "Vendor" }

-- TSM price sources pulled per item, in display order. money=false means a rate or count.
MAW.TSM_KEYS = {
    "DBMinBuyout", "DBMarket", "DBRecent", "DBHistorical",
    "DBRegionMarketAvg", "DBRegionHistorical", "DBRegionSaleAvg", "DBRegionSaleRate", "DBRegionSoldPerDay",
    "SmartAvgBuy", "AvgBuy", "MinBuy", "MaxBuy", "AvgSell", "MinSell", "MaxSell",
    "VendorSell", "Crafting",
}
MAW.TSM_KEY_INFO = {
    DBMinBuyout        = { label = "Min buyout (realm)",        group = "AuctionDB" },
    DBMarket           = { label = "Market value (14d)",        group = "AuctionDB" },
    DBRecent           = { label = "Recent value",              group = "AuctionDB" },
    DBHistorical       = { label = "Historical (60d)",          group = "AuctionDB" },
    DBRegionMarketAvg  = { label = "Region market avg",         group = "AuctionDB" },
    DBRegionHistorical = { label = "Region historical",         group = "AuctionDB" },
    DBRegionSaleAvg    = { label = "Region sale avg",           group = "AuctionDB" },
    DBRegionSaleRate   = { label = "Region sale rate",          group = "AuctionDB", money = false, fmt = "%.2f" },
    DBRegionSoldPerDay = { label = "Region sold per day",       group = "AuctionDB", money = false, fmt = "%.1f" },
    SmartAvgBuy        = { label = "Smart avg buy (you)",       group = "Accounting" },
    AvgBuy             = { label = "Avg buy (you)",             group = "Accounting" },
    MinBuy             = { label = "Min buy (you)",             group = "Accounting" },
    MaxBuy             = { label = "Max buy (you)",             group = "Accounting" },
    AvgSell            = { label = "Avg sell (you)",            group = "Accounting" },
    MinSell            = { label = "Min sell (you)",            group = "Accounting" },
    MaxSell            = { label = "Max sell (you)",            group = "Accounting" },
    VendorSell         = { label = "Vendor sell",               group = "Item" },
    Crafting           = { label = "TSM crafting cost",         group = "Crafting" },
}

-- Lines for a tooltip listing everything TSM reported for an item
function MAW:TsmTooltipLines(itemData)
    local ref = itemData and itemData.tsmRef
    if not ref or not ref.values then
        return {}
    end
    local lines = {}
    local lastGroup
    for _, key in ipairs(self.TSM_KEYS) do
        local value = ref.values[key]
        if value then
            local info = self.TSM_KEY_INFO[key]
            if info.group ~= lastGroup then
                table.insert(lines, { header = "TSM " .. info.group })
                lastGroup = info.group
            end
            local text
            if info.money == false then
                text = string.format(info.fmt or "%s", value)
            else
                text = self:FormatMoney(value)
            end
            local used = (key == ref.marketKey and " [14d col]") or (key == ref.historicalKey and " [60d col]") or ""
            table.insert(lines, { label = info.label .. used, value = text })
        end
    end
    return lines
end

MAW.SOURCE_TAGS = { atr = "A", tsm = "T" }

function MAW:SourceLabel(source)
    return self.SOURCE_LABELS[source or "scan"] or tostring(source)
end

-- Pull from Auctionator for one item. Returns true if anything was recorded,
-- plus a short diagnostic string.
function MAW:PullAuctionator(itemName, itemData)
    local atr = _G.Auctionator
    local api = atr and atr.API and atr.API.v1
    if not api or not itemData.itemID or itemData.itemID == 0 then
        return false, "no itemID"
    end

    local recorded = false
    local itemID = itemData.itemID
    local backfilledDays, historyRows = 0, 0

    -- Backfill daily history from Auctionator's internal DB (unsupported API, so guarded)
    if atr.Database and type(atr.Database.GetPriceHistory) == "function" then
        local ok, rows = pcall(atr.Database.GetPriceHistory, atr.Database, tostring(itemID))
        if ok and type(rows) == "table" then
            historyRows = #rows
            for _, row in ipairs(rows) do
                if row.rawDay and row.minSeen then
                    -- Auctionator days start at local midnight; use noon so DST shifts cannot move the day
                    local ts = tonumber(row.rawDay) * 86400 + ATR_SCAN_DAY_0 + 43200
                    local day = self:DayIndexFromTime(ts)
                    if self:BackfillHistory(itemName, day, row.minSeen, row.maxSeen, "atr") then
                        recorded = true
                        backfilledDays = backfilledDays + 1
                    end
                end
            end
        end
    end

    -- Current price counts as an observation only if Auctionator saw it today
    local okP, price = pcall(api.GetAuctionPriceByItemID, CALLER_ID, itemID)
    local okA, age = pcall(api.GetAuctionAgeByItemID, CALLER_ID, itemID)
    local addedToday = false
    if okP and price and price > 0 and okA and age == 0 then
        if not HasRecentScanEntry(itemData) and NewestEntryAge(itemData) >= EXTERNAL_ENTRY_MIN_AGE then
            self:AddPriceEntry(itemName, price, price, 1, "atr")
        else
            self:RecordHistory(itemName, price, "atr")
        end
        recorded = true
        addedToday = true
    end

    local detail
    if not okP or not price then
        detail = "Auctionator has never seen this item (run a Full Scan or search it on the Shopping tab)"
    else
        detail = string.format("price %s, last seen %s day(s) ago, %d history day(s), %d new day(s) merged%s",
            self:FormatMoney(price), tostring(age or "?"), historyRows, backfilledDays,
            addedToday and ", today's price recorded" or "")
    end
    return recorded, detail
end

-- Pull from TSM for one item. Returns true if anything was recorded, plus a diagnostic string.
function MAW:PullTSM(itemName, itemData)
    local tsm = _G.TSM_API
    if not tsm or not itemData.itemID or itemData.itemID == 0 then
        return false, "no itemID"
    end

    local okS, itemString = pcall(tsm.ToItemString, "item:" .. itemData.itemID)
    if not okS or not itemString then
        return false, "TSM could not resolve the item"
    end

    -- TSM keeps no per-day history; it exposes a current snapshot plus rolling averages.
    -- Store the averages as reference values for the chart, and record the snapshot as one observation.
    local function Value(key)
        local ok, value = pcall(tsm.GetCustomPriceValue, key, itemString)
        if ok and type(value) == "number" and value > 0 then
            return value
        end
        return nil
    end

    -- Every TSM price source we care about. Money values are copper; rates are plain numbers.
    local ref = { values = {}, time = time() }
    for _, key in ipairs(MAW.TSM_KEYS) do
        ref.values[key] = Value(key)
    end
    local v = ref.values

    -- The two summary columns, with fallbacks for realms where TSM lacks realm-level averages
    local function FirstOf(keys)
        for _, key in ipairs(keys) do
            if v[key] then return v[key], key end
        end
        return nil, nil
    end
    ref.minBuyout = v.DBMinBuyout
    ref.market, ref.marketKey = FirstOf({ "DBMarket", "DBRecent", "DBRegionMarketAvg", "DBRegionSaleAvg" })
    ref.historical, ref.historicalKey = FirstOf({ "DBHistorical", "DBRegionHistorical", "DBRegionSaleAvg" })

    local price = ref.minBuyout or ref.market
    if not price then
        itemData.tsmRef = nil
        return false, "TSM has no AuctionDB data for this item (needs the TSM desktop app synced for this realm)"
    end
    itemData.tsmRef = ref

    if not HasRecentScanEntry(itemData) and NewestEntryAge(itemData) >= EXTERNAL_ENTRY_MIN_AGE then
        self:AddPriceEntry(itemName, price, price, 1, "tsm")
    else
        self:RecordHistory(itemName, price, "tsm")
    end

    local parts = {}
    if ref.minBuyout then table.insert(parts, "min buyout " .. self:FormatMoney(ref.minBuyout)) end
    if ref.market then table.insert(parts, "14d " .. self:FormatMoney(ref.market) .. " (" .. ref.marketKey .. ")") end
    if ref.historical then table.insert(parts, "60d " .. self:FormatMoney(ref.historical) .. " (" .. ref.historicalKey .. ")") end
    local n = 0
    for _ in pairs(v) do n = n + 1 end
    table.insert(parts, n .. " TSM fields")
    return true, table.concat(parts, ", ")
end

-- Pull external prices for every tracked item.
-- only: nil (all enabled sources), "auctionator" or "tsm"
-- verbose: print a per-item report to chat
-- Returns number of items that received data.
function MAW:PullExternalPrices(reason, only, verbose)
    self:DetectSources()
    local useAtr = (not only or only == "auctionator")
        and self.sources.auctionator.available and self:IsSourceEnabled("auctionator")
    local useTsm = (not only or only == "tsm")
        and self.sources.tsm.available and self:IsSourceEnabled("tsm")
    if not useAtr and not useTsm then
        if verbose then
            print(addonName .. ": No external source is available and enabled (" .. self:DescribeSources() .. ")")
        end
        return 0
    end

    local db = self:GetActiveDB()
    local count, total = 0, 0
    for itemName, itemData in pairs(db.items) do
        total = total + 1
        local got = false
        if useAtr then
            local ok, detail = self:PullAuctionator(itemName, itemData)
            got = got or ok
            if verbose then
                print(string.format("  %s%s|r %s: %s", ok and "|cff80ff80" or "|cffff8080", "[Auctionator]", itemName, detail or ""))
            end
        end
        if useTsm then
            local ok, detail = self:PullTSM(itemName, itemData)
            got = got or ok
            if verbose then
                print(string.format("  %s%s|r %s: %s", ok and "|cff80ff80" or "|cffff8080", "[TSM]", itemName, detail or ""))
            end
        end
        if got then
            count = count + 1
        end
    end

    if verbose or self.debugMode then
        print(addonName .. ": External pull (" .. tostring(reason) .. ") found data for " .. count .. " of " .. total .. " items")
    end
    if count > 0 then
        self:FireCallbacks("onScanComplete")
    end
    return count
end

-- Human-readable status for /maw sources and the History tab
function MAW:DescribeSources()
    self:DetectSources()
    local parts = { "scan" }
    if self.sources.auctionator.available then
        table.insert(parts, "Auctionator (" .. (self:IsSourceEnabled("auctionator") and "on" or "off") .. ")")
    else
        table.insert(parts, "Auctionator (not loaded)")
    end
    if self.sources.tsm.available then
        table.insert(parts, "TSM (" .. (self:IsSourceEnabled("tsm") and "on" or "off") .. ")")
    else
        table.insert(parts, "TSM (not loaded)")
    end
    return table.concat(parts, ", ")
end

_G.MalexisAuctionWatcher = MAW
