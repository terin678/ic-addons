local addonName, ns = ...

ns.Scanner = ns.Scanner or {}
local Scanner = ns.Scanner

-- Pure. Folds a fresh scan into the stored book without losing user choices.
function Scanner.MergeBook(oldBook, scanned)
    oldBook = oldBook or {}
    local newBook = {}
    local seen = {}
    local added = 0

    for _, s in ipairs(scanned) do
        seen[s.itemID] = true
        local prev = oldBook[s.itemID]
        local entry = {
            itemID = s.itemID,
            name = s.name,
            link = s.link,
            header = s.header,
            classID = s.classID,
            subClassID = s.subClassID,
            quality = s.quality,
            bindType = s.bindType,
            numMade = s.numMade,
            reagents = s.reagents or {},
        }
        if prev then
            entry.advertise = prev.advertise
            entry.match = prev.match
            entry.aliases = prev.aliases or {}
            entry.stats = prev.stats
            if entry.advertise == nil then entry.advertise = true end
            if entry.match == nil then entry.match = true end
        else
            entry.advertise = true
            entry.match = true
            entry.aliases = {}
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

-- Pure. Auto-scan clears the tradeskill window's filters as a side effect, so
-- it only earns that disruption when it might actually learn something.
function Scanner.ShouldAutoScan(bookCount, dirty, scannedAt, now, staleSec)
    if bookCount == 0 then return true end
    if dirty then return true end
    return (now - (scannedAt or 0)) > staleSec
end

local function SaveFilters()
    return {
        makeable = TradeSkillFrame and TradeSkillFrame.filterTbl
            and TradeSkillFrame.filterTbl.hasMaterials or false,
    }
end

-- The tradeskill list only reports rows passing the window's active filters, so
-- a leftover subclass filter or search term silently yields a partial book.
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

local function ReadReagents(idx)
    local reagents = {}
    local n = GetTradeSkillNumReagents and GetTradeSkillNumReagents(idx) or 0
    for r = 1, n do
        local link = GetTradeSkillReagentItemLink(idx, r)
        local _, _, required = GetTradeSkillReagentInfo(idx, r)
        if link then
            local id = tonumber(link:match("|Hitem:(%d+)"))
            if id then reagents[id] = required or 1 end
        end
    end
    return reagents
end

local function CollectRows()
    local rows, failed = {}, {}
    local header = nil
    local count = GetNumTradeSkills() or 0

    for idx = 1, count do
        local skillName, skillType = GetTradeSkillInfo(idx)
        if skillType == "header" then
            header = skillName
        else
            local link = GetTradeSkillItemLink(idx)
            local itemID = link and tonumber(link:match("|Hitem:(%d+)"))
            if itemID then
                local name, _, quality, _, _, _, _, _, _, _, _, classID,
                      subClassID, bindType = GetItemInfo(link)
                local numMade = GetTradeSkillNumMade and GetTradeSkillNumMade(idx) or 1
                rows[#rows + 1] = {
                    itemID = itemID,
                    name = name or skillName,
                    link = link,
                    header = header or "Other",
                    classID = classID,
                    subClassID = subClassID,
                    quality = quality,
                    bindType = bindType,
                    numMade = math.max(1, math.floor(numMade or 1)),
                    reagents = ReadReagents(idx),
                }
            else
                failed[#failed + 1] = idx
            end
        end
    end

    return rows, failed
end

-- Scans whatever supported profession window is open into its own book.
-- The first profession ever scanned becomes the active one.
function Scanner.Scan(opts)
    opts = opts or {}

    local profile = ns.Prof.OpenWindow()
    if not profile then
        if not opts.silent then
            local line = GetTradeSkillLine and GetTradeSkillLine()
            if line and line ~= "" and line ~= "UNKNOWN" then
                ns.Print(line .. " is not a supported profession yet. Supported: "
                    .. table.concat(ns.Professions.Order, ", ") .. ".")
            else
                ns.Print("open a profession window first, then run /tm scan.")
            end
        end
        return 0, 0, 0
    end

    local pd = ns.Prof.DB(profile.key)
    local saved = SaveFilters()
    ClearFilters()

    local rows, failed = CollectRows()

    local function commit(finalRows, finalFailed)
        local book, added = Scanner.MergeBook(pd.book, finalRows)
        pd.book = book
        pd.bookScannedAt = ns.Now()
        pd.bookPartial = #finalFailed > 0
        pd.bookDirty = false

        local becameActive = false
        if not ns.db.activeProfession then
            ns.db.activeProfession = profile.key
            becameActive = true
        end
        if ns.Events then ns.Events.RebuildIndex() end
        if ns.Annotators then ns.Annotators.Annotate(profile, book) end
        if ns.Minimap and ns.Minimap.UpdateIcon then ns.Minimap.UpdateIcon() end

        RestoreFilters(saved)

        if not opts.silent then
            local n, products, noun = ns.Prof.BookCounts(profile, book)
            ns.Print(string.format("%s: scanned %d recipes (%d %s), %d new since last scan.",
                profile.name, #finalRows, products, noun, added))
            if #finalFailed > 0 then
                ns.Print(string.format(
                    "|cffff9900%d rows could not be read (item data not cached). Run /tm scan again.|r",
                    #finalFailed))
            end
        end
        if becameActive then
            ns.Print(profile.name .. " is now the active profession. /tm prof to change it.")
        elseif ns.db.activeProfession ~= profile.key and not opts.silent then
            ns.Print(string.format("|cff888888(%s scanned; %s stays active. /tm prof %s to switch)|r",
                profile.name, ns.Prof.Current().name, profile.key))
        end
        if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end

        if Scanner.initiatedByUs then
            Scanner.initiatedByUs = false
            if CloseTradeSkill then CloseTradeSkill() end
        end

        return added, #finalRows, #finalFailed
    end

    -- Uncached items return nil links on the first pass. Give them one retry.
    if #failed > 0 then
        C_Timer.After(0.5, function()
            if ns.Prof.OpenWindow() == profile then
                local retryRows, retryFailed = CollectRows()
                commit(retryRows, retryFailed)
            else
                commit(rows, failed)
            end
        end)
        return 0, #rows, #failed
    end

    return commit(rows, failed)
end
