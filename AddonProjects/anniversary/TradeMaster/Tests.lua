local addonName, ns = ...

ns.Tests = ns.Tests or {}
local T = ns.Tests
T.cases = {}

function T.Case(name, fn)
    T.cases[#T.cases + 1] = { name = name, fn = fn }
end

function T.Eq(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected [%s], got [%s]",
            tostring(label or "value"), tostring(expected), tostring(actual)), 2)
    end
end

function T.Run()
    local pass, fail = 0, 0
    -- Written to SavedVariables so failures can be read off disk after a /reload.
    ns.db.lastTestRun = { at = ns.Now(), failures = {} }

    for _, c in ipairs(T.cases) do
        local ok, err = pcall(c.fn)
        if ok then
            pass = pass + 1
        else
            fail = fail + 1
            ns.Print("|cffff4444FAIL|r " .. c.name .. " => " .. tostring(err))
            local f = ns.db.lastTestRun.failures
            f[#f + 1] = { name = c.name, err = tostring(err) }
        end
    end
    ns.db.lastTestRun.passed = pass
    ns.db.lastTestRun.failed = fail
    ns.Print(string.format("Tests: |cff44ff44%d passed|r, %s%d failed|r",
        pass, fail > 0 and "|cffff4444" or "|cff44ff44", fail))
    return pass, fail
end

--------------------------------------------------------------------------------
-- Fixtures
--------------------------------------------------------------------------------

local function link(itemID, name)
    return "|cffa335ee|Hitem:" .. itemID .. ":0:0:0:0:0:0:0|h[" .. name .. "]|h|r"
end

local RUBY_LINK = link(24033, "Bold Living Ruby")
local RUNED_LINK = link(24048, "Runed Living Ruby")
local DRAENITE_LINK = link(23096, "Great Golden Draenite")
local HASTE_LINK = link(22838, "Haste Potion")

local JC = ns.Prof.ByKey("jewelcrafting")
local ALCH = ns.Prof.ByKey("alchemy")

local function jcBook()
    return {
        [24033] = { itemID = 24033, name = "Bold Living Ruby", classID = 3, bindType = 0, match = true, aliases = {} },
        [24048] = { itemID = 24048, name = "Runed Living Ruby", classID = 3, bindType = 0, match = true, aliases = {} },
        [24028] = { itemID = 24028, name = "Solid Star of Elune", classID = 3, bindType = 0, match = true, aliases = {} },
        [23096] = { itemID = 23096, name = "Great Golden Draenite", classID = 3, bindType = 0, match = true, aliases = {} },
        [99999] = { itemID = 99999, name = "Hidden Cut Gem", classID = 3, bindType = 0, match = false, aliases = {} },
    }
end

local function alchBook()
    return {
        [22838] = { itemID = 22838, name = "Haste Potion", classID = 0, bindType = 0, match = true, aliases = {},
                    reagents = { [22789] = 2, [22791] = 1, [18256] = 1 }, numMade = 1 },
        [22832] = { itemID = 22832, name = "Super Mana Potion", classID = 0, bindType = 0, match = true, aliases = {},
                    reagents = { [22786] = 2, [22785] = 1, [18256] = 1 }, numMade = 1 },
        [22841] = { itemID = 22841, name = "Major Fire Protection Potion", classID = 0, bindType = 0, match = true, aliases = {},
                    reagents = { [21884] = 1, [22793] = 3, [18256] = 5 }, numMade = 5 },
        [22829] = { itemID = 22829, name = "Super Healing Potion", classID = 0, bindType = 0, match = true, aliases = {},
                    reagents = { [22791] = 2, [22785] = 1, [18256] = 1 }, numMade = 1 },
    }
end

local function scannedEntry(itemID, name, header)
    return {
        itemID = itemID, name = name, header = header or "Red",
        link = link(itemID, name), classID = 3, reagents = { [23436] = 1 },
    }
end

local function matchIDs(text, book, profile)
    local index = ns.Matcher.BuildIndex(book or jcBook(), profile or JC)
    local hits = ns.Matcher.Match(text, ns.Util.Normalize(text), index)
    local ids = {}
    for _, h in ipairs(hits) do ids[h.itemID] = h.tier end
    return ids, hits
end

local function filterFor(profile)
    return ns.DeepCopy(ns.Prof.DefaultSettings(profile).filter)
end

local function classify(text, over)
    over = over or {}
    local profile = over.profile or JC
    local index = ns.Matcher.BuildIndex(over.book or (profile == ALCH and alchBook() or jcBook()), profile)
    local norm = ns.Util.Normalize(text)
    local filter = over.filter or filterFor(profile)
    if over.isDirect then filter.requireBuyerSignal = false end
    return ns.Classifier.Evaluate({
        norm = norm,
        raw = text,
        matched = ns.Matcher.Match(text, norm, index),
        linkCount = #ns.Util.ExtractItemIDs(text),
        hasRecipeLink = over.hasRecipeLink or false,
        namedUnknownItem = over.namedUnknownItem or false,
        wrongSpec = over.wrongSpec,
        isRepeat = over.isRepeat or false,
        isDirect = over.isDirect or false,
        playerState = over.playerState,
        blocked = over.blocked,
        filter = filter,
    })
end

--------------------------------------------------------------------------------
-- Util
--------------------------------------------------------------------------------

T.Case("Util.Trim strips surrounding whitespace", function()
    T.Eq(ns.Util.Trim("  bold ruby  "), "bold ruby", "trim")
end)

T.Case("StripEscapes keeps link display text", function()
    T.Eq(ns.Util.StripEscapes(RUBY_LINK), "[Bold Living Ruby]", "stripped")
end)

T.Case("Normalize lowercases and strips punctuation", function()
    T.Eq(ns.Util.Normalize("WTB  Bold Living Ruby!!  "), "wtb bold living ruby", "normalized")
    T.Eq(ns.Util.Normalize("WTB " .. RUBY_LINK), "wtb bold living ruby", "normalized link")
end)

T.Case("ExtractItemIDs pulls every item id", function()
    local ids = ns.Util.ExtractItemIDs(RUBY_LINK .. " and " .. RUNED_LINK)
    T.Eq(#ids, 2, "count")
    T.Eq(ids[1], 24033, "first")
    T.Eq(ids[2], 24048, "second")
    T.Eq(#ns.Util.ExtractItemIDs("wtb bold living ruby"), 0, "plain text")
end)

T.Case("HasPhrase respects word boundaries", function()
    T.Eq(ns.Util.HasPhrase("jc lfw all cuts", "lfw"), true, "lfw present")
    T.Eq(ns.Util.HasPhrase("lfwork available", "lfw"), false, "lfw not inside lfwork")
    T.Eq(ns.Util.HasPhrase("who can cut this", "can cut"), true, "multi word")
end)

T.Case("ApplyDefaults fills missing nested keys without sharing tables", function()
    local defaults = { a = 1, nested = { x = 10, y = 20 } }
    local target = { nested = { x = 99 } }
    ns.ApplyDefaults(target, defaults)
    T.Eq(target.a, 1, "top level filled")
    T.Eq(target.nested.x, 99, "existing value preserved")
    T.Eq(target.nested.y, 20, "nested value filled")
    local a, b = {}, {}
    ns.ApplyDefaults(a, defaults); ns.ApplyDefaults(b, defaults)
    a.nested.x = 42
    T.Eq(b.nested.x, 10, "b unaffected")
end)

--------------------------------------------------------------------------------
-- Professions
--------------------------------------------------------------------------------

T.Case("Profiles exist for every V1 profession", function()
    for _, key in ipairs({ "jewelcrafting", "alchemy", "blacksmithing", "tailoring",
                           "leatherworking", "engineering", "cooking" }) do
        T.Eq(ns.Prof.ByKey(key) ~= nil, true, key)
    end
    T.Eq(ns.Prof.ByKey("enchanting"), nil, "enchanting not in V1")
end)

T.Case("ForLine resolves a tradeskill line name to its profile", function()
    T.Eq(ns.Prof.ForLine("Jewelcrafting").key, "jewelcrafting", "jc")
    T.Eq(ns.Prof.ForLine("Alchemy").key, "alchemy", "alchemy")
    T.Eq(ns.Prof.ForLine("Enchanting"), nil, "unsupported")
end)

T.Case("JC vocabulary keeps the CutMaster phrases", function()
    local v = JC.vocab
    local function has(list, phrase)
        for _, p in ipairs(list) do if p == phrase then return true end end
        return false
    end
    T.Eq(has(v.vetoWords, "jc lfw"), true, "jc lfw veto")
    T.Eq(has(v.vetoWords, "will cut"), true, "will cut veto")
    T.Eq(v.sellerWords["all cuts"], 3, "all cuts seller")
    T.Eq(v.buyerWords["lf jc"], 3, "lf jc buyer")
    T.Eq(has(v.professionWords, "lf jewelcrafter"), true, "lf jewelcrafter")
    T.Eq(has(v.askPhrases, "can you cut"), true, "can you cut")
end)

T.Case("Alchemy vocabulary is built from its own verbs and abbreviations", function()
    local v = ALCH.vocab
    local function has(list, phrase)
        for _, p in ipairs(list) do if p == phrase then return true end end
        return false
    end
    T.Eq(has(v.vetoWords, "alch lfw"), true, "alch lfw veto")
    T.Eq(has(v.vetoWords, "will brew"), true, "will brew veto")
    T.Eq(v.buyerWords["lf alch"], 3, "lf alch buyer")
    T.Eq(has(v.professionWords, "any alchemist"), true, "any alchemist")
    T.Eq(v.sellerWords["all potions"], 3, "all potions seller")
end)

T.Case("Templates use {item}/{items} and the profession noun", function()
    T.Eq(JC.templates.bark:find("{items}", 1, true) ~= nil, true, "jc bark has {items}")
    T.Eq(ALCH.templates.templateNoItem:find("potion", 1, true) ~= nil, true, "alchemy asks about a potion")
    T.Eq(JC.templates.noneTemplate, "Sorry, I don't have that cut.", "jc none template")
end)

T.Case("IsProduct follows the profile's item classes", function()
    T.Eq(ns.Prof.IsProduct(JC, { classID = 3 }), true, "gem is a jc product")
    T.Eq(ns.Prof.IsProduct(JC, { classID = 4 }), false, "ring is not")
    T.Eq(ns.Prof.IsProduct(ALCH, { classID = 0 }), true, "consumable is an alchemy product")
end)

T.Case("MigratePlaceholders rewrites CutMaster tokens", function()
    local s = { bark = { template = "WTS {gems}" },
                invite = { whisper = { template = "for {gem}", templateNoGem = "what cut?" } },
                filter = { canCutGuards = { "who" }, weights = { designLink = 4, canCut = 4 } } }
    ns.Prof.MigratePlaceholders(s)
    T.Eq(s.bark.template, "WTS {items}", "bark token")
    T.Eq(s.invite.whisper.template, "for {item}", "whisper token")
    T.Eq(s.invite.whisper.templateNoItem, "what cut?", "templateNoGem renamed")
    T.Eq(s.filter.canCraftGuards[1], "who", "guards renamed")
    T.Eq(s.filter.weights.recipeLink, 4, "weight renamed")
end)

--------------------------------------------------------------------------------
-- Scanner
--------------------------------------------------------------------------------

T.Case("MergeBook adds new entries with defaults on", function()
    local book, added = ns.Scanner.MergeBook({}, { scannedEntry(24033, "Bold Living Ruby") })
    T.Eq(added, 1, "added count")
    T.Eq(book[24033].advertise, true, "advertise default")
    T.Eq(book[24033].match, true, "match default")
    T.Eq(book[24033].reagents[23436], 1, "reagents captured")
end)

T.Case("MergeBook preserves user settings and flags stale entries", function()
    local old = { [24033] = { itemID = 24033, name = "Bold Living Ruby", advertise = false, match = false, aliases = { "bold ruby" } },
                  [24028] = { itemID = 24028, name = "Solid Star of Elune", advertise = true } }
    local book, added = ns.Scanner.MergeBook(old, { scannedEntry(24033, "Bold Living Ruby") })
    T.Eq(added, 0, "nothing new")
    T.Eq(book[24033].advertise, false, "advertise preserved")
    T.Eq(book[24033].aliases[1], "bold ruby", "aliases preserved")
    T.Eq(book[24028].stale, true, "missing flagged stale")
end)

T.Case("ShouldAutoScan rules", function()
    T.Eq(ns.Scanner.ShouldAutoScan(0, false, 999999, 1000000, 21600), true, "empty")
    T.Eq(ns.Scanner.ShouldAutoScan(173, true, 999999, 1000000, 21600), true, "dirty")
    T.Eq(ns.Scanner.ShouldAutoScan(173, false, 999999, 1000000, 21600), false, "fresh")
    T.Eq(ns.Scanner.ShouldAutoScan(173, false, 0, 1000000, 21600), true, "stale")
end)

--------------------------------------------------------------------------------
-- Matcher
--------------------------------------------------------------------------------

T.Case("Matcher hits link, name, alias and loose tiers for gems", function()
    T.Eq(matchIDs("wtb " .. RUBY_LINK)[24033], "link", "link tier")
    T.Eq(matchIDs("wtb bold living ruby please")[24033], "name", "name tier")
    T.Eq(matchIDs("wtb bold ruby")[24033], "loose", "bold ruby")
    T.Eq(matchIDs("lf great draenite")[23096], "loose", "great draenite")
    local book = jcBook()
    book[24033].aliases = { "brb gem" }
    T.Eq(matchIDs("wtb brb gem", book)[24033], "alias", "alias tier")
    T.Eq(matchIDs("wtb bold ruby " .. RUBY_LINK)[24033], "link", "link wins")
end)

T.Case("Matcher does not fire on a bare prefix or a disabled entry", function()
    T.Eq(matchIDs("boldly going where no one has gone")[24033], nil, "boldly")
    T.Eq(matchIDs("bold move friend")[24033], nil, "bold alone")
    T.Eq(matchIDs("wtb hidden cut gem")[99999], nil, "excluded")
end)

T.Case("Loose shorthand is off for professions without prefix-family names", function()
    local index = ns.Matcher.BuildIndex(alchBook(), ALCH)
    T.Eq(#index.loose, 0, "alchemy gets no loose entries")
    T.Eq(matchIDs("wtb haste potion", alchBook(), ALCH)[22838], "name", "full name still matches")
    T.Eq(matchIDs("wtb " .. HASTE_LINK, alchBook(), ALCH)[22838], "link", "link matches")
    T.Eq(matchIDs("haste please", alchBook(), ALCH)[22838], nil, "no shorthand")
end)

T.Case("Loose matching does not apply to jewelry even for jewelcrafting", function()
    local book = { [21779] = { itemID = 21779, name = "Band of Natural Fire", classID = 4, match = true, aliases = {} } }
    local index = ns.Matcher.BuildIndex(book, JC)
    T.Eq(#index.loose, 0, "rings get no loose entry")
    T.Eq(#ns.Matcher.Match("x", ns.Util.Normalize("wtb band of natural fire"), index), 1, "full name still works")
end)

T.Case("QtyHint reads leading and trailing counts", function()
    T.Eq(ns.Matcher.QtyHint("wtb 3 bold living ruby", "bold living ruby"), 3, "leading digit")
    T.Eq(ns.Matcher.QtyHint("wtb bold living ruby x4", "bold living ruby"), 4, "trailing x4")
    T.Eq(ns.Matcher.QtyHint("wtb two bold living ruby", "bold living ruby"), 2, "word number")
    T.Eq(ns.Matcher.QtyHint("wtb bold living ruby", "bold living ruby"), nil, "no hint")
end)

T.Case("NearMiss finds a known gem family and reports completeness", function()
    local book = jcBook()
    book[24099] = { itemID = 24099, name = "Glowing Living Ruby", classID = 3, match = true, aliases = {} }
    local index = ns.Matcher.BuildIndex(book, JC)
    local family, ids, exact = ns.Matcher.NearMiss(ns.Util.Normalize("can you do a Sparkling Living Ruby?"), index)
    T.Eq(family, "living ruby", "family")
    T.Eq(#ids, 3, "three known cuts")
    T.Eq(exact, true, "complete family name")
    T.Eq(ns.Matcher.NearMiss(ns.Util.Normalize("lfg deadmines"), index), nil, "no family")
end)

T.Case("NearMiss is silent for professions without families", function()
    local index = ns.Matcher.BuildIndex(alchBook(), ALCH)
    T.Eq(ns.Matcher.NearMiss(ns.Util.Normalize("wtb mana potion"), index), nil, "no family model")
end)

--------------------------------------------------------------------------------
-- Classifier, jewelcrafting
--------------------------------------------------------------------------------

T.Case("Classifier vetoes JC LFW and WTS", function()
    local r = classify("JC LFW all cuts pst " .. RUBY_LINK)
    T.Eq(r.verdict, "vetoed", "verdict")
    T.Eq(r.reason, "lfw", "reason")
    T.Eq(classify("WTS " .. RUBY_LINK .. " 5g").reason, "wts", "wts")
end)

T.Case("Classifier scores can cut by guard", function()
    local r = classify("Can cut any cut, mats + tip " .. RUBY_LINK)
    T.Eq(r.verdict, "lowscore", "not a veto")
    T.Eq(r.sellerScore >= 3, true, "seller score")
    T.Eq(classify("anyone who can cut " .. RUBY_LINK .. "? have mats").verdict, "invite", "guarded")
end)

T.Case("Classifier invites buyers and withholds bare links", function()
    T.Eq(classify("WTB bold ruby have mats").verdict, "invite", "wtb")
    T.Eq(classify("any jc able to cut " .. RUBY_LINK .. "?").verdict, "invite", "question")
    T.Eq(classify("LF " .. RUBY_LINK .. " will tip").verdict, "invite", "will tip")
    local r = classify(RUBY_LINK)
    T.Eq(r.verdict, "lowscore", "bare link")
    T.Eq(r.reason, "no buyer signal", "reason")
end)

T.Case("Classifier broadcast signals", function()
    local three = RUBY_LINK .. " " .. RUNED_LINK .. " " .. DRAENITE_LINK
    T.Eq(classify("gems available " .. three).sellerHits.manyLinks, 3, "manyLinks")
    T.Eq(classify("check these out " .. RUBY_LINK, { hasRecipeLink = true }).sellerHits.recipeLink, 4, "recipeLink")
    T.Eq(classify("gems here " .. RUBY_LINK, { isRepeat = true }).sellerHits.repeatBark, 5, "repeatBark")
end)

T.Case("Classifier player state and operational blocks", function()
    local r = classify("WTB bold ruby have mats", { playerState = { flaggedSeller = true } })
    T.Eq(r.reason, "flagged seller", "flagged")
    r = classify("WTB bold ruby have mats", { blocked = "cooldown" })
    T.Eq(r.verdict, "invite", "content verdict still computed")
    T.Eq(r.blocked, "cooldown", "block reported separately")
end)

T.Case("Classifier out of scope and profession requests", function()
    local r = classify("WTB a mount have gold")
    T.Eq(r.reason, "no item match", "no match")
    r = classify("LF JC")
    T.Eq(r.verdict, "invite", "lf jc invites")
    T.Eq(r.reason, "profession request", "reason")
    T.Eq(classify("anyone know a jc online?").verdict, "invite", "jc online")
    T.Eq(classify("any jc lfw here, all cuts available").reason, "lfw", "veto beats profession request")
    T.Eq(classify("JC LFW all cuts available pst").reason, "no item match", "competitor naming nothing is out of scope")
    T.Eq(classify("LF enchanter for boots").reason, "no item match", "other profession")
end)

T.Case("A profession request naming an item we lack does not invite", function()
    local r = classify("LF JC'er with [Veiled Pyrestone] pst", { namedUnknownItem = true })
    T.Eq(r.verdict, "lowscore", "no invite")
    T.Eq(r.reason, "named an item we lack", "reason")
    T.Eq(classify("LF JC for " .. RUBY_LINK).reason, "matched", "one we have invites")
end)

T.Case("Direct channels drop the buyer-signal requirement and broadcast signals", function()
    T.Eq(classify(RUBY_LINK, { isDirect = true }).verdict, "invite", "bare link in whisper invites")
    local three = RUBY_LINK .. " " .. RUNED_LINK .. " " .. DRAENITE_LINK
    local r = classify("can you do " .. three, { isDirect = true })
    T.Eq(r.sellerHits.manyLinks, nil, "manyLinks suppressed")
    T.Eq(r.verdict, "invite", "verdict")
    T.Eq(classify("WTS " .. RUBY_LINK .. " 300g", { isDirect = true }).verdict, "vetoed", "wts veto holds")
end)

--------------------------------------------------------------------------------
-- Classifier, alchemy
--------------------------------------------------------------------------------

T.Case("Alchemy: buyers invite, sellers veto, verbs are the profession's", function()
    T.Eq(classify("WTB haste potion have mats", { profile = ALCH }).verdict, "invite", "wtb potion")
    T.Eq(classify("LF alch for some potions", { profile = ALCH }).verdict, "invite", "lf alch")
    T.Eq(classify("LF alch for some potions", { profile = ALCH }).reason, "profession request", "reason")
    T.Eq(classify("alch lfw can brew all potions " .. HASTE_LINK, { profile = ALCH }).verdict, "vetoed", "alch lfw")
    T.Eq(classify("anyone who can brew " .. HASTE_LINK .. "? have mats", { profile = ALCH }).verdict, "invite", "guarded can brew")
    local r = classify("can brew " .. HASTE_LINK .. " mats + tip", { profile = ALCH })
    T.Eq(r.sellerHits["can brew"] ~= nil, true, "unguarded can brew is a seller tell")
end)

T.Case("Alchemy: jewelcrafting phrases mean nothing", function()
    T.Eq(classify("LF JC for cuts", { profile = ALCH }).reason, "no item match", "lf jc is not an alchemy request")
end)

--------------------------------------------------------------------------------
-- Players, Log, Inviter
--------------------------------------------------------------------------------

T.Case("Players.Observe flags a repeated ad inside the window only", function()
    local msg = "wts jc cuts all cuts avail pst"
    local st, rep = ns.Players.Observe(nil, msg, 1000, 600)
    T.Eq(rep, false, "first sighting")
    st, rep = ns.Players.Observe(st, msg, 1100, 600)
    T.Eq(rep, true, "repeat detected")
    T.Eq(st.flaggedSeller, true, "flagged")
    local st2 = ns.Players.Observe(nil, msg, 1000, 600)
    local _, rep2 = ns.Players.Observe(st2, msg, 2000, 600)
    T.Eq(rep2, false, "too far apart")
end)

T.Case("Log.Push caps the buffer at 100 entries", function()
    local log = {}
    for i = 1, 120 do ns.Log.Push(log, { id = i }) end
    T.Eq(#log, 100, "capped")
    T.Eq(log[1].id, 120, "newest first")
end)

T.Case("BlockReason reports cooldown, full group and disabled", function()
    local s = ns.DeepCopy(ns.Prof.DefaultSettings(JC).invite)
    T.Eq(ns.Inviter.BlockReason({ lastInviteAt = 1000 }, 1100, 1, s), "cooldown", "cooldown")
    T.Eq(ns.Inviter.BlockReason({ lastInviteAt = 1000 }, 2000, 1, s), nil, "cleared")
    T.Eq(ns.Inviter.BlockReason({}, 5000, 5, s), "group full", "full")
    s.enabled = false
    T.Eq(ns.Inviter.BlockReason({}, 5000, 1, s), "invites disabled", "disabled")
end)

T.Case("Inviter.Render substitutes placeholders and legacy tokens", function()
    T.Eq(ns.Inviter.Render("Invited you for {item}!", { item = "X" }, "Bob", JC), "Invited you for X!", "item")
    T.Eq(ns.Inviter.Render("Invited you for {gem}!", { item = "X" }, "Bob", JC), "Invited you for X!", "legacy gem")
    T.Eq(ns.Inviter.Render("Hi {player}, {item}", {}, "Bob", JC), "Hi Bob, your cut", "fallback noun")
    T.Eq(ns.Inviter.Render("Hi {player}, {item}", {}, "Bob", ALCH), "Hi Bob, your potion", "alchemy noun")
    T.Eq(ns.Inviter.Render("I can do: {items}", { items = "A B" }, "Bob", JC), "I can do: A B", "items")
end)

--------------------------------------------------------------------------------
-- Barker
--------------------------------------------------------------------------------

local function barkEntries(n)
    local out = {}
    for i = 1, n do
        local id = 24000 + i
        out[i] = { itemID = id, link = link(id, "Bold Living Ruby") }
    end
    return out
end

T.Case("Barker.Fit respects the cap, perBark, wrapping and the placeholder", function()
    local tpl = JC.templates.bark
    local msg, nextCursor, used = ns.Barker.Fit(barkEntries(40), 1, tpl, 255, 4)
    T.Eq(msg ~= nil, true, "message built")
    T.Eq(#msg <= 255, true, "within cap")
    T.Eq(nextCursor, 1 + used, "cursor advanced")
    local _, _, used2 = ns.Barker.Fit(barkEntries(40), 1, tpl, 255, 2)
    T.Eq(used2, 2, "perBark")
    local _, c3 = ns.Barker.Fit(barkEntries(5), 4, tpl, 255, 4)
    T.Eq(c3 <= 5, true, "wrapped")
    T.Eq(ns.Barker.Fit(barkEntries(5), 1, "WTS JC cuts, no placeholder", 255, 4), nil, "rejected")
    T.Eq(ns.Barker.Fit(barkEntries(5), 1, "WTS {gems} pst", 255, 4) ~= nil, true, "legacy {gems} accepted")
    T.Eq(ns.Barker.Fit({}, 1, tpl, 255, 4), nil, "empty list")
end)

T.Case("ApplyAdvertiseFilter uses the profile rule and never advertises BoP", function()
    local book = {
        [24033] = { itemID = 24033, name = "Bold Living Ruby", classID = 3, quality = 3 },
        [32196] = { itemID = 32196, name = "Bold Crimson Spinel", classID = 3, quality = 4 },
        [20969] = { itemID = 20969, name = "Lustrous Azure Moonstone", classID = 3, quality = 2 },
        [25500] = { itemID = 25500, name = "Braided Copper Ring", classID = 4, quality = 1 },
        [2] = { itemID = 2, name = "Bound Gem", classID = 3, quality = 4, bindType = 1 },
    }
    T.Eq(ns.Barker.ApplyAdvertiseFilter(book, "rare", JC), 2, "rare count")
    T.Eq(book[24033].advertise, true, "rare kept")
    T.Eq(book[20969].advertise, false, "uncommon dropped")
    T.Eq(book[25500].advertise, false, "non gem dropped")
    T.Eq(ns.Barker.ApplyAdvertiseFilter(book, "epic", JC), 1, "epic count")
    T.Eq(ns.Barker.ApplyAdvertiseFilter(book, "all", JC), 4, "all excludes bop")
    T.Eq(book[2].advertise, false, "bop excluded")
    T.Eq(ns.Barker.ApplyAdvertiseFilter(book, "none", JC), 0, "none")
end)

T.Case("A bark is due measured from the last one actually sent", function()
    T.Eq(ns.Barker.IsDue(1000, 1179, 180), false, "not yet")
    T.Eq(ns.Barker.IsDue(1000, 1180, 180), true, "exactly due")
    T.Eq(ns.Barker.IsDue(nil, 1788441671, 180), true, "never sent")
end)

--------------------------------------------------------------------------------
-- Orders, Trade, Ledger
--------------------------------------------------------------------------------

local function reagentBook()
    return {
        [24033] = { itemID = 24033, name = "Bold Living Ruby", reagents = { [23436] = 1 } },
        [24048] = { itemID = 24048, name = "Runed Living Ruby", reagents = { [23436] = 1 } },
        [24028] = { itemID = 24028, name = "Solid Star of Elune", reagents = { [23440] = 1 } },
        [99998] = { itemID = 99998, name = "Soulbound Figurine", reagents = { [23441] = 1 }, bindType = 1 },
    }
end

local function orderFor(itemIDs, qty)
    local o = { items = {}, matsReceived = {}, unmatchedMats = {} }
    for _, id in ipairs(itemIDs) do
        o.items[#o.items + 1] = { itemID = id, qty = qty or 1, qtySource = "default" }
    end
    return o
end

T.Case("InferQuantities takes the count from the mats and overrides text", function()
    local o = orderFor({ 24033 })
    o.items[1].qtySource = "text"; o.items[1].qty = 2
    local split = ns.Orders.InferQuantities(o, { [23436] = 3 }, reagentBook(), 1)
    T.Eq(split, false, "unambiguous")
    T.Eq(o.items[1].qty, 3, "quantity from mats")
    T.Eq(o.items[1].qtySource, "mats", "source")
end)

T.Case("InferQuantities flags an ambiguous split instead of guessing", function()
    local o = orderFor({ 24033, 24048 })
    local split = ns.Orders.InferQuantities(o, { [23436] = 3 }, reagentBook(), 1)
    T.Eq(split, true, "needsSplit")
    T.Eq(o.items[1].qtySource, "ambiguous", "not allocated")
end)

T.Case("InferQuantities adds an unrequested item only when the reagent is unambiguous", function()
    local o = orderFor({ 24033 })
    local _, added = ns.Orders.InferQuantities(o, { [23440] = 2 }, reagentBook(), 1)
    T.Eq(#added, 1, "one item added")
    T.Eq(added[1].itemID, 24028, "the only consumer of that reagent")
    -- 23436 feeds two cuts we can make: do not guess, record it for the user.
    local o2 = orderFor({ 24028 })
    local _, added2 = ns.Orders.InferQuantities(o2, { [23436] = 3 }, reagentBook(), 1)
    T.Eq(#added2, 0, "nothing guessed")
    T.Eq(o2.unmatchedMats[23436].count, 3, "recorded as unmatched")
    T.Eq(#o2.unmatchedMats[23436].options, 2, "two options offered")
    -- and never a soulbound craft
    local o3 = orderFor({ 24033 })
    local _, added3 = ns.Orders.InferQuantities(o3, { [23441] = 2 }, reagentBook(), 1)
    T.Eq(#added3, 0, "bop not added")
end)

T.Case("InferQuantities multiplies by items made per craft", function()
    local o = orderFor({ 22841 })
    ns.Orders.InferQuantities(o, { [21884] = 2, [22793] = 6, [18256] = 10 }, alchBook(), 1)
    -- Primal Fire is the tightest: 2 crafts of 5 potions each.
    T.Eq(o.items[1].qty, 10, "two batches of five")
end)

T.Case("Trade.Classify separates raw mats from finished products", function()
    local snapshot = { incoming = { [23436] = 3, [24033] = 1 }, outgoing = { [24048] = 2 } }
    local raw, products, delivered = ns.Trade.Classify(snapshot, reagentBook())
    T.Eq(raw[23436], 3, "raw")
    T.Eq(products[24033], 1, "known product incoming")
    T.Eq(delivered[24048], 2, "delivered")
end)

T.Case("Ledger.SumSince counts recent entries and the legacy gems field", function()
    local entries = {
        { at = 1000, copper = 5000, units = { [1] = 2 } },
        { at = 900, copper = 1000, gems = { [1] = 1 } },
        { at = 100, copper = 9000, units = { [1] = 1 } },
    }
    local copper, units, n = ns.Ledger.SumSince(entries, 500)
    T.Eq(copper, 6000, "copper")
    T.Eq(units, 3, "units incl. legacy")
    T.Eq(n, 2, "entries")
end)

T.Case("OpenList only counts people who actually joined", function()
    local saved = ns.db.orders
    ns.db.orders = {
        { id = 1, player = "A", status = "pending", items = {} },
        { id = 2, player = "B", status = "grouped", items = {} },
        { id = 3, player = "C", status = "mats", items = {} },
        { id = 4, player = "D", status = "done", items = {} },
    }
    T.Eq(#ns.Orders.OpenList(), 2, "grouped and mats only")
    T.Eq(#ns.Orders.ActiveList(), 3, "pending included")
    T.Eq(ns.Orders.PendingCount(), 1, "one waiting")
    ns.db.orders = saved
end)

T.Case("The master switch and barking refuse while disabled", function()
    local saved = ns.db.settings.enabled
    ns.db.settings.enabled = false
    T.Eq(ns.Enabled(), false, "off")
    local ok, reason = ns.Barker.Tick(true)
    T.Eq(ok, false, "forced bark refused")
    T.Eq(reason, "TradeMaster is disabled", "reason")
    ns.db.settings.enabled = saved
end)

T.Case("IsAvailabilityQuestion recognises direct questions only", function()
    local ASK = JC.vocab.askPhrases
    local function q(t) return ns.Util.IsAvailabilityQuestion(t, ns.Util.Normalize(t), ASK) end
    T.Eq(q("Do you have veiled pyrestone cut?"), true, "do you have")
    T.Eq(q("can you cut this one?"), true, "can you cut")
    T.Eq(q(RUBY_LINK .. "?"), true, "bare link plus ?")
    T.Eq(q("hey whats up?"), false, "question mark alone")
    T.Eq(q(RUBY_LINK .. " is this a good deal? not sure"), false, "question not trailing")
end)

T.Case("RecentText stitches together what someone just said", function()
    local st = {}
    ns.Players.PushRecent(st, "Shifting Shadowsong?", 1000)
    ns.Players.PushRecent(st, "Amethyst", 1010)
    T.Eq(ns.Players.RecentText(st, 1015, 90), "Shifting Shadowsong? Amethyst", "joined")
    T.Eq(ns.Players.RecentText(st, 2000, 90), "", "old messages drop out")
end)

--------------------------------------------------------------------------------
-- Invites across every scanned book
--------------------------------------------------------------------------------

T.Case("PickProfession: the book with the most hits answers", function()
    local cands = {
        { key = "jewelcrafting", index = ns.Matcher.BuildIndex(jcBook(), JC) },
        { key = "alchemy", index = ns.Matcher.BuildIndex(alchBook(), ALCH) },
    }
    local text = "WTB " .. HASTE_LINK .. " x5"
    local pick, hits = ns.Events.PickProfession(text, ns.Util.Normalize(text), cands)
    T.Eq(pick.key, "alchemy", "alchemy item picks alchemy even with JC active")
    T.Eq(#hits > 0, true, "hits")

    text = "WTB " .. RUBY_LINK
    pick, hits = ns.Events.PickProfession(text, ns.Util.Normalize(text), cands)
    T.Eq(pick.key, "jewelcrafting", "gem picks jewelcrafting")

    text = "anyone selling boats"
    pick, hits = ns.Events.PickProfession(text, ns.Util.Normalize(text), cands)
    T.Eq(pick.key, "jewelcrafting", "no match falls back to the first (active) candidate")
    T.Eq(#hits, 0, "no hits")
end)

T.Case("Inviter.BlockReason: only an explicit false disables", function()
    T.Eq(ns.Inviter.BlockReason({}, 100, 1, { enabled = false, maxParty = 5, playerCooldownSec = 60 }),
        "invites disabled", "false")
    T.Eq(ns.Inviter.BlockReason({}, 100, 1, { maxParty = 5, playerCooldownSec = 60 }),
        nil, "nil is on")
end)

--------------------------------------------------------------------------------
-- Ported from CutMaster 1.1.0
--------------------------------------------------------------------------------

T.Case("WantedFromOrder never wants a soulbound craft", function()
    local book = {
        [1] = { itemID = 1, name = "Tradeable" },
        [2] = { itemID = 2, name = "Soulbound", bindType = 1 },
    }
    local order = { items = { { itemID = 1, qty = 3 }, { itemID = 2, qty = 1 } } }
    local wanted = ns.Trade.WantedFromOrder(order, book)
    T.Eq(wanted[1], 3, "tradeable wanted")
    T.Eq(wanted[2], nil, "soulbound never queued")
end)

T.Case("WantedFromOrder sums duplicate line items", function()
    local book = { [1] = { itemID = 1, name = "X" } }
    local order = { items = { { itemID = 1, qty = 2 }, { itemID = 1, qty = 4 } } }
    T.Eq(ns.Trade.WantedFromOrder(order, book)[1], 6, "quantities summed")
end)

T.Case("NextFillSlot finds a bag row for a many-of-one order", function()
    local wanted = { [50] = 6 }
    local snapshot = {
        { bag = 0, slot = 3, itemID = 50, link = "i50", count = 4 },
        { bag = 1, slot = 1, itemID = 50, link = "i50", count = 2 },
    }
    local row = ns.Trade.NextFillSlot(wanted, snapshot)
    T.Eq(row.bag, 0, "first matching row")
    T.Eq(row.count, 4, "real stack size, not an assumed 1")
    wanted[50] = wanted[50] - row.count
    T.Eq(wanted[50], 2, "still wants the rest")
    local row2 = ns.Trade.NextFillSlot(wanted, { snapshot[2] })
    T.Eq(row2.bag, 1, "second stack found on the next fresh scan")
end)

T.Case("NextFillSlot handles several different items in one order", function()
    local wanted = { [10] = 2, [20] = 1 }
    local snapshot = {
        { bag = 0, slot = 1, itemID = 99, link = "unrelated", count = 1 },
        { bag = 0, slot = 2, itemID = 20, link = "i20", count = 1 },
        { bag = 0, slot = 3, itemID = 10, link = "i10", count = 2 },
    }
    T.Eq(ns.Trade.NextFillSlot(wanted, snapshot).itemID, 20, "skips the unrelated item")
end)

T.Case("NextFillSlot returns nil once everything is satisfied", function()
    T.Eq(ns.Trade.NextFillSlot({ [1] = 0 }, { { bag = 0, slot = 1, itemID = 1, link = "x", count = 5 } }),
        nil, "nothing left to fill")
end)

T.Case("PrefixNearMiss finds unrelated gems sharing a prefix", function()
    local book = {
        [1] = { itemID = 1, name = "Jagged Seaspray Emerald", classID = 3, bindType = 0, match = true, aliases = {} },
        [2] = { itemID = 2, name = "Jagged Deep Peridot", classID = 3, bindType = 0, match = true, aliases = {} },
    }
    local index = ns.Matcher.BuildIndex(book, JC)
    local text = "looking for jagged and do you happen to be an enchanter as well?"
    local word, ids = ns.Matcher.PrefixNearMiss(ns.Util.Normalize(text), index)
    T.Eq(word, "jagged", "prefix found")
    T.Eq(#ids, 2, "both gems returned, not merged as one family")
end)

T.Case("PrefixNearMiss requires the exact token", function()
    local book = {
        [1] = { itemID = 1, name = "Jagged Seaspray Emerald", classID = 3, bindType = 0, match = true, aliases = {} },
    }
    local index = ns.Matcher.BuildIndex(book, JC)
    T.Eq(ns.Matcher.PrefixNearMiss(ns.Util.Normalize("ragged old boots"), index), nil, "no substring hit")
end)

T.Case("PrefixNearMiss stays silent below the length gate", function()
    local book = {
        [1] = { itemID = 1, name = "Bold Living Ruby", classID = 3, bindType = 0, match = true, aliases = {} },
    }
    local index = ns.Matcher.BuildIndex(book, JC)
    T.Eq(ns.Matcher.PrefixNearMiss(ns.Util.Normalize("that was a bold move"), index), nil, "short prefix excluded")
end)

T.Case("PrefixNearMiss is off for flat-name professions", function()
    local index = ns.Matcher.BuildIndex(alchBook(), ALCH)
    T.Eq(ns.Matcher.PrefixNearMiss(ns.Util.Normalize("looking for haste potion"), index), nil, "no prefix index")
end)

T.Case("Orders.Open matches regardless of case", function()
    local saved = ns.db.orders
    ns.db.orders = { { id = 1, player = "wokenough", status = "grouped", items = {} } }
    T.Eq(ns.Orders.Open("Wokenough") ~= nil, true, "proper case finds lowercase order")
    T.Eq(ns.Orders.Open("WOKENOUGH") ~= nil, true, "all caps matches")
    ns.db.orders = saved
end)

T.Case("Orders.Open still respects done and cancelled", function()
    local saved = ns.db.orders
    ns.db.orders = { { id = 1, player = "Wokenough", status = "done", items = {} } }
    T.Eq(ns.Orders.Open("wokenough"), nil, "closed order not returned")
    ns.db.orders = saved
end)

T.Case("Classifier scores LF item crafter as a buyer signal", function()
    local r = classify("LF " .. RUBY_LINK .. " crafter")
    T.Eq(r.verdict, "invite", "verdict")
    T.Eq(r.buyerHits.crafter, 2, "crafter scored")
    local r2 = classify("LF " .. RUBY_LINK .. " cutter")
    T.Eq(r2.verdict, "invite", "cutter verdict")
end)

--------------------------------------------------------------------------------
-- Market saturation
--------------------------------------------------------------------------------

local PROFILES = ns.Professions.Profiles

local function marketDB()
    return { market = { samples = {}, prunedAt = 0 } }
end

local function classifyLine(text, over)
    over = over or {}
    local norm = ns.Util.Normalize(text)
    local result = over.skipClassifier and nil or classify(text, over)
    return ns.Market.ClassifyLine(result, norm, PROFILES, over.hasItemMatch or false)
end

T.Case("Market: a competitor bark counts for the profession it names", function()
    -- Jewelcrafting is active, so the classifier calls this "no item match" and
    -- never logs it. It is still a leatherworker advertising against us.
    local kind, keys = classifyLine("LW LFW all patterns pst")
    T.Eq(kind, "seller", "kind")
    T.Eq(#keys, 1, "one profession")
    T.Eq(keys[1], "leatherworking", "attributed to leatherworking")
end)

T.Case("Market: a veto phrase that names its own craft needs no tag", function()
    local kind, keys = classifyLine("will cut any gems, mats and tip")
    T.Eq(kind, "seller", "kind")
    T.Eq(keys[1], "jewelcrafting", "jewelcrafting")
end)

T.Case("Market: a bare sale with no profession named is ignored", function()
    local kind = classifyLine("WTS Primal Might 50g each")
    T.Eq(kind, nil, "not counted")
end)

T.Case("Market: a profession request counts as a buyer", function()
    local kind, keys = classifyLine("any leatherworker online?")
    T.Eq(kind, "buyer", "kind")
    T.Eq(keys[1], "leatherworking", "leatherworking")
end)

T.Case("Market: one line can name two professions", function()
    local kind, keys = classifyLine("jc lfw and lw lfw, full books")
    T.Eq(kind, "seller", "kind")
    T.Eq(#keys, 2, "both counted")
    T.Eq(keys[1], "jewelcrafting", "sorted first")
    T.Eq(keys[2], "leatherworking", "sorted second")
end)

T.Case("Market: advertising wins over asking on the same line", function()
    local kind = classifyLine("jc lfw, need mats, will tip")
    T.Eq(kind, "seller", "a crafter advertising is competition")
end)

T.Case("Market: Counts separates people from posts and honours the window", function()
    local db = marketDB()
    local now = 100000
    -- Oldest first, the order Trade chat arrives in.
    ns.Market.Record(db, now - 7200, "seller", "leatherworking", "Cid", "lw lfw")
    ns.Market.Record(db, now - 40, "buyer", "leatherworking", "Ann", "lf lw")
    ns.Market.Record(db, now - 30, "seller", "leatherworking", "Bob", "lw lfw")
    ns.Market.Record(db, now - 20, "seller", "leatherworking", "Bob", "lw lfw")
    ns.Market.Record(db, now - 10, "seller", "leatherworking", "Bob", "lw lfw")

    local s, b, sp, bp = ns.Market.Counts(db, now, "leatherworking", 3600)
    T.Eq(s, 1, "one distinct seller in the hour")
    T.Eq(sp, 3, "three seller posts")
    T.Eq(b, 1, "one buyer")
    T.Eq(bp, 1, "one buyer post")

    local sday = ns.Market.Counts(db, now, "leatherworking", 86400)
    T.Eq(sday, 2, "the older seller is inside the day window")

    local other = ns.Market.Counts(db, now, "jewelcrafting", 3600)
    T.Eq(other, 0, "another profession is unaffected")
end)

T.Case("Market: Prune drops old samples and caps the ring", function()
    local db = marketDB()
    local now = 200000
    -- Written straight in, so Record's own throttled prune does not run first.
    local m = db.market
    m.samples[1] = { at = now - 90000, prof = "alchemy", kind = "seller", who = "Old" }
    for i = 1, 5 do
        m.samples[i + 1] = { at = now - (6 - i), prof = "alchemy", kind = "buyer", who = "P" .. i }
    end
    m.prunedAt = now
    ns.Market.Prune(db, now)
    T.Eq(#db.market.samples, 5, "the day-old sample is gone")
    T.Eq(db.market.samples[1].who, "P1", "oldest kept is the earliest recent one")
    T.Eq(db.market.samples[5].who, "P5", "newest still last")
end)

T.Case("Market: Label thresholds", function()
    T.Eq(ns.Market.Label(0, 0), "quiet", "empty")
    T.Eq(ns.Market.Label(1, 5), "quiet", "one seller is never crowded")
    T.Eq(ns.Market.Label(2, 2), "balanced", "even")
    T.Eq(ns.Market.Label(3, 1), "crowded", "three sellers to one buyer")
    T.Eq(ns.Market.Label(4, 3), "balanced", "demand keeps up")
    T.Eq(ns.Market.Label(6, 3), "crowded", "twice the sellers")
end)

T.Case("Market: SuggestInterval steps, rounds and clamps", function()
    T.Eq(ns.Market.SuggestInterval(180, 3, 1), 300, "crowded backs off")
    T.Eq(ns.Market.SuggestInterval(180, 0, 3), 120, "quiet with demand leans in")
    T.Eq(ns.Market.SuggestInterval(180, 2, 2), 180, "balanced leaves it alone")
    T.Eq(ns.Market.SuggestInterval(560, 5, 0), 600, "clamped to the slider maximum")
    T.Eq(ns.Market.SuggestInterval(40, 0, 4), 30, "clamped to the slider minimum")
    T.Eq(ns.Market.SuggestInterval(185, 2, 2), 180, "rounded to 30s")
end)

T.Case("Market: Observe records one sample per named profession", function()
    local db = marketDB()
    local savedDB = ns.db
    ns.db = db
    local now = 300000
    ns.Market.Observe(db, now, "Bob", "jc lfw and lw lfw", ns.Util.Normalize("jc lfw and lw lfw"), nil, false)
    T.Eq(#db.market.samples, 2, "one per profession")
    T.Eq(ns.Market.Counts(db, now, "jewelcrafting", 3600), 1, "jewelcrafting seller")
    T.Eq(ns.Market.Counts(db, now, "leatherworking", 3600), 1, "leatherworking seller")
    ns.db = savedDB
end)


--------------------------------------------------------------------------------
-- Who gets an invite, and who gets an order
--------------------------------------------------------------------------------

T.Case("Invite: a customer we can craft for", function()
    local r = { verdict = "invite" }
    T.Eq(ns.Events.ShouldInvite(r, 1, 1), true, "one craftable match")
end)

T.Case("Invite: a bare profession request names nothing and still counts", function()
    local r = { verdict = "invite" }
    T.Eq(ns.Events.ShouldInvite(r, 0, 0), true, "no items named at all")
end)

T.Case("Invite: not when every match needs a BoP mat we lack", function()
    local r = { verdict = "invite" }
    T.Eq(ns.Events.ShouldInvite(r, 0, 2), false, "matched but nothing craftable")
end)

T.Case("Invite: never against the verdict or an operational block", function()
    T.Eq(ns.Events.ShouldInvite({ verdict = "lowscore" }, 1, 1), false, "lowscore")
    T.Eq(ns.Events.ShouldInvite({ verdict = "vetoed" }, 1, 1), false, "vetoed")
    T.Eq(ns.Events.ShouldInvite({ verdict = "invite", blocked = "invites off" }, 1, 1), false,
        "blocked")
end)

T.Case("Order: a whisper that named nothing still opens one", function()
    local r = { verdict = "invite" }
    T.Eq(ns.Events.ShouldOpenOrder(r, 0, 0, true), true, "direct")
    T.Eq(ns.Events.ShouldOpenOrder(r, 0, 0, false), false, "a Trade post is not at your door")
end)

T.Case("Order: an operational block still books the order", function()
    -- Group full or on cooldown means we cannot invite yet. They are still a
    -- customer, and the order is how we remember that.
    local r = { verdict = "invite", blocked = "group full" }
    T.Eq(ns.Events.ShouldOpenOrder(r, 1, 1, true), true, "blocked but wanted")
end)

--------------------------------------------------------------------------------
-- Crafting the next thing an order needs
--------------------------------------------------------------------------------

T.Case("Crafter: the next item is the first one not ticked off", function()
    local o = { items = { { itemID = 1, cut = true }, { itemID = 2 }, { itemID = 3 } } }
    T.Eq(ns.Crafter.NextItem(o).itemID, 2, "skips the finished line")
    T.Eq(ns.Crafter.NextItem({ items = { { itemID = 1, cut = true } } }), nil, "all done")
    T.Eq(ns.Crafter.NextItem(nil), nil, "no order")
end)

T.Case("Crafter: picks the oldest order this window can serve", function()
    local orders = {
        { id = 1, profession = "alchemy", createdAt = 50, status = "grouped",
          items = { { itemID = 1 } } },
        { id = 2, profession = "jewelcrafting", createdAt = 10, status = "grouped",
          items = { { itemID = 2 } } },
        { id = 3, profession = "jewelcrafting", createdAt = 20, status = "grouped",
          items = { { itemID = 3 } } },
    }
    T.Eq(ns.Crafter.PickOrder(orders, "jewelcrafting").id, 2, "oldest jewelcrafting order")
    T.Eq(ns.Crafter.PickOrder(orders, "alchemy").id, 1, "the other book")
    T.Eq(ns.Crafter.PickOrder(orders, "tailoring"), nil, "nothing for this window")
end)

T.Case("Crafter: an order with every line ticked is not picked", function()
    local orders = {
        { id = 1, profession = "jewelcrafting", createdAt = 10, status = "grouped",
          items = { { itemID = 1, cut = true } } },
        { id = 2, profession = "jewelcrafting", createdAt = 20, status = "grouped",
          items = { { itemID = 2 } } },
    }
    T.Eq(ns.Crafter.PickOrder(orders, "jewelcrafting").id, 2, "skips the finished order")
end)

T.Case("Crafter: mats in hand beat a customer who only asked", function()
    local orders = {
        { id = 1, profession = "jewelcrafting", createdAt = 10, status = "pending",
          items = { { itemID = 1 } } },
        { id = 2, profession = "jewelcrafting", createdAt = 20, status = "grouped",
          items = { { itemID = 2 } } },
        { id = 3, profession = "jewelcrafting", createdAt = 30, status = "mats",
          items = { { itemID = 3 } } },
    }
    T.Eq(ns.Crafter.PickOrder(orders, "jewelcrafting").id, 3, "newest, but their mats are here")
    orders[3] = nil
    T.Eq(ns.Crafter.PickOrder(orders, "jewelcrafting").id, 2, "then the one in your group")
end)

T.Case("Crafter: craft count divides by what one craft makes", function()
    T.Eq(ns.Crafter.CraftCount(5, 1), 5, "one per craft")
    T.Eq(ns.Crafter.CraftCount(5, 5), 1, "a batch of five is one craft")
    T.Eq(ns.Crafter.CraftCount(6, 5), 2, "six needs a second batch")
    T.Eq(ns.Crafter.CraftCount(3, nil), 3, "no batch size recorded")
end)

T.Case("Crafter: craft count never offers more than the mats allow", function()
    local crafts, wanted = ns.Crafter.CraftCount(10, 1, 4)
    T.Eq(crafts, 4, "mats for four")
    T.Eq(wanted, 10, "ten still wanted")
    T.Eq(ns.Crafter.CraftCount(10, 1, 0), 10, "no count from the window means no clamp")
end)

T.Case("Orders: hiding finished orders never removes them", function()
    local orders = {
        { id = 1, status = "grouped" },
        { id = 2, status = "done" },
        { id = 3, status = "cancelled" },
        { id = 4, status = "pending" },
    }
    local shown, hidden = ns.Orders.Visible(orders, false)
    T.Eq(#shown, 2, "the two live orders")
    T.Eq(hidden, 2, "and a count of what is held back")
    T.Eq(#orders, 4, "the list itself is untouched")

    local all = ns.Orders.Visible(orders, true)
    T.Eq(#all, 4, "showing finished shows everything")
end)

--------------------------------------------------------------------------------
-- Editing an order by hand
--------------------------------------------------------------------------------

T.Case("Money: what people type for an amount", function()
    T.Eq(ns.Util.ParseMoney("25g"), 250000, "gold")
    T.Eq(ns.Util.ParseMoney("25g50s"), 255000, "gold and silver")
    T.Eq(ns.Util.ParseMoney("1g 2s 3c"), 10203, "spaced out")
    T.Eq(ns.Util.ParseMoney("50s"), 5000, "silver alone")
    T.Eq(ns.Util.ParseMoney("250"), 2500000, "a bare number is gold")
    T.Eq(ns.Util.ParseMoney("1.5g"), 15000, "fractions of gold")
    T.Eq(ns.Util.ParseMoney(""), nil, "nothing typed")
    T.Eq(ns.Util.ParseMoney("thanks!"), nil, "no number in there")
end)

T.Case("Money: text that can be typed back in", function()
    T.Eq(ns.Util.MoneyText(255000), "25g50s", "round trips")
    T.Eq(ns.Util.ParseMoney(ns.Util.MoneyText(10203)), 10203, "and back again")
    T.Eq(ns.Util.MoneyText(0), "", "nothing to edit")
    T.Eq(ns.Util.MoneyText(nil), "", "no value at all")
end)

T.Case("Orders: adding an item, and adding it twice", function()
    local o = { items = {}, updatedAt = 0 }
    local it, isNew = ns.Orders.AddItem(o, 111, 2, 100)
    T.Eq(#o.items, 1, "one line")
    T.Eq(it.qty, 2, "two of them")
    T.Eq(isNew, true, "a new line")
    T.Eq(it.qtySource, "manual", "typed in, so the mats still win later")

    local same, again = ns.Orders.AddItem(o, 111, 3, 200)
    T.Eq(#o.items, 1, "still one line")
    T.Eq(same.qty, 5, "the count went up")
    T.Eq(again, false, "not a new line")
    T.Eq(o.updatedAt, 200, "the order moved")
end)

T.Case("Orders: removing an item", function()
    local o = { items = { { itemID = 1 }, { itemID = 2 }, { itemID = 3 } }, updatedAt = 0 }
    local gone = ns.Orders.RemoveItem(o, 2, 300)
    T.Eq(gone.itemID, 2, "the one asked for")
    T.Eq(#o.items, 2, "two left")
    T.Eq(o.items[2].itemID, 3, "the rest close up")
    T.Eq(ns.Orders.RemoveItem(o, 9, 400), nil, "removing what is not there")
end)

T.Case("Orders: finding a product by what was typed", function()
    local book = {
        [1] = { name = "Bold Living Ruby" },
        [2] = { name = "Delicate Living Ruby" },
        [3] = { name = "Runed Living Ruby" },
        [4] = { name = "Bold Ornate Ruby" },
    }
    T.Eq(#ns.Orders.FindInBook(book, "living ruby"), 3, "three of them")
    T.Eq(#ns.Orders.FindInBook(book, "delicate"), 1, "one of them")
    T.Eq(ns.Orders.FindInBook(book, "delicate")[1].itemID, 2, "the right one")
    T.Eq(#ns.Orders.FindInBook(book, "thorium"), 0, "none of them")
    T.Eq(#ns.Orders.FindInBook(book, ""), 0, "nothing typed")

    -- An exact name is never ambiguous, even though it is inside a longer one.
    local exact = ns.Orders.FindInBook(book, "Bold Ornate Ruby")
    T.Eq(#exact, 1, "exact wins alone")
    T.Eq(exact[1].itemID, 4, "and it is the right one")

    -- Shortest first, so the closest match is the first button offered. "Bold
    -- Living Ruby" and "Bold Ornate Ruby" are both 16 characters, and a tie goes
    -- alphabetically rather than to whatever order pairs() happened to produce.
    local ruby = ns.Orders.FindInBook(book, "ruby")
    T.Eq(ruby[1].entry.name, "Bold Living Ruby", "shortest first, ties alphabetical")
    T.Eq(ruby[#ruby].entry.name, "Delicate Living Ruby", "and the longest goes last")
end)

T.Case("Orders: correcting what a customer paid", function()
    local o = { copperIn = 0, updatedAt = 0 }
    T.Eq(ns.Orders.SetPaid(o, 250000, 100), 250000, "the whole amount is new money")
    T.Eq(o.copperIn, 250000, "recorded on the order")

    T.Eq(ns.Orders.SetPaid(o, 300000, 200), 50000, "a top-up is the difference")
    T.Eq(ns.Orders.SetPaid(o, 100000, 300), -200000, "a correction goes backwards")
    T.Eq(o.copperIn, 100000, "and the order follows")
    T.Eq(ns.Orders.SetPaid(o, -5, 400), -100000, "never below nothing")
    T.Eq(o.copperIn, 0, "clamped")
end)

T.Case("Money: the coin API is never handed something it refuses", function()
    -- GetCoinTextureString errors on a negative, and money reaches it negative
    -- (a correction), fractional (an average) and nil (a field never written).
    T.Eq(type(ns.Ledger.Money(-12345)), "string", "a correction")
    T.Eq(type(ns.Ledger.Money(nil)), "string", "nothing at all")
    T.Eq(type(ns.Ledger.Money(1.5)), "string", "a fraction")
    T.Eq(type(ns.Ledger.Money("nonsense")), "string", "not even a number")
    T.Eq(ns.Ledger.Money(-12345):sub(1, 1), "-", "and the sign survives")
end)

--------------------------------------------------------------------------------
-- Reviewing a reply before it goes out
--------------------------------------------------------------------------------

T.Case("Confirm: when a message needs a look first", function()
    T.Eq(ns.Confirm.Required("never", false), false, "never asks")
    T.Eq(ns.Confirm.Required("never", true), false, "never asks, understood or not")
    T.Eq(ns.Confirm.Required("always", true), true, "always asks")
    T.Eq(ns.Confirm.Required("unsure", true), false, "understood, so send it")
    T.Eq(ns.Confirm.Required("unsure", false), true, "not understood, so show me")
    T.Eq(ns.Confirm.Required(nil, false), true, "an unset setting reviews the rest")
end)

T.Case("Confirm: a bare profession request is answered at once", function()
    local profile = ns.Prof.ByKey("jewelcrafting")
    -- The profile's own defaults, so the test does not depend on which
    -- profession happens to be active.
    local phrases = ns.Confirm.Phrases(profile, ns.Prof.DefaultSettings(profile).filter)
    local function leftover(text)
        return ns.Confirm.Leftover(ns.Util.Normalize(text), phrases)
    end

    T.Eq(leftover("LF JC"), "", "the whole line is the request")
    T.Eq(leftover("any jc online?"), "", "and the polite version")
    T.Eq(leftover("anyone can cut for me please"), "", "no specific in there either")
    T.Eq(ns.Confirm.Understood(0, leftover("LF JC")), true, "so answer it")
end)

T.Case("Confirm: a specific we could not place waits for a person", function()
    local profile = ns.Prof.ByKey("jewelcrafting")
    -- The profile's own defaults, so the test does not depend on which
    -- profession happens to be active.
    local phrases = ns.Confirm.Phrases(profile, ns.Prof.DefaultSettings(profile).filter)
    local function leftover(text)
        return ns.Confirm.Leftover(ns.Util.Normalize(text), phrases)
    end

    T.Eq(leftover("LF JC shadow armor kit") ~= "", true, "they named something")
    T.Eq(ns.Confirm.Understood(0, leftover("LF JC shadow armor kit")), false, "so ask me")
    -- Matching it is what makes it answerable, whatever else is on the line.
    T.Eq(ns.Confirm.Understood(1, leftover("LF JC shadow armor kit")), true, "matched wins")
end)

T.Case("Confirm: a request goes stale rather than arriving late", function()
    local now = 1000
    local queue = {
        { player = "Old", at = now - 400 },
        { player = "Recent", at = now - 10 },
        { player = "Older", at = now - 181 },
    }
    local fresh = ns.Confirm.Fresh(queue, now, 180)
    T.Eq(#fresh, 1, "only the recent one")
    T.Eq(fresh[1].player, "Recent", "and it is the right one")
    T.Eq(#ns.Confirm.Fresh({}, now, 180), 0, "an empty queue")
    T.Eq(#ns.Confirm.Fresh(nil, now, 180), 0, "no queue at all")
end)

T.Case("Requests: everything in brackets is a specific", function()
    -- A recipe link carries no item id at all, which is how
    -- "LF LW [Leatherworking: Bindings of Lightning Reflexes]" was answered with
    -- "what item do you need?".
    local recipe = "LF LW |cffffd000|Htrade:3811:1:300:2:0|h[Leatherworking: Bindings of "
        .. "Lightning Reflexes]|h|r"
    T.Eq(#ns.Util.ExtractItemIDs(recipe), 0, "no item id to find")
    T.Eq(#ns.Util.BracketNames(recipe), 1, "but it named something")
    T.Eq(ns.Util.BracketNames(recipe)[1], "Leatherworking: Bindings of Lightning Reflexes",
        "and this is what")

    local item = "LF JC |cff1eff00|Hitem:24030:0:0:0:0:0:0:0:70|h[Bold Living Ruby]|h|r"
    T.Eq(ns.Util.BracketNames(item)[1], "Bold Living Ruby", "an item link too")

    T.Eq(ns.Util.BracketNames("LF LW [Shadow Armor Kit] please")[1], "Shadow Armor Kit",
        "and a name typed by hand")
    T.Eq(#ns.Util.BracketNames("LF LW"), 0, "a bare request names nothing")
    T.Eq(#ns.Util.BracketNames("anyone jc on? []"), 0, "empty brackets are not a request")
    T.Eq(#ns.Util.BracketNames(nil), 0, "no message at all")

    local two = "LF JC [Bold Living Ruby] and [Runed Living Ruby]"
    T.Eq(#ns.Util.BracketNames(two), 2, "one per name, not one big blob")
end)

T.Case("Log: the All view is every message, newest first", function()
    -- The log holds what the addon decided; capture holds everything it read,
    -- including the lines dropped for matching nothing. "All" has to be both, or
    -- it is only the decisions and says so on the tin that it is not.
    local log = {
        { at = 50, player = "A", msg = "third", verdict = "invite", profession = "leatherworking" },
        { at = 30, player = "B", msg = "first", verdict = "vetoed", profession = "alchemy" },
    }
    local capture = {
        { at = 60, player = "C", msg = "newest", verdict = "lowscore" },
        { at = 50, player = "A", msg = "third", verdict = "invite" },
        { at = 40, player = "D", msg = "second", verdict = "lowscore" },
    }

    local all = ns.Log.Window(log, capture)
    T.Eq(#all, 4, "the one in both lists appears once")
    T.Eq(all[1].msg, "newest", "newest first")
    T.Eq(all[2].msg, "third", "then the shared one")
    T.Eq(all[2].profession, "leatherworking", "as the log's copy, which knows the profession")
    T.Eq(all[3].msg, "second", "then capture's own")
    T.Eq(all[4].msg, "first", "then the oldest")

    T.Eq(#ns.Log.Window(log, capture, 2), 2, "the window caps the walk")
    T.Eq(#ns.Log.Window(log, nil), 2, "capture may be off entirely")
    T.Eq(#ns.Log.Window(nil, nil), 0, "or there may be nothing at all")

    local one, hidden = ns.Log.Filter(all, 100, "invite")
    T.Eq(#one, 1, "filtered to one verdict")
    T.Eq(hidden, 3, "and it says how many it held back")

    local prof = ns.Log.Filter(all, 100, nil, "alchemy")
    T.Eq(#prof, 1, "filtered to one profession")
    T.Eq(prof[1].msg, "first", "and it is the alchemy one")
    T.Eq(#ns.Log.Filter(all, 100, "lowscore", "alchemy"), 0, "both filters apply at once")

    local capped, held = ns.Log.Filter(all, 2)
    T.Eq(#capped, 2, "n caps the rows")
    T.Eq(held, 0, "rows past n are not filtered out, just not shown")
end)

--------------------------------------------------------------------------------
-- Reply composition
--------------------------------------------------------------------------------

-- The whisper settings, with the templates a leatherworker would have.
local function whisperSettings()
    local t = ns.Prof.DefaultSettings(ns.Prof.ByKey("leatherworking"))
    return t.invite.whisper
end

local LW = ns.Prof.ByKey("leatherworking")

local function lwBook()
    return {
        [32574] = {
            itemID = 32574, name = "Bindings of Lightning Reflexes",
            link = link(32574, "Bindings of Lightning Reflexes"),
            recipeLink = "|cffffd000|Htrade:3811:1:300:2:0|h[Pattern: Bindings of Lightning Reflexes]|h|r",
            reagentList = {
                { itemID = 21887, name = "Knothide Leather", count = 8 },
                { itemID = 22456, name = "Primal Shadow", count = 4 },
            },
        },
        [32397] = {
            itemID = 32397, name = "Waistguard of Shackled Souls",
            link = link(32397, "Waistguard of Shackled Souls"),
            -- Scanned before books kept the recipe link: the fallback case.
            reagentList = {
                { itemID = 21887, name = "Knothide Leather", count = 10 },
            },
        },
    }
end

local function hits(...)
    local out = {}
    for _, id in ipairs({ ... }) do out[#out + 1] = { itemID = id, tier = "name" } end
    return out
end

T.Case("Reply: two items named get two items answered", function()
    -- Bwasa linked two recipes and was told about one, then had to ask
    -- "can u do both ur just the belt?".
    local r = ns.Reply.Compose({
        book = lwBook(), matched = hits(32574, 32397), whisper = whisperSettings(),
        profile = LW, player = "Bwasa", base = "reply", withPatterns = false,
    })
    T.Eq(r.kind, "all", "everything they named is ours")
    T.Eq(r.named, 2, "and both are named")
    T.Eq(r.dropped, 0, "nothing left out")
    T.Eq(r.text:find("Bindings of Lightning Reflexes", 1, true) ~= nil, true, "the first")
    T.Eq(r.text:find("Waistguard of Shackled Souls", 1, true) ~= nil, true, "and the second")
end)

T.Case("Reply: knowing one of two says which", function()
    local r = ns.Reply.Compose({
        book = lwBook(), matched = hits(32574),
        cannotDo = { "Boots of Shackled Souls" },
        whisper = whisperSettings(), profile = LW, player = "Bwasa",
        base = "reply", withPatterns = false,
    })
    T.Eq(r.kind, "some", "partial coverage")
    T.Eq(r.text:find("Bindings of Lightning Reflexes", 1, true) ~= nil, true, "names what we have")
    T.Eq(r.text:find("Boots of Shackled Souls", 1, true) ~= nil, true, "and what we do not")
end)

T.Case("Reply: knowing none of it says so", function()
    local r = ns.Reply.Compose({
        book = lwBook(), matched = {},
        cannotDo = { "Boots of Shackled Souls" },
        whisper = whisperSettings(), profile = LW, player = "Bwasa",
        base = "reply", withPatterns = true,
    })
    T.Eq(r.kind, "none", "nothing of theirs is ours")
    T.Eq(r.named, 0, "so nothing is named")
    T.Eq(r.patternsDropped, 0, "and no pattern is attached to nothing")
end)

T.Case("Reply: the pattern goes back when they linked the item", function()
    local r = ns.Reply.Compose({
        book = lwBook(), matched = hits(32574), whisper = whisperSettings(),
        profile = LW, player = "Bwasa", base = "reply", withPatterns = true,
    })
    T.Eq(r.text:find("|Htrade:", 1, true) ~= nil, true, "the pattern link, which lists its reagents on hover")
end)

T.Case("Reply: no pattern goes back when they linked the pattern", function()
    -- They already have the reagent list in front of them.
    local r = ns.Reply.Compose({
        book = lwBook(), matched = hits(32574), whisper = whisperSettings(),
        profile = LW, player = "Bwasa", base = "reply", withPatterns = false,
    })
    T.Eq(r.text:find("|Htrade:", 1, true), nil, "nothing to hand back")
end)

T.Case("Reply: a book scanned before recipe links falls back to the reagents", function()
    local r = ns.Reply.Compose({
        book = lwBook(), matched = hits(32397), whisper = whisperSettings(),
        profile = LW, player = "Bwasa", base = "reply", withPatterns = true,
    })
    T.Eq(r.text:find("10x Knothide Leather", 1, true) ~= nil, true, "same information, more characters")
end)

T.Case("Reply: the whisper cap drops links before it drops names", function()
    local book = lwBook()
    -- A pattern link long enough that neither can be attached.
    book[32574].recipeLink = string.rep("L", 200)
    book[32397].recipeLink = string.rep("W", 200)
    local r = ns.Reply.Compose({
        book = book, matched = hits(32574, 32397), whisper = whisperSettings(),
        profile = LW, player = "Bwasa", base = "reply", withPatterns = true,
        maxLen = 250,
    })
    T.Eq(r.named, 2, "both are still named")
    T.Eq(r.patternsDropped, 2, "and both patterns are reported as left off")
    T.Eq(#r.text <= 250, true, "inside the cap")
    T.Eq(r.overLength, false, "so it did not overrun")

    -- Names that cannot all fit either: one is dropped and counted.
    book[32574].link = string.rep("A", 200)
    book[32397].link = string.rep("B", 200)
    local tight = ns.Reply.Compose({
        book = book, matched = hits(32574, 32397), whisper = whisperSettings(),
        profile = LW, player = "Bwasa", base = "reply", withPatterns = false,
        maxLen = 250,
    })
    T.Eq(tight.named, 1, "as many as fit")
    T.Eq(tight.dropped, 1, "and it knows what it left out")
end)

T.Case("Reply: what we cannot do is trimmed before what we can", function()
    -- The half that matters less goes first, and neither half goes to nothing:
    -- partialTemplate with an empty {lack} reads "I can do X, but I don't have ."
    local r = ns.Reply.Compose({
        book = lwBook(), matched = hits(32574),
        cannotDo = { string.rep("Y", 120), string.rep("Z", 120) },
        whisper = whisperSettings(), profile = LW, player = "Bwasa",
        base = "reply", withPatterns = false, maxLen = 250,
    })
    T.Eq(r.named, 1, "what we can do is kept")
    T.Eq(r.lacked, 1, "one of the two we cannot")
    T.Eq(r.lackDropped, 1, "and the other is reported")
    T.Eq(r.text:find("but I don't have %.") == nil, true, "never an empty lack")
end)

T.Case("Reply: a message that overruns even at the floor says so", function()
    local book = lwBook()
    book[32574].link = string.rep("A", 300)
    local r = ns.Reply.Compose({
        book = book, matched = hits(32574), whisper = whisperSettings(),
        profile = LW, player = "Bwasa", base = "reply", withPatterns = false,
        maxLen = 250,
    })
    T.Eq(r.named, 1, "one item is the floor")
    T.Eq(r.overLength, true, "and the caller is told the client will cut it")
end)

T.Case("Reply: at most three items, and the fourth is reported", function()
    local book = lwBook()
    book[1] = { itemID = 1, name = "A", link = "[A]" }
    book[2] = { itemID = 2, name = "B", link = "[B]" }
    book[3] = { itemID = 3, name = "C", link = "[C]" }
    book[4] = { itemID = 4, name = "D", link = "[D]" }
    local r = ns.Reply.Compose({
        book = book, matched = hits(1, 2, 3, 4), whisper = whisperSettings(),
        profile = LW, player = "Bwasa", base = "reply", withPatterns = false,
    })
    T.Eq(#r.have, 3, "the whisper cap is on characters, this one is on patience")
    T.Eq(r.named, 3, "all three named")
    T.Eq(r.dropped, 1, "counted against what they asked for, not against the cap")
end)

T.Case("Reply: reagents read in window order and stop", function()
    T.Eq(ns.Reply.Reagents(lwBook()[32574]), "8x Knothide Leather, 4x Primal Shadow", "in order")
    T.Eq(ns.Reply.Reagents(lwBook()[32574], 1), "8x Knothide Leather", "capped")
    T.Eq(ns.Reply.Reagents({}), "", "an entry with no reagent list says nothing")
    T.Eq(ns.Reply.Reagents(nil), "", "and neither does no entry")
end)

T.Case("Reply.Names matches the whole name, not a piece of one", function()
    local list = { link(32574, "Bindings of Lightning Reflexes"), "Boots of Shackled Souls" }
    T.Eq(ns.Reply.Names(list, "Bindings of Lightning Reflexes"), true, "inside a link")
    T.Eq(ns.Reply.Names(list, "Boots of Shackled Souls"), true, "as a bare name")
    T.Eq(ns.Reply.Names(list, "Bracers of Shackled Souls"), false, "and not one that is absent")

    -- A substring test here would swallow a different gem entirely.
    local gems = { link(24033, "Bold Living Ruby") }
    T.Eq(ns.Reply.Names(gems, "Living Ruby"), false, "a shorter name is its own item")
    T.Eq(ns.Reply.Names(gems, ""), false, "and an empty name matches nothing")
end)

T.Case("Requests: a craft link is theirs to read, an item link is not", function()
    T.Eq(ns.Util.HasCraftLink("LF LW |Htrade:3811:1:300:2:0|h[Pattern: X]|h|r"), true, "recipe link")
    T.Eq(ns.Util.HasCraftLink("LF ENCH |Henchant:25086|h[Cloak - Greater Shadow]|h"), true, "enchant link")
    T.Eq(ns.Util.HasCraftLink("LF LW " .. link(32574, "Bindings of Lightning Reflexes")), false, "item link")
    T.Eq(ns.Util.HasCraftLink("LF LW"), false, "nothing linked")
    T.Eq(ns.Util.HasCraftLink(nil), false, "no message at all")
end)

--------------------------------------------------------------------------------
-- Ported from CutMaster 1.2.0
--------------------------------------------------------------------------------

T.Case("Requests: a profession request is itself the buyer signal", function()
    -- "LF jewelcrafter" was dropped for no buyer signal while isProfReq was true,
    -- because the exact wording happened not to be a buyerWords phrase.
    local r = classify("LF jewelcrafter")
    T.Eq(r.professionRequest, true, "it is a profession request")
    T.Eq(r.buyerScore > 0, true, "so it carries a buyer signal")
    T.Eq(r.verdict, "invite", "and it is a customer")

    local bare = classify("any jc around?")
    T.Eq(bare.verdict, "invite", "however it is worded")

    -- A competitor advertising is still not a customer.
    local seller = classify("JC LFW full book, all cuts")
    T.Eq(seller.verdict ~= "invite", true, "a bark is not an ask")
end)

T.Case("Requests: they say make, whatever the profession calls it", function()
    local r = classify("who can make " .. RUBY_LINK)
    T.Eq(r.buyerHits["who can make"], 3, "make is the word customers use")
    T.Eq(r.verdict, "invite", "and this is a customer")
end)

T.Case("Orders: a pending order nobody joined for expires", function()
    local orders = {
        { id = 1, player = "A", status = "pending", createdAt = 0, items = {} },
        { id = 2, player = "B", status = "pending", createdAt = 250, items = {} },
        { id = 3, player = "C", status = "grouped", createdAt = 0, items = {} },
        { id = 4, player = "D", status = "done", createdAt = 0, items = {} },
    }
    local expired = ns.Orders.ExpireStale(orders, 300, 300)
    T.Eq(#expired, 1, "only the one that ran out of time")
    T.Eq(expired[1].id, 1, "and it is the old one")
    T.Eq(orders[1].status, "cancelled", "closed out")
    T.Eq(orders[2].status, "pending", "the recent one is still waiting")
    -- Once someone has grouped up, a slow reply is a different problem.
    T.Eq(orders[3].status, "grouped", "a joined order is never expired")
    T.Eq(orders[4].status, "done", "nor a finished one")

    -- Switched off means switched off. Without the guard the arithmetic reads
    -- "older than nothing" and cancels a pending order the moment it is made.
    local waiting = { { id = 9, player = "E", status = "pending", createdAt = 0, items = {} } }
    T.Eq(#ns.Orders.ExpireStale(waiting, 9999, 0), 0, "a zero timeout expires nothing")
    T.Eq(waiting[1].status, "pending", "and leaves it alone")
    T.Eq(#ns.Orders.ExpireStale(waiting, 9999, nil), 0, "nor does an unset one")
end)

T.Case("Orders: dropping an item clears the split prompt it caused", function()
    local o = { id = 1, player = "A", status = "grouped", needsSplit = true, items = {
        { itemID = 24033, qty = 2, qtySource = "ambiguous" },
        { itemID = 24048, qty = 1, qtySource = "mats" },
    } }
    T.Eq(ns.Orders.IndexOfItem(o, 24048), 2, "found by id")
    T.Eq(ns.Orders.IndexOfItem(o, 99), nil, "and not found when absent")

    ns.Orders.RemoveItem(o, 1, 100)
    T.Eq(#o.items, 1, "one left")
    T.Eq(o.needsSplit, false, "and nothing left to split")
    T.Eq(o.updatedAt, 100, "stamped")

    -- Removing the other one leaves nothing to ask about either.
    local both = { id = 2, player = "B", status = "grouped", needsSplit = true, items = {
        { itemID = 24033, qty = 2, qtySource = "ambiguous" },
        { itemID = 24048, qty = 2, qtySource = "ambiguous" },
    } }
    ns.Orders.RemoveItem(both, 1, 100)
    T.Eq(both.needsSplit, true, "still ambiguous while one remains")
    T.Eq(ns.Orders.RemoveItem(both, 9, 100), nil, "removing what is not there does nothing")
end)

T.Case("Invites: a decline is read in the client's own words", function()
    -- ERR_DECLINE_GROUP_S on an English client.
    local fmt = "%s declines your group invitation."
    T.Eq(ns.Inviter.DeclinedName("Bwasa declines your group invitation.", fmt), "Bwasa", "the name")
    T.Eq(ns.Inviter.DeclinedName("Bwasa is already in a group.", fmt), nil, "a different notice")

    -- The point of reading the format string is that the wording is not English
    -- everywhere, and the name is not always at the front.
    T.Eq(ns.Inviter.DeclinedName("Gruppeneinladung von Bwasa abgelehnt.",
        "Gruppeneinladung von %s abgelehnt."), "Bwasa", "another locale")

    -- A format string with magic characters must not be treated as a pattern.
    T.Eq(ns.Inviter.DeclinedName("Bwasa (declines) your invite.",
        "%s (declines) your invite."), "Bwasa", "parentheses are literal")

    T.Eq(ns.Inviter.DeclinedName(nil, fmt), nil, "no message")
    T.Eq(ns.Inviter.DeclinedName("anything", nil), nil, "no format string on this client")
    T.Eq(ns.Inviter.DeclinedName("anything", "no placeholder here"), nil, "a format with no %s")
end)

--------------------------------------------------------------------------------
-- Specializations
--------------------------------------------------------------------------------

local TAILOR = ns.Prof.ByKey("tailoring")

local function set(...)
    local out = {}
    for _, k in ipairs({ ... }) do out[k] = true end
    return out
end

T.Case("Specializations: they want a transmute master and you brew potions", function()
    -- Draxxino, in Trade: this matched [Primal Might] out of the book and opened
    -- an order, because nothing read the four words in front of it.
    local line = "LF  transmute alchemist for  primal might cool down pst"
    T.Eq(ns.Prof.SpecWanted(ALCH, line, set("potion")), "Transmutation Master",
        "not our customer")
    T.Eq(ns.Prof.SpecWanted(ALCH, line, set("transmute")), nil, "unless it is us")
    T.Eq(ns.Prof.SpecWanted(ALCH, line, set("potion", "transmute")), nil, "or one of ours")

    T.Eq(ns.Prof.SpecWanted(ALCH, "LF elixir master to make an elixir", set("potion")),
        "Elixir Master", "the same for elixirs, named the way people say it")
    T.Eq(ns.Prof.SpecWanted(ALCH, "lf alch to make a potion", set("potion")), nil,
        "an ordinary request names no specialization")

    -- A bare verb is an ordinary request any alchemist can take. Only the words
    -- that mean the specialist are listed.
    T.Eq(ns.Prof.SpecWanted(ALCH, "can you transmute this for me", set("potion")), nil,
        "transmute on its own is not a specialization")
end)

T.Case("Specializations: an item is not a request for a specialist", function()
    -- "Spellfire Belt" is an item; "spellfire tailor" is a specialization; the
    -- word is the same one. Reading the whole line would refuse the customer.
    local linked = "LF tailor for |cffa335ee|Hitem:21848:0:0:0:0:0:0:0|h[Spellfire Belt]|h|r"
    T.Eq(ns.Prof.SpecWanted(TAILOR, linked, set("mooncloth")), nil, "what they linked is cut out")

    local typed = "LF tailor for Spellfire Belt"
    T.Eq(ns.Prof.SpecWanted(TAILOR, typed, set("mooncloth"), { "Spellfire Belt" }), nil,
        "and so is what matched the book")
    -- Nor is the bare word enough on its own: the vanilla Shadoweave set needs no
    -- specialization at all, so every word here carries a qualifier.
    T.Eq(ns.Prof.SpecWanted(TAILOR, typed, set("mooncloth")), nil,
        "the item name alone asks for nobody in particular")
    T.Eq(ns.Prof.SpecWanted(TAILOR, "LF spellfire tailor for a belt", set("mooncloth")),
        "Spellfire Tailoring", "asking for the specialist is another matter")
end)

T.Case("Specializations: professions without them are unaffected", function()
    T.Eq(ns.Prof.SpecWanted(JC, "LF jc for a transmute master cut", set()), nil,
        "jewelcrafting has none, so nothing is refused")
    T.Eq(ns.Prof.SpecWanted(nil, "anything", set()), nil, "nor does no profile")
    T.Eq(ns.Prof.SpecWanted(ALCH, nil, set("potion")), nil, "nor no message")
end)

T.Case("Specializations: the choices a profession offers", function()
    local choices = ns.Prof.SpecChoices(ALCH)
    T.Eq(choices[1], "auto", "auto first")
    T.Eq(choices[#choices], "off", "off last")
    T.Eq(#choices, 5, "auto, three specializations, none, off")
    T.Eq(#ns.Prof.SpecChoices(JC), 3, "auto, none and off even with no specializations")
end)

T.Case("Requests: a specialization we lack is vetoed, not scored", function()
    -- Primal Might has to be in the book for this line to get past the "no item
    -- match" exit: matching it is exactly what opened Draxxino an order.
    local book = { [23571] = { itemID = 23571, name = "Primal Might", classID = 7,
                               bindType = 0, match = true, aliases = {} } }
    local line = "LF transmute alchemist for primal might cool down pst"

    local plain = classify(line, { profile = ALCH, book = book })
    T.Eq(plain.verdict ~= "vetoed", true, "a transmute master would take this one")

    local r = classify(line, { profile = ALCH, book = book,
        wrongSpec = "Transmutation Master" })
    T.Eq(r.verdict, "vetoed", "not our customer")
    T.Eq(r.reason, "wants a Transmutation Master", "and the log says why")
end)

--------------------------------------------------------------------------------
-- Answering our own question
--------------------------------------------------------------------------------

T.Case("Players: what we already said no to is remembered", function()
    -- We asked Remyy what they needed, they said [Fel Leather Gloves], and the
    -- book does not have it. Walking them through the same invite and the same
    -- apology on the repost is the part worth skipping.
    local state = {}
    ns.Players.Decline(state, "fel leather gloves", { "Fel Leather Gloves" })

    T.Eq(ns.Players.WasDeclined(state, "anything", { "Fel Leather Gloves" }), true,
        "named again, in any wrapping")
    T.Eq(ns.Players.WasDeclined(state, "fel leather gloves", {}), true, "or typed out")
    T.Eq(ns.Players.WasDeclined(state, "LF LW", {}), false, "a different ask is a fresh one")
    T.Eq(ns.Players.WasDeclined(state, "x", { "Felstalker Belt" }), false, "so is a different item")
    T.Eq(ns.Players.WasDeclined({}, "fel leather gloves", {}), false, "nothing remembered yet")

    T.Eq(ns.Players.ClearDeclined(state), 1, "and it can be forgotten")
    T.Eq(ns.Players.WasDeclined(state, "fel leather gloves", {}), false, "once cleared")
end)

T.Case("Players: the memory is capped and does not grow forever", function()
    local state = {}
    for i = 1, 20 do
        ns.Players.Decline(state, "item number " .. i, {})
    end
    T.Eq(#state.declinedOrder, 12, "the oldest fall off")
    T.Eq(ns.Players.WasDeclined(state, "item number 20", {}), true, "the newest is kept")
    T.Eq(ns.Players.WasDeclined(state, "item number 1", {}), false, "the oldest is not")

    -- The same thing said twice is one entry, not two.
    local dup = {}
    ns.Players.Decline(dup, "same thing", {})
    ns.Players.Decline(dup, "same thing", {})
    T.Eq(#dup.declinedOrder, 1, "no duplicates")
end)
