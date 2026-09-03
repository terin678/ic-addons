-- Professions.lua - Recipe scanning and caching
local addonName = "MalexisAuctionWatcher"
local MAW = _G.MalexisAuctionWatcher or {}

-- Scan and cache profession recipes
function MAW:ScanProfessionRecipes(professionName)
    local db = self:GetActiveDB()
    if not db.cache then
        db.cache = { bank = {}, auctionHouse = {}, recipes = {} }
    end

    local recipes = {}

    -- Check for TradeSkillFrame (most professions)
    if TradeSkillFrame and TradeSkillFrame:IsVisible() then
        local numTradeSkills = GetNumTradeSkills()
        for i = 1, numTradeSkills do
            local _, skillType = GetTradeSkillInfo(i)
            -- skillType: "header", "subheader", "recipe", "trivial"
            if skillType ~= "header" and skillType ~= "subheader" then
                local link = GetTradeSkillItemLink(i)
                if link then
                    local itemName = GetItemInfo(link)
                    if itemName then
                        table.insert(recipes, itemName)
                    end
                end
            end
        end
    -- Check for CraftFrame (Enchanting)
    elseif CraftFrame and CraftFrame:IsVisible() then
        local numCrafts = GetNumCrafts()
        for i = 1, numCrafts do
            local _, craftType = GetCraftInfo(i)
            if craftType ~= "header" then
                local link = GetCraftItemLink(i)
                if link then
                    local itemName = GetItemInfo(link)
                    if itemName then
                        table.insert(recipes, itemName)
                    end
                end
            end
        end
    end

    -- Store in cache if we found any recipes
    if #recipes > 0 and professionName then
        db.cache.recipes[professionName] = recipes
        if self.debugMode then
            print(addonName .. " [DEBUG]: Cached " .. #recipes .. " recipes for " .. professionName)
        end
    end
end

-- Read every recipe in the open TradeSkill window with exact reagents, through
-- LibICTradeSkill. Kept for callers that want a one-off read of the open
-- window; the recipe book dialog uses the scanned books instead (Book.lua).
-- Returns professionName, { {name, product, productID, numMade, reagents={ {item,id,count} }} }
function MAW:ReadOpenProfession()
    local lib = LibStub and LibStub("LibICTradeSkill-1.0", true)
    if not lib then return nil, {} end
    local line = lib:OpenLine()
    if not line then return nil, {} end
    local rows = lib:ReadOpen()
    local entries = {}
    for _, row in ipairs(rows) do
        local e = self:BookRowToImport(row)
        if #e.reagents > 0 then entries[#entries + 1] = e end
    end
    return line, entries
end

-- Get cached profession recipes (all professions)
function MAW:GetCachedRecipes()
    local db = self:GetActiveDB()
    if not db.cache or not db.cache.recipes then
        return {}
    end
    return db.cache.recipes
end

_G.MalexisAuctionWatcher = MAW
