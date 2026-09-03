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

-- One index per scanned book. Invites cover every profession the character
-- can craft for: a request is matched against each book and the one with the
-- most hits handles it, the active profession breaking ties. Events.index is
-- kept as the active book's index for callers that only care about that one.
function Events.RebuildIndex()
    Events.indexes = {}
    for _, key in ipairs(ns.Prof.Known()) do
        Events.indexes[key] = ns.Matcher.BuildIndex(ns.Prof.DB(key).book, ns.Prof.ByKey(key))
    end
    local active = ns.db and ns.db.activeProfession
    Events.index = (active and Events.indexes[active])
        or ns.Matcher.BuildIndex(ns.Book(), ns.Prof.Current())
    return Events.index
end

-- Pure. candidates = { { key = <profession>, index = <matcher index> }, ... }
-- in priority order. Returns the candidate with the most matches and its hits;
-- the first candidate with no hits when nothing matches anywhere.
function Events.PickProfession(raw, norm, candidates)
    local best, bestHits = nil, {}
    for _, c in ipairs(candidates) do
        local hits = ns.Matcher.Match(raw, norm, c.index)
        if #hits > #bestHits then best, bestHits = c, hits end
    end
    return best or candidates[1], bestHits
end

-- Active profession first, then every other scanned book. Falls back to the
-- active index alone (a generic, empty one before any scan) so the classifier
-- can still be exercised with /tm try.
local function Candidates()
    if not Events.indexes then Events.RebuildIndex() end
    local list = {}
    local active = ns.db.activeProfession
    if active and Events.indexes[active] then
        list[1] = { key = active, index = Events.indexes[active] }
    end
    for _, key in ipairs(ns.Prof.Known()) do
        if key ~= active and Events.indexes[key] then
            list[#list + 1] = { key = key, index = Events.indexes[key] }
        end
    end
    if #list == 0 then list[1] = { key = nil, index = Events.index } end
    return list
end

local function AnyBookHas(itemID)
    for _, key in ipairs(ns.Prof.Known()) do
        if ns.Prof.DB(key).book[itemID] then return true end
    end
    return false
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
    local candidates = Candidates()

    -- Which book is answering. Set once the request has been matched.
    local pick, profile, book, ps
    local function Use(c)
        pick = c
        local pd = c.key and ns.Prof.DB(c.key)
        profile = c.key and ns.Prof.ByKey(c.key) or ns.Prof.Current()
        book = pd and pd.book or ns.Book()
        ps = pd and pd.settings or ns.PS()
    end

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
    local first, matched = Events.PickProfession(text, norm, candidates)
    Use(first)

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
            local cpick, cm = Events.PickProfession(combined, cnorm, candidates)
            if #cm > 0 then
                Use(cpick)
                matched = cm
                norm = cnorm
                usedContext = true
            end
        end
    end
    -- A Trade post that named a real item is remembered too, not just
    -- whispers: someone posts "LF [Delicate Living Ruby] crafter" in Trade,
    -- then whispers only "delicate" and "all 9". Gated on an actual match so
    -- raid ads and unrelated chat do not fill the buffer. (CutMaster 1.1.0)
    if not opts.dryRun and (isDirect or #matched > 0) then
        ns.Players.PushRecent(state, text, now)
    end

    -- Matches you can't make for lack of a Bind on Pickup reagent are split
    -- off: they still count for classification, but never for inviting.
    local craftable, noMats = {}, {}
    for _, h in ipairs(matched) do
        local e = book[h.itemID]
        local missing = e and ns.Scanner.MissingBoP(e) or {}
        if #missing > 0 then
            noMats[#noMats + 1] = { entry = e, missing = missing, hit = h }
        else
            craftable[#craftable + 1] = h
        end
    end

    local filter = ps.filter
    if isDirect then
        filter = ns.DeepCopy(filter)
        filter.requireBuyerSignal = false
    end

    -- Did they name something specific that no book of ours answers?
    --
    -- Nothing matched, so whatever is in brackets is not ours: an item link, a
    -- recipe link, or a typed-out name, all of them a request for one thing in
    -- particular. Answering that with "what item do you need?" is the reply that
    -- reads as though nobody was listening, and it is worth no invite either.
    local namedUnknownItem = false
    if #matched == 0 then
        namedUnknownItem = #ns.Util.BracketNames(text) > 0
        if not namedUnknownItem and ns.Matcher.NearMiss(norm, pick.index) then
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
            elseif not AnyBookHas(l.id) and IsProductItem(profile, l.id) then
                cannotDo[#cannotDo + 1] = l.link
            end
        end
        if #craftable > 0 then
            for _, nm in ipairs(noMats) do
                cannotDo[#cannotDo + 1] = nm.entry.link or nm.entry.name
            end
        end

        -- A recipe link carries no item id, so the loop above walks straight past
        -- the most specific request there is, which is how two linked recipes got
        -- answered by naming one of them.
        --
        -- Read out of the link rather than out of the raw text: this list is
        -- quoted back to the customer, and every [...] in a message also catches
        -- player names, guild names and asides. "[Malexis] said u can make [X]"
        -- must not answer "but I don't have Malexis".
        local answered = {}
        for _, h in ipairs(matched) do
            local e = book[h.itemID]
            if e and e.name then answered[e.name:lower()] = true end
        end
        for bracket in text:gmatch("|H%a+:.-|h%[(.-)%]|h") do
            -- "Leatherworking: Bindings of Lightning Reflexes" names the same item
            -- as "Bindings of Lightning Reflexes".
            local plain = bracket:gsub("^[^:]+:%s*", "")
            if plain == "" then plain = bracket end
            if plain ~= "" and not answered[bracket:lower()] and not answered[plain:lower()]
                and not ns.Reply.Names(canDo, plain) and not ns.Reply.Names(cannotDo, plain) then
                cannotDo[#cannotDo + 1] = plain
            end
        end
    end

    local blocked
    if not opts.dryRun then
        if isWhisper and not ps.invite.fromWhisper then
            blocked = "whisper invites disabled"
        elseif UnitInParty(short) or UnitInRaid(short) then
            blocked = "already grouped"
        elseif not ns.InvitesOn() then
            blocked = "invites off"
        elseif #matched > 0 and #craftable == 0 then
            blocked = "not enough " .. ns.Scanner.DescribeMissing(noMats[1].missing)
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

    -- Market saturation counts every Trade line, including the ones the log
    -- drops for matching no item: a competitor's bark for another profession
    -- is exactly that case.
    if not opts.dryRun and source == "trade" and ns.Market then
        ns.Market.Observe(ns.db, now, short, text, norm, result, #matched > 0)
    end

    if ns.db.settings.captureAll and not opts.dryRun then
        ns.Log.Capture(short, text, result, now)
    end

    if result.reason ~= "no item match" and not opts.dryRun then
        ns.Log.Add(short, text, matched, result, now, book)
        if ns.db.settings.debug then
            ns.Print(ns.Log.Describe(ns.db.log[1]))
            ns.Print(ns.Log.DescribeHits(ns.db.log[1]))
        end
    end

    if isParty and not opts.dryRun and #matched > 0 then
        state.awaitingItem = nil
    end

    local willInvite = Events.ShouldInvite(result, #craftable, #matched)
    local nounS = profile.craftNoun[1]

    -- Everything they named needs a Bind on Pickup reagent you don't hold.
    -- Tell them, on any channel where an invite would otherwise have gone out.
    if #matched > 0 and #craftable == 0 and not opts.dryRun and result.verdict ~= "vetoed"
        and (isDirect or result.verdict == "invite") then
        local w = ps.invite.whisper
        local items, mats = {}, {}
        for i = 1, math.min(#noMats, 3) do
            local nm = noMats[i]
            items[#items + 1] = nm.entry.link or nm.entry.name
            local missing = ns.Scanner.DescribeMissing(nm.missing)
            if missing ~= "" and not ns.Reply.Names(mats, missing) then
                mats[#mats + 1] = missing
            end
        end
        local itemText = table.concat(items, " ")
        ns.Print(string.format("|cffffcc00%s asked for %s but you lack %s.|r Not invited.",
            short, itemText, ns.Scanner.DescribeMissing(noMats[1].missing, true)))
        if w.enabled and w.autoReply then
            ns.Inviter.Say(short, w.noMatsTemplate,
                { mats = table.concat(mats, ", "), item = itemText }, profile)
        end
        if isDirect and ns.db.settings.orders.captureTranscript then
            ns.Orders.AddTranscript(short, "in", text, now)
        end
        return result
    end

    if isWhisper and not opts.dryRun and result.verdict ~= "vetoed" then
        local w = ps.invite.whisper

        if #matched > 0 then
            -- One composer decides the sentence from what we can cover across
            -- everything they named. Taking matched[1] here is what answered two
            -- linked recipes with one item's name.
            local reply = ns.Reply.Compose({
                book = book,
                -- craftable, not matched: an item we matched but have no reagents
                -- for is already in cannotDo, and offering it and withdrawing it
                -- in one sentence is worse than either.
                matched = craftable,
                cannotDo = cannotDo,
                whisper = w,
                profile = profile,
                player = short,
                base = "reply",
                withPatterns = not ns.Util.HasCraftLink(text),
            })

            if not willInvite and w.enabled and w.autoReply
                and (#cannotDo > 0 or state.awaitingItem) then
                ns.Inviter.SayComposed(short, reply.text, profile)
                if #reply.lack > 0 then
                    ns.Print(string.format(
                        "|cffffcc00%s asked for %d %s, you have %d.|r Cannot do: %s",
                        short, #reply.have + #reply.lack, profile.craftNoun[2],
                        #reply.have, table.concat(reply.lack, " ")))
                end
                if reply.dropped > 0 or reply.lackDropped > 0
                    or reply.patternsDropped > 0 or reply.overLength then
                    ns.Print(string.format(
                        "|cff888888(whisper cap: %d item(s) and %d unknown left unnamed, "
                        .. "%d pattern link(s) left off%s)|r",
                        reply.dropped, reply.lackDropped, reply.patternsDropped,
                        reply.overLength and ", and it still overran" or ""))
                end
            end
            state.awaitingItem = nil

        else
            local asked = ns.Util.IsAvailabilityQuestion(text, norm, ps.filter.askPhrases)
            local mayReply = w.enabled and w.autoReply
                and (w.autoSuggest or (asked and w.answerQuestions))

            local family, ids, exactFamily = ns.Matcher.NearMiss(norm, pick.index)
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
                ns.Inviter.Say(short, w.askWhichTemplate, { items = table.concat(show, " ") }, profile)
                ns.Print(string.format(
                    "|cffffcc00%s typed a partial %s name.|r Asked which of: %s",
                    short, nounS, table.concat(show, " ")))
                result.reason = "asked which " .. nounS
                ns.Log.Add(short, text, matched, result, now, book)
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
                ns.Log.Add(short, text, matched, result, now, book)

                if mayReply then
                    if w.autoSuggest and #links > 0 then
                        while #links > 3 do table.remove(links) end
                        ns.Inviter.Say(short, w.suggestTemplate, { items = table.concat(links, " ") }, profile)
                    else
                        ns.Inviter.Say(short, w.noneTemplate, {}, profile)
                    end
                end
            else
                -- Last resort: a bare prefix with none of its base words
                -- ("looking for jagged..."). Genuinely ambiguous, so this is
                -- local only; guessing which one to whisper about would be
                -- worse than staying quiet. (CutMaster 1.1.0)
                local prefixWord, prefixIDs = ns.Matcher.PrefixNearMiss(norm, pick.index)
                if prefixWord then
                    local pl = {}
                    for _, id in ipairs(prefixIDs) do
                        local b = book[id]
                        if b and (b.link or b.name) then pl[#pl + 1] = b.link or b.name end
                    end
                    if #pl > 0 then
                        ns.Print(string.format(
                            "|cffffcc00%s mentioned \"%s\", could be:|r %s",
                            short, prefixWord, table.concat(pl, " ")))
                        result.reason = "ambiguous prefix"
                        ns.Log.Add(short, text, matched, result, now, book)
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
        if wanted and Events.ShouldOpenOrder(result, #craftable, #matched, isDirect) then
            if usedContext then
                ns.Print(string.format("|cff888888(matched %s using their previous message)|r", short))
            end
            ns.Orders.Record(short, source, text, craftable, now, profile.key)
        end
        if isDirect and o.captureTranscript then
            ns.Orders.AddTranscript(short, "in", text, now)
        end
    end

    if willInvite and not opts.dryRun then
        local ctx = { cannotDo = cannotDo, profession = profile.key, text = text }
        -- "LF LW" on its own is answered at once: asking what they need is exactly
        -- right when they named nothing. A line carrying a specific we could not
        -- place gets read by a person first, because asking the same question
        -- there says we were not listening.
        local leftover = ns.Confirm.Leftover(norm, ns.Confirm.Phrases(profile, ps.filter))
        local understood = ns.Confirm.Understood(#craftable, leftover)
        if ns.Confirm.Required(ps.invite.confirm, understood) then
            ns.Confirm.Ask({
                player = short, source = source, text = text, leftover = leftover,
                matched = craftable, cannotDo = cannotDo, profession = profile.key,
            })
        else
            ns.Inviter.Invite(short, craftable, ctx)
        end
    end

    return result
end

-- Pure. Invite when the content says customer, nothing operational blocks it, and
-- either we can make what they named or they named nothing at all. A bare "LF JC"
-- is a customer standing at the door: Inviter has a no-item whisper for exactly
-- that case, and requiring an item made it unreachable.
function Events.ShouldInvite(result, craftableCount, matchedCount)
    if result.verdict ~= "invite" or result.blocked then return false end
    return craftableCount > 0 or matchedCount == 0
end

-- Pure. Open an order for anything worth an invite, and also for a direct request
-- that named nothing. The customer who whispers "any JC on?" and then hands over
-- mats is the case Dezedin reported: with no order, the mats have nothing to fill
-- in and the trade cannot auto-fill on the way back.
function Events.ShouldOpenOrder(result, craftableCount, matchedCount, isDirect)
    if result.verdict ~= "invite" then return false end
    return craftableCount > 0 or (isDirect and matchedCount == 0)
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
