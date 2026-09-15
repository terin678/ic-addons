local addonName, ns = ...

ns.Sounds = ns.Sounds or {}
local Sounds = ns.Sounds

--[[
The soundboard: what can be played, whether this character is allowed to
play it right now, and the one line of chat that asks the bot to do it.

Nothing here reaches Discord. SendChatMessage is the whole interface -- see
Core.lua's file comment -- so "firing" a sound means putting a line the bot
recognises into chat and nothing more. Whether it is actually heard depends on
the bot being up, /chatlog being on, and the id below matching a row in the
bot's config.json. Docs/JamminWithJam.md says so; this file cannot check it.

The catalogue here and the bot's config.json are two files in two languages
with no shared storage, so a sound added to one and not the other fires a
chat line nobody is listening for. Keep them in step by hand.
]]

-- Every mention of the bot elsewhere assumes this exact prefix. Not a
-- setting: the addon and the bot must agree on it, and a player-editable
-- value would let one person's addon stop matching everyone else's bot.
Sounds.TRIGGER = "!jam"

-- id must match a key in the bot's config.json exactly (case-sensitive, no
-- spaces -- it is the second word of a chat line). cooldownSec is enforced
-- here for this character only; the bot keeps its own, shared, cooldown so
-- two different players cannot chain two different sounds back to back.
local CATALOGUE = {
    { id = "airhorn", label = "Air Horn", officerOnly = false, cooldownSec = 20 },
    { id = "applause", label = "Applause", officerOnly = false, cooldownSec = 15 },
    { id = "sadtrombone", label = "Sad Trombone", officerOnly = false, cooldownSec = 15 },
    { id = "wipesiren", label = "Wipe Siren", officerOnly = true, cooldownSec = 30 },
}

-- Pure.
function Sounds.List()
    return CATALOGUE
end

-- Pure.
function Sounds.ById(id)
    for _, sound in ipairs(CATALOGUE) do
        if sound.id == id then return sound end
    end
    return nil
end

-- Pure. The exact text SendChatMessage carries. Anything the bot's regex has
-- to match lives in exactly one place: this function and its mirror in
-- DiscordBots/JamminWithJam/src/chatLogParser.js.
function Sounds.ChatLine(sound)
    return Sounds.TRIGGER .. " " .. sound.id
end

-- Pure. rankIndex 0 is the guild master; a LARGER number is a LOWER rank, so
-- this is a ceiling, not a floor. nil is not permission: a roster that has
-- not loaded yet must not let anybody play an officer-only sound.
function Sounds.IsOfficer(rankIndex, threshold)
    if type(rankIndex) ~= "number" then return false end
    return rankIndex <= (threshold or 0)
end

-- Pure. Seconds until this character may play this sound again, floored at 0.
function Sounds.SecondsUntilReady(lastFiredAt, now, cooldownSec)
    return math.max(0, (lastFiredAt or 0) + (cooldownSec or 0) - (now or 0))
end

-- Pure. The chat type SendChatMessage wants for a saved channel setting.
-- Every value here is a broadcast type with no separate id or target to look
-- up, unlike a custom channel (Trade, LookingForGroup) -- see Bark.Channel in
-- GuildRecruitment for the shape that needs one.
function Sounds.ChatType(channel)
    return channel or "GUILD"
end

--[[
Pure. Why the sound will not play, or nil. Widest reason first: the addon,
then this character's rank, then this character's own cooldown, then the
world. The UI shows the first one, and a reason that changes depending on
which check ran first is worse than no reason at all.
]]
function Sounds.BlockReason(state)
    if not state.addonEnabled then return "JamminWithJam is disabled" end
    if state.officerOnly and not state.isOfficer then
        return "officers only"
    end
    if (state.secondsLeft or 0) > 0 then
        return string.format("on cooldown for %ds", math.ceil(state.secondsLeft))
    end
    if state.channel == "GUILD" and not state.inGuild then
        return "you are not in a guild"
    end
    return nil
end

-- The only function here that reads the world. Everything above can be
-- handed a table made up in a test.
function Sounds.MyRankIndex()
    if not (IsInGuild and IsInGuild()) then return nil end
    if type(GetNumGuildMembers) ~= "function" or type(GetGuildRosterInfo) ~= "function" then
        return nil
    end
    local me = ns.Util.Trim(UnitName and UnitName("player") or "")
    for i = 1, (GetNumGuildMembers() or 0) do
        local name, _, rankIndex = GetGuildRosterInfo(i)
        if name and (name:match("^([^%-]+)") or name) == me then
            return type(rankIndex) == "number" and rankIndex or nil
        end
    end
    return nil
end

function Sounds.ReadState(sound)
    local s = ns.db.settings
    local now = ns.Now()
    return {
        addonEnabled = ns.Enabled(),
        officerOnly = sound.officerOnly,
        isOfficer = Sounds.IsOfficer(Sounds.MyRankIndex(), s.officerRankIndex),
        secondsLeft = Sounds.SecondsUntilReady(ns.cdb.cooldowns[sound.id], now, sound.cooldownSec),
        channel = s.channel,
        inGuild = (IsInGuild and IsInGuild()) and true or false,
    }
end

--[[
Sends. Reached only from a hardware event -- the soundboard's Play button, a
key binding, or /jam play -- because a chat line typed in response to one of
those is exactly the case client-api.md documents as required for a public
channel message on this client.
]]
function Sounds.Fire(id)
    local sound = Sounds.ById(id)
    if not sound then
        return false, string.format("no sound called %q. /jam list names them all.", id)
    end

    local state = Sounds.ReadState(sound)
    local blocked = Sounds.BlockReason(state)
    if blocked then
        ns.Log.Add("skipped", "Sounds", sound.label, blocked)
        return false, blocked
    end

    SendChatMessage(Sounds.ChatLine(sound), Sounds.ChatType(state.channel))
    ns.cdb.cooldowns[sound.id] = ns.Now()

    ns.Log.Add("sent", "Sounds", sound.label, Sounds.ChatLine(sound))
    return true, sound.label
end
