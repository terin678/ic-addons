-- MalexisAuctionWatcher UI Module
local addonName = "MalexisAuctionWatcher"
local MAWUI = {}

-- Color constants for price ranges
local COLOR_LOW = {r = 0.5, g = 1.0, b = 0.5}      -- Green
local COLOR_AVE = {r = 1.0, g = 1.0, b = 0.5}      -- Yellow
local COLOR_HIGH = {r = 1.0, g = 0.5, b = 0.5}     -- Red
local COLOR_BELOW = {r = 0.3, g = 0.6, b = 1.0}    -- Blue (below low)
local COLOR_ABOVE = {r = 1.0, g = 0.3, b = 1.0}    -- Magenta (above high)

-- UI Configuration
local CELL_WIDTH = 80
local CELL_HEIGHT = 20
local HEADER_HEIGHT = 25
local ROW_NAME_WIDTH = 220  -- Wider to support long names like "Greater Shadow Protection Potion"
local CONTROL_BUTTON_SIZE = 18
local CONTROLS_WIDTH = 65  -- Space for up/down/refresh buttons
local PADDING = 5
local CONTROL_SECTION_HEIGHT = 60
local TAB_HEIGHT = 30
local RECIPE_CONTROLS_WIDTH = 26
-- Recipes tab columns. The two TSM profit columns appear only when the TSM feed is on.
local function RecipeColumns()
    local cols = {
        { header = "Recipe",   width = 230, key = "name" },
        { header = "Mat cost", width = 90,  key = "matCost" },
        { header = "Product",  width = 90,  key = "productValue" },
        { header = "AH net",   width = 90,  key = "ahNet" },
    }
    local MAW = _G.MalexisAuctionWatcher
    local tsmOn = MAW and MAW.sources and MAW.sources.tsm and MAW.sources.tsm.available and MAW:IsSourceEnabled("tsm")
    if tsmOn then
        table.insert(cols, { header = "Profit 60d", width = 90, key = "profitTsm60", basis = "tsm60" })
        table.insert(cols, { header = "Profit 14d", width = 90, key = "profitTsm14", basis = "tsm14" })
    end
    table.insert(cols, { header = "Profit",   width = 90, key = "profit" })
    table.insert(cols, { header = "Margin",   width = 70, key = "margin" })
    table.insert(cols, { header = "Can make", width = 60, key = "canMake" })
    return cols
end
local TSM_CELL_WIDTH = 80
local TSM_COLUMNS = {
    { key = "historical", header = "TSM 60d", label = "TSM historical (60 day)" },
    { key = "market",     header = "TSM 14d", label = "TSM market value (14 day)" },
}

-- Main frame and tabs
local mainFrame = nil
local windowTitle = "Malexis Auction Watcher"
local currentTab = "materials"  -- "materials" or "products"

-- Parse money input (supports formats like "1g", "50s", "25c", "1.5g", etc.)
local function ParseMoneyInput(input)
    if not input or input == "" then
        return nil
    end

    local total = 0

    -- Parse gold
    local gold = input:match("(%d+%.?%d*)g")
    if gold then
        total = total + (tonumber(gold) * 10000)
    end

    -- Parse silver
    local silver = input:match("(%d+%.?%d*)s")
    if silver then
        total = total + (tonumber(silver) * 100)
    end

    -- Parse copper
    local copper = input:match("(%d+)c")
    if copper then
        total = total + tonumber(copper)
    end

    -- If no suffix, treat as gold
    if not gold and not silver and not copper then
        local num = tonumber(input)
        if num then
            total = num * 10000  -- Assume gold
        end
    end

    return total > 0 and total or nil
end

-- Public handler for StaticPopup dialogs to parse money input (legacy)
_G.MAW_ParseMoneyInput = ParseMoneyInput

-- Get FormatMoney function from Helpers module
local function FormatMoney(copper)
    if _G.MalexisAuctionWatcherHelpers then
        return _G.MalexisAuctionWatcherHelpers.FormatMoney(copper)
    end
    -- Fallback if Helpers not loaded yet
    if not copper or copper == 0 then
        return "0c"
    end
    local gold = math.floor(copper / 10000)
    if gold > 0 then
        return string.format("%.2fg", copper / 10000)
    end
    local silver = math.floor((copper % 10000) / 100)
    if silver > 0 then
        return string.format("%.1fs", copper / 100)
    end
    return string.format("%dc", copper)
end

-- Calculate price statistics
local function CalculatePriceStats(itemName)
    local MAW = _G.MalexisAuctionWatcher
    local db = MAW:GetActiveDB()
    if not db or not db.items[itemName] then
        return nil
    end

    local itemData = db.items[itemName]
    local prices = itemData.prices

    -- If no prices yet, return custom prices if set, otherwise zeros (still show in list)
    if #prices == 0 then
        local low = itemData.customLow or 0
        local high = itemData.customHigh or 0
        local average = (low + high) / 2
        return {
            low = low,
            average = average,
            high = high,
            today = 0,
            todayBuyout = 0,
            todayBid = 0,
            isCustomLow = itemData.customLow ~= nil,
            isCustomHigh = itemData.customHigh ~= nil,
            itemType = itemData.itemType or "material",
            noPriceData = true
        }
    end

    -- Get most recent price (today)
    local today = prices[1]

    -- Check if custom bounds are set
    local low, high
    if itemData.customLow then
        low = itemData.customLow
    end
    if itemData.customHigh then
        high = itemData.customHigh
    end

    -- Calculate low, average, high from all prices if not custom set
    local minBids = {}
    local buyouts = {}

    for _, entry in ipairs(prices) do
        if entry.minBid and entry.minBid > 0 then
            table.insert(minBids, entry.minBidPerUnit)
        end
        if entry.buyout and entry.buyout > 0 then
            table.insert(buyouts, entry.buyoutPerUnit)
        end
    end

    if #buyouts == 0 then
        return nil
    end

    -- Calculate statistics on buyout prices (per unit)
    table.sort(buyouts)
    if not low then
        low = buyouts[1]
    end
    if not high then
        high = buyouts[#buyouts]
    end

    -- Calculate average: if custom bounds are set, use midpoint; otherwise use actual average
    local average
    if itemData.customLow or itemData.customHigh then
        -- Use midpoint of low and high when custom bounds are set
        average = (low + high) / 2
    else
        -- Use actual average from price data
        local sum = 0
        for _, price in ipairs(buyouts) do
            sum = sum + price
        end
        average = sum / #buyouts
    end

    return {
        low = low,
        average = average,
        high = high,
        today = today.buyoutPerUnit > 0 and today.buyoutPerUnit or today.minBidPerUnit,
        todayBuyout = today.buyoutPerUnit,
        todayBid = today.minBidPerUnit,
        isCustomLow = itemData.customLow ~= nil,
        isCustomHigh = itemData.customHigh ~= nil,
        itemType = itemData.itemType or "material"
    }
end

-- Linear interpolation between two values
local function Lerp(a, b, t)
    return a + (b - a) * t
end

-- Get color based on value position with smooth gradient
-- invertColors: true for products (high=green, low=red), false for materials (low=green, high=red)
local function GetPriceColor(value, low, high, invertColors)
    if not value or not low or not high then
        return COLOR_AVE
    end

    local range = high - low
    if range == 0 then
        return COLOR_AVE
    end

    -- Below low range
    if value < low then
        return invertColors and COLOR_ABOVE or COLOR_BELOW  -- Products: magenta, Materials: blue
    end

    -- Above high range
    if value > high then
        return invertColors and COLOR_BELOW or COLOR_ABOVE  -- Products: blue, Materials: magenta
    end

    -- Calculate position within range (0 to 1)
    local position = (value - low) / range

    -- Invert position for products (so high values are green)
    if invertColors then
        position = 1 - position
    end

    -- Lerp between green -> yellow -> red
    local r, g, b
    if position < 0.5 then
        -- Green to Yellow (first half)
        local t = position * 2  -- 0 to 1
        r = Lerp(COLOR_LOW.r, COLOR_AVE.r, t)
        g = Lerp(COLOR_LOW.g, COLOR_AVE.g, t)
        b = Lerp(COLOR_LOW.b, COLOR_AVE.b, t)
    else
        -- Yellow to Red (second half)
        local t = (position - 0.5) * 2  -- 0 to 1
        r = Lerp(COLOR_AVE.r, COLOR_HIGH.r, t)
        g = Lerp(COLOR_AVE.g, COLOR_HIGH.g, t)
        b = Lerp(COLOR_AVE.b, COLOR_HIGH.b, t)
    end

    return {r = r, g = g, b = b}
end


-- Hover tooltip citing the latest price, its source and when it was recorded
local function AttachSourceTooltip(cell, itemName, itemData)
    local MAW = _G.MalexisAuctionWatcher
    local latest = itemData and itemData.prices and itemData.prices[1]
    if not latest then return end
    cell:EnableMouse(true)
    cell:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(itemName)
        local unit = (latest.buyoutPerUnit and latest.buyoutPerUnit > 0) and latest.buyoutPerUnit or latest.minBidPerUnit
        GameTooltip:AddDoubleLine("Latest price", FormatMoney(unit or 0), 1, 1, 1, 1, 0.8, 0.5)
        GameTooltip:AddDoubleLine("Source", MAW.SourceLabel and MAW:SourceLabel(latest.source) or (latest.source or "scan"), 1, 1, 1, 0.9, 0.7, 0.4)
        GameTooltip:AddDoubleLine("Recorded", latest.date or "?", 1, 1, 1, 0.8, 0.8, 0.8)
        for _, line in ipairs(MAW:TsmTooltipLines(itemData)) do
            if line.header then
                GameTooltip:AddLine(line.header, 0.9, 0.7, 1)
            else
                GameTooltip:AddDoubleLine("  " .. line.label, line.value, 1, 1, 1, 1, 0.9, 0.6)
            end
        end
        GameTooltip:Show()
    end)
    cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- "[A]" / "[T]" suffix when the latest entry came from an external source
local function SourceTag(itemData)
    local MAW = _G.MalexisAuctionWatcher
    local latest = itemData and itemData.prices and itemData.prices[1]
    local tag = latest and MAW.SOURCE_TAGS and MAW.SOURCE_TAGS[latest.source]
    return tag and (" |cffe0b060[" .. tag .. "]|r") or ""
end

-- TSM columns show when the TSM feed is loaded and enabled
local function TsmColumnsShown()
    local MAW = _G.MalexisAuctionWatcher
    return MAW and MAW.sources and MAW.sources.tsm and MAW.sources.tsm.available and MAW:IsSourceEnabled("tsm")
end

local function TsmColumnsWidth()
    return TsmColumnsShown() and (#TSM_COLUMNS * TSM_CELL_WIDTH) or 0
end

-- Forward declarations; defined below CreateCell
local AddTsmCells, AddTsmHeaders

-- Create a cell
local function CreateCell(parent, text, color, width, height, clickable, onClick)
    local cell = CreateFrame("Frame", nil, parent)
    cell:SetSize(width or CELL_WIDTH, height or CELL_HEIGHT)

    if clickable then
        cell:EnableMouse(true)
        cell:SetScript("OnEnter", function(self)
            self.bg:SetColorTexture(color.r * 1.2, color.g * 1.2, color.b * 1.2, 0.5)
        end)
        cell:SetScript("OnLeave", function(self)
            self.bg:SetColorTexture(color.r, color.g, color.b, 0.3)
        end)
        cell:SetScript("OnMouseDown", function(self)
            if onClick then
                onClick(self)
            end
        end)
    end

    -- Background
    local bg = cell:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(cell)
    bg:SetColorTexture(color.r, color.g, color.b, 0.3)
    cell.bg = bg

    -- Border
    local border = cell:CreateTexture(nil, "BORDER")
    border:SetColorTexture(0.2, 0.2, 0.2, 1)
    border:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, 0)
    border:SetPoint("BOTTOMRIGHT", cell, "TOPRIGHT", 0, -1)

    local border2 = cell:CreateTexture(nil, "BORDER")
    border2:SetColorTexture(0.2, 0.2, 0.2, 1)
    border2:SetPoint("TOPLEFT", cell, "BOTTOMLEFT", 0, 0)
    border2:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", 0, 0)

    local border3 = cell:CreateTexture(nil, "BORDER")
    border3:SetColorTexture(0.2, 0.2, 0.2, 1)
    border3:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, 0)
    border3:SetPoint("BOTTOMRIGHT", cell, "BOTTOMLEFT", 1, 0)

    local border4 = cell:CreateTexture(nil, "BORDER")
    border4:SetColorTexture(0.2, 0.2, 0.2, 1)
    border4:SetPoint("TOPRIGHT", cell, "TOPRIGHT", 0, 0)
    border4:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", 0, 0)

    -- Text
    local label = cell:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER")
    label:SetText(text or "")
    cell.label = label

    return cell
end


-- Header cells for the TSM columns; returns the new x
AddTsmHeaders = function(parent, x, y)
    if not TsmColumnsShown() then return x end
    for _, col in ipairs(TSM_COLUMNS) do
        local header = CreateCell(parent, col.header, { r = 0.3, g = 0.2, b = 0.4 }, TSM_CELL_WIDTH, HEADER_HEIGHT)
        header:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        header.label:SetTextColor(0.9, 0.7, 1)
        table.insert(mainFrame.rows, header)
        x = x + TSM_CELL_WIDTH
    end
    return x
end

-- Value cells for the TSM columns, colored against the item's low/high bounds; returns the new x
AddTsmCells = function(parent, x, y, itemName, itemData, stats)
    if not TsmColumnsShown() then return x end
    local ref = itemData and itemData.tsmRef
    local invert = (itemData and itemData.itemType) == "product"
    for _, col in ipairs(TSM_COLUMNS) do
        local value = ref and ref[col.key]
        local color = { r = 0.15, g = 0.12, b = 0.18 }
        local text = "-"
        if value and value > 0 then
            text = FormatMoney(value)
            if stats and stats.low and stats.high and stats.high > 0 then
                color = GetPriceColor(value, stats.low, stats.high, invert)
            else
                color = { r = 0.3, g = 0.25, b = 0.35 }
            end
        end
        local cell = CreateCell(parent, text, color, TSM_CELL_WIDTH, CELL_HEIGHT)
        cell:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        cell:EnableMouse(true)
        cell:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(itemName)
            GameTooltip:AddLine(col.label, 0.9, 0.7, 1)
            if value and value > 0 then
                local usedKey = (col.key == "market") and ref.marketKey or ref.historicalKey
                GameTooltip:AddDoubleLine("Value", FormatMoney(value) .. (usedKey and (" (" .. usedKey .. ")") or ""), 1, 1, 1, 1, 0.8, 0.5)
                if ref.time then
                    GameTooltip:AddDoubleLine("Pulled", date("%Y-%m-%d %H:%M", ref.time), 1, 1, 1, 0.8, 0.8, 0.8)
                end
                if stats and stats.low and stats.high then
                    GameTooltip:AddDoubleLine("Your bounds", FormatMoney(stats.low) .. " - " .. FormatMoney(stats.high), 1, 1, 1, 0.8, 0.8, 0.8)
                end
                local MAW = _G.MalexisAuctionWatcher
                for _, line in ipairs(MAW:TsmTooltipLines(itemData)) do
                    if line.header then
                        GameTooltip:AddLine(line.header, 0.9, 0.7, 1)
                    else
                        GameTooltip:AddDoubleLine("  " .. line.label, line.value, 1, 1, 1, 1, 0.9, 0.6)
                    end
                end
            else
                GameTooltip:AddLine("No TSM data. Use Pull TSM on the History tab.", 0.7, 0.7, 0.7)
            end
            GameTooltip:Show()
        end)
        cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        table.insert(mainFrame.rows, cell)
        x = x + TSM_CELL_WIDTH
    end
    return x
end

-- Take whatever item is on the cursor and add it with default settings
local function AddItemFromCursor(itemType)
    local cursorType, _, itemLink = GetCursorInfo()
    if cursorType ~= "item" or not itemLink then
        return false
    end

    local itemName = GetItemInfo(itemLink)
    if not itemName then
        itemName = itemLink:match("%[(.-)%]")
    end
    ClearCursor()

    if itemName and _G.MalexisAuctionWatcher then
        _G.MalexisAuctionWatcher:AddItem(itemName, itemType)
        return true
    end
    return false
end

-- Create a drop target row at the bottom of a list. Dropping an item on it
-- registers the item with defaults, without opening the Add Item dialog.
local function CreateDropSlot(parent, yOffset, itemType, width)
    local slot = CreateFrame("Button", nil, parent)
    slot:SetSize(width, CELL_HEIGHT + 8)
    slot:SetPoint("TOPLEFT", parent, "TOPLEFT", PADDING, yOffset)
    slot:RegisterForDrag("LeftButton")

    slot.bg = slot:CreateTexture(nil, "BACKGROUND")
    slot.bg:SetAllPoints()
    slot.bg:SetColorTexture(0.15, 0.15, 0.2, 0.5)

    -- Dashed-looking border made from four thin lines
    local function Line(p1, r1, p2, r2)
        local t = slot:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.5, 0.5, 0.6, 0.8)
        t:SetPoint(p1, slot, r1, 0, 0)
        t:SetPoint(p2, slot, r2, 0, 0)
        return t
    end
    Line("TOPLEFT", "TOPLEFT", "BOTTOMRIGHT", "TOPRIGHT"):SetHeight(1)
    Line("BOTTOMLEFT", "BOTTOMLEFT", "TOPRIGHT", "BOTTOMRIGHT"):SetHeight(1)
    Line("TOPLEFT", "TOPLEFT", "BOTTOMRIGHT", "BOTTOMLEFT"):SetWidth(1)
    Line("TOPRIGHT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT"):SetWidth(1)

    slot.label = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    slot.label:SetPoint("CENTER")
    slot.label:SetText("Drop an item here to add it as a " .. itemType)
    slot.label:SetTextColor(0.7, 0.7, 0.8)

    slot:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(0.25, 0.3, 0.4, 0.7)
    end)
    slot:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(0.15, 0.15, 0.2, 0.5)
    end)
    slot:SetScript("OnReceiveDrag", function()
        AddItemFromCursor(itemType)
    end)
    slot:SetScript("OnMouseUp", function(_, mouseButton)
        if mouseButton == "LeftButton" then
            AddItemFromCursor(itemType)
        end
    end)

    return slot
end

-- Create tab button
local function CreateTabButton(parent, text, tabName, x)
    local tab = CreateFrame("Button", nil, parent)
    tab:SetSize(100, TAB_HEIGHT)
    tab:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", x, 0)

    -- Background
    tab.bg = tab:CreateTexture(nil, "BACKGROUND")
    tab.bg:SetAllPoints()
    tab.bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)

    -- Text
    tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    tab.text:SetPoint("CENTER")
    tab.text:SetText(text)

    -- Click handler
    tab:SetScript("OnClick", function()
        currentTab = tabName
        MAWUI:RefreshData()
        MAWUI:UpdateTabHighlights()
    end)

    -- Hover
    tab:SetScript("OnEnter", function(self)
        if currentTab ~= tabName then
            self.bg:SetColorTexture(0.3, 0.3, 0.3, 0.8)
        end
    end)
    tab:SetScript("OnLeave", function(self)
        if currentTab ~= tabName then
            self.bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
        end
    end)

    return tab
end

-- Create the main UI
function MAWUI:CreateUI()
    if mainFrame then
        return mainFrame
    end

    -- Main frame
    mainFrame = CreateFrame("Frame", "MalexisAuctionWatcherFrame", UIParent, "BasicFrameTemplateWithInset")
    mainFrame:SetSize(800, 400 + CONTROL_SECTION_HEIGHT)  -- Wider to accommodate longer item names and controls
    mainFrame.defaultHeight = 400 + CONTROL_SECTION_HEIGHT
    mainFrame.historyHeight = 620 + CONTROL_SECTION_HEIGHT
    mainFrame.defaultWidth = 800
    mainFrame:SetPoint("CENTER")
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)

    -- Register with UI escape handler so ESC key closes the window
    table.insert(UISpecialFrames, "MalexisAuctionWatcherFrame")

    -- Force to front of all addon UI
    mainFrame:SetFrameStrata("HIGH")
    mainFrame:SetFrameLevel(100)

    mainFrame:Hide()

    -- Closing while docked in the auction house goes back to the Browse tab
    mainFrame:HookScript("OnHide", function(self)
        if self.docked and AuctionFrame and AuctionFrame:IsShown() and AuctionFrameTab1 then
            AuctionFrameTab1:Click()
        end
    end)

    mainFrame.title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    mainFrame.title:SetPoint("CENTER", mainFrame.TitleBg, "CENTER", 5, 0)
    mainFrame.title:SetText(windowTitle)

    -- Control section at top
    local controlFrame = CreateFrame("Frame", nil, mainFrame)
    controlFrame:SetPoint("TOPLEFT", mainFrame.InsetBg or mainFrame, "TOPLEFT", 4, -4)
    controlFrame:SetPoint("TOPRIGHT", mainFrame.InsetBg or mainFrame, "TOPRIGHT", -4, -4)
    controlFrame:SetHeight(CONTROL_SECTION_HEIGHT)
    mainFrame.controlFrame = controlFrame

    -- Scan button
    local scanBtn = CreateFrame("Button", nil, controlFrame, "UIPanelButtonTemplate")
    scanBtn:SetSize(100, 25)
    scanBtn:SetPoint("TOPLEFT", controlFrame, "TOPLEFT", 5, -5)
    scanBtn:SetText("Scan AH")
    scanBtn:SetScript("OnClick", function()
        local MAW = _G.MalexisAuctionWatcher
        if not MAW then return end
        if MAW:IsScanning() then
            MAW:CancelScan("stopped by user")
        else
            MAW:ScanAuctionHouse()
        end
    end)
    mainFrame.scanBtn = scanBtn

    -- Reflect scan state on the button and the status label
    local function UpdateScanButton(done, total, current)
        local MAW = _G.MalexisAuctionWatcher
        if MAW and MAW:IsScanning() then
            scanBtn:SetText(string.format("Cancel (%d/%d)", done or 0, total or 0))
            if mainFrame.lastScanLabel then
                mainFrame.lastScanLabel:SetText("Scanning: " .. (current or "..."))
                mainFrame.lastScanLabel:SetTextColor(1, 0.9, 0.5)
            end
        else
            scanBtn:SetText("Scan AH")
            if mainFrame.UpdateLastScanLabel then
                mainFrame.UpdateLastScanLabel()
            end
        end
    end
    mainFrame.UpdateScanButton = UpdateScanButton

    -- Scan only the items shown on the current tab
    local scanTabBtn = CreateFrame("Button", nil, controlFrame, "UIPanelButtonTemplate")
    scanTabBtn:SetSize(120, 25)
    scanTabBtn:SetPoint("LEFT", scanBtn, "RIGHT", 5, 0)
    scanTabBtn:SetText("Scan Tab")
    scanTabBtn:SetScript("OnClick", function()
        local MAW = _G.MalexisAuctionWatcher
        if not MAW then return end
        local items = MAW:GetTabItems(currentTab)
        MAW:StartScan(items, "Scanning " .. currentTab)
    end)
    mainFrame.scanTabBtn = scanTabBtn

    -- Add item button
    local addBtn = CreateFrame("Button", nil, controlFrame, "UIPanelButtonTemplate")
    addBtn:SetSize(100, 25)
    addBtn:SetPoint("LEFT", scanTabBtn, "RIGHT", 5, 0)
    addBtn:SetText("Add Item")
    addBtn:SetScript("OnClick", function()
        local itemType = currentTab == "materials" and "material" or "product"
        if _G.MalexisAuctionWatcherDialogs then
            _G.MalexisAuctionWatcherDialogs.ShowAddItemDialog(itemType)
        end
    end)
    mainFrame.addBtn = addBtn

    -- Refresh-only button (Stores: counts, Recipes: table). No scan, just recompute.
    local refreshBtn = CreateFrame("Button", nil, controlFrame, "UIPanelButtonTemplate")
    refreshBtn:SetSize(130, 25)
    refreshBtn:SetPoint("LEFT", scanTabBtn, "RIGHT", 5, 0)
    refreshBtn:SetText("Refresh Counts")
    refreshBtn:SetScript("OnClick", function()
        MAWUI:RefreshData()
    end)
    refreshBtn:Hide()  -- Hidden by default
    mainFrame.refreshBtn = refreshBtn

    -- Character-specific mode checkbox
    local charCheckbox = CreateFrame("CheckButton", nil, controlFrame, "UICheckButtonTemplate")
    charCheckbox:SetPoint("TOPRIGHT", controlFrame, "TOPRIGHT", -5, -5)
    charCheckbox:SetSize(20, 20)

    -- Label for checkbox
    local charLabel = charCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    charLabel:SetPoint("RIGHT", charCheckbox, "LEFT", -3, 0)
    charLabel:SetText("Character-Specific Data")

    -- Set initial state
    if MalexisAuctionWatcherDB and MalexisAuctionWatcherDB.settings then
        charCheckbox:SetChecked(MalexisAuctionWatcherDB.settings.characterSpecific or false)
    end

    -- Checkbox click handler
    charCheckbox:SetScript("OnClick", function(self)
        local MAW = _G.MalexisAuctionWatcher
        if MAW then
            MAW:ToggleCharacterSpecific()
            -- Refresh the UI to show the new data
            MAWUI:RefreshData()
        end
    end)

    mainFrame.charCheckbox = charCheckbox

    -- Last scan timestamp label (below buttons, above tabs)
    local lastScanLabel = controlFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lastScanLabel:SetPoint("TOPLEFT", scanBtn, "BOTTOMLEFT", 0, -8)
    lastScanLabel:SetTextColor(0.7, 0.7, 0.7)
    lastScanLabel:SetText("Last scan: Never")
    mainFrame.lastScanLabel = lastScanLabel

    -- Update last scan label with current data
    local function UpdateLastScanLabel()
        local MAW = _G.MalexisAuctionWatcher
        if MAW then
            local db = MAW:GetActiveDB()
            if db and db.lastScanTime then
                local timeSince = time() - db.lastScanTime
                local timeText

                if timeSince < 60 then
                    timeText = "just now"
                elseif timeSince < 3600 then
                    local mins = math.floor(timeSince / 60)
                    timeText = mins .. " minute" .. (mins ~= 1 and "s" or "") .. " ago"
                elseif timeSince < 86400 then
                    local hours = math.floor(timeSince / 3600)
                    timeText = hours .. " hour" .. (hours ~= 1 and "s" or "") .. " ago"
                else
                    local days = math.floor(timeSince / 86400)
                    timeText = days .. " day" .. (days ~= 1 and "s" or "") .. " ago"
                end

                lastScanLabel:SetText("Last scan: " .. timeText)
                lastScanLabel:SetTextColor(0.5, 1.0, 0.5)  -- Green for recent scan
            else
                lastScanLabel:SetText("Last scan: Never")
                lastScanLabel:SetTextColor(0.7, 0.7, 0.7)  -- Gray for no scan
            end
        end
    end

    -- Call initially to set the label
    UpdateLastScanLabel()

    -- Store update function for later use
    mainFrame.UpdateLastScanLabel = UpdateLastScanLabel

    -- Tab buttons (positioned relative to control frame)
    mainFrame.materialTab = CreateTabButton(controlFrame, "Materials", "materials", 4)
    mainFrame.productTab = CreateTabButton(controlFrame, "Products", "products", 108)
    mainFrame.storesTab = CreateTabButton(controlFrame, "Stores", "stores", 212)
    mainFrame.historyTab = CreateTabButton(controlFrame, "History", "history", 316)
    mainFrame.recipesTab = CreateTabButton(controlFrame, "Recipes", "recipes", 420)

    -- Scroll frame (below control section and tabs)
    local scrollFrame = CreateFrame("ScrollFrame", nil, mainFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", controlFrame, "BOTTOMLEFT", 0, -TAB_HEIGHT - 5)
    scrollFrame:SetPoint("BOTTOMRIGHT", mainFrame.InsetBg or mainFrame, "BOTTOMRIGHT", -24, 4)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollFrame:SetScrollChild(scrollChild)
    scrollChild:SetSize(scrollFrame:GetWidth(), 1)

    mainFrame.scrollChild = scrollChild
    mainFrame.rows = {}

    -- Register callbacks with Core for MVC pattern
    if _G.MalexisAuctionWatcher then
        _G.MalexisAuctionWatcher:RegisterCallback("onScanComplete", function()
            MAWUI:RefreshData()
            -- Update last scan label when scan completes
            if mainFrame and mainFrame.UpdateLastScanLabel then
                mainFrame.UpdateLastScanLabel()
            end
        end)

        _G.MalexisAuctionWatcher:RegisterCallback("onItemAdded", function()
            MAWUI:RefreshData()
        end)

        _G.MalexisAuctionWatcher:RegisterCallback("onScanProgress", function(done, total, current)
            if mainFrame.UpdateScanButton then
                mainFrame.UpdateScanButton(done, total, current)
            end
        end)

        _G.MalexisAuctionWatcher:RegisterCallback("onItemRemoved", function()
            MAWUI:RefreshData()
        end)
    end

    return mainFrame
end

-- Update tab highlights
function MAWUI:UpdateTabHighlights()
    if not mainFrame then return end

    -- Reset all tabs to default
    mainFrame.materialTab.bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
    mainFrame.productTab.bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
    mainFrame.storesTab.bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
    mainFrame.historyTab.bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
    mainFrame.recipesTab.bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)

    -- Highlight active tab
    if currentTab == "materials" then
        mainFrame.materialTab.bg:SetColorTexture(0.4, 0.6, 0.4, 0.9)
    elseif currentTab == "products" then
        mainFrame.productTab.bg:SetColorTexture(0.4, 0.6, 0.4, 0.9)
    elseif currentTab == "stores" then
        mainFrame.storesTab.bg:SetColorTexture(0.4, 0.6, 0.4, 0.9)
    elseif currentTab == "history" then
        mainFrame.historyTab.bg:SetColorTexture(0.4, 0.6, 0.4, 0.9)
    elseif currentTab == "recipes" then
        mainFrame.recipesTab.bg:SetColorTexture(0.4, 0.6, 0.4, 0.9)
    end
end

-- Refresh the data display
function MAWUI:RefreshData()
    if not mainFrame then
        return
    end

    -- Update last scan label
    if mainFrame.UpdateLastScanLabel then
        mainFrame.UpdateLastScanLabel()
    end

    -- Clear existing rows
    for _, row in ipairs(mainFrame.rows) do
        row:Hide()
    end
    mainFrame.rows = {}

    local yOffset = -PADDING
    local scrollChild = mainFrame.scrollChild

    -- History panel is persistent; hide it unless we're on that tab
    if mainFrame.historyPanel and currentTab ~= "history" then
        mainFrame.historyPanel:Hide()
    end

    -- Per-tab control bar labels
    local scanLabels = {
        materials = "Scan Materials", products = "Scan Products", stores = "Scan All",
        recipes = "Scan Recipes", history = "Scan Item",
    }
    mainFrame.scanTabBtn:SetText(scanLabels[currentTab] or "Scan Tab")
    if currentTab == "stores" then
        mainFrame.refreshBtn:SetText("Refresh Counts")
        mainFrame.refreshBtn:Show()
    elseif currentTab == "recipes" then
        mainFrame.refreshBtn:SetText("Refresh Table")
        mainFrame.refreshBtn:Show()
    else
        mainFrame.refreshBtn:Hide()
    end

    -- Size the window to the tab: History needs height, Recipes needs width
    local wantHeight = (currentTab == "history") and mainFrame.historyHeight or mainFrame.defaultHeight
    local wantWidth = mainFrame.defaultWidth
    local chrome = 30 + 24 + 16  -- remove button + scrollbar + frame insets
    if currentTab == "recipes" then
        local cols = 0
        for _, c in ipairs(RecipeColumns()) do cols = cols + c.width end
        wantWidth = math.max(wantWidth, PADDING + RECIPE_CONTROLS_WIDTH + cols + chrome)
    elseif currentTab == "materials" or currentTab == "products" then
        wantWidth = math.max(wantWidth, PADDING + CONTROLS_WIDTH + ROW_NAME_WIDTH + CELL_WIDTH * 4 + TsmColumnsWidth() + chrome)
    elseif currentTab == "stores" then
        wantWidth = math.max(wantWidth, PADDING + ROW_NAME_WIDTH + 80 * 4 + 100 * 2 + TsmColumnsWidth() + chrome)
    end
    if mainFrame.docked and mainFrame.dockHost then
        -- Docked in the auction house: fill the host's height, never narrower than it
        local host = mainFrame.dockHost
        mainFrame:SetSize(math.max(wantWidth, host:GetWidth()), host:GetHeight())
    elseif mainFrame:GetHeight() ~= wantHeight or mainFrame:GetWidth() ~= wantWidth then
        -- Pin the top-left corner so the window grows down and to the right, not around its centre
        local left, top = mainFrame:GetLeft(), mainFrame:GetTop()
        mainFrame:SetSize(wantWidth, wantHeight)
        if left and top then
            local scale = mainFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
            mainFrame:ClearAllPoints()
            mainFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / scale, top / scale)
        end
    end

    -- Update Add Item button visibility (hide on Stores/History tabs)
    if currentTab == "stores" then
        mainFrame.addBtn:Hide()
        self:RenderStoresTab(scrollChild, yOffset)
        return
    elseif currentTab == "history" then
        mainFrame.addBtn:Hide()
        self:RenderHistoryTab(scrollChild, yOffset)
        return
    elseif currentTab == "recipes" then
        mainFrame.addBtn:Hide()
        self:RenderRecipesTab(scrollChild, yOffset)
        return
    else
        mainFrame.addBtn:Show()
    end

    -- Determine if we should invert colors (products = true)
    local invertColors = (currentTab == "products")

    -- Create headers (with space for control buttons on left)
    local headers = {"", "Prices", "Today", "low", "ave", "high"}
    local headerX = PADDING

    for i, headerText in ipairs(headers) do
        local width
        if i == 1 then
            width = CONTROLS_WIDTH  -- Control buttons column
        elseif i == 2 then
            width = ROW_NAME_WIDTH  -- Item name column
        else
            width = CELL_WIDTH  -- Price columns
        end

        local header = CreateCell(scrollChild, headerText, {r=0.2, g=0.2, b=0.4}, width, HEADER_HEIGHT)
        header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", headerX, yOffset)
        headerX = headerX + width
        table.insert(mainFrame.rows, header)
        if i == 2 then
            headerX = AddTsmHeaders(scrollChild, headerX, yOffset)
        end

        if i == 3 then
            header.label:SetTextColor(1, 0.8, 0.5) -- Orange for Today
        elseif i == 4 then
            header.label:SetTextColor(0.5, 1, 0.5) -- Green for low
        elseif i == 5 then
            header.label:SetTextColor(1, 1, 0.5) -- Yellow for ave
        elseif i == 6 then
            header.label:SetTextColor(1, 0.5, 0.5) -- Red for high
        else
            header.label:SetTextColor(1, 1, 1)
        end
    end

    yOffset = yOffset - HEADER_HEIGHT

    -- Add item rows (filtered by current tab)
    local MAW = _G.MalexisAuctionWatcher
    local db = MAW:GetActiveDB()
    if not db or not db.items then
        scrollChild:SetHeight(math.abs(yOffset) + PADDING)
        self:UpdateTabHighlights()
        return
    end

    local targetType = currentTab == "materials" and "material" or "product"

    -- Build sorted list of items by order
    local sortedItems = {}
    for itemName, itemData in pairs(db.items) do
        local itemType = itemData.itemType or "material"
        if itemType == targetType then
            table.insert(sortedItems, {name = itemName, data = itemData})
        end
    end

    -- Sort by order field
    table.sort(sortedItems, function(a, b)
        local orderA = a.data.order or 0
        local orderB = b.data.order or 0
        return orderA < orderB
    end)

    -- Render sorted items
    for _, item in ipairs(sortedItems) do
        local itemName = item.name
        local itemData = item.data
        local stats = CalculatePriceStats(itemName)

        if stats then
            local rowX = PADDING

            -- Control buttons area
            -- Up arrow button
            local upBtn = CreateFrame("Button", nil, scrollChild)
            upBtn:SetSize(CONTROL_BUTTON_SIZE, CONTROL_BUTTON_SIZE)
            upBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX + 2, yOffset - 1)

            local upTexture = upBtn:CreateTexture(nil, "ARTWORK")
            upTexture:SetAllPoints()
            upTexture:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
            upBtn.texture = upTexture

            upBtn:SetScript("OnEnter", function(self)
                self.texture:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Highlight")
            end)
            upBtn:SetScript("OnLeave", function(self)
                self.texture:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
            end)
            upBtn:SetScript("OnClick", function()
                if _G.MalexisAuctionWatcher then
                    _G.MalexisAuctionWatcher:MoveItemUp(itemName, targetType)
                end
            end)
            table.insert(mainFrame.rows, upBtn)

            -- Down arrow button
            local downBtn = CreateFrame("Button", nil, scrollChild)
            downBtn:SetSize(CONTROL_BUTTON_SIZE, CONTROL_BUTTON_SIZE)
            downBtn:SetPoint("LEFT", upBtn, "RIGHT", 2, 0)

            local downTexture = downBtn:CreateTexture(nil, "ARTWORK")
            downTexture:SetAllPoints()
            downTexture:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
            downBtn.texture = downTexture

            downBtn:SetScript("OnEnter", function(self)
                self.texture:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Highlight")
            end)
            downBtn:SetScript("OnLeave", function(self)
                self.texture:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
            end)
            downBtn:SetScript("OnClick", function()
                if _G.MalexisAuctionWatcher then
                    _G.MalexisAuctionWatcher:MoveItemDown(itemName, targetType)
                end
            end)
            table.insert(mainFrame.rows, downBtn)

            -- Refresh button
            local refreshBtn = CreateFrame("Button", nil, scrollChild)
            refreshBtn:SetSize(CONTROL_BUTTON_SIZE, CONTROL_BUTTON_SIZE)
            refreshBtn:SetPoint("LEFT", downBtn, "RIGHT", 2, 0)

            local refreshTexture = refreshBtn:CreateTexture(nil, "ARTWORK")
            refreshTexture:SetAllPoints()
            refreshTexture:SetTexture("Interface\\Buttons\\UI-RefreshButton")
            refreshBtn.texture = refreshTexture

            refreshBtn:SetScript("OnEnter", function(self)
                self.texture:SetVertexColor(1.0, 1.0, 0.5)  -- Highlight with yellow tint
            end)
            refreshBtn:SetScript("OnLeave", function(self)
                self.texture:SetVertexColor(1.0, 1.0, 1.0)  -- Reset to white
            end)
            refreshBtn:SetScript("OnClick", function()
                if _G.MalexisAuctionWatcher then
                    _G.MalexisAuctionWatcher:ScanSingleItem(itemName)
                end
            end)
            table.insert(mainFrame.rows, refreshBtn)

            rowX = rowX + CONTROLS_WIDTH

            -- Item name
            local nameCell = CreateCell(scrollChild, itemName, {r=0.1, g=0.1, b=0.1}, ROW_NAME_WIDTH, CELL_HEIGHT)
            nameCell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
            nameCell.label:SetJustifyH("LEFT")
            nameCell.label:SetPoint("LEFT", nameCell, "LEFT", 5, 0)
            table.insert(mainFrame.rows, nameCell)
            rowX = rowX + ROW_NAME_WIDTH

            rowX = AddTsmCells(scrollChild, rowX, yOffset, itemName, itemData, stats)

            -- Today (with color based on position). External sources get a tag and tooltip.
            local todayColor = GetPriceColor(stats.today, stats.low, stats.high, invertColors)
            local todayText = FormatMoney(stats.today) .. SourceTag(itemData)
            local todayCell = CreateCell(scrollChild, todayText, todayColor, CELL_WIDTH, CELL_HEIGHT)
            todayCell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
            AttachSourceTooltip(todayCell, itemName, itemData)
            table.insert(mainFrame.rows, todayCell)
            rowX = rowX + CELL_WIDTH

            -- Low (clickable) - red for products, green for materials
            local lowText = FormatMoney(stats.low)
            if stats.isCustomLow then
                lowText = lowText .. "*"
            end
            local lowColor = invertColors and COLOR_HIGH or COLOR_LOW
            local lowCell = CreateCell(scrollChild, lowText, lowColor, CELL_WIDTH, CELL_HEIGHT, true, function()
                if _G.MalexisAuctionWatcherDialogs then
                    _G.MalexisAuctionWatcherDialogs.ShowPriceInputDialog(itemName, "LOW")
                end
            end)
            lowCell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
            table.insert(mainFrame.rows, lowCell)
            rowX = rowX + CELL_WIDTH

            -- Average
            local aveCell = CreateCell(scrollChild, FormatMoney(stats.average), COLOR_AVE, CELL_WIDTH, CELL_HEIGHT)
            aveCell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
            table.insert(mainFrame.rows, aveCell)
            rowX = rowX + CELL_WIDTH

            -- High (clickable) - green for products, red for materials
            local highText = FormatMoney(stats.high)
            if stats.isCustomHigh then
                highText = highText .. "*"
            end
            local highColor = invertColors and COLOR_LOW or COLOR_HIGH
            local highCell = CreateCell(scrollChild, highText, highColor, CELL_WIDTH, CELL_HEIGHT, true, function()
                if _G.MalexisAuctionWatcherDialogs then
                    _G.MalexisAuctionWatcherDialogs.ShowPriceInputDialog(itemName, "HIGH")
                end
            end)
            highCell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
            table.insert(mainFrame.rows, highCell)
            rowX = rowX + CELL_WIDTH

            -- Remove button
            local removeBtn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
            removeBtn:SetSize(20, 20)
            removeBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX + 5, yOffset - 2)
            removeBtn:SetText("X")
            removeBtn:SetNormalFontObject("GameFontNormalSmall")
            removeBtn:SetScript("OnClick", function()
                if _G.MalexisAuctionWatcher then
                    _G.MalexisAuctionWatcher:RemoveItem(itemName)
                end
            end)
            table.insert(mainFrame.rows, removeBtn)

            yOffset = yOffset - CELL_HEIGHT
        end
    end

    -- Drop target for quick-adding items
    yOffset = yOffset - PADDING
    local dropWidth = CONTROLS_WIDTH + ROW_NAME_WIDTH + CELL_WIDTH * 4
    local dropSlot = CreateDropSlot(scrollChild, yOffset, targetType, dropWidth)
    table.insert(mainFrame.rows, dropSlot)
    yOffset = yOffset - (CELL_HEIGHT + 8)

    -- Source legend
    local legend = CreateFrame("Frame", nil, scrollChild)
    legend:SetSize(dropWidth, 14)
    legend:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", PADDING, yOffset - 2)
    legend.text = legend:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    legend.text:SetPoint("LEFT")
    legend.text:SetText("Today: no tag = your scan, |cffe0b060[A]|r = Auctionator, |cffe0b060[T]|r = TSM. TSM 60d/14d = TSM averages (region values when the realm has none), colored against your low/high. Hover for the full TSM picture.")
    legend.text:SetTextColor(0.6, 0.6, 0.6)
    table.insert(mainFrame.rows, legend)
    yOffset = yOffset - 16

    scrollChild:SetHeight(math.abs(yOffset) + PADDING)
    self:UpdateTabHighlights()
end

-- Render the Stores tab
function MAWUI:RenderStoresTab(scrollChild, yOffset)
    local MAW = _G.MalexisAuctionWatcher
    local db = MAW:GetActiveDB()
    if not db or not db.items then
        scrollChild:SetHeight(math.abs(yOffset) + PADDING)
        self:UpdateTabHighlights()
        return
    end

    -- Create headers for Stores tab
    local headers = {"Item", "Inventory", "Bank", "AH", "Total", "Value", "AH Net"}
    local widths = {ROW_NAME_WIDTH, 80, 80, 80, 80, 100, 100}
    local headerX = PADDING

    for i, headerText in ipairs(headers) do
        local header = CreateCell(scrollChild, headerText, {r=0.2, g=0.2, b=0.4}, widths[i], HEADER_HEIGHT)
        header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", headerX, yOffset)
        headerX = headerX + widths[i]
        table.insert(mainFrame.rows, header)
        header.label:SetTextColor(1, 1, 1)
        if i == 1 then
            headerX = AddTsmHeaders(scrollChild, headerX, yOffset)
        end
    end

    yOffset = yOffset - HEADER_HEIGHT

    -- Get inventory counts from Core
    local counts = MAW and MAW:GetAllInventoryCounts() or {}

    -- Build separate lists for products and materials
    local products = {}
    local materials = {}

    for itemName, itemData in pairs(db.items) do
        local itemType = itemData.itemType or "material"
        if itemType == "product" then
            table.insert(products, {name = itemName, data = itemData})
        else
            table.insert(materials, {name = itemName, data = itemData})
        end
    end

    -- Sort each list by order (same as Products/Materials tabs)
    table.sort(products, function(a, b)
        local orderA = a.data.order or 0
        local orderB = b.data.order or 0
        return orderA < orderB
    end)
    table.sort(materials, function(a, b)
        local orderA = a.data.order or 0
        local orderB = b.data.order or 0
        return orderA < orderB
    end)

    -- Calculate totals first
    local grandTotalInv = 0
    local grandTotalBank = 0
    local grandTotalAH = 0
    local grandTotalItems = 0
    local grandTotalValue = 0
    local grandTotalAHNet = 0

    local productTotalInv = 0
    local productTotalBank = 0
    local productTotalAH = 0
    local productTotalItems = 0
    local productTotalValue = 0
    local productTotalAHNet = 0

    local materialTotalInv = 0
    local materialTotalBank = 0
    local materialTotalAH = 0
    local materialTotalItems = 0
    local materialTotalValue = 0
    local materialTotalAHNet = 0

    -- Calculate product totals
    for _, item in ipairs(products) do
        local itemName = item.name
        local itemCounts = counts[itemName] or {inventory = 0, bank = 0, auctionHouse = 0}
        local total = itemCounts.inventory + itemCounts.bank + itemCounts.auctionHouse
        local stats = CalculatePriceStats(itemName)
        local marketValue = 0
        if stats and stats.today and stats.today > 0 then
            marketValue = stats.today * total
        elseif stats and stats.average then
            marketValue = stats.average * total
        end
        local ahNetValue = marketValue * 0.95  -- 5% AH cut

        productTotalInv = productTotalInv + itemCounts.inventory
        productTotalBank = productTotalBank + itemCounts.bank
        productTotalAH = productTotalAH + itemCounts.auctionHouse
        productTotalItems = productTotalItems + total
        productTotalValue = productTotalValue + marketValue
        productTotalAHNet = productTotalAHNet + ahNetValue
    end

    -- Calculate material totals
    for _, item in ipairs(materials) do
        local itemName = item.name
        local itemCounts = counts[itemName] or {inventory = 0, bank = 0, auctionHouse = 0}
        local total = itemCounts.inventory + itemCounts.bank + itemCounts.auctionHouse
        local stats = CalculatePriceStats(itemName)
        local marketValue = 0
        if stats and stats.today and stats.today > 0 then
            marketValue = stats.today * total
        elseif stats and stats.average then
            marketValue = stats.average * total
        end
        local ahNetValue = marketValue * 0.95  -- 5% AH cut

        materialTotalInv = materialTotalInv + itemCounts.inventory
        materialTotalBank = materialTotalBank + itemCounts.bank
        materialTotalAH = materialTotalAH + itemCounts.auctionHouse
        materialTotalItems = materialTotalItems + total
        materialTotalValue = materialTotalValue + marketValue
        materialTotalAHNet = materialTotalAHNet + ahNetValue
    end

    -- Calculate grand totals
    grandTotalInv = productTotalInv + materialTotalInv
    grandTotalBank = productTotalBank + materialTotalBank
    grandTotalAH = productTotalAH + materialTotalAH
    grandTotalItems = productTotalItems + materialTotalItems
    grandTotalValue = productTotalValue + materialTotalValue
    grandTotalAHNet = productTotalAHNet + materialTotalAHNet

    -- Render GRAND TOTAL at the top
    local rowX = PADDING
    local totalLabel = CreateCell(scrollChild, "GRAND TOTAL", {r=0.2, g=0.3, b=0.4}, widths[1], CELL_HEIGHT)
    totalLabel:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
    table.insert(mainFrame.rows, totalLabel)
    totalLabel.label:SetTextColor(1, 1, 1)
    rowX = rowX + widths[1] + TsmColumnsWidth()

    local totalInvCell = CreateCell(scrollChild, tostring(grandTotalInv), {r=0.15, g=0.2, b=0.25}, widths[2], CELL_HEIGHT)
    totalInvCell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
    table.insert(mainFrame.rows, totalInvCell)
    totalInvCell.label:SetTextColor(1, 1, 1)
    rowX = rowX + widths[2]

    local totalBankCell = CreateCell(scrollChild, tostring(grandTotalBank), {r=0.15, g=0.2, b=0.25}, widths[3], CELL_HEIGHT)
    totalBankCell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
    table.insert(mainFrame.rows, totalBankCell)
    totalBankCell.label:SetTextColor(1, 1, 1)
    rowX = rowX + widths[3]

    local totalAHCell = CreateCell(scrollChild, tostring(grandTotalAH), {r=0.15, g=0.2, b=0.25}, widths[4], CELL_HEIGHT)
    totalAHCell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
    table.insert(mainFrame.rows, totalAHCell)
    totalAHCell.label:SetTextColor(1, 1, 1)
    rowX = rowX + widths[4]

    local totalItemsCell = CreateCell(scrollChild, tostring(grandTotalItems), {r=0.2, g=0.25, b=0.3}, widths[5], CELL_HEIGHT)
    totalItemsCell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
    table.insert(mainFrame.rows, totalItemsCell)
    totalItemsCell.label:SetTextColor(1, 1, 0.5)
    rowX = rowX + widths[5]

    local totalValueText = FormatMoney(grandTotalValue)
    local totalValueCell = CreateCell(scrollChild, totalValueText, {r=0.15, g=0.25, b=0.2}, widths[6], CELL_HEIGHT)
    totalValueCell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
    table.insert(mainFrame.rows, totalValueCell)
    totalValueCell.label:SetTextColor(0.5, 1, 0.5)
    rowX = rowX + widths[6]

    local totalAHNetText = FormatMoney(grandTotalAHNet)
    local totalAHNetCell = CreateCell(scrollChild, totalAHNetText, {r=0.15, g=0.25, b=0.2}, widths[7], CELL_HEIGHT)
    totalAHNetCell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
    table.insert(mainFrame.rows, totalAHNetCell)
    totalAHNetCell.label:SetTextColor(0.5, 1, 0.5)

    yOffset = yOffset - CELL_HEIGHT - 10  -- Extra spacing after grand total

    -- Render Products section
    if #products > 0 then
        -- Products section header
        local productsHeader = CreateCell(scrollChild, "PRODUCTS", {r=0.3, g=0.4, b=0.3}, widths[1] + widths[2] + widths[3] + widths[4] + widths[5] + widths[6] + widths[7] + TsmColumnsWidth(), CELL_HEIGHT)
        productsHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", PADDING, yOffset)
        table.insert(mainFrame.rows, productsHeader)
        productsHeader.label:SetTextColor(1, 1, 0.5)
        yOffset = yOffset - CELL_HEIGHT
    end

    -- Render each product
    for _, item in ipairs(products) do
        local itemName = item.name
        local itemCounts = counts[itemName] or {inventory = 0, bank = 0, auctionHouse = 0}
        local total = itemCounts.inventory + itemCounts.bank + itemCounts.auctionHouse

        -- Calculate current market value
        local stats = CalculatePriceStats(itemName)
        local marketValue = 0
        if stats and stats.today and stats.today > 0 then
            marketValue = stats.today * total
        elseif stats and stats.average then
            marketValue = stats.average * total
        end

        local rowX = PADDING

        -- Item name cell
        local nameCell = CreateCell(scrollChild, itemName .. SourceTag(item.data), {r=0.15, g=0.15, b=0.15}, widths[1], CELL_HEIGHT)
        nameCell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
        nameCell.label:SetJustifyH("LEFT")
        nameCell.label:SetPoint("LEFT", nameCell, "LEFT", 5, 0)
        AttachSourceTooltip(nameCell, itemName, item.data)
        table.insert(mainFrame.rows, nameCell)
        rowX = rowX + widths[1]
        rowX = AddTsmCells(scrollChild, rowX, yOffset, itemName, item.data, stats)

        -- Inventory count
        local invCell = CreateCell(scrollChild, tostring(itemCounts.inventory), {r=0.1, g=0.1, b=0.1}, widths[2], CELL_HEIGHT)
        invCell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
        table.insert(mainFrame.rows, invCell)
        rowX = rowX + widths[2]

        -- Bank count
        local bankCell = CreateCell(scrollChild, tostring(itemCounts.bank), {r=0.1, g=0.1, b=0.1}, widths[3], CELL_HEIGHT)
        bankCell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
        table.insert(mainFrame.rows, bankCell)
        rowX = rowX + widths[3]

        -- Auction house count
        local ahCell = CreateCell(scrollChild, tostring(itemCounts.auctionHouse), {r=0.1, g=0.1, b=0.1}, widths[4], CELL_HEIGHT)
        ahCell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
        table.insert(mainFrame.rows, ahCell)
        rowX = rowX + widths[4]

        -- Total count
        local totalCell = CreateCell(scrollChild, tostring(total), {r=0.15, g=0.15, b=0.2}, widths[5], CELL_HEIGHT)
        totalCell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
        table.insert(mainFrame.rows, totalCell)
        totalCell.label:SetTextColor(1, 1, 0.5) -- Yellow for totals
        rowX = rowX + widths[5]

        -- Market value (with color grading for products)
        local valueText = FormatMoney(marketValue)
        local valueColor = {r=0.1, g=0.15, b=0.1}
        if stats and stats.low and stats.high then
            -- Use today's price for color grading, even if total is 0
            local pricePerItem = stats.today or stats.average or 0
            valueColor = GetPriceColor(pricePerItem, stats.low, stats.high, true) -- true = invertColors for products
        end
        local valueCell = CreateCell(scrollChild, valueText, valueColor, widths[6], CELL_HEIGHT)
        valueCell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
        table.insert(mainFrame.rows, valueCell)
        rowX = rowX + widths[6]

        -- AH Net value (95% of market value, with same color grading)
        local ahNetValue = marketValue * 0.95
        local ahNetText = FormatMoney(ahNetValue)
        local ahNetColor = {r=0.1, g=0.15, b=0.1}
        if stats and stats.low and stats.high then
            -- Use today's price * 0.95 for color grading, even if total is 0
            local pricePerItem = (stats.today or stats.average or 0) * 0.95
            ahNetColor = GetPriceColor(pricePerItem, stats.low, stats.high, true) -- true = invertColors for products
        end
        local ahNetCell = CreateCell(scrollChild, ahNetText, ahNetColor, widths[7], CELL_HEIGHT)
        ahNetCell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
        table.insert(mainFrame.rows, ahNetCell)

        yOffset = yOffset - CELL_HEIGHT
    end

    -- Add Products subtotal
    if #products > 0 then
        yOffset = yOffset - 5
        rowX = PADDING
        local productSubtotalLabel = CreateCell(scrollChild, "Products Total", {r=0.2, g=0.28, b=0.2}, widths[1], CELL_HEIGHT)
        productSubtotalLabel:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
        table.insert(mainFrame.rows, productSubtotalLabel)
        productSubtotalLabel.label:SetTextColor(0.9, 0.9, 0.9)
        rowX = rowX + widths[1] + TsmColumnsWidth()

        local pInvCell = CreateCell(scrollChild, tostring(productTotalInv), {r=0.15, g=0.18, b=0.15}, widths[2], CELL_HEIGHT)
        pInvCell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
        table.insert(mainFrame.rows, pInvCell)
        pInvCell.label:SetTextColor(0.9, 0.9, 0.9)
        rowX = rowX + widths[2]

        local pBankCell = CreateCell(scrollChild, tostring(productTotalBank), {r=0.15, g=0.18, b=0.15}, widths[3], CELL_HEIGHT)
        pBankCell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
        table.insert(mainFrame.rows, pBankCell)
        pBankCell.label:SetTextColor(0.9, 0.9, 0.9)
        rowX = rowX + widths[3]

        local pAHCell = CreateCell(scrollChild, tostring(productTotalAH), {r=0.15, g=0.18, b=0.15}, widths[4], CELL_HEIGHT)
        pAHCell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
        table.insert(mainFrame.rows, pAHCell)
        pAHCell.label:SetTextColor(0.9, 0.9, 0.9)
        rowX = rowX + widths[4]

        local pItemsCell = CreateCell(scrollChild, tostring(productTotalItems), {r=0.18, g=0.22, b=0.18}, widths[5], CELL_HEIGHT)
        pItemsCell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
        table.insert(mainFrame.rows, pItemsCell)
        pItemsCell.label:SetTextColor(1, 1, 0.5)
        rowX = rowX + widths[5]

        local pValueText = FormatMoney(productTotalValue)
        local pValueCell = CreateCell(scrollChild, pValueText, {r=0.15, g=0.22, b=0.15}, widths[6], CELL_HEIGHT)
        pValueCell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
        table.insert(mainFrame.rows, pValueCell)
        pValueCell.label:SetTextColor(0.5, 1, 0.5)
        rowX = rowX + widths[6]

        local pAHNetText = FormatMoney(productTotalAHNet)
        local pAHNetCell = CreateCell(scrollChild, pAHNetText, {r=0.15, g=0.22, b=0.15}, widths[7], CELL_HEIGHT)
        pAHNetCell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
        table.insert(mainFrame.rows, pAHNetCell)
        pAHNetCell.label:SetTextColor(0.5, 1, 0.5)

        yOffset = yOffset - CELL_HEIGHT
    end

    -- Render Materials section
    if #materials > 0 then
        -- Add spacing between sections
        yOffset = yOffset - 10

        -- Materials section header
        local materialsHeader = CreateCell(scrollChild, "MATERIALS", {r=0.3, g=0.4, b=0.3}, widths[1] + widths[2] + widths[3] + widths[4] + widths[5] + widths[6] + widths[7] + TsmColumnsWidth(), CELL_HEIGHT)
        materialsHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", PADDING, yOffset)
        table.insert(mainFrame.rows, materialsHeader)
        materialsHeader.label:SetTextColor(1, 1, 0.5)
        yOffset = yOffset - CELL_HEIGHT
    end

    -- Render each material
    for _, item in ipairs(materials) do
        local itemName = item.name
        local itemCounts = counts[itemName] or {inventory = 0, bank = 0, auctionHouse = 0}
        local total = itemCounts.inventory + itemCounts.bank + itemCounts.auctionHouse

        -- Calculate current market value
        local stats = CalculatePriceStats(itemName)
        local marketValue = 0
        if stats and stats.today and stats.today > 0 then
            marketValue = stats.today * total
        elseif stats and stats.average then
            marketValue = stats.average * total
        end

        -- Add to grand totals
        grandTotalInv = grandTotalInv + itemCounts.inventory
        grandTotalBank = grandTotalBank + itemCounts.bank
        grandTotalAH = grandTotalAH + itemCounts.auctionHouse
        grandTotalItems = grandTotalItems + total
        grandTotalValue = grandTotalValue + marketValue

        local rowX = PADDING

        -- Item name cell
        local nameCell = CreateCell(scrollChild, itemName .. SourceTag(item.data), {r=0.15, g=0.15, b=0.15}, widths[1], CELL_HEIGHT)
        nameCell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
        nameCell.label:SetJustifyH("LEFT")
        nameCell.label:SetPoint("LEFT", nameCell, "LEFT", 5, 0)
        AttachSourceTooltip(nameCell, itemName, item.data)
        table.insert(mainFrame.rows, nameCell)
        rowX = rowX + widths[1]
        rowX = AddTsmCells(scrollChild, rowX, yOffset, itemName, item.data, stats)

        -- Inventory count
        local invCell = CreateCell(scrollChild, tostring(itemCounts.inventory), {r=0.1, g=0.1, b=0.1}, widths[2], CELL_HEIGHT)
        invCell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
        table.insert(mainFrame.rows, invCell)
        rowX = rowX + widths[2]

        -- Bank count
        local bankCell = CreateCell(scrollChild, tostring(itemCounts.bank), {r=0.1, g=0.1, b=0.1}, widths[3], CELL_HEIGHT)
        bankCell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
        table.insert(mainFrame.rows, bankCell)
        rowX = rowX + widths[3]

        -- Auction house count
        local ahCell = CreateCell(scrollChild, tostring(itemCounts.auctionHouse), {r=0.1, g=0.1, b=0.1}, widths[4], CELL_HEIGHT)
        ahCell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
        table.insert(mainFrame.rows, ahCell)
        rowX = rowX + widths[4]

        -- Total count
        local totalCell = CreateCell(scrollChild, tostring(total), {r=0.15, g=0.15, b=0.2}, widths[5], CELL_HEIGHT)
        totalCell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
        table.insert(mainFrame.rows, totalCell)
        totalCell.label:SetTextColor(1, 1, 0.5) -- Yellow for totals
        rowX = rowX + widths[5]

        -- Market value (with color grading for materials)
        local valueText = FormatMoney(marketValue)
        local valueColor = {r=0.1, g=0.15, b=0.1}
        if stats and stats.low and stats.high then
            -- Use today's price for color grading, even if total is 0
            local pricePerItem = stats.today or stats.average or 0
            valueColor = GetPriceColor(pricePerItem, stats.low, stats.high, false) -- false = normal colors for materials
        end
        local valueCell = CreateCell(scrollChild, valueText, valueColor, widths[6], CELL_HEIGHT)
        valueCell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
        table.insert(mainFrame.rows, valueCell)
        rowX = rowX + widths[6]

        -- AH Net value (95% of market value, with same color grading)
        local ahNetValue = marketValue * 0.95
        local ahNetText = FormatMoney(ahNetValue)
        local ahNetColor = {r=0.1, g=0.15, b=0.1}
        if stats and stats.low and stats.high then
            -- Use today's price * 0.95 for color grading, even if total is 0
            local pricePerItem = (stats.today or stats.average or 0) * 0.95
            ahNetColor = GetPriceColor(pricePerItem, stats.low, stats.high, false) -- false = normal colors for materials
        end
        local ahNetCell = CreateCell(scrollChild, ahNetText, ahNetColor, widths[7], CELL_HEIGHT)
        ahNetCell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
        table.insert(mainFrame.rows, ahNetCell)

        yOffset = yOffset - CELL_HEIGHT
    end

    -- Add Materials subtotal
    if #materials > 0 then
        yOffset = yOffset - 5
        rowX = PADDING
        local materialSubtotalLabel = CreateCell(scrollChild, "Materials Total", {r=0.2, g=0.28, b=0.2}, widths[1], CELL_HEIGHT)
        materialSubtotalLabel:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
        table.insert(mainFrame.rows, materialSubtotalLabel)
        materialSubtotalLabel.label:SetTextColor(0.9, 0.9, 0.9)
        rowX = rowX + widths[1] + TsmColumnsWidth()

        local mInvCell = CreateCell(scrollChild, tostring(materialTotalInv), {r=0.15, g=0.18, b=0.15}, widths[2], CELL_HEIGHT)
        mInvCell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
        table.insert(mainFrame.rows, mInvCell)
        mInvCell.label:SetTextColor(0.9, 0.9, 0.9)
        rowX = rowX + widths[2]

        local mBankCell = CreateCell(scrollChild, tostring(materialTotalBank), {r=0.15, g=0.18, b=0.15}, widths[3], CELL_HEIGHT)
        mBankCell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
        table.insert(mainFrame.rows, mBankCell)
        mBankCell.label:SetTextColor(0.9, 0.9, 0.9)
        rowX = rowX + widths[3]

        local mAHCell = CreateCell(scrollChild, tostring(materialTotalAH), {r=0.15, g=0.18, b=0.15}, widths[4], CELL_HEIGHT)
        mAHCell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
        table.insert(mainFrame.rows, mAHCell)
        mAHCell.label:SetTextColor(0.9, 0.9, 0.9)
        rowX = rowX + widths[4]

        local mItemsCell = CreateCell(scrollChild, tostring(materialTotalItems), {r=0.18, g=0.22, b=0.18}, widths[5], CELL_HEIGHT)
        mItemsCell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
        table.insert(mainFrame.rows, mItemsCell)
        mItemsCell.label:SetTextColor(1, 1, 0.5)
        rowX = rowX + widths[5]

        local mValueText = FormatMoney(materialTotalValue)
        local mValueCell = CreateCell(scrollChild, mValueText, {r=0.15, g=0.22, b=0.15}, widths[6], CELL_HEIGHT)
        mValueCell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
        table.insert(mainFrame.rows, mValueCell)
        mValueCell.label:SetTextColor(0.5, 1, 0.5)
        rowX = rowX + widths[6]

        local mAHNetText = FormatMoney(materialTotalAHNet)
        local mAHNetCell = CreateCell(scrollChild, mAHNetText, {r=0.15, g=0.22, b=0.15}, widths[7], CELL_HEIGHT)
        mAHNetCell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowX, yOffset)
        table.insert(mainFrame.rows, mAHNetCell)
        mAHNetCell.label:SetTextColor(0.5, 1, 0.5)

        yOffset = yOffset - CELL_HEIGHT
    end

    -- Drop target for quick-adding items (added as materials from this tab)
    yOffset = yOffset - PADDING
    local dropWidth = 0
    for _, w in ipairs(widths) do dropWidth = dropWidth + w end
    local dropSlot = CreateDropSlot(scrollChild, yOffset, "material", dropWidth)
    table.insert(mainFrame.rows, dropSlot)
    yOffset = yOffset - (CELL_HEIGHT + 8)

    local legend = CreateFrame("Frame", nil, scrollChild)
    legend:SetSize(dropWidth, 14)
    legend:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", PADDING, yOffset - 2)
    legend.text = legend:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    legend.text:SetPoint("LEFT")
    legend.text:SetText("Value uses each item's latest price. Hover an item name for its source and time. |cffe0b060[A]|r = Auctionator, |cffe0b060[T]|r = TSM.")
    legend.text:SetTextColor(0.6, 0.6, 0.6)
    table.insert(mainFrame.rows, legend)
    yOffset = yOffset - 16

    scrollChild:SetHeight(math.abs(yOffset) + PADDING)
    self:UpdateTabHighlights()
end

-- ===================== History tab =====================

local HISTORY_MODES = {
    { key = "daily30",  label = "30 days",      mode = "daily",    span = 30, maxLabels = 10 },
    { key = "daily90",  label = "90 days",      mode = "daily",    span = 90, maxLabels = 9 },
    { key = "weekday",  label = "Weekday",      mode = "weekday",  maxLabels = 7 },
    { key = "monthday", label = "Day of month", mode = "monthday", maxLabels = 16 },
    { key = "hour",     label = "Hour",         mode = "hour",     maxLabels = 12 },
}
local CHART_HEIGHT = 340

MAWUI.historyItem = nil
MAWUI.historyMode = "daily30"
MAWUI.recipeBasis = "latest"

local function SortedTrackedItems()
    local MAW = _G.MalexisAuctionWatcher
    local db = MAW:GetActiveDB()
    local list = {}
    for itemName, itemData in pairs(db.items or {}) do
        table.insert(list, { name = itemName, data = itemData })
    end
    table.sort(list, function(a, b)
        local ta = a.data.itemType or "material"
        local tb = b.data.itemType or "material"
        if ta ~= tb then
            return ta == "material"
        end
        return (a.data.order or 0) < (b.data.order or 0)
    end)
    return list
end

local function BuildHistoryPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    panel:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)

    -- Item dropdown
    local dropdown = CreateFrame("Frame", "MalexisAuctionWatcherHistoryDropdown", panel, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", panel, "TOPLEFT", -10, -2)
    UIDropDownMenu_SetWidth(dropdown, 220)
    UIDropDownMenu_Initialize(dropdown, function(_, level)
        for _, item in ipairs(SortedTrackedItems()) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = item.name
            info.checked = (item.name == MAWUI.historyItem)
            info.func = function()
                MAWUI.historyItem = item.name
                UIDropDownMenu_SetText(dropdown, item.name)
                MAWUI:RefreshData()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    panel.dropdown = dropdown

    -- Mode buttons
    panel.modeButtons = {}
    local prev = nil
    for _, m in ipairs(HISTORY_MODES) do
        local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        btn:SetSize(m.key == "monthday" and 100 or 80, 22)
        if prev then
            btn:SetPoint("LEFT", prev, "RIGHT", 4, 0)
        else
            btn:SetPoint("TOPLEFT", panel, "TOPLEFT", PADDING, -36)
        end
        btn:SetText(m.label)
        btn.modeKey = m.key
        btn:SetScript("OnClick", function()
            MAWUI.historyMode = m.key
            MAWUI:RefreshData()
        end)
        panel.modeButtons[m.key] = btn
        prev = btn
    end

    -- Pull buttons for external sources
    local pullAtr = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    pullAtr:SetSize(130, 22)
    pullAtr:SetPoint("LEFT", prev, "RIGHT", 20, 0)
    pullAtr:SetText("Pull Auctionator")
    pullAtr:SetScript("OnClick", function()
        local MAW = _G.MalexisAuctionWatcher
        print("Malexis Auction Watcher: Pulling from Auctionator...")
        MAW:PullExternalPrices("button", "auctionator", true)
        MAWUI:RefreshData()
    end)
    panel.pullAtr = pullAtr

    local pullTsm = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    pullTsm:SetSize(90, 22)
    pullTsm:SetPoint("LEFT", pullAtr, "RIGHT", 4, 0)
    pullTsm:SetText("Pull TSM")
    pullTsm:SetScript("OnClick", function()
        local MAW = _G.MalexisAuctionWatcher
        print("Malexis Auction Watcher: Pulling from TSM...")
        MAW:PullExternalPrices("button", "tsm", true)
        MAWUI:RefreshData()
    end)
    panel.pullTsm = pullTsm

    -- Chart
    local parentWidth = parent:GetWidth()
    if not parentWidth or parentWidth < 100 then
        parentWidth = 740
    end
    local chartWidth = math.max(300, parentWidth - PADDING * 2)
    panel.chart = _G.MalexisAuctionWatcherChart.Create(panel, chartWidth, CHART_HEIGHT)
    panel.chart:SetPoint("TOPLEFT", panel, "TOPLEFT", PADDING, -66)

    -- Chart legend
    panel.legend = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.legend:SetPoint("TOPLEFT", panel.chart, "BOTTOMLEFT", 0, -4)
    panel.legend:SetJustifyH("LEFT")
    panel.legend:SetWidth(chartWidth)
    panel.legend:SetText("Bars: |cff8ca6d9blue|r = your scans, |cffccb366amber|r = Auctionator/TSM, |cff59e659green|r = cheapest, |cfff25959red|r = priciest. White tick = average. |cffffd94dYellow line|r = today; buckets to its right are from the previous cycle.")
    panel.legend:SetTextColor(0.6, 0.6, 0.6)

    -- Summary lines
    panel.summary = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.summary:SetPoint("TOPLEFT", panel.legend, "BOTTOMLEFT", 0, -6)
    panel.summary:SetJustifyH("LEFT")
    panel.summary:SetWidth(chartWidth)

    panel.note = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.note:SetPoint("TOPLEFT", panel.summary, "BOTTOMLEFT", 0, -4)
    panel.note:SetJustifyH("LEFT")
    panel.note:SetWidth(chartWidth)
    panel.note:SetTextColor(0.7, 0.7, 0.7)

    panel.sources = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.sources:SetPoint("TOPLEFT", panel.note, "BOTTOMLEFT", 0, -6)
    panel.sources:SetJustifyH("LEFT")
    panel.sources:SetWidth(chartWidth)
    panel.sources:SetTextColor(0.6, 0.7, 0.8)
    panel.sources:SetSpacing(2)

    panel:SetHeight(66 + CHART_HEIGHT + 110)
    return panel
end

function MAWUI:RenderHistoryTab(scrollChild, yOffset)
    local MAW = _G.MalexisAuctionWatcher
    if not mainFrame.historyPanel then
        mainFrame.historyPanel = BuildHistoryPanel(scrollChild)
    end
    local panel = mainFrame.historyPanel
    panel:Show()

    -- Pick a default item if none selected or the selection went away
    local db = MAW:GetActiveDB()
    if not self.historyItem or not (db.items and db.items[self.historyItem]) then
        local list = SortedTrackedItems()
        self.historyItem = list[1] and list[1].name or nil
    end
    UIDropDownMenu_SetText(panel.dropdown, self.historyItem or "No items tracked")

    -- Pull buttons only when the source is loaded
    if MAW.DetectSources then
        MAW:DetectSources()
        panel.pullAtr:SetEnabled(MAW.sources.auctionator.available)
        panel.pullTsm:SetEnabled(MAW.sources.tsm.available)
    end

    -- Mode button state
    for key, btn in pairs(panel.modeButtons) do
        if key == self.historyMode then
            btn:Disable()
        else
            btn:Enable()
        end
    end

    local modeDef = HISTORY_MODES[1]
    for _, m in ipairs(HISTORY_MODES) do
        if m.key == self.historyMode then modeDef = m end
    end

    if self.historyItem then
        local analysis = MAW:AnalyzePeriodicity(self.historyItem, modeDef.mode, modeDef.span)
        local highlight = {}
        if analysis.best and analysis.worst and analysis.best.index ~= analysis.worst.index then
            highlight.best = analysis.best.index
            highlight.worst = analysis.worst.index
        end
        -- TSM reference averages (snapshot values, not a time series)
        local refLines = {}
        local tsmRef = db.items[self.historyItem].tsmRef
        if tsmRef and MAW.sources.tsm.available and MAW:IsSourceEnabled("tsm") then
            if tsmRef.market then
                table.insert(refLines, { value = tsmRef.market, label = "TSM market 14d", color = { 0.95, 0.65, 0.95 } })
            end
            if tsmRef.historical then
                table.insert(refLines, { value = tsmRef.historical, label = "TSM historical 60d", color = { 0.7, 0.55, 0.95 } })
            end
        end

        -- Where "now" falls in cyclic views, so the wrap from last period to this one is visible
        local nowT = date("*t")
        local markerIndex, markerLabel
        if modeDef.mode == "monthday" then
            markerIndex, markerLabel = nowT.day, "Today (" .. nowT.day .. ")"
        elseif modeDef.mode == "weekday" then
            markerIndex, markerLabel = nowT.wday, "Today"
        elseif modeDef.mode == "hour" then
            markerIndex, markerLabel = nowT.hour + 1, "Now"
        end

        panel.chart:SetData(analysis.points, {
            highlight = highlight,
            refLines = refLines,
            markerIndex = markerIndex,
            markerLabel = markerLabel,
            maxLabels = modeDef.maxLabels,
            tooltipTitle = function(p)
                if modeDef.mode == "hour" then
                    return p.label .. ":00"
                elseif modeDef.mode == "monthday" then
                    return "Day " .. p.label
                end
                return p.label
            end,
        })

        if analysis.best and analysis.worst then
            local unit = ({ daily = "", weekday = "", monthday = "day ", hour = "hour " })[modeDef.mode] or ""
            panel.summary:SetText(string.format(
                "|cff80ff80Cheapest:|r %s%s (avg %s, %d samples)   |cffff8080Priciest:|r %s%s (avg %s, %d samples)   Spread %.0f%%",
                unit, analysis.best.label, FormatMoney(analysis.best.avg), analysis.best.n,
                unit, analysis.worst.label, FormatMoney(analysis.worst.avg), analysis.worst.n,
                analysis.spreadPct))
            if analysis.confident then
                panel.note:SetText("Pattern is based on at least 3 samples in both buckets.")
            else
                panel.note:SetText("Not enough data yet for a reliable pattern (need 3+ samples in the cheapest and priciest buckets).")
            end
        else
            panel.summary:SetText("No price history for " .. self.historyItem .. " yet. Scan the auction house or enable an external source.")
            panel.note:SetText("")
        end
    else
        panel.chart:SetData({}, {})
        panel.summary:SetText("Track an item first, then come back here.")
        panel.note:SetText("")
    end

    panel.sources:SetText("Sources: " .. (MAW.DescribeSources and MAW:DescribeSources() or "scan")
        .. "   |   Retention: " .. MAW:GetHistoryDays() .. " days"
        .. "\nBars come from your scans and Auctionator's daily history (up to 21 days back). "
        .. "TSM has no daily history: Pull TSM records today's snapshot and shows its 14d/60d averages as lines.")

    scrollChild:SetHeight(panel:GetHeight() + PADDING)
    self:UpdateTabHighlights()
end

-- Open the window on the History tab, optionally for a specific item
function MAWUI:ShowHistory(itemName)
    if itemName and itemName ~= "" then
        local MAW = _G.MalexisAuctionWatcher
        local db = MAW:GetActiveDB()
        if db.items and db.items[itemName] then
            self.historyItem = itemName
        else
            print("Malexis Auction Watcher: Not tracking " .. itemName)
        end
    end
    currentTab = "history"
    self:Show()
end

-- ===================== Recipes tab =====================


-- Small refresh icon that scans a list of items
local function CreateRowRefreshButton(parent, x, y, tooltipText, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(CONTROL_BUTTON_SIZE, CONTROL_BUTTON_SIZE)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    btn.texture = btn:CreateTexture(nil, "ARTWORK")
    btn.texture:SetAllPoints()
    btn.texture:SetTexture("Interface\\Buttons\\UI-RefreshButton")
    btn:SetScript("OnEnter", function(self)
        self.texture:SetVertexColor(1.0, 1.0, 0.5)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(tooltipText, 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        self.texture:SetVertexColor(1.0, 1.0, 1.0)
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", onClick)
    return btn
end

local function ProfitColor(profit)
    if not profit then
        return { r = 0.25, g = 0.25, b = 0.25 }
    elseif profit > 0 then
        return { r = 0.2, g = 0.5, b = 0.2 }
    elseif profit < 0 then
        return { r = 0.55, g = 0.2, b = 0.2 }
    end
    return { r = 0.35, g = 0.35, b = 0.2 }
end

local function AttachRecipeTooltip(cell, calc)
    local MAW = _G.MalexisAuctionWatcher
    cell:EnableMouse(true)
    cell:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(calc.recipe.name)
        if calc.recipe.skill then
            GameTooltip:AddLine((calc.recipe.profession or "Jewelcrafting") .. " " .. calc.recipe.skill .. (calc.recipe.color and (" - " .. calc.recipe.color) or ""), 0.7, 0.7, 0.9)
        end
        if calc.recipe.note then
            GameTooltip:AddLine(calc.recipe.note, 0.9, 0.8, 0.5)
        end
        GameTooltip:AddLine("Materials per batch:", 0.8, 0.8, 0.8)
        for _, m in ipairs(calc.materials) do
            local right = m.unit and (m.count .. " x " .. FormatMoney(m.unit) .. " = " .. FormatMoney(m.cost)) or "no price"
            local src = m.vendor and " (vendor)" or (m.source and (" (" .. (MAW.SourceLabel and MAW:SourceLabel(m.source) or m.source) .. (m.when and (", " .. m.when) or "") .. ")") or "")
            GameTooltip:AddDoubleLine("  " .. m.item .. src, right, 1, 1, 1, 1, 0.8, 0.5)
        end
        GameTooltip:AddLine(" ")
        local pright = calc.productUnit and (FormatMoney(calc.productUnit) .. " each") or "no price"
        local psrc = calc.productSource and (" (" .. (MAW.SourceLabel and MAW:SourceLabel(calc.productSource) or calc.productSource) .. (calc.productWhen and (", " .. calc.productWhen) or "") .. ")") or ""
        GameTooltip:AddDoubleLine("Product: " .. calc.recipe.product .. " x" .. (calc.recipe.productCount or 1) .. psrc, pright, 1, 1, 1, 1, 0.8, 0.5)
        if calc.complete then
            GameTooltip:AddDoubleLine("AH net (after 5% cut)", FormatMoney(calc.ahNet), 1, 1, 1, 0.8, 0.8, 0.8)
            GameTooltip:AddDoubleLine("Profit per batch", FormatMoney(calc.profit), 1, 1, 1,
                calc.profit >= 0 and 0.5 or 1, calc.profit >= 0 and 1 or 0.5, 0.5)
        else
            GameTooltip:AddLine("Missing prices: " .. table.concat(calc.missing, ", "), 1, 0.5, 0.5)
        end
        if calc.canMake then
            GameTooltip:AddDoubleLine("Batches you can make now", tostring(calc.canMake), 1, 1, 1, 1, 1, 0.5)
        end
        if TsmColumnsShown() then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Profit by price basis (table uses " .. MAW:PriceBasisDef(calc.basis).label .. "):", 0.8, 0.8, 0.8)
            for _, row in ipairs(MAW:CompareRecipeBases(calc.recipe)) do
                local text = row.profit and (FormatMoney(row.profit) .. (row.margin and string.format(" (%.0f%%)", row.margin) or "")) or "n/a"
                local g = (row.profit or 0) >= 0
                GameTooltip:AddDoubleLine("  " .. row.basis.label, text, 1, 1, 1, g and 0.5 or 1, g and 1 or 0.5, 0.5)
            end
        end
        GameTooltip:Show()
    end)
    cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function MAWUI:RenderRecipesTab(scrollChild, yOffset)
    local MAW = _G.MalexisAuctionWatcher

    -- Toolbar row inside the list: presets menu + add
    if not mainFrame.presetMenu then
        mainFrame.presetMenu = CreateFrame("Frame", "MalexisAuctionWatcherPresetMenu", UIParent, "UIDropDownMenuTemplate")
    end
    local presetBtn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
    presetBtn:SetSize(120, 22)
    presetBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", PADDING, yOffset)
    presetBtn:SetText("Presets...")
    presetBtn:SetScript("OnClick", function(self)
        local dlg = _G.MalexisAuctionWatcherRecipeDialog
        local function after() MAWUI:RefreshData() end
        local menu = {
            { text = "Add recipes", isTitle = true, notCheckable = true },
            { text = "Motes -> Primals (7)", notCheckable = true, func = function() MAW:AddMotePresets(); after() end },
            { text = "Transmute: Primal Might", notCheckable = true, func = function() MAW:AddPrimalMightPreset(); after() end },
            { text = "Alchemy consumables (7)", notCheckable = true, func = function() MAW:AddAlchemyPresets(); after() end },
            { text = "Gem cuts...", notCheckable = true, func = function() if dlg then dlg.ShowGemPicker() end end },
            { text = "Import from open profession window...", notCheckable = true, func = function() if dlg then dlg.ShowProfessionImport() end end },
            { text = "Track items only", isTitle = true, notCheckable = true },
            { text = "Flipping guide watchlist (herbs, primals, gems, shards)", notCheckable = true, func = function() MAW:AddGuideWatchlist(); after() end },
        }
        EasyMenu(menu, mainFrame.presetMenu, self, 0, 0, "MENU")
    end)
    table.insert(mainFrame.rows, presetBtn)

    local addRecipeBtn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
    addRecipeBtn:SetSize(110, 22)
    addRecipeBtn:SetPoint("LEFT", presetBtn, "RIGHT", 6, 0)
    addRecipeBtn:SetText("Add Recipe")
    addRecipeBtn:SetScript("OnClick", function()
        if _G.MalexisAuctionWatcherRecipeDialog then
            _G.MalexisAuctionWatcherRecipeDialog.Show()
        end
    end)
    table.insert(mainFrame.rows, addRecipeBtn)

    -- Price basis: cycles Latest -> TSM 14d -> TSM 60d
    local basisDef = MAW:PriceBasisDef(MAWUI.recipeBasis)
    local basisBtn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
    basisBtn:SetSize(130, 22)
    basisBtn:SetPoint("LEFT", addRecipeBtn, "RIGHT", 6, 0)
    basisBtn:SetText("Prices: " .. basisDef.label)
    basisBtn:SetScript("OnClick", function()
        local bases = MAW.PRICE_BASES
        for i, b in ipairs(bases) do
            if b.key == MAWUI.recipeBasis then
                MAWUI.recipeBasis = bases[(i % #bases) + 1].key
                break
            end
        end
        MAWUI:RefreshData()
    end)
    basisBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Price basis for the table")
        GameTooltip:AddLine("Latest: each item's most recent price from any source.", 1, 1, 1)
        GameTooltip:AddLine("TSM 14d / 60d: TSM market or historical average; items without TSM data use Latest.", 1, 1, 1)
        GameTooltip:AddLine("Hover a recipe to see profit under all three.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    basisBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if not TsmColumnsShown() then
        basisBtn:Disable()
        basisBtn:SetText("Prices: Latest")
        MAWUI.recipeBasis = "latest"
    end
    table.insert(mainFrame.rows, basisBtn)

    yOffset = yOffset - 30

    -- Headers (first a narrow controls column for the per-row refresh icon)
    local columns = RecipeColumns()
    local totalWidth = RECIPE_CONTROLS_WIDTH
    local x = PADDING
    local ctlHeader = CreateCell(scrollChild, "", { r = 0.2, g = 0.2, b = 0.4 }, RECIPE_CONTROLS_WIDTH, HEADER_HEIGHT)
    ctlHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", x, yOffset)
    table.insert(mainFrame.rows, ctlHeader)
    x = x + RECIPE_CONTROLS_WIDTH
    for _, col in ipairs(columns) do
        local header = CreateCell(scrollChild, col.header, col.basis and { r = 0.3, g = 0.2, b = 0.4 } or { r = 0.2, g = 0.2, b = 0.4 }, col.width, HEADER_HEIGHT)
        header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", x, yOffset)
        header.label:SetTextColor(col.basis and 0.9 or 1, col.basis and 0.7 or 1, 1)
        table.insert(mainFrame.rows, header)
        x = x + col.width
        totalWidth = totalWidth + col.width
    end
    yOffset = yOffset - HEADER_HEIGHT

    local recipes = MAW:GetRecipes()
    local rows = {}
    for _, recipe in ipairs(recipes) do
        table.insert(rows, MAW:ComputeRecipeProfit(recipe, MAWUI.recipeBasis))
    end
    -- Most profitable first; recipes without prices go to the bottom
    table.sort(rows, function(a, b)
        local pa = a.profit or -math.huge
        local pb = b.profit or -math.huge
        if pa ~= pb then return pa > pb end
        return a.recipe.name < b.recipe.name
    end)

    if #rows == 0 then
        local empty = CreateCell(scrollChild, "No recipes yet. Use the buttons above.", { r = 0.1, g = 0.1, b = 0.1 }, 700, CELL_HEIGHT)
        empty:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", PADDING + RECIPE_CONTROLS_WIDTH, yOffset)
        table.insert(mainFrame.rows, empty)
        yOffset = yOffset - CELL_HEIGHT
    end

    local totalProfit, totalMakeable = 0, 0
    for _, calc in ipairs(rows) do
        x = PADDING
        local color = ProfitColor(calc.profit)

        -- Per-row refresh: scan just this recipe's product and materials
        local recipe = calc.recipe
        local rowRefresh = CreateRowRefreshButton(scrollChild, x + 4, yOffset - 1,
            "Scan this recipe's items", function()
                MAW:StartScan(MAW:GetRecipeItems(recipe), "Scanning " .. recipe.name)
            end)
        table.insert(mainFrame.rows, rowRefresh)
        x = x + RECIPE_CONTROLS_WIDTH

        -- Profit under the TSM bases, for the optional columns
        local byBasis = {}
        if columns[5] and columns[5].basis then
            for _, row in ipairs(MAW:CompareRecipeBases(calc.recipe)) do
                byBasis[row.basis.key] = row
            end
        end

        for _, col in ipairs(columns) do
            local text, cellColor = "?", { r = 0.1, g = 0.1, b = 0.1 }
            local textColor = nil
            if col.key == "name" then
                text = calc.recipe.name
                cellColor = { r = 0.15, g = 0.15, b = 0.15 }
            elseif col.key == "matCost" then
                text = (calc.complete or #calc.missing == 0) and FormatMoney(calc.matCost) or "?"
            elseif col.key == "productValue" then
                text = calc.productValue and FormatMoney(calc.productValue) or "?"
            elseif col.key == "ahNet" then
                text = calc.ahNet and FormatMoney(calc.ahNet) or "?"
            elseif col.basis then
                local row = byBasis[col.basis]
                if row and row.profit then
                    text = FormatMoney(row.profit)
                    cellColor = ProfitColor(row.profit)
                    textColor = row.profit >= 0 and { 0.6, 1, 0.6 } or { 1, 0.6, 0.6 }
                else
                    text = "-"
                    cellColor = { r = 0.15, g = 0.12, b = 0.18 }
                end
            elseif col.key == "profit" then
                text = calc.profit and FormatMoney(calc.profit) or "?"
                cellColor = color
                if calc.profit then
                    textColor = calc.profit >= 0 and { 0.6, 1, 0.6 } or { 1, 0.6, 0.6 }
                end
            elseif col.key == "margin" then
                text = calc.margin and string.format("%.0f%%", calc.margin) or "?"
                cellColor = color
            elseif col.key == "canMake" then
                text = calc.canMake and tostring(calc.canMake) or "-"
            end

            local cell = CreateCell(scrollChild, text, cellColor, col.width, CELL_HEIGHT)
            cell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", x, yOffset)
            if textColor then
                cell.label:SetTextColor(textColor[1], textColor[2], textColor[3])
            end
            if col.key == "name" then
                cell.label:SetJustifyH("LEFT")
                cell.label:SetPoint("LEFT", cell, "LEFT", 5, 0)
                AttachRecipeTooltip(cell, calc)
            elseif col.basis then
                cell:EnableMouse(true)
                cell:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(calc.recipe.name)
                    GameTooltip:AddLine("Profit if every item were priced at its " .. col.header:gsub("Profit ", "TSM ") .. " average", 0.9, 0.7, 1)
                    GameTooltip:AddLine("Items TSM has no data for use their latest price.", 0.7, 0.7, 0.7)
                    GameTooltip:Show()
                end)
                cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end
            table.insert(mainFrame.rows, cell)
            x = x + col.width
        end

        local removeBtn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
        removeBtn:SetSize(20, 20)
        removeBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", x + 5, yOffset - 2)
        removeBtn:SetText("X")
        removeBtn:SetNormalFontObject("GameFontNormalSmall")
        removeBtn:SetScript("OnClick", function()
            MAW:RemoveRecipe(calc.recipe.name)
        end)
        table.insert(mainFrame.rows, removeBtn)

        if calc.profit and calc.canMake then
            totalProfit = totalProfit + calc.profit * calc.canMake
            totalMakeable = totalMakeable + calc.canMake
        end
        yOffset = yOffset - CELL_HEIGHT
    end

    if #rows > 0 then
        yOffset = yOffset - 6
        local sumText = string.format("If you converted everything you own now: %d batches, %s profit",
            totalMakeable, FormatMoney(totalProfit))
        local sumCell = CreateCell(scrollChild, sumText, { r = 0.2, g = 0.3, b = 0.4 }, totalWidth - RECIPE_CONTROLS_WIDTH, CELL_HEIGHT)
        sumCell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", PADDING + RECIPE_CONTROLS_WIDTH, yOffset)
        sumCell.label:SetTextColor(1, 1, 0.6)
        table.insert(mainFrame.rows, sumCell)
        yOffset = yOffset - CELL_HEIGHT
    end

    scrollChild:SetHeight(math.abs(yOffset) + PADDING)
    self:UpdateTabHighlights()
end

-- Dock the window over the auction house frame (selected via the Watcher AH tab)
function MAWUI:Dock(host)
    if not mainFrame then
        self:CreateUI()
    end
    if not mainFrame.docked then
        -- Remember where the floating window was
        mainFrame.floatLeft, mainFrame.floatTop = mainFrame:GetLeft(), mainFrame:GetTop()
    end
    mainFrame.docked = true
    mainFrame.dockHost = host
    mainFrame:SetParent(host)
    mainFrame:ClearAllPoints()
    mainFrame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    mainFrame:SetFrameStrata("HIGH")
    mainFrame:SetFrameLevel(host:GetFrameLevel() + 20)
    self:RefreshData()
    mainFrame:Show()
end

-- Return the window to a floating frame and hide it
function MAWUI:Undock()
    if not mainFrame or not mainFrame.docked then
        return
    end
    mainFrame.docked = false
    mainFrame.dockHost = nil
    mainFrame:Hide()
    mainFrame:SetParent(UIParent)
    mainFrame:ClearAllPoints()
    if mainFrame.floatLeft and mainFrame.floatTop then
        local scale = mainFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
        mainFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", mainFrame.floatLeft / scale, mainFrame.floatTop / scale)
    else
        mainFrame:SetPoint("CENTER")
    end
    mainFrame:SetSize(mainFrame.defaultWidth, mainFrame.defaultHeight)
end

function MAWUI:IsDocked()
    return mainFrame ~= nil and mainFrame.docked == true
end

-- Open the window on a given tab
function MAWUI:ShowTab(tabName)
    currentTab = tabName
    self:Show()
end

-- Show the UI
function MAWUI:Show()
    if not mainFrame then
        self:CreateUI()
    end
    -- At the auction house, open as the Watcher tab instead of a floating window
    if not mainFrame.docked and _G.MalexisAuctionWatcherAHTab and _G.MalexisAuctionWatcherAHTab.Select() then
        return
    end
    self:RefreshData()
    if mainFrame.UpdateScanButton then
        local s = _G.MalexisAuctionWatcher.scan
        mainFrame.UpdateScanButton(s and s.done, s and s.total, s and s.current)
    end
    mainFrame:Show()
end

-- Hide the UI
function MAWUI:Hide()
    if mainFrame then
        mainFrame:Hide()
    end
end

-- Toggle the UI
function MAWUI:Toggle()
    if mainFrame and mainFrame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

-- Export to global namespace
_G.MalexisAuctionWatcherUI = MAWUI
