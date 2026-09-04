local addonName, ns = ...

-- Market saturation: how many distinct crafters are advertising in Trade versus
-- how many customers are asking, per profession, over a rolling window. It only
-- reports and suggests; nothing here changes a setting on its own.
--
-- Why its own buffer rather than ns.db.log: the log holds 100 entries and never
-- records a line whose reason is "no item match" (Classifier bails before the
-- veto check), which is exactly where a competitor's "LW LFW" lands when some
-- other profession is active.

ns.Market = ns.Market or {}
local Market = ns.Market

local MAX_AGE_SEC = 86400
local MAX_SAMPLES = 2000
local MSG_MAX = 60
local PRUNE_EVERY_SEC = 60

Market.WINDOWS = {
    { key = "m15", label = "15m", seconds = 900 },
    { key = "h1", label = "1h", seconds = 3600 },
    { key = "today", label = "Today", seconds = MAX_AGE_SEC },
}

-- The window every headline number and the suggestion are read over.
local MAIN_WINDOW = 3600

--------------------------------------------------------------------------------
-- Classification
--------------------------------------------------------------------------------

-- Words that name a profession in chat: its abbreviations, what its crafters are
-- called, its bark tag and its own name. Memoised per profile.
local tagCache = {}
function Market.Tags(profile)
    if not profile then return {} end
    local hit = tagCache[profile.key]
    if hit then return hit end
    local tags, seen = {}, {}
    local function add(w)
        w = w and w:lower()
        if w and w ~= "" and not seen[w] then
            seen[w] = true
            tags[#tags + 1] = w
        end
    end
    for _, a in ipairs(profile.abbrevs or {}) do add(a) end
    for _, p in ipairs(profile.personNouns or {}) do add(p) end
    add(profile.barkTag)
    add(profile.name)
    tagCache[profile.key] = tags
    return tags
end

-- A seller phrase that names no profession ("wts") only counts when the line
-- also carries a profession tag; one that names its own ("jc lfw", "will cut")
-- stands on its own.
local GENERIC_SELLER = {
    ["lfw"] = true, ["lf work"] = true, ["looking for work"] = true,
    ["wts"] = true, ["selling"] = true,
}

local GENERIC_BUYER = {
    "wtb", "want to buy", "buying", "need", "have mats", "got mats",
    "have the mats", "will tip", "paying", "pay for", "crafter",
}

local function Tagged(norm, profile)
    for _, tag in ipairs(Market.Tags(profile)) do
        if ns.Util.HasPhrase(norm, tag) then return true end
    end
    return false
end

-- Pure. Decides whether a Trade line is a competitor advertising or a customer
-- asking, and which professions it is about. Every profile is checked, not just
-- the one that matched an item, so "LW LFW" counts for leatherworking while
-- Jewelcrafting is active. Returns kind ("seller"|"buyer"|nil) and sorted keys.
function Market.ClassifyLine(result, norm, profiles, hasItemMatch)
    if not norm or norm == "" then return nil, {} end
    profiles = profiles or ns.Professions.Profiles

    local sellers, buyers = {}, {}

    for key, profile in pairs(profiles) do
        if key ~= "generic" then
            local tagged = Tagged(norm, profile)
            local vocab = profile.vocab or {}
            local isSeller, isBuyer = false, false

            for _, phrase in ipairs(vocab.vetoWords or {}) do
                if ns.Util.HasPhrase(norm, phrase) then
                    if GENERIC_SELLER[phrase] then
                        if tagged then isSeller = true end
                    else
                        isSeller = true
                    end
                end
            end

            -- The classifier already judged this line for one profession; reuse
            -- that verdict rather than second-guessing it.
            if result and result.profession == key then
                if result.verdict == "vetoed" and result.reason ~= "never invite" then
                    isSeller = true
                elseif result.reason == "seller score" then
                    isSeller = true
                elseif result.verdict == "invite" or result.professionRequest then
                    isBuyer = true
                end
            end

            if not isSeller then
                for _, phrase in ipairs(vocab.professionWords or {}) do
                    if ns.Util.HasPhrase(norm, phrase) then isBuyer = true break end
                end
                if not isBuyer and tagged then
                    for _, phrase in ipairs(GENERIC_BUYER) do
                        if ns.Util.HasPhrase(norm, phrase) then isBuyer = true break end
                    end
                end
                if not isBuyer and tagged and hasItemMatch
                    and result and (result.buyerScore or 0) > 0 then
                    isBuyer = true
                end
            end

            if isSeller then
                sellers[#sellers + 1] = key
            elseif isBuyer then
                buyers[#buyers + 1] = key
            end
        end
    end

    -- One line is one or the other. Someone advertising is competition even if
    -- they also say "need mats".
    local keys = #sellers > 0 and sellers or buyers
    if #keys == 0 then return nil, {} end
    table.sort(keys)
    return (#sellers > 0) and "seller" or "buyer", keys
end

--------------------------------------------------------------------------------
-- Storage
--------------------------------------------------------------------------------

local function Store(db)
    db.market = db.market or { samples = {}, prunedAt = 0 }
    db.market.samples = db.market.samples or {}
    return db.market
end

-- Drops anything past a day old, then caps the ring. Samples are appended in
-- time order, so the old ones are always at the front.
function Market.Prune(db, now)
    local m = Store(db)
    local cut = now - MAX_AGE_SEC
    local first = 1
    while m.samples[first] and (m.samples[first].at or 0) < cut do first = first + 1 end
    if first > 1 then
        local kept = {}
        for i = first, #m.samples do kept[#kept + 1] = m.samples[i] end
        m.samples = kept
    end
    while #m.samples > MAX_SAMPLES do table.remove(m.samples, 1) end
    m.prunedAt = now
    return #m.samples
end

function Market.Record(db, now, kind, profKey, who, msg)
    if not kind or not profKey then return end
    local m = Store(db)
    m.samples[#m.samples + 1] = {
        at = now, prof = profKey, kind = kind, who = who,
        msg = msg and ns.Util.StripEscapes(msg):sub(1, MSG_MAX) or nil,
    }
    if (now - (m.prunedAt or 0)) > PRUNE_EVERY_SEC or #m.samples > MAX_SAMPLES then
        Market.Prune(db, now)
    end
end

-- The one impure entry point, called from Events for Trade lines.
function Market.Observe(db, now, who, text, norm, result, hasItemMatch)
    local kind, keys = Market.ClassifyLine(result, norm, ns.Professions.Profiles, hasItemMatch)
    if not kind then return nil end
    for _, key in ipairs(keys) do
        Market.Record(db, now, kind, key, who, text)
    end
    return kind, keys
end

--------------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------------

-- Distinct players first, posts second: one crafter reposting every three
-- minutes is not a crowded market.
function Market.Counts(db, now, profKey, windowSec)
    local m = Store(db)
    local since = now - (windowSec or MAIN_WINDOW)
    local sellerSet, buyerSet = {}, {}
    local sellerPosts, buyerPosts = 0, 0
    for i = #m.samples, 1, -1 do
        local s = m.samples[i]
        if (s.at or 0) < since then break end
        if not profKey or s.prof == profKey then
            if s.kind == "seller" then
                sellerPosts = sellerPosts + 1
                if s.who then sellerSet[s.who] = true end
            elseif s.kind == "buyer" then
                buyerPosts = buyerPosts + 1
                if s.who then buyerSet[s.who] = true end
            end
        end
    end
    local sellers, buyers = 0, 0
    for _ in pairs(sellerSet) do sellers = sellers + 1 end
    for _ in pairs(buyerSet) do buyers = buyers + 1 end
    return sellers, buyers, sellerPosts, buyerPosts
end

-- The most recent samples, newest first, optionally for one profession.
function Market.Recent(db, n, profKey)
    local m = Store(db)
    local out = {}
    for i = #m.samples, 1, -1 do
        if #out >= n then break end
        local s = m.samples[i]
        if not profKey or s.prof == profKey then out[#out + 1] = s end
    end
    return out
end

-- Pure.
function Market.Label(sellers, buyers)
    local ratio = sellers / math.max(buyers, 1)
    if sellers <= 1 then return "quiet", ratio end
    if sellers >= 3 and ratio >= 2 then return "crowded", ratio end
    return "balanced", ratio
end

function Market.LabelColor(label)
    if label == "crowded" then return "|cffff8888" end
    if label == "quiet" then return "|cff88ff88" end
    return "|cffffffff"
end

-- Pure. A suggestion only: bark less into a crowded channel, more when there is
-- demand and nobody answering it. Rounded to 30s and kept inside the range the
-- interval slider allows.
function Market.SuggestInterval(base, sellers, buyers)
    base = base or 180
    local label = Market.Label(sellers, buyers)
    local out = base
    if label == "crowded" then
        out = base + 120
    elseif label == "quiet" and buyers >= 2 then
        out = base - 60
    end
    out = math.floor(out / 30 + 0.5) * 30
    return math.max(30, math.min(600, out))
end

-- One line for the status bar, the minimap tooltip and /tm market.
function Market.Summary(db, now, profKey, intervalSec)
    local sellers, buyers = Market.Counts(db, now, profKey, MAIN_WINDOW)
    if sellers == 0 and buyers == 0 then
        return "market: |cff888888nothing seen in the last hour|r"
    end
    local label = Market.Label(sellers, buyers)
    local suggest = Market.SuggestInterval(intervalSec, sellers, buyers)
    return string.format("market: %s%s|r %dS/%dB 1h, suggest %ds",
        Market.LabelColor(label), label, sellers, buyers, suggest)
end
