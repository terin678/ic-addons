local addonName, ns = ...

--[[
Stickies: sticky notes that stay on screen. Each is a title and a checklist; each belongs
to this character or to every character on the account.

It is the first addon built on ICKit, and it uses each layer for what that layer is for:

    Notes.lua   the model: pure functions over the two saved tables     (LibICUtil)
    UI.lua      one small panel per note, drawn from what Notes says    (LibICWidgets, LibICTheme)
    Core.lua    this file: saved tables, commands, the two events       (LibICStore, LibICConsole, LibICEnv)
    Tests.lua   the cases                                               (LibICTest)

Nothing here runs while the game is idle: the addon acts on a click, a key, a command,
login, and the start of combat (to give the keyboard back).
]]

local VERSION = "0.1.0"

local Util = LibStub("LibICUtil-1.0")
local Test = LibStub("LibICTest-1.0")
local Env = LibStub("LibICEnv-1.0")
local Store = LibStub("LibICStore-1.0")
local Console = LibStub("LibICConsole-1.0")

local out = Console.New("Stickies", {
    debug = function() return ns.db ~= nil and ns.db.settings.debug == true end,
})

ns.VERSION = VERSION
ns.Util = Util
ns.Print, ns.Printf, ns.Debug = out.Print, out.Printf, out.Debug
ns.Tests = Test.New({ print = out.Print })

--------------------------------------------------------------------------------
-- Pure: what it says at login
--------------------------------------------------------------------------------

function ns.LoadLines(version, count, info)
    local lines = {
        string.format("v%s loaded with %d %s. /sticky new starts one, /sticky help lists commands.",
            version, count, Util.Plural(count, "note")),
    }
    if info and info.lost then
        lines[#lines + 1] = "|cffff4444The shared notes did not load.|r This character has used Stickies before, "
            .. "yet the account file came back empty. A client left running across .toc edits does this."
        lines[#lines + 1] = "|cffff4444Restart the client before you log out or reload|r, or the empty list is "
            .. "written over the file."
    end
    return lines
end

--------------------------------------------------------------------------------
-- Saved tables
--------------------------------------------------------------------------------

Store.Register(addonName, {
    account = "StickiesDB",
    character = "StickiesCharDB",
    schema = 1,
    charSchema = 1,
    defaults = {
        nextId = 1, notes = {}, trash = {},
        settings = {
            debug = false, locked = false,
            -- The button on the minimap's rim: whether it shows, and where round the rim.
            minimap = { hide = false, angle = 215 },
        },
    },
    charDefaults = { notes = {}, view = {} },
    onReady = Env.Wrap("Stickies saved variables", function(db, cdb, info)
        ns.db, ns.cdb, ns.loadInfo = db, cdb, info
        ns.Notes.Reconcile(db, cdb)
        -- A first run starts with one note, which is also the instructions.
        if info.firstRun and ns.Notes.Count(db, cdb) == 0 then
            ns.Notes.Welcome(db, cdb, time())
        end
    end),
})

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local HELP = {
    { "", "show every note, or hide them all if none is hidden" },
    { "new [title]", "start a note on this character" },
    { "list", "every note with its number" },
    { "show [note]", "show one note by number or title, or all of them" },
    { "hide [note]", "hide one note, or all of them" },
    { "lock | unlock", "pin every note where it is" },
    { "minimap", "show or hide the button on the minimap" },
    { "reset", "put every note back at its starting place" },
    { "restore", "bring back the last note deleted" },
    { "test", "run the built-in checks" },
    { "help", "this list" },
}

local COMMANDS = {}

local function Ready()
    if ns.db and ns.cdb then return true end
    out.Print("the saved notes are not in hand yet.")
    return false
end

local function Refresh()
    if ns.UI then ns.UI.Refresh() end
end

-- Show every note if any is hidden, otherwise hide them all. The command and the
-- minimap menu both come here.
function ns.ToggleAll()
    if not Ready() then return end
    local result = ns.Notes.ToggleAll(ns.db, ns.cdb)
    Refresh()
    if result == "none" then
        out.Print("no notes yet. /sticky new starts one.")
    elseif result == "shown" then
        out.Print("every note is showing.")
    else
        out.Print("every note is hidden. /sticky shows them again.")
    end
end
COMMANDS[""] = ns.ToggleAll

-- Starts a note on this character and puts the cursor in it. The command, the minimap
-- button and the compartment entry all come here. Returns the note, or nil when refused.
function ns.NewNote(title)
    if not Ready() then return nil end
    local note, why = ns.Notes.New(ns.db, ns.cdb, title, "character", time())
    if not note then
        out.Print(why)
        return nil
    end
    Refresh()
    if ns.UI then ns.UI.FocusAdd(note.id) end
    out.Printf("#%d %s is on screen. Type its first line and press Enter.", note.id, note.title)
    return note
end

COMMANDS.new = function(rest)
    ns.NewNote(rest)
end

COMMANDS.minimap = function()
    if not Ready() then return end
    local show = ns.db.settings.minimap.hide == true
    if ns.Launcher then ns.Launcher.SetShown(show) end
    out.Print(show and "the minimap button is showing."
        or "the minimap button is hidden. Stickies is still in the addon list beside the minimap; /sticky minimap brings the button back.")
end

COMMANDS.list = function()
    if not Ready() then return end
    local all = ns.Notes.All(ns.db, ns.cdb)
    if #all == 0 then
        out.Print("no notes yet. /sticky new starts one.")
        return
    end
    for _, entry in ipairs(all) do
        out.Print("  " .. ns.Notes.Describe(entry.note, entry.scope, ns.cdb.view[entry.note.id]))
    end
end

-- show and hide share everything but the flag they set.
local function SetHidden(hidden)
    return function(rest)
        if not Ready() then return end
        if Util.Trim(rest) == "" then
            for _, entry in ipairs(ns.Notes.All(ns.db, ns.cdb)) do
                ns.Notes.View(ns.cdb, entry.note.id).hidden = hidden
            end
            Refresh()
            out.Print(hidden and "every note is hidden. /sticky shows them again." or "every note is showing.")
            return
        end
        local note, _, why = ns.Notes.Match(ns.db, ns.cdb, rest)
        if not note then
            out.Print(why)
            return
        end
        ns.Notes.View(ns.cdb, note.id).hidden = hidden
        Refresh()
        out.Printf("#%d %s is %s.", note.id, note.title, hidden and "hidden" or "showing")
    end
end
COMMANDS.show = SetHidden(false)
COMMANDS.hide = SetHidden(true)

local function SetLocked(locked)
    return function()
        if not Ready() then return end
        ns.db.settings.locked = locked
        Refresh()
        out.Print(locked and "every note is pinned where it is. /sticky unlock frees them."
            or "notes can be dragged by their title again.")
    end
end
COMMANDS.lock = SetLocked(true)
COMMANDS.unlock = SetLocked(false)

COMMANDS.reset = function()
    if not Ready() then return end
    ns.Notes.ResetPlaces(ns.cdb)
    Refresh()
    out.Print("every note is back at its starting place.")
end

COMMANDS.restore = function()
    if not Ready() then return end
    local note, scopeOrWhy = ns.Notes.Restore(ns.db, ns.cdb)
    if not note then
        out.Print(scopeOrWhy)
        return
    end
    Refresh()
    out.Printf("#%d %s is back%s.", note.id, note.title,
        scopeOrWhy == "account" and ", shared with every character" or "")
end

COMMANDS.test = function()
    ns.Tests.Run()
end

local _, slashTaken = Console.Slash({
    key = "STICKIES", slash = { "/sticky", "/stickies" }, out = out, help = HELP, commands = COMMANDS,
})

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:SetScript("OnEvent", Env.Wrap("Stickies events", function(_, event)
    if event == "PLAYER_LOGIN" then
        -- The notes are drawn here rather than when the saved tables arrive: the screen
        -- has its size by now, and a place is a fraction of it.
        Refresh()
        if ns.Launcher then ns.Launcher.Create() end
        local count = (ns.db and ns.cdb) and ns.Notes.Count(ns.db, ns.cdb) or 0
        for _, line in ipairs(ns.LoadLines(VERSION, count, ns.loadInfo)) do out.Print(line) end
        if slashTaken then
            out.Print("|cffff9900another addon already registered the STICKIES slash key.|r One of you owns /sticky now.")
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- A box with focus takes every key, movement included. Combat gets the keyboard back.
        if ns.UI then ns.UI.DropFocus() end
    end
end))
