local addonName, ns = ...

--[[
ICTemplate: the worked example. Copy this folder to start a new addon, or let
scripts/new-addon.ps1 do it for you.

Exactly three tokens are all a rename touches, and the script rewrites these three:

    ICTemplate    the .toc filename and ## Title, the ## IconTexture path,
                  ICTemplateDB and ICTemplateCharDB, the chat prefix in ns.Print,
                  the window frame name, the LibDataBroker object name, the two
                  globals a key binding calls, and ICTemplate.tga
    ICTEMPLATE    SLASH_ICTEMPLATE1/2, SlashCmdList["ICTEMPLATE"], the BINDING_*
                  globals here, and the <Binding name=...> attributes in Bindings.xml
    /ictpl        the slash command itself, and every mention of it in help text

Everything else is namespaced. Every file opens with `local addonName, ns = ...`,
so no other file in the addon has to know what the addon is called.
]]

local VERSION = "1.0.1"
ns.VERSION = VERSION

-- Bumped when a saved-variable change needs code to read the old shape. See
-- ns.Migrations below; ApplyDefaults handles everything that is merely additive.
ns.SCHEMA = 2
ns.CHAR_SCHEMA = 1

--------------------------------------------------------------------------------
-- Output
--------------------------------------------------------------------------------

-- Everything the addon says is prefixed, so a player can tell who is talking.
-- settings.outputFrame moves it off the main chat frame; /ictpl out sets it.
function ns.Print(msg)
    local frame = DEFAULT_CHAT_FRAME
    local idx = ns.db and ns.db.settings and ns.db.settings.outputFrame
    if idx and idx > 1 then
        local f = _G["ChatFrame" .. idx]
        if f and f.AddMessage then frame = f end
    end
    frame:AddMessage("|cff33ff99ICTemplate|r: " .. tostring(msg))
end

function ns.Printf(fmt, ...)
    ns.Print(string.format(fmt, ...))
end

-- False means the addon takes no action of its own. Reading its window still works.
function ns.Enabled()
    return not ns.db or ns.db.settings.enabled ~= false
end

-- One clock for the whole addon, so anything pure can be handed a `now` in a test
-- instead of reading the real one.
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

-- Fills in what is missing and touches nothing already there, a stored `false`
-- included. Run on every load, so a field added in a later version simply appears
-- the first time anything asks for it and needs no migration of its own.
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

--[[
The schema changes ApplyDefaults cannot make on its own: anything that has to READ
the old shape before the new one exists. Keyed by the schema each step upgrades
FROM, so ns.Migrations[1] takes a schema-1 table to schema 2.

Steps run BEFORE ApplyDefaults, always. One that runs afterwards cannot tell a
field the player never had from one the defaults have just invented.
]]
ns.Migrations = {
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

-- Pure apart from what the steps themselves do. Returns how many ran.
-- An empty table is a fresh install and starts at the head, so nothing runs on it.
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
    log = {},
    capture = {},
}

ns.CharDefaults = {
    -- This character's rotation. In the account table, logging in on an alt would
    -- believe it had already sent.
    pulse = { cursor = 1, lastSentAt = 0 },
    ui = { tab = 1 },
}

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        ICTemplateDB = ICTemplateDB or {}
        ICTemplateCharDB = ICTemplateCharDB or {}

        -- Migrate, then default, then publish. Never the other way round.
        local ran = ns.Migrate(ICTemplateDB, ns.Migrations, ns.SCHEMA)
        ns.Migrate(ICTemplateCharDB, {}, ns.CHAR_SCHEMA)
        ns.ApplyDefaults(ICTemplateDB, ns.Defaults)
        ns.ApplyDefaults(ICTemplateCharDB, ns.CharDefaults)
        ns.db, ns.cdb = ICTemplateDB, ICTemplateCharDB
        if ran > 0 then
            ns.Printf("upgraded saved settings through %d schema %s.",
                ran, ran == 1 and "step" or "steps")
        end

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

        ns.Printf("v%s loaded. /ictpl opens the gallery, /ictpl help lists commands.", VERSION)

    elseif event == "PLAYER_LOGIN" then
        -- A copy of this template renamed but left on the same slash key is a
        -- confusing afternoon. Say so once rather than letting one silently win.
        if ns.slashTaken then
            ns.Print("|cffff9900another addon already registered the ICTEMPLATE slash key.|r "
                .. "One of you owns /ictpl now; rename the other's third token.")
        end

    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Combat is a reason a pulse cannot fire; the gate reads it, but the timer
        -- should stop nagging about it in the meantime.
        if ns.Pulse then ns.Pulse.pending = false end
    end
end)

ns.frame = frame

--------------------------------------------------------------------------------
-- Key bindings
--------------------------------------------------------------------------------

BINDING_HEADER_ICTEMPLATE = "ICTemplate"
BINDING_NAME_ICTEMPLATE_PULSE = "Send the armed pulse"
BINDING_NAME_ICTEMPLATE_TOGGLE = "Open or close the ICTemplate window"

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
    { "help", "this list" },
}

local function PrintHelp()
    ns.Print("commands:")
    for _, row in ipairs(HELP) do
        if not row.needs or ns[row.needs] then
            ns.Printf("  |cffffcc00/ictpl %s|r %s %s",
                row[1], row[1] == "" and "" or "\194\183", row[2])
        end
    end
end

local function HandleSlash(input)
    local raw = ns.Util.Trim(input or "")
    local cmd, rest = raw:match("^(%S*)%s*(.*)$")
    cmd = (cmd or ""):lower()

    if cmd == "" or cmd == "config" then
        ns.UI.Toggle()

    elseif cmd == "demo" or cmd == "list" then
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

    elseif cmd == "pulse" then
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

    elseif cmd == "send" then
        local ok, info = ns.Pulse.Fire(true)
        ns.Print(ok and ("sent: " .. tostring(info)) or ("skipped: " .. tostring(info)))

    elseif cmd == "preview" then
        local msg = ns.Pulse.Preview()
        ns.Print(msg and ("next pulse: " .. msg) or "nothing to send.")

    elseif cmd == "log" then
        local n = tonumber(rest) or 10
        local entries = ns.Log.Recent(n)
        if #entries == 0 then ns.Print("the log is empty.") return end
        for i = #entries, 1, -1 do
            ns.Print(ns.Log.Describe(entries[i], ns.Now()))
        end

    elseif cmd == "probe" then
        ns.Probe.Run()

    elseif cmd == "status" then
        for _, line in ipairs(ns.Probe.Status()) do ns.Print(line) end

    elseif cmd == "test" then
        ns.Tests.Run()

    elseif cmd == "enable" or cmd == "disable" then
        ns.db.settings.enabled = (cmd == "enable")
        ns.Printf("ICTemplate is %s.", ns.Util.OnOff(ns.db.settings.enabled))
        ns.Pulse.Restart()
        ns.UI.Refresh()

    elseif cmd == "out" then
        local n = tonumber(rest)
        if not n then
            ns.Printf("printing to ChatFrame %d. /ictpl out <n> moves it.",
                ns.db.settings.outputFrame or 1)
            return
        end
        ns.db.settings.outputFrame = math.max(1, math.min(10, math.floor(n)))
        ns.Printf("printing to ChatFrame %d.", ns.db.settings.outputFrame)

    elseif cmd == "reset" then
        local what = (rest ~= "" and rest or "settings"):lower()
        if what == "log" then
            ns.db.log, ns.db.capture = {}, {}
            ns.Print("log cleared.")
        elseif what == "settings" then
            ns.db.settings = nil
            ns.ApplyDefaults(ns.db, ns.Defaults)
            ns.Print("settings restored to defaults.")
        elseif what == "all" then
            ICTemplateDB, ICTemplateCharDB = {}, {}
            ns.Migrate(ICTemplateDB, ns.Migrations, ns.SCHEMA)
            ns.Migrate(ICTemplateCharDB, {}, ns.CHAR_SCHEMA)
            ns.ApplyDefaults(ICTemplateDB, ns.Defaults)
            ns.ApplyDefaults(ICTemplateCharDB, ns.CharDefaults)
            ns.db, ns.cdb = ICTemplateDB, ICTemplateCharDB
            ns.Print("everything reset.")
        else
            ns.Print("reset what? settings, log, or all.")
            return
        end
        ns.Pulse.Restart()
        ns.UI.Refresh()

    else
        PrintHelp()
    end
end

ns.slashTaken = SlashCmdList and SlashCmdList["ICTEMPLATE"] ~= nil
SLASH_ICTEMPLATE1 = "/ictpl"
SLASH_ICTEMPLATE2 = "/ictemplate"
SlashCmdList["ICTEMPLATE"] = HandleSlash
