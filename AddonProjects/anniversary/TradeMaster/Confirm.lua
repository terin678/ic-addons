local addonName, ns = ...

ns.Confirm = ns.Confirm or {}
local Confirm = ns.Confirm

--[[
Some replies are worth a second pair of eyes. When we cannot name what the
customer asked for, the whisper that goes out asks "what item do you need?" to
someone who just told us, in public, with a link. That reads as though nobody is
home.

So the message is shown first, with their line above it and the text editable,
and nothing is sent or invited until the button is pressed. Anything we could
name is still answered at once: the wait is for the cases we are unsure about.
]]

local WIDTH, HEIGHT = 460, 210
local EXPIRY_SEC = 180

-- Pure. "never" trusts the templates, "always" reviews everything, and the
-- default reviews only what we could not name.
function Confirm.Required(setting, namedSomething)
    if setting == "never" then return false end
    if setting == "always" then return true end
    return not namedSomething
end

-- Pure. Requests waiting behind the one on screen, oldest first, dropping any
-- that have gone stale: a whisper sent five minutes late is worse than none.
function Confirm.Fresh(queue, now, expiry)
    local out = {}
    for _, r in ipairs(queue or {}) do
        if (now - (r.at or 0)) < (expiry or EXPIRY_SEC) then
            out[#out + 1] = r
        end
    end
    return out
end

Confirm.queue = Confirm.queue or {}

local function Build()
    if Confirm.frame then return Confirm.frame end
    local ICUI = ns.UI.Lib

    local f = ICUI:Window("TradeMasterConfirmFrame", {
        style = ns.UI.Style, width = WIDTH, height = HEIGHT,
        title = "Send this?", status = false,
    })
    f:SetFrameStrata("DIALOG")

    local body = f.body

    f.who = ns.UI.Label(body, "", "GameFontNormalSmall")
    f.who:SetPoint("TOPLEFT", 12, -6)
    f.who:SetWidth(WIDTH - 24)
    f.who:SetJustifyH("LEFT")
    f.who:SetWordWrap(false)

    -- Their line, in full. Two lines is enough for any Trade post worth answering.
    f.said = ns.UI.Label(body, "", "GameFontHighlightSmall")
    f.said:SetPoint("TOPLEFT", 12, -24)
    f.said:SetWidth(WIDTH - 24)
    f.said:SetJustifyH("LEFT")
    f.said:SetSpacing(2)
    if f.said.SetMaxLines then f.said:SetMaxLines(2) end

    local youLabel = ns.UI.Label(body, "you would send", "GameFontDisableSmall")
    youLabel:SetPoint("TOPLEFT", 12, -64)

    f.box = ns.UI.EditBox(body, WIDTH - 24, 22)
    f.box:SetPoint("TOPLEFT", 12, -80)
    f.box:SetMaxLetters(250)

    f.note = ns.UI.Label(body, "", "GameFontDisableSmall")
    f.note:SetPoint("TOPLEFT", 12, -108)
    f.note:SetWidth(WIDTH - 24)
    f.note:SetJustifyH("LEFT")
    f.note:SetWordWrap(false)

    f.send = ns.UI.Button(body, "Invite and send", 130, 22, { kind = "accent" })
    f.send:SetPoint("BOTTOMLEFT", 12, 12)

    f.whisperOnly = ns.UI.Button(body, "Whisper only", 100, 22)
    f.whisperOnly:SetPoint("LEFT", f.send, "RIGHT", 6, 0)

    f.skip = ns.UI.Button(body, "Skip", 70, 22)
    f.skip:SetPoint("LEFT", f.whisperOnly, "RIGHT", 6, 0)

    f.never = ns.UI.Button(body, "Never invite", 90, 22, { kind = "danger" })
    f.never:SetPoint("BOTTOMRIGHT", -12, 12)

    Confirm.frame = f
    return f
end

-- Shows the request on top of the queue, or hides the window when there is none.
function Confirm.Next()
    local f = Build()
    Confirm.queue = Confirm.Fresh(Confirm.queue, ns.Now(), EXPIRY_SEC)

    local r = Confirm.queue[1]
    if not r then
        f:Hide()
        return
    end

    local waiting = #Confirm.queue - 1
    f.who:SetText(string.format("|cffffffff%s|r in %s%s", r.player, r.source,
        waiting > 0 and string.format("   |cff888888%d more waiting|r", waiting) or ""))
    f.said:SetText("\"" .. (r.text or "") .. "\"")
    f.box:SetText(r.plan.text or "")
    f.note:SetText(r.plan.haveText
        and ("|cff888888you can make " .. r.plan.haveText .. "|r")
        or "|cffff9900nothing they named is in your book|r")

    local function finish()
        table.remove(Confirm.queue, 1)
        Confirm.Next()
    end

    f.send:SetScript("OnClick", function()
        ns.Inviter.Invite(r.player, r.matched,
            { cannotDo = r.cannotDo, profession = r.profession, whisperText = f.box:GetText() })
        finish()
    end)

    f.whisperOnly:SetScript("OnClick", function()
        ns.Inviter.SayText(r.player, f.box:GetText(), r.plan.profile)
        finish()
    end)

    f.skip:SetScript("OnClick", finish)

    f.never:SetScript("OnClick", function()
        local state = ns.Players.Get(ns.db, r.player)
        state.neverInvite = true
        ns.Print(r.player .. " will never be invited. |cff888888/tm clearflags undoes it|r")
        finish()
    end)

    f:Show()
end

-- Queues a request for review. r = { player, source, text, matched, cannotDo,
-- profession }.
function Confirm.Ask(r)
    r.at = ns.Now()
    r.plan = ns.Inviter.Plan(r.player, r.matched, r)
    Confirm.queue[#Confirm.queue + 1] = r
    ns.Print(string.format("|cffffcc00%s asked and needs a look|r before anything is sent.",
        r.player))
    -- The same ping an invite makes: the window can end up behind the game's own.
    if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.MAP_PING) end
    Confirm.Next()
end
