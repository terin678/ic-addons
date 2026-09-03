-- The addon channel: message encoding, a rate-limited send queue, the Raid
-- Lead designation and the election fallback.
--
-- Encode, Decode, Drain and ResolveAuthority are pure so the coordination
-- logic is testable headlessly. Everything that touches the client lives below
-- them and runs from RegisterInit.
local MFD = _G.MarkedForDeath or {}

MFD.Comms = MFD.Comms or {}
local Comms = MFD.Comms

Comms.PREFIX = "MFD"

-- Chosen over "|" because the chat system treats that as an escape introducer,
-- and over "\n" because addon messages may not contain it. Player names and
-- npc ids can never contain it.
Comms.SEPARATOR = "~"

-- Lower drains first. The channel is throttled server side and that budget is
-- shared with every other addon the player runs, so bulk rule data must never
-- be able to starve a heartbeat or an assignment.
Comms.PRIORITY = {
    B = 1, A = 1, L = 1, E = 1, H = 1,
    S = 2, RG = 2, RV = 2, RQ = 2, C = 2,
    PC = 3,
    RD = 4, RM = 4,
}

Comms.MAX_PER_SECOND = 8         -- messages
Comms.HEARTBEAT_SECONDS = 5      -- seconds between authority heartbeats
Comms.PEER_TIMEOUT_SECONDS = 15  -- seconds of silence before a peer is ignored

-- Joins a message type and its fields into a wire string.
function Comms.Encode(msgType, fields)
    local parts = { msgType }
    for _, value in ipairs(fields or {}) do
        parts[#parts + 1] = tostring(value)
    end
    return table.concat(parts, Comms.SEPARATOR)
end

-- Splits a wire string. Returns the message type and an array of field strings,
-- or nil when the input is not a message. Fields always come back as strings;
-- callers convert.
function Comms.Decode(str)
    if type(str) ~= "string" or str == "" then
        return nil
    end

    local fields = {}
    for part in string.gmatch(str, "([^" .. Comms.SEPARATOR .. "]+)") do
        fields[#fields + 1] = part
    end

    local msgType = table.remove(fields, 1)
    if not msgType then
        return nil
    end

    return msgType, fields
end

-- Removes up to budget messages from queue in priority order and returns them.
-- Mutates queue. Ties keep insertion order, so a burst of sightings goes out in
-- the order they were observed.
function Comms.Drain(queue, budget)
    local indexed = {}
    for i, message in ipairs(queue) do
        indexed[#indexed + 1] = { message = message, index = i }
    end

    table.sort(indexed, function(a, b)
        local pa = Comms.PRIORITY[a.message.msgType] or 9
        local pb = Comms.PRIORITY[b.message.msgType] or 9
        if pa ~= pb then
            return pa < pb
        end
        return a.index < b.index
    end)

    local sent, taken = {}, {}
    for i = 1, math.min(budget, #indexed) do
        sent[#sent + 1] = indexed[i].message
        taken[indexed[i].index] = true
    end

    for i = #queue, 1, -1 do
        if taken[i] then
            table.remove(queue, i)
        end
    end

    return sent
end

-- Takes the known peers, the current designation and the time. Returns the
-- authority's name, the mode ("designated", "elected" or "none") and a reason
-- string explaining any fallback.
--
-- A designated lead wins outright when present and able to mark. Otherwise the
-- election runs: raid leader, then assistant, then name ascending. Peers silent
-- past PEER_TIMEOUT_SECONDS are ignored entirely, so a disconnected raid leader
-- cannot hold the authority hostage.
--
-- Pure and order independent, which is what lets every client reach the same
-- answer without negotiating.
function Comms.ResolveAuthority(peers, designation, now)
    local live = {}
    for _, p in ipairs(peers) do
        if (p.lastSeen + Comms.PEER_TIMEOUT_SECONDS) >= now then
            live[#live + 1] = p
        end
    end

    local reason = ""

    if designation and designation.name and designation.name ~= "" then
        local found
        for _, p in ipairs(live) do
            if p.name == designation.name then
                found = p
                break
            end
        end

        if found and found.canMark then
            return found.name, "designated", ""
        end

        if not found then
            reason = "designated lead " .. designation.name .. " is not in the group"
        else
            reason = "designated lead " .. designation.name .. " cannot place icons"
        end
    end

    local best
    for _, p in ipairs(live) do
        if p.canMark then
            local score = (p.isLeader and 1000 or 0) + (p.isAssist and 500 or 0)
            if not best or score > best.score or (score == best.score and p.name < best.peer.name) then
                best = { peer = p, score = score }
            end
        end
    end

    if not best then
        return nil, "none", reason ~= "" and reason or "nobody in the group can place icons"
    end

    return best.peer.name, "elected", reason
end

local queue = {}
local peers = {}
local sendAccumulator = 0
local heartbeatAccumulator = 0

Comms.authority = nil
Comms.authorityMode = "none"
Comms.authorityReason = ""

local function playerName()
    return UnitName("player")
end

-- Queues a message. Nothing is ever sent directly, so the rate limit cannot be
-- bypassed by accident.
function Comms:Send(msgType, fields)
    queue[#queue + 1] = { msgType = msgType, body = Comms.Encode(msgType, fields) }
end

local function channel()
    if IsInRaid and IsInRaid() then
        return "RAID"
    end
    if IsInGroup and IsInGroup() then
        return "PARTY"
    end
    return nil
end

local function flush()
    local target = channel()
    if not target then
        -- Solo, so nothing can be sent and a growing queue would leak.
        wipe(queue)
        return
    end

    local sendFn = C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
    if type(sendFn) ~= "function" then
        return
    end

    for _, message in ipairs(Comms.Drain(queue, Comms.MAX_PER_SECOND)) do
        pcall(sendFn, Comms.PREFIX, message.body, target)
    end
end

-- Records our own state as a peer, so a solo player or the only addon user in
-- a raid still resolves to an authority.
local function refreshSelf()
    peers[playerName()] = {
        canMark = MFD.Marker:CanMark(),
        isLeader = UnitIsGroupLeader("player") or false,
        isAssist = (UnitIsGroupAssistant and UnitIsGroupAssistant("player")) or false,
        lastSeen = GetTime(),
        version = MFD.VERSION,
    }
end

-- Rebuilds the peer list into the shape ResolveAuthority consumes and caches
-- the result. Prints a fallback reason only when it changes, so a persistent
-- problem is reported once rather than every heartbeat.
function Comms:RecomputeAuthority()
    refreshSelf()

    local list = {}
    for name, p in pairs(peers) do
        list[#list + 1] = {
            name = name,
            canMark = p.canMark,
            isLeader = p.isLeader,
            isAssist = p.isAssist,
            lastSeen = p.lastSeen,
            version = p.version,
        }
    end

    local name, mode, reason = Comms.ResolveAuthority(list, MFD.db.designatedLead, GetTime())

    if reason ~= "" and reason ~= Comms.authorityReason then
        MFD.Print(reason)
    end

    Comms.authority, Comms.authorityMode, Comms.authorityReason = name, mode, reason
end

function Comms:IsAuthority()
    return Comms.authority == playerName()
end

function Comms:PeerNames()
    return MFD.H.SortedKeys(peers)
end

-- Sets or clears the Raid Lead. Only the game's raid leader or an assistant may
-- do this, or anyone at all when solo.
function Comms:SetLead(name)
    local canSet = UnitIsGroupLeader("player")
        or (UnitIsGroupAssistant and UnitIsGroupAssistant("player"))
        or not (IsInGroup and IsInGroup())

    if not canSet then
        MFD.Error("only the raid leader or an assistant can set the Raid Lead")
        return
    end

    MFD.db.designatedLead = { name = name or "", setBy = playerName(), setAt = time() }
    Comms:Send("L", { name or "", playerName(), MFD.db.designatedLead.setAt })
    Comms:RecomputeAuthority()

    if name and name ~= "" then
        MFD.Print("Raid Lead set to " .. name)
    else
        MFD.Print("Raid Lead cleared, falling back to the automatic election")
    end
end

local function onMessage(prefix, body, _, sender)
    if prefix ~= Comms.PREFIX then
        return
    end

    local msgType, fields = Comms.Decode(body)
    if not msgType then
        return
    end

    -- Senders arrive realm-qualified on connected realms.
    sender = string.match(sender or "", "^([^%-]+)") or sender

    if sender == playerName() then
        return
    end

    if msgType == "H" then
        peers[sender] = {
            version = fields[1],
            canMark = fields[2] == "1",
            isLeader = fields[3] == "1",
            isAssist = fields[4] == "1",
            lastSeen = GetTime(),
        }
        Comms:RecomputeAuthority()
    elseif msgType == "B" then
        if peers[sender] then
            peers[sender].lastSeen = GetTime()
        end
    elseif msgType == "L" then
        local setAt = tonumber(fields[3]) or 0
        -- Last write wins, so two people setting the lead at once converges on
        -- the same answer everywhere.
        if setAt >= (MFD.db.designatedLead.setAt or 0) then
            MFD.db.designatedLead = {
                name = fields[1] or "",
                setBy = fields[2] or sender,
                setAt = setAt,
            }
            Comms:RecomputeAuthority()
            MFD.Print("Raid Lead set to "
                .. ((fields[1] ~= "" and fields[1]) or "nobody")
                .. " by " .. tostring(fields[2]))
        end
    end
end

local function announceSelf()
    Comms:Send("H", {
        MFD.VERSION,
        MFD.Marker:CanMark() and "1" or "0",
        UnitIsGroupLeader("player") and "1" or "0",
        (UnitIsGroupAssistant and UnitIsGroupAssistant("player")) and "1" or "0",
    })
end

MFD.RegisterInit(function()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, Comms.PREFIX)
    elseif RegisterAddonMessagePrefix then
        pcall(RegisterAddonMessagePrefix, Comms.PREFIX)
    end

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")

    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_ADDON" then
            onMessage(...)
        else
            Comms:RecomputeAuthority()
            announceSelf()
        end
    end)

    frame:SetScript("OnUpdate", function(_, elapsed)
        sendAccumulator = sendAccumulator + elapsed
        if sendAccumulator >= 1 then
            sendAccumulator = 0
            flush()
        end

        heartbeatAccumulator = heartbeatAccumulator + elapsed
        if heartbeatAccumulator >= Comms.HEARTBEAT_SECONDS then
            heartbeatAccumulator = 0
            Comms:RecomputeAuthority()
            if Comms:IsAuthority() then
                Comms:Send("B", { MFD.VERSION })
            end
        end
    end)

    Comms:RecomputeAuthority()
end)

_G.MarkedForDeath = MFD
