local addonName, ns = ...

--[[
UI_Main: the one window, its tabs, and the addon's on/off switch.

Owned by lane G (window and config). The top half is pure (each function has a case in
Tests_UI.lua). The window is built the first time it is opened, which is never before the
ns.OnReady hook at the bottom, and that hook returns early on IC_HEADLESS.

For other lanes:

    ns.UI.AddTab(key, label, build, opts)
        Adds a tab. build(page) fills `page`, a frame already sized to the room below the
        tabs (page:GetWidth() and GetHeight() answer at once). It runs the first time the
        tab is shown, inside a pcall: an error prints and leaves the tab saying so. Known
        keys sit in a fixed order (assign, roles, rules, check, deaths, settings); any
        other key goes after them in the order added. opts, all optional:
            refresh()            called by ns.UI.Refresh() while the tab is showing
            onResize(w, h)       the page's new size while the window is dragged larger
            placeholder = true   a later AddTab with the same key replaces this one
        Returns true, or false and why (a key already taken by a real tab).
        Lane C's raid check grid belongs in the "check" tab: until it calls AddTab("check",
        ...), a placeholder there opens the standalone grid.
    ns.UI.Open(key), Toggle(key), Close(), IsShown(), Select(key), Refresh()
    ns.UI.IsEnabled(), ns.UI.SetEnabled(on)
        The addon's master switch (settings.enabled), also /mfd on and /mfd off. Setting it
        re-syncs DeathWatch and ChatCue so their events are dropped or taken back, then
        tells every OnChange listener ("enabled", on).
    ns.UI.OnChange(key, fn)           fn(kind, value) after a change made here: "enabled"
                                      (the switch), "plan" (a seat plan edited, value the
                                      plan key) or "rules" (value the instance key). Lane B
                                      rebuilds the Mark pack plan on "plan" and "rules".
    ns.UI.Changed(kind, value)        tells them; the pages call it after every edit
    ns.UI.SetMarking(provider)        LANE B HOOK, see "The marking slot" below
    ns.UI.Here()                      instanceKey, instance name (client, readable or "open")
    ns.UI.Roster()                    the last roster snapshot read out of combat (LibICGroup)

The marking slot. Lane B (marking runtime) is waiting on the in-game test of secure /tm
marks, so the Assignments tab leaves a strip for it and the panel plans on its own until
then. Lane B calls ns.UI.SetMarking(provider) at ready, provider fields all optional:
    provider.BuildSlot(bar, guide)   bar: a frame across the Assignments toolbar for the Mark
                                     pack / Clear / Re-mark buttons; guide: a one-line frame
                                     under it for the Mark guide ("Skull: press Shift-1").
                                     Called once, when both the provider and the tab exist.
    provider.Steps()                 steps, key, sourceText: the plan the buttons hold, so
                                     the panel shows exactly what a press will do
    provider.WhyState()              fields of DebugWhy.WhyNot's state only lane B knows
                                     (blind, stale, built, dropped, nameless)

Layout of the window (px from its top): title bar 0 to 24, tabs at 30 (22 high), the page
from 58 to the footer, a 20 px footer line at the bottom with the resize grip in its
right-hand corner. Pages never reach the footer, so nothing shares a pixel with a list.
]]

ns.UI = ns.UI or {}
local UI = ns.UI

local W = LibStub("LibICWidgets-1.0")
local Restrict = LibStub("LibICRestrict-1.0")
local Theme = LibStub("LibICTheme-1.0")

UI.NAME = "MarkedForDeathMain"   -- named for UISpecialFrames, so Escape closes it
UI.DEFAULT_W, UI.DEFAULT_H = 720, 540   -- px
UI.MIN_W, UI.MIN_H = 680, 500           -- px; lane D's Deaths page needs about 600 by 330
UI.TITLE_H = 24        -- px, the title bar
UI.TABS_TOP = 30       -- px from the window top to the tab strip
UI.TAB_H = 22          -- px
UI.PAGE_TOP = 58       -- px from the window top to a page
UI.PAD = 8             -- px round a page
UI.FOOT_H = 20         -- px, the footer line under the pages
UI.TAB_W = 104         -- px, a tab before the strip shrinks them

-- Known tabs, in the order they sit. Anything else follows them in the order added.
UI.ORDER = { assign = 1, roles = 2, rules = 3, check = 4, deaths = 5, settings = 6 }

--------------------------------------------------------------------------------
-- Pure
--------------------------------------------------------------------------------

-- tabs: { { key, seq }, ... }. Returns a new list: known keys in UI.ORDER, then the rest
-- by seq (the order they were added).
function UI.SortTabs(tabs)
    local out = {}
    for i, tab in ipairs(tabs or {}) do out[i] = tab end
    table.sort(out, function(a, b)
        local ao, bo = UI.ORDER[a.key] or 100, UI.ORDER[b.key] or 100
        if ao ~= bo then return ao < bo end
        return (a.seq or 0) < (b.seq or 0)
    end)
    return out
end

-- The saved size held between the minimum and the screen. Returns w, h.
function UI.Size(saved, minW, minH, maxW, maxH)
    local w = tonumber(saved and saved.w) or UI.DEFAULT_W
    local h = tonumber(saved and saved.h) or UI.DEFAULT_H
    w, h = math.max(minW or UI.MIN_W, w), math.max(minH or UI.MIN_H, h)
    if maxW and maxW > 0 then w = math.min(w, math.max(minW or UI.MIN_W, maxW)) end
    if maxH and maxH > 0 then h = math.min(h, math.max(minH or UI.MIN_H, maxH)) end
    return math.floor(w + 0.5), math.floor(h + 0.5)
end

-- The room a page has in a window `w` by `h`. Returns pageW, pageH.
function UI.PageSize(w, h)
    return w - 2 * UI.PAD, h - UI.PAGE_TOP - UI.FOOT_H - UI.PAD
end

-- The tab to show: `want` if it is one of the sorted tabs, else the first. Nil with none.
function UI.PickTab(want, sorted)
    for _, tab in ipairs(sorted or {}) do
        if tab.key == want then return want end
    end
    return sorted and sorted[1] and sorted[1].key or nil
end

-- /mfd on and /mfd off. word: "on" or "off"; enabled: the setting now (nil counts as on).
-- Returns { action = "set" | "same", value, text }.
function UI.PowerPlan(word, enabled)
    local on = word == "on"
    local now = enabled ~= false
    if on == now then
        return { action = "same", value = on,
            text = on and "already on." or "already off. /mfd on turns it back on." }
    end
    return { action = "set", value = on,
        text = on and "on: death calls, chat cue and marking are back."
            or "off: no death calls, no chat cue, no marking. Rules and roles are kept. /mfd on undoes it." }
end

-- Relative age for a list or a status line: 12s, 5m, 3h, 2d. Nil or negative is "0s".
function UI.Age(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    if seconds < 60 then return seconds .. "s" end
    if seconds < 3600 then return math.floor(seconds / 60) .. "m" end
    if seconds < 86400 then return math.floor(seconds / 3600) .. "h" end
    return math.floor(seconds / 86400) .. "d"
end

-- How an instance key reads to a player. names: Instances.list (or a case's table).
function UI.KeyLabel(key, names)
    if key == nil or key == "default" then return "Default plan" end
    if key == "open" then return "Open world" end
    local id = type(key) == "string" and tonumber(key:match("^i:(%d+)$"))
    if id then
        local entry = names and names[id]
        local name = type(entry) == "table" and entry.name or nil
        return name and (name .. " (" .. id .. ")") or ("Instance " .. id)
    end
    local zone = type(key) == "string" and key:match("^legacy:(.+)$")
    if zone then return zone .. " (Anniversary)" end
    return tostring(key)
end

-- The footer: where the player is, how many rules apply there, and the switch when off.
-- view = { enabled, key, names, rules, lead, badHex }. badHex is the theme's red as a
-- colour code. Returns text (colour codes included).
function UI.FooterText(view)
    view = view or {}
    local parts = {}
    if view.enabled == false then parts[#parts + 1] = (view.badHex or "") .. "Off|r (/mfd on)" end
    parts[#parts + 1] = "Here: " .. UI.KeyLabel(view.key or "open", view.names)
    if view.rules then parts[#parts + 1] = view.rules .. (view.rules == 1 and " rule" or " rules") end
    if view.lead then parts[#parts + 1] = view.lead end
    return table.concat(parts, "   ")
end

--------------------------------------------------------------------------------
-- The tab registry
--------------------------------------------------------------------------------

local tabs = {}         -- { key, label, build, opts, seq, page, built, failed }
local seq = 0
local frame             -- the window, or nil before the first open
local strip             -- the W.Tabs strip
local current           -- the key showing
local changeListeners = {}     -- key -> fn(kind, value)
local marking           -- lane B's provider, or nil

local function Find(key)
    for _, tab in ipairs(tabs) do
        if tab.key == key then return tab end
    end
    return nil
end

local function Saved()
    local cdb = ns.cdb
    if not cdb then return {} end
    if type(cdb.windows) ~= "table" then cdb.windows = {} end
    if type(cdb.windows.main) ~= "table" then cdb.windows.main = {} end
    return cdb.windows.main
end

local function ErrorLine(text)
    ns.Print("|cffff5555" .. text .. "|r")
end

-- Fills a tab's page the first time it shows. A build that errors leaves a line in the
-- page saying so, and the chat line names the tab.
local function Ensure(tab)
    if tab.built or not tab.page then return end
    tab.built = true
    local ok, err = pcall(tab.build, tab.page)
    if not ok then
        tab.failed = true
        ErrorLine("the " .. tab.label .. " tab did not build: " .. tostring(err))
        local why = W.Label(tab.page, "This tab did not build. /mfd log error has the details.", { color = "bad" })
        why:SetPoint("TOPLEFT", tab.page, "TOPLEFT", 4, -4)
        if ns.Log and ns.Log.Write then ns.Log.Write("error", tab.label .. " tab: " .. tostring(err), "ui") end
    end
end

local function MakePage(tab)
    if tab.page or not frame then return end
    local pageW, pageH = UI.PageSize(frame:GetWidth(), frame:GetHeight())
    local page = CreateFrame("Frame", nil, frame)
    page:SetPoint("TOPLEFT", frame, "TOPLEFT", UI.PAD, -UI.PAGE_TOP)
    page:SetSize(pageW, pageH)
    page:Hide()
    tab.page = page
end

local function BuildStrip()
    if strip then strip:Hide() end
    local sorted = UI.SortTabs(tabs)
    local list = {}
    for i, tab in ipairs(sorted) do
        MakePage(tab)
        list[i] = { key = tab.key, label = tab.label, page = tab.page }
    end
    current = UI.PickTab(current or Saved().tab, sorted)
    strip = W.Tabs(frame, list, {
        width = frame:GetWidth() - 2 * UI.PAD, tabWidth = UI.TAB_W, height = UI.TAB_H,
        selected = current,
        onSelect = function(key) UI.Select(key) end,
    })
    strip:SetPoint("TOPLEFT", frame, "TOPLEFT", UI.PAD, -UI.TABS_TOP)
end

function UI.AddTab(key, label, build, opts)
    if type(key) ~= "string" or key == "" then return false, "a tab needs a key" end
    if type(label) ~= "string" or label == "" then return false, "a tab needs a label" end
    if type(build) ~= "function" then return false, "a tab needs a build function" end
    opts = type(opts) == "table" and opts or {}
    local tab = Find(key)
    if tab then
        if not tab.placeholder then return false, "the " .. key .. " tab is already taken" end
        -- A placeholder gives way. Its page is emptied by giving the tab a fresh one.
        if tab.page then tab.page:Hide() end
        tab.page, tab.built, tab.failed = nil, false, false
        tab.label, tab.build, tab.opts, tab.placeholder = label, build, opts, opts.placeholder == true
    else
        seq = seq + 1
        tabs[#tabs + 1] = { key = key, label = label, build = build, opts = opts, seq = seq,
            placeholder = opts.placeholder == true }
    end
    if frame then
        BuildStrip()
        if frame:IsShown() then UI.Select(current) end
    end
    return true
end

--------------------------------------------------------------------------------
-- Where we are, who is here
--------------------------------------------------------------------------------

local roster

-- The instance key and name from GetInstanceInfo, each only when readable. A secret or a
-- failed call reads as the open world, which has no rules of its own by default.
function UI.Here()
    if IC_HEADLESS or type(GetInstanceInfo) ~= "function" then return "open", nil end
    local ok, name, instanceType, _, _, _, _, _, instanceID = pcall(GetInstanceInfo)
    if not ok then return "open", nil end
    local key = ns.Rules.InstanceKey(Restrict.Readable(instanceType), Restrict.Readable(instanceID))
    name = Restrict.Readable(name)
    return key, type(name) == "string" and name or nil
end

-- The roster, read again only out of combat; in combat the last read stands.
function UI.ReadRoster()
    if IC_HEADLESS then return roster end
    if Restrict.InCombat() and roster then return roster end
    local Group = LibStub("LibICGroup-1.0", true)
    if not Group then return roster end
    local ok, snap = pcall(Group.Now)
    if ok and type(snap) == "table" then roster = snap end
    return roster
end

function UI.Roster()
    return roster or UI.ReadRoster()
end

--------------------------------------------------------------------------------
-- The switch
--------------------------------------------------------------------------------

function UI.IsEnabled()
    return not (ns.db and ns.db.settings and ns.db.settings.enabled == false)
end

function UI.OnChange(key, fn)
    assert(type(key) == "string" and type(fn) == "function", "OnChange needs a key and a function")
    changeListeners[key] = fn
end

-- Tells every OnChange listener, in key order. kind: "enabled", "plan" or "rules".
function UI.Changed(kind, value)
    local keys = {}
    for key in pairs(changeListeners) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local ok, err = pcall(changeListeners[key], kind, value)
        if not ok then ErrorLine(key .. " did not take the " .. tostring(kind) .. " change: " .. tostring(err)) end
    end
end

local function SyncAll(on)
    for _, mod in ipairs({ ns.DeathWatch, ns.ChatCue }) do
        if type(mod) == "table" and type(mod.Sync) == "function" then
            local ok, err = pcall(mod.Sync)
            if not ok then ErrorLine("could not apply the switch: " .. tostring(err)) end
        end
    end
    UI.Changed("enabled", on)
end

-- Returns the PowerPlan it acted on, or nil before the saved settings are in hand.
function UI.SetEnabled(on, quiet)
    if not (ns.db and ns.db.settings) then
        ns.Print("the saved settings are not in hand yet.")
        return nil
    end
    local plan = UI.PowerPlan(on and "on" or "off", ns.db.settings.enabled)
    if plan.action == "set" then
        ns.db.settings.enabled = plan.value
        SyncAll(plan.value)
        if ns.Log and ns.Log.Write then ns.Log.Write("plan", plan.value and "turned on" or "turned off", "switch") end
    end
    if not quiet then ns.Print(plan.text) end
    UI.Refresh()
    return plan
end

--------------------------------------------------------------------------------
-- The marking slot (lane B)
--------------------------------------------------------------------------------

function UI.SetMarking(provider)
    marking = type(provider) == "table" and provider or nil
    if ns.UIAssignments and ns.UIAssignments.MarkingChanged then ns.UIAssignments.MarkingChanged() end
end

function UI.Marking()
    return marking
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

local controls = {}

-- The theme's red as a colour code, so "off" reads on every theme.
local function BadHex()
    return Theme.Hex(Theme.Current().colors.bad)
end

local function PaintSwitch()
    if not frame then return end
    local on = UI.IsEnabled()
    controls.title:SetText(on and "Marked For Death" or ("Marked For Death  " .. BadHex() .. "(off)|r"))
    controls.switch:SetLabel(on and "Turn off" or "Turn on")
    controls.switch:SetKind(on and "normal" or "accent")
end

local function PaintFooter()
    if not frame then return end
    local key = UI.Here()
    local count
    if ns.Comms and ns.Comms.ActiveRules then
        local ok, set = pcall(ns.Comms.ActiveRules, key)
        if ok and type(set) == "table" then
            count = 0
            for _ in pairs(set) do count = count + 1 end
        end
    end
    local lead
    if ns.Comms and ns.Comms.Lead and ns.Lead and ns.Lead.Describe then
        local ok, text = pcall(function() return ns.Lead.Describe(ns.Comms.Lead()) end)
        if ok and type(text) == "string" then lead = (text:match("^([^,;]+)")) end
    end
    controls.footer:SetText(UI.FooterText({
        enabled = UI.IsEnabled(), key = key, names = ns.Instances and ns.Instances.list,
        rules = count, lead = lead, badHex = BadHex(),
    }))
end

local function Fit(w, h)
    local pageW, pageH = UI.PageSize(w, h)
    for _, tab in ipairs(tabs) do
        if tab.page then
            tab.page:SetSize(pageW, pageH)
            if tab.built and not tab.failed and type(tab.opts.onResize) == "function" then
                pcall(tab.opts.onResize, pageW, pageH)
            end
        end
    end
end

local function SavePlace(self)
    local fx, fy = W.GetPlace(self)
    if fx then
        local saved = Saved()
        saved.fx, saved.fy = fx, fy
    end
end

-- Listens only while the window is open: a roster or zone change repaints what is shown.
local function OnWorld()
    UI.ReadRoster()
    UI.Refresh()
end

local function Listen(on)
    for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
        "PLAYER_REGEN_ENABLED" }) do
        if on then ns.Events.On(event, "ui_main", OnWorld) else ns.Events.Off(event, "ui_main") end
    end
end

local function Build()
    local saved = Saved()
    local w, h = UI.Size(saved, UI.MIN_W, UI.MIN_H, UIParent:GetWidth(), UIParent:GetHeight())
    frame = W.Panel(UIParent, {
        name = UI.NAME, width = w, height = h, strata = "MEDIUM", movable = true, onMoved = SavePlace,
    })
    frame:SetToplevel(true)
    frame:Hide()

    local bar = W.Panel(frame, { height = UI.TITLE_H, role = "raised", edge = false })
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    W.DragHandle(bar, frame)
    controls.title = W.Label(bar, "Marked For Death", { font = "title", color = "accent" })
    controls.title:SetPoint("LEFT", bar, "LEFT", UI.PAD, 0)

    local close = W.Button(bar, "x", 20, 18, { kind = "flat", onClick = function() frame:Hide() end })
    close:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
    W.Tooltip(close, function(tip) tip:AddLine("Close") end)

    -- The switch sits in the title bar, not on a tab: the moment you want it you do not
    -- want to go looking for it.
    controls.switch = W.Button(bar, "Turn off", 80, 18, {
        kind = "normal",
        onClick = function() UI.SetEnabled(not UI.IsEnabled()) end,
    })
    controls.switch:SetPoint("RIGHT", close, "LEFT", -6, 0)
    W.Tooltip(controls.switch, function(tip)
        tip:AddLine(UI.IsEnabled() and "Turn Marked For Death off" or "Turn Marked For Death on")
        tip:AddLine("Off stops death calls, the chat cue and marking without unloading the addon.", 1, 1, 1, true)
        tip:AddLine("Rules, roles and settings are kept. Same as /mfd off and /mfd on.", 1, 1, 1, true)
    end)

    controls.footer = W.Label(frame, "", { font = "small", color = "textDim" })
    controls.footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", UI.PAD, 5)
    controls.footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -24, 5)
    controls.footer:SetWordWrap(false)
    if controls.footer.SetMaxLines then controls.footer:SetMaxLines(1) end

    BuildStrip()

    W.Resize(frame, {
        minWidth = UI.MIN_W, minHeight = UI.MIN_H,
        onResize = function(nw, nh) Fit(nw, nh) end,
        onResized = function(nw, nh)
            local s = Saved()
            s.w, s.h = math.floor(nw + 0.5), math.floor(nh + 0.5)
            Fit(nw, nh)
            -- A page that fits itself on show (lane D's) gets the new size this way.
            local tab = Find(current)
            if tab and tab.page and tab.page:IsShown() then
                tab.page:Hide()
                tab.page:Show()
            end
        end,
    })

    -- Hooked, not set: the panel's own OnHide ends a drag that a close interrupted.
    frame:HookScript("OnShow", function()
        Listen(true)
        UI.ReadRoster()
        PaintSwitch()
        PaintFooter()
    end)
    frame:HookScript("OnHide", function() Listen(false) end)

    W.SetPlace(frame, saved.fx or 0.25, saved.fy or 0.15)
    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = UI.NAME end
end

function UI.Select(key)
    if not frame then Build() end
    local sorted = UI.SortTabs(tabs)
    key = UI.PickTab(key, sorted)
    if not key then return end
    current = key
    Saved().tab = key
    local tab = Find(key)
    Ensure(tab)
    strip:Select(key)
    PaintSwitch()
    PaintFooter()
end

function UI.Open(key)
    if not ns.db then
        ns.Print("the saved settings are not in hand yet.")
        return
    end
    if not frame then Build() end
    frame:Show()
    frame:Raise()
    UI.Select(key or current or Saved().tab)
end

function UI.Close()
    if frame then frame:Hide() end
end

function UI.IsShown()
    return frame ~= nil and frame:IsShown()
end

-- Opens on `key`, or closes when that tab is already the one showing.
function UI.Toggle(key)
    if frame and frame:IsShown() and (key == nil or key == current) then
        frame:Hide()
        return
    end
    UI.Open(key)
end

-- Repaints the title, the footer and the tab showing. Cheap when the window is closed.
function UI.Refresh()
    if not frame or not frame:IsShown() then return end
    PaintSwitch()
    PaintFooter()
    local tab = Find(current)
    if tab and tab.built and not tab.failed and type(tab.opts.refresh) == "function" then
        local ok, err = pcall(tab.opts.refresh)
        if not ok then ErrorLine("the " .. tab.label .. " tab did not refresh: " .. tostring(err)) end
    end
end

--------------------------------------------------------------------------------
-- The raid check placeholder (until lane C moves its grid into the tab)
--------------------------------------------------------------------------------

local function BuildCheckPlaceholder(page)
    local open = W.Button(page, "Open the raid check", 150, 22, {
        kind = "accent",
        onClick = function() if ns.RaidCheckUI and ns.RaidCheckUI.ShowGrid then ns.RaidCheckUI.ShowGrid() end end,
    })
    open:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    local board = W.Button(page, "Buff board", 100, 22, {
        onClick = function() if ns.RaidCheckUI and ns.RaidCheckUI.ToggleBoard then ns.RaidCheckUI.ToggleBoard() end end,
    })
    board:SetPoint("LEFT", open, "RIGHT", 6, 0)
    local note = W.Label(page, "The raid check opens in its own window for now. Same as /mfd check.",
        { color = "textDim" })
    note:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -10)
end

--------------------------------------------------------------------------------
-- Commands and login
--------------------------------------------------------------------------------

ns.AddCommand("on", "turn Marked For Death back on", function() UI.SetEnabled(true) end)
ns.AddCommand("off", "turn death calls, the chat cue and marking off; rules and roles are kept",
    function() UI.SetEnabled(false) end)
ns.AddCommand("window", "open or close the window, on a tab if named (assign, roles, rules, check, deaths, settings)",
    function(rest)
        local word = (type(rest) == "string" and rest or ""):lower():match("^%s*(%S*)") or ""
        if word ~= "" and not Find(word) then
            ns.Print("no tab called " .. word .. ". Tabs: assign, roles, rules, check, deaths, settings.")
            return
        end
        UI.Toggle(word ~= "" and word or nil)
    end, "window [tab]")

ns.OnReady("ui_main", function()
    if IC_HEADLESS then return end
    if ns.RaidCheckUI and not Find("check") then
        UI.AddTab("check", "Raid check", BuildCheckPlaceholder, { placeholder = true })
    end
    if ns.Comms and ns.Comms.Listen then
        ns.Comms.Listen("ui_main", function() UI.Refresh() end)
    end
end)
