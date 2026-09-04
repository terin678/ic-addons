local addonName, ns = ...

-- Market tab: who else is advertising in Trade, and who is asking.

ns.UI = ns.UI or {}
local UI = ns.UI

local REFRESH_SEC = 30
local KIND_COLOR = { seller = "|cffff8888", buyer = "|cff88ff88" }

function UI.BuildMarket(page)
    local intro = UI.Label(page,
        "Counted from Trade chat: distinct crafters advertising (S) against customers asking (B).\n"
        .. "The suggested interval is advice only; barking keeps the interval you set on the Bark tab.",
        "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", 0, -2)
    intro:SetWidth(690)
    intro:SetJustifyH("LEFT")
    intro:SetSpacing(3)

    local profTable = UI.Table(page, {
        top = -36,
        height = 8 * 18,
        columns = {
            { key = "name", label = "Profession", width = 128 },
            { key = "m15", label = "15m S/B", width = 70, justify = "RIGHT" },
            { key = "h1", label = "1h S/B", width = 70, justify = "RIGHT" },
            { key = "today", label = "Today S/B", width = 80, justify = "RIGHT" },
            { key = "label", label = "Market", width = 80 },
            { key = "suggest", label = "Suggested bark", width = "flex" },
        },
    })

    local recentHead = UI.Label(page, "Recent Trade activity", "GameFontNormal")
    recentHead:SetPoint("TOPLEFT", 0, -(36 + 18 + 8 * 18 + 10))

    local recent = UI.Table(page, {
        top = -(36 + 18 + 8 * 18 + 30),
        bottom = 0,
        columns = {
            { key = "age", label = "Age", width = 40, justify = "RIGHT" },
            { key = "kind", label = "Kind", width = 54 },
            { key = "prof", label = "Prof", width = 100 },
            { key = "who", label = "Player", width = 100 },
            { key = "msg", label = "Message", width = "flex" },
        },
        onEnter = function(row, s)
            GameTooltip:SetOwner(row, "ANCHOR_CURSOR")
            GameTooltip:AddLine(s.who or "?", 1, 1, 1)
            GameTooltip:AddLine(date("%H:%M:%S", s.at or 0), 0.7, 0.7, 0.7)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(s.msg or "", 1, 1, 1, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("counted as",
                (KIND_COLOR[s.kind] or "|cffffffff") .. (s.kind or "?") .. "|r", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end,
    })

    function UI.RefreshMarket()
        local now = ns.Now()
        local active = ns.db.activeProfession

        local list = {}
        for _, key in ipairs(ns.Professions.Order) do
            local _, _, sp, bp = ns.Market.Counts(ns.db, now, key, 86400)
            local pd = ns.db.professions and ns.db.professions[key]
            local scanned = pd and pd.book and next(pd.book) ~= nil
            if scanned or sp > 0 or bp > 0 then list[#list + 1] = key end
        end

        profTable:Render(list, function(row, key)
            local p = ns.Prof.ByKey(key)
            local s15, b15 = ns.Market.Counts(ns.db, now, key, 900)
            local s1h, b1h = ns.Market.Counts(ns.db, now, key, 3600)
            local sd, bd = ns.Market.Counts(ns.db, now, key, 86400)
            local label = ns.Market.Label(s1h, b1h)

            profTable:Set(row, "name",
                (key == active and "|cff44ff44" or "|cffffffff") .. p.name .. "|r")
            profTable:Set(row, "m15", string.format("%d/%d", s15, b15))
            profTable:Set(row, "h1", string.format("%d/%d", s1h, b1h))
            profTable:Set(row, "today", string.format("%d/%d", sd, bd))
            profTable:Set(row, "label", ns.Market.LabelColor(label) .. label .. "|r")

            local pd = ns.db.professions and ns.db.professions[key]
            if pd and pd.settings and pd.settings.bark then
                local base = pd.settings.bark.intervalSec
                local suggest = ns.Market.SuggestInterval(base, s1h, b1h)
                profTable:Set(row, "suggest", suggest == base
                    and string.format("|cff888888%ds, unchanged|r", base)
                    or string.format("%ds  |cff888888(set to %ds)|r", suggest, base))
            else
                profTable:Set(row, "suggest", "|cff777777no book scanned|r")
            end
        end)

        local samples = ns.Market.Recent(ns.db, 100)
        recent:Render(samples, function(row, s)
            local p = ns.Prof.ByKey(s.prof)
            recent:Set(row, "age", UI.Age(now - (s.at or now)))
            recent:Set(row, "kind", (KIND_COLOR[s.kind] or "|cffffffff") .. (s.kind or "?") .. "|r")
            recent:Set(row, "prof", "|cff888888" .. (p and p.name or s.prof or "") .. "|r")
            recent:Set(row, "who", s.who or "?")
            recent:Set(row, "msg", s.msg or "")
        end)

        if #samples == 0 then
            recentHead:SetText("Recent Trade activity  |cff888888nothing seen yet; it fills up as Trade chat scrolls|r")
        else
            recentHead:SetText("Recent Trade activity")
        end
    end

    -- Counts move on their own, so the page keeps itself current while visible.
    page:SetScript("OnShow", function()
        if not UI.marketTicker then
            UI.marketTicker = C_Timer.NewTicker(REFRESH_SEC, function()
                if page:IsVisible() then UI.RefreshMarket() end
            end)
        end
    end)
    page:SetScript("OnHide", function()
        if UI.marketTicker then
            UI.marketTicker:Cancel()
            UI.marketTicker = nil
        end
    end)
end
