local addonName, ns = ...

ns.Reply = ns.Reply or {}
local Reply = ns.Reply

-- A whisper is cut off at 255 characters once links expand, and a reply that
-- names three items and loses the third to truncation is worse than one that
-- names two and knows it.
local MAX_LEN = 250
local MAX_ITEMS = 3
local MAX_REAGENTS = 4

-- Pure. What the recipe needs, for a customer who linked the item rather than the
-- pattern and so has no reagent list in front of them. reagentList is in the order
-- the profession window shows, which is the order they will read it in.
function Reply.Reagents(entry, max)
    if not entry or not entry.reagentList then return "" end
    local parts = {}
    for _, r in ipairs(entry.reagentList) do
        if #parts >= (max or MAX_REAGENTS) then break end
        if r.name then
            parts[#parts + 1] = string.format("%dx %s", r.count or 1, r.name)
        end
    end
    return table.concat(parts, ", ")
end

-- Pure. Is this exact name already quoted in the list? Matched against each
-- entry's bracketed name rather than by substring, because "Living Ruby" is not
-- covered by a "Bold Living Ruby" already in the list -- it is a different gem we
-- would then never mention.
function Reply.Names(list, name)
    if not name or name == "" then return false end
    for _, text in ipairs(list or {}) do
        if text == name then return true end
        if text:match("%[(.-)%]") == name then return true end
    end
    return false
end

-- Pure. The one place a customer-facing sentence is built, so the invite, the
-- reply to an awaited item and the confirmation window's editable box always say
-- the same thing.
--
-- o = { book, matched, cannotDo, whisper, profile, player,
--       base = "invite"|"reply", withPatterns, maxLen }
--
-- Coverage picks the sentence: everything they named, some of it, or none. It is
-- decided over ALL of it, because answering two linked recipes by naming the first
-- is what got asked back "can u do both ur just the belt?".
function Reply.Compose(o)
    local maxLen = o.maxLen or MAX_LEN
    local whisper = o.whisper or {}
    local book = o.book or {}

    local have = {}
    for i = 1, math.min(#(o.matched or {}), MAX_ITEMS) do
        local entry = book[o.matched[i].itemID]
        if entry then have[#have + 1] = entry end
    end
    local lack = {}
    for i = 1, math.min(#(o.cannotDo or {}), MAX_ITEMS) do lack[i] = o.cannotDo[i] end

    local kind = "all"
    if #have == 0 then
        kind = "none"
    elseif #lack > 0 then
        kind = "some"
    end

    local template
    if kind == "none" then
        template = (o.base == "invite") and whisper.templateNoItem or whisper.noneTemplate
    elseif kind == "some" then
        template = whisper.partialTemplate
    else
        template = (o.base == "invite") and whisper.template or whisper.confirmTemplate
    end

    if not template or template == "" then
        return { kind = kind, have = have, lack = lack, text = "", named = 0,
                 lacked = 0, dropped = #have, lackDropped = #lack,
                 patternsDropped = 0, overLength = false }
    end

    local function Filled(itemCount, lackCount)
        local items, lacks = {}, {}
        for i = 1, itemCount do
            local text = have[i].link or have[i].name
            if text then items[#items + 1] = text end
        end
        for i = 1, lackCount do lacks[#lacks + 1] = lack[i] end
        local itemText = table.concat(items, " ")
        return ns.Inviter.Render(template, {
            item = itemText, items = itemText, have = itemText,
            lack = table.concat(lacks, " "),
        }, o.player, o.profile)
    end

    -- Trim to fit the whisper cap, the less useful half first: what we cannot do
    -- matters less than what we can. Neither half is trimmed to nothing, because
    -- partialTemplate with an empty {lack} reads "I can do X, but I don't have ."
    local named, lacked = #have, #lack
    local text = Filled(named, lacked)
    while #text > maxLen and lacked > 1 do
        lacked = lacked - 1
        text = Filled(named, lacked)
    end
    while #text > maxLen and named > 1 do
        named = named - 1
        text = Filled(named, lacked)
    end

    local result = {
        kind = kind,
        have = have,
        lack = lack,
        text = text,
        named = named,
        lacked = lacked,
        -- Counted against everything they said, not against the capped lists, so
        -- a fourth item is reported as left out rather than quietly forgotten.
        dropped = math.max(0, #(o.matched or {}) - named),
        lackDropped = math.max(0, #(o.cannotDo or {}) - lacked),
        patternsDropped = 0,
        -- One item and one thing we lack is the floor. If that still overruns,
        -- the client will cut the wire message mid-link, so the caller says so
        -- rather than letting the customer see half an escape sequence.
        overLength = #text > maxLen,
        template = template,
    }
    if kind == "none" or not o.withPatterns then return result end

    -- The pattern link is the whole point of answering with one: hovering it shows
    -- the reagents, so they can gather before the trade. An entry scanned before
    -- books started keeping the link falls back to naming the reagents, which is
    -- the same information and more characters.
    for i = 1, named do
        local entry = have[i]
        local extra = entry.recipeLink
        if not extra then
            local mats = Reply.Reagents(entry)
            if mats ~= "" then extra = "(" .. mats .. ")" end
        end
        if extra then
            local candidate = result.text .. " " .. extra
            if #candidate <= maxLen then
                result.text = candidate
            else
                result.patternsDropped = result.patternsDropped + 1
            end
        end
    end

    return result
end
