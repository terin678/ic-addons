local addonName, ns = ...

--[[
Schema: what MarkedForDeath saves, version 1. Pure: no client call, ever.

Owned by lane S (the scaffold). A setting another lane needs goes to the coordinator,
who has lane S add it here; no other lane edits this file.

    Schema.VERSION, Schema.CHAR_VERSION     the schema numbers the store upgrades to
    Schema.Defaults, Schema.CharDefaults    every field with a default
    Schema.migrations, Schema.charMigrations
                                            steps keyed by the schema they upgrade FROM
    Schema.DEFAULT_PLAN                     the seat plan a new install starts with
    Schema.Prepare(db)                      what defaults cannot do: seed the default plan
    Schema.Spec(onReady)                    the LibICStore spec Core.lua registers
    Schema.Boot(globals)                    the same work on tables a case hands in

Rules for later versions: a new field with a default needs no step. A change that has to
read the old shape adds migrations[1] (or charMigrations[1]) and moves VERSION to 2 in the
same commit, with a case that boots the v1 fixture. Steps never delete player data.
]]

ns.Schema = ns.Schema or {}
local Schema = ns.Schema

Schema.VERSION = 1
Schema.CHAR_VERSION = 1

Schema.ACCOUNT = "MarkedForDeathDB"
Schema.CHARACTER = "MarkedForDeathCharDB"

-- The eight raid icons by index (1 Star, 2 Circle, 3 Diamond, 4 Triangle, 5 Moon,
-- 6 Square, 7 Cross, 8 Skull) and the seat each one is. Kill 1 to 4 are Skull, Cross,
-- Square, Circle; Sheep 1 and 2 are Moon and Star; Banish 1 and 2 are Triangle and Diamond.
-- No pins: a raid pins its own players (spec section 1).
Schema.DEFAULT_PLAN = {
    [8] = { intent = "KILL", ordinal = 1 },
    [7] = { intent = "KILL", ordinal = 2 },
    [6] = { intent = "KILL", ordinal = 3 },
    [2] = { intent = "KILL", ordinal = 4 },
    [5] = { intent = "SHEEP", ordinal = 1 },
    [1] = { intent = "SHEEP", ordinal = 2 },
    [4] = { intent = "BANISH", ordinal = 1 },
    [3] = { intent = "BANISH", ordinal = 2 },
}

-- Account-wide. A field whose default is "nothing" (raidLead, a plan per instance, a rule)
-- has no entry: ApplyDefaults cannot tell an absent nil from a chosen one, and need not.
-- The seat plan is not here either; Prepare seeds it, so a seat the player clears is not
-- put back on the next load.
Schema.Defaults = {
    settings = {
        enabled = true, debug = false, sound = true,
        announce = { prepull = true, channel = "RAID" },
        marking = { mouseover = false, rebuildDebounce = 0.5 },   -- seconds
        chat = { deathTTL = 10 },                                 -- seconds
        logCombat = { enabled = true, instances = {} },           -- [instanceKey] = true
        capture = false,
        cue = { enabled = false, word = "", sound = "" },
        minimap = { hidden = false, angle = 200 },                -- degrees round the rim
    },
    plans = {},       -- default = seat plan, ["i:<id>"] = seat plan once edited
    rules = {},       -- [instanceKey] = { ["n:<name>" | "id:<npc>"] = rule }
    deaths = {
        tank = { on = true, trash = true, override = "auto", extra = {}, bosses = {} },
        healer = { on = false, trash = false, override = "auto", extra = {}, bosses = {} },
    },
    check = {
        columns = { flask = true, food = true, buffs = true, durability = true, version = true },
        minDurability = 50,   -- percent
    },
    learned = {},     -- [instanceKey] = { [npcID] = { name, seen } }, readable sightings only
    capture = { instances = {}, encounters = {}, npcs = {}, auras = {}, hidden = 0 },
    log = { head = 0, entries = {} },
}

-- Per character. Window places are fractions of UIParent, filled by the window lane.
Schema.CharDefaults = {
    windows = { main = {}, assignments = {}, board = {} },
    bar = { shown = true, locked = false, outsideRaid = false },
    planEditing = "default",
}

Schema.migrations = {}
Schema.charMigrations = {}

local function Copy(t)
    local out = {}
    for k, v in pairs(t) do
        out[k] = type(v) == "table" and Copy(v) or v
    end
    return out
end

-- Seeds what a default cannot: the default seat plan, once, on a table that has none.
-- Returns true when it seeded.
function Schema.Prepare(db)
    if type(db.plans) ~= "table" then db.plans = {} end
    if db.plans.default ~= nil then return false end
    db.plans.default = Copy(Schema.DEFAULT_PLAN)
    return true
end

-- The spec LibICStore boots from. onReady(db, cdb, info) runs after Prepare.
function Schema.Spec(onReady)
    return {
        account = Schema.ACCOUNT,
        character = Schema.CHARACTER,
        schema = Schema.VERSION,
        charSchema = Schema.CHAR_VERSION,
        defaults = Schema.Defaults,
        charDefaults = Schema.CharDefaults,
        migrations = Schema.migrations,
        charMigrations = Schema.charMigrations,
        onReady = function(db, cdb, info)
            Schema.Prepare(db)
            if onReady then onReady(db, cdb, info) end
        end,
    }
end

-- Boots the two tables found in `globals` (a case's own table) exactly as the client
-- load does. Returns db, cdb, info.
function Schema.Boot(globals)
    local Store = LibStub("LibICStore-1.0")
    local db, cdb, info = Store.Boot(Schema.Spec(), globals)
    Schema.Prepare(db)
    return db, cdb, info
end
