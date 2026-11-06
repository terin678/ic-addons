local addonName, ns = ...

--[[
Tests_RaidCheck: the raid check lane's cases (Data_Auras, RaidCheckModel, and the pure
halves of RaidCheck and UI_RaidCheck). Owned by lane C. Cases registered on ns.Tests with T.Case;
Tests.lua runs them all. Every case builds its own tables.
]]

local T = ns.Tests
local Auras = ns.Auras
local Model = ns.RaidCheckModel

-- Shorthand: an aura list from ids, each { id }.
local function Ids(...)
    local list = {}
    for i = 1, select("#", ...) do list[#list + 1] = { id = (select(i, ...)) } end
    return list
end

local FORT, INT, MARK, SPIRIT, SPROT = 1244, 1459, 21849, 14752, 976
local KINGS, MIGHT = 25898, 19740
local TITANS = 17626
local MONGOOSE, SAGES, BRUTE = 17538, 17535, 17537
local WELL_FED = 1248688

local function ColumnByKey(key)
    for _, c in ipairs(Model.Columns({})) do
        if c.key == key then return c end
    end
end

local function Cell(state, key, providers, extra, ctx)
    ctx = ctx or {}
    ctx.providers = providers or ctx.providers or {}
    return Model.Status(state, ColumnByKey(key), ctx, extra)
end

local ALL = { INT = true, MARK = true, FORT = true, SPIRIT = true, SHADOW = true, blessings = 1 }

--------------------------------------------------------------------------------
-- Data_Auras
--------------------------------------------------------------------------------

T.Case("Data_Auras: no id is claimed twice, and every entry names its source", function()
    local _, problems = Auras.Index()
    T.Eq(#problems, 0, "duplicates: " .. table.concat(problems, "; "))
    local SOURCES = { eui = true, vuhdo = true, dbcache = true, probe = true, classic = true }
    for _, b in ipairs(Auras.BUFFS) do T.True(SOURCES[b.src], "buff " .. b.key .. " source") end
    for _, b in ipairs(Auras.BLESSINGS) do T.True(SOURCES[b.src], "blessing " .. b.key .. " source") end
    for id, c in pairs(Auras.CONSUMABLES) do
        T.True(SOURCES[c.src], tostring(id) .. " source")
        T.True(c.kind == "flask" or c.kind == "elixir", tostring(id) .. " kind")
        T.True(c.slot == nil or c.slot == "battle" or c.slot == "guardian", tostring(id) .. " slot")
    end
    for id, f in pairs(Auras.FOOD) do T.True(SOURCES[f.src], tostring(id) .. " food source") end
end)

T.Case("Data_Auras: an id claimed twice is reported, not overwritten", function()
    local ids, problems = Auras.Index({
        BUFFS = { { key = "A", ids = { 1, 2 } } },
        BLESSINGS = { { key = "B", ids = { 2 } } },
        CONSUMABLES = {}, FOOD = {}, IGNORED = {},
    })
    T.Eq(#problems, 1, "one clash")
    T.True(problems[1]:find("2 is in buff A and blessing B", 1, true), problems[1])
    T.Eq(ids[2].what, "buff", "the first claim stands")
end)

T.Case("Data_Auras: the Forever-only ids are present", function()
    local ids = Auras.Lookup()
    T.Eq(ids[1291335].key, "MARK", "Mark of the Wild, Forever 1291335")
    T.Eq(ids[1310503].key, "MARK", "Mark of the Wild, Forever 1310503")
    T.Eq(ids[1213408].key, "Kings", "Kings, Forever 1213408")
    T.Eq(ids[WELL_FED].what, "food", "Well Fed 1248688 (probe)")
    T.Eq(ids[1245244].what, "elixir", "Minor Arcane Elixir 1245244 (probe)")
    T.Eq(ids[1327736].what, "elixir", "Elixir of Endless Intellect (dbcache)")
    T.Eq(ids[1328127].what, "ignored", "Endless Experience is not raid preparation")
    T.Eq(ids[FORT].key, "FORT", "Fortitude rank seen by the probe")
    T.Eq(ids[INT].key, "INT", "Arcane Intellect rank seen by the probe")
    T.Eq(ids[11371].slot, "guardian", "Gift of Arthas is a guardian elixir")
end)

T.Case("Data_Auras: Buff finds a column by key", function()
    T.Eq(Auras.Buff("SHADOW").required, false, "Shadow Protection is never required")
    T.Eq(Auras.Buff("SPIRIT").proven, true, "Divine Spirit needs proof")
    T.Eq(Auras.Buff("NOPE"), nil, "an unknown key is nil")
end)

--------------------------------------------------------------------------------
-- Classify
--------------------------------------------------------------------------------

T.Case("Classify: buffs, blessings, flask and food by spell id", function()
    local s = Model.Classify(Ids(FORT, INT, MARK, KINGS, MIGHT, TITANS, WELL_FED))
    T.Eq(s.readable, true, "readable")
    T.Eq(s.partial, false, "nothing hidden")
    T.True(s.buffs.FORT and s.buffs.INT and s.buffs.MARK, "three buffs")
    T.True(s.blessings.Kings and s.blessings.Might, "two blessings, greater and single")
    T.Eq(s.flask, "Flask of the Titans", "flask")
    T.Eq(s.food, "Well Fed", "food")
    T.Eq(#Model.Unlisted({ s }), 0, "nothing unlisted")
end)

T.Case("Classify: nothing readable, or nothing at all, is unknown", function()
    local s = Model.Classify(nil)
    T.Eq(s.readable, false, "nil is unreadable")
    T.True(s.why ~= nil, "with a reason")
    local empty = Model.Classify({})
    T.Eq(empty.readable, false, "an empty aura list is a unit we were not given, not a naked raider")
end)

T.Case("Classify: a secret aura makes the answer partial", function()
    local s = Model.Classify({ { id = FORT }, { secret = true }, { id = nil, name = "x" } })
    T.Eq(s.secret, 2, "the secret entry and the one with no id")
    T.Eq(s.partial, true, "partial")
    T.Eq(s.buffs.FORT, true, "what was readable still counts")
end)

T.Case("Classify: unlisted ids fall back by name, and are listed for the table", function()
    local s = Model.Classify({
        { id = 999001, name = "Flask of Something New" },
        { id = 999002, name = "Elixir of the New Thing" },
        { id = 999003, name = "Gift of Arthas" },
        { id = 999004, name = "Hearty Meal", icon = Auras.FOOD_ICON },
        { id = 999005, name = "Some Quest Buff" },
    })
    T.Eq(s.flask, "Flask of Something New", "flask by prefix")
    T.Eq(#s.elixirs, 2, "two elixirs, one by the word and one by name")
    T.Eq(s.food, "Hearty Meal", "food by its icon")
    local unlisted = Model.Unlisted({ s })
    T.Eq(#unlisted, 4, "the four fallbacks are listed")
    T.Eq(unlisted[1], "Elixir of the New Thing", "sorted")
    T.True(not s.unlisted["Some Quest Buff"], "an ordinary buff is not listed")
end)

T.Case("Classify: an ignored consumable counts for nothing", function()
    local s = Model.Classify(Ids(1328127, FORT))
    T.Eq(#s.elixirs, 0, "Endless Experience is not an elixir here")
    T.Eq(#Model.Unlisted({ s }), 0, "and is not unlisted")
end)

T.Case("Classify: the same elixir twice is one elixir", function()
    local s = Model.Classify({ { id = MONGOOSE }, { id = MONGOOSE } })
    T.Eq(#s.elixirs, 1, "one")
end)

--------------------------------------------------------------------------------
-- Flask or two elixirs
--------------------------------------------------------------------------------

T.Case("Flask rule: a flask, or two elixirs, meets it", function()
    T.Eq((Cell(Model.Classify(Ids(TITANS)), "FLASK")), Model.OK, "a flask")
    local status, text = Cell(Model.Classify(Ids(MONGOOSE, SAGES)), "FLASK")
    T.Eq(status, Model.OK, "battle and guardian")
    T.Eq(text, "2 elixirs", "says how many")
    -- Two elixirs without known slots: right on vanilla rules, and where slots exist two
    -- of one kind cannot be worn together anyway.
    T.Eq((Cell(Model.Classify(Ids(1327736, 1327737)), "FLASK")), Model.OK, "two Endless elixirs")
end)

T.Case("Flask rule: one elixir names the half that is missing", function()
    local status, text, label = Cell(Model.Classify(Ids(MONGOOSE)), "FLASK")
    T.Eq(status, Model.MISSING, "half is missing")
    T.Eq(text, "1 elixir", "the cell says one")
    T.Eq(label, "Guardian elixir", "a battle elixir wants a guardian")
    T.Eq(select(3, Cell(Model.Classify(Ids(BRUTE)), "FLASK")), "Battle elixir", "and the other way")
    T.Eq(select(3, Cell(Model.Classify(Ids(1327736)), "FLASK")), "Second elixir", "slot unknown")
    T.Eq(select(3, Cell(Model.Classify(Ids(FORT)), "FLASK")), "Flask or elixirs", "nothing at all")
end)

-- Anniversary, 2026-09-14: a raider wore Major Agility and Gift of Arthas at every pull and
-- was called out at all eleven, because the table did not know Gift of Arthas. Listed or
-- not, it must count.
T.Case("Flask rule: Gift of Arthas beside a battle elixir is two elixirs", function()
    T.Eq((Cell(Model.Classify(Ids(MONGOOSE, 11371)), "FLASK")), Model.OK, "by id")
    local s = Model.Classify({ { id = MONGOOSE }, { id = 999009, name = "Gift of Arthas" } })
    T.Eq((Cell(s, "FLASK")), Model.OK, "and by name when its id is not the classic one")
    local rows = Model.Rows({ { guid = "g1", name = "Moophie" } }, { g1 = s }, nil,
        { columns = { ColumnByKey("FLASK") }, providers = {} })
    T.Eq(#Model.Callout(rows), 0, "nothing to call out")
end)

T.Case("Flask rule: a partial read never says missing", function()
    local s = Model.Classify({ { id = MONGOOSE }, { secret = true } })
    T.Eq((Cell(s, "FLASK")), Model.UNKNOWN, "the hidden aura may be the second elixir")
    T.Eq((Cell(Model.Classify({ { secret = true }, { id = FORT } }), "FOOD")), Model.UNKNOWN, "food too")
end)

--------------------------------------------------------------------------------
-- Buffs and providers
--------------------------------------------------------------------------------

T.Case("Providers: classes present, paladin count, and proof for a talent buff", function()
    local members = { { class = "MAGE" }, { class = "PRIEST" }, { class = "PALADIN" }, { class = "PALADIN" } }
    local p = Model.Providers(members, {})
    T.Eq(p.INT, true, "a mage gives Int")
    T.Eq(p.FORT, true, "a priest gives Fort")
    T.Eq(p.MARK, false, "no druid, no Mark")
    T.Eq(p.SPIRIT, false, "a priest alone does not prove Divine Spirit")
    T.Eq(p.blessings, 2, "two paladins, two blessings")
    local seen = Model.Providers(members, { a = Model.Classify(Ids(SPIRIT)) })
    T.Eq(seen.SPIRIT, true, "somebody wearing it proves it")
    T.Eq(Model.Providers(nil, nil).blessings, 0, "an empty group gives nothing")
end)

T.Case("Buff cell: nobody can cast it is not missing", function()
    local s = Model.Classify(Ids(FORT))
    T.Eq((Cell(s, "MARK", { MARK = false })), Model.NONE, "no druid")
    T.Eq((Cell(s, "MARK", { MARK = true })), Model.MISSING, "a druid present")
    T.Eq(select(3, Cell(s, "MARK", { MARK = true })), "Mark", "labelled for chat")
    T.Eq((Cell(s, "FORT", { FORT = true })), Model.OK, "has it")
    T.Eq((Cell(s, "FORT", { FORT = false })), Model.OK, "has it even with no priest here")
end)

T.Case("Buff cell: Shadow Protection is shown, never missing", function()
    local s = Model.Classify(Ids(FORT))
    T.Eq((Cell(s, "SHADOW", { SHADOW = true })), Model.NONE, "absent and not required")
    T.Eq((Cell(Model.Classify(Ids(SPROT)), "SHADOW", { SHADOW = true })), Model.OK, "shown when worn")
end)

T.Case("Buff cell: secret or unreadable is grey unknown, never red missing", function()
    T.Eq((Cell(Model.Classify(nil), "INT", ALL)), Model.UNKNOWN, "unreadable")
    T.Eq((Cell(Model.Classify({ { secret = true }, { id = FORT } }), "INT", ALL)), Model.UNKNOWN, "partial")
    T.Eq((Cell(nil, "INT", ALL)), Model.UNKNOWN, "no state at all")
    T.Eq((Cell(Model.Classify(nil), "BLESS", ALL)), Model.UNKNOWN, "blessings too")
end)

T.Case("Blessing cell: one per paladin, shown by name", function()
    local one = Model.Classify(Ids(KINGS, FORT))
    local status, text, label = Cell(one, "BLESS", { blessings = 2 })
    T.Eq(status, Model.MISSING, "one of two")
    T.Eq(text, "Kings", "says which")
    T.Eq(label, "Blessing", "one plain label so everyone short groups on one line")
    T.Eq((Cell(Model.Classify(Ids(KINGS, MIGHT)), "BLESS", { blessings = 2 })), Model.OK, "two of two")
    T.Eq((Cell(one, "BLESS", { blessings = 0 })), Model.OK, "no paladin, but carrying one")
    T.Eq((Cell(Model.Classify(Ids(FORT)), "BLESS", { blessings = 0 })), Model.NONE, "no paladin, none")
end)

--------------------------------------------------------------------------------
-- Durability and version
--------------------------------------------------------------------------------

T.Case("Durability: percent of the sums, broken items counted", function()
    local pct, broken = Model.Durability({ { cur = 50, max = 100 }, { cur = 0, max = 50 }, nil, { cur = 75, max = 75 } })
    T.Eq(pct, 55, "125 of 225")
    T.Eq(broken, 1, "one at zero")
    T.Eq(Model.Durability({}), nil, "nothing equipped")
    T.Eq(Model.Durability({ { cur = 1, max = 0 } }), nil, "a zero max is ignored")
end)

T.Case("Durability cell: under the floor or broken is missing; unknown is grey", function()
    local col = { key = "DUR", kind = "durability", label = "Dur" }
    T.Eq((Model.Status(nil, col, { minDurability = 50 }, { durability = 80, broken = 0 })), Model.OK, "fine")
    T.Eq((Model.Status(nil, col, { minDurability = 50 }, { durability = 40 })), Model.MISSING, "low")
    T.Eq(select(3, Model.Status(nil, col, { minDurability = 50 }, { durability = 90, broken = 1 })),
        "Repair (1 broken)", "a broken item is called out even at 90%")
    T.Eq((Model.Status(nil, col, {}, {})), Model.UNKNOWN, "nobody said")
end)

T.Case("Version cell: older is amber, unknown grey, never missing", function()
    local col = { key = "VER", kind = "version", label = "Ver" }
    T.Eq((Model.Status(nil, col, { myVersion = "0.2.0" }, { version = "0.1.9" })), Model.OLD, "older")
    T.Eq((Model.Status(nil, col, { myVersion = "0.2.0" }, { version = "0.2.0" })), Model.OK, "same")
    T.Eq((Model.Status(nil, col, { myVersion = "0.2.0" }, { version = "0.10.0" })), Model.OK, "newer, by number")
    T.Eq((Model.Status(nil, col, { myVersion = "0.2.0" }, {})), Model.UNKNOWN, "no hello")
    T.Eq(Model.Older("1.2", "1.2.0"), false, "a missing part is zero")
    T.Eq(Model.Older(nil, "1"), nil, "not a version")
end)

--------------------------------------------------------------------------------
-- Columns, rows, callout
--------------------------------------------------------------------------------

T.Case("Columns: the saved switches hide whole groups", function()
    local all = Model.Columns({})
    T.Eq(#all, #Auras.BUFFS + 5, "every buff, blessings, flask, food, durability, version")
    T.Eq(all[1].key, "INT", "Int first")
    local some = Model.Columns({ buffs = false, version = false })
    T.Eq(#some, 3, "flask, food, durability")
    T.Eq(some[1].key, "FLASK", "flask first")
end)

T.Case("Rows: sorted by name, missing and unknown counted, unknown never called out", function()
    local members = {
        { guid = "c", display = "Cid Dee", class = "WARRIOR" },
        { guid = "a", display = "Ann Bee", class = "MAGE" },
        { guid = "b", display = "Bob Cat", class = "PRIEST" },
    }
    local states = {
        a = Model.Classify(Ids(INT, FORT, TITANS, WELL_FED)),
        b = Model.Classify(Ids(INT, WELL_FED)),
        c = Model.Classify(nil),
    }
    local ctx = { columns = Model.Columns({ durability = false, version = false }), data = Auras }
    ctx.providers = Model.Providers(members, states)
    local rows = Model.Rows(members, states, nil, ctx)
    T.Eq(rows[1].name, "Ann Bee", "sorted")
    T.Eq(#rows[1].missing, 0, "Ann has it all")
    T.Eq(Model.MissingLine(rows[1]), nil, "nothing to say")
    T.Eq(Model.MissingLine(rows[2]), "Fort, Flask or elixirs", "Bob")
    T.Eq(#rows[3].missing, 0, "Cid could not be read: nothing missing")
    T.True(rows[3].unknown > 0, "but unknown cells counted")
    local lines = Model.Callout(rows)
    T.Eq(#lines, 2, "two fixes")
    T.Eq(lines[1], "Fort: Bob Cat", "grouped by fix")
    T.Eq(lines[2], "Flask or elixirs: Bob Cat", "in the order they appear")
end)

T.Case("Callout: names sorted, capped at four lines, long lines cut", function()
    local rows = {}
    for i, label in ipairs({ "A", "B", "C", "D", "E", "F" }) do
        rows[#rows + 1] = { name = "P" .. i, missing = { { key = label, label = label } } }
    end
    rows[#rows + 1] = { name = "Aaa", missing = { { key = "A", label = "A" } } }
    local lines = Model.Callout(rows)
    T.Eq(#lines, 4, "four lines")
    T.Eq(lines[1], "A: Aaa, P1", "names sorted")
    T.True(lines[4]:find("(and 2 more)", 1, true), "says what was left out")
    local long = {}
    for i = 1, 40 do long[#long + 1] = { name = "Name" .. i, missing = { { key = "X", label = "X" } } } end
    local cut = Model.Callout(long)
    T.Eq(#cut[1], Model.CALLOUT_LINE_BYTES, "cut to the byte cap")
    T.True(cut[1]:sub(-3) == "...", "with an ellipsis")
    T.Eq(#Model.Callout({}), 0, "nothing missing, nothing said")
end)

--------------------------------------------------------------------------------
-- Reads and the ready check
--------------------------------------------------------------------------------

T.Case("MayRead: the regen event alone still reads; lockdown, combat or secrecy does not", function()
    T.Eq(Model.MayRead({ lockdown = false, combat = false, aurasSecret = false }), true, "out of combat")
    -- At PLAYER_REGEN_DISABLED the lock is about three seconds away: that read is the
    -- snapshot a pull keeps.
    T.Eq(Model.MayRead({ lockdown = false, combat = false, aurasSecret = false, regen = true }), true,
        "at the regen event")
    T.Eq(Model.MayRead({ lockdown = true, aurasSecret = false }), false, "lockdown")
    T.Eq(Model.MayRead({ combat = true, aurasSecret = false }), false, "Combat restriction")
    local ok, why = Model.MayRead({ aurasSecret = true })
    T.Eq(ok, false, "secret auras")
    T.True(why:find("hiding", 1, true), "says why")
    T.Eq(Model.MayRead({}), false, "an unanswered secrecy check is taken as secret")
end)

T.Case("ShouldAutoOpen: leader or assist only, and the switch wins", function()
    local function Roster(kind, rank, everyone)
        return { kind = kind, me = { rank = rank }, everyoneAssist = everyone }
    end
    T.Eq(Model.ShouldAutoOpen(Roster("raid", "leader"), {}), true, "raid leader")
    T.Eq(Model.ShouldAutoOpen(Roster("raid", "assist"), {}), true, "assistant")
    T.Eq(Model.ShouldAutoOpen(Roster("raid", "member"), {}), false, "a member")
    T.Eq(Model.ShouldAutoOpen(Roster("raid", nil), {}), false, "a rank that could not be read")
    T.Eq(Model.ShouldAutoOpen(Roster("raid", "member", true), {}), true, "everyone is assistant")
    T.Eq(Model.ShouldAutoOpen(Roster("party", "leader"), {}), true, "party leader")
    T.Eq(Model.ShouldAutoOpen(Roster("solo", "leader"), {}), false, "alone")
    T.Eq(Model.ShouldAutoOpen(Roster("raid", "leader"), { autoOpen = false }), false, "switched off")
    T.Eq(Model.ShouldAutoOpen(nil, {}), false, "no roster")
end)

T.Case("RaidCheckUI.ListColumns: name fills, each cell column keeps its kind's width", function()
    local UI = ns.RaidCheckUI
    local columns = Model.Columns({})
    local list = UI.ListColumns(columns)
    T.Eq(#list, #columns + 1, "a name column plus one per model column")
    T.Eq(list[1].key, "name", "name first")
    T.Eq(list[1].width, nil, "the name column fills")
    for i, c in ipairs(columns) do
        T.Eq(list[i + 1].key, c.key, "same order: " .. c.key)
        T.True(type(list[i + 1].width) == "number" and list[i + 1].width > 0, "fixed width: " .. c.key)
    end
    local flask = UI.ListColumns({ { key = "flask", label = "Flask", kind = "flask" } })[2]
    T.Eq(flask.justify, "LEFT", "flask text reads from the left")
    local odd = UI.ListColumns({ { key = "x", label = "X", kind = "nothing known" } })[2]
    T.Eq(odd.width, 40, "an unknown kind gets the narrow width")
end)

T.Case("RaidCheckUI.GridCell: colour roles, and grey is never red", function()
    local UI = ns.RaidCheckUI
    local row = { name = "Ann", missing = {}, unknown = 0, cells = {
        fort = { status = "ok", text = "yes" },
        int = { status = "missing", text = "no" },
        mark = { status = "unknown", text = "?" },
        ver = { status = "old", text = "0.0.9" },
        sprot = { status = "none", text = "-" },
        odd = { status = "made up", text = "x" },
    } }
    local function Role(key) return select(2, UI.GridCell(row, { key = key })) end
    T.Eq(Role("fort"), "good", "ok")
    T.Eq(Role("int"), "bad", "missing")
    T.Eq(Role("mark"), "textDim", "unknown is grey")
    T.Eq(Role("ver"), "warn", "older version")
    T.Eq(Role("sprot"), "textDisabled", "nothing expected")
    T.Eq(Role("odd"), "textDim", "a status the grid does not know is grey, not red")
    T.Eq(UI.GridCell(row, { key = "fort" }), "yes", "the cell's text")
    T.Eq(UI.GridCell(row, { key = "absent" }), "", "a column with no cell is blank")
    T.Eq(select(2, UI.GridCell(row, { key = "name" })), "good", "nothing missing: green name")
    row.unknown = 1
    T.Eq(select(2, UI.GridCell(row, { key = "name" })), "textDim", "only unread: grey name")
    row.missing = { "Fort" }
    T.Eq(select(2, UI.GridCell(row, { key = "name" })), "bad", "missing something: red name")
end)
