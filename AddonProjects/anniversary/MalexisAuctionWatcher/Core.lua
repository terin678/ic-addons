-- MalexisAuctionWatcher Core - Main coordination and utilities
local addonName = "MalexisAuctionWatcher"
local VERSION = "1.19.0"
local MAW = {}

-- Debug mode flag
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
    print(addonName .. ": Tracked items:")
    local count = 0
    for itemName, itemData in pairs(db.items) do
        local priceCount = #itemData.prices
        print("  - " .. itemName .. " (" .. priceCount .. " prices recorded)")
        count = count + 1
    end
    if count == 0 then
        print("  None")
    end
end

-- Show recent prices for an item
function MAW:ShowPrices(itemName, limit)
    if not itemName or itemName == "" then
        print(addonName .. ": Please specify an item name")
        return
    end

    local db = self:GetActiveDB()
    if not db.items[itemName] then
        print(addonName .. ": Not tracking " .. itemName)
        return
    end

    limit = limit or 10
    local prices = db.items[itemName].prices

    if #prices == 0 then
        print(addonName .. ": No prices recorded for " .. itemName)
        return
    end

    print(addonName .. ": Recent prices for " .. itemName .. ":")
    for i = 1, math.min(limit, #prices) do
        local entry = prices[i]

        -- Handle old format (just buyout) and new format (minBid + buyout)
        if entry.minBid then
            local buyoutStr = entry.buyout > 0 and self:FormatMoney(entry.buyout) or "no buyout"
            print(string.format("  %s: Bid %s (%s/ea), Buyout %s (%s/ea) [%dx]",
                entry.date,
                self:FormatMoney(entry.minBid),
                self:FormatMoney(entry.minBidPerUnit),
                buyoutStr,
                entry.buyoutPerUnit > 0 and self:FormatMoney(entry.buyoutPerUnit) or "n/a",
                entry.stackSize
            ))
        else
            -- Old format compatibility
            print(string.format("  %s: %s (%dx, %s per unit)",
                entry.date,
                self:FormatMoney(entry.buyout or 0),
                entry.stackSize,
                self:FormatMoney(entry.pricePerUnit or 0)
            ))
        end
    end
end

-- Slash command handler
local function SlashCommandHandler(msg)
    local args = {}
    for word in msg:gmatch("%S+") do
        table.insert(args, word)
    end

    local command = args[1] and args[1]:lower() or ""

    if command == "scan" then
        local sub = args[2] and args[2]:lower()
        if sub == "stop" or sub == "cancel" then
            if not MAW:CancelScan("stopped by user") then
                print(addonName .. ": No scan is running")
            end
        elseif sub == "status" then
            print(addonName .. ": Scan " .. MAW:ScanStatusText())
        else
            MAW:ScanAuctionHouse()
        end
    elseif command == "add" then
        local itemName = table.concat(args, " ", 2)
        -- Check if it's an item link
        if itemName:match("|H") then
            local linkItemName = itemName:match("%[(.-)%]")
            if linkItemName then
                MAW:AddItem(linkItemName)
            else
                MAW:AddItem(itemName)
            end
        else
            MAW:AddItem(itemName)
        end
    elseif command == "remove" then
        local itemName = table.concat(args, " ", 2)
        MAW:RemoveItem(itemName)
    elseif command == "list" then
        MAW:ListItems()
    elseif command == "prices" then
        local itemName = table.concat(args, " ", 2)
        MAW:ShowPrices(itemName)
    elseif command == "debug" then
        MAW.debugMode = not MAW.debugMode
        print(addonName .. ": Debug mode " .. (MAW.debugMode and "enabled" or "disabled"))
    elseif command == "show" or command == "ui" then
        if MalexisAuctionWatcherUI then
            MalexisAuctionWatcherUI:Toggle()
        else
            print(addonName .. ": UI module not loaded")
        end
    elseif command == "movers" then
        if MalexisAuctionWatcherUI then
            MalexisAuctionWatcherUI:ShowTab("movers")
        end
    elseif command == "recipes" then
        if MalexisAuctionWatcherUI then
            MalexisAuctionWatcherUI:ShowTab("recipes")
        end
    elseif command == "history" then
        local itemName = table.concat(args, " ", 2)
        if MalexisAuctionWatcherUI then
            MalexisAuctionWatcherUI:ShowHistory(itemName ~= "" and itemName or nil)
        end
    elseif command == "sources" then
        local which = args[2] and args[2]:lower()
        local state = args[3] and args[3]:lower()
        local keyMap = { atr = "auctionator", auctionator = "auctionator", tsm = "tsm" }
        if which and keyMap[which] and (state == "on" or state == "off") then
            MAW:SetSourceEnabled(keyMap[which], state == "on")
            print(addonName .. ": " .. keyMap[which] .. " source " .. state)
        elseif which == "pull" then
            local only = state and keyMap[state] or nil
            MAW:PullExternalPrices("manual", only, true)
        else
            print(addonName .. ": Sources - " .. MAW:DescribeSources())
            print("  /maw sources atr|tsm on|off   - toggle a source")
            print("  /maw sources pull [atr|tsm]   - pull now and report per item")
        end
    elseif command == "ahcut" then
        local pct = args[2]
        if pct and MAW:SetAHCutPercent(pct) then
            print(addonName .. ": Auction house cut set to " .. tonumber(pct) .. "% (faction AH is 5%, neutral AH is 15%)")
        else
            print(string.format("%s: Auction house cut is %d%%. Use /maw ahcut <percent> (faction AH 5, neutral AH 15)", addonName, math.floor(MAW:GetAHCut() * 100 + 0.5)))
        end
    elseif command == "retention" then
        local days = tonumber(args[2])
        if days and days >= 7 then
            MalexisAuctionWatcherDB.settings.historyDays = math.floor(days)
            print(addonName .. ": History retention set to " .. math.floor(days) .. " days")
        else
            print(addonName .. ": History retention is " .. MAW:GetHistoryDays() .. " days (use /maw retention <days>, min 7)")
        end
    elseif command == "scale" then
        if not MalexisAuctionWatcherUI then
            print(addonName .. ": UI module not loaded")
        else
            local pct = tonumber(args[2])
            if pct then
                local applied, why = MalexisAuctionWatcherUI:SetScale(pct / 100)
                if applied then
                    print(string.format("%s: Window scale set to %d%%",
                        addonName, applied * 100 + 0.5))
                else
                    print(addonName .. ": " .. (why or "could not set the scale"))
                end
            else
                print(string.format("%s: Window scale is %d%%. Use /maw scale <percent> "
                    .. "(50-125), or drag the grip in the bottom-right corner.",
                    addonName, MalexisAuctionWatcherUI:GetScale() * 100 + 0.5))
            end
        end
    elseif command == "test" then
        MAW.Tests.Run()
    elseif command == "minimap" then
        if MalexisAuctionWatcherMinimap then
            MalexisAuctionWatcherMinimap:Toggle()
        end
    elseif command == "help" then
        print(addonName .. " Commands:")
        print("  /maw show (or /maw ui) - Toggle merchant price spreadsheet")
        print("  /maw minimap - Show/hide the minimap button")
        print("  /maw scale <percent> - Resize the window, 50 to 125 (or drag its bottom-right corner)")
        print("  /maw test - Run the built-in checks")
        print("  /maw history [item name] - Open the price history chart")
        print("  /maw recipes - Open the material -> product profit table")
        print("  /maw movers - What to buy, convert, and list right now")
        print("  /maw sources - Show/toggle Auctionator and TSM price feeds")
        print("  /maw retention <days> - Days of price history to keep")
        print("  /maw ahcut <percent> - Auction house cut used for net values (default 5)")
        print("  /maw scan - Scan auction house for tracked items (merges into a running scan)")
        print("  /maw scan stop - Cancel the running scan")
        print("  /maw scan status - Show scan state")
        print("  /maw add <item name or link> - Add an item to track")
        print("    Example: /maw add Black Lotus")
        print("    Or shift-click item then: /maw add [Item Link]")
        print("  /maw remove <item name> - Remove an item from tracking")
        print("  /maw list - List all tracked items")
        print("  /maw prices <item name> - Show recent prices for an item")
        print("  /maw debug - Toggle debug mode on/off")
        print("  /maw help - Show this help message")
    else
        print(addonName .. ": Use '/maw help' for commands")
    end
end


-- Event handler
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
    if event == "ADDON_LOADED" and arg1 == addonName then
        MAW:InitializeDB()
        print(addonName .. " v" .. VERSION .. " loaded. Type /maw help for commands.")

        -- Create minimap button
        if MalexisAuctionWatcherMinimap then
            MalexisAuctionWatcherMinimap:Create()
        end

        -- Auction house tab: the AH UI is load-on-demand, so create now if it is already in
        local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
        if isLoaded and isLoaded("Blizzard_AuctionUI") and MalexisAuctionWatcherAHTab then
            MalexisAuctionWatcherAHTab.Create()
        end
    elseif event == "ADDON_LOADED" and arg1 == "Blizzard_AuctionUI" then
        if MalexisAuctionWatcherAHTab then
            MalexisAuctionWatcherAHTab.Create()
        end

        -- Register slash commands
        SLASH_MALEXISAUCTIONWATCHER1 = "/maw"
        SLASH_MALEXISAUCTIONWATCHER2 = "/malexisauctionwatcher"
        SlashCmdList["MALEXISAUCTIONWATCHER"] = SlashCommandHandler
    elseif event == "PLAYER_LOGIN" then
        -- Other addons are loaded by now; detect optional price sources
        if MAW.DetectSources then
            MAW:DetectSources()
            C_Timer.After(5, function() MAW:SchedulePull("login") end)
        end
    elseif event == "AUCTION_HOUSE_SHOW" then
        if MAW.debugMode then
            print(addonName .. " [DEBUG]: AUCTION_HOUSE_SHOW event fired")
        end
        if MAW.SchedulePull then
            MAW:SchedulePull("ah_open")
        end
        -- Scan auction house listings cache
        C_Timer.After(0.5, function()
            MAW:ScanAuctionHouseCache()
        end)
        if MalexisAuctionWatcherDB.settings.autoScan then
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
