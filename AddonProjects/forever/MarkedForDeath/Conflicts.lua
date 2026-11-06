local addonName, ns = ...

--[[
Conflicts: other addons doing one of MFD's jobs, named with the setting to change.

Owned by lane H (ops). The model is pure: every function takes the globals table it reads
(the client's _G in game, a case's own table in a test) and MFD's settings, and calls no
client API. The only runtime is a login line from an OnReady hook and /mfd conflicts,
both of which read _G and print.

Nothing here changes another addon's settings. Switching off a feature somebody turned on
is not a fix, it is a surprise, so a finding names the addon and the setting instead.

Reading another addon's saved table is guarded twice: a test that throws counts as "not
found", and a test only runs once the addon's own saved global exists, which is how an
addon that is installed but not loaded stays out of it. Nothing here is required.

    Conflicts.KNOWN              what is checked, one row per setting
    Conflicts.Find(g, settings)  rows that hold now, gated on MFD's own settings
    Conflicts.Lines(found)       one line each
    Conflicts.Headline(found)    the line above them, naming the jobs
    Conflicts.HasTopic(found, t) for Debug.WhyNot: is a marker addon active
    Conflicts.Now()              Find on the live _G and saved settings (runtime only)
]]

ns.Conflicts = ns.Conflicts or {}
local Conflicts = ns.Conflicts

Conflicts.TOPIC_ICONS = "raid icons"
Conflicts.TOPIC_LOGGING = "combat logging"

local DEFAULT_PROFILE = "Default"   -- EllesmereUI's profile name when none is chosen

--------------------------------------------------------------------------------
-- Pure: reading other addons' saved tables
--------------------------------------------------------------------------------

local function Table(v)
    return type(v) == "table" and v or nil
end

-- One EllesmereUI child addon's slice of the active profile, or nil. EllesmereUI keeps
-- every child's settings in EllesmereUIDB.profiles[active].addons[folder]; the child's
-- own <folder>DB global is left empty but present while the child is loaded, so that
-- global is the loaded test.
local function EllesmereProfile(g, folder)
    if not Table(g[folder .. "DB"]) then return nil end
    local db = Table(g.EllesmereUIDB)
    local profiles = db and Table(db.profiles)
    if not profiles then return nil end
    local name = type(db.activeProfile) == "string" and db.activeProfile or DEFAULT_PROFILE
    local profile = Table(profiles[name])
    local addons = profile and Table(profile.addons)
    return addons and Table(addons[folder])
end

-- Quickdraw slot kinds that place or clear raid icons.
local QUICKDRAW_ICON_KINDS = { raidtarget = true, cycleraidtarget = true, clearmarkers = true }

local function QuickdrawHasIconSlot(profile)
    for _, palette in pairs(Table(profile.palettes) or {}) do
        for _, slot in pairs(type(palette) == "table" and Table(palette.slots) or {}) do
            if type(slot) == "table" and QUICKDRAW_ICON_KINDS[slot.kind] then return true end
        end
    end
    return false
end

-- MFD's own side of each topic: a marker addon only matters while MFD marks, and a
-- logging addon only while MFD has somewhere to log.
local function MineMarks(settings)
    return settings == nil or settings.enabled ~= false
end

local function MineLogs(settings)
    local log = settings and Table(settings.logCombat)
    if not log or log.enabled == false then return false end
    return next(Table(log.instances) or {}) ~= nil
end

--------------------------------------------------------------------------------
-- The list
--------------------------------------------------------------------------------

--[[
Each row:
    addon   the name a player knows it by
    topic   TOPIC_ICONS or TOPIC_LOGGING
    what    what it is doing, as a clause
    fix     the setting to change
    quiet   true for a row worth listing on /mfd conflicts but not at every login: the
            addon only ever acts on a click the player makes
    test(g) true when the setting is on. Runs under pcall.
Defaults are read as the other addon ships them: an absent key is its default.
]]
Conflicts.KNOWN = {
    {
        addon = "EllesmereUI Quality of Life",
        topic = Conflicts.TOPIC_LOGGING,
        what = "its Auto Logging is on, so two addons switch the same combat log",
        fix = "turn Auto Logging off in EllesmereUI's Quality of Life options, or /mfd combatlog off",
        test = function(g)
            if not Table(g.EllesmereUIQoLDB) then return false end
            local db = Table(g.EllesmereUIDB)
            local auto = db and Table(db.autoLogging)
            return auto ~= nil and auto.enabled == true
        end,
    },
    {
        addon = "EllesmereUI Quality of Life",
        topic = Conflicts.TOPIC_ICONS,
        what = "its Raid Tools window has raid icon buttons, and a click there moves an icon the plan placed",
        fix = "set Raid Tools to Never in EllesmereUI's Quality of Life options, or leave its icon buttons alone",
        quiet = true,
        test = function(g)
            local profile = EllesmereProfile(g, "EllesmereUIQoL")
            local tools = profile and Table(profile.raidTools)
            local mode = tools and tools.mode
            return type(mode) == "string" and mode ~= "never"
        end,
    },
    {
        addon = "EllesmereUI Quickdraw",
        topic = Conflicts.TOPIC_ICONS,
        what = "an action menu holds raid icon slots, and firing one moves an icon the plan placed",
        fix = "take the raid icon slots out of its menus, or leave them alone in a raid",
        quiet = true,
        test = function(g)
            local profile = EllesmereProfile(g, "EllesmereUIQuickdraw")
            return profile ~= nil and profile.enabled == true and QuickdrawHasIconSlot(profile)
        end,
    },
    {
        addon = "Forever Dungeon Journal",
        topic = Conflicts.TOPIC_ICONS,
        what = "its quest-giver map pins put a raid icon on the giver when clicked nearby",
        fix = "nothing to change; avoid its quest-giver pins while the raid is marking",
        quiet = true,
        test = function(g)
            return Table(g.ForeverDungeonJournalDB) ~= nil
        end,
    },
    {
        addon = "Method Raid Tools",
        topic = Conflicts.TOPIC_ICONS,
        what = "its automarker is on, so both addons mark the same mobs",
        fix = "/mrt, Marks, Auto marks, untick Enable",
        test = function(g)
            local marks = Table(g.VMRT) and Table(g.VMRT.MarksSimple)
            return marks ~= nil and marks.autoMarkEnabled == true
        end,
    },
    {
        addon = "Method Raid Tools",
        topic = Conflicts.TOPIC_ICONS,
        what = "its buff marks are on, which also place raid icons",
        fix = "/mrt, Marks, Auto marks, untick Buff marks",
        test = function(g)
            local marks = Table(g.VMRT) and Table(g.VMRT.MarksSimple)
            return marks ~= nil and marks.buffMarkEnabled == true
        end,
    },
    {
        addon = "Method Raid Tools",
        topic = Conflicts.TOPIC_LOGGING,
        what = "its auto logging is on, so two addons switch the same combat log",
        fix = "/mrt, Logging, untick Enable, or /mfd combatlog off",
        test = function(g)
            local logging = Table(g.VMRT) and Table(g.VMRT.Logging)
            return logging ~= nil and logging.enabled == true
        end,
    },
}

--------------------------------------------------------------------------------
-- Pure: findings
--------------------------------------------------------------------------------

-- g: the globals to read (_G in game). settings: MFD's db.settings, or nil to report
-- every row regardless of what MFD has switched on. known: the rows (Conflicts.KNOWN by
-- default). Returns the rows that hold, in list order. A test that throws is "not found":
-- another addon's internals are not our contract, and a wrong guess must never cost more
-- than a missed line.
function Conflicts.Find(g, settings, known)
    local found = {}
    if type(g) ~= "table" then return found end
    for _, row in ipairs(known or Conflicts.KNOWN) do
        local relevant = settings == nil
            or (row.topic == Conflicts.TOPIC_ICONS and MineMarks(settings))
            or (row.topic == Conflicts.TOPIC_LOGGING and MineLogs(settings))
        if relevant then
            local ok, on = pcall(row.test, g)
            if ok and on == true then found[#found + 1] = row end
        end
    end
    return found
end

-- Drops the quiet rows: what is worth a line at login.
function Conflicts.Loud(found)
    local out = {}
    for _, row in ipairs(found or {}) do
        if not row.quiet then out[#out + 1] = row end
    end
    return out
end

-- One line per row: "Addon: what. Fix: fix".
function Conflicts.Lines(found)
    local lines = {}
    for _, row in ipairs(found or {}) do
        lines[#lines + 1] = string.format("%s: %s. Fix: %s.", row.addon, row.what, row.fix)
    end
    return lines
end

-- The line above the list, naming the jobs that overlap, or nil when nothing does.
-- Named by topic so a raider with a logging overlap is not told icons are being fought
-- over (a raider without assist cannot place one at all).
function Conflicts.Headline(found)
    local seen, topics = {}, {}
    for _, row in ipairs(found or {}) do
        if not seen[row.topic] then
            seen[row.topic] = true
            topics[#topics + 1] = row.topic
        end
    end
    if #topics == 0 then return nil end
    local list = topics[1]
    for i = 2, #topics do
        list = list .. (i == #topics and " and " or ", ") .. topics[i]
    end
    return "another addon is also handling " .. list .. ":"
end

function Conflicts.HasTopic(found, topic)
    for _, row in ipairs(found or {}) do
        if row.topic == topic then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- Runtime: reads _G and prints, nothing else
--------------------------------------------------------------------------------

local AMBER = "|cffffcc00"
local GREEN = "|cff66ff66"
local CLOSE = "|r"

-- The findings now, from the live globals and MFD's saved settings.
function Conflicts.Now()
    return Conflicts.Find(_G, ns.db and ns.db.settings)
end

-- Prints found rows under their headline. Returns how many it printed.
local function Report(found, sayClean)
    local headline = Conflicts.Headline(found)
    if not headline then
        if sayClean then ns.Print(GREEN .. "no other addon is doing one of these jobs." .. CLOSE) end
        return 0
    end
    ns.Print(AMBER .. headline .. CLOSE)
    for _, line in ipairs(Conflicts.Lines(found)) do
        ns.Print("  " .. AMBER .. line .. CLOSE)
    end
    return #found
end

ns.AddCommand("conflicts", "other addons doing the same jobs, and the setting to change", function()
    Report(Conflicts.Now(), true)
end)

-- Once per session, at login, and only the rows worth interrupting for. Printed, never
-- raised: nothing is broken and nothing is urgent.
ns.OnReady("conflicts", function()
    if IC_HEADLESS then return end
    Report(Conflicts.Loud(Conflicts.Now()), false)
end)
