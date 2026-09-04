-- Book.lua - Scanned recipe books, one per profession, read through
-- LibICTradeSkill (ICLibs). A book is per character: recipes belong to the
-- character that knows them, whichever database the price data lives in.
local addonName = "MalexisAuctionWatcher"
local MAW = _G.MalexisAuctionWatcher or {}

local function Lib()
    return LibStub and LibStub("LibICTradeSkill-1.0", true) or nil
end

local function Books()
    MalexisAuctionWatcherCharDB = MalexisAuctionWatcherCharDB or {}
    MalexisAuctionWatcherCharDB.books = MalexisAuctionWatcherCharDB.books or {}
    return MalexisAuctionWatcherCharDB.books
end

-- Sorted profession names that have a scanned book on this character.
function MAW:GetBookNames()
    local out = {}
    for line, book in pairs(Books()) do
        if book.entries and next(book.entries) then out[#out + 1] = line end
    end
    table.sort(out)
    return out
end

-- { scannedAt = <time>, entries = { [itemID] = row } } or nil.
function MAW:GetBook(line)
    return line and Books()[line] or nil
end

-- Rows of a book as a list, stale ones dropped, sorted by header then name.
function MAW:GetBookRows(line)
    local book = self:GetBook(line)
    local rows = {}
    if not book then return rows end
    for _, e in pairs(book.entries or {}) do
        if not e.stale then rows[#rows + 1] = e end
    end
    table.sort(rows, function(a, b)
        if (a.header or "") ~= (b.header or "") then return (a.header or "") < (b.header or "") end
        return (a.name or "") < (b.name or "")
    end)
    return rows
end

-- The shape ImportProfessionRecipe expects. The recipe keeps the window's
-- line name ("Transmute: Primal Might"), the product is the item it makes.
function MAW:BookRowToImport(row)
    local reagents = {}
    for _, r in ipairs(row.reagentList or {}) do
        reagents[#reagents + 1] = { item = r.name, id = r.itemID, count = r.count }
    end
    if #reagents == 0 then
        for id, count in pairs(row.reagents or {}) do
            reagents[#reagents + 1] = { item = GetItemInfo(id) or ("item " .. id), id = id, count = count }
        end
    end
    return {
        name = row.skillName or row.name,
        product = row.name,
        productID = row.itemID,
        numMade = row.numMade or 1,
        reagents = reagents,
    }
end

-- Scans whatever profession window is open into its book. Runs on window
-- open (silent) and from the recipe book dialog. opts.silent hides the
-- summary line; opts.onDone(line, rows, failed) runs after the merge.
function MAW:ScanOpenBook(opts)
    opts = opts or {}
    local lib = Lib()
    if not lib then
        if not opts.silent then MAW.Print("ICLibs is not loaded, cannot read the recipe book.") end
        return false
    end
    local line = lib:OpenLine()
    if not line then
        if not opts.silent then MAW.Print("open a profession window first (Enchanting is not supported).") end
        return false
    end

    lib:ScanOpen(function(rows, failed, scannedLine)
        if not scannedLine then return end
        local books = Books()
        local book = books[scannedLine] or { entries = {} }
        local entries, added = lib:MergeBook(book.entries, rows)
        book.entries = entries
        book.scannedAt = time()
        book.partial = #failed > 0
        books[scannedLine] = book

        if not opts.silent then
            MAW.Printf("%s book scanned, %d recipes (%d new).%s", scannedLine,
                #rows, added, #failed > 0 and (" " .. #failed .. " could not be read; scan again.") or "")
        end
        if opts.onDone then opts.onDone(scannedLine, rows, failed) end
        local dlg = _G.MalexisAuctionWatcherRecipeDialog
        if dlg and dlg.OnBookScanned then dlg.OnBookScanned(scannedLine) end
    end)
    return true
end

_G.MalexisAuctionWatcher = MAW
