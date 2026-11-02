local addonName, ns = ...

--[[
The two ways in from the minimap, both doing the same thing.

    the Addon Compartment   the client's own list of addons beside the minimap: the modern
                            way, always there
    a button on the rim     one click instead of two; /sticky minimap hides it

Left-click shows the notes, or hides them if they are all showing: a click that is made
by accident changes nothing that cannot be clicked back. Making a note is deliberate, so
it is in the right-click menu, beside showing and hiding them all.
]]

local Util = LibStub("LibICUtil-1.0")
local W = LibStub("LibICWidgets-1.0")

local Notes = ns.Notes

local Launcher = {}
ns.Launcher = Launcher

Launcher.ICON = "Interface\\Icons\\INV_Misc_Note_02"

local button

-- Pure. "3 notes, 1 hidden" for the tooltip.
function Launcher.Summary(count, hidden)
    if count == 0 then return "no notes yet" end
    local text = string.format("%d %s", count, Util.Plural(count, "note"))
    if hidden > 0 then text = text .. string.format(", %d hidden", hidden) end
    return text
end

local function Counts()
    if not (ns.db and ns.cdb) then return 0, 0 end
    local count, hidden = 0, 0
    for _, entry in ipairs(Notes.All(ns.db, ns.cdb)) do
        count = count + 1
        if Notes.View(ns.cdb, entry.note.id).hidden then hidden = hidden + 1 end
    end
    return count, hidden
end

-- Pure. What a left-click will do, for the tooltip: the same rule as Notes.ToggleAll.
function Launcher.ClickHint(count, hidden)
    if count == 0 then return "Right-click to make a note" end
    if hidden > 0 then return "Left-click to show all notes" end
    return "Left-click to hide all notes"
end

local function Tip(tip)
    local count, hidden = Counts()
    tip:AddLine("Stickies")
    tip:AddLine(Launcher.Summary(count, hidden), 1, 1, 1)
    tip:AddLine(Launcher.ClickHint(count, hidden), 0.7, 0.7, 0.7)
    if count > 0 then tip:AddLine("Right-click for a new note and more", 0.7, 0.7, 0.7) end
end

local function OpenMenu(owner)
    if not (ns.db and ns.cdb) then return end
    W.Menu(owner, {
        { title = "Stickies" },
        { text = "New note", onClick = function() ns.NewNote("") end },
        { divider = true },
        { text = "Show all notes", onClick = function() ns.SetAllHidden(false) end },
        { text = "Hide all notes", onClick = function() ns.SetAllHidden(true) end },
        { text = "Lock all notes in place",
          checked = function() return ns.db.settings.locked == true end,
          onClick = function()
              ns.db.settings.locked = not ns.db.settings.locked
              ns.UI.Refresh()
          end },
        { divider = true },
        { text = "Show the minimap button",
          checked = function() return ns.db.settings.minimap.hide ~= true end,
          onClick = function() Launcher.SetShown(ns.db.settings.minimap.hide == true) end },
    })
end

local function Click(mouseButton, owner)
    if mouseButton == "RightButton" then
        OpenMenu(owner)
    else
        ns.ToggleAll()
    end
end

-- Shows or hides the button on the rim. The compartment entry stays either way, so
-- there is always a way back.
function Launcher.SetShown(shown)
    if not ns.db then return end
    ns.db.settings.minimap.hide = not shown
    if button then button:SetShown(shown) end
end

-- Called once, at login, when the saved settings and the minimap both exist.
function Launcher.Create()
    if button or not ns.db then return end
    local saved = ns.db.settings.minimap
    button = W.MinimapButton({
        icon = Launcher.ICON,
        angle = saved.angle,
        onClick = function(self, mouseButton) Click(mouseButton, self) end,
        onMoved = function(angle) saved.angle = angle end,
        tooltip = function(tip)
            Tip(tip)
            tip:AddLine("Drag to move this button", 0.7, 0.7, 0.7)
        end,
    })
    button:SetShown(saved.hide ~= true)

    W.Compartment({
        text = "Stickies",
        icon = Launcher.ICON,
        onClick = function(mouseButton) Click(mouseButton, nil) end,
        tooltip = Tip,
    })
end
