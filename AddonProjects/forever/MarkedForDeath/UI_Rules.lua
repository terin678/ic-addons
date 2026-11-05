local addonName, ns = ...

--[[
UI_Rules: the Rules tab. The kill order and crowd control jobs for one instance: add a mob
by name, by npc id or from your target, paste a whole list, share and load files, and edit
many rules at once. Every rule is checked by lane A's Rules; the pure helpers below edit a
rule set they are handed, each with a case in Tests_UI.lua.

Owned by lane G (window and config). Frames are made only inside Build; the ready hook
returns early on IC_HEADLESS.

What the list shows is ns.Comms.ActiveRules(key): your rules, plus, in a group, rules from
other addon users that fill gaps (amber, "from <name>"; the Raid Lead's win). Edits only
ever touch your own saved set (db.rules[key]); a rule from someone else is kept as your own
with "Keep a copy". Every edit calls ns.Comms.RulesChanged() so the group hears of it.

    UIRules.KeyChoices(db, names)      the instance picker's { value, label } list
    UIRules.Items(merged, mine, sources)  list rows in rank order
    UIRules.Add(set, text, intent)     a rule from a typed name or npc id, last in the order
    UIRules.Move(set, keys, dir)       moves the chosen rules one place up (-1) or down (+1)
    UIRules.Apply(set, keys, field, value)  job, fallback or max count for many rules
    UIRules.Delete(set, keys)
    UIRules.Paste(set, rules)          a pasted list goes on top in its order; the rest follow
    UIRules.Import(byKey, loaded)      a loaded file merged in; matches updated, nothing deleted
    UIRules.MoveLegacy(byKey, from, to) an Anniversary zone's rules moved under an instance
    UIRules.NpcFromGuid(guid)          the npc id in a creature GUID, or nil
    UIRules.Note(view)                 the line above the list

Layout, px from the page top: picker and file buttons 0, add row 30, selection toolbar 60
(all 22 high), note 90, then the list (header row above its scroll) from 110 to the page's
bottom. Paste, Share and Load swap the list for a text area in the same rectangle, with its
own buttons in the note's row, so nothing is ever drawn over the list.
]]

ns.UIRules = ns.UIRules or {}
local UIRules = ns.UIRules
local Rules, CC, Seats = ns.Rules, ns.CC, ns.Seats

local W = LibStub("LibICWidgets-1.0")
local Util = LibStub("LibICUtil-1.0")
local Restrict = LibStub("LibICRestrict-1.0")

local ROW1, ROW2, ROW3, NOTE_TOP, LIST_TOP = 0, 30, 60, 90, 110   -- px from the page top
local HERE = "here"    -- the picker value that follows where the player is

--------------------------------------------------------------------------------
-- Pure
--------------------------------------------------------------------------------

function UIRules.KeyChoices(db, names)
    local out = { { HERE, "Where I am" } }
    local seen, rest = {}, {}
    local function Add(key)
        if type(key) ~= "string" or seen[key] or not Rules.IsInstanceKey(key) then return end
        seen[key] = true
        rest[#rest + 1] = { key, ns.UI.KeyLabel(key, names) }
    end
    Add("open")
    for key in pairs(db and db.rules or {}) do Add(key) end
    for id in pairs(names or {}) do
        if type(id) == "number" then Add("i:" .. id) end
    end
    table.sort(rest, function(a, b)
        -- The open world first, Anniversary leftovers last, the rest by name.
        local ao = a[1] == "open" and 0 or (Rules.IsLegacy(a[1]) and 2 or 1)
        local bo = b[1] == "open" and 0 or (Rules.IsLegacy(b[1]) and 2 or 1)
        if ao ~= bo then return ao < bo end
        return a[2] < b[2]
    end)
    for _, choice in ipairs(rest) do out[#out + 1] = choice end
    return out
end

-- merged: the set shown; mine: your saved set (or nil); sources: { [key] = owner }.
-- Returns { { key, rule, pos, mine, from }, ... } in rank order. `from` is set only for a
-- rule that is not yours.
function UIRules.Items(merged, mine, sources)
    local _, ranked = Rules.Ranked(merged or {})
    local out = {}
    for i, entry in ipairs(ranked) do
        local isMine = mine ~= nil and mine[entry.key] ~= nil
        out[i] = {
            key = entry.key, rule = entry.rule, pos = i, mine = isMine,
            from = (not isMine) and (sources and sources[entry.key] or entry.rule.from or "someone else") or nil,
        }
    end
    return out
end

local function MaxRank(set)
    local top = 0
    for _, rule in pairs(set) do
        if type(rule) == "table" and type(rule.rank) == "number" and rule.rank > top then top = rule.rank end
    end
    return top
end

-- text: a mob name as the game shows it, or an npc id. Returns the new key, or nil and why.
function UIRules.Add(set, text, intent)
    local trimmed = Util.Trim(tostring(text or ""))
    local id = trimmed:match("^%d+$") and tonumber(trimmed)
    local rule, why = Rules.New({
        name = (not id) and trimmed or nil, npcID = id or nil, intent = intent or "KILL",
        rank = MaxRank(set) + Rules.RANK_STEP, from = "me",
    })
    if not rule then return nil, why end
    local key = Rules.Key(rule)
    if set[key] or Rules.Match(set, rule) then return nil, trimmed .. " is already in this list" end
    set[key] = rule
    return key
end

local function Ordered(set)
    return (Rules.Ranked(set))
end

-- keys: { [key] = true }. Moves every chosen rule one place, keeping their order among
-- themselves, then renumbers 10, 20, 30 ... Returns whether anything moved.
function UIRules.Move(set, keys, dir)
    local _, ranked = Rules.Ranked(set)
    local list = {}
    for i, entry in ipairs(ranked) do list[i] = entry.key end
    local moved = false
    local from, to, step = 1, #list, 1
    if dir > 0 then from, to, step = #list, 1, -1 end
    for i = from, to, step do
        local j = i + (dir > 0 and 1 or -1)
        if keys[list[i]] and list[j] and not keys[list[j]] then
            list[i], list[j] = list[j], list[i]
            moved = true
        end
    end
    local rules = {}
    for i, key in ipairs(list) do rules[i] = set[key] end
    Rules.Renumber(rules)
    return moved
end

-- field: "intent", "fallback" (false or "none" clears it) or "maxCount" (nil clears it).
-- A rule the change would make invalid is left as it was. Returns changed, refused.
function UIRules.Apply(set, keys, field, value)
    local changed, refused = 0, 0
    for _, key in ipairs(Util.SortedKeys(keys)) do
        local rule = set[key]
        if type(rule) == "table" then
            local fields = Util.DeepCopy(rule)
            if field == "fallback" and (value == false or value == "none") then
                fields.fallback = nil
            else
                fields[field] = value
            end
            local fresh = Rules.New(fields)
            if fresh then
                rule.intent, rule.fallback, rule.maxCount = fresh.intent, fresh.fallback, fresh.maxCount
                changed = changed + 1
            else
                refused = refused + 1
            end
        end
    end
    return changed, refused
end

function UIRules.Delete(set, keys)
    local n = 0
    for key in pairs(keys) do
        if set[key] ~= nil then
            set[key] = nil
            n = n + 1
        end
    end
    if n > 0 then Rules.Renumber(Ordered(set)) end
    return n
end

-- rules: Rules.ParseBulk's answer, best first. Mobs already listed take the pasted job and
-- place; new ones are added; rules the paste did not name keep their order below it.
-- Returns added, updated.
function UIRules.Paste(set, rules)
    local added, updated = 0, 0
    local pasted, order = {}, {}
    for _, rule in ipairs(rules or {}) do
        local _, key = Rules.Match(set, rule)
        if key then
            set[key].intent = rule.intent
            updated = updated + 1
        else
            key = Rules.Key(rule)
            rule.from = "me"
            set[key] = rule
            added = added + 1
        end
        if not pasted[key] then
            pasted[key] = true
            order[#order + 1] = set[key]
        end
    end
    for _, rule in ipairs(Ordered(set)) do
        if not pasted[Rules.Key(rule) or ""] then order[#order + 1] = rule end
    end
    Rules.Renumber(order)
    return added, updated
end

-- byKey: db.rules. loaded: Rules.FromJSON's answer. A rule for a mob already listed takes
-- the file's job, priority, fallback and max count; new ones are added; nothing is deleted.
-- Returns instances, added, updated.
function UIRules.Import(byKey, loaded)
    local instances, added, updated = 0, 0, 0
    for _, key in ipairs(Util.SortedKeys(loaded or {})) do
        instances = instances + 1
        if type(byKey[key]) ~= "table" then byKey[key] = {} end
        local set = byKey[key]
        for _, rkey in ipairs(Util.SortedKeys(loaded[key])) do
            local rule = loaded[key][rkey]
            local _, have = Rules.Match(set, rule)
            if have then
                local mine = set[have]
                mine.intent, mine.rank, mine.fallback, mine.maxCount = rule.intent, rule.rank, rule.fallback, rule.maxCount
                updated = updated + 1
            else
                rule.from = "me"
                set[rkey] = rule
                added = added + 1
            end
        end
        Rules.Renumber(Ordered(set))
    end
    return instances, added, updated
end

-- Moves an Anniversary zone's rules ("legacy:<zone>") under a Forever instance key. Rules
-- already there win. Returns how many came across, or nil and why.
function UIRules.MoveLegacy(byKey, from, to)
    if not Rules.IsLegacy(from) then return nil, "only Anniversary rules move this way" end
    if not Rules.IsInstanceKey(to) or Rules.IsLegacy(to) or to == "open" then
        return nil, "go inside the instance these rules are for first"
    end
    local merged, added = Rules.Merge(byKey[to] or {}, byKey[from] or {}, "me")
    local rules = Ordered(merged)
    -- What was already here stays on top; what came across follows in its own order.
    Rules.Renumber(rules)
    byKey[to] = merged
    byKey[from] = nil
    return added
end

-- "Creature-0-1-2-3-4294-0000ABCD" -> 4294. Players, pets and anything else -> nil.
function UIRules.NpcFromGuid(guid)
    if type(guid) ~= "string" then return nil end
    local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    return tonumber(id)
end

-- view = { key, label, items, selected, legacy }. Returns text and its colour role.
function UIRules.Note(view)
    view = view or {}
    if view.legacy then
        return "From an Anniversary file, not a Forever instance. Stand in the instance they are for "
            .. "and press Move here.", "warn"
    end
    local total, theirs = #(view.items or {}), 0
    for _, item in ipairs(view.items or {}) do
        if not item.mine then theirs = theirs + 1 end
    end
    if total == 0 then
        return "No rules for " .. tostring(view.label) .. " yet: add a mob above or paste a list.", "textDim"
    end
    local text = total .. " " .. Util.Plural(total, "rule") .. ", top first"
    if theirs > 0 then text = text .. "; " .. theirs .. " from the group in amber (yours win)" end
    if (view.selected or 0) > 0 then text = text .. "; " .. view.selected .. " chosen" end
    return text .. ".", "textDim"
end

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------

local page
local controls = {}
local chosen = {}        -- { [key] = true }: session state, cleared when the instance changes
local shownKey
local mode = "list"      -- "list" | "paste" | "share" | "load"

local function Saved()
    local cdb = ns.cdb
    if type(cdb.windows) ~= "table" then cdb.windows = {} end
    if type(cdb.windows.main) ~= "table" then cdb.windows.main = {} end
    return cdb.windows.main
end

local function Picked()
    local v = Saved().rulesKey
    return type(v) == "string" and v ~= "" and v or HERE
end

local function Key()
    local v = Picked()
    if v == HERE then return (ns.UI.Here()) end
    return v
end

local function Label(key)
    return ns.UI.KeyLabel(key, ns.Instances and ns.Instances.list)
end

-- Your own set for the key, made when `create` and missing.
local function Mine(key, create)
    local rules = ns.db.rules
    if type(rules[key]) ~= "table" then
        if not create then return nil end
        rules[key] = {}
    end
    return rules[key]
end

local function Shown(key)
    if Rules.IsLegacy(key) or not (ns.Comms and ns.Comms.ActiveRules) then
        return Mine(key, false) or {}, {}
    end
    local ok, merged, sources = pcall(ns.Comms.ActiveRules, key)
    if not ok or type(merged) ~= "table" then return Mine(key, false) or {}, {} end
    return merged, sources or {}
end

local function Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function Changed(key)
    local set = ns.db.rules[key]
    if type(set) == "table" and next(set) == nil then ns.db.rules[key] = nil end
    if ns.Comms and ns.Comms.RulesChanged then pcall(ns.Comms.RulesChanged) end
    ns.UI.Changed("rules", key)
    UIRules.Refresh()
end

local function Say(text)
    ns.Print(text)
end

local function Tip(frame, title, ...)
    local lines = { ... }
    W.Tooltip(frame, function(tip)
        tip:AddLine(title)
        for _, line in ipairs(lines) do tip:AddLine(line, 1, 1, 1, true) end
    end)
end

-- The jobs this instance's plan can carry, plus Never mark. A rule holding any other job
-- would silently fall back mid-pull.
local function JobChoices(key)
    local out = {}
    for _, intent in ipairs(CC.Pickable((Seats.PlanFor(ns.db, key)))) do
        out[#out + 1] = { intent, CC.INTENTS[intent].label }
    end
    return out
end

local function FallbackChoices()
    local out = { { "none", "No fallback" } }
    for _, intent in ipairs(CC.ORDER) do
        local def = CC.INTENTS[intent]
        if intent ~= "IGNORE" and not def.hidden then out[#out + 1] = { intent, "Else " .. def.label } end
    end
    return out
end

local function JobText(rule)
    local def = CC.INTENTS[rule.intent]
    return def and def.label or tostring(rule.intent)
end

--------------------------------------------------------------------------------
-- Editing
--------------------------------------------------------------------------------

local function ChosenMine(key)
    local mine = Mine(key, false) or {}
    local keys, n = {}, 0
    for k in pairs(chosen) do
        if mine[k] then
            keys[k] = true
            n = n + 1
        end
    end
    return keys, n
end

local function EditChosen(fn)
    local key = Key()
    local keys, n = ChosenMine(key)
    if n == 0 then
        Say("choose your own rules in the list first (a rule from the group needs Keep a copy).")
        return
    end
    fn(Mine(key, true), keys, n)
    Changed(key)
end

local function AddTyped()
    local key = Key()
    if Rules.IsLegacy(key) then
        Say("rules cannot be added to an Anniversary leftover; pick an instance first.")
        return
    end
    local text = controls.addBox:GetText()
    local rkey, why = UIRules.Add(Mine(key, true), text, controls.addJob:GetValue() or "KILL")
    if not rkey then
        Say("not added: " .. tostring(why) .. ".")
        if next(ns.db.rules[key]) == nil then ns.db.rules[key] = nil end
        return
    end
    controls.addBox:SetText("")
    Say("added " .. rkey:sub(rkey:find(":") + 1) .. " to " .. Label(key) .. ", last in the order.")
    Changed(key)
end

-- The target's name and npc id, each only when the client lets us read it.
local function TargetFacts()
    if type(UnitGUID) ~= "function" or type(UnitName) ~= "function" then return nil, "the target is not readable" end
    local okG, guid = pcall(UnitGUID, "target")
    local okN, name = pcall(UnitName, "target")
    guid = okG and Restrict.Readable(guid) or nil
    name = okN and Restrict.Readable(name) or nil
    if guid == nil and name == nil then return nil, "no target, or its name is hidden here" end
    local id = UIRules.NpcFromGuid(guid)
    if not id and type(guid) == "string" then return nil, "that target is not a mob" end
    return { name = type(name) == "string" and name or nil, npcID = id }
end

local function AddTarget()
    local key = Key()
    if Rules.IsLegacy(key) then
        Say("rules cannot be added to an Anniversary leftover; pick an instance first.")
        return
    end
    local facts, why = TargetFacts()
    if not facts then
        Say("not added: " .. why .. ". Type the name instead.")
        return
    end
    local set = Mine(key, true)
    local rule, err = Rules.New({
        name = facts.name, npcID = facts.npcID, intent = controls.addJob:GetValue() or "KILL",
        rank = MaxRank(set) + Rules.RANK_STEP, from = "me",
    })
    if not rule then
        Say("not added: " .. tostring(err) .. ".")
    elseif Rules.Match(set, rule) then
        Say((facts.name or ("npc " .. tostring(facts.npcID))) .. " is already in this list.")
    else
        set[Rules.Key(rule)] = rule
        Say("added " .. (facts.name or ("npc " .. facts.npcID)) .. " to " .. Label(key) .. ", last in the order.")
    end
    Changed(key)
end

local function KeepCopies()
    local key = Key()
    local merged = Shown(key)
    local mine = Mine(key, true)
    local n = 0
    for k in pairs(chosen) do
        if merged[k] and not mine[k] then
            local copy = Util.DeepCopy(merged[k])
            copy.from = "me"
            copy.rank = MaxRank(mine) + Rules.RANK_STEP
            mine[k] = copy
            n = n + 1
        end
    end
    if n == 0 then Say("choose a rule from the group (amber) first.") end
    Changed(key)
end

--------------------------------------------------------------------------------
-- Text modes: paste, share, load
--------------------------------------------------------------------------------

local SHARE_HINT = "Your rules for every instance, as a file. Ctrl+C copies the selection."
local PASTE_HINT = "One mob per line, best first; \"= sheep\" sets a job; -- starts a comment."
local LOAD_HINT = "Paste a shared file, then Load. Matches are updated, nothing is deleted."

local function SetMode(m)
    mode = m
    local text = m ~= "list"
    controls.list:SetShown(not text)
    controls.note:SetShown(not text)
    controls.area:SetShown(text)
    controls.textBar:SetShown(text)
    controls.go:SetShown(m == "paste" or m == "load")
    if m == "paste" then
        controls.go:SetLabel("Add all")
        controls.hint:SetText(PASTE_HINT)
        controls.area:SetText("")
    elseif m == "load" then
        controls.go:SetLabel("Load")
        controls.hint:SetText(LOAD_HINT)
        controls.area:SetText("")
    elseif m == "share" then
        local text2, why = Rules.ToJSON(ns.db.rules, { note = "Marked For Death rules" })
        controls.hint:SetText(SHARE_HINT)
        controls.area:SetText(text2 or ("could not write the file: " .. tostring(why)))
        controls.area:SelectAll()
    end
    if not text then controls.area.edit:ClearFocus() end
    UIRules.Refresh()
end

local function Go()
    if mode == "paste" then
        local key = Key()
        if Rules.IsLegacy(key) then
            Say("pick an instance first; an Anniversary leftover takes no new rules.")
            return
        end
        local rules, why = Rules.ParseBulk(controls.area:GetText())
        if not rules then
            Say("nothing added: " .. tostring(why) .. ".")
            return
        end
        local added, updated = UIRules.Paste(Mine(key, true), rules)
        Say(string.format("%s: %d added, %d updated.", Label(key), added, updated))
        Changed(key)
        SetMode("list")
    elseif mode == "load" then
        local loaded, why = Rules.FromJSON(controls.area:GetText())
        if not loaded then
            Say("nothing loaded: " .. tostring(why) .. ".")
            return
        end
        local zones, added, updated = UIRules.Import(ns.db.rules, loaded)
        Say(string.format("loaded %d %s: %d added, %d updated. Roles are set on the Roles tab.",
            zones, Util.Plural(zones, "instance"), added, updated))
        for key in pairs(loaded) do ns.UI.Changed("rules", key) end
        if ns.Comms and ns.Comms.RulesChanged then pcall(ns.Comms.RulesChanged) end
        SetMode("list")
    end
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

local function Button(text, w, onClick, title, ...)
    local b = W.Button(page, text, w, 22, { onClick = onClick })
    Tip(b, title or text, ...)
    return b
end

local function BuildTop(width)
    local label = W.Label(page, "Rules for:")
    label:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(ROW1 + 4))
    controls.picker = W.Choice(page, 230, 22, {
        choices = {},
        onChange = function(value)
            Saved().rulesKey = value
            UIRules.Refresh()
        end,
    })
    controls.picker:SetPoint("LEFT", label, "RIGHT", 8, 0)
    Tip(controls.picker, "Rules for", "Where I am follows you from instance to instance.",
        "Pick an instance to plan it from anywhere. Kept between sessions.")

    controls.legacy = Button("Move here", 90, function()
        local from, to = Key(), (ns.UI.Here())
        local n, why = UIRules.MoveLegacy(ns.db.rules, from, to)
        if not n then
            Say("not moved: " .. why .. ".")
            return
        end
        Say(string.format("%d %s moved to %s.", n, Util.Plural(n, "rule"), Label(to)))
        Saved().rulesKey = HERE
        Changed(to)
    end, "Move here", "Moves these Anniversary rules under the instance you are standing in.",
        "Rules already there win.")
    controls.legacy:SetPoint("LEFT", controls.picker, "RIGHT", 6, 0)

    local load = Button("Load file", 80, function() SetMode(mode == "load" and "list" or "load") end,
        "Load file", "Paste a file someone shared. It is checked whole: one bad rule refuses it.")
    load:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -ROW1)
    local share = Button("Share", 70, function() SetMode(mode == "share" and "list" or "share") end,
        "Share", "Every rule you have, as a file to copy for someone else.")
    share:SetPoint("RIGHT", load, "LEFT", -6, 0)
    local paste = Button("Paste list", 84, function() SetMode(mode == "paste" and "list" or "paste") end,
        "Paste list", "A whole kill order at once, best first.")
    paste:SetPoint("RIGHT", share, "LEFT", -6, 0)

    -- Add row
    controls.addBox = W.EditBox(page, 220, 22, {
        maxBytes = Rules.MAX_NAME,
        placeholder = "mob name, or npc id",
        onEnter = function(_, box)
            AddTyped()
            box:ClearFocus()
        end,
    })
    controls.addBox:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -ROW2)
    Tip(controls.addBox, "Add a mob", "The name exactly as the game shows it, or its npc id.",
        "Quotes, semicolons, brackets and | are refused: a macro could not hold them.")
    controls.addJob = W.Choice(page, 110, 22, { choices = {}, value = "KILL" })
    controls.addJob:SetPoint("LEFT", controls.addBox, "RIGHT", 6, 0)
    Tip(controls.addJob, "Job", "The job a new rule starts with.")
    local add = Button("Add", 50, AddTyped, "Add", "Adds the typed mob last in the order.")
    add:SetPoint("LEFT", controls.addJob, "RIGHT", 6, 0)
    local target = Button("Add target", 90, AddTarget, "Add target",
        "Adds the mob you have targeted, by name and npc id, where the game lets addons read them.",
        "Inside instances names may be hidden: type them instead.")
    target:SetPoint("LEFT", add, "RIGHT", 6, 0)

    -- Selection toolbar
    controls.chosen = W.Label(page, "", { color = "textDim" })
    controls.chosen:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(ROW3 + 4))
    controls.chosen:SetWidth(70)
    controls.chosen:SetWordWrap(false)
    local all = Button("All", 36, function()
        for _, item in ipairs(controls.list:GetItems()) do chosen[item.key] = true end
        UIRules.Refresh()
    end, "All", "Chooses every rule in the list.")
    all:SetPoint("TOPLEFT", page, "TOPLEFT", 72, -ROW3)
    local none = Button("None", 44, function()
        chosen = {}
        UIRules.Refresh()
    end, "None", "Clears the choice.")
    none:SetPoint("LEFT", all, "RIGHT", 4, 0)

    controls.bulkJob = W.Choice(page, 96, 22, {
        choices = {},
        onChange = function(value, c)
            -- A picker that acts, not one that holds a value: back to its own name at once.
            c.icValue = nil
            c:SetLabel("Set job")
            EditChosen(function(set, keys, n)
                local changed = UIRules.Apply(set, keys, "intent", value)
                Say(string.format("%d of %d set to %s.", changed, n, CC.INTENTS[value].label))
            end)
        end,
    })
    controls.bulkJob:SetPoint("LEFT", none, "RIGHT", 10, 0)
    Tip(controls.bulkJob, "Set job", "Gives every chosen rule of yours this job.")

    controls.bulkFallback = W.Choice(page, 104, 22, {
        choices = FallbackChoices(),
        onChange = function(value, c)
            c.icValue = nil
            c:SetLabel("Set else")
            EditChosen(function(set, keys, n)
                local changed, refused = UIRules.Apply(set, keys, "fallback", value)
                Say(string.format("%d of %d changed%s.", changed, n,
                    refused > 0 and (", " .. refused .. " refused (a fallback cannot be the job itself)") or ""))
            end)
        end,
    })
    controls.bulkFallback:SetPoint("LEFT", controls.bulkJob, "RIGHT", 4, 0)
    Tip(controls.bulkFallback, "Fallback", "The job a chosen rule takes when no seat of its own job is free",
        "(no mage for a Sheep rule: else Kill). No fallback: it goes unmarked.")

    controls.bulkMax = W.EditBox(page, 34, 22, {
        maxBytes = 2,
        placeholder = "max",
        onEnter = function(text, box)
            box:ClearFocus()
            local n = tonumber(text)
            if text ~= "" and not n then
                Say("max count is a whole number from 1, or empty for no limit.")
                return
            end
            EditChosen(function(set, keys, count)
                local changed = UIRules.Apply(set, keys, "maxCount", n)
                Say(string.format("%d of %d now mark %s.", changed, count, n and ("at most " .. n) or "every copy"))
            end)
            box:SetText("")
        end,
    })
    controls.bulkMax:SetPoint("LEFT", controls.bulkFallback, "RIGHT", 4, 0)
    Tip(controls.bulkMax, "Max count", "How many copies of a chosen mob get an icon at once.",
        "Type a number and press Enter; empty and Enter clears the limit.")

    local up = Button("Up", 36, function()
        EditChosen(function(set, keys) UIRules.Move(set, keys, -1) end)
    end, "Up", "Moves the chosen rules one place higher in the kill order.")
    up:SetPoint("LEFT", controls.bulkMax, "RIGHT", 8, 0)
    local down = Button("Down", 46, function()
        EditChosen(function(set, keys) UIRules.Move(set, keys, 1) end)
    end, "Down", "Moves the chosen rules one place lower.")
    down:SetPoint("LEFT", up, "RIGHT", 4, 0)
    local delete = W.Button(page, "Delete", 56, 22, {
        kind = "danger",
        onClick = function()
            local _, n = ChosenMine(Key())
            if n == 0 then
                Say("choose your own rules in the list first.")
                return
            end
            W.Confirm("Delete " .. n .. " " .. Util.Plural(n, "rule") .. "?", function()
                EditChosen(function(set, keys) UIRules.Delete(set, keys) end)
                chosen = {}
                UIRules.Refresh()
            end)
        end,
    })
    delete:SetPoint("LEFT", down, "RIGHT", 4, 0)
    Tip(delete, "Delete", "Deletes the chosen rules of yours. Rules from the group are not yours to delete.")
    local keep = Button("Keep a copy", 90, KeepCopies, "Keep a copy",
        "Saves the chosen rules from the group (amber) as your own, last in the order.")
    keep:SetPoint("LEFT", delete, "RIGHT", 4, 0)

    controls.note = W.Label(page, "", { color = "textDim" })
    controls.note:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(NOTE_TOP + 2))
    controls.note:SetPoint("RIGHT", page, "RIGHT", 0, 0)
    controls.note:SetWordWrap(false)
    if controls.note.SetMaxLines then controls.note:SetMaxLines(1) end

    -- The text modes' own row, in the note's place.
    controls.textBar = CreateFrame("Frame", nil, page)
    controls.textBar:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(NOTE_TOP - 4))
    controls.textBar:SetSize(width, 20)
    controls.go = W.Button(controls.textBar, "Add all", 70, 20, { kind = "accent", onClick = Go })
    controls.go:SetPoint("LEFT", controls.textBar, "LEFT", 0, 0)
    local back = W.Button(controls.textBar, "Back", 56, 20, { onClick = function() SetMode("list") end })
    back:SetPoint("LEFT", controls.go, "RIGHT", 6, 0)
    controls.hint = W.Label(controls.textBar, "", { color = "textDim" })
    controls.hint:SetPoint("LEFT", back, "RIGHT", 10, 0)
    controls.hint:SetPoint("RIGHT", controls.textBar, "RIGHT", 0, 0)
    controls.hint:SetWordWrap(false)
    controls.textBar:Hide()
end

local function BuildList(width, height)
    local list
    list = W.List(page, width, height, {
        columns = {
            { key = "pick", label = "", width = 18, text = function(item)
                return chosen[item.key] and "+" or "", "accent"
            end },
            { key = "pos", label = "#", width = 28, justify = "RIGHT", tip = "Place in the kill order, 1 first",
                text = function(item) return tostring(item.pos) end },
            { key = "mob", label = "Mob", tip = "As the game shows it; an npc id alone cannot be targeted by name",
                text = function(item)
                    if item.rule.name then return item.rule.name, item.mine and "text" or "warn" end
                    return "npc " .. tostring(item.rule.npcID) .. " (no name yet)", "textDim"
                end },
            { key = "job", label = "Job", width = 84, text = function(item) return JobText(item.rule) end },
            { key = "fallback", label = "Else", width = 70, tip = "The job taken when no seat of its own is free",
                text = function(item)
                    local def = item.rule.fallback and CC.INTENTS[item.rule.fallback]
                    return def and def.label or "", "textDim"
                end },
            { key = "max", label = "Max", width = 36, justify = "RIGHT", tip = "Copies marked at once",
                text = function(item) return item.rule.maxCount and tostring(item.rule.maxCount) or "", "textDim" end },
            { key = "from", label = "From", width = 110, text = function(item)
                if item.mine then return "you", "textDim" end
                return tostring(item.from), "warn"
            end },
        },
        selected = function(item) return chosen[item.key] == true end,
        onClick = function(item, mouseButton, row)
            if mouseButton == "RightButton" then
                if not item.mine then
                    Say("that rule is " .. tostring(item.from) .. "'s. Keep a copy makes it yours to edit.")
                    return
                end
                chosen = { [item.key] = true }
                local menu = { { title = item.rule.name or ("npc " .. tostring(item.rule.npcID)) } }
                for _, choice in ipairs(JobChoices(Key())) do
                    menu[#menu + 1] = {
                        text = choice[2],
                        radio = function() return item.rule.intent == choice[1] end,
                        onClick = function()
                            EditChosen(function(set, keys) UIRules.Apply(set, keys, "intent", choice[1]) end)
                        end,
                    }
                end
                W.Menu(row, menu)
                UIRules.Refresh()
                return
            end
            chosen[item.key] = (not chosen[item.key]) or nil
            UIRules.Refresh()
        end,
        tooltip = function(tip, item)
            local rule = item.rule
            tip:AddLine(rule.name or ("npc " .. tostring(rule.npcID)))
            tip:AddLine("Job: " .. JobText(rule) .. (rule.fallback and (", else " .. CC.INTENTS[rule.fallback].label) or ""),
                1, 1, 1)
            if rule.npcID then tip:AddLine("npc id " .. rule.npcID, 1, 1, 1) end
            if rule.maxCount then tip:AddLine("At most " .. rule.maxCount .. " marked at once", 1, 1, 1) end
            tip:AddLine(item.mine and "Yours." or ("From " .. tostring(item.from) .. "; yours win."), 0.7, 0.7, 0.7)
            tip:AddLine("Click to choose, right-click for its job.", 0.7, 0.7, 0.7)
        end,
        empty = "No rules here yet",
    })
    list:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -LIST_TOP)
    controls.list = list

    controls.area = W.TextArea(page, width, height, { maxBytes = 60000 })
    controls.area:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -LIST_TOP)
    controls.area:Hide()
end

function UIRules.Refresh()
    if not page or not ns.db then return end
    local key = Key()
    if key ~= shownKey then
        chosen = {}
        shownKey = key
    end
    local names = ns.Instances and ns.Instances.list
    controls.picker.icChoices = UIRules.KeyChoices(ns.db, names)
    controls.picker:SetValue(Picked())
    if Picked() == HERE then controls.picker:SetLabel("Where I am: " .. Label(key)) end
    local legacy = Rules.IsLegacy(key)
    controls.legacy:SetShown(legacy)

    local jobs = JobChoices(key)
    controls.addJob.icChoices = jobs
    controls.bulkJob.icChoices = jobs
    controls.bulkJob:SetLabel("Set job")
    controls.bulkFallback:SetLabel("Set else")

    local merged, sources = Shown(key)
    local items = UIRules.Items(merged, Mine(key, false), sources)
    for k in pairs(chosen) do
        if merged[k] == nil then chosen[k] = nil end
    end
    local n = Count(chosen)
    controls.chosen:SetText(n > 0 and (n .. " chosen") or "Choose:")
    controls.list:SetItems(items)
    local note, noteRole = UIRules.Note({ key = key, label = Label(key), items = items, selected = n, legacy = legacy })
    controls.note:SetText(note)
    controls.note:SetRole(noteRole or "textDim")
end

local function Fit(w, h)
    local height = math.max(60, h - LIST_TOP)
    controls.list:Resize(w, height)
    controls.area:Resize(w, height)
    controls.textBar:SetWidth(w)
end

local function DropFocus()
    controls.addBox:ClearFocus()
    controls.bulkMax:ClearFocus()
    controls.area.edit:ClearFocus()
end

function UIRules.Build(parent)
    if page then return page end
    page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints(parent)
    local width, height = parent:GetWidth(), parent:GetHeight()
    BuildTop(width)
    BuildList(width, math.max(60, height - LIST_TOP))
    ns.Events.On("PLAYER_REGEN_DISABLED", "ui_rules", DropFocus)
    page:SetScript("OnShow", UIRules.Refresh)
    page:SetScript("OnHide", DropFocus)
    UIRules.Refresh()
    return page
end

UIRules.Fit = Fit

ns.OnReady("ui_rules", function()
    if IC_HEADLESS then return end
    ns.UI.AddTab("rules", "Rules", UIRules.Build, {
        refresh = UIRules.Refresh,
        onResize = function(w, h) if page then Fit(w, h) end end,
    })
end)
