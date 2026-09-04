-- The Deaths tab: who gets announced when they die, and where.
--
-- Tank and healer calls are configured apart all the way down. They share this
-- screen and nothing else: two sets of controls side by side, and one boss list
-- carrying a tick for each kind, so you can see at a glance that Naj'entus
-- calls healers and Illidan calls both.
local MFD = _G.MarkedForDeath or {}

MFD.UI = MFD.UI or {}
MFD.UI.Deaths = MFD.UI.Deaths or {}
local Deaths = MFD.UI.Deaths

local ROW_HEIGHT = 18       -- pixels per boss row
local COLUMN_WIDTH = 210    -- pixels per raid column
local TICK_SIZE = 16        -- pixels per per-kind checkbox
local MIN_COLUMN_ROWS = 6   -- floor if the height cannot be read yet

local GREEN, RED, GREY, AMBER = "|cff66ff66", "|cffff4444", "|cff999999", "|cffffcc66"

-- Which kind each tick column belongs to, left to right.
local KIND_ORDER = { "tank", "healer" }
local KIND_SHORT = { tank = "T", healer = "H" }

local function settings(kind)
    return MFD.db.settings.deaths[kind]
end

-- One block of controls, built once per kind. Everything reads and writes only
-- its own kind's settings.
local function togglesFor(kind)
    local label = MFD.Encounters.KIND_LABELS[kind]
    local isTank = kind == "tank"

    return {
        {
            label = "Announce when a " .. (isTank and "main tank" or "healer") .. " dies",
            tip = isTank
                and "Posts the name as a raid warning. Only the Raid Lead's client announces, so the raid sees it once. Tanks come from the raid's own Main Tank assignment plus anyone you type below."
                or "Healers are recognised by spec, which the addon learns by inspection for the raid check grid, plus anyone you type below.",
            get = function() return settings(kind).isEnabled end,
            set = function(v) settings(kind).isEnabled = v end,
        },
        {
            label = "Announce " .. label:lower() .. " deaths on trash",
            tip = "Trash is one yes or no rather than a list, because nobody wants to tick five hundred mobs. Bosses are picked individually below.",
            get = function() return settings(kind).onTrash end,
            set = function(v) settings(kind).onTrash = v end,
        },
    }
end

local function editFor(kind)
    local isTank = kind == "tank"

    return {
        label = isTank and "Extra tanks" or "Extra healers",
        tip = isTank
            and "Whoever the raid flags as Main Tank is picked up automatically. Only type names the raid does not flag. Commas between them."
            or "Anyone whose spec the addon has read as Holy, Discipline or Restoration already counts. Type names here for people it cannot see.",
        get = function() return settings(kind).names end,
        set = function(v) settings(kind).names = v end,
        preview = function(text)
            if isTank then
                local parts = {}
                local assigned = {}
                for name in pairs(MFD.Tanks.AssignedTanks()) do
                    assigned[#assigned + 1] = name
                end
                table.sort(assigned)

                if #assigned > 0 then
                    parts[#parts + 1] = GREEN .. "from the raid:|r " .. table.concat(assigned, ", ")
                else
                    parts[#parts + 1] = GREY .. "nobody set as Main Tank|r"
                end

                local typed = MFD.Tanks.ParseList(text)
                if #typed > 0 then
                    parts[#parts + 1] = GREEN .. "typed:|r " .. table.concat(typed, ", ")
                end
                return table.concat(parts, "   ")
            end

            -- Which healers the addon can actually see right now. Worth being
            -- able to answer before the pull rather than after somebody dies
            -- unannounced.
            local known = MFD.Healers.Known(MFD.Healers.KnownSpecs(), MFD.Tanks.ParseList(text))
            if #known == 0 then
                return AMBER .. "none recognised yet. Run a ready check, or type names.|r"
            end
            return GREEN .. "counted:|r " .. table.concat(known, ", ")
        end,
    }
end

local frame

local function refreshOverrides()
    for _, kind in ipairs(KIND_ORDER) do
        local button = frame.overrides and frame.overrides[kind]
        if button then
            local current = settings(kind).override
            local color = (current == "ON" and GREEN) or (current == "OFF" and RED) or ""
            button:SetText(color .. MFD.Encounters.OVERRIDE_LABELS[current] .. (color ~= "" and "|r" or ""))
        end
    end
end

local function refreshActive()
    if not frame or not frame.active then
        return
    end

    local active = MFD.Encounters.active
    if active then
        frame.active:SetText(GREEN .. "boss up: " .. active .. "|r")
    else
        frame.active:SetText(GREY .. "no boss detected right now|r")
    end
end

function Deaths:Refresh()
    if not frame or not frame:IsShown() then
        return
    end

    for _, check in ipairs(frame.checks or {}) do
        check:SetChecked(check.entry.get() and true or false)
    end

    for _, box in ipairs(frame.edits or {}) do
        if not box:HasFocus() then
            box:SetText(box.entry.get() or "")
        end
        box.preview:SetText(box.entry.preview(box:GetText()))
    end

    for _, check in ipairs(frame.bossChecks or {}) do
        check:SetChecked(settings(check.kind).bosses[check.bossName] and true or false)
    end

    refreshOverrides()
    refreshActive()
end

-- Ticks or unticks one kind across a whole instance. Forty three boxes twice
-- over is a lot of clicking for "the whole of Black Temple".
local function setInstance(kind, instance, value)
    for _, boss in ipairs(MFD.Data.Bosses) do
        if boss.instance == instance then
            settings(kind).bosses[boss.name] = value or nil
        end
    end
    Deaths:Refresh()
end

local function addCheck(entry, x, y)
    -- The library's check button carries its own label; nothing places one
    -- beside it by hand.
    local check = MFD.UI.CheckBox(frame, entry.label)
    check:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)

    check.entry = entry
    check:SetScript("OnClick", function(self)
        entry.set(self:GetChecked() and true or false)
    end)
    MFD.UI.Tooltip(check, function()
        GameTooltip:AddLine(entry.label, 1, 1, 1)
        GameTooltip:AddLine(entry.tip, 0.8, 0.8, 0.8, true)
    end)

    frame.checks[#frame.checks + 1] = check
end

local function addEdit(entry, x, y, width)
    local label = MFD.UI.CellLabel(frame, entry.label)
    label:SetPoint("TOPLEFT", frame, "TOPLEFT", x + 4, y - 4)
    label:SetWidth(84)

    local box = MFD.UI.EditBox(frame, width - 104, 20)
    box:SetPoint("LEFT", label, "RIGHT", 12, 0)
    box.entry = entry
    -- Escape comes with the library's box; Enter to commit does not.
    box:SetScript("OnEnterPressed", box.ClearFocus)

    box.preview = MFD.UI.CellLabel(frame, "", "GameFontDisableSmall")
    box.preview:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 4, -2)
    box.preview:SetWidth(width - 20)

    -- Set last, so the handler cannot fire against a preview that does not
    -- exist yet when SetText runs during the first refresh.
    box:SetScript("OnTextChanged", function(self)
        entry.set(self:GetText())
        self.preview:SetText(entry.preview(self:GetText()))
    end)

    frame.edits[#frame.edits + 1] = box
end

-- One kind's controls as a column. Returns the y it finished at.
local function buildKind(kind, x, width)
    local heading = MFD.UI.Label(frame, MFD.Encounters.KIND_LABELS[kind] .. " deaths", "GameFontNormal")
    heading:SetPoint("TOPLEFT", frame, "TOPLEFT", x + 4, -10)

    local y = -32
    for _, entry in ipairs(togglesFor(kind)) do
        addCheck(entry, x, y)
        y = y - 24
    end

    y = y - 4

    local overrideLabel = MFD.UI.CellLabel(frame, "Right now:")
    overrideLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", x + 4, y - 6)

    local button = MFD.UI.Button(frame, "", 130, 22)
    button:SetPoint("LEFT", overrideLabel, "RIGHT", 8, 0)
    button:SetScript("OnClick", function()
        MFD.Actions.Run("deaths_" .. kind)
    end)
    MFD.UI.Tooltip(button, function()
        GameTooltip:AddLine(MFD.Encounters.KIND_LABELS[kind] .. " deaths, right now", 1, 1, 1)
        GameTooltip:AddLine("Per boss follows the ticks below and the trash setting above. "
            .. "On everywhere announces every death of this kind, trash included. Off everywhere "
            .. "announces none. The other kind is not affected.", 0.8, 0.8, 0.8, true)
    end)

    frame.overrides[kind] = button
    y = y - 30

    addEdit(editFor(kind), x, y, width)

    return y - 40
end

-- The boss list. One row per encounter with a tick per kind, so both lists are
-- visible at once rather than hidden behind a mode switch.
local function buildBossList(top)
    local area = CreateFrame("Frame", nil, frame)
    area:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, top)
    area:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)

    -- The list scrolls. Laying it out to fit the height instead meant choosing
    -- however many columns that took, which was five, and five columns of two
    -- hundred and ten pixels do not fit a nine hundred pixel tab: Zul'Aman and
    -- Sunwell drew off the right edge. Width is the constraint that cannot be
    -- negotiated, so it decides the columns and the height gets a scrollbar.
    local list = MFD.UI.MakeScrollable(area)

    local width = area:GetWidth()
    if not width or width < COLUMN_WIDTH then
        width = MFD.UI.PAGE_W
    end
    -- 26 for the scrollbar the list now has.
    local maxColumns = math.max(1, math.floor((width - 26) / COLUMN_WIDTH))

    -- Every raid needs its bosses plus a heading and a gap, and no raid is ever
    -- split across two columns. Working the rows out by dividing the total by
    -- the columns is what put five columns in a tab with room for four: the
    -- tail of each column goes to waste when the next raid does not fit in it.
    local groups = MFD.Encounters.GroupByInstance(MFD.Data.Bosses)
    local sizes = {}
    for index, group in ipairs(groups) do
        sizes[index] = #group.bosses + 2
    end

    local maxRows = math.max(MIN_COLUMN_ROWS, MFD.Encounters.PackColumns(sizes, maxColumns))

    local column, rowIndex, deepest = 0, 0, 0

    for _, group in ipairs(groups) do
        -- A raid that would run past the bottom of its column starts a new one
        -- rather than being split across two.
        if rowIndex > 0 and rowIndex + #group.bosses + 2 > maxRows then
            column = column + 1
            rowIndex = 0
        end

        local left = column * COLUMN_WIDTH

        local heading = list:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        heading:SetPoint("TOPLEFT", list, "TOPLEFT", left, -rowIndex * ROW_HEIGHT)
        heading:SetText(group.instance)

        -- One all-or-none per kind, since the lists are independent.
        local previous
        for _, kind in ipairs(KIND_ORDER) do
            local all = CreateFrame("Button", nil, list)
            all:SetSize(18, 14)
            if previous then
                all:SetPoint("LEFT", previous, "RIGHT", 2, 0)
            else
                all:SetPoint("LEFT", heading, "RIGHT", 8, 0)
            end
            all.text = all:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            all.text:SetAllPoints()
            all.text:SetText(KIND_SHORT[kind])
            all.kind, all.instance = kind, group.instance

            all:SetScript("OnClick", function(self)
                -- Whether the click means all or none is read from what is
                -- there: anything unticked means the intent is to tick.
                local anyOff = false
                for _, boss in ipairs(MFD.Data.Bosses) do
                    if boss.instance == self.instance and not settings(self.kind).bosses[boss.name] then
                        anyOff = true
                    end
                end
                setInstance(self.kind, self.instance, anyOff)
            end)
            all:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine("All or none: " .. MFD.Encounters.KIND_LABELS[self.kind]
                    .. " deaths in " .. self.instance)
                GameTooltip:Show()
            end)
            all:SetScript("OnLeave", function() GameTooltip:Hide() end)

            previous = all
        end

        rowIndex = rowIndex + 1

        for _, boss in ipairs(group.bosses) do
            local y = -rowIndex * ROW_HEIGHT

            for index, kind in ipairs(KIND_ORDER) do
                -- No label on these: the boss's name is the row, shared by both
                -- ticks, so each box is bare and says which kind it is in its
                -- tooltip instead.
                local check = MFD.UI.CheckBox(list, "")
                check:SetSize(TICK_SIZE, TICK_SIZE)
                check:SetPoint("TOPLEFT", list, "TOPLEFT", left + (index - 1) * (TICK_SIZE + 2), y)

                check.bossName, check.kind = boss.name, kind
                check:SetScript("OnClick", function(self)
                    settings(self.kind).bosses[self.bossName] = self:GetChecked() and true or nil
                end)
                MFD.UI.Tooltip(check, function(self)
                    GameTooltip:AddLine(MFD.Encounters.KIND_LABELS[self.kind]
                        .. " deaths on " .. self.bossName, 1, 1, 1)
                end)

                frame.bossChecks[#frame.bossChecks + 1] = check
            end

            local label = list:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetPoint("TOPLEFT", list, "TOPLEFT",
                left + #KIND_ORDER * (TICK_SIZE + 2) + 4, y - 2)
            label:SetWidth(COLUMN_WIDTH - #KIND_ORDER * (TICK_SIZE + 2) - 12)
            label:SetJustifyH("LEFT")
            label:SetWordWrap(false)
            label:SetText(boss.name)

            rowIndex = rowIndex + 1
        end

        rowIndex = rowIndex + 1
        if rowIndex > deepest then
            deepest = rowIndex
        end
    end

    -- The scroll child has to be told how tall its content ended up or there is
    -- nothing for the bar to scroll through.
    list:SetHeight(deepest * ROW_HEIGHT + ROW_HEIGHT)
end

function Deaths:BuildInto(container)
    frame = container
    frame.checks = {}
    frame.edits = {}
    frame.bossChecks = {}
    frame.overrides = {}

    -- Two columns of controls, one per kind, so neither reads as a sub-setting
    -- of the other.
    local half = math.floor(((frame:GetWidth() or 860) - 32) / 2)
    local bottom = buildKind("tank", 16, half)
    buildKind("healer", 16 + half + 16, half)

    frame.active = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.active:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, bottom - 2)
    frame.active:SetJustifyH("LEFT")
    frame.active:SetWordWrap(false)

    local legend = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    legend:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, bottom - 18)
    legend:SetJustifyH("LEFT")
    legend:SetText("Per boss: left tick calls tanks, right tick calls healers.")

    buildBossList(bottom - 36)

    frame:SetScript("OnShow", function()
        Deaths:Refresh()
    end)
end

_G.MarkedForDeath = MFD
