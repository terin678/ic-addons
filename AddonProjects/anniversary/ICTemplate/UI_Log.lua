local addonName, ns = ...

local UI = ns.UI

--[[
The log page. Two filter axes across the toolbar, a count line that says what is
being held back, and a table of what the addon has been doing.

The shape to copy here is the pipeline: 500 captured plus 100 decided, merged down
to a 300-entry window, filtered, and 100 of those drawn. Reading the whole pile on
every click buys nothing anyone can see.
]]

local KINDS = {
    { key = "all", label = "All" },
    { key = "ok", label = "Did" },
    { key = "warn", label = "Skipped" },
    { key = "err", label = "Failed" },
    { key = "info", label = "Noted" },
}

local SHOWN = 100

UI.RegisterPage(40, "Log", function(page)
    local function View()
        return ns.db.settings.log
    end

    local bar = UI.Toolbar(page, { top = 0 })

    local kindButtons = {}
    for _, kind in ipairs(KINDS) do
        local b = bar:Left(UI.Button(bar, kind.label, 58, 22))
        b:SetScript("OnClick", function()
            View().kind = kind.key
            UI.Refresh()
        end)
        kindButtons[kind.key] = b
    end

    -- One button cycling the sources, rather than a button per source: the list
    -- is built from the log itself and a new one can appear at any time.
    local source = bar:Left(UI.Button(bar, "Source: all", 120, 22))
    source:SetScript("OnClick", function()
        local seen = ns.Log.Window(ns.db.log, ns.db.capture)
        local sources = ns.Log.Sources(seen)
        table.insert(sources, 1, "all")
        local v = View()
        local at = 1
        for i, name in ipairs(sources) do
            if name == v.source then at = i end
        end
        v.source = sources[at % #sources + 1]
        UI.Refresh()
    end)

    local clear = bar:Left(UI.Button(bar, "Clear", 60, 22, { kind = "danger" }))
    clear:SetScript("OnClick", function()
        local n = #ns.db.log + #ns.db.capture
        ns.db.log, ns.db.capture = {}, {}
        ns.Printf("cleared %d log %s.", n, ns.Util.Plural(n, "line"))
        UI.Refresh()
    end)

    local hint = bar:Right(UI.Label(page, "", "GameFontDisableSmall"))

    local t = UI.Table(page, {
        top = -28,
        columns = {
            { key = "age", label = "Age", width = 40, justify = "RIGHT" },
            { key = "kind", label = "Kind", width = 48 },
            { key = "source", label = "Source", width = 80 },
            { key = "text", label = "What happened", width = "flex" },
        },
        onEnter = function(row, item)
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:AddLine(item.source or "?", 1, 1, 1)
            GameTooltip:AddLine(date("%Y-%m-%d %H:%M:%S", item.at), 0.8, 0.8, 0.8)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(item.text or "", 1, 1, 1, true)
            if item.detail then
                GameTooltip:AddLine(item.detail, 0.7, 0.7, 0.7, true)
            end
            GameTooltip:Show()
        end,
    })

    return function()
        local v = View()
        for key, b in pairs(kindButtons) do b:SetActive(key == v.kind) end
        source:SetText("Source: " .. (v.source or "all"))

        local seen = ns.Log.Window(ns.db.log, ns.db.capture)
        local entries, hidden = ns.Log.Filter(seen, SHOWN, {
            kind = v.kind,
            source = v.source,
        })

        local now = ns.Now()
        t:Render(entries, function(row, e)
            local age, ageColor = ns.Util.Freshness(e.at, now, 3600)
            t:Set(row, "age", age, ageColor)
            t:Set(row, "kind", (ns.Log.KIND_COLOR[e.kind] or "|cffffffff") .. (e.kind or "?") .. "|r")
            t:Set(row, "source", e.source or "?")
            t:Set(row, "text", e.text or "")
        end)

        -- Say what is being held back. A filtered list that merely looks short is
        -- the thing that gets reported as data loss.
        local parts = { string.format("%d of %d", #entries, #seen) }
        if hidden > 0 then parts[#parts + 1] = string.format("%d filtered", hidden) end
        parts[#parts + 1] = string.format("%d kept, %d captured",
            #ns.db.log, #ns.db.capture)
        hint:SetText("|cff888888" .. table.concat(parts, "  \194\183  ") .. "|r")
    end
end)
