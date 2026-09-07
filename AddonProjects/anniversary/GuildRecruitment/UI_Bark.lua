local addonName, ns = ...

local UI = ns.UI

--[[
Two pages: the one every officer uses, and the one only raid leaders can write on.

The Bark page shows the exact line that will go out, right above the button that
sends it. That is deliberate and it is the point: nobody should put something in
a public channel under their own name without having read it first.
]]

--------------------------------------------------------------------------------
-- Bark
--------------------------------------------------------------------------------

UI.RegisterPage(10, "Bark", function(page)
    local bar = UI.Toolbar(page, { top = 0, right = -26 })

    local send = bar:Left(UI.Button(bar, "Send now", 100, 22, { kind = "accent" }))
    send:SetScript("OnClick", function()
        -- A click IS a hardware event, which is the only reason this button can do
        -- what the timer five feet away from it cannot.
        local ok, info = ns.Bark.Fire(true)
        if not ok then ns.Print("not sent: " .. tostring(info)) end
        UI.Refresh()
    end)

    local timer = bar:Left(UI.Button(bar, "Reminder", 100, 22))
    timer:SetScript("OnClick", function()
        ns.db.settings.bark.enabled = not ns.db.settings.bark.enabled
        ns.Bark.Restart()
        UI.Refresh()
    end)

    local sync = bar:Left(UI.Button(bar, "Sync", 70, 22))
    UI.Tooltip(sync, function()
        GameTooltip:AddLine("Sync", 1, 1, 1)
        GameTooltip:AddLine("Asks the other officers whether anyone has a newer "
            .. "message than yours.", 0.8, 0.8, 0.8, true)
    end)
    sync:SetScript("OnClick", function()
        local ok, reason = ns.Comm.Request()
        ns.Print(ok and "asked the guild for a newer message."
            or ("not asked: " .. tostring(reason)))
    end)

    local countdown = bar:Right(UI.Label(page, "", "GameFontDisableSmall"))

    -- The gate line. When Send does nothing, this is where it says why.
    local gate = UI.Label(page, "", "GameFontNormal")
    gate:SetPoint("TOPLEFT", 0, -32)
    gate:SetWidth(UI.PAGE_W - 20)

    local previewLabel = UI.Label(page, "What will go out", "GameFontDisableSmall")
    previewLabel:SetPoint("TOPLEFT", 0, -58)

    local preview = UI.Panel(page)
    preview:SetSize(UI.PAGE_W - 26, 44)
    preview:SetPoint("TOPLEFT", 0, -74)

    local previewText = UI.Label(preview, "", "GameFontHighlightSmall")
    previewText:SetPoint("TOPLEFT", 8, -8)
    previewText:SetWidth(UI.PAGE_W - 48)
    previewText:SetSpacing(2)

    local meter = UI.Label(page, "", "GameFontDisableSmall")
    meter:SetPoint("TOPLEFT", 0, -124)

    local barksLabel = UI.Label(page, "Who has been recruiting", "GameFontDisableSmall")
    barksLabel:SetPoint("TOPLEFT", 0, -144)

    local t = UI.Table(page, {
        top = -160,
        columns = {
            { key = "age", label = "Age", width = 44, justify = "RIGHT" },
            { key = "who", label = "Officer", width = 110 },
            { key = "channel", label = "Channel", width = 150 },
            { key = "rev", label = "Rev", width = 44, justify = "RIGHT" },
            { key = "note", label = "", width = "flex" },
        },
        onEnter = function(row, item)
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:AddLine(item.who or "?", 1, 1, 1)
            GameTooltip:AddLine(date("%Y-%m-%d %H:%M:%S", item.at), 0.8, 0.8, 0.8)
            GameTooltip:AddLine(string.format("%d characters, revision %d",
                item.len or 0, item.rev or 0))
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("The text itself is not sent between officers: everyone "
                .. "is converging on the same revision, so the number is enough.",
                0.6, 0.6, 0.6, true)
            GameTooltip:Show()
        end,
    })

    return function()
        local s = ns.db.settings.bark
        local now = ns.Now()
        local state = ns.Bark.ReadState()
        local blocked = ns.Bark.BlockReason(state)

        timer:SetActive(s.enabled)
        timer:SetText("Reminder: " .. (s.enabled and "on" or "off"))
        send:SetEnabled(blocked == nil)

        if blocked then
            gate:SetText("|cffffcc00Will not send:|r " .. blocked)
        elseif ns.Bark.pending then
            gate:SetText("|cff44ff44Ready.|r Press your GuildRecruitment key, click Send "
                .. "now, or type /gr send.")
        else
            gate:SetText("|cff44ff44Ready.|r Sending to " .. (state.channelName or "?") .. ".")
        end

        if s.enabled then
            local due = ns.Bark.SecondsUntilDue()
            countdown:SetText(string.format("|cff888888next reminder in %s|r",
                due > 0 and ns.Util.Duration(due) or "a moment"))
        else
            countdown:SetText("|cff888888no reminder set|r")
        end

        local msg = ns.Bark.Preview()
        previewText:SetText(msg or ("|cff888888" .. (state.messageReason or "nothing to send")
            .. "|r"))

        local length = msg and #msg or 0
        local color = "|cff44ff44"
        if length > ns.Message.MAX_LEN then color = "|cffff4444"
        elseif length > ns.Message.MAX_LEN - 30 then color = "|cffffcc00" end
        meter:SetText(string.format("%s%d|r / %d characters", color, length,
            ns.Message.MAX_LEN))

        local me = ns.Roster.Short(UnitName and UnitName("player") or "")
        t:Render(ns.db.barks, function(row, item)
            local age, ageColor = ns.Util.Freshness(item.at, now, s.quietSec)
            t:Set(row, "age", age, ageColor)
            t:Set(row, "who", item.who == me and ("|cff44ff44" .. item.who .. "|r") or item.who)
            t:Set(row, "channel", item.channel ~= "" and item.channel or "?")
            t:Set(row, "rev", tostring(item.rev or 0))

            local note = ""
            if (item.rev or 0) < (ns.db.doc.rev or 0) then
                note = "|cffffcc00went out on an older revision|r"
            end
            t:Set(row, "note", note)
        end)

        if #ns.db.barks == 0 then
            barksLabel:SetText("|cff888888Who has been recruiting  \194\183  nothing yet. "
                .. "Barks sent while you were offline are not recovered.|r")
        else
            barksLabel:SetText(string.format(
                "|cff888888Who has been recruiting  \194\183  %d remembered  \194\183  "
                .. "barks sent while you were offline are not recovered|r", #ns.db.barks))
        end
    end
end)

--------------------------------------------------------------------------------
-- Message
--------------------------------------------------------------------------------

UI.RegisterPage(30, "Message", function(page)
    local intro = UI.Label(page,
        "The whole guild sends this line, exactly as written here. Pipes and line breaks "
        .. "come out and runs of spaces close up; nothing else is changed.")
    intro:SetPoint("TOPLEFT", 0, -2)
    intro:SetWidth(UI.PAGE_W - 20)
    intro:SetSpacing(3)

    local label = UI.Label(page, "Message", "GameFontDisableSmall")
    label:SetPoint("TOPLEFT", 0, -34)

    -- Assigned once every widget below exists. The box calls it as it is typed in, so
    -- the meter is of what is on screen rather than of what was last saved.
    local UpdateMeter
    -- Set the moment anybody types, cleared by Save and by Revert. Without it the refresh
    -- reloads the box from the saved document whenever nothing has focus, so switching
    -- to another tab and back would throw away an unsaved edit without saying so.
    local dirty = false
    local function Typed()
        dirty = true
        if UpdateMeter then UpdateMeter() end
    end

    -- The whole page width: TextBox reserves its own 26 for its scrollbar.
    local box = UI.TextBox(page, UI.PAGE_W, 88,
        { maxBytes = ns.Message.MAX_LEN, onChange = Typed })
    box:SetPoint("TOPLEFT", 0, -50)

    local meter = UI.Label(page, "", "GameFontDisableSmall")
    meter:SetPoint("TOPLEFT", 0, -144)

    local warning = UI.Label(page, "", "GameFontHighlightSmall")
    warning:SetPoint("TOPLEFT", 0, -162)
    warning:SetWidth(UI.PAGE_W - 20)
    warning:SetSpacing(2)

    local bar = UI.Toolbar(page, { top = -220, right = -26 })
    local save = bar:Left(UI.Button(bar, "Save and push", 120, 22, { kind = "accent" }))
    local revert = bar:Left(UI.Button(bar, "Revert", 80, 22))
    local footer = bar:Right(UI.Label(page, "", "GameFontDisableSmall"))

    local function LoadDraft()
        box:SetText(ns.db.doc.text or "")
        -- The box now matches the document again, whoever asked for that.
        dirty = false
    end

    -- What Save would store: the box, cleaned the way a copy arriving from another
    -- officer is cleaned in Doc.Sanitize, so the line hashes the same on the client
    -- that wrote it and on the ones that received it.
    local function Draft()
        return ns.Util.Clean(box:GetText(), ns.Message.MAX_LEN)
    end

    -- The length meter and the warnings, off the box as it stands right now. Separate
    -- from the page refresh because it runs on every keystroke.
    UpdateMeter = function()
        local text = Draft()
        local length = #text
        local color = "|cff44ff44"
        if length > ns.Message.MAX_LEN then color = "|cffff4444"
        elseif length > ns.Message.MAX_LEN - 30 then color = "|cffffcc00" end
        meter:SetText(string.format("%s%d|r / %d characters%s", color, length,
            ns.Message.MAX_LEN,
            -- The meter is of the box, so once it differs from the saved document it
            -- has to say so, or this reads as a line the guild is already sending.
            dirty and "  \194\183  |cffffcc00unsaved  \194\183  Save and push to send it|r"
                or ""))

        local notes = {}
        if text == "" then
            notes[#notes + 1] = "|cffffcc00Nothing to send yet.|r Until a line is saved, "
                .. "every officer's Bark tab says so instead of sending."
        end
        if not ns.Roster.ICanAuthor() then
            notes[#notes + 1] = "|cffffcc00You can send this message but not change it.|r"
        end
        local _, _, ahead = ns.Doc.Agreement(ns.db.doc, ns.db.peers)
        if ahead > 0 then
            notes[#notes + 1] = string.format(
                "|cffffcc00%d officer%s has a newer revision than yours.|r Press Sync on the "
                .. "Bark tab before you edit, or your change will fight theirs.",
                ahead, ahead == 1 and "" or "s")
        end
        if not ns.Comm.Status().available then
            notes[#notes + 1] = "|cffff4444This client cannot send addon messages,|r so "
                .. "nothing you save here reaches anyone else. /gr probe for detail."
        end
        warning:SetText(table.concat(notes, "\n"))
    end

    save:SetScript("OnClick", function()
        if not ns.Roster.ICanAuthor() then return end
        ns.db.doc.text = Draft()

        local me = ns.Roster.Short(UnitName and UnitName("player") or "")
        ns.Doc.Bump(ns.db.doc, me, ns.Roster.GuildName(), ns.Now(), ns.db.highestSeenRev)
        ns.db.highestSeenRev = ns.db.doc.rev

        local ok, reason = ns.Comm.Broadcast()
        ns.Printf("saved as rev %d. %s", ns.db.doc.rev,
            ok and "Sent to the guild." or ("Not sent: " .. tostring(reason)))
        ns.Log.Add("doc", "Message", "saved rev " .. ns.db.doc.rev,
            ok and "sent to the guild" or tostring(reason))
        LoadDraft()
        UI.Refresh()
    end)

    revert:SetScript("OnClick", function()
        LoadDraft()
        UI.Refresh()
    end)

    LoadDraft()

    return function()
        local now = ns.Now()
        local mine = ns.Roster.ICanAuthor()
        local why = string.format("Rank %d or better may change the message. "
            .. "Yours is %d. Ask a raid leader, or check the Settings tab.",
            ns.db.settings.authorRankIndex, select(2, ns.Roster.Me()))

        UI.Gate(save, mine, why)
        UI.Gate(revert, mine, why)
        -- Greyed rather than hidden: an officer who cannot edit should still be
        -- able to read what the guild is sending in their name.
        UI.SetEditable(box, mine)

        -- Never overwrite what somebody is halfway through typing, and never throw away
        -- an edit they have stopped typing but not yet saved. Focus is lost the moment
        -- they click another tab, so focus alone is not enough to tell those apart.
        if not box.edit:HasFocus() and not dirty then
            LoadDraft()
        end

        UpdateMeter()

        local same, behind, ahead = ns.Doc.Agreement(ns.db.doc, ns.db.peers)
        footer:SetText(string.format("|cff888888%s  \194\183  %d of %d officers have it|r",
            ns.Doc.Summary(ns.db.doc, now), same, same + behind + ahead))
    end
end)
