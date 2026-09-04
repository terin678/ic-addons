local addonName, ns = ...

ns.Snippet = ns.Snippet or {}
local Snippet = ns.Snippet

--[[
A demo is a string of Lua source. The gallery compiles that string to build the
live widget AND shows the same string in the pane beside it, so the two cannot
disagree: editing the snippet is editing the code, because they are the same
bytes.

The alternative -- a widget built in one place and a string describing it written
in another -- drifts the first time either is touched, and drifts silently.

Two things follow from doing it this way:

  * loadstring has to exist. /ictpl probe reports whether it does. If a future
    client drops it, put a real function on each demo and say "source in
    Demos.lua" in the pane. Do not go back to a hand-written string.
  * a compiled chunk is tainted, so no demo may touch a secure frame or the
    Blizzard dropdown system. Nothing in the gallery does.
]]

-- Pure. Removes the indentation every line shares, so a snippet stored inside a
-- [[ ]] block in an indented table still reads as top-level code.
function Snippet.Dedent(src)
    src = tostring(src or ""):gsub("^\n", ""):gsub("%s+$", "")
    local least
    for line in (src .. "\n"):gmatch("([^\n]*)\n") do
        if line:match("%S") then
            local indent = #line:match("^[ \t]*")
            if not least or indent < least then least = indent end
        end
    end
    if not least or least == 0 then return src end
    local out = {}
    for line in (src .. "\n"):gmatch("([^\n]*)\n") do
        out[#out + 1] = line:sub(least + 1)
    end
    -- Parenthesised: gsub returns a count as well, and a helper that quietly
    -- hands back two values breaks the first assertion that compares it to one.
    return (table.concat(out, "\n"):gsub("%s+$", ""))
end

-- Pure. "[string \"@button\"]:3: unexpected symbol" -> "line 3: unexpected symbol".
-- The chunk name is ours, not the reader's problem.
function Snippet.CleanError(err)
    err = tostring(err or "")
    err = err:gsub('%[string "@?([^"]*)"%]:(%d+):', "line %2:")
    err = err:gsub("^@?[%w_%-]*:(%d+):", "line %1:")
    return ns.Util.Trim(err)
end

-- Pure. The source split into lines, for a pane that numbers them.
function Snippet.Lines(src)
    local out = {}
    for line in (tostring(src or "") .. "\n"):gmatch("([^\n]*)\n") do
        out[#out + 1] = line
    end
    if out[#out] == "" then table.remove(out) end
    return out
end

--[[
Compiles a demo body into fn(page, ICUI, ns), or returns nil and a message.

The wrapper header stays on line 1 with no newline after it, so a syntax error's
line number is the demo's own line number and not one more than it.
]]
function Snippet.Compile(src, chunkName)
    if type(loadstring) ~= "function" then
        return nil, "this client has no loadstring; see Demos.lua for the source"
    end
    local wrapped = "return function(page, ICUI, ns) " .. Snippet.Dedent(src) .. " end"
    local chunk, err = loadstring(wrapped, "@" .. (chunkName or "demo"))
    if not chunk then return nil, Snippet.CleanError(err) end
    local ok, fn = pcall(chunk)
    if not ok then return nil, Snippet.CleanError(fn) end
    return fn
end
