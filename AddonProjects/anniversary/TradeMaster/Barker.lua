local addonName, ns = ...

ns.Barker = ns.Barker or {}
local Barker = ns.Barker

local MAX_LEN = 255
local POLL_INTERVAL = 5

-- Pure.
function Barker.IsDue(lastSentAt, now, intervalSec)
    return (now - (lastSentAt or 0)) >= intervalSec
end

function Barker.SecondsUntilDue()
    local s = ns.PS().bark
    local left = s.intervalSec - (ns.Now() - (s.lastSentAt or 0))
    return left > 0 and math.floor(left) or 0
end

-- Pure. Fills the template with as many item links as fit under maxLen and
-- reports where the rotation cursor should land next. Accepts the legacy
-- {gems} token as well as {items}.
function Barker.Fit(entries, cursor, template, maxLen, perBark)
    if not entries or #entries == 0 then return nil end
    if not template then return nil end
    local token = template:find("{items}", 1, true) and "{items}"
        or (template:find("{gems}", 1, true) and "{gems}") or nil
    if not token then return nil end

    maxLen = maxLen or MAX_LEN
    cursor = cursor or 1
    if cursor < 1 or cursor > #entries then cursor = 1 end

    local shell = template:gsub(token, "")
    local budget = maxLen - #shell

    local picked, used, length = {}, 0, 0
    local idx = cursor

    for _ = 1, math.min(perBark, #entries) do
        local link = entries[idx].link
        local addition = #link + (used > 0 and 1 or 0)
        if length + addition > budget then break end
        picked[#picked + 1] = link
        length = length + addition
        used = used + 1
        idx = idx + 1
        if idx > #entries then idx = 1 end
    end

    if used == 0 then return nil end

    local msg = template:gsub(token, table.concat(picked, " "), 1)
    return msg, idx, used
end

-- Books scanned before bindType was captured have no idea what is soulbound.
-- Fill it in from the item cache on demand.
local function BindTypeOf(itemID, e)
    if e.bindType ~= nil then return e.bindType end
    local bind = select(14, GetItemInfo(itemID))
    if bind ~= nil then e.bindType = bind end
    return bind
end

function Barker.AdvertisedEntries(book)
    book = book or ns.Book()
    local list = {}
    for itemID, e in pairs(book) do
        if e.advertise and not e.stale and e.link and BindTypeOf(itemID, e) ~= 1 then
            list[#list + 1] = {
                itemID = itemID, link = e.link,
                header = e.header or "", name = e.name or "",
            }
        end
    end
    table.sort(list, function(a, b)
        if a.header ~= b.header then return a.header < b.header end
        return a.name < b.name
    end)
    return list
end

-- Locale safe: matches both "Trade" and "Trade - City".
function Barker.TradeChannel()
    local channels = { GetChannelList() }
    for i = 1, #channels, 3 do
        local id, name = channels[i], channels[i + 1]
        if type(name) == "string" and name:find("Trade", 1, true) then
            return id
        end
    end
    return nil
end

function Barker.BlockReason()
    local s = ns.PS().bark
    if not ns.Enabled() then return "TradeMaster is disabled" end
    if not ns.Prof.Active() then return "no active profession" end
    if not s.enabled then return "disabled" end
    if s.pauseCombat and (InCombatLockdown() or UnitAffectingCombat("player")) then
        return "in combat"
    end
    if s.pauseInstance and IsInInstance() then return "in an instance" end
    if s.onlyInCity and not Barker.TradeChannel() then return "no trade channel" end
    return nil
end

function Barker.Tick(force)
    local s = ns.PS().bark

    if not ns.Enabled() then return false, "TradeMaster is disabled" end
    if not ns.Prof.Active() then return false, "no active profession" end

    if not force then
        local blocked = Barker.BlockReason()
        if blocked then return false, blocked end
    end

    local channel = Barker.TradeChannel()
    if not channel then return false, "no trade channel" end

    local entries = Barker.AdvertisedEntries()
    local msg, nextCursor, used = Barker.Fit(entries, s.cursor, s.template, MAX_LEN, s.perBark)
    if not msg then return false, "nothing to advertise" end

    SendChatMessage(msg, "CHANNEL", nil, channel)

    s.cursor = nextCursor
    s.lastSentAt = ns.Now()
    Barker.pending = false
    Barker.lastSkipReason = nil
    return true, used
end

-- Bulk advertise selection through the profession's rule. BoP can never reach
-- a customer, so it is never advertised; that overrides even "all".
function Barker.ApplyAdvertiseFilter(book, mode, profile)
    profile = profile or ns.Prof.Current()
    local n = 0
    for _, e in pairs(book) do
        if not e.stale then
            e.advertise = profile.bulkFilterFn(e, mode, profile) and true or false
            if e.bindType == 1 then e.advertise = false end
            if e.advertise then n = n + 1 end
        end
    end
    return n
end

function Barker.SetAdvertiseMatching(book, needle, on)
    local n = 0
    needle = ns.Util.Normalize(needle)
    for _, e in pairs(book) do
        if not e.stale and e.name and ns.Util.Normalize(e.name):find(needle, 1, true) then
            e.advertise = on
            n = n + 1
        end
    end
    return n
end

function Barker.Stop()
    if Barker.ticker then
        Barker.ticker:Cancel()
        Barker.ticker = nil
    end
end

-- SendChatMessage to a public channel is PROTECTED on this client: it only
-- works from a hardware event. The timer only ARMS a bark and tells the user.
function Barker.Alert()
    local blocked = Barker.BlockReason()
    if blocked then return false, blocked end

    Barker.pending = true
    if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION) end
    ns.Print("|cffffcc00bark ready|r. Press your TradeMaster bark key, or use /tm send.")
    return true
end

function Barker.Poll()
    local s = ns.PS().bark
    if not s.enabled or not ns.Enabled() then return end
    if Barker.pending then return end
    if not Barker.IsDue(s.lastSentAt, ns.Now(), s.intervalSec) then return end

    local ok, reason = Barker.Alert()
    if not ok then
        if reason ~= Barker.lastSkipReason then
            ns.Print("bark due but skipped: " .. tostring(reason))
            Barker.lastSkipReason = reason
        end
    else
        Barker.lastSkipReason = nil
    end
end

function Barker.Start(immediate)
    Barker.Stop()
    if immediate then
        local ok, info = Barker.Tick()
        if not ok then ns.Print("first bark skipped: " .. tostring(info)) end
    end
    Barker.ticker = C_Timer.NewTicker(POLL_INTERVAL, Barker.Poll)
end

-- After the active profession changes: the timer follows the new bark settings.
function Barker.Restart()
    Barker.pending = false
    Barker.Stop()
    if ns.Enabled() and ns.PS().bark.enabled then Barker.Start() end
end

function Barker.Preview()
    local entries = Barker.AdvertisedEntries()
    local s = ns.PS().bark
    return Barker.Fit(entries, s.cursor, s.template, MAX_LEN, s.perBark)
end
