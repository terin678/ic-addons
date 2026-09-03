local addonName, ns = ...

ns.Scanner = ns.Scanner or {}
local Scanner = ns.Scanner

-- Pure. Folds a fresh scan into the stored book without losing user choices.
-- The merge itself is LibICTradeSkill's; this adds TradeMaster's defaults.
function Scanner.MergeBook(oldBook, scanned)
    local book, added = LibStub("LibICTradeSkill-1.0"):MergeBook(oldBook, scanned,
        { preserve = { "advertise", "match", "aliases", "stats" } })
    for _, e in pairs(book) do
        if e.advertise == nil then e.advertise = true end
        if e.match == nil then e.match = true end
        e.aliases = e.aliases or {}
    end
    return book, added
end

-- Pure. Auto-scan clears the tradeskill window's filters as a side effect, so
-- it only earns that disruption when it might actually learn something.
function Scanner.ShouldAutoScan(bookCount, dirty, scannedAt, now, staleSec)
    if bookCount == 0 then return true end
    if dirty then return true end
    return (now - (scannedAt or 0)) > staleSec
end

local Lib = LibStub("LibICTradeSkill-1.0")

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

    -- The library clears the window filters, reads, restores them, and retries
    -- once for items not yet in the cache. The callback is synchronous when
    -- no retry is needed.
    local result
    Lib:ScanOpen(function(rows, failed) result = { commit(rows, failed) } end)
    if result then return result[1], result[2], result[3] end
    return 0, 0, 0
end

--------------------------------------------------------------------------------
-- Bind on Pickup reagents
--------------------------------------------------------------------------------

-- Both live in LibICTradeSkill; kept here so callers read Scanner.*.
function Scanner.MissingBoP(e) return Lib:MissingBoP(e) end
function Scanner.DescribeMissing(missing, withCounts) return Lib:DescribeMissing(missing, withCounts) end
