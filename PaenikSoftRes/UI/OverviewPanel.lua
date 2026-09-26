-- Übersicht-Tab: alle Reserves der Sitzung, gruppiert nach Item.
local _, ns = ...

local UI = ns.UI
local panel = UI.GetPanel(UI.TAB_OVERVIEW)

local ROW_HEIGHT = 36

local refreshList -- forward

local header = UI.CreateText(panel, nil, nil, "GameFontNormal")
header:SetWidth(560)

local emptyText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
emptyText:SetPoint("CENTER", panel, "CENTER", 0, -20)

local onItemLoaded = UI.Debounce(function() refreshList() end)

local function onRowEnter(row)
    if not row.itemID then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(row.itemID)
    GameTooltip:Show()
end

local function onRowLeave()
    GameTooltip:Hide()
end

local function initRow(row, data)
    if not row.icon then
        row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints()
        row.highlight:SetColorTexture(1, 1, 1, 0.08)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(ROW_HEIGHT - 6, ROW_HEIGHT - 6)
        row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, 0)
        row.name:SetPoint("RIGHT", row, "RIGHT", -60, 0)
        row.name:SetJustifyH("LEFT")
        row.count = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.count:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -3)
        row.players = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.players:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 0)
        row.players:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.players:SetJustifyH("LEFT")
        row.players:SetWordWrap(false)
        row:SetScript("OnEnter", onRowEnter)
        row:SetScript("OnLeave", onRowLeave)
    end
    row.itemID = data.itemID
    local name, icon = UI.GetItemDisplay(data.itemID, onItemLoaded)
    row.icon:SetTexture(icon)
    row.name:SetText(name)
    row.count:SetText(data.countText or (data.total .. " SR"))
    row.players:SetText(data.players)
end

local scrollBox = UI.CreateScrollList(panel, ROW_HEIGHT, initRow)
scrollBox:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -10)
scrollBox:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -20, 0)

-- Reihenfolge der Items wie in der Instanz (Boss für Boss)
local function itemOrder(s)
    local order, n = {}, 0
    if s.instanceKey then
        for _, encounter in ipairs(ns.LootData:GetDisplayEncounters(s.instanceKey)) do
            for _, itemID in ipairs(encounter.items) do
                if not order[itemID] then
                    n = n + 1
                    order[itemID] = n
                end
            end
        end
    end
    return order
end

local IMPORT_COLOR = "ff80c8ff" -- Reserves aus softres.it

local function buildElements(s)
    local byItem = {}
    local playerCount, reserveCount, importedCount = 0, 0, 0
    for player, list in pairs(s.reserves) do
        playerCount = playerCount + 1
        for _, entry in ipairs(list) do
            reserveCount = reserveCount + 1
            local item = byItem[entry.itemID]
            if not item then
                item = { itemID = entry.itemID, total = 0, names = {}, imported = {} }
                byItem[entry.itemID] = item
            end
            item.total = item.total + 1
            item.names[player] = (item.names[player] or 0) + 1
            if entry.source == "softres" then
                item.imported[player] = true
                importedCount = importedCount + 1
            end
        end
    end

    local elements = {}
    for _, item in pairs(byItem) do
        local names = {}
        for player, count in pairs(item.names) do
            local short = UI.ShortName(player)
            local text = count > 1 and (short .. " x" .. count) or short
            table.insert(names, { sort = short, text = item.imported[player] and ("|c" .. IMPORT_COLOR .. text .. "|r") or text })
        end
        table.sort(names, function(a, b) return a.sort < b.sort end)
        for i, entry in ipairs(names) do
            names[i] = entry.text
        end
        item.players = table.concat(names, ", ")
        table.insert(elements, item)
    end
    local order = itemOrder(s)
    table.sort(elements, function(a, b)
        local oa, ob = order[a.itemID] or math.huge, order[b.itemID] or math.huge
        if oa ~= ob then return oa < ob end
        return a.itemID < b.itemID
    end)
    return elements, playerCount, reserveCount, importedCount
end

-- Verlauf: vergebene Items, neueste zuerst
local showHistory = false

local function buildHistoryElements(s)
    local elements = {}
    for i = #(s.history or {}), 1, -1 do
        local entry = s.history[i]
        table.insert(elements, {
            itemID = entry.itemID,
            total = 0,
            countText = date("%H:%M", entry.time),
            players = string.format("|cffffd100%s|r – %s, %d", UI.ShortName(entry.winner or "?"),
                ns.Rolls.LABEL[entry.category] or entry.category or "?", entry.roll or 0),
        })
    end
    return elements
end

local modeButton = UI.CreateButton(panel, "Verlauf", 110, function(self)
    showHistory = not showHistory
    self:SetText(showHistory and "Reserves" or "Verlauf")
    refreshList()
end)
modeButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 4)

function refreshList()
    local s = ns.Session:GetViewed()
    if not s then
        header:SetText("Keine Sitzung")
        scrollBox:Hide()
        emptyText:SetText("Noch keine Soft-Reserve-Sitzung.")
        emptyText:Show()
        return
    end
    if showHistory then
        local elements = buildHistoryElements(s)
        header:SetText(string.format("%s – Verlauf, %d Items vergeben", UI.SessionTitle(s), #elements))
        scrollBox:SetShown(#elements > 0)
        emptyText:SetShown(#elements == 0)
        emptyText:SetText("Noch keine Items vergeben.")
        scrollBox:SetDataProvider(CreateDataProvider(elements), ScrollBoxConstants.RetainScrollPosition)
        return
    end
    local elements, playerCount, reserveCount, importedCount = buildElements(s)
    local importText = importedCount > 0
        and string.format(" (|c%s%d aus softres.it|r)", IMPORT_COLOR, importedCount) or ""
    header:SetText(string.format("%s – %d Spieler, %d Reserves%s%s",
        UI.SessionTitle(s), playerCount, reserveCount, importText,
        (ns.Session:IsLocked(s) or s.deadline) and (" – " .. UI.LockStateText(s)) or ""))
    scrollBox:SetShown(#elements > 0)
    emptyText:SetShown(#elements == 0)
    emptyText:SetText("Noch keine Reserves.")
    scrollBox:SetDataProvider(CreateDataProvider(elements), ScrollBoxConstants.RetainScrollPosition)
end
panel:HookScript("OnShow", refreshList)
local refreshIfShown = UI.Debounce(function()
    if panel:IsVisible() then
        refreshList()
    end
end)
ns:On("SESSION_CHANGED", refreshIfShown)
ns:On("LOOT_ITEMS_CHANGED", refreshIfShown)
