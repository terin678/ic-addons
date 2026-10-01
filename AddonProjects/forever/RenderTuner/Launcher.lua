local addonName, ns = ...

--[[
The way in from the minimap: an entry in the Addon Compartment, the client's own list of
addons beside the minimap. Left-click opens or closes the panel; right-click is the
presets, for changing the render scale without opening anything.
]]

local W = LibStub("LibICWidgets-1.0")

local Launcher = {}
ns.Launcher = Launcher

Launcher.ICON = "Interface\\Icons\\INV_Misc_Spyglass_03"

local created = false

local function Tip(tip)
    tip:AddLine("RenderTuner")
    if ns.db and ns.db.saved then tip:AddLine(ns.StatusText(), 1, 1, 1, true) end
    tip:AddLine("Left-click to open the panel", 0.7, 0.7, 0.7)
    tip:AddLine("Right-click for the upscaling presets", 0.7, 0.7, 0.7)
end

local function PresetMenu()
    local items = { { title = "Upscaling" } }
    for _, preset in ipairs(ns.Catalog.PRESETS) do
        items[#items + 1] = {
            text = preset.label,
            radio = function()
                return ns.Model.PresetOf(ns.Apply.Live().RenderScale, ns.Catalog.PRESETS, ns.Apply.Limits()) == preset
            end,
            onClick = function() ns.ApplyPreset(preset) end,
        }
    end
    W.Menu(UIParent, items)
end

-- Called once, at login, when the saved settings are in hand.
function Launcher.Create()
    if created then return end
    created = true
    W.Compartment({
        text = "RenderTuner",
        icon = Launcher.ICON,
        onClick = function(mouseButton)
            if not (ns.db and ns.db.saved) then return end
            if mouseButton == "RightButton" then PresetMenu() else ns.Panel.Toggle() end
        end,
        tooltip = Tip,
    })
end
