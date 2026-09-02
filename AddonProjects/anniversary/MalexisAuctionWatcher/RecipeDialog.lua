-- RecipeDialog.lua - Add a custom material -> product recipe
local addonName = "MalexisAuctionWatcher"
local MAWRecipeDialog = {}

local MAX_MATERIALS = 5
local frame = nil

-- Small item slot: accepts a dragged item, or a typed name
local function CreateItemPicker(parent, labelText, width)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width, 26)

    local slot = CreateFrame("Button", nil, holder)
    slot:SetSize(24, 24)
    slot:SetPoint("LEFT", holder, "LEFT", 0, 0)
    slot.bg = slot:CreateTexture(nil, "BACKGROUND")
    slot.bg:SetAllPoints()
    slot.bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetSize(22, 22)
    slot.icon:SetPoint("CENTER")
    slot.icon:Hide()

    local input = CreateFrame("EditBox", nil, holder, "InputBoxTemplate")
    input:SetSize(width - 34, 20)
    input:SetPoint("LEFT", slot, "RIGHT", 8, 0)
    input:SetAutoFocus(false)
    input:SetMaxLetters(60)

    if labelText then
        local label = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("BOTTOMLEFT", input, "TOPLEFT", 0, 2)
        label:SetText(labelText)
    end

    local function TakeCursorItem()
        local cursorType, _, itemLink = GetCursorInfo()
        if cursorType ~= "item" or not itemLink then
            return
        end
        local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemLink)
        if not itemName then
            itemName = itemLink:match("%[(.-)%]")
        end
        if itemName then
            holder.itemName = itemName
            holder.itemID = tonumber(itemLink:match("item:(%d+)"))
            input:SetText(itemName)
            if itemTexture then
                slot.icon:SetTexture(itemTexture)
                slot.icon:Show()
            end
            ClearCursor()
        end
    end
    slot:RegisterForDrag("LeftButton")
    slot:SetScript("OnReceiveDrag", TakeCursorItem)
    slot:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            TakeCursorItem()
        elseif button == "RightButton" then
            holder.itemName = nil
            holder.itemID = nil
            input:SetText("")
            slot.icon:Hide()
        end
    end)
    input:SetScript("OnReceiveDrag", TakeCursorItem)
    input:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            holder.itemName = nil
            holder.itemID = nil
            slot.icon:Hide()
        end
    end)

    holder.slot = slot
    holder.input = input
    function holder:GetItem()
        local name = self.itemName or strtrim(self.input:GetText() or "")
        if name == "" then
            return nil
        end
        return name, self.itemID
    end
    function holder:Reset()
        self.itemName = nil
        self.itemID = nil
        self.input:SetText("")
        self.slot.icon:Hide()
    end
    return holder
end

local function EnsureTracked(itemName, itemID, itemType)
    local MAW = _G.MalexisAuctionWatcher
    local db = MAW:GetActiveDB()
    if db.items[itemName] then
        return true
    end
    if itemID then
        return MAW:AddItemByID(itemName, itemID, itemType)
    end
    MAW:AddItem(itemName, itemType)
    return db.items[itemName] ~= nil
end

local function Build()
    frame = CreateFrame("Frame", "MAWRecipeDialog", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(420, 120 + MAX_MATERIALS * 32 + 80)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    table.insert(UISpecialFrames, "MAWRecipeDialog")

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("CENTER", frame.TitleBg, "CENTER", 5, 0)
    frame.title:SetText("Add Recipe")

    local y = -44
    frame.product = CreateItemPicker(frame, "Product (drag an item or type its name)", 300)
    frame.product:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, y)

    frame.productCount = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    frame.productCount:SetSize(40, 20)
    frame.productCount:SetPoint("LEFT", frame.product, "RIGHT", 12, 0)
    frame.productCount:SetAutoFocus(false)
    frame.productCount:SetNumeric(true)
    frame.productCount:SetText("1")
    local pcLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pcLabel:SetPoint("BOTTOMLEFT", frame.productCount, "TOPLEFT", 0, 2)
    pcLabel:SetText("Makes")

    y = y - 44
    local matsLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    matsLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, y)
    matsLabel:SetText("Materials (item and count per batch)")
    y = y - 22

    frame.materials = {}
    for i = 1, MAX_MATERIALS do
        local picker = CreateItemPicker(frame, nil, 300)
        picker:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, y)
        local count = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
        count:SetSize(40, 20)
        count:SetPoint("LEFT", picker, "RIGHT", 12, 0)
        count:SetAutoFocus(false)
        count:SetNumeric(true)
        frame.materials[i] = { picker = picker, count = count }
        y = y - 32
    end

    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.status:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 44)
    frame.status:SetWidth(380)
    frame.status:SetJustifyH("LEFT")
    frame.status:SetTextColor(1, 0.6, 0.6)

    local addBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    addBtn:SetSize(100, 22)
    addBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 14)
    addBtn:SetText("Add Recipe")
    addBtn:SetScript("OnClick", function() MAWRecipeDialog.Submit() end)

    local cancelBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    cancelBtn:SetSize(80, 22)
    cancelBtn:SetPoint("LEFT", addBtn, "RIGHT", 6, 0)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function() frame:Hide() end)
end

function MAWRecipeDialog.Submit()
    local MAW = _G.MalexisAuctionWatcher
    local productName, productID = frame.product:GetItem()
    if not productName then
        frame.status:SetText("Pick a product first.")
        return
    end
    local productCount = tonumber(frame.productCount:GetText()) or 1
    if productCount < 1 then productCount = 1 end

    local materials = {}
    for _, row in ipairs(frame.materials) do
        local name, id = row.picker:GetItem()
        local count = tonumber(row.count:GetText()) or 0
        if name and count > 0 then
            table.insert(materials, { item = name, count = count, id = id })
        elseif name then
            frame.status:SetText("Enter a count for " .. name .. ".")
            return
        end
    end
    if #materials == 0 then
        frame.status:SetText("Add at least one material with a count.")
        return
    end

    -- Track everything involved so prices can be scanned
    if not EnsureTracked(productName, productID, "product") then
        frame.status:SetText("Could not find item '" .. productName .. "'. Drag it from your bags instead.")
        return
    end
    for _, mat in ipairs(materials) do
        if not EnsureTracked(mat.item, mat.id, "material") then
            frame.status:SetText("Could not find item '" .. mat.item .. "'. Drag it from your bags instead.")
            return
        end
        mat.id = nil
    end

    local ok, err = MAW:AddRecipe({
        name = productName,
        product = productName,
        productCount = productCount,
        materials = materials,
    })
    if not ok then
        frame.status:SetText(err or "Could not add recipe.")
        return
    end
    print(addonName .. ": Added recipe for " .. productName)
    frame:Hide()
end

function MAWRecipeDialog.Show()
    if not frame then
        Build()
    end
    frame.product:Reset()
    frame.productCount:SetText("1")
    for _, row in ipairs(frame.materials) do
        row.picker:Reset()
        row.count:SetText("")
    end
    frame.status:SetText("")
    frame:Show()
    frame.product.input:SetFocus()
end


-- ===================== Gem cut picker =====================
local gemFrame = nil

local function BuildGemPicker()
    local MAW = _G.MalexisAuctionWatcher
    local raws = MAW:GetPresetRawGems()

    gemFrame = CreateFrame("Frame", "MAWGemPicker", UIParent, "BasicFrameTemplateWithInset")
    gemFrame:SetSize(560, 300)
    gemFrame:SetPoint("CENTER")
    gemFrame:SetFrameStrata("DIALOG")
    gemFrame:SetMovable(true)
    gemFrame:EnableMouse(true)
    gemFrame:RegisterForDrag("LeftButton")
    gemFrame:SetScript("OnDragStart", gemFrame.StartMoving)
    gemFrame:SetScript("OnDragStop", gemFrame.StopMovingOrSizing)
    table.insert(UISpecialFrames, "MAWGemPicker")

    gemFrame.title = gemFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    gemFrame.title:SetPoint("CENTER", gemFrame.TitleBg, "CENTER", 5, 0)
    gemFrame.title:SetText("Add Gem Cut Recipes (TBC Jewelcrafting)")

    local info = gemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    info:SetPoint("TOPLEFT", gemFrame, "TOPLEFT", 16, -32)
    info:SetWidth(520)
    info:SetJustifyH("LEFT")
    info:SetTextColor(0.7, 0.7, 0.7)
    info:SetText("Click a raw gem to add every cut made from it (1 raw -> 1 cut). Each column is a tier; the buttons at the bottom add a whole tier.")

    local tiers = { "uncommon", "rare", "epic" }
    local tierTitles = { uncommon = "Uncommon", rare = "Rare", epic = "Epic" }
    local colX = { uncommon = 16, rare = 196, epic = 376 }
    local rowY = { uncommon = 0, rare = 0, epic = 0 }

    for _, tier in ipairs(tiers) do
        local header = gemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header:SetPoint("TOPLEFT", gemFrame, "TOPLEFT", colX[tier], -68)
        header:SetText(tierTitles[tier])
    end

    local function Refresh()
        MAWRecipeDialog.RefreshGemCounts()
        if _G.MalexisAuctionWatcherUI then
            _G.MalexisAuctionWatcherUI:RefreshData()
        end
    end

    gemFrame.rawButtons = {}
    for _, raw in ipairs(raws) do
        local btn = CreateFrame("Button", nil, gemFrame, "UIPanelButtonTemplate")
        btn:SetSize(165, 22)
        btn:SetPoint("TOPLEFT", gemFrame, "TOPLEFT", colX[raw.tier], -88 - rowY[raw.tier] * 26)
        btn.raw = raw
        btn:SetScript("OnClick", function()
            MAW:AddGemPresets({ rawID = raw.id })
            Refresh()
        end)
        rowY[raw.tier] = rowY[raw.tier] + 1
        table.insert(gemFrame.rawButtons, btn)
    end

    local x = 16
    for _, tier in ipairs(tiers) do
        local btn = CreateFrame("Button", nil, gemFrame, "UIPanelButtonTemplate")
        btn:SetSize(120, 22)
        btn:SetPoint("BOTTOMLEFT", gemFrame, "BOTTOMLEFT", x, 14)
        btn:SetText("All " .. tierTitles[tier])
        btn:SetScript("OnClick", function()
            MAW:AddGemPresets({ tier = tier })
            Refresh()
        end)
        x = x + 126
    end

    local closeBtn = CreateFrame("Button", nil, gemFrame, "UIPanelButtonTemplate")
    closeBtn:SetSize(80, 22)
    closeBtn:SetPoint("BOTTOMRIGHT", gemFrame, "BOTTOMRIGHT", -16, 14)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() gemFrame:Hide() end)
end

-- Show "(n of m)" on each raw gem button so it is clear what is already added
function MAWRecipeDialog.RefreshGemCounts()
    if not gemFrame then return end
    local MAW = _G.MalexisAuctionWatcher
    local have = {}
    for _, r in ipairs(MAW:GetRecipes()) do
        have[r.product] = true
    end
    for _, btn in ipairs(gemFrame.rawButtons) do
        local total, done = 0, 0
        for _, g in ipairs(MAW.PRESET_TBC_GEMS) do
            if g.raw.id == btn.raw.id then
                total = total + 1
                local cutName = GetItemInfo(g.cut.id) or g.cut.name
                if have[cutName] then done = done + 1 end
            end
        end
        btn:SetText(string.format("%s (%d/%d)", btn.raw.name, done, total))
    end
end

function MAWRecipeDialog.ShowGemPicker()
    if not gemFrame then
        BuildGemPicker()
    end
    MAWRecipeDialog.RefreshGemCounts()
    gemFrame:Show()
end

_G.MalexisAuctionWatcherRecipeDialog = MAWRecipeDialog
