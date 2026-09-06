local addonName, ns = ...

ns.Events = ns.Events or {}
local Events = ns.Events

--[[
A line of chat comes in; something happens back. This file is that in two halves:

    Events.Decide(line, ctx) -> plan     pure: reads, never writes
    Events.Act(plan)                     the effects, in one fixed order

Decide reads the line, the books, the settings and the player's memory, classifies it,
and returns a plan: the verdict, and for every effect the addon could take -- remember,
log, open an order, whisper, invite, ask first -- whether it will, and when it will not,
why. Act performs the plan. Nothing in Decide touches a frame, a timer, the saved tables
or chat, so a plan can be built for a made-up line in a test and read in full; /tm try
prints one, which is how a dry run and the live path can never disagree.

The channel is looked up once, in POLICY. Before this split "what may we do back on this
channel" was answered at four separate places, and one of them answered differently.
]]

-- How far back to look when stitching together a fragmented request.
local CONTEXT_WINDOW = 90

-- A message this short naming a family is a fragment, not conversation.
local FRAGMENT_WORDS = 5

--[[
One policy per channel, and the only place a channel name is compared.

    requireBuyerSignal  a matched item is not enough on its own; the line has to ask
    stitch              a line naming nothing is read with what they said just before
    observeRepeats      the same advertisement twice inside the window flags a seller
    market              the line counts toward Trade saturation
    remember            "always" keeps every line for stitching; "matched" only a hit
    transcript          the line goes on the order's transcript
    orderSetting        the settings.orders key that switches order-opening here
                        (autoFromTrade is the trade WINDOW's switch, Trade.lua, not this)
    inviteGate          a per-profession invite setting that can refuse this channel
    replies             which of the whispers back may go: noMats, reply, askWhich,
                        suggest, none, drop. A channel with none of them is never
                        replied to; it gets an invite, with the invite's own line, or
                        nothing.
]]
Events.POLICY = {
    trade = {
        label = "Trade", requireBuyerSignal = true, stitch = false, observeRepeats = true,
        market = true, remember = "matched", transcript = false, orderSetting = "autoFromInvite",
        replies = {},
    },
    whisper = {
        label = "a whisper", requireBuyerSignal = false, stitch = true, observeRepeats = false,
        market = false, remember = "always", transcript = true, orderSetting = "autoFromWhisper",
        inviteGate = "fromWhisper",
        replies = { noMats = true, reply = true, askWhich = true, suggest = true, none = true, drop = true },
    },
    party = {
        label = "party chat", requireBuyerSignal = false, stitch = true, observeRepeats = false,
        market = false, remember = "always", transcript = true, orderSetting = "autoFromParty",
        replies = { noMats = true },
    },
}

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

-- Pure. candidates = { { key, index, book, profile, settings }, ... } in priority
-- order. Returns the candidate with the most matches and its hits; the first
-- candidate with no hits when nothing matches anywhere.
function Events.PickProfession(raw, norm, candidates)
    local best, bestHits = nil, {}
    for _, c in ipairs(candidates) do
        local hits = ns.Matcher.Match(raw, norm, c.index)
        if #hits > #bestHits then best, bestHits = c, hits end
    end
    return best or candidates[1], bestHits
end

-- Active profession first, then every other scanned book, each carrying its book,
-- profile and settings so Decide never has to look them up. Falls back to the
-- active index alone (a generic, empty one before any scan) so the classifier
-- can still be exercised with /tm try.
local function Candidates()
    if not Events.indexes then Events.RebuildIndex() end
    local list = {}
    local function add(key)
        local pd = ns.Prof.DB(key)
        list[#list + 1] = {
            key = key, index = Events.indexes[key],
            book = pd.book, profile = ns.Prof.ByKey(key), settings = pd.settings,
        }
    end
    local active = ns.db.activeProfession
    if active and Events.indexes[active] then add(active) end
    for _, key in ipairs(ns.Prof.Known()) do
        if key ~= active and Events.indexes[key] then add(key) end
    end
    if #list == 0 then
        list[1] = { key = nil, index = Events.index, book = ns.Book(),
                    profile = ns.Prof.Current(), settings = ns.PS() }
    end
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

--------------------------------------------------------------------------------
-- Decide
--------------------------------------------------------------------------------

--[[
line = { text, short, source }. ctx = { candidates, now, state, settings, inGroup,
groupSize, invitesOn }; `state` is the player's record and is only read.

Returns the plan:

    result          Classifier.Evaluate's table, with source and profession
    profile, book, matched, craftable, noMats, canDo, cannotDo, usedContext, norm
    blocked         the operational reason, if any; computed for a dry run too
    actions         observe = { isRepeat }, pushRecent, market, capture, log,
                    clearAwaiting, transcript, order, decline = { names }, drop,
                    whisper = { kind, template, vars } or { kind, text }, confirm =
                    { leftover }, invite
    why             for each action not taken, the reason, by name
    prints          the lines for the user's own chat
]]
function Events.Decide(line, ctx)
    local text, short, source = line.text, line.short, line.source
    local P = Events.POLICY[source] or Events.POLICY.trade
    local isDirect = source ~= "trade"
    local isWhisper = source == "whisper"
    local state = ctx.state or {}
    local now = ctx.now
    local settings = ctx.settings
    local candidates = ctx.candidates

    local pick, profile, book, ps
    local function Use(c)
        pick, profile, book, ps = c, c.profile, c.book, c.settings
    end

    local norm = ns.Util.Normalize(text)
    local first, matched = Events.PickProfession(text, norm, candidates)
    Use(first)

    local plan = { source = source, short = short, text = text, actions = {}, why = {}, prints = {} }
    local A, why = plan.actions, plan.why
    local function say(fmt, ...) plan.prints[#plan.prints + 1] = string.format(fmt, ...) end

    -- The same advertisement again inside the window. Trade only: a whisper is not
    -- a broadcast.
    local isRepeat = false
    if P.observeRepeats and #matched > 0 then
        isRepeat = ns.Players.Repeat(state, norm, now, ps.filter.repeatWindowSec)
        A.observe = { isRepeat = isRepeat }
    end

    -- Fragmented requests across two messages: "Shifting Shadowsong?" then "Amethyst".
    local usedContext, contextText = false, nil
    if P.stitch and #matched == 0 then
        local combined = ns.Players.RecentText(state, now, CONTEXT_WINDOW)
        if combined ~= "" then
            combined = combined .. " " .. text
            local cnorm = ns.Util.Normalize(combined)
            local cpick, cm = Events.PickProfession(combined, cnorm, candidates)
            if #cm > 0 then
                Use(cpick)
                matched = cm
                norm = cnorm
                contextText = combined
                usedContext = true
            end
        end
    end
    -- A Trade post that named a real item is remembered too, not just whispers: someone
    -- posts "LF [Delicate Living Ruby] crafter" in Trade, then whispers only "delicate"
    -- and "all 9". Gated on a match so raid ads do not fill the buffer. (CutMaster 1.1.0)
    A.pushRecent = (P.remember == "always") or #matched > 0

    -- Matches you can't make for lack of a Bind on Pickup reagent are split off: they
    -- still count for classification, but never for inviting.
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
    if not P.requireBuyerSignal then
        filter = ns.DeepCopy(filter)
        filter.requireBuyerSignal = false
    end

    -- Did they name something specific that no book of ours answers? Nothing matched,
    -- so whatever is in brackets is not ours: a request for one thing in particular.
    -- "What item do you need?" is the reply that reads as though nobody was listening.
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

        -- A recipe link carries no item id, so the loop above walks straight past the
        -- most specific request there is. Read out of the link rather than the raw
        -- text: every [...] in a message also catches player names and asides, and
        -- "[Malexis] said u can make [X]" must not answer "but I don't have Malexis".
        local answered = {}
        for _, h in ipairs(matched) do
            local e = book[h.itemID]
            if e and e.name then answered[e.name:lower()] = true end
        end
        for bracket in text:gmatch("|H%a+:.-|h%[(.-)%]|h") do
            local plain = bracket:gsub("^[^:]+:%s*", "")
            if plain == "" then plain = bracket end
            if plain ~= "" and not answered[bracket:lower()] and not answered[plain:lower()]
                and not ns.Reply.Names(canDo, plain) and not ns.Reply.Names(cannotDo, plain) then
                cannotDo[#cannotDo + 1] = plain
            end
        end
    end

    -- Operational state. Computed for a dry run as well, so /tm try says what the live
    -- path would have refused and why, rather than an invite it would not have sent.
    local blocked
    if P.inviteGate and not ps.invite[P.inviteGate] then
        blocked = "whisper invites disabled"
    elseif ctx.inGroup then
        blocked = "already grouped"
    elseif not ctx.invitesOn then
        blocked = "invites off"
    elseif ns.Players.WasDeclined(state, norm, ns.Util.BracketNames(text)) then
        blocked = "already told them no"
    elseif #matched > 0 and #craftable == 0 then
        blocked = "not enough " .. ns.Scanner.DescribeMissing(noMats[1].missing)
    else
        blocked = ns.Inviter.BlockReason(state, now, ctx.groupSize or 0, ps.invite)
    end

    -- A request for a specialization we do not hold, read off the line with everything
    -- they named cut out, so an item whose name carries a specialization word is still
    -- an ordinary request for that item.
    local wrongSpec
    if pick.key then
        local have, specSource = ns.Prof.SpecSet(pick.key)
        if specSource ~= "off" then
            local names = {}
            for _, h in ipairs(matched) do
                local e = book[h.itemID]
                if e and e.name then names[#names + 1] = e.name end
            end
            wrongSpec = ns.Prof.SpecWanted(profile, contextText or text, have, names)
        end
    end

    -- The player as the classifier should see them: a repeat this very line flags them.
    local view = { flaggedSeller = state.flaggedSeller or isRepeat, neverInvite = state.neverInvite }

    local result = ns.Classifier.Evaluate({
        norm = norm,
        raw = text,
        wrongSpec = wrongSpec,
        matched = matched,
        materialsOnly = ns.Classifier.MaterialsOnly(matched, book, profile),
        linkCount = #ns.Util.ExtractItemIDs(text),
        hasRecipeLink = HasRecipeLink(text, profile),
        namedUnknownItem = namedUnknownItem,
        isRepeat = isRepeat,
        isDirect = isDirect,
        playerState = view,
        blocked = blocked,
        filter = filter,
    })
    result.source = source
    result.profession = profile.key

    plan.result, plan.profile, plan.book, plan.norm = result, profile, book, norm
    plan.matched, plan.craftable, plan.noMats = matched, craftable, noMats
    plan.canDo, plan.cannotDo, plan.usedContext, plan.blocked = canDo, cannotDo, usedContext, blocked
    plan.settings = ps

    A.market = P.market
    A.capture = settings.captureAll and true or false
    A.log = result.reason ~= "no item match"
    if isDirect and #matched > 0 then A.clearAwaiting = true end

    local willInvite = Events.ShouldInvite(result, #craftable, #matched)
    local nounS = profile.craftNoun[1]
    local w = ps.invite.whisper

    -- One place decides whether a whisper goes back. The channel first, then the
    -- switches; the reason it did not is kept for the plan.
    local function Whisper(kind, template, vars, composed)
        if not P.replies[kind] then
            why.whisper = "a " .. kind .. " reply does not go to " .. P.label
            return
        end
        if not (w.enabled and w.autoReply) then
            why.whisper = "auto replies are off"
            return
        end
        A.whisper = { kind = kind, template = template, vars = vars, text = composed }
    end

    -- Everything they named needs a Bind on Pickup reagent you don't hold. No invite, a
    -- line in your own chat saying why, and a whisper only where the channel allows one.
    if #matched > 0 and #craftable == 0 and result.verdict ~= "vetoed"
        and (isDirect or result.verdict == "invite") then
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
        say("|cffffcc00%s asked for %s but you lack %s.|r Not invited.",
            short, itemText, ns.Scanner.DescribeMissing(noMats[1].missing, true))
        Whisper("noMats", w.noMatsTemplate, { mats = table.concat(mats, ", "), item = itemText })
        A.transcript = P.transcript and settings.orders.captureTranscript or false
        why.invite, why.order = "not enough mats", "not enough mats"
        return plan
    end

    -- The conversation: only a channel that allows replies has one.
    if P.replies.reply and result.verdict ~= "vetoed" then
        if #matched > 0 then
            -- One composer decides the sentence from what we can cover across everything
            -- they named; matched[1] alone is what answered two recipes with one name.
            -- craftable, not matched: an item we lack reagents for is already in cannotDo.
            local reply = ns.Reply.Compose({
                book = book, matched = craftable, cannotDo = cannotDo, whisper = w,
                profile = profile, player = short, base = "reply",
                withPatterns = not ns.Util.HasCraftLink(text),
            })
            plan.reply = reply
            if not willInvite and (#cannotDo > 0 or state.awaitingItem) then
                Whisper("reply", nil, nil, reply.text)
                if #reply.lack > 0 then
                    say("|cffffcc00%s asked for %d %s, you have %d.|r Cannot do: %s",
                        short, #reply.have + #reply.lack, profile.craftNoun[2],
                        #reply.have, table.concat(reply.lack, " "))
                end
                if reply.dropped > 0 or reply.lackDropped > 0
                    or reply.patternsDropped > 0 or reply.overLength then
                    say("|cff888888(whisper cap: %d item(s) and %d unknown left unnamed, "
                        .. "%d pattern link(s) left off%s)|r",
                        reply.dropped, reply.lackDropped, reply.patternsDropped,
                        reply.overLength and ", and it still overran" or "")
                end
            elseif willInvite then
                why.whisper = "the invite carries its own line"
            else
                why.whisper = "nothing to say: everything they named is covered"
            end
            A.clearAwaiting = true
        else
            local asked = ns.Util.IsAvailabilityQuestion(text, norm, ps.filter.askPhrases)
            -- We asked what they needed and this is the answer. Saying nothing to that is
            -- the one reply that is always wrong: they are in the group waiting for one.
            local answering = state.awaitingItem and true or false
            local mayReply = w.enabled and w.autoReply
                and (w.autoSuggest or answering or (asked and w.answerQuestions))

            local family, ids, exactFamily = ns.Matcher.NearMiss(norm, pick.index)
            local links = {}
            for _, id in ipairs(ids or {}) do
                local b = book[id]
                if b and (b.link or b.name) then links[#links + 1] = b.link or b.name end
            end
            local fragment = family and not exactFamily and #links > 0
                and (asked or #ns.Util.Tokenize(norm) <= FRAGMENT_WORDS)

            if fragment then
                local show = {}
                for i = 1, math.min(3, #links) do show[i] = links[i] end
                Whisper("askWhich", w.askWhichTemplate, { items = table.concat(show, " ") })
                say("|cffffcc00%s typed a partial %s name.|r Asked which of: %s",
                    short, nounS, table.concat(show, " "))
                result.reason = "asked which " .. nounS
                A.log = true
                why.invite, why.order = "asked which", "asked which"
                return plan
            end

            if #links > 0 or ((asked or answering) and namedUnknownItem) then
                if #links > 0 then
                    say("|cffffcc00%s asked about a %s you do not know.|r You can do: %s",
                        short, nounS, table.concat(links, " "))
                else
                    say("|cffffcc00%s asked for a %s you do not have.|r", short, nounS)
                end
                result.reason = "unknown " .. nounS
                A.log = true

                if mayReply then
                    if w.autoSuggest and #links > 0 then
                        while #links > 3 do table.remove(links) end
                        Whisper("suggest", w.suggestTemplate, { items = table.concat(links, " ") })
                    else
                        Whisper("none", w.noneTemplate, {})
                    end
                else
                    why.whisper = "auto suggest is off and this was not a question"
                end

                if answering and #links == 0 then
                    -- Nothing we can offer: remember the answer and give the group slot
                    -- back. A repost is then blocked rather than invited again.
                    A.decline = { names = ns.Util.BracketNames(text) }
                    A.declineHours = math.floor((ps.invite.declinedCooldownSec or 86400) / 3600)
                    A.drop = P.replies.drop and ps.invite.dropOnNoMatch ~= false or false
                end
                A.clearAwaiting = true
            else
                -- Last resort: a bare prefix with none of its base words ("looking for
                -- jagged..."). Genuinely ambiguous, so this is local only. (CutMaster 1.1.0)
                local prefixWord, prefixIDs = ns.Matcher.PrefixNearMiss(norm, pick.index)
                if prefixWord then
                    local pl = {}
                    for _, id in ipairs(prefixIDs) do
                        local b = book[id]
                        if b and (b.link or b.name) then pl[#pl + 1] = b.link or b.name end
                    end
                    if #pl > 0 then
                        say("|cffffcc00%s mentioned \"%s\", could be:|r %s",
                            short, prefixWord, table.concat(pl, " "))
                        result.reason = "ambiguous prefix"
                        A.log = true
                    end
                end
            end
        end
    elseif not P.replies.reply then
        why.whisper = "no reply goes to " .. P.label
    end

    -- The order.
    if not settings.orders[P.orderSetting] then
        why.order = P.orderSetting .. " is off"
    elseif not Events.ShouldOpenOrder(result, #craftable, #matched, isDirect) then
        why.order = result.verdict ~= "invite" and ("verdict " .. result.verdict) or "nothing we can make"
    else
        A.order = true
    end
    A.transcript = P.transcript and settings.orders.captureTranscript or false

    -- The invite, or the question first. "LF LW" on its own is answered at once; a line
    -- carrying a specific we could not place gets read by a person first, because asking
    -- the same question there says we were not listening.
    if willInvite then
        local leftover = ns.Confirm.Leftover(norm, ns.Confirm.Phrases(profile, ps.filter))
        local understood = ns.Confirm.Understood(#craftable, leftover)
        if ns.Confirm.Required(ps.invite.confirm, understood) then
            A.confirm = { leftover = leftover }
            why.invite = "asking you first"
        else
            A.invite = true
        end
    elseif result.blocked then
        why.invite = result.blocked
    elseif result.verdict ~= "invite" then
        why.invite = string.format("verdict %s: %s", result.verdict, tostring(result.reason))
    else
        why.invite = "nothing we can make"
    end

    return plan
end

--------------------------------------------------------------------------------
-- Act
--------------------------------------------------------------------------------

-- The effects of a plan, in one fixed order: memory, market, log, the user's own chat,
-- transcript, order, decline, then the invite or the question, then the whisper. Each
-- effect exists here once. A dry run never reaches this.
function Events.Act(plan)
    local A, short, now = plan.actions, plan.short, ns.Now()
    local state = ns.Players.Get(ns.db, short)
    local ctx = { cannotDo = plan.cannotDo, profession = plan.profile.key, text = plan.text }

    if A.observe then ns.Players.Note(state, plan.norm, now, A.observe.isRepeat) end
    if A.pushRecent then ns.Players.PushRecent(state, plan.text, now) end
    if A.market and ns.Market then
        ns.Market.Observe(ns.db, now, short, plan.text, plan.norm, plan.result, #plan.matched > 0)
    end
    if A.capture then ns.Log.Capture(short, plan.text, plan.result, now) end
    if A.log then
        ns.Log.Add(short, plan.text, plan.matched, plan.result, now, plan.book)
        if ns.db.settings.debug then
            ns.Print(ns.Log.Describe(ns.db.log[1]))
            ns.Print(ns.Log.DescribeHits(ns.db.log[1]))
        end
    end
    for _, line in ipairs(plan.prints) do ns.Print(line) end
    if A.clearAwaiting then state.awaitingItem = nil end
    if A.transcript then ns.Orders.AddTranscript(short, "in", plan.text, now) end
    if A.order then
        if plan.usedContext then
            ns.Print(string.format("|cff888888(matched %s using their previous message)|r", short))
        end
        ns.Orders.Record(short, plan.source, plan.text, plan.craftable, now, plan.profile.key)
    end
    if A.decline then
        ns.Players.Decline(state, plan.norm, A.decline.names, now)
        if A.drop and ns.Inviter.Drop(short) then
            ns.Print(string.format("|cff888888removed %s from the group.|r "
                .. "No invites for %dh; Clear Flags on the Log tab undoes it.", short, A.declineHours))
        else
            ns.Print(string.format("|cff888888%s asked for something you do not "
                .. "have.|r No invites for %dh.", short, A.declineHours))
        end
    end
    if A.confirm then
        ns.Confirm.Ask({
            player = short, source = plan.source, text = plan.text, leftover = A.confirm.leftover,
            matched = plan.craftable, cannotDo = plan.cannotDo, profession = plan.profile.key,
        })
    elseif A.invite then
        ns.Inviter.Invite(short, plan.craftable, ctx)
    end
    if A.whisper then
        if A.whisper.text then
            ns.Inviter.SayComposed(short, A.whisper.text, plan.profile)
        else
            ns.Inviter.Say(short, A.whisper.template, A.whisper.vars, plan.profile)
        end
    end
end

-- Pure. The plan as lines for chat: the verdict, then each effect, yes or the reason
-- it is no. What /tm try prints.
function Events.Describe(plan)
    local A, why, r = plan.actions, plan.why, plan.result
    local function yn(on, key)
        if on then return "|cff44ff44yes|r" end
        return "|cff888888no|r" .. (why[key] and (" (" .. why[key] .. ")") or "")
    end
    local whisper = A.whisper and ("|cff44ff44yes|r (" .. A.whisper.kind .. ")") or yn(false, "whisper")
    local lines = {
        string.format("%s from %s: verdict |cffffffff%s|r (%s), seller %d buyer %d net %d%s",
            plan.source, plan.short, r.verdict, tostring(r.reason),
            r.sellerScore or 0, r.buyerScore or 0, r.netScore or 0,
            plan.blocked and ("  blocked: " .. plan.blocked) or ""),
        string.format("  invite %s   order %s   whisper %s",
            A.confirm and "|cffffcc00ask me first|r" or yn(A.invite, "invite"),
            yn(A.order, "order"), whisper),
        string.format("  log %s   transcript %s   remember %s%s",
            A.log and "yes" or "no", A.transcript and "yes" or "no", A.pushRecent and "yes" or "no",
            A.observe and A.observe.isRepeat and "   |cffffcc00repeat|r" or ""),
    }
    for _, line in ipairs(plan.prints) do lines[#lines + 1] = "  " .. line end
    return lines
end

--------------------------------------------------------------------------------
-- Process: read the client, decide, act
--------------------------------------------------------------------------------

-- source is "trade", "whisper" or "party". opts.dryRun builds the plan and returns
-- it without acting; /tm try prints it.
function Events.Process(text, author, source, opts)
    opts = opts or {}
    if not ns.db then return end

    local short = (author or ""):gsub("%-.*", "")
    if short == "" then return end

    -- Master switch. /tm try still works so the classifier can be tested while the
    -- addon is otherwise silent. Our own barks are not input.
    if not opts.dryRun and not ns.Enabled() then return end
    if not opts.dryRun and short == UnitName("player") then return end

    -- A dry run reads the real record too, so its plan is the live one; it just never
    -- creates one for a name that has none.
    local state = opts.dryRun and ((ns.db.players or {})[short] or {}) or ns.Players.Get(ns.db, short)

    local plan = Events.Decide({ text = text, short = short, source = source }, {
        candidates = Candidates(),
        now = ns.Now(),
        state = state,
        settings = ns.db.settings,
        inGroup = (UnitInParty(short) or UnitInRaid(short)) and true or false,
        groupSize = GetNumGroupMembers() or 0,
        invitesOn = ns.InvitesOn(),
    })
    plan.result.plan = plan

    if not opts.dryRun then Events.Act(plan) end
    return plan.result
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
