--[[
LibICCore-1.0: the plumbing every Impulse Control addon used to carry its own copy of.

One call in Core.lua installs it onto the addon's namespace:

    local Core = LibStub("LibICCore-1.0")
    Core:Attach(ns, {
        name = addonName,               -- the folder name, as ADDON_LOADED reports it
        prefix = "GuildRecruitment",    -- what chat lines are prefixed with
        version = VERSION,
        db = "GuildRecruitmentDB",      -- the ## SavedVariables global, by name
        cdb = "GuildRecruitmentCharDB", -- the ## SavedVariablesPerCharacter global; optional
        defaults = ns.Defaults, charDefaults = ns.CharDefaults,
        schema = 1, migrations = ns.Migrations, charSchema = 1,
        slash = { "/gr", "/guildrecruitment" }, slashKey = "GUILDRECRUITMENT",
        help = HELP,                    -- { { "sub args", "what it does", needs = "Module" }, ... }
        commands = { ... },             -- sub-command -> function(rest, cmd); overrides a built-in
        logKinds = { sent = "|cff44ff44" },
        onLoad = function(info) end,    -- after the tables exist; info.sawFile, info.firstRun
        onToggle = function(on) end,    -- after /x enable or disable
        onReset = function(what) end,   -- after /x reset
        loadedHint = "/gr opens the window, /gr help lists commands.",  -- or a function
        log = false,                    -- the addon has a Log of its own shape
    })

Everything lands on `ns` under the names the addons already use -- ns.Print, ns.Util.Trim,
ns.Log.Add, ns.Tests.Case, ns.Migrate -- so adopting the library is mostly deleting files.

The one thing here that is not a convenience is the load check. At ADDON_LOADED the addon
is told whether the client handed its saved variables back at all, logs it, and says so in
red when an account that has run before comes up empty. A client that has been running
across .toc edits can stop restoring one addon's account-wide table while still restoring
the per-character one; only a restart clears it, and the damage is not the empty load but
the logout after it, which writes defaults over the file that still holds the real thing.
]]

local MAJOR, MINOR = "LibICCore-1.0", 2
local Core = LibStub:NewLibrary(MAJOR, MINOR)
if not Core then return end

--------------------------------------------------------------------------------
-- Pure helpers, shared by every addon as ns.Util
--------------------------------------------------------------------------------

local Util = {}
Core.Util = Util

function Util.Trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Colour codes, hyperlinks and inline textures out. Do this BEFORE storing a string, not
-- when drawing it, so what lands in SavedVariables is readable too.
function Util.StripEscapes(s)
    s = tostring(s or "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("|H.-|h(.-)|h", "%1")
    s = s:gsub("|T.-|t", "")
    s = s:gsub("|A.-|a", "")
    return s
end

-- Lower case, punctuation flattened to single spaces. For comparing two things a player
-- typed, where the difference is only ever spelling.
function Util.Normalize(s)
    s = Util.StripEscapes(s):lower()
    s = s:gsub("[^%w%s]", " ")
    return Util.Trim(s:gsub("%s+", " "))
end

-- Cuts to n bytes without leaving a half-written escape or a split UTF-8 character
-- behind. A truncation that cuts a |c open eats the rest of the chat row it lands in, and
-- one that cuts a multi-byte character prints a box.
function Util.Truncate(s, n)
    s = tostring(s or "")
    if #s <= n then return s end
    local cut = n
    while cut > 0 do
        local b = s:byte(cut + 1)
        if not b or b < 128 or b >= 192 then break end
        cut = cut - 1
    end
    local out = s:sub(1, cut)
    local opens = select(2, out:gsub("|c%x%x%x%x%x%x%x%x", ""))
    local closes = select(2, out:gsub("|r", ""))
    if opens > closes then out = out .. "|r" end
    out = out:gsub("|c?%x*$", "")
    return out
end

-- pairs() hands back a different order between two calls on the same table, and a list
-- drawn from it changes under the reader. Anything iterated for display or for a hash
-- goes through here first.
function Util.SortedKeys(t)
    local keys = {}
    for k in pairs(t or {}) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        if type(a) == type(b) then return tostring(a) < tostring(b) end
        return type(a) < type(b)
    end)
    return keys
end

-- A stable string for a table of scalars, arrays and nested tables. Two tables built
-- key-by-key in different orders must serialize identically, or anything comparing them
-- decides they differ forever.
function Util.Serialize(v)
    local t = type(v)
    if t == "table" then
        local parts = {}
        for _, k in ipairs(Util.SortedKeys(v)) do
            parts[#parts + 1] = tostring(k) .. "=" .. Util.Serialize(v[k])
        end
        return "{" .. table.concat(parts, ",") .. "}"
    elseif t == "number" then
        return string.format("%.14g", v)
    elseif t == "boolean" then
        return v and "true" or "false"
    elseif t == "nil" then
        return "nil"
    end
    return string.format("%q", tostring(v))
end

-- The one choke point every string that arrived from another player passes through
-- before it is stored or drawn: escapes off, any surviving pipe gone, cut to a length
-- this addon chose rather than one the sender did.
function Util.Clean(s, maxLen)
    s = Util.StripEscapes(s or "")
    s = s:gsub("|", "")
    s = s:gsub("[%c]", " ")
    return Util.Truncate(Util.Trim(s:gsub("%s+", " ")), maxLen or 255)
end

function Util.Plural(n, one, many)
    return n == 1 and one or (many or (one .. "s"))
end

function Util.OnOff(v)
    return v and "|cff44ff44on|r" or "|cffff4444off|r"
end

-- A span of seconds as a list cell shows it.
function Util.Duration(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    if seconds < 60 then return string.format("%ds", seconds) end
    if seconds < 3600 then return string.format("%dm", math.floor(seconds / 60)) end
    if seconds < 86400 then return string.format("%dh", math.floor(seconds / 3600)) end
    return string.format("%dd", math.floor(seconds / 86400))
end

-- Relative age plus the colour it should be drawn in: grey for never, plain for fresh,
-- amber once it is past staleSec. Returns label, color.
function Util.Freshness(at, now, staleSec)
    if not at or at <= 0 then
        return "never", { r = 0.5, g = 0.5, b = 0.5 }
    end
    local age = math.max(0, (now or 0) - at)
    local label = Util.Duration(age)
    if staleSec and staleSec > 0 and age >= staleSec then
        return label, { r = 1, g = 0.8, b = 0.3 }
    end
    return label, { r = 0.9, g = 0.9, b = 0.9 }
end

function Util.DeepCopy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = Util.DeepCopy(v) end
    return out
end

-- Fills in what is missing and touches nothing already there, a stored `false` included.
-- Run on every load, so a field added in a later version simply appears the first time
-- anything asks for it and needs no migration of its own.
function Util.ApplyDefaults(target, defaults)
    for k, v in pairs(defaults or {}) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then target[k] = {} end
            Util.ApplyDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
    return target
end

--[[
The schema changes ApplyDefaults cannot make on its own: anything that has to READ the old
shape before the new one exists. `steps` is keyed by the schema each one upgrades FROM, so
steps[1] takes a schema-1 table to schema 2. They run BEFORE ApplyDefaults, always: one that
runs afterwards cannot tell a field the player never had from one the defaults just invented.

An empty table is a fresh install and starts at the head, so nothing runs on it. Returns
how many steps ran, which is what the load line reports, so a step that adopts a schema
rather than upgrading to one does not claim to have upgraded anything.
]]
function Util.Migrate(db, steps, head)
    head = head or 1
    if db.schema == nil then
        db.schema = next(db) == nil and head or 1
    end
    local ran = 0
    while db.schema < head do
        local at = db.schema
        local step = (steps or {})[at]
        if step then step(db) end

        -- A step may set db.schema itself to ADOPT a schema instead of
        -- upgrading to one: an addon that stamped its own version under a
        -- different key before this library owned the bootstrap does that on
        -- its first step, to skip the steps it has already run. Nothing was
        -- upgraded, so nothing is counted, and the loop resumes where the step
        -- left it. The <= rather than < is a hang guard: a step that moves the
        -- schema backwards is a bug, but it must not be an infinite loop.
        if db.schema <= at then
            db.schema = at + 1
            ran = ran + 1
        end
    end
    return ran
end

--------------------------------------------------------------------------------
-- Log: two ring buffers, merged at read time
--------------------------------------------------------------------------------

--[[
`log` is what the addon decided and acted on. `capture` is everything it merely saw.
Without the second half an "All" view shows only what the addon acted on, which is not
the same as everything that happened, and the difference is exactly where "why did it do
nothing" lives. Both live in the addon's saved table, so escapes come off before storing.
]]
local function BuildLog(ns, kinds)
    local Log = ns.Log or {}
    local MAX_ENTRIES, MAX_CAPTURE, WINDOW = 100, 500, 300
    Log.MAX_ENTRIES, Log.MAX_CAPTURE, Log.WINDOW = MAX_ENTRIES, MAX_CAPTURE, WINDOW
    -- An addon with its own Log of a different shape (TradeMaster keys entries on
    -- player and verdict) passes log = false; this is how the bootstrap tells the two apart.
    Log.icCore = true

    -- One colour per kind everywhere: green happened, amber waiting, red failed, grey noted.
    Log.KIND_COLOR = Log.KIND_COLOR or {}
    local base = { ok = "|cff44ff44", warn = "|cffffcc00", err = "|cffff4444", info = "|cff888888" }
    for k, v in pairs(base) do Log.KIND_COLOR[k] = Log.KIND_COLOR[k] or v end
    for k, v in pairs(kinds or {}) do Log.KIND_COLOR[k] = v end

    -- Pure. Newest first, trimmed from the tail.
    function Log.Push(list, entry, max)
        table.insert(list, 1, entry)
        for i = #list, (max or MAX_ENTRIES) + 1, -1 do
            table.remove(list, i)
        end
        return list
    end

    function Log.Add(kind, source, text, detail, now)
        ns.db.log = ns.db.log or {}
        return Log.Push(ns.db.log, {
            at = now or ns.Now(),
            kind = kind or "info",
            source = source or "?",
            text = Util.StripEscapes(text or ""),
            detail = detail and Util.StripEscapes(detail) or nil,
        }, MAX_ENTRIES)
    end

    function Log.Capture(kind, source, text, now)
        ns.db.capture = ns.db.capture or {}
        return Log.Push(ns.db.capture, {
            at = now or ns.Now(),
            kind = kind or "info",
            source = source or "?",
            text = Util.StripEscapes(text or ""),
        }, MAX_CAPTURE)
    end

    -- Pure. The last `window` things that happened, newest first, decisions and capture
    -- together. Both lists are already newest-first, so this walks them side by side and
    -- stops the moment the window is full. An entry in both is returned once, as the
    -- log's copy, which is the one carrying the detail.
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
            local key = string.format("%s|%s|%s", e.source or "", e.at or 0, e.text or "")
            if not seen[key] then
                seen[key] = true
                out[#out + 1] = e
            end
        end
        return out
    end

    -- Pure. At most n entries, and how many the filters held back, so a short list can
    -- say why it is short. opts = { kind = "sent", source = "Bark", since = <timestamp> }
    function Log.Filter(entries, n, opts)
        opts = opts or {}
        local out, hidden = {}, 0
        for _, e in ipairs(entries or {}) do
            local keep = true
            if opts.kind and opts.kind ~= "all" and e.kind ~= opts.kind then keep = false end
            if opts.source and opts.source ~= "all" and e.source ~= opts.source then keep = false end
            if opts.since and (e.at or 0) < opts.since then keep = false end
            if keep then
                if #out < n then out[#out + 1] = e end
            else
                hidden = hidden + 1
            end
        end
        return out, hidden
    end

    -- Newest first, straight off the stored log. For chat, where there is no toolbar.
    function Log.Recent(n, kind)
        local out = {}
        local log = ns.db and ns.db.log or {}
        for i = 1, #log do
            if #out >= n then break end
            local e = log[i]
            if not kind or kind == "all" or e.kind == kind then out[#out + 1] = e end
        end
        return out
    end

    -- Pure. Which sources have written anything, in a fixed order, for a filter menu.
    function Log.Sources(entries)
        local seen, out = {}, {}
        for _, e in ipairs(entries or {}) do
            if e.source and not seen[e.source] then
                seen[e.source] = true
                out[#out + 1] = e.source
            end
        end
        table.sort(out)
        return out
    end

    function Log.Describe(entry, now)
        local color = Log.KIND_COLOR[entry.kind] or "|cffffffff"
        local age = Util.Freshness(entry.at, now or ns.Now())
        return string.format("%s%s|r %s |cff888888%s|r %s",
            color, entry.kind, entry.source or "?", age, entry.text or "")
    end

    return Log
end

--------------------------------------------------------------------------------
-- Tests: the in-game harness
--------------------------------------------------------------------------------

--[[
There is no Lua interpreter on the maintainer's machine and no CI, so this runs in game
with /x test and writes its result to SavedVariables, where it can still be read after a
/reload took the chat frame with it. The house rule: any decision worth arguing about
lives in a pure function, and every pure function has a case.
]]
local function BuildTests(ns)
    local T = ns.Tests or {}
    T.cases = T.cases or {}

    function T.Case(name, fn)
        T.cases[#T.cases + 1] = { name = name, fn = fn }
    end

    -- Level 2 on every error, so the reported line is the assertion's and not this file's.
    function T.Eq(actual, expected, label)
        if actual ~= expected then
            error(string.format("%s: expected [%s], got [%s]",
                tostring(label or "value"), tostring(expected), tostring(actual)), 2)
        end
    end

    function T.True(value, label)
        if not value then
            error(string.format("%s: expected true, got [%s]",
                tostring(label or "value"), tostring(value)), 2)
        end
    end

    -- T.Near(actual, expected, label) is accepted too, with the tolerance money needs:
    -- copper is computed in floating point, so equality on it wants slack.
    function T.Near(actual, expected, tolerance, label)
        if type(tolerance) == "string" then label, tolerance = tolerance, nil end
        if tolerance == nil then tolerance = 0.001 end
        if type(actual) ~= "number" or math.abs(actual - expected) > tolerance then
            error(string.format("%s: expected [%s] give or take %s, got [%s]",
                tostring(label or "value"), tostring(expected), tostring(tolerance),
                tostring(actual)), 2)
        end
    end

    -- Runs fn against a made-up saved-variables table and puts the real one back
    -- afterwards, whatever fn does. The restore is unconditional: a case that errors must
    -- not leave the player's own settings swapped out.
    function T.With(db, cdb, fn)
        local realDB, realCDB = ns.db, ns.cdb
        ns.db, ns.cdb = db, cdb or {}
        local ok, err = pcall(fn)
        ns.db, ns.cdb = realDB, realCDB
        if not ok then error(err, 2) end
    end

    function T.Run()
        local pass, fail = 0, 0
        ns.db.lastTestRun = { at = ns.Now(), failures = {} }
        for _, case in ipairs(T.cases) do
            local ok, err = pcall(case.fn)
            if ok then
                pass = pass + 1
            else
                fail = fail + 1
                ns.Print("|cffff4444FAIL|r " .. case.name .. " => " .. tostring(err))
                local f = ns.db.lastTestRun.failures
                f[#f + 1] = { name = case.name, err = tostring(err) }
            end
        end
        ns.db.lastTestRun.passed, ns.db.lastTestRun.failed = pass, fail
        ns.Printf("Tests: |cff44ff44%d passed|r, %s%d failed|r",
            pass, fail > 0 and "|cffff4444" or "|cff44ff44", fail)
        if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
        return pass, fail
    end

    return T
end

--------------------------------------------------------------------------------
-- Probe: "does this client have X"
--------------------------------------------------------------------------------

local Probe = {}
Core.Probe = Probe

-- Pure. Walks a dotted path without indexing a nil on the way.
function Probe.Resolve(root, path)
    local node = root
    for part in tostring(path or ""):gmatch("[^%.]+") do
        if type(node) ~= "table" then return nil end
        node = node[part]
    end
    return node
end

-- Pure. present(boolean), kind(string).
function Probe.Describe(value)
    if value == nil then return false, "missing" end
    return true, type(value)
end

-- checks is a list of { "C_Timer.After", "why the addon cares" }.
function Probe.Rows(checks)
    local out = {}
    for _, check in ipairs(checks or {}) do
        local ok, kind = Probe.Describe(Probe.Resolve(_G, check[1]))
        out[#out + 1] = { name = check[1], present = ok, kind = kind, why = check[2] }
    end
    return out
end

-- One line per check: green present, red missing, and the reason the addon cares, so a
-- missing line says what breaks rather than just "no". Returns present, absent.
function Probe.Print(ns, checks)
    ns.Printf("client probe, interface %s:", (select(4, GetBuildInfo())) or "?")
    local present, absent = 0, 0
    for _, row in ipairs(Probe.Rows(checks)) do
        if row.present then present = present + 1 else absent = absent + 1 end
        ns.Printf("  %s %-42s |cff888888%s|r",
            row.present and "|cff44ff44yes|r" or "|cffff4444no |r",
            row.name, row.present and row.kind or row.why)
    end
    ns.Printf("%d present, %s%d missing|r.", present,
        absent > 0 and "|cffffcc00" or "|cff44ff44", absent)
    return present, absent
end

-- Installs Resolve/Describe/Rows/PrintChecks on ns.Probe over the addon's own CHECKS, and
-- a Run that prints them. An addon with more to probe replaces Run and calls PrintChecks.
function Core:Probe(ns, checks)
    ns.Probe = ns.Probe or {}
    local P = ns.Probe
    P.Resolve, P.Describe = Probe.Resolve, Probe.Describe
    function P.Rows() return Probe.Rows(checks) end
    function P.PrintChecks() return Probe.Print(ns, checks) end
    if not P.Run then P.Run = P.PrintChecks end
    return P
end

--------------------------------------------------------------------------------
-- Minimap launcher
--------------------------------------------------------------------------------

--[[
spec = { name, icon, onClick(button), tooltip(tt) }. Both libraries are optional and both
are checked before anything is done with them: the global has to exist AND be what you
think it is. Returns the data object and LibDBIcon, or nil when either is missing.

LibDBIcon keeps the button's position in the table it is handed, so that has to be the
saved one and not a fresh table each login.
]]
function Core:MinimapButton(ns, spec)
    local LDB = LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true)
    local Icon = LibStub and LibStub:GetLibrary("LibDBIcon-1.0", true)
    if not LDB or not Icon then return nil end

    local obj = LDB:NewDataObject(spec.name, {
        type = "launcher",
        icon = spec.icon,
        OnClick = function(_, button)
            if spec.onClick then spec.onClick(button) end
        end,
        OnTooltipShow = spec.tooltip,
    })

    ns.db.settings.minimap = ns.db.settings.minimap or {}
    Icon:Register(spec.name, obj, ns.db.settings.minimap)
    return obj, Icon
end

--------------------------------------------------------------------------------
-- Key bindings
--------------------------------------------------------------------------------

-- Bindings.xml names the functions; this names the header and the actions the key
-- binding screen shows. names = { BARK = "Send the recruitment message", TOGGLE = "..." }.
function Core:Bindings(key, header, names)
    _G["BINDING_HEADER_" .. key] = header
    for action, text in pairs(names or {}) do
        _G["BINDING_NAME_" .. key .. "_" .. action] = text
    end
end

--------------------------------------------------------------------------------
-- Attach
--------------------------------------------------------------------------------

local function InstallOutput(ns, opts)
    local tag = "|cff33ff99" .. (opts.prefix or opts.name) .. "|r: "

    -- Everything the addon says is prefixed, so a player can tell who is talking.
    -- settings.outputFrame moves it off the main chat frame; /x out sets it.
    function ns.Print(msg)
        local frame = DEFAULT_CHAT_FRAME
        local idx = ns.db and ns.db.settings and ns.db.settings.outputFrame
        if idx and idx > 1 then
            local f = _G["ChatFrame" .. idx]
            if f and f.AddMessage then frame = f end
        end
        frame:AddMessage(tag .. tostring(msg))
    end

    function ns.Printf(fmt, ...)
        ns.Print(string.format(fmt, ...))
    end

    -- Only when settings.debug is on. For the lines a maintainer wants and a player does not.
    function ns.Debug(fmt, ...)
        if ns.db and ns.db.settings and ns.db.settings.debug then
            ns.Print("|cff888888" .. string.format(fmt, ...) .. "|r")
        end
    end

    -- False means the addon takes no action of its own. Reading its window still works.
    function ns.Enabled()
        return not ns.db or ns.db.settings.enabled ~= false
    end

    -- One clock for the whole addon, so anything pure can be handed a `now` in a test.
    function ns.Now()
        return GetServerTime and GetServerTime() or time()
    end

    ns.DeepCopy, ns.ApplyDefaults, ns.Migrate = Util.DeepCopy, Util.ApplyDefaults, Util.Migrate
end

--[[
Creates or takes over the saved tables and publishes them as ns.db and ns.cdb. Migrate,
then default, then publish: never the other way round. `fresh` throws the old ones away,
which is what /x reset all means. Returns sawFile, stepsRun.
]]
local function Bootstrap(ns, opts, fresh)
    if fresh then
        _G[opts.db] = {}
        if opts.cdb then _G[opts.cdb] = {} end
    end
    local sawFile = _G[opts.db] ~= nil and next(_G[opts.db]) ~= nil
    _G[opts.db] = _G[opts.db] or {}
    local ran = Util.Migrate(_G[opts.db], opts.migrations, opts.schema or 1)
    Util.ApplyDefaults(_G[opts.db], opts.defaults)
    ns.db = _G[opts.db]
    if opts.cdb then
        _G[opts.cdb] = _G[opts.cdb] or {}
        Util.Migrate(_G[opts.cdb], opts.charMigrations, opts.charSchema or 1)
        Util.ApplyDefaults(_G[opts.cdb], opts.charDefaults)
        ns.cdb = _G[opts.cdb]
    end
    return sawFile, ran
end

local function InstallSlash(ns, opts)
    local slash = opts.slash[1]
    local help = opts.help or {}

    local function PrintHelp()
        ns.Print("commands:")
        for _, row in ipairs(help) do
            -- A row with `needs` is only offered when that module is loaded, so a copy
            -- made with new-addon.ps1 -Minimal does not advertise what it no longer has.
            if not row.needs or ns[row.needs] then
                ns.Printf("  |cffffcc00%s %s|r %s %s", slash,
                    row[1], row[1] == "" and "" or "\194\183", row[2])
            end
        end
    end
    ns.PrintHelp = PrintHelp

    local function Refresh()
        if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
    end

    local builtin = {}

    builtin[""] = function()
        if ns.UI and ns.UI.Toggle then ns.UI.Toggle() else PrintHelp() end
    end
    builtin.help = PrintHelp

    builtin.log = function(rest)
        local n = tonumber(rest) or 10
        local entries = ns.Log.Recent(n)
        if #entries == 0 then ns.Print("the log is empty.") return end
        for i = #entries, 1, -1 do
            ns.Print(ns.Log.Describe(entries[i], ns.Now()))
        end
    end

    builtin.status = function()
        if ns.Probe and ns.Probe.Status then
            for _, line in ipairs(ns.Probe.Status()) do ns.Print(line) end
        else
            ns.Printf("v%s, addon %s", ns.VERSION, Util.OnOff(ns.Enabled()))
        end
    end

    builtin.test = function() ns.Tests.Run() end

    builtin.probe = function(rest)
        if ns.Probe and ns.Probe.Run then ns.Probe.Run(rest) else ns.Print("nothing to probe.") end
    end

    local function Toggle(rest, cmd)
        ns.db.settings.enabled = (cmd == "enable")
        ns.Printf("%s is %s.", opts.prefix or opts.name, Util.OnOff(ns.db.settings.enabled))
        if opts.onToggle then opts.onToggle(ns.db.settings.enabled) end
        Refresh()
    end
    builtin.enable, builtin.disable = Toggle, Toggle

    builtin.out = function(rest)
        local n = tonumber(rest)
        if not n then
            ns.Printf("printing to ChatFrame %d. %s out <n> moves it.",
                ns.db.settings.outputFrame or 1, slash)
            return
        end
        ns.db.settings.outputFrame = math.max(1, math.min(10, math.floor(n)))
        ns.Printf("printing to ChatFrame %d.", ns.db.settings.outputFrame)
    end

    builtin.scale = function(rest)
        local pct = tonumber(rest)
        if not pct then
            ns.Printf("window scale is %d%%. %s scale <percent> sets it, or drag the grip "
                .. "in the bottom-right corner.",
                (ns.db.settings.windowScale or 1) * 100 + 0.5, slash)
            return
        end
        local frame = ns.UI and ns.UI.frame
        if not frame or not frame.SetWindowScale then
            ns.Print("open the window first, then set the scale.")
            return
        end
        local applied = frame:SetWindowScale(pct / 100)
        ns.Printf("window scale set to %d%%.", applied * 100 + 0.5)
    end

    builtin.reset = function(rest)
        local ok, msg = ns.Reset(rest)
        ns.Print(msg)
        if ok then Refresh() end
    end

    builtin.version = function()
        local ui = select(2, LibStub:GetLibrary("LibICUI-1.0", true))
        ns.Printf("v%s, ICLibs LibICCore-1.0 minor %d, LibICUI-1.0 minor %s",
            ns.VERSION, MINOR, tostring(ui or "?"))
    end

    local commands = {}
    for k, v in pairs(builtin) do commands[k] = v end
    for k, v in pairs(opts.commands or {}) do commands[k] = v end

    local function HandleSlash(input)
        local raw = Util.Trim(input or "")
        local cmd, rest = raw:match("^(%S*)%s*(.*)$")
        cmd = (cmd or ""):lower()
        local fn = commands[cmd]
        if fn then
            fn(rest, cmd)
        else
            PrintHelp()
        end
    end
    ns.HandleSlash = HandleSlash

    -- A copy of the template renamed but left on the same slash key is a confusing
    -- afternoon. Remembered here, said once at PLAYER_LOGIN.
    ns.slashTaken = SlashCmdList and SlashCmdList[opts.slashKey] ~= nil
    for i, s in ipairs(opts.slash) do
        _G["SLASH_" .. opts.slashKey .. i] = s
    end
    SlashCmdList[opts.slashKey] = HandleSlash
end

--[[
what: "all" throws both tables away and rebuilds them; "log" empties the log and capture;
any top-level key of the defaults ("settings", "doc") goes back to its default. Returns
ok, message. Addons that need to gate a reset (an author check) wrap this in their own
`reset` command.
]]
local function InstallReset(ns, opts)
    function ns.Reset(what)
        what = Util.Trim(what or ""):lower()
        if what == "" then what = opts.resetDefault or "settings" end

        if what == "all" then
            Bootstrap(ns, opts, true)
            if opts.onReset then opts.onReset(what) end
            return true, "everything reset."
        elseif what == "log" then
            ns.db.log, ns.db.capture = {}, {}
            if opts.onReset then opts.onReset(what) end
            return true, "log cleared."
        elseif opts.defaults and opts.defaults[what] ~= nil then
            ns.db[what] = nil
            Util.ApplyDefaults(ns.db, opts.defaults)
            if opts.onReset then opts.onReset(what) end
            return true, what .. " restored to defaults."
        end

        local names = { "all", "log" }
        for _, k in ipairs(Util.SortedKeys(opts.defaults or {})) do
            if k ~= "log" and k ~= "capture" then names[#names + 1] = k end
        end
        return false, "reset what? " .. table.concat(names, ", ") .. "."
    end
end

--[[
The load itself. Runs on ADDON_LOADED for this addon and nothing else.

`sawFile` is the one fact that separates "the file did not load" from "the addon cleared
it": an account that has run this addon before has settings written, so a table with
nothing in it at all is either a first run or a load that did not happen. The second is
said in red BEFORE anything is edited, because the damage is not the empty load but the
logout afterwards, which writes these defaults over the file that still holds the real
thing. That file is still on disk as a .bak until the next save.
]]
local function OnAddonLoaded(ns, opts)
    local sawFile, ran = Bootstrap(ns, opts, false)
    if ran > 0 then
        ns.Printf("upgraded saved settings through %d schema %s.",
            ran, ran == 1 and "step" or "steps")
    end

    if ns.Log and ns.Log.icCore then
        ns.Log.Add("info", "Core",
            string.format("loaded v%s, schema %s", tostring(ns.VERSION), tostring(ns.db.schema)),
            sawFile and "saved variables were present" or "SAVED VARIABLES WERE EMPTY")
    end

    local firstRun = false
    if ns.cdb then
        if not sawFile and not ns.cdb.everRan then
            firstRun = true
        elseif not sawFile then
            ns.Print("|cffff4444The saved settings did not load.|r This session started "
                .. "empty even though this account has run the addon before. A client "
                .. "that has been running across .toc edits does this; restart it.")
            ns.Print("|cffff4444Do not log out or reload yet|r if what was saved matters: "
                .. "that writes these defaults over the file. The previous session is still "
                .. "in WTF\\Account\\<account>\\SavedVariables\\" .. opts.name .. ".lua.bak")
        end
        ns.cdb.everRan = true
    end

    if opts.onLoad then
        opts.onLoad({ sawFile = sawFile, firstRun = firstRun, migrated = ran })
    end

    local slash = opts.slash and opts.slash[1] or ("/" .. opts.name:lower())
    local hint = opts.loadedHint
    if type(hint) == "function" then hint = hint() end
    ns.Printf("v%s loaded. %s", tostring(ns.VERSION), hint
        or string.format("%s opens the window, %s help lists commands.", slash, slash))
end

function Core:Attach(ns, opts)
    assert(type(ns) == "table", "LibICCore: Attach needs the addon's namespace table")
    assert(opts and opts.name and opts.db, "LibICCore: Attach needs at least name and db")
    opts.defaults = opts.defaults or {}
    if opts.log ~= false then
        opts.defaults.log = opts.defaults.log or {}
        opts.defaults.capture = opts.defaults.capture or {}
    end

    ns.Core = Core
    ns.CoreOpts = opts
    ns.VERSION = opts.version or ns.VERSION or "?"
    ns.SCHEMA, ns.CHAR_SCHEMA = opts.schema or 1, opts.charSchema or 1
    ns.Defaults, ns.CharDefaults = opts.defaults, opts.charDefaults
    ns.Migrations = opts.migrations or {}

    InstallOutput(ns, opts)

    ns.Util = ns.Util or {}
    for k, v in pairs(Util) do ns.Util[k] = v end

    if opts.log ~= false then ns.Log = BuildLog(ns, opts.logKinds) end
    ns.Tests = BuildTests(ns)
    InstallReset(ns, opts)
    if opts.slash and opts.slashKey then InstallSlash(ns, opts) end

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("ADDON_LOADED")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:SetScript("OnEvent", function(_, event, arg1)
        if event == "ADDON_LOADED" and arg1 == opts.name then
            OnAddonLoaded(ns, opts)
        elseif event == "PLAYER_LOGIN" then
            if ns.slashTaken then
                ns.Printf("|cffff9900another addon already registered the %s slash key.|r "
                    .. "One of you owns %s now.", opts.slashKey, opts.slash[1])
            end
        end
    end)
    ns.coreFrame = frame
    return ns
end
