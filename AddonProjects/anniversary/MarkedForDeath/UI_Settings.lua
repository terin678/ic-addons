-- The settings window, and the same panel registered in Blizzard's addon
-- options list so it is findable without knowing a slash command.
--
-- Every toggle the addon has lives here. Before this, three of them could only
-- be changed by editing saved variables, which is not a setting, it is a
-- trapdoor.
local MFD = _G.MarkedForDeath or {}

MFD.UI = MFD.UI or {}
MFD.UI.Settings = MFD.UI.Settings or {}
local Settings = MFD.UI.Settings

local ROW_SPACING = 26      -- pixels between checkboxes
local SECTION_SPACING = 14  -- extra pixels above a section heading

-- Every toggle, in display order. get and set take and return a boolean, so a
-- setting stored in a nested table looks the same here as a flat one.
local TOGGLES = {
    { section = "Everything" },
    {
        label = "Addon enabled",
        tip = "The master switch. Off means no icons, no chat, no warnings, without unloading the addon or reloading. Nothing you have configured is lost.",
        get = function() return MFD.IsEnabled() end,
        set = function(v) MFD.SetEnabled(v) end,
    },

    { section = "Marking" },
    {
        label = "Place raid icons automatically",
        tip = "Turn this off to stop the addon marking anything without losing your rules or roles.",
        get = function() return MFD.db.settings.isMarkingEnabled end,
        set = function(v) MFD.db.settings.isMarkingEnabled = v end,
    },
    {
        label = "Announce assignments to raid chat on the pull",
        tip = "One compact line naming each icon, its job and its owner, for people not running the addon.",
        get = function() return MFD.db.settings.isAnnounceEnabled end,
        set = function(v) MFD.db.settings.isAnnounceEnabled = v end,
    },
    {
        label = "Warn when nameplate settings would break marking",
        tip = "Marking mobs you are not targeting needs enemy nameplates on. Without this warning it fails silently.",
        get = function() return MFD.db.settings.isCvarWarnEnabled end,
        set = function(v) MFD.db.settings.isCvarWarnEnabled = v end,
    },
    {
        label = "Use spare crowd control icons for extra kill targets",
        tip = "When no mob in the pack needs Moon, Star, Triangle or Diamond, hand them to kill targets rather than leaving them idle. A crowd control mob always takes its own icon back, even one that walks in late.",
        get = function() return MFD.db.settings.isIconReuseEnabled end,
        set = function(v) MFD.db.settings.isIconReuseEnabled = v end,
    },
    {
        label = "A mark placed by hand wins",
        tip = "If a tank marks a mob themselves, the addon keeps their icon on that mob and works everything else around it, instead of arguing with them. Take the mark off again and the addon takes the mob back.",
        get = function() return MFD.db.settings.isManualOverrideEnabled end,
        set = function(v) MFD.db.settings.isManualOverrideEnabled = v end,
    },
    {
        label = "Raid warning when crowd control turns up late",
        tip = "If a sheep or banish target appears after the pull, take its icon back, post a raid warning and whisper whoever owns that job.",
        get = function() return MFD.db.settings.isLateCCAlertEnabled end,
        set = function(v) MFD.db.settings.isLateCCAlertEnabled = v end,
    },
    {
        label = "Play a sound for crowd control that cannot land",
        tip = "Sounds when you rule a mob for something its creature type is immune to, such as banishing a humanoid.",
        get = function() return MFD.db.settings.isWarningSoundEnabled end,
        set = function(v) MFD.db.settings.isWarningSoundEnabled = v end,
    },

    { section = "Deaths" },
    {
        note = true,
        label = "Tank and healer death announcements, and which bosses they apply to, are on the Deaths tab.",
    },

    { section = "Raid check" },
    {
        label = "Open the grid on ready check (raid leader and assistants)",
        tip = "Everyone else still gathers the data quietly, so their buff board is current.",
        get = function() return MFD.db.settings.raidCheck.isAutoOpenEnabled end,
        set = function(v) MFD.db.settings.raidCheck.isAutoOpenEnabled = v end,
    },

    { section = "Interface" },
    {
        label = "Show the action bar",
        tip = "The bar of mid-pull buttons. Drag it anywhere, drag its corner to reshape it, and the buttons rewrap to fit.",
        get = function() return MFD.db.settings.actionBar.isShown end,
        set = function(v) MFD.UI.ActionBar:SetShown(v) end,
    },
    {
        label = "Lock the action bar",
        tip = "Hides its resize grip and refuses drags, so a stray click mid-fight cannot shove it across the screen. /mfd bar reset puts it back in the middle.",
        get = function() return MFD.db.settings.actionBar.isLocked end,
        set = function(v)
            MFD.db.settings.actionBar.isLocked = v
            MFD.UI.ActionBar:UpdateLock()
        end,
    },
    {
        label = "Show the minimap button",
        tip = "The button opens this menu. /mfd minimap brings it back if you hide it.",
        get = function() return not MFD.db.settings.minimap.hide end,
        set = function(v)
            MFD.db.settings.minimap.hide = not v
            if MFD.Minimap and MFD.Minimap.SetShown then
                MFD.Minimap:SetShown(v)
            end
        end,
    },
}

-- Windows reachable from the buttons at the bottom of the panel.
local SHORTCUTS = {
    { label = "Roles", open = function() MFD.UI.Config:Toggle() end },
    { label = "Rules", open = function() MFD.UI.Rules:Toggle() end },
    { label = "Raid check", open = function() MFD.UI.RaidCheck:Toggle() end },
    { label = "Buff board", open = function() MFD.UI.BuffBoard:Toggle() end },
}

local panel

-- Builds the panel body onto any parent, so the same layout serves both the
-- standalone window and the Blizzard options category.
local function buildBody(parent)
    parent.checks = {}
    parent.edits = {}
    local y = -12

    for _, entry in ipairs(TOGGLES) do
        if entry.section then
            y = y - SECTION_SPACING
            local heading = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            heading:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
            heading:SetText(entry.section)
            y = y - ROW_SPACING
        elseif entry.note then
            -- A pointer, not a control. Settings that moved elsewhere are worth
            -- saying so, otherwise they read as removed.
            local note = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            note:SetPoint("TOPLEFT", parent, "TOPLEFT", 24, y - 4)
            note:SetPoint("RIGHT", parent, "RIGHT", -20, 0)
            note:SetJustifyH("LEFT")
            note:SetText(entry.label)
            y = y - ROW_SPACING
        elseif entry.edit then
            local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetPoint("TOPLEFT", parent, "TOPLEFT", 24, y - 4)
            label:SetText(entry.label)

            local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
            box:SetSize(360, 20)
            box:SetPoint("LEFT", label, "RIGHT", 12, 0)
            box:SetAutoFocus(false)
            box.entry = entry
            -- Saved as you type rather than on enter, so a name typed and then
            -- forgotten still counts.
            box:SetScript("OnTextChanged", function(self)
                entry.set(self:GetText())
            end)
            box:SetScript("OnEscapePressed", function(self)
                self:ClearFocus()
            end)
            box:SetScript("OnEnterPressed", function(self)
                self:ClearFocus()
            end)

            -- Live feedback on what the text parsed to. A list field with no
            -- echo leaves you guessing whether the separator was right.
            if entry.preview then
                box.preview = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                box.preview:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 4, -2)
                box.preview:SetPoint("RIGHT", parent, "RIGHT", -20, 0)
                box.preview:SetJustifyH("LEFT")
                box:HookScript("OnTextChanged", function(self)
                    self.preview:SetText(entry.preview(self:GetText()))
                end)
                y = y - 14
            end

            parent.edits = parent.edits or {}
            parent.edits[#parent.edits + 1] = box
            y = y - ROW_SPACING
        else
            local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
            check:SetSize(24, 24)
            check:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, y)

            local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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
            check:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)

            parent.checks[#parent.checks + 1] = check
            y = y - ROW_SPACING
        end
    end

    y = y - SECTION_SPACING
    local heading = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    heading:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    heading:SetText("Windows")
    y = y - ROW_SPACING

    local previous
    for _, shortcut in ipairs(SHORTCUTS) do
        local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        button:SetSize(100, 22)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 6, 0)
        else
            button:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, y)
        end
        button:SetText(shortcut.label)
        button:SetScript("OnClick", shortcut.open)
        previous = button
    end

    y = y - ROW_SPACING - SECTION_SPACING

    parent.status = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    parent.status:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, y)
    parent.status:SetPoint("RIGHT", parent, "RIGHT", -20, 0)
    parent.status:SetJustifyH("LEFT")

    return parent
end

-- Repaints every checkbox from the saved settings, and the status line.
local function refreshBody(body)
    if not body or not body.checks then
        return
    end

    for _, check in ipairs(body.checks) do
        check:SetChecked(check.entry.get() and true or false)
    end

    for _, box in ipairs(body.edits or {}) do
        -- Only when unfocused: overwriting what somebody is halfway through
        -- typing is maddening.
        if not box:HasFocus() then
            box:SetText(box.entry.get() or "")
        end
        if box.preview then
            box.preview:SetText(box.entry.preview(box:GetText()))
        end
    end

    if body.status then
        local marker = MFD.Comms and MFD.Comms.authority
        body.status:SetText(string.format(
            "|cff999999version %s   marker: %s   rules here: %d|r",
            MFD.VERSION,
            tostring(marker or "nobody"),
            (function()
                local n = 0
                for _ in pairs(MFD.Rules.Active()) do n = n + 1 end
                return n
            end)()))
    end
end

function Settings:Refresh()
    if panel then
        refreshBody(panel.body)
    end
    if Settings.blizzardBody then
        refreshBody(Settings.blizzardBody)
    end
end

-- Builds the settings panel into a container the main window owns.
function Settings:BuildInto(container)
    panel = container
    panel.body = CreateFrame("Frame", nil, panel)
    panel.body:SetAllPoints(panel)
    buildBody(panel.body)
end

function Settings:Toggle()
    MFD.UI.Main:Toggle("settings")
end

-- Registers the same layout as a category under Blizzard's addon options, so
-- the addon is configurable by someone who never learns a slash command.
-- Guarded because the registration API differs by client generation.
local function registerBlizzardPanel()
    local category = CreateFrame("Frame")
    category.name = "Marked For Death"

    local body = CreateFrame("Frame", nil, category)
    body:SetAllPoints(category)
    buildBody(body)
    Settings.blizzardBody = body

    category:SetScript("OnShow", function()
        refreshBody(body)
    end)

    if InterfaceOptions_AddCategory then
        pcall(InterfaceOptions_AddCategory, category)
        Settings.blizzardCategory = category
    elseif _G.Settings and _G.Settings.RegisterCanvasLayoutCategory then
        local ok, registered = pcall(_G.Settings.RegisterCanvasLayoutCategory, category, category.name)
        if ok and registered then
            pcall(_G.Settings.RegisterAddOnCategory, registered)
            Settings.blizzardCategory = registered
        end
    end
end

MFD.RegisterInit(function()
    local ok, err = pcall(registerBlizzardPanel)
    if not ok then
        MFD.Error("could not add the options panel: " .. tostring(err))
    end
end)

_G.MarkedForDeath = MFD
