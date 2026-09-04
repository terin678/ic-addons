local addonName, ns = ...

--[[
GuildRecruitment. Built from ICTemplate; see Docs/ICTemplate.md for the shape.

The guild runs two raid teams and every raid officer recruits for both. Before
this, each officer typed their own line into a channel, nobody knew who had
posted last, and the wording drifted. So: raid leaders author one message, every
officer's copy converges on it, and a log of who barked when means the second
officer does not add a second line four minutes after the first.

The plumbing -- Print, the saved-variable bootstrap, Util, Log, the test harness, the
slash dispatcher -- is LibICCore's. This file is the version, the defaults, the
commands that are this addon's own, and the events it listens to.
]]

local Core = LibStub("LibICCore-1.0")

local VERSION = "0.3.0"
local SCHEMA = 1
local CHAR_SCHEMA = 1

--------------------------------------------------------------------------------
-- Saved variables
--------------------------------------------------------------------------------

-- Keyed by the schema each step upgrades FROM. Run before ApplyDefaults, always.
local Migrations = {}

local Defaults = {
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
    stats = { sent = 0, received = 0, rejected = {} },

    settings = {
        enabled = true,
        outputFrame = 1,
        windowScale = 1,
        minimap = { hide = false },
        log = { kind = "all", source = "all" },

        -- rankIndex 0 is the guild master and a LARGER number is a LOWER rank, so
        -- both of these are ceilings, not floors.
        -- Impulse Control's ranks, in the game's 0-based numbering: 0 is the guild
        -- master, 1 and 2 are the two raid teams' leaders. The guild window shows
        -- those as 1, 2 and 3.
        authorRankIndex = 2,
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

local CharDefaults = {
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
ns.SeedTeams = SeedTeams

--------------------------------------------------------------------------------
-- Key bindings
--------------------------------------------------------------------------------

Core:Bindings("GUILDRECRUITMENT", "GuildRecruitment", {
    BARK = "Send the recruitment message",
    TOGGLE = "Open or close the GuildRecruitment window",
})

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
    { "scale [percent]", "window size, 50 to 125, or drag its bottom-right corner" },
    { "reset [doc|peers|log|all]", "restore defaults" },
    { "version", "addon and library versions" },
    { "help", "this list" },
}

local function RequireAuthor()
    if ns.Roster.ICanAuthor() then return true end
    local _, rank = ns.Roster.Me()
    ns.Printf("your guild rank (%s) cannot change the message. "
        .. "Ask a raid leader, or /gr rank author <n> if you set the threshold wrong.",
        rank == ns.Roster.UNKNOWN_RANK and "not read yet" or tostring(rank))
    return false
end
ns.RequireAuthor = RequireAuthor

-- Only what the library does not already do. help, log, probe, status, test, enable,
-- disable, out, scale and version are built in; a key here overrides one.
local COMMANDS = {}

COMMANDS.config = function() ns.UI.Toggle() end

local function Send()
    local ok, info = ns.Bark.Fire(true)
    ns.Print(ok and ("sent: " .. tostring(info)) or ("not sent: " .. tostring(info)))
end
COMMANDS.send, COMMANDS.bark = Send, Send

COMMANDS.preview = function()
    local msg, level, dropped = ns.Bark.Preview()
    if not msg then
        local _, _, _, _, reason = ns.Message.Assemble(ns.db.doc, ns.cdb.bark.cursor)
        ns.Print("nothing to send: " .. tostring(reason))
        return
    end
    ns.Printf("%s  |cff888888(%d characters, %s%s)|r", msg, #msg,
        ns.Message.LEVEL_NAME[level] or "?",
        dropped > 0 and string.format(", %d needs left out", dropped) or "")
end

local function Reminder(_, cmd)
    ns.db.settings.bark.enabled = (cmd == "on")
    ns.Printf("the reminder timer is %s.", ns.Util.OnOff(ns.db.settings.bark.enabled))
    ns.Bark.Restart()
    ns.UI.Refresh()
end
COMMANDS.on, COMMANDS.off = Reminder, Reminder

local function Timing(rest, cmd)
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
end
COMMANDS.every, COMMANDS.quiet = Timing, Timing

COMMANDS.push = function()
    if not RequireAuthor() then return end
    local ok, reason = ns.Comm.Broadcast()
    ns.Print(ok and ("sent rev " .. ns.db.doc.rev .. " to the guild.")
        or ("not sent: " .. tostring(reason)))
end

COMMANDS.sync = function()
    local ok, reason = ns.Comm.Request()
    ns.Print(ok and "asked the guild for a newer message."
        or ("not asked: " .. tostring(reason)))
end

COMMANDS.who = function()
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
end

COMMANDS.rank = function(rest)
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
end

-- Over the library's: the document is guild property, so resetting it is gated on
-- being allowed to author, and "peers" forgets the barks too.
COMMANDS.reset = function(rest)
    local what = (rest ~= "" and rest or "peers"):lower()
    if what == "doc" then
        if not RequireAuthor() then return end
        ns.Reset("doc")
        ns.Print("the message is back to its default. Nothing was sent to anyone; "
            .. "/gr push does that.")
    elseif what == "peers" then
        ns.db.peers, ns.db.barks = {}, {}
        ns.Print("forgot every other officer's revision and every bark.")
    elseif what == "log" or what == "all" then
        local _, msg = ns.Reset(what)
        ns.Print(msg)
    else
        ns.Print("reset what? doc, peers, log, or all.")
        return
    end
    ns.Bark.Restart()
    ns.UI.Refresh()
end

--------------------------------------------------------------------------------
-- Attach
--------------------------------------------------------------------------------

Core:Attach(ns, {
    name = addonName,
    prefix = "GuildRecruitment",
    version = VERSION,
    db = "GuildRecruitmentDB",
    cdb = "GuildRecruitmentCharDB",
    defaults = Defaults,
    charDefaults = CharDefaults,
    schema = SCHEMA,
    charSchema = CHAR_SCHEMA,
    migrations = Migrations,
    slash = { "/gr", "/guildrecruitment" },
    slashKey = "GUILDRECRUITMENT",
    help = HELP,
    commands = COMMANDS,
    loadedHint = "/gr opens the window, /gr help lists commands.",
    -- One colour per kind everywhere: green happened, amber waiting, red failed.
    logKinds = {
        sent = "|cff44ff44",        -- we put a line in a channel
        armed = "|cffffcc00",       -- the timer says it is time
        skipped = "|cff888888",     -- we could have and did not, with a reason
        remote = "|cff88bbff",      -- another officer did something
        doc = "|cffdf9c33",         -- the message itself changed
    },

    onLoad = function()
        -- What came back off disk, before anything else can touch it. A document that
        -- is whole here and empty later was lost while running; one that is already
        -- empty was never saved. The library's own line says whether the file loaded.
        local teams, needs = #ns.db.doc.teams, 0
        for _, team in ipairs(ns.db.doc.teams) do needs = needs + #(team.needs or {}) end
        ns.Log.Add("info", "Core", string.format("rev %d, %s, %s, scale %d%%",
            ns.db.doc.rev or 0,
            ns.Util.Plural(teams, teams .. " team"),
            ns.Util.Plural(needs, needs .. " need"),
            (ns.db.settings.windowScale or 1) * 100 + 0.5))
        if teams == 0 and (ns.db.doc.rev or 0) > 0 then
            ns.Print("|cffffcc00the saved message has a revision but no teams,|r which "
                .. "should not happen. /gr log has the detail.")
        end

        SeedTeams()
        ns.Comm.Init()
        if ns.Minimap and ns.Minimap.Init then ns.Minimap.Init() end
        ns.Bark.Restart()
    end,
    onToggle = function() ns.Bark.Restart() end,
    onReset = function(what)
        if what == "doc" or what == "all" then SeedTeams() end
    end,
})

--------------------------------------------------------------------------------
-- Events that are this addon's own
--------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("GUILD_ROSTER_UPDATE")
frame:RegisterEvent("CHAT_MSG_ADDON")

frame:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4)
    if event == "PLAYER_LOGIN" then
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
