local addonName, ns = ...

--[[
Deaths: whether and how a tank or healer death is called. Pure: no client call, ever;
every function takes its tables as arguments. DeathWatch.lua is the frame half that reads
the client, asks Decide, and acts on the plan.

Owned by lane D (deaths and chat). Spec section 6.

    Deaths.KINDS                    { "tank", "healer" }, the order every surface lists them
    Deaths.KindsOf(member, deaths)  { tank = true, healer = true } for what member counts as
    Deaths.Wants(kind, cfg, fight)  whether this fight calls deaths of kind, and why not
    Deaths.Fight(encounterID, name, lookup)   the fight an ENCOUNTER_START names
    Deaths.Edge(was, is)            true only for an alive-to-dead change
    Deaths.BossRows(list)           the deaths tab's boss list from Data_Instances
    Deaths.Decide(event, state)     the plan: say | queue | local | skip, with the reason
    Deaths.Record(called, plan)     spend that person's call for the fight
    Deaths.Line(plan, ttl)          the LibICChat line a say or queue plan sends
    Deaths.FallbackLead(raidLead, roster)     whether this client calls, until Lead.lua says

How a death is told apart from a fight: one call per person per fight, cleared when the
next fight starts (PLAYER_REGEN_DISABLED or ENCOUNTER_START), never when it ends, so the
Raid Lead's own death and battle rez do not let somebody be called twice.
]]

ns.Deaths = ns.Deaths or {}
local Deaths = ns.Deaths

Deaths.KINDS = { "tank", "healer" }
Deaths.LABELS = { tank = "Tank", healer = "Healer" }

-- The override every kind carries: "auto" follows the trash box and the per-boss ticks,
-- the other two ignore both in their direction.
Deaths.OVERRIDES = { "auto", "on", "off" }
Deaths.OVERRIDE_LABELS = { auto = "per boss", on = "everywhere", off = "nowhere" }

-- What a boss the player never ticked or unticked means, per kind. Tank deaths have always
-- been called on every boss; healer deaths only where somebody asked. A tick stores true,
-- an untick stores false, so the default never overwrites a choice.
Deaths.BOSS_DEFAULT = { tank = true, healer = false }

-- Channels in the order LibICChat tries them: a raid warning where the client lets this
-- player send one, raid chat in a raid, party chat in a party.
Deaths.CHANNELS = { "RAID_WARNING", "RAID", "PARTY" }

Deaths.DEFAULT_TTL = 10   -- seconds a held death line waits for chat to unlock

local function Lower(s)
    return type(s) == "string" and s:lower() or nil
end

-- Names typed into a kind's extra box, as a list. Accepts a list or a set, and drops
-- anything that is not a name.
function Deaths.ExtraNames(extra)
    local names = {}
    if type(extra) ~= "table" then return names end
    for k, v in pairs(extra) do
        local name = type(k) == "string" and v == true and k or (type(v) == "string" and v or nil)
        if name then
            name = name:match("^%s*(.-)%s*$")
            if name ~= "" then names[#names + 1] = name end
        end
    end
    table.sort(names)
    return names
end

-- Splits typed text on commas, spaces and line breaks into a list of names.
function Deaths.ParseExtra(text)
    local names = {}
    if type(text) ~= "string" then return names end
    for name in text:gmatch("[^,%s]+") do names[#names + 1] = name end
    return names
end

local function Listed(member, extra)
    local name, display = Lower(member.name), Lower(member.display)
    for _, typed in ipairs(Deaths.ExtraNames(extra)) do
        local t = typed:lower()
        if t == name or t == display then return true end
    end
    return false
end

-- member: a LibICGroup snapshot member { name, display, role, mainTank }. deaths: the
-- saved deaths block. A raid marks a tank two ways that do not overlap, the role icon and
-- Main Tank, so either counts (Anniversary read Main Tank alone until 1.27.2 and missed
-- every tank marked by icon). The extra boxes add anyone the roster does not mark.
function Deaths.KindsOf(member, deaths)
    local kinds = {}
    if type(member) ~= "table" then return kinds end
    deaths = deaths or {}
    if member.role == "TANK" or member.mainTank == true or Listed(member, (deaths.tank or {}).extra) then
        kinds.tank = true
    end
    if member.role == "HEALER" or Listed(member, (deaths.healer or {}).extra) then
        kinds.healer = true
    end
    return kinds
end

-- The next override for a one-click toggle: per boss, everywhere, nowhere, per boss.
function Deaths.NextOverride(current)
    if current == "auto" then return "on" end
    if current == "on" then return "off" end
    return "auto"
end

-- Whether a boss is ticked for kind: the saved answer, else the kind's default.
function Deaths.BossTicked(kind, cfg, encounterID)
    local bosses = type(cfg) == "table" and cfg.bosses or nil
    if type(bosses) == "table" and encounterID ~= nil then
        local saved = bosses[encounterID]
        if saved == true or saved == false then return saved end
    end
    return Deaths.BOSS_DEFAULT[kind] == true
end

-- fight: nil or { boss = false } is trash; { boss = true, encounterID } a boss, with
-- encounterID nil when the client hid it ("boss, unknown": the kind's boss default).
-- Returns true, or false and why.
function Deaths.Wants(kind, cfg, fight)
    if type(cfg) ~= "table" or cfg.on ~= true then return false, Deaths.LABELS[kind] .. " calls are off" end
    if cfg.override == "off" then return false, Deaths.LABELS[kind] .. " calls are set to nowhere" end
    if cfg.override == "on" then return true end
    if fight and fight.boss then
        if Deaths.BossTicked(kind, cfg, fight.encounterID) then return true end
        return false, (fight.name or "this boss") .. " is not ticked for " .. kind .. " calls"
    end
    if cfg.trash == true then return true end
    return false, kind .. " calls are off on trash"
end

-- The fight an ENCOUNTER_START names. encounterID and eventName are what the client said,
-- already made plain (nil when secret). lookup(id) -> name is ns.Instances.Encounter; the
-- name from data wins, the event's name is the fallback, "an unknown boss" the last.
function Deaths.Fight(encounterID, eventName, lookup)
    local id = type(encounterID) == "number" and encounterID or nil
    local name = id and lookup and lookup(id) or nil
    if not name and type(eventName) == "string" and eventName ~= "" then name = eventName end
    return { boss = true, encounterID = id, name = name or "an unknown boss" }
end

-- The bosses the deaths tab lists: every encounter in the instance list (Data_Instances'
-- shape: [instanceID] = { name, encounters = { [encounterID] = boss } }), sorted by
-- instance then boss. Returns { { encounterID, boss, instance }, ... }.
function Deaths.BossRows(list)
    local rows = {}
    for instanceID, entry in pairs(list or {}) do
        if type(entry) == "table" and type(entry.encounters) == "table" then
            local instance = entry.name or ("instance " .. tostring(instanceID))
            for encounterID, boss in pairs(entry.encounters) do
                rows[#rows + 1] = { encounterID = encounterID, boss = tostring(boss), instance = instance }
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.instance ~= b.instance then return a.instance < b.instance end
        if a.boss ~= b.boss then return a.boss < b.boss end
        return a.encounterID < b.encounterID
    end)
    return rows
end

-- An alive-to-dead change. A first reading (was nil) is not a death: somebody already
-- dead when the roster was read would otherwise be called at login.
function Deaths.Edge(was, is)
    return was == false and is == true
end

local function Text(kind, name)
    return string.format("%s %s has died", Deaths.LABELS[kind] or "", name)
end

--[[
event = { guid, at }                    who died (the GUID UNIT_DIED or the roster gave)
state = {
    enabled     the addon is on (settings.enabled)
    isLead      this client is the Raid Lead (only it calls)
    deaths      the saved deaths block { tank = cfg, healer = cfg }
    roster      a LibICGroup snapshot taken out of combat (byGuid)
    fight       the fight now (Deaths.Fight's answer), nil on trash
    called      { [guid] = true } already called this fight
    chatLocked  chat is locked here (LibICRestrict's State.chat)
    group       "solo", "party" or "raid" (LibICGroup's kind)
}
Returns plan = { action, reason, kind, guid, name, text, alert, counts }
    counts  the person is a tank or healer (a skip worth logging)
    action  "say"   send now, and alert locally
            "queue" chat is locked: hold the line in LibICChat for its TTL, alert locally
            "local" nobody to tell in chat: the local alert only
            "skip"  nothing, and reason says why (logged, never printed)
]]
function Deaths.Decide(event, state)
    state = state or {}
    local guid = type(event) == "table" and event.guid or nil
    local plan = { action = "skip", guid = guid }
    if state.enabled == false then
        plan.reason = "the addon is off"
        return plan
    end
    local member = guid and state.roster and state.roster.byGuid and state.roster.byGuid[guid]
    if not member then
        plan.reason = "not somebody in the group"
        return plan
    end
    plan.name = member.display or member.name or "Somebody"
    local kinds = Deaths.KindsOf(member, state.deaths)
    if not kinds.tank and not kinds.healer then
        plan.reason = plan.name .. " is not a tank or healer"
        return plan
    end
    plan.counts = true
    local why
    for _, kind in ipairs(Deaths.KINDS) do
        if kinds[kind] then
            local ok, no = Deaths.Wants(kind, (state.deaths or {})[kind], state.fight)
            if ok then
                plan.kind = kind
                break
            end
            why = why or no
        end
    end
    if not plan.kind then
        plan.reason = why
        return plan
    end
    -- Asked after every other gate, so a death filtered out anyway never spends the call.
    if (state.called or {})[guid] then
        plan.reason = plan.name .. " was already called this fight"
        return plan
    end
    if state.isLead ~= true then
        plan.reason = "only the Raid Lead calls deaths"
        return plan
    end
    plan.text = Text(plan.kind, plan.name)
    plan.alert = true
    if state.group ~= "party" and state.group ~= "raid" then
        plan.action, plan.reason = "local", "not in a group"
    elseif state.chatLocked == true then
        plan.action, plan.reason = "queue", "chat is locked here"
    else
        plan.action = "say"
    end
    return plan
end

-- Spends the person's call for this fight once a plan said anything. Mutates called.
function Deaths.Record(called, plan)
    if type(called) ~= "table" or type(plan) ~= "table" or not plan.guid then return end
    if plan.action == "say" or plan.action == "queue" or plan.action == "local" then
        called[plan.guid] = true
    end
end

-- The LibICChat line for a say or queue plan: held through a lock for ttl seconds.
function Deaths.Line(plan, ttl)
    return {
        text = plan.text,
        channels = Deaths.CHANNELS,
        whenLocked = "queue",
        ttl = tonumber(ttl) or Deaths.DEFAULT_TTL,
    }
end

-- Whether this client is the Raid Lead, from the saved setting and a roster, for while
-- Lead.lua has no answer of its own. A named Raid Lead who is in the group wins; else the
-- group's leader; alone or in a party nobody leads, this client.
function Deaths.FallbackLead(raidLead, roster)
    roster = roster or {}
    local me = roster.me
    if type(raidLead) == "string" and raidLead ~= "" then
        for _, m in ipairs(roster.members or {}) do
            if m.name == raidLead or m.display == raidLead then
                return me ~= nil and m == me
            end
        end
    end
    if roster.kind == "solo" then return true end
    if roster.leader then return me ~= nil and roster.leader == me end
    return roster.kind ~= "raid"
end

-- The /mfd deaths command, read: "tank on", "healer auto", "" for the status. Returns
-- { action = "status" | "set" | "refuse", kind, value, why }.
function Deaths.Command(rest)
    local words = {}
    for w in tostring(rest or ""):lower():gmatch("%S+") do words[#words + 1] = w end
    if #words == 0 then return { action = "status" } end
    if words[1] == "test" then return { action = "test" } end
    local kind = words[1]
    if kind ~= "tank" and kind ~= "healer" then
        return { action = "refuse", why = "say /mfd deaths, /mfd deaths test, or /mfd deaths tank|healer on|off|auto" }
    end
    local value = words[2]
    if value ~= "on" and value ~= "off" and value ~= "auto" then
        return { action = "refuse", why = "say /mfd deaths " .. kind .. " on, off or auto" }
    end
    return { action = "set", kind = kind, value = value }
end

-- Status lines for /mfd deaths, one per kind.
function Deaths.StatusLines(deaths)
    local lines = {}
    for _, kind in ipairs(Deaths.KINDS) do
        local cfg = (deaths or {})[kind] or {}
        local where
        if cfg.on ~= true then
            where = "|cffff4444off|r"
        elseif cfg.override == "on" then
            where = "|cff88ff88everywhere|r"
        elseif cfg.override == "off" then
            where = "|cffff4444nowhere|r (override)"
        else
            where = "per boss, trash " .. (cfg.trash == true and "yes" or "no")
        end
        local extra = Deaths.ExtraNames(cfg.extra)
        lines[#lines + 1] = string.format("%s deaths: %s%s", Deaths.LABELS[kind], where,
            #extra > 0 and (", also " .. table.concat(extra, ", ")) or "")
    end
    return lines
end
