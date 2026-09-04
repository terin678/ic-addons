-- Namespace, saved variables, event dispatch and the slash router.
local MFD = _G.MarkedForDeath or {}

-- Must match ## Version: in the toc and the packaged zip name.
MFD.VERSION = "1.16.0"

-- Bumped only when the saved-variable shape changes in a way that needs a
-- migration. See MFD:MigrateDB.
local SCHEMA_VERSION = 5

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
    rolePlan = {},
    rules = {},
    rulesVersion = { counter = 0, hash = "" },
    designatedLead = { name = "", setBy = "", setAt = 0 },
    learnedMobs = {},
    -- { [aura name] = icon texture }, filled in as the addon sees buffs on
    -- people. Saved, so the grid is icons from the second raid night onward
    -- without anyone having written a texture path down.
    learnedAuraIcons = {},
    settings = {
        -- The master switch. Off means the addon takes no action of its own:
        -- no icons, no chat, no warnings. Windows still open so it can be
        -- turned back on, and nothing configured is lost.
        isEnabled = true,
        isMarkingEnabled = true,
        isAnnounceEnabled = true,
        -- Announce the pack as it is marked rather than as it is pulled. The
        -- pull is too late: the tank is pulling while the crowd control is
        -- still reading the line.
        isAnnounceOnMarkEnabled = true,
        isCvarWarnEnabled = true,
        isWarningSoundEnabled = true,
        isIconReuseEnabled = true,
        isManualOverrideEnabled = true,
        isLateCCAlertEnabled = true,
        minimap = { hide = false },
        -- The mid-pull button bar. Shown by default: buttons nobody can find
        -- are no better than no buttons, which is how the first attempt at
        -- this went.
        actionBar = { isShown = true, isLocked = false },
        -- Death announcements. The two kinds are configured separately all the
        -- way down: their own boss list, their own override, their own people.
        -- Wanting healer calls on Naj'entus and tank calls on Illidan is a
        -- normal thing to want and one shared list cannot express it.
        --
        -- override is the mid-raid escape hatch: AUTO follows that kind's
        -- per-boss ticks, ON and OFF ignore them.
        deaths = {
            -- Set once, the first time this block exists, so the shipped
            -- defaults can tick every boss for tanks without re-ticking what
            -- somebody has since turned off. See Encounters.SeedDefaults.
            isSeeded = false,
            tank = {
                isEnabled = true,
                -- On, because tank deaths have always announced everywhere.
                onTrash = true,
                override = "AUTO",
                names = "",
                bosses = {},
            },
            healer = {
                isEnabled = false,
                onTrash = false,
                override = "AUTO",
                names = "",
                bosses = {},
            },
        },
        raidCheck = {
            isAutoOpenEnabled = true,
            expected = { FOOD = true, ELIXIRS = true },
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

    -- Schema 2: "seats" became "roles" everywhere. Copy rather than move, so a
    -- downgrade to the previous version still finds its plan. The old key is
    -- kept for one version per the repo standard.
    if db.schemaVersion < 2 then
        if db.seatPlan and next(db.seatPlan) and not (db.rolePlan and next(db.rolePlan)) then
            db.rolePlan = MFD.H.DeepCopy(db.seatPlan)
        end

        -- Circle became the icon of last resort at the same time. Only applied
        -- to a plan that still matches the shipped default for that icon, so
        -- an edited plan is left exactly as the player left it.
        local circle = db.rolePlan and db.rolePlan[2]
        if circle and circle.intent == "KILL" and circle.ordinal == 4 and circle.isLastResort == nil then
            circle.isLastResort = true
        end

        db.schemaVersion = 2
    end

    -- Schema 3: the separate FLASK, BATTLE and GUARDIAN expectations became one
    -- ELIXIRS requirement, met by a flask or by both elixirs. Anyone who asked
    -- for any of the three was asking for elixirs, so that carries over. The
    -- old keys stay for one version.
    if db.schemaVersion < 3 then
        local expected = db.settings and db.settings.raidCheck and db.settings.raidCheck.expected
        if expected and expected.ELIXIRS == nil then
            expected.ELIXIRS = (expected.FLASK or expected.BATTLE or expected.GUARDIAN) and true or false
        end

        db.schemaVersion = 3
    end

    -- Schema 4: the two tank death settings moved under settings.deaths, which
    -- now holds healer deaths and the shared boss gate as well. Copied rather
    -- than moved, per the repo standard of keeping the old keys for a version.
    if db.schemaVersion < 4 then
        local settings = db.settings
        if settings then
            settings.deaths = settings.deaths or {}
            if settings.deaths.isTankAlertEnabled == nil and settings.isTankDeathAlertEnabled ~= nil then
                settings.deaths.isTankAlertEnabled = settings.isTankDeathAlertEnabled
            end
            if settings.deaths.tankNames == nil and settings.tankNames ~= nil then
                settings.deaths.tankNames = settings.tankNames
            end
        end

        db.schemaVersion = 4
    end

    -- Schema 5: tank and healer announcements stopped sharing a boss list and
    -- an override and became two independent blocks, and "boss fights only"
    -- became a plain trash yes or no per kind.
    --
    -- The point is to land on the same behaviour the player already had. Tank
    -- deaths that announced everywhere become trash yes and every boss ticked;
    -- tank deaths already held to the list keep that list and lose trash.
    -- Healers were never on trash either way.
    if db.schemaVersion < 5 then
        local deaths = db.settings and db.settings.deaths
        if deaths and not deaths.tank then
            local sharedBosses = deaths.bosses or {}
            local sharedOverride = deaths.override or "AUTO"
            local wasBossOnly = deaths.isTankBossOnly == true

            local tankBosses
            if wasBossOnly then
                tankBosses = MFD.H.DeepCopy(sharedBosses)
            else
                tankBosses = {}
                for _, boss in ipairs(MFD.Data.Bosses) do
                    tankBosses[boss.name] = true
                end
            end

            deaths.tank = {
                isEnabled = deaths.isTankAlertEnabled ~= false,
                onTrash = not wasBossOnly,
                override = sharedOverride,
                names = deaths.tankNames or "",
                bosses = tankBosses,
            }
            deaths.healer = {
                isEnabled = deaths.isHealerAlertEnabled == true,
                onTrash = false,
                override = sharedOverride,
                names = deaths.healerNames or "",
                -- A copy, not the same table. Sharing one would make these two
                -- lists move together forever, which is the thing being fixed.
                bosses = MFD.H.DeepCopy(sharedBosses),
            }
            -- Already decided above; the seeder must not touch it.
            deaths.isSeeded = true
        end

        db.schemaVersion = 5
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

    MFD.Roles.EnsurePlan(MFD.db)
    MFD.Encounters.SeedDefaults(MFD.db.settings.deaths, MFD.Data.Bosses)

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
        if not MFD.IsEnabled() or not MFD.db.settings.raidCheck.isAutoOpenEnabled then
            return
        end
        -- Specs come from inspection, so give the pump a window after every
        -- ready check even on clients that keep the window closed.
        MFD.RaidCheck.inspectUntil = GetTime() + MFD.RaidCheck.INSPECT_READY_CHECK_SECONDS

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

-- The master switch. Every path that acts on the world asks this first:
-- marking, chat announcements, tank death alerts, callouts and the ready
-- check window. Reading and configuring always work, so the addon can be
-- turned back on without a reload.
function MFD.IsEnabled()
    return MFD.db and MFD.db.settings.isEnabled ~= false
end

-- Turns everything off or on. Clearing icons on the way out matters: leaving
-- the raid marked by an addon that has stopped defending those marks is worse
-- than leaving it unmarked.
function MFD.SetEnabled(isEnabled)
    MFD.db.settings.isEnabled = isEnabled and true or false

    if not isEnabled then
        MFD.Marker:ClearAll()
        MFD.Print("|cffff4444disabled. Nothing will be marked or announced. /mfd on to resume.|r")
    else
        wipe(MFD.Marker.locked)
        wipe(MFD.Marker.placed)
        MFD.Print("|cff66ff66enabled|r")
    end

    if MFD.UI and MFD.UI.Settings then
        MFD.UI.Settings:Refresh()
    end
end

commands.off = {
    desc = "stop the addon doing anything, without unloading it",
    run = function()
        MFD.SetEnabled(false)
    end,
}

commands.on = {
    desc = "resume after /mfd off",
    run = function()
        MFD.SetEnabled(true)
    end,
}

commands.config = {
    desc = "open the role editor: which icon means which job, and who is pinned to it",
    run = function()
        MFD.UI.Config:Toggle()
    end,
}

commands.whycheck = {
    desc = "explain why the raid check grid is empty or calling nobody out",
    run = function()
        MFD.Print("addon enabled: " .. tostring(MFD.IsEnabled())
            .. (MFD.IsEnabled() and "" or "  |cffff4444Call out is switched off with it. /mfd on|r"))

        local inRaid = IsInRaid and IsInRaid() or false
        local inGroup = IsInGroup and IsInGroup() or false
        MFD.Print(string.format("in raid: %s   in group: %s   members: %s",
            tostring(inRaid), tostring(inGroup), tostring(GetNumGroupMembers and GetNumGroupMembers() or "?")))

        local units = MFD.RaidCheck.GroupUnits()
        local named = {}
        for _, unit in ipairs(units) do
            named[#named + 1] = unit .. "=" .. tostring(UnitName(unit))
        end
        MFD.Print("units the check will read (" .. #units .. "): "
            .. (#named > 0 and table.concat(named, ", ") or "|cffff4444none|r"))

        MFD.RaidCheck:Scan()
        local rows = MFD.RaidCheck:SortedRows()
        MFD.Print("rows after a scan: " .. #rows)

        local roster = MFD.Marker.CurrentRoster()
        local classes = {}
        for _, member in ipairs(roster) do
            classes[#classes + 1] = tostring(member.class)
        end
        MFD.Print("roster the provider check uses (" .. #roster .. "): "
            .. (#classes > 0 and table.concat(classes, ", ") or "|cffff4444none|r"))

        local providers = {}
        for column, canProvide in pairs(MFD.RaidCheck.providers or {}) do
            if canProvide then
                providers[#providers + 1] = column
            end
        end
        table.sort(providers)
        MFD.Print("buffs somebody here can cast: "
            .. (#providers > 0 and table.concat(providers, ", ")
                or "|cff999999none, so no raid buff is reported missing|r"))

        for _, entry in ipairs(rows) do
            MFD.Print(string.format("  %s: %d missing", entry.name, #entry.missing))
        end
    end,
}

commands.conflicts = {
    desc = "check whether another addon is also placing raid icons",
    run = function()
        MFD.Conflicts.Report(true)
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

commands.readycheck = {
    desc = "start a real ready check, the native one everybody sees",
    run = function()
        MFD.RaidCheck:StartReadyCheck()
    end,
}

commands.callout = {
    desc = "post who is missing what to raid chat, grouped by fix",
    run = function()
        MFD.RaidCheck:PostCallout()
    end,
}

commands.bulk = {
    desc = "paste a whole kill order for a zone, one mob per line",
    run = function()
        MFD.UI.Rules:ShowTransferBox("", "bulk")
    end,
}

commands.addname = {
    desc = "add a rule by typing a mob name, e.g. /mfd addname Illidari Nightlord",
    run = function(rest)
        local name = string.match(rest or "", "^%s*(.-)%s*$")
        if name == "" then
            MFD.Error("give a mob name. /mfd addname Illidari Nightlord")
            return
        end
        MFD.UI.Rules:AddRule({ name = name })
    end,
}

commands.options = {
    desc = "open the settings window",
    run = function()
        MFD.UI.Settings:Toggle()
    end,
}

commands.bar = {
    desc = "show or hide the action bar of mid-pull buttons",
    run = function(rest)
        local what = string.lower(string.match(rest or "", "^%s*(%S*)") or "")
        if what == "reset" then
            MFD.UI.ActionBar:Reset()
        elseif what == "lock" then
            local settings = MFD.db.settings.actionBar
            settings.isLocked = not settings.isLocked
            MFD.UI.ActionBar:UpdateLock()
            MFD.Print("action bar " .. (settings.isLocked and "locked" or "unlocked"))
        else
            MFD.UI.ActionBar:Toggle()
        end
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

        MFD.Conflicts.Report(false)

        MFD.Print(string.format(
            "|cff888888roles %d, visible %d, rules %d, assigned %d, zone %s|r",
            state.roleCount, state.candidateCount, state.ruleCount, state.desiredCount,
            tostring(state.instanceKey or "none")))
    end,
}

commands.mark = {
    desc = "force a full re-mark of the visible pack",
    run = function()
        MFD.Actions.Run("remark")
    end,
}

commands.deaths = {
    desc = "death announcements: /mfd deaths tank|healer [on|off|auto]",
    run = function(rest)
        local kind, state = string.match(rest or "", "^%s*(%S*)%s*(%S*)")
        kind = string.lower(kind or "")
        state = string.upper(state or "")

        -- Bare, it reports both rather than guessing which one you meant. The
        -- two are configured apart and a command that silently picked one would
        -- be the wrong one half the time.
        if kind == "" then
            for _, each in ipairs(MFD.Encounters.KINDS) do
                local config = MFD.Encounters.Settings(each)
                MFD.Print(MFD.Encounters.KIND_LABELS[each] .. " deaths: "
                    .. (config.isEnabled and "on" or "off")
                    .. ", " .. MFD.Encounters.OVERRIDE_LABELS[config.override]
                    .. ", trash " .. (config.onTrash and "yes" or "no"))
            end
            return
        end

        local config = MFD.Encounters.Settings(kind)
        if not config then
            MFD.Error("use /mfd deaths tank|healer [on|off|auto]")
            return
        end

        if state == "" then
            -- Same code the button and the keybind run, not a second copy.
            MFD.Actions.Run("deaths_" .. kind)
            return
        end

        if state ~= "ON" and state ~= "OFF" and state ~= "AUTO" then
            MFD.Error("use /mfd deaths " .. kind .. " on|off|auto")
            return
        end

        config.override = state
        MFD.Print(MFD.Encounters.KIND_LABELS[kind] .. " death announcements: "
            .. MFD.Encounters.OVERRIDE_LABELS[config.override])
        if MFD.UI.Deaths and MFD.UI.Deaths.Refresh then
            MFD.UI.Deaths:Refresh()
        end
    end,
}

commands.healers = {
    desc = "list who the addon currently counts as a healer",
    run = function()
        local known = MFD.Healers.Known(MFD.Healers.KnownSpecs(), MFD.Healers.ManualList())
        if #known == 0 then
            MFD.Print("no healers recognised. Specs come from inspection, so open the raid check "
                .. "tab or run a ready check, or type names on the Deaths tab.")
            return
        end
        MFD.Print("healers: " .. table.concat(known, ", "))
    end,
}

commands.announce = {
    desc = "call the current assignments out in raid chat now, before the pull",
    run = function()
        MFD.Actions.Run("announce")
    end,
}

commands.clear = {
    desc = "clear every icon on visible mobs",
    run = function()
        MFD.Actions.Run("clear")
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

        if not MFD.Roles.INTENTS[intent] then
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
        local canApply, why = MFD.Roles.CanIntentApply(intent, creatureType)
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
                MFD.Print(name .. " is now " .. MFD.Roles.INTENTS[intent].label)
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
            name, npcID, MFD.Roles.INTENTS[intent].label, list[#list].rank, instanceKey))
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
            local label = MFD.Roles.INTENTS[rule.intent] and MFD.Roles.INTENTS[rule.intent].label or rule.intent
            local mine = rule.owner == UnitName("player")
            MFD.Print(string.format("%s%d. %s - %s (npc %d)%s|r",
                mine and "" or "|cffffcc66",
                rule.rank, rule.name or "?", label, rule.npcID,
                mine and "" or (" from " .. tostring(rule.owner))))

            -- Surfaced here as well as at /mfd add, because a rule can become
            -- wrong later: rebinding a role changes which intent a mob gets.
            local learned = MFD.db.learnedMobs[rule.npcID]
            local canApply, why = MFD.Roles.CanIntentApply(rule.intent, learned and learned.creatureType)
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
        for _, intent in ipairs(MFD.H.SortedKeys(MFD.Roles.INTENTS)) do
            MFD.Print("  " .. string.lower(intent) .. " - " .. MFD.Roles.INTENTS[intent].label)
        end
    end,
}

commands.share = {
    desc = "a shareable JSON file of your rules, for posting or handing to someone",
    run = function()
        MFD.UI.Rules:ShowTransferBox(MFD.Rules.ToJSON(MFD.db.rules, {}), "exportjson")
    end,
}

commands.load = {
    desc = "paste a shared rule file to merge it into yours",
    run = function()
        MFD.UI.Rules:ShowTransferBox("", "importjson")
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
-- The mid-pull ones, named from the action table so the keybinding screen and
-- the buttons cannot describe the same thing two different ways.
BINDING_NAME_MARKEDFORDEATH_ANNOUNCE = MFD.Actions.BY_KEY.announce.binding
BINDING_NAME_MARKEDFORDEATH_CLEAR = MFD.Actions.BY_KEY.clear.binding
BINDING_NAME_MARKEDFORDEATH_REMARK = MFD.Actions.BY_KEY.remark.binding
BINDING_NAME_MARKEDFORDEATH_MARKING = MFD.Actions.BY_KEY.marking.binding
BINDING_NAME_MARKEDFORDEATH_DEATHS_TANK = MFD.Actions.BY_KEY.deaths_tank.binding
BINDING_NAME_MARKEDFORDEATH_DEATHS_HEALER = MFD.Actions.BY_KEY.deaths_healer.binding
BINDING_NAME_MARKEDFORDEATH_RULES = "Toggle the rule editor"
BINDING_NAME_MARKEDFORDEATH_ASSIGNMENTS = "Toggle the assignment panel"
BINDING_NAME_MARKEDFORDEATH_BUFFS = "Toggle the buff board"
BINDING_NAME_MARKEDFORDEATH_BAR = "Toggle the action bar"

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

    -- Bare /mfd opens the window, which is what a player reaching for it
    -- almost always wants. /mfd help still lists everything.
    if cmd == "" then
        MFD.UI.Main:Toggle()
        return
    end

    local entry = commands[cmd]
    if not entry then
        MFD.Error("unknown command '" .. cmd .. "'. Try /mfd help.")
        return
    end

    entry.run(rest)
end

_G.MarkedForDeath = MFD
