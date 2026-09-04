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
--
-- Empty fields keep their position. A gmatch of "[^sep]+" looks like the
-- obvious way to do this and is wrong: the + skips empty fields entirely, so
-- every later field shifts down one. That turned clearing the Raid Lead, which
-- sends an empty name, into setting the lead to the clearer's own name.
function Comms.Decode(str)
    if type(str) ~= "string" or str == "" then
        return nil
    end

    local fields = {}
    local separator = Comms.SEPARATOR
    local position = 1

    while true do
        local at = string.find(str, separator, position, true)
        if not at then
            fields[#fields + 1] = string.sub(str, position)
            break
        end
        fields[#fields + 1] = string.sub(str, position, at - 1)
        position = at + 1
    end

    local msgType = table.remove(fields, 1)
    if not msgType or msgType == "" then
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

-- Sighting payload: "key:npcID" entries joined by commas. Pure.
function Comms.EncodeSightings(entries)
    return table.concat(entries or {}, ",")
end

-- Takes a sighting payload. Returns an array of { key, npcID }. Anything that
-- does not match in full is ignored, so a corrupt batch cannot inject a
-- candidate with a nil npcID that the allocator would then have to guess at.
-- Pure.
function Comms.DecodeSightings(payload)
    local list = {}
    if type(payload) ~= "string" then
        return list
    end

    for key, npcID in string.gmatch(payload, "([%d]+:%x+):(%d+)") do
        list[#list + 1] = { key = key, npcID = tonumber(npcID) }
    end

    return list
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
    else
        Comms:HandleRuleMessage(msgType, fields, sender)
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
            Comms.Republish()
            Comms:AdvertiseRules()
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
            Comms:SweepStalledTransfers()
            Comms:RecomputeAuthority()
            if Comms:IsAuthority() then
                Comms:Send("B", { MFD.VERSION })
            end
        end
    end)

    Comms:RecomputeAuthority()
end)

-- Bytes per chunk. Addon messages cap at 255 including the prefix and the
-- envelope fields, so this leaves comfortable headroom.
Comms.CHUNK_BYTES = 200
Comms.TRANSFER_TIMEOUT_SECONDS = 20

-- Splits payload into chunks of at most size bytes. Returns an array with at
-- least one entry, even for an empty payload, so a receiver always sees a
-- terminating chunk.
function Comms.Chunk(payload, size)
    local chunks = {}
    local position = 1

    repeat
        chunks[#chunks + 1] = string.sub(payload, position, position + size - 1)
        position = position + size
    until position > #payload

    return chunks
end

-- Accumulates a chunked transfer. Returns the complete payload once the last
-- chunk arrives, otherwise nil. Mutates state, keyed by sender, and clears the
-- sender's entry on completion.
--
-- Caller contract: when this function creates an entry it stamps startedAt as
-- 0, because it has no clock and must stay pure. The client wiring pre-creates
-- the entry with a real startedAt before the first call; SweepTransfers would
-- otherwise abandon the transfer immediately.
function Comms.Reassemble(state, sender, index, total, chunk)
    local entry = state[sender]

    if not entry or entry.total ~= total then
        entry = { total = total, parts = {}, received = 0, startedAt = 0 }
        state[sender] = entry
    end

    if not entry.parts[index] then
        entry.parts[index] = chunk
        entry.received = entry.received + 1
    end

    if entry.received < total then
        return nil
    end

    state[sender] = nil
    return table.concat(entry.parts)
end

-- Drops transfers that stalled. Returns the senders whose transfers were
-- abandoned so the caller can report it, because a silent stall is exactly the
-- kind of failure the repo standards forbid.
function Comms.SweepTransfers(state, now, timeout)
    local abandoned = {}

    for _, sender in ipairs(MFD.H.SortedKeys(state)) do
        local entry = state[sender]
        if (entry.startedAt + timeout) < now then
            abandoned[#abandoned + 1] = sender
            state[sender] = nil
        end
    end

    return abandoned
end

local transfers = {}
local assignmentTransfers = {}
local contributions = {}
local peerVersions = {}
local haveVersions = {}
local ruledDigest = {}

-- Rebuilds the merged rule set from every contribution we hold, always
-- including our own, and (if we are the authority) publishes the digest of
-- ruled npc ids so backups know which mobs are worth reporting.
--
-- Never writes to saved variables. Merged rules are session state.
function Comms.Republish()
    contributions[playerName()] = MFD.db.rules

    local list = {}
    for owner, rules in pairs(contributions) do
        list[#list + 1] = { owner = owner, rules = rules }
    end

    MFD.Rules.SetContributions(list, MFD.db.designatedLead.name)

    if not Comms:IsAuthority() then
        return
    end

    local ids = {}
    for _, instanceKey in ipairs(MFD.H.SortedKeys(MFD.Rules.merged)) do
        for npcID in pairs(MFD.Rules.merged[instanceKey]) do
            ids[#ids + 1] = npcID
        end
    end

    table.sort(ids)
    for _, chunkText in ipairs(Comms.Chunk(table.concat(ids, ","), Comms.CHUNK_BYTES)) do
        Comms:Send("RG", { chunkText })
    end
end

-- Advertises our rule version. Bumps first, so a local edit is always
-- reflected in what peers hear about.
function Comms:AdvertiseRules()
    MFD.Rules.BumpVersion(MFD.db)
    Comms:Send("RV", { MFD.db.rulesVersion.counter .. ":" .. MFD.db.rulesVersion.hash })
end

-- Broadcasts our own rules, chunked. Broadcast rather than whispered so every
-- client accumulates the same contributions and computes the same merge.
local function sendRules()
    local payload = MFD.Rules.Serialize(MFD.db.rules)
    local chunks = Comms.Chunk(payload, Comms.CHUNK_BYTES)

    for i, chunkText in ipairs(chunks) do
        Comms:Send("RD", { i, #chunks, chunkText })
    end
end

function Comms:IsRuled(npcID)
    return ruledDigest[npcID] == true
end

-- Handles the rule sync message types. Returns true when it consumed the
-- message. Split out of onMessage so the dispatch there stays readable.
function Comms:HandleRuleMessage(msgType, fields, sender)
    if msgType == "RV" then
        peerVersions[sender] = fields[1]
        -- Only the authority requests, so a raid of twenty five does not
        -- produce twenty five requests per version change.
        if Comms:IsAuthority() and haveVersions[sender] ~= fields[1] then
            Comms:Send("RQ", { sender })
        end
        return true
    end

    if msgType == "RQ" then
        if fields[1] == playerName() then
            sendRules()
        end
        return true
    end

    if msgType == "RD" then
        local index, total = tonumber(fields[1]), tonumber(fields[2])
        if not index or not total then
            return true
        end

        if not transfers[sender] then
            transfers[sender] = { total = total, parts = {}, received = 0, startedAt = GetTime() }
        end

        local payload = Comms.Reassemble(transfers, sender, index, total, fields[3] or "")
        if payload then
            local parsed, err = MFD.Rules.Deserialize(payload)
            if not parsed then
                MFD.Error("could not read rules from " .. sender .. ": " .. tostring(err))
                return true
            end
            contributions[sender] = parsed
            haveVersions[sender] = peerVersions[sender]
            Comms.Republish()
            MFD.Print("merged rules from " .. sender)
        end
        return true
    end

    if msgType == "RG" then
        wipe(ruledDigest)
        for id in string.gmatch(fields[1] or "", "(%d+)") do
            ruledDigest[tonumber(id)] = true
        end
        return true
    end

    if msgType == "S" then
        -- Peer sightings merge into the authority's candidate set with no unit
        -- token, so the allocator can consider a mob we cannot see ourselves.
        -- They are stamped lost immediately so they expire through the normal
        -- grace window unless the backup keeps re-reporting them.
        if Comms:IsAuthority() then
            local now = GetTime()
            for _, sighting in ipairs(Comms.DecodeSightings(fields[1])) do
                MFD.Candidates.Observe(MFD.Candidates.set, sighting.key, sighting.npcID, nil, now)
                local entry = MFD.Candidates.set[sighting.key]
                if entry and not entry.unit then
                    entry.lostAt = now
                end
            end
        end
        return true
    end

    if msgType == "PC" then
        if MFD.RaidCheck and MFD.RaidCheck.ReceiveReport then
            MFD.RaidCheck:ReceiveReport(sender, fields)
        end
        return true
    end

    if msgType == "A" then
        local index, total = tonumber(fields[1]), tonumber(fields[2])
        if not index or not total then
            return true
        end

        if not assignmentTransfers[sender] then
            assignmentTransfers[sender] = { total = total, parts = {}, received = 0, startedAt = GetTime() }
        end

        local payload = Comms.Reassemble(assignmentTransfers, sender, index, total, fields[3] or "")
        if payload then
            MFD.Marker.ApplyPublished(payload, GetTime())
        end
        return true
    end

    return false
end

Comms.SIGHTING_INTERVAL_SECONDS = 0.5   -- how often a backup may send a batch
Comms.SIGHTING_REFRESH_SECONDS = 2      -- how often one key is re-reported
Comms.SIGHTINGS_PER_MESSAGE = 10

-- Keys this client has reported, with the time of the last report.
Comms.reportedSightings = {}

-- Returns up to max "key:npcID" strings for ruled, currently visible mobs in
-- set that are due for a report, and stamps them in reported. Mutates reported.
--
-- Filtering to ruled mobs, requiring a unit (so we only vouch for what we can
-- actually see), and refreshing on an interval rather than every tick is what
-- keeps the coverage merge affordable on a throttled shared channel.
function Comms.PendingSightings(set, reported, isRuled, max, now, refreshSeconds)
    local pending = {}

    for _, key in ipairs(MFD.H.SortedKeys(set)) do
        if #pending >= max then
            break
        end

        local entry = set[key]
        local isDue = not reported[key] or (now - reported[key]) >= refreshSeconds
        if isDue and entry.unit and isRuled(entry.npcID) then
            reported[key] = now
            pending[#pending + 1] = key .. ":" .. entry.npcID
        end
    end

    return pending
end

-- Returns { [owner] = rule count } for every contributor other than us, for
-- /mfd status.
function Comms:ContributionCounts()
    local counts = {}
    for owner, rules in pairs(contributions) do
        if owner ~= playerName() then
            local total = 0
            for _, list in pairs(rules) do
                total = total + #list
            end
            counts[owner] = total
        end
    end
    return counts
end

-- Called from the heartbeat so a stalled transfer is reported and retried
-- rather than hanging forever.
function Comms:SweepStalledTransfers()
    for _, sender in ipairs(Comms.SweepTransfers(transfers, GetTime(), Comms.TRANSFER_TIMEOUT_SECONDS)) do
        MFD.Error("rule transfer from " .. sender .. " timed out, will retry on their next update")
        haveVersions[sender] = nil
    end
end

_G.MarkedForDeath = MFD
