local addonName, ns = ...

--[[
UI_Deaths: the Deaths tab. Draws the death and announce settings and the per-boss ticks;
every decision it shows comes from Deaths.lua and Announce.lua.

Owned by lane D (deaths and chat).

    UIDeaths.Build(parent)          builds the page into parent, once; returns the page
    UIDeaths.Refresh()              re-reads every control from the saved settings

The page registers itself with ns.UI.AddTab("deaths", "Deaths", Build, { refresh = Refresh })
at login when the window offers it. Frames are made only inside Build, never at file scope,
and the ready hook returns early on IC_HEADLESS.

Layout, top to bottom (y offsets from the page's top, in pixels):
    8     toolbar: Announce, Test alert, Announce allowed, Death sound
    40    two columns, Tank and Healer: the kind on, on trash, right now, extra names
    170   held line wait
    198   chat cue: on, its word, its sound
    232   the boss list's header row (outside the scroll)
    252   the boss list, a scroll of fixed 20 px single-line rows, to the page's bottom

The page needs about 600 px of width (the Healer tick sits at 524 in the list) and about
330 px of height for the form and a few list rows; the list's height follows the page on
each show.
]]

ns.UIDeaths = ns.UIDeaths or {}
local UIDeaths = ns.UIDeaths

local W = LibStub("LibICWidgets-1.0")
local Deaths = ns.Deaths

local PAD = 8                 -- px round the page
local COL_W = 300             -- px, one kind's column
local ROW_H = 20              -- px, one boss row
local TOP_COLUMNS = 40        -- px, where the two kind columns start
local TOP_SETTINGS = 170      -- px, the held line wait row
local TOP_CUE = 198           -- px, the chat cue row
local TOP_HEADER = 232        -- px, the boss list's header row
local TOP_LIST = 252          -- px, the boss list
local FALLBACK_W, FALLBACK_H = 660, 478   -- px, a page with no size yet

-- Boss list columns: x and width, px from the list's left.
local COL_BOSS, COL_BOSS_W = 4, 220
local COL_INSTANCE, COL_INSTANCE_W = 232, 220
local COL_TANK = 464
local COL_HEALER = 524

local page                    -- the built page, or nil before Build
local controls = {}           -- what Refresh re-reads
local bossRows = {}           -- the pooled list rows

local function Db()
    return ns.db
end

local function Cfg(kind)
    local db = Db()
    return db and db.deaths and db.deaths[kind] or nil
end

local function Changed()
    if ns.DeathWatch and ns.DeathWatch.Sync then ns.DeathWatch.Sync() end
    if ns.ChatCue and ns.ChatCue.Sync then ns.ChatCue.Sync() end
    UIDeaths.Refresh()
end

local function Tip(frame, title, ...)
    local lines = { ... }
    W.Tooltip(frame, function(tip)
        tip:AddLine(title)
        for _, line in ipairs(lines) do tip:AddLine(line, 1, 1, 1, true) end
    end)
end

-- A tick box with its label to the right; the label is part of the click target's tooltip.
local function Check(parent, x, y, text, onClick)
    local box = W.CheckBox(parent, { onClick = onClick })
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    local label = W.Label(parent, text)
    label:SetPoint("LEFT", box, "RIGHT", 6, 0)
    box.label = label
    return box
end

--------------------------------------------------------------------------------
-- Toolbar
--------------------------------------------------------------------------------

local function BuildToolbar()
    local announce = W.Button(page, "Announce", 90, 22, {
        kind = "accent",
        onClick = function()
            local plan = ns.DeathWatch.Announce()
            if plan.action ~= "send" then ns.Print("nothing announced: " .. tostring(plan.reason) .. ".") end
            UIDeaths.Refresh()
        end,
    })
    announce:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, -PAD)
    Tip(announce, "Announce", "Posts the seat plan this instance follows to the group now:",
        "Skull first, each crowd control seat with its player.",
        "Only the Raid Lead's press posts. Refused while chat is locked:",
        "a pre-pull line after the pull is wrong, so it is never held.")
    controls.announce = announce

    local test = W.Button(page, "Test alert", 90, 22, {
        onClick = function() ns.DeathWatch.Alert("Tank Example has died") end,
    })
    test:SetPoint("LEFT", announce, "RIGHT", 6, 0)
    Tip(test, "Test alert", "Shows a death call on your screen with its sound. Nobody else sees it.")

    local allowed = Check(page, PAD + 196, PAD + 4, "Announce allowed", function(on)
        Db().settings.announce.prepull = on
        Changed()
    end)
    Tip(allowed, "Announce allowed", "Off: the Announce button and /mfd announce stay quiet.",
        "Same as /mfd announce on or off.")
    controls.allowed = allowed

    local sound = Check(page, PAD + 340, PAD + 4, "Death sound", function(on)
        Db().settings.sound = on
        Changed()
    end)
    Tip(sound, "Death sound", "Plays the raid warning sound with each death call on your screen.")
    controls.sound = sound
end

--------------------------------------------------------------------------------
-- The two kind columns
--------------------------------------------------------------------------------

local OVERRIDE_CHOICES = {
    { "auto", "Per boss" },
    { "on", "Everywhere" },
    { "off", "Nowhere" },
}

local function BuildKind(kind, x)
    local label = Deaths.LABELS[kind]
    local c = {}
    controls[kind] = c

    local head = W.Label(page, label .. " deaths", { font = "title" })
    head:SetPoint("TOPLEFT", page, "TOPLEFT", x, -TOP_COLUMNS)

    c.on = Check(page, x, TOP_COLUMNS + 24, "Call " .. kind .. " deaths", function(on)
        Cfg(kind).on = on
        Changed()
    end)
    Tip(c.on, "Call " .. kind .. " deaths", "The Raid Lead's client says \"" .. label .. " <name> has died\"",
        "as a raid warning (raid chat without assist, party chat in a party),",
        "and shows it on the Raid Lead's screen. Once per person per fight.")

    c.trash = Check(page, x, TOP_COLUMNS + 48, "On trash", function(on)
        Cfg(kind).trash = on
        Changed()
    end)
    Tip(c.trash, "On trash", "Calls " .. kind .. " deaths outside a boss encounter.",
        "Bosses are ticked one at a time in the list below.")

    local nowLabel = W.Label(page, "Right now:")
    nowLabel:SetPoint("TOPLEFT", page, "TOPLEFT", x, -(TOP_COLUMNS + 76))
    c.override = W.Choice(page, 120, 20, {
        choices = OVERRIDE_CHOICES,
        onChange = function(value)
            Cfg(kind).override = value
            Changed()
        end,
    })
    c.override:SetPoint("LEFT", nowLabel, "RIGHT", 8, 0)
    Tip(c.override, "Right now", "Per boss: the trash box and the boss ticks decide.",
        "Everywhere: every " .. kind .. " death, trash and every boss.",
        "Nowhere: none, without losing the ticks. /mfd deaths " .. kind .. " on|off|auto.")

    local extraLabel = W.Label(page, "Also counts:")
    extraLabel:SetPoint("TOPLEFT", page, "TOPLEFT", x, -(TOP_COLUMNS + 104))
    c.extra = W.EditBox(page, 180, 20, {
        maxBytes = 200,
        placeholder = "names, comma separated",
        onEnter = function(text, box)
            Cfg(kind).extra = Deaths.ParseExtra(text)
            box:ClearFocus()
        end,
        onFocusLost = function(box)
            Cfg(kind).extra = Deaths.ParseExtra(box:GetText())
            UIDeaths.Refresh()
        end,
    })
    c.extra:SetPoint("LEFT", extraLabel, "RIGHT", 8, 0)
    local roleWord = kind == "tank" and "the tank icon or Main Tank" or "the healer icon"
    Tip(c.extra, "Also counts as " .. kind, "Players called as a " .. kind .. " besides those with " .. roleWord .. ".",
        "Who counts is read before the pull; a change in combat counts from the next one.")
end

--------------------------------------------------------------------------------
-- Wait, chat cue
--------------------------------------------------------------------------------

local function BuildSettings()
    local waitLabel = W.Label(page, "Held lines wait:")
    waitLabel:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, -(TOP_SETTINGS + 3))
    local wait = W.Slider(page, {
        width = 180, min = 5, max = 30, step = 1, value = 10,
        format = function(v) return string.format("%d s", v) end,
        live = false,
        onChange = function(v)
            Db().settings.chat.deathTTL = v
        end,
    })
    wait:SetPoint("LEFT", waitLabel, "RIGHT", 8, 0)
    wait:EnableMouse(true)
    Tip(wait, "Held lines wait", "When chat is locked, a death line waits this long for it to unlock,",
        "then is dropped and logged (/mfd log held). The alert on your screen shows at once either way.")
    controls.wait = wait

    local cue = Check(page, PAD, TOP_CUE + 3, "Chat cue on", function(on)
        Db().settings.cue.enabled = on
        Changed()
    end)
    Tip(cue, "Chat cue", "A sound when the word is said in party, raid or instance chat,",
        "at most once every few seconds, once a word and a sound are set.",
        "Quiet for a message the client keeps secret.")
    controls.cue = cue

    local word = W.EditBox(page, 120, 20, {
        maxBytes = 40,
        placeholder = "word",
        onEnter = function(text, box)
            Db().settings.cue.word = text
            box:ClearFocus()
        end,
        onFocusLost = function(box)
            Db().settings.cue.word = box:GetText() or ""
            Changed()
        end,
    })
    word:SetPoint("LEFT", cue.label, "RIGHT", 8, 0)
    Tip(word, "Chat cue word", "A whole word or phrase, any case.")
    controls.word = word

    local sound = W.EditBox(page, 220, 20, {
        maxBytes = 200,
        placeholder = "sound kit id or file path",
        onEnter = function(text, box)
            Db().settings.cue.sound = text
            box:ClearFocus()
        end,
        onFocusLost = function(box)
            Db().settings.cue.sound = box:GetText() or ""
            Changed()
        end,
    })
    sound:SetPoint("LEFT", word, "RIGHT", 8, 0)
    Tip(sound, "Chat cue sound", "A sound kit id (a number) or a sound file path under Interface/AddOns.",
        "Nothing plays until one is set: there is no default sound.")
    controls.cueSound = sound
end

--------------------------------------------------------------------------------
-- The boss list
--------------------------------------------------------------------------------

local function BossTick(kind, row)
    local box = W.CheckBox(row, {
        onClick = function(on, self)
            local cfg = Cfg(kind)
            if type(cfg.bosses) ~= "table" then cfg.bosses = {} end
            cfg.bosses[self.encounterID] = on
            Changed()
        end,
    })
    box.encounterID = 0
    W.Tooltip(box, function(tip, self)
        tip:AddLine(Deaths.LABELS[kind] .. " deaths on " .. tostring(self.boss))
        local default = Deaths.BOSS_DEFAULT[kind] and "called" or "not called"
        tip:AddLine("Untouched, a boss is " .. default .. " for " .. kind .. "s.", 1, 1, 1, true)
        tip:AddLine("Read only while Right now is Per boss.", 1, 1, 1, true)
    end)
    return box
end

local function Row(content, i)
    local row = bossRows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, content)
    row:SetSize(COL_HEALER + 40, ROW_H)
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * ROW_H)
    row.boss = W.Label(row, "")
    row.boss:SetPoint("LEFT", row, "LEFT", COL_BOSS, 0)
    row.boss:SetWidth(COL_BOSS_W)
    row.instance = W.Label(row, "", { color = "textDim" })
    row.instance:SetPoint("LEFT", row, "LEFT", COL_INSTANCE, 0)
    row.instance:SetWidth(COL_INSTANCE_W)
    row.tank = BossTick("tank", row)
    row.tank:SetPoint("LEFT", row, "LEFT", COL_TANK, 0)
    row.healer = BossTick("healer", row)
    row.healer:SetPoint("LEFT", row, "LEFT", COL_HEALER, 0)
    bossRows[i] = row
    return row
end

local function BuildList(width, height)
    local header = CreateFrame("Frame", nil, page)
    header:SetSize(width, ROW_H)
    header:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, -TOP_HEADER)
    local cols = {
        { "Boss", COL_BOSS }, { "Instance", COL_INSTANCE }, { "Tank", COL_TANK - 6 }, { "Healer", COL_HEALER - 8 },
    }
    for i, col in ipairs(cols) do
        local l = W.Label(header, col[1], { font = "small", color = "textDim" })
        l:SetPoint("LEFT", header, "LEFT", col[2], 0)
        if i == 1 then controls.count = l end
    end
    header:EnableMouse(true)
    Tip(header, "Bosses", "Every boss in the bundled data. Tick a boss to call that kind's deaths in it.",
        "A boss this client has not met yet is called by its encounter id once one starts.")

    local scroll = W.Scroll(page, width, math.max(ROW_H, height), { step = ROW_H * 3 })
    scroll:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, -TOP_LIST)
    controls.scroll = scroll

    controls.empty = W.Label(scroll.content, "No bosses in the bundled data yet.", { color = "textDim" })
    controls.empty:SetPoint("TOPLEFT", scroll.content, "TOPLEFT", 4, -4)
end

local function RefreshList()
    local rows = Deaths.BossRows(ns.Instances and ns.Instances.list)
    local tank, healer = Cfg("tank"), Cfg("healer")
    for i, data in ipairs(rows) do
        local row = Row(controls.scroll.content, i)
        row.boss:SetText(data.boss)
        row.instance:SetText(data.instance)
        row.tank.encounterID, row.tank.boss = data.encounterID, data.boss
        row.healer.encounterID, row.healer.boss = data.encounterID, data.boss
        row.tank:SetChecked(Deaths.BossTicked("tank", tank, data.encounterID))
        row.healer:SetChecked(Deaths.BossTicked("healer", healer, data.encounterID))
        row:Show()
    end
    for i = #rows + 1, #bossRows do bossRows[i]:Hide() end
    controls.scroll:SetContentHeight(#rows * ROW_H)
    controls.empty:SetShown(#rows == 0)
    controls.count:SetText("Boss (" .. #rows .. ")")
end

--------------------------------------------------------------------------------
-- Refresh and build
--------------------------------------------------------------------------------

function UIDeaths.Refresh()
    if not page or not ns.db then return end
    local s = ns.db.settings
    controls.allowed:SetChecked(s.announce.prepull ~= false)
    controls.sound:SetChecked(s.sound ~= false)
    controls.announce:SetLabel(s.announce.prepull ~= false and "Announce" or "Announce off")
    controls.announce:SetKind(s.announce.prepull ~= false and "accent" or "normal")
    for _, kind in ipairs(Deaths.KINDS) do
        local c, cfg = controls[kind], Cfg(kind)
        c.on:SetChecked(cfg.on == true)
        c.trash:SetChecked(cfg.trash == true)
        c.override:SetValue(cfg.override or "auto")
        if not c.extra:HasFocus() then c.extra:SetText(table.concat(Deaths.ExtraNames(cfg.extra), ", ")) end
    end
    -- A window refresh (roster, zone, comms) must not snap the thumb back mid-drag.
    if controls.wait.icHeld ~= true then
        controls.wait:SetValue(tonumber(s.chat.deathTTL) or Deaths.DEFAULT_TTL)
    end
    controls.cue:SetChecked(s.cue.enabled == true)
    if not controls.word:HasFocus() then controls.word:SetText(s.cue.word or "") end
    if not controls.cueSound:HasFocus() then controls.cueSound:SetText(tostring(s.cue.sound or "")) end
    RefreshList()
end

-- A box with focus takes every key, movement included: drop it when combat starts.
local function DropFocus()
    for _, kind in ipairs(Deaths.KINDS) do controls[kind].extra:ClearFocus() end
    controls.word:ClearFocus()
    controls.cueSound:ClearFocus()
end

function UIDeaths.Build(parent)
    if page then return page end
    page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints(parent)
    local width = parent:GetWidth()
    local height = parent:GetHeight()
    if not width or width < 1 then width = FALLBACK_W end
    if not height or height < 1 then height = FALLBACK_H end

    BuildToolbar()
    BuildKind("tank", PAD)
    BuildKind("healer", PAD + COL_W)
    BuildSettings()
    BuildList(math.min(width - 2 * PAD, COL_HEALER + 60), height - TOP_LIST - PAD)

    -- Kept for the page's life: the page is built already shown, so an OnShow hook would
    -- miss the first display, and dropping focus costs nothing.
    ns.Events.On("PLAYER_REGEN_DISABLED", "uideaths", DropFocus)
    page:SetScript("OnShow", function(self)
        -- The window may have been laid out since Build, or resized: fit the list to it.
        local h = self:GetHeight()
        if h and h > 1 then controls.scroll:SetViewHeight(math.max(ROW_H, h - TOP_LIST - PAD)) end
        UIDeaths.Refresh()
    end)
    page:SetScript("OnHide", DropFocus)
    UIDeaths.Refresh()
    return page
end

ns.OnReady("ui_deaths", function()
    if IC_HEADLESS then return end
    if type(ns.UI) == "table" and type(ns.UI.AddTab) == "function" then
        -- refresh: ns.UI.Refresh() repaints this page while it is the tab showing.
        ns.UI.AddTab("deaths", "Deaths", UIDeaths.Build, { refresh = UIDeaths.Refresh })
    end
end)
