local addonName, ns = ...

local UI = ns.UI

--[[
Every officer who is allowed to send, and which revision of the message they last
told us they had.

This is the tab that answers "why is Threnody sending the old line". Without it,
a client that never converged is invisible: everything still works from where you
are standing, and the guild sees two different messages.
]]

UI.RegisterPage(40, "Officers", function(page)
    local bar = UI.Toolbar(page, { top = 0, right = -26 })

    local refresh = bar:Left(UI.Button(bar, "Read roster", 100, 22))
    refresh:SetScript("OnClick", function()
        ns.Roster.Refresh(true)
        ns.Roster.Read()
        UI.Refresh()
    end)

    local sync = bar:Left(UI.Button(bar, "Ask for newer", 110, 22))
    sync:SetScript("OnClick", function()
        local ok, reason = ns.Comm.Request()
        ns.Print(ok and "asked the guild for a newer message."
            or ("not asked: " .. tostring(reason)))
    end)

    local push = bar:Left(UI.Button(bar, "Send mine", 90, 22, { kind = "accent" }))
    push:SetScript("OnClick", function()
        if not ns.Roster.ICanAuthor() then return end
        local ok, reason = ns.Comm.Broadcast()
        ns.Print(ok and ("sent rev " .. ns.db.doc.rev .. " to the guild.")
            or ("not sent: " .. tostring(reason)))
    end)

    local hint = bar:Right(UI.Label(page, "", "GameFontDisableSmall"))

    -- Three lines, and the table starts below three lines. Prose above a list
    -- needs a known height or it grows down into the header.
    local note = UI.Label(page, "", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", 0, -30)
    note:SetWidth(UI.PAGE_W - 20)
    note:SetHeight(48)
    note:SetSpacing(2)
    if note.SetMaxLines then note:SetMaxLines(3) end

    local t = UI.Table(page, {
        top = -84,
        columns = {
            { key = "name", label = "Officer", width = 130 },
            { key = "rank", label = "Rank", width = 130 },
            { key = "may", label = "May", width = 90 },
            { key = "rev", label = "Rev", width = 44, justify = "RIGHT" },
            { key = "heard", label = "Heard", width = 50, justify = "RIGHT" },
            { key = "barked", label = "Barked", width = 54, justify = "RIGHT" },
            { key = "state", label = "", width = "flex" },
        },
        onEnter = function(row, item)
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:AddLine(item.name, 1, 1, 1)
            GameTooltip:AddLine(string.format("%s, rank index %s", item.rank,
                tostring(item.rankIndex)), 0.8, 0.8, 0.8)
            if item.peer then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(string.format("last told us: rev %s",
                    tostring(item.peer.rev or "?")))
            else
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Has never said anything to this addon. Either they "
                    .. "are not running it, or they have not been online since you were.",
                    0.7, 0.7, 0.7, true)
            end
            GameTooltip:Show()
        end,
    })

    return function()
        local now = ns.Now()
        local settings = ns.db.settings
        local ours = ns.db.doc.rev or 0

        UI.Gate(push, ns.Roster.ICanAuthor(),
            string.format("Rank %d or better may push the message.", settings.authorRankIndex))

        -- Everyone allowed to send it, plus anyone who has spoken to us even if
        -- their rank says they should not have.
        local list, seen = {}, {}
        for _, row in ipairs(ns.Roster.Sorted(ns.Roster.rows)) do
            if ns.Roster.MayBark(row.rankIndex, settings.barkRankIndex) then
                seen[row.name] = true
                list[#list + 1] = {
                    name = row.name, rank = row.rank, rankIndex = row.rankIndex,
                    online = row.online, peer = ns.db.peers[row.name],
                }
            end
        end
        for name, peer in pairs(ns.db.peers) do
            if not seen[name] then
                list[#list + 1] = {
                    name = name, rank = "not on the roster",
                    rankIndex = peer.rank, online = false, peer = peer, stranger = true,
                }
            end
        end

        t:Render(list, function(row, item)
            local peer = item.peer
            t:Set(row, "name", item.online and ("|cff44ff44" .. item.name .. "|r")
                or item.name)
            t:Set(row, "rank", item.rank)

            local may = "send"
            if ns.Roster.MayAuthor(item.rankIndex, settings.authorRankIndex) then
                may = "|cffffcc00edit|r"
            elseif item.stranger then
                may = "|cffff4444nothing|r"
            end
            t:Set(row, "may", may)

            if not peer then
                t:Set(row, "rev", "-")
                t:Set(row, "heard", "-")
                t:Set(row, "state", "|cff888888never heard from|r")
            else
                t:Set(row, "rev", tostring(peer.rev or "?"))
                local heard, heardColor = ns.Util.Freshness(peer.seenAt, now, 86400)
                t:Set(row, "heard", heard, heardColor)

                -- Green is in step, amber is not. One meaning per colour, and the
                -- words say which way they are out.
                if (peer.rev or 0) == ours then
                    t:Set(row, "state", "|cff44ff44has the current message|r")
                elseif (peer.rev or 0) < ours then
                    t:Set(row, "state", "|cffffcc00behind by " .. (ours - (peer.rev or 0))
                        .. "|r")
                else
                    t:Set(row, "state", "|cffffcc00ahead of you; press Ask for newer|r")
                end
            end

            t:Set(row, "barked", peer and peer.barkedAt
                and ns.Util.Freshness(peer.barkedAt, now, 0) or "-")
        end)

        local same, behind, ahead = ns.Doc.Agreement(ns.db.doc, ns.db.peers)
        local total = same + behind + ahead
        local status = ns.Comm.Status()

        -- The window's own status bar already carries the revision, so this is
        -- only what this page adds. Short enough to clear the buttons on its left.
        hint:SetText(string.format(
            "|cff888888%d of %d in step  \194\183  sent %d, heard %d, ignored %d|r",
            same, total, status.sent, status.received, status.rejected))

        local notes = {}
        if not status.available then
            notes[#notes + 1] = "|cffff4444This client has no addon message API,|r so this "
                .. "list will never fill in. /gr probe for detail."
        elseif total == 0 then
            notes[#notes + 1] = "|cff888888Nobody else has said anything yet. They have to "
                .. "be online and running this addon; press Ask for newer to prod them.|r"
        end
        if ahead > 0 then
            notes[#notes + 1] = string.format("|cffffcc00%d officer%s ahead of you.|r "
                .. "Press Ask for newer before you edit anything.",
                ahead, ahead == 1 and " is" or "s are")
        end
        notes[#notes + 1] = "|cff888888Rank thresholds are per client, so an officer "
            .. "whose copy disagrees with yours accepts messages yours ignores.|r"
        note:SetText(table.concat(notes, "\n"))
    end
end)
