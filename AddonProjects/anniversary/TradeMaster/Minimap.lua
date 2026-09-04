local addonName, ns = ...

ns.Minimap = ns.Minimap or {}
local M = ns.Minimap

-- The minimap launcher. LibICCore does the LibDataBroker and LibDBIcon work and checks
-- both are there first. The icon follows the active profession.

local DEFAULT_ICON = "Interface\\AddOns\\TradeMaster\\TradeMaster.tga"

local function CurrentIcon()
    local p = ns.Prof.Current()
    return (p and p.key ~= "generic" and p.iconPath) or DEFAULT_ICON
end

function M.Init()
    M.obj, M.icon = ns.Core:MinimapButton(ns, {
        name = "TradeMaster",
        icon = CurrentIcon(),
        onClick = function(button)
            if button == "MiddleButton" then
                ns.Tracker.Toggle()
            elseif button == "RightButton" then
                local ok, info = ns.Barker.Tick(true)
                if not ok then ns.Print("bark skipped: " .. tostring(info)) end
            else
                ns.UI.Toggle()
            end
        end,
        tooltip = function(tt)
            local s = ns.PS()
            local profile = ns.Prof.Current()
            local n, products, noun = ns.Prof.BookCounts(profile, ns.Book())
            tt:AddLine("TradeMaster " .. ns.VERSION)
            if not ns.Enabled() then tt:AddLine("|cffff4444DISABLED|r") end
            tt:AddLine(string.format("active: |cffffffff%s|r",
                profile.key ~= "generic" and profile.name or "none"))
            tt:AddLine(string.format("|cffffffff%d|r recipes, |cffffffff%d|r %s, |cffffffff%d|r advertised",
                n, products, noun, #ns.Barker.AdvertisedEntries()))
            tt:AddLine(string.format("|cffffffff%d|r open orders", #ns.Orders.OpenList()))
            local key = ns.db.activeProfession
            if key then
                tt:AddLine(ns.Market.Summary(ns.db, ns.Now(), key, s.bark.intervalSec))
            end
            tt:AddLine(string.format("barking %s   invites %s",
                s.bark.enabled and "|cff44ff44on|r" or "|cffff4444off|r",
                ns.InvitesOn() and "|cff44ff44on|r" or "|cffff4444off|r"))
            if ns.Barker.pending then
                tt:AddLine("|cffffcc00A bark is ready. Right click to send.|r")
            elseif s.bark.enabled then
                tt:AddLine(string.format("|cff888888next bark in %ds|r", ns.Barker.SecondsUntilDue()))
            end
            tt:AddLine(" ")
            tt:AddLine("|cff888888Left click: open TradeMaster|r")
            tt:AddLine("|cff888888Right click: send a bark now|r")
            tt:AddLine("|cff888888Middle click: toggle the order tracker|r")
        end,
    })
end

-- The icon follows the active profession.
function M.UpdateIcon()
    if M.obj then M.obj.icon = CurrentIcon() end
end
