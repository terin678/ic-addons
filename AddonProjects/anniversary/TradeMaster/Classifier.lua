local addonName, ns = ...

ns.Classifier = ns.Classifier or {}
local Classifier = ns.Classifier
local Util = ns.Util

local MANY_LINKS = 3
local GUARDED_CAN_CRAFT_WEIGHT = 3
local QUESTION_WEIGHT = 1

-- "can cut" is a seller phrase in "I can cut that" but a buyer phrase in
-- "anyone who can cut this?". Look back two tokens to tell them apart. The
-- verb comes from the profession (cut, brew, craft, ...).
local function CanCraftIsGuarded(norm, verb, guards)
    local toks = Util.Tokenize(norm)
    for i = 1, #toks - 1 do
        if toks[i] == "can" and toks[i + 1] == verb then
            for back = 1, 2 do
                local w = toks[i - back]
                if w then
                    for _, g in ipairs(guards) do
                        if w == g then return true end
                    end
                end
            end
        end
    end
    return false
end

function Classifier.Evaluate(ctx)
    local filter = ctx.filter
    local result = {
        sellerScore = 0, sellerHits = {},
        buyerScore = 0, buyerHits = {},
        netScore = 0,
    }

    local function seller(key, weight)
        result.sellerScore = result.sellerScore + weight
        result.sellerHits[key] = weight
    end

    local function buyer(key, weight)
        result.buyerScore = result.buyerScore + weight
        result.buyerHits[key] = weight
    end

    -- Operational state ("invites off", "cooldown", "group full") is recorded
    -- but must NOT decide the content verdict.
    result.blocked = ctx.blocked

    -- Someone asking for the profession without naming an item ("LF JC",
    -- "any alchemist online?") is a customer too.
    local isProfReq = false
    for _, phrase in ipairs(filter.professionWords or {}) do
        if Util.HasPhrase(ctx.norm, phrase) then
            isProfReq = true
            break
        end
    end
    result.professionRequest = isProfReq

    local nothingMatched = (not ctx.matched or #ctx.matched == 0)

    -- "LF JC with [Veiled Pyrestone]" is a request for one specific item. If it
    -- is not ours, the profession phrase must not carry it.
    if isProfReq and nothingMatched and ctx.namedUnknownItem then
        result.verdict = "lowscore"
        result.reason = "named an item we lack"
        return result
    end

    if nothingMatched and not isProfReq then
        result.verdict = "lowscore"
        result.reason = "no item match"
        return result
    end

    for phrase, weight in pairs(filter.sellerWords) do
        if Util.HasPhrase(ctx.norm, phrase) then seller(phrase, weight) end
    end

    local guards = filter.canCraftGuards or filter.canCutGuards or {}
    local canWeight = (filter.weights and (filter.weights.canCraft or filter.weights.canCut)) or 4
    for _, verb in ipairs(filter.craftVerbs or { "craft" }) do
        if Util.HasPhrase(ctx.norm, "can " .. verb) then
            if CanCraftIsGuarded(ctx.norm, verb, guards) then
                buyer("can " .. verb .. " (guarded)", GUARDED_CAN_CRAFT_WEIGHT)
            else
                seller("can " .. verb, canWeight)
            end
        end
    end

    -- Vocabulary-free signals describe a BROADCAST. Whispers and party chat
    -- are directed at us, so there they invert.
    local hasQuestion = ctx.raw and ctx.raw:find("?", 1, true) ~= nil

    if not ctx.isDirect then
        if (ctx.linkCount or 0) >= MANY_LINKS then
            seller("manyLinks", filter.weights.manyLinks)
        end
        if ctx.isRepeat then
            seller("repeatBark", filter.weights.repeatBark)
        end
        if (ctx.linkCount or 0) >= 2 and not hasQuestion and result.sellerScore > 0 then
            seller("shapeMatch", filter.weights.shapeMatch)
        end
    end

    if ctx.hasRecipeLink then
        seller("recipeLink", filter.weights.recipeLink or filter.weights.designLink or 4)
    end

    for phrase, weight in pairs(filter.buyerWords) do
        if Util.HasPhrase(ctx.norm, phrase) then buyer(phrase, weight) end
    end

    -- A recognised profession request ("LF leatherworker", "any alch around") is
    -- itself the ask, whether or not its exact wording also happens to be a
    -- buyerWords phrase. Without this, "LF jewelcrafter" as against "lf jc"
    -- scored no buyer signal at all and requireBuyerSignal dropped it, even with
    -- isProfReq already true. (CutMaster 1.2.0)
    if isProfReq then buyer("professionRequest", 1) end

    if hasQuestion then buyer("question", QUESTION_WEIGHT) end

    -- Content vetoes are applied after scoring so the log still shows which
    -- signals were present, rather than an unexplained rejection.
    if ctx.playerState and ctx.playerState.neverInvite then
        result.verdict = "vetoed"
        result.reason = "never invite"
        return result
    end

    if ctx.playerState and ctx.playerState.flaggedSeller then
        result.verdict = "vetoed"
        result.reason = "flagged seller"
        return result
    end

    -- They asked for a specialization this character does not hold. It is a
    -- customer, just not ours: no invite, no order, no reply. Scored first so the
    -- log still shows they looked like a buyer.
    if ctx.wrongSpec then
        result.verdict = "vetoed"
        result.reason = "wants a " .. ctx.wrongSpec
        return result
    end

    for _, word in ipairs(filter.vetoWords) do
        if Util.HasPhrase(ctx.norm, word) then
            result.verdict = "vetoed"
            result.reason = word
            return result
        end
    end

    -- Net, not raw. A raw seller threshold would make buyer evidence
    -- decorative and any heavy signal an unconditional block.
    result.netScore = result.sellerScore - result.buyerScore

    if result.netScore >= filter.netThreshold then
        result.verdict = "lowscore"
        result.reason = "seller score"
        return result
    end

    if filter.requireBuyerSignal and result.buyerScore < 1 then
        result.verdict = "lowscore"
        result.reason = "no buyer signal"
        return result
    end

    result.verdict = "invite"
    if isProfReq and (not ctx.matched or #ctx.matched == 0) then
        result.reason = "profession request"
    else
        result.reason = "matched"
    end
    return result
end
