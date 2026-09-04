local addonName, ns = ...

ns.Util = ns.Util or {}

local VERSION = "1.13.1"

-- Output goes straight into a chat frame rather than through the chat event
-- system, so it has no message type and the chat settings UI cannot route it.
-- Picking the target frame here is the only way to move it. See /tm out.
function ns.Print(msg)
    local frame = DEFAULT_CHAT_FRAME
    local idx = ns.db and ns.db.settings and ns.db.settings.outputFrame
    if idx and idx > 1 then
        local f = _G["ChatFrame" .. idx]
        if f and f.AddMessage then frame = f end
    end
    frame:AddMessage("|cff33ff99TradeMaster|r: " .. tostring(msg))
end

-- Master switch. False means TradeMaster takes no action of its own: no
-- invites, no whispers, no barking, no order creation, no filling trades.
-- Reading the UI, scanning, and the /tm try commands still work.
function ns.Enabled()
    return not ns.db or ns.db.settings.enabled ~= false
end

-- Invites are one switch for every scanned book. Barking stays with the
-- active profession (see ns.SetBark).
function ns.InvitesOn()
    return ns.Enabled() and (not ns.db or ns.db.settings.invites ~= false)
end

local function onoffText(v) return v and "|cff44ff44on|r" or "|cffff4444off|r" end

function ns.SetBark(on)
    local s = ns.PS().bark
    s.enabled = on and true or false
    if s.enabled then ns.Barker.Start(true) else ns.Barker.Stop() end
    local p = ns.Prof.Current()
    ns.Print("barking " .. onoffText(s.enabled)
        .. (p.key ~= "generic" and (" for " .. p.name) or ""))
    if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

function ns.SetInvites(on)
    ns.db.settings.invites = on and true or false
    ns.Print("invites " .. onoffText(on) .. " for every scanned profession")
    if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

function ns.DeepCopy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do
        out[k] = ns.DeepCopy(v)
    end
    return out
end

function ns.ApplyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then target[k] = {} end
            ns.ApplyDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
    return target
end

function ns.Now()
    return GetServerTime and GetServerTime() or time()
end

-- Global (cross-profession) defaults. Per-profession settings live under
-- db.professions[key].settings and come from Professions.lua.
ns.Defaults = {
    version = 2,
    activeProfession = nil,
    professions = {},
    players = {},
    log = {},
    capture = {},
    market = { samples = {}, prunedAt = 0 },
    orders = {},
    nextOrderID = 1,
    ledger = { entries = {}, allTimeCopper = 0, allTimeUnits = 0 },
    settings = {
        orders = {
            autoFromInvite = true,
            autoFromWhisper = true,
            autoFromParty = true,
            autoFromTrade = true,
            focusOnOpen = true,
            captureTranscript = true,
            autoAdvanceMats = true,
            autoFillTrade = true,
            promptOnDone = true,
            showFinished = false,
            keepDoneDays = 30,
            -- How long a customer has to accept the invite before the order is
            -- written off. 0 turns it off. (CutMaster 1.2.0)
            pendingTimeoutSec = 300,
        },
        enabled = true,
        annotate = true,
        captureAll = true,
        log = { verdict = "all", mine = false },
        outputFrame = 1,
        minimap = { hide = false },
        tracker = { shown = false, autoShow = true, point = nil },
        debug = false,
        bookSort = "category",
        invites = true,
    },
}

--------------------------------------------------------------------------------
-- One-time import from CutMaster, so a jewelcrafter switching over keeps their
-- book, choices, orders and ledger. Never writes back to CutMasterDB.
--------------------------------------------------------------------------------
local function ImportCutMaster()
    local src = _G.CutMasterDB
    if type(src) ~= "table" or ns.db.importedFromCutMaster then return false end
    if not src.book or next(src.book) == nil then return false end
    local existing = ns.db.professions and ns.db.professions.jewelcrafting
    if existing and existing.book and next(existing.book) ~= nil then return false end

    local pd = ns.Prof.DB("jewelcrafting")
    pd.book = ns.DeepCopy(src.book)
    pd.bookScannedAt = src.bookScannedAt or 0
    pd.bookPartial = src.bookPartial or false
    pd.bookDirty = src.bookDirty or false
    local s = src.settings or {}
    for _, k in ipairs({ "bark", "invite", "filter", "scan" }) do
        if type(s[k]) == "table" then pd.settings[k] = ns.DeepCopy(s[k]) end
    end
    ns.Prof.MigratePlaceholders(pd.settings)
    ns.ApplyDefaults(pd.settings, ns.Prof.DefaultSettings(ns.Prof.ByKey("jewelcrafting")))

    if next(ns.db.players) == nil then ns.db.players = ns.DeepCopy(src.players or {}) end
    if #ns.db.orders == 0 then
        ns.db.orders = ns.DeepCopy(src.orders or {})
        for _, o in ipairs(ns.db.orders) do o.profession = o.profession or "jewelcrafting" end
        ns.db.nextOrderID = math.max(ns.db.nextOrderID or 1, src.nextOrderID or 1)
    end
    if (ns.db.ledger.allTimeCopper or 0) == 0 and src.ledger then
        ns.db.ledger = ns.DeepCopy(src.ledger)
        ns.db.ledger.allTimeUnits = ns.db.ledger.allTimeUnits or ns.db.ledger.allTimeGems or 0
        ns.db.ledger.allTimeGems = nil
        for _, e in ipairs(ns.db.ledger.entries or {}) do
            if e.gems and not e.units then e.units = e.gems; e.gems = nil end
        end
    end
    for _, k in ipairs({ "orders", "captureAll", "outputFrame", "tracker", "debug" }) do
        if s[k] ~= nil and ns.db.settings[k] == ns.Defaults.settings[k] then
            ns.db.settings[k] = ns.DeepCopy(s[k])
        end
    end
    if s.gemStats ~= nil then ns.db.settings.annotate = s.gemStats end
    ns.db.importedFromCutMaster = true
    if not ns.db.activeProfession then ns.db.activeProfession = "jewelcrafting" end
    return true
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("SKILL_LINES_CHANGED")
frame:RegisterEvent("TRADE_SKILL_SHOW")
frame:RegisterEvent("TRADE_SKILL_CLOSE")
frame:RegisterEvent("CHAT_MSG_CHANNEL")
frame:RegisterEvent("CHAT_MSG_WHISPER")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("CHAT_MSG_SYSTEM")
frame:RegisterEvent("SPELLS_CHANGED")
frame:RegisterEvent("CHAT_MSG_RAID_LEADER")
frame:RegisterEvent("CHAT_MSG_RAID")
frame:RegisterEvent("CHAT_MSG_PARTY_LEADER")
frame:RegisterEvent("CHAT_MSG_PARTY")
frame:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
frame:RegisterEvent("TRADE_CLOSED")
frame:RegisterEvent("TRADE_ACCEPT_UPDATE")
frame:RegisterEvent("TRADE_SHOW")
frame:SetScript("OnEvent", function(self, event, ...)
    local arg1 = ...
    if event == "ADDON_LOADED" and arg1 == addonName then
        TradeMasterDB = TradeMasterDB or {}
        ns.ApplyDefaults(TradeMasterDB, ns.Defaults)
        ns.db = TradeMasterDB
        for key in pairs(ns.db.professions) do
            local pd = ns.Prof.DB(key)
            if pd then ns.Prof.MigratePlaceholders(pd.settings) end
        end
        -- 1.2.0 changed the default bark wording; a saved copy of the old
        -- default follows it, a customised template is left alone.
        for key, pd in pairs(ns.db.professions) do
            local p = ns.Prof.ByKey(key)
            if p and pd.settings and pd.settings.bark
                and pd.settings.bark.template == ns.Prof.LegacyBarkTemplate(p) then
                pd.settings.bark.template = p.templates.bark
            end
        end
        -- Invites used to be switched per profession. One switch now covers
        -- every book; a profession that had it off turns the whole thing off.
        if ns.db.settings.invites == nil then ns.db.settings.invites = true end
        for _, pd in pairs(ns.db.professions) do
            local inv = pd.settings and pd.settings.invite
            if inv and inv.enabled == false then
                ns.db.settings.invites = false
                inv.enabled = true
            end
        end
        local imported = ImportCutMaster()
        if not ns.db.activeProfession then
            local known = ns.Prof.Known()
            if known[1] then ns.db.activeProfession = known[1] end
        end
        if ns.PS().bark.enabled and ns.Enabled() then ns.Barker.Start() end
        ns.Orders.StartExpiryTicker()
        if not ns.Enabled() then
            ns.Print("|cffff9900currently disabled.|r /tm enable to switch back on.")
        end
        if ns.Market then ns.Market.Prune(ns.db, ns.Now()) end
        if ns.Minimap and ns.Minimap.Init then ns.Minimap.Init() end
        if ns.db.settings.tracker.shown then
            C_Timer.After(1, function() ns.Tracker.Show() end)
        end
        local active = ns.Prof.Current()
        ns.Print(string.format("v%s loaded. Active profession: %s. /tm opens the window, /tm help lists commands.",
            VERSION, active.key ~= "generic" and active.name or "none yet (open a profession window)"))
        if imported then
            ns.Print("|cff44ff44imported your CutMaster book, orders and income.|r CutMasterDB was left untouched.")
        end
    elseif event == "PLAYER_LOGIN" then
        local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
        if loaded and loaded("CutMaster") then
            ns.Print("|cffff9900CutMaster is also loaded.|r Both watch Trade chat and both will invite. "
                .. "Disable one of them (/tm disable or /cm disable).")
        end
    elseif event == "SPELLS_CHANGED" then
        -- Retraining a specialization changes the spellbook, and nothing else
        -- tells us it happened.
        ns.Prof.ForgetSpells()
        if ns.UI and ns.UI.frame and ns.UI.frame:IsShown() then ns.UI.Refresh() end
    elseif event == "SKILL_LINES_CHANGED" then
        if ns.db and ns.db.professions then
            for _, pd in pairs(ns.db.professions) do pd.bookDirty = true end
        end
    elseif event == "TRADE_SKILL_SHOW" then
        C_Timer.After(0.1, function() ns.Annotators.OnTradeSkillShow() end)
        -- GetNumTradeSkills reads 0 for a frame or two after the event fires.
        C_Timer.After(0.2, function()
            local profile = ns.Prof.OpenWindow()
            if not profile then return end
            local pd = ns.Prof.DB(profile.key)
            local count = 0
            for _ in pairs(pd.book) do count = count + 1 end
            local should = ns.Scanner.initiatedByUs or ns.Scanner.ShouldAutoScan(
                count, pd.bookDirty, pd.bookScannedAt, ns.Now(), pd.settings.scan.autoStaleSec)
            if should then
                ns.Scanner.Scan({ silent = not ns.Scanner.initiatedByUs })
            elseif ns.Crafter then
                ns.Crafter.Focus()
            end
        end)
    elseif event == "TRADE_SKILL_CLOSE" then
        ns.Scanner.initiatedByUs = false
    elseif event == "CHAT_MSG_CHANNEL" then
        local text, author, _, _, _, _, _, _, channelName = ...
        if channelName and channelName:find("Trade", 1, true) then
            ns.Events.OnTradeMessage(text, author)
        end
    elseif event == "CHAT_MSG_WHISPER" then
        local text, author = ...
        ns.Events.OnWhisper(text, author)
    elseif event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_PARTY_LEADER"
        or event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" then
        local text, author = ...
        ns.Events.OnParty(text, author)
    elseif event == "GROUP_ROSTER_UPDATE" then
        if ns.db then ns.Orders.PromoteGrouped(ns.Now()) end
    elseif event == "CHAT_MSG_SYSTEM" then
        -- They said no. Close the order now rather than waiting out the timeout.
        local text = ...
        local name = ns.db and ns.Enabled()
            and ns.Inviter.DeclinedName(text, _G.ERR_DECLINE_GROUP_S)
        if name then
            local short = name:gsub("%-.*", "")
            local o = ns.Orders.CancelPending(short, ns.Now())
            if o then
                ns.Print(string.format("|cff888888%s declined the invite.|r Order #%d closed.",
                    short, o.id))
                if ns.Tracker then ns.Tracker.Refresh() end
            end
        end
    elseif event == "CHAT_MSG_WHISPER_INFORM" then
        local text, target = ...
        if ns.db.settings.orders.captureTranscript then
            ns.Orders.AddTranscript(target, "out", text, ns.Now())
        end
    elseif event == "TRADE_SHOW" or event == "TRADE_ACCEPT_UPDATE"
        or event == "TRADE_CLOSED" then
        ns.Trade.OnEvent(event, ...)
    end
end)
ns.frame = frame

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

local function onoff(v)
    return v and "|cff44ff44on|r" or "|cffff4444off|r"
end

local function HandleSlash(input)
    local raw = ns.Util.Trim(input or "")
    local cmd, rest = raw:match("^(%S*)%s*(.*)$")
    cmd = (cmd or ""):lower()
    local profile = ns.Prof.Current()
    local book = ns.Book()
    local ps = ns.PS()

    if cmd == "" or cmd == "config" then
        ns.UI.Toggle()
    elseif cmd == "test" then
        ns.Tests.Run()
    elseif cmd == "prof" or cmd == "profession" then
        local known = ns.Prof.Known()
        if rest == "" then
            if #known == 0 then
                ns.Print("no professions scanned yet. Open a profession window and it will be picked up.")
            end
            for _, key in ipairs(known) do
                local p = ns.Prof.ByKey(key)
                local n, products = ns.Prof.BookCounts(p, ns.Prof.DB(key).book)
                ns.Print(string.format("  %s%s|r  %d recipes, %d %s",
                    key == ns.db.activeProfession and "|cff44ff44" or "|cffffffff",
                    p.name, n, products, p.craftNoun[2]))
            end
            ns.Print("usage: /tm prof <name> to make one active")
        else
            local want = rest:lower()
            for _, key in ipairs(known) do
                local p = ns.Prof.ByKey(key)
                if key == want or p.name:lower() == want or (p.abbrevs[1] == want) then
                    ns.Prof.SetActive(key)
                    ns.Print("active profession is now " .. p.name .. ".")
                    if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
                    return
                end
            end
            ns.Print("no scanned profession called '" .. rest .. "'. /tm prof lists them.")
        end
    elseif cmd == "scan" then
        ns.Scanner.Scan()
    elseif cmd == "craft" then
        ns.Crafter.Focus({ manual = true })
    elseif cmd == "spec" then
        local want = ns.Util.Trim(rest or ""):lower()
        local key = ns.db.activeProfession
        local p = key and ns.Prof.ByKey(key)
        if not p or not p.specs or #p.specs == 0 then
            ns.Print("no specializations for " .. (p and p.name or "this profession") .. ".")
        elseif want == "" then
            ns.Print(string.format("%s: %s", p.name, ns.Prof.DescribeSpecs(key)))
            ns.Print("  /tm spec " .. table.concat(ns.Prof.SpecChoices(p), "|")
                .. "   (none = you have none, off = stop refusing on this)")
        else
            local pd = ns.Prof.DB(key)
            local ok = false
            for _, choice in ipairs(ns.Prof.SpecChoices(p)) do
                if choice == want then ok = true end
            end
            if not ok then
                ns.Print("|cffff4444no such specialization.|r /tm spec lists them.")
                return
            end
            pd.settings.specialization = (want ~= "auto") and want or nil
            ns.Print(string.format("%s: %s", p.name, ns.Prof.DescribeSpecs(key)))
            if ns.UI then ns.UI.Refresh() end
        end
    elseif cmd == "probe" then
        ns.Crafter.Probe()
    elseif cmd == "book" then
        local n, products, noun = ns.Prof.BookCounts(profile, book)
        ns.Print(string.format("%s book holds %d recipes (%d %s).", profile.name, n, products, noun))
    elseif cmd == "match" then
        if rest == "" then
            ns.Print("usage: /tm match <text or linked item>")
            return
        end
        local index = ns.Matcher.BuildIndex(book, profile)
        local hits = ns.Matcher.Match(rest, ns.Util.Normalize(rest), index)
        if #hits == 0 then ns.Print("no item matched.") end
        for _, h in ipairs(hits) do
            local e = book[h.itemID]
            ns.Print(string.format("  %s  |cff888888[%s%s]|r",
                e and (e.link or e.name) or h.itemID, h.tier,
                h.qtyHint and (", qty " .. h.qtyHint) or ""))
        end
    elseif cmd == "invite" then
        ns.SetInvites(ns.db.settings.invites == false)
    elseif cmd == "bark" then
        local s = ps.bark
        local secs = tonumber(rest)
        if secs then
            s.intervalSec = math.max(30, math.min(600, secs))
            s.enabled = true
            if secs ~= s.intervalSec then
                ns.Print(string.format("|cffff9900%d is outside the allowed 30 to 600 range, using %d.|r",
                    secs, s.intervalSec))
            end
            ns.Print(string.format("barking every %d seconds.", s.intervalSec))
            ns.Barker.Start(true)
        else
            ns.SetBark(not s.enabled)
        end
    elseif cmd == "disable" or cmd == "off" then
        ns.db.settings.enabled = false
        ns.Barker.Stop()
        ns.Print("|cffff4444disabled.|r No invites, whispers, barks or trade filling until /tm enable.")
    elseif cmd == "enable" or cmd == "on" then
        ns.db.settings.enabled = true
        if ps.bark.enabled then ns.Barker.Start() end
        ns.Print("|cff44ff44enabled.|r Back to: invites " .. onoff(ns.db.settings.invites ~= false)
            .. ", whisper invites " .. onoff(ps.invite.fromWhisper)
            .. ", barking " .. (ps.bark.enabled and ("|cff44ff44on|r every " .. ps.bark.intervalSec .. "s") or "|cffff4444off|r")
            .. ", trade fill " .. onoff(ns.db.settings.orders.autoFillTrade))
    elseif cmd == "market" then
        local now = ns.Now()
        ns.Print(ns.Market.Summary(ns.db, now, profile.key ~= "generic" and profile.key or nil,
            ps.bark.intervalSec))
        for _, key in ipairs(ns.Professions.Order) do
            local s15 = { ns.Market.Counts(ns.db, now, key, 900) }
            local h1 = { ns.Market.Counts(ns.db, now, key, 3600) }
            local day = { ns.Market.Counts(ns.db, now, key, 86400) }
            if day[1] > 0 or day[2] > 0 then
                local label = ns.Market.Label(h1[1], h1[2])
                ns.Print(string.format("  %-16s 15m %dS/%dB   1h %dS/%dB   today %dS/%dB   %s%s|r",
                    ns.Prof.ByKey(key).name, s15[1], s15[2], h1[1], h1[2], day[1], day[2],
                    ns.Market.LabelColor(label), label))
            end
        end
    elseif cmd == "stats" or cmd == "annotate" then
        ns.Annotators.Toggle()
    elseif cmd == "tracker" then
        ns.Tracker.Toggle()
    elseif cmd == "orders" then
        local open = ns.Orders.ActiveList()
        local _, finished = ns.Orders.Visible(ns.db.orders, false)
        if #open == 0 then
            ns.Print(finished > 0
                and string.format("no open orders. %d finished %s still saved: the Orders tab's "
                    .. "Finished button shows them.", finished, finished == 1 and "order is" or "orders are")
                or "no open orders.")
        end
        for _, o in ipairs(open) do
            ns.Print(string.format("|cffffffff#%d|r %s [%s]%s  %s",
                o.id, o.player, o.status,
                o.needsSplit and " |cffff9900SPLIT?|r" or "",
                ns.Orders.Summarise(o)))
            if (o.copperIn or 0) > 0 then
                ns.Print("    paid " .. ns.Ledger.Money(o.copperIn))
            end
        end
    elseif cmd == "order" then
        local sub, arg = rest:match("^(%S*)%s*(.*)$")
        sub = (sub or ""):lower()
        local now = ns.Now()
        if sub == "add" and arg ~= "" then
            local o = ns.Orders.Create(arg, "manual", "", {}, now, "grouped")
            ns.Print(string.format("order #%d opened for %s. Trade them the mats and it will fill itself in.", o.id, arg))
        elseif sub == "removeitem" then
            local id, name = arg:match("^(%S+)%s+(.+)$")
            local o = id and ns.Orders.ByID(tonumber(id))
            if not id then
                ns.Print("usage: /tm order removeitem <id> <item name>")
            elseif not o then
                ns.Print("no order with that id.")
            else
                local itemID = ns.Orders.FindItemByName(o, name)
                local index = itemID and ns.Orders.IndexOfItem(o, itemID)
                if not index then
                    ns.Print(string.format("no item matching '%s' on order #%d. It has: %s",
                        name, o.id, ns.Orders.Summarise(o)))
                else
                    local e = ns.Orders.BookFor(o)[itemID]
                    ns.Orders.RemoveItem(o, index, ns.Now())
                    ns.Print(string.format("removed %s from order #%d.",
                        e and (e.link or e.name) or tostring(itemID), o.id))
                    if ns.Tracker then ns.Tracker.Refresh() end
                end
            end
        elseif sub == "done" or sub == "cancel" or sub == "reopen" then
            local o = ns.Orders.ByID(tonumber(arg))
            if not o then ns.Print("no order with that id.") return end
            local status = (sub == "done" and "done") or (sub == "cancel" and "cancelled") or "grouped"
            ns.Orders.SetStatus(o, status, now)
            ns.Print(string.format("order #%d %s.", o.id, sub == "reopen" and "reopened" or (sub == "done" and "closed" or "cancelled")))
        else
            ns.Print("usage: /tm order add <player> | done <id> | cancel <id> "
                .. "| reopen <id> | removeitem <id> <item name>")
        end
    elseif cmd == "income" then
        ns.Ledger.Report()
    elseif cmd == "adv" then
        local sub = rest:lower()
        if sub == "all" or sub == "none" or sub == "rare" or sub == "epic" then
            local n = ns.Barker.ApplyAdvertiseFilter(book, sub, profile)
            ns.Print(string.format("advertising %d recipes (%s).", n, sub))
        elseif sub:sub(1, 1) == "+" or sub:sub(1, 1) == "-" then
            local on = sub:sub(1, 1) == "+"
            local n = ns.Barker.SetAdvertiseMatching(book, rest:sub(2), on)
            ns.Print(string.format("%s %d recipes matching '%s'.", on and "added" or "removed", n, rest:sub(2)))
        else
            local list = ns.Barker.AdvertisedEntries()
            ns.Print(string.format("advertising %d recipes:", #list))
            for i = 1, math.min(#list, 40) do
                ns.Print("  " .. (book[list[i].itemID].link or list[i].name))
            end
            if #list > 40 then ns.Print(string.format("  ...and %d more", #list - 40)) end
            ns.Print("usage: /tm adv epic | rare | all | none | +<text> | -<text>")
        end
    elseif cmd == "send" then
        local ok, info = ns.Barker.Tick(true)
        if not ok then ns.Print("bark skipped: " .. tostring(info)) end
    elseif cmd == "preview" then
        local msg, _, used = ns.Barker.Preview()
        if not msg then
            ns.Print("nothing to advertise. Scan your book first.")
        else
            ns.Print(string.format("next bark (%d %s, %d chars):", used, profile.craftNoun[2], #msg))
            ns.Print("  " .. msg)
        end
    elseif cmd == "try" or cmd == "trywhisper" or cmd == "tryparty" then
        if rest == "" then
            ns.Print("usage: /tm " .. cmd .. " <message>")
            return
        end
        local fn = (cmd == "try" and ns.Events.OnTradeMessage)
            or (cmd == "trywhisper" and ns.Events.OnWhisper) or ns.Events.OnParty
        local r = fn(rest, "TestDummy", { dryRun = true })
        if r then
            ns.Print(string.format("verdict |cffffffff%s|r (%s), seller %d buyer %d net %d",
                r.verdict, r.reason, r.sellerScore or 0, r.buyerScore or 0, r.netScore or 0))
            ns.Print(ns.Log.DescribeHits(r))
        end
    elseif cmd == "debug" then
        ns.db.settings.debug = not ns.db.settings.debug
        ns.Print("debug " .. onoff(ns.db.settings.debug))
    elseif cmd == "capture" then
        local s = ns.db.settings
        s.captureAll = not s.captureAll
        if s.captureAll then
            ns.Print("capture |cff44ff44on|r. Recording every Trade message, matched or not. Run /reload to flush it to disk.")
        else
            ns.Print(string.format("capture |cffff4444off|r. %d messages held.", #(ns.db.capture or {})))
        end
    elseif cmd == "status" then
        local s = ns.db.settings
        local pd = ns.Prof.Active()
        local n, products, noun = ns.Prof.BookCounts(profile, book)
        local age = pd and pd.bookScannedAt > 0 and math.floor((ns.Now() - pd.bookScannedAt) / 60) or -1
        if not ns.Enabled() then
            ns.Print("|cffff4444TradeMaster is disabled.|r /tm enable to switch it on.")
        end
        ns.Print(string.format("active profession: %s   known: %s",
            profile.key ~= "generic" and profile.name or "none", table.concat(ns.Prof.Known(), ", ")))
        ns.Print(string.format("invites %s (all scanned)   barking %s (%ds, timer %s, active only)   capture %s   debug %s",
            onoff(ns.db.settings.invites ~= false), onoff(ps.bark.enabled), ps.bark.intervalSec,
            ns.Barker.ticker and ("next in " .. ns.Barker.SecondsUntilDue() .. "s") or "stopped",
            onoff(s.captureAll), onoff(s.debug)))
        ns.Print(string.format("advertising %d recipes", #ns.Barker.AdvertisedEntries()))
        ns.Print(string.format("book: %d recipes (%d %s), scanned %s",
            n, products, noun, age >= 0 and (age .. " min ago") or "never"))
        ns.Print(string.format("log: %d entries   capture: %d messages", #ns.db.log, #(ns.db.capture or {})))
    elseif cmd == "out" then
        if rest == "" then
            ns.Print("chat windows:")
            for i = 1, NUM_CHAT_WINDOWS do
                local name = GetChatWindowInfo(i)
                if name and name ~= "" then
                    ns.Print(string.format("  %d = %s%s", i, name,
                        ns.db.settings.outputFrame == i and "  |cff44ff44(current)|r" or ""))
                end
            end
            ns.Print("usage: /tm out <number>")
        else
            local n = tonumber(rest)
            if n and _G["ChatFrame" .. n] then
                ns.db.settings.outputFrame = n
                ns.Print("TradeMaster output now prints here.")
            else
                ns.Print("no such chat window. Run /tm out to list them.")
            end
        end
    elseif cmd == "clearcapture" then
        ns.db.capture = {}
        ns.Print("capture cleared.")
    elseif cmd == "clearflags" then
        local n = 0
        for _, st in pairs(ns.db.players) do
            if st.flaggedSeller then st.flaggedSeller = nil; n = n + 1 end
        end
        ns.Print(string.format("cleared the auto seller flag on %d players.", n))
    elseif cmd == "log" then
        local entries = ns.Log.Recent(10)
        if #entries == 0 then ns.Print("log is empty.") end
        for i = #entries, 1, -1 do
            ns.Print(ns.Log.Describe(entries[i]))
            ns.Print(ns.Log.DescribeHits(entries[i]))
        end
    else
        ns.Print("Commands: /tm (open window), /tm prof [name], /tm scan, /tm book, /tm match <text>,")
        ns.Print("  /tm try <msg>, /tm trywhisper <msg>, /tm tryparty <msg>, /tm bark [secs],")
        ns.Print("  /tm send, /tm preview, /tm adv epic|rare|all|none|+text|-text,")
        ns.Print("  /tm invite, /tm log, /tm debug, /tm capture, /tm clearcapture,")
        ns.Print("  /tm orders, /tm order add|done|cancel|reopen|removeitem, /tm craft,")
        ns.Print("  /tm probe, /tm spec [auto|none|off|<name>],")
        ns.Print("  /tm tracker,")
        ns.Print("  /tm income, /tm market, /tm annotate, /tm clearflags, /tm out [n],")
        ns.Print("  /tm status, /tm test, /tm disable, /tm enable")
    end
end

-- Key binding names shown in the game's Key Bindings menu.
BINDING_HEADER_TRADEMASTER = "TradeMaster"
BINDING_NAME_TRADEMASTER_BARK = "Send bark to Trade"
BINDING_NAME_TRADEMASTER_TOGGLE = "Toggle TradeMaster window"

-- Called from a key binding, which IS a hardware event, so the protected
-- SendChatMessage is allowed here where a timer callback would be blocked.
function TradeMaster_BarkNow()
    local ok, info = ns.Barker.Tick(true)
    if not ok then ns.Print("bark skipped: " .. tostring(info)) end
end

function TradeMaster_Toggle()
    if ns.UI and ns.UI.Toggle then ns.UI.Toggle() else ns.Print("UI not loaded.") end
end

SLASH_TRADEMASTER1 = "/tm"
SLASH_TRADEMASTER2 = "/trademaster"
SlashCmdList["TRADEMASTER"] = HandleSlash
