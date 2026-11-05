local addonName, ns = ...

--[[
The case registry. Loaded last, so every module and every lane's Tests_<Lane>.lua has
registered its cases on ns.Tests by now. Run headless with
scripts/run-tests.ps1 -Flavor forever -Addon MarkedForDeath, and in game with /mfd selftest.

Owned by lane S (the scaffold). The cases below are the scaffold's own: Core.lua and
Schema.lua. Every one builds its own tables; none touches the saved ones.
]]

local T = ns.Tests
local Schema = ns.Schema

local function Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

--------------------------------------------------------------------------------
-- Core
--------------------------------------------------------------------------------

T.Case("Core.LoadLines: the version, and a red warning when the account table was lost", function()
    local lines = ns.LoadLines("9.9.9", { firstRun = true })
    T.Eq(#lines, 1, "one line on a normal load")
    T.True(lines[1]:find("v9.9.9", 1, true), "it names the version")
    T.True(lines[1]:find("/mfd help", 1, true), "and says where the commands are")

    local lost = ns.LoadLines("9.9.9", { lost = true })
    T.Eq(#lost, 3, "two more lines when the file did not load")
    T.True(lost[2]:find("|cffff4444", 1, true), "in red")
    T.True(lost[3]:find("Restart the client", 1, true), "saying what to do")

    T.Eq(#ns.LoadLines("9.9.9", nil), 1, "no info at all is a normal load")
end)

T.Case("Core.NewCommandSet: added commands sit between head and tail, clashes refused", function()
    local set = ns.NewCommandSet({ { "", "this list" } }, { { "selftest", "checks" }, { "help", "this list" } })
    local function Run() end

    T.True(set.Add("capture", "capture mode", Run, "capture on|off"), "a new command is added")
    T.True(set.Add("rules", "the rules", Run), "and another")
    T.Eq(#set.help, 5, "head, two added, tail")
    T.Eq(set.help[1][1], "", "head first")
    T.Eq(set.help[2][1], "capture on|off", "added in load order, with its usage")
    T.Eq(set.help[3][1], "rules", "second added")
    T.Eq(set.help[4][1], "selftest", "tail last")
    T.Eq(set.commands.capture, Run, "the function is wired")

    local ok, why = set.Add("rules", "again", Run)
    T.Eq(ok, false, "a name already added is refused")
    T.True(why:find("already taken", 1, true), "with a reason")
    T.Eq(set.Add("help", "mine", Run), false, "a tail row's name is taken too")
    T.Eq(set.Add("Two Words", "x", Run), false, "a name is one lower-case word")
    T.Eq(set.Add("nofn", "x", nil), false, "a command needs a function")
    T.Eq(#set.help, 5, "nothing refused reached the help list")
end)

T.Case("Core.NewEventSet: register on the first listener, unregister after the last", function()
    local set = ns.NewEventSet()
    local calls = {}
    local function A() calls[#calls + 1] = "a" end
    local function B() calls[#calls + 1] = "b" end

    T.Eq(set.On("GROUP_ROSTER_UPDATE", "sense", B), true, "the first listener registers the event")
    T.Eq(set.On("GROUP_ROSTER_UPDATE", "comms", A), false, "a second one does not")
    T.Eq(set.On("GROUP_ROSTER_UPDATE", "comms", A), false, "the same key again replaces, not adds")
    for _, fn in ipairs(set.Each("GROUP_ROSTER_UPDATE")) do fn() end
    T.Eq(table.concat(calls), "ab", "delivered in key order")

    T.Eq(set.Off("GROUP_ROSTER_UPDATE", "nobody"), false, "dropping a key never added changes nothing")
    T.Eq(set.Off("GROUP_ROSTER_UPDATE", "comms"), false, "one listener left, still registered")
    T.Eq(set.Off("GROUP_ROSTER_UPDATE", "sense"), true, "the last one gone unregisters it")
    T.Eq(#set.Each("GROUP_ROSTER_UPDATE"), 0, "nothing listens now")
    T.Eq(set.Off("GROUP_ROSTER_UPDATE", "sense"), false, "and dropping again is harmless")
end)

--------------------------------------------------------------------------------
-- Schema
--------------------------------------------------------------------------------

T.Case("Schema.DEFAULT_PLAN: eight icons, each seat once, no pins", function()
    T.Eq(Count(Schema.DEFAULT_PLAN), 8, "every icon has a seat")
    local seen = {}
    for icon, seat in pairs(Schema.DEFAULT_PLAN) do
        T.True(icon >= 1 and icon <= 8, "icon index " .. tostring(icon))
        local key = seat.intent .. seat.ordinal
        T.Eq(seen[key], nil, key .. " is held once")
        seen[key] = true
        T.Eq(seat.pin, nil, "no pin on " .. key)
    end
    T.Eq(Schema.DEFAULT_PLAN[8].intent .. Schema.DEFAULT_PLAN[8].ordinal, "KILL1", "Skull is Kill 1")
    T.Eq(Schema.DEFAULT_PLAN[5].intent .. Schema.DEFAULT_PLAN[5].ordinal, "SHEEP1", "Moon is Sheep 1")
    T.Eq(Schema.DEFAULT_PLAN[4].intent .. Schema.DEFAULT_PLAN[4].ordinal, "BANISH1", "Triangle is Banish 1")
end)

T.Case("Schema.Boot: an empty install gets every default, the plan and schema 1", function()
    local g = {}
    local db, cdb, info = Schema.Boot(g)
    T.Eq(g[Schema.ACCOUNT], db, "the account table is the global the client saves")
    T.Eq(g[Schema.CHARACTER], cdb, "and so is the character table")
    T.Eq(info.firstRun, true, "a first run")
    T.Eq(info.migrated, 0, "nothing to migrate")
    T.Eq(db.schema, 1, "account schema")
    T.Eq(cdb.schema, 1, "character schema")
    T.Eq(db.settings.enabled, true, "enabled by default")
    T.Eq(db.settings.announce.channel, "RAID", "nested defaults")
    T.Eq(db.settings.minimap.angle, 200, "the rim angle")
    T.Eq(db.deaths.tank.on, true, "tank deaths on")
    T.Eq(db.deaths.healer.on, false, "healer deaths off")
    T.Eq(db.check.minDurability, 50, "durability floor")
    T.Eq(db.log.head, 0, "an empty log")
    T.Eq(Count(db.plans.default), 8, "the default plan is seeded")
    T.True(db.plans.default[8] ~= Schema.DEFAULT_PLAN[8], "as a copy, not the constant")
    T.Eq(cdb.bar.shown, true, "the bar shows")
    T.Eq(cdb.planEditing, "default", "editing the default plan")
    T.Eq(cdb.everRan, true, "the character remembers it ran")
end)

T.Case("Schema.Boot: a v1 fixture keeps what the player chose", function()
    local g = {
        [Schema.ACCOUNT] = {
            schema = 1,
            settings = { enabled = false, debug = true, announce = { channel = "PARTY" } },
            plans = { default = { [8] = { intent = "KILL", ordinal = 1, pin = "Someone" } } },
            rules = { open = { ["n:Scarlet Sorcerer"] = { name = "Scarlet Sorcerer", intent = "SHEEP", rank = 20 } } },
            deaths = { tank = { on = false } },
        },
        [Schema.CHARACTER] = { schema = 1, everRan = true, planEditing = "i:33" },
    }
    local db, cdb, info = Schema.Boot(g)
    T.Eq(info.sawFile, true, "the file came back")
    T.Eq(info.lost, false, "nothing lost")
    T.Eq(info.migrated, 0, "no step at schema 1")
    T.Eq(db.settings.enabled, false, "a stored false is kept")
    T.Eq(db.settings.debug, true, "a stored true is kept")
    T.Eq(db.settings.announce.channel, "PARTY", "a stored channel is kept")
    T.Eq(db.settings.announce.prepull, true, "its missing sibling is filled")
    T.Eq(Count(db.plans.default), 1, "an edited plan is not refilled: cleared seats stay cleared")
    T.Eq(db.plans.default[8].pin, "Someone", "the pin is kept")
    T.Eq(db.rules.open["n:Scarlet Sorcerer"].rank, 20, "rules are kept")
    T.Eq(db.deaths.tank.on, false, "tank deaths stay off")
    T.Eq(db.deaths.tank.trash, true, "the rest of the tank row is filled")
    T.Eq(cdb.planEditing, "i:33", "the character's choice is kept")
end)

T.Case("Schema.Boot: a fixture missing every optional field is filled", function()
    local g = { [Schema.ACCOUNT] = { schema = 1 }, [Schema.CHARACTER] = { schema = 1, everRan = true } }
    local db, cdb = Schema.Boot(g)
    T.Eq(type(db.settings.marking), "table", "marking settings")
    T.Eq(db.settings.marking.rebuildDebounce, 0.5, "with its debounce")
    T.Eq(db.settings.chat.deathTTL, 10, "death TTL")
    T.Eq(db.settings.capture, false, "capture off")
    T.Eq(db.capture.hidden, 0, "the capture store")
    T.Eq(type(db.learned), "table", "learned")
    T.Eq(db.check.columns.version, true, "check columns")
    T.Eq(Count(db.plans.default), 8, "no plan at all is seeded")
    T.Eq(type(cdb.windows.main), "table", "window places")
    T.Eq(cdb.bar.locked, false, "bar unlocked")
end)

T.Case("Schema.Boot: an empty account beside a character that ran is reported lost", function()
    local g = { [Schema.CHARACTER] = { schema = 1, everRan = true } }
    local _, _, info = Schema.Boot(g)
    T.Eq(info.lost, true, "lost")
    T.Eq(info.firstRun, false, "not a first run")
    T.Eq(#ns.LoadLines("0.1.0", info), 3, "and the load lines say so")
end)

T.Case("Schema.Spec: the store spec names both tables and runs Prepare before onReady", function()
    local seen
    local spec = Schema.Spec(function(db) seen = db.plans.default end)
    T.Eq(spec.account, "MarkedForDeathDB", "account table")
    T.Eq(spec.character, "MarkedForDeathCharDB", "character table")
    T.Eq(spec.schema, 1, "schema")
    T.Eq(spec.charSchema, 1, "character schema")
    T.Eq(spec.migrations, Schema.migrations, "migrations table from day one")
    T.Eq(spec.charMigrations, Schema.charMigrations, "and the character's")
    spec.onReady({ plans = {} }, {}, {})
    T.True(seen ~= nil and seen[8] ~= nil, "the plan is there by the time onReady runs")
end)
