--[[
LibICSecure-1.0
Layer 2 of ICKit: secure buttons an addon writes out of combat and the player presses.

Some things on Forever only the player's own press may do, raid marks first: SetRaidTarget
from addon Lua is forbidden, but a secure button running a macro, pressed through a key
binding, marks in combat (Docs/client-reference.md, "Secure buttons"). This library makes
those buttons, keeps their macros, and binds keys to them, and never touches one while
the client forbids it: a change asked for then is held and made when combat ends.

    local Secure = LibStub("LibICSecure-1.0")

    -- Pure
    Secure.Fit(entries, limit, tail)    -> text, kept, dropped: whole entries that fit in limit bytes
    Secure.Words()                      -> { mark, exact, click, clearWorld }: this client's slash words
    Secure.ClickBinding(name, mouse)    -> "CLICK <name>:LeftButton", a binding command for Bindings.xml
    Secure.ReadMark(value)              -> "none" | "marked" | "icon", icon: a GetRaidTargetIndex answer

    -- The client
    Secure.MacroButton(name, opts)      -> button, or nil and why
    Secure.ClearAllButton(name, opts)   -> button, or nil and why
    Secure.SetMacro(button, text)       -> "set" | "held"
    Secure.Bind(owner, keys)            -> "set" | "held": owner's override keys, replaced whole
    Secure.Pending(button or owner)     -> whether a change for it is waiting on combat to end
    Secure.Macro(button)                -> the macro the button runs now
    Secure.Locked()                     -> whether secure frames may not be changed now, and why

What the probe proved, and what this library is built around:

  * A named SecureActionButtonTemplate button with type "macro", registered for "AnyDown"
    with useOnKeyDown, bound with SetOverrideBindingClick, placed marks in combat. That is
    the shape every button here has.
  * Attributes and click registration set in combat raised ADDON_ACTION_BLOCKED. So no
    attribute, binding or button is made or changed while Restrict says secure frames are
    locked (lockdown, or the seconds after PLAYER_REGEN_DISABLED before it).
  * GetRaidTargetIndex on a marked mob is secret in combat. Nothing here reads marks
    back; a caller that wants to know what it marked tracks what it pressed, and
    ReadMark says how much an answer tells.
  * A mouse click puts the pointer on the button, so [@mouseover] means the button. A
    button meant for [@mouseover] is pressed by key only.
]]

local MAJOR, MINOR = "LibICSecure-1.0", 1
local Secure = LibStub:NewLibrary(MAJOR, MINOR)
if not Secure then return end

local Env = LibStub("LibICEnv-1.0")
local Restrict = LibStub("LibICRestrict-1.0")

Secure.MACRO_LIMIT = 255   -- bytes of macrotext proven to run; longer is not yet probed

--------------------------------------------------------------------------------
-- Pure
--------------------------------------------------------------------------------

-- An entry's text: a string, or a list of lines kept together (a /targetexact and its /tm).
local function EntryText(entry)
    if type(entry) == "table" then return table.concat(entry, "\n") end
    return tostring(entry)
end

-- entries: a list of strings or of line lists, most important first.
-- limit:   bytes the text may take (Secure.MACRO_LIMIT when nil).
-- tail:    optional text that always ends the macro (/targetlasttarget, say); its room is
--          kept first.
-- Returns the macro text, how many entries it holds, and the indexes of those left out.
-- Entries are kept in order and the first that does not fit ends the text, so a less
-- important entry never takes the place of a more important one. A tail longer than the
-- limit leaves an empty text and every entry dropped.
function Secure.Fit(entries, limit, tail)
    limit = limit or Secure.MACRO_LIMIT
    entries = entries or {}
    local parts, dropped = {}, {}
    local used = 0
    local room = limit
    if tail ~= nil and tail ~= "" then
        room = limit - #tail - 1   -- the tail and the line break before it
        if #tail > limit then
            for i = 1, #entries do dropped[i] = i end
            return "", 0, dropped
        end
    end
    local full = false
    for i, entry in ipairs(entries) do
        local text = EntryText(entry)
        local cost = #text + (#parts > 0 and 1 or 0)
        if full or text == "" or used + cost > room then
            full = full or text ~= ""
            dropped[#dropped + 1] = i
        else
            parts[#parts + 1] = text
            used = used + cost
        end
    end
    local kept = #parts
    if tail ~= nil and tail ~= "" then
        parts[#parts + 1] = tail
    end
    return table.concat(parts, "\n"), kept, dropped
end

-- The slash word for a command from the client's SLASH_ global, or the English word when
-- the global is missing or not a word. The probe found the English ones on this client.
local function Word(global, english)
    local word = _G[global]
    if type(word) == "string" and not Env.IsSecret(word) and word:match("^/%S+$") then return word end
    return english
end

function Secure.Words()
    return {
        mark = Word("SLASH_TARGET_MARKER1", "/tm"),
        exact = Word("SLASH_TARGET_EXACT1", "/targetexact"),
        click = Word("SLASH_CLICK1", "/click"),
        clearWorld = Word("SLASH_CLEAR_WORLD_MARKER1", "/cwm"),
    }
end

-- The binding command that presses a named button, for a Bindings.xml entry or a
-- SetBinding call: "CLICK MFDMarkPack:LeftButton".
function Secure.ClickBinding(name, mouseButton)
    return "CLICK " .. tostring(name) .. ":" .. (mouseButton or "LeftButton")
end

-- What a GetRaidTargetIndex answer says. A plain number 1 to 8 is that icon; a secret
-- (a marked unit in combat) is "marked" with no icon; nil or anything else is "none".
function Secure.ReadMark(value)
    if Env.IsSecret(value) then return "marked", nil end
    if type(value) == "number" and value >= 1 and value <= 8 and value == math.floor(value) then
        return "icon", value
    end
    return "none", nil
end

--------------------------------------------------------------------------------
-- The client
--------------------------------------------------------------------------------

-- Changes held for the end of combat, newest wins: macros by button, key sets by owner.
Secure.heldMacros = Secure.heldMacros or {}
Secure.heldKeys = Secure.heldKeys or {}
local heldMacros, heldKeys = Secure.heldMacros, Secure.heldKeys
local stopListening

-- Whether secure frames may not be changed now, and why.
function Secure.Locked()
    local state = Restrict.Now()
    if state.secure then return true, state.reason or "in combat" end
    return false
end

local function ApplyMacro(button, text)
    button:SetAttribute("type", "macro")
    button:SetAttribute("macrotext", text)
    button.icMacro = text
    if button.icOnApplied then button.icOnApplied(button, text) end
end

local function ApplyKeys(owner, keys)
    ClearOverrideBindings(owner)
    local list = {}
    for key in pairs(keys) do list[#list + 1] = key end
    table.sort(list)
    for _, key in ipairs(list) do
        local target = keys[key]
        local name, mouse = target, "LeftButton"
        if type(target) == "table" then name, mouse = target[1], target[2] or "LeftButton" end
        SetOverrideBindingClick(owner, true, key, name, mouse)
    end
end

-- Makes every held change, oldest owner first, once the client allows it again.
local function Flush()
    if Secure.Locked() then return end
    local macros, keys = {}, {}
    for button, text in pairs(heldMacros) do macros[#macros + 1] = { button, text } end
    for owner, set in pairs(heldKeys) do keys[#keys + 1] = { owner, set } end
    for button in pairs(heldMacros) do heldMacros[button] = nil end
    for owner in pairs(heldKeys) do heldKeys[owner] = nil end
    for _, pair in ipairs(macros) do ApplyMacro(pair[1], pair[2]) end
    for _, pair in ipairs(keys) do ApplyKeys(pair[1], pair[2]) end
end
Secure.Flush = Flush

-- Listens for the end of combat from the first button on.
local function Listen()
    if stopListening then return end
    stopListening = Restrict.OnChange(function(now)
        if not now.secure then Flush() end
    end)
end

local NAME_PATTERN = "^[%a_][%w_]*$"

-- The one shape the probe proved: a named secure action button, pressed on the key's
-- down edge only. Left unset, the edge would follow the ActionButtonUseKeyDown setting.
local function MakeButton(name, opts)
    if type(name) ~= "string" or not name:match(NAME_PATTERN) then
        return nil, "a secure button needs a global name of letters, digits and underscores"
    end
    Listen()
    local locked, why = Secure.Locked()
    if locked then return nil, why end
    local template = "SecureActionButtonTemplate"
    if opts.template then template = template .. ", " .. opts.template end
    local b = CreateFrame("Button", name, opts.parent or UIParent, template)
    b:RegisterForClicks("AnyDown")
    b:SetAttribute("useOnKeyDown", true)
    if opts.hidden then
        -- Pressed by key binding or /click only. Shown, because a press has to reach a live
        -- button, but invisible, off the screen and deaf to the mouse.
        b:EnableMouse(false)
        b:SetSize(1, 1)
        b:SetAlpha(0)
        b:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -400, 100)
        b:Show()
    end
    return b
end

-- name: the button's global name, which bindings and /click find it by.
-- opts: parent (UIParent), template (a look to add to the secure template, such as
--       "UIPanelButtonTemplate"), hidden (key and /click only), text (the first macro),
--       onApplied(button, text) each time its macro is written, a held one included
--       (when combat ends), so a caller can drop a "stale" tint then.
-- Out of combat only: in combat returns nil and why, because the client blocks the
-- attributes then.
function Secure.MacroButton(name, opts)
    opts = opts or {}
    local b, why = MakeButton(name, opts)
    if not b then return nil, why end
    b.icOnApplied = opts.onApplied
    ApplyMacro(b, opts.text or "")
    return b
end

-- The client's own clear-every-mark action on a secure button, no macro. Same options as
-- MacroButton, without text.
function Secure.ClearAllButton(name, opts)
    local b, why = MakeButton(name, opts or {})
    if not b then return nil, why end
    b:SetAttribute("type", "raidtarget")
    b:SetAttribute("action", "clear-all")
    return b
end

-- Writes a button's macro now, or holds it for the end of combat ("held"; a later write
-- replaces a held one). The button keeps its last macro until then.
function Secure.SetMacro(button, text)
    assert(type(button) == "table", "LibICSecure: SetMacro needs a button")
    text = text or ""
    Listen()
    if Secure.Locked() then
        heldMacros[button] = text
        return "held"
    end
    heldMacros[button] = nil
    ApplyMacro(button, text)
    return "set"
end

-- keys: { [key] = buttonName or { buttonName, mouseButton } }, the whole set for owner (a
-- frame); {} clears it. Override bindings, so they last until changed or the UI reloads
-- and never touch the player's saved keys.
function Secure.Bind(owner, keys)
    assert(type(owner) == "table", "LibICSecure: Bind needs an owner frame")
    keys = keys or {}
    Listen()
    if Secure.Locked() then
        heldKeys[owner] = keys
        return "held"
    end
    heldKeys[owner] = nil
    ApplyKeys(owner, keys)
    return "set"
end

function Secure.Pending(thing)
    return heldMacros[thing] ~= nil or heldKeys[thing] ~= nil
end

-- The macro a button runs now (not a held one).
function Secure.Macro(button)
    return button.icMacro
end
