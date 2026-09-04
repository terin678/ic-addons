local addonName, ns = ...

ns.Inviter = ns.Inviter or {}
local Inviter = ns.Inviter

Inviter.whisperCount = 0

local WHISPER_WARN_AT = 60
local WHISPER_DELAY = 1.5

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

-- What this request would get: which book answers, which template, and the text
-- once it is filled in. Nothing is sent and nothing is recorded, so the
-- confirmation window can show the message before anyone commits to it.
function Inviter.Plan(name, matched, ctx)
    local short = name:gsub("%-.*", "")
    -- ctx.profession names the book that matched; older callers get the active one.
    local key = ctx and ctx.profession
    local pd = key and ns.Prof.DB(key)
    local settings = (pd and pd.settings or ns.PS()).invite
    local book = pd and pd.book or ns.Book()
    local profile = key and ns.Prof.ByKey(key) or ns.Prof.Current()

    -- Someone who linked the pattern already has its reagent list in front of
    -- them; handing it back is noise.
    local withPatterns = not ns.Util.HasCraftLink(ctx and ctx.text)
    if ctx and ctx.withPatterns ~= nil then withPatterns = ctx.withPatterns end

    local reply = ns.Reply.Compose({
        book = book,
        matched = matched,
        cannotDo = ctx and ctx.cannotDo,
        whisper = settings.whisper,
        profile = profile,
        player = short,
        base = "invite",
        withPatterns = withPatterns,
    })

    local have = {}
    for _, entry in ipairs(reply.have) do
        have[#have + 1] = entry.link or entry.name
    end

    return {
        profile = profile, settings = settings, template = reply.template,
        haveText = #have > 0 and table.concat(have, " ") or nil,
        lack = reply.lack,
        text = reply.text,
        reply = reply,
    }
end

-- ctx.whisperText overrides the template, which is how an edited message from the
-- confirmation window gets sent.
function Inviter.Invite(name, matched, ctx)
    if not ns.Enabled() then return end
    local short = name:gsub("%-.*", "")
    local plan = Inviter.Plan(short, matched, ctx)
    local key = ctx and ctx.profession
    local now = ns.Now()

    DoInvite(short)

    local state = ns.Players.Get(ns.db, short)
    state.lastInviteAt = now

    if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.MAP_PING) end

    ns.Print(string.format("invited %s for %s%s%s", short,
        plan.haveText or ("a " .. plan.profile.craftNoun[1]),
        (key and key ~= ns.db.activeProfession) and ("  |cff888888" .. plan.profile.name .. "|r") or "",
        #plan.lack > 0 and ("  |cffff9900cannot do: " .. table.concat(plan.lack, " ") .. "|r") or ""))

    if not plan.settings.whisper.enabled then return end

    local last = state.lastWhisperAt or 0
    if (now - last) < plan.settings.whisper.cooldownSec then return end
    state.lastWhisperAt = now

    -- With nothing named, their next line is the answer to our question.
    if not plan.haveText then state.awaitingItem = now end

    local override = ctx and ctx.whisperText
    C_Timer.After(WHISPER_DELAY, function()
        if override and override ~= "" then
            Inviter.SayText(short, override, plan.profile)
        else
            Inviter.SayComposed(short, plan.text, plan.profile)
        end
    end)
end

-- Sends a whisper immediately, subject to the short conversational cooldown.
-- One auto-reply per player per replyCooldownSec, whichever entry point asked.
local function ReplyDue(name, profile)
    local pd = ns.db.professions and ns.db.professions[profile.key]
    local inv = (pd and pd.settings or ns.PS()).invite
    local now = ns.Now()
    local state = ns.Players.Get(ns.db, name)
    if (now - (state.lastReplyAt or 0)) < (inv.whisper.replyCooldownSec or 10) then
        return false
    end
    state.lastReplyAt = now
    return true
end

-- profile picks whose templates and cooldown apply; defaults to the active one.
function Inviter.Say(name, template, vars, profile)
    if not ns.Enabled() then return false end
    if not template or template == "" then return false end
    profile = profile or ns.Prof.Current()
    if not ReplyDue(name, profile) then return false end
    return Inviter.SayText(name, Inviter.Render(template, vars, name, profile), profile)
end

-- Text that Reply.Compose already rendered, because it had to render it to
-- measure it against the whisper cap. Its own entry point rather than a nil-vars
-- overload of Say: one forgotten argument there would whisper a customer a raw
-- "{item}".
function Inviter.SayComposed(name, text, profile)
    if not ns.Enabled() then return false end
    if not text or text == "" then return false end
    profile = profile or ns.Prof.Current()
    if not ReplyDue(name, profile) then return false end
    return Inviter.SayText(name, text, profile)
end

-- They are in the group because we asked what they needed, and the answer was
-- something we cannot make. Leaving them there holds a slot for a trade that is
-- not going to happen.
function Inviter.Drop(name)
    if not name or name == "" then return false end
    if not (UnitInParty(name) or UnitInRaid(name)) then return false end
    -- Only the leader can, and never mid-fight.
    if InCombatLockdown and InCombatLockdown() then return false end
    if UninviteUnit then
        UninviteUnit(name)
        return true
    end
    return false
end

-- Pure. Pulls the player name out of a CHAT_MSG_SYSTEM decline notice by turning
-- the client's own localized format string (ERR_DECLINE_GROUP_S, "%s declines
-- your group invitation.") into a pattern. Hardcoding the English wording would
-- quietly do nothing on any other locale. (CutMaster 1.2.0)
function Inviter.DeclinedName(text, fmt)
    if not text or not fmt then return nil end
    local pre, post = fmt:match("^(.-)%%s(.*)$")
    if not pre then return nil end
    local pattern = "^" .. ns.Util.EscapePattern(pre) .. "(.+)" .. ns.Util.EscapePattern(post) .. "$"
    return text:match(pattern)
end

-- Sends text as it stands, with no template and no cooldown: the player has read
-- this one and pressed the button, which is a decision the addon should not
-- second-guess.
function Inviter.SayText(name, text, profile)
    if not ns.Enabled() then return false end
    if not text or text == "" then return false end
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
