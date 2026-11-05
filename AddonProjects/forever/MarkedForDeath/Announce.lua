local addonName, ns = ...

--[[
Announce: the pre-pull line and callout lines. Pure: no client call, ever; every function
takes its tables as arguments. DeathWatch.lua sends what these decide, through LibICChat.

Owned by lane D (deaths and chat). Spec section 6.4.

    Announce.Lines(resolved)        the seat plan as chat lines, Skull first
    Announce.Decide(lines, state)   send, or refuse with the reason the button shows
    Announce.Command(rest)          /mfd announce, /mfd announce on|off

A pre-pull line after the pull is wrong, so these lines are never held through a chat
lockdown: they go now or not at all.
]]

ns.Announce = ns.Announce or {}
local Announce = ns.Announce

Announce.MAX_BYTES = 255    -- the longest line the client sends
Announce.MAX_LINES = 3      -- lines one press may post; past this the rest are cut
Announce.SEPARATOR = " | "

local ICON_NAMES = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }

-- One part per seat: "Skull>Kill 1", "Moon>Sheep Malexis", "Star>Sheep (nobody)".
local function Part(record)
    local def = ns.CC and ns.CC.INTENTS and ns.CC.INTENTS[record.intent]
    local label = (def and def.label or tostring(record.intent)) .. " " .. tostring(record.ordinal or 1)
    local icon = ICON_NAMES[record.icon] or ("icon " .. tostring(record.icon))
    local owner = ""
    if type(record.owner) == "string" then
        owner = " " .. record.owner
    elseif record.owner == false then
        owner = " (nobody)"
    end
    return icon .. ">" .. label .. owner
end

-- resolved: Seats.Resolve's answer (seats in Seats.Before order). Returns a list of lines,
-- each under MAX_BYTES and cut only between whole seats, at most MAX_LINES, the last one
-- saying how many seats did not fit. An empty plan gives an empty list.
function Announce.Lines(resolved)
    local parts = {}
    for _, record in ipairs((resolved or {}).seats or {}) do parts[#parts + 1] = Part(record) end
    local lines, current = {}, nil
    local placed = 0
    for i, part in ipairs(parts) do
        local candidate = current and (current .. Announce.SEPARATOR .. part) or part
        if #candidate <= Announce.MAX_BYTES then
            current = candidate
        else
            if #lines + 1 >= Announce.MAX_LINES then break end
            lines[#lines + 1] = current
            current = part:sub(1, Announce.MAX_BYTES)
        end
        placed = i
    end
    if current then lines[#lines + 1] = current end
    local left = #parts - placed
    if left > 0 then
        local tail = string.format(" (+%d more)", left)
        local last = lines[#lines]
        if #last + #tail > Announce.MAX_BYTES then last = last:sub(1, Announce.MAX_BYTES - #tail) end
        lines[#lines] = last .. tail
    end
    return lines
end

--[[
lines: what to say. state = {
    prepull     settings.announce.prepull (false refuses a pre-pull announce)
    kind        "prepull" (the default) or "callout"
    isLead      this client is the Raid Lead
    chatLocked  chat is locked here
    group       "solo", "party" or "raid"
}
Returns { action = "send" | "refuse", reason, lines }.
]]
function Announce.Decide(lines, state)
    state = state or {}
    local plan = { action = "refuse", lines = lines or {} }
    if #plan.lines == 0 then
        plan.reason = state.kind == "callout" and "nothing to call out" or "the plan has no seats"
    elseif state.kind ~= "callout" and state.prepull == false then
        plan.reason = "announce is off (/mfd announce on)"
    elseif state.isLead ~= true then
        plan.reason = "only the Raid Lead announces"
    elseif state.group ~= "party" and state.group ~= "raid" then
        plan.reason = "not in a group"
    elseif state.chatLocked == true then
        plan.reason = "chat is locked here"
    else
        plan.action = "send"
    end
    return plan
end

-- The channels a line tries, the saved one first; PARTY last so a party hears it too.
function Announce.Channels(channel)
    local list = { type(channel) == "string" and channel or "RAID" }
    if list[1] ~= "PARTY" then list[2] = "PARTY" end
    return list
end

-- "/mfd announce" sends; "on" and "off" set the switch. Returns
-- { action = "send" | "set" | "refuse", value, why }.
function Announce.Command(rest)
    local word = tostring(rest or ""):lower():match("^%s*(%S*)")
    if word == "" then return { action = "send" } end
    if word == "on" then return { action = "set", value = true } end
    if word == "off" then return { action = "set", value = false } end
    return { action = "refuse", why = "say /mfd announce, or /mfd announce on or off" }
end
