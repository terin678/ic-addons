-- Chart.lua - Minimal texture-based range bar chart
local MAWChart = {}

local COLOR_NEUTRAL = { 0.55, 0.65, 0.85 }
local COLOR_BEST = { 0.35, 0.9, 0.35 }
local COLOR_WORST = { 0.95, 0.35, 0.35 }
local COLOR_EMPTY = { 0.3, 0.3, 0.3 }
local COLOR_EXTERNAL = { 0.8, 0.7, 0.4 }

local LEFT_MARGIN = 62
local BOTTOM_MARGIN = 18
local TOP_MARGIN = 8
local RIGHT_MARGIN = 8
local GRIDLINES = 4

local function FormatMoney(copper)
    if _G.MalexisAuctionWatcherHelpers then
        return _G.MalexisAuctionWatcherHelpers.FormatMoney(copper)
    end
    return tostring(math.floor(copper or 0))
end

local ChartMixin = {}

function ChartMixin:AcquireBar(index)
    local bar = self.bars[index]
    if bar then
        return bar
    end

    bar = CreateFrame("Button", nil, self.plot)
    bar.range = bar:CreateTexture(nil, "ARTWORK")
    bar.avg = bar:CreateTexture(nil, "OVERLAY")
    bar.avg:SetColorTexture(1, 1, 1, 0.9)
    bar.avg:SetHeight(2)

    bar:SetScript("OnEnter", function(b)
        local p = b.point
        if not p then return end
        -- Anchor to the visible candle, not the full-height hit area
        GameTooltip:SetOwner(b, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("BOTTOM", b.range, "TOP", 0, 6)
        GameTooltip:AddLine(b.tooltipTitle or p.label)
        if p.n and p.n > 0 then
            GameTooltip:AddDoubleLine("Low", FormatMoney(p.low), 1, 1, 1, 0.5, 1, 0.5)
            GameTooltip:AddDoubleLine("Average", FormatMoney(p.avg), 1, 1, 1, 1, 1, 0.5)
            GameTooltip:AddDoubleLine("High", FormatMoney(p.high), 1, 1, 1, 1, 0.5, 0.5)
            GameTooltip:AddDoubleLine("Samples", tostring(p.n), 1, 1, 1, 0.8, 0.8, 0.8)
            if p.src then
                local MAW = _G.MalexisAuctionWatcher
                local name = (MAW and MAW.SourceLabel) and MAW:SourceLabel(p.src) or p.src
                GameTooltip:AddDoubleLine("Source", name, 1, 1, 1, 0.9, 0.7, 0.4)
            end
        else
            GameTooltip:AddLine("No data", 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
    end)
    bar:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self.bars[index] = bar
    return bar
end

function ChartMixin:AcquireLabel(index)
    local label = self.xLabels[index]
    if label then
        return label
    end
    label = self.plot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetTextColor(0.7, 0.7, 0.7)
    self.xLabels[index] = label
    return label
end

-- points: { {label, low, avg, high, n, src}, ... }
-- opts: { highlight = { best = i, worst = i }, maxLabels = n, tooltipTitle = fn(point) }
function ChartMixin:SetData(points, opts)
    opts = opts or {}
    local plotW = self:GetWidth() - LEFT_MARGIN - RIGHT_MARGIN
    local plotH = self:GetHeight() - TOP_MARGIN - BOTTOM_MARGIN
    self.plot:SetSize(math.max(plotW, 1), math.max(plotH, 1))

    -- Value range
    local minV, maxV
    for _, p in ipairs(points) do
        if p.n and p.n > 0 then
            if not minV or p.low < minV then minV = p.low end
            if not maxV or p.high > maxV then maxV = p.high end
        end
    end
    local hasData = minV ~= nil
    -- Reference lines widen the range so they are drawn at their real value
    for _, ref in ipairs(opts.refLines or {}) do
        if ref.value and ref.value > 0 then
            if not minV or ref.value < minV then minV = ref.value end
            if not maxV or ref.value > maxV then maxV = ref.value end
        end
    end
    if not minV then
        minV, maxV = 0, 1
    end
    -- Pad the range so bars don't touch the edges, and never start below zero
    local pad = (maxV - minV) * 0.1
    if pad == 0 then pad = math.max(maxV * 0.1, 1) end
    minV = math.max(0, minV - pad)
    maxV = maxV + pad
    local range = maxV - minV

    local function YFor(value)
        return ((value - minV) / range) * plotH
    end

    -- Gridlines and y labels
    for i = 0, GRIDLINES do
        local line = self.grid[i]
        local text = self.yLabels[i]
        local frac = i / GRIDLINES
        local y = frac * plotH
        line:ClearAllPoints()
        line:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", 0, y)
        line:SetPoint("BOTTOMRIGHT", self.plot, "BOTTOMRIGHT", 0, y)
        text:ClearAllPoints()
        text:SetPoint("RIGHT", self.plot, "BOTTOMLEFT", -4, y)
        text:SetText(hasData and FormatMoney(minV + frac * range) or "")
    end

    -- Bars
    local count = #points
    local slotW = count > 0 and (plotW / count) or plotW
    local barW = math.max(2, math.floor(slotW * 0.7))
    local maxLabels = opts.maxLabels or count
    local labelEvery = math.max(1, math.ceil(count / maxLabels))
    local highlight = opts.highlight or {}

    for i, p in ipairs(points) do
        local bar = self:AcquireBar(i)
        bar.point = p
        bar.tooltipTitle = opts.tooltipTitle and opts.tooltipTitle(p) or nil
        local x = (i - 1) * slotW + (slotW - barW) / 2
        bar:ClearAllPoints()
        bar:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", x, 0)
        bar:SetSize(barW, plotH)

        bar.range:ClearAllPoints()
        bar.avg:ClearAllPoints()
        if p.n and p.n > 0 then
            local yLow = YFor(p.low)
            local yHigh = YFor(p.high)
            local h = math.max(2, yHigh - yLow)
            bar.range:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, yLow)
            bar.range:SetSize(barW, h)

            local c = COLOR_NEUTRAL
            if highlight.best == i then
                c = COLOR_BEST
            elseif highlight.worst == i then
                c = COLOR_WORST
            elseif p.src and p.src ~= "scan" then
                c = COLOR_EXTERNAL
            end
            bar.range:SetColorTexture(c[1], c[2], c[3], 0.85)

            bar.avg:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, YFor(p.avg) - 1)
            bar.avg:SetWidth(barW)
            bar.avg:Show()
        else
            bar.range:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
            bar.range:SetSize(barW, 2)
            bar.range:SetColorTexture(COLOR_EMPTY[1], COLOR_EMPTY[2], COLOR_EMPTY[3], 0.6)
            bar.avg:Hide()
        end
        bar:Show()

        local label = self:AcquireLabel(i)
        label:ClearAllPoints()
        label:SetPoint("TOP", bar, "BOTTOM", 0, -2)
        if (i - 1) % labelEvery == 0 then
            label:SetText(p.label or "")
            label:Show()
        else
            label:Hide()
        end
    end

    -- Hide leftovers from a previous, larger data set
    for i = count + 1, #self.bars do
        self.bars[i]:Hide()
        if self.xLabels[i] then self.xLabels[i]:Hide() end
    end

    -- Reference lines (horizontal, e.g. TSM averages)
    local refs = opts.refLines or {}
    local LABEL_H = 12
    local placedLabelYs = {}
    local function LabelCollides(y)
        for _, other in ipairs(placedLabelYs) do
            if math.abs(other - y) < LABEL_H then
                return true
            end
        end
        return false
    end

    for i, ref in ipairs(refs) do
        local line = self.refLines[i]
        if not line then
            line = {}
            line.tex = self.plot:CreateTexture(nil, "OVERLAY")
            line.tex:SetHeight(1)
            line.text = self.plot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            self.refLines[i] = line
        end
        local c = ref.color or { 0.9, 0.6, 0.9 }
        line.tex:SetColorTexture(c[1], c[2], c[3], 0.9)
        line.text:SetTextColor(c[1], c[2], c[3])

        if ref.value and ref.value > 0 then
            local y = math.max(0, math.min(plotH, YFor(ref.value)))
            line.tex:ClearAllPoints()
            line.tex:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", 0, y)
            line.tex:SetPoint("BOTTOMRIGHT", self.plot, "BOTTOMRIGHT", 0, y)

            -- Label sits just above its line; if that overlaps another label,
            -- try just below, then keep stepping down until it is clear.
            local labelY = y + 1
            if LabelCollides(labelY) or labelY + LABEL_H > plotH then
                labelY = y - LABEL_H
                while LabelCollides(labelY) and labelY > 0 do
                    labelY = labelY - LABEL_H
                end
            end
            table.insert(placedLabelYs, labelY)

            line.text:ClearAllPoints()
            line.text:SetPoint("BOTTOMRIGHT", self.plot, "BOTTOMRIGHT", -2, labelY)
            line.text:SetText((ref.label or "") .. " " .. FormatMoney(ref.value))
            line.tex:Show()
            line.text:Show()
        else
            line.tex:Hide()
            line.text:Hide()
        end
    end
    for i = #refs + 1, #self.refLines do
        self.refLines[i].tex:Hide()
        self.refLines[i].text:Hide()
    end

    self.emptyText:SetShown(not hasData)
end

function MAWChart.Create(parent, width, height)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width, height)
    Mixin(frame, ChartMixin)

    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.bg:SetColorTexture(0.05, 0.05, 0.08, 0.8)

    frame.plot = CreateFrame("Frame", nil, frame)
    frame.plot:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", LEFT_MARGIN, BOTTOM_MARGIN)

    frame.grid = {}
    frame.yLabels = {}
    for i = 0, GRIDLINES do
        local line = frame.plot:CreateTexture(nil, "BORDER")
        line:SetColorTexture(0.35, 0.35, 0.4, 0.5)
        line:SetHeight(1)
        frame.grid[i] = line
        local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetTextColor(0.7, 0.7, 0.7)
        frame.yLabels[i] = text
    end

    frame.refLines = {}

    frame.emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.emptyText:SetPoint("CENTER")
    frame.emptyText:SetText("No price history yet")
    frame.emptyText:SetTextColor(0.6, 0.6, 0.6)
    frame.emptyText:Hide()

    frame.bars = {}
    frame.xLabels = {}

    return frame
end

_G.MalexisAuctionWatcherChart = MAWChart
