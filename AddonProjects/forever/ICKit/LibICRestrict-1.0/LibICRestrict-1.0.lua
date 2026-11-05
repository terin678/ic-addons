--[[
LibICRestrict-1.0
Layer 1 of ICKit: what the client will not let an addon do or read right now.

On Forever the client hides some values from addons (secret values) and switches off some
actions while a restriction is active: in combat, in an encounter, while chat is locked.
An addon asks here before it reads a value or acts, and gets a plain answer with a reason.

    local Restrict = LibStub("LibICRestrict-1.0")

    Restrict.IsSecret(v)            -> whether v is a secret value (Env.IsSecret)
    Restrict.Readable(v, fallback)  -> v when it can be read, else fallback
    Restrict.State(reading)         -> { combat, chat, secure, restricted, active, unknown, reason }
    Restrict.Changed(a, b)          -> whether two States differ in anything an addon acts on

    Restrict.Read()                 -> the reading State takes, from the client now
    Restrict.Now()                  -> State(Read())
    Restrict.InCombat(), ChatLocked(), Active(kind)   -> booleans, from Now()
    Restrict.OnChange(fn)           -> fn(state, previous) on every change; returns a stop function

State and Changed are the pure half: they take what the client said and decide. Read,
Now and OnChange ask the client, using only what the in-game probe confirmed (see
"Combat restrictions and secret values" in Docs/client-reference.md). Each call is
guarded, so a client without one of them reads as that restriction off.
]]

local MAJOR, MINOR = "LibICRestrict-1.0", 1
local Restrict = LibStub:NewLibrary(MAJOR, MINOR)
if not Restrict then return end

local Env = LibStub("LibICEnv-1.0")

local INACTIVE = 0  -- a restriction state the client reports when the restriction is off

-- The kinds an addon most often branches on, most fundamental first; State's reason is
-- the first of these that is on. Any other kind the client reports still lands in
-- `active`, after these.
local REASONS = {
    { key = "combat", text = "in combat" },
    { key = "encounter", text = "in an encounter" },
    { key = "chat", text = "chat is locked" },
}

--------------------------------------------------------------------------------
-- Values
--------------------------------------------------------------------------------

function Restrict.IsSecret(v)
    return Env.IsSecret(v)
end

-- v when an addon may read it, else fallback (nil by default). For a value the client may
-- or may not hide: `local hp = Restrict.Readable(UnitHealth(unit))`.
function Restrict.Readable(v, fallback)
    if Env.IsSecret(v) then return fallback end
    return v
end

--------------------------------------------------------------------------------
-- State, pure
--------------------------------------------------------------------------------

-- reading: what the client said, all fields optional.
--   states         { [kind] = state }: Enum.AddOnRestrictionType names (Combat, Chat,
--                  Encounter, Map, ChallengeMode, PvPMatch) to the number the client
--                  gave. 0 is off; any other number is on, because the change event
--                  reports a restriction starting with 1 while the state then reads 2.
--   lockdown       InCombatLockdown()
--   regenDisabled  between PLAYER_REGEN_DISABLED and PLAYER_REGEN_ENABLED. The client
--                  turns lockdown and the Combat restriction on a few seconds after that
--                  event, so the event is the earliest sign of combat.
--   chatLockdown   C_ChatInfo.InChatMessagingLockdown()
-- Returns:
--   combat      in combat by any of the three signs
--   encounter   the Encounter restriction is on
--   chat        an addon may not send chat (lockdown, or the Chat restriction)
--   secure      secure frames may not be changed: lockdown, or combat about to begin
--   restricted  any of the above, or any other restriction on
--   active      { [kind] = true } for every restriction on
--   unknown     { [kind] = true } for every state that was not a readable number
--   reason      the first thing on, as words ("in combat"), or nil when nothing is
function Restrict.State(reading)
    reading = reading or {}
    local active, unknown = {}, {}
    local anyOther = false
    for kind, state in pairs(reading.states or {}) do
        local plain = Restrict.Readable(state)
        if type(plain) ~= "number" then
            unknown[kind] = true
        elseif plain ~= INACTIVE then
            active[kind] = true
            if kind ~= "Combat" and kind ~= "Encounter" and kind ~= "Chat" then anyOther = true end
        end
    end

    local lockdown = Restrict.Readable(reading.lockdown) == true
    local regen = Restrict.Readable(reading.regenDisabled) == true
    local chatLockdown = Restrict.Readable(reading.chatLockdown) == true

    local s = {
        combat = lockdown or regen or active.Combat == true,
        encounter = active.Encounter == true,
        chat = chatLockdown or active.Chat == true,
        secure = lockdown or regen,
        active = active,
        unknown = unknown,
    }
    s.restricted = s.combat or s.encounter or s.chat or anyOther
    for _, r in ipairs(REASONS) do
        if s[r.key] then
            s.reason = r.text
            break
        end
    end
    if not s.reason and anyOther then
        local kinds = {}
        for kind in pairs(active) do kinds[#kinds + 1] = kind end
        table.sort(kinds)
        s.reason = "restricted (" .. table.concat(kinds, ", ") .. ")"
    end
    return s
end

local FLAGS = { "combat", "encounter", "chat", "secure", "restricted" }

local function SameSet(a, b)
    for k in pairs(a) do
        if not b[k] then return false end
    end
    for k in pairs(b) do
        if not a[k] then return false end
    end
    return true
end

-- Whether b differs from a in anything an addon acts on: a flag, or which restrictions
-- are on. A nil a (nothing known yet) always differs.
function Restrict.Changed(a, b)
    if a == nil or b == nil then return a ~= b end
    for _, flag in ipairs(FLAGS) do
        if a[flag] ~= b[flag] then return true end
    end
    return not SameSet(a.active or {}, b.active or {})
end

--------------------------------------------------------------------------------
-- The client
--------------------------------------------------------------------------------

local STATE_ON = 2  -- what a restriction reads as when only IsAddOnRestrictionActive answers

-- Events that can change the State. The restriction event fires with (type, state) when a
-- restriction starts and ends; the regen pair marks combat seconds before it does.
local EVENTS = { "ADDON_RESTRICTION_STATE_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }

Restrict.listeners = Restrict.listeners or {}
local listeners = Restrict.listeners
local regenDisabled = false
local last

-- fn(...) under pcall, its first return when that reads plainly, else nil.
local function Ask(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok then return nil end
    return value
end

-- The restriction state of one kind: GetAddOnRestrictionState's number, or STATE_ON / 0
-- from IsAddOnRestrictionActive, or nil when the client says neither.
local function KindState(api, value)
    local state = Ask(api.GetAddOnRestrictionState, value)
    if state ~= nil then return state end
    local on = Ask(api.IsAddOnRestrictionActive, value)
    if on == nil or Env.IsSecret(on) then return on end
    return on == true and STATE_ON or INACTIVE
end

-- What the client says now, in the shape State takes. Values pass through as the client
-- gave them; State decides what a secret or a missing answer means.
function Restrict.Read()
    local states = {}
    local kinds = type(Enum) == "table" and Enum.AddOnRestrictionType
    local api = type(C_RestrictedActions) == "table" and C_RestrictedActions
    if type(kinds) == "table" and api then
        for name, value in pairs(kinds) do
            states[name] = KindState(api, value)
        end
    end
    local chat = type(C_ChatInfo) == "table" and C_ChatInfo.InChatMessagingLockdown
    return {
        states = states,
        lockdown = Ask(InCombatLockdown),
        regenDisabled = regenDisabled,
        chatLockdown = Ask(chat),
    }
end

function Restrict.Now()
    return Restrict.State(Restrict.Read())
end

function Restrict.InCombat()
    return Restrict.Now().combat
end

function Restrict.ChatLocked()
    return Restrict.Now().chat
end

-- kind: an Enum.AddOnRestrictionType name, "Combat" for example.
function Restrict.Active(kind)
    return Restrict.Now().active[kind] == true
end

-- Runs on every event in EVENTS: notes the regen window, reads the client, and tells each
-- listener when the State changed. A listener added or removed during the round waits
-- for the next one.
local function OnEvent(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        regenDisabled = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        regenDisabled = false
    end
    local now = Restrict.Now()
    if not Restrict.Changed(last, now) then return end
    local previous = last
    last = now
    local round = {}
    for i, fn in ipairs(listeners) do round[i] = fn end
    for _, fn in ipairs(round) do fn(now, previous) end
end

-- The one event frame, made at the first OnChange so a file that only reads costs nothing.
local function Listen()
    if Restrict.frame then return end
    local frame = CreateFrame("Frame")
    for _, event in ipairs(EVENTS) do frame:RegisterEvent(event) end
    frame:SetScript("OnEvent", Env.Wrap("ICKit restrictions", OnEvent))
    Restrict.frame = frame
    last = Restrict.Now()
end

-- fn(state, previous) whenever the State changes in a flag or in which restrictions are
-- on. Nothing is called for the State at the time of the call: read Restrict.Now() for
-- that. Returns a function that stops the listening.
function Restrict.OnChange(fn)
    assert(type(fn) == "function", "LibICRestrict: OnChange needs a function")
    Listen()
    listeners[#listeners + 1] = fn
    return function()
        for i, other in ipairs(listeners) do
            if other == fn then
                table.remove(listeners, i)
                return
            end
        end
    end
end
