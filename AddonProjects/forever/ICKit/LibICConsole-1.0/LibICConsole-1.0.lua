--[[
LibICConsole-1.0
Layer 1 of ICKit: what an addon says in chat, and the commands a player types at it.

    local Console = LibStub("LibICConsole-1.0")

    local out = Console.New("Stickies", { debug = function() return db.settings.debug end })
    out.Print(msg)   out.Printf(fmt, ...)   out.Debug(fmt, ...)

    Console.Parse("new  Raid prep")         -> "new", "Raid prep"
    Console.HelpLines("/sticky", rows)      -> the lines a help command prints
    Console.Dispatcher(spec)                -> handler(input), Help()
    Console.Slash({ key = "STICKIES", slash = { "/sticky", "/stickies" },
                    out = out, help = rows, commands = { [""] = fn, new = fn } })
                                            -> handler, taken

A command is fn(rest, cmd). The bare command is the "" entry; a word with no entry prints
the help, as does "help" unless the addon supplies its own. help rows are
{ "new [title]", "start a note" }. `taken` says another addon already held the slash key,
which the addon reports at login rather than leave as a confusing afternoon.

Lifted from LibICCore-1.0's output and slash dispatcher, without its reach into the
addon's saved variables: the caller supplies the debug test and, if it wants one, the
chat frame.
]]

local MAJOR, MINOR = "LibICConsole-1.0", 1
local Console = LibStub:NewLibrary(MAJOR, MINOR)
if not Console then return end

-- opts.color is the tag's rrggbb (the theme gold by default); opts.debug() says whether
-- Debug lines print; opts.frame() returns the chat frame to write to.
function Console.New(prefix, opts)
    opts = opts or {}
    local tag = "|cff" .. (opts.color or "df9c33") .. tostring(prefix) .. "|r: "
    local out = {}

    -- Everything the addon says is prefixed, so a player can tell who is talking.
    function out.Print(msg)
        local frame = (opts.frame and opts.frame()) or DEFAULT_CHAT_FRAME
        if frame and frame.AddMessage then
            frame:AddMessage(tag .. tostring(msg))
        else
            print(tag .. tostring(msg))
        end
    end

    function out.Printf(fmt, ...)
        out.Print(string.format(fmt, ...))
    end

    -- For the lines a maintainer wants and a player does not.
    function out.Debug(fmt, ...)
        if opts.debug and opts.debug() then
            out.Print("|cff888888" .. string.format(fmt, ...) .. "|r")
        end
    end

    return out
end

-- Pure. The first word, lower-cased, and everything after it with the ends trimmed.
function Console.Parse(input)
    local raw = tostring(input or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = raw:match("^(%S*)%s*(.*)$")
    return (cmd or ""):lower(), rest or ""
end

-- Pure. One line per help row: the command in gold, then what it does.
function Console.HelpLines(slash, rows)
    local lines = {}
    for _, row in ipairs(rows or {}) do
        lines[#lines + 1] = string.format("  |cffffcc00%s%s|r  %s",
            slash, row[1] ~= "" and (" " .. row[1]) or "", row[2])
    end
    return lines
end

-- The function a slash command runs, built from spec and registered nowhere: a case can
-- call it with a made-up `out`. Returns handler, Help.
function Console.Dispatcher(spec)
    local commands = spec.commands or {}
    local slash = spec.slash and spec.slash[1] or ""

    local function Help()
        spec.out.Print("commands:")
        for _, line in ipairs(Console.HelpLines(slash, spec.help)) do
            spec.out.Print(line)
        end
    end

    local function Handle(input)
        local cmd, rest = Console.Parse(input)
        local fn = commands[cmd]
        if fn then
            fn(rest, cmd)
        else
            Help()
        end
    end

    return Handle, Help
end

-- Registers the command with the client. Returns handler, taken.
function Console.Slash(spec)
    assert(type(spec) == "table" and type(spec.key) == "string" and type(spec.slash) == "table"
        and spec.out, "LibICConsole: Slash needs key, slash and out")
    local handler = Console.Dispatcher(spec)
    local taken = type(SlashCmdList) == "table" and SlashCmdList[spec.key] ~= nil
    for i, s in ipairs(spec.slash) do
        _G["SLASH_" .. spec.key .. i] = s
    end
    SlashCmdList[spec.key] = handler
    return handler, taken
end
