local addonName, ns = ...

--[[
Launcher: the way into the window from the minimap. The Addon Compartment entry (the
client's own list beside the minimap) is always there; the round button on the minimap's
rim is the extra many players look for, and can be hidden (settings.minimap.hidden, its
place in settings.minimap.angle).

Owned by lane G (window and config). Frames are made only from the ready hook, which
returns early on IC_HEADLESS.

    Launcher.ICON             the texture both show (the same skull the AddOns list shows)
    Launcher.MenuItems(view)  the right-click menu, pure: a case checks it
    Launcher.SetShown(on)     shows or hides the rim button; the compartment stays
    Launcher.Click(button, owner)

Left click opens or closes the window; right click opens the menu.
]]

ns.Launcher = ns.Launcher or {}
local Launcher = ns.Launcher

local W = LibStub("LibICWidgets-1.0")
local Theme = LibStub("LibICTheme-1.0")

Launcher.ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"

local button

--------------------------------------------------------------------------------
-- Pure
--------------------------------------------------------------------------------

--[[
view = { enabled, minimap (shown), act = { open(key), toggleEnabled(), float(),
check(), minimap(on) } }. Returns W.Menu items.
]]
function Launcher.MenuItems(view)
    view = view or {}
    local act = view.act or {}
    local function Do(name, ...)
        local args = { ... }
        return function() if act[name] then act[name](unpack(args)) end end
    end
    return {
        { title = "Marked For Death" },
        { text = "Assignments", onClick = Do("open", "assign") },
        { text = "Roles", onClick = Do("open", "roles") },
        { text = "Rules", onClick = Do("open", "rules") },
        { text = "Raid check", onClick = Do("check") },
        { text = "Settings", onClick = Do("open", "settings") },
        { divider = true },
        { text = "Floating assignment panel", onClick = Do("float") },
        { text = "Marked For Death on", checked = function() return view.enabled ~= false end,
          onClick = Do("toggleEnabled") },
        { text = "Minimap button", checked = function() return view.minimap ~= false end,
          onClick = Do("minimap", view.minimap == false) },
    }
end

--------------------------------------------------------------------------------
-- Runtime
--------------------------------------------------------------------------------

local function Saved()
    local s = ns.db.settings
    if type(s.minimap) ~= "table" then s.minimap = { hidden = false, angle = 200 } end
    return s.minimap
end

function Launcher.SetShown(on)
    if not ns.db then return end
    Saved().hidden = not on
    if button then button:SetShown(on) end
    ns.UI.Refresh()
end

local function Tip(tip)
    tip:AddLine("Marked For Death")
    if not ns.UI.IsEnabled() then
        local bad = Theme.Current().colors.bad
        tip:AddLine("Off: /mfd on turns it back on.", bad.r, bad.g, bad.b)
    end
    tip:AddLine("Click: the window", 1, 1, 1)
    tip:AddLine("Right-click: menu", 1, 1, 1)
end

local function Menu(owner)
    if not ns.db then return end
    W.Menu(owner, Launcher.MenuItems({
        enabled = ns.UI.IsEnabled(),
        minimap = Saved().hidden ~= true,
        act = {
            open = function(key) ns.UI.Open(key) end,
            check = function()
                if ns.RaidCheckUI and ns.RaidCheckUI.ShowGrid then ns.RaidCheckUI.ShowGrid() else ns.UI.Open("check") end
            end,
            float = function() if ns.UIAssignments then ns.UIAssignments.Toggle() end end,
            toggleEnabled = function() ns.UI.SetEnabled(not ns.UI.IsEnabled()) end,
            minimap = function(on) Launcher.SetShown(on) end,
        },
    }))
end

function Launcher.Click(mouseButton, owner)
    if mouseButton == "RightButton" then
        Menu(owner)
    else
        ns.UI.Toggle()
    end
end

ns.AddCommand("minimap", "show or hide the minimap button (the addon list beside the minimap keeps an entry)",
    function(rest)
        if not ns.db then return end
        local word = (type(rest) == "string" and rest or ""):lower():match("^%s*(%S*)") or ""
        local on
        if word == "on" or word == "show" then
            on = true
        elseif word == "off" or word == "hide" then
            on = false
        else
            on = Saved().hidden == true
        end
        Launcher.SetShown(on)
        ns.Print(on and "minimap button shown." or "minimap button hidden. /mfd minimap brings it back.")
    end, "minimap [on|off]")

ns.OnReady("launcher", function()
    if IC_HEADLESS then return end
    local saved = Saved()
    W.Compartment({
        text = "Marked For Death",
        icon = Launcher.ICON,
        -- The menu needs an owner to sit by; the compartment's own frame, else the screen.
        onClick = function(mouseButton) Launcher.Click(mouseButton, AddonCompartmentFrame or UIParent) end,
        tooltip = Tip,
    })
    if type(W.MinimapButton) == "function" then
        button = W.MinimapButton({
            icon = Launcher.ICON,
            angle = saved.angle,
            onClick = function(self, mouseButton) Launcher.Click(mouseButton, self) end,
            onMoved = function(angle) saved.angle = angle end,
            tooltip = function(tip)
                Tip(tip)
                tip:AddLine("Drag to move this button", 0.7, 0.7, 0.7)
            end,
        })
        button:SetShown(saved.hidden ~= true)
    end
end)
