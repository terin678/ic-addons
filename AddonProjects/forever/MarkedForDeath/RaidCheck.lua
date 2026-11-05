local addonName, ns = ...

--[[
RaidCheck: asks auras per member out of combat, ready check, durability.
Owned by lane C (raid check). Frame module: calls the client only inside the functions
below, run from a /mfd command, an event this file listens to, or the ns.OnReady hook,
which returns early on IC_HEADLESS. Every decision is in RaidCheckModel.

Reads, all confirmed on this client (Docs/client-reference.md):
    C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")   full tables out of combat; throws
                                                           in combat, so every call is pcall'd
    C_Secrets.ShouldAurasBeSecret()                       the gate: false out of combat
    InCombatLockdown(), LibICRestrict                    the lock, about 3 s after the pull
    GetInventoryItemDurability(slot)                      the player's own durability
    LibICGroup                                           who is here, their class and rank
DoReadyCheck is called guarded (/mfd readycheck); a client without it says so.

The snapshot. A read is taken on a ready check, on demand, and while the grid is open
whenever a buff or the roster changes. At PLAYER_REGEN_DISABLED one more read is taken,
because the lock starts about three seconds later; that snapshot is what the grid shows
through the pull, marked with its age. In combat nothing is read and nothing is thrown away.

For other lanes:
    RaidCheck.Scan(reason)            read now; returns ok, why
    RaidCheck.Snapshot()              the last snapshot (nil before the first)
    RaidCheck.OnChange(key, fn)       fn(snapshot) after every read; fn nil to stop
    RaidCheck.Live(key, on)           keep the live events while any key wants them

Other members' durability and versions come from lane F's Comms (ns.Comms.Durability and
ns.Comms.Versions, keyed by player name), read guarded: before Comms exists those cells
are grey. Comms tells the check when either changes (ns.Comms.Listen).
]]

ns.RaidCheck = ns.RaidCheck or {}
local RC = ns.RaidCheck
local Model = ns.RaidCheckModel
local Auras = ns.Auras

local Restrict = LibStub("LibICRestrict-1.0")
local Group = LibStub("LibICGroup-1.0")

local KEY = "raidcheck"            -- this module's key on the shared event frame
local MAX_AURAS = 40               -- helpful aura slots read per member
local SETTLE = 0.5                 -- seconds: a burst of UNIT_AURA reads once
local READY_LIVE = 120             -- seconds the live events stay on after a ready check
local CALLOUT_GAP = 10             -- seconds between two callouts

local Readable = Restrict.Readable

local snapshot
local listeners = {}
local wanted = {}                  -- [key] = true while something wants live events
local isLive = false
local pending = false
local lastCalloutAt = -CALLOUT_GAP

-- A client function, called guarded: nil when it is missing or throws.
local function Ask(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
    if not ok then return nil end
    return a, b, c, d, e, f, g, h
end

local function Settings()
    local check = ns.db and ns.db.check or {}
    return check
end

--------------------------------------------------------------------------------
-- Reads
--------------------------------------------------------------------------------

-- What MayRead needs, from the client now.
local function Facts()
    local secrets = C_Secrets
    local aurasSecret = false
    if secrets then aurasSecret = Readable(Ask(secrets.ShouldAurasBeSecret)) end
    return {
        lockdown = Ask(InCombatLockdown) == true,
        combat = Restrict.Active("Combat") == true,
        aurasSecret = aurasSecret,
    }
end

-- One member's helpful auras as { id, name, icon } (secret = true when the id is hidden),
-- or nil when nothing could be read.
local function ReadUnit(unit)
    local api = C_UnitAuras
    if not api or type(unit) ~= "string" then return nil end
    local list = {}
    for i = 1, MAX_AURAS do
        local ok, data = pcall(api.GetAuraDataByIndex, unit, i, "HELPFUL")
        -- A throw is the client hiding auras: everything so far is not the whole answer.
        if not ok then return nil end
        if type(data) ~= "table" then break end
        local id = Readable(data.spellId)
        if type(id) == "number" then
            list[#list + 1] = { id = id, name = Readable(data.name), icon = Readable(data.icon) }
        else
            list[#list + 1] = { secret = true }
        end
    end
    return list
end

local function OwnDurability()
    local slots = {}
    for _, slot in ipairs(Model.DURABILITY_SLOTS) do
        local cur, max = Ask(GetInventoryItemDurability, slot)
        slots[#slots + 1] = { cur = Readable(cur), max = Readable(max) }
    end
    return Model.Durability(slots)
end

-- A table from lane F's Comms (Durability or Versions), or an empty one while it is not
-- there or fails.
local function FromComms(name)
    local comms = ns.Comms
    local fn = comms and comms[name]
    if type(fn) ~= "function" then return {} end
    local ok, t = pcall(fn)
    return ok and type(t) == "table" and t or {}
end

-- One member's entry in a Comms table, by the name the client gives senders ("First
-- Second" on Forever), then by the first name alone.
local function Heard(t, m)
    return t[m.display or ""] or t[m.name or ""]
end

local function Notify()
    for _, fn in pairs(listeners) do
        local ok, err = pcall(fn, snapshot)
        if not ok then ns.Debug("raid check listener failed: " .. tostring(err)) end
    end
end

--[[
Reads every member's auras now and rebuilds the snapshot. Returns true, or false and why
(in combat, auras hidden, the saved settings not in hand). A refusal keeps the last
snapshot and notes why on it, so the grid can say "held: in combat".
]]
function RC.Scan(reason)
    if not ns.db then return false, "the saved settings are not in hand yet" end
    local ok, why = Model.MayRead(Facts())
    if not ok then
        if snapshot then snapshot.held = why end
        Notify()
        return false, why
    end

    local roster = Group.Now()
    local members = roster.members or {}
    local durability, versions = FromComms("Durability"), FromComms("Versions")
    local states, extras = {}, {}
    for _, m in ipairs(members) do
        local key = m.guid or m.name
        if key then
            local auras = nil
            if m.online ~= false and m.unit then auras = ReadUnit(m.unit) end
            states[key] = Model.Classify(auras, Auras.Lookup(), Auras)
            local extra = {}
            local dur = Heard(durability, m)
            if dur then extra.durability, extra.broken = dur.percent, dur.broken end
            local ver = Heard(versions, m)
            if ver then extra.version = ver.version end
            if m.isMe then
                extra.version = ns.VERSION
                extra.durability, extra.broken = OwnDurability()
            end
            extras[key] = extra
        end
    end

    local check = Settings()
    local ctx = {
        columns = Model.Columns(check.columns),
        data = Auras,
        minDurability = check.minDurability,
        myVersion = ns.VERSION,
    }
    ctx.providers = Model.Providers(members, states, Auras)
    snapshot = {
        at = time(),
        reason = reason or "scan",
        roster = roster,
        states = states,
        ctx = ctx,
        rows = Model.Rows(members, states, extras, ctx),
    }
    Notify()
    return true
end

function RC.Snapshot()
    return snapshot
end

function RC.OnChange(key, fn)
    listeners[key] = fn
end


--------------------------------------------------------------------------------
-- Live events
--------------------------------------------------------------------------------

local function Settle()
    pending = false
    RC.Scan("change")
end

-- A burst of events (a raid-wide buff lands on forty people) reads once.
local function Soon()
    if pending then return end
    pending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(SETTLE, Settle)
    else
        Settle()
    end
end

local function OnAura(_, unit)
    if type(unit) ~= "string" or Restrict.IsSecret(unit) then return end
    if unit == "player" or unit:find("^raid%d") or unit:find("^party%d") then Soon() end
end

local function OnPull()
    -- The last read before the lock: what the grid keeps through the pull.
    RC.Scan("pull")
end

local function SetLive(on)
    if on == isLive then return end
    isLive = on
    if on then
        ns.Events.On("UNIT_AURA", KEY, OnAura)
        ns.Events.On("GROUP_ROSTER_UPDATE", KEY, Soon)
        ns.Events.On("PLAYER_REGEN_DISABLED", KEY, OnPull)
        ns.Events.On("PLAYER_REGEN_ENABLED", KEY, Soon)
    else
        ns.Events.Off("UNIT_AURA", KEY)
        ns.Events.Off("GROUP_ROSTER_UPDATE", KEY)
        ns.Events.Off("PLAYER_REGEN_DISABLED", KEY)
        ns.Events.Off("PLAYER_REGEN_ENABLED", KEY)
    end
end

-- Live events run while any key wants them (the grid shown, the board shown, the minutes
-- after a ready check) and stop when none does, so a closed check costs nothing.
function RC.Live(key, on)
    wanted[key] = on and true or nil
    SetLive(next(wanted) ~= nil)
end

local readyToken = 0

local function OnReadyCheck()
    RC.Scan("ready check")
    RC.Live("ready", true)
    readyToken = readyToken + 1
    local token = readyToken
    if C_Timer and C_Timer.After then
        C_Timer.After(READY_LIVE, function()
            if token == readyToken then RC.Live("ready", false) end
        end)
    end
    if Model.ShouldAutoOpen(snapshot and snapshot.roster or Group.Now(), Settings()) then
        local ui = ns.RaidCheckUI
        if ui and ui.ShowGrid then ui.ShowGrid() end
    end
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local function ScanOrSay()
    local ok, why = RC.Scan("command")
    if not ok then
        if snapshot then
            ns.Printf("not read again (%s); showing the read from %ds ago.", why, time() - snapshot.at)
        else
            ns.Printf("|cffff4444nothing read:|r %s.", why)
        end
    end
    return snapshot
end

local function UICall(name)
    local ui = ns.RaidCheckUI
    if ui and ui[name] then
        ui[name]()
        return true
    end
    ns.Print("the raid check window is not available.")
    return false
end

local function Missing()
    local snap = ScanOrSay()
    if not snap then return end
    local anyone, unknown = false, 0
    for _, row in ipairs(snap.rows) do
        local line = Model.MissingLine(row)
        if line then
            anyone = true
            ns.Printf("%s: %s", row.name, line)
        end
        if row.unknown > 0 then unknown = unknown + 1 end
    end
    if not anyone then ns.Print("everyone has everything the group can give.") end
    if unknown > 0 then
        ns.Printf("|cff999999%d %s could not be read in full (out of sight, offline or hidden).|r",
            unknown, unknown == 1 and "member" or "members")
    end
end

local function Callout()
    local now = Ask(GetTime) or 0
    if now - lastCalloutAt < CALLOUT_GAP then
        ns.Printf("a callout went %ds ago; wait a few seconds.", math.floor(now - lastCalloutAt))
        return
    end
    local snap = ScanOrSay()
    if not snap then return end
    local lines = Model.Callout(snap.rows)
    if #lines == 0 then
        ns.Print("nothing to call out.")
        return
    end
    -- Lane D's chat path: the announce channel, Raid Lead only, refused (never held) in a
    -- chat lockdown, and written to the log either way.
    local say = ns.DeathWatch and ns.DeathWatch.SayLines
    if type(say) ~= "function" then
        ns.Print("|cffff4444callout not sent:|r the chat path is not loaded.")
        return
    end
    for i, line in ipairs(lines) do lines[i] = "[MFD] " .. line end
    local ok, plan = pcall(say, lines, "callout")
    if not ok then
        ns.Printf("|cffff4444callout not sent:|r %s", tostring(plan))
    elseif type(plan) == "table" and plan.action ~= "send" then
        ns.Printf("|cffff4444callout not sent:|r %s.", tostring(plan.reason))
    else
        lastCalloutAt = now
    end
end

local function OwnAuras()
    local ok, why = Model.MayRead(Facts())
    if not ok then
        ns.Printf("|cffff4444your auras cannot be read now:|r %s.", why)
        return
    end
    local auras = ReadUnit("player")
    local state = Model.Classify(auras, Auras.Lookup(), Auras)
    if not state.readable then
        ns.Printf("nothing read: %s.", tostring(state.why))
        return
    end
    local lookup = Auras.Lookup()
    local parts = {}
    for _, a in ipairs(auras) do
        if a.secret then
            parts[#parts + 1] = "|cff999999(hidden)|r"
        else
            local e = lookup[a.id]
            local tag = e and e.what or "-"
            parts[#parts + 1] = string.format("%s %d [%s]", tostring(a.name or "?"), a.id, tag)
        end
    end
    ns.Printf("%d buffs on you: %s", #auras, table.concat(parts, ", "))
    local buffs = {}
    for _, b in ipairs(Auras.BUFFS) do
        if state.buffs[b.key] then buffs[#buffs + 1] = b.label end
    end
    local elixirs = {}
    for _, e in ipairs(state.elixirs) do elixirs[#elixirs + 1] = e.name end
    ns.Printf("buffs: %s; flask: %s; elixirs: %s; food: %s",
        #buffs > 0 and table.concat(buffs, " ") or "none", tostring(state.flask or "none"),
        #elixirs > 0 and table.concat(elixirs, ", ") or "none", tostring(state.food or "none"))
    local unlisted = Model.Unlisted({ state })
    if snapshot then unlisted = Model.Unlisted(snapshot.states) end
    if #unlisted > 0 then
        ns.Printf("|cffffcc66matched by name only|r (their ids belong in Data_Auras): %s",
            table.concat(unlisted, ", "))
    end
end

local function ReadyCheck()
    local roster = Group.Now()
    if roster.kind == "solo" then
        ns.Print("|cffff4444not in a group.|r")
        return
    end
    local rank = roster.me and roster.me.rank
    if rank ~= "leader" and rank ~= "assist" and not roster.everyoneAssist then
        ns.Print("|cffff4444a ready check needs the group's leader or an assistant.|r")
        return
    end
    if type(DoReadyCheck) ~= "function" then
        ns.Print("|cffff4444this client has no ready check call.|r")
        return
    end
    local ok, err = pcall(DoReadyCheck)
    if not ok then ns.Printf("|cffff4444the ready check did not start:|r %s", tostring(err)) end
end

local SUB = {
    [""] = function() UICall("ToggleGrid") end,
    missing = Missing,
    callout = Callout,
    auras = OwnAuras,
    board = function() UICall("ToggleBoard") end,
    ready = ReadyCheck,
}

local function Command(rest)
    if not ns.db then
        ns.Print("the saved settings are not in hand yet.")
        return
    end
    local word = ((rest or ""):match("^%s*(%S*)") or ""):lower()
    local fn = SUB[word]
    if fn then
        fn()
        return
    end
    ns.Print("/mfd check: the grid. /mfd check missing|callout|auras|board|ready")
end

-- Exposed for the window's toolbar.
RC.Missing, RC.Callout, RC.ReadyCheck = Missing, Callout, ReadyCheck

ns.AddCommand("check", "the raid buff and consumable grid; missing, callout, auras, board, ready",
    Command, "check [missing|callout|auras|board|ready]")

ns.OnReady("raidcheck", function()
    if IC_HEADLESS then return end
    ns.Events.On("READY_CHECK", KEY, OnReadyCheck)
    local comms = ns.Comms
    if comms and type(comms.Listen) == "function" then
        pcall(comms.Listen, KEY, function(kind)
            if (kind == "durability" or kind == "peers") and next(wanted) ~= nil then Soon() end
        end)
    end
end)
