local addonName, ns = ...

--[[
UI_Settings: the Settings tab. The switches that are not another tab's, and the status
lines that say why something is not happening: the Raid Lead, combat logging (lane H's
CombatLog), other addons doing the same jobs (lane H's Conflicts) and the reasons a Mark
pack press would not do what you expect (lane A's DebugWhy). Death calls and the chat cue
have their own Deaths tab (lane D); this one sums them up and opens it.

Owned by lane G (window and config). Frames are made only inside Build; the ready hook
returns early on IC_HEADLESS. The pure helpers below have cases in Tests_UI.lua.

    UISettings.DeathsSummary(db)     one line for the death calls and the chat cue
    UISettings.WhyState(view)        DebugWhy.WhyNot's state from what this file can see
    UISettings.WhyLines(reasons)     { { text, role } } for DebugWhy's answer
    UISettings.ConflictLines(lines)  { { text, role } } for Conflicts' findings
    UISettings.ListedText(settings, names)  which instances combat logging is listed for

The page is a form in a scroll: sections of fixed single-line rows (24 px), each status
block with a fixed number of line slots, so its height is known before anything is drawn.
]]

ns.UISettings = ns.UISettings or {}
local UIS = ns.UISettings

local W = LibStub("LibICWidgets-1.0")
local Util = LibStub("LibICUtil-1.0")

local ROW = 24              -- px, one row of the form
local HEAD = 28             -- px, a section heading with the gap above it
local LINE = 18             -- px, one status line
local LOG_LINES = 4         -- status slots for combat logging
local CONFLICT_LINES = 5    -- for other addons
local WHY_LINES = 8         -- for the marking reasons (DebugWhy has nine; "solo" never shows with others)

local LEVEL_ROLE = { block = "bad", warn = "warn", info = "textDim" }

--------------------------------------------------------------------------------
-- Pure
--------------------------------------------------------------------------------

local function KindWord(cfg)
    if type(cfg) ~= "table" then return "off" end
    if cfg.override == "on" then return "on everywhere" end
    if cfg.override == "off" then return "off (right now: nowhere)" end
    if cfg.on ~= true then return "off" end
    return cfg.trash and "on, bosses and trash" or "on, ticked bosses"
end

function UIS.DeathsSummary(db)
    local deaths = db and db.deaths or {}
    local cue = db and db.settings and db.settings.cue or {}
    local cueText = "off"
    if cue.enabled == true then
        cueText = (cue.word ~= nil and cue.word ~= "" and cue.sound ~= nil and tostring(cue.sound) ~= "")
            and ("on for \"" .. cue.word .. "\"") or "on, but no word or sound set yet"
    end
    return "Tank deaths " .. KindWord(deaths.tank) .. ".   Healer deaths " .. KindWord(deaths.healer)
        .. ".   Chat cue " .. cueText .. "."
end

--[[
view = { enabled, roster (a LibICGroup snapshot), ruleCount, conflicts (Conflicts rows),
         extra (lane B's WhyState fields) }. Returns the state DebugWhy.WhyNot reads.
Fields nobody here can know (blind, stale, built, dropped, nameless) come only from extra.
]]
function UIS.WhyState(view)
    view = view or {}
    local roster = view.roster
    local state = { enabled = view.enabled, ruleCount = view.ruleCount }
    if type(roster) == "table" and roster.kind then
        state.inGroup = roster.kind ~= "solo"
        state.inRaid = roster.kind == "raid"
        state.canMark = roster.canMark
    end
    local names = {}
    for _, row in ipairs(view.conflicts or {}) do
        if row.topic == (ns.Conflicts and ns.Conflicts.TOPIC_ICONS) and row.addon then names[#names + 1] = row.addon end
    end
    if #names > 0 then state.conflicts = names end
    for k, v in pairs(view.extra or {}) do state[k] = v end
    return state
end

function UIS.WhyLines(reasons)
    local out = {}
    for i, r in ipairs(reasons or {}) do out[i] = { r.text, LEVEL_ROLE[r.level] or "text" } end
    if #out == 0 then out[1] = { "Nothing in the way that this addon can see.", "good" } end
    return out
end

function UIS.ConflictLines(lines)
    local out = {}
    for i, line in ipairs(lines or {}) do out[i] = { line, "warn" } end
    if #out == 0 then out[1] = { "No other addon is doing one of these jobs.", "good" } end
    return out
end

function UIS.ListedText(settings, names)
    local keys = Util.SortedKeys(settings and settings.instances or {})
    local labels = {}
    for _, key in ipairs(keys) do
        if settings.instances[key] == true then labels[#labels + 1] = ns.UI.KeyLabel(key, names) end
    end
    if #labels == 0 then return "Listed: none, so nothing is logged." end
    table.sort(labels)
    return "Listed: " .. table.concat(labels, ", ") .. "."
end

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------

local page
local controls = {}
local content
local y = 0

local function Tip(frame, title, ...)
    local lines = { ... }
    W.Tooltip(frame, function(tip)
        tip:AddLine(title)
        for _, line in ipairs(lines) do tip:AddLine(line, 1, 1, 1, true) end
    end)
end

local function Heading(text)
    y = y + 6
    local l = W.Label(content, text, { font = "title", color = "accent" })
    l:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    y = y + HEAD - 6
end

local function Check(text, onClick, title, ...)
    local box = W.CheckBox(content, { onClick = onClick })
    box:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -(y + 2))
    local label = W.Label(content, text)
    label:SetPoint("LEFT", box, "RIGHT", 6, 0)
    Tip(box, title or text, ...)
    y = y + ROW
    return box
end

-- n fixed single-line slots; Fill writes { text, role } pairs into them and hides the rest.
-- A line cut at the edge is read in full on hover.
local function Slots(n, x)
    local slots = {}
    for i = 1, n do
        local l = W.Label(content, "")
        l:SetPoint("TOPLEFT", content, "TOPLEFT", x or 4, -(y + (i - 1) * LINE))
        l:SetPoint("RIGHT", content, "RIGHT", -4, 0)
        l:SetWordWrap(false)
        if l.SetMaxLines then l:SetMaxLines(1) end
        local hit = CreateFrame("Frame", nil, content)
        hit:SetPoint("TOPLEFT", l, "TOPLEFT", 0, 2)
        hit:SetPoint("BOTTOMRIGHT", l, "BOTTOMRIGHT", 0, -2)
        hit:EnableMouse(true)
        W.Tooltip(hit, function(tip) tip:AddLine(l.icFull or "", 1, 1, 1, true) end)
        l.hit = hit
        slots[i] = l
    end
    y = y + n * LINE + 4
    return slots
end

local function Fill(slots, pairsList)
    for i, slot in ipairs(slots) do
        local p = pairsList[i]
        if p then
            slot:SetText(p[1])
            slot:SetRole(p[2] or "text")
            slot.icFull = p[1]
            slot:Show()
            slot.hit:Show()
        else
            slot:SetText("")
            slot.icFull = nil
            slot:Hide()
            slot.hit:Hide()
        end
    end
end

local function ButtonRow(buttons)
    local last
    for _, spec in ipairs(buttons) do
        local b = W.Button(content, spec[1], spec[2], 22, { onClick = spec[3] })
        if last then b:SetPoint("LEFT", last, "RIGHT", 6, 0) else b:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -y) end
        Tip(b, spec[1], spec[4])
        controls[spec[5] or spec[1]] = b
        last = b
    end
    y = y + ROW + 4
end

local function Settings()
    return ns.db.settings
end

-- Combat logging, through lane H's module only.
local function LogSettings()
    local s = Settings()
    if type(s.logCombat) ~= "table" then s.logCombat = { enabled = true, instances = {} } end
    return s.logCombat
end

local function LogChanged()
    local CombatLog = ns.CombatLog
    if CombatLog and CombatLog.Check then pcall(CombatLog.Check, "settings changed") end
    if CombatLog and CombatLog.Sync then pcall(CombatLog.Sync) end
    UIS.Refresh()
end

local function ListHere()
    local CombatLog = ns.CombatLog
    if not (CombatLog and CombatLog.Command) then return end
    local settings = LogSettings()
    local plan = CombatLog.Command("here", { key = (ns.UI.Here()), settings = settings })
    if plan.action == "refuse" then
        ns.Print(plan.why .. ".")
        return
    end
    if type(settings.instances) ~= "table" then settings.instances = {} end
    if plan.action == "add" then
        settings.instances[plan.key] = true
    elseif plan.action == "remove" then
        settings.instances[plan.key] = nil
    end
    LogChanged()
end

local function Build()
    -- General
    Heading("General")
    controls.enabled = Check("Marked For Death on", function(on) ns.UI.SetEnabled(on) end,
        "Marked For Death on", "Off stops death calls, the chat cue and marking without unloading anything.",
        "Rules, roles and settings are kept. Same as /mfd off and /mfd on, and the title bar's button.")
    controls.debug = Check("Debug lines in chat", function(on)
        Settings().debug = on
        UIS.Refresh()
    end, "Debug lines", "Maintainer lines in chat. Same as /mfd debug.")
    controls.minimap = Check("Minimap button", function(on)
        if ns.Launcher and ns.Launcher.SetShown then ns.Launcher.SetShown(on) end
        UIS.Refresh()
    end, "Minimap button", "The round button on the minimap's rim. The addon list beside the minimap",
        "(the Addon Compartment) always has Marked For Death, so there is a way back. /mfd minimap.")

    -- Raid Lead
    Heading("Raid Lead")
    controls.lead = Slots(1)
    local hint = W.Label(content, "The Raid Lead says the pre-pull and death lines: /mfd lead <name>, or clear.",
        { color = "textDim" })
    hint:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -y)
    hint:SetPoint("RIGHT", content, "RIGHT", -4, 0)
    hint:SetWordWrap(false)
    y = y + LINE + 4

    -- Deaths
    Heading("Death calls and chat cue")
    controls.deaths = Slots(1)
    ButtonRow({ { "Open the Deaths tab", 150, function() ns.UI.Open("deaths") end,
        "Tank and healer death calls, the bosses they are called on, the chat cue and its sound." } })

    -- Combat logging
    Heading("Combat logging")
    controls.logOn = Check("Combat logging allowed", function(on)
        LogSettings().enabled = on
        LogChanged()
    end, "Combat logging allowed", "Lets Marked For Death switch the game's combat log file on inside the",
        "instances listed below, and off on the way out. Nothing is logged until an instance is listed.")
    ButtonRow({
        { "List this instance", 130, ListHere,
            "Adds the instance you are in to the list, or takes it off. Same as /mfd combatlog here.", "logHere" },
        { "Clear the list", 110, function()
            W.Confirm("Take every instance off the combat logging list?", function()
                LogSettings().instances = {}
                LogChanged()
            end)
        end, "Takes every instance off the list.", "logClear" },
    })
    controls.listed = Slots(1)
    controls.log = Slots(LOG_LINES)

    -- Conflicts
    Heading("Other addons")
    controls.conflicts = Slots(CONFLICT_LINES)
    ButtonRow({ { "Check again", 100, function() UIS.Refresh() end,
        "Reads the other addons' settings again. Nothing of theirs is ever changed.", "conflictsAgain" } })

    -- Why
    Heading("Why marking might not work")
    controls.why = Slots(WHY_LINES)
    ButtonRow({ { "Check again", 100, function()
        ns.UI.ReadRoster()
        UIS.Refresh()
    end, "Reads the group again and works the list out afresh. Out of combat only.", "whyAgain" } })

    controls.scroll:SetContentHeight(y)
end

function UIS.Refresh()
    if not page or not ns.db then return end
    local s = Settings()
    controls.enabled:SetChecked(s.enabled ~= false)
    controls.debug:SetChecked(s.debug == true)
    controls.minimap:SetChecked(not (type(s.minimap) == "table" and s.minimap.hidden == true))

    local leadText = "Raid Lead: not known yet."
    if ns.Comms and ns.Comms.Lead and ns.Lead and ns.Lead.Describe then
        local ok, text = pcall(function() return ns.Lead.Describe(ns.Comms.Lead()) end)
        if ok and type(text) == "string" then leadText = text end
    end
    Fill(controls.lead, { { leadText, "text" } })
    Fill(controls.deaths, { { UIS.DeathsSummary(ns.db), "text" } })

    local logS = LogSettings()
    controls.logOn:SetChecked(logS.enabled == true)
    local names = ns.Instances and ns.Instances.list
    Fill(controls.listed, { { UIS.ListedText(logS, names), "text" } })
    local here, hereName = ns.UI.Here()
    local listed = type(logS.instances) == "table" and logS.instances[here] == true
    controls.logHere:SetLabel(listed and "Unlist this instance" or "List this instance")
    controls.logHere:SetEnabled(here ~= "open")
    local lines = {}
    if ns.CombatLog and ns.CombatLog.StatusLines then
        local view = { settings = logS, key = here, name = hereName }
        -- Lane H owns whether the client is logging and whether the log is ours; a View()
        -- from it fills those in. Without one the line says it is not readable from here.
        if ns.CombatLog.View then
            local ok, extra = pcall(ns.CombatLog.View)
            if ok and type(extra) == "table" then
                for k, v in pairs(extra) do view[k] = v end
            end
        end
        local ok, got = pcall(ns.CombatLog.StatusLines, view)
        if ok and type(got) == "table" then
            for i, line in ipairs(got) do lines[i] = { line, "text" } end
        end
    end
    Fill(controls.log, lines)

    local found = {}
    if ns.Conflicts and ns.Conflicts.Now then
        local ok, rows = pcall(ns.Conflicts.Now)
        if ok and type(rows) == "table" then found = rows end
    end
    local conflictLines = (#found > 0 and ns.Conflicts.Lines) and ns.Conflicts.Lines(found) or {}
    Fill(controls.conflicts, UIS.ConflictLines(conflictLines))

    local ruleCount = 0
    if ns.Comms and ns.Comms.ActiveRules then
        local ok, set = pcall(ns.Comms.ActiveRules, here)
        if ok and type(set) == "table" then
            for _ in pairs(set) do ruleCount = ruleCount + 1 end
        end
    end
    local extra
    local provider = ns.UI.Marking()
    if provider and type(provider.WhyState) == "function" then
        local ok, got = pcall(provider.WhyState)
        if ok and type(got) == "table" then extra = got end
    end
    local state = UIS.WhyState({
        enabled = s.enabled ~= false, roster = ns.UI.Roster(), ruleCount = ruleCount, conflicts = found, extra = extra,
    })
    local reasons = ns.DebugWhy and ns.DebugWhy.WhyNot and ns.DebugWhy.WhyNot(state) or {}
    Fill(controls.why, UIS.WhyLines(reasons))
end

local function Fit(w, h)
    if not controls.scroll then return end
    controls.scroll:SetViewWidth(w)
    controls.scroll:SetViewHeight(h)
end

function UIS.Build(parent)
    if page then return page end
    page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints(parent)
    local width, height = parent:GetWidth(), parent:GetHeight()
    controls.scroll = W.Scroll(page, width, height, { step = ROW * 3 })
    controls.scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    content = controls.scroll.content
    y = 0
    Build()
    page:SetScript("OnShow", UIS.Refresh)
    UIS.Refresh()
    return page
end

ns.OnReady("ui_settings", function()
    if IC_HEADLESS then return end
    ns.UI.AddTab("settings", "Settings", UIS.Build, { refresh = UIS.Refresh, onResize = Fit })
end)
