local addonName, ns = ...

--[[
The two ways in from the minimap, both doing the same thing.

    the Addon Compartment   the client's own list of addons beside the minimap: the modern
                            way, always there
    a button on the rim     one click instead of two, for the thing done most often;
                            /sticky minimap hides it

Left-click starts a new note. Right-click opens a short menu.
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

local function Tip(tip)
    tip:AddLine("Stickies")
    tip:AddLine(Launcher.Summary(Counts()), 1, 1, 1)
    tip:AddLine("Left-click for a new note", 0.7, 0.7, 0.7)
    tip:AddLine("Right-click for more", 0.7, 0.7, 0.7)
end

local function OpenMenu(owner)
    if not (ns.db and ns.cdb) then return end
    local _, hidden = Counts()
    W.Menu(owner, {
        { title = "Stickies" },
        { text = "New note", onClick = function() ns.NewNote("") end },
        { text = hidden > 0 and "Show every note" or "Hide every note",
          onClick = function() ns.ToggleAll() end },
        { text = "Lock every note in place",
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
        ns.NewNote("")
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
