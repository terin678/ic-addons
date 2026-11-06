local addonName, ns = ...

--[[
RaidCheckModel: aura answers to the grid, the missing list and callout groups.
Owned by lane C (raid check). Pure: no client call, ever; every function takes its tables
as arguments.

The one rule that matters most: what the client would not let us read is "unknown" (grey),
never "missing" (red). A member out of sight, a secret aura, an aura list that came back
empty: none of these is evidence that someone forgot a flask, and a callout that names the
wrong people teaches a raid to ignore the callout.

    Model.Classify(auras, lookup, data)        one member's auras -> their state
    Model.Providers(members, states, data)     what the group can hand out
    Model.Columns(columns, data)               the grid's columns, in order
    Model.Status(state, column, providers, ctx) -> status, text, label for one cell
    Model.Rows(members, states, ctx)           the whole grid, sorted by name
    Model.Callout(rows), Model.MissingLine(row) chat lines
    Model.Durability(slots)                    percent and broken count
    Model.MayRead(facts)                       whether auras may be read now
    Model.ShouldAutoOpen(roster, settings)     open the grid on a ready check?
    Model.Unlisted(states)                     names of auras no table knows
]]

ns.RaidCheckModel = ns.RaidCheckModel or {}
local Model = ns.RaidCheckModel

-- Cell statuses. One colour each on every surface: ok green, missing red, unknown grey,
-- old amber, none dim (nothing expected: nobody can cast it, or it is never required).
Model.OK, Model.MISSING, Model.UNKNOWN, Model.OLD, Model.NONE = "ok", "missing", "unknown", "old", "none"

Model.CALLOUT_MAX_LINES = 4      -- lines per callout
Model.CALLOUT_LINE_BYTES = 200   -- bytes per line, under the 255 chat cap
Model.DEFAULT_MIN_DURABILITY = 50  -- percent

local function Count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

local function SortedKeys(t)
    local keys = {}
    for k in pairs(t or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

--------------------------------------------------------------------------------
-- One member
--------------------------------------------------------------------------------

local function AddElixir(state, name, slot)
    for _, e in ipairs(state.elixirs) do
        if e.name == name then return end
    end
    state.elixirs[#state.elixirs + 1] = { name = name, slot = slot }
end

local function AddUnlisted(state, name)
    if type(name) == "string" and name ~= "" then state.unlisted[name] = true end
end

-- An aura whose id no table lists: the name and icon rules in data.FALLBACK. Only ever
-- adds what the member holds; never takes anything away.
local function Fallback(state, aura, data)
    local name, fb = aura.name, data.FALLBACK or {}
    if type(name) ~= "string" then name = nil end
    if (data.FOOD_ICON and aura.icon == data.FOOD_ICON) or (name and (data.FOOD_NAMES or {})[name]) then
        state.food = state.food or name or "food"
        AddUnlisted(state, name)
    elseif name and fb.flaskPrefix and name:sub(1, #fb.flaskPrefix) == fb.flaskPrefix then
        state.flask = state.flask or name
        AddUnlisted(state, name)
    elseif name and fb.names and fb.names[name] then
        AddElixir(state, name, fb.names[name])
        AddUnlisted(state, name)
    elseif name and fb.elixirWord and name:find(fb.elixirWord, 1, true) then
        AddElixir(state, name, nil)
        AddUnlisted(state, name)
    end
end

--[[
`auras` is what the client gave for one member, a list of { id, name, icon }, with
`secret = true` on an entry whose id could not be read. nil means nothing could be read
at all (offline, out of sight, combat). `lookup` is Auras.Index's id table; `data` the
Auras tables (for the fallbacks).

Returns the state:
    readable    false when there is nothing to go on; then `why` says so
    partial     some aura could not be read, so an absence is not proof
    buffs       { [key] = true }      blessings { [key] = true }
    flask       its name, or nil      elixirs   { { name, slot } }
    food        its name, or nil      unlisted  { [name] = true }, matched by name only
]]
function Model.Classify(auras, lookup, data)
    data = data or ns.Auras
    lookup = lookup or data.Lookup()
    local state = {
        readable = true, partial = false, secret = 0,
        buffs = {}, blessings = {}, elixirs = {}, unlisted = {},
    }
    if type(auras) ~= "table" then
        state.readable, state.why = false, "not readable"
        return state
    end
    -- Nobody in a raid wears nothing at all; an empty answer is a unit the client did
    -- not give us, not a naked raider.
    if #auras == 0 then
        state.readable, state.why = false, "no auras came back"
        return state
    end
    for _, aura in ipairs(auras) do
        local id = aura.id
        if aura.secret or type(id) ~= "number" then
            state.secret = state.secret + 1
        else
            local e = lookup[id]
            if not e then
                Fallback(state, aura, data)
            elseif e.what == "buff" then
                state.buffs[e.key] = true
            elseif e.what == "blessing" then
                state.blessings[e.key] = true
            elseif e.what == "flask" then
                state.flask = state.flask or e.name
            elseif e.what == "elixir" then
                AddElixir(state, e.name, e.slot)
            elseif e.what == "food" then
                state.food = state.food or e.name
            end
        end
    end
    state.partial = state.secret > 0
    return state
end

--------------------------------------------------------------------------------
-- The group
--------------------------------------------------------------------------------

--[[
`members` are LibICGroup roster members ({ class, ... }), `states` the Classify results
keyed by the same member's guid (or index). Returns { [buffKey] = true } for every buff
somebody present can give, and `blessings`, the paladin count: one blessing each is what
a member should carry. A `proven` buff (a talent, such as Divine Spirit) also needs
somebody seen wearing it, because a class alone does not prove anyone has the talent.
]]
function Model.Providers(members, states, data)
    data = data or ns.Auras
    local classes = {}
    for _, m in ipairs(members or {}) do
        if m.class then classes[m.class] = (classes[m.class] or 0) + 1 end
    end
    local providers = { blessings = 0 }
    for _, buff in ipairs(data.BUFFS) do
        local can = false
        for _, class in ipairs(buff.classes) do
            if classes[class] then can = true end
        end
        if can and buff.proven then
            can = false
            for _, s in pairs(states or {}) do
                if s.buffs and s.buffs[buff.key] then can = true end
            end
        end
        providers[buff.key] = can
    end
    for _, class in ipairs(data.BLESSING_CLASSES) do
        providers.blessings = providers.blessings + (classes[class] or 0)
    end
    return providers
end

--[[
The grid's columns in order, from the saved `check.columns` switches ({ buffs, flask,
food, durability, version }, a missing switch is on). Each is { key, label, kind } with
kind "buff", "blessing", "flask", "food", "durability" or "version".
]]
function Model.Columns(columns, data)
    data = data or ns.Auras
    columns = columns or {}
    local out = {}
    if columns.buffs ~= false then
        for _, buff in ipairs(data.BUFFS) do
            out[#out + 1] = { key = buff.key, label = buff.label, kind = "buff" }
        end
        out[#out + 1] = { key = "BLESS", label = "Bless", kind = "blessing" }
    end
    if columns.flask ~= false then out[#out + 1] = { key = "FLASK", label = "Flask", kind = "flask" } end
    if columns.food ~= false then out[#out + 1] = { key = "FOOD", label = "Food", kind = "food" } end
    if columns.durability ~= false then out[#out + 1] = { key = "DUR", label = "Dur", kind = "durability" } end
    if columns.version ~= false then out[#out + 1] = { key = "VER", label = "Ver", kind = "version" } end
    return out
end

-- The words for half a flask requirement: the slot the member still needs, when the one
-- elixir they hold has a known slot.
local function ElixirLabel(state)
    local one = state.elixirs[1]
    if one and one.slot == "battle" then return "Guardian elixir" end
    if one and one.slot == "guardian" then return "Battle elixir" end
    return "Second elixir"
end

-- Whether version `a` is older than `b`, part by part as numbers. nil when either is not
-- a version.
local function Older(a, b)
    if type(a) ~= "string" or type(b) ~= "string" then return nil end
    local pa, pb = {}, {}
    for n in a:gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
    for n in b:gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
    if #pa == 0 or #pb == 0 then return nil end
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x < y end
    end
    return false
end
Model.Older = Older

--[[
One cell. `column` from Columns; `ctx` = { providers, data, minDurability, myVersion }
and the row's `extra` = { durability, broken, version } (any may be nil).
Returns status, text, label: `label` is what a missing cell is called in chat ("Int",
"Flask or elixirs"), nil unless the status is missing.
]]
function Model.Status(state, column, ctx, extra)
    ctx, extra = ctx or {}, extra or {}
    local providers, data = ctx.providers or {}, ctx.data or ns.Auras
    local kind = column.kind

    if kind == "durability" then
        local pct = extra.durability
        if type(pct) ~= "number" then return Model.UNKNOWN, "?" end
        local text = pct .. "%"
        if (extra.broken or 0) > 0 then
            return Model.MISSING, text, "Repair (" .. extra.broken .. " broken)"
        end
        if pct < (ctx.minDurability or Model.DEFAULT_MIN_DURABILITY) then
            return Model.MISSING, text, "Repair"
        end
        return Model.OK, text
    end

    if kind == "version" then
        local v = extra.version
        if type(v) ~= "string" then return Model.UNKNOWN, "?" end
        if Older(v, ctx.myVersion) then return Model.OLD, v end
        return Model.OK, v
    end

    if not state or not state.readable then return Model.UNKNOWN, "?" end

    if kind == "buff" then
        if state.buffs[column.key] then return Model.OK, "+" end
        if not providers[column.key] then return Model.NONE, "-" end
        local buff = data.Buff and data.Buff(column.key)
        if buff and buff.required == false then return Model.NONE, "-" end
        if state.partial then return Model.UNKNOWN, "?" end
        return Model.MISSING, "-", column.label
    end

    if kind == "blessing" then
        local have, want = Count(state.blessings), providers.blessings or 0
        local text = have > 0 and table.concat(SortedKeys(state.blessings), " ") or "-"
        if want == 0 then return have > 0 and Model.OK or Model.NONE, text end
        if have >= want then return Model.OK, text end
        if state.partial then return Model.UNKNOWN, text end
        return Model.MISSING, text, "Blessing"
    end

    if kind == "flask" then
        if state.flask then return Model.OK, state.flask end
        local n = #state.elixirs
        if n >= 2 then return Model.OK, n .. " elixirs" end
        if state.partial then return Model.UNKNOWN, n == 1 and "1 elixir" or "?" end
        if n == 1 then return Model.MISSING, "1 elixir", ElixirLabel(state) end
        return Model.MISSING, "-", "Flask or elixirs"
    end

    if kind == "food" then
        if state.food then return Model.OK, "+" end
        if state.partial then return Model.UNKNOWN, "?" end
        return Model.MISSING, "-", "Food"
    end

    return Model.UNKNOWN, "?"
end

--[[
The whole grid. `members` are roster members ({ guid, name, display, class, online }),
`states` and `extras` keyed by guid. `ctx` = { columns (from Columns), providers, data,
minDurability, myVersion }. Returns rows sorted by name:
    { member, name, class, cells = { [colKey] = { status, text } }, missing = { { key, label } },
      unknown = n (cells that could not be read) }
]]
function Model.Rows(members, states, extras, ctx)
    local rows = {}
    for _, m in ipairs(members or {}) do
        local key = m.guid or m.name
        local state, extra = (states or {})[key], (extras or {})[key]
        local row = {
            member = m, name = m.display or m.name or "?", class = m.class,
            cells = {}, missing = {}, unknown = 0, state = state,
        }
        for _, column in ipairs(ctx.columns or {}) do
            local status, text, label = Model.Status(state, column, ctx, extra)
            row.cells[column.key] = { status = status, text = text }
            if status == Model.MISSING then
                row.missing[#row.missing + 1] = { key = column.key, label = label or column.label }
            elseif status == Model.UNKNOWN then
                row.unknown = row.unknown + 1
            end
        end
        rows[#rows + 1] = row
    end
    table.sort(rows, function(a, b) return a.name < b.name end)
    return rows
end

--[[
Chat lines grouped by the fix, in the order the fixes first appear, names sorted:
"Int: Ann Bee, Cid Dee". Grouped by fix because that is what makes it actionable: the
mage reads the Int line. Unknown cells are never called out. At most CALLOUT_MAX_LINES
lines, the last one saying how many fixes were left out; a long line is cut with "...".
]]
function Model.Callout(rows)
    local byFix, order = {}, {}
    for _, row in ipairs(rows or {}) do
        for _, m in ipairs(row.missing or {}) do
            if not byFix[m.label] then
                byFix[m.label] = {}
                order[#order + 1] = m.label
            end
            table.insert(byFix[m.label], row.name)
        end
    end
    local lines = {}
    for i, label in ipairs(order) do
        if i > Model.CALLOUT_MAX_LINES then
            lines[#lines] = lines[#lines] .. " (and " .. (#order - Model.CALLOUT_MAX_LINES) .. " more)"
            break
        end
        local names = byFix[label]
        table.sort(names)
        local line = label .. ": " .. table.concat(names, ", ")
        if #line > Model.CALLOUT_LINE_BYTES then
            line = line:sub(1, Model.CALLOUT_LINE_BYTES - 3) .. "..."
        end
        lines[#lines + 1] = line
    end
    return lines
end

-- One row's missing list as words ("Int, Food"), or nil when nothing is missing.
function Model.MissingLine(row)
    if not row or #(row.missing or {}) == 0 then return nil end
    local labels = {}
    for _, m in ipairs(row.missing) do labels[#labels + 1] = m.label end
    return table.concat(labels, ", ")
end

--------------------------------------------------------------------------------
-- Durability, reads, ready check
--------------------------------------------------------------------------------

-- The equipped slots that wear: head, shoulder, chest, waist, legs, feet, wrist, hands,
-- main hand, off hand, ranged.
Model.DURABILITY_SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 16, 17, 18 }

--[[
`slots` is a list of { cur, max } (nil entries for empty slots are fine). Returns the
overall percent (floor of the sums) and how many items are at zero, or nil when nothing
that wears is equipped. The broken count is apart because a broken weapon matters more
than a low average.
]]
function Model.Durability(slots)
    local cur, max, broken = 0, 0, 0
    for _, s in pairs(slots or {}) do
        if type(s) == "table" and type(s.cur) == "number" and type(s.max) == "number" and s.max > 0 then
            cur, max = cur + s.cur, max + s.max
            if s.cur == 0 then broken = broken + 1 end
        end
    end
    if max == 0 then return nil end
    return math.floor(cur / max * 100), broken
end

--[[
Whether auras may be read now. `facts` = { lockdown = InCombatLockdown(), combat = the
Combat restriction is on, aurasSecret = C_Secrets.ShouldAurasBeSecret() }. Returns ok, why.

PLAYER_REGEN_DISABLED alone is not a reason to stop: the lock arrives about three seconds
after it, so a read at the event is still good, and that snapshot is the one a pull keeps.
An answer that is not a plain boolean false (nil, secret) counts as secret.
]]
function Model.MayRead(facts)
    facts = facts or {}
    if facts.lockdown == true then return false, "in combat" end
    if facts.combat == true then return false, "in combat" end
    if facts.aurasSecret ~= false then return false, "the client is hiding auras" end
    return true
end

--[[
Whether the grid opens itself on a ready check: only for the group's leader or an
assistant, and only when `settings.autoOpen` is not false. A window on twenty four screens
at every ready check is how an addon gets uninstalled; everyone else's check still runs,
so their buff board is fresh. `roster` is a LibICGroup snapshot.
]]
function Model.ShouldAutoOpen(roster, settings)
    if settings and settings.autoOpen == false then return false end
    if not roster or roster.kind == "solo" or not roster.me then return false end
    local rank = roster.me.rank
    return rank == "leader" or rank == "assist" or roster.everyoneAssist == true
end

-- Every unlisted aura name across `states`, sorted: the ids /mfd auras asks to be added.
function Model.Unlisted(states)
    local set = {}
    for _, s in pairs(states or {}) do
        for name in pairs(s.unlisted or {}) do set[name] = true end
    end
    return SortedKeys(set)
end
