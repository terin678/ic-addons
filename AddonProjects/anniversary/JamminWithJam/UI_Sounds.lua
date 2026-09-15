local addonName, ns = ...

local UI = ns.UI

--[[
One row per catalogue entry: its label, what Sounds.BlockReason says about it
right now, and a Play button that is only enabled when there is nothing in
the way. The row never hides a reason -- a greyed button with nothing to say
reads as a broken addon.
]]

UI.RegisterPage(10, "Sounds", function(page)
    local intro = UI.Label(page,
        "Play sends a chat line the Discord bot is listening for; it does not "
        .. "make sound by itself. See the About tab if nothing happens on the "
        .. "Discord side.", "GameFontDisableSmall")
    intro:SetPoint("TOPLEFT", 0, -2)
    intro:SetWidth(UI.Style.pageWidth - 20)
    intro:SetSpacing(2)

    local t = UI.Table(page, {
        top = -34,
        columns = {
            { key = "label", label = "Sound", width = "flex" },
            { key = "status", label = "Status", width = 170 },
        },
        buttons = { { key = "play", label = "Play", width = 70, kind = "accent" } },
    })

    return function()
        t:Render(ns.Sounds.List(), function(row, sound)
            local state = ns.Sounds.ReadState(sound)
            local blocked = ns.Sounds.BlockReason(state)

            t:Set(row, "label", sound.officerOnly
                and ("|cffdf9c33" .. sound.label .. "|r  |cff888888(officers)|r")
                or sound.label)
            t:Set(row, "status", blocked and ("|cffffcc00" .. blocked .. "|r")
                or "|cff44ff44ready|r")

            local btn = row.buttons.play
            btn:SetEnabled(blocked == nil)
            btn:SetScript("OnClick", function()
                -- A click IS a hardware event, which is the only reason this
                -- can send where a timer could not. See Sounds.Fire.
                local ok, info = ns.Sounds.Fire(sound.id)
                if not ok then ns.Print("not sent: " .. tostring(info)) end
                UI.Refresh()
            end)
            UI.Tooltip(btn, blocked and function()
                GameTooltip:AddLine("Will not send", 1, 1, 1)
                GameTooltip:AddLine(blocked, 0.8, 0.8, 0.8, true)
            end or nil)
        end)
    end
end)
