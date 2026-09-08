-- UI_Schedule.lua - The Schedule tab: this week's plan, and one item's week as a grid
local addonName = "MalexisAuctionWatcher"
local MAW = _G.MalexisAuctionWatcher
local MAWUI = _G.MalexisAuctionWatcherUI
local K = MAWUI.kit
local C = K.colors

local HEAD_H = 66           -- toolbar plus the hint under it
local PICKER_CHUNK = 24

local BADGE = {
    buy  = { text = "BUY",  color = C.LOW },
    sell = { text = "SELL", color = C.HIGH },
}
local STATUS = {
    now     = { text = "now",     color = C.GOLD },
    pending = { text = "ahead",   color = C.WHITE },
    hit     = { text = "hit",     color = C.LOW },
    miss    = { text = "miss",    color = C.HIGH },
    noscan  = { text = "no scan", color = C.DIM },
    seen    = { text = "seen",    color = C.DIM },
}

local function Held(hits, misses)
    local judged = (hits or 0) + (misses or 0)
    if judged == 0 then return "not judged yet", C.DIM end
    local text = string.format("held %d of %d weeks", hits, judged)
    return text, (hits / judged >= 0.5) and C.LOW or C.HIGH
end

-- The grid's item: saved, so the tab comes back where it was left; the first tracked
-- item when nothing was picked or the pick was untracked since.
local function GridItem()
    local sc = MAW:ScheduleSettings()
    local db = MAW:GetActiveDB()
    if sc.gridItem and db.items and db.items[sc.gridItem] then return sc.gridItem end
    local list = MAW:SortedTrackedItemNames()
    return list[1] and list[1].name or nil
end

-- Materials then products, each split into chunks a classic dropdown can show.
local function PickerGroups()
    local groups = {}
    local byType = { material = {}, product = {} }
    for _, it in ipairs(MAW:SortedTrackedItemNames()) do
        local list = byType[it.data.itemType or "material"] or byType.material
        list[#list + 1] = it.name
    end
    for _, kind in ipairs({ { "material", "Materials" }, { "product", "Products" } }) do
        local names = byType[kind[1]]
        table.sort(names)
        if #names <= PICKER_CHUNK then
            groups[#groups + 1] = { text = string.format("%s (%d)", kind[2], #names), entries = names }
        else
            local from = 1
            while from <= #names do
                local to = math.min(from + PICKER_CHUNK - 1, #names)
                local part = {}
                for i = from, to do part[#part + 1] = names[i] end
                groups[#groups + 1] = {
                    text = string.format("%s  %s - %s", kind[2], names[from]:sub(1, 3), names[to]:sub(1, 3)),
                    entries = part,
                }
                from = to + 1
            end
        end
    end
    return groups
end

local function BuildSchedulePage(page)
    local view = { mode = "plan" }

    local bar = K.Toolbar(page, { top = 0, height = 24 })
    view.clockBtn = bar:Left(K.Button(bar, "Clock: Server", 120, 22))
    K.Tooltip(view.clockBtn, function()
        GameTooltip:AddLine("Which clock the week runs on", 1, 1, 1)
        GameTooltip:AddLine("Server: the realm's, which raid resets and most players' evenings follow. "
            .. "Local: the clock on your wall.", 0.8, 0.8, 0.8, true)
    end)
    view.clockBtn:SetScript("OnClick", function()
        local sc = MAW:ScheduleSettings()
        sc.clock = (sc.clock == "server") and "local" or "server"
        MAWUI:RefreshData()
    end)

    view.modeBtn = bar:Left(K.Button(bar, "Show: Plan", 110, 22))
    view.modeBtn:SetScript("OnClick", function()
        view.mode = (view.mode == "plan") and "grid" or "plan"
        MAWUI:RefreshData()
    end)

    -- The grid's item picker, the History tab's two-level pattern
    local dropdown = CreateFrame("Frame", "MalexisAuctionWatcherScheduleDropdown", bar, "UIDropDownMenuTemplate")
    dropdown:SetPoint("LEFT", view.modeBtn, "RIGHT", -10, -2)
    UIDropDownMenu_SetWidth(dropdown, 220)
    UIDropDownMenu_Initialize(dropdown, function(_, level)
        if level == 1 then
            view.pickerGroups = PickerGroups()
            for index, group in ipairs(view.pickerGroups) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = group.text
                info.hasArrow = true
                info.notCheckable = true
                info.disabled = #group.entries == 0
                info.value = index
                UIDropDownMenu_AddButton(info, level)
            end
            return
        end
        local group = view.pickerGroups and view.pickerGroups[UIDROPDOWNMENU_MENU_VALUE]
        if not group then return end
        local current = GridItem()
        for _, name in ipairs(group.entries) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = name
            info.checked = (name == current)
            info.func = function()
                MAW:ScheduleSettings().gridItem = name
                CloseDropDownMenus()
                MAWUI:RefreshData()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    view.dropdown = dropdown

    view.hint = K.Note(page, "", K.STYLE.pageWidth - 26)
    view.hint:SetPoint("TOPLEFT", 0, -30)

    -- The plan: one row per action in one block, under a heading per day
    view.plan = K.Table(page, {
        top = -HEAD_H, bottom = 20,
        columns = {
            { key = "badge",    label = "",         width = 70 },
            { key = "when",     label = "When",     width = 90 },
            { key = "name",     label = "Item",     width = 260, hit = true },
            { key = "expected", label = "Expected", width = 90, justify = "RIGHT" },
            { key = "actual",   label = "Actual",   width = 90, justify = "RIGHT" },
            { key = "status",   label = "Status",   width = 80 },
            { key = "held",     label = "Pattern",  width = "flex" },
        },
    })

    -- The grid: seven rows from the week's first day, six blocks across
    local gridCols = { { key = "day", label = "Day", width = 60 } }
    for b, label in ipairs(MAW.BLOCK_LABELS) do
        gridCols[#gridCols + 1] = { key = "b" .. b, label = label, width = 130, justify = "RIGHT", hit = true }
    end
    gridCols[#gridCols + 1] = { key = "note", label = "", width = "flex" }
    view.grid = K.Table(page, { top = -HEAD_H, bottom = 20, columns = gridCols })

    local function ShowTable(t, on)
        t.header:SetShown(on)
        t.scroll:SetShown(on)
    end

    local function RefreshPlan(self, sc, offset, opts)
        local plan = MAW:GetWeekPlan()
        local rows = {}
        for _, day in ipairs(plan.days) do
            rows[#rows + 1] = { kind = "section", title = day.label }
            if #day.rows == 0 then
                rows[#rows + 1] = { kind = "empty" }
            else
                for _, r in ipairs(day.rows) do rows[#rows + 1] = r end
            end
        end
        if #plan.setAside > 0 then
            rows[#rows + 1] = { kind = "section", title = "Set aside: the pattern is not holding" }
            for _, s in ipairs(plan.setAside) do
                rows[#rows + 1] = { kind = "aside", name = s.name, reliability = s.reliability, judged = s.judged }
            end
        end

        local t = self.plan
        t:Render(rows, function(row, entry)
            if entry.kind == "section" then
                t:Span(row, entry.title, C.GOLD)
                t:Tint(row, K.STYLE.headerBg)
                return
            elseif entry.kind == "empty" then
                t:Span(row, "nothing scheduled", C.DIM)
                return
            elseif entry.kind == "aside" then
                t:Set(row, "name", entry.name, C.DIM)
                t:Set(row, "held", string.format("held %d%% of %d judged weeks; back on the plan when it climbs above %d%%",
                    math.floor((entry.reliability or 0) * 100 + 0.5), entry.judged, opts.minReliabilityPct), C.DIM)
                K.Tooltip(row.hit.name, nil)
                return
            end

            local badge = BADGE[entry.action]
            t:Set(row, "badge", badge.text, badge.color)
            t:Set(row, "when", MAW.BLOCK_LABELS[entry.block], C.WHITE)
            t:Set(row, "name", entry.name, C.BONE)
            t:Set(row, "expected", K.FormatMoney(entry.expected), C.WHITE)
            t:Set(row, "actual", entry.actual and K.FormatMoney(entry.actual.avg) or "-", entry.actual and C.WHITE or C.DIM)
            local st = STATUS[entry.status] or STATUS.pending
            t:Set(row, "status", st.text, st.color)
            local heldText, heldColor = Held(entry.hits, entry.misses)
            t:Set(row, "held", heldText, heldColor)
            if entry.now then t:Tint(row, K.STYLE.selectedBg) end

            local db = MAW:GetActiveDB()
            K.Tooltip(row.hit.name, function()
                GameTooltip:AddLine(entry.name)
                GameTooltip:AddLine(string.format("%s %s, %s", badge.text, MAW.WEEKDAY_NAMES[math.floor((entry.slot - 1) / MAW.SLOTS_PER_DAY) + 1],
                    MAW.BLOCK_LABELS[entry.block]), 0.9, 0.7, 1)
                GameTooltip:AddDoubleLine("Expected", K.FormatMoney(entry.expected)
                    .. string.format(" over %d weeks", entry.weeksSeen), 1, 1, 1, 1, 0.8, 0.5)
                if entry.low and entry.high then
                    GameTooltip:AddDoubleLine("Seen in this block", K.FormatMoney(entry.low) .. " - " .. K.FormatMoney(entry.high), 1, 1, 1, 0.8, 0.8, 0.8)
                end
                if entry.actual then
                    GameTooltip:AddDoubleLine("This week", K.FormatMoney(entry.actual.avg)
                        .. string.format(" (%d scan%s)", entry.actual.n, entry.actual.n == 1 and "" or "s"), 1, 1, 1, 1, 0.9, 0.6)
                end
                GameTooltip:AddDoubleLine("Pattern", heldText, 1, 1, 1, heldColor.r, heldColor.g, heldColor.b)
                local itemData = db.items[entry.name]
                if itemData and itemData.prices and itemData.prices[1] then
                    local latest = itemData.prices[1]
                    GameTooltip:AddDoubleLine("Latest price", K.FormatMoney(latest.buyoutPerUnit or latest.minBidPerUnit or 0)
                        .. " (" .. (latest.date or "?") .. ")", 1, 1, 1, 0.8, 0.8, 0.8)
                end
            end)
        end)
        return plan
    end

    local function RefreshGrid(self, sc, offset, opts)
        local name = GridItem()
        local t = self.grid
        if not name then
            t:Render({ { empty = true } }, function(row)
                t:Span(row, "Nothing tracked yet. Add items on Materials or Products.", C.DIM)
            end)
            return nil
        end
        local db = MAW:GetActiveDB()
        local itemData = db.items[name]
        local invert = (itemData.itemType or "material") == "product"
        local schedule = MAW:GetSchedule(name)

        local rows = {}
        for d = 1, 7 do
            local wday = (opts.weekStart - 1 + d - 1) % 7 + 1
            rows[d] = { wday = wday, label = MAW.WEEKDAY_NAMES[wday] }
        end
        t:Render(rows, function(row, day)
            t:Set(row, "day", day.label, C.GOLD)
            for b = 1, MAW.SLOTS_PER_DAY do
                local slot = (day.wday - 1) * MAW.SLOTS_PER_DAY + b
                local s = schedule.slots[slot]
                local key = "b" .. b
                local text, color = "-", C.DIM
                if s.expected then
                    text = K.FormatMoney(s.expected)
                    color = schedule.flat and C.WHITE or K.GetPriceColor(s.expected, schedule.min, schedule.max, invert)
                elseif s.mean then
                    text = K.FormatMoney(s.mean) .. "~"
                end
                if slot == schedule.currentSlot then
                    text = text .. "  <"
                    color = C.GOLD
                end
                t:Set(row, key, text, color)

                K.Tooltip(row.hit[key], function()
                    GameTooltip:AddLine(name)
                    GameTooltip:AddLine(day.label .. " " .. MAW.BLOCK_LABELS[b], 0.9, 0.7, 1)
                    if s.expected then
                        GameTooltip:AddDoubleLine("Expected", K.FormatMoney(s.expected) .. string.format(" over %d weeks", s.weeksSeen), 1, 1, 1, 1, 0.8, 0.5)
                    elseif s.mean then
                        GameTooltip:AddDoubleLine("So far", K.FormatMoney(s.mean) .. string.format(" from %d week%s; needs %d",
                            s.weeksSeen, s.weeksSeen == 1 and "" or "s", opts.minWeeks), 1, 1, 1, 0.8, 0.8, 0.8)
                    else
                        GameTooltip:AddLine("No scan has landed in this block yet.", 0.7, 0.7, 0.7)
                    end
                    if s.low and s.high then
                        GameTooltip:AddDoubleLine("Seen", K.FormatMoney(s.low) .. " - " .. K.FormatMoney(s.high), 1, 1, 1, 0.8, 0.8, 0.8)
                    end
                    if s.action then
                        local badge = BADGE[s.action]
                        GameTooltip:AddDoubleLine("Plan", badge.text, 1, 1, 1, badge.color.r, badge.color.g, badge.color.b)
                    end
                    local st = STATUS[s.status]
                    if s.actual then
                        GameTooltip:AddDoubleLine("This week", K.FormatMoney(s.actual.avg) .. string.format(" (%d scan%s)", s.actual.n, s.actual.n == 1 and "" or "s"),
                            1, 1, 1, st.color.r, st.color.g, st.color.b)
                    end
                    GameTooltip:AddDoubleLine("Status", st.text, 1, 1, 1, st.color.r, st.color.g, st.color.b)
                    if s.hits + s.misses > 0 then
                        local heldText, heldColor = Held(s.hits, s.misses)
                        GameTooltip:AddDoubleLine("Pattern", heldText, 1, 1, 1, heldColor.r, heldColor.g, heldColor.b)
                    end
                end)
            end
            local note = ""
            if day == rows[1] then
                if schedule.flat then
                    note = schedule.min and string.format("spread %.0f%%: nothing to schedule", schedule.spreadPct) or "no complete weeks yet"
                else
                    note = string.format("spread %.0f%%", schedule.spreadPct)
                end
            elseif day == rows[2] and schedule.reliability then
                note = string.format("held %d%%", math.floor(schedule.reliability * 100 + 0.5))
            end
            t:Set(row, "note", note, C.DIM)
        end)
        return schedule
    end

    function view:Refresh()
        local sc = MAW:ScheduleSettings()
        local opts = MAW:ScheduleOptions()
        local offset = opts.offset
        local now = time()

        self.clockBtn:SetText("Clock: " .. (sc.clock == "server" and "Server" or "Local"))
        self.modeBtn:SetText("Show: " .. (self.mode == "plan" and "Plan" or "Grid"))
        self.dropdown:SetShown(self.mode == "grid")
        if self.mode == "grid" then
            UIDropDownMenu_SetText(self.dropdown, GridItem() or "(nothing tracked)")
        end
        ShowTable(self.plan, self.mode == "plan")
        ShowTable(self.grid, self.mode == "grid")

        -- The week's first day, under the chosen clock
        local _, wday = MAW.ScheduleSlot(now, offset, sc.weekStart)
        local since = (wday - sc.weekStart) % 7
        local startText = date("%a %d %b", now + offset - since * 86400)
        local clockText = sc.clock == "server"
            and string.format("server clock%s", offset ~= 0 and string.format(" (%+dh)", offset / 3600) or "")
            or "your local clock"

        local summary
        if self.mode == "plan" then
            local plan = RefreshPlan(self, sc, offset, opts)
            summary = string.format("%d item%s scheduled, %d set aside.", plan.scheduled,
                plan.scheduled == 1 and "" or "s", #plan.setAside)
        else
            local schedule = RefreshGrid(self, sc, offset, opts)
            summary = schedule and (schedule.flat and "Flat week, nothing to schedule for this item."
                or string.format("Cheap end %s, dear end %s.", K.FormatMoney(schedule.min), K.FormatMoney(schedule.max)))
                or "Nothing tracked."
        end
        self.hint:SetText(string.format(
            "Week of %s, %s.  %s\nExpected = the mean of the last %d weeks per 4-hour block, after %d complete week%s; "
            .. "a hit is within %d%%. Fills in as weeks complete.",
            startText, clockText, summary, sc.weeks, sc.minWeeks, sc.minWeeks == 1 and "" or "s", sc.tolerancePct))
    end

    return view
end

MAWUI.RegisterTab("schedule", "Schedule", BuildSchedulePage, "Scan Plan")
