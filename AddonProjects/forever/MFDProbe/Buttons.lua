local addonName, ns = ...

--[[
Buttons: the marking route the recon says is left. SetRaidTarget refuses addon Lua, so a
Forever MarkedForDeath would write a secure macro out of combat and the player would press
it. Four buttons ask whether that works, and how far:

    Mark by name    /targetexact <name> then /tm ~<icon>, for each name    (P6)
    Conditionals    /tm [@mouseover,exists] ~8 and /tm [@nameplate1,exists] ~7  (P7)
    Long macro      a macro past 255 characters whose last line marks you with the moon  (P7)
    Clear all       the secure raidtarget action's clear-all

Each click is a run: after a second the marks on the target, mouseover and player are read
back, with the client's refusals heard in between. Attributes are set out of combat only;
clicking works in combat, which is the point.

The buttons are the client's own SecureActionButtonTemplate with its panel button look:
an ICKit button cannot carry the secure template. The panel around them is ICKit's.
]]

local Buttons = {}
ns.Buttons = Buttons

local W = LibStub("LibICWidgets-1.0")

-- Pixels.
local BUTTON_W, BUTTON_H, GAP = 150, 22, 6
local PANEL_W = BUTTON_W * 2 + GAP * 3
local TOP = 46
local PANEL_H = TOP + BUTTON_H * 2 + GAP * 2
-- Seconds after a click before the marks are read back.
local READBACK = 1.0
-- Characters in the long macro: past the old 255 limit.
local LONG = 300

local panel
local buttons = {}   -- key -> button

-- What each button's click is recorded under, and what it reads back afterwards.
local READ_UNITS = { "target", "mouseover", "player" }

local function OnClicked(key)
    local run = ns.Checks.NewRun("click " .. key, "click")
    ns.Listen.Ensure(run, READBACK + 2)
    local button = buttons[key]
    run.rows[#run.rows + 1] = { id = "button." .. key .. ".clicked", outcome = "ok",
        v = string.format("%d characters", #(button.macroText or "")), combat = ns.InCombat() }
    C_Timer.After(READBACK, function()
        for _, unit in ipairs(READ_UNITS) do
            local exists = ns.Call(UnitExists, unit)
            -- A secret answer is still asked about: the read itself is the finding.
            if exists.ok and (ns.IsSecret(exists.values[1]) or exists.values[1]) then
                ns.AddRow(run, "button." .. key .. ".after." .. unit .. ".GetRaidTargetIndex",
                    ns.Call(GetRaidTargetIndex, unit))
            end
        end
        ns.Print(string.format("click on %s recorded as run %d.", button.label, run.id))
    end)
end

local function MakeButton(key, label, column, row)
    local b = CreateFrame("Button", nil, panel, "SecureActionButtonTemplate, UIPanelButtonTemplate")
    b:SetSize(BUTTON_W, BUTTON_H)
    b:SetPoint("TOPLEFT", panel, "TOPLEFT", GAP + (column - 1) * (BUTTON_W + GAP), -(TOP + (row - 1) * (BUTTON_H + GAP)))
    b:RegisterForClicks("AnyUp", "AnyDown")
    b.label = label
    b:SetText(label)
    -- PostClick runs after the secure action and is not secure itself, which is fine: it
    -- only reads.
    b:HookScript("PostClick", function() OnClicked(key) end)
    buttons[key] = b
    return b
end

local function Build()
    if panel then return end
    panel = W.Panel(UIParent, { width = PANEL_W, height = PANEL_H, strata = "MEDIUM" })
    panel:SetPoint("TOP", UIParent, "TOP", 0, -120)
    local title = W.Label(panel, "MFD Probe: marking buttons", { font = "title" })
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", GAP, -GAP)
    local hint = W.Label(panel, "Click each out of combat, then again in combat.", { font = "small", color = "textDim" })
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    hint:SetWidth(PANEL_W - GAP * 2)

    MakeButton("names", "Mark by name", 1, 1)
    local cond = MakeButton("conditionals", "Conditionals", 2, 1)
    cond.macroText = "/tm [@mouseover,exists] ~8\n/tm [@nameplate1,exists] ~7"
    cond:SetAttribute("type", "macro")
    cond:SetAttribute("macrotext", cond.macroText)

    local long = MakeButton("long", "Long macro", 1, 2)
    long.macroText = ns.Report.LongMacro(LONG, "/tm [@player] 5")
    long:SetAttribute("type", "macro")
    long:SetAttribute("macrotext", long.macroText)

    local clear = MakeButton("clear", "Clear all", 2, 2)
    clear.macroText = ""
    clear:SetAttribute("type", "raidtarget")
    clear:SetAttribute("action", "clear-all")
end

-- The hostile names in view that read plainly, without repeats.
local function NamesInView()
    local names, seen = {}, {}
    for _, entry in ipairs(ns.Checks.HostileUnits()) do
        local call = ns.Call(UnitName, entry.unit)
        local name = call.ok and call.values[1]
        if type(name) == "string" and not ns.IsSecret(name) and not seen[name] then
            seen[name] = true
            names[#names + 1] = name
        end
    end
    return names
end

-- Out of combat only: the caller checks. Builds the panel the first time, points the
-- name button at `names` (or at the mobs in view), shows it, and returns what to say.
function Buttons.Show(names)
    Build()
    if #names == 0 then names = NamesInView() end
    local named = buttons.names
    named.macroText = ns.Report.MarkMacro(names, 8)
    named:SetAttribute("type", "macro")
    named:SetAttribute("macrotext", named.macroText)
    named:SetText(#names > 0 and string.format("Mark by name (%d)", #names) or "Mark by name (none)")
    panel:Show()
    local lines = { "the marking buttons are up, below the top of the screen." }
    if #names == 0 then
        lines[#lines + 1] = "no mob names read plainly here; type them: /mfdp buttons Name One, Name Two"
    else
        lines[#lines + 1] = "Mark by name targets and marks: " .. table.concat(names, ", ")
    end
    return lines
end

function Buttons.Hide()
    if panel then panel:Hide() end
end
