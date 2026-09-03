local addonName, ns = ...

ns.Log = ns.Log or {}
local Log = ns.Log

local MAX_ENTRIES = 100

-- Shared with the UI so a verdict keeps one colour everywhere.
local VERDICT_COLOR = {
    invite = "|cff44ff44",
    vetoed = "|cffff4444",
    lowscore = "|cffffcc00",
}
Log.VERDICT_COLOR = VERDICT_COLOR

function Log.Push(log, entry)
    table.insert(log, 1, entry)
    for i = #log, MAX_ENTRIES + 1, -1 do
        table.remove(log, i)
    end
    return log
end

local MAX_CAPTURE = 1500

-- Written to SavedVariables, so this is what gets read off disk after a
-- /reload. Store names as well as ids or the file is unreadable on its own.
function Log.Capture(player, msg, result, now)
    ns.db.capture = ns.db.capture or {}
    table.insert(ns.db.capture, 1, {
        at = now,
        player = player,
        msg = ns.Util.StripEscapes(msg),
        verdict = result.verdict,
        reason = result.reason,
        blocked = result.blocked,
        sellerScore = result.sellerScore,
        buyerScore = result.buyerScore,
        sellerHits = result.sellerHits,
        buyerHits = result.buyerHits,
    })
    for i = #ns.db.capture, MAX_CAPTURE + 1, -1 do
        table.remove(ns.db.capture, i)
    end
end

function Log.Add(player, msg, matched, result, now, book)
    book = book or ns.Book()
    local ids, names = {}, {}
    for _, h in ipairs(matched or {}) do
        ids[#ids + 1] = h.itemID
        local e = book[h.itemID]
        names[#names + 1] = string.format("%s (%s)", e and e.name or h.itemID, h.tier)
    end

    return Log.Push(ns.db.log, {
        at = now,
        player = player,
        msg = ns.Util.StripEscapes(msg),
        matched = ids,
        matchedNames = names,
        profession = result.profession,
        verdict = result.verdict,
        reason = result.reason,
        blocked = result.blocked,
        sellerScore = result.sellerScore,
        sellerHits = result.sellerHits,
        buyerScore = result.buyerScore,
        buyerHits = result.buyerHits,
    })
end

-- How far back any one view reads. Capture holds 1500 lines and the panel shows
-- 100 of them: reading the whole pile on every click buys nothing you can see.
local WINDOW = 300
Log.WINDOW = WINDOW

-- Pure. The last `window` messages the addon looked at, newest first: the
-- decisions it recorded, plus the raw capture of lines dropped for matching
-- nothing. That second half is what makes an "All" view honest -- without it the
-- log shows only what the addon acted on, which is not the same as everything it
-- saw.
--
-- Both lists are kept newest-first, so this walks them together and stops as
-- soon as the window is full: no sort, and no reading past what is shown. A
-- message in both is returned once, as the log's copy, which is the one carrying
-- the matches and the profession.
function Log.Window(log, capture, window)
    window = window or WINDOW
    log, capture = log or {}, capture or {}
    local out, seen = {}, {}
    local i, j = 1, 1
    while #out < window do
        local a, b = log[i], capture[j]
        local e
        if a and b then
            if (a.at or 0) >= (b.at or 0) then e = a; i = i + 1 else e = b; j = j + 1 end
        elseif a then
            e = a; i = i + 1
        elseif b then
            e = b; j = j + 1
        else
            break
        end
        local key = string.format("%s|%s|%s", e.player or "", e.at or 0, e.msg or "")
        if not seen[key] then
            seen[key] = true
            out[#out + 1] = e
        end
    end
    return out
end

-- Pure. verdict and profession are each optional. Returns at most n entries and
-- the number the filters held back, so a filtered list can say why it is short
-- rather than looking like the log was lost.
function Log.Filter(entries, n, verdict, profession)
    local out, hidden = {}, 0
    for _, e in ipairs(entries or {}) do
        if (not verdict or e.verdict == verdict)
            and (not profession or e.profession == profession) then
            if #out < n then out[#out + 1] = e end
        else
            hidden = hidden + 1
        end
    end
    return out, hidden
end

-- Newest first. verdict filters to one of invite/vetoed/lowscore when given.
function Log.Recent(n, verdict)
    local out = {}
    for i = 1, #ns.db.log do
        if #out >= n then break end
        local e = ns.db.log[i]
        if not verdict or e.verdict == verdict then out[#out + 1] = e end
    end
    return out
end

function Log.Describe(entry)
    local color = VERDICT_COLOR[entry.verdict] or "|cffffffff"
    return string.format("%s%s|r %s (s%d/b%d, %s): %s",
        color, entry.verdict, entry.player or "?",
        entry.sellerScore or 0, entry.buyerScore or 0,
        entry.reason or "?", entry.msg or "")
end

-- Pure. The signals that fired, sellers then buyers, each heaviest first and ties
-- broken by name. A pairs() walk shuffled between refreshes and made a row's own
-- text change height under the reader.
function Log.SortedHits(entry)
    local out = {}
    for k, v in pairs(entry.sellerHits or {}) do
        out[#out + 1] = { sign = "-", name = k, weight = v, seller = true }
    end
    for k, v in pairs(entry.buyerHits or {}) do
        out[#out + 1] = { sign = "+", name = k, weight = v }
    end
    table.sort(out, function(a, b)
        if (a.seller or false) ~= (b.seller or false) then return a.seller or false end
        if a.weight ~= b.weight then return a.weight > b.weight end
        return a.name < b.name
    end)
    return out
end

-- Which named signals fired, for the "why did it decide that" case.
function Log.DescribeHits(entry)
    local parts = {}
    for _, h in ipairs(Log.SortedHits(entry)) do
        parts[#parts + 1] = string.format("%s%s%s %d|r",
            h.seller and "|cffff8888" or "|cff88ff88", h.sign, h.name, h.weight)
    end
    if #parts == 0 then return "  (no signals)" end
    return "  " .. table.concat(parts, ", ")
end
