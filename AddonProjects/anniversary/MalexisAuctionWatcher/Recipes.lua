-- Recipes.lua - Material -> product conversions and profit math
local addonName = "MalexisAuctionWatcher"
local MAW = _G.MalexisAuctionWatcher or {}

local DEFAULT_AH_CUT = 0.05  -- faction auction houses take 5%; neutral ones 15%

-- Auction house cut as a fraction (0.15 = 15%)
function MAW:GetAHCut()
    local s = MalexisAuctionWatcherDB and MalexisAuctionWatcherDB.settings
    local cut = s and s.ahCut
    if type(cut) ~= "number" or cut < 0 or cut > 0.5 then
        return DEFAULT_AH_CUT
    end
    return cut
end

function MAW:SetAHCutPercent(percent)
    local p = tonumber(percent)
    if not p or p < 0 or p > 50 then
        return false
    end
    MalexisAuctionWatcherDB.settings.ahCut = p / 100
    self:FireCallbacks("onItemAdded")
    return true
end

-- Built-in preset: 10 motes -> 1 primal (no profession required)
MAW.PRESET_MOTES_TO_PRIMALS = {
    { mote = { name = "Mote of Air",    id = 22572 }, primal = { name = "Primal Air",    id = 22451 } },
    { mote = { name = "Mote of Earth",  id = 22573 }, primal = { name = "Primal Earth",  id = 22452 } },
    { mote = { name = "Mote of Fire",   id = 22574 }, primal = { name = "Primal Fire",   id = 21884 } },
    { mote = { name = "Mote of Life",   id = 22575 }, primal = { name = "Primal Life",   id = 21886 } },
    { mote = { name = "Mote of Mana",   id = 22576 }, primal = { name = "Primal Mana",   id = 22457 } },
    { mote = { name = "Mote of Shadow", id = 22577 }, primal = { name = "Primal Shadow", id = 22456 } },
    { mote = { name = "Mote of Water",  id = 22578 }, primal = { name = "Primal Water",  id = 21885 } },
}

function MAW:GetRecipes()
    local db = self:GetActiveDB()
    db.recipes = db.recipes or {}
    return db.recipes
end

-- Track an item when we already know its ID (so the item cache doesn't matter)
function MAW:AddItemByID(itemName, itemID, itemType)
    local db = self:GetActiveDB()
    if db.items[itemName] then
        return false
    end
    local maxOrder = 0
    for _, itemData in pairs(db.items) do
        if itemData.order and itemData.order > maxOrder then
            maxOrder = itemData.order
        end
    end
    db.items[itemName] = {
        itemID = itemID,
        itemType = itemType or "material",
        prices = {},
        order = maxOrder + 1,
    }
    self:FireCallbacks("onItemAdded", itemName)
    return true
end

-- Price bases for recipe math
MAW.PRICE_BASES = {
    { key = "latest", label = "Latest",  short = "Latest" },
    { key = "tsm14",  label = "TSM 14d", short = "TSM14", tsmKey = "market" },
    { key = "tsm60",  label = "TSM 60d", short = "TSM60", tsmKey = "historical" },
}

function MAW:PriceBasisDef(key)
    for _, b in ipairs(self.PRICE_BASES) do
        if b.key == key then return b end
    end
    return self.PRICE_BASES[1]
end

-- Per-unit price for a tracked item under a basis ("latest", "tsm14", "tsm60"), with the
-- source and time it came from. TSM bases fall back to the latest price when TSM has no
-- value for the item. Falls back to custom bounds when there are no observations at all.
function MAW:GetUnitPrice(itemName, basis)
    local db = self:GetActiveDB()
    local itemData = db.items[itemName]
    if not itemData then
        return nil
    end
    local def = self:PriceBasisDef(basis)
    if def.tsmKey then
        local ref = itemData.tsmRef
        local value = ref and ref[def.tsmKey]
        if value and value > 0 then
            return value, def.key, ref.time and date("%Y-%m-%d %H:%M", ref.time) or nil
        end
    end
    local latest = itemData.prices and itemData.prices[1]
    if latest then
        local unit = (latest.buyoutPerUnit and latest.buyoutPerUnit > 0) and latest.buyoutPerUnit
            or latest.minBidPerUnit or latest.pricePerUnit
        if unit and unit > 0 then
            return unit, latest.source or "scan", latest.date
        end
    end
    if itemData.customLow and itemData.customHigh then
        return (itemData.customLow + itemData.customHigh) / 2, "custom", nil
    elseif itemData.customLow or itemData.customHigh then
        return itemData.customLow or itemData.customHigh, "custom", nil
    end
    return nil
end

-- recipe = { name, product = itemName, productCount = n, materials = { {item = name, count = n}, ... } }
function MAW:AddRecipe(recipe)
    if not recipe or not recipe.product or not recipe.materials or #recipe.materials == 0 then
        return false, "recipe needs a product and at least one material"
    end
    recipe.productCount = recipe.productCount or 1
    recipe.name = recipe.name or recipe.product

    local recipes = self:GetRecipes()
    for _, existing in ipairs(recipes) do
        if existing.name == recipe.name then
            return false, "a recipe named " .. recipe.name .. " already exists"
        end
    end
    table.insert(recipes, recipe)
    self:FireCallbacks("onItemAdded")
    return true
end

function MAW:RemoveRecipe(name)
    local recipes = self:GetRecipes()
    for i, r in ipairs(recipes) do
        if r.name == name then
            table.remove(recipes, i)
            self:FireCallbacks("onItemRemoved")
            return true
        end
    end
    return false
end

-- Add the Motes -> Primals preset, tracking motes as materials and primals as products
function MAW:AddMotePresets()
    local added, tracked = 0, 0
    for _, pair in ipairs(self.PRESET_MOTES_TO_PRIMALS) do
        if self:AddItemByID(pair.mote.name, pair.mote.id, "material") then tracked = tracked + 1 end
        if self:AddItemByID(pair.primal.name, pair.primal.id, "product") then tracked = tracked + 1 end
        local ok = self:AddRecipe({
            name = pair.mote.name .. " -> " .. pair.primal.name,
            product = pair.primal.name,
            productCount = 1,
            materials = { { item = pair.mote.name, count = 10 } },
        })
        if ok then added = added + 1 end
    end
    print(string.format("%s: Added %d recipes and started tracking %d items", addonName, added, tracked))
    return added
end

-- Built-in preset: Alchemy transmute, 1 each of five primals -> 1 Primal Might (skill 350, daily cooldown)
MAW.PRESET_PRIMAL_MIGHT = {
    product = { name = "Primal Might", id = 23571 },
    materials = {
        { name = "Primal Earth", id = 22452 },
        { name = "Primal Water", id = 21885 },
        { name = "Primal Air",   id = 22451 },
        { name = "Primal Fire",  id = 21884 },
        { name = "Primal Mana",  id = 22457 },
    },
}

function MAW:AddPrimalMightPreset()
    local p = self.PRESET_PRIMAL_MIGHT
    local tracked = 0
    local mats = {}
    for _, m in ipairs(p.materials) do
        if self:AddItemByID(m.name, m.id, "material") then tracked = tracked + 1 end
        table.insert(mats, { item = m.name, count = 1 })
    end
    if self:AddItemByID(p.product.name, p.product.id, "product") then tracked = tracked + 1 end
    local ok, err = self:AddRecipe({
        name = "Transmute: Primal Might",
        product = p.product.name,
        productCount = 1,
        materials = mats,
        skill = 350,
        profession = "Alchemy",
        note = "Transmute has a daily cooldown",
    })
    if ok then
        print(string.format("%s: Added Primal Might transmute and started tracking %d items", addonName, tracked))
    else
        print(addonName .. ": " .. (err or "could not add recipe"))
    end
    return ok
end

-- Compute the economics of one recipe under a price basis (default "latest").
-- Returns a table; fields are nil when a price is missing and `missing` lists the item names.
function MAW:ComputeRecipeProfit(recipe, basis)
    basis = basis or "latest"
    local result = {
        recipe = recipe,
        basis = basis,
        matCost = 0,
        missing = {},
        materials = {},
        canMake = nil,
    }

    local complete = true
    for _, mat in ipairs(recipe.materials) do
        local unit, source, when
        if mat.vendor then
            unit, source = mat.vendor, "vendor"
        else
            unit, source, when = self:GetUnitPrice(mat.item, basis)
        end
        local lineCost = unit and unit * mat.count or nil
        table.insert(result.materials, { item = mat.item, count = mat.count, unit = unit, cost = lineCost, source = source, when = when, vendor = mat.vendor })
        if unit then
            result.matCost = result.matCost + lineCost
        else
            complete = false
            table.insert(result.missing, mat.item)
        end

        -- How many full batches the player owns materials for (vendor mats assumed buyable)
        if not mat.vendor then
            local owned = (self:CountInventory(mat.item) or 0) + (self:CountBank(mat.item) or 0)
            local batches = math.floor(owned / mat.count)
            if not result.canMake or batches < result.canMake then
                result.canMake = batches
            end
        end
    end

    local productUnit, productSource, productWhen = self:GetUnitPrice(recipe.product, basis)
    result.productUnit = productUnit
    result.productSource = productSource
    result.productWhen = productWhen
    if productUnit then
        result.productValue = productUnit * (recipe.productCount or 1)
        result.ahNet = result.productValue * (1 - self:GetAHCut())
    else
        complete = false
        table.insert(result.missing, recipe.product)
    end

    result.complete = complete
    if complete then
        result.profit = result.ahNet - result.matCost
        result.margin = result.matCost > 0 and (result.profit / result.matCost) * 100 or nil
    end
    return result
end

-- Profit under every basis, for side-by-side comparison in tooltips
function MAW:CompareRecipeBases(recipe)
    local out = {}
    for _, b in ipairs(self.PRICE_BASES) do
        local calc = self:ComputeRecipeProfit(recipe, b.key)
        table.insert(out, { basis = b, profit = calc.profit, margin = calc.margin, complete = calc.complete })
    end
    return out
end


-- Built-in preset: TBC Jewelcrafting, 1 raw gem -> 1 cut gem.
-- Generated from AtlasLoot's TBC crafting data; item IDs verified against its source table.
MAW.PRESET_TBC_GEMS = {
    { color = "Red", cut = { name = "Teardrop Crimson Spinel", id = 32195 }, raw = { name = "Crimson Spinel", id = 32249 }, skill = 375 },
    { color = "Red", cut = { name = "Teardrop Living Ruby", id = 24029 }, raw = { name = "Living Ruby", id = 23436 }, skill = 350 },
    { color = "Red", cut = { name = "Teardrop Blood Garnet", id = 23094 }, raw = { name = "Blood Garnet", id = 23077 }, skill = 300 },
    { color = "Red", cut = { name = "Runed Crimson Spinel", id = 32196 }, raw = { name = "Crimson Spinel", id = 32249 }, skill = 375 },
    { color = "Red", cut = { name = "Runed Living Ruby", id = 24030 }, raw = { name = "Living Ruby", id = 23436 }, skill = 350 },
    { color = "Red", cut = { name = "Runed Blood Garnet", id = 23096 }, raw = { name = "Blood Garnet", id = 23077 }, skill = 315 },
    { color = "Red", cut = { name = "Bright Crimson Spinel", id = 32197 }, raw = { name = "Crimson Spinel", id = 32249 }, skill = 375 },
    { color = "Red", cut = { name = "Bright Living Ruby", id = 24031 }, raw = { name = "Living Ruby", id = 23436 }, skill = 350 },
    { color = "Red", cut = { name = "Bright Blood Garnet", id = 28595 }, raw = { name = "Blood Garnet", id = 23077 }, skill = 305 },
    { color = "Red", cut = { name = "Delicate Crimson Spinel", id = 32194 }, raw = { name = "Crimson Spinel", id = 32249 }, skill = 375 },
    { color = "Red", cut = { name = "Delicate Living Ruby", id = 24028 }, raw = { name = "Living Ruby", id = 23436 }, skill = 350 },
    { color = "Red", cut = { name = "Delicate Blood Garnet", id = 23097 }, raw = { name = "Blood Garnet", id = 23077 }, skill = 325 },
    { color = "Red", cut = { name = "Bold Crimson Spinel", id = 32193 }, raw = { name = "Crimson Spinel", id = 32249 }, skill = 375 },
    { color = "Red", cut = { name = "Bold Living Ruby", id = 24027 }, raw = { name = "Living Ruby", id = 23436 }, skill = 350 },
    { color = "Red", cut = { name = "Bold Blood Garnet", id = 23095 }, raw = { name = "Blood Garnet", id = 23077 }, skill = 305 },
    { color = "Red", cut = { name = "Subtle Crimson Spinel", id = 32198 }, raw = { name = "Crimson Spinel", id = 32249 }, skill = 375 },
    { color = "Red", cut = { name = "Subtle Living Ruby", id = 24032 }, raw = { name = "Living Ruby", id = 23436 }, skill = 350 },
    { color = "Red", cut = { name = "Flashing Crimson Spinel", id = 32199 }, raw = { name = "Crimson Spinel", id = 32249 }, skill = 375 },
    { color = "Red", cut = { name = "Flashing Living Ruby", id = 24036 }, raw = { name = "Living Ruby", id = 23436 }, skill = 350 },
    { color = "Yellow", cut = { name = "Smooth Lionseye", id = 32205 }, raw = { name = "Lionseye", id = 32231 }, skill = 375 },
    { color = "Yellow", cut = { name = "Smooth Dawnstone", id = 24048 }, raw = { name = "Dawnstone", id = 23440 }, skill = 350 },
    { color = "Yellow", cut = { name = "Smooth Golden Draenite", id = 28290 }, raw = { name = "Golden Draenite", id = 23112 }, skill = 325 },
    { color = "Yellow", cut = { name = "Gleaming Lionseye", id = 32207 }, raw = { name = "Lionseye", id = 32231 }, skill = 375 },
    { color = "Yellow", cut = { name = "Gleaming Dawnstone", id = 24050 }, raw = { name = "Dawnstone", id = 23440 }, skill = 350 },
    { color = "Yellow", cut = { name = "Gleaming Golden Draenite", id = 23114 }, raw = { name = "Golden Draenite", id = 23112 }, skill = 305 },
    { color = "Yellow", cut = { name = "Thick Lionseye", id = 32208 }, raw = { name = "Lionseye", id = 32231 }, skill = 375 },
    { color = "Yellow", cut = { name = "Thick Dawnstone", id = 24052 }, raw = { name = "Dawnstone", id = 23440 }, skill = 350 },
    { color = "Yellow", cut = { name = "Thick Golden Draenite", id = 23115 }, raw = { name = "Golden Draenite", id = 23112 }, skill = 315 },
    { color = "Yellow", cut = { name = "Rigid Lionseye", id = 32206 }, raw = { name = "Lionseye", id = 32231 }, skill = 375 },
    { color = "Yellow", cut = { name = "Rigid Dawnstone", id = 24051 }, raw = { name = "Dawnstone", id = 23440 }, skill = 350 },
    { color = "Yellow", cut = { name = "Rigid Golden Draenite", id = 23116 }, raw = { name = "Golden Draenite", id = 23112 }, skill = 325 },
    { color = "Yellow", cut = { name = "Great Lionseye", id = 32210 }, raw = { name = "Lionseye", id = 32231 }, skill = 375 },
    { color = "Yellow", cut = { name = "Great Dawnstone", id = 31861 }, raw = { name = "Dawnstone", id = 23440 }, skill = 350 },
    { color = "Yellow", cut = { name = "Great Golden Draenite", id = 31860 }, raw = { name = "Golden Draenite", id = 23112 }, skill = 325 },
    { color = "Yellow", cut = { name = "Brilliant Lionseye", id = 32204 }, raw = { name = "Lionseye", id = 32231 }, skill = 375 },
    { color = "Yellow", cut = { name = "Brilliant Dawnstone", id = 24047 }, raw = { name = "Dawnstone", id = 23440 }, skill = 350 },
    { color = "Yellow", cut = { name = "Brilliant Golden Draenite", id = 23113 }, raw = { name = "Golden Draenite", id = 23112 }, skill = 300 },
    { color = "Yellow", cut = { name = "Quick Lionseye", id = 35761 }, raw = { name = "Lionseye", id = 32231 }, skill = 375 },
    { color = "Yellow", cut = { name = "Quick Dawnstone", id = 35315 }, raw = { name = "Dawnstone", id = 23440 }, skill = 350 },
    { color = "Yellow", cut = { name = "Mystic Lionseye", id = 32209 }, raw = { name = "Lionseye", id = 32231 }, skill = 375 },
    { color = "Yellow", cut = { name = "Mystic Dawnstone", id = 24053 }, raw = { name = "Dawnstone", id = 23440 }, skill = 350 },
    { color = "Blue", cut = { name = "Solid Empyrean Sapphire", id = 32200 }, raw = { name = "Empyrean Sapphire", id = 32229 }, skill = 375 },
    { color = "Blue", cut = { name = "Solid Star of Elune", id = 24033 }, raw = { name = "Star of Elune", id = 23438 }, skill = 350 },
    { color = "Blue", cut = { name = "Solid Azure Moonstone", id = 23118 }, raw = { name = "Azure Moonstone", id = 23117 }, skill = 300 },
    { color = "Blue", cut = { name = "Stormy Empyrean Sapphire", id = 32203 }, raw = { name = "Empyrean Sapphire", id = 32229 }, skill = 375 },
    { color = "Blue", cut = { name = "Stormy Star of Elune", id = 24039 }, raw = { name = "Star of Elune", id = 23438 }, skill = 350 },
    { color = "Blue", cut = { name = "Stormy Azure Moonstone", id = 23120 }, raw = { name = "Azure Moonstone", id = 23117 }, skill = 315 },
    { color = "Blue", cut = { name = "Sparkling Empyrean Sapphire", id = 32201 }, raw = { name = "Empyrean Sapphire", id = 32229 }, skill = 375 },
    { color = "Blue", cut = { name = "Sparkling Star of Elune", id = 24035 }, raw = { name = "Star of Elune", id = 23438 }, skill = 350 },
    { color = "Blue", cut = { name = "Sparkling Azure Moonstone", id = 23119 }, raw = { name = "Azure Moonstone", id = 23117 }, skill = 305 },
    { color = "Blue", cut = { name = "Lustrous Empyrean Sapphire", id = 32202 }, raw = { name = "Empyrean Sapphire", id = 32229 }, skill = 375 },
    { color = "Blue", cut = { name = "Lustrous Star of Elune", id = 24037 }, raw = { name = "Star of Elune", id = 23438 }, skill = 350 },
    { color = "Blue", cut = { name = "Lustrous Azure Moonstone", id = 23121 }, raw = { name = "Azure Moonstone", id = 23117 }, skill = 325 },
    { color = "Orange", cut = { name = "Wicked Pyrestone", id = 32222 }, raw = { name = "Pyrestone", id = 32230 }, skill = 375 },
    { color = "Orange", cut = { name = "Wicked Noble Topaz", id = 31868 }, raw = { name = "Noble Topaz", id = 23439 }, skill = 350 },
    { color = "Orange", cut = { name = "Wicked Flame Spessarite", id = 31869 }, raw = { name = "Flame Spessarite", id = 21929 }, skill = 325 },
    { color = "Orange", cut = { name = "Veiled Pyrestone", id = 32221 }, raw = { name = "Pyrestone", id = 32230 }, skill = 375 },
    { color = "Orange", cut = { name = "Veiled Noble Topaz", id = 31867 }, raw = { name = "Noble Topaz", id = 23439 }, skill = 350 },
    { color = "Orange", cut = { name = "Veiled Flame Spessarite", id = 31866 }, raw = { name = "Flame Spessarite", id = 21929 }, skill = 325 },
    { color = "Orange", cut = { name = "Potent Pyrestone", id = 32218 }, raw = { name = "Pyrestone", id = 32230 }, skill = 375 },
    { color = "Orange", cut = { name = "Potent Noble Topaz", id = 24059 }, raw = { name = "Noble Topaz", id = 23439 }, skill = 350 },
    { color = "Orange", cut = { name = "Potent Flame Spessarite", id = 23101 }, raw = { name = "Flame Spessarite", id = 21929 }, skill = 325 },
    { color = "Orange", cut = { name = "Reckless Pyrestone", id = 35760 }, raw = { name = "Pyrestone", id = 32230 }, skill = 375 },
    { color = "Orange", cut = { name = "Reckless Noble Topaz", id = 35316 }, raw = { name = "Noble Topaz", id = 23439 }, skill = 350 },
    { color = "Orange", cut = { name = "Luminous Pyrestone", id = 32219 }, raw = { name = "Pyrestone", id = 32230 }, skill = 375 },
    { color = "Orange", cut = { name = "Luminous Noble Topaz", id = 24060 }, raw = { name = "Noble Topaz", id = 23439 }, skill = 350 },
    { color = "Orange", cut = { name = "Luminous Flame Spessarite", id = 23099 }, raw = { name = "Flame Spessarite", id = 21929 }, skill = 305 },
    { color = "Orange", cut = { name = "Inscribed Pyrestone", id = 32217 }, raw = { name = "Pyrestone", id = 32230 }, skill = 375 },
    { color = "Orange", cut = { name = "Inscribed Noble Topaz", id = 24058 }, raw = { name = "Noble Topaz", id = 23439 }, skill = 350 },
    { color = "Orange", cut = { name = "Inscribed Flame Spessarite", id = 23098 }, raw = { name = "Flame Spessarite", id = 21929 }, skill = 300 },
    { color = "Orange", cut = { name = "Glinting Pyrestone", id = 32220 }, raw = { name = "Pyrestone", id = 32230 }, skill = 375 },
    { color = "Orange", cut = { name = "Glinting Noble Topaz", id = 24061 }, raw = { name = "Noble Topaz", id = 23439 }, skill = 350 },
    { color = "Orange", cut = { name = "Glinting Flame Spessarite", id = 23100 }, raw = { name = "Flame Spessarite", id = 21929 }, skill = 315 },
    { color = "Green", cut = { name = "Enduring Seaspray Emerald", id = 32223 }, raw = { name = "Seaspray Emerald", id = 32250 }, skill = 375 },
    { color = "Green", cut = { name = "Enduring Talasite", id = 24062 }, raw = { name = "Talasite", id = 23437 }, skill = 350 },
    { color = "Green", cut = { name = "Enduring Deep Peridot", id = 23105 }, raw = { name = "Deep Peridot", id = 23079 }, skill = 315 },
    { color = "Green", cut = { name = "Radiant Seaspray Emerald", id = 32224 }, raw = { name = "Seaspray Emerald", id = 32250 }, skill = 375 },
    { color = "Green", cut = { name = "Radiant Talasite", id = 24066 }, raw = { name = "Talasite", id = 23437 }, skill = 350 },
    { color = "Green", cut = { name = "Radiant Deep Peridot", id = 23103 }, raw = { name = "Deep Peridot", id = 23079 }, skill = 300 },
    { color = "Green", cut = { name = "Steady Seaspray Emerald", id = 35758 }, raw = { name = "Seaspray Emerald", id = 32250 }, skill = 375 },
    { color = "Green", cut = { name = "Steady Talasite", id = 33782 }, raw = { name = "Talasite", id = 23437 }, skill = 350 },
    { color = "Green", cut = { name = "Jagged Seaspray Emerald", id = 32226 }, raw = { name = "Seaspray Emerald", id = 32250 }, skill = 375 },
    { color = "Green", cut = { name = "Jagged Talasite", id = 24067 }, raw = { name = "Talasite", id = 23437 }, skill = 350 },
    { color = "Green", cut = { name = "Jagged Deep Peridot", id = 23104 }, raw = { name = "Deep Peridot", id = 23079 }, skill = 305 },
    { color = "Green", cut = { name = "Dazzling Seaspray Emerald", id = 32225 }, raw = { name = "Seaspray Emerald", id = 32250 }, skill = 375 },
    { color = "Green", cut = { name = "Dazzling Talasite", id = 24065 }, raw = { name = "Talasite", id = 23437 }, skill = 350 },
    { color = "Green", cut = { name = "Dazzling Deep Peridot", id = 23106 }, raw = { name = "Deep Peridot", id = 23079 }, skill = 325 },
    { color = "Green", cut = { name = "Forceful Seaspray Emerald", id = 35759 }, raw = { name = "Seaspray Emerald", id = 32250 }, skill = 375 },
    { color = "Green", cut = { name = "Forceful Talasite", id = 35318 }, raw = { name = "Talasite", id = 23437 }, skill = 350 },
    { color = "Purple", cut = { name = "Shifting Shadowsong Amethyst", id = 32212 }, raw = { name = "Shadowsong Amethyst", id = 32228 }, skill = 375 },
    { color = "Purple", cut = { name = "Shifting Nightseye", id = 24055 }, raw = { name = "Nightseye", id = 23441 }, skill = 350 },
    { color = "Purple", cut = { name = "Shifting Shadow Draenite", id = 23110 }, raw = { name = "Shadow Draenite", id = 23107 }, skill = 315 },
    { color = "Purple", cut = { name = "Sovereign Shadowsong Amethyst", id = 32211 }, raw = { name = "Shadowsong Amethyst", id = 32228 }, skill = 375 },
    { color = "Purple", cut = { name = "Sovereign Nightseye", id = 24054 }, raw = { name = "Nightseye", id = 23441 }, skill = 350 },
    { color = "Purple", cut = { name = "Sovereign Shadow Draenite", id = 23111 }, raw = { name = "Shadow Draenite", id = 23107 }, skill = 325 },
    { color = "Purple", cut = { name = "Balanced Shadowsong Amethyst", id = 32213 }, raw = { name = "Shadowsong Amethyst", id = 32228 }, skill = 375 },
    { color = "Purple", cut = { name = "Balanced Nightseye", id = 31863 }, raw = { name = "Nightseye", id = 23441 }, skill = 350 },
    { color = "Purple", cut = { name = "Balanced Shadow Draenite", id = 31862 }, raw = { name = "Shadow Draenite", id = 23107 }, skill = 325 },
    { color = "Purple", cut = { name = "Infused Shadowsong Amethyst", id = 32214 }, raw = { name = "Shadowsong Amethyst", id = 32228 }, skill = 375 },
    { color = "Purple", cut = { name = "Infused Nightseye", id = 31865 }, raw = { name = "Nightseye", id = 23441 }, skill = 350 },
    { color = "Purple", cut = { name = "Infused Shadow Draenite", id = 31864 }, raw = { name = "Shadow Draenite", id = 23107 }, skill = 325 },
    { color = "Purple", cut = { name = "Glowing Nightseye", id = 32215 }, raw = { name = "Nightseye", id = 23441 }, skill = 375 },
    { color = "Purple", cut = { name = "Glowing Nightseye", id = 24056 }, raw = { name = "Nightseye", id = 23441 }, skill = 350 },
    { color = "Purple", cut = { name = "Glowing Shadow Draenite", id = 23108 }, raw = { name = "Shadow Draenite", id = 23107 }, skill = 300 },
    { color = "Purple", cut = { name = "Royal Shadowsong Amethyst", id = 32216 }, raw = { name = "Shadowsong Amethyst", id = 32228 }, skill = 375 },
    { color = "Purple", cut = { name = "Royal Nightseye", id = 24057 }, raw = { name = "Nightseye", id = 23441 }, skill = 350 },
    { color = "Purple", cut = { name = "Royal Shadow Draenite", id = 23109 }, raw = { name = "Shadow Draenite", id = 23107 }, skill = 305 },
    { color = "Purple", cut = { name = "Purified Shadowsong Amethyst", id = 37503 }, raw = { name = "Shadowsong Amethyst", id = 32228 }, skill = 375 },
    { color = "Purple", cut = { name = "Regal Nightseye", id = 35707 }, raw = { name = "Nightseye", id = 23441 }, skill = 350 },
}

MAW.GEM_TIERS = {
    uncommon = { [23077]=true, [23079]=true, [21929]=true, [23112]=true, [23117]=true, [23107]=true },
    rare     = { [23436]=true, [23437]=true, [23438]=true, [23439]=true, [23440]=true, [23441]=true },
    epic     = { [32249]=true, [32229]=true, [32231]=true, [32230]=true, [32250]=true, [32228]=true },
}

-- Distinct raw gems in the preset, in a stable order
function MAW:GetPresetRawGems()
    local seen, list = {}, {}
    for _, g in ipairs(self.PRESET_TBC_GEMS) do
        if not seen[g.raw.id] then
            seen[g.raw.id] = true
            local tier = "uncommon"
            if self.GEM_TIERS.rare[g.raw.id] then tier = "rare" elseif self.GEM_TIERS.epic[g.raw.id] then tier = "epic" end
            table.insert(list, { name = g.raw.name, id = g.raw.id, tier = tier })
        end
    end
    table.sort(list, function(a, b)
        local order = { uncommon = 1, rare = 2, epic = 3 }
        if order[a.tier] ~= order[b.tier] then return order[a.tier] < order[b.tier] end
        return a.name < b.name
    end)
    return list
end

-- Prefer the live item name from the client when it is cached, in case of naming differences
local function LiveName(id, fallback)
    local name = GetItemInfo(id)
    return name or fallback
end

-- Add gem-cut recipes. filter = { rawID = n } for one raw gem, or { tier = "uncommon"|"rare"|"epic" }
function MAW:AddGemPresets(filter)
    filter = filter or {}
    local added, tracked = 0, 0
    for _, g in ipairs(self.PRESET_TBC_GEMS) do
        local wanted = true
        if filter.rawID and g.raw.id ~= filter.rawID then wanted = false end
        if filter.tier and not self.GEM_TIERS[filter.tier][g.raw.id] then wanted = false end
        if wanted then
            local rawName = LiveName(g.raw.id, g.raw.name)
            local cutName = LiveName(g.cut.id, g.cut.name)
            if self:AddItemByID(rawName, g.raw.id, "material") then tracked = tracked + 1 end
            if self:AddItemByID(cutName, g.cut.id, "product") then tracked = tracked + 1 end
            local ok = self:AddRecipe({
                name = cutName,
                product = cutName,
                productCount = 1,
                materials = { { item = rawName, count = 1 } },
                skill = g.skill,
                color = g.color,
            })
            if ok then added = added + 1 end
        end
    end
    print(string.format("%s: Added %d gem-cut recipes and started tracking %d items", addonName, added, tracked))
    return added
end


-- ---------------------------------------------------------------------------
-- Vendor-priced reagents: fixed cost, never scanned or tracked
-- ---------------------------------------------------------------------------
MAW.VENDOR_MATS = {
    [18256] = { name = "Imbued Vial",  price = 2000 },
    [8925]  = { name = "Crystal Vial", price = 2000 },
    [3372]  = { name = "Leaded Vial",  price = 200 },
    [3371]  = { name = "Empty Vial",   price = 20 },
}

function MAW:VendorMatByName(name)
    for id, v in pairs(self.VENDOR_MATS) do
        if v.name == name then return v, id end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Built-in preset: TBC Alchemy consumables the raid market moves quickly.
-- Only recipes whose reagents are certain are listed. Imbued Vial is vendor priced.
-- ---------------------------------------------------------------------------
local VIAL = { name = "Imbued Vial", id = 18256, count = 1, vendor = 2000 }
MAW.PRESET_ALCHEMY = {
    { product = { name = "Haste Potion", id = 22838 }, skill = 360, mats = {
        { name = "Netherbloom", id = 22791, count = 1 }, { name = "Terocone", id = 22789, count = 1 }, VIAL } },
    { product = { name = "Destruction Potion", id = 22839 }, skill = 350, mats = {
        { name = "Nightmare Vine", id = 22792, count = 1 }, { name = "Terocone", id = 22789, count = 1 }, VIAL } },
    { product = { name = "Super Mana Potion", id = 22832 }, skill = 340, mats = {
        { name = "Dreaming Glory", id = 22786, count = 2 }, { name = "Felweed", id = 22785, count = 1 }, VIAL } },
    { product = { name = "Super Healing Potion", id = 22829 }, skill = 325, mats = {
        { name = "Netherbloom", id = 22791, count = 2 }, { name = "Felweed", id = 22785, count = 1 }, VIAL } },
    { product = { name = "Elixir of Major Mageblood", id = 22840 }, skill = 355, mats = {
        { name = "Ancient Lichen", id = 22790, count = 1 }, { name = "Netherbloom", id = 22791, count = 1 }, VIAL } },
    { product = { name = "Flask of Fortification", id = 22851 }, skill = 375, mats = {
        { name = "Ancient Lichen", id = 22790, count = 7 }, { name = "Mana Thistle", id = 22793, count = 3 },
        { name = "Fel Lotus", id = 22794, count = 1 }, VIAL } },
    { product = { name = "Flask of Mighty Restoration", id = 22853 }, skill = 375, mats = {
        { name = "Dreaming Glory", id = 22786, count = 7 }, { name = "Mana Thistle", id = 22793, count = 3 },
        { name = "Fel Lotus", id = 22794, count = 1 }, VIAL } },
}

function MAW:AddAlchemyPresets()
    local added, tracked = 0, 0
    for _, r in ipairs(self.PRESET_ALCHEMY) do
        local mats = {}
        for _, m in ipairs(r.mats) do
            if m.vendor then
                table.insert(mats, { item = m.name, count = m.count, vendor = m.vendor })
            else
                if self:AddItemByID(m.name, m.id, "material") then tracked = tracked + 1 end
                table.insert(mats, { item = m.name, count = m.count })
            end
        end
        if self:AddItemByID(r.product.name, r.product.id, "product") then tracked = tracked + 1 end
        local ok = self:AddRecipe({
            name = r.product.name,
            product = r.product.name,
            productCount = 1,
            materials = mats,
            skill = r.skill,
            profession = "Alchemy",
            note = "Preset reagents; check against your recipe book",
        })
        if ok then added = added + 1 end
    end
    print(string.format("%s: Added %d Alchemy recipes and started tracking %d items", addonName, added, tracked))
    return added
end

-- ---------------------------------------------------------------------------
-- Guide watchlist: items a TBC flipping guide singles out. Tracks only, no recipes.
-- ---------------------------------------------------------------------------
MAW.PRESET_GUIDE_WATCHLIST = {
    materials = {
        { name = "Large Prismatic Shard", id = 22449 },
        { name = "Felweed", id = 22785 }, { name = "Dreaming Glory", id = 22786 },
        { name = "Terocone", id = 22789 }, { name = "Ancient Lichen", id = 22790 },
        { name = "Netherbloom", id = 22791 }, { name = "Nightmare Vine", id = 22792 },
        { name = "Mana Thistle", id = 22793 }, { name = "Fel Lotus", id = 22794 },
        { name = "Flame Cap", id = 22788 }, { name = "Nightmare Seed", id = 22797 },
        { name = "Ghost Mushroom", id = 8845 }, { name = "Gromsblood", id = 8846 },
        { name = "Firebloom", id = 4625 },
    },
    products = {
        { name = "Haste Potion", id = 22838 }, { name = "Destruction Potion", id = 22839 },
        { name = "Super Mana Potion", id = 22832 }, { name = "Elixir of Demonslaying", id = 9224 },
        { name = "Primal Fire", id = 21884 }, { name = "Primal Mana", id = 22457 },
        { name = "Primal Life", id = 21886 }, { name = "Primal Air", id = 22451 },
        { name = "Primal Shadow", id = 22456 },
        { name = "Living Ruby", id = 23436 }, { name = "Noble Topaz", id = 23439 },
        { name = "Nightseye", id = 23441 }, { name = "Dawnstone", id = 23440 },
        { name = "Star of Elune", id = 23438 },
    },
}

function MAW:AddGuideWatchlist()
    local tracked = 0
    for _, it in ipairs(self.PRESET_GUIDE_WATCHLIST.materials) do
        if self:AddItemByID(it.name, it.id, "material") then tracked = tracked + 1 end
    end
    for _, it in ipairs(self.PRESET_GUIDE_WATCHLIST.products) do
        if self:AddItemByID(it.name, it.id, "product") then tracked = tracked + 1 end
    end
    print(string.format("%s: Guide watchlist added %d new tracked items", addonName, tracked))
    return tracked
end

-- ---------------------------------------------------------------------------
-- Import from the profession window that is open right now (exact reagents from the client)
-- entry = { name, product, productID, numMade, reagents = { {item, id, count, vendor} } }
-- ---------------------------------------------------------------------------
function MAW:ImportProfessionRecipe(entry, professionName)
    local mats, tracked = {}, 0
    for _, r in ipairs(entry.reagents) do
        local vendor = self.VENDOR_MATS[r.id or 0] or self:VendorMatByName(r.item)
        if vendor then
            table.insert(mats, { item = r.item, count = r.count, vendor = vendor.price })
        else
            if r.id then
                if self:AddItemByID(r.item, r.id, "material") then tracked = tracked + 1 end
            end
            table.insert(mats, { item = r.item, count = r.count })
        end
    end
    if entry.productID and self:AddItemByID(entry.product, entry.productID, "product") then
        tracked = tracked + 1
    end
    local ok, err = self:AddRecipe({
        name = entry.name,
        product = entry.product,
        productCount = entry.numMade or 1,
        materials = mats,
        profession = professionName,
        note = "Imported from your " .. (professionName or "profession") .. " window",
    })
    return ok, err, tracked
end

_G.MalexisAuctionWatcher = MAW
