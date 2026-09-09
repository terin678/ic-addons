-- UI_Settings.lua - The Settings tab: every knob that used to live only behind a slash command
local addonName = "MalexisAuctionWatcher"
local MAW = _G.MalexisAuctionWatcher
local MAWUI = _G.MalexisAuctionWatcherUI
local K = MAWUI.kit
local C = K.colors
local ICUI = K.ICUI
local STYLE = K.STYLE

local COL_W = 470
local RIGHT_X = 500
local ROW_H = 26

local function Settings()
    return MalexisAuctionWatcherDB and MalexisAuctionWatcherDB.settings or {}
end

local function BuildSettingsPage(page)
    local view = { rows = {} }
    local ly, ry = -4, -4

    local function Label(parent, text, template)
        local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
        fs:SetJustifyH("LEFT")
        fs:SetText(text or "")
        return fs
    end

    local function Section(x, y, text)
        local fs = Label(page, text, "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", x, y)
        fs:SetTextColor(C.GOLD.r, C.GOLD.g, C.GOLD.b)
        return y - 20
    end

    -- A labelled number box. get() returns the value to show; set(number) applies it and
    -- returns the value that stuck (clamped) and a sentence for the status line, or nil
    -- and a reason. Enter applies; Escape and losing focus put the current value back.
    local function NumberRow(x, y, text, width, get, set)
        local label = Label(page, text)
        label:SetPoint("TOPLEFT", x, y - 4)
        label:SetWidth(width - 80)
        local box = ICUI:EditBox(page, 70, 22, { style = STYLE })
        box:SetPoint("TOPLEFT", x + width - 76, y)
        box:SetNumeric(false)
        box:SetScript("OnEnterPressed", function(self)
            local n = tonumber(self:GetText())
            if not n then
                view.status:SetText("|cffff8080Not a number.|r")
                self:SetText(tostring(get()))
                self:ClearFocus()
                return
            end
            local applied, note = set(n)
            if applied == nil then
                view.status:SetText("|cffff8080" .. tostring(note) .. "|r")
            else
                view.status:SetText(note or "")
            end
            self:ClearFocus()
            MAWUI:RefreshData()
        end)
        box:SetScript("OnEditFocusLost", function(self) self:SetText(tostring(get())) end)
        view.rows[#view.rows + 1] = { box = box, get = get }
        return y - ROW_H
    end

    local function CheckRow(x, y, text, get, set)
        local cb = ICUI:CheckBox(page, text, { style = STYLE })
        cb:SetPoint("TOPLEFT", x, y)
        cb:SetScript("OnClick", function(self)
            set(self:GetChecked() and true or false)
            MAWUI:RefreshData()
        end)
        view.rows[#view.rows + 1] = { check = cb, get = get }
        return y - ROW_H
    end

    -- A button that cycles through named choices
    local function CycleRow(x, y, text, width, get, set, describe)
        local label = Label(page, text)
        label:SetPoint("TOPLEFT", x, y - 4)
        label:SetWidth(width - 150)
        local btn = K.Button(page, "", 140, 22)
        btn:SetPoint("TOPLEFT", x + width - 146, y)
        btn:SetScript("OnClick", function()
            set(get())
            MAWUI:RefreshData()
        end)
        view.rows[#view.rows + 1] = { button = btn, get = get, describe = describe }
        return y - ROW_H
    end

    local function Pct(v) return math.floor((v or 0) * 100 + 0.5) end

    -- Left column: feeds, the auction house, Movers -------------------------------

    ly = Section(0, ly, "Price feeds")
    ly = CheckRow(0, ly, "Auctionator: current price and daily history",
        function() return MAW:IsSourceEnabled("auctionator") end,
        function(on) MAW:SetSourceEnabled("auctionator", on) end)
    ly = CheckRow(0, ly, "TradeSkillMaster: averages, sale rates, your Accounting",
        function() return MAW:IsSourceEnabled("tsm") end,
        function(on) MAW:SetSourceEnabled("tsm", on) end)
    view.feeds = Label(page, "", "GameFontDisableSmall")
    view.feeds:SetPoint("TOPLEFT", 0, ly - 2)
    view.feeds:SetWidth(COL_W - 10)
    ly = ly - 24

    ly = Section(0, ly, "Auction house")
    ly = NumberRow(0, ly, "House cut, percent (faction 5, neutral 15)", COL_W,
        function() return Pct(MAW:GetAHCut()) end,
        function(n)
            if MAW:SetAHCutPercent(n) then return n, string.format("Auction house cut set to %d%%.", n) end
            return nil, "The cut is a percentage from 0 to 50."
        end)
    ly = CheckRow(0, ly, "Scan tracked items whenever the auction house opens",
        function() return Settings().autoScan and true or false end,
        function(on) Settings().autoScan = on end)
    ly = NumberRow(0, ly, "Days of price history to keep (7 or more)", COL_W,
        function() return MAW:GetHistoryDays() end,
        function(n)
            if n < 7 then return nil, "Seven days is the least that still draws a weekday view." end
            Settings().historyDays = math.floor(n)
            return math.floor(n), string.format("Keeping %d days of history.", math.floor(n))
        end)

    ly = Section(0, ly - 6, "Movers")
    local function MoverPct(key, low, high, sentence)
        return function() return Pct(MAW:MoverSetting(key)) end,
            function(n)
                if n < low or n > high then return nil, string.format("Between %d and %d.", low, high) end
                Settings()[key] = n / 100
                return n, string.format(sentence, n)
            end
    end
    ly = NumberRow(0, ly, "Buy at or below this much of the range, percent", COL_W,
        MoverPct("moverBuyPct", 0, 100, "Buy when Today is at or below %d%% of the low-high range."))
    ly = NumberRow(0, ly, "List at or above this much of the range, percent", COL_W,
        MoverPct("moverSellPct", 0, 100, "List when Today is at or above %d%% of the range."))
    ly = NumberRow(0, ly, "Convert needs at least this margin, percent", COL_W,
        function() return MAW:MoverSetting("moverMinMargin") end,
        function(n)
            if n < 0 or n > 1000 then return nil, "A margin from 0 to 1000 percent." end
            Settings().moverMinMargin = n
            return n, string.format("Convert needs %d%% margin.", n)
        end)
    ly = NumberRow(0, ly, "Convert needs a TSM sale rate of, percent (0 off)", COL_W,
        MoverPct("moverMinSaleRate", 0, 100, "Convert needs a region sale rate of %d%%."))

    -- Right column: the schedule ------------------------------------------------------

    ry = Section(RIGHT_X, ry, "Schedule")
    ry = CycleRow(RIGHT_X, ry, "Clock the week runs on", COL_W,
        function() return MAW:ScheduleSettings().clock end,
        function(current) MAW:ScheduleSettings().clock = (current == "server") and "local" or "server" end,
        function(v) return v == "server" and "Server time" or "Local time" end)
    ry = CycleRow(RIGHT_X, ry, "The week starts on", COL_W,
        function() return MAW:ScheduleSettings().weekStart end,
        function(current) MAW:ScheduleSettings().weekStart = current % 7 + 1 end,
        function(v) return ({ "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" })[v] or "?" end)
    ry = NumberRow(RIGHT_X, ry, "A hit is within this much of the expected price, percent", COL_W,
        function() return MAW:ScheduleSettings().tolerancePct end,
        function(n)
            if n < 1 or n > 50 then return nil, "Between 1 and 50." end
            MAW:ScheduleSettings().tolerancePct = math.floor(n)
            return math.floor(n), string.format("A hit is within %d%% of the expected price.", math.floor(n))
        end)
    ry = NumberRow(RIGHT_X, ry, "Weeks an expectation is drawn from (4 to 12)", COL_W,
        function() return MAW:ScheduleSettings().weeks end,
        function(n)
            if n < 4 or n > 12 then return nil, "Between 4 and 12 weeks." end
            MAW:ScheduleSettings().weeks = math.floor(n)
            return math.floor(n), string.format("Expectations come from the last %d weeks.", math.floor(n))
        end)
    ry = NumberRow(RIGHT_X, ry, "Complete weeks a block needs before it counts (1 to 4)", COL_W,
        function() return MAW:ScheduleSettings().minWeeks end,
        function(n)
            if n < 1 or n > 4 then return nil, "Between 1 and 4 weeks." end
            MAW:ScheduleSettings().minWeeks = math.floor(n)
            return math.floor(n), string.format("A block needs %d complete week%s.", math.floor(n), n == 1 and "" or "s")
        end)
    ry = NumberRow(RIGHT_X, ry, "Set an item aside when its pattern held under, percent", COL_W,
        function() return MAW:ScheduleSettings().minReliabilityPct end,
        function(n)
            if n < 0 or n > 100 then return nil, "Between 0 and 100." end
            MAW:ScheduleSettings().minReliabilityPct = math.floor(n)
            return math.floor(n), string.format("Items whose pattern held under %d%% are set aside.", math.floor(n))
        end)
    local schedNote = Label(page, "The plan lists an item's cheap and dear blocks once a block has enough complete "
        .. "weeks behind it. After three judged weeks on those blocks, an item whose pattern held "
        .. "under the floor is set aside; the grid still shows it. The slash commands keep working "
        .. "and write the same settings.", "GameFontDisableSmall")
    schedNote:SetPoint("TOPLEFT", RIGHT_X, ry - 2)
    schedNote:SetWidth(COL_W - 10)
    schedNote:SetSpacing(2)

    view.status = K.Note(page, "", STYLE.pageWidth - 26)
    view.status:SetPoint("BOTTOMLEFT", 0, 24)

    function view:Refresh()
        for _, r in ipairs(self.rows) do
            if r.box then
                if not r.box:HasFocus() then r.box:SetText(tostring(r.get())) end
            elseif r.check then
                r.check:SetChecked(r.get() and true or false)
            elseif r.button then
                r.button:SetText(r.describe(r.get()))
            end
        end
        self.feeds:SetText(MAW:DescribeSources())
    end

    return view
end

MAWUI.RegisterTab("settings", "Settings", BuildSettingsPage)
