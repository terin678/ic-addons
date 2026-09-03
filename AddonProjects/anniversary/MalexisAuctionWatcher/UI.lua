-- MalexisAuctionWatcher UI Module
--
-- The window, its tabs and every list come from LibICUI-1.0 (ICLibs), so the addon wears
-- the guild palette and follows the "Window layout" rules in CODING_STANDARDS.md: column
-- headers sit outside the scroll child, rows are a fixed height and never wrap, and the
-- controls that act on a list live above it. Rows are pooled by the library, so a refresh
-- reuses frames instead of building new ones.
local addonName = "MalexisAuctionWatcher"
local MAWUI = {}

local ICUI = LibStub("LibICUI-1.0")

-- Price colours. These are drawn as text on the brand navy, not as a background
-- swatch, so the two ends are lightened well past where they started: saturated
-- blue and magenta on #152333 were the pair nobody could read. Green through amber
-- to red carries the position in range; cyan and pink mean "off the scale".
--
-- Two rules hold this set together, so measure before changing any of it. Every
-- colour clears 5.5:1 against a banded row (the navy under STYLE.altBg), including
-- the whole LOW -> AVE -> HIGH ramp. And the pairs that mean opposite things differ
-- in lightness, not only hue: BELOW and ABOVE swap meaning between Materials and
-- Products, so someone who cannot tell red from green has L* left to read them by.
-- COLOR_AVE is not ICUI.Brand.gold, and folding the two together would break both
-- rules: gold is this window's heading colour (section rows, totals), and a price
-- wearing it would read as a label rather than a value.
local COLOR_LOW = {r = 0.55, g = 0.95, b = 0.55}    -- at the cheap end of your range
local COLOR_AVE = {r = 0.99, g = 0.67, b = 0.13}    -- mid-range, well under COLOR_LOW in lightness so the middle never shouts
local COLOR_HIGH = {r = 0.98, g = 0.56, b = 0.52}   -- at the dear end
local COLOR_BELOW = {r = 0.45, g = 0.85, b = 0.98}  -- under your low bound: a bargain
local COLOR_ABOVE = {r = 1, g = 0.45, b = 0.98}     -- over your high bound: a spike, darker than BELOW

-- Text colours with one meaning each, as in "User-facing text"
local BONE = ICUI.Brand.bone
local GOLD = ICUI.Brand.gold
local DIM = { r = 0.68, g = 0.70, b = 0.74 }        -- missing or not graded
local WHITE = { r = 0.93, g = 0.94, b = 0.96 }      -- plain counts
local TSM_TINT = { r = 0.86, g = 0.74, b = 1 }      -- TSM, which is purple everywhere

-- UI configuration
local WINDOW_WIDTH = 1024   -- fits Recipes with both TSM profit columns, E/X buttons, scrollbar
local WINDOW_HEIGHT = 700   -- fits the History panel
local PAGE_INSET = 8
local PAGE_TOP = -68        -- under the tab strip and the control bar
local ROW_H = 20
local TAB_H = 24
local CHART_HEIGHT = 340
local CONTROL_BUTTON_SIZE = 18
local RECIPE_CONTROLS_WIDTH = 26
local ITEM_CONTROLS_WIDTH = 64

local STYLE = ICUI:Style("MalexisAuctionWatcher", {
    rowHeight = ROW_H,
    headerHeight = 22,
    font = "GameFontHighlightSmall",
    headerFont = "GameFontNormalSmall",
    pageWidth = WINDOW_WIDTH - PAGE_INSET * 2,
    -- 3% banding disappears on the navy ground; this is still quiet but visible.
    altBg = { r = 1, g = 1, b = 1, a = 0.055 },
})

local function Button(parent, text, w, h, opts)
    opts = opts or {}
    opts.style = STYLE
    return ICUI:Button(parent, text, w, h, opts)
end

local function Toolbar(parent, opts)
    opts = opts or {}
    opts.style = STYLE
    return ICUI:Toolbar(parent, opts)
end

local function Table(parent, opts)
    opts = opts or {}
    opts.style = STYLE
    return ICUI:Table(parent, opts)
end

-- builder(widget) adds the lines; nil takes the tooltip off a pooled cell again.
local function Tooltip(widget, builder)
    return ICUI:Tooltip(widget, builder)
end

-- Settings arrive with ADDON_LOADED. A refresh can run before that, so read through here.
local function Setting(key, default)
    local st = MalexisAuctionWatcherDB and MalexisAuctionWatcherDB.settings
    local v = st and st[key]
    if v == nil then return default end
    return v
end

local function SortMode()
    return Setting("sortMode") == "manual" and "manual" or "movers"
end

local function Note(parent, text, width)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetJustifyH("LEFT")
    fs:SetSpacing(2)
    if width then fs:SetWidth(width) end
    fs:SetTextColor(DIM.r, DIM.g, DIM.b)
    fs:SetText(text or "")
    return fs
end

-- Recipes tab columns. The two TSM profit columns appear only when the TSM feed is on.
local function RecipeColumns()
    local MAW = _G.MalexisAuctionWatcher
    local cols = {
        { header = "Recipe",   width = "flex", key = "name" },
        { header = "Mat cost", width = 90,  key = "matCost" },
        { header = "Product",  width = 90,  key = "productValue" },
        { header = string.format("AH net -%d%%", math.floor(MAW:GetAHCut() * 100 + 0.5)), width = 90, key = "ahNet" },
    }
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

local TSM_COLUMNS = {
    { key = "historical", header = "TSM 60d", label = "TSM historical (60 day)" },
    { key = "market",     header = "TSM 14d", label = "TSM market value (14 day)" },
}
local TSM_CELL_WIDTH = 80

-- Main frame and tabs
local mainFrame = nil
local windowTitle = "Malexis Auction Watcher"
local currentTab = "materials"

local TABS = {
    { key = "materials", label = "Materials" },
    { key = "products",  label = "Products" },
    { key = "stores",    label = "Stores" },
    { key = "history",   label = "History" },
    { key = "recipes",   label = "Recipes" },
    { key = "movers",    label = "Movers" },
}

--------------------------------------------------------------------------------
-- Money, price statistics and colours (pure)
--------------------------------------------------------------------------------

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

    -- If no prices yet, still show the row with whatever bounds exist (custom, TSM, or none)
    if #prices == 0 then
        local low, high, lowSrc, highSrc = MAW:GetPriceBounds(itemName)
        low, high = low or 0, high or 0
        return {
            low = low,
            average = (low + high) / 2,
            high = high,
            today = 0,
            todayBuyout = 0,
            todayBid = 0,
            isCustomLow = lowSrc == "custom",
            isCustomHigh = highSrc == "custom",
            isTsmLow = lowSrc == "tsm",
            isTsmHigh = highSrc == "tsm",
            itemType = itemData.itemType or "material",
            noPriceData = true
        }
    end

    -- Get most recent price (today)
    local today = prices[1]

    -- Bounds: custom -> TSM averages -> scan min/max (one shared function for every tab)
    local low, high, lowSrc, highSrc = MAW:GetPriceBounds(itemName)

    local buyouts = {}
    for _, entry in ipairs(prices) do
        if entry.buyout and entry.buyout > 0 then
            table.insert(buyouts, entry.buyoutPerUnit)
        end
    end

    if not low or not high then
        return nil
    end

    -- Average: midpoint when either bound is custom or TSM-derived; else the scan average
    local average
    if lowSrc ~= "scan" or highSrc ~= "scan" or #buyouts == 0 then
        average = (low + high) / 2
    else
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
        isCustomLow = lowSrc == "custom",
        isCustomHigh = highSrc == "custom",
        isTsmLow = lowSrc == "tsm",
        isTsmHigh = highSrc == "tsm",
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

--------------------------------------------------------------------------------
-- Tooltips (attached to a row's hover cells, which the pool reuses)
--------------------------------------------------------------------------------

-- Hover tooltip citing the latest price, its source and when it was recorded
local function SourceTooltip(hit, itemName, itemData)
    local MAW = _G.MalexisAuctionWatcher
    local latest = itemData and itemData.prices and itemData.prices[1]
    if not latest then
        return Tooltip(hit, nil)
    end
    Tooltip(hit, function()
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
    end)
end

-- Hover tooltip for one of the TSM average columns
local function TsmTooltip(hit, col, itemName, itemData, stats)
    local MAW = _G.MalexisAuctionWatcher
    local ref = itemData and itemData.tsmRef
    local value = ref and ref[col.key]
    Tooltip(hit, function()
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
    end)
end

local function RecipeTooltip(hit, calc)
    local MAW = _G.MalexisAuctionWatcher
    Tooltip(hit, function()
        GameTooltip:AddLine(calc.recipe.name)
        if calc.recipe.skill or calc.recipe.profession or calc.recipe.color then
            local line = (calc.recipe.profession or "Jewelcrafting")
            if calc.recipe.skill then line = line .. " " .. calc.recipe.skill end
            if calc.recipe.color then line = line .. " - " .. calc.recipe.color end
            GameTooltip:AddLine(line, 0.7, 0.7, 0.9)
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
            GameTooltip:AddDoubleLine(string.format("AH net (after %d%% cut)", math.floor(MAW:GetAHCut() * 100 + 0.5)), FormatMoney(calc.ahNet), 1, 1, 1, 0.8, 0.8, 0.8)
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
    end)
end

--------------------------------------------------------------------------------
-- Small shared pieces
--------------------------------------------------------------------------------

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

-- A drop target that registers whatever item is dropped on it, with defaults.
local function CreateDropSlot(parent, itemType, width)
    local slot = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    slot:SetSize(width, 24)
    slot:RegisterForDrag("LeftButton")
    ICUI:Skin(slot, STYLE.panelBg, STYLE.buttonBorder)

    slot.label = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    slot.label:SetPoint("CENTER")
    slot.label:SetText("Drop an item here to add it as a " .. itemType)
    slot.label:SetTextColor(DIM.r, DIM.g, DIM.b)

    slot:SetScript("OnEnter", function(self)
        local c = STYLE.buttonHoverBg
        self:SetBackdropColor(c.r, c.g, c.b, c.a)
        self.label:SetTextColor(BONE.r, BONE.g, BONE.b)
    end)
    slot:SetScript("OnLeave", function(self)
        local c = STYLE.panelBg
        self:SetBackdropColor(c.r, c.g, c.b, c.a)
        self.label:SetTextColor(DIM.r, DIM.g, DIM.b)
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

-- A small texture button, used for the row arrows and the per-row rescan.
local function IconButton(parent, size, texture, highlight, tip, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.texture = b:CreateTexture(nil, "ARTWORK")
    b.texture:SetAllPoints()
    b.texture:SetTexture(texture)
    b:SetScript("OnEnter", function(self)
        if highlight then
            self.texture:SetTexture(highlight)
        else
            self.texture:SetVertexColor(1.0, 1.0, 0.5)
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(tip, 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        self.texture:SetTexture(texture)
        self.texture:SetVertexColor(1.0, 1.0, 1.0)
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", onClick)
    return b
end

-- Tables are built once per column layout. The TSM columns come and go with the feed,
-- so each layout gets its own table and the one on screen is the one that matches.
local function CachedTable(page, sig, build)
    page.tables = page.tables or {}
    for key, t in pairs(page.tables) do
        if key ~= sig then
            t.header:Hide()
            t.scroll:Hide()
        end
    end
    local t = page.tables[sig]
    if not t then
        t = build()
        page.tables[sig] = t
    end
    t.header:Show()
    t.scroll:Show()
    return t
end

--------------------------------------------------------------------------------
-- Materials and Products
--------------------------------------------------------------------------------

local ITEM_FOOTER_H = 56

-- The reorder arrows and per-item rescan, as one cell the pool can reuse.
local function ItemControls(row, col, x, style)
    local box = CreateFrame("Frame", nil, row)
    box:SetSize(col.width, row.rowHeight)
    box:SetPoint("LEFT", row, "LEFT", x, 0)

    local function act(fn)
        return function()
            local MAW = _G.MalexisAuctionWatcher
            if MAW and row.item then fn(MAW, row.item) end
        end
    end

    box.up = IconButton(box, CONTROL_BUTTON_SIZE,
        "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up",
        "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Highlight",
        "Move up", act(function(MAW, item) MAW:MoveItemUp(item.name, item.kind) end))
    box.up:SetPoint("LEFT", box, "LEFT", 2, 0)

    box.down = IconButton(box, CONTROL_BUTTON_SIZE,
        "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up",
        "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Highlight",
        "Move down", act(function(MAW, item) MAW:MoveItemDown(item.name, item.kind) end))
    box.down:SetPoint("LEFT", box.up, "RIGHT", 2, 0)

    box.rescan = IconButton(box, CONTROL_BUTTON_SIZE,
        "Interface\\Buttons\\UI-RefreshButton", nil,
        "Scan this item", act(function(MAW, item) MAW:ScanSingleItem(item.name) end))
    box.rescan:SetPoint("LEFT", box.down, "RIGHT", 2, 0)

    return box
end

local function ItemColumns()
    local cols = {
        { key = "ctrl", label = "", width = ITEM_CONTROLS_WIDTH, type = "custom", make = ItemControls },
        { key = "name", label = "Item", width = "flex" },
    }
    if TsmColumnsShown() then
        for _, col in ipairs(TSM_COLUMNS) do
            cols[#cols + 1] = { key = "tsm_" .. col.key, label = col.header,
                width = TSM_CELL_WIDTH, justify = "RIGHT", hit = true, font = "GameFontHighlightSmall" }
        end
    end
    cols[#cols + 1] = { key = "today", label = "Today", width = 80, justify = "RIGHT", hit = true }
    cols[#cols + 1] = { key = "low",   label = "low",   width = 80, justify = "RIGHT", hit = true }
    cols[#cols + 1] = { key = "ave",   label = "ave",   width = 80, justify = "RIGHT" }
    cols[#cols + 1] = { key = "high",  label = "high",  width = 80, justify = "RIGHT", hit = true }
    return cols
end

-- Sorted item list for one tab, with the stats each row needs already worked out.
local function ItemRows(kind, sortMode)
    local MAW = _G.MalexisAuctionWatcher
    local db = MAW:GetActiveDB()
    local list = {}
    if not db or not db.items then return list end

    for itemName, itemData in pairs(db.items) do
        if (itemData.itemType or "material") == kind then
            local stats = CalculatePriceStats(itemName)
            if stats then
                list[#list + 1] = { name = itemName, data = itemData, stats = stats, kind = kind,
                    order = itemData.order or 0 }
            end
        end
    end

    if sortMode == "movers" then
        for _, item in ipairs(list) do
            item.pos = MAW:GetRangePosition(item.name)
        end
        table.sort(list, function(a, b)
            if (a.pos == nil) ~= (b.pos == nil) then
                return a.pos ~= nil
            end
            if a.pos ~= nil and a.pos ~= b.pos then
                if kind == "material" then return a.pos < b.pos end
                return a.pos > b.pos
            end
            return a.order < b.order
        end)
    else
        table.sort(list, function(a, b) return a.order < b.order end)
    end
    return list
end

local function BuildItemsPage(page, kind)
    local view = { kind = kind }

    local footer = CreateFrame("Frame", nil, page)
    footer:SetPoint("BOTTOMLEFT", 0, 0)
    footer:SetPoint("BOTTOMRIGHT", 0, 0)
    footer:SetHeight(ITEM_FOOTER_H)

    view.drop = CreateDropSlot(footer, kind, 360)
    view.drop:SetPoint("TOPLEFT", 0, 0)

    local legend = Note(footer,
        "Today: no tag = your scan, |cffe0b060[A]|r = Auctionator, |cffe0b060[T]|r = TSM."
        .. "  TSM 60d/14d = TSM averages (region values when the realm has none)."
        .. "\nlow/high: * = set by you, ~ = from TSM, plain = your scans.",
        STYLE.pageWidth - 26)
    legend:SetPoint("TOPLEFT", view.drop, "BOTTOMLEFT", 0, -6)

    function view:Refresh()
        local MAW = _G.MalexisAuctionWatcher
        local invert = (kind == "product")
        local sig = TsmColumnsShown() and "tsm" or "plain"

        local t = CachedTable(page, sig, function()
            return Table(page, {
                top = 0, bottom = ITEM_FOOTER_H + 4,
                columns = ItemColumns(),
                buttons = { { key = "remove", label = "X", width = 22, kind = "danger" } },
            })
        end)

        t:Render(ItemRows(kind, SortMode()), function(row, item)
            local stats = item.stats
            t:Set(row, "name", item.name, BONE)

            if TsmColumnsShown() then
                local ref = item.data.tsmRef
                for _, col in ipairs(TSM_COLUMNS) do
                    local key = "tsm_" .. col.key
                    local value = ref and ref[col.key]
                    local text, color = "-", DIM
                    if value and value > 0 then
                        text = FormatMoney(value)
                        color = (stats.high and stats.high > 0)
                            and GetPriceColor(value, stats.low, stats.high, invert) or TSM_TINT
                    end
                    t:Set(row, key, text, color)
                    TsmTooltip(row.hit[key], col, item.name, item.data, stats)
                end
            end

            t:Set(row, "today", FormatMoney(stats.today) .. SourceTag(item.data),
                GetPriceColor(stats.today, stats.low, stats.high, invert))
            SourceTooltip(row.hit.today, item.name, item.data)

            local lowText = FormatMoney(stats.low)
            if stats.isCustomLow then
                lowText = lowText .. "*"
            elseif stats.isTsmLow then
                lowText = lowText .. "~"
            end
            t:Set(row, "low", lowText, invert and COLOR_HIGH or COLOR_LOW)

            t:Set(row, "ave", FormatMoney(stats.average), COLOR_AVE)

            local highText = FormatMoney(stats.high)
            if stats.isCustomHigh then
                highText = highText .. "*"
            elseif stats.isTsmHigh then
                highText = highText .. "~"
            end
            t:Set(row, "high", highText, invert and COLOR_LOW or COLOR_HIGH)

            for _, bound in ipairs({ { "low", "LOW" }, { "high", "HIGH" } }) do
                local hit = row.hit[bound[1]]
                Tooltip(hit, function()
                    GameTooltip:AddLine(item.name)
                    GameTooltip:AddLine("Click to set the " .. bound[1] .. " bound by hand", 1, 1, 1)
                    GameTooltip:AddLine("* set by you, ~ from TSM, plain from your scans", 0.7, 0.7, 0.7)
                end)
                hit:SetScript("OnClick", function()
                    if _G.MalexisAuctionWatcherDialogs then
                        _G.MalexisAuctionWatcherDialogs.ShowPriceInputDialog(item.name, bound[2])
                    end
                end)
            end

            local remove = row.buttons.remove
            Tooltip(remove, function() GameTooltip:AddLine("Stop tracking " .. item.name) end)
            remove:SetScript("OnClick", function() MAW:RemoveItem(item.name) end)
        end)
    end

    return view
end

--------------------------------------------------------------------------------
-- Stores
--------------------------------------------------------------------------------

local STORES_FOOTER_H = 56

local function StoresColumns()
    local MAW = _G.MalexisAuctionWatcher
    local cols = { { key = "name", label = "Item", width = "flex", hit = true } }
    if TsmColumnsShown() then
        for _, col in ipairs(TSM_COLUMNS) do
            cols[#cols + 1] = { key = "tsm_" .. col.key, label = col.header,
                width = TSM_CELL_WIDTH, justify = "RIGHT", hit = true }
        end
    end
    cols[#cols + 1] = { key = "inv",   label = "Inventory", width = 80, justify = "RIGHT" }
    cols[#cols + 1] = { key = "bank",  label = "Bank",      width = 80, justify = "RIGHT" }
    cols[#cols + 1] = { key = "ah",    label = "AH",        width = 80, justify = "RIGHT" }
    cols[#cols + 1] = { key = "total", label = "Total",     width = 80, justify = "RIGHT" }
    cols[#cols + 1] = { key = "value", label = "Value",     width = 100, justify = "RIGHT" }
    cols[#cols + 1] = { key = "ahnet",
        label = string.format("AH Net -%d%%", math.floor(MAW:GetAHCut() * 100 + 0.5)),
        width = 100, justify = "RIGHT" }
    return cols
end

-- One stock line: counts, what it is worth, and what the auction house would leave you.
local function StoreEntry(itemName, itemData, counts)
    local MAW = _G.MalexisAuctionWatcher
    local c = counts[itemName] or { inventory = 0, bank = 0, auctionHouse = 0 }
    local total = c.inventory + c.bank + c.auctionHouse
    local stats = CalculatePriceStats(itemName)
    local unit = 0
    if stats then
        unit = (stats.today and stats.today > 0) and stats.today or (stats.average or 0)
    end
    local value = unit * total
    return {
        kind = "item", name = itemName, data = itemData, stats = stats, unit = unit,
        inv = c.inventory, bank = c.bank, ah = c.auctionHouse, total = total,
        value = value, ahNet = value * (1 - MAW:GetAHCut()),
    }
end

local function SumEntries(list, label)
    local row = { kind = "total", name = label, inv = 0, bank = 0, ah = 0, total = 0,
        value = 0, ahNet = 0 }
    for _, e in ipairs(list) do
        row.inv = row.inv + e.inv
        row.bank = row.bank + e.bank
        row.ah = row.ah + e.ah
        row.total = row.total + e.total
        row.value = row.value + e.value
        row.ahNet = row.ahNet + e.ahNet
    end
    return row
end

local function BuildStoresPage(page)
    local view = {}

    local footer = CreateFrame("Frame", nil, page)
    footer:SetPoint("BOTTOMLEFT", 0, 0)
    footer:SetPoint("BOTTOMRIGHT", 0, 0)
    footer:SetHeight(STORES_FOOTER_H)

    view.drop = CreateDropSlot(footer, "material", 360)
    view.drop:SetPoint("TOPLEFT", 0, 0)

    local legend = Note(footer,
        "Value uses each item's latest price. Hover an item name for its source and time."
        .. "\n|cffe0b060[A]|r = Auctionator, |cffe0b060[T]|r = TSM.",
        STYLE.pageWidth - 26)
    legend:SetPoint("TOPLEFT", view.drop, "BOTTOMLEFT", 0, -6)

    function view:Refresh()
        local MAW = _G.MalexisAuctionWatcher
        local db = MAW:GetActiveDB()
        local counts = MAW:GetAllInventoryCounts() or {}
        local sig = TsmColumnsShown() and "tsm" or "plain"

        local cols = StoresColumns()
        local t = CachedTable(page, sig, function()
            return Table(page, {
                top = 0, bottom = STORES_FOOTER_H + 4,
                columns = cols,
            })
        end)
        -- The AH cut can change, so refresh the labels the table was built with.
        for _, col in ipairs(cols) do
            local label = t.header.labels[col.key]
            if label then label:SetText(col.label or "") end
        end

        local products, materials = {}, {}
        for itemName, itemData in pairs((db and db.items) or {}) do
            local entry = StoreEntry(itemName, itemData, counts)
            if (itemData.itemType or "material") == "product" then
                products[#products + 1] = entry
            else
                materials[#materials + 1] = entry
            end
        end
        local function byOrder(a, b)
            return (a.data.order or 0) < (b.data.order or 0)
        end
        table.sort(products, byOrder)
        table.sort(materials, byOrder)

        -- Grand total first, then each section with its own subtotal underneath.
        local all = {}
        for _, e in ipairs(products) do all[#all + 1] = e end
        for _, e in ipairs(materials) do all[#all + 1] = e end

        local rows = { SumEntries(all, "GRAND TOTAL") }
        if #products > 0 then
            rows[#rows + 1] = { kind = "section", name = "PRODUCTS" }
            for _, e in ipairs(products) do rows[#rows + 1] = e end
            rows[#rows + 1] = SumEntries(products, "Products total")
        end
        if #materials > 0 then
            rows[#rows + 1] = { kind = "section", name = "MATERIALS" }
            for _, e in ipairs(materials) do rows[#rows + 1] = e end
            rows[#rows + 1] = SumEntries(materials, "Materials total")
        end

        t:Render(rows, function(row, e)
            if e.kind == "section" then
                t:Span(row, e.name, GOLD)
                t:Tint(row, STYLE.headerBg)
                return
            end

            local invert = e.data and (e.data.itemType or "material") == "product"
            if e.kind == "total" then
                t:Set(row, "name", e.name, GOLD)
                t:Tint(row, STYLE.headerBg)
            else
                t:Set(row, "name", e.name .. SourceTag(e.data), BONE)
                SourceTooltip(row.hit.name, e.name, e.data)
                if TsmColumnsShown() then
                    local ref = e.data.tsmRef
                    for _, col in ipairs(TSM_COLUMNS) do
                        local key = "tsm_" .. col.key
                        local value = ref and ref[col.key]
                        local text, color = "-", DIM
                        if value and value > 0 then
                            text = FormatMoney(value)
                            color = (e.stats and e.stats.high and e.stats.high > 0)
                                and GetPriceColor(value, e.stats.low, e.stats.high, invert) or TSM_TINT
                        end
                        t:Set(row, key, text, color)
                        TsmTooltip(row.hit[key], col, e.name, e.data, e.stats)
                    end
                end
            end

            t:Set(row, "inv", tostring(e.inv), WHITE)
            t:Set(row, "bank", tostring(e.bank), WHITE)
            t:Set(row, "ah", tostring(e.ah), WHITE)
            t:Set(row, "total", tostring(e.total), COLOR_AVE)

            -- Value is graded on the unit price, so an empty shelf still reads high or
            -- low. A totals line is money in hand (green); an item with no bounds has
            -- nothing to grade against, and grey is what missing looks like.
            local color, netColor = COLOR_LOW, COLOR_LOW
            if e.kind == "item" then
                color, netColor = DIM, DIM
                if e.stats and e.stats.low and e.stats.high then
                    local cut = _G.MalexisAuctionWatcher:GetAHCut()
                    color = GetPriceColor(e.unit, e.stats.low, e.stats.high, invert)
                    netColor = GetPriceColor(e.unit * (1 - cut), e.stats.low, e.stats.high, invert)
                end
            end
            t:Set(row, "value", FormatMoney(e.value), color)
            t:Set(row, "ahnet", FormatMoney(e.ahNet), netColor)
        end)
    end

    return view
end

--------------------------------------------------------------------------------
-- History
--------------------------------------------------------------------------------

local HISTORY_MODES = {
    { key = "daily30",  label = "30 days",      mode = "daily",    span = 30, maxLabels = 10 },
    { key = "daily90",  label = "90 days",      mode = "daily",    span = 90, maxLabels = 9 },
    { key = "weekday",  label = "Weekday",      mode = "weekday",  maxLabels = 7 },
    { key = "monthday", label = "Day of month", mode = "monthday", maxLabels = 16 },
    { key = "hour",     label = "Hour",         mode = "hour",     maxLabels = 12 },
}

-- Which price basis the Recipes tab reads. Saved for the same reason the History
-- selection is: it changes every number on the page, so finding a different one on
-- the next login reads as the numbers having moved rather than as a setting.
local function RecipeBasis()
    return Setting("recipeBasis", "latest")
end

local function SetRecipeBasis(key)
    local settings = MalexisAuctionWatcherDB and MalexisAuctionWatcherDB.settings
    if settings then settings.recipeBasis = key end
end

-- What History is looking at, and the period it shows, are saved settings now:
-- see MAW:GetHistorySelection. The ordering is shared with the data layer.
local function SortedTrackedItems()
    return _G.MalexisAuctionWatcher:SortedTrackedItemNames()
end

-- A classic dropdown does not scroll. With a preset loaded, "Gem" alone is 120
-- entries and runs off the bottom of the screen, so a long category is split into
-- alphabetical chunks rather than given a third level to hide in.
local PICKER_CHUNK = 24

local function Chunked(groups, label, entries)
    if #entries <= PICKER_CHUNK then
        groups[#groups + 1] = {
            text = string.format("%s (%d)", label, #entries),
            entries = entries,
        }
        return
    end
    local from = 1
    while from <= #entries do
        local to = math.min(from + PICKER_CHUNK - 1, #entries)
        local part = {}
        for i = from, to do part[#part + 1] = entries[i] end
        groups[#groups + 1] = {
            text = string.format("%s  %s - %s", label,
                entries[from].name:sub(1, 3), entries[to].name:sub(1, 3)),
            entries = part,
        }
        from = to + 1
    end
end

-- Level one of the picker: auction house categories, then the recipes. An item
-- whose class this client has not cached yet lands in Other; asking for the class
-- is also what queues the request, so it moves to its real category the next time
-- the menu is opened.
local function HistoryPickerGroups()
    local MAW = _G.MalexisAuctionWatcher
    local byClass, classes = {}, {}
    for _, item in ipairs(SortedTrackedItems()) do
        local class = MAW:GetItemClass(item.name, item.data) or "Other"
        if not byClass[class] then
            byClass[class] = {}
            classes[#classes + 1] = class
        end
        local list = byClass[class]
        list[#list + 1] = { name = item.name, kind = "item" }
    end
    table.sort(classes, function(a, b)
        -- Other last: it is the "we do not know yet" pile, not a category.
        if (a == "Other") ~= (b == "Other") then return b == "Other" end
        return a < b
    end)

    local groups = {}
    for _, class in ipairs(classes) do
        local entries = byClass[class]
        table.sort(entries, function(a, b) return a.name < b.name end)
        Chunked(groups, class, entries)
    end

    local recipes = {}
    for _, recipe in ipairs(MAW:GetRecipes()) do
        recipes[#recipes + 1] = { name = recipe.name, kind = "recipe" }
    end
    table.sort(recipes, function(a, b) return a.name < b.name end)
    if #recipes == 0 then
        groups[#groups + 1] = { text = "Tracked Recipes (none)", entries = {} }
    else
        Chunked(groups, "Tracked Recipes", recipes)
    end
    return groups
end

local HISTORY_PANEL_H = 60 + CHART_HEIGHT + 160

local function BuildHistoryPage(page)
    local view = {}
    local chartWidth = STYLE.pageWidth - 26

    -- Docked over the auction house the window is only as tall as its host, so the
    -- panel scrolls rather than running off the bottom.
    local scroll, panel = ICUI:ScrollList(page, 0, 0)
    panel:SetSize(chartWidth, HISTORY_PANEL_H)
    view.scroll = scroll
    page = panel

    -- Item picker and the external pulls, above everything they change
    local top = Toolbar(page, { top = 0, height = 24 })

    local dropdown = CreateFrame("Frame", "MalexisAuctionWatcherHistoryDropdown", top, "UIDropDownMenuTemplate")
    dropdown:SetPoint("LEFT", top, "LEFT", -14, 0)
    UIDropDownMenu_SetWidth(dropdown, 220)
    -- Two levels: categories, then what is in one. The group list is rebuilt on
    -- every level-1 pass and read back by index at level 2, which is what
    -- UIDROPDOWNMENU_MENU_VALUE carries between the two calls.
    UIDropDownMenu_Initialize(dropdown, function(_, level)
        local MAW = _G.MalexisAuctionWatcher
        if level == 1 then
            view.pickerGroups = HistoryPickerGroups()
            for index, group in ipairs(view.pickerGroups) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = group.text
                info.hasArrow = true
                info.notCheckable = true
                info.disabled = #group.entries == 0
                info.value = index
                UIDropDownMenu_AddButton(info, level)
            end
            return
        end

        local group = view.pickerGroups and view.pickerGroups[UIDROPDOWNMENU_MENU_VALUE]
        if not group then return end
        local kind, name = MAW:GetHistorySelection()
        for _, entry in ipairs(group.entries) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = entry.name
            info.checked = (entry.kind == kind and entry.name == name)
            info.func = function()
                MAW:SetHistorySelection(entry.kind, entry.name)
                CloseDropDownMenus()
                MAWUI:RefreshData()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    view.dropdown = dropdown

    view.pullAtr = Button(top, "Pull Auctionator", 130, 22)
    view.pullAtr:SetPoint("LEFT", top, "LEFT", 265, 0)
    view.pullAtr:SetScript("OnClick", function()
        local MAW = _G.MalexisAuctionWatcher
        print("Malexis Auction Watcher: Pulling from Auctionator...")
        MAW:PullExternalPrices("button", "auctionator", true)
        MAWUI:RefreshData()
    end)

    view.pullTsm = Button(top, "Pull TSM", 90, 22)
    view.pullTsm:SetPoint("LEFT", view.pullAtr, "RIGHT", 6, 0)
    view.pullTsm:SetScript("OnClick", function()
        local MAW = _G.MalexisAuctionWatcher
        print("Malexis Auction Watcher: Pulling from TSM...")
        MAW:PullExternalPrices("button", "tsm", true)
        MAWUI:RefreshData()
    end)

    -- Period buttons on their own row
    local modes = Toolbar(page, { top = -30, height = 22 })
    view.modeButtons = {}
    for _, m in ipairs(HISTORY_MODES) do
        local btn = Button(modes, m.label, m.key == "monthday" and 100 or 80, 22)
        btn:SetScript("OnClick", function()
            _G.MalexisAuctionWatcher:SetHistoryMode(m.key)
            MAWUI:RefreshData()
        end)
        modes:Left(btn)
        view.modeButtons[m.key] = btn
    end

    view.chart = _G.MalexisAuctionWatcherChart.Create(page, chartWidth, CHART_HEIGHT)
    view.chart:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -60)

    -- Set per view: an item and a recipe are read differently.
    view.legend = Note(page, "", chartWidth)
    view.legend:SetPoint("TOPLEFT", view.chart, "BOTTOMLEFT", 0, -6)

    view.summary = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    view.summary:SetPoint("TOPLEFT", view.legend, "BOTTOMLEFT", 0, -8)
    view.summary:SetJustifyH("LEFT")
    view.summary:SetWidth(chartWidth)

    view.note = Note(page, "", chartWidth)
    view.note:SetPoint("TOPLEFT", view.summary, "BOTTOMLEFT", 0, -4)

    view.sources = Note(page, "", chartWidth)
    view.sources:SetPoint("TOPLEFT", view.note, "BOTTOMLEFT", 0, -6)
    view.sources:SetTextColor(0.6, 0.7, 0.8)

    -- Material lines cycle through these. Blues, purples and teals only: green is
    -- money in, red is money out, and amber already means an external price feed in
    -- the legend directly above this chart. A thin line must not look like a washed
    -- out version of the bold line it means the opposite of.
    local MAT_COLORS = {
        { 0.45, 0.72, 0.98 }, { 0.72, 0.58, 0.95 }, { 0.35, 0.82, 0.85 },
        { 0.58, 0.62, 0.92 }, { 0.45, 0.88, 0.98 }, { 0.85, 0.60, 0.90 },
    }
    local COST_COLOR = { 0.98, 0.45, 0.42 }
    local VALUE_COLOR = { 0.45, 0.92, 0.45 }

    -- Where "now" falls in cyclic views, so the wrap from last period to this one
    -- is visible. Shared by both views.
    local function MarkerFor(modeDef)
        local nowT = date("*t")
        if modeDef.mode == "monthday" then
            return nowT.day, "Today (" .. nowT.day .. ")"
        elseif modeDef.mode == "weekday" then
            return nowT.wday, "Today"
        elseif modeDef.mode == "hour" then
            return nowT.hour + 1, "Now"
        end
    end

    local function TitleFor(modeDef)
        return function(p)
            if modeDef.mode == "hour" then
                return p.label .. ":00"
            elseif modeDef.mode == "monthday" then
                return "Day " .. p.label
            end
            return p.label
        end
    end

    -- Signed, because a craft can lose money and the coin API refuses a negative.
    local function Signed(copper)
        local text = FormatMoney(math.abs(copper))
        if copper < 0 then return "|cffff8080-" .. text .. "|r" end
        return "|cff80ff80+" .. text .. "|r"
    end

    function view:RefreshItem(itemName, modeDef, markerIndex, markerLabel)
        local MAW = _G.MalexisAuctionWatcher
        local db = MAW:GetActiveDB()

        self.legend:SetText(
            "Bars: |cff8ca6d9blue|r = your scans, |cffccb366amber|r = Auctionator/TSM, "
            .. "|cff59e659green|r = cheapest, |cfff25959red|r = priciest."
            .. "\nWhite tick = average. |cffffd94dYellow lines|r bracket the bucket you are in "
            .. "now; the ones past it are from the previous cycle.")

        local analysis = MAW:AnalyzePeriodicity(itemName, modeDef.mode, modeDef.span)
        local highlight = {}
        if analysis.best and analysis.worst and analysis.best.index ~= analysis.worst.index then
            highlight.best = analysis.best.index
            highlight.worst = analysis.worst.index
        end

        -- TSM reference averages (snapshot values, not a time series)
        local refLines = {}
        local tsmRef = db.items[itemName] and db.items[itemName].tsmRef
        if tsmRef and MAW.sources.tsm.available and MAW:IsSourceEnabled("tsm") then
            if tsmRef.market then
                table.insert(refLines, { value = tsmRef.market, label = "TSM mrkt 14d", color = { 0.95, 0.65, 0.95 } })
            end
            if tsmRef.historical then
                table.insert(refLines, { value = tsmRef.historical, label = "TSM hist 60d", color = { 0.7, 0.55, 0.95 } })
            end
        end

        self.chart:SetData(analysis.points, {
            highlight = highlight,
            refLines = refLines,
            markerIndex = markerIndex,
            markerLabel = markerLabel,
            maxLabels = modeDef.maxLabels,
            tooltipTitle = TitleFor(modeDef),
        })

        if analysis.best and analysis.worst then
            local unit = ({ daily = "", weekday = "", monthday = "day ", hour = "hour " })[modeDef.mode] or ""
            self.summary:SetText(string.format(
                "|cff80ff80Cheapest:|r %s%s (avg %s, %d samples)   |cffff8080Priciest:|r %s%s (avg %s, %d samples)   Spread %.0f%%",
                unit, analysis.best.label, FormatMoney(analysis.best.avg), analysis.best.n,
                unit, analysis.worst.label, FormatMoney(analysis.worst.avg), analysis.worst.n,
                analysis.spreadPct))
            if analysis.confident then
                self.note:SetText("Pattern is based on at least 3 samples in both buckets.")
            else
                self.note:SetText("Not enough data yet for a reliable pattern (need 3+ samples in the cheapest and priciest buckets).")
            end
        else
            self.summary:SetText("No price history for " .. itemName .. " yet. Scan the auction house or enable an external source.")
            self.note:SetText("")
        end
    end

    -- One recipe as three kinds of line: what a batch sells for, what its
    -- materials cost, and each material on its own. The distance between the two
    -- bold lines is the conversion you are deciding about.
    function view:RefreshRecipe(recipe, modeDef, markerIndex, markerLabel)
        local MAW = _G.MalexisAuctionWatcher
        local series = MAW:GetRecipeSeries(recipe, modeDef.mode, modeDef.span)
        local cutPct = math.floor((series.cut or 0) * 100 + 0.5)

        self.legend:SetText(string.format(
            "|cff73eb73Green|r = a batch of %s sold, after the %d%% cut. "
            .. "|cfffa736bRed|r = its materials. Thin lines = each material x how many."
            .. "\nA break in a line is a slot with no price for that item; the cost "
            .. "line breaks whenever any material does. Vendor materials are folded "
            .. "into the cost at their fixed price.",
            recipe.product or "the product", cutPct))

        -- The chart still wants one entry per slot: they carry the labels and are
        -- the hover targets, they just draw no candle.
        local points = {}
        for i = 1, series.count do
            points[i] = { label = series.labels[i], n = 0 }
        end

        local lines = {}
        for index, mat in ipairs(series.mats) do
            if mat.values then
                lines[#lines + 1] = {
                    label = string.format("%s x%d", mat.name, mat.count),
                    color = MAT_COLORS[((index - 1) % #MAT_COLORS) + 1],
                    width = 1,
                    values = mat.values,
                }
            end
        end
        lines[#lines + 1] = { label = "Material cost", color = COST_COLOR, width = 2, values = series.cost }
        lines[#lines + 1] = { label = "Batch value", color = VALUE_COLOR, width = 2, values = series.value }
        -- Listed but not drawn: a margin has its own scale and would flatten the
        -- two lines it is the distance between.
        lines[#lines + 1] = { label = "Margin", color = { 1, 0.9, 0.5 }, values = series.margin, plot = false }

        self.chart:SetData(points, {
            noBars = true,
            lines = lines,
            markerIndex = markerIndex,
            markerLabel = markerLabel,
            maxLabels = modeDef.maxLabels,
            tooltipTitle = TitleFor(modeDef),
        })

        local slot = MAW.RecipeSlotAt(series, markerIndex or series.count)
        if slot then
            local margin = series.margin[slot]
            local cost = series.cost[slot]
            local pct = cost > 0 and (margin / cost * 100) or 0
            self.summary:SetText(string.format(
                "%s: value %s, materials %s, margin %s (%.0f%%)",
                series.labels[slot] or "Latest",
                FormatMoney(series.value[slot]), FormatMoney(cost), Signed(margin), pct))
        else
            self.summary:SetText("No slot yet has a price for the product and every material.")
        end

        local parts = {}
        if #series.missing > 0 then
            parts[#parts + 1] = "|cffffcc00Not tracked:|r " .. table.concat(series.missing, ", ")
                .. " - add them, or use Scan Tab to price the whole recipe."
        end
        if series.best and series.worst and series.best.index ~= series.worst.index then
            parts[#parts + 1] = string.format("Best %s %s, worst %s %s.",
                series.best.label, Signed(series.best.margin),
                series.worst.label, Signed(series.worst.margin))
        end
        parts[#parts + 1] = string.format("%d of %d slots priced.", series.complete, series.count)
        self.note:SetText(table.concat(parts, "   "))
    end

    function view:Refresh()
        local MAW = _G.MalexisAuctionWatcher

        local kind, name = MAW:GetHistorySelection()
        UIDropDownMenu_SetText(self.dropdown,
            (kind == "recipe" and ("Recipe: " .. name))
            or name
            or "No items tracked")

        -- Pull buttons only when the source is loaded
        if MAW.DetectSources then
            MAW:DetectSources()
            self.pullAtr:SetEnabled(MAW.sources.auctionator.available)
            self.pullTsm:SetEnabled(MAW.sources.tsm.available)
        end

        local mode = MAW:GetHistoryMode()
        for key, btn in pairs(self.modeButtons) do
            btn:SetActive(key == mode)
        end

        local modeDef = HISTORY_MODES[1]
        for _, m in ipairs(HISTORY_MODES) do
            if m.key == mode then modeDef = m end
        end

        local markerIndex, markerLabel = MarkerFor(modeDef)

        if kind == "recipe" then
            local recipe = MAW:FindRecipe(name)
            if recipe then
                self:RefreshRecipe(recipe, modeDef, markerIndex, markerLabel)
            else
                kind = nil
            end
        elseif kind == "item" then
            self:RefreshItem(name, modeDef, markerIndex, markerLabel)
        end

        if not kind then
            self.chart:SetData({}, {})
            self.legend:SetText("")
            self.summary:SetText("Track an item first, then come back here.")
            self.note:SetText("")
        end

        self.sources:SetText("Sources: " .. (MAW.DescribeSources and MAW:DescribeSources() or "scan")
            .. "   |   Retention: " .. MAW:GetHistoryDays() .. " days"
            .. "\nBars come from your scans and Auctionator's daily history (up to 21 days back). "
            .. "TSM has no daily history: Pull TSM records today's snapshot and shows its 14d/60d averages as lines.")
    end

    return view
end

--------------------------------------------------------------------------------
-- Recipes
--------------------------------------------------------------------------------

local RECIPE_FOOTER_H = 22

local function ProfitColor(profit)
    if not profit then
        return DIM
    elseif profit > 0 then
        return COLOR_LOW
    elseif profit < 0 then
        return COLOR_HIGH
    end
    return COLOR_AVE
end

-- The per-recipe rescan icon, as one reusable cell.
local function RecipeControls(row, col, x, style)
    local box = CreateFrame("Frame", nil, row)
    box:SetSize(col.width, row.rowHeight)
    box:SetPoint("LEFT", row, "LEFT", x, 0)
    box.rescan = IconButton(box, CONTROL_BUTTON_SIZE,
        "Interface\\Buttons\\UI-RefreshButton", nil,
        "Scan this recipe's items", function()
            local MAW = _G.MalexisAuctionWatcher
            if row.item and row.item.recipe then
                MAW:StartScan(MAW:GetRecipeItems(row.item.recipe), "Scanning " .. row.item.recipe.name)
            end
        end)
    box.rescan:SetPoint("LEFT", box, "LEFT", 4, 0)
    return box
end

local function BuildRecipesPage(page)
    local view = {}

    local bar = Toolbar(page, { top = 0, height = 24 })

    if not page.presetMenu then
        page.presetMenu = CreateFrame("Frame", "MalexisAuctionWatcherPresetMenu", UIParent, "UIDropDownMenuTemplate")
        UIDropDownMenu_Initialize(page.presetMenu, function(_, level)
            local MAW = _G.MalexisAuctionWatcher
            local dlg = _G.MalexisAuctionWatcherRecipeDialog
            local function after() MAWUI:RefreshData() end
            local items = {
                { text = "Add recipes", isTitle = true },
                { text = "Motes -> Primals (7)", func = function() MAW:AddMotePresets(); after() end },
                { text = "Transmute: Primal Might", func = function() MAW:AddPrimalMightPreset(); after() end },
                { text = "Alchemy: potions", func = function() MAW:AddAlchemyPresets("potion"); after() end },
                { text = "Alchemy: elixirs", func = function() MAW:AddAlchemyPresets("elixir"); after() end },
                { text = "Alchemy: flasks", func = function() MAW:AddAlchemyPresets("flask"); after() end },
                { text = "Alchemy: transmutes", func = function() MAW:AddAlchemyPresets("transmute"); after() end },
                { text = "Alchemy: everything TBC (" .. #MAW.PRESET_ALCHEMY .. ")", func = function() MAW:AddAlchemyPresets(); after() end },
                { text = "Gem cuts...", func = function() if dlg then dlg.ShowGemPicker() end end },
                { text = "From your recipe book...", func = function() if dlg then dlg.ShowProfessionImport() end end },
                { text = "Track items only", isTitle = true },
                { text = "Flipping guide watchlist (herbs, primals, gems, shards)", func = function() MAW:AddGuideWatchlist(); after() end },
            }
            for _, item in ipairs(items) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = item.text
                info.isTitle = item.isTitle
                info.notCheckable = true
                info.disabled = item.isTitle
                info.func = item.func
                UIDropDownMenu_AddButton(info, level)
            end
        end, "MENU")
    end

    local presetBtn = Button(bar, "Presets...", 120, 22)
    presetBtn:SetScript("OnClick", function(self)
        ToggleDropDownMenu(1, nil, page.presetMenu, self, 0, 0)
    end)
    bar:Left(presetBtn)

    local addRecipeBtn = Button(bar, "Add Recipe", 110, 22)
    addRecipeBtn:SetScript("OnClick", function()
        if _G.MalexisAuctionWatcherRecipeDialog then
            _G.MalexisAuctionWatcherRecipeDialog.Show()
        end
    end)
    bar:Left(addRecipeBtn)

    -- Price basis: cycles Latest -> TSM 14d -> TSM 60d
    view.basisBtn = Button(bar, "Prices: Latest", 130, 22)
    view.basisBtn:SetScript("OnClick", function()
        local MAW = _G.MalexisAuctionWatcher
        local bases = MAW.PRICE_BASES
        for i, b in ipairs(bases) do
            if b.key == RecipeBasis() then
                SetRecipeBasis(bases[(i % #bases) + 1].key)
                break
            end
        end
        MAWUI:RefreshData()
    end)
    Tooltip(view.basisBtn, function()
        GameTooltip:AddLine("Price basis for the table")
        GameTooltip:AddLine("Latest: each item's most recent price from any source.", 1, 1, 1)
        GameTooltip:AddLine("TSM 14d / 60d: TSM market or historical average; items without TSM data use Latest.", 1, 1, 1)
        GameTooltip:AddLine("Hover a recipe to see profit under all three.", 0.7, 0.7, 0.7)
    end)
    bar:Left(view.basisBtn)

    view.summary = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    view.summary:SetPoint("BOTTOMLEFT", 0, 4)
    view.summary:SetJustifyH("LEFT")
    view.summary:SetWordWrap(false)
    view.summary:SetTextColor(GOLD.r, GOLD.g, GOLD.b)

    function view:Refresh()
        local MAW = _G.MalexisAuctionWatcher
        local tsmOn = TsmColumnsShown()
        if not tsmOn then
            SetRecipeBasis("latest")
        end
        local basisDef = MAW:PriceBasisDef(RecipeBasis())
        self.basisBtn:SetText("Prices: " .. basisDef.label)
        self.basisBtn:SetEnabled(tsmOn)

        local columns = RecipeColumns()
        local sig = tsmOn and "tsm" or "plain"
        local t = CachedTable(page, sig, function()
            local cols = { { key = "ctrl", label = "", width = RECIPE_CONTROLS_WIDTH,
                type = "custom", make = RecipeControls } }
            for _, col in ipairs(columns) do
                cols[#cols + 1] = {
                    key = col.key, label = col.header, width = col.width,
                    justify = (col.key ~= "name") and "RIGHT" or "LEFT",
                    hit = (col.key == "name" or col.basis) and true or nil,
                }
            end
            return Table(page, {
                top = -30, bottom = RECIPE_FOOTER_H + 4,
                columns = cols,
                buttons = {
                    { key = "edit", label = "E", width = 22 },
                    { key = "remove", label = "X", width = 22, kind = "danger" },
                },
            })
        end)

        for _, col in ipairs(columns) do
            local label = t.header.labels[col.key]
            if label then label:SetText(col.header or "") end
        end

        local rows = {}
        for _, recipe in ipairs(MAW:GetRecipes()) do
            rows[#rows + 1] = MAW:ComputeRecipeProfit(recipe, RecipeBasis())
        end
        -- Best margin first; recipes without prices go to the bottom
        table.sort(rows, function(a, b)
            local ma = a.margin or -math.huge
            local mb = b.margin or -math.huge
            if ma ~= mb then return ma > mb end
            return a.recipe.name < b.recipe.name
        end)

        local totalProfit, totalMakeable = 0, 0
        t:Render(rows, function(row, calc)
            local byBasis = {}
            if tsmOn then
                for _, r in ipairs(MAW:CompareRecipeBases(calc.recipe)) do
                    byBasis[r.basis.key] = r
                end
            end

            for _, col in ipairs(columns) do
                if col.key == "name" then
                    t:Set(row, col.key, calc.recipe.name, BONE)
                    RecipeTooltip(row.hit.name, calc)
                elseif col.key == "matCost" then
                    t:Set(row, col.key, (calc.complete or #calc.missing == 0) and FormatMoney(calc.matCost) or "?", WHITE)
                elseif col.key == "productValue" then
                    t:Set(row, col.key, calc.productValue and FormatMoney(calc.productValue) or "?", WHITE)
                elseif col.key == "ahNet" then
                    t:Set(row, col.key, calc.ahNet and FormatMoney(calc.ahNet) or "?", WHITE)
                elseif col.basis then
                    local r = byBasis[col.basis]
                    t:Set(row, col.key, r and r.profit and FormatMoney(r.profit) or "-",
                        r and r.profit and ProfitColor(r.profit) or DIM)
                    Tooltip(row.hit[col.key], function()
                        GameTooltip:AddLine(calc.recipe.name)
                        GameTooltip:AddLine("Profit if every item were priced at its "
                            .. col.header:gsub("Profit ", "TSM ") .. " average", 0.9, 0.7, 1)
                        GameTooltip:AddLine("Items TSM has no data for use their latest price.", 0.7, 0.7, 0.7)
                    end)
                elseif col.key == "profit" then
                    t:Set(row, col.key, calc.profit and FormatMoney(calc.profit) or "?", ProfitColor(calc.profit))
                elseif col.key == "margin" then
                    t:Set(row, col.key, calc.margin and string.format("%.0f%%", calc.margin) or "?",
                        ProfitColor(calc.profit))
                elseif col.key == "canMake" then
                    t:Set(row, col.key, calc.canMake and tostring(calc.canMake) or "-", COLOR_AVE)
                end
            end

            local edit = row.buttons.edit
            Tooltip(edit, function() GameTooltip:AddLine("Edit recipe") end)
            edit:SetScript("OnClick", function()
                if _G.MalexisAuctionWatcherRecipeDialog then
                    _G.MalexisAuctionWatcherRecipeDialog.ShowEdit(calc.recipe)
                end
            end)

            local remove = row.buttons.remove
            Tooltip(remove, function() GameTooltip:AddLine("Remove " .. calc.recipe.name) end)
            remove:SetScript("OnClick", function() MAW:RemoveRecipe(calc.recipe.name) end)

            if calc.profit and calc.canMake then
                totalProfit = totalProfit + calc.profit * calc.canMake
                totalMakeable = totalMakeable + calc.canMake
            end
        end)

        if #rows == 0 then
            self.summary:SetText("No recipes yet. Use Presets or Add Recipe above.")
        else
            self.summary:SetText(string.format(
                "If you converted everything you own now: %d batches, %s profit",
                totalMakeable, FormatMoney(totalProfit)))
        end
    end

    return view
end

--------------------------------------------------------------------------------
-- Movers
--------------------------------------------------------------------------------

local MOVER_HINT_H = 32

local function UseKeyDown()
    if GetCVarBool then
        local ok, v = pcall(GetCVarBool, "ActionButtonUseKeyDown")
        if ok and v ~= nil then return v end
    end
    return false
end

local MOVER_SECTIONS = {
    { key = "buy", title = "BUY  -  anything cheap: materials to craft, products to stock" },
    { key = "convert", title = "CONVERT  -  profitable recipes you can make now" },
    { key = "sell", title = "LIST  -  anything expensive that you hold, materials included" },
}

local MOVER_BADGE = {
    buy = { text = "BUY", color = COLOR_LOW },
    convert = { text = "CONVERT", color = COLOR_AVE },
    sell = { text = "LIST", color = COLOR_HIGH },
}

local function BuildMoversPage(page)
    local view = {}

    view.hint = Note(page, "", STYLE.pageWidth - 26)
    view.hint:SetPoint("TOPLEFT", 0, 0)

    -- One action button per row. It is secure so a Convert click can cast or use;
    -- Buy and List clear the attributes and run an ordinary script.
    local t = Table(page, {
        top = -MOVER_HINT_H,
        columns = {
            { key = "badge",  label = "",        width = 70 },
            { key = "name",   label = "Item",    width = 260, hit = true },
            { key = "price",  label = "Price",   width = 90, justify = "RIGHT" },
            { key = "reason", label = "Why",     width = "flex" },
        },
        buttons = { { key = "act", label = "", width = 80, template = "SecureActionButtonTemplate" } },
    })
    view.table = t

    function view:Refresh()
        local MAW = _G.MalexisAuctionWatcher
        local movers = MAW:GetMovers()
        local db = MAW:GetActiveDB()

        self.hint:SetText(string.format(
            "Buy: any item at or below %d%% of its range.   Convert: recipes above %d%% margin with mats on hand."
            .. "\nList: any item at or above %d%% of range that you hold.",
            MAW:MoverSetting("moverBuyPct") * 100, MAW:MoverSetting("moverMinMargin"),
            MAW:MoverSetting("moverSellPct") * 100))

        local rows = {}
        for _, sec in ipairs(MOVER_SECTIONS) do
            rows[#rows + 1] = { kind = "section", title = sec.title }
            local list = movers[sec.key]
            if #list == 0 then
                rows[#rows + 1] = { kind = "empty" }
            else
                for _, entry in ipairs(list) do
                    rows[#rows + 1] = entry
                end
            end
        end

        t:Render(rows, function(row, entry)
            if entry.kind == "section" then
                t:Span(row, entry.title, GOLD)
                t:Tint(row, STYLE.headerBg)
                return
            end
            if entry.kind == "empty" then
                t:Span(row, "Nothing right now", DIM)
                return
            end

            local badge = MOVER_BADGE[entry.kind]
            t:Set(row, "badge", badge.text, badge.color)
            t:Set(row, "name", entry.name, BONE)
            if entry.kind == "convert" then
                RecipeTooltip(row.hit.name, entry.calc)
            else
                SourceTooltip(row.hit.name, entry.name, db.items[entry.name])
            end
            t:Set(row, "price",
                FormatMoney(entry.kind == "convert" and entry.profit or entry.price),
                entry.kind == "convert" and COLOR_LOW or WHITE)
            t:Set(row, "reason", entry.reason, DIM)

            local btn = row.buttons.act
            btn:SetScript("OnClick", nil)
            -- Secure attributes cannot be touched in combat, and a row from the pool may
            -- still carry the previous entry's spell. Disable rather than leave a Buy
            -- button pointing at someone else's craft.
            local locked = InCombatLockdown()
            if not locked then
                btn:SetAttribute("type", nil)
                btn:SetAttribute("spell", nil)
                btn:SetAttribute("item", nil)
            end
            btn:SetEnabled(not locked)
            if entry.kind == "convert" then
                btn:SetText("Convert")
                if not locked then
                    local attrType, attrValue = MAW:MoverConvertAction(entry.recipe)
                    btn:SetAttribute("type", attrType)
                    btn:SetAttribute(attrType, attrValue)
                    btn:RegisterForClicks(UseKeyDown() and "AnyDown" or "AnyUp")
                end
                Tooltip(btn, function()
                    local attrType, attrValue = MAW:MoverConvertAction(entry.recipe)
                    GameTooltip:AddLine(attrType == "item"
                        and ("Use " .. attrValue .. " (combines 10)") or ("Cast " .. attrValue))
                    GameTooltip:AddLine("One click makes one batch. Needs the recipe known and mats in bags.", 0.7, 0.7, 0.7)
                end)
            else
                if not locked then
                    btn:RegisterForClicks("AnyUp")
                end
                if entry.kind == "buy" then
                    btn:SetText("Buy")
                    btn:SetScript("OnClick", function() MAW:MoverBuy(entry.name) end)
                    Tooltip(btn, function()
                        GameTooltip:AddLine("Search the auction house for " .. entry.name)
                        GameTooltip:AddLine("Opens Browse with an exact search. You choose what to buy.", 0.7, 0.7, 0.7)
                    end)
                else
                    btn:SetText("List")
                    btn:SetScript("OnClick", function()
                        MAW:MoverList(entry.name, entry.itemID, entry.price)
                    end)
                    Tooltip(btn, function()
                        GameTooltip:AddLine("Put " .. entry.name .. " in the sell slot")
                        GameTooltip:AddLine("Fills start and buyout from today's price, undercut by 1c per unit. You press Create Auction.", 0.7, 0.7, 0.7)
                    end)
                end
            end
        end)
    end

    return view
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------

local BUILDERS = {
    materials = function(page) return BuildItemsPage(page, "material") end,
    products  = function(page) return BuildItemsPage(page, "product") end,
    stores    = BuildStoresPage,
    history   = BuildHistoryPage,
    recipes   = BuildRecipesPage,
    movers    = BuildMoversPage,
}

-- Create the main UI
function MAWUI:CreateUI()
    if mainFrame then
        return mainFrame
    end

    mainFrame = ICUI:Window("MalexisAuctionWatcherFrame", {
        style = STYLE,
        width = WINDOW_WIDTH,
        height = WINDOW_HEIGHT,
        title = windowTitle,
    })
    mainFrame:SetFrameLevel(100)

    -- Closing while docked in the auction house goes back to the Browse tab
    mainFrame:HookScript("OnHide", function(self)
        if self.docked and AuctionFrame and AuctionFrame:IsShown() and AuctionFrameTab1 then
            AuctionFrameTab1:Click()
        end
    end)

    local body = mainFrame.body

    local names = {}
    for i, t in ipairs(TABS) do names[i] = t.label end
    mainFrame.tabs = ICUI:TabStrip(body, {
        style = STYLE, names = names, top = -6, left = PAGE_INSET,
        width = 100, height = TAB_H,
        onSelect = function(_, index)
            currentTab = TABS[index].key
            MAWUI:RefreshData()
        end,
    })

    -- Control row under the tabs: scans, then sort, then the tab's own action
    local bar = Toolbar(body, { top = -36, left = PAGE_INSET, right = -PAGE_INSET, height = 24 })
    mainFrame.controlBar = bar

    local scanBtn = Button(bar, "Scan AH", 100, 24)
    scanBtn:SetScript("OnClick", function()
        local MAW = _G.MalexisAuctionWatcher
        if not MAW then return end
        if MAW:IsScanning() then
            MAW:CancelScan("stopped by user")
        else
            MAW:ScanAuctionHouse()
        end
    end)
    bar:Left(scanBtn)
    mainFrame.scanBtn = scanBtn

    local scanTabBtn = Button(bar, "Scan Tab", 120, 24)
    scanTabBtn:SetScript("OnClick", function()
        local MAW = _G.MalexisAuctionWatcher
        if not MAW then return end
        MAW:StartScan(MAW:GetTabItems(currentTab), "Scanning " .. currentTab)
    end)
    bar:Left(scanTabBtn)
    mainFrame.scanTabBtn = scanTabBtn

    -- Sort toggle for Materials/Products: by mover position or by your manual order
    local sortBtn = Button(bar, "Sort: Movers", 120, 24)
    sortBtn:SetScript("OnClick", function()
        local s = MalexisAuctionWatcherDB.settings
        s.sortMode = (SortMode() == "manual") and "movers" or "manual"
        MAWUI:RefreshData()
    end)
    Tooltip(sortBtn, function()
        GameTooltip:AddLine("Row order")
        GameTooltip:AddLine("Movers: materials cheapest-in-range first, products highest-in-range first. Items without a range go last.", 1, 1, 1)
        GameTooltip:AddLine("Manual: the order you set with the arrows.", 1, 1, 1)
    end)
    bar:Left(sortBtn)
    mainFrame.sortBtn = sortBtn

    -- The last slot is shared: Add Item on Materials/Products, Refresh elsewhere.
    local addBtn = Button(bar, "Add Item", 100, 24)
    addBtn:SetScript("OnClick", function()
        local itemType = currentTab == "materials" and "material" or "product"
        if _G.MalexisAuctionWatcherDialogs then
            _G.MalexisAuctionWatcherDialogs.ShowAddItemDialog(itemType)
        end
    end)
    bar:Left(addBtn)
    mainFrame.addBtn = addBtn

    local refreshBtn = Button(bar, "Refresh Counts", 130, 24)
    refreshBtn:SetPoint("LEFT", addBtn, "LEFT", 0, 0)
    refreshBtn:SetScript("OnClick", function() MAWUI:RefreshData() end)
    refreshBtn:Hide()
    mainFrame.refreshBtn = refreshBtn

    -- Character-specific mode, on the right where it cannot be mistaken for an action
    local charCheck = ICUI:CheckBox(bar, "Character-Specific Data",
        { style = STYLE, labelSide = "LEFT" })
    charCheck:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    charCheck:SetChecked(Setting("characterSpecific", false) and true or false)
    charCheck:SetScript("OnClick", function()
        local MAW = _G.MalexisAuctionWatcher
        if MAW then
            MAW:ToggleCharacterSpecific()
            MAWUI:RefreshData()
        end
    end)
    mainFrame.charCheckbox = charCheck

    -- One page per tab, all the same size; only the live one is shown.
    mainFrame.pages = {}
    for _, t in ipairs(TABS) do
        local page = CreateFrame("Frame", nil, body)
        page:SetPoint("TOPLEFT", PAGE_INSET, PAGE_TOP)
        page:SetPoint("BOTTOMRIGHT", -PAGE_INSET, 6)
        page:Hide()
        mainFrame.pages[t.key] = page
    end

    -- Reflect scan state on the button and the status line
    local function UpdateScanButton(done, total, current)
        local MAW = _G.MalexisAuctionWatcher
        if MAW and MAW:IsScanning() then
            scanBtn:SetText(string.format("Cancel (%d/%d)", done or 0, total or 0))
            mainFrame.status:SetText("Scanning: " .. (current or "..."))
            mainFrame.status:SetTextColor(1, 0.9, 0.5)
        else
            scanBtn:SetText("Scan AH")
            MAWUI:UpdateStatus()
        end
    end
    mainFrame.UpdateScanButton = UpdateScanButton

    -- Register callbacks with Core for MVC pattern
    if _G.MalexisAuctionWatcher then
        _G.MalexisAuctionWatcher:RegisterCallback("onScanComplete", function()
            MAWUI:RefreshData()
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

-- Status line: how long ago the last scan was, in the window header
function MAWUI:UpdateStatus()
    if not mainFrame or not mainFrame.status then return end
    local MAW = _G.MalexisAuctionWatcher
    local db = MAW and MAW:GetActiveDB()
    if db and db.lastScanTime then
        local age = ICUI:Age(time() - db.lastScanTime)
        mainFrame.status:SetText("Last scan: " .. (age == "now" and "just now" or (age .. " ago")))
        mainFrame.status:SetTextColor(0.5, 1.0, 0.5)
    else
        mainFrame.status:SetText("Last scan: never")
        mainFrame.status:SetTextColor(0.7, 0.7, 0.7)
    end
end

-- Refresh the data display
function MAWUI:RefreshData()
    if not mainFrame then
        return
    end

    self:UpdateStatus()
    mainFrame.charCheckbox:SetChecked(Setting("characterSpecific", false) and true or false)

    for i, t in ipairs(TABS) do
        mainFrame.tabs.buttons[i]:SetActive(t.key == currentTab)
        mainFrame.pages[t.key]:SetShown(t.key == currentTab)
    end

    -- Per-tab control bar
    local scanLabels = {
        materials = "Scan Materials", products = "Scan Products", stores = "Scan All",
        recipes = "Scan Recipes", history = "Scan Item", movers = "Scan All",
    }
    mainFrame.scanTabBtn:SetText(scanLabels[currentTab] or "Scan Tab")

    local onItems = (currentTab == "materials" or currentTab == "products")
    mainFrame.sortBtn:SetShown(onItems)
    if onItems then
        mainFrame.sortBtn:SetText(SortMode() == "manual" and "Sort: Manual" or "Sort: Movers")
    end
    mainFrame.addBtn:SetShown(onItems)
    if currentTab == "stores" then
        mainFrame.refreshBtn:SetText("Refresh Counts")
        mainFrame.refreshBtn:Show()
    elseif currentTab == "recipes" or currentTab == "movers" then
        mainFrame.refreshBtn:SetText("Refresh Table")
        mainFrame.refreshBtn:Show()
    else
        mainFrame.refreshBtn:Hide()
    end

    -- One window size for every tab. Docked in the auction house it follows the host.
    if mainFrame.docked and mainFrame.dockHost then
        local host = mainFrame.dockHost
        mainFrame:SetSize(math.max(WINDOW_WIDTH, host:GetWidth()), host:GetHeight())
    end

    local page = mainFrame.pages[currentTab]
    if not page then
        currentTab = "materials"
        return self:RefreshData()
    end
    if not page.view then
        page.view = BUILDERS[currentTab](page)
    end
    page.view:Refresh()
end

-- Open the window on the History tab, optionally for a specific item
function MAWUI:ShowHistory(name)
    if name and name ~= "" then
        local MAW = _G.MalexisAuctionWatcher
        local db = MAW:GetActiveDB()
        if db.items and db.items[name] then
            MAW:SetHistorySelection("item", name)
        elseif MAW:FindRecipe(name) then
            MAW:SetHistorySelection("recipe", name)
        else
            print("Malexis Auction Watcher: Not tracking " .. name)
        end
    end
    currentTab = "history"
    self:Show()
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
    mainFrame:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
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
