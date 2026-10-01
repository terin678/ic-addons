--[[
LibICStore-1.0
Layer 1 of ICKit: saved variables. An addon names its tables and their defaults once; the
store takes them over when the client hands them back, upgrades what an older version
saved, fills in what is missing, and says whether the file was really there.

    local Store = LibStub("LibICStore-1.0")

    Store.Register(addonName, {
        account = "StickiesDB",             -- ## SavedVariables
        character = "StickiesCharDB",       -- ## SavedVariablesPerCharacter (optional)
        defaults = { ... }, charDefaults = { ... },
        schema = 1, charSchema = 1,
        migrations = { [1] = function(db) ... end }, charMigrations = { ... },
        onReady = function(db, cdb, info) end,
    })

    Store.Boot(spec, globals)       -> db, cdb, info      the same work, on a table you hand in
    Store.ApplyDefaults(target, defaults)
    Store.Migrate(db, steps, head)  -> steps run

info = { sawFile, firstRun, migrated, lost }
    sawFile    the account table came back with something in it
    firstRun   nothing came back and this character has never run the addon
    lost       nothing came back although this character has: the file did not load
    migrated   how many schema steps ran on the account table

The store prints nothing. An addon that cares about `lost` says so itself, in its own
voice. It owns one event frame for every addon that registers, and that frame is the
only one this layer creates. Lifted from LibICCore-1.0's bootstrap and load check.
]]

local MAJOR, MINOR = "LibICStore-1.0", 1
local Store = LibStub:NewLibrary(MAJOR, MINOR)
if not Store then return end

Store.registered = Store.registered or {}

-- Fills in what is missing and touches nothing already there, a stored `false` included.
-- Run on every load, so a field added in a later version simply appears the first time
-- anything asks for it and needs no migration of its own.
function Store.ApplyDefaults(target, defaults)
    for k, v in pairs(defaults or {}) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then target[k] = {} end
            Store.ApplyDefaults(target[k], v)
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
how many steps ran.
]]
function Store.Migrate(db, steps, head)
    head = head or 1
    if db.schema == nil then
        db.schema = next(db) == nil and head or 1
    end
    local ran = 0
    while db.schema < head do
        local at = db.schema
        local step = (steps or {})[at]
        if step then step(db) end
        -- A step may set db.schema itself to adopt a schema rather than upgrade to one.
        -- The <= is a hang guard: a step that moves the schema backwards is a bug, but it
        -- must not be an infinite loop.
        if db.schema <= at then
            db.schema = at + 1
            ran = ran + 1
        end
    end
    return ran
end

--[[
Takes over the saved tables named in spec, inside `globals` (the global table when none is
given, which is what a case hands its own table in place of). Migrate, then default, then
hand back: never the other way round. Returns db, cdb, info.
]]
function Store.Boot(spec, globals)
    globals = globals or _G
    local info = { sawFile = false, firstRun = false, migrated = 0, lost = false }

    local db = globals[spec.account]
    info.sawFile = type(db) == "table" and next(db) ~= nil
    if type(db) ~= "table" then
        db = {}
        globals[spec.account] = db
    end
    info.migrated = Store.Migrate(db, spec.migrations, spec.schema or 1)
    Store.ApplyDefaults(db, spec.defaults)

    local cdb
    if spec.character then
        cdb = globals[spec.character]
        if type(cdb) ~= "table" then
            cdb = {}
            globals[spec.character] = cdb
        end
        Store.Migrate(cdb, spec.charMigrations, spec.charSchema or 1)
        Store.ApplyDefaults(cdb, spec.charDefaults)
        -- The character table remembers that the addon has run here. An empty account
        -- table beside a character that has run before is a file that did not load, which
        -- a client left running across .toc edits will do.
        if not info.sawFile then
            if cdb.everRan then info.lost = true else info.firstRun = true end
        end
        cdb.everRan = true
    else
        info.firstRun = not info.sawFile
    end

    return db, cdb, info
end

local frame

local function OnEvent(_, event, name)
    if event ~= "ADDON_LOADED" then return end
    local spec = Store.registered[name]
    if not spec or spec.booted then return end
    spec.booted = true
    local db, cdb, info = Store.Boot(spec)
    if spec.onReady then spec.onReady(db, cdb, info) end
end

-- Call at file scope, before the client fires ADDON_LOADED for the addon. onReady runs
-- once, when its saved variables are in hand.
function Store.Register(addonName, spec)
    assert(type(addonName) == "string" and type(spec) == "table" and type(spec.account) == "string",
        "LibICStore: Register needs the addon's name and a spec naming its account table")
    Store.registered[addonName] = spec
    if not frame then
        frame = CreateFrame("Frame")
        frame:RegisterEvent("ADDON_LOADED")
        frame:SetScript("OnEvent", OnEvent)
        Store.frame = frame
    end
end
