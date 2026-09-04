local addonName, ns = ...

--[[
GuildRecruitment. Built from ICTemplate; see Docs/ICTemplate.md for the shape.

The guild runs two raid teams and every raid officer recruits for both. Before
this, each officer typed their own line into a channel, nobody knew who had
posted last, and the wording drifted. So: raid leaders author one message, every
officer's copy converges on it, and a log of who barked when means the second
officer does not add a second line four minutes after the first.
]]

local VERSION = "0.1.2"
ns.VERSION = VERSION

ns.SCHEMA = 1
ns.CHAR_SCHEMA = 1

--------------------------------------------------------------------------------
-- Output
--------------------------------------------------------------------------------

function ns.Print(msg)
    local frame = DEFAULT_CHAT_FRAME
    local idx = ns.db and ns.db.settings and ns.db.settings.outputFrame
    if idx and idx > 1 then
        local f = _G["ChatFrame" .. idx]
        if f and f.AddMessage then frame = f end
    end
    frame:AddMessage("|cff33ff99GuildRecruitment|r: " .. tostring(msg))
end

function ns.Printf(fmt, ...)
    ns.Print(string.format(fmt, ...))
end

-- False means the addon says nothing of its own. Reading the window still works,
-- and so does sending by hand.
function ns.Enabled()
    return not ns.db or ns.db.settings.enabled ~= false
end

function ns.Now()
    return GetServerTime and GetServerTime() or time()
end

--------------------------------------------------------------------------------
-- Saved variables
--------------------------------------------------------------------------------

function ns.DeepCopy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = ns.DeepCopy(v) end
    return out
end

function ns.ApplyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then target[k] = {} end
            ns.ApplyDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
    return target
end

-- Keyed by the schema each step upgrades FROM. Run before ApplyDefaults, always.
ns.Migrations = {}

function ns.Migrate(db, steps, head)
    if db.schema == nil then
        db.schema = next(db) == nil and head or 1
    end
    local ran = 0
    while db.schema < head do
        local step = steps[db.schema]
        if step then step(db) end
        db.schema = db.schema + 1
        ran = ran + 1
    end
    return ran
end

ns.Defaults = {
    -- The document is guild property, so it is account-wide: an officer's alt is
    -- the same officer, and this is exactly what Comm sends and receives.
    doc = {
        rev = 0, author = "", updatedAt = 0, guild = "", hash = "",
        template = "<{guild}> is recruiting: {teams}. Whisper {contacts}!",
        teamTemplate = "{tag} {days}: {needs}",
        contacts = {},
        teams = {},
    },
    -- The largest rev heard from anyone, kept whether or not that document was
    -- taken. An edit made after seeing rev 9 still has to outrank rev 9.
    highestSeenRev = 0,

    peers = {},     -- [name] = { rev, hash, seenAt, rank, barkedAt }
    barks = {},     -- newest first, ours and everyone else's
    log = {},
    capture = {},
    stats = { sent = 0, received = 0, rejected = {} },

    settings = {
        enabled = true,
        outputFrame = 1,
        minimap = { hide = false },
        log = { kind = "all", source = "all" },

        -- rankIndex 0 is the guild master and a LARGER number is a LOWER rank, so
        -- both of these are ceilings, not floors.
        authorRankIndex = 1,
        barkRankIndex = 4,

        bark = {
            enabled = false,        -- off until somebody turns it on, deliberately
            intervalSec = 900,      -- seconds between arms
            quietSec = 600,         -- another officer barked this recently: stay quiet
            channel = "auto",       -- or a substring: "LookingForGroup", "Trade"
            pauseCombat = true,
            pauseInstance = true,
            confirmNewRev = true,   -- read a revision once before sending it
        },
        sync = { enabled = true, onLogin = true, registerPrefix = true },
        debug = false,
    },
}

ns.CharDefaults = {
    -- This character's own sending. In the account table, logging in on an alt
    -- would believe it had already barked.
    bark = { lastSentAt = 0, cursor = 1, confirmedRev = -1 },
    ui = { tab = 1 },
}

-- The two teams the guild actually runs, made on first login so the window has
-- something in it rather than an empty page and no hint what to do.
local function SeedTeams()
    -- Only while nothing has ever been authored. Past rev 0 the document is
    -- shared, and editing it here would move its hash without moving its rev,
    -- which is how one client quietly stops agreeing with everyone else.
    if (ns.db.doc.rev or 0) > 0 then return end
    if #ns.db.doc.teams == 0 then
        ns.db.doc.teams = {
            ns.Teams.New(1, "Team One"),
            ns.Teams.New(2, "Team Two"),
        }
    end
    if ns.db.doc.guild == "" then ns.db.doc.guild = ns.Roster.GuildName() end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("GUILD_ROSTER_UPDATE")
frame:RegisterEvent("CHAT_MSG_ADDON")

frame:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4)
    if event == "ADDON_LOADED" and arg1 == addonName then
        GuildRecruitmentDB = GuildRecruitmentDB or {}
        GuildRecruitmentCharDB = GuildRecruitmentCharDB or {}
        ns.Migrate(GuildRecruitmentDB, ns.Migrations, ns.SCHEMA)
        ns.Migrate(GuildRecruitmentCharDB, {}, ns.CHAR_SCHEMA)
        ns.ApplyDefaults(GuildRecruitmentDB, ns.Defaults)
        ns.ApplyDefaults(GuildRecruitmentCharDB, ns.CharDefaults)
        ns.db, ns.cdb = GuildRecruitmentDB, GuildRecruitmentCharDB

        -- Two teams up front, so the window has something in it rather than an
        -- empty page and no hint what to do with it. The guild's own name arrives
        -- later, on the first roster update.
        SeedTeams()

        ns.Comm.Init()
        if ns.Minimap and ns.Minimap.Init then ns.Minimap.Init() end
        ns.Bark.Restart()

        ns.Printf("v%s loaded. /gr opens the window, /gr help lists commands.", VERSION)

    elseif event == "PLAYER_LOGIN" then
        ns.Roster.Refresh(true)

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- One small "I hold rev N" a little while from now. The delay is not
        -- politeness: the guild roster arrives asynchronously and a rank we have
        -- not read yet is a rank that is allowed to do nothing.
        if not ns.loginOffered then
            ns.loginOffered = true
            ns.Comm.ScheduleLogin()
        end

    elseif event == "GUILD_ROSTER_UPDATE" then
        ns.Roster.Read()
        SeedTeams()
        if ns.UI then ns.UI.Refresh() end

    elseif event == "CHAT_MSG_ADDON" then
        ns.Comm.OnAddonMessage(arg1, arg2, arg3, arg4)
    end
end)

ns.frame = frame

--------------------------------------------------------------------------------
-- Key bindings
--------------------------------------------------------------------------------

BINDING_HEADER_GUILDRECRUITMENT = "GuildRecruitment"
BINDING_NAME_GUILDRECRUITMENT_BARK = "Send the recruitment message"
BINDING_NAME_GUILDRECRUITMENT_TOGGLE = "Open or close the GuildRecruitment window"

-- Called from Bindings.xml, which IS a hardware event, so the protected
-- SendChatMessage is allowed here where the timer that armed it would be blocked.
function GuildRecruitment_BarkNow()
    local ok, info = ns.Bark.Fire(true)
    if not ok then ns.Print("not sent: " .. tostring(info)) end
end

function GuildRecruitment_Toggle()
    ns.UI.Toggle()
end

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

local HELP = {
    { "", "open the window" },
    { "send", "send the recruitment message now" },
    { "preview", "print what would go out, and how long it is" },
    { "on | off", "turn the reminder timer on or off" },
    { "every <mins>", "how often to remind you" },
    { "quiet <mins>", "how long to stay quiet after another officer barks" },
    { "push", "send the message to the other officers" },
    { "sync", "ask the guild for a newer one" },
    { "who", "which officers have which revision" },
    { "rank author|bark <n>", "which guild rank may author, and which may send" },
    { "log [n]", "print the last n log lines" },
    { "probe", "report which client APIs this build has" },
    { "status", "one line per part of the addon" },
    { "test", "run the test suite" },
    { "enable | disable", "master switch" },
    { "out [n]", "print to ChatFrame n" },
    { "reset [doc|peers|log|all]", "restore defaults" },
    { "help", "this list" },
}

local function PrintHelp()
    ns.Print("commands:")
    for _, row in ipairs(HELP) do
        ns.Printf("  |cffffcc00/gr %s|r %s %s",
            row[1], row[1] == "" and "" or "\194\183", row[2])
    end
end

local function RequireAuthor()
    if ns.Roster.ICanAuthor() then return true end
    local _, rank = ns.Roster.Me()
    ns.Printf("your guild rank (%s) cannot change the message. "
        .. "Ask a raid leader, or /gr rank author <n> if you set the threshold wrong.",
        rank == ns.Roster.UNKNOWN_RANK and "not read yet" or tostring(rank))
    return false
end

local function HandleSlash(input)
    local raw = ns.Util.Trim(input or "")
    local cmd, rest = raw:match("^(%S*)%s*(.*)$")
    cmd = (cmd or ""):lower()

    if cmd == "" or cmd == "config" then
        ns.UI.Toggle()

    elseif cmd == "send" or cmd == "bark" then
        local ok, info = ns.Bark.Fire(true)
        ns.Print(ok and ("sent: " .. tostring(info)) or ("not sent: " .. tostring(info)))

    elseif cmd == "preview" then
        local msg, level, dropped = ns.Bark.Preview()
        if not msg then
            local _, _, _, _, reason = ns.Message.Assemble(ns.db.doc, ns.cdb.bark.cursor)
            ns.Print("nothing to send: " .. tostring(reason))
            return
        end
        ns.Printf("%s  |cff888888(%d characters, %s%s)|r", msg, #msg,
            ns.Message.LEVEL_NAME[level] or "?",
            dropped > 0 and string.format(", %d needs left out", dropped) or "")

    elseif cmd == "on" or cmd == "off" then
        ns.db.settings.bark.enabled = (cmd == "on")
        ns.Printf("the reminder timer is %s.", ns.Util.OnOff(ns.db.settings.bark.enabled))
        ns.Bark.Restart()
        ns.UI.Refresh()

    elseif cmd == "every" or cmd == "quiet" then
        local mins = tonumber(rest)
        local s = ns.db.settings.bark
        if not mins then
            ns.Printf("reminders every %d minutes, quiet for %d after another officer.",
                math.floor(s.intervalSec / 60), math.floor(s.quietSec / 60))
            return
        end
        if cmd == "every" then
            s.intervalSec = ns.Bark.ClampInterval(mins * 60)
            ns.Printf("reminding you every %d minutes.", math.floor(s.intervalSec / 60))
            ns.Bark.Restart()
        else
            s.quietSec = math.max(0, math.min(7200, math.floor(mins * 60)))
            ns.Printf("staying quiet for %d minutes after another officer barks%s.",
                math.floor(s.quietSec / 60), s.quietSec == 0 and " (off)" or "")
        end
        ns.UI.Refresh()

    elseif cmd == "push" then
        if not RequireAuthor() then return end
        local ok, reason = ns.Comm.Broadcast()
        ns.Print(ok and ("sent rev " .. ns.db.doc.rev .. " to the guild.")
            or ("not sent: " .. tostring(reason)))

    elseif cmd == "sync" then
        local ok, reason = ns.Comm.Request()
        ns.Print(ok and "asked the guild for a newer message."
            or ("not asked: " .. tostring(reason)))

    elseif cmd == "who" then
        ns.Roster.Read()
        local now = ns.Now()
        local ours = ns.db.doc.rev or 0
        ns.Printf("you hold %s", ns.Doc.Summary(ns.db.doc, now))
        local any = false
        for name, peer in pairs(ns.db.peers) do
            any = true
            local mark = "|cffffcc00"
            if (peer.rev or 0) == ours then mark = "|cff44ff44"
            elseif (peer.rev or 0) > ours then mark = "|cff88bbff" end
            ns.Printf("  %s%-14s|r rev %-4s heard %s ago", mark, name,
                tostring(peer.rev or "?"), ns.Util.Freshness(peer.seenAt, now, 0))
        end
        if not any then
            ns.Print("  nobody else has said anything yet. /gr sync asks.")
        end

    elseif cmd == "rank" then
        local which, value = rest:match("^(%a+)%s*(%-?%d*)$")
        which = (which or ""):lower()
        if which ~= "author" and which ~= "bark" then
            ns.Print("which rank? /gr rank author <n> or /gr rank bark <n>. "
                .. "0 is the guild master and larger numbers are lower ranks.")
            return
        end
        local key = which == "author" and "authorRankIndex" or "barkRankIndex"
        local n = tonumber(value)
        if not n then
            ns.Printf("%s rank is %d or better.", which, ns.db.settings[key])
            return
        end
        ns.db.settings[key] = math.max(0, math.min(20, math.floor(n)))
        ns.Printf("rank %d or better may %s.", ns.db.settings[key], which)
        ns.UI.Refresh()

    elseif cmd == "log" then
        local n = tonumber(rest) or 10
        local entries = ns.Log.Recent(n)
        if #entries == 0 then ns.Print("the log is empty.") return end
        for i = #entries, 1, -1 do
            ns.Print(ns.Log.Describe(entries[i], ns.Now()))
        end

    elseif cmd == "probe" then
        ns.Probe.Run(rest)

    elseif cmd == "status" then
        for _, line in ipairs(ns.Probe.Status()) do ns.Print(line) end

    elseif cmd == "test" then
        ns.Tests.Run()

    elseif cmd == "enable" or cmd == "disable" then
        ns.db.settings.enabled = (cmd == "enable")
        ns.Printf("GuildRecruitment is %s.", ns.Util.OnOff(ns.db.settings.enabled))
        ns.Bark.Restart()
        ns.UI.Refresh()

    elseif cmd == "out" then
        local n = tonumber(rest)
        if not n then
            ns.Printf("printing to ChatFrame %d. /gr out <n> moves it.",
                ns.db.settings.outputFrame or 1)
            return
        end
        ns.db.settings.outputFrame = math.max(1, math.min(10, math.floor(n)))
        ns.Printf("printing to ChatFrame %d.", ns.db.settings.outputFrame)

    elseif cmd == "reset" then
        local what = (rest ~= "" and rest or "peers"):lower()
        if what == "doc" then
            if not RequireAuthor() then return end
            ns.db.doc = nil
            ns.ApplyDefaults(ns.db, ns.Defaults)
            SeedTeams()
            ns.Print("the message is back to its default. Nothing was sent to anyone; "
                .. "/gr push does that.")
        elseif what == "peers" then
            ns.db.peers, ns.db.barks = {}, {}
            ns.Print("forgot every other officer's revision and every bark.")
        elseif what == "log" then
            ns.db.log, ns.db.capture = {}, {}
            ns.Print("log cleared.")
        elseif what == "all" then
            GuildRecruitmentDB, GuildRecruitmentCharDB = {}, {}
            ns.Migrate(GuildRecruitmentDB, ns.Migrations, ns.SCHEMA)
            ns.Migrate(GuildRecruitmentCharDB, {}, ns.CHAR_SCHEMA)
            ns.ApplyDefaults(GuildRecruitmentDB, ns.Defaults)
            ns.ApplyDefaults(GuildRecruitmentCharDB, ns.CharDefaults)
            ns.db, ns.cdb = GuildRecruitmentDB, GuildRecruitmentCharDB
            SeedTeams()
            ns.Print("everything reset.")
        else
            ns.Print("reset what? doc, peers, log, or all.")
            return
        end
        ns.Bark.Restart()
        ns.UI.Refresh()

    else
        PrintHelp()
    end
end

ns.slashTaken = SlashCmdList and SlashCmdList["GUILDRECRUITMENT"] ~= nil
SLASH_GUILDRECRUITMENT1 = "/gr"
SLASH_GUILDRECRUITMENT2 = "/guildrecruitment"
SlashCmdList["GUILDRECRUITMENT"] = HandleSlash
