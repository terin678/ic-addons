local addonName, ns = ...

--[[
DeathWatch: the frame half of death calls and the pre-pull announce. It reads the client,
asks Deaths.Decide or Announce.Decide, and acts on the plan; every decision is in those
two pure modules.

Owned by lane D (deaths and chat). Spec section 6.

    DeathWatch.Sync()               register the death events while a setting asks for them,
                                    drop them otherwise; call after any deaths setting change
    DeathWatch.Announce()           the pre-pull announce (button and /mfd announce)
    DeathWatch.SayLines(lines, kind) send lines now through the same path, refused (never held)
                                    in a chat lockdown; for the raid check callout
    DeathWatch.Alert(text)          the local alert and sound, as a death call shows it
    DeathWatch.Fight()              the fight now, for the deaths tab

Sources of a death, in order (6.1): UNIT_DIED(guid) mapped to a group member through the
roster taken out of combat; else UnitIsDeadOrGhost on UNIT_HEALTH and UNIT_FLAGS for group
units, edge-triggered. UnitHealth is never read, and COMBAT_LOG_EVENT_UNFILTERED is never
registered (the client forbids it on Forever).

Calls run in IC_HEADLESS only as far as the pure modules; the ready hook returns early.
]]

ns.DeathWatch = ns.DeathWatch or {}
local DeathWatch = ns.DeathWatch

local Restrict = LibStub("LibICRestrict-1.0")
local Group = LibStub("LibICGroup-1.0")
local Chat = LibStub("LibICChat-1.0")
local Deaths = ns.Deaths
local Announce = ns.Announce

local KEY = "deathwatch"

-- Events registered while a death setting asks for them. ENCOUNTER_START names the boss;
-- the rest are deaths and the fight's edges.
local EVENTS = {
    "UNIT_DIED", "UNIT_HEALTH", "UNIT_FLAGS",
    "ENCOUNTER_START", "ENCOUNTER_END",
    "PLAYER_REGEN_DISABLED", "GROUP_ROSTER_UPDATE",
}

local listening = false
local sender                -- the LibICChat sender, made at the first line
local roster = { kind = "solo", members = {}, byGuid = {} }
local byUnit = {}           -- unit token -> guid, from the roster
local dead = {}             -- guid -> last plain UnitIsDeadOrGhost answer
local called = {}           -- guid -> true, called this fight
local fight                 -- Deaths.Fight's answer while an encounter runs, else nil

local function Settings()
    return ns.db and ns.db.settings or nil
end

local function Log(kind, text)
    if ns.Log and ns.Log.Write then ns.Log.Write(kind, text, "deaths") end
end

local function Answer(ok, ...)
    if not ok then return nil end
    return ...
end

-- fn(...) under pcall, the first return made plain (nil when secret or missing).
local function Ask(fn, ...)
    if type(fn) ~= "function" then return nil end
    return Restrict.Readable((Answer(pcall(fn, ...))))
end

local function Sender()
    if not sender then
        sender = Chat.New({
            onDrop = function(entry, reason)
                Log("held", "death line dropped (" .. tostring(reason) .. "): " .. tostring(entry.line.text))
            end,
        })
    end
    return sender
end

--------------------------------------------------------------------------------
-- Roster and fight
--------------------------------------------------------------------------------

-- A fresh roster, out of combat only: in combat the last one stands (6.1: who is a tank
-- or healer is fixed at the pull).
local function ReadRoster()
    if Restrict.InCombat() then return end
    local ok, snapshot = pcall(Group.Now)
    if not ok or type(snapshot) ~= "table" then return end
    roster = snapshot
    byUnit = {}
    for _, m in ipairs(roster.members or {}) do
        if m.unit and m.guid then
            byUnit[m.unit] = m.guid
            if m.isMe then byUnit.player = m.guid end
            if m.dead ~= nil then dead[m.guid] = m.dead end
        end
    end
end

local function IsLead()
    local lead = ns.Lead
    if type(lead) == "table" and type(lead.IsMe) == "function" then
        local ok, answer = pcall(lead.IsMe)
        if ok and type(answer) == "boolean" then return answer end
    end
    local s = Settings()
    return Deaths.FallbackLead(s and s.raidLead, roster)
end

-- A new fight: everybody may be called again.
local function NewFight()
    called = {}
end

function DeathWatch.Fight()
    return fight
end

--------------------------------------------------------------------------------
-- Acting
--------------------------------------------------------------------------------

-- The client's raid warning frame and the raid warning sound. Shows in and out of combat
-- in the open world (probe P16); in an encounter it is still pending.
function DeathWatch.Alert(text)
    if type(RaidNotice_AddMessage) == "function" and RaidWarningFrame then
        local info = type(ChatTypeInfo) == "table" and ChatTypeInfo.RAID_WARNING or nil
        pcall(RaidNotice_AddMessage, RaidWarningFrame, text, info)
    end
    local s = Settings()
    if s and s.sound ~= false and type(PlaySound) == "function" and type(SOUNDKIT) == "table"
        and SOUNDKIT.RAID_WARNING then
        pcall(PlaySound, SOUNDKIT.RAID_WARNING, "Master")
    end
end

local function Act(plan)
    if plan.action == "skip" then
        if plan.counts then Log("held", "death not called: " .. tostring(plan.reason)) end
        return
    end
    Deaths.Record(called, plan)
    local s = Settings()
    if plan.action == "say" or plan.action == "queue" then
        local ttl = s and s.chat and s.chat.deathTTL
        local said = Sender():Say(Deaths.Line(plan, ttl))
        if said.action == "refuse" then
            Log("held", "death line not sent (" .. tostring(said.reason) .. "): " .. plan.text)
        elseif said.action == "queue" then
            Log("death", "death call held until chat unlocks: " .. plan.text)
        else
            Log("death", "death called on " .. tostring(said.channel) .. ": " .. plan.text)
        end
    else
        Log("death", "death shown here only (" .. tostring(plan.reason) .. "): " .. plan.text)
    end
    if plan.alert then DeathWatch.Alert(plan.text) end
end

local function OnDeath(guid)
    local s = Settings()
    if not s then return end
    local plan = Deaths.Decide({ guid = guid }, {
        enabled = s.enabled,
        isLead = IsLead(),
        deaths = ns.db.deaths,
        roster = roster,
        fight = fight,
        called = called,
        chatLocked = Restrict.ChatLocked(),
        group = roster.kind,
    })
    Act(plan)
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local function OnEvent(event, ...)
    if event == "UNIT_DIED" then
        local guid = Restrict.Readable((...))
        if type(guid) ~= "string" or not roster.byGuid[guid] then return end
        dead[guid] = true
        OnDeath(guid)
    elseif event == "UNIT_HEALTH" or event == "UNIT_FLAGS" then
        local unit = Restrict.Readable((...))
        local guid = type(unit) == "string" and byUnit[unit] or nil
        if not guid then return end
        local isDead = Ask(UnitIsDeadOrGhost, unit)
        if type(isDead) ~= "boolean" then return end
        local was = dead[guid]
        dead[guid] = isDead
        if Deaths.Edge(was, isDead) then OnDeath(guid) end
    elseif event == "ENCOUNTER_START" then
        local id, name = ...
        local lookup = ns.Instances and ns.Instances.Encounter
        fight = Deaths.Fight(Restrict.Readable(id), Restrict.Readable(name), lookup)
        NewFight()
    elseif event == "ENCOUNTER_END" then
        fight = nil
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- The pull. Not cleared when combat ends: the Raid Lead dying drops their combat
        -- while the fight goes on, and clearing there would call somebody twice.
        NewFight()
        ReadRoster()
        if Ask(IsEncounterInProgress) == false then fight = nil end
    elseif event == "GROUP_ROSTER_UPDATE" then
        ReadRoster()
    end
end

-- Whether any death setting asks for the events.
function DeathWatch.Needed()
    local s = Settings()
    if not s or s.enabled == false or not ns.db.deaths then return false end
    for _, kind in ipairs(Deaths.KINDS) do
        local cfg = ns.db.deaths[kind]
        if type(cfg) == "table" and cfg.on == true and cfg.override ~= "off" then return true end
    end
    return false
end

function DeathWatch.Sync()
    if IC_HEADLESS then return end
    local want = DeathWatch.Needed()
    if want == listening then return end
    listening = want
    for _, event in ipairs(EVENTS) do
        if want then ns.Events.On(event, KEY, OnEvent) else ns.Events.Off(event, KEY) end
    end
    if want then ReadRoster() end
end

--------------------------------------------------------------------------------
-- Announce and callouts
--------------------------------------------------------------------------------

-- Sends lines now on the announce channel, or refuses. kind: "prepull" or "callout".
-- Returns the Announce plan (action "send" or "refuse", reason).
function DeathWatch.SayLines(lines, kind)
    local s = Settings()
    if not s then return { action = "refuse", reason = "the saved settings are not in hand yet" } end
    ReadRoster()
    local plan = Announce.Decide(lines, {
        kind = kind, prepull = s.announce and s.announce.prepull, isLead = IsLead(),
        chatLocked = Restrict.ChatLocked(), group = roster.kind,
    })
    if plan.action ~= "send" then
        Log("held", (kind or "prepull") .. " not sent: " .. tostring(plan.reason))
        return plan
    end
    local channels = Announce.Channels(s.announce and s.announce.channel)
    for _, text in ipairs(plan.lines) do
        local said = Sender():Say({ text = text, channels = channels, whenLocked = "refuse", pressed = true })
        if said.action ~= "send" then
            plan.action, plan.reason = "refuse", said.reason
            Log("held", (kind or "prepull") .. " stopped: " .. tostring(said.reason))
            return plan
        end
        Log("say", tostring(said.channel) .. ": " .. text)
    end
    return plan
end

-- The pre-pull announce: the seat plan this instance follows, owners from the roster.
function DeathWatch.Announce()
    ReadRoster()
    local instanceID = Ask(function() return select(8, GetInstanceInfo()) end)
    local key = ns.Instances and ns.Instances.Key(instanceID) or "open"
    local seatPlan = ns.Seats.PlanFor(ns.db, key)
    local lines = Announce.Lines(ns.Seats.Resolve(seatPlan, roster.members))
    return DeathWatch.SayLines(lines, "prepull")
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

ns.AddCommand("deaths", "tank and healer death calls: status, test, or tank|healer on|off|auto",
    function(rest)
        if not ns.db then
            ns.Print("the saved settings are not in hand yet.")
            return
        end
        local cmd = Deaths.Command(rest)
        if cmd.action == "refuse" then
            ns.Print(cmd.why .. ".")
            return
        elseif cmd.action == "test" then
            DeathWatch.Alert("Tank Example has died")
            ns.Print("that is how a death call shows on your screen. Raid chat was not told.")
            return
        elseif cmd.action == "set" then
            local cfg = ns.db.deaths[cmd.kind]
            if cmd.value == "auto" then
                cfg.override = "auto"
            else
                cfg.on = true
                cfg.override = cmd.value
            end
            DeathWatch.Sync()
            if ns.UIDeaths and ns.UIDeaths.Refresh then ns.UIDeaths.Refresh() end
        end
        for _, line in ipairs(Deaths.StatusLines(ns.db.deaths)) do ns.Print(line) end
    end, "deaths [test|tank|healer on|off|auto]")

ns.AddCommand("announce", "post the seat plan to the group now; on or off allows or stops it",
    function(rest)
        local s = Settings()
        if not s then
            ns.Print("the saved settings are not in hand yet.")
            return
        end
        local cmd = Announce.Command(rest)
        if cmd.action == "refuse" then
            ns.Print(cmd.why .. ".")
        elseif cmd.action == "set" then
            s.announce.prepull = cmd.value
            ns.Print(cmd.value and "announce is on." or "announce is off: the Announce button and "
                .. "/mfd announce stay quiet until /mfd announce on.")
            if ns.UIDeaths and ns.UIDeaths.Refresh then ns.UIDeaths.Refresh() end
        else
            local plan = DeathWatch.Announce()
            if plan.action ~= "send" then ns.Print("nothing announced: " .. tostring(plan.reason) .. ".") end
        end
    end, "announce [on|off]")

ns.OnReady("deathwatch", function()
    if IC_HEADLESS then return end
    DeathWatch.Sync()
end)
