local addonName, ns = ...

ns.Events = ns.Events or {}
local Events = ns.Events

-- How far back to look when stitching together a fragmented request.
local CONTEXT_WINDOW = 90

-- A message this short naming a family is a fragment, not conversation.
local FRAGMENT_WORDS = 5

-- Only the recipe ITEM ("Design: Bold Living Ruby", "Recipe: Haste Potion") is a
-- seller tell. Craft spell links are not: real trade chat shows buyers using
-- them too. The prefix comes from the active profession.
local function HasRecipeLink(raw, profile)
    if not raw then return false end
    local prefix = profile and profile.recipeItemPrefix
    if not prefix then return false end
    return raw:find(prefix, 1, true) ~= nil
end

-- The index covers the ACTIVE profession only. Matching idle books would
-- invite people for orders we are not running.
function Events.RebuildIndex()
    Events.index = ns.Matcher.BuildIndex(ns.Book(), ns.Prof.Current())
    return Events.index
end

local function IsProductItem(profile, itemID)
    local classID = select(12, GetItemInfo(itemID))
    if classID == nil then return false end
    return ns.Prof.IsProduct(profile, { classID = classID })
end

-- source is "trade", "whisper" or "party". A whisper naming an item is a
-- request by definition, so the buyer-signal requirement and the
-- broadcast-shaped seller signals are dropped for that channel.
function Events.Process(text, author, source, opts)
    opts = opts or {}
    if not ns.db then return end
    if not Events.index then Events.RebuildIndex() end

    local profile = ns.Prof.Current()
    local book = ns.Book()
    local ps = ns.PS()

    local short = (author or ""):gsub("%-.*", "")
    if short == "" then return end

    -- Master switch. /tm try still works so the classifier can be tested
    -- while the addon is otherwise silent.
    if not opts.dryRun and not ns.Enabled() then return end

    local isWhisper = (source == "whisper")
    local isParty = (source == "party")
    local isDirect = isWhisper or isParty

    -- Our own barks are not input. Bail before touching any state.
    if not opts.dryRun and short == UnitName("player") then return end

    local norm = ns.Util.Normalize(text)
    local now = ns.Now()
    local matched = ns.Matcher.Match(text, norm, Events.index)

    -- A dry run must never touch persistent player state.
    local state = opts.dryRun and {} or ns.Players.Get(ns.db, short)

    -- Repeat detection ONLY applies to item-mentioning trade chat.
    local isRepeat = false
    if #matched > 0 and not isDirect then
        _, isRepeat = ns.Players.Observe(state, norm, now, ps.filter.repeatWindowSec)
    end

    -- Fragmented requests across two messages, direct channels only.
    local usedContext = false
    if isDirect and #matched == 0 then
        local combined = ns.Players.RecentText(state, now, CONTEXT_WINDOW)
        if combined ~= "" then
            combined = combined .. " " .. text
            local cnorm = ns.Util.Normalize(combined)
            local cm = ns.Matcher.Match(combined, cnorm, Events.index)
            if #cm > 0 then
                matched = cm
                norm = cnorm
                usedContext = true
            end
        end
    end
    if isDirect and not opts.dryRun then
        ns.Players.PushRecent(state, text, now)
    end

    local filter = ps.filter
    if isDirect then
        filter = ns.DeepCopy(filter)
        filter.requireBuyerSignal = false
    end

    -- Did they name a specific product that is not in our book?
    local namedUnknownItem = false
    if #matched == 0 then
        for _, id in ipairs(ns.Util.ExtractItemIDs(text)) do
            if not book[id] and IsProductItem(profile, id) then
                namedUnknownItem = true
                break
            end
        end
        if not namedUnknownItem and ns.Matcher.NearMiss(norm, Events.index) then
            namedUnknownItem = true
        end
    end

    -- They may have linked several items and we only know some of them.
    local canDo, cannotDo = {}, {}
    do
        local matchedSet = {}
        for _, h in ipairs(matched) do matchedSet[h.itemID] = true end
        for _, l in ipairs(ns.Util.ExtractItemLinks(text)) do
            if matchedSet[l.id] then
                canDo[#canDo + 1] = l.link
            elseif not book[l.id] and IsProductItem(profile, l.id) then
                cannotDo[#cannotDo + 1] = l.link
            end
        end
    end

    local blocked
    if not opts.dryRun then
        if isWhisper and not ps.invite.fromWhisper then
            blocked = "whisper invites disabled"
        elseif UnitInParty(short) or UnitInRaid(short) then
            blocked = "already grouped"
        else
            blocked = ns.Inviter.BlockReason(state, now, GetNumGroupMembers() or 0, ps.invite)
        end
    end

    local result = ns.Classifier.Evaluate({
        norm = norm,
        raw = text,
        matched = matched,
        linkCount = #ns.Util.ExtractItemIDs(text),
        hasRecipeLink = HasRecipeLink(text, profile),
        namedUnknownItem = namedUnknownItem,
        isRepeat = isRepeat,
        isDirect = isDirect,
        playerState = state,
        blocked = blocked,
        filter = filter,
    })
    result.source = source
    result.profession = profile.key

    if ns.db.settings.captureAll and not opts.dryRun then
        ns.Log.Capture(short, text, result, now)
    end

    if result.reason ~= "no item match" and not opts.dryRun then
        ns.Log.Add(short, text, matched, result, now)
        if ns.db.settings.debug then
            ns.Print(ns.Log.Describe(ns.db.log[1]))
            ns.Print(ns.Log.DescribeHits(ns.db.log[1]))
        end
    end

    if isParty and not opts.dryRun and #matched > 0 then
        state.awaitingItem = nil
    end

    local willInvite = result.verdict == "invite" and not result.blocked
    local nounS = profile.craftNoun[1]

    if isWhisper and not opts.dryRun and result.verdict ~= "vetoed" then
        local w = ps.invite.whisper

        if #matched > 0 then
            local e = book[matched[1].itemID]
            local link = e and (e.link or e.name)

            if #cannotDo > 0 and not willInvite and w.enabled and w.autoReply then
                local have = #canDo > 0 and table.concat(canDo, " ") or (link or "that")
                ns.Inviter.Say(short, w.partialTemplate, {
                    have = have,
                    lack = table.concat(cannotDo, " "),
                })
                ns.Print(string.format(
                    "|cffffcc00%s asked for %d %s, you have %d.|r Cannot do: %s",
                    short, #canDo + #cannotDo, profile.craftNoun[2], #canDo, table.concat(cannotDo, " ")))
            elseif state.awaitingItem and not willInvite and w.enabled and w.autoReply then
                ns.Inviter.Say(short, w.confirmTemplate, { item = link })
            end
            state.awaitingItem = nil

        else
            local asked = ns.Util.IsAvailabilityQuestion(text, norm, ps.filter.askPhrases)
            local mayReply = w.enabled and w.autoReply
                and (w.autoSuggest or (asked and w.answerQuestions))

            local family, ids, exactFamily = ns.Matcher.NearMiss(norm, Events.index)
            local links = {}
            for _, id in ipairs(ids or {}) do
                local b = book[id]
                if b and (b.link or b.name) then links[#links + 1] = b.link or b.name end
            end

            local fragment = family and not exactFamily and #links > 0
                and (asked or #ns.Util.Tokenize(norm) <= FRAGMENT_WORDS)

            if fragment and w.enabled and w.autoReply then
                local show = {}
                for i = 1, math.min(3, #links) do show[i] = links[i] end
                ns.Inviter.Say(short, w.askWhichTemplate, { items = table.concat(show, " ") })
                ns.Print(string.format(
                    "|cffffcc00%s typed a partial %s name.|r Asked which of: %s",
                    short, nounS, table.concat(show, " ")))
                result.reason = "asked which " .. nounS
                ns.Log.Add(short, text, matched, result, now)
                return result
            end

            if #links > 0 or (asked and namedUnknownItem) then
                if #links > 0 then
                    ns.Print(string.format(
                        "|cffffcc00%s asked about a %s you do not know.|r You can do: %s",
                        short, nounS, table.concat(links, " ")))
                else
                    ns.Print(string.format(
                        "|cffffcc00%s asked for a %s you do not have.|r", short, nounS))
                end
                result.reason = "unknown " .. nounS
                ns.Log.Add(short, text, matched, result, now)

                if mayReply then
                    if w.autoSuggest and #links > 0 then
                        while #links > 3 do table.remove(links) end
                        ns.Inviter.Say(short, w.suggestTemplate, { items = table.concat(links, " ") })
                    else
                        ns.Inviter.Say(short, w.noneTemplate, {})
                    end
                end
            end
        end
    end

    if not opts.dryRun then
        local o = ns.db.settings.orders
        local wanted = (isWhisper and o.autoFromWhisper)
            or (isParty and o.autoFromParty)
            or (not isDirect and o.autoFromInvite)
        if wanted and result.verdict == "invite" and #matched > 0 then
            if usedContext then
                ns.Print(string.format("|cff888888(matched %s using their previous message)|r", short))
            end
            ns.Orders.Record(short, source, text, matched, now)
        end
        if isDirect and o.captureTranscript then
            ns.Orders.AddTranscript(short, "in", text, now)
        end
    end

    if willInvite and not opts.dryRun then
        ns.Inviter.Invite(short, matched, { cannotDo = cannotDo })
    end

    return result
end

function Events.OnTradeMessage(text, author, opts)
    return Events.Process(text, author, "trade", opts)
end

function Events.OnWhisper(text, author, opts)
    return Events.Process(text, author, "whisper", opts)
end

function Events.OnParty(text, author, opts)
    return Events.Process(text, author, "party", opts)
end
