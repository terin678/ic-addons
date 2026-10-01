--[[
LibICTest-1.0
Layer 0 of ICKit: the case runner. The same cases run headless under LuaJIT
(scripts/run-tests.ps1) and in game behind an addon's own "test" command, so a change is
checked before the client is ever opened and again on the client it ships to.

    local Test = LibStub("LibICTest-1.0")
    local T = Test.New({ print = fn(line), onDone = fn(result) })

    T.Case(name, fn)                        register a case
    T.Eq(actual, expected, label)           raise unless equal
    T.True(value, label)                    raise unless truthy
    T.Near(actual, expected, tol, label)    raise unless within tol (default 0.001)
    T.Run() -> passed, failed               run every case, print failures and a summary

result = { passed, failed, failures = { { name, err }, ... } }

A registry knows nothing about saved variables or windows. Model functions take their
tables as arguments, so a case builds its own input and nothing has to be swapped out and
restored around it. Lifted from LibICCore-1.0's harness, without its reach into ns.db.
]]

local MAJOR, MINOR = "LibICTest-1.0", 1
local Test = LibStub:NewLibrary(MAJOR, MINOR)
if not Test then return end

function Test.New(opts)
    opts = opts or {}
    local out = opts.print or print
    local T = { cases = {} }

    function T.Case(name, fn)
        T.cases[#T.cases + 1] = { name = name, fn = fn }
    end

    -- Level 2 on every error, so the reported line is the assertion's and not this file's.
    function T.Eq(actual, expected, label)
        if actual ~= expected then
            error(string.format("%s: expected [%s], got [%s]",
                tostring(label or "value"), tostring(expected), tostring(actual)), 2)
        end
    end

    function T.True(value, label)
        if not value then
            error(string.format("%s: expected true, got [%s]",
                tostring(label or "value"), tostring(value)), 2)
        end
    end

    -- T.Near(actual, expected, label) is accepted too.
    function T.Near(actual, expected, tolerance, label)
        if type(tolerance) == "string" then label, tolerance = tolerance, nil end
        if tolerance == nil then tolerance = 0.001 end
        if type(actual) ~= "number" or math.abs(actual - expected) > tolerance then
            error(string.format("%s: expected [%s] give or take %s, got [%s]",
                tostring(label or "value"), tostring(expected), tostring(tolerance),
                tostring(actual)), 2)
        end
    end

    function T.Run()
        local pass, fail, failures = 0, 0, {}
        for _, case in ipairs(T.cases) do
            local ok, err = pcall(case.fn)
            if ok then
                pass = pass + 1
            else
                fail = fail + 1
                failures[#failures + 1] = { name = case.name, err = tostring(err) }
                out("|cffff4444FAIL|r " .. case.name .. " => " .. tostring(err))
            end
        end
        out(string.format("Tests: |cff44ff44%d passed|r, %s%d failed|r",
            pass, fail > 0 and "|cffff4444" or "|cff44ff44", fail))
        if opts.onDone then
            opts.onDone({ passed = pass, failed = fail, failures = failures })
        end
        return pass, fail
    end

    return T
end
