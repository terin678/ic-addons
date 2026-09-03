local addonName, ns = ...

ns.Inviter = ns.Inviter or {}
local Inviter = ns.Inviter

Inviter.whisperCount = 0

local WHISPER_WARN_AT = 60
local WHISPER_DELAY = 1.5

-- Keeps a whisper inside the 255 character cap once links are expanded.
local MAX_ITEMS_PER_WHISPER = 3

-- Pure. Reasons the invite cannot happen regardless of message content.
function Inviter.BlockReason(playerState, now, groupSize, settings)
    if settings.enabled == false then return "invites disabled" end
    if groupSize >= settings.maxParty then return "group full" end
    if playerState and playerState.lastInviteAt
        and (now - playerState.lastInviteAt) < settings.playerCooldownSec then
        return "cooldown"
    end
    return nil
end

local function DoInvite(name)
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        C_PartyInfo.InviteUnit(name)
    elseif InviteUnit then
        InviteUnit(name)
    else
        ns.Print("|cffff4444no invite API available on this client.|r")
    end
end

function Inviter.Invite(name, matched, ctx)
    if not ns.Enabled() then return end
    local short = name:gsub("%-.*", "")
    -- ctx.profession names the book that matched; older callers get the active one.
    local key = ctx and ctx.profession
    local pd = key and ns.Prof.DB(key)
    local settings = (pd and pd.settings or ns.PS()).invite
    local book = pd and pd.book or ns.Book()
    local profile = key and ns.Prof.ByKey(key) or ns.Prof.Current()
    local now = ns.Now()

    DoInvite(short)

    local state = ns.Players.Get(ns.db, short)
    state.lastInviteAt = now

    if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.MAP_PING) end

    -- Acknowledge EVERY item they asked for, not just the first.
    local have = {}
    for i = 1, math.min(#(matched or {}), MAX_ITEMS_PER_WHISPER) do
        local entry = book[matched[i].itemID]
        if entry then have[#have + 1] = entry.link or entry.name end
    end
    local haveText = #have > 0 and table.concat(have, " ") or nil

    local lack = {}
    for i = 1, math.min(#((ctx and ctx.cannotDo) or {}), MAX_ITEMS_PER_WHISPER) do
        lack[i] = ctx.cannotDo[i]
    end

    ns.Print(string.format("invited %s for %s%s%s", short, haveText or ("a " .. profile.craftNoun[1]),
        (key and key ~= ns.db.activeProfession) and ("  |cff888888" .. profile.name .. "|r") or "",
        #lack > 0 and ("  |cffff9900cannot do: " .. table.concat(lack, " ") .. "|r") or ""))

    if not settings.whisper.enabled then return end

    local last = state.lastWhisperAt or 0
    if (now - last) < settings.whisper.cooldownSec then return end
    state.lastWhisperAt = now

    local template, vars
    if not haveText then
        template, vars = settings.whisper.templateNoItem, {}
        state.awaitingItem = now
    elseif #lack > 0 then
        template = settings.whisper.partialTemplate
        vars = { have = haveText, lack = table.concat(lack, " ") }
    else
        template, vars = settings.whisper.template, { item = haveText }
    end

    C_Timer.After(WHISPER_DELAY, function()
        Inviter.Say(short, template, vars, profile)
    end)
end

-- Sends a whisper immediately, subject to the short conversational cooldown.
-- profile picks whose templates and cooldown apply; defaults to the active one.
function Inviter.Say(name, template, vars, profile)
    if not ns.Enabled() then return false end
    if not template or template == "" then return false end
    profile = profile or ns.Prof.Current()
    local pd = ns.db.professions and ns.db.professions[profile.key]
    local inv = (pd and pd.settings or ns.PS()).invite
    local now = ns.Now()
    local state = ns.Players.Get(ns.db, name)
    local last = state.lastReplyAt or 0
    if (now - last) < (inv.whisper.replyCooldownSec or 10) then
        return false
    end
    state.lastReplyAt = now

    local text = Inviter.Render(template, vars, name, profile)
    SendChatMessage(text, "WHISPER", nil, name)
    Inviter.whisperCount = Inviter.whisperCount + 1
    if Inviter.whisperCount == WHISPER_WARN_AT then
        ns.Print("|cffff9900" .. WHISPER_WARN_AT ..
            " whispers sent this session. Watch the game whisper throttle.|r")
    end
    return true
end

-- Pure. Placeholder substitution: named vars, {player}, then leftovers. The
-- legacy {gem}/{gems} tokens are honoured too.
function Inviter.Render(template, vars, name, profile)
    local text = template
    for k, v in pairs(vars or {}) do
        text = text:gsub("{" .. k .. "}", function() return v end)
        if k == "item" then text = text:gsub("{gem}", function() return v end) end
        if k == "items" then text = text:gsub("{gems}", function() return v end) end
    end
    text = text:gsub("{player}", name or "")
    local noun = "your " .. ((profile and profile.craftNoun[1]) or "item")
    text = text:gsub("{item}", noun):gsub("{gem}", noun)
    text = text:gsub("{items}", ""):gsub("{gems}", "")
    return text
end
