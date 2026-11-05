--[[
Merges Marked For Death capture exports into the data files the Forever addon ships.

    luajit scripts/mfd-forever-capture.lua <export file> [more export files...]
    luajit scripts/mfd-forever-capture.lua --write <export file> [...]
    luajit scripts/mfd-forever-capture.lua --check
    luajit scripts/mfd-forever-capture.lua --selftest

An export file is the text `/mfd capture export` puts in its copy box, pasted into a
file as it is. Without --write the script reports what it would change and writes
nothing. With --write it rewrites the blocks between the GENERATED markers in
AddonProjects/forever/MarkedForDeath/Data_Instances.lua and Data_Mobs.lua, and leaves
every other line of those files alone. --check reads both files and fails if writing
them back unchanged would change a byte: the format the script writes and the files
agree. --selftest runs the script's own cases.

What a merge does, per export:
  instances   a known id fills in what it lacks (name, kind, size); a new id that has the
              name of a pending raid or dungeon takes that entry's place and leaves the
              pending list; any other new id is added with src = "capture"
  encounters  filed under their instance, by id; one whose name was hidden keeps the name
              already known, else it is skipped and reported
  npcs        filed under their instance (open-world sightings are skipped); the client's
              own name wins over a bundled one, and the change is reported; a mob whose
              name is an encounter's name in that instance, or that the client calls a
              world boss, is marked boss
Every change and every conflict is printed, so the run is the review.

Pure Lua under LuaJIT. It loads the addon's own Capture.lua (and LibICJSON from ICKit)
to read exports, so the game and this script read one format with one reader.
]]

local M = {}

local scriptDir = (arg and arg[0] or ""):gsub("\\", "/"):match("^(.*)/[^/]*$") or "."
local repoRoot = scriptDir .. "/.."
local ADDON_DIR = repoRoot .. "/AddonProjects/forever/MarkedForDeath"
local JSON_LIB = repoRoot .. "/AddonProjects/forever/ICKit/LibICJSON-1.0/LibICJSON-1.0.lua"

local KIND_OF_TYPE = { party = "party", raid = "raid", scenario = "scenario", pvp = "pvp", arena = "pvp" }

--------------------------------------------------------------------------------
-- Loading
--------------------------------------------------------------------------------

local function ReadFile(path)
    local f, err = io.open(path, "rb")
    if not f then return nil, err end
    local text = f:read("*a")
    f:close()
    return text
end

local function WriteFile(path, text)
    local f = assert(io.open(path, "wb"))
    f:write(text)
    f:close()
end

-- A LibStub that is just enough for LibICJSON, so Capture.lua loads outside the game.
local function NewLibStub()
    local libs = {}
    local stub = {}
    function stub:NewLibrary(major) libs[major] = libs[major] or {}; return libs[major] end
    return setmetatable(stub, { __call = function(_, major) return assert(libs[major], major) end })
end

-- Runs an addon file's text with (addonName, ns). Returns ns.
local function RunAddonFile(text, chunkName, ns, env)
    local chunk = assert(loadstring(text, "@" .. chunkName))
    if env then setfenv(chunk, env) end
    chunk("MarkedForDeath", ns)
    return ns
end

-- Loads Capture.lua with a private LibStub. Returns ns.Capture.
function M.LoadCapture(addonDir, jsonLib)
    local env = setmetatable({ LibStub = NewLibStub() }, { __index = _G })
    local libChunk = assert(loadstring(assert(ReadFile(jsonLib or JSON_LIB)), "@LibICJSON"))
    setfenv(libChunk, env)
    libChunk()
    local ns = {}
    RunAddonFile(assert(ReadFile((addonDir or ADDON_DIR) .. "/Capture.lua")), "Capture.lua", ns, env)
    return ns.Capture
end

-- The data the two files hold now: { list, pending, byInstance }.
function M.LoadData(instancesText, mobsText)
    local ns = {}
    RunAddonFile(instancesText, "Data_Instances.lua", ns)
    RunAddonFile(mobsText, "Data_Mobs.lua", ns)
    return {
        list = ns.Instances.list,
        pending = ns.Instances.pending,
        difficulties = ns.Instances.DIFFICULTIES,
        byInstance = ns.Mobs.byInstance,
    }
end

--------------------------------------------------------------------------------
-- Merge, pure
--------------------------------------------------------------------------------

local function Lower(s) return type(s) == "string" and s:lower() or nil end

local function ExpectedDifficulty(difficulties, kind, size)
    local best
    for id, row in pairs(difficulties or {}) do
        if row.kind == kind and row.size == size and (best == nil or id < best) then best = id end
    end
    return best
end

-- Merges every export (from Capture.Read) into data, in place. Returns a report:
-- { lines = { text, ... }, changed = n }.
function M.Merge(data, exports)
    local report = { lines = {}, changed = 0 }
    local function Say(fmt, ...) report.lines[#report.lines + 1] = string.format(fmt, ...) end
    local function Changed() report.changed = report.changed + 1 end

    local list, byInstance = data.list, data.byInstance

    local function TakePending(name)
        local want = Lower(name)
        if not want then return nil end
        for i, entry in ipairs(data.pending) do
            if Lower(entry.name) == want then return table.remove(data.pending, i) end
        end
        return nil
    end

    for _, export in ipairs(exports) do
        for _, row in ipairs(export.instances) do
            local id = row.id
            local kind = KIND_OF_TYPE[row.type]
            local entry = list[id]
            if not entry then
                local pending = TakePending(row.name)
                if pending then
                    entry = { name = pending.name, kind = pending.kind, size = pending.size, src = "capture" }
                    Say("instance %d is %s (was pending)", id, pending.name)
                else
                    entry = { name = row.name, kind = kind or "unknown", size = row.size, src = "capture" }
                    Say("instance %d is new: %s", id, tostring(row.name))
                end
                list[id] = entry
                Changed()
            end
            if not entry.name and row.name then
                entry.name = row.name
                Say("instance %d is named %s", id, row.name)
                Changed()
            end
            if kind and (entry.kind == nil or entry.kind == "unknown") then
                entry.kind = kind
                Say("instance %d is a %s instance", id, kind)
                Changed()
            elseif kind and entry.kind ~= kind then
                Say("CONFLICT instance %d: the data says %s, the client said %s; kept %s", id, entry.kind, kind, entry.kind)
            end
            if row.size and entry.size ~= row.size then
                if entry.size then
                    Say("instance %d size %d -> %d (the client's own number)", id, entry.size, row.size)
                else
                    Say("instance %d size %d", id, row.size)
                end
                entry.size = row.size
                Changed()
            end
            local expected = ExpectedDifficulty(data.difficulties, entry.kind, entry.size)
            if row.difficulty and expected and row.difficulty ~= expected then
                Say("NOTE instance %d reported difficulty %d (%s); the data expects %d for a %s of %d",
                    id, row.difficulty, tostring(row.difficultyName), expected, entry.kind, entry.size)
            end
        end

        for _, row in ipairs(export.encounters) do
            local instance = row.instance
            local entry = instance and list[instance]
            if not entry then
                Say("SKIPPED encounter %d: no instance %s in the data", row.id, tostring(instance))
            else
                entry.encounters = entry.encounters or {}
                local known = entry.encounters[row.id]
                if not row.name then
                    if not known then Say("SKIPPED encounter %d in instance %d: its name was hidden", row.id, instance) end
                elseif known ~= row.name then
                    if known then
                        Say("encounter %d renamed %s -> %s", row.id, known, row.name)
                    else
                        Say("encounter %d is %s, instance %d", row.id, row.name, instance)
                    end
                    entry.encounters[row.id] = row.name
                    Changed()
                end
            end
        end

        local openWorld = 0
        for _, row in ipairs(export.npcs) do
            local instance = row.instance
            if not instance or instance <= 0 then
                openWorld = openWorld + 1
            else
                if not list[instance] then
                    list[instance] = { kind = "unknown", src = "capture" }
                    Say("instance %d is new (seen only through its mobs)", instance)
                    Changed()
                end
                local mobs = byInstance[instance] or {}
                byInstance[instance] = mobs
                local mob = mobs[row.id]
                if not mob then
                    mob = { name = row.name }
                    mobs[row.id] = mob
                    Say("mob %d %s, instance %d", row.id, row.name, instance)
                    Changed()
                elseif mob.name ~= row.name then
                    Say("CONFLICT mob %d: the data says %s, the client said %s; the client's name kept",
                        row.id, mob.name, row.name)
                    mob.name = row.name
                    Changed()
                end
                local class = row.classification
                local function Set(field, value)
                    if value ~= nil and mob[field] ~= value then mob[field] = value; Changed() end
                end
                if class == "worldboss" then Set("boss", true) end
                if class == "elite" or class == "rareelite" then Set("elite", true) end
                Set("creature", row.creature)
            end
        end
        if openWorld > 0 then Say("%d open-world mobs skipped: Data_Mobs lists instances only", openWorld) end
    end

    -- A mob named like an encounter of its own instance is that encounter's boss.
    for instance, mobs in pairs(byInstance) do
        local entry = list[instance]
        if entry and entry.encounters then
            local names = {}
            for _, name in pairs(entry.encounters) do names[Lower(name)] = true end
            for id, mob in pairs(mobs) do
                if names[Lower(mob.name)] and not mob.boss then
                    mob.boss = true
                    Say("mob %d %s is a boss", id, mob.name)
                    Changed()
                end
            end
        end
    end
    return report
end

--------------------------------------------------------------------------------
-- Writing, pure
--------------------------------------------------------------------------------

local function Quote(s)
    s = tostring(s):gsub("[%c]", "")
    return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

local function SortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

function M.EmitInstances(list)
    local out = { "Instances.list = {" }
    for _, id in ipairs(SortedKeys(list)) do
        local e = list[id]
        local parts = {}
        if e.name then parts[#parts + 1] = "name = " .. Quote(e.name) end
        parts[#parts + 1] = "kind = " .. Quote(e.kind or "unknown")
        if e.size then parts[#parts + 1] = "size = " .. e.size end
        if e.forever then parts[#parts + 1] = "forever = true" end
        if e.src then parts[#parts + 1] = "src = " .. Quote(e.src) end
        if e.encounters and next(e.encounters) then
            local enc = {}
            for _, encID in ipairs(SortedKeys(e.encounters)) do
                enc[#enc + 1] = string.format("[%d] = %s", encID, Quote(e.encounters[encID]))
            end
            parts[#parts + 1] = "encounters = { " .. table.concat(enc, ", ") .. " }"
        end
        out[#out + 1] = string.format("    [%d] = { %s },", id, table.concat(parts, ", "))
    end
    out[#out + 1] = "}"
    return table.concat(out, "\n")
end

-- Raids first, then by name, as the hand-written list has them.
function M.EmitPending(pending)
    local sorted = {}
    for i, e in ipairs(pending) do sorted[i] = e end
    table.sort(sorted, function(a, b)
        if (a.kind == "raid") ~= (b.kind == "raid") then return a.kind == "raid" end
        if a.kind == "raid" and (a.size or 0) ~= (b.size or 0) then return (a.size or 0) < (b.size or 0) end
        return a.name < b.name
    end)
    local out = { "Instances.pending = {" }
    for _, e in ipairs(sorted) do
        local parts = { "name = " .. Quote(e.name), "kind = " .. Quote(e.kind) }
        if e.size then parts[#parts + 1] = "size = " .. e.size end
        if e.opens then parts[#parts + 1] = "opens = " .. Quote(e.opens) end
        out[#out + 1] = "    { " .. table.concat(parts, ", ") .. " },"
    end
    out[#out + 1] = "}"
    return table.concat(out, "\n")
end

function M.EmitMobs(byInstance, list)
    local out = { "Mobs.byInstance = {" }
    for _, instance in ipairs(SortedKeys(byInstance)) do
        local mobs = byInstance[instance]
        if next(mobs) then
            local name = list and list[instance] and list[instance].name
            out[#out + 1] = string.format("    [%d] = {%s", instance, name and (" -- " .. name:gsub("[%c]", "")) or "")
            for _, id in ipairs(SortedKeys(mobs)) do
                local m = mobs[id]
                local parts = { "name = " .. Quote(m.name) }
                if m.boss then parts[#parts + 1] = "boss = true" end
                if m.elite then parts[#parts + 1] = "elite = true" end
                if m.creature then parts[#parts + 1] = "creature = " .. Quote(m.creature) end
                out[#out + 1] = string.format("        [%d] = { %s },", id, table.concat(parts, ", "))
            end
            out[#out + 1] = "    },"
        end
    end
    out[#out + 1] = "}"
    return table.concat(out, "\n")
end

-- Replaces what lies between "-- BEGIN GENERATED <name>" and "-- END GENERATED <name>".
-- Returns the new text, or nil and why when the markers are not there exactly once.
function M.Splice(text, name, body)
    local open = "-- BEGIN GENERATED " .. name .. "\n"
    local close = "-- END GENERATED " .. name .. "\n"
    local a, aEnd = text:find(open, 1, true)
    if not a then return nil, "no BEGIN GENERATED " .. name end
    if text:find(open, aEnd + 1, true) then return nil, "two BEGIN GENERATED " .. name end
    local b, bEnd = text:find(close, aEnd + 1, true)
    if not b then return nil, "no END GENERATED " .. name end
    return text:sub(1, aEnd) .. body .. "\n" .. text:sub(b)
end

-- Both files rewritten from data. Returns instancesText, mobsText (or raises).
function M.Render(instancesText, mobsText, data)
    local i1 = assert(M.Splice(instancesText, "instances", M.EmitInstances(data.list)))
    local i2 = assert(M.Splice(i1, "pending", M.EmitPending(data.pending)))
    local m1 = assert(M.Splice(mobsText, "mobs", M.EmitMobs(data.byInstance, data.list)))
    return i2, m1
end

--------------------------------------------------------------------------------
-- Cases
--------------------------------------------------------------------------------

function M.SelfTest()
    local passed, failed = 0, 0
    local function Case(name, fn)
        local ok, err = pcall(fn)
        if ok then passed = passed + 1 else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
    end
    local function Eq(a, b, label)
        if a ~= b then error(string.format("%s: expected %s, got %s", label, tostring(b), tostring(a)), 2) end
    end

    local Capture = M.LoadCapture()
    local instancesText = assert(ReadFile(ADDON_DIR .. "/Data_Instances.lua"))
    local mobsText = assert(ReadFile(ADDON_DIR .. "/Data_Mobs.lua"))

    Case("the shipped files are in the script's own format", function()
        local data = M.LoadData(instancesText, mobsText)
        local i, m = M.Render(instancesText, mobsText, data)
        Eq(i == instancesText, true, "Data_Instances round-trips")
        Eq(m == mobsText, true, "Data_Mobs round-trips")
    end)

    -- A Lua table constructor keeps the last of two equal keys without a word, so a
    -- duplicate in a generated block would silently drop a mob. Read the source instead.
    Case("no key appears twice in a generated block", function()
        local seen, block = {}, ""
        for line in (instancesText .. mobsText):gmatch("[^\n]+") do
            if line:match("^%S") then seen, block = {}, line end
            local indent, key = line:match("^(%s+)%[(%d+)%] = ")
            if key then
                if #indent == 4 then seen.inner = {} end
                local scope = (#indent == 8 and seen.inner) or seen
                local tag = #indent .. ":" .. key
                Eq(scope[tag], nil, "key " .. key .. " twice in " .. block)
                scope[tag] = true
            end
        end
    end)

    Case("Splice refuses missing or doubled markers", function()
        Eq(M.Splice("x\n", "mobs", "y"), nil, "no markers")
        local two = "-- BEGIN GENERATED mobs\n-- END GENERATED mobs\n-- BEGIN GENERATED mobs\n"
        Eq(M.Splice(two, "mobs", "y"), nil, "two openings")
        Eq(M.Splice("-- BEGIN GENERATED mobs\nold\n-- END GENERATED mobs\n", "mobs", "new"),
            "-- BEGIN GENERATED mobs\nnew\n-- END GENERATED mobs\n", "body replaced")
    end)

    local function Fixture()
        return {
            list = {
                [2999] = { name = "Ruins of Lordaeron", kind = "party", size = 5, src = "fdj",
                    encounters = { [3354] = "Rath'mael" } },
                [2970] = { kind = "unknown", src = "dbcache" },
            },
            pending = {
                { name = "Onyxia's Lair", kind = "raid", size = 40, opens = "2026-12-09" },
                { name = "Hyjal Summit", kind = "raid", size = 20, opens = "2026-12-09" },
            },
            difficulties = { [1] = { kind = "party", size = 5 }, [9] = { kind = "raid", size = 40 },
                [148] = { kind = "raid", size = 20 } },
            byInstance = { [2999] = { [250660] = { name = "The Baron", boss = true } } },
        }
    end

    local function ExportOf(store)
        local text = assert(Capture.Export(store, { version = "0.1.0", now = 100 }))
        return assert(Capture.Read(text))
    end

    Case("a pending raid captured by name takes its id and leaves pending", function()
        local store = {}
        Capture.Merge(store, { kind = "instance", id = 3201, name = "Onyxia's Lair", type = "raid",
            difficulty = 9, size = 40 }, 1)
        Capture.Merge(store, { kind = "encounter", id = 3500, name = "Onyxia", instance = 3201, result = "kill" }, 2)
        Capture.Merge(store, { kind = "npc", id = 10184, name = "Onyxia", instance = 3201,
            classification = "worldboss", creature = "Dragonkin" }, 3)
        Capture.Merge(store, { kind = "npc", id = 12129, name = "Onyxian Warder", instance = 3201,
            classification = "elite" }, 4)
        local data = Fixture()
        local report = M.Merge(data, { ExportOf(store) })
        Eq(data.list[3201].name, "Onyxia's Lair", "named from pending")
        Eq(data.list[3201].size, 40, "size kept")
        Eq(data.list[3201].kind, "raid", "kind kept")
        Eq(#data.pending, 1, "left the pending list")
        Eq(data.pending[1].name, "Hyjal Summit", "the other stays")
        Eq(data.list[3201].encounters[3500], "Onyxia", "encounter filed")
        Eq(data.byInstance[3201][10184].boss, true, "the world boss is a boss")
        Eq(data.byInstance[3201][10184].creature, "Dragonkin", "creature type kept")
        Eq(data.byInstance[3201][12129].elite, true, "elite marked")
        Eq(data.byInstance[3201][12129].boss, nil, "trash is not a boss")
        Eq(report.changed > 0, true, "changes counted")
    end)

    Case("a hidden encounter name keeps the known one; an unknown one is skipped", function()
        local data = Fixture()
        local export = { instances = {}, npcs = {}, encounters = {
            { id = 3354, instance = 2999 },
            { id = 3999, instance = 2999 },
            { id = 4000, instance = 1234, name = "Nobody" },
        } }
        local report = M.Merge(data, { export })
        Eq(data.list[2999].encounters[3354], "Rath'mael", "known name kept")
        Eq(data.list[2999].encounters[3999], nil, "nameless new encounter skipped")
        local text = table.concat(report.lines, "\n")
        Eq(text:find("its name was hidden", 1, true) ~= nil, true, "reported")
        Eq(text:find("no instance 1234", 1, true) ~= nil, true, "unknown instance reported")
    end)

    Case("the client's npc name wins and the conflict is reported", function()
        local data = Fixture()
        local report = M.Merge(data, { { instances = {}, encounters = {}, npcs = {
            { id = 250660, name = "The Butcher", instance = 2999 },
            { id = 250483, name = "Witherfang", instance = 2999 },
            { id = 99, name = "Wolf", instance = 0 },
        } } })
        Eq(data.byInstance[2999][250660].name, "The Butcher", "client name kept")
        Eq(data.byInstance[2999][250660].boss, true, "boss flag survives")
        Eq(data.byInstance[2999][250483].name, "Witherfang", "new mob added")
        local text = table.concat(report.lines, "\n")
        Eq(text:find("CONFLICT mob 250660", 1, true) ~= nil, true, "conflict reported")
        Eq(text:find("1 open-world mobs skipped", 1, true) ~= nil, true, "open world skipped")
    end)

    Case("an unknown-kind map learns its kind, name and size", function()
        local data = Fixture()
        M.Merge(data, { { npcs = {}, encounters = {}, instances = {
            { id = 2970, name = "Serpent's Coil", type = "party", size = 5, difficulty = 1 },
        } } })
        Eq(data.list[2970].name, "Serpent's Coil", "named")
        Eq(data.list[2970].kind, "party", "kind")
        Eq(data.list[2970].size, 5, "size")
        Eq(data.list[2970].src, "dbcache", "source kept")
    end)

    Case("a difficulty id other than expected is noted, not applied", function()
        local data = Fixture()
        local report = M.Merge(data, { { npcs = {}, encounters = {}, instances = {
            { id = 2999, name = "Ruins of Lordaeron", type = "party", size = 5, difficulty = 201 },
        } } })
        Eq(table.concat(report.lines, "\n"):find("reported difficulty 201", 1, true) ~= nil, true, "noted")
    end)

    Case("merge then render then load gives the same data", function()
        local data = M.LoadData(instancesText, mobsText)
        M.Merge(data, { { instances = { { id = 3301, name = "Barrow Deeps", type = "raid", size = 10 } },
            encounters = { { id = 3600, name = "Barrow King", instance = 3301 } },
            npcs = { { id = 270001, name = "Barrow King", instance = 3301, creature = "Undead" },
                { id = 270002, name = "Barrow \"Wight\"", instance = 3301 } } } })
        local i, m = M.Render(instancesText, mobsText, data)
        local again = M.LoadData(i, m)
        Eq(again.list[3301].name, "Barrow Deeps", "instance written")
        Eq(again.list[3301].encounters[3600], "Barrow King", "encounter written")
        Eq(again.byInstance[3301][270001].boss, true, "boss by encounter name")
        Eq(again.byInstance[3301][270002].name, "Barrow \"Wight\"", "quotes survive")
        for _, p in ipairs(again.pending) do Eq(p.name ~= "Barrow Deeps", true, "left pending") end
        local i2, m2 = M.Render(i, m, again)
        Eq(i2 == i and m2 == m, true, "a second render changes nothing")
    end)

    print(string.format("mfd-forever-capture: %d passed, %d failed", passed, failed))
    return failed == 0
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

local function Main(args)
    if args[1] == "--selftest" then
        os.exit(M.SelfTest() and 0 or 1)
    end
    local instancesPath, mobsPath = ADDON_DIR .. "/Data_Instances.lua", ADDON_DIR .. "/Data_Mobs.lua"
    local instancesText = assert(ReadFile(instancesPath))
    local mobsText = assert(ReadFile(mobsPath))
    local data = M.LoadData(instancesText, mobsText)

    if args[1] == "--check" then
        local i, m = M.Render(instancesText, mobsText, data)
        if i ~= instancesText or m ~= mobsText then
            print("the data files are not in the script's format; run it once with --write and review the diff")
            os.exit(1)
        end
        print("the data files are in the script's format")
        return
    end

    local write = false
    local files = {}
    for _, a in ipairs(args) do
        if a == "--write" then write = true else files[#files + 1] = a end
    end
    if #files == 0 then
        print("usage: luajit scripts/mfd-forever-capture.lua [--write] <export file> [...] | --check | --selftest")
        os.exit(2)
    end

    local Capture = M.LoadCapture()
    local exports = {}
    for _, path in ipairs(files) do
        local text = assert(ReadFile(path))
        text = text:gsub("^%s+", ""):gsub("%s+$", "")
        local export, why = Capture.Read(text)
        if not export then
            print(path .. ": " .. tostring(why))
            os.exit(1)
        end
        print(string.format("%s: %d instances, %d encounters, %d mobs, %d auras, %d hidden sightings%s",
            path, #export.instances, #export.encounters, #export.npcs, #export.auras, export.hidden,
            export.skipped > 0 and string.format(", %d unusable rows skipped", export.skipped) or ""))
        exports[#exports + 1] = export
    end

    local report = M.Merge(data, exports)
    for _, line in ipairs(report.lines) do print("  " .. line) end
    for _, export in ipairs(exports) do
        for _, aura in ipairs(export.auras) do
            print(string.format("  aura %d %s (%s): for Data_Auras by hand", aura.id, tostring(aura.name), tostring(aura.source)))
        end
    end

    if report.changed == 0 then
        print("nothing to change")
        return
    end
    local i, m = M.Render(instancesText, mobsText, data)
    if not write then
        print(string.format("%d changes; run again with --write to apply them", report.changed))
        return
    end
    WriteFile(instancesPath, i)
    WriteFile(mobsPath, m)
    print(string.format("%d changes written to Data_Instances.lua and Data_Mobs.lua", report.changed))
end

if arg and arg[0] and arg[0]:match("mfd%-forever%-capture%.lua$") then
    Main(arg)
end

return M
