local addonName, ns = ...

--[[
MarkButtons: the secure Mark pack, Clear all, Re-mark and Clear target buttons, what they
hold, and the press record (spec 5.1, 5.3, 5.5, 5.8).

Owned by lane B (marking runtime). Two pure halves with cases in Tests_Marking.lua, then
a frame half that calls the client only from the ready hook and returns early on
IC_HEADLESS.

Pure: the plan turned into macro text
    MarkButtons.NAMES                         the buttons' global names (Bindings.xml uses them)
    MarkButtons.Entries(steps, words)         one { "/targetexact Name", "/tm ~8" } pair per step
    MarkButtons.PackText(steps, words, limit) Mark pack's text, the steps kept, the steps dropped
    MarkButtons.RemarkText(steps, words, limit, clearName)   "/click MFDClear" then the pack
    MarkButtons.ClearTargetText(words)        "/tm 0": the fallback clear, target only
    MarkButtons.Plan(input)                   everything a rebuild writes, from the rules
    MarkButtons.KeySet(keys)                  saved keys to the override set Secure.Bind takes
    MarkButtons.ParseKeys(rest, keys)         what /mfd keys asks for
    MarkButtons.KeyText(key)                  "CTRL-1" as "Ctrl-1"

Pure: the press record (ns.Ledger). In combat GetRaidTargetIndex on a marked mob is
secret and RAID_TARGET_UPDATE carries no arguments, so what MFD shows as placed in combat
is what it pressed, never what it read.
    Ledger.New()                              an empty record
    Ledger.Pressed(led, kind, steps, now)     kind "pack" | "remark" | "clear" | "cleartarget"
    Ledger.Seen(led, now)                     a RAID_TARGET_UPDATE: counted, nothing more
    Ledger.Settle(led, reads, now)            out of combat: icons read on mobs replace planned
    Ledger.View(led)                          { [icon] = { name, guid, state, at } }
    Ledger.RowState(view, step)               "placed" | "planned" | "other" | nil, for a panel row
    Ledger.Held(led)                          { ["n:<name>"] = icon } for Allocator, placed only
    Ledger.Describe(facts, steps, view, marked)  the Mark guide line for one unit
    Ledger.Summary(led, now)                  "pressed 12s ago, 3 marks landed"

Frame half (for other lanes):
    MarkButtons.Rebuild(why)      works the plan out again and writes it (held in combat)
    MarkButtons.Provider          what ns.UI.SetMarking gets: BuildSlot, Steps, WhyState
    MarkButtons.Button(kind)      the secure button for "pack" | "clear" | "remark" | "cleartarget"
    MarkButtons.Record()          the live press record
]]

ns.MarkButtons = ns.MarkButtons or {}
local MB = ns.MarkButtons
ns.Ledger = ns.Ledger or {}
local Ledger = ns.Ledger

local Secure = LibStub("LibICSecure-1.0")
local Restrict = LibStub("LibICRestrict-1.0")
local Seats, Allocator, MarkPlan, Rules = ns.Seats, ns.Allocator, ns.MarkPlan, ns.Rules

-- The buttons' global names. Bindings.xml and /click find a button by its name, so these
-- never change once shipped.
MB.NAMES = {
    pack = "MFDMarkPack",
    clear = "MFDClear",
    remark = "MFDRemark",
    cleartarget = "MFDClearTarget",
}
MB.ORDER = { "pack", "clear", "remark", "cleartarget" }

-- The keys /mfd keys on binds: the keys the probe's control test pressed (f101e96).
MB.DEFAULT_KEYS = { pack = "CTRL-1", clear = "CTRL-2", remark = "CTRL-3", cleartarget = "CTRL-4" }

MB.LABELS = {
    pack = "Mark pack",
    clear = "Clear all",
    remark = "Re-mark",
    cleartarget = "Clear target",
}

local ENGLISH = { mark = "/tm", exact = "/targetexact", click = "/click" }

local function WordsOr(words)
    words = words or {}
    return {
        mark = words.mark or ENGLISH.mark,
        exact = words.exact or ENGLISH.exact,
        click = words.click or ENGLISH.click,
    }
end

--------------------------------------------------------------------------------
-- Pure: the plan turned into macro text
--------------------------------------------------------------------------------

-- steps: MarkPlan.Steps. words: Secure.Words() (the client's slash words; the probe found a
-- literal /tm may not work where the client renames it). Returns one line pair per step.
function MB.Entries(steps, words)
    words = WordsOr(words)
    local entries = {}
    for i, step in ipairs(steps or {}) do
        entries[i] = { words.exact .. " " .. step.name, words.mark .. " ~" .. step.icon }
    end
    return entries
end

-- Splits steps by the indexes Secure.Fit dropped (offset: entries before the first step).
local function Split(steps, dropped, offset)
    local out = {}
    for _, i in ipairs(dropped) do out[i - offset] = true end
    local kept, lost = {}, {}
    for i, step in ipairs(steps) do
        if out[i] then lost[#lost + 1] = step else kept[#kept + 1] = step end
    end
    return kept, lost
end

--[[
steps: from MarkPlan.Steps, Skull first. limit: bytes (Secure.MACRO_LIMIT when nil).
Returns text, kept, dropped: the macro, the steps it holds and the steps cut off. Cut on a
whole pair, and the first pair that does not fit ends the text, so a lower seat never takes
a higher one's place. Ends with /targetlasttarget. An empty plan is empty text.
]]
function MB.PackText(steps, words, limit)
    steps = steps or {}
    if #steps == 0 then return "", {}, {} end
    local text, kept, dropped = Secure.Fit(MB.Entries(steps, words), limit, MarkPlan.RESTORE)
    if kept == 0 then return "", {}, steps end
    local keptSteps, lost = Split(steps, dropped, 0)
    return text, keptSteps, lost
end

-- One press that clears every icon (by clicking the Clear all button) then marks the pack.
-- Unproven twice over: clear-all (P6) and /click in macrotext (P17). Returns text, kept,
-- dropped as PackText; with no steps it is the click alone.
function MB.RemarkText(steps, words, limit, clearName)
    words = WordsOr(words)
    steps = steps or {}
    local click = words.click .. " " .. tostring(clearName or MB.NAMES.clear)
    if #steps == 0 then return click, {}, {} end
    local entries = { click }
    for _, pair in ipairs(MB.Entries(steps, words)) do entries[#entries + 1] = pair end
    local text, kept, dropped = Secure.Fit(entries, limit, MarkPlan.RESTORE)
    if kept <= 1 then return click, {}, steps end
    local keptSteps, lost = Split(steps, dropped, 1)
    return text, keptSteps, lost
end

-- The fallback clear (spec 5.5): the target's icon only. Proven: it is plain /tm.
function MB.ClearTargetText(words)
    return WordsOr(words).mark .. " 0"
end

--[[
input = {
    enabled   false when the addon is off: every macro is empty, so a press does nothing
    rules     the merged rule set for here (Comms.ActiveRules)
    plan      the seat plan for here (Seats.PlanFor)
    members   a roster's members (LibICGroup snapshot), for seat owners
    held      { [ruleKey] = icon } from an out-of-combat Settle (Ledger.Held), or nil
    words     Secure.Words()
    limit     bytes per macro (Secure.MACRO_LIMIT when nil)
}
Blind (spec 5.2): each rule stands for one mob, since one /targetexact marks one mob per
press. Returns {
    steps       the steps Mark pack holds, Skull first
    dropped     steps that did not fit
    nameless    rule keys with no name a macro can target
    unmet       crowd control rules that got no seat (Allocator)
    pack, remark, cleartarget   the three macro texts
    fingerprint MarkPlan.Fingerprint(steps)
}
]]
function MB.Plan(input)
    input = input or {}
    local out = { steps = {}, dropped = {}, nameless = {}, unmet = {} }
    if input.enabled == false then
        out.pack, out.remark, out.cleartarget = "", "", ""
        out.fingerprint = "off"
        return out
    end
    local seats = Seats.Resolve(input.plan or {}, input.members or {})
    local alloc = Allocator.Blind(input.rules or {}, seats, { lend = false, held = input.held })
    local steps, nameless = MarkPlan.Steps(alloc)
    for _, key in ipairs(alloc.skipped or {}) do nameless[#nameless + 1] = key end
    local text, kept, dropped = MB.PackText(steps, input.words, input.limit)
    out.steps, out.dropped, out.nameless, out.unmet = kept, dropped, nameless, alloc.unmet or {}
    out.pack = text
    out.remark = MB.RemarkText(kept, input.words, input.limit)
    out.cleartarget = MB.ClearTargetText(input.words)
    out.fingerprint = MarkPlan.Fingerprint(kept)
    return out
end

--------------------------------------------------------------------------------
-- Pure: keys
--------------------------------------------------------------------------------

local KEY_PATTERN = "^[%u%d%-]+$"

-- "CTRL-SHIFT-1" as "Ctrl-Shift-1", for a label.
function MB.KeyText(key)
    if type(key) ~= "string" or key == "" then return nil end
    return (key:lower():gsub("(%a)(%w*)", function(a, b) return a:upper() .. b end))
end

-- keys: { [kind] = "CTRL-1" } (saved). Returns the set Secure.Bind takes: { [key] = name }.
-- A key named twice goes to the first kind in button order.
function MB.KeySet(keys)
    local set = {}
    for _, kind in ipairs(MB.ORDER) do
        local key = type(keys) == "table" and keys[kind] or nil
        if type(key) == "string" and key ~= "" and set[key] == nil then set[key] = MB.NAMES[kind] end
    end
    return set
end

local KIND_WORDS = {
    pack = "pack", mark = "pack", markpack = "pack",
    clear = "clear", clearall = "clear",
    remark = "remark",
    cleartarget = "cleartarget", target = "cleartarget",
}

--[[
rest: what followed "/mfd keys". keys: the saved set or nil. Returns a plan:
    { action = "show" }
    { action = "set", keys = {...}, text }      the whole new set (nil keys = none)
    { action = "refuse", text }
"on" binds the defaults, "off" drops them, "<button> <KEY>" sets one, "<button> none" drops one.
]]
function MB.ParseKeys(rest, keys)
    rest = (rest or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if rest == "" then return { action = "show" } end
    local lower = rest:lower()
    if lower == "on" then
        local copy = {}
        for kind, key in pairs(MB.DEFAULT_KEYS) do copy[kind] = key end
        return { action = "set", keys = copy, text = "keys bound: Ctrl-1 Mark pack, Ctrl-2 Clear all, Ctrl-3 Re-mark, "
            .. "Ctrl-4 Clear target." }
    end
    if lower == "off" then
        return { action = "set", keys = nil, text = "the Marked For Death keys are off. Keys you set in Key Bindings stay." }
    end
    local word, key = rest:match("^(%S+)%s+(%S+)$")
    local kind = word and KIND_WORDS[word:lower()]
    if not kind then
        return { action = "refuse", text = "say on, off, or a button and a key: /mfd keys pack CTRL-1" }
    end
    local copy = {}
    for k, v in pairs(type(keys) == "table" and keys or {}) do copy[k] = v end
    if key:lower() == "none" then
        copy[kind] = nil
        return { action = "set", keys = next(copy) and copy or nil, text = MB.LABELS[kind] .. " has no key of ours now." }
    end
    key = key:upper()
    if not key:match(KEY_PATTERN) or key:match("%-$") then
        return { action = "refuse", text = "a key looks like CTRL-1, SHIFT-F or ALT-CTRL-Q" }
    end
    for other, bound in pairs(copy) do
        if bound == key and other ~= kind then copy[other] = nil end
    end
    copy[kind] = key
    return { action = "set", keys = copy, text = MB.LABELS[kind] .. " is on " .. MB.KeyText(key) .. "." }
end

--------------------------------------------------------------------------------
-- Pure: the press record
--------------------------------------------------------------------------------

function Ledger.New()
    return { entries = {}, seen = 0, press = nil, settledAt = nil }
end

local function SameName(a, b)
    return type(a) == "string" and type(b) == "string" and a:lower() == b:lower()
end

--[[
A press of a button. kind: "pack" records each step as planned (the macro marks only the
names in range, and a ~ skips a mob already marked, so nothing is "placed" until an out of
combat read says so); an icon already confirmed on the same mob stays placed. "clear"
empties the record; "remark" is clear then pack; "cleartarget" cannot know which icon
went, so it only notes the press. Seen restarts at 0 on every press. Returns led.
]]
function Ledger.Pressed(led, kind, steps, now)
    if kind == "clear" or kind == "remark" then led.entries = {} end
    if kind == "pack" or kind == "remark" then
        for _, step in ipairs(steps or {}) do
            local icon = step.icon
            local old = led.entries[icon]
            if not (old and old.state == "placed" and SameName(old.name, step.name)) then
                led.entries[icon] = { name = step.name, guid = step.guid, state = "planned", at = now }
            end
        end
    end
    led.seen = 0
    led.press = { kind = kind, at = now, count = #(steps or {}) }
    return led
end

-- A RAID_TARGET_UPDATE: a mark changed somewhere. It says nothing of which, so it is a
-- count since the last press and nothing else.
function Ledger.Seen(led, now)
    led.seen = (led.seen or 0) + 1
    led.seenAt = now
    return led
end

-- A read is usable only if its icon is a plain whole number 1 to 8. IsSecret is asked
-- first: a secret value must never reach a type test's neighbour, a comparison.
local function PlainIcon(v)
    if Restrict.IsSecret(v) then return nil end
    if type(v) ~= "number" then return nil end
    if v < 1 or v > 8 or v % 1 ~= 0 then return nil end
    return v
end

local function PlainText(v)
    if Restrict.IsSecret(v) then return nil end
    if type(v) ~= "string" or v == "" then return nil end
    return v
end

--[[
reads: { { guid, name, icon }, ... } from an out-of-combat read of every unit in reach.
A row whose icon is secret or not an icon is dropped whole, and a secret name or GUID is
dropped. Each icon read replaces the record's entry for that icon as "placed"; a planned
entry no read confirms stays planned (the mob may simply be out of reach). The same mob
read under a new icon loses its old entry. Returns led.
]]
function Ledger.Settle(led, reads, now)
    for _, row in ipairs(reads or {}) do
        local icon = type(row) == "table" and PlainIcon(row.icon) or nil
        if icon then
            local guid, name = PlainText(row.guid), PlainText(row.name)
            if guid or name then
                for other, entry in pairs(led.entries) do
                    if other ~= icon and ((guid and entry.guid == guid)
                            or (not guid and not entry.guid and SameName(entry.name, name))) then
                        led.entries[other] = nil
                    end
                end
                led.entries[icon] = { name = name, guid = guid, state = "placed", at = now }
            end
        end
    end
    led.settledAt = now
    return led
end

-- { [icon] = { name, guid, state, at } }, a copy.
function Ledger.View(led)
    local view = {}
    for icon, entry in pairs(led and led.entries or {}) do
        view[icon] = { name = entry.name, guid = entry.guid, state = entry.state, at = entry.at }
    end
    return view
end

-- One assignment row's state: the record agrees ("placed" or "planned"), the icon is on
-- another mob ("other"), or the record says nothing (nil).
function Ledger.RowState(view, step)
    local entry = view and step and view[step.icon]
    if not entry then return nil end
    local same = (step.guid and entry.guid == step.guid) or SameName(entry.name, step.name)
    if not same then return "other" end
    return entry.state
end

-- Placed icons as Allocator's held set, keyed as a blind candidate is (the rule key of the
-- name). Planned entries never count: Allocator's held means icons on mobs.
function Ledger.Held(led)
    local held = {}
    for icon, entry in pairs(led and led.entries or {}) do
        if entry.state == "placed" and type(entry.name) == "string" then
            held[Rules.Key({ name = entry.name })] = icon
        end
    end
    return held
end

--[[
The Mark guide line for one unit. facts: { guid, name } readable now, or nil. steps: what
Mark pack holds. view: Ledger.View. marked: true (it carries a mark; in combat the icon is
unknown), false, or nil (not asked). icon: a plain icon read out of combat, or nil.
Returns text, role ("good" | "warn" | "textDim").
]]
function Ledger.Describe(facts, steps, view, marked, icon)
    if type(facts) ~= "table" or (facts.guid == nil and facts.name == nil) then
        return "Target a mob to see which icon the plan gives it.", "textDim"
    end
    local who = facts.name or "this mob"
    local iconName = function(i) return Seats.ICON_NAMES[i] or ("icon " .. tostring(i)) end
    if marked and icon then
        local wanted = MarkPlan.IconFor(facts, steps or {}, {})
        if wanted == nil then return who .. " carries " .. iconName(icon) .. ": not one the plan gives.", "warn" end
        if wanted == icon then return who .. " carries " .. iconName(icon) .. ", as planned.", "good" end
        return who .. " carries " .. iconName(icon) .. "; the plan gives it " .. iconName(wanted) .. ".", "warn"
    end
    if marked then
        -- In combat: which icon is unknown. Say what the record planned there, as planned.
        for i, entry in pairs(view or {}) do
            if (facts.guid and entry.guid == facts.guid) or SameName(entry.name, facts.name) then
                return who .. " is marked: " .. iconName(i) .. " planned (the icon is hidden in combat).", "good"
            end
        end
        return who .. " is marked by someone, not by a Mark pack press.", "warn"
    end
    local used = {}
    for i, entry in pairs(view or {}) do
        if not ((facts.guid and entry.guid == facts.guid) or SameName(entry.name, facts.name)) then used[i] = true end
    end
    local wanted, why = MarkPlan.IconFor(facts, steps or {}, used)
    if not wanted then return "No icon for " .. who .. ": " .. tostring(why) .. ".", "textDim" end
    return iconName(wanted) .. " is planned for " .. who .. ": press Mark pack.", "good"
end

local function Age(seconds)
    if ns.UI and ns.UI.Age then return ns.UI.Age(seconds) end
    return tostring(math.floor(seconds)) .. "s"
end

-- "Mark pack pressed 12s ago, 3 marks seen" (or nil before any press).
function Ledger.Summary(led, now)
    local press = led and led.press
    if not press then return nil end
    local label = MB.LABELS[press.kind] or press.kind
    local seen = led.seen or 0
    local text = label .. " pressed " .. Age(math.max(0, (now or press.at) - press.at)) .. " ago"
    if seen == 1 then return text .. ", 1 mark change seen" end
    return text .. ", " .. seen .. " mark changes seen"
end

--------------------------------------------------------------------------------
-- Frame half: the buttons, what they hold, and the record of presses
--------------------------------------------------------------------------------

-- The Key Bindings screen (AddOns) lists Bindings.xml's entries under this header. A
-- binding named "CLICK <button>:LeftButton" presses the secure button by its name.
BINDING_HEADER_MARKEDFORDEATH = "Marked For Death"

local buttons = {}      -- kind -> secure button
local kindOf = {}       -- button -> kind
local wanted = {}       -- kind -> { text, steps }: the newest text asked for
local written = {}      -- kind -> steps the button runs now (set when the macro is applied)
local plan              -- MB.Plan's answer, the newest
local planKey           -- the instance key it was worked out for
local led = Ledger.New()
local built = false
local listeners = {}    -- key -> fn(): told after a rebuild, a write, a press or a settle
local keyOwner          -- the frame the override keys belong to
local pendingParent     -- where the buttons go, kept for a build that had to wait
local rebuildQueued = false

local function Tell()
    for _, fn in pairs(listeners) do pcall(fn) end
end

-- fn() after anything here changes. UI_Bar and the Mark guide repaint from it.
function MB.OnUpdate(key, fn)
    listeners[key] = fn
end

function MB.Button(kind) return buttons[kind] end
function MB.Built() return built end
function MB.Record() return led end
function MB.Current() return plan, planKey end
function MB.Written(kind) return written[kind or "pack"] end

-- Whether the button's newest text waits on combat to end (the bar's stale tint).
function MB.Stale(kind)
    local b = buttons[kind or "pack"]
    return b ~= nil and Secure.Pending(b)
end

local function Saved()
    local cdb = ns.cdb
    if not cdb then return {} end
    if type(cdb.bar) ~= "table" then cdb.bar = {} end
    return cdb.bar
end

-- The keys pressing a button: ours (override keys, saved per character) first, then the
-- player's own from Key Bindings. GetBindingKey is guarded: not yet confirmed here.
function MB.KeysFor(kind)
    local keys = {}
    local mine = Saved().keys
    if type(mine) == "table" and type(mine[kind]) == "string" then keys[#keys + 1] = mine[kind] end
    if type(GetBindingKey) == "function" then
        local ok, a, b = pcall(GetBindingKey, Secure.ClickBinding(MB.NAMES[kind]))
        if ok then
            for _, key in ipairs({ a or false, b or false }) do
                if key and not Restrict.IsSecret(key) and type(key) == "string" and key ~= keys[1] then
                    keys[#keys + 1] = key
                end
            end
        end
    end
    return keys
end

function MB.KeyLabel(kind)
    local keys = MB.KeysFor(kind)
    if #keys == 0 then return nil end
    return MB.KeyText(keys[1])
end

local function Here()
    if ns.UI and ns.UI.Here then return (ns.UI.Here()) end
    return "open"
end

local function Input()
    local key = Here()
    local rules = {}
    if ns.Comms and ns.Comms.ActiveRules then
        local ok, set = pcall(ns.Comms.ActiveRules, key)
        if ok and type(set) == "table" then rules = set end
    elseif ns.db and type(ns.db.rules) == "table" and type(ns.db.rules[key]) == "table" then
        rules = ns.db.rules[key]
    end
    local roster = ns.UI and ns.UI.Roster and ns.UI.Roster() or nil
    return key, {
        enabled = not (ns.UI and ns.UI.IsEnabled) or ns.UI.IsEnabled(),
        rules = rules,
        plan = (Seats.PlanFor(ns.db, key)),
        members = roster and roster.members or {},
        held = Ledger.Held(led),
        words = Secure.Words(),
    }
end

-- The Raid Lead sends what Mark pack holds, so every panel in the raid agrees.
local function Publish()
    if not (ns.Comms and ns.Comms.PublishPlan) or not written.pack or not planKey then return end
    pcall(ns.Comms.PublishPlan, planKey, written.pack)
end

-- A button's macro has been written, now or when combat ended. What it runs is what was
-- asked for with that exact text.
local function Applied(button, text)
    local kind = kindOf[button]
    if not kind then return end
    local want = wanted[kind]
    if want and want.text == text then written[kind] = want.steps end
    if kind == "pack" then Publish() end
    Tell()
end

local function Write(kind, text, steps)
    wanted[kind] = { text = text, steps = steps }
    local b = buttons[kind]
    if not b then return end
    if Secure.Macro(b) == text and not Secure.Pending(b) then
        written[kind] = steps
        return
    end
    Secure.SetMacro(b, text)
end

--[[
Works the plan out from the rules, seats and roster here and writes it into the buttons.
Out of combat the write is made now; in combat LibICSecure holds it (the bar shows stale)
and makes it when combat ends. The roster is read again only out of combat. why: a word
for the debug line.
]]
function MB.Rebuild(why)
    if IC_HEADLESS or not ns.db then return end
    if ns.UI and ns.UI.ReadRoster and not Restrict.InCombat() then ns.UI.ReadRoster() end
    local key, input = Input()
    plan, planKey = MB.Plan(input), key
    Write("pack", plan.pack, plan.steps)
    Write("remark", plan.remark, plan.steps)
    Write("cleartarget", plan.cleartarget, {})
    ns.Debug("Mark pack rebuilt (" .. tostring(why) .. "): " .. #plan.steps .. " names, "
        .. #plan.dropped .. " dropped")
    Tell()
end

-- A rebuild a moment from now, so a burst of roster or zone events makes one.
function MB.RebuildSoon(why)
    if rebuildQueued then return end
    local marking = ns.db and ns.db.settings and ns.db.settings.marking
    local delay = tonumber(marking and marking.rebuildDebounce) or 0.5
    if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then
        MB.Rebuild(why)
        return
    end
    rebuildQueued = true
    C_Timer.After(delay, function()
        rebuildQueued = false
        MB.Rebuild(why)
    end)
end

-- Out of combat: the icons on mobs in reach replace what the record planned.
function MB.Settle()
    if IC_HEADLESS or Restrict.InCombat() then return false end
    Ledger.Settle(led, ns.Sense.Reads(), time())
    Tell()
    return true
end

-- After a secure click has run. Not a secure handler, so it cannot change what the press
-- did; it only writes the record.
local function Pressed(kind)
    local steps = kind == "clear" and {} or (written[kind] or {})
    if (kind == "pack" or kind == "remark") and #steps == 0 then return end
    Ledger.Pressed(led, kind, steps, time())
    Tell()
end

-- Applies the saved override keys: "set", "held" (in combat), or nil before the bar exists.
function MB.ApplyKeys()
    if not keyOwner then return nil end
    return Secure.Bind(keyOwner, MB.KeySet(Saved().keys))
end

--[[
Makes the four secure buttons on `parent` (UI_Bar's bar) and binds the saved keys to
`owner`. Out of combat only: returns false and why in combat, and is tried again when
combat ends. A button the client refuses is reported and the others still build.
]]
function MB.Build(parent, owner)
    if built then return true end
    pendingParent, keyOwner = parent, owner or parent
    local locked, why = Secure.Locked()
    if locked then return false, why end
    local key, input = Input()
    plan, planKey = MB.Plan(input), key
    local texts = { pack = plan.pack, remark = plan.remark, cleartarget = plan.cleartarget }
    local stepsFor = { pack = plan.steps, remark = plan.steps, cleartarget = {} }
    local problems = {}
    for _, kind in ipairs(MB.ORDER) do
        local b, err
        if kind == "clear" then
            b, err = Secure.ClearAllButton(MB.NAMES.clear, { parent = parent })
        else
            wanted[kind] = { text = texts[kind], steps = stepsFor[kind] }
            b, err = Secure.MacroButton(MB.NAMES[kind], { parent = parent, text = texts[kind], onApplied = Applied })
        end
        if b then
            buttons[kind], kindOf[b] = b, kind
            if kind ~= "clear" then written[kind] = stepsFor[kind] end
            local ok = pcall(b.HookScript, b, "PostClick", function() Pressed(kind) end)
            if not ok then problems[#problems + 1] = MB.LABELS[kind] .. ": presses will not be recorded" end
        else
            problems[#problems + 1] = MB.LABELS[kind] .. ": " .. tostring(err)
        end
    end
    built = buttons.pack ~= nil
    for _, line in ipairs(problems) do ns.Print("|cffff5555" .. line .. "|r") end
    MB.ApplyKeys()
    if built then Publish() end
    Tell()
    if not built then return false, "Mark pack could not be made" end
    return true
end

-- The state DebugWhy.WhyNot needs that only this file knows.
function MB.WhyState()
    return {
        blind = ns.Sense.Blind(),
        stale = MB.Stale("pack"),
        built = built,
        dropped = plan and plan.dropped or {},
        nameless = plan and plan.nameless or {},
        unbound = #MB.KeysFor("pack") == 0,
    }
end

local function SourceText()
    if MB.Stale("pack") then
        return "What Mark pack holds. The plan changed in combat: the new one is written when combat ends."
    end
    local key = MB.KeyLabel("pack")
    local text = "What Mark pack will place" .. (key and (" (" .. key .. ").") or ": bind a key, /mfd keys on.")
    if plan and #plan.dropped > 0 then text = text .. " " .. #plan.dropped .. " more did not fit." end
    return text
end

-- What ns.UI.SetMarking gets (UI_Main's marking slot); UI_Bar adds BuildSlot.
MB.Provider = {
    Steps = function()
        if not built then return nil end
        return written.pack or {}, planKey, SourceText()
    end,
    WhyState = MB.WhyState,
}

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

-- DebugWhy levels in chat, in the colours the Settings tab gives them.
local AMBER = "|cffffaa00"
local LEVEL_COLOR = { block = "|cffff5555", warn = AMBER, info = "|cff999999" }

local function PrintMark()
    if not built then ns.Print("Mark pack is not built yet: it is made at the first moment out of combat.") end
    local steps = written.pack or (plan and plan.steps) or {}
    if #steps == 0 then
        ns.Print("Mark pack holds nothing here: no named rules for " .. tostring(planKey or Here()) .. ".")
    else
        ns.Print("Mark pack holds, in press order:")
        for _, line in ipairs(ns.DebugWhy.PlanLines(steps)) do ns.Print("  " .. line) end
    end
    if MB.Stale("pack") then ns.Print(AMBER .. "stale:|r a newer plan is written when combat ends.") end
    for _, kind in ipairs(MB.ORDER) do
        local shown = {}
        for i, key in ipairs(MB.KeysFor(kind)) do shown[i] = MB.KeyText(key) end
        ns.Print(MB.LABELS[kind] .. ": " .. (#shown > 0 and table.concat(shown, ", ") or (AMBER .. "no key|r")))
    end
    local summary = Ledger.Summary(led, time())
    if summary then ns.Print(summary .. ".") end
    for _, r in ipairs(ns.DebugWhy.WhyNot(MB.WhyState())) do
        if r.code ~= "norules" then ns.Print((LEVEL_COLOR[r.level] or "") .. r.text .. ".|r") end
    end
end

ns.AddCommand("mark", "what Mark pack holds, its keys, and the last press", function()
    if not ns.db then
        ns.Print("the saved settings are not in hand yet.")
        return
    end
    MB.Settle()
    PrintMark()
end)

ns.AddCommand("keys", "keys for the marking buttons: on (Ctrl-1 to Ctrl-4), off, or a button and a key",
    function(rest)
        if not ns.db then
            ns.Print("the saved settings are not in hand yet.")
            return
        end
        local bar = Saved()
        local parsed = MB.ParseKeys(rest, bar.keys)
        if parsed.action == "refuse" then
            ns.Print("|cffff5555" .. parsed.text .. "|r")
            return
        end
        if parsed.action == "set" then
            bar.keys = parsed.keys
            local result = MB.ApplyKeys()
            ns.Print(parsed.text)
            if result == "held" then ns.Print("|cffffaa00in combat:|r the keys change when combat ends.") end
            if result == nil then ns.Print("the bar is not built yet; the keys apply when it is.") end
            Tell()
            return
        end
        for _, kind in ipairs(MB.ORDER) do
            ns.Print(MB.LABELS[kind] .. ": " .. (MB.KeyLabel(kind) or (AMBER .. "no key|r")))
        end
        ns.Print("/mfd keys on binds Ctrl-1 to Ctrl-4; Key Bindings > AddOns > Marked For Death sets your own.")
    end, "keys [on|off|<button> <key>]")

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local function OnRaidTarget()
    if Restrict.InCombat() then
        Ledger.Seen(led, time())
        Tell()
    else
        MB.Settle()
    end
end

ns.OnReady("markbuttons", function()
    if IC_HEADLESS then return end
    ns.Events.On("RAID_TARGET_UPDATE", "markbuttons", OnRaidTarget)
    for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
        ns.Events.On(event, "markbuttons", function() MB.RebuildSoon(event) end)
    end
    if ns.UI and ns.UI.OnChange then
        ns.UI.OnChange("markbuttons", function(kind)
            if kind == "plan" or kind == "rules" or kind == "enabled" then MB.Rebuild(kind) end
        end)
    end
    if ns.Comms and ns.Comms.Listen then
        ns.Comms.Listen("markbuttons", function(kind)
            if kind == "rules" or kind == "lead" then MB.RebuildSoon("comms " .. tostring(kind)) end
        end)
    end
    -- Combat over: build what could not be built, read the marks back, write the plan again.
    Restrict.OnChange(function(now, previous)
        if now.secure or now.combat then return end
        if not (previous and (previous.secure or previous.combat)) then return end
        if not built and pendingParent then MB.Build(pendingParent, keyOwner) end
        MB.Settle()
        MB.Rebuild("combat over")
    end)
end)
