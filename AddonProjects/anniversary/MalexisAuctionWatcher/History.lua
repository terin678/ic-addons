-- History.lua - Long-lived price history store and periodicity analytics
local addonName = "MalexisAuctionWatcher"
local MAW = _G.MalexisAuctionWatcher or {}

local SECONDS_PER_DAY = 86400
local DEFAULT_HISTORY_DAYS = 180
local MIN_SAMPLES_FOR_CONFIDENCE = 3

local WEEKDAY_NAMES = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"}

-- Day index: whole UTC days since the epoch
function MAW:DayIndexFromTime(timestamp)
    return math.floor((timestamp or time()) / SECONDS_PER_DAY)
end

-- Local-time hour (0-23) for a timestamp
local function HourFromTime(timestamp)
    local t = date("*t", timestamp or time())
    return t and t.hour or 0
end

function MAW:GetHistoryDays()
    local settings = MalexisAuctionWatcherDB and MalexisAuctionWatcherDB.settings
    return (settings and settings.historyDays) or DEFAULT_HISTORY_DAYS
end

-- Make sure an item has a history table, returns it
function MAW:EnsureHistory(itemData)
    if not itemData.history then
        itemData.history = { days = {}, hours = {}, src = {} }
    end
    itemData.history.days = itemData.history.days or {}
    itemData.history.hours = itemData.history.hours or {}
    itemData.history.src = itemData.history.src or {}
    return itemData.history
end

-- Drop day buckets older than the retention window
function MAW:PruneHistory(history)
    local cutoff = self:DayIndexFromTime() - self:GetHistoryDays()
    for day in pairs(history.days) do
        if day < cutoff then
            history.days[day] = nil
            history.src[day] = nil
        end
    end
end

local function MergeDay(bucket, low, high, sum, n)
    if not bucket then
        return { l = low, h = high, s = sum, n = n }
    end
    if low < bucket.l then bucket.l = low end
    if high > bucket.h then bucket.h = high end
    bucket.s = bucket.s + sum
    bucket.n = bucket.n + n
    return bucket
end

-- Record a single observed per-unit price
function MAW:RecordHistory(itemName, unitPrice, source, timestamp)
    if not unitPrice or unitPrice <= 0 then
        return
    end
    local db = self:GetActiveDB()
    local itemData = db.items[itemName]
    if not itemData then
        return
    end

    source = source or "scan"
    timestamp = timestamp or time()
    local history = self:EnsureHistory(itemData)
    local day = self:DayIndexFromTime(timestamp)

    history.days[day] = MergeDay(history.days[day], unitPrice, unitPrice, unitPrice, 1)
    -- Our own scans take precedence over external writers for the day tag
    if source == "scan" or history.src[day] ~= "scan" then
        history.src[day] = source
    end

    local hour = HourFromTime(timestamp)
    local hb = history.hours[hour]
    if not hb then
        history.hours[hour] = { l = unitPrice, h = unitPrice, s = unitPrice, n = 1 }
    else
        if unitPrice < hb.l then hb.l = unitPrice end
        if not hb.h or unitPrice > hb.h then hb.h = unitPrice end
        hb.s = hb.s + unitPrice
        hb.n = hb.n + 1
    end

    self:PruneHistory(history)
end

-- Merge an external daily low/high into the store without touching hour buckets.
-- Days already written by our own scans are left alone.
function MAW:BackfillHistory(itemName, dayIndex, low, high, source)
    if not low or low <= 0 then
        return false
    end
    high = (high and high > 0) and high or low

    local db = self:GetActiveDB()
    local itemData = db.items[itemName]
    if not itemData then
        return false
    end

    local history = self:EnsureHistory(itemData)
    if dayIndex < self:DayIndexFromTime() - self:GetHistoryDays() then
        return false
    end
    if history.src[dayIndex] == "scan" then
        return false
    end

    local existing = history.days[dayIndex]
    if existing and existing.src_backfilled then
        -- Already merged this day from a backfill; only widen the range
        if low < existing.l then existing.l = low end
        if high > existing.h then existing.h = high end
        return true
    end

    local mid = (low + high) / 2
    local bucket = MergeDay(existing, low, high, mid, 1)
    bucket.src_backfilled = true
    history.days[dayIndex] = bucket
    history.src[dayIndex] = source or "ext"
    return true
end

-- Seed history from the short-term prices list (migration for older data)
function MAW:MigrateHistory()
    local dbs = { MalexisAuctionWatcherDB, MalexisAuctionWatcherCharDB }
    for _, db in ipairs(dbs) do
        if db and db.items then
            for itemName, itemData in pairs(db.items) do
                if not itemData.history then
                    local history = self:EnsureHistory(itemData)
                    for _, entry in ipairs(itemData.prices or {}) do
                        local price = (entry.buyoutPerUnit and entry.buyoutPerUnit > 0) and entry.buyoutPerUnit
                            or entry.minBidPerUnit or entry.pricePerUnit
                        if price and price > 0 and entry.timestamp then
                            local day = self:DayIndexFromTime(entry.timestamp)
                            history.days[day] = MergeDay(history.days[day], price, price, price, 1)
                            history.src[day] = entry.source or "scan"
                            local hour = HourFromTime(entry.timestamp)
                            local hb = history.hours[hour]
                            if not hb then
                                history.hours[hour] = { l = price, h = price, s = price, n = 1 }
                            else
                                if price < hb.l then hb.l = price end
                                if not hb.h or price > hb.h then hb.h = price end
                                hb.s = hb.s + price
                                hb.n = hb.n + 1
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Build a series of points for charting.
-- mode: "daily" (span days), "weekday", "monthday", "hour"
-- Each point: { label, low, avg, high, n }
function MAW:GetSeries(itemName, mode, span)
    local db = self:GetActiveDB()
    local itemData = db.items[itemName]
    if not itemData then
        return {}
    end
    local history = self:EnsureHistory(itemData)
    local points = {}

    if mode == "daily" then
        span = span or 30
        local today = self:DayIndexFromTime()
        for day = today - span + 1, today do
            local b = history.days[day]
            local t = date("*t", day * SECONDS_PER_DAY)
            local label = string.format("%d/%d", t.month, t.day)
            if b and b.n > 0 then
                table.insert(points, { label = label, low = b.l, avg = b.s / b.n, high = b.h, n = b.n,
                    src = history.src[day], day = day })
            else
                table.insert(points, { label = label, n = 0, day = day })
            end
        end
    elseif mode == "hour" then
        for hour = 0, 23 do
            local b = history.hours[hour]
            local label = string.format("%02d", hour)
            if b and b.n > 0 then
                table.insert(points, { label = label, low = b.l, avg = b.s / b.n, high = b.h or (b.s / b.n), n = b.n })
            else
                table.insert(points, { label = label, n = 0 })
            end
        end
    else
        -- Aggregate day buckets by weekday or day-of-month
        local count = (mode == "weekday") and 7 or 31
        local agg = {}
        for i = 1, count do
            agg[i] = { l = nil, h = nil, s = 0, n = 0 }
        end
        for day, b in pairs(history.days) do
            if b.n > 0 then
                local t = date("*t", day * SECONDS_PER_DAY)
                local idx = (mode == "weekday") and t.wday or t.day
                local a = agg[idx]
                if a then
                    if not a.l or b.l < a.l then a.l = b.l end
                    if not a.h or b.h > a.h then a.h = b.h end
                    a.s = a.s + b.s
                    a.n = a.n + b.n
                end
            end
        end
        for i = 1, count do
            local a = agg[i]
            local label = (mode == "weekday") and WEEKDAY_NAMES[i] or tostring(i)
            if a.n > 0 then
                table.insert(points, { label = label, low = a.l, avg = a.s / a.n, high = a.h, n = a.n })
            else
                table.insert(points, { label = label, n = 0 })
            end
        end
    end

    return points
end

-- Find the cheapest and priciest bucket by average.
-- Returns { best = {index,label,avg,n}, worst = {...}, spreadPct, confident, samples }
function MAW:AnalyzePeriodicity(itemName, mode, span)
    local points = self:GetSeries(itemName, mode, span)
    local best, worst
    local samples = 0
    for i, p in ipairs(points) do
        if p.n and p.n > 0 and p.avg then
            samples = samples + p.n
            if not best or p.avg < best.avg then
                best = { index = i, label = p.label, avg = p.avg, n = p.n }
            end
            if not worst or p.avg > worst.avg then
                worst = { index = i, label = p.label, avg = p.avg, n = p.n }
            end
        end
    end

    if not best or not worst then
        return { points = points, samples = samples, confident = false }
    end

    local spreadPct = 0
    if best.avg > 0 then
        spreadPct = ((worst.avg - best.avg) / best.avg) * 100
    end

    local confident = best.n >= MIN_SAMPLES_FOR_CONFIDENCE
        and worst.n >= MIN_SAMPLES_FOR_CONFIDENCE
        and best.index ~= worst.index

    return {
        points = points,
        best = best,
        worst = worst,
        spreadPct = spreadPct,
        confident = confident,
        samples = samples,
    }
end

_G.MalexisAuctionWatcher = MAW
