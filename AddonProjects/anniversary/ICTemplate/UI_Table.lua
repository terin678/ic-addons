local addonName, ns = ...

local UI = ns.UI

--[[
One page, one table, every feature of it at once, at the size a real page uses it.
The gallery shows each trick on its own; this shows them getting along.

Everything here follows "Window layout" in CODING_STANDARDS.md, and the two rules
that get broken most often are worth naming:

  * the filter buttons write to ns.db, not to a local. A filter kept in a Lua
    table resets on /reload, and a list that comes back empty reads as lost data.
  * the count line says how many rows the filters are holding back, so a short
    list explains itself instead of looking like a bug.
]]

local GOOD = { r = 0.4, g = 1, b = 0.4 }
local BAD = { r = 1, g = 0.4, b = 0.4 }
local GREY = { r = 0.55, g = 0.55, b = 0.55 }

local FILTERS = {
    { key = "all", label = "All" },
    { key = "ready", label = "Ready" },
    { key = "waiting", label = "Waiting" },
}

-- Pure. Which rows survive the filter, and how many did not.
local function Apply(rows, filter)
    local out, hidden = {}, 0
    for _, item in ipairs(rows) do
        local keep = filter == "all"
            or (filter == "ready" and item.ready)
            or (filter == "waiting" and not item.ready)
        if keep then out[#out + 1] = item else hidden = hidden + 1 end
    end
    return out, hidden
end

UI.RegisterPage(20, "Table", function(page)
    local function View()
        return ns.db.settings.tablePage
    end

    local bar = UI.Toolbar(page, { top = 0 })
    local buttons = {}
    for _, filter in ipairs(FILTERS) do
        local b = bar:Left(UI.Button(bar, filter.label, 64, 22))
        b:SetScript("OnClick", function()
            View().filter = filter.key
            UI.Refresh()
        end)
        buttons[filter.key] = b
    end

    local reset = bar:Left(UI.Button(bar, "Reset stock", 90, 22, { kind = "danger" }))
    reset:SetScript("OnClick", function()
        for _, item in ipairs(ns.Demos.rows) do item.ready = item.stock > 0 end
        UI.Refresh()
    end)

    local hint = bar:Right(UI.Label(page, "", "GameFontDisableSmall"))

    local t
    t = UI.Table(page, {
        top = -28,
        columns = {
            { key = "icon", label = "", width = 24, type = "texture" },
            -- The flex column is the one with no natural width. Exactly one may
            -- be flex; the library asserts if a second tries.
            { key = "name", label = "Item", width = "flex", hit = true },
            { key = "kind", label = "Kind", width = 90 },
            { key = "stock", label = "Stock", width = 54, justify = "RIGHT" },
            { key = "price", label = "Price", width = 110, justify = "RIGHT" },
            { key = "ready", label = "Ready", width = 44, type = "check" },
        },
        buttons = {
            { key = "bump", label = "+1", width = 34 },
            { key = "zero", label = "Empty", width = 54, kind = "danger" },
        },
        onHeaderClick = function(col)
            local v = View()
            -- Clicking the live column reverses it; a different one starts
            -- ascending, which is the order a reader expects to land in.
            if v.sort == col.key then
                v.desc = not v.desc
            else
                v.sort, v.desc = col.key, false
            end
            UI.Refresh()
        end,
        onEnter = function(row, item)
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:AddLine(item.name, 1, 1, 1)
            GameTooltip:AddLine(item.kind, 0.8, 0.8, 0.8)
            GameTooltip:AddLine(string.format("%d on hand at %s each",
                item.stock, GetCoinTextureString(item.price)))
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("A row is one line and truncates. The whole of it "
                .. "lives here.", 0.6, 0.6, 0.6, true)
            GameTooltip:Show()
        end,
        onClick = function(row, item, button, tbl)
            tbl:SetSelected(item)
        end,
    })

    return function()
        local v = View()
        for key, b in pairs(buttons) do b:SetActive(key == v.filter) end

        local rows, hidden = Apply(ns.Demos.rows, v.filter)

        table.sort(rows, function(a, b)
            local x, y = a[v.sort], b[v.sort]
            if x == y then return a.name < b.name end
            if type(x) == "boolean" then x, y = x and 1 or 0, y and 1 or 0 end
            if v.desc then return x > y end
            return x < y
        end)

        for _, col in ipairs(t.columns) do
            local label = col.label
            if col.key == v.sort and label ~= "" then
                label = label .. (v.desc and " v" or " ^")
            end
            local fs = t.header.labels[col.key]
            if fs then fs:SetText(label) end
        end

        -- Group the survivors under a heading each, and total them at the bottom.
        local list, total, seen = {}, 0, {}
        for _, item in ipairs(rows) do
            if not seen[item.kind] then
                seen[item.kind] = true
                list[#list + 1] = { span = item.kind }
                for _, other in ipairs(rows) do
                    if other.kind == item.kind then
                        list[#list + 1] = other
                        total = total + other.price * other.stock
                    end
                end
            end
        end
        if #rows > 0 then list[#list + 1] = { total = total } end

        t:Render(list, function(row, item)
            if item.span then
                t:Span(row, item.span)
                return
            end
            if item.total then
                t:Tint(row, ns.UI.Lib.Brand.gold)
                t:Set(row, "name", "Everything shown")
                t:Set(row, "price", GetCoinTextureString(item.total))
                -- Render hands every row back with its cells and buttons showing.
                -- A totals line has nothing to check and nothing to press, and an
                -- empty check box on it reads as a row somebody forgot to tick.
                row.cells.ready:Hide()
                for _, btn in pairs(row.buttons) do btn:Hide() end
                return
            end

            row.cells.icon:SetTexture(item.icon)
            t:Set(row, "name", item.name)
            t:Set(row, "kind", item.kind)
            -- Nothing in stock is missing, not bad: grey rather than red.
            local color = GREY
            if item.stock > 5 then color = GOOD elseif item.stock > 0 then color = BAD end
            t:Set(row, "stock", tostring(item.stock), color)
            t:Set(row, "price", GetCoinTextureString(item.price))

            row.cells.ready:SetChecked(item.ready)
            row.cells.ready:SetScript("OnClick", function(self)
                item.ready = self:GetChecked() and true or false
                UI.Refresh()
            end)

            -- Rows come out of a pool wearing the last item's scripts, so every
            -- one of these is set on every render, never once at build time.
            UI.Tooltip(row.hit.name, function()
                GameTooltip:AddLine(item.name, 1, 1, 1)
                GameTooltip:AddLine("The name cell has its own hit frame, because a "
                    .. "FontString takes no scripts.", 0.8, 0.8, 0.8, true)
            end)

            row.buttons.bump:SetScript("OnClick", function()
                item.stock = item.stock + 1
                UI.Refresh()
            end)
            row.buttons.zero:SetEnabled(item.stock > 0)
            row.buttons.zero:SetScript("OnClick", function()
                item.stock = 0
                UI.Refresh()
            end)
        end)

        local parts = { string.format("%d of %d", #rows, #ns.Demos.rows) }
        if hidden > 0 then parts[#parts + 1] = string.format("%d filtered", hidden) end
        parts[#parts + 1] = "sorted by " .. v.sort
        hint:SetText("|cff888888" .. table.concat(parts, "  \194\183  ") .. "|r")
    end
end)
