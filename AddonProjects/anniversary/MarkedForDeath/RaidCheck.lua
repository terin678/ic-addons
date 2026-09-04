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

_G.MarkedForDeath = MFD
