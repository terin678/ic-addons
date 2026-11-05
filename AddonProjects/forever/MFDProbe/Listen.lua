local addonName, ns = ...

--[[
Listen: a window in which the probe hears events, and the only place it registers any
besides the commands' own two.

Nothing is registered outside a window, so the addon costs nothing while idle. A window
belongs to one run: whether each event could be registered is a row in that run, and every
event heard is counted into run.events with its first few payloads described. Secret
payloads are recognised before they are touched.

    Listen.Ensure(run, seconds)   open a window for run, or keep the open one going longer
    Listen.Stop()                 close it now
    Listen.On(event, fn)          a check's own handler, fn(event, ...), while windows open
    Listen.Off(event, fn)
    Listen.IsOpen()
]]

local Listen = {}
ns.Listen = Listen

-- What is asked for. A name the client does not know fails to register, and that failure
-- is a finding: the event does not exist here.
Listen.EVENTS = {
    -- COMBAT_LOG_EVENT_UNFILTERED is not asked for: registering it is forbidden here and
    -- opens the blocked-action dialog (client-reference.md).
    "UNIT_DIED", "UNIT_DESTROYED", "PARTY_KILL", "UNIT_FLAGS", "UNIT_HEALTH", "UNIT_AURA",
    "PLAYER_DEAD", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "RAID_TARGET_UPDATE",
    "ENCOUNTER_START", "ENCOUNTER_END", "BOSS_KILL", "INSTANCE_ENCOUNTER_ENGAGE_UNIT",
    "READY_CHECK", "READY_CHECK_CONFIRM", "READY_CHECK_FINISHED",
    "INSPECT_READY", "CHAT_MSG_ADDON", "CHAT_MSG_SYSTEM",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_RAID_WARNING", "CHAT_MSG_SAY", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "ADDON_RESTRICTION_STATE_CHANGED", "DAMAGE_METER_COMBAT_SESSION_UPDATED", "DAMAGE_METER_CURRENT_SESSION_UPDATED",
    "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED",
}

-- Payloads kept per event, and arguments described per payload.
local SAMPLES = 3
local ARGS = 8
-- The longest window anyone may ask for, in seconds.
Listen.MAX_SECONDS = 900

-- Combat log subevents whose whole payload is worth keeping: deaths, and the aura
-- applications crowd control shows up as.
local CLEU_KEEP = { UNIT_DIED = true, UNIT_DESTROYED = true, PARTY_KILL = true, SPELL_AURA_APPLIED = true,
    SPELL_AURA_REMOVED = true, SPELL_CAST_SUCCESS = true }

-- Events whose first argument is a unit: the unit is asked about inside the handler too.
local UNIT_EVENTS = { UNIT_FLAGS = true, UNIT_HEALTH = true, UNIT_AURA = true,
    NAME_PLATE_UNIT_REMOVED = true, NAME_PLATE_UNIT_ADDED = true }

-- Events whose payloads are the finding, so more of them are kept.
local SAMPLES_FOR = { ADDON_RESTRICTION_STATE_CHANGED = 20, ENCOUNTER_START = 10, ENCOUNTER_END = 10,
    BOSS_KILL = 5, UNIT_DIED = 10, UNIT_DESTROYED = 5, PARTY_KILL = 10, INSTANCE_ENCOUNTER_ENGAGE_UNIT = 5 }
-- Deaths written as rows per run; the rest are only counted.
local DEATH_ROWS = 20
-- Rows of that kind kept per event per combat state.
local UNIT_ROWS = 2

local frame
local window          -- { run, deadline, token, registered = { name = true } }
local hooks = {}      -- event -> { fn, ... }
local unitRows = {}   -- "EVENT:combat" -> count, per window

local function IsSecret(v) return ns.IsSecret(v) end

local function Describe(...)
    local n = math.min(select("#", ...), ARGS)
    local parts = {}
    for i = 1, n do
        parts[i] = (ns.Report.Describe((select(i, ...)), ns.IsSecret, ns.IsSecretTable))
    end
    return table.concat(parts, ", ")
end

local function Count(name, ...)
    local run = window and window.run
    if not run then return end
    run.events = run.events or {}
    local entry = run.events[name]
    if not entry then
        entry = { count = 0, samples = {} }
        run.events[name] = entry
    end
    entry.count = entry.count + 1
    if #entry.samples < (SAMPLES_FOR[name] or SAMPLES) then
        entry.samples[#entry.samples + 1] = string.format("%s%s", ns.InCombat() and "[combat] " or "", Describe(...))
    end
end

local function OnCombatLog(event)
    local call = ns.Call(CombatLogGetCurrentEventInfo)
    local run = window.run
    if not call.ok then
        Count(event .. ":info error")
        if not run.cleuErrorSaid then
            run.cleuErrorSaid = true
            ns.AddRow(run, "cleu.CombatLogGetCurrentEventInfo", call)
        end
        return
    end
    local sub = call.values[2]
    local key = IsSecret(sub) and "<secret>" or tostring(sub)
    local name = "CLEU:" .. key
    if CLEU_KEEP[key] or key == "<secret>" then
        Count(name, unpack(call.values, 1, call.n))
    else
        Count(name)
    end
    -- One row per subevent kind and combat state, so the matrix says whether the payload
    -- turns secret in combat.
    run.cleuRows = run.cleuRows or {}
    local rowKey = key .. (ns.InCombat() and ":in" or ":out")
    if not run.cleuRows[rowKey] and (CLEU_KEEP[key] or key == "<secret>" or not next(run.cleuRows)) then
        run.cleuRows[rowKey] = true
        ns.AddRow(run, "cleu.payload." .. key, call)
    end
end

local function OnUnitEvent(event, unit)
    local run = window.run
    local key = event .. (ns.InCombat() and ":in" or ":out")
    if (unitRows[key] or 0) >= UNIT_ROWS then return end
    if IsSecret(unit) or type(unit) ~= "string" then
        unitRows[key] = (unitRows[key] or 0) + 1
        ns.AddRow(run, "evunit." .. event .. ".token", ns.Call(function() return unit end))
        return
    end
    -- A raid member's event says little about a hostile mob; keep both kinds apart.
    local kind = unit:find("^nameplate") and "plate" or (unit:find("^party") or unit:find("^raid")) and "member"
        or (unit == "player" or unit == "target" or unit == "mouseover" or unit == "focus") and unit or "other"
    unitRows[key] = (unitRows[key] or 0) + 1
    ns.AddRow(run, "evunit." .. event .. "." .. kind .. ".UnitIsDead", ns.Call(UnitIsDead, unit))
    ns.AddRow(run, "evunit." .. event .. "." .. kind .. ".UnitGUID", ns.Call(UnitGUID, unit))
    ns.AddRow(run, "evunit." .. event .. "." .. kind .. ".UnitHealth", ns.Call(UnitHealth, unit))
end

-- A death: the GUID it carries, the npc id inside it when plain, and whether a group
-- member with that GUID reads as dead.
local function OnDeath(event, ...)
    local run = window.run
    run.deathRows = (run.deathRows or 0) + 1
    if run.deathRows > DEATH_ROWS then return end
    local guids = event == "PARTY_KILL" and { (select(2, ...)) } or { (...) }
    for _, guid in ipairs(guids) do
        local secret = IsSecret(guid)
        run.rows[#run.rows + 1] = { id = "death." .. event .. ".guid", outcome = secret and "secret" or "ok",
            v = (ns.Report.Describe(guid, IsSecret)), combat = ns.InCombat() }
        if not secret and type(guid) == "string" then
            local npc = ns.Report.NpcId(guid, IsSecret)
            if npc and ns.db and ns.db.capture.npcs[npc] == nil then ns.Collect("npcs", npc, "(seen dying)") end
            for _, unit in ipairs(ns.Checks.Members()) do
                local call = ns.Call(UnitGUID, unit)
                if call.ok and not IsSecret(call.values[1]) and call.values[1] == guid then
                    ns.AddRow(run, "death.member.UnitIsDead", ns.Call(UnitIsDead, unit))
                    ns.AddRow(run, "death.member.UnitIsDeadOrGhost", ns.Call(UnitIsDeadOrGhost, unit))
                end
            end
        end
    end
end

local function OnEncounter(event, encounterId, encounterName)
    if event == "ENCOUNTER_START" then ns.Collect("encounters", encounterId, encounterName) end
end

local function OnEvent(_, event, ...)
    if not window then return end
    if event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED" then
        local who, what = ...
        if who == addonName then
            local run = ns.CurrentRun() or window.run
            run.rows[#run.rows + 1] = { id = "forbidden." .. tostring(what), outcome = "blocked",
                v = event, combat = ns.InCombat() }
        end
    end
    if event == "COMBAT_LOG_EVENT_UNFILTERED" or event == "COMBAT_LOG_EVENT" then
        OnCombatLog(event)
    else
        Count(event, ...)
        if UNIT_EVENTS[event] then OnUnitEvent(event, ...) end
        if event == "UNIT_DIED" or event == "UNIT_DESTROYED" or event == "PARTY_KILL" then OnDeath(event, ...) end
        if event == "ENCOUNTER_START" or event == "ENCOUNTER_END" then OnEncounter(event, ...) end
    end
    local list = hooks[event]
    if list then
        for _, fn in ipairs(list) do
            local ok, err = pcall(fn, event, ...)
            if not ok then ns.Debug("hook for %s failed: %s", event, tostring(err)) end
        end
    end
end

local function Open(run)
    if not frame then
        frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", ns.Wrap("MFDProbe listen", OnEvent))
    end
    unitRows = {}
    window = { run = run, registered = {} }
    for _, name in ipairs(Listen.EVENTS) do
        local call = ns.Call(frame.RegisterEvent, frame, name)
        if call.ok then window.registered[name] = true end
        -- Whether it could be registered is a finding once per run, not per window reopen.
        run.registerSaid = run.registerSaid or {}
        if not run.registerSaid[name] then
            run.registerSaid[name] = true
            ns.AddRow(run, "event." .. name .. ".register", call)
        end
    end
end

function Listen.Stop()
    if not window then return end
    for name in pairs(window.registered) do
        pcall(frame.UnregisterEvent, frame, name)
    end
    window = nil
end

-- Keeps a window open for at least `seconds` more. A window already open stays with the
-- run that opened it; a later run only lengthens it.
function Listen.Ensure(run, seconds)
    seconds = math.min(seconds or 10, Listen.MAX_SECONDS)
    if not window then Open(run) end
    local now = GetTime()
    if window.deadline and window.deadline >= now + seconds then return end
    window.deadline = now + seconds
    local token = {}
    window.token = token
    C_Timer.After(seconds, function()
        if window and window.token == token then Listen.Stop() end
    end)
end

function Listen.IsOpen()
    return window ~= nil
end

function Listen.On(event, fn)
    hooks[event] = hooks[event] or {}
    table.insert(hooks[event], fn)
end

function Listen.Off(event, fn)
    local list = hooks[event]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == fn then table.remove(list, i) end
    end
end
