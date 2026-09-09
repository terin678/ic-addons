local addonName, ns = ...

--[[
AuctionatorSellingTweaks: two changes to Auctionator's Selling tab on this client.

    Guard.lua     a confirmation before posting an item far under the market
    Columns.lua   an Expiry column before "You?" in the current-prices list

Nothing inside Auctionator's own files is edited. Both wrap a function Auctionator
already calls, so Auctionator updates keep working; if a wrap finds nothing to wrap,
the addon says so at login and leaves that part alone.

The plumbing -- Print, the saved-variable bootstrap, the slash dispatcher, the test
harness -- is LibICCore's. This file is the version, the defaults and the commands.
]]

local Core = LibStub("LibICCore-1.0")

local VERSION = "1.1.0"
local SCHEMA = 1

local Defaults = {
    settings = {
        enabled = true,
        outputFrame = 1,
        debug = false,
        -- The guard fires when the unit price is this far, in percent, under the
        -- reference: the cheapest listing on the auction house right now, or with
        -- none, Auctionator's last known price for the item.
        guard = { enabled = true, floorPct = 40 },
        columns = { enabled = true },
    },
}

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

local HELP = {
    { "", "what the guard is set to" },
    { "floor <percent>", "how far under the market a price must be before it asks (default 40)" },
    { "guard on | off", "the posting guard" },
    { "columns on | off", "the Expiry column; takes effect after a reload" },
    { "test", "run the built-in checks" },
    { "status", "one line per part of the addon" },
    { "enable | disable", "master switch" },
    { "out [n]", "print to ChatFrame n" },
    { "version", "addon and library versions" },
    { "help", "this list" },
}

local COMMANDS = {}

local function Describe()
    local g = ns.db.settings.guard
    ns.Printf("posting guard %s: asks before posting more than %d%% under the cheapest listing (or "
        .. "Auctionator's last price when there is none). Expiry column %s.",
        ns.Util.OnOff(g.enabled), g.floorPct, ns.Util.OnOff(ns.db.settings.columns.enabled))
end

COMMANDS.config = Describe

COMMANDS.floor = function(rest)
    local pct = tonumber(rest)
    if not pct then
        Describe()
        return
    end
    ns.db.settings.guard.floorPct = ns.Guard.ClampFloor(pct)
    if ns.db.settings.guard.floorPct ~= pct then
        ns.Printf("held to %d%%; the floor is a percentage between 1 and 90.", ns.db.settings.guard.floorPct)
    end
    ns.Printf("the guard asks when a price is more than %d%% under the market.", ns.db.settings.guard.floorPct)
end

local function Toggle(key)
    return function(rest)
        local state = (rest or ""):lower()
        if state ~= "on" and state ~= "off" then
            Describe()
            return
        end
        ns.db.settings[key].enabled = (state == "on")
        Describe()
    end
end
COMMANDS.guard, COMMANDS.columns = Toggle("guard"), Toggle("columns")

--------------------------------------------------------------------------------
-- Attach
--------------------------------------------------------------------------------

Core:Attach(ns, {
    name = addonName,
    prefix = "SellingTweaks",
    version = VERSION,
    db = "AuctionatorSellingTweaksDB",
    defaults = Defaults,
    schema = SCHEMA,
    slash = { "/ast", "/sellingtweaks" },
    slashKey = "AUCTIONATORSELLINGTWEAKS",
    help = HELP,
    commands = COMMANDS,
    loadedHint = "/ast shows the posting guard's floor.",
    onLoad = function()
        -- Auctionator has loaded by now (it is a dependency), so its mixins exist.
        ns.Guard.Install()
        if ns.db.settings.columns.enabled then ns.Columns.Install() end
    end,
})

-- The wraps are on the mixins, which Auctionator copies onto its frames when the
-- auction house opens, so anything not wrapped by login is not going to be.
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
    if not ns.Guard.Install() then
        ns.Print("|cffff4444Auctionator's posting code was not found;|r the guard is not in place.")
    end
    if ns.db.settings.columns.enabled and not ns.Columns.Install() then
        ns.Print("Auctionator's selling price list was not found; the columns are unchanged.")
    end
end)
