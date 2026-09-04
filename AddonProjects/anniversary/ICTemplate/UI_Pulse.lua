local addonName, ns = ...

local UI = ns.UI

--[[
The arm-and-fire page. Everything that actually sends is a button here or a key
binding, because SendChatMessage to a public channel is protected on this client
and a timer can only ever arm.

The gate line above the Send button is the important part of this page: when the
button does nothing, it says which of the reasons in Pulse.BlockReason applied,
in that function's fixed order.
]]

UI.RegisterPage(30, "Pulse", function(page)
    local intro = UI.Label(page,
        "A timer cannot send to a public channel on this client. It arms, and a keypress\n"
        .. "or a click sends. Everything below the preview is that split.")
    intro:SetPoint("TOPLEFT", 0, -2)
    intro:SetWidth(UI.Style.pageWidth - 20)
    intro:SetSpacing(3)

    local bar = UI.Toolbar(page, { top = -40 })

    local onOff = bar:Left(UI.Button(bar, "Timer", 80, 22))
    onOff:SetScript("OnClick", function()
        local s = ns.db.settings.pulse
        s.enabled = not s.enabled
        ns.Pulse.Restart()
        UI.Refresh()
    end)

    local send = bar:Left(UI.Button(bar, "Send now", 90, 22, { kind = "accent" }))
    send:SetScript("OnClick", function()
        -- A click IS a hardware event, which is the whole reason this button
        -- exists next to a timer that cannot do the same thing.
        local ok, info = ns.Pulse.Fire(true)
        ns.Print(ok and ("sent: " .. tostring(info)) or ("skipped: " .. tostring(info)))
        UI.Refresh()
    end)

    local slower = bar:Left(UI.Button(bar, "-15s", 50, 22))
    local faster = bar:Left(UI.Button(bar, "+15s", 50, 22))
    local function Nudge(delta)
        local s = ns.db.settings.pulse
        s.intervalSec = ns.Pulse.ClampInterval(s.intervalSec + delta)
        ns.Pulse.Restart()
        UI.Refresh()
    end
    slower:SetScript("OnClick", function() Nudge(-15) end)
    faster:SetScript("OnClick", function() Nudge(15) end)

    local pauseCombat = bar:Left(UI.CheckBox(bar, "Pause in combat"))
    pauseCombat:SetScript("OnClick", function(self)
        ns.db.settings.pulse.pauseCombat = self:GetChecked() and true or false
        UI.Refresh()
    end)

    local gate = UI.Label(page, "", "GameFontNormal")
    gate:SetPoint("TOPLEFT", 0, -74)
    gate:SetWidth(UI.Style.pageWidth - 20)

    local templateLabel = UI.Label(page, "Template  |cff888888{items} is where the "
        .. "entries go|r", "GameFontDisableSmall")
    templateLabel:SetPoint("TOPLEFT", 0, -100)

    local template = UI.TextBox(page, 460, 54, { maxBytes = 255 })
    template:SetPoint("TOPLEFT", 0, -116)

    local apply = UI.Button(page, "Apply", 70, 22, { kind = "accent" })
    apply:SetPoint("TOPLEFT", 470, -116)
    apply:SetScript("OnClick", function()
        ns.db.settings.pulse.template = ns.Util.Trim(template:GetText())
        UI.Refresh()
    end)

    local revert = UI.Button(page, "Revert", 70, 22)
    revert:SetPoint("TOPLEFT", 470, -142)
    revert:SetScript("OnClick", function()
        template:SetText(ns.db.settings.pulse.template or "")
        UI.Refresh()
    end)

    local previewLabel = UI.Label(page, "Next message", "GameFontDisableSmall")
    previewLabel:SetPoint("TOPLEFT", 0, -180)

    local preview = ns.UI.Lib:Panel(page, { style = UI.Style })
    preview:SetSize(UI.Style.pageWidth - 20, 40)
    preview:SetPoint("TOPLEFT", 0, -196)

    local previewText = UI.Label(preview, "", "GameFontHighlightSmall")
    previewText:SetPoint("TOPLEFT", 8, -8)
    previewText:SetWidth(UI.Style.pageWidth - 40)
    previewText:SetSpacing(2)

    local meter = UI.Label(page, "", "GameFontDisableSmall")
    meter:SetPoint("TOPLEFT", 0, -242)

    local t = UI.Table(page, {
        top = -266,
        columns = {
            { key = "age", label = "Age", width = 40, justify = "RIGHT" },
            { key = "kind", label = "", width = 44 },
            { key = "text", label = "What the pulse did", width = "flex" },
        },
    })

    -- Rebuilt from the settings each time the page is shown, but NOT while the
    -- box has focus: overwriting what someone is halfway through typing is the
    -- worst thing a refresh can do.
    template:SetText(ns.db.settings.pulse.template or "")

    return function()
        local s = ns.db.settings.pulse
        local c = ns.cdb.pulse
        local now = ns.Now()

        onOff:SetActive(s.enabled)
        onOff:SetText("Timer: " .. (s.enabled and "on" or "off"))
        pauseCombat:SetChecked(s.pauseCombat)

        local blocked = ns.Pulse.BlockReason(ns.Pulse.ReadState())
        if blocked then
            gate:SetText("|cffffcc00Will not send:|r " .. blocked)
        elseif ns.Pulse.pending then
            gate:SetText("|cff44ff44Armed.|r Press your ICTemplate key, click Send now, "
                .. "or type /ictpl send.")
        else
            local due = math.max(0, (c.lastSentAt or 0) + s.intervalSec - now)
            gate:SetText(string.format("|cff44ff44Ready.|r Every %ds; %s.",
                s.intervalSec,
                (c.lastSentAt or 0) == 0 and "never sent"
                    or (due > 0 and ("next in " .. UI.Age(due)) or "due now")))
        end
        send:SetEnabled(blocked == nil)

        if not template.edit:HasFocus() then
            template:SetText(s.template or "")
        end

        local msg = ns.Pulse.Preview()
        previewText:SetText(msg or "|cff888888nothing fits|r")
        local length = msg and #msg or 0
        local color = "|cff44ff44"
        if length > ns.Pulse.MAX_LEN then color = "|cffff4444"
        elseif length > ns.Pulse.MAX_LEN - 40 then color = "|cffffcc00" end
        meter:SetText(string.format("%s%d|r / %d bytes  \194\183  channel %s  \194\183  "
            .. "%d entries, %d per message",
            color, length, ns.Pulse.MAX_LEN, s.channel or "EMOTE",
            #ns.Pulse.entries, s.perLine))

        local seen = ns.Log.Window(ns.db.log, ns.db.capture)
        local entries = ns.Log.Filter(seen, 30, { source = "Pulse" })
        t:Render(entries, function(row, e)
            local age, ageColor = ns.Util.Freshness(e.at, now, s.intervalSec * 4)
            t:Set(row, "age", age, ageColor)
            t:Set(row, "kind", (ns.Log.KIND_COLOR[e.kind] or "") .. e.kind .. "|r")
            t:Set(row, "text", e.detail and (e.text .. "  \194\183  " .. e.detail) or e.text)
        end)
    end
end)
