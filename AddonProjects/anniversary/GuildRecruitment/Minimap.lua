local addonName, ns = ...

ns.Minimap = ns.Minimap or {}
local M = ns.Minimap

--[[
The minimap launcher. LibICCore does the LibDataBroker and LibDBIcon work and checks
both are there first.

The right click is here for the same reason the key binding is: it is a hardware
event, so it is one of the few places a send is allowed at all.
]]

local ICON = "Interface\\AddOns\\GuildRecruitment\\GuildRecruitment.tga"

function M.Init()
    M.obj, M.icon = ns.Core:MinimapButton(ns, {
        name = "GuildRecruitment",
        icon = ICON,
        onClick = function(button)
            if button == "RightButton" then
                local ok, info = ns.Bark.Fire(true)
                if not ok then ns.Print("not sent: " .. tostring(info)) end
            elseif button == "MiddleButton" then
                local ok, reason = ns.Comm.Request()
                ns.Print(ok and "asked the guild for a newer message."
                    or ("not asked: " .. tostring(reason)))
            else
                ns.UI.Toggle()
            end
        end,
        tooltip = function(tt)
            local now = ns.Now()
            local s = ns.db.settings.bark
            tt:AddLine("Guild Recruitment " .. ns.VERSION)
            if not ns.Enabled() then tt:AddLine("|cffff4444DISABLED|r") end
            tt:AddLine(ns.Doc.Summary(ns.db.doc, now), 1, 1, 1)

            local same, behind, ahead = ns.Doc.Agreement(ns.db.doc, ns.db.peers)
            tt:AddLine(string.format("|cffffffff%d|r in step, |cffffcc00%d|r behind, "
                .. "|cff88bbff%d|r ahead", same, behind, ahead))
            tt:AddLine(string.format("|cffffffff%d|r still needed",
                ns.Teams.TotalNeeded(ns.db.doc)))

            local blocked = ns.Bark.BlockReason(ns.Bark.ReadState())
            if ns.Bark.pending then
                tt:AddLine("|cffffcc00Ready to send. Right click.|r")
            elseif blocked then
                tt:AddLine("|cffffcc00will not send: " .. blocked .. "|r")
            elseif s.enabled then
                tt:AddLine(string.format("|cff888888next reminder in %s|r",
                    ns.Util.Duration(ns.Bark.SecondsUntilDue())))
            end

            tt:AddLine(" ")
            tt:AddLine("|cff888888Left click: open the window|r")
            tt:AddLine("|cff888888Right click: send the recruitment message|r")
            tt:AddLine("|cff888888Middle click: ask the guild for a newer one|r")
        end,
    })
end
