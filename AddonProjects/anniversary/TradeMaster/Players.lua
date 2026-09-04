local addonName, ns = ...

ns.Players = ns.Players or {}
local Players = ns.Players

-- Sellers repost the same advertisement on a timer, usually varying only the
-- price. Ignoring digits is what lets "5g" and "7g" count as the same message.
function Players.Similar(a, b)
    if not a or not b then return false end
    local ca = a:gsub("%d+", "")
    local cb = b:gsub("%d+", "")
    return ca == cb
end

function Players.Observe(state, norm, now, windowSec)
    state = state or {}
    local isRepeat = false

    if state.lastMsg and state.lastMsgAt
        and (now - state.lastMsgAt) <= windowSec
        and Players.Similar(state.lastMsg, norm) then
        isRepeat = true
        state.repeats = (state.repeats or 0) + 1
        state.flaggedSeller = true
    end

    state.lastMsg = norm
    state.lastMsgAt = now
    return state, isRepeat
end

local RECENT_MAX = 4

-- People type a gem name across several messages: "Shifting Shadowsong?" then
-- "Amethyst". Matching each line in isolation misses all of them, so keep a
-- short rolling buffer of what someone just said.
function Players.PushRecent(state, text, now)
    state.recent = state.recent or {}
    state.recent[#state.recent + 1] = { text = text, at = now }
    while #state.recent > RECENT_MAX do table.remove(state.recent, 1) end
    return state
end

function Players.RecentText(state, now, windowSec)
    local parts = {}
    for _, r in ipairs(state.recent or {}) do
        if (now - (r.at or 0)) <= windowSec then parts[#parts + 1] = r.text end
    end
    return table.concat(parts, " ")
end

local DECLINED_MAX = 12

-- What we have already told this player we cannot make. Keyed on the normalized
-- name so a repost, in any channel and with any wrapping around it, is answered
-- from memory instead of walking them through the invite and the same apology a
-- second time.
--
-- Pure. names are the bracketed names off the line; norm is the whole line, for
-- the case where they typed it out rather than linking it.
function Players.Decline(state, norm, names)
    state.declined = state.declined or {}
    local function remember(key)
        key = ns.Util.Normalize(key or "")
        if key == "" or state.declined[key] then return end
        state.declined[key] = true
        state.declinedOrder = state.declinedOrder or {}
        state.declinedOrder[#state.declinedOrder + 1] = key
        while #state.declinedOrder > DECLINED_MAX do
            local oldest = table.remove(state.declinedOrder, 1)
            state.declined[oldest] = nil
        end
    end
    for _, name in ipairs(names or {}) do remember(name) end
    remember(norm)
    return state
end

-- Pure. Have we already answered this exact ask?
function Players.WasDeclined(state, norm, names)
    local declined = state and state.declined
    if not declined then return false end
    for _, name in ipairs(names or {}) do
        if declined[ns.Util.Normalize(name or "")] then return true end
    end
    return declined[ns.Util.Normalize(norm or "")] == true
end

function Players.ClearDeclined(state)
    local n = state.declinedOrder and #state.declinedOrder or 0
    state.declined, state.declinedOrder = nil, nil
    return n
end

function Players.Get(db, name)
    db.players = db.players or {}
    db.players[name] = db.players[name] or {}
    return db.players[name]
end
