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

    -- A flask occupies both elixir slots, so it satisfies both.
    local hasFlask = state.flask ~= nil
    local present = {
        FOOD = state.food ~= nil,
        FLASK = hasFlask,
        BATTLE = hasFlask or state.battle ~= nil,
        GUARDIAN = hasFlask or state.guardian ~= nil,
        WEAPON = state.weapon,
    }

    for _, column in ipairs(RC.CONSUMABLE_ORDER) do
        if expected[column] and present[column] == false then
            missing[#missing + 1] = { column = column, label = RC.CONSUMABLE_LABELS[column] }
        end
    end

    return missing
end

local REPORT_ONLY = { "weapon", "durability", "spec", "version" }
local FLAG_ONLY = { "AI", "MOTW", "FORT", "SP" }

-- Takes a scanned state and a reported state (or nil). Returns
-- { state, isReported }. Pure.
--
-- The owning client is the authority on its own flags, so a non-nil reported
-- flag overrides the scan. Names come only from the scan because the wire
-- carries flags, not names. Weapon, durability, spec and version come only
-- from the report because nothing else can see them.
function RC.MergeRow(scanned, reported)
    local state = {}
    for k, v in pairs(scanned) do
        state[k] = v
    end

    if not reported then
        return { state = state, isReported = false }
    end

    for _, key in ipairs(FLAG_ONLY) do
        if reported[key] ~= nil then
            state[key] = reported[key]
        end
    end

    for _, key in ipairs(REPORT_ONLY) do
        state[key] = reported[key]
    end

    return { state = state, isReported = true }
end

RC.REPORT_HEARTBEAT_SECONDS = 60   -- periodic self-report while in a group
RC.REPORT_DEBOUNCE_SECONDS = 2     -- coalesce bursts of change into one report

-- Tri-state flags on the wire: 1 true, 0 false, ? unknown. Unknown must stay
-- distinct from false, because "no data" is not "no flask".
local FLAG_ORDER = { "weapon", "AI", "MOTW", "FORT", "SP", "food", "flask", "battle", "guardian" }

local function flagChar(v)
    if v == true then
        return "1"
    end
    if v == false then
        return "0"
    end
    return "?"
end

local function charFlag(c)
    if c == "1" then
        return true
    end
    if c == "0" then
        return false
    end
    return nil
end

-- Takes a state. Returns the fields array for a PC message:
-- { version, flags, durability, spec }. Pure.
function RC.EncodeReport(state)
    local flags = {}
    for i, key in ipairs(FLAG_ORDER) do
        flags[i] = flagChar(state[key])
    end
    return {
        state.version or "?",
        table.concat(flags),
        state.durability and tostring(math.floor(state.durability)) or "?",
        state.spec or "?",
    }
end

-- Takes the fields array from a PC message. Returns a state, or nil when the
-- fields are not a report. Pure.
function RC.DecodeReport(fields)
    if type(fields) ~= "table" or #fields < 4 then
        return nil
    end
    local flags = fields[2]
    if type(flags) ~= "string" or #flags ~= #FLAG_ORDER then
        return nil
    end

    local state = { version = fields[1] ~= "?" and fields[1] or nil }
    for i, key in ipairs(FLAG_ORDER) do
        state[key] = charFlag(string.sub(flags, i, i))
    end
    state.durability = tonumber(fields[3])
    state.spec = fields[4] ~= "?" and fields[4] or nil
    return state
end

-- ---------------------------------------------------------------- client --
-- Everything below touches the client. Nothing here runs at file scope
-- beyond caching globals, so the harness can still load this file.

local UnitAura = UnitAura
local GetWeaponEnchantInfo = GetWeaponEnchantInfo
local GetInventoryItemDurability = GetInventoryItemDurability
local GetTalentTabInfo = GetTalentTabInfo

-- Reports received from other clients, { [playerName] = { state, at } }.
RC.reports = {}

-- Returns an array of aura names on unit. Reads only the first return of
-- UnitAura, which is the name on every client build. Wrapped because the
-- return signature differs across the flavors this repo targets.
function RC.AuraNames(unit)
    local names = {}
    if not UnitAura then
        return names
    end
    for i = 1, 40 do
        local ok, name = pcall(UnitAura, unit, i, "HELPFUL")
        if not ok or not name then
            break
        end
        names[#names + 1] = name
    end
    return names
end

-- Equipped item slots that have durability: head, shoulder, chest, waist,
-- legs, feet, wrist, hands, main hand, off hand, ranged. Same slots the
-- repair vendor totals.
local DURABILITY_SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 16, 17, 18 }

local function durabilityPercent()
    if not GetInventoryItemDurability then
        return nil
    end
    local current, maximum = 0, 0
    for _, slot in ipairs(DURABILITY_SLOTS) do
        local ok, cur, max = pcall(GetInventoryItemDurability, slot)
        if ok and cur and max and max > 0 then
            current = current + cur
            maximum = maximum + max
        end
    end
    if maximum == 0 then
        return nil
    end
    return math.floor(current / maximum * 100)
end

local function specName()
    if not GetTalentTabInfo then
        return nil
    end
    local bestName, bestPoints = nil, -1
    for tab = 1, 3 do
        local ok, name, _, points = pcall(GetTalentTabInfo, tab)
        if ok and name and points and points > bestPoints then
            bestName, bestPoints = name, points
        end
    end
    return bestName
end

-- Reads this client's own state. The only place weapon enchant, durability
-- and spec can ever be learned from, which is why they are self-reported.
function RC:GatherSelf()
    local state = RC.Classify(RC.AuraNames("player"))
    state.version = MFD.VERSION
    state.durability = durabilityPercent()
    state.spec = specName()

    if GetWeaponEnchantInfo then
        local ok, hasMainHand = pcall(GetWeaponEnchantInfo)
        if ok then
            state.weapon = hasMainHand and true or false
        end
    end

    -- Flatten names to flags for the wire; a receiver in range has the names
    -- from its own scan, and names for twenty five people do not fit.
    state.food = state.food ~= nil
    state.flask = state.flask ~= nil
    state.battle = state.battle ~= nil
    state.guardian = state.guardian ~= nil
    return state
end

local isReportPending = false

-- Sends a self-report, debounced so a mass rebuff produces one message per
-- client rather than one per buff. Nothing is sent when solo.
function RC:SendReport()
    if isReportPending then
        return
    end
    isReportPending = true
    C_Timer.After(RC.REPORT_DEBOUNCE_SECONDS, function()
        isReportPending = false
        if not ((IsInRaid and IsInRaid()) or (IsInGroup and IsInGroup())) then
            return
        end
        MFD.Comms:Send("PC", RC.EncodeReport(RC:GatherSelf()))
    end)
end

-- Called by Comms when a PC message arrives.
function RC:ReceiveReport(sender, fields)
    local state = RC.DecodeReport(fields)
    if not state then
        return
    end
    RC.reports[sender] = { state = state, at = GetTime() }
    if RC.OnDataChanged then
        RC.OnDataChanged()
    end
end

-- One entry per group member, { [name] = { name, class, unit, row, missing,
-- scannedAt } }, rebuilt by Scan and patched by ScanUnit.
RC.rows = {}
RC.providers = {}

-- Returns the unit tokens for everyone in the group, self included.
local function groupUnits()
    local units = {}
    if IsInRaid and IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            units[#units + 1] = "raid" .. i
        end
        return units
    end
    units[1] = "player"
    if IsInGroup and IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do
            units[#units + 1] = "party" .. i
        end
    end
    return units
end

local function expectedConsumables()
    return MFD.db.settings.raidCheck.expected
end

-- Rebuilds one player's row from a live unit token. Providers must already
-- be current; Scan sets them, and a single-unit rescan reuses them.
function RC:ScanUnit(unit)
    local name = UnitName(unit)
    if not name or name == "" then
        return
    end
    local _, class = UnitClass(unit)
    local scanned = RC.Classify(RC.AuraNames(unit))
    local reported = RC.reports[name] and RC.reports[name].state or nil
    local row = RC.MergeRow(scanned, reported)
    RC.rows[name] = {
        name = name,
        class = class,
        unit = unit,
        row = row,
        missing = RC.Missing(row.state, RC.providers, expectedConsumables()),
        scannedAt = GetTime(),
    }
end

-- Rebuilds every row. Providers first, because Missing depends on them.
function RC:Scan()
    RC.providers = RC.Providers(MFD.Marker.CurrentRoster())
    wipe(RC.rows)
    for _, unit in ipairs(groupUnits()) do
        RC:ScanUnit(unit)
    end
    if RC.OnDataChanged then
        RC.OnDataChanged()
    end
end

-- Returns the rows as an array sorted by name, so every surface lists people
-- in the same order.
function RC:SortedRows()
    local list = {}
    for _, entry in pairs(RC.rows) do
        list[#list + 1] = entry
    end
    table.sort(list, function(a, b)
        return a.name < b.name
    end)
    return list
end

local heartbeat = 0

MFD.RegisterInit(function()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("UNIT_INVENTORY_CHANGED")
    frame:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("UNIT_AURA")

    frame:SetScript("OnEvent", function(_, event, unit)
        if (event == "UNIT_INVENTORY_CHANGED" or event == "UNIT_AURA") and unit ~= "player" then
            return
        end
        RC:SendReport()
    end)

    frame:SetScript("OnUpdate", function(_, elapsed)
        heartbeat = heartbeat + elapsed
        if heartbeat >= RC.REPORT_HEARTBEAT_SECONDS then
            heartbeat = 0
            RC:SendReport()
        end
    end)
end)

_G.MarkedForDeath = MFD
