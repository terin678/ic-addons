local addonName, ns = ...

-- Profession profiles. Everything that made CutMaster a Jewelcrafting addon lives
-- here as data: vocabulary, the craft verb, the recipe-item prefix that marks a
-- seller, which item classes count as products, whether "bold ruby" style
-- shorthand applies, the bulk advertise filters, and the default templates.
--
-- The rest of the addon asks ns.Prof for the ACTIVE profile and reads these
-- fields. Detection is by GetTradeSkillLine(), so the `name` must match the
-- client's localised skill line name (English on this client).

ns.Professions = ns.Professions or {}
local P = ns.Professions
ns.Prof = ns.Prof or {}
local Prof = ns.Prof

local function list(...) return { ... } end

-- Vocabulary builder. Every profession gets the same generic buyer/seller
-- signals plus phrases built from its abbreviations, person nouns and verbs.
local function BuildVocab(spec)
    local verbs = spec.craftVerbs
    local nounS, nounP = spec.craftNoun[1], spec.craftNoun[2]
    local names = {}
    for _, a in ipairs(spec.abbrevs) do names[#names + 1] = a end
    for _, p in ipairs(spec.personNouns) do names[#names + 1] = p end

    local veto = { "lfw", "lf work", "looking for work", "wts", "selling" }
    for _, a in ipairs(spec.abbrevs) do veto[#veto + 1] = a .. " lfw" end
    for _, v in ipairs(verbs) do
        veto[#veto + 1] = "will " .. v
        veto[#veto + 1] = "i " .. v
        veto[#veto + 1] = (spec.gerunds and spec.gerunds[v] or (v .. "ing")) .. " for"
    end

    local seller = {
        ["full book"] = 3, ["mats tip"] = 2, ["tips appreciated"] = 2, ["no charge"] = 2,
        ["all " .. nounP] = 3, ["any " .. nounS] = 2, ["most " .. nounP] = 3,
        ["every " .. nounS] = 3, ["free " .. nounP] = 2,
    }

    local buyer = {
        ["wtb"] = 3, ["want to buy"] = 3, ["buying"] = 2, ["need"] = 2,
        ["have mats"] = 2, ["got mats"] = 2, ["have the mats"] = 2,
        ["will tip"] = 2, ["paying"] = 2, ["pay for"] = 2,
        -- "LF [item] crafter" named the item but scored no buyer signal and
        -- was blocked by requireBuyerSignal. (CutMaster 1.1.0)
        ["crafter"] = 2,
        -- Customers say "make" whatever the profession calls it, so this is not
        -- covered by the per-verb phrases below for a jeweller who cuts or an
        -- alchemist who brews. (CutMaster 1.2.0)
        ["who can make"] = 3, ["anyone make"] = 3,
    }
    for _, p in ipairs(spec.personNouns) do buyer[p] = 2 end
    for _, v in ipairs(verbs) do
        buyer["anyone " .. v] = 3
        buyer["who can " .. v] = 3
    end
    for _, a in ipairs(spec.abbrevs) do
        buyer["any " .. a] = 2
        buyer["lf" .. a] = 3
        buyer["lf " .. a] = 3
    end

    local prof = {}
    for _, n in ipairs(names) do
        for _, form in ipairs({ "lf %s", "lf a %s", "any %s", "any %ss", "need a %s", "need %s",
                                "looking for a %s", "looking for %s", "%s online", "%s around" }) do
            prof[#prof + 1] = string.format(form, n)
        end
    end
    for _, a in ipairs(spec.abbrevs) do prof[#prof + 1] = "lf" .. a end

    local guards = { "who", "anyone", "any1", "anybody", "someone" }
    for _, a in ipairs(spec.abbrevs) do guards[#guards + 1] = a end

    local ask = { "do you have", "do u have", "you have", "do you got", "got", "have you got",
                  "can you do", "do you do", "any chance", "you got" }
    for _, v in ipairs(verbs) do
        ask[#ask + 1] = "can you " .. v
        ask[#ask + 1] = "can u " .. v
        ask[#ask + 1] = "able to " .. v
    end

    return {
        vetoWords = veto, sellerWords = seller, buyerWords = buyer,
        professionWords = prof, canCraftGuards = guards, askPhrases = ask,
        craftVerbs = verbs,
    }
end

local function BuildTemplates(spec)
    local nounS, nounP = spec.craftNoun[1], spec.craftNoun[2]
    local tag = spec.barkTag or spec.abbrevs[1]:upper()
    local done = spec.doneWord or "made"
    return {
        bark = string.format("%s LFW: {items} and more! /w me", tag),
        template = "Invited you for {item}! Accept and trade me the mats.",
        templateNoItem = string.format("Hey! What %s do you need? Link the item or name it and I'll tell you if I have it.", nounS),
        confirmTemplate = string.format("Yep, I can do {item}. Trade me the mats and I'll get it %s.", done),
        suggestTemplate = string.format("I don't have that exact %s, but I can do: {items}", nounS),
        partialTemplate = "I can do {have}, but I don't have {lack}.",
        noneTemplate = string.format("Sorry, I don't have that %s.", nounS),
        askWhichTemplate = "Did you mean one of these? {items}",
        noMatsTemplate = "Not enough {mats} for {item} right now, sorry.",
    }
end

-- The bark default before 1.2.0, so a saved copy of it can follow the new one.
function Prof.LegacyBarkTemplate(profile)
    local tag = profile.barkTag or profile.abbrevs[1]:upper()
    return string.format("WTS %s %s: {items} and more! /w me", tag, profile.craftNoun[2])
end

-- Bulk advertise rules shared by every profession. BoP is excluded elsewhere.
local function QualityFilter(entry, mode, profile)
    local product = Prof.IsProduct(profile, entry)
    if mode == "all" then return true end
    if mode == "none" then return false end
    if mode == "rare" then return product and (entry.quality or 0) >= 3 end
    if mode == "epic" then return product and (entry.quality or 0) >= 4 end
    return entry.advertise
end

local SPECS = {
    {
        key = "jewelcrafting", name = "Jewelcrafting", abbrevs = list("jc"),
        personNouns = list("jewelcrafter", "jeweller", "jeweler", "cutter"),
        craftVerbs = list("cut"), gerunds = { cut = "cutting" },
        craftNoun = list("cut", "cuts"), doneWord = "cut",
        recipeItemPrefix = "Design:", productClasses = { [3] = true },
        shorthand = "prefix-family", minTokenLen = 7,
        bulkFilters = { { "Epic", "epic" }, { "Rare+", "rare" }, { "All", "all" }, { "None", "none" } },
        annotator = "gems", icon = "Interface\\Icons\\INV_Misc_Gem_01",
    },
    {
        key = "alchemy", name = "Alchemy", abbrevs = list("alch", "alchy"),
        personNouns = list("alchemist"),
        craftVerbs = list("brew", "make"), gerunds = { make = "making" },
        craftNoun = list("potion", "potions"), doneWord = "brewed",
        specs = list(
            { key = "potion", name = "Master of Potions", label = "Potion Master", spellID = 28675,
              words = list("potion master", "master of potions", "potion spec",
                           "potion specialist", "potion alchemist") },
            { key = "elixir", name = "Master of Elixirs", label = "Elixir Master", spellID = 28677,
              words = list("elixir master", "master of elixirs", "elixir spec",
                           "elixir specialist", "elixir alchemist") },
            { key = "transmute", name = "Master of Transmutation", label = "Transmutation Master",
              spellID = 28672,
              words = list("transmute master", "transmutation master", "transmute alchemist",
                           "master of transmutation", "transmute spec", "transmutation spec",
                           "transmute specialist") }
        ),
        recipeItemPrefix = "Recipe:", productClasses = { [0] = true },
        shorthand = "none", minTokenLen = 7,
        bulkFilters = { { "Rare+", "rare" }, { "All", "all" }, { "None", "none" } },
        icon = "Interface\\Icons\\Trade_Alchemy",
    },
    {
        key = "blacksmithing", name = "Blacksmithing", abbrevs = list("bs", "smith"),
        personNouns = list("blacksmith"),
        craftVerbs = list("craft", "smith", "make"), gerunds = { make = "making" },
        craftNoun = list("item", "items"), barkTag = "BS", doneWord = "made",
        specs = list(
            { key = "armorsmith", name = "Armorsmith", spellID = 9788,
              words = list("armorsmith", "armoursmith", "armor smith", "armour smith") },
            { key = "weaponsmith", name = "Weaponsmith", spellID = 9787,
              words = list("weaponsmith", "weapon smith") },
            { key = "swordsmith", name = "Master Swordsmith", spellID = 17039,
              words = list("swordsmith", "sword smith") },
            { key = "axesmith", name = "Master Axesmith", spellID = 17041,
              words = list("axesmith", "axe smith") },
            { key = "hammersmith", name = "Master Hammersmith", spellID = 17040,
              words = list("hammersmith", "hammer smith") }
        ),
        recipeItemPrefix = "Plans:", productClasses = { [2] = true, [4] = true },
        shorthand = "none", minTokenLen = 7,
        bulkFilters = { { "Rare+", "rare" }, { "All", "all" }, { "None", "none" } },
        icon = "Interface\\Icons\\Trade_BlackSmithing",
    },
    {
        key = "tailoring", name = "Tailoring", abbrevs = list("tailor"),
        personNouns = list("tailor"),
        craftVerbs = list("craft", "sew", "make"), gerunds = { make = "making" },
        craftNoun = list("item", "items"), barkTag = "Tailoring", doneWord = "made",
        specs = list(
            { key = "spellfire", name = "Spellfire Tailoring", spellID = 26797,
              words = list("spellfire tailor", "spellfire tailoring", "spellfire spec") },
            { key = "mooncloth", name = "Mooncloth Tailoring", spellID = 26798,
              words = list("mooncloth tailor", "mooncloth tailoring", "mooncloth spec") },
            { key = "shadoweave", name = "Shadoweave Tailoring", spellID = 26801,
              words = list("shadoweave tailor", "shadoweave tailoring", "shadoweave spec") }
        ),
        recipeItemPrefix = "Pattern:", productClasses = { [4] = true, [1] = true },
        shorthand = "none", minTokenLen = 7,
        bulkFilters = { { "Rare+", "rare" }, { "All", "all" }, { "None", "none" } },
        icon = "Interface\\Icons\\Trade_Tailoring",
    },
    {
        key = "leatherworking", name = "Leatherworking", abbrevs = list("lw"),
        personNouns = list("leatherworker"),
        craftVerbs = list("craft", "make"), gerunds = { make = "making" },
        craftNoun = list("item", "items"), barkTag = "LW", doneWord = "made",
        specs = list(
            { key = "dragonscale", name = "Dragonscale Leatherworking", spellID = 10656,
              words = list("dragonscale lw", "dragonscale leatherworker",
                           "dragonscale leatherworking", "dragonscale spec") },
            { key = "elemental", name = "Elemental Leatherworking", spellID = 10658,
              words = list("elemental lw", "elemental leatherworker",
                           "elemental leatherworking", "elemental spec") },
            { key = "tribal", name = "Tribal Leatherworking", spellID = 10660,
              words = list("tribal lw", "tribal leatherworker",
                           "tribal leatherworking", "tribal spec") }
        ),
        recipeItemPrefix = "Pattern:", productClasses = { [4] = true, [1] = true },
        shorthand = "none", minTokenLen = 7,
        bulkFilters = { { "Rare+", "rare" }, { "All", "all" }, { "None", "none" } },
        icon = "Interface\\Icons\\INV_Misc_ArmorKit_17",
    },
    {
        key = "engineering", name = "Engineering", abbrevs = list("eng", "engi"),
        personNouns = list("engineer"),
        craftVerbs = list("craft", "make", "build"), gerunds = { make = "making" },
        craftNoun = list("item", "items"), barkTag = "Engineering", doneWord = "made",
        specs = list(
            { key = "gnomish", name = "Gnomish Engineer", spellID = 20219,
              words = list("gnomish engineer", "gnomish engineering", "gnome engineer",
                           "gnomish spec") },
            { key = "goblin", name = "Goblin Engineer", spellID = 20222,
              words = list("goblin engineer", "goblin engineering", "goblin spec") }
        ),
        recipeItemPrefix = "Schematic:",
        productClasses = { [7] = true, [15] = true, [2] = true, [4] = true, [0] = true },
        shorthand = "none", minTokenLen = 7,
        bulkFilters = { { "Rare+", "rare" }, { "All", "all" }, { "None", "none" } },
        icon = "Interface\\Icons\\Trade_Engineering",
    },
    {
        key = "cooking", name = "Cooking", abbrevs = list("cook"),
        personNouns = list("cook", "chef"),
        craftVerbs = list("cook", "make"), gerunds = { make = "making" },
        craftNoun = list("food", "foods"), barkTag = "Cooking", doneWord = "cooked",
        recipeItemPrefix = "Recipe:", productClasses = { [0] = true },
        shorthand = "none", minTokenLen = 7,
        bulkFilters = { { "All", "all" }, { "None", "none" } },
        icon = "Interface\\Icons\\INV_Misc_Food_15",
    },
}

P.Profiles = {}
P.Order = {}
for _, spec in ipairs(SPECS) do
    spec.vocab = BuildVocab(spec)
    spec.templates = BuildTemplates(spec)
    spec.bulkFilterFn = QualityFilter
    spec.reagentAmbiguityMax = 1
    spec.iconPath = spec.icon
    P.Profiles[spec.key] = spec
    P.Order[#P.Order + 1] = spec.key
end

-- Used for defaults when no profession has been scanned yet, so the UI and
-- settings always have a shape to work with.
P.Generic = {
    key = "generic", name = "No profession", abbrevs = list("crafter"),
    personNouns = list("crafter"), craftVerbs = list("craft", "make"),
    gerunds = { make = "making" }, craftNoun = list("item", "items"), barkTag = "crafts",
    recipeItemPrefix = "Recipe:", productClasses = {}, shorthand = "none", minTokenLen = 7,
    bulkFilters = { { "All", "all" }, { "None", "none" } }, reagentAmbiguityMax = 1,
    iconPath = "Interface\\AddOns\\TradeMaster\\TradeMaster.tga",
}
P.Generic.vocab = BuildVocab(P.Generic)
P.Generic.templates = BuildTemplates(P.Generic)
P.Generic.bulkFilterFn = QualityFilter

--------------------------------------------------------------------------------
-- Lookups
--------------------------------------------------------------------------------

function Prof.ByKey(key)
    return key and P.Profiles[key] or nil
end

-- Profile for a tradeskill window's skill line name, or nil if unsupported.
function Prof.ForLine(lineName)
    if not lineName then return nil end
    for _, key in ipairs(P.Order) do
        local p = P.Profiles[key]
        if p.name == lineName then return p end
    end
    -- Tolerate locale variants by prefix ("Jewelcrafting" inside longer text)
    local lower = lineName:lower()
    for _, key in ipairs(P.Order) do
        local p = P.Profiles[key]
        if lower:find(p.name:lower(), 1, true) then return p end
    end
    return nil
end

-- Profile of the profession window that is open right now, if supported.
function Prof.OpenWindow()
    if not GetTradeSkillLine then return nil end
    if TradeSkillFrame and not TradeSkillFrame:IsShown() then return nil end
    return Prof.ForLine(GetTradeSkillLine())
end

-- The active profile (the one that runs barks, invites, orders, trade fills).
function Prof.Current()
    local key = ns.db and ns.db.activeProfession
    return Prof.ByKey(key) or P.Generic
end

function Prof.IsProduct(profile, entry)
    if not entry then return false end
    local classes = profile and profile.productClasses or {}
    if next(classes) == nil then return true end
    return classes[entry.classID] == true
end

-- Keys of professions this character has a book for, in profile order.
function Prof.Known()
    local out = {}
    if not ns.db or not ns.db.professions then return out end
    for _, key in ipairs(P.Order) do
        local pd = ns.db.professions[key]
        if pd and pd.book and next(pd.book) ~= nil then out[#out + 1] = key end
    end
    return out
end

-- Counts for a book: recipes, products (per the profile), and the display noun.
function Prof.BookCounts(profile, book)
    local n, products = 0, 0
    for _, e in pairs(book or {}) do
        if not e.stale then
            n = n + 1
            if Prof.IsProduct(profile, e) then products = products + 1 end
        end
    end
    return n, products, profile and profile.craftNoun[2] or "items"
end

function Prof.SetActive(key)
    if key and not P.Profiles[key] then return false end
    ns.db.activeProfession = key
    if ns.Events then ns.Events.RebuildIndex() end
    if ns.Barker and ns.Barker.Restart then ns.Barker.Restart() end
    if ns.Minimap and ns.Minimap.UpdateIcon then ns.Minimap.UpdateIcon() end
    return true
end

--------------------------------------------------------------------------------
-- Per-profession saved data
--------------------------------------------------------------------------------

-- Default settings for one profession, built from its profile.
--------------------------------------------------------------------------------
-- Specializations
--------------------------------------------------------------------------------

-- Asking for a specialization is asking for a different crafter, not a different
-- item. A potion master can still brew the elixir; they cannot give the customer
-- the proc they came for. So a request naming one we do not hold is not a
-- customer for us, however well it matches the book.
--
-- The words are deliberately specific. A bare "transmute" is an ordinary request
-- any alchemist can take; "transmute master" is not.

-- The spellbook, read once. A specialization is a passive spell that only changes
-- at a trainer, so this is cached and dropped on SPELLS_CHANGED.
local spellNames
local specCache

-- nil when this client cannot be asked. "You hold nothing" and "we could not
-- look" are the same table otherwise, and the first would refuse every
-- specialization request there is.
local function ReadSpellbook()
    if not (GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemName) then
        return nil
    end
    local names = {}
    for i = 1, GetNumSpellTabs() do
        local _, _, offset, count = GetSpellTabInfo(i)
        offset, count = offset or 0, count or 0
        for j = offset + 1, offset + count do
            local name = GetSpellBookItemName(j, "spell")
            if name then names[name:lower()] = true end
        end
    end
    return names
end

function Prof.ForgetSpells()
    spellNames, specCache = nil, nil
end

-- True when we can answer the question at all.
function Prof.CanDetectSpecs()
    if IsSpellKnown then return true end
    if spellNames == nil then spellNames = ReadSpellbook() or false end
    return spellNames ~= false
end

-- IsSpellKnown answers straight away when the client has it. The spellbook walk
-- is the fallback, and it is why the spec `name` has to be the client's own
-- wording, same rule as the profession names above.
function Prof.KnowsSpec(spec)
    if not spec then return false end
    if IsSpellKnown and spec.spellID then
        local ok, known = pcall(IsSpellKnown, spec.spellID)
        if ok and known then return true end
    end
    if spellNames == nil then spellNames = ReadSpellbook() or false end
    if spellNames == false then return false end
    return spellNames[(spec.name or ""):lower()] == true
end

-- Every specialization this character actually holds, as a set. More than one is
-- normal: a Weaponsmith who went on to Swordsmith holds both.
function Prof.DetectSpecs(profile)
    local key = profile and profile.key
    specCache = specCache or {}
    if key and specCache[key] then return specCache[key] end
    local found = {}
    for _, spec in ipairs(profile and profile.specs or {}) do
        if Prof.KnowsSpec(spec) then found[spec.key] = true end
    end
    if key then specCache[key] = found end
    return found
end

-- What we answer to, and where that came from. The saved override wins:
--   nil     leave it to the client, so retraining is picked up on its own
--   <key>   you hold that one, whatever the client says
--   "none"  you hold none, so every specialization request is somebody else's
--   "off"   stop weighing specializations at all
function Prof.SpecSet(key)
    local pd = ns.db and ns.db.professions and ns.db.professions[key]
    local override = pd and pd.settings and pd.settings.specialization
    if override == "off" then return {}, "off" end
    if override == "none" then return {}, "none" end
    if override then return { [override] = true }, "manual" end
    -- Nothing to read it from, so refuse nobody rather than everybody.
    if not Prof.CanDetectSpecs() then return {}, "off" end
    return Prof.DetectSpecs(Prof.ByKey(key)), "auto"
end

-- The states the Professions button cycles through, in order.
function Prof.SpecChoices(profile)
    local out = { "auto" }
    for _, spec in ipairs(profile and profile.specs or {}) do out[#out + 1] = spec.key end
    out[#out + 1] = "none"
    out[#out + 1] = "off"
    return out
end

-- Short enough for a button: what we hold, and whether anyone chose it.
function Prof.SpecLabel(key)
    local have, source = Prof.SpecSet(key)
    if source == "off" then return "off" end
    if source == "none" then return "none" end
    local profile = Prof.ByKey(key)
    local keys = {}
    for _, spec in ipairs(profile and profile.specs or {}) do
        if have[spec.key] then keys[#keys + 1] = spec.key end
    end
    local what = (#keys == 0 and "none") or (#keys == 1 and keys[1]) or (#keys .. " held")
    return source == "auto" and ("auto: " .. what) or what
end

-- Pure. The specialization a line asks for that we do not hold, as its display
-- name and key, or nil.
--
-- Anything they linked or that matched the book is cut out first: "[Bolt of
-- Mooncloth]" is an item and "mooncloth tailor" is a specialization, and the word
-- is the same one. Reading the whole line would refuse the customer who wanted
-- the item.
function Prof.SpecWanted(profile, raw, have, matchedNames)
    if not profile or not profile.specs or not raw then return nil end
    local norm = ns.Util.Normalize((raw:gsub("%[.-%]", " ")))
    for _, name in ipairs(matchedNames or {}) do
        local n = ns.Util.Normalize(name or "")
        if n ~= "" then norm = norm:gsub(ns.Util.EscapePattern(n), " ") end
    end
    for _, spec in ipairs(profile.specs) do
        if not (have or {})[spec.key] then
            for _, word in ipairs(spec.words) do
                if ns.Util.HasPhrase(norm, word) then
                    return spec.label or spec.name, spec.key
                end
            end
        end
    end
    return nil
end

-- How to describe what we hold, for the UI and /tm spec.
function Prof.DescribeSpecs(key)
    local profile = Prof.ByKey(key)
    if not profile or not profile.specs or #profile.specs == 0 then return "none for this profession" end
    local have, source = Prof.SpecSet(key)
    if source == "off" then
        return "|cff888888not checked; requests for a specialization are not refused|r"
    end
    local names = {}
    for _, spec in ipairs(profile.specs) do
        if have[spec.key] then names[#names + 1] = spec.label or spec.name end
    end
    local what = #names > 0 and table.concat(names, ", ") or "none"
    if source == "auto" then return what .. " |cff888888(detected)|r" end
    return what .. " |cff888888(set by you)|r"
end

function Prof.DefaultSettings(profile)
    local v = profile.vocab
    local t = profile.templates
    return {
        bark = {
            enabled = false, intervalSec = 180, perBark = 4,
            template = t.bark, cursor = 1, lastSentAt = 0,
            onlyInCity = true, pauseCombat = true, pauseInstance = true,
        },
        invite = {
            enabled = true, maxParty = 5, playerCooldownSec = 600, fromWhisper = true,
            -- We asked what they needed, they named something we cannot make:
            -- give the group slot back rather than holding it. (1.12.0)
            dropOnNoMatch = true,
            -- And do not invite them again for a day. They repost the same bare
            -- request without the item in it, so nothing tells us they have
            -- stopped wanting the thing we do not have. 0 switches it off.
            declinedCooldownSec = 86400,
            -- "unsure" shows the message first when we cannot name what they
            -- asked for; "never" trusts the templates, "always" reviews everything.
            confirm = "unsure",
            whisper = {
                enabled = true, autoReply = true, autoSuggest = false, answerQuestions = true,
                template = t.template, templateNoItem = t.templateNoItem,
                confirmTemplate = t.confirmTemplate, suggestTemplate = t.suggestTemplate,
                partialTemplate = t.partialTemplate, noneTemplate = t.noneTemplate,
                askWhichTemplate = t.askWhichTemplate, noMatsTemplate = t.noMatsTemplate,
                cooldownSec = 600, replyCooldownSec = 10,
            },
        },
        filter = {
            requireBuyerSignal = true, netThreshold = 3, repeatWindowSec = 600,
            vetoWords = ns.DeepCopy(v.vetoWords),
            sellerWords = ns.DeepCopy(v.sellerWords),
            buyerWords = ns.DeepCopy(v.buyerWords),
            professionWords = ns.DeepCopy(v.professionWords),
            canCraftGuards = ns.DeepCopy(v.canCraftGuards),
            askPhrases = ns.DeepCopy(v.askPhrases),
            craftVerbs = ns.DeepCopy(v.craftVerbs),
            weights = { manyLinks = 3, recipeLink = 4, repeatBark = 5, shapeMatch = 2, canCraft = 4 },
        },
        scan = { autoStaleSec = 21600 },
    }
end

-- Ensure db.professions[key] exists with defaults applied. Returns it.
function Prof.DB(key)
    local profile = Prof.ByKey(key)
    if not profile then return nil end
    ns.db.professions = ns.db.professions or {}
    local pd = ns.db.professions[key]
    if not pd then
        pd = { book = {}, bookScannedAt = 0, bookPartial = false, bookDirty = false, settings = {} }
        ns.db.professions[key] = pd
    end
    pd.book = pd.book or {}
    pd.settings = pd.settings or {}
    ns.ApplyDefaults(pd.settings, Prof.DefaultSettings(profile))
    return pd
end

-- Active profession's saved data, or nil when nothing is active yet.
function Prof.Active()
    local key = ns.db and ns.db.activeProfession
    if not key then return nil end
    return Prof.DB(key)
end

local EMPTY_BOOK = {}
local genericSettings

-- Book of the active profession (read-only empty table when none).
function ns.Book()
    local pd = Prof.Active()
    return pd and pd.book or EMPTY_BOOK
end

-- Settings of the active profession. When nothing is active, a throwaway
-- default set so the UI never dereferences nil.
function ns.PS()
    local pd = Prof.Active()
    if pd then return pd.settings end
    if not genericSettings then
        genericSettings = Prof.DefaultSettings(P.Generic)
    end
    return genericSettings
end

-- Templates saved by CutMaster or older builds use {gem}/{gems}; accept and rewrite.
function Prof.MigratePlaceholders(settings)
    local function fix(s)
        if type(s) ~= "string" then return s end
        return (s:gsub("{gems}", "{items}"):gsub("{gem}", "{item}"))
    end
    if settings.bark then settings.bark.template = fix(settings.bark.template) end
    local w = settings.invite and settings.invite.whisper
    if w then
        if w.templateNoGem and not w.templateNoItem then w.templateNoItem = w.templateNoGem end
        w.templateNoGem = nil
        for k, v in pairs(w) do w[k] = fix(v) end
    end
    local f = settings.filter
    if f then
        if f.canCutGuards and not f.canCraftGuards then f.canCraftGuards = f.canCutGuards end
        f.canCutGuards = nil
        if f.weights then
            if f.weights.designLink and not f.weights.recipeLink then f.weights.recipeLink = f.weights.designLink end
            if f.weights.canCut and not f.weights.canCraft then f.weights.canCraft = f.weights.canCut end
        end
    end
end
