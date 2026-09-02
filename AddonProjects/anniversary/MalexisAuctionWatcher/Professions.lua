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

-- Get cached profession recipes (all professions)
function MAW:GetCachedRecipes()
    local db = self:GetActiveDB()
    if not db.cache or not db.cache.recipes then
        return {}
    end
    return db.cache.recipes
end

_G.MalexisAuctionWatcher = MAW
