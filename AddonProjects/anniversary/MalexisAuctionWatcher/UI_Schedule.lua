-- UI_Schedule.lua - The Schedule tab: this week's plan, and one item's week as a grid
local addonName = "MalexisAuctionWatcher"
local MAW = _G.MalexisAuctionWatcher
local MAWUI = _G.MalexisAuctionWatcherUI
local K = MAWUI.kit
local C = K.colors

local HEAD_H = 66           -- toolbar plus the hint under it
local DAY_STRIP_TOP = -72    -- the seven days, from the week's first
local BLOCK_STRIP_TOP = -98  -- the six blocks under the chosen day, plus all of it
local PLAN_TOP = 126        -- where the plan's table starts, under both strips
local PICKER_CHUNK = 24

local BADGE = {
    buy  = { text = "BUY",  color = C.LOW,  verb = "buy at or under" },
    sell = { text = "SELL", color = C.HIGH, verb = "list at or over" },
}

-- Where a block's expectation came from, in the words a row shows.
local function Basis(entry)
    if entry.basis == "weeks" then
        return string.format("%d weeks of scans", entry.weeksSeen), C.WHITE
    elseif entry.basis == "model" then
        return string.format("modelled from %d history samples", entry.samples or 0), C.TSM
    elseif entry.basis == "partial" then
        return string.format("%d week so far", entry.weeksSeen), C.DIM
    end
    return "", C.DIM
end
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

    -- Keep only the rows whose actual is already on the right side of the target
    view.fitBtn = bar:Left(K.Button(bar, "Rows: All", 130, 22))
    K.Tooltip(view.fitBtn, function()
        GameTooltip:AddLine("Which rows to show", 1, 1, 1)
        GameTooltip:AddLine("All: every scheduled block. On target: only the rows whose latest actual "
            .. "already sits at or under a buy target, or at or over a sell target.", 0.8, 0.8, 0.8, true)
    end)
    view.fitBtn:SetScript("OnClick", function()
        view.onlyFit = not view.onlyFit
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

    -- One day at a time, and one block of it or all six: a whole week in one list was
    -- too much to read. The strips are rebuilt when the week's first day moves, since a
    -- strip's names are fixed when it is built.
    local function BuildStrips(weekStart)
        if view.dayStrip then
            view.dayStrip:Hide()
            view.blockStrip:Hide()
        end
        local dayNames = {}
        for d = 1, 7 do dayNames[d] = MAW.WEEKDAY_NAMES[(weekStart - 1 + d - 1) % 7 + 1] end
        view.dayStrip = K.ICUI:TabStrip(page, {
            style = K.STYLE, names = dayNames, top = DAY_STRIP_TOP, left = 0, width = 90, height = 22,
            onSelect = function(_, index)
                view.day = index
                MAWUI:RefreshData()
            end,
        })
        local blockNames = { "All day" }
        for _, label in ipairs(MAW.BLOCK_LABELS) do blockNames[#blockNames + 1] = label end
        view.blockStrip = K.ICUI:TabStrip(page, {
            style = K.STYLE, names = blockNames, top = BLOCK_STRIP_TOP, left = 0, width = 80, height = 22,
            onSelect = function(_, index)
                view.block = index - 1
                MAWUI:RefreshData()
            end,
        })
        view.builtWeekStart = weekStart
    end

    -- The plan: one row per action in one block of the chosen day
    view.plan = K.Table(page, {
        top = -PLAN_TOP, bottom = 20,
        columns = {
            { key = "badge",    label = "",         width = 60 },
            { key = "when",     label = "When",     width = 96 },
            { key = "name",     label = "Check",    width = 230, hit = true },
            { key = "target",   label = "Target",   width = 130 },
            { key = "actual",   label = "Actual",   width = 90, justify = "RIGHT" },
            { key = "status",   label = "Status",   width = 70 },
            { key = "counter",  label = "Then",     width = 250 },
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

    local function RefreshPlan(self, sc, offset, opts, weekStartTime)
        local plan = MAW:GetWeekPlan()
        local rows = {}
        local day = plan.days[self.day] or plan.days[1]
        local title = date("%A %d %b", weekStartTime + (self.day - 1) * 86400)
        if self.block > 0 then title = title .. ", " .. MAW.BLOCK_LABELS[self.block] end
        rows[#rows + 1] = { kind = "section", title = title }
        local shown, hidden = 0, 0
        for _, r in ipairs(day.rows) do
            if self.block == 0 or r.block == self.block then
                if self.onlyFit and MAW.RowOnTarget(r) ~= true then
                    hidden = hidden + 1
                else
                    rows[#rows + 1] = r
                    shown = shown + 1
                end
            end
        end
        if shown == 0 then
            rows[#rows + 1] = { kind = "empty", text = hidden > 0
                and string.format("nothing on target yet; %d row%s hidden", hidden, hidden == 1 and "" or "s") or nil }
        end
        plan.hidden = hidden
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
                t:Span(row, entry.text or "nothing scheduled", C.DIM)
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
            -- The block, and the hour inside it this item is usually cheapest or dearest
            t:Set(row, "when", MAW.BLOCK_LABELS[entry.block]
                .. (entry.hour and string.format("  |cffffd100%02d:00|r", entry.hour) or ""), C.WHITE)
            t:Set(row, "name", entry.name, C.BONE)
            t:Set(row, "target", (entry.action == "buy" and "<= " or ">= ") .. K.FormatMoney(entry.expected), badge.color)
            local onTarget = MAW.RowOnTarget(entry)
            t:Set(row, "actual", entry.actual and K.FormatMoney(entry.actual.avg) or "-",
                onTarget == true and badge.color or (entry.actual and C.WHITE or C.DIM))
            local st = STATUS[entry.status] or STATUS.pending
            t:Set(row, "status", st.text, st.color)
            -- The other half of the trade: when the item's next opposite block comes,
            -- its target, and what the round trip is worth.
            local c = entry.counter
            if c then
                local other = BADGE[c.action]
                t:Set(row, "counter", string.format("%s %s%s %s%s %s%s",
                    other.text:lower(), c.nextWeek and "next " or "", MAW.WEEKDAY_NAMES[c.wday],
                    MAW.BLOCK_LABELS[c.block], c.hour and string.format(" %02d:00", c.hour) or "",
                    (c.action == "buy" and "<= " or ">= ") .. K.FormatMoney(c.expected),
                    entry.gain and string.format("  %+.0f%%", entry.gain * 100) or ""), other.color)
            else
                t:Set(row, "counter", entry.action == "buy" and "no sell block on its week" or "no buy block on its week", C.DIM)
            end
            local heldText, heldColor = Held(entry.hits, entry.misses)
            t:Set(row, "held", heldText, heldColor)
            if entry.now then t:Tint(row, K.STYLE.selectedBg) end

            local db = MAW:GetActiveDB()
            K.Tooltip(row.hit.name, function()
                GameTooltip:AddLine(entry.name)
                GameTooltip:AddLine(string.format("%s %s: check the price, %s %s", MAW.WEEKDAY_NAMES[math.floor((entry.slot - 1) / MAW.SLOTS_PER_DAY) + 1],
                    MAW.BLOCK_LABELS[entry.block], badge.verb, K.FormatMoney(entry.expected)), 0.9, 0.7, 1)
                if entry.hour then
                    GameTooltip:AddDoubleLine("Best hour in the block", string.format("%02d:00, its %s hour on record", entry.hour,
                        entry.action == "buy" and "cheapest" or "dearest"), 1, 1, 1, 1, 0.85, 0.3)
                end
                if onTarget ~= nil then
                    GameTooltip:AddDoubleLine("Right now", onTarget and "on target: act" or "not there yet", 1, 1, 1,
                        onTarget and 0.55 or 0.98, onTarget and 0.95 or 0.56, onTarget and 0.55 or 0.52)
                end
                if c then
                    GameTooltip:AddDoubleLine("Then", string.format("%s %s%s %s at %s", c.action == "buy" and "buy" or "sell",
                        c.nextWeek and "next " or "", MAW.WEEKDAY_NAMES[c.wday], MAW.BLOCK_LABELS[c.block],
                        K.FormatMoney(c.expected)), 1, 1, 1, 1, 0.9, 0.6)
                    if entry.gain then
                        GameTooltip:AddDoubleLine("Round trip", string.format("%+.0f%% between the two targets, before the cut", entry.gain * 100),
                            1, 1, 1, 1, 0.9, 0.6)
                    end
                end
                GameTooltip:AddDoubleLine("From", (Basis(entry)), 1, 1, 1, 0.8, 0.8, 0.8)
                GameTooltip:AddDoubleLine("Expected", K.FormatMoney(entry.expected) .. " (" .. Basis(entry) .. ")", 1, 1, 1, 1, 0.8, 0.5)
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
                    if s.basis == "model" then text = text .. "~" elseif s.basis == "partial" then text = text .. "?" end
                    color = schedule.flat and C.WHITE or K.GetPriceColor(s.expected, schedule.min, schedule.max, invert)
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
                        GameTooltip:AddDoubleLine("Expected", K.FormatMoney(s.expected) .. " (" .. Basis(s) .. ")", 1, 1, 1, 1, 0.8, 0.5)
                        if s.basis ~= "weeks" then
                            GameTooltip:AddLine(string.format("Becomes a real expectation after %d complete week%s of scans in this block.",
                                opts.minWeeks, opts.minWeeks == 1 and "" or "s"), 0.7, 0.7, 0.7, true)
                        end
                    else
                        GameTooltip:AddLine("Nothing to go on: no scan in this block and too little history to model it.", 0.7, 0.7, 0.7, true)
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
        self.fitBtn:SetText("Rows: " .. (self.onlyFit and "On target" or "All"))
        self.fitBtn:SetShown(self.mode == "plan")
        self.dropdown:SetShown(self.mode == "grid")
        if self.mode == "grid" then
            UIDropDownMenu_SetText(self.dropdown, GridItem() or "(nothing tracked)")
        end
        ShowTable(self.plan, self.mode == "plan")
        ShowTable(self.grid, self.mode == "grid")

        -- The week's first day, under the chosen clock
        local currentSlot, wday, block = MAW.ScheduleSlot(now, offset, sc.weekStart)
        local since = (wday - sc.weekStart) % 7
        local weekStartTime = now + offset - since * 86400
        local startText = date("%a %d %b", weekStartTime)

        -- The strips open on today, all day, and follow the week's first day
        if self.builtWeekStart ~= sc.weekStart then BuildStrips(sc.weekStart) end
        self.day = self.day or (since + 1)
        self.block = self.block or 0
        for i, b in ipairs(self.dayStrip.buttons) do
            b:SetActive(i == self.day)
            b:SetText(MAW.WEEKDAY_NAMES[(sc.weekStart - 1 + i - 1) % 7 + 1] .. (i == since + 1 and " *" or ""))
        end
        for i, b in ipairs(self.blockStrip.buttons) do
            b:SetActive(i - 1 == self.block)
            b:SetText((i == 1) and "All day" or (MAW.BLOCK_LABELS[i - 1] .. ((self.day == since + 1 and i - 1 == block) and " *" or "")))
        end
        self.dayStrip:SetShown(self.mode == "plan")
        self.blockStrip:SetShown(self.mode == "plan")
        local clockText = sc.clock == "server"
            and string.format("server clock%s", offset ~= 0 and string.format(" (%+dh)", offset / 3600) or "")
            or "your local clock"

        local summary
        if self.mode == "plan" then
            local plan = RefreshPlan(self, sc, offset, opts, weekStartTime)
            summary = string.format("%d item%s scheduled this week, %d set aside%s. * marks now.", plan.scheduled,
                plan.scheduled == 1 and "" or "s", #plan.setAside,
                self.onlyFit and string.format(", %d off-target row%s hidden", plan.hidden or 0, (plan.hidden or 0) == 1 and "" or "s") or "")
        else
            local schedule = RefreshGrid(self, sc, offset, opts)
            summary = schedule and (schedule.flat and "Flat week, nothing to schedule for this item."
                or string.format("Cheap end %s, dear end %s.", K.FormatMoney(schedule.min), K.FormatMoney(schedule.max)))
                or "Nothing tracked."
        end
        self.hint:SetText(string.format(
            "Week of %s, %s.  %s\nCheck the price in the block and act on the right side of the target. Targets: %d complete "
            .. "week%s of scans in the block, else modelled (~) from the History tab. A hit is within %d%%.",
            startText, clockText, summary, sc.minWeeks, sc.minWeeks == 1 and "" or "s", sc.tolerancePct))
    end

    return view
end

MAWUI.RegisterTab("schedule", "Schedule", BuildSchedulePage, "Scan Plan")
