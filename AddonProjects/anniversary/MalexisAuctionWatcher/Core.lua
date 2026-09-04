-- MalexisAuctionWatcher Core - the table every other file hangs off, the saved
-- variables, and the slash commands.
--
-- This addon predates the namespace convention: files share the global
-- MalexisAuctionWatcher table, exported at the end of this file, rather than the
-- `local addonName, ns = ...` pair. LibICCore attaches to that table just the same, so
-- MAW.Print, MAW.db, MAW.Util and the rest are the same names the other addons use.
local addonName = "MalexisAuctionWatcher"
local VERSION = "1.20.0"
local Core = LibStub("LibICCore-1.0")
local MAW = {}

-- Mirrors settings.debug. Every other file reads this flag, so it is kept in step
-- rather than replaced.
MAW.debugMode = false

-- Callback registry for MVC pattern
MAW.callbacks = {
    onScanComplete = {},
    onScanProgress = {},
    onPriceAdded = {},
    onItemAdded = {},
    onItemRemoved = {}
}

-- Register a callback
function MAW:RegisterCallback(event, callback)
    if self.callbacks[event] then
        table.insert(self.callbacks[event], callback)
    end
end

-- Fire callbacks
function MAW:FireCallbacks(event, ...)
    if self.callbacks[event] then
        for _, callback in ipairs(self.callbacks[event]) do
            callback(...)
        end
    end
end

-- Format money in gold/silver/copper
function MAW:FormatMoney(copper)
    if not copper or copper == 0 then
        return "0c"
    end

    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local copperRemainder = copper % 100

    local str = ""
    if gold > 0 then
        str = str .. gold .. "g "
    end
    if silver > 0 then
        str = str .. silver .. "s "
    end
    if copperRemainder > 0 or str == "" then
        str = str .. copperRemainder .. "c"
    end

    return strtrim(str)
end

-- List all tracked items
function MAW:ListItems()
    local db = self:GetActiveDB()
    MAW.Print("Tracked items:")
    local count = 0
    for itemName, itemData in pairs(db.items) do
        local priceCount = #itemData.prices
        MAW.Print("  - " .. itemName .. " (" .. priceCount .. " prices recorded)")
        count = count + 1
    end
    if count == 0 then
        MAW.Print("  None")
    end
end

-- Show recent prices for an item
function MAW:ShowPrices(itemName, limit)
    if not itemName or itemName == "" then
        MAW.Print("Please specify an item name")
        return
    end

    local db = self:GetActiveDB()
    if not db.items[itemName] then
        MAW.Print("Not tracking " .. itemName)
        return
    end

    limit = limit or 10
    local prices = db.items[itemName].prices

    if #prices == 0 then
        MAW.Print("No prices recorded for " .. itemName)
        return
    end

    MAW.Print("Recent prices for " .. itemName .. ":")
    for i = 1, math.min(limit, #prices) do
        local entry = prices[i]

        -- Handle old format (just buyout) and new format (minBid + buyout)
        if entry.minBid then
            local buyoutStr = entry.buyout > 0 and self:FormatMoney(entry.buyout) or "no buyout"
            MAW.Printf("  %s: Bid %s (%s/ea), Buyout %s (%s/ea) [%dx]",
                entry.date,
                self:FormatMoney(entry.minBid),
                self:FormatMoney(entry.minBidPerUnit),
                buyoutStr,
                entry.buyoutPerUnit > 0 and self:FormatMoney(entry.buyoutPerUnit) or "n/a",
                entry.stackSize
            )
        else
            -- Old format compatibility
            MAW.Printf("  %s: %s (%dx, %s per unit)",
                entry.date,
                self:FormatMoney(entry.buyout or 0),
                entry.stackSize,
                self:FormatMoney(entry.pricePerUnit or 0)
            )
        end
    end
end

--------------------------------------------------------------------------------
-- Saved variables
--------------------------------------------------------------------------------

local SCHEMA = 2
local CHAR_SCHEMA = 1

-- Account-wide. windowScale is deliberately absent: the window shrinks to fit the
-- screen on its first open and stores what it chose, and a default of 1 here would
-- skip that and open oversized.
local Defaults = {
    items = {},
    cache = { bank = {}, auctionHouse = {}, recipes = {} },
    settings = {
        autoScan = false,
        maxEntries = 10,            -- price entries kept per item
        characterSpecific = false,  -- which of the two tables GetActiveDB hands back
        historyDays = 180,
        sources = {},
        enabled = true,
        outputFrame = 1,
        debug = false,
        minimap = { hide = false },
    },
}

-- This character's own items and caches, used when settings.characterSpecific is on.
local CharDefaults = {
    items = {},
    cache = { bank = {}, auctionHouse = {}, recipes = {} },
}

-- Keyed by the schema each step upgrades FROM. Every table saved before 1.20.0 has no
-- schema stamp and is treated as schema 1, so this runs once on each of them.
local Migrations = {
    -- 1.20.0 moved the minimap button onto LibDBIcon, which keeps its position as
    -- minimap.minimapPos (degrees) and its visibility as minimap.hide.
    [1] = function(db)
        local s = db.settings
        if not s then return end
        s.minimap = s.minimap or {}
        if s.minimapAngle ~= nil then
            s.minimap.minimapPos = s.minimapAngle
            s.minimapAngle = nil
        end
        if s.minimapHidden ~= nil then
            s.minimap.hide = s.minimapHidden and true or false
            s.minimapHidden = nil
        end
    end,
}

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

local HELP = {
    { "", "toggle the merchant price spreadsheet" },
    { "show | ui", "the same" },
    { "minimap", "show or hide the minimap button" },
    { "scale <percent>", "resize the window, 50 to 125, or drag its bottom-right corner" },
    { "history [item name]", "open the price history chart" },
    { "recipes", "open the material -> product profit table" },
    { "movers", "what to buy, convert, and list right now" },
    { "sources", "show or toggle the Auctionator and TSM price feeds" },
    { "retention <days>", "days of price history to keep" },
    { "ahcut <percent>", "auction house cut used for net values (default 5)" },
    { "scan", "scan the auction house for tracked items (merges into a running scan)" },
    { "scan stop", "cancel the running scan" },
    { "scan status", "show the scan state" },
    { "add <item name or link>", "add an item to track; shift-click an item to link it" },
    { "remove <item name>", "remove an item from tracking" },
    { "list", "list every tracked item" },
    { "prices <item name>", "recent prices for an item" },
    { "log [n]", "print the last n log lines" },
    { "test", "run the built-in checks" },
    { "debug", "toggle debug output" },
    { "out [n]", "print to ChatFrame n" },
    { "version", "addon and library versions" },
    { "help", "this list" },
}

local COMMANDS = {}

local function ToggleWindow()
    if MalexisAuctionWatcherUI then
        MalexisAuctionWatcherUI:Toggle()
    else
        MAW.Print("UI module not loaded")
    end
end
COMMANDS[""], COMMANDS.show, COMMANDS.ui = ToggleWindow, ToggleWindow, ToggleWindow

COMMANDS.scan = function(rest)
    local sub = rest:lower()
    if sub == "stop" or sub == "cancel" then
        if not MAW:CancelScan("stopped by user") then
            MAW.Print("No scan is running")
        end
    elseif sub == "status" then
        MAW.Print("Scan " .. MAW:ScanStatusText())
    else
        MAW:ScanAuctionHouse()
    end
end

COMMANDS.add = function(rest)
    -- A shift-clicked link carries the name in brackets.
    if rest:match("|H") then
        local linkItemName = rest:match("%[(.-)%]")
        MAW:AddItem(linkItemName or rest)
    else
        MAW:AddItem(rest)
    end
end

COMMANDS.remove = function(rest) MAW:RemoveItem(rest) end
COMMANDS.list = function() MAW:ListItems() end
COMMANDS.prices = function(rest) MAW:ShowPrices(rest) end

-- Over the library's default: the other files read MAW.debugMode, so both move.
COMMANDS.debug = function()
    MAW.db.settings.debug = not MAW.db.settings.debug
    MAW.debugMode = MAW.db.settings.debug
    MAW.Print("Debug mode " .. (MAW.debugMode and "enabled" or "disabled"))
end

COMMANDS.movers = function()
    if MalexisAuctionWatcherUI then MalexisAuctionWatcherUI:ShowTab("movers") end
end
COMMANDS.recipes = function()
    if MalexisAuctionWatcherUI then MalexisAuctionWatcherUI:ShowTab("recipes") end
end
COMMANDS.history = function(rest)
    if MalexisAuctionWatcherUI then
        MalexisAuctionWatcherUI:ShowHistory(rest ~= "" and rest or nil)
    end
end

COMMANDS.sources = function(rest)
    local which, state = rest:match("^(%S*)%s*(%S*)")
    which, state = (which or ""):lower(), (state or ""):lower()
    local keyMap = { atr = "auctionator", auctionator = "auctionator", tsm = "tsm" }
    if keyMap[which] and (state == "on" or state == "off") then
        MAW:SetSourceEnabled(keyMap[which], state == "on")
        MAW.Print(keyMap[which] .. " source " .. state)
    elseif which == "pull" then
        local only = keyMap[state] or nil
        MAW:PullExternalPrices("manual", only, true)
    else
        MAW.Print("Sources - " .. MAW:DescribeSources())
        MAW.Print("  /maw sources atr|tsm on|off   - toggle a source")
        MAW.Print("  /maw sources pull [atr|tsm]   - pull now and report per item")
    end
end

COMMANDS.ahcut = function(rest)
    if rest ~= "" and MAW:SetAHCutPercent(rest) then
        MAW.Print("Auction house cut set to " .. tonumber(rest) .. "% (faction AH is 5%, neutral AH is 15%)")
    else
        MAW.Printf("Auction house cut is %d%%. Use /maw ahcut <percent> (faction AH 5, neutral AH 15)",
            math.floor(MAW:GetAHCut() * 100 + 0.5))
    end
end

COMMANDS.retention = function(rest)
    local days = tonumber(rest)
    if days and days >= 7 then
        MAW.db.settings.historyDays = math.floor(days)
        MAW.Print("History retention set to " .. math.floor(days) .. " days")
    else
        MAW.Print("History retention is " .. MAW:GetHistoryDays() .. " days (use /maw retention <days>, min 7)")
    end
end

-- Over the library's: this window docks into the auction house, and the UI module
-- knows when a scale may not be applied.
COMMANDS.scale = function(rest)
    if not MalexisAuctionWatcherUI then
        MAW.Print("UI module not loaded")
        return
    end
    local pct = tonumber(rest)
    if pct then
        local applied, why = MalexisAuctionWatcherUI:SetScale(pct / 100)
        if applied then
            MAW.Printf("Window scale set to %d%%", applied * 100 + 0.5)
        else
            MAW.Print(why or "could not set the scale")
        end
    else
        MAW.Printf("Window scale is %d%%. Use /maw scale <percent> (50-125), or drag the "
            .. "grip in the bottom-right corner.", MalexisAuctionWatcherUI:GetScale() * 100 + 0.5)
    end
end

COMMANDS.minimap = function()
    if MAW.Minimap then MAW.Minimap.Toggle() end
end

-- Over the library's: this addon IS its price history. There is nothing here that
-- should be one typo away from gone.
COMMANDS.reset = function()
    MAW.Print("this addon keeps months of price history and has no reset command. "
        .. "To start over, close the game and delete "
        .. "WTF\\Account\\<account>\\SavedVariables\\MalexisAuctionWatcher.lua.")
end

--------------------------------------------------------------------------------
-- Attach
--------------------------------------------------------------------------------

Core:Attach(MAW, {
    name = addonName,
    prefix = "MalexisAuctionWatcher",
    version = VERSION,
    db = "MalexisAuctionWatcherDB",
    cdb = "MalexisAuctionWatcherCharDB",
    defaults = Defaults,
    charDefaults = CharDefaults,
    schema = SCHEMA,
    charSchema = CHAR_SCHEMA,
    migrations = Migrations,
    slash = { "/maw", "/malexisauctionwatcher" },
    slashKey = "MALEXISAUCTIONWATCHER",
    help = HELP,
    commands = COMMANDS,
    loadedHint = "Type /maw help for commands.",

    onLoad = function()
        MAW.debugMode = MAW.db.settings.debug and true or false

        -- Both repair in place and are safe to run every load, which is why they are
        -- not schema steps.
        if MAW.MigrateHistory then MAW:MigrateHistory() end
        if MAW.RepairGemPresetData then MAW:RepairGemPresetData() end

        if MAW.Minimap and MAW.Minimap.Init then MAW.Minimap.Init() end

        -- Auction house tab: the AH UI is load-on-demand, so create now if it is already in
        local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
        if isLoaded and isLoaded("Blizzard_AuctionUI") and MalexisAuctionWatcherAHTab then
            MalexisAuctionWatcherAHTab.Create()
        end
    end,
})

--------------------------------------------------------------------------------
-- Events that are this addon's own
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
eventFrame:RegisterEvent("AUCTION_HOUSE_CLOSED")
eventFrame:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
eventFrame:RegisterEvent("BANKFRAME_OPENED")
eventFrame:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
eventFrame:RegisterEvent("TRADE_SKILL_SHOW")
eventFrame:RegisterEvent("CRAFT_SHOW")
eventFrame:SetScript("OnUpdate", function(self, elapsed) MAW:OnUpdateHandler(self, elapsed) end)

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "Blizzard_AuctionUI" then
        -- Our own ADDON_LOADED is the library's; this one is the auction house arriving.
        if MalexisAuctionWatcherAHTab then
            MalexisAuctionWatcherAHTab.Create()
        end
    elseif event == "PLAYER_LOGIN" then
        -- Other addons are loaded by now; detect optional price sources
        if MAW.DetectSources then
            MAW:DetectSources()
            C_Timer.After(5, function() MAW:SchedulePull("login") end)
        end
    elseif event == "AUCTION_HOUSE_SHOW" then
        MAW.Debug("AUCTION_HOUSE_SHOW event fired")
        if MAW.SchedulePull then
            MAW:SchedulePull("ah_open")
        end
        -- Scan auction house listings cache
        C_Timer.After(0.5, function()
            MAW:ScanAuctionHouseCache()
        end)
        if MAW.db.settings.autoScan then
            C_Timer.After(1, function()
                MAW:ScanAuctionHouse()
            end)
        end
    elseif event == "AUCTION_ITEM_LIST_UPDATE" then
        MAW:OnAuctionListUpdate()
    elseif event == "AUCTION_HOUSE_CLOSED" then
        MAW:CancelScan("auction house closed")
    elseif event == "BANKFRAME_OPENED" then
        -- Scan bank contents when bank is opened
        C_Timer.After(0.5, function()
            MAW:ScanBankCache()
        end)
    elseif event == "PLAYERBANKSLOTS_CHANGED" then
        -- Rescan bank when items change
        C_Timer.After(0.1, function()
            MAW:ScanBankCache()
        end)
    elseif event == "TRADE_SKILL_SHOW" then
        -- Scan tradeskill recipes when profession window opens
        C_Timer.After(0.5, function()
            -- Get profession name from the tradeskill window title
            local professionName = TradeSkillFrame and TradeSkillFrame.titleText and TradeSkillFrame.titleText:GetText()
            if professionName then
                MAW:ScanProfessionRecipes(professionName)
            end
            -- The full book (reagents, counts, quality) through ICLibs, kept
            -- per character so recipes can be added without the window open.
            if MAW.ScanOpenBook then MAW:ScanOpenBook({ silent = true }) end
        end)
    elseif event == "CRAFT_SHOW" then
        -- Scan craft recipes when enchanting window opens
        C_Timer.After(0.5, function()
            local professionName = CraftFrame and CraftFrame.titleText and CraftFrame.titleText:GetText()
            if not professionName then
                professionName = "Enchanting"  -- Default for Enchanting
            end
            MAW:ScanProfessionRecipes(professionName)
        end)
    end
end)

-- Export MAW to global namespace for UI access
-- Note: Inventory and Profession functions are now in separate files (Inventory.lua, Professions.lua)
_G.MalexisAuctionWatcher = MAW
