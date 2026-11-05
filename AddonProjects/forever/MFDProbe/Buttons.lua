local addonName, ns = ...

--[[
Buttons: the marking route the recon says is left. SetRaidTarget refuses addon Lua, so a
Forever MarkedForDeath would write a secure macro out of combat and the player would press
it. Six buttons ask whether that works, and how far:

    Mark by name    /targetexact <name> then /tm ~<icon>, for each name    (P6)
    Conditionals    /tm [@mouseover,exists] ~8 and /tm [@nameplate1,exists] ~7  (P7)
    Long macro      a macro past 255 characters whose last line marks you with the moon  (P7)
    Clear all       the secure raidtarget action's clear-all
    Snippet         a secure snippet rewrites the macro on each click, mouseover square
                    then diamond                                            (P15)
    Click chain     /click on a hidden named button that marks you with the triangle  (P17)

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
local PANEL_H = TOP + BUTTON_H * 3 + GAP * 3
-- Seconds after a click before the marks are read back.
local READBACK = 1.0
-- Characters in the long macro: past the old 255 limit.
local LONG = 300

-- The button "/click" presses. It has to have a global name, because /click finds a
-- button by name; nothing else in the addon is a global.
local CLICK_TARGET = "MFDProbeClickTarget"

-- Run in the restricted environment before the snippet button's own click: it rewrites
-- the button's macro, which is the question (P15). Odd clicks mark the mouseover with the
-- square, even ones with the diamond, so every click, in combat too, needs a rewrite to
-- come out right; the counter shows the snippet ran at all.
local SNIPPET = [=[
    local n = (self:GetAttribute("probe-runs") or 0) + 1
    self:SetAttribute("probe-runs", n)
    if n % 2 == 1 then
        self:SetAttribute("macrotext", "/tm [@mouseover,exists] 6")
    else
        self:SetAttribute("macrotext", "/tm [@mouseover,exists] 3")
    end
]=]

local panel
local buttons = {}   -- key -> button

-- What each button's click is recorded under, and what it reads back afterwards.
local READ_UNITS = { "target", "mouseover", "player" }

local function OnClicked(key)
    local run = ns.Checks.NewRun("click " .. key, "click")
    ns.Listen.Ensure(run, READBACK + 2)
    local button = buttons[key]
    -- The attribute, not the Lua field: the snippet rewrites only the attribute.
    local text = ns.Call(button.GetAttribute, button, "macrotext")
    local macro = text.ok and type(text.values[1]) == "string" and text.values[1] or ""
    run.rows[#run.rows + 1] = { id = "button." .. key .. ".clicked", outcome = "ok",
        v = string.format("%d characters", #macro), combat = ns.InCombat() }
    C_Timer.After(READBACK, function()
        for _, unit in ipairs(READ_UNITS) do
            local exists = ns.Call(UnitExists, unit)
            -- A secret answer is still asked about: the read itself is the finding.
            if exists.ok and (ns.IsSecret(exists.values[1]) or exists.values[1]) then
                ns.AddRow(run, "button." .. key .. ".after." .. unit .. ".GetRaidTargetIndex",
                    ns.Call(GetRaidTargetIndex, unit))
            end
        end
        -- What the secure side left on the button, for the snippet's question.
        for _, name in ipairs(button.readAttributes or {}) do
            ns.AddRow(run, "button." .. key .. ".attribute." .. name, ns.Call(button.GetAttribute, button, name))
        end
        ns.Print(string.format("click on %s recorded as run %d.", button.label, run.id))
    end)
end

local function MakeButton(key, label, column, row)
    local b = CreateFrame("Button", nil, panel, "SecureActionButtonTemplate, UIPanelButtonTemplate")
    b:SetSize(BUTTON_W, BUTTON_H)
    b:SetPoint("TOPLEFT", panel, "TOPLEFT", GAP + (column - 1) * (BUTTON_W + GAP), -(TOP + (row - 1) * (BUTTON_H + GAP)))
    -- One edge only: PreClick and PostClick run on every edge registered, so with both a
    -- press would be recorded twice, once before the action fired.
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("useOnKeyDown", false)
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

    -- P15: the macro starts empty; only the snippet, run on the click, gives it one.
    local snippet = MakeButton("snippet", "Snippet: mouseover", 1, 3)
    snippet.macroText = ""
    snippet.readAttributes = { "probe-runs", "macrotext" }
    snippet:SetAttribute("type", "macro")
    snippet:SetAttribute("macrotext", "")
    local header = CreateFrame("Frame", nil, panel, "SecureHandlerBaseTemplate")
    local wrapped = ns.Call(SecureHandlerWrapScript, snippet, "OnClick", header, SNIPPET)
    Buttons.wrapError = not wrapped.ok and wrapped.err or nil

    -- P17: a hidden button that marks you with the triangle, pressed by another's /click.
    local target = CreateFrame("Button", CLICK_TARGET, panel, "SecureActionButtonTemplate")
    target:Hide()
    target:RegisterForClicks("AnyUp")
    target:SetAttribute("useOnKeyDown", false)
    target:SetAttribute("type", "macro")
    target:SetAttribute("macrotext", "/tm [@player] 4")
    local chain = MakeButton("click", "Click chain", 2, 3)
    chain.macroText = "/click " .. CLICK_TARGET .. " LeftButton"
    chain:SetAttribute("type", "macro")
    chain:SetAttribute("macrotext", chain.macroText)
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
    if Buttons.wrapError then
        lines[#lines + 1] = "|cffff4444the snippet could not be attached:|r " .. Buttons.wrapError
    end
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
