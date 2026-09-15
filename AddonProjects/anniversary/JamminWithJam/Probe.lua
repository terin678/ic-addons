local addonName, ns = ...

--[[
"Does this client have X." Retail documentation is often wrong for interface
20506, and guessing has cost this repo a release more than once, so anything
the code is unsure about gets asked here and the answer goes into
.claude/skills/wow-addon-dev/client-api.md.

Every entry is { path, why }. `path` is dotted, so a field on a namespace table
can be checked without indexing a nil. LibICCore does the walking and the
printing; this file is the list and the status lines.
]]

local CHECKS = {
    { "SendChatMessage", "the trigger line itself, from a hardware event" },
    { "InCombatLockdown", "half the reasons a send would be blocked elsewhere" },

    { "IsInGuild", "is there a guild to check a rank against" },
    { "C_GuildInfo.GuildRoster", "asks the server to refresh the roster" },
    { "GuildRoster", "the legacy name for the same thing" },
    { "GetNumGuildMembers", "how many rows to read" },
    { "GetGuildRosterInfo", "name and rankIndex per member, for the officer check" },

    { "BackdropTemplateMixin", "whether frames need the backdrop template mixed in" },
}

local Probe = ns.Core:Probe(ns, CHECKS)

-- One line per part of the addon. The answer to "it is not doing anything".
function Probe.Status()
    local lines = {
        string.format("v%s, ICLibs LibICUI-1.0 minor %s, addon %s",
            ns.VERSION,
            tostring(select(2, LibStub:GetLibrary("LibICUI-1.0", true)) or "?"),
            ns.Util.OnOff(ns.Enabled())),
        string.format("channel %s, officer rank %d and up",
            ns.db.settings.channel, ns.db.settings.officerRankIndex),
        string.format("log %d of %d, capture %d of %d",
            #ns.db.log, ns.Log.MAX_ENTRIES, #ns.db.capture, ns.Log.MAX_CAPTURE),
        "this addon cannot tell whether the Discord bot is running or "
            .. "/chatlog is on; that is what /jam play is for -- send one and "
            .. "check the bot's own console.",
    }

    local run = ns.db.lastTestRun
    if run then
        lines[#lines + 1] = string.format("tests %s: %d passed, %s%d failed|r",
            ns.Util.Freshness(run.at, ns.Now()), run.passed or 0,
            (run.failed or 0) > 0 and "|cffff4444" or "|cff44ff44", run.failed or 0)
    else
        lines[#lines + 1] = "tests have not been run this session. /jam test"
    end
    return lines
end
