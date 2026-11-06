local addonName, ns = ...

--[[
UI_Bar: the marking bar, a small movable strip holding the four secure buttons from
MarkButtons (Mark pack, Clear all, Re-mark, Clear target), each with its key under it; and
the marking slot on the Assignments tab (a status line, Bar and Keys buttons, and the
Mark guide line for the target).

Owned by lane B (marking runtime). The top half is pure, with cases in Tests_Marking.lua.
Frames are made only from the ready hook, which returns early on IC_HEADLESS.

    UIBar.Shows(saved, kind)          whether the bar is shown: saved.shown, and in a group
                                      unless saved.outsideRaid ("solo" on)
    UIBar.Role(view)                  a button label's colour role from { stale, enabled, canMark }: red off or no right, amber stale
    UIBar.IsShown()                   whether the bar is on screen now
    UIBar.Parse(rest)                 what /mfd bar asks for
    UIBar.Status(view)                the slot's one status line, and its colour role
    UIBar.BuildSlot(bar, guide)       lane G's marking slot (UI_Main's SetMarking provider)

The bar's buttons are secure, so the bar is shown, hidden and moved out of combat only; in
combat it stays as it is and its drag is locked. A key is the proven way to press a
button (probe f101e96). A mouse click on the bar, a press while the bar is hidden, Clear
all and Re-mark are not yet proven, and their tooltips say so.

Layout, px: the bar is PAD round a row of four BTN_W x BTN_H buttons GAP apart, with a
KEY_H line of key text under them.
]]

ns.UIBar = ns.UIBar or {}
local UIBar = ns.UIBar
local MB, Ledger = ns.MarkButtons, ns.Ledger

local W = LibStub("LibICWidgets-1.0")
local Restrict = LibStub("LibICRestrict-1.0")

local NAME = "MarkedForDeathBar"
local BTN_W, BTN_H, GAP, PAD, KEY_H = 88, 22, 6, 8, 12   -- px
local BAR_W = PAD * 2 + BTN_W * 4 + GAP * 3                -- px
local BAR_H = PAD + BTN_H + 2 + KEY_H + PAD - 2            -- px
local DEFAULT_FX, DEFAULT_FY = 0.38, 0.72                  -- fractions of the screen

local TIPS = {
    pack = { "Marks each mob of the plan in reach with its seat's icon, Skull first, then puts your target back.",
        "A mob that already carries a mark is left alone.",
        "Proven by key (probe): bind one with /mfd keys on or in Key Bindings. A mouse click is not yet proven." },
    clear = { "Clears every raid icon, using the game's own clear-all action.",
        "Not yet proven to work on this client. Clear target is the proven way." },
    remark = { "Clear all, then Mark pack, in one press.",
        "Not yet proven: it needs Clear all and a /click inside a macro." },
    cleartarget = { "Clears the icon on your target only (/tm 0). Proven.", },
}

--------------------------------------------------------------------------------
-- Pure
--------------------------------------------------------------------------------

-- saved: cdb.bar. kind: the roster's kind ("solo", "party", "raid") or nil.
function UIBar.Shows(saved, kind)
    saved = saved or {}
    if saved.shown == false then return false end
    if saved.outsideRaid then return true end
    return kind == "party" or kind == "raid"
end

-- view = { stale, enabled, canMark }. Red while off or without the right to mark (as the
-- status line and the Settings reasons say it), amber while stale, else the button's own.
function UIBar.Role(view)
    view = view or {}
    if view.enabled == false or view.canMark == false then return "bad" end
    if view.stale then return "warn" end
    return nil
end

local BAR_WORDS = {
    show = "show", on = "show", hide = "hide", off = "hide",
    lock = "lock", unlock = "unlock", solo = "solo", reset = "reset",
}

-- Returns { action, arg }: show, hide, lock, unlock, solo (arg true/false/nil to flip),
-- reset, toggle (nothing typed), or refuse.
function UIBar.Parse(rest)
    local word, arg = (rest or ""):lower():match("^%s*(%S*)%s*(%S*)")
    if word == "" then return { action = "toggle" } end
    local action = BAR_WORDS[word]
    if not action then return { action = "refuse" } end
    if action == "solo" then
        if arg == "on" then return { action = "solo", arg = true } end
        if arg == "off" then return { action = "solo", arg = false } end
        return { action = "solo" }
    end
    return { action = action }
end

-- view = { built, enabled, count, dropped, stale, key, summary }. Returns text, role.
function UIBar.Status(view)
    view = view or {}
    if view.enabled == false then return "Marking is off: the buttons do nothing. /mfd on", "bad" end
    if not view.built then return "Mark pack is made at the first moment out of combat.", "warn" end
    local text = "Mark pack: " .. (view.count or 0) .. ((view.count == 1) and " name" or " names")
    if (view.dropped or 0) > 0 then text = text .. ", " .. view.dropped .. " did not fit" end
    text = text .. (view.key and (", key " .. view.key) or ", no key")
    if view.stale then return text .. ". Stale: the new plan is written when combat ends.", "warn" end
    if view.summary then text = text .. ". " .. view.summary end
    if not view.key then return text .. ".", "warn" end
    return text .. ".", "good"
end

--------------------------------------------------------------------------------
-- The bar
--------------------------------------------------------------------------------

local bar
local skins = {}        -- kind -> { label, key }

local function Saved()
    local cdb = ns.cdb
    if type(cdb.bar) ~= "table" then cdb.bar = {} end
    return cdb.bar
end

local function Roster()
    return ns.UI and ns.UI.Roster and ns.UI.Roster() or nil
end

local function Enabled()
    return not (ns.UI and ns.UI.IsEnabled) or ns.UI.IsEnabled()
end

local function Paint()
    if not bar then return end
    local roster = Roster()
    local canMark = roster and roster.canMark
    for kind, skin in pairs(skins) do
        local stale = kind ~= "clear" and kind ~= "cleartarget" and MB.Stale(kind)
        skin.label:SetRole(UIBar.Role({ stale = stale, enabled = Enabled(), canMark = canMark }) or "buttonText")
        local key = MB.KeyLabel(kind)
        skin.key:SetText(key or "no key")
        skin.key:SetRole(key and "textDim" or "warn")
    end
end

-- Shows or hides the bar as saved. Out of combat only: the buttons are secure children.
-- Whether the bar is on screen now.
function UIBar.IsShown()
    return bar ~= nil and bar:IsShown() == true
end

local function Place()
    if not bar or Restrict.InCombat() then return end
    local saved = Saved()
    local roster = Roster()
    W.SetPlace(bar, saved.fx or DEFAULT_FX, saved.fy or DEFAULT_FY)
    bar:SetLocked(saved.locked == true)
    bar:SetShown(UIBar.Shows(saved, roster and roster.kind))
end

local function Skin(button, kind)
    button:SetSize(BTN_W, BTN_H)
    local face = W.Panel(button, { role = "raised" })
    face:SetAllPoints(button)
    face:EnableMouse(false)
    local label = W.Label(face, MB.LABELS[kind], { font = "button", justify = "CENTER" })
    label:SetPoint("LEFT", face, "LEFT", 2, 0)
    label:SetPoint("RIGHT", face, "RIGHT", -2, 0)
    label:SetWordWrap(false)
    local key = W.Label(bar, "", { font = "small", justify = "CENTER", color = "textDim" })
    key:SetPoint("TOP", button, "BOTTOM", 0, -2)
    key:SetWidth(BTN_W)
    key:SetWordWrap(false)
    skins[kind] = { label = label, key = key }
    W.Tooltip(button, function(tip)
        tip:AddLine(MB.LABELS[kind])
        for _, line in ipairs(TIPS[kind]) do tip:AddLine(line, 1, 1, 1, true) end
        local keys = MB.KeysFor(kind)
        tip:AddLine(#keys > 0 and ("Key: " .. MB.KeyText(keys[1])) or "No key bound.", 1, 0.82, 0)
        if kind == "pack" and MB.Stale("pack") then
            tip:AddLine("Stale: the plan changed in combat. The new one is written when combat ends.", 1, 0.67, 0, true)
        end
    end)
end

local function Layout()
    if Restrict.InCombat() then return end   -- the buttons are secure: placed out of combat only
    for i, kind in ipairs(MB.ORDER) do
        local b = MB.Button(kind)
        if b then
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", bar, "TOPLEFT", PAD + (i - 1) * (BTN_W + GAP), -PAD)
            if not skins[kind] then Skin(b, kind) end
        end
    end
    Paint()
end

local function SavePlace(panel)
    local fx, fy = W.GetPlace(panel)
    if not fx then return end
    local saved = Saved()
    saved.fx, saved.fy = fx, fy
end

local function Build()
    if bar then return end
    bar = W.Panel(UIParent, { name = NAME, width = BAR_W, height = BAR_H, movable = true, onMoved = SavePlace,
        strata = "MEDIUM" })
    W.Tooltip(bar, function(tip)
        tip:AddLine("Marked For Death")
        tip:AddLine("Drag to move. /mfd bar lock pins it; /mfd bar hide hides it.", 1, 1, 1, true)
    end, "ANCHOR_TOP")
    Place()
    local ok, why = MB.Build(bar, bar)
    if ok then Layout() else ns.Debug("marking bar waits: " .. tostring(why)) end
end

--------------------------------------------------------------------------------
-- The Assignments tab's slot
--------------------------------------------------------------------------------

local slot = {}

local function PaintGuide()
    if not slot.guide or not slot.guide:IsVisible() then return end
    local facts = ns.Sense.Facts("target")
    local marked, icon = ns.Sense.Marked("target")
    local steps = MB.Written("pack") or {}
    local text, role = Ledger.Describe(facts, steps, Ledger.View(MB.Record()), marked, icon)
    slot.guideText:SetText(text)
    slot.guideText:SetRole(role)
end

local function PaintSlot()
    if not slot.status then return end
    local current = MB.Current()
    local text, role = UIBar.Status({
        built = MB.Built(), enabled = Enabled(), count = #(MB.Written("pack") or {}),
        dropped = current and #current.dropped or 0, stale = MB.Stale("pack"), key = MB.KeyLabel("pack"),
        summary = Ledger.Summary(MB.Record(), time()),
    })
    slot.status:SetText(text)
    slot.status:SetRole(role)
    slot.status.icFull = text
    slot.barButton:SetLabel(UIBar.IsShown() and "Hide bar" or "Show bar")
    PaintGuide()
end

local function GuideEvents(on)
    if on then
        ns.Events.On("PLAYER_TARGET_CHANGED", "uibar_guide", PaintGuide)
    else
        ns.Events.Off("PLAYER_TARGET_CHANGED", "uibar_guide")
    end
end

-- The one line /mfd bar and the Bar button print: what the bar is doing now.
local function SayState()
    local saved = Saved()
    if UIBar.IsShown() then
        local pinned = saved.locked or (bar and bar.icLocked)
        local why = (not saved.locked and pinned) and ", pinned until combat ends." or ", pinned."
        ns.Print("the bar is shown" .. (pinned and why or ". Drag it to move it."))
    elseif saved.shown == false then
        ns.Print("the bar is hidden. Keys still press its buttons (not yet proven). /mfd bar show")
    else
        ns.Print("the bar shows in a group. /mfd bar solo on shows it alone too.")
    end
end

-- Flips the bar on screen: hidden if it shows, else shown (alone too, if being alone is
-- why it was not). Out of combat only.
local function ToggleShown()
    if Restrict.InCombat() then
        ns.Print("the bar holds secure buttons, so it is shown and hidden out of combat only.")
        return
    end
    local saved = Saved()
    if UIBar.IsShown() then
        saved.shown = false
    else
        saved.shown = true
        local roster = Roster()
        if not UIBar.Shows(saved, roster and roster.kind) then
            saved.outsideRaid = true
            ns.Print("solo is on now, so the bar shows out of a group too (/mfd bar solo off).")
        end
    end
    Place()
    SayState()
    PaintSlot()
end

-- lane G's slot: bar is the toolbar strip left of Announce, guide the line under it.
function UIBar.BuildSlot(barFrame, guide)
    slot.barButton = W.Button(barFrame, "Hide bar", 76, 22, { onClick = ToggleShown })
    slot.barButton:SetPoint("LEFT", barFrame, "LEFT", 0, 0)
    W.Tooltip(slot.barButton, function(tip)
        tip:AddLine("The marking bar")
        tip:AddLine("Shows or hides the bar with Mark pack, Clear all, Re-mark and Clear target. "
            .. "Out of combat only. Same as /mfd bar.", 1, 1, 1, true)
    end)
    slot.keysButton = W.Button(barFrame, "Keys", 50, 22, { onClick = function()
        ns.Print("/mfd keys on binds Ctrl-1 to Ctrl-4 (Mark pack, Clear all, Re-mark, Clear target); "
            .. "Key Bindings > AddOns > Marked For Death sets your own.")
    end })
    slot.keysButton:SetPoint("LEFT", slot.barButton, "RIGHT", 6, 0)
    W.Tooltip(slot.keysButton, function(tip)
        tip:AddLine("Keys")
        for _, kind in ipairs(MB.ORDER) do
            local key = MB.KeyLabel(kind)
            if key then
                tip:AddLine(MB.LABELS[kind] .. ": " .. key, 1, 1, 1)
            else
                tip:AddLine(MB.LABELS[kind] .. ": no key", 1, 0.67, 0)
            end
        end
    end)
    slot.status = W.Label(barFrame, "")
    slot.status:SetPoint("LEFT", slot.keysButton, "RIGHT", 8, 0)
    slot.status:SetPoint("RIGHT", barFrame, "RIGHT", 0, 0)
    slot.status:SetWordWrap(false)
    if slot.status.SetMaxLines then slot.status:SetMaxLines(1) end
    local hit = CreateFrame("Frame", nil, barFrame)
    hit:SetPoint("TOPLEFT", slot.status, "TOPLEFT", 0, 2)
    hit:SetPoint("BOTTOMRIGHT", slot.status, "BOTTOMRIGHT", 0, -2)
    hit:EnableMouse(true)
    W.Tooltip(hit, function(tip) tip:AddLine(slot.status.icFull or "", 1, 1, 1, true) end)

    slot.guide = guide
    slot.guideText = W.Label(guide, "", { font = "small", color = "textDim" })
    slot.guideText:SetPoint("LEFT", guide, "LEFT", 0, 0)
    slot.guideText:SetPoint("RIGHT", guide, "RIGHT", 0, 0)
    slot.guideText:SetWordWrap(false)
    if slot.guideText.SetMaxLines then slot.guideText:SetMaxLines(1) end
    guide:HookScript("OnShow", function()
        GuideEvents(true)
        PaintSlot()
    end)
    guide:HookScript("OnHide", function() GuideEvents(false) end)
    if guide:IsVisible() then GuideEvents(true) end
    PaintSlot()
end

--------------------------------------------------------------------------------
-- Commands and the ready hook
--------------------------------------------------------------------------------

ns.AddCommand("bar", "the marking bar: show, hide, lock, unlock, solo on|off, reset", function(rest)
    if not ns.cdb then
        ns.Print("the saved settings are not in hand yet.")
        return
    end
    local parsed = UIBar.Parse(rest)
    if parsed.action == "refuse" then
        ns.Print("|cffff5555say show, hide, lock, unlock, solo on, solo off or reset.|r")
        return
    end
    if Restrict.InCombat() and parsed.action ~= "lock" and parsed.action ~= "unlock" then
        ns.Print("the bar holds secure buttons, so it changes out of combat only.")
        return
    end
    local saved = Saved()
    if parsed.action == "toggle" then
        ToggleShown()
        return
    elseif parsed.action == "show" then
        saved.shown = true
    elseif parsed.action == "hide" then
        saved.shown = false
    elseif parsed.action == "lock" then
        saved.locked = true
    elseif parsed.action == "unlock" then
        saved.locked = false
    elseif parsed.action == "solo" then
        if parsed.arg == nil then saved.outsideRaid = not saved.outsideRaid else saved.outsideRaid = parsed.arg end
    elseif parsed.action == "reset" then
        saved.fx, saved.fy, saved.locked, saved.shown = nil, nil, false, true
    end
    if bar then
        if Restrict.InCombat() then bar:SetLocked(true) else Place() end
    end
    if parsed.action == "solo" then
        ns.Print(saved.outsideRaid and "the bar shows out of a group too." or "the bar shows in a group only.")
    end
    if bar then SayState() end
    PaintSlot()
end, "bar [show|hide|lock|unlock|solo on|off|reset]")

ns.OnReady("ui_bar", function()
    if IC_HEADLESS then return end
    Build()
    MB.OnUpdate("ui_bar", function()
        if bar and MB.Built() and not skins.pack then Layout() end
        Paint()
        PaintSlot()
    end)
    MB.Provider.BuildSlot = UIBar.BuildSlot
    if ns.UI and ns.UI.SetMarking then ns.UI.SetMarking(MB.Provider) end
    -- The roster decides whether the bar shows; combat locks its drag and holds its place.
    ns.Events.On("GROUP_ROSTER_UPDATE", "ui_bar", function()
        if Restrict.InCombat() then return end
        if ns.UI and ns.UI.ReadRoster then ns.UI.ReadRoster() end
        Place()
        Paint()
        PaintSlot()
    end)
    Restrict.OnChange(function(now)
        if not bar then return end
        if now.secure or now.combat then
            -- PLAYER_REGEN_DISABLED comes about 3 s before lockdown: let go of a drag under
            -- way now, while the bar (the secure buttons' parent) may still be moved.
            local lockdown = type(InCombatLockdown) == "function" and InCombatLockdown()
            if bar.icMoving and not lockdown then
                bar.icMoving = false
                bar:StopMovingOrSizing()
                bar:SetUserPlaced(false)
                SavePlace(bar)
            end
            bar:SetLocked(true)
        else
            Place()
            Paint()
        end
        PaintSlot()
    end)
end)
