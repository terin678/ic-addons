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

State is the pure half: it takes what the client said and decides. The half that asks the
client and listens for changes is added once the in-game probe has confirmed it.
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
