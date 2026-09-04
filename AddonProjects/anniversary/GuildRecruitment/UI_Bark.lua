local addonName, ns = ...

local UI = ns.UI

--[[
Two pages: the one every officer uses, and the one only raid leaders can.

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
    preview:SetSize(UI.PAGE_W - 26, 52)
    preview:SetPoint("TOPLEFT", 0, -74)

    local previewText = UI.Label(preview, "", "GameFontHighlightSmall")
    previewText:SetPoint("TOPLEFT", 8, -8)
    previewText:SetWidth(UI.PAGE_W - 48)
    previewText:SetSpacing(2)

    local meter = UI.Label(page, "", "GameFontDisableSmall")
    meter:SetPoint("TOPLEFT", 0, -132)

    local barksLabel = UI.Label(page, "Who has been recruiting", "GameFontDisableSmall")
    barksLabel:SetPoint("TOPLEFT", 0, -156)

    local t = UI.Table(page, {
        top = -174,
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

        local msg, level, dropped = ns.Bark.Preview()
        previewText:SetText(msg or ("|cff888888" .. (state.messageReason or "nothing to send")
            .. "|r"))

        local length = msg and #msg or 0
        local color = "|cff44ff44"
        if length > ns.Message.MAX_LEN then color = "|cffff4444"
        elseif length > ns.Message.MAX_LEN - 30 then color = "|cffffcc00" end
        local parts = { string.format("%s%d|r / %d characters", color, length,
            ns.Message.MAX_LEN) }
        if level then
            parts[#parts + 1] = ns.Message.LEVEL_NAME[level] or ("level " .. level)
        end
        if dropped and dropped > 0 then
            -- Say what got cut. A message that quietly lost a role is worse than a
            -- longer one, because nobody knows to shorten anything.
            parts[#parts + 1] = string.format("|cffffcc00%d needs left out|r", dropped)
        end
        parts[#parts + 1] = string.format("%d needed in total", ns.Teams.TotalNeeded(ns.db.doc))
        meter:SetText(table.concat(parts, "  \194\183  "))

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
        "The whole guild sends this one line. {teams} is where the teams go, and each\n"
        .. "team is written with the second template below.")
    intro:SetPoint("TOPLEFT", 0, -2)
    intro:SetWidth(UI.PAGE_W - 20)
    intro:SetSpacing(3)

    local mainLabel = UI.Label(page, "Message  |cff888888{guild}  {teams}  {contacts}|r",
        "GameFontDisableSmall")
    mainLabel:SetPoint("TOPLEFT", 0, -40)

    -- Assigned once every widget below exists. The boxes call it as they are typed in, so
    -- the preview is of what is on screen rather than of what was last saved.
    local UpdatePreview
    -- Set the moment anybody types, cleared by Save and by Revert. Without it the refresh
    -- reloads the boxes from the saved document whenever nothing has focus, so switching
    -- to the Teams tab and back would throw away an unsaved edit without saying so.
    local dirty = false
    local function Typed()
        dirty = true
        if UpdatePreview then UpdatePreview() end
    end

    -- Full page width: TextBox reserves its own 26 for its scrollbar, so taking
    -- 26 off first put this page's right edge 26 short of every other tab's.
    local main = UI.TextBox(page, UI.PAGE_W, 54, { maxBytes = 255, onChange = Typed })
    main:SetPoint("TOPLEFT", 0, -56)

    local teamLabel = UI.Label(page, "Each team  |cff888888{tag}  {days}  {needs}|r",
        "GameFontDisableSmall")
    teamLabel:SetPoint("TOPLEFT", 0, -118)

    local team = UI.TextBox(page, UI.PAGE_W, 40, { maxBytes = 255, onChange = Typed })
    team:SetPoint("TOPLEFT", 0, -134)

    local contactsLabel = UI.Label(page, "Whisper who  |cff888888comma separated|r",
        "GameFontDisableSmall")
    contactsLabel:SetPoint("TOPLEFT", 0, -182)

    local contacts = UI.EditBox(page, 300, 22)
    contacts:SetPoint("TOPLEFT", 0, -198)
    contacts:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    -- byUser only: LoadDraft's own SetText comes through here too, and re-previewing on
    -- our own write would be work for nothing.
    contacts:SetScript("OnTextChanged", function(_, byUser)
        if byUser then Typed() end
    end)

    local bar = UI.Toolbar(page, { top = -230, right = -26 })
    local save = bar:Left(UI.Button(bar, "Save and push", 120, 22, { kind = "accent" }))
    local revert = bar:Left(UI.Button(bar, "Revert", 80, 22))
    local footer = bar:Right(UI.Label(page, "", "GameFontDisableSmall"))

    local previewLabel = UI.Label(page, "Preview", "GameFontDisableSmall")
    previewLabel:SetPoint("TOPLEFT", 0, -262)

    local preview = UI.Panel(page)
    preview:SetSize(UI.PAGE_W - 26, 52)
    preview:SetPoint("TOPLEFT", 0, -278)

    local previewText = UI.Label(preview, "", "GameFontHighlightSmall")
    previewText:SetPoint("TOPLEFT", 8, -8)
    previewText:SetWidth(UI.PAGE_W - 48)
    previewText:SetSpacing(2)

    local meter = UI.Label(page, "", "GameFontDisableSmall")
    meter:SetPoint("TOPLEFT", 0, -336)

    local warning = UI.Label(page, "", "GameFontHighlightSmall")
    warning:SetPoint("TOPLEFT", 0, -358)
    warning:SetWidth(UI.PAGE_W - 20)
    warning:SetSpacing(2)

    -- What is being edited, kept apart from the document so nothing is committed
    -- until Save. Typing must not move the revision every officer is watching.
    local draft = {}

    local function LoadDraft()
        draft.template = ns.db.doc.template
        draft.teamTemplate = ns.db.doc.teamTemplate
        draft.contacts = table.concat(ns.db.doc.contacts or {}, ", ")
        main:SetText(draft.template)
        team:SetText(draft.teamTemplate)
        contacts:SetText(draft.contacts)
        -- The boxes now match the document again, whoever asked for that.
        dirty = false
    end

    local function Draft()
        -- A preview has to be of what is in the boxes, not of what is saved.
        local copy = ns.DeepCopy(ns.db.doc)
        copy.template = ns.Util.Trim(main:GetText())
        copy.teamTemplate = ns.Util.Trim(team:GetText())
        copy.contacts = {}
        for name in (contacts:GetText() or ""):gmatch("[^,]+") do
            local clean = ns.Util.Clean(name, 24)
            if clean ~= "" then copy.contacts[#copy.contacts + 1] = clean end
        end
        return copy
    end

    --[[
    The preview and its length meter, off the boxes as they stand right now.

    Separate from the page refresh because it runs on every keystroke: it reads the two
    templates and the contacts from the widgets and the TEAMS from the live document, so
    editing a team on the Teams tab shows up here as soon as this tab is drawn again, and
    editing a template shows up as you type.

    Assembling per keystroke is a handful of string operations over at most a few teams.
    ]]
    UpdatePreview = function()
        local copy = Draft()
        local msg, level, dropped, _, reason = ns.Message.Assemble(copy, ns.cdb.bark.cursor)
        previewText:SetText(msg or ("|cff888888" .. tostring(reason) .. "|r"))

        local length = msg and #msg or 0
        local color = "|cff44ff44"
        if length > ns.Message.MAX_LEN then color = "|cffff4444"
        elseif length > ns.Message.MAX_LEN - 30 then color = "|cffffcc00" end
        meter:SetText(string.format("%s%d|r / %d characters  \194\183  %s%s%s",
            color, length, ns.Message.MAX_LEN,
            level and (ns.Message.LEVEL_NAME[level] or "?") or "nothing to show",
            (dropped or 0) > 0 and string.format("  \194\183  |cffffcc00%d needs left out|r",
                dropped) or "",
            -- The preview is of the boxes, so once they differ from the saved document it
            -- has to say so, or this reads as a line the guild is already sending.
            dirty and "  \194\183  |cffffcc00unsaved  \194\183  Save and push to send it|r"
                or ""))
    end

    save:SetScript("OnClick", function()
        if not ns.Roster.ICanAuthor() then return end
        local copy = Draft()
        ns.db.doc.template = copy.template
        ns.db.doc.teamTemplate = copy.teamTemplate
        ns.db.doc.contacts = copy.contacts

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
        UI.SetEditable(main, mine)
        UI.SetEditable(team, mine)
        UI.SetEditable(contacts, mine)

        -- Never overwrite what somebody is halfway through typing, and never throw away
        -- an edit they have stopped typing but not yet saved. Focus is lost the moment
        -- they click another tab, so focus alone is not enough to tell those apart.
        local busy = main.edit:HasFocus() or team.edit:HasFocus() or contacts:HasFocus()
        if not busy and not dirty then
            LoadDraft()
        end

        UpdatePreview()

        local same, behind, ahead = ns.Doc.Agreement(ns.db.doc, ns.db.peers)
        footer:SetText(string.format("|cff888888%s  \194\183  %d of %d officers have it|r",
            ns.Doc.Summary(ns.db.doc, now), same, same + behind + ahead))

        local notes = {}
        if not mine then
            notes[#notes + 1] = "|cffffcc00You can send this message but not change it.|r"
        end
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
end)
