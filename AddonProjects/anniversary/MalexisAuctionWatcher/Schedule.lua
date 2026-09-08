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
    return slot, d.wday, block, weekIndex
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
-- Pure: one item's week
--------------------------------------------------------------------------------

--[[
Pure. obs is the flat ring; now is the moment the grid is read; opts = { offset, weeks,
tolerancePct, minWeeks, weekStart, buyPct, sellPct }.

Returns { slots[1..42], min, max, spreadPct, flat, currentSlot, currentWeek,
          judged = { hits, misses }, reliability }, each slot being
    { mean, weeksSeen, expected, low, high, hits, misses, action, actual, status }.

The rules, in order:
  * Completed weeks inside the window form the expectation; the current week is the
    actual. An expectation is the mean of the WEEKLY means, so a week with five scans in
    one evening counts once, and it needs minWeeks of them.
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

    local currentSlot, _, _, currentWeek = MAW.ScheduleSlot(now, offset, weekStart)
    local currentPos = SlotPosition(currentSlot, weekStart)
    local out = {
        slots = {}, currentSlot = currentSlot, currentWeek = currentWeek,
        judged = { hits = 0, misses = 0 },
    }

    local cells = {}
    for i = 1, SLOTS do cells[i] = {} end
    for i = 1, #(obs or {}) - 1, 2 do
        local t, p = obs[i], obs[i + 1]
        if t and p and p > 0 then
            local slot, _, _, w = MAW.ScheduleSlot(t, offset, weekStart)
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
            s.expected = s.mean
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
                local any = false
                for i = 1, SLOTS do
                    local s = sc.slots[i]
                    if s.action then
                        any = true
                        local _, wday, block = SlotPosition(i, weekStart)
                        local d = (wday - weekStart) % 7 + 1
                        local rows = out.days[d].rows
                        rows[#rows + 1] = {
                            slot = i, block = block, action = s.action,
                            name = it.name, itemType = it.itemType,
                            expected = s.expected, actual = s.actual, status = s.status,
                            weeksSeen = s.weeksSeen, low = s.low, high = s.high,
                            hits = s.hits, misses = s.misses,
                            reliability = sc.reliability, judged = judged,
                            now = (i == sc.currentSlot),
                        }
                    end
                end
                if any then out.scheduled = out.scheduled + 1 end
            end
        end
    end

    for _, day in ipairs(out.days) do
        table.sort(day.rows, function(a, b)
            if a.block ~= b.block then return a.block < b.block end
            if a.action ~= b.action then return a.action == "buy" end
            return a.name < b.name
        end)
    end
    table.sort(out.setAside, function(a, b) return a.name < b.name end)
    return out
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

-- One item's week, or nil when it is not tracked.
function MAW:GetSchedule(itemName)
    local db = self:GetActiveDB()
    local itemData = db.items and db.items[itemName]
    if not itemData then return nil end
    local history = self:EnsureHistory(itemData)
    return MAW.ComposeSchedule(history.obs or {}, time(), self:ScheduleOptions())
end

-- This week across every tracked item.
function MAW:GetWeekPlan()
    local items = {}
    for _, it in ipairs(self:SortedTrackedItemNames()) do
        local history = self:EnsureHistory(it.data)
        items[#items + 1] = {
            name = it.name, itemType = it.data.itemType or "material",
            schedule = MAW.ComposeSchedule(history.obs or {}, time(), self:ScheduleOptions()),
        }
    end
    return MAW.WeekPlan(items, self:ScheduleOptions())
end

-- The window the store keeps, one week beyond what the grid reads.
function MAW:ObsCutoff(now)
    local sc = self:ScheduleSettings()
    return (now or time()) - (sc.weeks + 1) * SECONDS_PER_WEEK
end

_G.MalexisAuctionWatcher = MAW
