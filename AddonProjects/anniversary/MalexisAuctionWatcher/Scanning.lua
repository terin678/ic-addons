-- Scanning.lua - Auction house scanning as an explicit state machine
--
-- States:
--   idle      nothing running
--   pending   an item is queued; waiting for the client to allow a query
--   waiting   query sent; waiting for AUCTION_ITEM_LIST_UPDATE
--   settling  results arrived but rows were not populated yet; retrying with a delay
local addonName = "MalexisAuctionWatcher"
local MAW = _G.MalexisAuctionWatcher or {}

local TICK = 0.1                 -- OnUpdate throttle, seconds
local PENDING_TIMEOUT = 15       -- give up if the client never allows a query
local RESULT_TIMEOUT = 10        -- give up on one item if no usable results arrive
local EVENT_NO_SLOT_GRACE = 3    -- event fired but CanSendAuctionQuery stuck: proceed after this
local SLOT_NO_EVENT_GRACE = 1    -- CanSendAuctionQuery true but no event: proceed after this
local SETTLE_DELAY = 0.25
local SETTLE_MAX = 8

MAW.scan = MAW.scan or {
    state = "idle",
    queue = {},
    current = nil,
    sentAt = 0,
    pendingSince = 0,
    listUpdated = false,
    settleAt = 0,
    settleTries = 0,
    total = 0,
    done = 0,
    accum = 0,
}

local function Debug(msg)
    if MAW.debugMode then
        print(addonName .. " [DEBUG]: " .. msg)
    end
end

local function AtAuctionHouse()
    return AuctionFrame and AuctionFrame:IsVisible()
end

function MAW:IsScanning()
    return self.scan.state ~= "idle"
end

-- Back-compat alias used by older code paths
function MAW:GetCurrentScanItem()
    return self.scan.current
end

local function Progress()
    MAW:FireCallbacks("onScanProgress", MAW.scan.done, MAW.scan.total, MAW.scan.current)
end

local function ResetState()
    local s = MAW.scan
    s.state = "idle"
    s.queue = {}
    s.current = nil
    s.sentAt = 0
    s.pendingSince = 0
    s.listUpdated = false
    s.settleAt = 0
    s.settleTries = 0
    s.total = 0
    s.done = 0
    MAW.currentScan = nil
    MAW.waitingForResults = false
end

local function Contains(list, value)
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

-- Start a scan of the given item names, or merge them into a running scan.
function MAW:StartScan(itemNames, label)
    if not AtAuctionHouse() then
        print(addonName .. ": You must be at the Auction House to scan")
        UIErrorsFrame:AddMessage("You must be at the Auction House to scan", 1.0, 0.1, 0.1, 1.0)
        return false
    end

    local db = self:GetActiveDB()
    local wanted = {}
    for _, name in ipairs(itemNames or {}) do
        if db.items[name] and not Contains(wanted, name) then
            table.insert(wanted, name)
        end
    end
    if #wanted == 0 then
        print(addonName .. ": No items to scan. Use /maw add to track items.")
        return false
    end

    local s = self.scan
    if s.state ~= "idle" then
        local added = 0
        for _, name in ipairs(wanted) do
            if name ~= s.current and not Contains(s.queue, name) then
                table.insert(s.queue, name)
                added = added + 1
            end
        end
        s.total = s.total + added
        if added > 0 then
            print(string.format("%s: Added %d item(s) to the running scan (%d/%d done)", addonName, added, s.done, s.total))
        else
            print(addonName .. ": Those items are already in the running scan")
        end
        Progress()
        return true
    end

    ResetState()
    s.queue = wanted
    s.total = #wanted
    s.state = "pending"
    s.pendingSince = GetTime()
    print(string.format("%s: %s (%d items)...", addonName, label or "Starting scan", s.total))
    Progress()
    return true
end

-- Stop whatever is running and reset. Safe in any state.
function MAW:CancelScan(reason)
    if self.scan.state == "idle" then
        return false
    end
    ResetState()
    print(addonName .. ": Scan cancelled" .. (reason and (" (" .. reason .. ")") or ""))
    self:FireCallbacks("onScanComplete")
    Progress()
    return true
end

function MAW:ScanStatusText()
    local s = self.scan
    if s.state == "idle" then
        return "idle"
    end
    return string.format("%s, %d/%d done, current: %s", s.state, s.done, s.total, s.current or "-")
end

-- Public entry points
function MAW:ScanAuctionHouse()
    local db = self:GetActiveDB()
    local names = {}
    for itemName in pairs(db.items) do
        table.insert(names, itemName)
    end
    table.sort(names)
    return self:StartScan(names, "Starting scan")
end

function MAW:ScanSingleItem(itemName)
    local db = self:GetActiveDB()
    if not db.items[itemName] then
        print(addonName .. ": Not tracking " .. tostring(itemName))
        return false
    end
    return self:StartScan({ itemName }, "Scanning " .. itemName)
end

-- Called from Core on AUCTION_ITEM_LIST_UPDATE
function MAW:OnAuctionListUpdate()
    local s = self.scan
    if s.state == "waiting" then
        Debug("AUCTION_ITEM_LIST_UPDATE received for " .. tostring(s.current))
        s.listUpdated = true
    end
end

local function FinishScan()
    local s = MAW.scan
    ResetState()
    print(addonName .. ": Scan complete!")
    local db = MAW:GetActiveDB()
    db.lastScanTime = time()
    MAW:FireCallbacks("onScanComplete")
    Progress()
    if MAW.SchedulePull then
        MAW:SchedulePull("scan_complete")
    end
end

-- Move to the next queued item, or finish
local function Advance()
    local s = MAW.scan
    s.current = nil
    MAW.currentScan = nil
    s.listUpdated = false
    s.settleTries = 0
    if #s.queue == 0 then
        FinishScan()
        return
    end
    s.state = "pending"
    s.pendingSince = GetTime()
    Progress()
end

local function SendQuery()
    local s = MAW.scan
    s.current = table.remove(s.queue, 1)
    MAW.currentScan = s.current
    s.listUpdated = false
    s.sentAt = GetTime()
    s.state = "waiting"
    Debug("Querying: " .. s.current)
    -- name, minLevel, maxLevel, page, isUsable, qualityIndex, getAll, exactMatch, filterData
    QueryAuctionItems(s.current, nil, nil, 0, false, nil, false, true, nil)
    Progress()
end

-- Read the result list for the current item. Returns true when done with this item,
-- false when rows were not populated yet (caller will retry).
local function ProcessResults()
    local s = MAW.scan
    local itemName = s.current
    local numAuctions = GetNumAuctionItems("list")
    Debug("Found " .. numAuctions .. " auction entries for " .. itemName)

    if numAuctions == 0 then
        Debug("No auctions found for " .. itemName)
        return true
    end

    local cheapestBuyout, cheapestBuyoutStack, cheapestBuyoutBid
    local cheapestBid, cheapestBidStack, cheapestBidBuyout
    local dataReady = false

    for i = 1, numAuctions do
        local name, _, stackSize, _, _, _, _, minBid, _, buyoutPrice = GetAuctionItemInfo("list", i)
        if name and type(minBid) == "number" and stackSize then
            dataReady = true
            if name == itemName then
                if buyoutPrice and buyoutPrice > 0 and stackSize > 0 then
                    local perUnit = buyoutPrice / stackSize
                    if not cheapestBuyout or perUnit < (cheapestBuyout / cheapestBuyoutStack) then
                        cheapestBuyout, cheapestBuyoutStack, cheapestBuyoutBid = buyoutPrice, stackSize, minBid
                    end
                end
                if minBid > 0 and stackSize > 0 then
                    local perUnit = minBid / stackSize
                    if not cheapestBid or perUnit < (cheapestBid / cheapestBidStack) then
                        cheapestBid, cheapestBidStack, cheapestBidBuyout = minBid, stackSize, buyoutPrice or 0
                    end
                end
            end
        end
    end

    if not dataReady then
        return false
    end

    if cheapestBuyout then
        MAW:AddPriceEntry(itemName, cheapestBuyoutBid, cheapestBuyout, cheapestBuyoutStack)
        Debug("Recorded " .. itemName .. " buyout " .. MAW:FormatMoney(cheapestBuyout) .. " (" .. cheapestBuyoutStack .. "x)")
    elseif cheapestBid then
        MAW:AddPriceEntry(itemName, cheapestBid, cheapestBidBuyout, cheapestBidStack)
        Debug("Recorded " .. itemName .. " bid only " .. MAW:FormatMoney(cheapestBid) .. " (" .. cheapestBidStack .. "x)")
    else
        Debug("No valid prices for " .. itemName)
    end
    return true
end

local function TryProcess()
    local s = MAW.scan
    if ProcessResults() then
        s.done = s.done + 1
        Advance()
    else
        s.state = "settling"
        s.settleTries = s.settleTries + 1
        s.settleAt = GetTime() + SETTLE_DELAY
        Debug("Rows not populated yet, settle attempt " .. s.settleTries)
    end
end

-- Driven by the event frame's OnUpdate in Core.lua
function MAW:OnUpdateHandler(frame, elapsed)
    local s = self.scan
    if s.state == "idle" then
        return
    end

    s.accum = (s.accum or 0) + (elapsed or 0)
    if s.accum < TICK then
        return
    end
    s.accum = 0

    if not AtAuctionHouse() then
        self:CancelScan("auction house closed")
        return
    end

    local now = GetTime()

    if s.state == "pending" then
        if CanSendAuctionQuery() then
            SendQuery()
        elseif now - s.pendingSince > PENDING_TIMEOUT then
            self:CancelScan("the client would not allow another query for " .. PENDING_TIMEOUT .. "s")
        end

    elseif s.state == "waiting" then
        local since = now - s.sentAt
        local canSend = CanSendAuctionQuery()
        if s.listUpdated and canSend then
            TryProcess()
        elseif s.listUpdated and since > EVENT_NO_SLOT_GRACE then
            Debug("Event fired but query slot still busy; processing anyway")
            TryProcess()
        elseif canSend and since > SLOT_NO_EVENT_GRACE then
            Debug("Query slot free but no event; processing anyway")
            TryProcess()
        elseif since > RESULT_TIMEOUT then
            print(addonName .. ": No results for " .. tostring(s.current) .. " (timed out), skipping")
            s.done = s.done + 1
            Advance()
        end

    elseif s.state == "settling" then
        if now >= s.settleAt then
            if s.settleTries >= SETTLE_MAX then
                print(addonName .. ": Results for " .. tostring(s.current) .. " never populated, skipping")
                s.done = s.done + 1
                Advance()
            else
                TryProcess()
            end
        end
    end
end

_G.MalexisAuctionWatcher = MAW
