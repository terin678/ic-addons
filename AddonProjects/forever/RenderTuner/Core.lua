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
    Probe.lua     what the client was asked while this was being built (LibICEnv)
    Core.lua      this file: saved tables, commands, login             (LibICStore, LibICConsole)
    Tests.lua     the cases                                            (LibICTest)

Nothing here runs while the game is idle: the addon acts on a command and at login.
]]

local VERSION = "0.1.0"

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
    return { string.format("v%s loaded: %s /tuner help lists commands.", version, status) }
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
        },
    },
    charDefaults = {},
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

-- Turns the live settings into `target`. Says what it did under the name `what`.
function ns.ApplyTarget(target, what)
    local plan = ns.Model.Plan(target, ns.Apply.Live(), ns.Apply.Knobs())
    if #plan == 0 then
        out.Printf("%s: nothing to change.", what)
        return 0
    end
    local done, refused = ns.Apply.Run(plan)
    out.Printf("%s: %d %s set.", what, done, Util.Plural(done, "variable"))
    if #refused > 0 then
        out.Print("|cffff4444the client refused:|r " .. table.concat(refused, ", "))
    end
    local need = ns.Model.Restart(plan)
    if need then
        ns.pendingRestart = need
        out.Print(ns.Model.RestartHint(need))
    end
    return done
end

function ns.ApplyPreset(preset)
    local target = ns.Model.Preset(preset, ns.Apply.Limits(), ns.Catalog.FSR)
    if preset.scale < 1 then ns.db.settings.upscale.last = preset.key end
    ns.ApplyTarget(target, preset.label)
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local HELP = {
    { "", "the render scale, and how many settings differ from the saved set" },
    { "preset [name]", "list the upscaling presets, or use one" },
    { "on | off", "upscale with the last preset used, or go back to native" },
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
    ns.ApplyTarget({ [knob.cvar] = wanted }, knob.label .. " " .. ns.Model.Format(knob, wanted))
end

COMMANDS.save = function()
    if not Ready() then return end
    local changed = #ns.Changes()
    ns.db.saved = ns.Apply.Live()
    out.Printf("saved, with %d %s since the last save.", changed, Util.Plural(changed, "change"))
end

COMMANDS.revert = function()
    if not Ready() then return end
    ns.ApplyTarget(ns.db.saved, "back to the saved set")
end

COMMANDS.defaults = function()
    if not Ready() then return end
    ns.ApplyTarget(ns.Apply.Defaults(), "the client's defaults")
    out.Print("/tuner revert undoes this; /tuner save keeps it.")
end

COMMANDS.restore = function()
    if not Ready() then return end
    ns.ApplyTarget(ns.db.original, "back to before RenderTuner")
end

COMMANDS.restart = function()
    if ns.pendingRestart == "client" then
        out.Print("that change needs the whole game restarted, which an addon cannot do.")
        return
    end
    out.Print("restarting the graphics engine.")
    ns.Apply.Restart(ns.pendingRestart or "gx")
    ns.pendingRestart = nil
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
frame:SetScript("OnEvent", Env.Wrap("RenderTuner events", function()
    -- The console variables are read here rather than when the saved tables arrive: by
    -- login the client has loaded them.
    if ns.db then
        ns.Baseline()
        for _, line in ipairs(ns.LoadLines(VERSION, ns.StatusText())) do out.Print(line) end
    end
    if slashTaken then
        out.Print("|cffff9900another addon already registered the RENDERTUNER slash key.|r One of you owns /tuner now.")
    end
end))
