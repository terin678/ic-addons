local addonName, ns = ...

--[[
Tests_Deaths: the deaths and chat lane's cases: Deaths, Announce and ChatCue's pure halves.
Owned by lane D (deaths and chat). Every case builds its own tables; none touches the saved
ones or the real globals.
]]

local T = ns.Tests
local Deaths = ns.Deaths
local Announce = ns.Announce
local ChatCue = ns.ChatCue
local Chat = LibStub("LibICChat-1.0")
local Group = LibStub("LibICGroup-1.0")

-- The shipped deaths block: tank on everywhere, healer off.
local function Settings()
    return {
        tank = { on = true, trash = true, override = "auto", extra = {}, bosses = {} },
        healer = { on = false, trash = false, override = "auto", extra = {}, bosses = {} },
    }
end

-- A raid roster: Tankard (tank icon), Shield (Main Tank only), Mender (healer), Stabby
-- (damage), Lead (the player, who leads).
local function Roster()
    return Group.Snapshot({
        inRaid = true, inGroup = true, me = "G-LEAD",
        units = {
            { unit = "raid1", guid = "G-LEAD", name = "Lead", class = "MAGE", leader = true, assist = false },
            { unit = "raid2", guid = "G-TANK", name = "Tankard", class = "WARRIOR", role = "TANK",
                leader = false, assist = false },
            { unit = "raid3", guid = "G-MT", name = "Shield", class = "PALADIN", role = "DAMAGER",
                mainTank = true, leader = false, assist = false },
            { unit = "raid4", guid = "G-HEAL", name = "Mender", class = "PRIEST", role = "HEALER",
                leader = false, assist = false },
            { unit = "raid5", guid = "G-DPS", name = "Stabby", class = "ROGUE", role = "DAMAGER",
                leader = false, assist = false },
        },
    })
end

local function State(overrides)
    local s = { enabled = true, isLead = true, deaths = Settings(), roster = Roster(), called = {},
        chatLocked = false, group = "raid" }
    for k, v in pairs(overrides or {}) do s[k] = v end
    return s
end

local function Death(guid) return { guid = guid } end

--------------------------------------------------------------------------------
-- Who counts
--------------------------------------------------------------------------------

T.Case("Deaths.KindsOf: role icon, Main Tank and the extra boxes", function()
    local r, d = Roster(), Settings()
    T.True(Deaths.KindsOf(r.byGuid["G-TANK"], d).tank, "the tank icon is a tank")
    T.True(Deaths.KindsOf(r.byGuid["G-MT"], d).tank, "Main Tank alone is a tank")
    T.True(Deaths.KindsOf(r.byGuid["G-HEAL"], d).healer, "the healer icon is a healer")
    T.Eq(next(Deaths.KindsOf(r.byGuid["G-DPS"], d)), nil, "damage is neither")
    d.tank.extra = { "stabby" }
    T.True(Deaths.KindsOf(r.byGuid["G-DPS"], d).tank, "a typed name counts, any case")
    d.tank.extra = { Stabby = true }
    T.True(Deaths.KindsOf(r.byGuid["G-DPS"], d).tank, "a set of names counts too")
end)

T.Case("Deaths.ParseExtra and ExtraNames: commas, spaces, empties", function()
    T.Eq(table.concat(Deaths.ParseExtra(" Ann, Bob\nCid,, "), ";"), "Ann;Bob;Cid", "three names")
    T.Eq(#Deaths.ParseExtra(nil), 0, "nothing typed")
    T.Eq(table.concat(Deaths.ExtraNames({ "Bob", " ", "Ann" }), ";"), "Ann;Bob", "sorted, blanks out")
end)

--------------------------------------------------------------------------------
-- Which fight
--------------------------------------------------------------------------------

T.Case("Deaths.Decide: a tank on trash is called", function()
    local plan = Deaths.Decide(Death("G-TANK"), State())
    T.Eq(plan.action, "say", "said")
    T.Eq(plan.kind, "tank", "as a tank")
    T.Eq(plan.text, "Tank Tankard has died", "the line")
    T.True(plan.alert, "and shown locally")
end)

T.Case("Deaths.Decide: a healer is off on trash by default", function()
    local plan = Deaths.Decide(Death("G-HEAL"), State())
    T.Eq(plan.action, "skip", "not called")
    T.True(plan.counts, "but worth logging")
    T.True(plan.reason:find("Healer calls are off", 1, true), "and says why")
    local s = State()
    s.deaths.healer.on = true
    T.Eq(Deaths.Decide(Death("G-HEAL"), s).action, "skip", "on, but trash unticked")
    s.deaths.healer.trash = true
    T.Eq(Deaths.Decide(Death("G-HEAL"), s).action, "say", "trash ticked")
end)

T.Case("Deaths.Decide: per-boss ticks, with each kind's own default", function()
    local s = State({ fight = Deaths.Fight(3303, nil, function() return "Shade of the Archmage" end) })
    T.Eq(Deaths.Decide(Death("G-TANK"), s).action, "say", "an unticked-or-untouched boss calls tanks")
    s.deaths.tank.bosses[3303] = false
    local plan = Deaths.Decide(Death("G-TANK"), s)
    T.Eq(plan.action, "skip", "an unticked boss does not")
    T.True(plan.reason:find("Shade of the Archmage", 1, true), "naming the boss")
    s.deaths.healer.on = true
    T.Eq(Deaths.Decide(Death("G-HEAL"), s).action, "skip", "healers default to unticked")
    s.deaths.healer.bosses[3303] = true
    T.Eq(Deaths.Decide(Death("G-HEAL"), s).action, "say", "a ticked boss calls healers")
    s.deaths.tank.trash = false
    s.fight = nil
    T.Eq(Deaths.Decide(Death("G-TANK"), s).action, "skip", "out of the encounter is trash again")
end)

T.Case("Deaths.Decide: an override wins over the ticks both ways", function()
    local s = State({ fight = Deaths.Fight(3303) })
    s.deaths.tank.bosses[3303] = false
    s.deaths.tank.override = "on"
    T.Eq(Deaths.Decide(Death("G-TANK"), s).action, "say", "on calls an unticked boss")
    s.deaths.tank.override = "off"
    s.fight = nil
    T.Eq(Deaths.Decide(Death("G-TANK"), s).action, "skip", "off silences trash")
    s.deaths.tank.on = false
    s.deaths.tank.override = "on"
    T.Eq(Deaths.Decide(Death("G-TANK"), s).action, "skip", "a kind switched off stays off")
    T.Eq(Deaths.NextOverride("auto"), "on", "auto to on")
    T.Eq(Deaths.NextOverride("on"), "off", "on to off")
    T.Eq(Deaths.NextOverride("off"), "auto", "off back to auto")
end)

T.Case("Deaths.Fight: the id from data, then the event's name, then unknown", function()
    local lookup = function(id) return id == 3303 and "Shade of the Archmage" or nil end
    T.Eq(Deaths.Fight(3303, "Ignored", lookup).name, "Shade of the Archmage", "data wins")
    T.Eq(Deaths.Fight(9999, "Someone", lookup).name, "Someone", "the event's name next")
    local unknown = Deaths.Fight(nil, nil, lookup)
    T.Eq(unknown.encounterID, nil, "a secret id is no id")
    T.Eq(unknown.name, "an unknown boss", "and no name")
    T.True(unknown.boss, "but still a boss")
    local s = State({ fight = unknown })
    T.Eq(Deaths.Decide(Death("G-TANK"), s).action, "say", "an unknown boss takes the tank default")
end)

T.Case("Deaths.BossRows: every encounter, by instance then boss", function()
    local rows = Deaths.BossRows({
        [2999] = { name = "Ruins of Lordaeron", encounters = { [3411] = "Viktor the Vile", [3354] = "Rath'mael" } },
        [2970] = { kind = "unknown", encounters = { [3479] = "Min'loth the Serpent" } },
        [36] = { name = "The Deadmines" },
    })
    T.Eq(#rows, 3, "instances without encounters list nothing")
    T.Eq(rows[1].boss, "Rath'mael", "Ruins first, its bosses by name")
    T.Eq(rows[2].encounterID, 3411, "then Viktor")
    T.Eq(rows[3].instance, "instance 2970", "an unnamed instance by id, sorted last")
    T.Eq(#Deaths.BossRows(nil), 0, "no list")
    T.True(#Deaths.BossRows(ns.Instances.list) > 0, "the bundled data has bosses")
end)

--------------------------------------------------------------------------------
-- Once per person per fight
--------------------------------------------------------------------------------

T.Case("Deaths.Decide: once per person per fight, cleared by a new fight", function()
    local s = State()
    local first = Deaths.Decide(Death("G-TANK"), s)
    Deaths.Record(s.called, first)
    local again = Deaths.Decide(Death("G-TANK"), s)
    T.Eq(again.action, "skip", "the second death in the fight is not called")
    T.True(again.reason:find("already called", 1, true), "and says so")
    T.Eq(Deaths.Decide(Death("G-MT"), s).action, "say", "another tank still is")
    s.called = {}
    T.Eq(Deaths.Decide(Death("G-TANK"), s).action, "say", "the next pull starts over")
end)

T.Case("Deaths.Record: only a plan that said something spends the call", function()
    local called = {}
    Deaths.Record(called, { action = "skip", guid = "G-TANK" })
    T.Eq(called["G-TANK"], nil, "a skip spends nothing")
    Deaths.Record(called, { action = "queue", guid = "G-TANK" })
    T.True(called["G-TANK"], "a held line does")
end)

T.Case("Deaths.Edge: only alive to dead", function()
    T.True(Deaths.Edge(false, true), "alive to dead")
    T.Eq(Deaths.Edge(true, true), false, "still dead")
    T.Eq(Deaths.Edge(nil, true), false, "a first reading is not a death")
    T.Eq(Deaths.Edge(true, false), false, "a rez is not a death")
end)

--------------------------------------------------------------------------------
-- Saying it
--------------------------------------------------------------------------------

T.Case("Deaths.Decide: not the Raid Lead says nothing", function()
    local plan = Deaths.Decide(Death("G-TANK"), State({ isLead = false }))
    T.Eq(plan.action, "skip", "skipped")
    T.True(plan.reason:find("Raid Lead", 1, true), "because of the Raid Lead")
    T.Eq(plan.alert, nil, "and no local alert")
    T.Eq(Deaths.Decide(Death("G-TANK"), State({ enabled = false })).action, "skip", "the addon off")
    T.Eq(Deaths.Decide(Death("G-NOBODY"), State()).action, "skip", "somebody not in the group")
    T.Eq(Deaths.Decide(Death("G-DPS"), State()).counts, nil, "a damage death is not logged")
end)

T.Case("Deaths.Decide: chat locked queues, alone is local only", function()
    local held = Deaths.Decide(Death("G-TANK"), State({ chatLocked = true }))
    T.Eq(held.action, "queue", "held for the lock")
    T.True(held.alert, "with the local alert now")
    T.Eq(Deaths.Decide(Death("G-TANK"), State({ group = "solo" })).action, "local", "no group")
end)

T.Case("Deaths.Line: held through a lock, then dropped when its time runs out", function()
    local plan = Deaths.Decide(Death("G-TANK"), State({ chatLocked = true }))
    local line = Deaths.Line(plan, 10)
    T.Eq(line.ttl, 10, "the setting's TTL")
    T.Eq(line.whenLocked, "queue", "held, not refused")
    local chatState = { chat = true, group = "raid", lead = true, now = 0 }
    T.Eq(Chat.Decide(line, chatState).action, "queue", "LibICChat holds it")
    local queue = { { line = line, expires = 10 } }
    local early = Chat.Flush(queue, { chat = false, group = "raid", lead = true, now = 5 })
    T.Eq(#early.send, 1, "the lock lifting within the TTL sends it")
    T.Eq(early.send[1].channel, "RAID_WARNING", "as a raid warning")
    local late = Chat.Flush(queue, { chat = true, group = "raid", lead = true, now = 11 })
    T.Eq(#late.send, 0, "past the TTL nothing goes")
    T.Eq(late.dropped[1].reason, "expired", "it is dropped as expired")
    local member = Chat.Decide(line, { group = "raid", lead = false })
    T.Eq(member.channel, "RAID", "without assist it falls back to raid chat")
    T.Eq(Chat.Decide(line, { group = "party" }).channel, "PARTY", "and party chat in a party")
end)

T.Case("Deaths.FallbackLead: the named Raid Lead, else the leader, else alone", function()
    local r = Roster()
    T.True(Deaths.FallbackLead(nil, r), "the leader leads")
    T.Eq(Deaths.FallbackLead("Mender", r), false, "a named Raid Lead who is someone else")
    T.True(Deaths.FallbackLead("Lead", r), "a named Raid Lead who is me")
    T.True(Deaths.FallbackLead("Gone", r), "a named Raid Lead not here falls back to the leader")
    T.True(Deaths.FallbackLead(nil, { kind = "solo" }), "alone")
end)

T.Case("Deaths.Command and StatusLines", function()
    T.Eq(Deaths.Command("").action, "status", "no words is the status")
    T.Eq(Deaths.Command("test").action, "test", "test")
    local set = Deaths.Command("Healer AUTO")
    T.Eq(set.kind .. "/" .. set.value, "healer/auto", "any case")
    T.Eq(Deaths.Command("tank maybe").action, "refuse", "a bad value")
    T.Eq(Deaths.Command("dps on").action, "refuse", "a bad kind")
    local lines = Deaths.StatusLines(Settings())
    T.Eq(#lines, 2, "one line per kind")
    T.True(lines[1]:find("Tank deaths: per boss, trash yes", 1, true), "tank")
    T.True(lines[2]:find("off", 1, true), "healer")
end)

--------------------------------------------------------------------------------
-- Announce
--------------------------------------------------------------------------------

local function Resolved()
    return ns.Seats.Resolve(ns.Schema.DEFAULT_PLAN, {
        { name = "Frosty", class = "MAGE" }, { name = "Locky", class = "WARLOCK" },
    })
end

T.Case("Announce.Lines: Skull first, owners named, nobody marked", function()
    local lines = Announce.Lines(Resolved())
    T.Eq(#lines, 1, "the default plan fits one line")
    T.True(lines[1]:find("^Skull>Kill 1 | Cross>Kill 2"), "kill seats first, Skull leading")
    T.True(lines[1]:find("Moon>Sheep 1 Frosty", 1, true), "an owner by name")
    T.True(lines[1]:find("Star>Sheep 2 (nobody)", 1, true), "a seat nobody can take")
    T.Eq(#Announce.Lines({ seats = {} }), 0, "an empty plan says nothing")
    T.Eq(#Announce.Lines(nil), 0, "no plan says nothing")
end)

T.Case("Announce.Lines: every line under 255, cut between seats", function()
    local seats = {}
    for i = 1, 40 do
        seats[i] = { icon = 8, intent = "KILL", ordinal = i, owner = string.rep("x", 30) }
    end
    local lines = Announce.Lines({ seats = seats })
    T.Eq(#lines, Announce.MAX_LINES, "capped")
    for i, line in ipairs(lines) do T.True(#line <= 255, "line " .. i .. " fits") end
    T.True(lines[#lines]:find("more)", 1, true), "the last says how many were left out")
end)

T.Case("Announce.Decide: locked chat refuses, never holds", function()
    local lines = { "Skull>Kill 1" }
    local base = { prepull = true, isLead = true, chatLocked = false, group = "raid" }
    T.Eq(Announce.Decide(lines, base).action, "send", "open chat sends")
    base.chatLocked = true
    local locked = Announce.Decide(lines, base)
    T.Eq(locked.action, "refuse", "locked refuses")
    T.Eq(locked.reason, "chat is locked here", "with the reason the button shows")
    base.chatLocked = false
    base.prepull = false
    T.True(Announce.Decide(lines, base).reason:find("announce on", 1, true), "switched off")
    base.kind = "callout"
    T.Eq(Announce.Decide(lines, base).action, "send", "the switch is the pre-pull's only")
    base.isLead = false
    T.Eq(Announce.Decide(lines, base).action, "refuse", "only the Raid Lead")
    T.Eq(Announce.Decide({}, { isLead = true, group = "raid" }).action, "refuse", "an empty plan")
end)

T.Case("Announce.Channels and Command", function()
    T.Eq(table.concat(Announce.Channels("RAID"), ","), "RAID,PARTY", "raid, then party")
    T.Eq(table.concat(Announce.Channels("PARTY"), ","), "PARTY", "party alone")
    T.Eq(Announce.Command("").action, "send", "bare sends")
    T.Eq(Announce.Command(" OFF ").value, false, "off")
    T.Eq(Announce.Command("on").value, true, "on")
    T.Eq(Announce.Command("loud").action, "refuse", "anything else")
end)

--------------------------------------------------------------------------------
-- ChatCue
--------------------------------------------------------------------------------

T.Case("ChatCue.Matches: whole word, any case, nothing on nothing", function()
    T.True(ChatCue.Matches("Who FARTED? fart!", "fart"), "a whole word, any case")
    T.Eq(ChatCue.Matches("farther than that", "fart"), false, "not inside a word")
    T.True(ChatCue.Matches("pull in 5", "pull in"), "a phrase")
    T.True(ChatCue.Matches("go go-go now", "go-go"), "pattern characters are plain")
    T.Eq(ChatCue.Matches("a (b", "(b"), false, "and never raise")
    T.Eq(ChatCue.Matches("anything", ""), false, "no word set")
    T.Eq(ChatCue.Matches(nil, "fart"), false, "no text (a secret reads as nil)")
end)

T.Case("ChatCue.Allow: one sound per gap", function()
    local s = {}
    T.True(ChatCue.Allow(s, 10), "the first")
    T.Eq(ChatCue.Allow(s, 12), false, "too soon")
    T.True(ChatCue.Allow(s, 10 + ChatCue.MIN_GAP), "after the gap")
end)

T.Case("ChatCue.Sound: a kit id, a file, or nothing (no default)", function()
    T.Eq(ChatCue.Sound(8959).id, 8959, "a number is a sound kit id")
    T.Eq(ChatCue.Sound(" 8959 ").kind, "kit", "digits too")
    T.Eq(ChatCue.Sound("Interface/AddOns/X/cue.ogg").kind, "file", "a path is a file")
    T.Eq(ChatCue.Sound(""), nil, "empty plays nothing")
    T.Eq(ChatCue.Sound(nil), nil, "unset plays nothing")
end)
