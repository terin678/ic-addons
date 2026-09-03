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

-- Read every recipe in the open TradeSkill window with exact reagents.
-- Returns professionName, { {name, product, productID, numMade, reagents={ {item,id,count} }} }
function MAW:ReadOpenProfession()
    if not (TradeSkillFrame and TradeSkillFrame:IsVisible() and GetNumTradeSkills) then
        return nil, {}
    end
    local professionName = GetTradeSkillLine and GetTradeSkillLine() or nil
    if not professionName and TradeSkillFrame.titleText then
        professionName = TradeSkillFrame.titleText:GetText()
    end

    local entries = {}
    for i = 1, GetNumTradeSkills() do
        local skillName, skillType = GetTradeSkillInfo(i)
        if skillName and skillType ~= "header" and skillType ~= "subheader" then
            local link = GetTradeSkillItemLink(i)
            local productName = link and GetItemInfo(link) or (link and link:match("%[(.-)%]"))
            local productID = link and tonumber(link:match("item:(%d+)"))
            if productName then
                local minMade = GetTradeSkillNumMade and GetTradeSkillNumMade(i) or 1
                local reagents = {}
                local numReagents = GetTradeSkillNumReagents and GetTradeSkillNumReagents(i) or 0
                for j = 1, numReagents do
                    local rName, _, rCount = GetTradeSkillReagentInfo(i, j)
                    local rLink = GetTradeSkillReagentItemLink and GetTradeSkillReagentItemLink(i, j)
                    local rID = rLink and tonumber(rLink:match("item:(%d+)"))
                    if not rName and rLink then
                        rName = rLink:match("%[(.-)%]")
                    end
                    if rName and rCount and rCount > 0 then
                        table.insert(reagents, { item = rName, id = rID, count = rCount })
                    end
                end
                if #reagents > 0 then
                    table.insert(entries, {
                        name = skillName,
                        product = productName,
                        productID = productID,
                        numMade = math.max(1, math.floor(minMade or 1)),
                        reagents = reagents,
                    })
                end
            end
        end
    end
    return professionName, entries
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
