-- The things you do mid-pull, defined once.
--
-- A raid leader tanking ten mobs cannot type. Every one of these is a button on
-- the assignment panel, a keybind, and a slash command, and all three run the
-- same function from this table so they can never drift apart.
--
-- What belongs here is anything you would want between two globals of a fight.
-- Anything you sit down and configure belongs on a tab instead.
local MFD = _G.MarkedForDeath or {}

MFD.Actions = MFD.Actions or {}
local Actions = MFD.Actions

local GREEN, RED, GREY, AMBER = "|cff66ff66", "|cffff4444", "|cff999999", "|cffffcc66"

-- Lays out n buttons into rows that fit the width available. Returns an array
-- of { row, column } in order, and the number of rows. Pure, so the panel and
-- the tab can share one layout rule at two very different widths.
function Actions.Layout(count, availableWidth, buttonWidth, gap)
    local perRow = math.floor((availableWidth + gap) / (buttonWidth + gap))
    if perRow < 1 then
        perRow = 1
    end

    local slots = {}
    for index = 1, count do
        slots[index] = {
            row = math.floor((index - 1) / perRow),
            column = (index - 1) % perRow,
        }
    end

    return slots, math.ceil(count / perRow)
end

-- Each action: a stable key, the button text, a tooltip, what it does, and for
-- the ones that hold a state, how to paint themselves.
--
-- run returns nothing. Anything that can decline says so in chat itself, so the
-- button, the keybind and the command all report failure the same way.
Actions.LIST = {
    {
        key = "announce",
        label = "Announce",
        binding = "Announce the assignments",
        tip = "Post the current assignments to raid chat now, for calling a pack out before you pull it.",
        run = function()
            local ok, reason = MFD.Announce.PostNow()
            if not ok then
                MFD.Print("nothing announced: " .. reason)
            end
        end,
    },
    {
        key = "clear",
        label = "Clear",
        binding = "Clear every icon",
        tip = "Take every icon off every mob you can see, and drop any marks placed by hand. The addon will mark the pack again from scratch.",
        run = function()
            MFD.Print("cleared " .. MFD.Marker:ClearAll() .. " icons")
        end,
    },
    {
        key = "remark",
        label = "Re-mark",
        binding = "Re-mark the pack",
        tip = "Forget everything about the icons currently up and work the pack out again. Use it when the marks look wrong rather than missing.",
        run = function()
            MFD.Marker.ResetMarkState()
            MFD.Print("re-marking")
        end,
    },
    {
        key = "marking",
        label = "Marking",
        binding = "Toggle marking",
        tip = "Stop or start placing icons. Nothing you have configured is lost either way.",
        run = function()
            local settings = MFD.db.settings
            settings.isMarkingEnabled = not settings.isMarkingEnabled
            MFD.Print("marking " .. (settings.isMarkingEnabled and "on" or "off"))
        end,
        status = function()
            local isOn = MFD.db.settings.isMarkingEnabled
            return isOn and (GREEN .. "Marking on|r") or (RED .. "Marking off|r")
        end,
    },
    {
        key = "deaths",
        label = "Death calls",
        binding = "Cycle death announcements",
        tip = "Per boss follows the ticks on the Deaths tab. On everywhere announces on any boss. Off everywhere announces nothing. Trash is never announced.",
        run = function()
            local settings = MFD.db.settings.deaths
            settings.override = MFD.Encounters.NextOverride(settings.override)
            MFD.Print("death announcements: " .. MFD.Encounters.OVERRIDE_LABELS[settings.override])
            if MFD.UI.Deaths and MFD.UI.Deaths.Refresh then
                MFD.UI.Deaths:Refresh()
            end
        end,
        status = function()
            local override = MFD.db.settings.deaths.override
            local color = (override == "ON" and GREEN) or (override == "OFF" and RED) or AMBER
            return color .. "Deaths: " .. MFD.Encounters.OVERRIDE_LABELS[override] .. "|r"
        end,
    },
}

-- Looked up by key for the keybindings and the slash router.
Actions.BY_KEY = {}
for _, action in ipairs(Actions.LIST) do
    Actions.BY_KEY[action.key] = action
end

-- The text a button should currently show. Pure apart from the status readers.
function Actions.TextFor(action)
    if action.status then
        return action.status()
    end
    return action.label
end

-- ---------------------------------------------------------------- client --

-- Runs one action by key. Every entry point goes through here, so an action
-- that is not in this build says so rather than erroring.
function Actions.Run(key)
    local action = Actions.BY_KEY[key]
    if not action then
        MFD.Error("no such action: " .. tostring(key))
        return
    end

    local ok, err = pcall(action.run)
    if not ok then
        MFD.Error(action.label .. " failed: " .. tostring(err))
    end
end

-- Builds the action bar along the bottom of a container and returns its height
-- in pixels, so the caller can leave room for it.
--
-- The buttons are deliberately large. This is the one surface that gets used
-- with a boss on you, and a 60 pixel button is a miss.
Actions.BUTTON_WIDTH = 104
Actions.BUTTON_HEIGHT = 24
Actions.BUTTON_GAP = 6

function Actions.BuildBar(container, availableWidth)
    local slots, rows = Actions.Layout(
        #Actions.LIST, availableWidth, Actions.BUTTON_WIDTH, Actions.BUTTON_GAP)

    container.actionButtons = {}

    for index, action in ipairs(Actions.LIST) do
        local slot = slots[index]
        local button = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
        button:SetSize(Actions.BUTTON_WIDTH, Actions.BUTTON_HEIGHT)
        button:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT",
            8 + slot.column * (Actions.BUTTON_WIDTH + Actions.BUTTON_GAP),
            8 + (rows - 1 - slot.row) * (Actions.BUTTON_HEIGHT + Actions.BUTTON_GAP))

        button.action = action
        button:SetText(Actions.TextFor(action))

        button:SetScript("OnClick", function()
            Actions.Run(action.key)
            Actions.RefreshBar(container)
        end)

        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
            GameTooltip:AddLine(action.label)
            GameTooltip:AddLine(action.tip, 1, 1, 1, true)
            GameTooltip:AddLine("Bindable under Key Bindings, Marked For Death.", 0.6, 0.8, 1, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)

        container.actionButtons[#container.actionButtons + 1] = button
    end

    return rows * Actions.BUTTON_HEIGHT + (rows - 1) * Actions.BUTTON_GAP + 16
end

-- Repaints the stateful buttons. Cheap enough to call on the panel's normal
-- refresh cadence, which is what keeps "Marking off" honest when it was turned
-- off from somewhere else.
function Actions.RefreshBar(container)
    for _, button in ipairs(container.actionButtons or {}) do
        if button.action.status then
            button:SetText(Actions.TextFor(button.action))
        end
    end
end

_G.MarkedForDeath = MFD
