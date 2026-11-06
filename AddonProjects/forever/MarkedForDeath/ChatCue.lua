local addonName, ns = ...

--[[
ChatCue: a sound when one chosen word is said in group chat. Off by default
(settings.cue = { enabled, word, sound }).

Owned by lane D (deaths and chat). Spec sections 4 and 12.

    ChatCue.Matches(text, word)     whole word, any case; pure
    ChatCue.Allow(state, now)       at most one sound per MIN_GAP seconds; pure, mutates state
    ChatCue.Sound(value)            what the sound setting names; nil when unset (no default)

The frame half registers the chat events only while the cue is on with a word and a sound (idle
means zero work), and stays quiet for a message the client hands over as a secret value:
it cannot be read, so it cannot be matched. It returns early on IC_HEADLESS.
]]

ns.ChatCue = ns.ChatCue or {}
local ChatCue = ns.ChatCue

local Restrict = LibStub("LibICRestrict-1.0")

ChatCue.MIN_GAP = 4   -- seconds between two sounds, so a raid chanting the word is one sound

ChatCue.EVENTS = {
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER",
}

-- Whether text says word as a whole word, any case: "fart" matches "FART!" and not
-- "farther". A word with spaces matches as that phrase. Pure.
function ChatCue.Matches(text, word)
    if type(text) ~= "string" or type(word) ~= "string" then return false end
    word = word:match("^%s*(.-)%s*$"):lower()
    if word == "" then return false end
    local escaped = word:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    return text:lower():find("%f[%w]" .. escaped .. "%f[%W]") ~= nil
end

-- Whether a sound may play at `now`; records it when yes. Pure apart from state.
function ChatCue.Allow(state, now)
    if state.lastAt and now - state.lastAt < ChatCue.MIN_GAP then return false end
    state.lastAt = now
    return true
end

--------------------------------------------------------------------------------
-- The client
--------------------------------------------------------------------------------

local KEY = "chatcue"
local listening = false
local state = {}

local function Settings()
    return ns.db and ns.db.settings or nil
end

-- What settings.cue.sound names: { kind = "kit", id } for a sound kit id (a number, or
-- digits), { kind = "file", path } for a file path, nil for nothing set. There is no
-- default: the player picks the sound. Pure.
function ChatCue.Sound(value)
    local id = tonumber(value)
    if id then return { kind = "kit", id = id } end
    if type(value) ~= "string" then return nil end
    value = value:match("^%s*(.-)%s*$")
    if value == "" then return nil end
    return { kind = "file", path = value }
end

-- Plays settings.cue.sound. Every call guarded: a client without one plays nothing.
function ChatCue.Play()
    local s = Settings()
    local sound = ChatCue.Sound(s and s.cue and s.cue.sound)
    if not sound then return end
    if sound.kind == "kit" and type(PlaySound) == "function" then
        pcall(PlaySound, sound.id, "Master")
    elseif sound.kind == "file" and type(PlaySoundFile) == "function" then
        pcall(PlaySoundFile, sound.path, "Master")
    end
end

local function OnChat(_, text)
    local s = Settings()
    if not s or s.enabled == false or not s.cue or s.cue.enabled ~= true then return end
    local plain = Restrict.Readable(text)
    if plain == nil then return end
    if not ChatCue.Matches(plain, s.cue.word) then return end
    local now = Restrict.Readable(GetTime and GetTime()) or 0
    if not ChatCue.Allow(state, now) then return end
    ChatCue.Play()
end

-- Registers the chat events while the cue is on with a word, and drops them otherwise.
-- Call after any change to settings.cue.
function ChatCue.Sync()
    local s = Settings()
    local want = s ~= nil and s.enabled ~= false and type(s.cue) == "table" and s.cue.enabled == true
        and type(s.cue.word) == "string" and s.cue.word:match("%w") ~= nil
        and ChatCue.Sound(s.cue.sound) ~= nil
    if want == listening then return end
    listening = want
    for _, event in ipairs(ChatCue.EVENTS) do
        if want then ns.Events.On(event, KEY, OnChat) else ns.Events.Off(event, KEY) end
    end
end

ns.OnReady("chatcue", function()
    if IC_HEADLESS then return end
    ChatCue.Sync()
end)
