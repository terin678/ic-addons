local addonName, ns = ...

--[[
Buttons: the marking route the recon says is left. SetRaidTarget refuses addon Lua, so a
Forever MarkedForDeath would write a secure macro out of combat and the player would press
it. Ten buttons ask whether that works, and how far. The first four are the control: does
a secure button mark anything at all, and in which spelling.

    Literal /tm 8       "/tm 8" on the target, spelled as typed
    Global tm 7         the same command as SLASH_TARGET_MARKER1 spells it on this client
    Secure set 6        the secure raidtarget action, set, on the target: no macro at all
    Literal exact 5     "/targetexact <name>" then "/tm 5", spelled as typed
    Mark by name        the client's own spellings: targetexact then tm ~N, per name (P6)
    Conditionals        tm [@mouseover,exists] ~8 and tm [@nameplate1,exists] ~7  (P7)
    Snippet             a secure snippet rewrites the macro on each press: mouseover
                        square, then diamond                                 (P15)
    Long macro          past 255 characters, its last line puts the circle on you  (P7)
    Click chain         click on a named button that puts the star on you    (P17)
    Clear all           the secure raidtarget action's clear-all

Another addon on this client builds its macros from the SLASH_ globals because the slash
words are localised, and says a literal "/tm" does not work here. The first two buttons
settle that.

Each press is a run: a second later the marks on the target, mouseover and player are read
back, with the client's refusals heard in between. Attributes are set out of combat only;
pressing works in combat, which is the point. A mouse click puts the pointer on the
button, so [@mouseover] means nothing then: /mfdp keys binds CTRL-1 to CTRL-0 to the
buttons, and a key press leaves the pointer on the mob.

The buttons are the client's own SecureActionButtonTemplate with its panel button look:
an ICKit button cannot carry the secure template. The panel around them is ICKit's.
]]

local Buttons = {}
ns.Buttons = Buttons

local W = LibStub("LibICWidgets-1.0")

-- Pixels.
local BUTTON_W, BUTTON_H, GAP = 150, 22, 6
local ROWS = 5
local PANEL_W = BUTTON_W * 2 + GAP * 3
local TOP = 46
local PANEL_H = TOP + BUTTON_H * ROWS + GAP * ROWS
-- Seconds after a press before the marks are read back.
local READBACK = 1.0
-- Characters in the long macro: past the old 255 limit.
local LONG = 300

-- Every button has a global name: /click and key bindings find a button by name. These
-- and the saved table are the addon's only globals.
local NAME_PREFIX = "MFDProbe_"
local CLICK_TARGET = "MFDProbeClickTarget"

-- { key, label, column, row }, in the order the keys are bound: CTRL-1 is the first.
local LAYOUT = {
    { "literal", "Literal /tm 8", 1, 1 },
    { "global", "Global tm 7", 2, 1 },
    { "raidtarget", "Secure set 6", 1, 2 },
    { "exact", "Literal exact 5", 2, 2 },
    { "names", "Mark by name", 1, 3 },
    { "conditionals", "Conditionals", 2, 3 },
    { "snippet", "Snippet: mouseover", 1, 4 },
    { "long", "Long macro", 2, 4 },
    { "click", "Click chain", 1, 5 },
    { "clear", "Clear all", 2, 5 },
}
local KEYS = { "CTRL-1", "CTRL-2", "CTRL-3", "CTRL-4", "CTRL-5", "CTRL-6", "CTRL-7", "CTRL-8", "CTRL-9", "CTRL-0" }

-- Run in the restricted environment before the snippet button's own press: it rewrites
-- the button's macro, which is the question (P15). Odd presses put the square on the
-- mouseover, even ones the diamond, so every press, in combat too, needs a rewrite to come
-- out right; the counter shows the snippet ran at all. The two macros go in with %q.
local SNIPPET_FORMAT = [=[
    local n = (self:GetAttribute("probe-runs") or 0) + 1
    self:SetAttribute("probe-runs", n)
    if n %% 2 == 1 then
        self:SetAttribute("macrotext", %q)
    else
        self:SetAttribute("macrotext", %q)
    end
]=]

local panel
local buttons = {}   -- key -> button
local bound = false

-- What each press reads back afterwards.
local READ_UNITS = { "target", "mouseover", "player" }

-- The slash word this client uses for a command, from its SLASH_ global, or the English
-- spelling when the global is missing.
local function Slash(global, english)
    local word = _G[global]
    if type(word) == "string" and word ~= "" then return word end
    return english
end

local function Spellings()
    return {
        mark = Slash("SLASH_TARGET_MARKER1", "/tm"),
        exact = Slash("SLASH_TARGET_EXACT1", "/targetexact"),
        click = Slash("SLASH_CLICK1", "/click"),
    }
end

local function OnClicked(key)
    local run = ns.Checks.NewRun("press " .. key, "click")
    ns.Listen.Ensure(run, READBACK + 2)
    local button = buttons[key]
    -- The attribute, not a Lua field: the snippet rewrites only the attribute.
    local text = ns.Call(button.GetAttribute, button, "macrotext")
    local macro = text.ok and type(text.values[1]) == "string" and text.values[1] or ""
    run.rows[#run.rows + 1] = { id = "button." .. key .. ".pressed", outcome = "ok",
        v = string.format("%d characters, %s", #macro, bound and "keys bound" or "mouse"), combat = ns.InCombat() }
    C_Timer.After(READBACK, function()
        for _, unit in ipairs(READ_UNITS) do
            local exists = ns.Call(UnitExists, unit)
            -- A secret answer is still asked about: the read itself is the finding.
            if exists.ok and (ns.IsSecret(exists.values[1]) or exists.values[1]) then
                ns.AddRow(run, "button." .. key .. ".after." .. unit .. ".GetRaidTargetIndex",
                    ns.Call(GetRaidTargetIndex, unit))
            end
        end
        for _, name in ipairs(button.readAttributes or {}) do
            ns.AddRow(run, "button." .. key .. ".attribute." .. name, ns.Call(button.GetAttribute, button, name))
        end
        ns.Print(string.format("%s recorded as run %d.", button.label, run.id))
    end)
end

-- Fires on the press, as the marker buttons of an addon that works on this client do:
-- one edge only (PostClick runs on every edge registered), and pinned, because left unset
-- the edge follows the ActionButtonUseKeyDown console variable.
local function OneEdge(b)
    b:RegisterForClicks("AnyDown")
    b:SetAttribute("useOnKeyDown", true)
end

local function MakeButton(spec)
    local key, label, column, row = spec[1], spec[2], spec[3], spec[4]
    local b = CreateFrame("Button", NAME_PREFIX .. key, panel, "SecureActionButtonTemplate, UIPanelButtonTemplate")
    b:SetSize(BUTTON_W, BUTTON_H)
    b:SetPoint("TOPLEFT", panel, "TOPLEFT", GAP + (column - 1) * (BUTTON_W + GAP), -(TOP + (row - 1) * (BUTTON_H + GAP)))
    OneEdge(b)
    b.label = label
    b:SetText(label)
    -- PostClick runs after the secure action and is not secure itself, which is fine: it
    -- only reads.
    b:HookScript("PostClick", function() OnClicked(key) end)
    buttons[key] = b
    return b
end

local function SetMacro(b, text)
    b.macroText = text
    b:SetAttribute("type", "macro")
    b:SetAttribute("macrotext", text)
end

local function Build()
    if panel then return end
    local say = Spellings()
    panel = W.Panel(UIParent, { width = PANEL_W, height = PANEL_H, strata = "MEDIUM" })
    panel:SetPoint("TOP", UIParent, "TOP", 0, -120)
    local title = W.Label(panel, "MFD Probe: marking buttons", { font = "title" })
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", GAP, -GAP)
    local hint = W.Label(panel, "Clear all between tests. Keys: /mfdp keys",
        { font = "small", color = "textDim" })
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    hint:SetWidth(PANEL_W - GAP * 2)

    for _, spec in ipairs(LAYOUT) do MakeButton(spec) end

    SetMacro(buttons.literal, "/tm 8")
    SetMacro(buttons.global, say.mark .. " 7")

    local set = buttons.raidtarget
    set.macroText = ""
    set:SetAttribute("type", "raidtarget")
    set:SetAttribute("unit", "target")
    set:SetAttribute("marker", "6")
    set:SetAttribute("action", "set")

    SetMacro(buttons.conditionals, say.mark .. " [@mouseover,exists] ~8\n" .. say.mark .. " [@nameplate1,exists] ~7")
    SetMacro(buttons.long, ns.Report.LongMacro(LONG, say.mark .. " [@player] 2", say.mark .. " [@player] 0\n"))

    local clear = buttons.clear
    clear.macroText = ""
    clear:SetAttribute("type", "raidtarget")
    clear:SetAttribute("action", "clear-all")

    -- P15: the macro starts empty; only the snippet, run on the press, gives it one.
    local snippet = buttons.snippet
    snippet.readAttributes = { "probe-runs", "macrotext" }
    SetMacro(snippet, "")
    local header = CreateFrame("Frame", nil, panel, "SecureHandlerBaseTemplate")
    local code = string.format(SNIPPET_FORMAT, say.mark .. " [@mouseover,exists] 6", say.mark .. " [@mouseover,exists] 3")
    local wrapped = ns.Call(SecureHandlerWrapScript, snippet, "OnClick", header, code)
    Buttons.wrapError = not wrapped.ok and wrapped.err or nil

    -- P17: the button the chain presses. Shown, because a click from a binding or /click
    -- has to reach a live button, but invisible, out of the way and deaf to the mouse.
    local target = CreateFrame("Button", CLICK_TARGET, panel, "SecureActionButtonTemplate")
    OneEdge(target)
    target:EnableMouse(false)
    target:SetSize(1, 1)
    target:SetAlpha(0)
    target:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -400, 100)
    target:SetAttribute("type", "macro")
    target:SetAttribute("macrotext", say.mark .. " [@player] 1")
    SetMacro(buttons.click, say.click .. " " .. CLICK_TARGET)
end

-- The hostile names in view that read plainly, without repeats; failing those, the
-- target's name, hostile or not.
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
    if #names == 0 then
        local call = ns.Call(UnitName, "target")
        local name = call.ok and call.values[1]
        if type(name) == "string" and not ns.IsSecret(name) then names[1] = name end
    end
    return names
end

-- Out of combat only: the caller checks. Builds the panel the first time, points the
-- name buttons at `names` (or at the mobs in view, or the target), shows it, and returns
-- what to say.
function Buttons.Show(names)
    Build()
    if #names == 0 then names = NamesInView() end
    local say = Spellings()
    SetMacro(buttons.names, ns.Report.MarkMacro(names, 8, say.exact, say.mark))
    buttons.names:SetText(#names > 0 and string.format("Mark by name (%d)", #names) or "Mark by name (none)")
    SetMacro(buttons.exact, names[1] and ("/targetexact " .. names[1] .. "\n/tm 5") or "")
    panel:Show()
    local lines = {
        "the marking buttons are up, below the top of the screen.",
        string.format("this client spells the commands %s, %s and %s.", say.mark, say.exact, say.click),
    }
    if Buttons.wrapError then
        lines[#lines + 1] = "|cffff4444the snippet could not be attached:|r " .. Buttons.wrapError
    end
    if #names == 0 then
        lines[#lines + 1] = "no mob names read plainly and nothing targeted: target a mob, or type them: "
            .. "/mfdp buttons Name One, Name Two"
    else
        lines[#lines + 1] = "Mark by name and Literal exact use: " .. table.concat(names, ", ")
    end
    return lines
end

-- Out of combat only. CTRL-1 to CTRL-0 press the buttons in panel order, until put back.
function Buttons.BindKeys(on)
    if not panel then return { "show the buttons first: /mfdp buttons" } end
    ns.Call(ClearOverrideBindings, panel)
    bound = false
    if not on then return { "the CTRL keys are back to normal." } end
    local parts = {}
    for i, spec in ipairs(LAYOUT) do
        local call = ns.Call(SetOverrideBindingClick, panel, true, KEYS[i], NAME_PREFIX .. spec[1], "LeftButton")
        if not call.ok then return { "|cffff4444the keys could not be bound:|r " .. tostring(call.err) } end
        parts[#parts + 1] = KEYS[i]:gsub("CTRL%-", "") .. " " .. spec[2]
    end
    bound = true
    return { "CTRL plus: " .. table.concat(parts, ", ") .. ". /mfdp keys off puts them back." }
end

function Buttons.Hide()
    if not panel then return end
    ns.Call(ClearOverrideBindings, panel)
    bound = false
    panel:Hide()
end
