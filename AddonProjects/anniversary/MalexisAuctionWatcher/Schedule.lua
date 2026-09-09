-- Schedule.lua - The week as a grid: when an item is expected cheap or dear, and whether it was
local addonName = "MalexisAuctionWatcher"
local MAW = _G.MalexisAuctionWatcher or {}

--[[
Prices on a realm move with the week: raids reset on Tuesday, consumables spike the
evening before, materials sag mid-week, weekends bring more players. The history store
keeps a weekday view and an hour-of-day view but never the two together, so this file
keeps its own store: the raw observations of the last few weeks, as a flat ring of
(timestamp, price) pairs on history.obs, sliced onto a 7 x 6 grid at read time.

Slicing at read time is what makes the clock switch free. Nothing on disk knows whether
it was recorded under server or local time; the offset is applied when the grid is drawn.

Everything but the server offset is pure and has cases in Tests.lua.
]]

local SLOTS_PER_DAY = 6
local BLOCK_HOURS = 4
local SLOTS = 7 * SLOTS_PER_DAY
local SECONDS_PER_DAY = 86400
local SECONDS_PER_WEEK = 7 * SECONDS_PER_DAY
local MAX_OBS_PAIRS = 600            -- per item; nine weeks of several scans a day
local FLAT_SPREAD_PCT = 5            -- under this, the week has no cheap or dear end
local MIN_JUDGED = 3                 -- action slots judged before a pattern can be set aside
local MIN_SAMPLES = 3                -- history samples a weekday or a block needs to model from

MAW.SCHEDULE_MIN_SAMPLES = MIN_SAMPLES

MAW.SCHEDULE_SLOTS, MAW.SLOTS_PER_DAY = SLOTS, SLOTS_PER_DAY
MAW.BLOCK_LABELS = { "00-04", "04-08", "08-12", "12-16", "16-20", "20-24" }
MAW.WEEKDAY_NAMES = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }

-- Seconds to add to a UTC timestamp to get local wall-clock time (handles DST per timestamp)
local function LocalOffset(timestamp)
    local u = date("!*t", timestamp)
    u.isdst = date("*t", timestamp).isdst
    return difftime(timestamp, time(u))
end

--------------------------------------------------------------------------------
-- The clock
--------------------------------------------------------------------------------

-- Seconds to add to a local timestamp so date("*t") reads it as the realm's wall clock.
-- GetGameTime gives the server's hour and minute; the difference to this PC's clock,
-- rounded to the quarter hour, is the offset. Cached at login; zero when the client
-- cannot say (headless).
MAW.serverOffset = 0

function MAW.RefreshServerOffset()
    if type(GetGameTime) ~= "function" then
        MAW.serverOffset = 0
        return 0
    end
    local sh, sm = GetGameTime()
    local l = date("*t")
    if not sh or not sm or not l then return MAW.serverOffset end
    local diff = (sh * 60 + sm) - (l.hour * 60 + l.min)
    if diff > 720 then diff = diff - 1440 elseif diff < -720 then diff = diff + 1440 end
    diff = math.floor(diff / 15 + 0.5) * 15
    MAW.serverOffset = diff * 60
    return MAW.serverOffset
end

function MAW:ScheduleSettings()
    local s = MalexisAuctionWatcherDB and MalexisAuctionWatcherDB.settings
    if not s then return { clock = "server", tolerancePct = 10, weeks = 8, minWeeks = 2, minReliabilityPct = 50, weekStart = 3 } end
    s.schedule = s.schedule or {}
    local sc = s.schedule
    sc.clock = sc.clock or "server"
    sc.tolerancePct = sc.tolerancePct or 10
    sc.weeks = sc.weeks or 8
    sc.minWeeks = sc.minWeeks or 2
    sc.minReliabilityPct = sc.minReliabilityPct or 50
    sc.weekStart = sc.weekStart or 3
    return sc
end

-- The offset the grid is drawn under: the realm's, or none for the wall clock.
function MAW:ClockOffset()
    if self:ScheduleSettings().clock == "local" then return 0 end
    return MAW.serverOffset or 0
end

--------------------------------------------------------------------------------
-- Pure: where a moment falls on the grid
--------------------------------------------------------------------------------

--[[
Pure. Returns slot (1..42), wday (1 = Sunday), block (1..6) and a week index.

The slot is by calendar weekday so a cell means the same thing whatever day the week
starts on; the week index turns over on weekStart (the raid reset, Tuesday, by default),
so "this week" and "last week" are the weeks a raider means.
]]
function MAW.ScheduleSlot(t, offset, weekStart)
    local shifted = t + (offset or 0)
    local d = date("*t", shifted)
    local block = math.floor(d.hour / BLOCK_HOURS) + 1
    local slot = (d.wday - 1) * SLOTS_PER_DAY + block
    local dayIndex = math.floor((shifted + LocalOffset(shifted)) / SECONDS_PER_DAY)
    local sinceStart = (d.wday - (weekStart or 3)) % 7
    local weekIndex = math.floor((dayIndex - sinceStart) / 7)
    return slot, d.wday, block, weekIndex, d.hour
end

-- Pure. The slot's position within a week that starts on weekStart: 1 is the first
-- block of the first day, 42 the last of the last. Behind and ahead are read off this.
local function SlotPosition(slot, weekStart)
    local wday = math.floor((slot - 1) / SLOTS_PER_DAY) + 1
    local block = (slot - 1) % SLOTS_PER_DAY + 1
    return ((wday - (weekStart or 3)) % 7) * SLOTS_PER_DAY + block, wday, block
end
MAW.SlotPosition = SlotPosition

--------------------------------------------------------------------------------
-- Pure: the store
--------------------------------------------------------------------------------

-- Pure. Drops pairs older than cutoff, then the oldest beyond maxPairs, in place, so
-- the saved table keeps its identity.
function MAW.PruneObs(obs, cutoff, maxPairs)
    obs = obs or {}
    local kept = {}
    for i = 1, #obs - 1, 2 do
        local t, p = obs[i], obs[i + 1]
        if t and p and t >= (cutoff or 0) then
            kept[#kept + 1] = t
            kept[#kept + 1] = p
        end
    end
    local limit = (maxPairs or MAX_OBS_PAIRS) * 2
    local drop = math.max(0, #kept - limit)
    for i = #obs, 1, -1 do obs[i] = nil end
    for i = drop + 1, #kept do obs[#obs + 1] = kept[i] end
    return obs
end

-- Pure. The prices ring (newest first) as observation pairs, oldest first, so an item
-- tracked before this store existed starts with what the ring remembers.
function MAW.SeedObs(prices)
    local list = {}
    for _, entry in ipairs(prices or {}) do
        local price = (entry.buyoutPerUnit and entry.buyoutPerUnit > 0) and entry.buyoutPerUnit
            or entry.minBidPerUnit or entry.pricePerUnit
        if entry.timestamp and price and price > 0 then
            list[#list + 1] = { t = entry.timestamp, p = price }
        end
    end
    table.sort(list, function(a, b) return a.t < b.t end)
    local obs = {}
    for _, o in ipairs(list) do
        obs[#obs + 1] = o.t
        obs[#obs + 1] = o.p
    end
    return obs
end

-- Every item's ring, seeded once from its prices. Safe to run on every load.
function MAW:SeedScheduleObs()
    for _, db in ipairs({ MalexisAuctionWatcherDB, MalexisAuctionWatcherCharDB }) do
        if db and db.items then
            for _, itemData in pairs(db.items) do
                local history = self:EnsureHistory(itemData)
                if not history.obs then
                    history.obs = MAW.SeedObs(itemData.prices)
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Pure: the week modelled from the history the tab already has
--------------------------------------------------------------------------------

--[[
Pure. The History tab keeps months of buckets, a weekday view and an hour-of-day view,
and the raw ring starts empty. Until a block has real weeks behind it, its expectation
is modelled from those: the weekday's average times the block's share of the day.

    expected[wday, block] = weekdayAvg[wday] * blockAvg[block] / dayAvg

weekdayPoints and hourPoints are what GetSeries emits (label, avg, n; n == 0 is empty).
A weekday needs minSamples to count; a block with fewer takes the day's average as its
share (a factor of one), and says so with fewer samples. Returns
    { [slot] = { expected, samples, weekdaySamples, blockSamples } }, or {} with nothing.
]]
function MAW.ModelWeek(weekdayPoints, hourPoints, minSamples)
    minSamples = minSamples or MIN_SAMPLES
    local blockSum, blockN = {}, {}
    local cheapHour, dearHour = {}, {}      -- per block: the hour with the lowest and highest average
    local daySum, dayN = 0, 0
    for hour = 0, 23 do
        local p = hourPoints and hourPoints[hour + 1]
        if p and (p.n or 0) > 0 and p.avg then
            local b = math.floor(hour / BLOCK_HOURS) + 1
            blockSum[b] = (blockSum[b] or 0) + p.avg * p.n
            blockN[b] = (blockN[b] or 0) + p.n
            daySum = daySum + p.avg * p.n
            dayN = dayN + p.n
            if not cheapHour[b] or p.avg < cheapHour[b].avg then cheapHour[b] = { hour = hour, avg = p.avg } end
            if not dearHour[b] or p.avg > dearHour[b].avg then dearHour[b] = { hour = hour, avg = p.avg } end
        end
    end
    local dayAvg = dayN > 0 and daySum / dayN or nil

    local out = {}
    for wday = 1, 7 do
        local w = weekdayPoints and weekdayPoints[wday]
        if w and (w.n or 0) >= minSamples and w.avg then
            for b = 1, SLOTS_PER_DAY do
                local factor, bn = 1, 0
                if dayAvg and dayAvg > 0 and (blockN[b] or 0) >= minSamples then
                    factor = (blockSum[b] / blockN[b]) / dayAvg
                    bn = blockN[b]
                end
                out[(wday - 1) * SLOTS_PER_DAY + b] = {
                    expected = w.avg * factor,
                    samples = math.min(w.n, bn > 0 and bn or w.n),
                    weekdaySamples = w.n, blockSamples = bn,
                    cheapHour = cheapHour[b] and cheapHour[b].hour or nil,
                    dearHour = dearHour[b] and dearHour[b].hour or nil,
                }
            end
        end
    end
    return out
end

--------------------------------------------------------------------------------
-- Pure: one item's week
--------------------------------------------------------------------------------

--[[
Pure. obs is the flat ring; now is the moment the grid is read; opts = { offset, weeks,
tolerancePct, minWeeks, weekStart, buyPct, sellPct, model }.

Returns { slots[1..42], min, max, spreadPct, flat, currentSlot, currentWeek,
          judged = { hits, misses }, reliability }, each slot being
    { mean, weeksSeen, expected, basis, samples, low, high, hits, misses, action, actual, status,
      hour }, hour being the best hour inside the block for the action: the cheapest for a
    buy, the dearest for a sell, from real scans when there are any, else from the model.

The rules, in order:
  * Completed weeks inside the window form the expectation; the current week is the
    actual. An expectation is the mean of the WEEKLY means, so a week with five scans in
    one evening counts once, and it needs minWeeks of them (basis "weeks").
  * A block short of that takes the modelled expectation from opts.model when there is
    one (basis "model", from the History buckets), else the mean of the weeks it does
    have (basis "partial"). Real weeks win the moment they exist.
  * The hit record: each completed week's mean against the mean of the other weeks,
    within the tolerance. Two weeks or more.
  * Actions come from the item's own profile: buy where the expectation sits in the
    bottom of its range, sell at the top, by the Movers quartiles. Under FLAT_SPREAD_PCT
    of spread there is no cheap or dear end, and nothing is scheduled.
  * This week's status: now, pending, and behind us hit, miss, noscan, or seen when
    there was a scan but nothing yet to hold it against.
  * reliability is the hit record over the action slots alone: it judges the plan.
]]
function MAW.ComposeSchedule(obs, now, opts)
    opts = opts or {}
    local offset = opts.offset or 0
    local weeks = opts.weeks or 8
    local tol = (opts.tolerancePct or 10) / 100
    local minWeeks = opts.minWeeks or 2
    local weekStart = opts.weekStart or 3
    local buyPct, sellPct = opts.buyPct or 0.25, opts.sellPct or 0.75

    local model = opts.model or {}

    local currentSlot, _, _, currentWeek = MAW.ScheduleSlot(now, offset, weekStart)
    local currentPos = SlotPosition(currentSlot, weekStart)
    local out = {
        slots = {}, currentSlot = currentSlot, currentWeek = currentWeek,
        judged = { hits = 0, misses = 0 },
    }

    local cells, hours = {}, {}
    for i = 1, SLOTS do cells[i] = {}; hours[i] = {} end
    for i = 1, #(obs or {}) - 1, 2 do
        local t, p = obs[i], obs[i + 1]
        if t and p and p > 0 then
            local slot, _, _, w, hour = MAW.ScheduleSlot(t, offset, weekStart)
            if w <= currentWeek and w >= currentWeek - weeks then
                local wk = cells[slot][w]
                if not wk then
                    wk = { s = 0, n = 0, l = p, h = p }
                    cells[slot][w] = wk
                end
                wk.s = wk.s + p
                wk.n = wk.n + 1
                if p < wk.l then wk.l = p end
                if p > wk.h then wk.h = p end
                if w < currentWeek then
                    local hb = hours[slot][hour]
                    if not hb then hb = { s = 0, n = 0 }; hours[slot][hour] = hb end
                    hb.s = hb.s + p
                    hb.n = hb.n + 1
                end
            end
        end
    end

    local min, max
    for i = 1, SLOTS do
        local s = { hits = 0, misses = 0, weeksSeen = 0 }
        local means, sum = {}, 0
        for w, wk in pairs(cells[i]) do
            if w < currentWeek then
                local m = wk.s / wk.n
                means[#means + 1] = m
                sum = sum + m
                if not s.low or wk.l < s.low then s.low = wk.l end
                if not s.high or wk.h > s.high then s.high = wk.h end
            end
        end
        s.weeksSeen = #means
        if #means > 0 then s.mean = sum / #means end
        if #means >= minWeeks then
            s.expected, s.basis = s.mean, "weeks"
        elseif model[i] then
            s.expected, s.basis, s.samples = model[i].expected, "model", model[i].samples
        elseif s.mean then
            s.expected, s.basis = s.mean, "partial"
        end
        if s.expected then
            if not min or s.expected < min then min = s.expected end
            if not max or s.expected > max then max = s.expected end
        end
        if #means >= 2 then
            for _, m in ipairs(means) do
                local others = (sum - m) / (#means - 1)
                if math.abs(m - others) <= tol * others then
                    s.hits = s.hits + 1
                else
                    s.misses = s.misses + 1
                end
            end
        end
        local cur = cells[i][currentWeek]
        if cur then
            s.actual = { avg = cur.s / cur.n, n = cur.n, low = cur.l, high = cur.h }
        end
        -- The block's own cheapest and dearest hour, from the scans behind it; the
        -- model's when it has none of its own.
        for hour, hb in pairs(hours[i]) do
            local avg = hb.s / hb.n
            if not s.cheapAvg or avg < s.cheapAvg then s.cheapHour, s.cheapAvg = hour, avg end
            if not s.dearAvg or avg > s.dearAvg then s.dearHour, s.dearAvg = hour, avg end
        end
        if s.cheapHour == nil and model[i] then
            s.cheapHour, s.dearHour = model[i].cheapHour, model[i].dearHour
        end
        out.slots[i] = s
    end

    out.min, out.max = min, max
    if min and max and min > 0 then
        out.spreadPct = (max - min) / min * 100
        out.flat = out.spreadPct < FLAT_SPREAD_PCT
    else
        out.spreadPct = 0
        out.flat = true
    end

    local range = (max or 0) - (min or 0)
    for i = 1, SLOTS do
        local s = out.slots[i]
        if s.expected and not out.flat then
            if s.expected <= min + buyPct * range then
                s.action = "buy"
            elseif s.expected >= min + sellPct * range then
                s.action = "sell"
            end
        end
        if s.action then
            out.judged.hits = out.judged.hits + s.hits
            out.judged.misses = out.judged.misses + s.misses
            s.hour = (s.action == "buy") and s.cheapHour or s.dearHour
        end

        local pos = SlotPosition(i, weekStart)
        if pos == currentPos then
            s.status = "now"
        elseif pos > currentPos then
            s.status = "pending"
        elseif not s.actual then
            s.status = "noscan"
        elseif not s.expected then
            s.status = "seen"
        elseif math.abs(s.actual.avg - s.expected) <= tol * s.expected then
            s.status = "hit"
        else
            s.status = "miss"
        end
    end

    local judged = out.judged.hits + out.judged.misses
    if judged > 0 then out.reliability = out.judged.hits / judged end
    return out
end

--------------------------------------------------------------------------------
-- Pure: the week's plan across items
--------------------------------------------------------------------------------

--[[
Pure. items = { { name, itemType, schedule } }; opts = { weekStart, minReliabilityPct,
minJudged }. Returns { days[1..7] = { wday, label, rows }, setAside, scheduled }.

Days run from weekStart. A row is one action in one block for one item. An item whose
action slots have been judged minJudged times and held under the floor is set aside:
the pattern is not holding, so the plan moves on, and the grid still shows it.
]]
function MAW.WeekPlan(items, opts)
    opts = opts or {}
    local weekStart = opts.weekStart or 3
    local floor = (opts.minReliabilityPct or 50) / 100
    local minJudged = opts.minJudged or MIN_JUDGED
    local out = { days = {}, setAside = {}, scheduled = 0 }
    for d = 1, 7 do
        local wday = (weekStart - 1 + d - 1) % 7 + 1
        out.days[d] = { wday = wday, label = MAW.WEEKDAY_NAMES[wday], rows = {} }
    end

    for _, it in ipairs(items or {}) do
        local sc = it.schedule
        if sc and not sc.flat then
            local judged = sc.judged.hits + sc.judged.misses
            if judged >= minJudged and (sc.reliability or 0) < floor then
                out.setAside[#out.setAside + 1] = {
                    name = it.name, itemType = it.itemType,
                    reliability = sc.reliability, judged = judged,
                }
            else
                -- The item's action slots in week order, so each row can name the other
                -- half of its trade: the next opposite block after it, wrapping into next
                -- week when this week has none left.
                local actions = {}
                for i = 1, SLOTS do
                    local s = sc.slots[i]
                    if s.action then
                        local pos, wday, block = SlotPosition(i, weekStart)
                        actions[#actions + 1] = { slot = i, pos = pos, wday = wday, block = block, hour = s.hour,
                            action = s.action, expected = s.expected }
                    end
                end
                table.sort(actions, function(a, b) return a.pos < b.pos end)
                local function Counter(a)
                    local wanted = (a.action == "buy") and "sell" or "buy"
                    local first
                    for _, b in ipairs(actions) do
                        if b.action == wanted then
                            if b.pos > a.pos then return b, false end
                            if not first then first = b end
                        end
                    end
                    return first, first ~= nil          -- next week's, when there is one
                end

                for _, a in ipairs(actions) do
                    local s = sc.slots[a.slot]
                    local d = (a.wday - weekStart) % 7 + 1
                    local rows = out.days[d].rows
                    local counter, nextWeek = Counter(a)
                    local gain
                    if counter and a.expected and counter.expected and a.expected > 0 and counter.expected > 0 then
                        gain = (a.action == "buy") and (counter.expected - a.expected) / a.expected
                            or (a.expected - counter.expected) / counter.expected
                    end
                    rows[#rows + 1] = {
                        slot = a.slot, block = a.block, hour = a.hour, action = a.action,
                        name = it.name, itemType = it.itemType,
                        expected = s.expected, actual = s.actual, status = s.status,
                        basis = s.basis, samples = s.samples,
                        weeksSeen = s.weeksSeen, low = s.low, high = s.high,
                        hits = s.hits, misses = s.misses,
                        reliability = sc.reliability, judged = judged,
                        now = (a.slot == sc.currentSlot),
                        counter = counter and {
                            slot = counter.slot, wday = counter.wday, block = counter.block,
                            hour = counter.hour, action = counter.action, expected = counter.expected,
                            nextWeek = nextWeek,
                        } or nil,
                        gain = gain,
                    }
                    local row = rows[#rows]
                    row.delta, row.edge = MAW.RowDelta(row)
                end
                if #actions > 0 then out.scheduled = out.scheduled + 1 end
            end
        end
    end

    -- Inside a block, by the hour to act (a row with no hour of its own goes last), and
    -- inside an hour by the margin in the row's favour, best first; rows with no actual
    -- yet come after the ones that have one.
    for _, day in ipairs(out.days) do
        table.sort(day.rows, function(a, b)
            if a.block ~= b.block then return a.block < b.block end
            local ha, hb = a.hour or 99, b.hour or 99
            if ha ~= hb then return ha < hb end
            if (a.edge == nil) ~= (b.edge == nil) then return a.edge ~= nil end
            if a.edge ~= nil and a.edge ~= b.edge then return a.edge > b.edge end
            if a.action ~= b.action then return a.action == "buy" end
            return a.name < b.name
        end)
    end
    table.sort(out.setAside, function(a, b) return a.name < b.name end)
    return out
end

-- Pure. Whether a plan row's actual is on the right side of its target: at or under
-- for a buy, at or over for a sell. nil with no actual yet.
function MAW.RowOnTarget(row)
    if not row or not row.actual or not row.expected then return nil end
    if row.action == "buy" then return row.actual.avg <= row.expected end
    return row.actual.avg >= row.expected
end

-- Pure. How far the actual sits from the target, as a fraction of the target: delta is
-- signed as the price moved (over is positive), edge is signed in the row's favour (a
-- buy under its target and a sell over it are both positive). nil with no actual.
function MAW.RowDelta(row)
    if not row or not row.actual or not row.expected or row.expected <= 0 then return nil end
    local delta = (row.actual.avg - row.expected) / row.expected
    local edge = (row.action == "buy") and -delta or delta
    return delta, edge
end

--------------------------------------------------------------------------------
-- Reading the world
--------------------------------------------------------------------------------

function MAW:ScheduleOptions()
    local sc = self:ScheduleSettings()
    return {
        offset = self:ClockOffset(),
        weeks = sc.weeks, tolerancePct = sc.tolerancePct, minWeeks = sc.minWeeks,
        weekStart = sc.weekStart,
        buyPct = self:MoverSetting("moverBuyPct"), sellPct = self:MoverSetting("moverSellPct"),
        minReliabilityPct = sc.minReliabilityPct,
    }
end

-- The modelled week from the History tab's own series, the weekday and hour views.
function MAW:ModelFromHistory(itemName)
    return MAW.ModelWeek(self:GetSeries(itemName, "weekday"), self:GetSeries(itemName, "hour"), MIN_SAMPLES)
end

local function Compose(self, itemName, itemData, opts)
    local history = self:EnsureHistory(itemData)
    opts.model = self:ModelFromHistory(itemName)
    return MAW.ComposeSchedule(history.obs or {}, time(), opts)
end

-- One item's week, or nil when it is not tracked.
function MAW:GetSchedule(itemName)
    local db = self:GetActiveDB()
    local itemData = db.items and db.items[itemName]
    if not itemData then return nil end
    return Compose(self, itemName, itemData, self:ScheduleOptions())
end

-- This week across every tracked item.
function MAW:GetWeekPlan()
    local items = {}
    local opts = self:ScheduleOptions()
    for _, it in ipairs(self:SortedTrackedItemNames()) do
        items[#items + 1] = {
            name = it.name, itemType = it.data.itemType or "material",
            schedule = Compose(self, it.name, it.data, opts),
        }
    end
    return MAW.WeekPlan(items, opts)
end

-- The window the store keeps, one week beyond what the grid reads.
function MAW:ObsCutoff(now)
    local sc = self:ScheduleSettings()
    return (now or time()) - (sc.weeks + 1) * SECONDS_PER_WEEK
end

_G.MalexisAuctionWatcher = MAW
