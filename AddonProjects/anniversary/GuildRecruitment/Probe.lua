local addonName, ns = ...

--[[
"Does this client have X", and then "does it actually work".

Nothing in this repo had ever sent an addon message or read the guild roster
before this addon, so neither is in
.claude/skills/wow-addon-dev/client-api.md. Everything the code is unsure about
gets asked here, and whatever the answer turns out to be gets written down there.

The existence checks are the easy half, and LibICCore does them. The loopback at
the end is the one that matters: it sends a real message to the guild channel and
waits to hear it come back, which is the only thing that proves the channel works.
]]

local LOOPBACK_TIMEOUT = 5      -- seconds to wait for our own message to return

local CHECKS = {
    -- Which of these two exists decides how Comm sends. Both are tried.
    { "C_ChatInfo.SendAddonMessage", "guild sync, the modern name" },
    { "SendAddonMessage", "guild sync, the legacy global" },
    { "C_ChatInfo.RegisterAddonMessagePrefix", "whether a prefix must be registered first" },
    { "RegisterAddonMessagePrefix", "the legacy prefix registration" },

    { "IsInGuild", "is there a guild to talk to at all" },
    -- 20506 has neither the bare GuildRoster nor, so far as the code knows, the
    -- namespaced one. Both are checked; the roster reads fine without either.
    { "C_GuildInfo.GuildRoster", "asks the server to refresh the roster" },
    { "GuildRoster", "the legacy name for the same thing" },
    { "GetNumGuildMembers", "how many rows to walk" },
    { "GetGuildRosterInfo", "name, rank and rankIndex per member" },
    { "GetGuildInfo", "the guild's own name, used to drop a message from elsewhere" },

    { "GetChannelList", "finding a public channel by name; stride of three" },
    { "SendChatMessage", "the bark itself, from a hardware event" },
    { "InCombatLockdown", "one of the reasons a bark is blocked" },
    { "IsInInstance", "another" },
    { "C_Timer.After", "delays; never busy-wait in OnUpdate" },
    { "GetServerTime", "one clock for every officer, which the merge rule leans on" },
}

local Probe = ns.Core:Probe(ns, CHECKS)

--[[
Sends one message to the guild and waits to hear it back.

The whole design rests on a GUILD-distribution addon message arriving, and no
amount of checking that the function exists proves the server will carry it. This
is the experiment.

`/gr probe noreg` turns prefix registration off and asks you to reload, which
answers the other open question: whether registration is required at all on this
client, or whether CHAT_MSG_ADDON fires without it.
]]
function Probe.Loopback()
    if not ns.Comm.available then
        ns.Print("|cffff4444no send path,|r so there is nothing to test.")
        return false
    end
    if not (IsInGuild and IsInGuild()) then
        ns.Print("|cffffcc00not in a guild,|r so a GUILD message has nowhere to go.")
        return false
    end

    Probe.pingAt = ns.Now()
    Probe.pinged = true
    ns.Print("|cffffcc00loopback: pinging the guild, waiting " .. LOOPBACK_TIMEOUT .. "s...|r")

    local ok, reason = ns.Comm.Send("V", ns.Comm.EncodeVersion(ns.db.doc), 0, 1, 1)
    if not ok then
        Probe.pinged = false
        ns.Print("|cffff4444loopback failed to send:|r " .. tostring(reason))
        return false
    end

    -- Every wait on the client gets a timeout and a way out. This is that.
    C_Timer.After(LOOPBACK_TIMEOUT, function()
        if not Probe.pinged then return end
        Probe.pinged = false
        ns.Print("|cffff4444loopback failed|r: nothing came back in "
            .. LOOPBACK_TIMEOUT .. "s. Either the prefix has to be registered before "
            .. "CHAT_MSG_ADDON will fire (run /gr probe noreg, /reload, and compare), "
            .. "or this client does not deliver GUILD addon messages at all.")
    end)
    return true
end

-- Called by Comm when anything arrives, so the loopback can notice its own echo.
-- Whether the client echoes your own message back is itself unverified, which is
-- why nothing else in the addon depends on it.
function Probe.Heard(sender)
    if not Probe.pinged then return end
    Probe.pinged = false
    ns.Printf("|cff44ff44loopback ok|r: heard from %s in %.2fs.",
        sender, ns.Now() - (Probe.pingAt or ns.Now()))
end

function Probe.Run(arg)
    arg = (arg or ""):lower()

    if arg == "cancel" then
        Probe.pinged = false
        ns.Print("loopback cancelled.")
        return
    end
    if arg == "noreg" then
        ns.db.settings.sync.registerPrefix = false
        ns.Print("prefix registration is off. |cffffcc00/reload|r, then /gr probe again: "
            .. "if the loopback still works, registration was never needed on this client.")
        return
    end
    if arg == "reg" then
        ns.db.settings.sync.registerPrefix = true
        ns.Print("prefix registration is back on. /reload to apply it.")
        return
    end

    Probe.PrintChecks()

    ns.Printf("sending via |cffffcc00%s|r, prefix registration %s.",
        ns.Comm.sendHow or "nothing",
        ns.Comm.registered and "|cff44ff44accepted|r"
            or (ns.db.settings.sync.registerPrefix and "|cffff4444refused|r" or "off"))

    ns.Roster.Read()
    local me, rank = ns.Roster.Me()
    ns.Printf("guild %s, %d roster rows read; you are %s at rank index %s, which may %s.",
        (IsInGuild and IsInGuild()) and ("|cff44ff44" .. ns.Roster.GuildName() .. "|r")
            or "|cffff4444none|r",
        #ns.Roster.rows, me,
        rank == ns.Roster.UNKNOWN_RANK and "|cffff4444unknown|r" or tostring(rank),
        ns.Roster.ICanAuthor() and "|cff44ff44edit and send|r"
            or (ns.Roster.ICanBark() and "send" or "|cffff4444neither|r"))
    if #ns.Roster.rows > 0 then
        local first = ns.Roster.rows[1]
        ns.Printf("  GetGuildRosterInfo(1) = %s, %s, rankIndex %s",
            first.name, first.rank, tostring(first.rankIndex))
    end

    Probe.Loopback()
end

-- One line per part of the addon. The answer to "it is not doing anything".
function Probe.Status()
    local now = ns.Now()
    local s = ns.db.settings
    local status = ns.Comm.Status()
    local same, behind, ahead = ns.Doc.Agreement(ns.db.doc, ns.db.peers)

    local lines = {
        string.format("v%s, addon %s, %s", ns.VERSION, ns.Util.OnOff(ns.Enabled()),
            ns.Doc.Summary(ns.db.doc, now)),
        string.format("sync %s via %s  \194\183  sent %d, received %d, ignored %d",
            status.available and "|cff44ff44on|r" or "|cffff4444unavailable|r",
            status.how, status.sent, status.received, status.rejected),
        string.format("%d officers in step, %d behind, %d ahead", same, behind, ahead),
        string.format("reminder %s every %s, quiet %s after another officer",
            ns.Util.OnOff(s.bark.enabled), ns.Util.Duration(s.bark.intervalSec),
            s.bark.quietSec == 0 and "off" or ns.Util.Duration(s.bark.quietSec)),
    }

    local blocked = ns.Bark.BlockReason(ns.Bark.ReadState())
    lines[#lines + 1] = blocked
        and ("cannot send: |cffffcc00" .. blocked .. "|r")
        or "|cff44ff44ready to send.|r"

    local run = ns.db.lastTestRun
    lines[#lines + 1] = run
        and string.format("tests %s ago: %d passed, %s%d failed|r",
            ns.Util.Freshness(run.at, now, 0), run.passed or 0,
            (run.failed or 0) > 0 and "|cffff4444" or "|cff44ff44", run.failed or 0)
        or "tests have not been run this session. /gr test"

    return lines
end
