--[[
LibICEnv-1.0
Layer 1 of ICKit: what this client offers, and what the addons cost it.

The Forever client is new to us, so nothing above this layer may assume an API exists.
Env answers the question with data and never prints: the caller decides what to say.

    local Env = LibStub("LibICEnv-1.0")

    Env.Build()                     -> { version, build, date, interface }
    Env.Resolve(path, root)         -> the value at a dotted path, or nil
    Env.Has(path, root)             -> present, kind
    Env.Probe(checks, root)         -> rows { path, present, kind, why }
    Env.Try(label, fn, ...)         -> { label, ok, n, values, text } or { label, ok = false, err }

    Env.Wrap(label, fn)             -> fn that counts its calls and its time
    Env.Counters()                  -> rows { label, calls, total, max }, costliest first
    Env.ResetCounters()
    Env.SetClock(fn)                milliseconds; tests hand in their own

    Env.Memory(addon)               -> KB, or nil when the client does not say
    Env.Cpu(addon)                  -> ms, source, or nil, "unavailable"

Wrap is the profiling that is always on: it needs no console variable, costs two clock
reads a call, and a handler that fires while the game is idle shows up as a call count
that keeps climbing. Resolve, Has and Probe are lifted from LibICCore-1.0's probe.
]]

local MAJOR, MINOR = "LibICEnv-1.0", 1
local Env = LibStub:NewLibrary(MAJOR, MINOR)
if not Env then return end

--------------------------------------------------------------------------------
-- What exists
--------------------------------------------------------------------------------

-- The value at "C_Timer.After" under root (the global table by default), or nil when any
-- step of the path is missing. Pure when handed a root.
function Env.Resolve(path, root)
    if path == nil or path == "" then return nil end
    local node = root or _G
    for part in tostring(path):gmatch("[^%.]+") do
        if type(node) ~= "table" then return nil end
        node = node[part]
    end
    return node
end

-- present (boolean), kind ("function", "table", ... or "missing").
function Env.Has(path, root)
    local value = Env.Resolve(path, root)
    if value == nil then return false, "missing" end
    return true, type(value)
end

-- checks is a list of paths, or of { path, "why the addon cares" }.
function Env.Probe(checks, root)
    local rows = {}
    for _, check in ipairs(checks or {}) do
        local path, why = check, nil
        if type(check) == "table" then path, why = check[1], check[2] end
        local present, kind = Env.Has(path, root)
        rows[#rows + 1] = { path = path, present = present, kind = kind, why = why }
    end
    return rows
end

-- The client's build as a table. Hand in a function to stand in for GetBuildInfo.
function Env.Build(getBuildInfo)
    local fn = getBuildInfo or GetBuildInfo
    if type(fn) ~= "function" then
        return { version = "?", build = "?", date = "?", interface = 0 }
    end
    local version, build, date, interface = fn()
    return {
        version = tostring(version or "?"), build = tostring(build or "?"),
        date = tostring(date or "?"), interface = tonumber(interface) or 0,
    }
end

local function Pack(ok, ...)
    return ok, select("#", ...), { ... }
end

-- Calls fn under pcall and reports what came back, so a probe can ask a question the
-- client may not be able to answer. `text` is every return joined for a report line.
function Env.Try(label, fn, ...)
    if type(fn) ~= "function" then
        return { label = label, ok = false, err = "not a function" }
    end
    local ok, n, values = Pack(pcall(fn, ...))
    if not ok then
        return { label = label, ok = false, err = tostring(values[1]) }
    end
    local parts = {}
    for i = 1, n do parts[i] = tostring(values[i]) end
    return { label = label, ok = true, n = n, values = values, text = table.concat(parts, ", ") }
end

--------------------------------------------------------------------------------
-- What it costs
--------------------------------------------------------------------------------

Env.counters = Env.counters or {}
local counters = Env.counters
local clock

-- Milliseconds. The client's profiling clock when it has one.
local function Now()
    if clock then return clock() end
    if type(debugprofilestop) == "function" then return debugprofilestop() end
    if type(os) == "table" and os.clock then return os.clock() * 1000 end
    return 0
end

function Env.SetClock(fn)
    clock = fn
end

-- Outside the wrapper so a wrapped call allocates nothing.
local function Finish(counter, start, ...)
    local took = Now() - start
    counter.total = counter.total + took
    if took > counter.max then counter.max = took end
    return ...
end

-- fn, counted. An error passes through as it would unwrapped; that call is counted but
-- its time is not.
function Env.Wrap(label, fn)
    local counter = counters[label]
    if not counter then
        counter = { label = label, calls = 0, total = 0, max = 0 }
        counters[label] = counter
    end
    return function(...)
        counter.calls = counter.calls + 1
        local start = Now()
        return Finish(counter, start, fn(...))
    end
end

function Env.Counters()
    local rows = {}
    for _, c in pairs(counters) do
        rows[#rows + 1] = { label = c.label, calls = c.calls, total = c.total, max = c.max }
    end
    table.sort(rows, function(a, b)
        if a.total ~= b.total then return a.total > b.total end
        return a.label < b.label
    end)
    return rows
end

function Env.ResetCounters()
    for _, c in pairs(counters) do
        c.calls, c.total, c.max = 0, 0, 0
    end
end

-- The client's own figure for an addon's memory, in KB; nil when it will not say.
function Env.Memory(addon)
    if type(UpdateAddOnMemoryUsage) ~= "function" or type(GetAddOnMemoryUsage) ~= "function" then
        return nil
    end
    local ok, kb = pcall(function()
        UpdateAddOnMemoryUsage()
        return GetAddOnMemoryUsage(addon)
    end)
    if ok and type(kb) == "number" then return kb end
    return nil
end

-- The client's own figure for an addon's CPU, in ms since it started counting, and where
-- it came from. It reads zero unless the scriptProfile console variable is on.
function Env.Cpu(addon)
    if type(UpdateAddOnCPUUsage) == "function" and type(GetAddOnCPUUsage) == "function" then
        local ok, ms = pcall(function()
            UpdateAddOnCPUUsage()
            return GetAddOnCPUUsage(addon)
        end)
        if ok and type(ms) == "number" then return ms, "scriptProfile" end
    end
    return nil, "unavailable"
end
