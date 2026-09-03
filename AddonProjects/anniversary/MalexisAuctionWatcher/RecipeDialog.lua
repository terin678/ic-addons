-- RecipeDialog.lua - Add a custom material -> product recipe
local addonName = "MalexisAuctionWatcher"
local MAWRecipeDialog = {}

-- Dialogs wear the same palette as the main window. The style is registered by name in
-- UI.lua, which loads later, so it is looked up when a dialog is actually built.
local ICUI = LibStub("LibICUI-1.0")
local STYLE_NAME = "MalexisAuctionWatcher"

-- UI.lua's DIM, repeated here because it is a file-local there: the grey for prose
-- and cells that are context rather than data. One name per file, so the dialogs
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
    frame = Window("MAWRecipeDialog", 420, 120 + MAX_MATERIALS * 32 + 80, "Add Recipe")

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

    local addBtn = Button(frame)
    addBtn:SetSize(100, 22)
    addBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 14)
    addBtn:SetText("Add Recipe")
    addBtn:SetScript("OnClick", function() MAWRecipeDialog.Submit() end)
    frame.addBtn = addBtn

    local cancelBtn = Button(frame)
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
        local vendor = (mat.id and MAW.VENDOR_MATS[mat.id]) or MAW:VendorMatByName(mat.item)
        if vendor then
            mat.vendor = vendor.price
        elseif not EnsureTracked(mat.item, mat.id, "material") then
            frame.status:SetText("Could not find item '" .. mat.item .. "'. Drag it from your bags instead.")
            return
        end
        mat.id = nil
    end

    local editing = frame.editing
    if editing then
        -- Keep the recipe's identity and notes; rename only if the name was just the old product
        local newName = editing.name
        if editing.name == editing.product and productName ~= editing.product then
            newName = productName
        end
        local ok, err = MAW:UpdateRecipe(editing.name, {
            name = newName,
            product = productName,
            productCount = productCount,
            materials = materials,
            skill = editing.skill,
            profession = editing.profession,
            color = editing.color,
            note = editing.note,
        })
        if not ok then
            frame.status:SetText(err or "Could not save recipe.")
            return
        end
        print(addonName .. ": Updated recipe " .. newName)
    else
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
    end
    frame.editing = nil
    frame:Hide()
end

local function ResetDialog()
    frame.editing = nil
    frame.title:SetText("Add Recipe")
    frame.addBtn:SetText("Add Recipe")
    frame.product:Reset()
    frame.productCount:SetText("1")
    for _, row in ipairs(frame.materials) do
        row.picker:Reset()
        row.count:SetText("")
    end
    frame.status:SetText("")
end

function MAWRecipeDialog.Show()
    if not frame then
        Build()
    end
    ResetDialog()
    frame:Show()
    frame.product.input:SetFocus()
end

-- Open the dialog pre-filled with an existing recipe; saving replaces it in place
function MAWRecipeDialog.ShowEdit(recipe)
    if not frame then
        Build()
    end
    ResetDialog()
    frame.editing = recipe
    frame.title:SetText("Edit Recipe")
    frame.addBtn:SetText("Save")

    local MAW = _G.MalexisAuctionWatcher
    local db = MAW:GetActiveDB()
    local function Fill(picker, name)
        picker.itemName = name
        local data = db.items[name]
        picker.itemID = data and data.itemID or nil
        picker.input:SetText(name)
        local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(picker.itemID or name)
        if tex then
            picker.slot.icon:SetTexture(tex)
            picker.slot.icon:Show()
        end
    end

    Fill(frame.product, recipe.product)
    frame.productCount:SetText(tostring(recipe.productCount or 1))
    for i, mat in ipairs(recipe.materials or {}) do
        local row = frame.materials[i]
        if row then
            Fill(row.picker, mat.item)
            row.count:SetText(tostring(mat.count))
        end
    end
    if #(recipe.materials or {}) > #frame.materials then
        frame.status:SetText("This recipe has more materials than the dialog can show; extra ones will be dropped on save.")
    elseif recipe.note then
        frame.status:SetText(recipe.note)
    end
    frame:Show()
end


-- ===================== Gem cut picker =====================
local gemFrame = nil

local function BuildGemPicker()
    local MAW = _G.MalexisAuctionWatcher
    local raws = MAW:GetPresetRawGems()

    gemFrame = Window("MAWGemPicker", 740, 300, "Add Gem Cut Recipes (TBC Jewelcrafting)")

    local info = gemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    info:SetPoint("TOPLEFT", gemFrame, "TOPLEFT", 16, -32)
    info:SetWidth(700)
    info:SetJustifyH("LEFT")
    info:SetTextColor(DIM.r, DIM.g, DIM.b)
    info:SetText("Click a raw gem to add every cut made from it (1 raw -> 1 cut). Each column is a tier; the buttons at the bottom add a whole tier.")

    local tiers = { "uncommon", "rare", "epic", "meta" }
    local tierTitles = { uncommon = "Uncommon", rare = "Rare", epic = "Epic", meta = "Meta" }
    local colX = { uncommon = 16, rare = 196, epic = 376, meta = 556 }
    local rowY = { uncommon = 0, rare = 0, epic = 0, meta = 0 }

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
        local btn = Button(gemFrame)
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
        local btn = Button(gemFrame)
        btn:SetSize(120, 22)
        btn:SetPoint("BOTTOMLEFT", gemFrame, "BOTTOMLEFT", x, 14)
        btn:SetText("All " .. tierTitles[tier])
        btn:SetScript("OnClick", function()
            MAW:AddGemPresets({ tier = tier })
            Refresh()
        end)
        x = x + 126
    end

    local closeBtn = Button(gemFrame)
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


-- ===================== Add from your recipe book =====================
-- Books are scanned by ICLibs whenever a profession window opens (Book.lua),
-- so this dialog works with the window closed. One book shows at a time.
local importFrame = nil
local IMPORT_ROWS = 14

local function QualityColor(row)
    local q = row.quality
    if q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] then
        return ITEM_QUALITY_COLORS[q].hex or "|cffffffff"
    end
    return "|cffffffff"
end

local function BuildImportDialog()
    importFrame = Window("MAWProfessionImport", 560, 110 + IMPORT_ROWS * 22 + 60,
        "Add from your recipe book")

    -- Which book is on display; cycles through every scanned profession.
    local bookBtn = Button(importFrame)
    bookBtn:SetSize(170, 22)
    bookBtn:SetPoint("TOPLEFT", importFrame, "TOPLEFT", 16, -32)
    bookBtn:SetText("Book: -")
    bookBtn:SetScript("OnClick", function()
        local MAW = _G.MalexisAuctionWatcher
        local names = MAW:GetBookNames()
        if #names == 0 then return end
        local idx = 1
        for i, n in ipairs(names) do if n == importFrame.line then idx = i end end
        importFrame.line = names[(idx % #names) + 1]
        MAWRecipeDialog.RefreshImport()
    end)
    importFrame.bookBtn = bookBtn

    local scanBtn = Button(importFrame)
    scanBtn:SetSize(130, 22)
    scanBtn:SetPoint("LEFT", bookBtn, "RIGHT", 6, 0)
    scanBtn:SetText("Scan open window")
    scanBtn:SetScript("OnClick", function()
        local MAW = _G.MalexisAuctionWatcher
        MAW:ScanOpenBook({ onDone = function(line)
            importFrame.line = line
            MAWRecipeDialog.RefreshImport()
        end })
    end)

    local search = CreateFrame("EditBox", nil, importFrame, "InputBoxTemplate")
    search:SetSize(170, 20)
    search:SetPoint("TOPRIGHT", importFrame, "TOPRIGHT", -20, -33)
    search:SetAutoFocus(false)
    search:SetMaxLetters(40)
    search:SetScript("OnTextChanged", function(self)
        importFrame.search = self:GetText():lower()
        MAWRecipeDialog.RefreshImport()
    end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local searchLbl = importFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLbl:SetPoint("RIGHT", search, "LEFT", -6, 0)
    searchLbl:SetText("Search")

    importFrame.info = importFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    importFrame.info:SetPoint("TOPLEFT", importFrame, "TOPLEFT", 16, -60)
    importFrame.info:SetWidth(520)
    importFrame.info:SetJustifyH("LEFT")
    -- At most two lines: the list underneath starts at a fixed offset, and prose
    -- that grew a third line would land on its first row.
    if importFrame.info.SetMaxLines then importFrame.info:SetMaxLines(2) end
    importFrame.info:SetTextColor(DIM.r, DIM.g, DIM.b)

    -- Reagents live in the hover tooltip, so the row stays one readable line.
    importFrame.table = ICUI:Table(importFrame, {
        style = STYLE_NAME,
        top = -92, left = 16, width = 500, height = IMPORT_ROWS * 22, rowHeight = 22,
        columns = {
            { key = "name", label = "Recipe", width = "flex", hit = true },
            { key = "header", label = "Category", width = 130 },
        },
        buttons = { { key = "add", label = "Add", width = 70 } },
    })

    local addAll = Button(importFrame)
    addAll:SetSize(120, 22)
    addAll:SetPoint("BOTTOMLEFT", importFrame, "BOTTOMLEFT", 16, 14)
    addAll:SetText("Add all shown")
    addAll:SetScript("OnClick", function()
        local MAW = _G.MalexisAuctionWatcher
        local added = 0
        for _, e in ipairs(importFrame.shown or {}) do
            if not e.have then
                local ok = MAW:ImportProfessionRecipe(e.entry, importFrame.line)
                if ok then added = added + 1 end
            end
        end
        print(string.format("%s: added %d recipes from your %s book", addonName, added, importFrame.line or "profession"))
        MAWRecipeDialog.RefreshImport()
        if _G.MalexisAuctionWatcherUI then _G.MalexisAuctionWatcherUI:RefreshData() end
    end)

    local closeBtn = Button(importFrame)
    closeBtn:SetSize(80, 22)
    closeBtn:SetPoint("BOTTOMRIGHT", importFrame, "BOTTOMRIGHT", -16, 14)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() importFrame:Hide() end)
end

function MAWRecipeDialog.RefreshImport()
    local MAW = _G.MalexisAuctionWatcher
    local names = MAW:GetBookNames()
    local line = importFrame.line
    if not line or not MAW:GetBook(line) then line = names[1] end
    importFrame.line = line

    importFrame.bookBtn:SetText("Book: " .. (line or "-"))

    local have = {}
    for _, r in ipairs(MAW:GetRecipes()) do have[r.name] = true end

    local rows = line and MAW:GetBookRows(line) or {}
    local book = line and MAW:GetBook(line)
    if not line then
        importFrame.info:SetText("No recipe book scanned yet on this character. Open a profession window and it is read automatically. Enchanting is not supported.")
    else
        -- Relative age from the shared helper, so a day-old book reads "1d" rather
        -- than a four-digit minute count. It says "now" for a fresh scan, which only
        -- reads right without the "ago".
        local age = book and book.scannedAt and ICUI:Age(time() - book.scannedAt) or nil
        local when = "never"
        if age == "now" then
            when = "just now"
        elseif age then
            when = age .. " ago"
        end
        importFrame.info:SetText(string.format("%s: %d recipes, scanned %s. Reagents and batch sizes come from your book; vials are vendor priced.%s",
            line, #rows, when,
            book and book.partial and " Some rows could not be read; scan again." or ""))
    end

    local needle = importFrame.search or ""
    local shown = {}
    for _, row in ipairs(rows) do
        local hay = ((row.name or "") .. " " .. (row.skillName or "") .. " " .. (row.header or "")):lower()
        if needle == "" or hay:find(needle, 1, true) then
            local entry = MAW:BookRowToImport(row)
            shown[#shown + 1] = { row = row, entry = entry, have = have[entry.name] }
        end
    end
    importFrame.shown = shown

    local t = importFrame.table
    t:Render(shown, function(row, s)
        local e, r = s.entry, s.row
        local matText = {}
        for _, m in ipairs(e.reagents) do table.insert(matText, m.count .. " " .. m.item) end

        t:Set(row, "name", string.format("%s%s|r%s", QualityColor(r), e.name,
            e.numMade > 1 and (" x" .. e.numMade) or ""))
        t:Set(row, "header", r.header or "", DIM)

        ICUI:Tooltip(row.hit.name, function()
            if r.link then GameTooltip:SetHyperlink(r.link) end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Reagents: " .. table.concat(matText, ", "), 0.8, 0.8, 0.8, true)
        end)

        local btn = row.buttons.add
        if s.have then
            btn:SetText("Added")
            btn:SetScript("OnClick", nil)
            btn:Disable()
        else
            btn:SetText("Add")
            btn:Enable()
            btn:SetScript("OnClick", function()
                local ok, err = MAW:ImportProfessionRecipe(e, line)
                if not ok then print(addonName .. ": " .. (err or "could not add")) end
                MAWRecipeDialog.RefreshImport()
                if _G.MalexisAuctionWatcherUI then _G.MalexisAuctionWatcherUI:RefreshData() end
            end)
        end
    end)
end

-- Book.lua calls this after every scan so an open dialog follows along.
function MAWRecipeDialog.OnBookScanned(line)
    if importFrame and importFrame:IsShown() then
        importFrame.line = line
        MAWRecipeDialog.RefreshImport()
    end
end

function MAWRecipeDialog.ShowProfessionImport()
    if not importFrame then
        BuildImportDialog()
    end
    -- A window open right now is the freshest source; read it first.
    local MAW = _G.MalexisAuctionWatcher
    local lib = LibStub and LibStub("LibICTradeSkill-1.0", true)
    if lib and lib:OpenLine() then
        MAW:ScanOpenBook({ silent = true, onDone = function(line) importFrame.line = line end })
    end
    MAWRecipeDialog.RefreshImport()
    importFrame:Show()
end

_G.MalexisAuctionWatcherRecipeDialog = MAWRecipeDialog
