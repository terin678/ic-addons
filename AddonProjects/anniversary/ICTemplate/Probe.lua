local addonName, ns = ...

--[[
"Does this client have X." Retail documentation is often wrong for interface
20506, and guessing has cost this repo a release more than once, so anything the
code is unsure about gets asked here and the answer goes into
.claude/skills/wow-addon-dev/client-api.md.

Every entry is { path, why }. `path` is dotted, so a field on a namespace table
can be checked without indexing a nil. LibICCore does the walking and the printing;
this file is the list and the status lines.
]]

local CHECKS = {
    { "loadstring",
      "the gallery compiles each demo's own source to build it" },
    { "C_Timer.After", "delays; never busy-wait in OnUpdate" },
    { "C_Timer.NewTicker", "the pulse timer" },
    { "SendChatMessage", "the pulse itself, from a hardware event" },
    { "GetChannelList", "finding a public channel by name" },
    { "InCombatLockdown", "half the reasons a send is blocked" },

    { "C_ChatInfo.SendAddonMessage", "addon-to-addon sync, the modern name" },
    { "C_ChatInfo.RegisterAddonMessagePrefix", "whether a prefix must be registered first" },
    { "SendAddonMessage", "addon-to-addon sync, the legacy global" },
    { "RegisterAddonMessagePrefix", "the legacy prefix registration" },

    { "IsInGuild", "is there a guild to talk to at all" },
    { "C_GuildInfo.GuildRoster", "asks the server to refresh the roster" },
    { "GuildRoster", "the legacy name for the same thing" },
    { "GetGuildRosterInfo", "name, rank and rankIndex per member" },
    { "GetGuildInfo", "the guild's own name" },

    { "BackdropTemplateMixin", "whether frames need the backdrop template mixed in" },
    { "GetCoinTextureString", "money in a list cell" },
}

local Probe = ns.Core:Probe(ns, CHECKS)

-- One line per part of the addon. The answer to "it is not doing anything".
function Probe.Status()
    local s = ns.db.settings
    local c = ns.cdb.pulse
    local now = ns.Now()
    local lines = {
        string.format("v%s, ICLibs LibICUI-1.0 minor %s, addon %s",
            ns.VERSION,
            tostring(select(2, LibStub:GetLibrary("LibICUI-1.0", true)) or "?"),
            ns.Util.OnOff(ns.Enabled())),
        string.format("pulse %s, every %ds, last sent %s%s",
            ns.Util.OnOff(s.pulse.enabled), s.pulse.intervalSec,
            ns.Util.Freshness(c.lastSentAt, now, s.pulse.intervalSec * 2),
            ns.Pulse.pending and ", |cffffcc00armed|r" or ""),
        string.format("log %d of %d, capture %d of %d",
            #ns.db.log, ns.Log.MAX_ENTRIES, #ns.db.capture, ns.Log.MAX_CAPTURE),
    }

    local blocked = ns.Pulse.BlockReason(ns.Pulse.ReadState())
    lines[#lines + 1] = blocked
        and ("the pulse cannot fire: |cffffcc00" .. blocked .. "|r")
        or "the pulse can fire."

    if ns.Demos then
        local ok, failed = 0, 0
        for _, demo in ipairs(ns.Demos.list) do
            if demo.fn then ok = ok + 1 else failed = failed + 1 end
        end
        lines[#lines + 1] = string.format("%d demos compile%s", ok,
            failed > 0 and string.format(", |cffff4444%d do not|r", failed) or "")
    end

    local run = ns.db.lastTestRun
    if run then
        lines[#lines + 1] = string.format("tests %s: %d passed, %s%d failed|r",
            ns.Util.Freshness(run.at, now), run.passed or 0,
            (run.failed or 0) > 0 and "|cffff4444" or "|cff44ff44", run.failed or 0)
    else
        lines[#lines + 1] = "tests have not been run this session. /ictpl test"
    end
    return lines
end
