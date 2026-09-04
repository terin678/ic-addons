-- The Deaths tab: who gets announced when they die, and on which bosses.
--
-- Tank and healer announcements share a boss list and one mid-raid override,
-- because during a fight you want one switch to reach for, not two.
local MFD = _G.MarkedForDeath or {}

MFD.UI = MFD.UI or {}
MFD.UI.Deaths = MFD.UI.Deaths or {}
local Deaths = MFD.UI.Deaths

local ROW_HEIGHT = 18       -- pixels per boss row
local COLUMN_WIDTH = 200    -- pixels per raid column
local HEADER_HEIGHT = 150   -- pixels reserved for the toggles above the list
local MAX_COLUMN_ROWS = 22  -- rows before a raid starts a new column

local GREEN, RED, GREY, AMBER = "|cff66ff66", "|cffff4444", "|cff999999", "|cffffcc66"

local function settings()
    return MFD.db.settings.deaths
end

-- The toggles above the boss list, in display order.
local TOGGLES = {
    {
        label = "Announce when a main tank dies",
        tip = "Posts the name as a raid warning. Only the Raid Lead's client announces, so the raid sees it once. Tanks come from the raid's own Main Tank assignment plus anyone you type below.",
        get = function() return settings().isTankAlertEnabled end,
        set = function(v) settings().isTankAlertEnabled = v end,
    },
    {
        label = "Tank deaths only on the bosses ticked below",
        tip = "Off by default, so tank deaths announce anywhere including trash, which is what they have always done. Tick this to hold them to the same boss list healer deaths use.",
        get = function() return settings().isTankBossOnly end,
        set = function(v) settings().isTankBossOnly = v end,
    },
    {
        label = "Announce when a healer dies",
        tip = "Always limited to the bosses ticked below, never trash. Healers are recognised by spec, which the addon learns by inspection for the raid check grid, plus anyone you type below.",
        get = function() return settings().isHealerAlertEnabled end,
        set = function(v) settings().isHealerAlertEnabled = v end,
    },
}

local EDITS = {
    {
        label = "Extra tanks",
        tip = "Whoever the raid flags as Main Tank is picked up automatically. Only type names the raid does not flag. Commas between them.",
        get = function() return settings().tankNames end,
        set = function(v) settings().tankNames = v end,
        preview = function(text)
            local parts = {}

            local assigned = {}
            for name in pairs(MFD.Tanks.AssignedTanks()) do
                assigned[#assigned + 1] = name
            end
            table.sort(assigned)

            if #assigned > 0 then
                parts[#parts + 1] = GREEN .. "from the raid:|r " .. table.concat(assigned, ", ")
            else
                parts[#parts + 1] = GREY .. "nobody is set as Main Tank in the raid frame|r"
            end

            local typed = MFD.Tanks.ParseList(text)
            if #typed > 0 then
                parts[#parts + 1] = GREEN .. "typed:|r " .. table.concat(typed, ", ")
            end

            return table.concat(parts, "   ")
        end,
    },
    {
        label = "Extra healers",
        tip = "Anyone whose spec the addon has read as Holy, Discipline or Restoration already counts. Type names here for people it cannot see, such as somebody who has never been in inspect range.",
        get = function() return settings().healerNames end,
        set = function(v) settings().healerNames = v end,
        preview = function(text)
            -- Which healers the addon can actually see right now. Worth being
            -- able to answer before the pull rather than after somebody dies
            -- unannounced.
            local known = MFD.Healers.Known(MFD.Healers.KnownSpecs(), MFD.Tanks.ParseList(text))
            if #known == 0 then
                return AMBER .. "no healers recognised yet. Open the raid check tab or run a ready "
                    .. "check so specs get read, or type names here.|r"
            end
            return GREEN .. "counted as healers:|r " .. table.concat(known, ", ")
        end,
    },
}

local frame

-- Paints the override button. Three states, one button, because during a fight
-- the question is "is this on right now" and a dropdown answers it slowly.
local function refreshOverride()
    if not frame or not frame.override then
        return
    end

    local current = settings().override
    local color = (current == "ON" and GREEN) or (current == "OFF" and RED) or ""
    frame.override:SetText(color .. MFD.Encounters.OVERRIDE_LABELS[current] .. (color ~= "" and "|r" or ""))
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
        check:SetChecked(settings().bosses[check.bossName] and true or false)
    end

    refreshOverride()
    refreshActive()
end

-- Ticks or unticks every boss in one instance at once. Forty three boxes is a
-- lot of clicking for "the whole of Black Temple".
local function setInstance(instance, value)
    for _, boss in ipairs(MFD.Data.Bosses) do
        if boss.instance == instance then
            settings().bosses[boss.name] = value or nil
        end
    end
    Deaths:Refresh()
end

local function buildToggles()
    local y = -10

    for _, entry in ipairs(TOGGLES) do
        local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        check:SetSize(24, 24)
        check:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, y)

        local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", check, "RIGHT", 4, 0)
        label:SetText(entry.label)

        check.entry = entry
        check:SetScript("OnClick", function(self)
            entry.set(self:GetChecked() and true or false)
        end)
        check:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(entry.label)
            GameTooltip:AddLine(entry.tip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        check:SetScript("OnLeave", function() GameTooltip:Hide() end)

        frame.checks[#frame.checks + 1] = check
        y = y - 24
    end

    y = y - 6

    for _, entry in ipairs(EDITS) do
        local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, y - 4)
        label:SetWidth(90)
        label:SetJustifyH("LEFT")
        label:SetText(entry.label)

        local box = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
        box:SetSize(300, 20)
        box:SetPoint("LEFT", label, "RIGHT", 12, 0)
        box:SetAutoFocus(false)
        box.entry = entry
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

        box.preview = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        box.preview:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 4, -2)
        box.preview:SetPoint("RIGHT", frame, "RIGHT", -20, 0)
        box.preview:SetJustifyH("LEFT")
        box.preview:SetWordWrap(false)

        -- Set last, so the handler cannot fire against a preview that does not
        -- exist yet when SetText runs during the first refresh.
        box:SetScript("OnTextChanged", function(self)
            entry.set(self:GetText())
            self.preview:SetText(entry.preview(self:GetText()))
        end)

        frame.edits[#frame.edits + 1] = box
        y = y - 40
    end

    return y
end

local function buildOverride(y)
    local overrideLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    overrideLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, y - 6)
    overrideLabel:SetText("Right now:")

    frame.override = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.override:SetSize(130, 22)
    frame.override:SetPoint("LEFT", overrideLabel, "RIGHT", 8, 0)
    frame.override:SetScript("OnClick", function()
        settings().override = MFD.Encounters.NextOverride(settings().override)
        Deaths:Refresh()
    end)
    frame.override:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Right now")
        GameTooltip:AddLine("Per boss follows the ticks below. On everywhere announces on any boss "
            .. "regardless of the ticks. Off everywhere announces nothing at all. Trash is never "
            .. "announced under any of the three.", 1, 1, 1, true)
        GameTooltip:AddLine("Click to cycle. /mfd deaths does the same from a macro.", 0.6, 0.8, 1, true)
        GameTooltip:Show()
    end)
    frame.override:SetScript("OnLeave", function() GameTooltip:Hide() end)

    frame.active = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.active:SetPoint("LEFT", frame.override, "RIGHT", 12, 0)
    frame.active:SetJustifyH("LEFT")
end

-- The boss list, in columns by raid so all of it is visible at once. A
-- scrolling list of forty three would mean hunting for Supremus.
local function buildBossList()
    local list = CreateFrame("Frame", nil, frame)
    list:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -HEADER_HEIGHT)
    list:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)

    local column, rowIndex = 0, 0

    for _, group in ipairs(MFD.Encounters.GroupByInstance(MFD.Data.Bosses)) do
        -- A raid that would run off the bottom starts a new column instead of
        -- being split across two.
        if rowIndex > 0 and rowIndex + #group.bosses + 2 > MAX_COLUMN_ROWS then
            column = column + 1
            rowIndex = 0
        end

        local heading = list:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        heading:SetPoint("TOPLEFT", list, "TOPLEFT", column * COLUMN_WIDTH, -rowIndex * ROW_HEIGHT)
        heading:SetText(group.instance)

        local all = CreateFrame("Button", nil, list)
        all:SetSize(60, 14)
        all:SetPoint("LEFT", heading, "RIGHT", 8, 0)
        all.text = all:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        all.text:SetAllPoints()
        all.text:SetText("all / none")
        all.instance = group.instance
        all:SetScript("OnClick", function(self)
            -- Whether the click means all or none is read from what is there:
            -- anything unticked means the intent is to tick everything.
            local anyOff = false
            for _, boss in ipairs(MFD.Data.Bosses) do
                if boss.instance == self.instance and not settings().bosses[boss.name] then
                    anyOff = true
                end
            end
            setInstance(self.instance, anyOff)
        end)

        rowIndex = rowIndex + 1

        for _, boss in ipairs(group.bosses) do
            local check = CreateFrame("CheckButton", nil, list, "UICheckButtonTemplate")
            check:SetSize(18, 18)
            check:SetPoint("TOPLEFT", list, "TOPLEFT", column * COLUMN_WIDTH + 4, -rowIndex * ROW_HEIGHT)

            local label = list:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetPoint("LEFT", check, "RIGHT", 2, 0)
            label:SetWidth(COLUMN_WIDTH - 34)
            label:SetJustifyH("LEFT")
            label:SetWordWrap(false)
            label:SetText(boss.name)

            check.bossName = boss.name
            check:SetScript("OnClick", function(self)
                settings().bosses[self.bossName] = self:GetChecked() and true or nil
            end)

            frame.bossChecks[#frame.bossChecks + 1] = check
            rowIndex = rowIndex + 1
        end

        rowIndex = rowIndex + 1
    end
end

function Deaths:BuildInto(container)
    frame = container
    frame.checks = {}
    frame.edits = {}
    frame.bossChecks = {}

    buildOverride(buildToggles())
    buildBossList()

    frame:SetScript("OnShow", function()
        Deaths:Refresh()
    end)
end

_G.MarkedForDeath = MFD
