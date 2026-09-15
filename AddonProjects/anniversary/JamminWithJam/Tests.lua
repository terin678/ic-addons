local addonName, ns = ...

--[[
The harness -- Case, Eq, True, Near, With, Run -- is LibICCore's. What lives
here are the cases. There is no Lua interpreter on the maintainer's machine
and no CI, so this runs in game with /jam test and writes its result to
SavedVariables, where it can still be read after a /reload took the chat
frame with it.

The house rule: any decision worth arguing about lives in a pure function,
and every pure function has a case here.
]]

local T = ns.Tests

--------------------------------------------------------------------------------
-- Util
--------------------------------------------------------------------------------

T.Case("Util: trimming and stripping", function()
    T.Eq(ns.Util.Trim("  hello  "), "hello", "both ends")
    T.Eq(ns.Util.Trim(""), "", "nothing to trim")
    T.Eq(ns.Util.Trim(nil), "", "nil is not an error")

    T.Eq(ns.Util.StripEscapes("|cff44ff44green|r"), "green", "colour codes")
    -- The brackets are part of what the player saw, so they stay; only the link
    -- machinery around them goes.
    T.Eq(ns.Util.StripEscapes("|cffa335ee|Hitem:29434:0:0:0|h[Badge]|h|r"), "[Badge]",
        "a link keeps only its display name")
    T.Eq(ns.Util.StripEscapes("a|TInterface\\Icons\\x:12|tb"), "ab", "inline textures")
end)

T.Case("Util: normalizing is for comparing, not for showing", function()
    T.Eq(ns.Util.Normalize("Fel Leather Gloves"), "fel leather gloves", "case")
    T.Eq(ns.Util.Normalize("LF  LW,  please!"), "lf lw please", "punctuation and runs of space")
    T.Eq(ns.Util.Normalize("|cff44ff44Primal Might|r"), "primal might", "escapes go first")
end)

T.Case("Util: sorted keys, plurals and switches", function()
    local keys = ns.Util.SortedKeys({ zebra = 1, apple = 1, mango = 1 })
    T.Eq(table.concat(keys, ","), "apple,mango,zebra", "alphabetical")
    T.Eq(#ns.Util.SortedKeys(nil), 0, "nil is an empty table")

    T.Eq(ns.Util.Plural(1, "line"), "line", "one")
    T.Eq(ns.Util.Plural(2, "line"), "lines", "many")
    T.Eq(ns.Util.Plural(0, "entry", "entries"), "entries", "an irregular one")
end)

T.Case("Util: freshness says how old and whether that is a problem", function()
    local now = 1000000
    T.Eq(ns.Util.Freshness(nil, now, 60), "never", "nothing stored")
    T.Eq(ns.Util.Freshness(0, now, 60), "never", "and zero means the same")
    T.Eq(ns.Util.Freshness(now - 42, now, 3600), "42s", "seconds")
    T.Eq(ns.Util.Freshness(now - 400, now, 3600), "6m", "minutes")
end)

--------------------------------------------------------------------------------
-- Saved variables
--------------------------------------------------------------------------------

T.Case("Defaults: filling gaps without trampling anything", function()
    local target = { a = 1, nested = { keep = "mine" } }
    ns.ApplyDefaults(target, { a = 9, b = 2, nested = { keep = "theirs", add = 3 } })
    T.Eq(target.a, 1, "an existing value is left alone")
    T.Eq(target.b, 2, "a missing one is filled in")
    T.Eq(target.nested.keep, "mine", "and nested is the same rule")
    T.Eq(target.nested.add, 3, "new nested keys arrive")

    -- The classic one: `false` is a value the player chose, not a missing key.
    local off = { enabled = false }
    ns.ApplyDefaults(off, { enabled = true })
    T.Eq(off.enabled, false, "a stored false survives its own default")
end)

T.Case("Defaults: a deep copy shares nothing", function()
    local source = { list = { 1, 2 }, deep = { inner = { "x" } } }
    local copy = ns.DeepCopy(source)
    copy.list[1] = 99
    copy.deep.inner[1] = "y"
    T.Eq(source.list[1], 1, "the original list is untouched")
    T.Eq(source.deep.inner[1], "x", "however deep it goes")
end)

T.Case("Migrations: run in order, once, and never on a fresh install", function()
    local ran = {}
    local steps = {
        [1] = function(db) ran[#ran + 1] = 1; db.one = true end,
        [2] = function(db) ran[#ran + 1] = 2; db.two = true end,
    }

    -- An empty table is somebody's first login, not an ancient save.
    local fresh = {}
    T.Eq(ns.Migrate(fresh, steps, 3), 0, "nothing runs on a fresh table")
    T.Eq(fresh.schema, 3, "and it is stamped at the head")

    local old = { settings = {} }
    T.Eq(ns.Migrate(old, steps, 3), 2, "an unstamped table with data is schema 1")
    T.Eq(table.concat(ran, ","), "1,2", "in order")
    T.Eq(old.schema, 3, "and lands on the head")

    T.Eq(ns.Migrate(old, steps, 3), 0, "running again does nothing")
    T.Eq(table.concat(ran, ","), "1,2", "and does not repeat a step")
end)

--------------------------------------------------------------------------------
-- Log
--------------------------------------------------------------------------------

local function entry(at, kind, source, text)
    return { at = at, kind = kind, source = source, text = text }
end

T.Case("Log: the ring buffer keeps the newest and drops the oldest", function()
    local list = {}
    for i = 1, 12 do ns.Log.Push(list, entry(i, "info", "T", "line " .. i), 10) end
    T.Eq(#list, 10, "capped")
    T.Eq(list[1].text, "line 12", "newest first")
    T.Eq(list[10].text, "line 3", "and the two oldest are gone")
end)

T.Case("Log: the window merges both streams without sorting either", function()
    local log = { entry(90, "ok", "Sounds", "sent"), entry(50, "ok", "Sounds", "sent") }
    local capture = { entry(80, "info", "Sounds", "skipped"), entry(60, "info", "Sounds", "skipped") }

    local out = ns.Log.Window(log, capture, 10)
    T.Eq(#out, 4, "everything, once")
    T.Eq(out[1].at .. "," .. out[2].at .. "," .. out[3].at .. "," .. out[4].at,
        "90,80,60,50", "in time order")
end)

T.Case("Log: writing goes through a made-up database", function()
    -- The point of T.With: Log.Add is not pure, and it is still testable.
    T.With({ log = {}, capture = {}, settings = { outputFrame = 1 } }, {}, function()
        ns.Log.Add("ok", "Test", "|cff44ff44coloured|r", "and a detail", 500)
        T.Eq(#ns.db.log, 1, "written")
        T.Eq(ns.db.log[1].text, "coloured", "escapes come off BEFORE storing")
        T.Eq(ns.db.log[1].at, 500, "the caller's clock, not the real one")
    end)
    T.Eq(type(ns.db.settings), "table", "the real database came back")
end)

--------------------------------------------------------------------------------
-- Probe
--------------------------------------------------------------------------------

T.Case("Probe: a dotted path never indexes a nil", function()
    local root = { C_Thing = { Method = function() end }, plain = 1 }
    T.Eq(type(ns.Probe.Resolve(root, "C_Thing.Method")), "function", "two levels")
    T.Eq(ns.Probe.Resolve(root, "plain"), 1, "one level")
    T.Eq(ns.Probe.Resolve(root, "C_Missing.Method"), nil, "a missing namespace is nil, not an error")

    local present, kind = ns.Probe.Describe(nil)
    T.Eq(present, false, "missing")
    T.Eq(kind, "missing", "and says so")
end)

--------------------------------------------------------------------------------
-- Sounds
--------------------------------------------------------------------------------

T.Case("Sounds: the catalogue is addressable by id", function()
    local list = ns.Sounds.List()
    T.Eq(#list > 0, true, "there is at least one sound")
    local first = list[1]
    T.Eq(ns.Sounds.ById(first.id).label, first.label, "found by id")
    T.Eq(ns.Sounds.ById("no-such-id"), nil, "a bad id is nil, not an error")
end)

T.Case("Sounds: the chat line is the trigger, a space, and the id", function()
    T.Eq(ns.Sounds.ChatLine({ id = "airhorn" }), "!jam airhorn", "exact format")
    T.Eq(ns.Sounds.TRIGGER, "!jam", "the bot's parser assumes this literally")
end)

T.Case("Sounds: officer is a rank ceiling, not a floor", function()
    T.Eq(ns.Sounds.IsOfficer(0, 1), true, "the guild master is rank 0")
    T.Eq(ns.Sounds.IsOfficer(1, 1), true, "on the threshold")
    T.Eq(ns.Sounds.IsOfficer(2, 1), false, "one below the threshold, i.e. a higher number")
    T.Eq(ns.Sounds.IsOfficer(nil, 1), false, "an unread rank can do nothing")
end)

T.Case("Sounds: cooldown counts down to exactly zero", function()
    T.Eq(ns.Sounds.SecondsUntilReady(1000, 1015, 20), 5, "part way through")
    T.Eq(ns.Sounds.SecondsUntilReady(1000, 1020, 20), 0, "exactly due")
    T.Eq(ns.Sounds.SecondsUntilReady(1000, 1099, 20), 0, "long past due, not negative")
    T.Eq(ns.Sounds.SecondsUntilReady(nil, 1000, 20), 0, "never fired is always ready")
end)

T.Case("Sounds: every reason it will not play, in a fixed order", function()
    local function state(over)
        local s = {
            addonEnabled = true, officerOnly = false, isOfficer = false,
            secondsLeft = 0, channel = "GUILD", inGuild = true,
        }
        for k, v in pairs(over or {}) do s[k] = v end
        return s
    end

    T.Eq(ns.Sounds.BlockReason(state()), nil, "nothing in the way")
    T.Eq(ns.Sounds.BlockReason(state({ addonEnabled = false })),
        "JamminWithJam is disabled", "off")
    T.Eq(ns.Sounds.BlockReason(state({ officerOnly = true })), "officers only",
        "locked and not an officer")
    T.Eq(ns.Sounds.BlockReason(state({ officerOnly = true, isOfficer = true })), nil,
        "locked, but this character qualifies")
    T.Eq(ns.Sounds.BlockReason(state({ secondsLeft = 4 })), "on cooldown for 4s", "cooldown")
    T.Eq(ns.Sounds.BlockReason(state({ inGuild = false })), "you are not in a guild",
        "GUILD with nobody to send it to")
    T.Eq(ns.Sounds.BlockReason(state({ channel = "SAY", inGuild = false })), nil,
        "a public channel does not need a guild")

    -- The order is the contract, not an accident. The UI shows the FIRST
    -- reason, and one that changes with whichever check ran first is worse
    -- than none.
    T.Eq(ns.Sounds.BlockReason(state({ addonEnabled = false, officerOnly = true })),
        "JamminWithJam is disabled", "widest reason first")
    T.Eq(ns.Sounds.BlockReason(state({ officerOnly = true, secondsLeft = 4 })),
        "officers only", "rank before cooldown")
end)

--------------------------------------------------------------------------------
-- UI
--------------------------------------------------------------------------------

T.Case("UI: every page draws without erroring", function()
    -- A page draws with real widgets or not at all; the headless stub has none.
    if IC_HEADLESS then return end
    -- A page refresher is not pure, so no other case in this file reaches one;
    -- building the window and calling each one is the cheapest thing that
    -- does. It is a smoke test, not a check of what is drawn: it catches the
    -- nil index, the bad format argument and the renamed field, which is most
    -- of what goes wrong in a refresher.
    local frame = ns.UI.Create()
    T.Eq(type(frame), "table", "the window builds")
    T.Eq(#ns.UI.Pages > 0, true, "and it has pages")

    for _, page in ipairs(ns.UI.Pages) do
        T.Eq(type(page.refresh), "function", page.name .. " built a refresher")
        local ok, err = pcall(page.refresh)
        T.Eq(ok, true, page.name .. " draws => " .. tostring(err))
    end
end)
