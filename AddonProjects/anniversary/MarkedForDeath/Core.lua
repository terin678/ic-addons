-- Namespace, saved variables, event dispatch and the slash router.
local MFD = _G.MarkedForDeath or {}

-- Must match ## Version: in the toc and the packaged zip name.
MFD.VERSION = "1.0.1"

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
        isWarningSoundEnabled = true,
        minimap = { hide = false },
        raidCheck = {
            isAutoOpenEnabled = true,
            expected = { FOOD = true, FLASK = true, BATTLE = false, GUARDIAN = false, WEAPON = true },
        },
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

    MFD.Seats.EnsurePlan(MFD.db)

    for _, fn in ipairs(inits) do
        local ok, err = pcall(fn)
        if not ok then
            MFD.Error("init failed: " .. tostring(err))
        end
    end

    -- Rules are filed per zone and activate automatically, so the addon needs
    -- to know where the player is before any rule can match.
    local zoneFrame = CreateFrame("Frame")
    zoneFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    zoneFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    zoneFrame:SetScript("OnEvent", function()
        local _, _, _, _, _, _, _, instanceMapID = GetInstanceInfo()
        MFD.Rules.currentInstanceKey = MFD.Rules.InstanceKeyFor(instanceMapID)
    end)

    MFD.Rules.RefreshLocal(MFD.db, UnitName("player"))

    -- The grid opens itself on ready check for the raid leader and assistants
    -- only. A window on twenty four screens every ready check is how an addon
    -- gets uninstalled. Everyone else still scans so their buff board is fresh.
    local readyFrame = CreateFrame("Frame")
    readyFrame:RegisterEvent("READY_CHECK")
    readyFrame:SetScript("OnEvent", function()
        if not MFD.db.settings.raidCheck.isAutoOpenEnabled then
            return
        end
        local isLeadOrAssist = UnitIsGroupLeader("player")
            or (UnitIsGroupAssistant and UnitIsGroupAssistant("player"))
        if isLeadOrAssist then
            MFD.UI.RaidCheck:Show()
        else
            MFD.RaidCheck:Scan()
        end
    end)

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

-- Path relative to the game root, as PlaySoundFile requires. Shipped inside the
-- addon folder the same way CutMaster ships its icon texture.
local BAD_MARK_SOUND = "Interface\\AddOns\\MarkedForDeath\\Sounds\\BadMark.mp3"

-- Plays the "that rule cannot work" sound. Guarded on every side: the setting,
-- the API's existence, and the call itself, because a missing or unplayable
-- file must never turn an advisory warning into a Lua error.
function MFD.PlayBadMarkSound()
    if not MFD.db or not MFD.db.settings.isWarningSoundEnabled then
        return
    end

    if type(PlaySoundFile) ~= "function" then
        return
    end

    pcall(PlaySoundFile, BAD_MARK_SOUND, "Master")
end

commands.config = {
    desc = "open the seat editor: which icon means which job, and who is pinned to it",
    run = function()
        MFD.UI.Config:Toggle()
    end,
}

commands.coverage = {
    desc = "compare the mobs you have seen against the bundled database",
    run = function()
        local bundled, learned, missing = 0, 0, {}
        for _ in pairs(MFD.Data.Mobs) do
            bundled = bundled + 1
        end
        for npcID, entry in pairs(MFD.db.learnedMobs) do
            learned = learned + 1
            if not MFD.Data.Mobs[npcID] then
                missing[#missing + 1] = npcID .. " " .. tostring(entry.name)
            end
        end
        table.sort(missing)
        MFD.Print(string.format("%d bundled, %d learned, %d seen but not bundled", bundled, learned, #missing))
        for i = 1, math.min(#missing, 20) do
            MFD.Print("  |cffffcc66" .. missing[i] .. "|r")
        end
        if #missing > 20 then
            MFD.Print("  ... and " .. (#missing - 20) .. " more")
        end
    end,
}

commands.missing = {
    desc = "text summary of who is missing what buff or consumable",
    run = function()
        MFD.RaidCheck:Scan()
        local anyone = false
        for _, entry in ipairs(MFD.RaidCheck:SortedRows()) do
            if #entry.missing > 0 then
                anyone = true
                local labels = {}
                for _, m in ipairs(entry.missing) do
                    labels[#labels + 1] = m.label
                end
                MFD.Print(string.format("%s%s|r: %s",
                    entry.row.isReported and "" or "|cffffcc66",
                    entry.name, table.concat(labels, ", ")))
            end
        end
        if not anyone then
            MFD.Print("everyone has everything the group can provide")
        end
    end,
}

commands.check = {
    desc = "open the full raid buff and consumable grid",
    run = function()
        MFD.UI.RaidCheck:Toggle()
    end,
}

commands.auras = {
    desc = "list the buff names on you and how the addon classified them",
    run = function()
        local names = MFD.RaidCheck.AuraNames("player")
        local state = MFD.RaidCheck.Classify(names)
        MFD.Print(#names .. " buffs on you: " .. table.concat(names, ", "))
        MFD.Print(string.format("food=%s flask=%s battle=%s guardian=%s unclassified=%s",
            tostring(state.food), tostring(state.flask), tostring(state.battle),
            tostring(state.guardian), tostring(state.unclassifiedElixir)))
        MFD.Print(string.format("int=%s motw=%s fort=%s sprot=%s blessings=%s",
            tostring(state.AI), tostring(state.MOTW), tostring(state.FORT), tostring(state.SP),
            table.concat(state.blessings, " ")))
    end,
}

commands.buffs = {
    desc = "quick board of who is missing buffs, no ready check needed",
    run = function()
        MFD.UI.BuffBoard:Toggle()
    end,
}

commands.callout = {
    desc = "post who is missing what to raid chat, grouped by fix",
    run = function()
        MFD.RaidCheck:PostCallout()
    end,
}

commands.minimap = {
    desc = "show or hide the minimap button",
    run = function()
        MFD.Minimap:Toggle()
    end,
}

commands.sound = {
    desc = "toggle the sound played when a rule cannot work on its target",
    run = function()
        local settings = MFD.db.settings
        settings.isWarningSoundEnabled = not settings.isWarningSoundEnabled

        if settings.isWarningSoundEnabled then
            MFD.Print("bad-mark sound on")
            MFD.PlayBadMarkSound()
        else
            MFD.Print("bad-mark sound off")
        end
    end,
}

commands.lead = {
    desc = "designate the Raid Lead, or clear it with no name",
    run = function(rest)
        MFD.Comms:SetLead(rest ~= "" and rest or nil)
    end,
}

commands.status = {
    desc = "show the marker, the peers and the rule counts",
    run = function()
        MFD.Print("marker: " .. tostring(MFD.Comms.authority or "|cffff4444nobody|r")
            .. " (" .. MFD.Comms.authorityMode .. ")")

        if MFD.Comms.authorityReason ~= "" then
            MFD.Print("  |cffff4444" .. MFD.Comms.authorityReason .. "|r")
        end

        local designated = MFD.db.designatedLead.name
        MFD.Print("designated lead: " .. (designated ~= "" and designated or "|cff999999none|r"))

        local canMark, why = MFD.Marker:CanMark()
        MFD.Print("you can place icons: " .. tostring(canMark)
            .. (why ~= "" and " (" .. why .. ")" or ""))

        local names = MFD.Comms:PeerNames()
        MFD.Print(#names .. " addon users: " .. table.concat(names, ", "))

        local count = 0
        for _ in pairs(MFD.Rules.Active()) do
            count = count + 1
        end
        local counts = MFD.Comms:ContributionCounts()
        for _, owner in ipairs(MFD.H.SortedKeys(counts)) do
            MFD.Print("|cffffcc66" .. counts[owner] .. " rules merged from " .. owner .. "|r")
        end

        MFD.Print("active rules: " .. count .. " in "
            .. tostring(MFD.Rules.currentInstanceKey or "no known zone"))
    end,
}

commands.debug = {
    desc = "explain why marking is or is not happening right now",
    run = function()
        local reasons, state = MFD.Marker:Diagnose()

        for _, reason in ipairs(reasons) do
            MFD.Print(reason)
        end

        MFD.Print(string.format(
            "|cff888888seats %d, visible %d, rules %d, assigned %d, zone %s|r",
            state.seatCount, state.candidateCount, state.ruleCount, state.desiredCount,
            tostring(state.instanceKey or "none")))
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
        -- Routed through ActionableUnits for the same reason the marker is:
        -- clearing through a stale token wipes the icon off whatever the
        -- player is currently pointing at.
        local cleared = 0
        for _, unit in pairs(MFD.Candidates.ActionableUnits(MFD.Candidates.set, UnitGUID)) do
            SetRaidTarget(unit, 0)
            cleared = cleared + 1
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

commands.where = {
    desc = "print the current zone and how many rules are active for it",
    run = function()
        local name, _, _, _, _, _, _, instanceMapID = GetInstanceInfo()
        local key = MFD.Rules.InstanceKeyFor(instanceMapID)
        MFD.Print(string.format("%s (map %s) filed under %s",
            tostring(name), tostring(instanceMapID), tostring(key)))

        local count = 0
        for _ in pairs(MFD.Rules.Active()) do
            count = count + 1
        end
        MFD.Print(count .. " active rules here")
    end,
}

-- Resolves the unit the player is pointing at. Returns the unit token, its
-- npcID and its name, or nil plus a reason.
local function pointedAtCreature()
    local unit = (UnitExists("target") and "target")
        or (UnitExists("mouseover") and "mouseover")
        or nil

    if not unit then
        return nil, nil, nil, "target or mouse over a mob first"
    end

    local key = MFD.H.KeyFromGUID(UnitGUID(unit) or "")
    if not key then
        return nil, nil, nil, "that is not a creature"
    end

    return unit, MFD.H.NpcIDFromKey(key), UnitName(unit)
end

commands.add = {
    desc = "rule the current target, e.g. /mfd add sheep (defaults to kill)",
    run = function(rest)
        local unit, npcID, name, why = pointedAtCreature()
        if not unit then
            MFD.Error(why)
            return
        end

        local intent = string.upper(rest or "")
        if intent == "" then
            intent = "KILL"
        end

        if not MFD.Seats.INTENTS[intent] then
            MFD.Error("unknown intent '" .. intent .. "'. Try /mfd intents.")
            return
        end

        local instanceKey = MFD.Rules.currentInstanceKey
        if not instanceKey then
            MFD.Error("cannot tell what zone this is yet, try again in a moment")
            return
        end

        -- Advisory only. The rule is still added: the player may know something
        -- this table does not, and a wrong table must not block real work.
        local creatureType = UnitCreatureType and UnitCreatureType(unit) or nil
        local canApply, why = MFD.Seats.CanIntentApply(intent, creatureType)
        if not canApply then
            MFD.Print("|cffff4444" .. why .. ". Adding it anyway.|r")
            MFD.PlayBadMarkSound()
        end

        MFD.db.rules[instanceKey] = MFD.db.rules[instanceKey] or {}
        local list = MFD.db.rules[instanceKey]

        for _, rule in ipairs(list) do
            if rule.npcID == npcID then
                rule.intent = intent
                MFD.Comms.Republish()
                MFD.Comms:AdvertiseRules()
                MFD.Print(name .. " is now " .. MFD.Seats.INTENTS[intent].label)
                return
            end
        end

        list[#list + 1] = {
            npcID = npcID,
            name = name,
            intent = intent,
            rank = MFD.Rules.NextRank(list),
        }

        MFD.Comms.Republish()
        MFD.Comms:AdvertiseRules()
        MFD.Print(string.format("%s (npc %d) added as %s, priority %d in %s",
            name, npcID, MFD.Seats.INTENTS[intent].label, list[#list].rank, instanceKey))
    end,
}

commands.list = {
    desc = "list the rules active in this zone, best priority first",
    run = function()
        local ranked = MFD.Rules.Ranked(MFD.Rules.Active())
        if #ranked == 0 then
            MFD.Print("no rules for " .. tostring(MFD.Rules.currentInstanceKey or "this zone")
                .. ". Target a mob and use /mfd add.")
            return
        end

        local hasBadRule = false

        for _, rule in ipairs(ranked) do
            local label = MFD.Seats.INTENTS[rule.intent] and MFD.Seats.INTENTS[rule.intent].label or rule.intent
            local mine = rule.owner == UnitName("player")
            MFD.Print(string.format("%s%d. %s - %s (npc %d)%s|r",
                mine and "" or "|cffffcc66",
                rule.rank, rule.name or "?", label, rule.npcID,
                mine and "" or (" from " .. tostring(rule.owner))))

            -- Surfaced here as well as at /mfd add, because a rule can become
            -- wrong later: rebinding a seat changes which intent a mob gets.
            local learned = MFD.db.learnedMobs[rule.npcID]
            local canApply, why = MFD.Seats.CanIntentApply(rule.intent, learned and learned.creatureType)
            if not canApply then
                MFD.Print("     |cffff4444" .. why .. "|r")
                hasBadRule = true
            end
        end

        -- Once per listing, not once per bad rule.
        if hasBadRule then
            MFD.PlayBadMarkSound()
        end
    end,
}

commands.del = {
    desc = "remove a rule by npc id, e.g. /mfd del 22890",
    run = function(rest)
        local npcID = tonumber(rest)
        if not npcID then
            MFD.Error("give an npc id. /mfd list shows them.")
            return
        end

        local list = MFD.db.rules[MFD.Rules.currentInstanceKey or ""] or {}
        for i, rule in ipairs(list) do
            if rule.npcID == npcID then
                table.remove(list, i)
                MFD.Comms.Republish()
                MFD.Comms:AdvertiseRules()
                MFD.Print("removed rule for npc " .. npcID)
                return
            end
        end

        MFD.Error("no rule of your own for npc " .. npcID .. " in this zone")
    end,
}

commands.intents = {
    desc = "list the crowd control intents a rule can use",
    run = function()
        for _, intent in ipairs(MFD.H.SortedKeys(MFD.Seats.INTENTS)) do
            MFD.Print("  " .. string.lower(intent) .. " - " .. MFD.Seats.INTENTS[intent].label)
        end
    end,
}

commands.export = {
    desc = "show a shareable string of your own rules",
    run = function()
        MFD.UI.Rules:ShowTransferBox(MFD.H.Base64Encode(MFD.Rules.Serialize(MFD.db.rules)), "export")
    end,
}

commands["import"] = {
    desc = "open a box to paste a rule string into",
    run = function()
        MFD.UI.Rules:ShowTransferBox("", "import")
    end,
}

commands.rules = {
    desc = "open the rule editor and mob search",
    run = function()
        MFD.UI.Rules:Toggle()
    end,
}

-- Binding display names. These must be globals; the client reads them by name
-- from the keybinding UI, which is the documented exception to the one-global
-- rule in CODING_STANDARDS.md.
BINDING_HEADER_MARKEDFORDEATH = "Marked For Death"
BINDING_NAME_MARKEDFORDEATH_ADD = "Add target as a rule"
BINDING_NAME_MARKEDFORDEATH_REMARK = "Re-mark the visible pack"
BINDING_NAME_MARKEDFORDEATH_RULES = "Toggle the rule editor"
BINDING_NAME_MARKEDFORDEATH_ASSIGNMENTS = "Toggle the assignment panel"
BINDING_NAME_MARKEDFORDEATH_BUFFS = "Toggle the buff board"

MFD.Bindings = {}

-- Opens the rule editor pre-filled with whatever the player is pointing at.
-- This is the primary way rules get created; search is for planning at a desk.
function MFD.Bindings.AddTarget()
    local unit, npcID, name, why = pointedAtCreature()
    if not unit then
        MFD.Error(why)
        return
    end

    MFD.UI.Rules:OpenFor(npcID, name, unit)
end

function MFD.Bindings.Remark()
    commands.mark.run()
end

function MFD.Bindings.ToggleRules()
    MFD.UI.Rules:Toggle()
end

function MFD.Bindings.ToggleAssignments()
    if MFD.UI.Assignments then
        MFD.UI.Assignments:Toggle()
    else
        MFD.Error("the assignment panel is not in this build yet")
    end
end

function MFD.Bindings.ToggleBuffs()
    MFD.UI.BuffBoard:Toggle()
end

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
