-- Listens to group chat for one word and answers it with a sound. Not a
-- configured feature: no setting, no command, no row in Docs.md. It rides the
-- master switch in Core.lua like everything else, so /mfd off silences it too.
local MFD = _G.MarkedForDeath or {}

MFD.ChatCue = MFD.ChatCue or {}
local ChatCue = MFD.ChatCue

-- Case-insensitive, whole word only, so "farther" and "Farthing" do not
-- trigger it. %f[%a] / %f[%A] are Lua's frontier pattern, matched against the
-- lower-cased message so FART, Fart and fart all count. Pure.
function ChatCue.Matches(message)
    if type(message) ~= "string" then
        return false
    end
    return string.find(string.lower(message), "%f[%a]fart%f[%A]") ~= nil
end

-- Minimum seconds between plays, so a raid chanting the word does not turn
-- into a wall of the same sound on top of itself. Pure: takes and returns
-- state rather than reading the clock itself.
ChatCue.MIN_GAP = 4

function ChatCue.Allow(state, now)
    if state.lastAt and (now - state.lastAt) < ChatCue.MIN_GAP then
        return false
    end
    state.lastAt = now
    return true
end

-- ---------------------------------------------------------------- client --

-- Path relative to the game root, as PlaySoundFile requires.
local CUE_SOUND = "Interface\\AddOns\\MarkedForDeath\\Sounds\\Cue2.mp3"

ChatCue.state = { lastAt = nil }

local function playCue()
    if type(PlaySoundFile) ~= "function" then
        return
    end
    pcall(PlaySoundFile, CUE_SOUND, "Master")
end

local EVENTS = {
    "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER",
}

MFD.RegisterInit(function()
    local frame = CreateFrame("Frame")
    for _, event in ipairs(EVENTS) do
        frame:RegisterEvent(event)
    end

    frame:SetScript("OnEvent", function(_, _, message)
        if not MFD.IsEnabled() then
            return
        end
        if not ChatCue.Matches(message) then
            return
        end
        if not ChatCue.Allow(ChatCue.state, GetTime()) then
            return
        end
        playCue()
    end)
end)

_G.MarkedForDeath = MFD
