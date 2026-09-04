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

    local roleBox = UI.EditBox(editor, 140, 22)
    roleBox:SetPoint("TOPLEFT", 8, -32)
    local classBox = UI.EditBox(editor, 140, 22)
    classBox:SetPoint("TOPLEFT", 154, -32)
    local countBox = UI.EditBox(editor, 44, 22)
    countBox:SetPoint("TOPLEFT", 300, -32)

    local roleHint = UI.Label(editor, "role", "GameFontDisableSmall")
    roleHint:SetPoint("BOTTOMLEFT", roleBox, "TOPLEFT", 2, 1)
    local classHint = UI.Label(editor, "class, or blank for any", "GameFontDisableSmall")
    classHint:SetPoint("BOTTOMLEFT", classBox, "TOPLEFT", 2, 1)
    local countHint = UI.Label(editor, "how many", "GameFontDisableSmall")
    countHint:SetPoint("BOTTOMLEFT", countBox, "TOPLEFT", 2, 1)

    local apply = UI.Button(editor, "Apply", 70, 22, { kind = "accent" })
    apply:SetPoint("TOPLEFT", 352, -32)
    local cancel = UI.Button(editor, "Cancel", 70, 22)
    cancel:SetPoint("TOPLEFT", 428, -32)

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
            { key = "up", label = "^", width = 24 },
            { key = "del", label = "X", width = 24, kind = "danger" },
        },
    })

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
        editing = { teamID = teamID, need = need }
        roleBox:SetText(need and need.role or "DPS")
        classBox:SetText(need and need.class or "")
        countBox:SetText(tostring(need and need.count or 1))
        UI.Refresh()
    end

    apply:SetScript("OnClick", function()
        if not editing or not ns.Roster.ICanAuthor() then return end
        local team = ns.Teams.ById(ns.db.doc, editing.teamID)
        if not team then editing = nil; UI.Refresh(); return end

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
        ns.db.doc.teams[#ns.db.doc.teams + 1] = ns.Teams.New(id, "Team " .. id)
        Bump()
        UI.Refresh()
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
            editLabel:SetText(string.format("%s  \194\183  %s  \194\183  |cff888888roles are "
                .. "free text: %s, or whatever your raid leader calls it|r",
                team and team.name or "?",
                editing.need and "editing a need" or "a new need",
                table.concat(ROLES, ", ")))
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
                -- Span sizes its text to the whole row, which is under the two
                -- buttons this row puts back. Stop it before they start.
                row.span:SetWidth(548)

                local toggle = row.buttons.edit
                toggle:Show()
                toggle:SetText(team.active ~= false and "On" or "Off")
                UI.Gate(toggle, mine, why)
                toggle:SetScript("OnClick", function()
                    team.active = not (team.active ~= false)
                    Bump()
                    UI.Refresh()
                end)

                local remove = row.buttons.del
                remove:Show()
                UI.Gate(remove, mine and #ns.db.doc.teams > 1,
                    #ns.db.doc.teams > 1 and why or "The guild needs at least one team.")
                remove:SetScript("OnClick", function()
                    for i, other in ipairs(ns.db.doc.teams) do
                        if other.id == team.id then table.remove(ns.db.doc.teams, i) break end
                    end
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
