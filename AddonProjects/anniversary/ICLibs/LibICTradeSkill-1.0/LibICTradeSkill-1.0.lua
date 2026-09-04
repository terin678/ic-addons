--[[
LibICTradeSkill-1.0
Reads the open profession (TradeSkill) window into plain tables and keeps a
scanned "book" per profession up to date. Shared by the ic-addons guild addons
(TradeMaster, MalexisAuctionWatcher). TBC Anniversary client, legacy
GetTradeSkill* API. Enchanting uses the Craft API and is not covered.

    local Lib = LibStub("LibICTradeSkill-1.0")

    Lib:OpenLine()                 -> profession name of the open window, or nil
    Lib:ReadOpen(opts)             -> rows, failed   (one pass, filters cleared and restored)
    Lib:ScanOpen(callback, opts)   -> reads, retries once for uncached items, then
                                      callback(rows, failed, lineName)
    Lib:MergeBook(oldBook, rows, opts) -> newBook, added
    Lib:MissingBoP(row)            -> { {itemID, need, have}, ... }
    Lib:DescribeMissing(list, withCounts) -> "Primal Nether x1 (have 0)"

A row:
    itemID, name (product), link,
    recipeLink (the |Htrade: link for the craft itself, nil on a client with no
    GetTradeSkillRecipeLink; hovering it lists the reagents, which is what makes
    it worth handing to a customer),
    skillName (the recipe line, e.g. "Transmute:
    Primal Might"), skillType ("optimal"/"medium"/"easy"/"trivial"), header,
    classID, subClassID, quality, bindType, numMade,
    reagents     = { [itemID] = count },
    reagentList  = { { itemID=, name=, count=, link= }, ... } in window order,
    reagentBind  = { [itemID] = bindType } for reagents in the item cache.
]]

local MAJOR, MINOR = "LibICTradeSkill-1.0", 2
local Lib = LibStub:NewLibrary(MAJOR, MINOR)
if not Lib then return end

-- Uncached items return nil links on the first pass; one retry after this.
local RETRY_DELAY = 0.5

function Lib:OpenLine()
    if not (TradeSkillFrame and TradeSkillFrame:IsVisible()) then return nil end
    if not (GetTradeSkillLine and GetNumTradeSkills) then return nil end
    local line = GetTradeSkillLine()
    if not line or line == "" or line == "UNKNOWN" then return nil end
    return line
end

--------------------------------------------------------------------------------
-- Window filters. The list only reports rows passing the active filters, so a
-- leftover subclass filter or search term silently yields a partial book.
--------------------------------------------------------------------------------

local function SaveFilters()
    return {
        makeable = TradeSkillFrame and TradeSkillFrame.filterTbl
            and TradeSkillFrame.filterTbl.hasMaterials or false,
    }
end

local function ClearFilters()
    if SetTradeSkillSubClassFilter then SetTradeSkillSubClassFilter(0, 1, 1) end
    if SetTradeSkillInvSlotFilter then SetTradeSkillInvSlotFilter(0, 1, 1) end
    if TradeSkillOnlyShowMakeable then TradeSkillOnlyShowMakeable(false) end
    if TradeSkillOnlyShowSkillUps then TradeSkillOnlyShowSkillUps(false) end
    if SetTradeSkillItemNameFilter then SetTradeSkillItemNameFilter("") end
    if ExpandTradeSkillSubClass then ExpandTradeSkillSubClass(0) end
end

local function RestoreFilters(saved)
    if TradeSkillOnlyShowMakeable and saved and saved.makeable then
        TradeSkillOnlyShowMakeable(true)
    end
end

--------------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------------

local function ReadReagents(idx)
    local map, list = {}, {}
    local n = GetTradeSkillNumReagents and GetTradeSkillNumReagents(idx) or 0
    for r = 1, n do
        local name, _, required = GetTradeSkillReagentInfo(idx, r)
        local link = GetTradeSkillReagentItemLink and GetTradeSkillReagentItemLink(idx, r)
        local id = link and tonumber(link:match("|Hitem:(%d+)"))
        if not name and link then name = link:match("%[(.-)%]") end
        if id then map[id] = required or 1 end
        if (id or name) and (required or 0) > 0 then
            list[#list + 1] = { itemID = id, name = name, count = required, link = link }
        end
    end
    return map, list
end

local function ReagentBinds(reagents)
    local out = {}
    for id in pairs(reagents or {}) do
        local bind = select(14, GetItemInfo(id))
        if bind ~= nil then out[id] = bind end
    end
    return out
end

local function CollectRows()
    local rows, failed = {}, {}
    local header = nil
    local count = GetNumTradeSkills() or 0

    for idx = 1, count do
        local skillName, skillType = GetTradeSkillInfo(idx)
        if skillType == "header" or skillType == "subheader" then
            if skillType == "header" then header = skillName end
        else
            local link = GetTradeSkillItemLink(idx)
            local itemID = link and tonumber(link:match("|Hitem:(%d+)"))
            if itemID then
                local name, _, quality, _, _, _, _, _, _, _, _, classID,
                      subClassID, bindType = GetItemInfo(link)
                local numMade = GetTradeSkillNumMade and GetTradeSkillNumMade(idx) or 1
                -- The |Htrade: link for the craft itself. Hovering it lists the
                -- reagents, which is the whole reason to hand it to a customer.
                -- Not on every client, so nil is an expected value here.
                local recipeLink = GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(idx) or nil
                local reagents, reagentList = ReadReagents(idx)
                rows[#rows + 1] = {
                    itemID = itemID,
                    name = name or (link:match("%[(.-)%]")) or skillName,
                    link = link,
                    recipeLink = recipeLink,
                    skillName = skillName,
                    skillType = skillType,
                    header = header or "Other",
                    classID = classID,
                    subClassID = subClassID,
                    quality = quality,
                    bindType = bindType,
                    numMade = math.max(1, math.floor(numMade or 1)),
                    reagents = reagents,
                    reagentList = reagentList,
                    reagentBind = ReagentBinds(reagents),
                }
            else
                failed[#failed + 1] = idx
            end
        end
    end

    return rows, failed
end

-- One pass over the open window. opts.keepFilters leaves the window's own
-- filters alone (and so may return a partial book).
function Lib:ReadOpen(opts)
    opts = opts or {}
    if not self:OpenLine() then return {}, {} end
    local saved
    if not opts.keepFilters then
        saved = SaveFilters()
        ClearFilters()
    end
    local rows, failed = CollectRows()
    if saved then RestoreFilters(saved) end
    return rows, failed
end

-- Reads the open window and calls back with the result. When some rows could
-- not be read (item data not cached yet) it retries once after a short delay,
-- as long as the same window is still open. The callback always runs, on the
-- same frame when no retry is needed.
function Lib:ScanOpen(callback, opts)
    local line = self:OpenLine()
    if not line then
        callback({}, {}, nil)
        return
    end
    local rows, failed = self:ReadOpen(opts)
    if #failed == 0 or not C_Timer then
        callback(rows, failed, line)
        return
    end
    C_Timer.After(RETRY_DELAY, function()
        if self:OpenLine() == line then
            local rows2, failed2 = self:ReadOpen(opts)
            callback(rows2, failed2, line)
        else
            callback(rows, failed, line)
        end
    end)
end

--------------------------------------------------------------------------------
-- Books
--------------------------------------------------------------------------------

-- Pure. Folds a fresh scan into a stored book keyed by product itemID. Fields
-- named in opts.preserve are carried over from the previous entry (user
-- choices such as flags or aliases). Entries no longer in the window are kept
-- with stale = true so nothing the user set is lost by a partial read.
-- Returns the new book and how many entries are new.
function Lib:MergeBook(oldBook, rows, opts)
    oldBook = oldBook or {}
    opts = opts or {}
    local preserve = opts.preserve or {}
    local newBook, seen, added = {}, {}, 0

    for _, s in ipairs(rows or {}) do
        seen[s.itemID] = true
        local prev = oldBook[s.itemID]
        local entry = {}
        for k, v in pairs(s) do entry[k] = v end
        if prev then
            for _, k in ipairs(preserve) do entry[k] = prev[k] end
        else
            added = added + 1
        end
        newBook[s.itemID] = entry
    end

    for itemID, prev in pairs(oldBook) do
        if not seen[itemID] then
            local kept = {}
            for k, v in pairs(prev) do kept[k] = v end
            kept.stale = true
            newBook[itemID] = kept
        end
    end

    return newBook, added
end

--------------------------------------------------------------------------------
-- Bind on Pickup reagents
--------------------------------------------------------------------------------

-- A Bind on Pickup reagent (Primal Nether, Nether Vortex, ...) can't be bought
-- or handed over, so a recipe needing one you don't hold can't be made for
-- someone else. Returns { {itemID, need, have}, ... } for each such reagent,
-- empty when the recipe is doable. Bags plus bank; bank counts are known once
-- the bank has been opened this session. Caches reagent bind types on the row.
function Lib:MissingBoP(row)
    local out = {}
    if not row or not row.reagents then return out end
    row.reagentBind = row.reagentBind or {}
    for id, need in pairs(row.reagents) do
        local bind = row.reagentBind[id]
        if bind == nil then
            bind = select(14, GetItemInfo(id))
            if bind ~= nil then row.reagentBind[id] = bind end
        end
        if bind == 1 then
            local have = GetItemCount and GetItemCount(id, true) or 0
            if have < need then out[#out + 1] = { itemID = id, need = need, have = have } end
        end
    end
    table.sort(out, function(a, b) return a.itemID < b.itemID end)
    return out
end

-- "Primal Nether" or, with counts, "Primal Nether x1 (have 0)".
function Lib:DescribeMissing(missing, withCounts)
    local parts = {}
    for _, m in ipairs(missing or {}) do
        local name = GetItemInfo(m.itemID) or ("item " .. m.itemID)
        parts[#parts + 1] = withCounts
            and string.format("%s x%d (have %d)", name, m.need, m.have) or name
    end
    return table.concat(parts, ", ")
end
