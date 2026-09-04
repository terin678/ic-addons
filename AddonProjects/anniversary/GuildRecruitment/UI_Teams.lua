local addonName, ns = ...

local UI = ns.UI

--[[
Both teams and everything they are short of, in ONE table rather than one table
per team. Two tables would mean two scrollbars, two headers and two things to keep
lined up; a Span row is what a section heading inside a list is for.

Every control here is gated on the author rank, and a gated control says why.
]]

local ROLES = { "Tank", "Healer", "DPS" }

UI.RegisterPage(20, "Teams", function(page)
    -- { teamID, need } while the editor is open; need is nil for a new one. The
    -- NEED itself, never its position: rows are drawn sorted and the stored array
    -- is not, so an index taken from the list stops meaning anything the moment
    -- somebody uses the priority button.
    local editing = nil

    local bar = UI.Toolbar(page, { top = 0, right = -26 })
    local addNeed = bar:Left(UI.Button(bar, "Add a need", 100, 22, { kind = "accent" }))
    local addTeam = bar:Left(UI.Button(bar, "Add a team", 100, 22))
    local push = bar:Left(UI.Button(bar, "Save and push", 120, 22))
    local hint = bar:Right(UI.Label(page, "", "GameFontDisableSmall"))

    -- The editor. One row of controls that the table's Edit buttons point at,
    -- rather than a dialog: a list you cannot see while editing it is a list you
    -- end up editing wrong.
    local editor = UI.Panel(page)
    editor:SetSize(UI.PAGE_W - 26, 62)
    editor:SetPoint("TOPLEFT", 0, -28)

    local editLabel = UI.Label(editor, "", "GameFontDisableSmall")
    editLabel:SetPoint("TOPLEFT", 8, -6)
    editLabel:SetWidth(UI.PAGE_W - 48)

    -- Two sets of fields in one panel: needs on one, the team's own details on the other.
    -- Apply and Cancel are shared and sit right of both, so the buttons do not move when
    -- the panel changes what it is editing.
    local APPLY_X = 470

    local function Field(w, x, hintText)
        local box = UI.EditBox(editor, w, 22)
        box:SetPoint("TOPLEFT", x, -32)
        local hint = UI.Label(editor, hintText, "GameFontDisableSmall")
        hint:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 2, 1)
        box.hint, box.x = hint, x
        return box
    end

    --[[
    A hint is only as wide as the gap to the next field, so it can never run into its
    neighbour's. The first version left them at their natural width and "tag, or blank to
    follow the name" printed straight through "raid days and times".

    Nothing wraps: a hint that no longer fits is a hint that needs shortening, and a second
    line here would push the fields out of the panel.
    ]]
    local function LayoutHints(fields)
        for i, box in ipairs(fields) do
            local nextX = fields[i + 1] and fields[i + 1].x or APPLY_X
            box.hint:SetWidth(nextX - box.x - 6)
            box.hint:SetWordWrap(false)
            if box.hint.SetMaxLines then box.hint:SetMaxLines(1) end
        end
    end

    local roleBox = Field(140, 8, "role")
    local classBox = Field(140, 154, "class, or blank for any")
    local countBox = Field(44, 300, "how many")
    local needFields = { roleBox, classBox, countBox }

    -- "tag" and nothing more: the label above the fields already explains what a tag is
    -- for and what clearing it does, and there are only 80 pixels here.
    local nameBox = Field(140, 8, "team name")
    local tagBox = Field(80, 154, "tag")
    local daysBox = Field(220, 240, "raid days and times")
    local teamFields = { nameBox, tagBox, daysBox }

    LayoutHints(needFields)
    LayoutHints(teamFields)

    nameBox:SetMaxLetters(ns.Teams.MAX_NAME)
    tagBox:SetMaxLetters(ns.Teams.MAX_TAG)
    daysBox:SetMaxLetters(ns.Teams.MAX_DAYS)
    roleBox:SetMaxLetters(ns.Teams.MAX_ROLE)
    classBox:SetMaxLetters(ns.Teams.MAX_CLASS)
    countBox:SetMaxLetters(3)

    -- Show/Hide rather than SetShown: a hint is a FontString, and every other SetShown in
    -- this addon is on a Frame.
    local function ShowFields(fields, on)
        for _, box in ipairs(fields) do
            if on then box:Show() else box:Hide() end
            if on then box.hint:Show() else box.hint:Hide() end
        end
    end

    local apply = UI.Button(editor, "Apply", 70, 22, { kind = "accent" })
    apply:SetPoint("TOPLEFT", APPLY_X, -32)
    local cancel = UI.Button(editor, "Cancel", 70, 22)
    cancel:SetPoint("TOPLEFT", APPLY_X + 76, -32)

    local t
    t = UI.Table(page, {
        top = -98,
        columns = {
            { key = "role", label = "Needs", width = "flex" },
            { key = "class", label = "Class", width = 130 },
            { key = "count", label = "How many", width = 70, justify = "RIGHT" },
            { key = "priority", label = "Priority", width = 60, justify = "RIGHT" },
        },
        buttons = {
            { key = "edit", label = "Edit", width = 50 },
            { key = "onoff", label = "On", width = 34 },
            { key = "up", label = "^", width = 24 },
            { key = "del", label = "X", width = 24, kind = "danger" },
        },
    })

    -- Where the button column starts, so a Span can stop before it. Read off the table
    -- rather than written down: the old hardcoded 548 was silently wrong the moment a
    -- fourth button moved the packing.
    local SPAN_W = (t.buttons[1] and t.buttons[1].x or t.width) - 12

    --------------------------------------------------------------------------
    -- Editing
    --------------------------------------------------------------------------

    local function Bump()
        local me = ns.Roster.Short(UnitName and UnitName("player") or "")
        ns.Doc.Bump(ns.db.doc, me, ns.Roster.GuildName(), ns.Now(), ns.db.highestSeenRev)
        ns.db.highestSeenRev = ns.db.doc.rev
    end

    -- Opens on the need ITSELF, never on its position. Rows are drawn in sorted
    -- order and the storage array is not sorted, so an index taken from the list
    -- points at a different need the moment anybody uses the priority button.
    local function Open(teamID, need)
        editing = { kind = "need", teamID = teamID, need = need }
        roleBox:SetText(need and need.role or "DPS")
        classBox:SetText(need and need.class or "")
        countBox:SetText(tostring(need and need.count or 1))
        UI.Refresh()
    end

    -- The team's own details. Opened on the team, for the same reason Open is opened on
    -- the need: a position in the list is not a stable name for anything.
    local function OpenTeam(team)
        editing = { kind = "team", teamID = team.id }
        nameBox:SetText(team.name or "")
        tagBox:SetText(team.tag or "")
        daysBox:SetText(team.days or "")
        UI.Refresh()
    end

    apply:SetScript("OnClick", function()
        if not editing or not ns.Roster.ICanAuthor() then return end
        local team = ns.Teams.ById(ns.db.doc, editing.teamID)
        if not team then editing = nil; UI.Refresh(); return end

        if editing.kind == "team" then
            ns.Teams.Edit(team, {
                name = nameBox:GetText(),
                tag = tagBox:GetText(),
                days = daysBox:GetText(),
            })
            editing = nil
            Bump()
            UI.Refresh()
            return
        end

        local need = editing.need
        if not need then
            if #team.needs >= ns.Doc.MAX_NEEDS then
                ns.Printf("%s already has %d needs, which is as many as fit in a message.",
                    team.name, ns.Doc.MAX_NEEDS)
                return
            end
            need = { priority = #team.needs + 1 }
            team.needs[#team.needs + 1] = need
        end
        need.role, need.class, need.count = roleBox:GetText(), classBox:GetText(),
            tonumber(countBox:GetText()) or 1
        ns.Teams.NormalizeNeed(need)

        editing = nil
        Bump()
        UI.Refresh()
    end)

    cancel:SetScript("OnClick", function()
        editing = nil
        UI.Refresh()
    end)

    addNeed:SetScript("OnClick", function()
        if not ns.Roster.ICanAuthor() then return end
        local team = ns.db.doc.teams[1]
        if editing then team = ns.Teams.ById(ns.db.doc, editing.teamID) or team end
        if not team then
            ns.Print("add a team first.")
            return
        end
        Open(team.id, nil)
    end)

    addTeam:SetScript("OnClick", function()
        if not ns.Roster.ICanAuthor() then return end
        if #ns.db.doc.teams >= ns.Doc.MAX_TEAMS then
            ns.Printf("%d teams is as many as fit in one message.", ns.Doc.MAX_TEAMS)
            return
        end
        local id = ns.Teams.NextId(ns.db.doc)
        local team = ns.Teams.New(id, "Team " .. id)
        ns.db.doc.teams[#ns.db.doc.teams + 1] = team
        Bump()
        -- Open it straight away: "Team 3" is a placeholder, not a name anybody wanted, and
        -- a new team with no days set is not yet worth putting in a message.
        OpenTeam(team)
    end)

    push:SetScript("OnClick", function()
        if not ns.Roster.ICanAuthor() then return end
        local ok, reason = ns.Comm.Broadcast()
        ns.Print(ok and ("sent rev " .. ns.db.doc.rev .. " to the guild.")
            or ("not sent: " .. tostring(reason)))
    end)

    --------------------------------------------------------------------------

    return function()
        local mine = ns.Roster.ICanAuthor()
        local why = string.format("Rank %d or better may change the teams. Yours is %d.",
            ns.db.settings.authorRankIndex, select(2, ns.Roster.Me()))
        UI.Gate(addNeed, mine, why)
        UI.Gate(addTeam, mine, why)
        UI.Gate(push, mine, why)
        UI.Gate(apply, mine, why)

        editor:SetShown(editing ~= nil)
        if editing then
            local team = ns.Teams.ById(ns.db.doc, editing.teamID)
            local isTeam = editing.kind == "team"
            ShowFields(needFields, not isTeam)
            ShowFields(teamFields, isTeam)
            if isTeam then
                editLabel:SetText(string.format("%s  \194\183  editing the team  \194\183  "
                    .. "|cff888888the tag is what goes in the message, so keep it short; "
                    .. "clear it to build one from the name|r",
                    team and team.name or "?"))
            else
                editLabel:SetText(string.format("%s  \194\183  %s  \194\183  |cff888888roles "
                    .. "are free text: %s, or whatever your raid leader calls it|r",
                    team and team.name or "?",
                    editing.need and "editing a need" or "a new need",
                    table.concat(ROLES, ", ")))
            end
        end

        -- One flat list: a heading per team, its needs under it.
        local list = {}
        for _, team in ipairs(ns.db.doc.teams) do
            list[#list + 1] = { team = team }
            for i, need in ipairs(ns.Teams.Sorted(team.needs)) do
                list[#list + 1] = { team = team, need = need, index = i }
            end
            if #team.needs == 0 then
                list[#list + 1] = { team = team, empty = true }
            end
        end

        t:Render(list, function(row, item)
            if item.need == nil and not item.empty then
                local team = item.team
                t:Span(row, string.format("%s%s|r  |cff888888%s  \194\183  %s  \194\183  %s|r",
                    team.active ~= false and "|cffffcc00" or "|cff888888",
                    team.name, team.tag,
                    team.days ~= "" and team.days or "no days set",
                    ns.Teams.NeedsSummary(team)))
                -- Span hides the cells, so the team's own controls live on its
                -- heading row's buttons, which Span also hid: put them back.
                -- Span sizes its text to the whole row, which is under the
                -- buttons this row puts back. Stop it before they start.
                row.span:SetWidth(SPAN_W)

                local edit = row.buttons.edit
                edit:Show()
                edit:SetText("Edit")
                UI.Gate(edit, mine, why)
                edit:SetScript("OnClick", function() OpenTeam(team) end)

                local toggle = row.buttons.onoff
                toggle:Show()
                toggle:SetText(team.active ~= false and "On" or "Off")
                UI.Gate(toggle, mine, why)
                toggle:SetScript("OnClick", function()
                    team.active = not (team.active ~= false)
                    Bump()
                    UI.Refresh()
                end)

                -- Array order is what Message.Rotate reads, so this decides which team
                -- leads the line, not just where the heading sits on screen.
                local first = ns.db.doc.teams[1] and ns.db.doc.teams[1].id == team.id
                local up = row.buttons.up
                up:Show()
                UI.Gate(up, mine and not first, first and "Already first." or why)
                up:SetScript("OnClick", function()
                    if ns.Teams.MoveUp(ns.db.doc, team.id) then
                        Bump()
                        UI.Refresh()
                    end
                end)

                local last = #ns.db.doc.teams > 1
                local remove = row.buttons.del
                remove:Show()
                UI.Gate(remove, mine and last,
                    last and why or "The guild needs at least one team.")
                remove:SetScript("OnClick", function()
                    local gone, reason = ns.Teams.Remove(ns.db.doc, team.id)
                    if not gone then
                        ns.Printf("not removed: %s.", tostring(reason))
                        return
                    end
                    -- The editor may be open on the team that just went.
                    if editing and editing.teamID == team.id then editing = nil end
                    Bump()
                    UI.Refresh()
                end)
                return
            end

            if item.empty then
                t:Set(row, "role", "|cff888888nothing needed; this team is left out of the "
                    .. "message|r")
                for _, btn in pairs(row.buttons) do btn:Hide() end
                return
            end

            local need = item.need
            t:Set(row, "role", "   " .. need.role)
            t:Set(row, "class", need.class ~= "" and need.class or "|cff888888any|r")
            t:Set(row, "count", tostring(need.count))
            t:Set(row, "priority", tostring(need.priority))

            -- On/Off belongs to a team, not to a need. Render shows every button again
            -- before this runs, so a need row has to put it back down.
            row.buttons.onoff:Hide()

            row.buttons.edit:SetText("Edit")
            UI.Gate(row.buttons.edit, mine, why)
            row.buttons.edit:SetScript("OnClick", function()
                Open(item.team.id, need)
            end)

            UI.Gate(row.buttons.up, mine and item.index > 1,
                item.index > 1 and why or "Already first.")
            row.buttons.up:SetScript("OnClick", function()
                -- Priority decides what survives a message that will not fit, so
                -- moving something up is moving it out of the firing line.
                --
                -- Renumber by the order actually on screen and then swap, rather
                -- than nudging a number down: once two needs share a priority,
                -- decrementing one moves nothing and the button silently does
                -- nothing while still looking live.
                local order = ns.Teams.Sorted(item.team.needs)
                for i, other in ipairs(order) do other.priority = i end
                local above = order[item.index - 1]
                need.priority, above.priority = above.priority, need.priority
                Bump()
                UI.Refresh()
            end)

            UI.Gate(row.buttons.del, mine, why)
            row.buttons.del:SetScript("OnClick", function()
                for i, other in ipairs(item.team.needs) do
                    if other == need then table.remove(item.team.needs, i) break end
                end
                Bump()
                UI.Refresh()
            end)
        end)

        local msg, _, dropped = ns.Bark.Preview()
        local parts = { string.format("%d needed", ns.Teams.TotalNeeded(ns.db.doc)) }
        if msg then
            parts[#parts + 1] = string.format("%d of %d characters", #msg, ns.Message.MAX_LEN)
        end
        if (dropped or 0) > 0 then
            parts[#parts + 1] = string.format("|cffffcc00%d will not fit|r", dropped)
        end
        if not mine then parts[#parts + 1] = "|cff888888read only|r" end
        hint:SetText("|cff888888" .. table.concat(parts, "  \194\183  ") .. "|r")
    end
end)
