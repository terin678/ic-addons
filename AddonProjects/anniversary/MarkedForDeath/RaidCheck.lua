-- Raid buff and consumable check.
--
-- The functions above the "client" marker are pure and tested. Everything
-- below it touches the client and runs from RegisterInit or a command.
local MFD = _G.MarkedForDeath or {}

MFD.RaidCheck = MFD.RaidCheck or {}
local RC = MFD.RaidCheck

-- Takes an array of aura names on one unit. Returns that unit's buff state.
-- Unknown names are ignored. Booleans are explicit false when absent so a
-- cell can be painted red rather than grey.
function RC.Classify(auraNames)
    local A = MFD.Data.Auras
    local state = {
        food = nil, flask = nil, battle = nil, guardian = nil, unclassifiedElixir = nil,
        blessings = {},
    }
    for column in pairs(A.RAID_BUFFS) do
        state[column] = false
    end

    local nameSet = {}
    for _, name in ipairs(auraNames) do
        if type(name) == "string" and name ~= "" then
            nameSet[name] = true
        end
    end

    for column, def in pairs(A.RAID_BUFFS) do
        for _, name in ipairs(def.names) do
            if nameSet[name] then
                state[column] = true
            end
        end
    end

    local blessingSeen = {}
    for name in pairs(nameSet) do
        if A.FOOD[name] then
            state.food = name
        elseif string.sub(name, 1, #A.FLASK_PREFIX) == A.FLASK_PREFIX then
            state.flask = name
        elseif A.BATTLE_ELIXIRS[name] then
            state.battle = name
        elseif A.GUARDIAN_ELIXIRS[name] then
            state.guardian = name
        elseif string.find(name, A.ELIXIR_PATTERN, 1, true) then
            state.unclassifiedElixir = name
        elseif A.BLESSINGS[name] then
            blessingSeen[A.BLESSINGS[name]] = true
        end
    end

    for label in pairs(blessingSeen) do
        state.blessings[#state.blessings + 1] = label
    end
    table.sort(state.blessings)

    return state
end

RC.CONSUMABLE_ORDER = { "FOOD", "FLASK", "BATTLE", "GUARDIAN", "WEAPON" }
RC.CONSUMABLE_LABELS = {
    FOOD = "Food", FLASK = "Flask", BATTLE = "Battle elixir",
    GUARDIAN = "Guardian elixir", WEAPON = "Weapon enchant",
}

-- Takes the roster ({ name, class } array). Returns { [column] = bool } saying
-- whether anyone present can cast each raid buff. Pure.
function RC.Providers(roster)
    local classesPresent = {}
    for _, member in ipairs(roster or {}) do
        classesPresent[member.class] = true
    end

    local providers = {}
    for column, def in pairs(MFD.Data.Auras.RAID_BUFFS) do
        providers[column] = false
        for _, class in ipairs(def.classes) do
            if classesPresent[class] then
                providers[column] = true
            end
        end
    end
    return providers
end

-- Takes a player's state, the providers table and { [consumable] = true } for
-- the consumables the raid expects. Returns an array of { column, label } in a
-- fixed order: raid buffs first, then consumables. Pure.
--
-- A raid buff is missing only when absent AND someone present can cast it.
-- A consumable is missing only when expected AND known to be absent; unknown
-- (no self-report yet) is never reported, because "no data" is not "no flask".
function RC.Missing(state, providers, expected)
    local A = MFD.Data.Auras
    local missing = {}

    for _, column in ipairs(A.RAID_BUFF_ORDER) do
        if providers[column] and state[column] == false then
            missing[#missing + 1] = { column = column, label = A.RAID_BUFFS[column].label }
        end
    end

    local present = {
        FOOD = state.food ~= nil,
        FLASK = state.flask ~= nil,
        BATTLE = state.battle ~= nil,
        GUARDIAN = state.guardian ~= nil,
        WEAPON = state.weapon,
    }

    for _, column in ipairs(RC.CONSUMABLE_ORDER) do
        if expected[column] and present[column] == false then
            missing[#missing + 1] = { column = column, label = RC.CONSUMABLE_LABELS[column] }
        end
    end

    return missing
end

_G.MarkedForDeath = MFD
