local addonName, ns = ...

--[[
JamminWithJam: a guild soundboard. A player clicks a button (or types
/jam play <id>), the addon puts a short recognisable line in chat, and a
companion Discord bot -- a separate program, not part of this addon -- watches
this client's own chat log file for that line and plays the matching sound in
the guild's Discord voice channel.

An addon cannot open a network connection or write an arbitrary file; the
chat line is the entire interface between the two halves. Docs/JamminWithJam.md
has the setup for the bot side and DiscordBots/JamminWithJam has its source.

The plumbing -- Print, the saved-variable bootstrap, Util, Log, the test
harness, the slash dispatcher -- comes from LibICCore-1.0 in ICLibs. This file
is what is left: the version, the defaults, and the commands that are this
addon's own.
]]

local Core = LibStub("LibICCore-1.0")

local VERSION = "0.1.0"

-- Bumped when a saved-variable change needs code to read the old shape. See
-- Migrations below; ApplyDefaults handles everything that is merely additive.
local SCHEMA = 1
local CHAR_SCHEMA = 1

--------------------------------------------------------------------------------
-- Saved variables
--------------------------------------------------------------------------------

-- Nothing to upgrade yet: this addon has shipped only one shape.
local Migrations = {}
local CharMigrations = {}

local Defaults = {
    settings = {
        enabled = true,
        outputFrame = 1,
        minimap = { hide = false },
        log = { kind = "all", source = "all" },

        -- Where the trigger line is sent. GUILD needs nothing else; the bot
        -- reads it out of the chat log regardless of which of these it is, so
        -- this is about who in the raid sees the line go by, not the bridge.
        channel = "GUILD",     -- GUILD | OFFICER | PARTY | RAID | RAID_WARNING | SAY | YELL

        -- rankIndex 0 is the guild master and a LARGER number is a LOWER
        -- rank, so this is a ceiling: a sound flagged officerOnly in
        -- Sounds.lua is playable by this rank and every one above it.
        officerRankIndex = 1,
        debug = false,
    },
}

local CharDefaults = {
    -- Per character, like the button it gates: an alt should not read as
    -- still cooling down from the main's last play.
    cooldowns = {},     -- [soundID] = lastFiredAt (ns.Now())
    ui = { tab = 1 },
}

--------------------------------------------------------------------------------
-- Key bindings
--------------------------------------------------------------------------------

Core:Bindings("JAMMINWITHJAM", "JamminWithJam", {
    TOGGLE = "Open or close the JamminWithJam window",
})

function JamminWithJam_Toggle()
    ns.UI.Toggle()
end

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

local HELP = {
    { "", "open the window" },
    { "play <id>", "send the chat trigger for that sound; /jam list names them" },
    { "list", "print every sound id, and which are officer-only" },
    { "log [n]", "print the last n log lines" },
    { "probe", "report which client APIs this build has" },
    { "status", "one line per part of the addon" },
    { "test", "run the test suite" },
    { "enable | disable", "master switch" },
    { "out [n]", "print to ChatFrame n" },
    { "reset [settings|log|all]", "restore defaults" },
    { "version", "addon and library versions" },
    { "help", "this list" },
}

-- Only what the library does not already do. help, log, probe, status, test,
-- enable, disable, out, reset, scale and version are built in; a key here
-- overrides one.
local COMMANDS = {}

COMMANDS.config = function() ns.UI.Toggle() end

COMMANDS.play = function(rest)
    local id = ns.Util.Trim(rest)
    if id == "" then
        ns.Print("which sound? /jam list names them.")
        return
    end
    local ok, info = ns.Sounds.Fire(id)
    ns.Print(ok and ("sent: " .. tostring(info)) or ("not sent: " .. tostring(info)))
    ns.UI.Refresh()
end

COMMANDS.list = function()
    for _, sound in ipairs(ns.Sounds.List()) do
        ns.Printf("  %-16s %s%s", sound.id, sound.label,
            sound.officerOnly and " |cffffcc00(officers)|r" or "")
    end
end

--------------------------------------------------------------------------------
-- Attach
--------------------------------------------------------------------------------

Core:Attach(ns, {
    name = addonName,
    prefix = "JamminWithJam",
    version = VERSION,
    db = "JamminWithJamDB",
    cdb = "JamminWithJamCharDB",
    defaults = Defaults,
    charDefaults = CharDefaults,
    schema = SCHEMA,
    charSchema = CHAR_SCHEMA,
    migrations = Migrations,
    charMigrations = CharMigrations,
    slash = { "/jam", "/jamminwithjam" },
    slashKey = "JAMMINWITHJAM",
    help = HELP,
    commands = COMMANDS,
    loadedHint = "/jam opens the soundboard, /jam help lists commands.",
    -- One colour per kind everywhere: green played, amber did not. Sounds.lua
    -- is the only thing that writes these; the Log page's filter buttons
    -- have to name the same two kinds, which is what UI_Log.lua's KINDS does.
    logKinds = {
        sent = "|cff44ff44",
        skipped = "|cffffcc00",
    },

    onLoad = function()
        if ns.Minimap and ns.Minimap.Init then ns.Minimap.Init() end
        local ask = (C_GuildInfo and C_GuildInfo.GuildRoster) or _G.GuildRoster
        if type(ask) == "function" then pcall(ask) end
    end,
})

--------------------------------------------------------------------------------
-- Events that are this addon's own
--------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("GUILD_ROSTER_UPDATE")
frame:SetScript("OnEvent", function(_, event)
    if event == "GUILD_ROSTER_UPDATE" then
        -- Whether a sound is officer-only reads this character's rank live off
        -- the roster, so a page left open should catch up once it arrives.
        if ns.UI then ns.UI.Refresh() end
    end
end)
