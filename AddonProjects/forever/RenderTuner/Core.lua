local addonName, ns = ...

--[[
RenderTuner: the client's rendering knobs in one place. Upscaling presets, a control for
every graphics console variable worth having, and a way to compare the saved settings
with the ones being tried.

The client has no DLSS, XeSS or FSR 2 and up. What it has is a render scale with an
FSR 1.0 upscale and a sharpening pass, image and multisample anti-aliasing, low latency
modes, HDR and colour correction, all driven by console variables. This addon sets those
and nothing else.

There is one source of truth, the console variables as the client has them now. The
addon keeps two copies to go back to and none that could disagree with the game:

    saved      what Save last recorded: side A of a comparison, and where Revert returns
    original   what was live the first time the addon ran: the way back to before it

    Catalog.lua   the knobs, as data
    Model.lua     every decision about values, pure                    (LibICUtil)
    Apply.lua     the only file that reads or sets a console variable  (LibICEnv)
    Panel.lua     the floating panel: every knob as a control          (LibICWidgets, LibICTheme)
    Launcher.lua  the way in from the addon list beside the minimap    (LibICWidgets)
    Probe.lua     what the client was asked while this was being built (LibICEnv)
    Core.lua      this file: saved tables, commands, login             (LibICStore, LibICConsole)
    Tests.lua     the cases                                            (LibICTest)

Nothing here runs while the game is idle: the addon acts on a command, a click or a
drag, and at login.
]]

local VERSION = "0.4.0"

local Util = LibStub("LibICUtil-1.0")
local Test = LibStub("LibICTest-1.0")
local Env = LibStub("LibICEnv-1.0")
local Store = LibStub("LibICStore-1.0")
local Console = LibStub("LibICConsole-1.0")

local out = Console.New("RenderTuner", {
    debug = function() return ns.db ~= nil and ns.db.settings.debug == true end,
})

ns.VERSION = VERSION
ns.Print, ns.Printf, ns.Debug = out.Print, out.Printf, out.Debug
ns.Tests = Test.New({ print = out.Print })

--------------------------------------------------------------------------------
-- Pure: what it says at login
--------------------------------------------------------------------------------

function ns.LoadLines(version, status)
    return { string.format("v%s loaded: %s /tuner opens the panel.", version, status) }
end

--------------------------------------------------------------------------------
-- Saved tables
--------------------------------------------------------------------------------

Store.Register(addonName, {
    account = "RenderTunerDB",
    character = "RenderTunerCharDB",
    schema = 1,
    charSchema = 1,
    defaults = {
        settings = {
            debug = false,
            -- The preset that "on" returns to.
            upscale = { last = "quality" },
            -- The warning about experimental settings is shown before the panel, once a
            -- session, until its box is ticked.
            skipWarning = false,
        },
    },
    -- Where the panel sits, and the group it was last showing.
    -- compact: only the title bar, the two preset rows and the actions are shown.
    -- advanced: the Advanced cluster of groups is unfolded.
    charDefaults = { panel = { group = "upscale", compact = false, advanced = false } },
    onReady = Env.Wrap("RenderTuner saved variables", function(db, cdb, info)
        ns.db, ns.cdb, ns.loadInfo = db, cdb, info
    end),
})

--------------------------------------------------------------------------------
-- Doing things: the commands and, later, the panel both come here
--------------------------------------------------------------------------------

local function Ready()
    if ns.db and ns.db.saved then return true end
    out.Print("the settings are not in hand yet.")
    return false
end

-- Records the live values as the two sets to go back to, the first time; after that,
-- only adds knobs those sets have not seen.
function ns.Baseline()
    local live = ns.Apply.Live()
    if not ns.db.original then ns.db.original = Util.DeepCopy(live) else ns.Model.Fill(ns.db.original, live) end
    if not ns.db.saved then ns.db.saved = Util.DeepCopy(live) else ns.Model.Fill(ns.db.saved, live) end
end

function ns.Changes()
    return ns.Model.Diff(ns.db.saved, ns.Apply.Live(), ns.Apply.Knobs())
end

function ns.StatusText()
    local live = ns.Apply.Live()
    local knob = ns.Model.Find(ns.Apply.Knobs(), "RenderScale")
    local scale = live.RenderScale
    local preset = ns.Model.PresetOf(scale, ns.Catalog.PRESETS, ns.Apply.Limits())
    return ns.Model.Status(knob and ns.Model.Format(knob, scale) or "?", preset, #ns.Changes())
end

local function RefreshPanel()
    if ns.Panel then ns.Panel.Refresh() end
end

-- Turns the live settings into `target`. Says what it did under the name `what`, unless
-- `quiet`: a slider being dragged would fill the chat. A refusal is always said.
function ns.ApplyTarget(target, what, quiet)
    local plan = ns.Model.Plan(target, ns.Apply.Live(), ns.Apply.Knobs())
    if #plan == 0 then
        if not quiet then out.Printf("%s: nothing to change.", what) end
        return 0
    end
    local done, refused = ns.Apply.Run(plan)
    if not quiet then out.Printf("%s: %d %s set.", what, done, Util.Plural(done, "variable")) end
    if #refused > 0 then
        out.Print("|cffff4444the client refused:|r " .. table.concat(refused, ", "))
    end
    local need = ns.Model.Restart(plan)
    if need then
        ns.pendingRestart = need
        if not quiet then out.Print(ns.Model.RestartHint(need)) end
    end
    RefreshPanel()
    return done
end

function ns.ApplyPreset(preset)
    local target = ns.Model.Preset(preset, ns.Apply.Limits(), ns.Catalog.FSR)
    if preset.scale < 1 then ns.db.settings.upscale.last = preset.key end
    ns.ApplyTarget(target, preset.label)
end

-- One knob, from a control in the panel. The value is the variable's own, not the
-- reversed one a slider may show.
function ns.SetKnob(knob, value)
    local wanted = ns.Model.Clamp(knob, value)
    if wanted == nil then return end
    local refused = ns.Apply.Unsupported(knob.cvar, wanted)
    if refused then
        out.Printf("%s cannot be %s here: %s", knob.label, ns.Model.Format(knob, wanted), refused)
        RefreshPanel()
        return
    end
    -- The overall quality level carries the levels beneath it, as it does on the game's
    -- own graphics page.
    local target = knob.rank == 1 and ns.Apply.LevelValues(wanted, knob.raid) or {}
    target[knob.cvar] = wanted
    ns.ApplyTarget(target, knob.label, true)
end

-- Whether the client will not take a value, for the extras: ray traced shadows on a card
-- without ray tracing, or a multisample level the card lacks.
local function Refused(cvar, value)
    return ns.Apply.Unsupported(cvar, value)
end
ns.Refused = Refused

-- What a preset's extras are judged by: the client's refusals, and the values it took but
-- did not keep (it caps a light distance of its own, and holds back multisampling until the
-- graphics restart). Those are noted when a preset is applied, and not held against it.
function ns.Excused(cvar, value)
    local unkept = ns.db and ns.db.settings.unkept
    return Refused(cvar, value) or (unkept ~= nil and unkept[cvar] == value) or nil
end

-- The preset with extras that the settings are holding now, or nil.
local function HeldExtras(live)
    for _, other in ipairs(ns.Catalog.LEVELS) do
        if other.also and ns.Model.AlsoHeld(other, live, ns.Excused) then return other end
    end
end

-- An overall quality preset: the game's master level, and the levels beneath it.
--
-- A preset with extras (Extreme) sets the level first, so the client works out the levels
-- beneath it, and then the extras on top, noting what each was before in
-- settings.beforeExtras. Any other preset, chosen while the extras are what Extreme left
-- them at, puts them back as they were noted, or at the client's defaults for any that were
-- not, and then sets its level. A player's own tuning, which makes the extras differ from
-- Extreme, is left alone: choosing High does not switch off their HDR.
function ns.ApplyLevel(preset)
    local knob = ns.Model.Find(ns.Apply.Knobs(), "graphicsQuality")
    if not knob then
        out.Print("this client has no overall quality level.")
        return
    end
    local live = ns.Apply.Live()
    local held = HeldExtras(live)
    local line = string.format("%s quality: level %s, and the levels beneath it", preset.label,
        ns.Model.Format(knob, preset.level))

    if preset.also then
        local wanted, left = ns.Model.AlsoWanted(preset, Refused)
        if not held then
            local before = {}
            for cvar in pairs(wanted) do before[cvar] = live[cvar] end
            ns.db.settings.beforeExtras = before
        end
        ns.SetKnob(knob, preset.level)
        ns.ApplyTarget(wanted, preset.label .. " extras", true)
        local count = 0
        for _ in pairs(wanted) do count = count + 1 end
        line = line .. string.format("; and %d more %s turned all the way up", count, Util.Plural(count, "setting"))
        if #left > 0 then
            local labels = {}
            for _, cvar in ipairs(left) do
                local extra = ns.Model.Find(ns.Apply.Knobs(), cvar)
                labels[#labels + 1] = extra and extra.label or cvar
            end
            line = line .. "; this machine cannot do: " .. table.concat(labels, ", ")
        end
        -- What the client did not keep, said at once: the client may round or reset a value.
        local after, odd = ns.Apply.Live(), {}
        if after.graphicsQuality ~= nil and not ns.Model.Same(after.graphicsQuality, preset.level) then
            odd[#odd + 1] = "graphicsQuality is " .. tostring(after.graphicsQuality)
        end
        for cvar, want in pairs(wanted) do
            if after[cvar] ~= nil and not ns.Model.Same(want, after[cvar]) then
                odd[#odd + 1] = string.format("%s is %s, not %s", cvar, tostring(after[cvar]), tostring(want))
            end
        end
        table.sort(odd)
        local unkept = {}
        for cvar, want in pairs(wanted) do
            if after[cvar] ~= nil and not ns.Model.Same(want, after[cvar]) then unkept[cvar] = want end
        end
        ns.db.settings.unkept = next(unkept) and unkept or nil
        if #odd > 0 then
            line = line .. "; |cffff8040the client did not keep: " .. table.concat(odd, "; ") .. "|r"
        end
    else
        if held then
            local back = {}
            local defaults = ns.Apply.Defaults()
            local before = ns.db.settings.beforeExtras or {}
            for cvar in pairs(held.also) do
                if before[cvar] ~= nil then back[cvar] = before[cvar] else back[cvar] = defaults[cvar] end
            end
            ns.db.settings.beforeExtras = nil
            ns.ApplyTarget(back, held.label .. " extras", true)
            line = line .. string.format("; and %s put back as they were", held.label)
        end
        ns.SetKnob(knob, preset.level)
    end
    out.Print(line .. ".")
end

-- Puts a list of knobs back to their saved values: one group, or what a search found.
function ns.RevertKnobs(knobs, what)
    local target = {}
    for _, knob in ipairs(knobs) do target[knob.cvar] = ns.db.saved[knob.cvar] end
    ns.ApplyTarget(target, what)
end

function ns.Save()
    local changed = #ns.Changes()
    ns.db.saved = ns.Apply.Live()
    out.Printf("saved, with %d %s since the last save.", changed, Util.Plural(changed, "change"))
    RefreshPanel()
end

function ns.Revert()
    ns.ApplyTarget(ns.db.saved, "back to the saved set")
end

function ns.Defaults()
    ns.ApplyTarget(ns.Apply.Defaults(), "the client's defaults")
    out.Print("Revert undoes this; Save keeps it.")
end

function ns.Restore()
    ns.ApplyTarget(ns.db.original, "back to before RenderTuner")
end

function ns.Restart()
    if ns.pendingRestart == "client" then
        out.Print("that change needs the whole game restarted, which an addon cannot do.")
        return
    end
    out.Print("restarting the graphics engine.")
    ns.Apply.Restart(ns.pendingRestart or "gx")
    ns.pendingRestart = nil
    RefreshPanel()
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local HELP = {
    { "", "open or close the panel" },
    { "status", "the render scale, and how many settings differ from the saved set" },
    { "preset [name]", "list the upscaling presets, or use one" },
    { "on | off", "upscale with the last preset used, or go back to native" },
    { "quality [name]", "list the overall quality presets, or use one" },
    { "list [group | changed]", "the groups, the settings in one, or the ones that differ from saved" },
    { "set <variable> <value>", "set one console variable from the catalogue" },
    { "save", "record the settings as they are now as the saved set" },
    { "revert", "go back to the saved set" },
    { "defaults", "set everything to the client's defaults" },
    { "restore", "go back to how things were before RenderTuner first ran" },
    { "restart", "restart the graphics engine, for the changes that need it" },
    { "probe, capture ...", "questions for the client, used while building this" },
    { "test", "run the built-in checks" },
    { "help", "this list" },
}

local COMMANDS = {}

COMMANDS[""] = function()
    if not Ready() then return end
    ns.Panel.Toggle()
end

COMMANDS.status = function()
    if not Ready() then return end
    out.Print(ns.StatusText())
    if ns.pendingRestart then out.Print(ns.Model.RestartHint(ns.pendingRestart)) end
end

COMMANDS.preset = function(rest)
    if not Ready() then return end
    local limits = ns.Apply.Limits()
    if Util.Trim(rest) == "" then
        local now = ns.Model.PresetOf(ns.Apply.Live().RenderScale, ns.Catalog.PRESETS, limits)
        for _, preset in ipairs(ns.Catalog.PRESETS) do
            out.Printf("  %s%s: render scale %d%%%s", preset.key, preset == now and " |cff00ff00(in use)|r" or "",
                math.floor(Util.Clamp(preset.scale, limits.min, limits.max) * 100 + 0.5),
                preset.scale < 1 and ", FSR 1.0 upscale" or "")
        end
        return
    end
    local preset = ns.Model.FindPreset(ns.Catalog.PRESETS, rest)
    if not preset then
        out.Print("no preset by that name. /tuner preset lists them.")
        return
    end
    ns.ApplyPreset(preset)
end

COMMANDS.quality = function(rest)
    if not Ready() then return end
    if Util.Trim(rest) == "" then
        local live = ns.Apply.Live()
        local now = ns.Model.LevelOf(live.graphicsQuality, ns.Catalog.LEVELS, live, ns.Excused)
        for _, preset in ipairs(ns.Catalog.LEVELS) do
            out.Printf("  %s%s: level %d of 10%s", preset.key, preset == now and " |cff00ff00(in use)|r" or "",
                preset.level + 1, preset.also and ", and every setting beyond the levels turned all the way up (experimental)" or "")
        end
        return
    end
    local preset = ns.Model.FindPreset(ns.Catalog.LEVELS, rest)
    if not preset then
        out.Print("no quality preset by that name. /tuner quality lists them.")
        return
    end
    ns.ApplyLevel(preset)
end

COMMANDS.on = function()
    if not Ready() then return end
    local preset = ns.Model.FindPreset(ns.Catalog.PRESETS, ns.db.settings.upscale.last)
        or ns.Model.FindPreset(ns.Catalog.PRESETS, "quality")
    ns.ApplyPreset(preset)
end

COMMANDS.off = function()
    if not Ready() then return end
    ns.ApplyPreset(ns.Model.FindPreset(ns.Catalog.PRESETS, "native"))
end

COMMANDS.list = function(rest)
    if not Ready() then return end
    local knobs, live, saved = ns.Apply.Knobs(), ns.Apply.Live(), ns.db.saved
    local want = Util.Trim(rest):lower()

    if want == "changed" then
        local changes = ns.Changes()
        if #changes == 0 then
            out.Print("everything is as saved.")
            return
        end
        for _, change in ipairs(changes) do
            out.Print(ns.Model.Line(change.knob, change.to, change.from))
        end
        return
    end

    if want == "" then
        for _, group in ipairs(ns.Catalog.GROUPS) do
            local count, changed = 0, 0
            for _, knob in ipairs(knobs) do
                if knob.group == group.key then
                    count = count + 1
                    if not ns.Model.Same(live[knob.cvar], saved[knob.cvar]) then changed = changed + 1 end
                end
            end
            out.Printf("  %s (%s): %d %s%s", group.label, group.key, count, Util.Plural(count, "setting"),
                changed > 0 and string.format(", |cffffcc00%d changed|r", changed) or "")
        end
        out.Print("/tuner list <group> shows one; /tuner list changed shows what differs from saved.")
        return
    end

    local group = ns.Model.Group(ns.Catalog.GROUPS, want)
    if not group then
        out.Print("no group by that name. /tuner list shows them.")
        return
    end
    out.Print(group.label .. ":")
    for _, knob in ipairs(knobs) do
        if knob.group == group.key then
            out.Print(ns.Model.Line(knob, live[knob.cvar], saved[knob.cvar]))
        end
    end
end

COMMANDS.set = function(rest)
    if not Ready() then return end
    local name, value = Console.Parse(rest)
    local knob = ns.Model.Find(ns.Apply.Knobs(), name)
    if not knob then
        out.Print("that variable is not in the catalogue. /tuner list <group> shows the names.")
        return
    end
    local word = Util.Trim(value):lower()
    local shown = (word == "on" and 1) or (word == "off" and 0) or tonumber(word)
    local wanted, why = ns.Model.Clamp(knob, shown and ns.Model.FromShown(knob, shown))
    if wanted == nil then
        out.Printf("%s: %s.", knob.label, why)
        return
    end
    local refused = ns.Apply.Unsupported(knob.cvar, wanted)
    if refused then
        out.Printf("%s cannot be %s here: %s", knob.label, ns.Model.Format(knob, wanted), refused)
        return
    end
    ns.ApplyTarget({ [knob.cvar] = wanted }, knob.label .. " " .. ns.Model.Format(knob, wanted))
end

-- The commands that are also buttons in the panel.
for word, action in pairs({ save = "Save", revert = "Revert", defaults = "Defaults", restore = "Restore",
    restart = "Restart" }) do
    COMMANDS[word] = function()
        if not Ready() then return end
        ns[action]()
    end
end

COMMANDS.probe = function()
    if not ns.db then return end
    ns.db.probe = ns.Probe.Run()
    for _, line in ipairs(ns.Probe.Summary(ns.db.probe)) do out.Print(line) end
    out.Print("saved. /reload writes it to disk.")
end

COMMANDS.capture = function(rest)
    if not ns.db then return end
    local word, arg = Console.Parse(rest)
    arg = arg:lower()
    if word == "report" or word == "photo" then
        ns.db.capture = ns.db.capture or {}
        ns.Probe.Capture(word, ns.db.capture, out.Print)
    elseif word == "view" and (arg == "split" or arg == "full") then
        ns.Probe.CaptureView(arg)
        out.Printf("the capture is shown %s.", arg == "split" and "on the left half of the screen" or "whole, at half size")
    elseif word == "clear" then
        ns.Probe.CaptureClear()
        out.Print("the capture is off the screen.")
    else
        out.Print("capture report, capture photo, capture view split, capture view full, or capture clear.")
    end
end

COMMANDS.test = function()
    ns.Tests.Run()
end

local _, slashTaken = Console.Slash({
    key = "RENDERTUNER", slash = { "/tuner", "/rendertuner" }, out = out, help = HELP, commands = COMMANDS,
})

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:SetScript("OnEvent", Env.Wrap("RenderTuner events", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        -- A box with focus takes every key, movement included. Combat gets the keyboard back.
        if ns.Panel then ns.Panel.DropFocus() end
        return
    end
    -- The console variables are read here rather than when the saved tables arrive: by
    -- login the client has loaded them.
    if ns.db then
        ns.Baseline()
        if ns.Launcher then ns.Launcher.Create() end
        for _, line in ipairs(ns.LoadLines(VERSION, ns.StatusText())) do out.Print(line) end
    end
    if slashTaken then
        out.Print("|cffff9900another addon already registered the RENDERTUNER slash key.|r One of you owns /tuner now.")
    end
end))

-- For the key binding (Bindings.xml).
function RenderTuner_Toggle()
    if ns.db and ns.db.saved then ns.Panel.Toggle() end
end

-- For the held key binding: the panel fades while the key is down, so the world can be
-- seen as it is, and comes back when it is let go.
function RenderTuner_Peek(keystate)
    if ns.db and ns.db.saved then ns.Panel.Peek(keystate == "down") end
end

BINDING_HEADER_RENDERTUNER = "RenderTuner"
BINDING_NAME_RENDERTUNER_TOGGLE = "Open or close the panel"
BINDING_NAME_RENDERTUNER_PEEK = "Hold to see the world behind the panel"
