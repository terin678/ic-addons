local addonName, ns = ...

ns.Message = ns.Message or {}
local Message = ns.Message

--[[
The line, and whether it can go out.

There used to be an assembler here: two teams, their needs, a template with tokens
and a ladder of steps that gave up detail to fit 255 characters. The guild's message
is one line ending in "/w me", so all of that was machinery for a shape nobody used.
Now the raid leader's text IS the message, and this file only has to say whether
there is one and whether a chat channel will take it.

All pure.
]]

local MAX_LEN = ns.Doc.MAX_TEXT     -- bytes SendChatMessage accepts

Message.MAX_LEN = MAX_LEN

-- Pure. Bytes, as SendChatMessage counts them.
function Message.Length(s)
    return #tostring(s or "")
end

--[[
Pure. The line to send, or nil and the reason there is none. The reason is written
to be shown to an officer, because a Bark button that does nothing has to say what
it is waiting for.
]]
function Message.Ready(doc)
    local text = ns.Util.Trim((doc or {}).text or "")
    if text == "" then
        return nil, "no message set yet: a raid leader writes one on the Message tab"
    end
    return text
end

--[[
Pure. The last look before it goes out. Returns ok, reason.

The unclosed-colour check matters: a truncation that cut a |c open would colour
everything after it in the chat window, including other people's lines.
]]
function Message.Validate(msg, maxLen)
    maxLen = maxLen or MAX_LEN
    if not msg or msg == "" then return false, "there is nothing to send" end
    if #msg > maxLen then
        return false, string.format("%d characters; the limit is %d", #msg, maxLen)
    end
    if msg:find("\n") or msg:find("\r") then
        return false, "a chat message cannot contain a line break"
    end
    local opens = select(2, msg:gsub("|c%x%x%x%x%x%x%x%x", ""))
    local closes = select(2, msg:gsub("|r", ""))
    if opens ~= closes then
        return false, "a colour code is left open, which would colour the rest of the chat"
    end
    return true
end
