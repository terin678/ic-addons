-- Dialogs.lua - Dialog windows for the addon
local addonName = "MalexisAuctionWatcher"
local MAWDialogs = {}

-- Dialogs wear the same palette as the main window. The style is registered by name in
-- UI.lua, which loads later, so it is looked up when a dialog is actually built.
local ICUI = LibStub("LibICUI-1.0")
local STYLE_NAME = "MalexisAuctionWatcher"

-- UI.lua's DIM, repeated here because it is a file-local there: the grey for prose
-- and labels that are context rather than data. One name per file, so the dialogs
-- and the main window cannot drift a shade apart again.
local DIM = { r = 0.68, g = 0.70, b = 0.74 }

local function Button(parent, text, w, h, opts)
    opts = opts or {}
    opts.style = STYLE_NAME
    return ICUI:Button(parent, text, w, h, opts)
end

local function Window(name, w, h, title)
    return ICUI:Window(name, { style = STYLE_NAME, width = w, height = h, title = title,
        status = false, strata = "DIALOG" })
end

-- Helper function to get all cached recipes organized by profession
local function GetCachedRecipes()
    if not _G.MalexisAuctionWatcher then
        return {}
    end

    local cachedRecipes = _G.MalexisAuctionWatcher:GetCachedRecipes()
    local organizedRecipes = {}

    -- Organize recipes by profession
    for professionName, recipeList in pairs(cachedRecipes) do
        organizedRecipes[professionName] = {}
        for _, recipeName in ipairs(recipeList) do
            table.insert(organizedRecipes[professionName], recipeName)
        end
    end

    return organizedRecipes
end

-- Custom Add Item frame
local addItemFrame = nil
function MAWDialogs.ShowAddItemDialog(itemType)
    -- Always recreate the frame to pick up newly cached recipes
    if addItemFrame then
        addItemFrame:Hide()
        addItemFrame = nil
    end

    -- Check if a profession window is currently open and scan it
    if _G.MalexisAuctionWatcher then
        local debugMode = _G.MalexisAuctionWatcher.debugMode

        if debugMode then
            print("MAW Debug: TradeSkillFrame exists:", TradeSkillFrame ~= nil)
            print("MAW Debug: CraftFrame exists:", CraftFrame ~= nil)
        end

        if TradeSkillFrame and TradeSkillFrame:IsVisible() then
            if debugMode then
                print("MAW Debug: TradeSkillFrame is visible")
            end
            -- Try multiple ways to get the profession name
            local professionName = nil
            if TradeSkillFrame.titleText then
                professionName = TradeSkillFrame.titleText:GetText()
                if debugMode then
                    print("MAW Debug: Got profession from titleText:", professionName)
                end
            end
            if not professionName and TradeSkillFrameTitleText then
                professionName = TradeSkillFrameTitleText:GetText()
                if debugMode then
                    print("MAW Debug: Got profession from TradeSkillFrameTitleText:", professionName)
                end
            end
            if not professionName then
                -- Fallback: just use a generic name
                professionName = "TradeSkill"
                if debugMode then
                    print("MAW Debug: Using fallback profession name")
                end
            end
            _G.MalexisAuctionWatcher:ScanProfessionRecipes(professionName)
        elseif CraftFrame and CraftFrame:IsVisible() then
            if debugMode then
                print("MAW Debug: CraftFrame is visible")
            end
            local professionName = "Enchanting"
            if CraftFrame.titleText then
                professionName = CraftFrame.titleText:GetText() or professionName
            elseif CraftFrameTitleText then
                professionName = CraftFrameTitleText:GetText() or professionName
            end
            if debugMode then
                print("MAW Debug: Scanning profession:", professionName)
            end
            _G.MalexisAuctionWatcher:ScanProfessionRecipes(professionName)
        else
            if debugMode then
                print("MAW Debug: No profession window detected as visible")
            end
        end
    end

    -- Create frame (made taller to accommodate recipe list)
    addItemFrame = Window("MAWAddItemFrame", 500, 450,
        "Add " .. (itemType == "product" and "Product" or "Material"))

    local yOffset = -35

    -- Item slot for drag-and-drop
    local itemSlot = CreateFrame("Button", nil, addItemFrame)
    itemSlot:SetSize(40, 40)
    itemSlot:SetPoint("TOP", addItemFrame, "TOP", 0, yOffset)

    -- Item slot background
    itemSlot.bg = itemSlot:CreateTexture(nil, "BACKGROUND")
    itemSlot.bg:SetAllPoints()
    itemSlot.bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)

    -- Item slot border
    itemSlot.border = itemSlot:CreateTexture(nil, "BORDER")
    itemSlot.border:SetAllPoints()
    itemSlot.border:SetTexture("Interface\\Buttons\\UI-SlotBackground")

    -- Item icon
    itemSlot.icon = itemSlot:CreateTexture(nil, "ARTWORK")
    itemSlot.icon:SetSize(36, 36)
    itemSlot.icon:SetPoint("CENTER")

    -- Store item info
    itemSlot.itemName = nil
    itemSlot.itemLink = nil

    -- Handle receiving items
    itemSlot:RegisterForDrag("LeftButton")
    itemSlot:SetScript("OnReceiveDrag", function(self)
        local cursorType, _, itemLink = GetCursorInfo()
        if cursorType == "item" then
            local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemLink)
            if itemName then
                self.itemName = itemName
                self.itemLink = itemLink
                self.icon:SetTexture(itemTexture)
                self.icon:Show()
                ClearCursor()
            end
        end
    end)

    itemSlot:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            local cursorType, _, itemLink = GetCursorInfo()
            if cursorType == "item" then
                local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemLink)
                if itemName then
                    self.itemName = itemName
                    self.itemLink = itemLink
                    self.icon:SetTexture(itemTexture)
                    self.icon:Show()
                    ClearCursor()
                end
            end
        elseif button == "RightButton" then
            -- Clear the slot
            self.itemName = nil
            self.itemLink = nil
            self.icon:SetTexture(nil)
            self.icon:Hide()
        end
    end)

    itemSlot.icon:Hide()
    addItemFrame.itemSlot = itemSlot

    -- Instruction text
    local instructionText = addItemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    instructionText:SetPoint("TOP", itemSlot, "BOTTOM", 0, -5)
    instructionText:SetText("Drag item here or enter name below")
    instructionText:SetTextColor(DIM.r, DIM.g, DIM.b)

    yOffset = yOffset - 75

    -- Item name input (alternative to drag-and-drop)
    local nameInput = CreateFrame("EditBox", nil, addItemFrame, "InputBoxTemplate")
    nameInput:SetSize(200, 20)
    nameInput:SetPoint("TOP", addItemFrame, "TOP", 0, yOffset)
    nameInput:SetAutoFocus(false)
    nameInput:SetMaxLetters(50)
    addItemFrame.nameInput = nameInput

    local nameLabel = addItemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameLabel:SetPoint("BOTTOMLEFT", nameInput, "TOPLEFT", 0, 2)
    nameLabel:SetText("Item Name:")

    yOffset = yOffset - 40

    -- Recipe list section
    local recipes = GetCachedRecipes()
    local hasRecipes = false
    for _ in pairs(recipes) do
        hasRecipes = true
        break
    end

    if hasRecipes then
        -- Profession recipes label
        local recipesLabel = addItemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        recipesLabel:SetPoint("TOP", addItemFrame, "TOP", 0, yOffset)
        recipesLabel:SetText("Known Recipes:")

        yOffset = yOffset - 20

        -- One list with a header that stays put, professions as section rows.
        -- pairs() has no order, so the professions are sorted before rendering.
        local profNames = {}
        for professionName in pairs(recipes) do profNames[#profNames + 1] = professionName end
        table.sort(profNames)

        local list = {}
        for _, professionName in ipairs(profNames) do
            list[#list + 1] = { section = professionName }
            for _, recipeName in ipairs(recipes[professionName]) do
                list[#list + 1] = { name = recipeName }
            end
        end

        local t = ICUI:Table(addItemFrame, {
            style = STYLE_NAME,
            -- Six whole 18px rows: a height that is not a multiple of rowHeight
            -- leaves the last row sliced off halfway down.
            top = yOffset, left = 30, width = 440, height = 108, rowHeight = 18,
            columns = { { key = "name", label = "Known recipe", width = "flex" } },
            onClick = function(_, item)
                if not item.name then return end
                itemSlot.itemName = item.name
                nameInput:SetText(item.name)
                -- The tenth return of GetItemInfo is the icon.
                local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(item.name)
                if texture then
                    itemSlot.icon:SetTexture(texture)
                    itemSlot.icon:Show()
                end
            end,
        })
        t:Render(list, function(row, item)
            if item.section then
                t:Span(row, item.section, ICUI.Brand.gold)
            else
                t:Set(row, "name", item.name)
            end
        end)

        yOffset = yOffset - 130
    else
        -- No profession recipes cached
        local noProfLabel = addItemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        noProfLabel:SetPoint("TOP", addItemFrame, "TOP", 0, yOffset)
        noProfLabel:SetText("(Open a profession window to cache recipes)")
        noProfLabel:SetTextColor(DIM.r, DIM.g, DIM.b)

        yOffset = yOffset - 25
    end

    -- Price section label
    local priceLabel = addItemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    priceLabel:SetPoint("TOP", addItemFrame, "TOP", 0, yOffset)
    priceLabel:SetText("Starting Prices (Optional):")

    yOffset = yOffset - 25

    -- Low price inputs
    local lowLabel = addItemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lowLabel:SetPoint("TOPLEFT", addItemFrame, "TOPLEFT", 20, yOffset)
    lowLabel:SetText("Low:")

    local lowGoldInput = CreateFrame("EditBox", nil, addItemFrame, "InputBoxTemplate")
    lowGoldInput:SetSize(40, 20)
    lowGoldInput:SetPoint("LEFT", lowLabel, "RIGHT", 5, 0)
    lowGoldInput:SetAutoFocus(false)
    lowGoldInput:SetNumeric(true)
    lowGoldInput:SetMaxLetters(6)

    local lowGoldSuffix = addItemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lowGoldSuffix:SetPoint("LEFT", lowGoldInput, "RIGHT", 2, 0)
    lowGoldSuffix:SetText("g")

    local lowSilverInput = CreateFrame("EditBox", nil, addItemFrame, "InputBoxTemplate")
    lowSilverInput:SetSize(40, 20)
    lowSilverInput:SetPoint("LEFT", lowGoldSuffix, "RIGHT", 5, 0)
    lowSilverInput:SetAutoFocus(false)
    lowSilverInput:SetNumeric(true)
    lowSilverInput:SetMaxLetters(2)

    local lowSilverSuffix = addItemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lowSilverSuffix:SetPoint("LEFT", lowSilverInput, "RIGHT", 2, 0)
    lowSilverSuffix:SetText("s")

    local lowCopperInput = CreateFrame("EditBox", nil, addItemFrame, "InputBoxTemplate")
    lowCopperInput:SetSize(40, 20)
    lowCopperInput:SetPoint("LEFT", lowSilverSuffix, "RIGHT", 5, 0)
    lowCopperInput:SetAutoFocus(false)
    lowCopperInput:SetNumeric(true)
    lowCopperInput:SetMaxLetters(2)

    local lowCopperSuffix = addItemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lowCopperSuffix:SetPoint("LEFT", lowCopperInput, "RIGHT", 2, 0)
    lowCopperSuffix:SetText("c")

    yOffset = yOffset - 25

    -- High price inputs
    local highLabel = addItemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    highLabel:SetPoint("TOPLEFT", addItemFrame, "TOPLEFT", 20, yOffset)
    highLabel:SetText("High:")

    local highGoldInput = CreateFrame("EditBox", nil, addItemFrame, "InputBoxTemplate")
    highGoldInput:SetSize(40, 20)
    highGoldInput:SetPoint("LEFT", highLabel, "RIGHT", 5, 0)
    highGoldInput:SetAutoFocus(false)
    highGoldInput:SetNumeric(true)
    highGoldInput:SetMaxLetters(6)

    local highGoldSuffix = addItemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    highGoldSuffix:SetPoint("LEFT", highGoldInput, "RIGHT", 2, 0)
    highGoldSuffix:SetText("g")

    local highSilverInput = CreateFrame("EditBox", nil, addItemFrame, "InputBoxTemplate")
    highSilverInput:SetSize(40, 20)
    highSilverInput:SetPoint("LEFT", highGoldSuffix, "RIGHT", 5, 0)
    highSilverInput:SetAutoFocus(false)
    highSilverInput:SetNumeric(true)
    highSilverInput:SetMaxLetters(2)

    local highSilverSuffix = addItemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    highSilverSuffix:SetPoint("LEFT", highSilverInput, "RIGHT", 2, 0)
    highSilverSuffix:SetText("s")

    local highCopperInput = CreateFrame("EditBox", nil, addItemFrame, "InputBoxTemplate")
    highCopperInput:SetSize(40, 20)
    highCopperInput:SetPoint("LEFT", highSilverSuffix, "RIGHT", 5, 0)
    highCopperInput:SetAutoFocus(false)
    highCopperInput:SetNumeric(true)
    highCopperInput:SetMaxLetters(2)

    local highCopperSuffix = addItemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    highCopperSuffix:SetPoint("LEFT", highCopperInput, "RIGHT", 2, 0)
    highCopperSuffix:SetText("c")

    -- Add button
    local addBtn = Button(addItemFrame)
    addBtn:SetSize(80, 22)
    addBtn:SetPoint("BOTTOMLEFT", addItemFrame, "BOTTOMLEFT", 15, 15)
    addBtn:SetText("Add")
    addBtn:SetScript("OnClick", function()
        -- Get item name from slot or text input
        local itemName = itemSlot.itemName or nameInput:GetText()

        if not itemName or itemName == "" then
            print("Malexis Auction Watcher: Please specify an item")
            return
        end

        -- Add the item
        if _G.MalexisAuctionWatcher then
            -- Calculate custom prices first
            local lowGold = tonumber(lowGoldInput:GetText()) or 0
            local lowSilver = tonumber(lowSilverInput:GetText()) or 0
            local lowCopper = tonumber(lowCopperInput:GetText()) or 0
            local lowTotal = (lowGold * 10000) + (lowSilver * 100) + lowCopper

            local highGold = tonumber(highGoldInput:GetText()) or 0
            local highSilver = tonumber(highSilverInput:GetText()) or 0
            local highCopper = tonumber(highCopperInput:GetText()) or 0
            local highTotal = (highGold * 10000) + (highSilver * 100) + highCopper

            -- Add the item
            local MAW = _G.MalexisAuctionWatcher
            MAW:AddItem(itemName, itemType)

            -- Set custom prices if provided (after item is added)
            local db = MAW:GetActiveDB()
            if db.items[itemName] then
                local pricesSet = false
                if lowTotal > 0 then
                    db.items[itemName].customLow = lowTotal
                    pricesSet = true
                end
                if highTotal > 0 then
                    db.items[itemName].customHigh = highTotal
                    pricesSet = true
                end

                -- Force a refresh if prices were set to show them immediately
                if pricesSet and _G.MalexisAuctionWatcherUI then
                    _G.MalexisAuctionWatcherUI:RefreshData()
                end
            end

            addItemFrame:Hide()
        end
    end)

    -- Cancel button
    local cancelBtn = Button(addItemFrame)
    cancelBtn:SetSize(80, 22)
    cancelBtn:SetPoint("LEFT", addBtn, "RIGHT", 5, 0)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function()
        addItemFrame:Hide()
    end)

    nameInput:SetFocus()
    addItemFrame:Show()
end

-- Custom price input frame
local priceInputFrame = nil
function MAWDialogs.ShowPriceInputDialog(itemName, priceType)
    if priceInputFrame then
        priceInputFrame:Hide()
    end

    -- Create frame
    priceInputFrame = Window("MAWPriceInputFrame", 280, 140, "Set " .. priceType .. " Price")

    local yOffset = -35

    -- Item name label
    local itemLabel = priceInputFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemLabel:SetPoint("TOP", priceInputFrame, "TOP", 0, yOffset)
    itemLabel:SetText(itemName)
    yOffset = yOffset - 30

    -- Gold input
    local goldInput = CreateFrame("EditBox", nil, priceInputFrame, "InputBoxTemplate")
    goldInput:SetSize(50, 20)
    goldInput:SetPoint("TOP", priceInputFrame, "TOP", -80, yOffset)
    goldInput:SetAutoFocus(false)
    goldInput:SetNumeric(true)
    goldInput:SetMaxLetters(6)
    priceInputFrame.goldInput = goldInput

    local goldSuffix = priceInputFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    goldSuffix:SetPoint("LEFT", goldInput, "RIGHT", 3, 0)
    goldSuffix:SetText("g")

    -- Silver input
    local silverInput = CreateFrame("EditBox", nil, priceInputFrame, "InputBoxTemplate")
    silverInput:SetSize(50, 20)
    silverInput:SetPoint("TOP", priceInputFrame, "TOP", 0, yOffset)
    silverInput:SetAutoFocus(false)
    silverInput:SetNumeric(true)
    silverInput:SetMaxLetters(2)
    priceInputFrame.silverInput = silverInput

    local silverSuffix = priceInputFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    silverSuffix:SetPoint("LEFT", silverInput, "RIGHT", 3, 0)
    silverSuffix:SetText("s")

    -- Copper input
    local copperInput = CreateFrame("EditBox", nil, priceInputFrame, "InputBoxTemplate")
    copperInput:SetSize(50, 20)
    copperInput:SetPoint("TOP", priceInputFrame, "TOP", 80, yOffset)
    copperInput:SetAutoFocus(false)
    copperInput:SetNumeric(true)
    copperInput:SetMaxLetters(2)
    priceInputFrame.copperInput = copperInput

    local copperSuffix = priceInputFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    copperSuffix:SetPoint("LEFT", copperInput, "RIGHT", 3, 0)
    copperSuffix:SetText("c")

    yOffset = yOffset - 35

    -- Set button
    local setBtn = Button(priceInputFrame)
    setBtn:SetSize(80, 22)
    setBtn:SetPoint("BOTTOMLEFT", priceInputFrame, "BOTTOMLEFT", 15, 15)
    setBtn:SetText("Set")
    setBtn:SetScript("OnClick", function()
        local gold = tonumber(goldInput:GetText()) or 0
        local silver = tonumber(silverInput:GetText()) or 0
        local copper = tonumber(copperInput:GetText()) or 0

        local totalCopper = (gold * 10000) + (silver * 100) + copper

        if totalCopper > 0 then
            local MAW = _G.MalexisAuctionWatcher
            local db = MAW:GetActiveDB()
            local item = db.items and db.items[itemName]
            if not item then
                print("Malexis Auction Watcher: no longer tracking " .. itemName)
                priceInputFrame:Hide()
                return
            end
            if priceType == "LOW" then
                item.customLow = totalCopper
            else
                item.customHigh = totalCopper
            end
            if _G.MalexisAuctionWatcherUI then
                _G.MalexisAuctionWatcherUI:RefreshData()
            end
            priceInputFrame:Hide()
        else
            print("Price must be greater than 0")
        end
    end)

    -- Clear button
    local clearBtn = Button(priceInputFrame)
    clearBtn:SetSize(80, 22)
    clearBtn:SetPoint("LEFT", setBtn, "RIGHT", 5, 0)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        local MAW = _G.MalexisAuctionWatcher
        local db = MAW:GetActiveDB()
        local item = db.items and db.items[itemName]
        if item then
            if priceType == "LOW" then
                item.customLow = nil
            else
                item.customHigh = nil
            end
        end
        if _G.MalexisAuctionWatcherUI then
            _G.MalexisAuctionWatcherUI:RefreshData()
        end
        priceInputFrame:Hide()
    end)

    -- Cancel button
    local cancelBtn = Button(priceInputFrame)
    cancelBtn:SetSize(80, 22)
    cancelBtn:SetPoint("LEFT", clearBtn, "RIGHT", 5, 0)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function()
        priceInputFrame:Hide()
    end)

    -- Pre-fill with current value if exists
    local MAW = _G.MalexisAuctionWatcher
    local db = MAW:GetActiveDB()
    local item = db.items and db.items[itemName] or {}
    local currentValue = nil
    if priceType == "LOW" and item.customLow then
        currentValue = item.customLow
    elseif priceType == "HIGH" and item.customHigh then
        currentValue = item.customHigh
    elseif MAW.GetPriceBounds then
        -- No custom value: start from the bound in effect (TSM-derived or scan-derived)
        local low, high = MAW:GetPriceBounds(itemName)
        currentValue = (priceType == "LOW") and low or high
    end

    if currentValue and currentValue > 0 then
        local g = math.floor(currentValue / 10000)
        local s = math.floor((currentValue % 10000) / 100)
        local c = currentValue % 100
        goldInput:SetText(g > 0 and tostring(g) or "")
        silverInput:SetText(s > 0 and tostring(s) or "")
        copperInput:SetText(c > 0 and tostring(c) or "")
    end

    goldInput:SetFocus()
    priceInputFrame:Show()
end

-- Show copy data confirmation dialog
function MAWDialogs.ShowCopyDataDialog()
    local MAW = _G.MalexisAuctionWatcher
    if not MAW then return end

    -- Create frame
    local copyFrame = Window("MAWCopyDataDialog", 400, 180, "Copy Account Data?")

    -- Message text
    local accountItemCount = MAW:CountItems(MalexisAuctionWatcherDB.items or {})
    local messageText = copyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    messageText:SetPoint("TOP", copyFrame, "TOP", 0, -40)
    messageText:SetWidth(360)
    messageText:SetJustifyH("CENTER")
    messageText:SetText(string.format("You've enabled character-specific mode.\n\nWould you like to copy your account-wide data\n(%d items) to this character?", accountItemCount))

    local infoText = copyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoText:SetPoint("TOP", messageText, "BOTTOM", 0, -10)
    infoText:SetWidth(360)
    infoText:SetJustifyH("CENTER")
    infoText:SetTextColor(DIM.r, DIM.g, DIM.b)
    infoText:SetText("(Your account-wide data will remain unchanged)")

    -- Copy button
    local copyBtn = Button(copyFrame)
    copyBtn:SetSize(120, 25)
    copyBtn:SetPoint("BOTTOM", copyFrame, "BOTTOM", -65, 15)
    copyBtn:SetText("Copy Data")
    copyBtn:SetScript("OnClick", function()
        MAW:CopyAccountDataToCharacter()
        copyFrame:Hide()
        -- Refresh UI to show the copied data
        if _G.MalexisAuctionWatcherUI then
            _G.MalexisAuctionWatcherUI:RefreshData()
        end
    end)

    -- Start Fresh button
    local freshBtn = Button(copyFrame)
    freshBtn:SetSize(120, 25)
    freshBtn:SetPoint("BOTTOM", copyFrame, "BOTTOM", 65, 15)
    freshBtn:SetText("Start Fresh")
    freshBtn:SetScript("OnClick", function()
        print(addonName .. ": Starting with empty character-specific data")
        copyFrame:Hide()
        -- Refresh UI to show the empty character data
        if _G.MalexisAuctionWatcherUI then
            _G.MalexisAuctionWatcherUI:RefreshData()
        end
    end)

    -- Close on escape
    copyFrame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            copyFrame:Hide()
        end
    end)
    copyFrame:SetPropagateKeyboardInput(true)

    copyFrame:Show()
end

-- Export to global namespace
_G.MalexisAuctionWatcherDialogs = MAWDialogs
