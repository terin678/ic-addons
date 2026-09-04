local addonName, ns = ...

local UI = ns.UI

--[[
The gallery. Left, an index of every demo; right, the demo running, with the
source it was built from underneath it.

The two panes cannot disagree, because there is only one artifact: the string in
Demos.lua is compiled to make the live widget AND printed in the pane. Editing one
is editing the other.

The index is itself a demo of two Table features that have nowhere else to show
themselves: Span for the group headings, and SetSelected for the current pick.
]]

local INDEX_W = 170        -- the demo list on the left
local PANE_X = INDEX_W + 12
local PANE_W = 518         -- everything to the right of the index
local LIVE_H = 190         -- how tall a demo gets to be
local SOURCE_H = 186

UI.RegisterPage(10, "Gallery", function(page)
    local index
    index = UI.Table(page, {
        left = 0, top = 0, width = INDEX_W,
        columns = {
            { key = "title", label = "Demos", width = "flex" },
        },
        onClick = function(row, item, button, t)
            if not item.demo then return end
            ns.db.settings.gallery.demo = item.demo.id
            t:SetSelected(item)
            UI.Refresh()
        end,
    })

    local title = UI.Label(page, "", "GameFontNormal")
    title:SetPoint("TOPLEFT", PANE_X, -2)
    title:SetWidth(PANE_W)

    local blurb = UI.Label(page, "", "GameFontHighlightSmall")
    blurb:SetPoint("TOPLEFT", PANE_X, -20)
    blurb:SetWidth(PANE_W)
    blurb:SetSpacing(2)

    -- The demo runs in here. One container per demo, built on first sight and
    -- kept: frame pools over frame churn, and rebuilding on every click would
    -- leak a widget set each time.
    local live = ns.UI.Lib:Panel(page, { style = UI.Style })
    live:SetSize(PANE_W, LIVE_H)
    live:SetPoint("TOPLEFT", PANE_X, -54)

    local bar = UI.Toolbar(page, { top = -(54 + LIVE_H + 6), left = PANE_X })

    local copy = bar:Left(UI.Button(bar, "Copy source", 100, 22))
    local reload = bar:Left(UI.Button(bar, "Rebuild", 80, 22, { kind = "accent" }))
    UI.Tooltip(reload, function()
        GameTooltip:AddLine("Rebuild", 1, 1, 1)
        GameTooltip:AddLine("Throws this demo's widgets away and compiles it again. "
            .. "After a /reload with a changed ICLibs, this is the check that it "
            .. "still works.", 0.8, 0.8, 0.8, true)
    end)

    local source = UI.TextBox(page, PANE_W, SOURCE_H, { readOnly = true })
    source:SetPoint("TOPLEFT", PANE_X, -(54 + LIVE_H + 34))

    local containers = {}

    local function Current()
        return ns.Demos.ById(ns.db.settings.gallery.demo) or ns.Demos.list[1]
    end

    -- Builds a demo's widgets once. Returns the container, whether it drew, and
    -- the error if it did not.
    local function Container(demo)
        local held = containers[demo.id]
        if held then return held.frame, held.ok, held.err end

        local frame = CreateFrame("Frame", nil, live)
        frame:SetPoint("TOPLEFT", 8, -8)
        frame:SetPoint("BOTTOMRIGHT", -8, 8)
        frame:Hide()

        local ok, err = demo.fn ~= nil, demo.err
        if ok then
            -- A demo that errors while drawing must not take the window with it,
            -- and the error belongs on screen where the demo would have been.
            local ran, runErr = pcall(demo.fn, frame, ns.UI.Lib, ns)
            if not ran then
                ok, err = false, ns.Snippet.CleanError(runErr)
                ns.Log.Add("err", "Gallery", "demo " .. demo.id .. " errored while drawing", err)
            end
        end

        if not ok then
            local msg = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            msg:SetPoint("TOPLEFT", 0, 0)
            msg:SetWidth(PANE_W - 30)
            msg:SetJustifyH("LEFT")
            msg:SetText("|cffff4444This demo did not build.|r\n" .. tostring(err))
        end

        containers[demo.id] = { frame = frame, ok = ok, err = err }
        return frame, ok, err
    end

    local function Rebuild(demo)
        local held = containers[demo.id]
        if held then
            held.frame:Hide()
            held.frame:SetParent(nil)
            containers[demo.id] = nil
        end
        demo.fn, demo.err = ns.Snippet.Compile(demo.source, demo.id)
        UI.Refresh()
    end

    copy:SetScript("OnClick", function() source:SelectAllAndFocus() end)
    reload:SetScript("OnClick", function() Rebuild(Current()) end)

    return function()
        local demo = Current()

        -- The index: one Span per group, then its demos.
        local list = {}
        for _, group in ipairs(ns.Demos.Groups()) do
            list[#list + 1] = { span = group.name }
            for _, d in ipairs(group.demos) do list[#list + 1] = { demo = d } end
        end

        local selected
        index:Render(list, function(row, item)
            if item.span then
                index:Span(row, item.span)
                return
            end
            index:Set(row, "title", item.demo.title)
            if not item.demo.fn then
                index:Set(row, "title", item.demo.title, { r = 1, g = 0.3, b = 0.3 })
            end
            if item.demo.id == demo.id then selected = item end
        end)
        if selected then index:SetSelected(selected) end

        title:SetText(demo.title .. "  |cff888888" .. demo.id .. "|r")
        blurb:SetText(demo.blurb or "")
        source:SetText(ns.Snippet.Dedent(demo.source))

        for id, held in pairs(containers) do
            held.frame:SetShown(id == demo.id)
        end
        local frame = Container(demo)
        frame:Show()
    end
end)
