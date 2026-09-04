local addonName, ns = ...

--[[
ICTemplate: the worked example. Copy this folder to start a new addon, or let
scripts/new-addon.ps1 do it for you.

Exactly three tokens are all a rename touches, and the script rewrites these three:

    ICTemplate    the .toc filename and ## Title, the ## IconTexture path,
                  ICTemplateDB and ICTemplateCharDB, the chat prefix, the window frame
                  name, the LibDataBroker object name, the two globals a key binding
                  calls, and ICTemplate.tga
    ICTEMPLATE    the slash key, the BINDING_* globals, and the <Binding name=...>
                  attributes in Bindings.xml
    /ictpl        the slash command itself, and every mention of it in help text

Everything else is namespaced. Every file opens with `local addonName, ns = ...`, so no
other file in the addon has to know what the addon is called.

The plumbing -- Print, the saved-variable bootstrap, Util, Log, the test harness, the
slash dispatcher -- comes from LibICCore-1.0 in ICLibs. This file is what is left: the
version, the defaults, the migrations, and the commands that are this addon's own.
]]

local Core = LibStub("LibICCore-1.0")

local VERSION = "1.1.0"

-- Bumped when a saved-variable change needs code to read the old shape. See
-- Migrations below; ApplyDefaults handles everything that is merely additive.
local SCHEMA = 2
local CHAR_SCHEMA = 1

--------------------------------------------------------------------------------
-- Saved variables
--------------------------------------------------------------------------------

--[[
The schema changes ApplyDefaults cannot make on its own: anything that has to READ
the old shape before the new one exists. Keyed by the schema each step upgrades
FROM, so Migrations[1] takes a schema-1 table to schema 2.
]]
local Migrations = {
    -- The example, shipped in 1.0.0 so a copier can see the shape. `pulse.every`
    -- became `pulse.intervalSec` once it stopped being obvious what unit it was in.
    [1] = function(db)
        local p = db.settings and db.settings.pulse
        if p and p.every ~= nil then
            p.intervalSec = p.intervalSec or p.every
            p.every = nil
        end
    end,
}

local Defaults = {
    settings = {
        enabled = true,
        outputFrame = 1,
        minimap = { hide = false },
        -- Filters are saved, never session state. Kept on a Lua table one resets
        -- on reload, and a list that comes back empty reads as lost data.
        log = { kind = "all", source = "all" },
        gallery = { demo = "button" },
        tablePage = { filter = "all", sort = "name", desc = false },
        pulse = {
            enabled = false,
            intervalSec = 60,           -- seconds between arms
            perLine = 3,                -- items packed into one message
            -- EMOTE, not a public channel: nobody running the template should be
            -- able to spam Trade by accident. It is still a protected send, so it
            -- exercises the same hardware-event rule a real barker lives under.
            channel = "EMOTE",
            template = "waves. ICTemplate demo: {items}",
            pauseCombat = true,
        },
        debug = false,
    },
}

local CharDefaults = {
    -- This character's rotation. In the account table, logging in on an alt would
    -- believe it had already sent.
    pulse = { cursor = 1, lastSentAt = 0 },
    ui = { tab = 1 },
}

--------------------------------------------------------------------------------
-- Key bindings
--------------------------------------------------------------------------------

Core:Bindings("ICTEMPLATE", "ICTemplate", {
    PULSE = "Send the armed pulse",
    TOGGLE = "Open or close the ICTemplate window",
})

-- Called from Bindings.xml, which IS a hardware event, so a protected
-- SendChatMessage is allowed here where the timer that armed it would be blocked.
function ICTemplate_PulseNow()
    local ok, info = ns.Pulse.Fire(true)
    if not ok then ns.Print("pulse skipped: " .. tostring(info)) end
end

function ICTemplate_Toggle()
    ns.UI.Toggle()
end

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

-- A row with `needs` is only offered when that module is loaded, so a copy made
-- with new-addon.ps1 -Minimal does not advertise commands it no longer has.
local HELP = {
    { "", "open the window" },
    { "demo <id>", "show one demo; /ictpl list names them all", needs = "Demos" },
    { "list", "print every demo id", needs = "Demos" },
    { "pulse [secs]", "turn the pulse timer on or off, or set its interval" },
    { "send", "send the pulse now" },
    { "preview", "print what the next pulse would say" },
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

-- Only what the library does not already do. help, log, probe, status, test, enable,
-- disable, out, reset, scale and version are built in; a key here overrides one.
local COMMANDS = {}

COMMANDS.config = function() ns.UI.Toggle() end

local function DemoCommand(rest, cmd)
    -- new-addon.ps1 -Minimal leaves the gallery behind, so these two have to
    -- say so rather than error on a nil table.
    if not ns.Demos then
        ns.Print("this copy has no gallery. /ictpl help lists what it does have.")
        return
    end
    if cmd == "list" then
        for _, group in ipairs(ns.Demos.Groups()) do
            ns.Printf("|cffffcc00%s|r", group.name)
            for _, d in ipairs(group.demos) do
                ns.Printf("  %-16s %s", d.id, d.title)
            end
        end
        return
    end
    local demo = ns.Demos.ById(rest)
    if not demo then
        ns.Printf("no demo called %q. /ictpl list names them all.", rest)
        return
    end
    ns.db.settings.gallery.demo = demo.id
    ns.UI.Show("Gallery")
end
COMMANDS.demo, COMMANDS.list = DemoCommand, DemoCommand

COMMANDS.pulse = function(rest)
    local s = ns.db.settings.pulse
    local secs = tonumber(rest)
    if secs then
        s.intervalSec = ns.Pulse.ClampInterval(secs)
        if s.intervalSec ~= secs then
            ns.Printf("interval held to %ds; %ds is outside what this is for.",
                s.intervalSec, secs)
        end
        ns.Printf("pulse every %ds.", s.intervalSec)
    else
        s.enabled = not s.enabled
        ns.Printf("pulse timer %s.", ns.Util.OnOff(s.enabled))
    end
    ns.Pulse.Restart()
    ns.UI.Refresh()
end

COMMANDS.send = function()
    local ok, info = ns.Pulse.Fire(true)
    ns.Print(ok and ("sent: " .. tostring(info)) or ("skipped: " .. tostring(info)))
end

COMMANDS.preview = function()
    local msg = ns.Pulse.Preview()
    ns.Print(msg and ("next pulse: " .. msg) or "nothing to send.")
end

--------------------------------------------------------------------------------
-- Attach
--------------------------------------------------------------------------------

Core:Attach(ns, {
    name = addonName,
    prefix = "ICTemplate",
    version = VERSION,
    db = "ICTemplateDB",
    cdb = "ICTemplateCharDB",
    defaults = Defaults,
    charDefaults = CharDefaults,
    schema = SCHEMA,
    charSchema = CHAR_SCHEMA,
    migrations = Migrations,
    slash = { "/ictpl", "/ictemplate" },
    slashKey = "ICTEMPLATE",
    help = HELP,
    commands = COMMANDS,
    loadedHint = "/ictpl opens the gallery, /ictpl help lists commands.",

    onLoad = function()
        -- Compile every demo now rather than on the first click, so a broken one
        -- is a line in the log at load instead of a blank pane later.
        if ns.Demos then
            local ok, failed = ns.Demos.Verify()
            if failed > 0 then
                ns.Printf("|cffff4444%d of %d demos do not compile.|r /ictpl log for detail.",
                    failed, ok + failed)
            end
        end
        if ns.Minimap and ns.Minimap.Init then ns.Minimap.Init() end
        if ns.cdb.pulse and ns.db.settings.pulse.enabled and ns.Enabled() then
            ns.Pulse.Start()
        end
    end,
    onToggle = function() ns.Pulse.Restart() end,
    onReset = function() ns.Pulse.Restart() end,
})

--------------------------------------------------------------------------------
-- Events that are this addon's own
--------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        -- Combat is a reason a pulse cannot fire; the gate reads it, but the timer
        -- should stop nagging about it in the meantime.
        if ns.Pulse then ns.Pulse.pending = false end
    end
end)
