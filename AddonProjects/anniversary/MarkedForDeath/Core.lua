-- Namespace, saved variables, event dispatch and the slash router.
local MFD = _G.MarkedForDeath or {}

-- Must match ## Version: in the toc and the packaged zip name.
MFD.VERSION = "0.1.0"

-- Bumped only when the saved-variable shape changes in a way that needs a
-- migration. See MFD:MigrateDB.
local SCHEMA_VERSION = 1

local CHAT_PREFIX = "|cff33ff99Marked For Death|r: "

local inits = {}

-- Registers fn to run once on ADDON_LOADED, after saved variables are ready.
-- Modules use this instead of creating frames or reading client state at file
-- scope, which is what keeps them loadable under the headless test harness.
function MFD.RegisterInit(fn)
    inits[#inits + 1] = fn
end

function MFD.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. tostring(msg))
end

-- Prints to chat and also to the on-screen error area, per the repo standard
-- that errors are visible without watching the chat frame.
function MFD.Error(msg)
    MFD.Print("|cffff4444" .. tostring(msg) .. "|r")
    if UIErrorsFrame then
        UIErrorsFrame:AddMessage("Marked For Death: " .. tostring(msg), 1, 0.3, 0.3)
    end
end

local DB_DEFAULTS = {
    schemaVersion = SCHEMA_VERSION,
    seatPlan = {},
    rules = {},
    rulesVersion = { counter = 0, hash = "" },
    designatedLead = { name = "", setBy = "", setAt = 0 },
    learnedMobs = {},
    settings = {
        isMarkingEnabled = true,
        isAnnounceEnabled = true,
        isCvarWarnEnabled = true,
    },
    lastTestRun = {},
}

local CHAR_DB_DEFAULTS = {
    windows = {},
}

-- Migrates an existing saved-variable table in place. Reads the previous shape
-- for one version and never deletes user data.
function MFD:MigrateDB()
    local db = MarkedForDeathDB
    if not db.schemaVersion then
        db.schemaVersion = SCHEMA_VERSION
    end
end

local function onAddonLoaded()
    MarkedForDeathDB = MarkedForDeathDB or {}
    MarkedForDeathCharDB = MarkedForDeathCharDB or {}

    MFD:MigrateDB()
    MFD.H.ApplyDefaults(MarkedForDeathDB, DB_DEFAULTS)
    MFD.H.ApplyDefaults(MarkedForDeathCharDB, CHAR_DB_DEFAULTS)

    MFD.db = MarkedForDeathDB
    MFD.charDb = MarkedForDeathCharDB

    for _, fn in ipairs(inits) do
        local ok, err = pcall(fn)
        if not ok then
            MFD.Error("init failed: " .. tostring(err))
        end
    end

    MFD.Print("v" .. MFD.VERSION .. " loaded. /mfd help for commands.")
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "MarkedForDeath" then
        onAddonLoaded()
    end
end)

-- Slash commands. Every entry here must also appear in the help output below,
-- which is enforced by the review checklist rather than by code.
local commands = {}

commands.help = {
    desc = "list commands",
    run = function()
        MFD.Print("commands:")
        for _, name in ipairs(MFD.H.SortedKeys(commands)) do
            MFD.Print("  /mfd " .. name .. " - " .. commands[name].desc)
        end
    end,
}

commands.version = {
    desc = "print the addon version",
    run = function()
        MFD.Print("version " .. MFD.VERSION)
    end,
}

commands.selftest = {
    desc = "run the test suite in game",
    run = function()
        if not MFD.Tests then
            MFD.Error("test suite not loaded")
            return
        end
        MFD.Tests.Run()
    end,
}

commands.candidates = {
    desc = "list the hostile units the addon can currently see",
    run = function()
        local list = MFD.Candidates.ToList(MFD.Candidates.set)
        if #list == 0 then
            MFD.Print("no candidates visible. Are enemy nameplates enabled?")
            return
        end
        for _, c in ipairs(list) do
            MFD.Print(string.format("  %s (npc %d)", c.key, c.npcID))
        end
    end,
}

commands.mark = {
    desc = "force a full re-mark of the visible pack",
    run = function()
        wipe(MFD.Marker.locked)
        wipe(MFD.Marker.placed)
        MFD.Print("re-marking")
    end,
}

commands.clear = {
    desc = "clear every icon on visible mobs",
    run = function()
        local cleared = 0
        for _, entry in pairs(MFD.Candidates.set) do
            if entry.unit then
                SetRaidTarget(entry.unit, 0)
                cleared = cleared + 1
            end
        end
        wipe(MFD.Marker.locked)
        wipe(MFD.Marker.placed)
        MFD.Print("cleared " .. cleared .. " icons")
    end,
}

commands.fixcvars = {
    desc = "set the nameplate settings marking needs",
    run = function()
        SetCVar("nameplateShowEnemies", 1)
        SetCVar("nameplateMaxDistance", 41)
        MFD.Print("enemy nameplates on, distance set to 41 yards")
    end,
}

-- Temporary hand-testing hook, removed in Task 7 once the rule editor exists.
commands.testrule = {
    desc = "temporary: rule the current target as a kill target",
    run = function()
        local guid = UnitGUID("target")
        local npcID = guid and MFD.H.NpcIDFromKey(MFD.H.KeyFromGUID(guid) or "")
        if not npcID then
            MFD.Print("no valid creature targeted")
            return
        end
        MFD.Rules.activeByNpcID = MFD.Rules.activeByNpcID or {}
        MFD.Rules.activeByNpcID[npcID] = { npcID = npcID, intent = "KILL", rank = 10 }
        MFD.Print("npc " .. npcID .. " will now be marked as a kill target")
    end,
}

MFD.commands = commands

SLASH_MARKEDFORDEATH1 = "/mfd"
SLASH_MARKEDFORDEATH2 = "/markedfordeath"
SlashCmdList["MARKEDFORDEATH"] = function(input)
    local cmd, rest = string.match(input or "", "^(%S*)%s*(.-)$")
    cmd = string.lower(cmd or "")

    if cmd == "" then
        cmd = "help"
    end

    local entry = commands[cmd]
    if not entry then
        MFD.Error("unknown command '" .. cmd .. "'. Try /mfd help.")
        return
    end

    entry.run(rest)
end

_G.MarkedForDeath = MFD
