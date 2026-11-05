local addonName, ns = ...

--[[
UI_Roles: the Roles tab. Which job each raid icon's seat carries, in which order, and who
holds it. Every rule it applies is lane A's (Seats, Data_CC); the pure helpers below only
edit a plan table they are handed, each with a case in Tests_UI.lua.

Owned by lane G (window and config). Frames are made only inside Build, from the window's
first showing of the tab; the ready hook returns early on IC_HEADLESS.

    UIRoles.ROW_ORDER                 icons top to bottom: kill seats, then sheep, then banish
    UIRoles.PlanChoices(db, here, names)   the plan picker's { value, label } list
    UIRoles.PlanNote(key, own, label)      the line under the picker
    UIRoles.JobChoices()              { value, label } for the job picker
    UIRoles.SetJob(plan, icon, intent)     moves a seat to a job, last in that job's order
    UIRoles.MoveSeat(plan, icon, dir)      swaps a seat with its neighbour in its job (-1 up)
    UIRoles.SetPin(plan, icon, text)       the pinned player, trimmed; empty clears it
    UIRoles.SetReserved(plan, icon, on)
    UIRoles.OwnerText(record)              text and colour role for "Owner right now"

Which plan is being edited is saved per character (planEditing), because a picker that
forgets on reload makes an edit look lost. Picking an instance only reads its plan; the
first edit gives it a copy of its own (Seats.Detach), so browsing leaves nothing behind.

Layout, px from the page top: picker row 0 (22 high), note 30, header 56 (20), eight
fixed 26 px rows from 78 to 286, the footnote at 296 (two lines, to 326). The page is at
least 434 px high in the smallest window, so it never overflows.
]]

ns.UIRoles = ns.UIRoles or {}
local UIRoles = ns.UIRoles
local CC, Seats = ns.CC, ns.Seats

local W = LibStub("LibICWidgets-1.0")
local Util = LibStub("LibICUtil-1.0")

UIRoles.ROW_ORDER = { 8, 7, 6, 2, 5, 1, 4, 3 }

local TOP_NOTE = 30       -- px
local TOP_HEADER = 56     -- px
local TOP_ROWS = 78       -- px
local ROW_H = 26          -- px, one seat
local TOP_FOOT = 296      -- px

-- Column x positions, px from the page's left.
local X_ICON, X_SEAT, X_JOB, X_ORDER, X_PIN, X_RES, X_OWNER = 4, 26, 98, 214, 264, 414, 452
local W_SEAT, W_JOB, W_PIN = 66, 108, 140

--------------------------------------------------------------------------------
-- Pure
--------------------------------------------------------------------------------

-- The plans a player can pick: Default, where they are, every instance with a plan or
-- rules of its own, then every instance the bundled data knows. Each once, by label.
function UIRoles.PlanChoices(db, here, names)
    local seen, rest = { default = true }, {}
    local out = { { "default", "Default plan" } }
    local function Add(key)
        if type(key) ~= "string" or seen[key] or not ns.Rules.IsInstanceKey(key) or ns.Rules.IsLegacy(key) then
            return
        end
        seen[key] = true
        rest[#rest + 1] = { key, ns.UI.KeyLabel(key, names) }
    end
    if here and here ~= "open" then
        Add(here)
        out[2] = rest[1]
        rest = {}
    end
    for key in pairs(db and db.plans or {}) do Add(key) end
    for key in pairs(db and db.rules or {}) do Add(key) end
    for id in pairs(names or {}) do
        if type(id) == "number" then Add("i:" .. id) end
    end
    table.sort(rest, function(a, b) return a[2] < b[2] end)
    for _, choice in ipairs(rest) do out[#out + 1] = choice end
    return out
end

function UIRoles.PlanNote(key, own, label)
    if key == nil or key == "default" then
        return "The default plan: every instance without a plan of its own follows it."
    end
    if own then return label .. " has a plan of its own. Use default puts it back on the default." end
    return label .. " follows the default. Change anything here and it gets a plan of its own."
end

function UIRoles.JobChoices()
    local out = {}
    for _, intent in ipairs(CC.ORDER) do
        local def = CC.INTENTS[intent]
        if intent ~= "IGNORE" and not def.hidden then out[#out + 1] = { intent, def.label } end
    end
    return out
end

-- Ordinals 1..n for one job's seats, in their current order. Mutates plan.
local function Renumber(plan, intent)
    local icons = {}
    for icon, seat in pairs(plan) do
        if type(seat) == "table" and seat.intent == intent then icons[#icons + 1] = icon end
    end
    table.sort(icons, function(a, b)
        local sa, sb = plan[a], plan[b]
        if (sa.ordinal or 0) ~= (sb.ordinal or 0) then return (sa.ordinal or 0) < (sb.ordinal or 0) end
        return a > b
    end)
    for i, icon in ipairs(icons) do plan[icon].ordinal = i end
end

-- Returns true, or false and why. A seat moving job goes last in the new job's order; both
-- jobs are renumbered so no two seats share a number.
function UIRoles.SetJob(plan, icon, intent)
    if not CC.IsKnown(intent) or intent == "IGNORE" then return false, "a seat cannot carry that job" end
    local seat = plan[icon]
    if type(seat) ~= "table" then
        seat = {}
        plan[icon] = seat
    end
    if seat.intent == intent then return true end
    local old = seat.intent
    seat.intent, seat.ordinal = intent, 99
    if old then Renumber(plan, old) end
    Renumber(plan, intent)
    return true
end

-- dir -1 moves the seat earlier in its job (Kill 2 becomes Kill 1), +1 later. Returns
-- whether anything moved: nothing does at either end.
function UIRoles.MoveSeat(plan, icon, dir)
    local seat = plan[icon]
    if type(seat) ~= "table" or not seat.intent then return false end
    Renumber(plan, seat.intent)
    local want = seat.ordinal + dir
    for other, s in pairs(plan) do
        if other ~= icon and type(s) == "table" and s.intent == seat.intent and s.ordinal == want then
            s.ordinal, seat.ordinal = seat.ordinal, want
            return true
        end
    end
    return false
end

-- Returns the pin now set (nil for none). A seat that did not exist becomes Kill, last.
function UIRoles.SetPin(plan, icon, text)
    if type(plan[icon]) ~= "table" then UIRoles.SetJob(plan, icon, "KILL") end
    local pin = Util.Trim(tostring(text or ""))
    plan[icon].pin = pin ~= "" and pin or nil
    return plan[icon].pin
end

function UIRoles.SetReserved(plan, icon, on)
    if type(plan[icon]) ~= "table" then UIRoles.SetJob(plan, icon, "KILL") end
    plan[icon].reserved = on and true or nil
end

local PIN_WORDS = {
    absent = "is not in the group", offline = "is offline", ["wrong class"] = "cannot do this job",
    taken = "already holds an earlier seat of this job",
}

-- record: one Seats.Resolve record, or nil for a seat with no job. Returns text, role.
function UIRoles.OwnerText(record)
    if not record then return "no job", "textDim" end
    if record.owner == true then return "anyone: no class needed", "good" end
    local pinNote = record.pin and PIN_WORDS[record.pinState]
    if type(record.owner) == "string" then
        if record.pinState == "held" then return record.owner .. " (pinned)", "good" end
        if pinNote then return record.owner .. "; " .. record.pin .. " " .. pinNote, "warn" end
        return record.owner, "good"
    end
    if pinNote then return "nobody: " .. record.pin .. " " .. pinNote, "bad" end
    return "nobody in the group can do this", "bad"
end

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------

local page
local controls = {}
local rows = {}

local function Key()
    local key = ns.cdb and ns.cdb.planEditing
    if type(key) ~= "string" or key == "" then return "default" end
    return key
end

local function Label(key)
    return ns.UI.KeyLabel(key, ns.Instances and ns.Instances.list)
end

-- The plan to change: the first edit of an instance that follows the default copies it.
local function Editable()
    return Seats.Detach(ns.db, Key())
end

local function Changed()
    ns.UI.Changed("plan", Key())
    UIRoles.Refresh()
end

-- Applies fn(plan) to the editable plan. If the result does not validate, the plan is put
-- back as it was and the reason printed.
local function Edit(fn)
    if not ns.db then return end
    local plan = Editable()
    local before = Util.DeepCopy(plan)
    fn(plan)
    local ok, why = Seats.Validate(plan)
    if not ok then
        for k in pairs(plan) do plan[k] = nil end
        for k, v in pairs(before) do plan[k] = v end
        ns.Print("|cffff5555not changed:|r " .. tostring(why) .. ".")
    end
    Changed()
end

local function Tip(frame, title, ...)
    local lines = { ... }
    W.Tooltip(frame, function(tip)
        tip:AddLine(title)
        for _, line in ipairs(lines) do tip:AddLine(line, 1, 1, 1, true) end
    end)
end

local function BuildPicker()
    local label = W.Label(page, "Plan for:")
    label:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -4)
    controls.picker = W.Choice(page, 240, 22, {
        choices = {},
        onChange = function(value)
            ns.cdb.planEditing = value
            UIRoles.Refresh()
        end,
    })
    controls.picker:SetPoint("LEFT", label, "RIGHT", 8, 0)
    Tip(controls.picker, "Plan for", "Which seat plan this tab shows and edits.",
        "Looking at an instance changes nothing; its first edit gives it a plan of its own.")

    controls.reattach = W.Button(page, "Use default", 100, 22, {
        onClick = function()
            local key = Key()
            W.Confirm("Put " .. Label(key) .. " back on the default plan? Its own seats are dropped.", function()
                Seats.Reattach(ns.db, key)
                Changed()
            end)
        end,
    })
    controls.reattach:SetPoint("LEFT", controls.picker, "RIGHT", 8, 0)
    Tip(controls.reattach, "Use default", "Drops this instance's own plan, so it follows the default again.")

    controls.here = W.Button(page, "Where I am", 100, 22, {
        onClick = function()
            local key = ns.UI.Here()
            ns.cdb.planEditing = key == "open" and "default" or key
            UIRoles.Refresh()
        end,
    })
    controls.here:SetPoint("LEFT", controls.reattach, "RIGHT", 6, 0)
    Tip(controls.here, "Where I am", "Shows the plan of the instance you are in (the default in the open world).")

    controls.note = W.Label(page, "", { color = "textDim" })
    controls.note:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -TOP_NOTE)
    controls.note:SetPoint("RIGHT", page, "RIGHT", 0, 0)
    controls.note:SetWordWrap(false)
    if controls.note.SetMaxLines then controls.note:SetMaxLines(1) end
end

local function BuildHeader()
    local header = CreateFrame("Frame", nil, page)
    header:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -TOP_HEADER)
    header:SetPoint("RIGHT", page, "RIGHT", 0, 0)
    header:SetHeight(20)
    local cols = {
        { "Seat", X_SEAT, "The icon and the seat it is: Kill 1 is the first kill target." },
        { "Job", X_JOB, "What the mob under this icon is for. Rules name jobs, never icons." },
        { "Order", X_ORDER, "Kill 1 before Kill 2: moves this seat within its job." },
        { "Pinned player", X_PIN, "Gives this seat to one player when present. Empty: the next capable player by name." },
        { "Kept", X_RES - 8, "Never lent to an extra kill target, even when nobody holds it." },
        { "Owner right now", X_OWNER, "Who holds the seat with the group as it is, read out of combat." },
    }
    for _, col in ipairs(cols) do
        local cell = CreateFrame("Frame", nil, header)
        cell:SetPoint("TOPLEFT", header, "TOPLEFT", col[2], 0)
        cell:SetSize(90, 20)
        local l = W.Label(cell, col[1], { font = "small", color = "textDim" })
        l:SetPoint("LEFT", cell, "LEFT", 0, 0)
        cell:EnableMouse(true)
        Tip(cell, col[1], col[3])
    end
end

local function BuildRow(i)
    local row = CreateFrame("Frame", nil, page)
    row:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(TOP_ROWS + (i - 1) * ROW_H))
    row:SetPoint("RIGHT", page, "RIGHT", 0, 0)
    row:SetHeight(ROW_H)
    row.icon = W.RaidIcon(row, UIRoles.ROW_ORDER[i], 18)
    row.icon:SetPoint("LEFT", row, "LEFT", X_ICON, 0)

    row.seat = W.Label(row, "")
    row.seat:SetPoint("LEFT", row, "LEFT", X_SEAT, 0)
    row.seat:SetWidth(W_SEAT)
    row.seat:SetWordWrap(false)

    row.job = W.Choice(row, W_JOB, 20, {
        choices = UIRoles.JobChoices(),
        onChange = function(value)
            Edit(function(plan) UIRoles.SetJob(plan, row.iconIndex, value) end)
        end,
    })
    row.job:SetPoint("LEFT", row, "LEFT", X_JOB, 0)

    row.up = W.Button(row, "^", 20, 20, {
        onClick = function() Edit(function(plan) UIRoles.MoveSeat(plan, row.iconIndex, -1) end) end,
    })
    row.up:SetPoint("LEFT", row, "LEFT", X_ORDER, 0)
    Tip(row.up, "Earlier", "Kill 2 becomes Kill 1, and Kill 1 becomes Kill 2.")
    row.down = W.Button(row, "v", 20, 20, {
        onClick = function() Edit(function(plan) UIRoles.MoveSeat(plan, row.iconIndex, 1) end) end,
    })
    row.down:SetPoint("LEFT", row.up, "RIGHT", 4, 0)
    Tip(row.down, "Later", "Kill 1 becomes Kill 2, and Kill 2 becomes Kill 1.")

    -- The pin is saved on Enter and when focus leaves, never by a repaint: Refresh does not
    -- touch a box that has focus, so a roster change while typing cannot blank the name.
    local function SavePin(box)
        local text = box:GetText()
        local plan = Seats.PlanFor(ns.db, Key())
        local seat = plan[row.iconIndex]
        local was = seat and seat.pin or ""
        if (Util.Trim(text or "")) == was then return end
        Edit(function(p) UIRoles.SetPin(p, row.iconIndex, text) end)
    end
    row.pin = W.EditBox(row, W_PIN, 20, {
        maxBytes = 48,
        placeholder = "anyone able",
        onEnter = function(_, box) box:ClearFocus() end,
        onFocusLost = SavePin,
    })
    row.pin:SetPoint("LEFT", row, "LEFT", X_PIN, 0)

    row.reserved = W.CheckBox(row, {
        onClick = function(on) Edit(function(plan) UIRoles.SetReserved(plan, row.iconIndex, on) end) end,
    })
    row.reserved:SetPoint("LEFT", row, "LEFT", X_RES, 0)
    Tip(row.reserved, "Kept", "A spare crowd control icon may be lent to an extra kill target.",
        "Ticked, this icon never is: a do-not-touch icon stays one.")

    row.owner = W.Label(row, "")
    row.owner:SetPoint("LEFT", row, "LEFT", X_OWNER, 0)
    row.owner:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.owner:SetWordWrap(false)
    if row.owner.SetMaxLines then row.owner:SetMaxLines(1) end

    row.iconIndex = UIRoles.ROW_ORDER[i]
    rows[i] = row
end

function UIRoles.Refresh()
    if not page or not ns.db then return end
    local key = Key()
    local here = ns.UI.Here()
    controls.picker.icChoices = UIRoles.PlanChoices(ns.db, here, ns.Instances and ns.Instances.list)
    controls.picker:SetValue(key)
    local plan, own = Seats.PlanFor(ns.db, key)
    controls.reattach:SetShown(own)
    controls.note:SetText(UIRoles.PlanNote(key, own, Label(key)))

    local roster = ns.UI.Roster()
    local resolved = Seats.Resolve(plan, roster and roster.members or {})
    for _, row in ipairs(rows) do
        local seat = plan[row.iconIndex]
        local record = resolved.byIcon[row.iconIndex]
        row.seat:SetText(seat and Seats.Label(seat) or "no job")
        row.job:SetValue(seat and seat.intent or nil)
        row.up:SetEnabled(seat ~= nil)
        row.down:SetEnabled(seat ~= nil)
        if not row.pin:HasFocus() then row.pin:SetText(seat and seat.pin or "") end
        row.reserved:SetChecked(seat ~= nil and seat.reserved == true)
        local text, role = UIRoles.OwnerText(record)
        row.owner:SetText(text)
        row.owner:SetRole(role)
    end
end

local function DropFocus()
    for _, row in ipairs(rows) do row.pin:ClearFocus() end
end

function UIRoles.Build(parent)
    if page then return page end
    page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints(parent)
    BuildPicker()
    BuildHeader()
    for i = 1, #UIRoles.ROW_ORDER do BuildRow(i) end

    local foot = W.Label(page, "Rules name a job, never an icon: a mob ruled Sheep takes the first free Sheep seat.\n"
        .. "Owners are worked out the same way on every client: pins first, then by name.", { color = "textDim" })
    foot:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -TOP_FOOT)

    ns.Events.On("PLAYER_REGEN_DISABLED", "ui_roles", DropFocus)
    page:SetScript("OnShow", UIRoles.Refresh)
    page:SetScript("OnHide", DropFocus)
    UIRoles.Refresh()
    return page
end

ns.OnReady("ui_roles", function()
    if IC_HEADLESS then return end
    ns.UI.AddTab("roles", "Roles", UIRoles.Build, { refresh = UIRoles.Refresh })
end)
