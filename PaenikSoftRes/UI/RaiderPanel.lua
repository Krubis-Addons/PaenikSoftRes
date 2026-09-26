-- Raider-Tab: Boss-Liste mit Porträts (links), eigene Reserves und Loot des Bosses (rechts).
local _, ns = ...

local UI = ns.UI
local panel = UI.GetPanel(UI.TAB_RAIDER)

local ROW_HEIGHT = 26
local BOSS_ROW_HEIGHT = 40
local SIDEBAR_WIDTH = 190
local ALL_BOSSES = 0
local ALL_BOSSES_ICON = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local PORTRAIT_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local selectedBoss = ALL_BOSSES
local lastInstanceKey
local refreshList -- forward

local onItemLoaded = UI.Debounce(function() refreshList() end)

-- Kopfzeile ---------------------------------------------------------------

local statusText = UI.CreateText(panel, nil, nil, "GameFontNormal")
statusText:SetWidth(540)

local refreshButton = UI.CreateButton(panel, "Aktualisieren", 110, function()
    ns.Comm:RequestState()
end)
refreshButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 4)

local emptyText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
emptyText:SetPoint("CENTER", panel, "CENTER", 0, -20)

-- Eigene Reserves ändern und einreichen ------------------------------------

local function submit(list)
    local ok, err = ns.Comm:SubmitOwnReserves(list)
    if not ok then
        ns.Print(err)
    end
    refreshList()
end

local function canEdit()
    local s = ns.Session:Get()
    if not s then return false end
    if s.locked then
        ns.Print("Die Sitzung ist gesperrt.")
        return false
    end
    return true
end

local function toggleItem(itemID, addAnother)
    if not canEdit() then return end
    local s = ns.Session:Get()
    -- enthält eine noch unbestätigte Auswahl, damit schnelle Klicks nichts verlieren
    local list = ns.Comm:GetOwnReserves()
    local position
    for i, id in ipairs(list) do
        if id == itemID then
            position = i
        end
    end

    if position and not addAnother then
        table.remove(list, position)
    elseif #list < s.maxReserves then
        table.insert(list, itemID)
    elseif s.maxReserves == 1 then
        list = { itemID } -- bei nur einem SR direkt tauschen
    else
        ns.Print("Limit erreicht (" .. s.maxReserves .. "). Erst ein Item entfernen.")
        return
    end
    submit(list)
end

local function removeAt(index)
    if not canEdit() then return end
    local list = ns.Comm:GetOwnReserves()
    if list[index] then
        table.remove(list, index)
        submit(list)
    end
end

-- Boss zu einem Item (für die Anzeige in „Meine Reserves“)
local function bossNameForItem(s, itemID)
    for _, encounter in ipairs(ns.LootData:GetDisplayEncounters(s.instanceKey)) do
        for _, id in ipairs(encounter.items) do
            if id == itemID then
                return encounter.name
            end
        end
    end
end

-- Tooltip für Item-Zeilen --------------------------------------------------

local function showItemTooltip(owner, itemID, hint)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(itemID)
    if hint then
        GameTooltip:AddLine(" ")
        for _, line in ipairs(hint) do
            GameTooltip:AddLine(line, 0.6, 0.8, 1)
        end
    end
    GameTooltip:Show()
end

local function hideTooltip()
    GameTooltip:Hide()
end

-- Linke Seite: Bosse mit Porträt -------------------------------------------

local function onBossClick(row)
    selectedBoss = row.bossIndex
    refreshList()
end

local function initBossRow(row, data)
    if not row.portrait then
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints()
        row.highlight:SetColorTexture(1, 1, 1, 0.08)
        row.portrait = row:CreateTexture(nil, "ARTWORK")
        row.portrait:SetSize(BOSS_ROW_HEIGHT - 6, BOSS_ROW_HEIGHT - 6)
        row.portrait:SetPoint("LEFT", row, "LEFT", 3, 0)
        row.mask = row:CreateMaskTexture()
        row.mask:SetAllPoints(row.portrait)
        row.mask:SetTexture(PORTRAIT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        row.portrait:AddMaskTexture(row.mask)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.name:SetPoint("TOPLEFT", row.portrait, "TOPRIGHT", 6, -3)
        row.name:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.info = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.info:SetPoint("BOTTOMLEFT", row.portrait, "BOTTOMRIGHT", 6, 3)
        row.info:SetJustifyH("LEFT")
        row:SetScript("OnClick", onBossClick)
    end
    row.bossIndex = data.index
    if data.displayID then
        SetPortraitTextureFromCreatureDisplayID(row.portrait, data.displayID)
    else
        row.portrait:SetTexture(ALL_BOSSES_ICON)
    end
    row.name:SetText(data.name)
    row.info:SetText(data.mine > 0 and ("|cff40ff40" .. data.mine .. " reserviert|r") or "")
    if data.index == selectedBoss then
        row.bg:SetColorTexture(1, 0.82, 0, 0.18)
        row.name:SetFontObject("GameFontHighlight")
    else
        row.bg:SetColorTexture(0, 0, 0, 0)
        row.name:SetFontObject("GameFontNormal")
    end
end

local bossList = UI.CreateScrollList(panel, BOSS_ROW_HEIGHT, initBossRow)
bossList:SetPoint("TOPLEFT", statusText, "BOTTOMLEFT", 0, -12)
bossList:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)
bossList:SetWidth(SIDEBAR_WIDTH)

-- Rechte Seite: Meine Reserves ---------------------------------------------

local content = CreateFrame("Frame", nil, panel)
content:SetPoint("TOPLEFT", bossList, "TOPRIGHT", 22, 0)
content:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)

local myHeader = UI.CreateText(content, nil, nil, "GameFontNormal")

local myRows = {}

local function createMyRow(index)
    local row = CreateFrame("Button", nil, content)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -18 - (index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", content, "RIGHT", -20, 0)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.remove = CreateFrame("Button", nil, row, "UIPanelCloseButtonNoScripts")
    row.remove:SetSize(ROW_HEIGHT, ROW_HEIGHT)
    row.remove:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.remove:SetScript("OnClick", function() removeAt(index) end)
    row.remove:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Reserve entfernen")
        GameTooltip:Show()
    end)
    row.remove:SetScript("OnLeave", hideTooltip)
    row.boss = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.boss:SetPoint("RIGHT", row.remove, "LEFT", -4, 0)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.boss, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row:SetScript("OnEnter", function(self)
        if self.itemID then
            showItemTooltip(self, self.itemID)
        end
    end)
    row:SetScript("OnLeave", hideTooltip)
    return row
end

for i = 1, ns.Session.MAX_RESERVES_LIMIT do
    myRows[i] = createMyRow(i)
end

local function refreshMyReserves(s)
    local list = ns.Comm:GetOwnReserves()
    local text = string.format("Meine Reserves (%d/%d)", #list, s.maxReserves)
    if ns.Comm:IsRequestPending() then
        text = text .. "  |cffffd100warte auf Raidlead …|r"
    elseif s.locked then
        text = text .. "  |cffff6060gesperrt|r"
    end
    myHeader:SetText(text)

    -- Höchstens so viele Zeilen wie vorhanden (ein Import kann mehr Reserves bringen als das Limit)
    local shown = math.min(#myRows, math.max(s.maxReserves, #list))
    if #list > #myRows then
        myHeader:SetText(myHeader:GetText() .. string.format("  |cff999999(+%d weitere, siehe Übersicht)|r",
            #list - #myRows))
    end
    for i, row in ipairs(myRows) do
        local itemID = list[i]
        row:SetShown(i <= shown)
        row.itemID = itemID
        if itemID then
            local name, icon = UI.GetItemDisplay(itemID, onItemLoaded)
            row.icon:SetTexture(icon)
            row.icon:Show()
            row.name:SetText(name)
            row.boss:SetText("|cff999999" .. (bossNameForItem(s, itemID) or "") .. "|r")
            row.remove:Show()
            row.remove:SetEnabled(not s.locked)
            row.bg:SetColorTexture(0.1, 0.6, 0.1, 0.2)
        else
            row.icon:Hide()
            row.name:SetText("|cff808080– frei –|r")
            row.boss:SetText("")
            row.remove:Hide()
            row.bg:SetColorTexture(1, 1, 1, 0.03)
        end
    end
    return shown
end

-- Rechte Seite: Loot-Liste --------------------------------------------------

local lootHeader = UI.CreateText(content, nil, nil, "GameFontNormal")

local function onItemClick(row)
    if row.itemID then
        toggleItem(row.itemID, IsShiftKeyDown())
    end
end

local function onItemEnter(row)
    if not row.itemID then return end
    local hint = { "Klick: reservieren / entfernen" }
    local s = ns.Session:Get()
    if s and s.allowDuplicates and s.maxReserves > 1 then
        table.insert(hint, "Shift-Klick: ein weiteres Mal reservieren")
    end
    showItemTooltip(row, row.itemID, hint)
end

local function initItemRow(row, data)
    if not row.icon then
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints()
        row.highlight:SetColorTexture(1, 1, 1, 0.08)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
        row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.info = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.info:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.info:SetJustifyH("RIGHT")
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.name:SetPoint("RIGHT", row.info, "LEFT", -6, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row:SetScript("OnClick", onItemClick)
        row:SetScript("OnEnter", onItemEnter)
        row:SetScript("OnLeave", hideTooltip)
    end
    row.itemID = data.itemID
    local name, icon = UI.GetItemDisplay(data.itemID, onItemLoaded)
    row.icon:SetTexture(icon)
    row.name:SetText(name)

    local info = {}
    if data.mine > 0 then
        table.insert(info, data.mine > 1 and ("|cff40ff40Reserviert x" .. data.mine .. "|r") or "|cff40ff40Reserviert|r")
    end
    if data.others > 0 then
        table.insert(info, data.others .. " SR")
    end
    if selectedBoss == ALL_BOSSES and data.boss then
        table.insert(info, "|cff999999" .. data.boss .. "|r")
    end
    row.info:SetText(table.concat(info, "  "))
    if data.mine > 0 then
        row.bg:SetColorTexture(0.1, 0.6, 0.1, 0.25)
    else
        row.bg:SetColorTexture(0, 0, 0, 0)
    end
end

local itemList = UI.CreateScrollList(content, ROW_HEIGHT, initItemRow)
itemList:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -20, 0)

-- Daten aufbauen -------------------------------------------------------------

local function countOwn()
    local mine = {}
    for _, itemID in ipairs(ns.Comm:GetOwnReserves()) do
        mine[itemID] = (mine[itemID] or 0) + 1
    end
    return mine
end

local function buildBossElements(s, mineCount)
    local total = 0
    for _, count in pairs(mineCount) do
        total = total + count
    end
    local elements = { { index = ALL_BOSSES, name = "Alle Bosse", mine = total } }
    for index, encounter in ipairs(ns.LootData:GetDisplayEncounters(s.instanceKey)) do
        local mine = 0
        local counted = {}
        for _, itemID in ipairs(encounter.items) do
            if mineCount[itemID] and not counted[itemID] then
                counted[itemID] = true
                mine = mine + mineCount[itemID]
            end
        end
        table.insert(elements, {
            index = index,
            name = encounter.name,
            displayID = encounter.displayID,
            mine = mine,
        })
    end
    return elements
end

local function buildItemElements(s, mineCount)
    local me = ns.FullName("player")
    local otherCount = {}
    for player, list in pairs(s.reserves) do
        if player ~= me then
            for _, entry in ipairs(list) do
                otherCount[entry.itemID] = (otherCount[entry.itemID] or 0) + 1
            end
        end
    end

    local elements, index = {}, {}
    for bossIndex, encounter in ipairs(ns.LootData:GetDisplayEncounters(s.instanceKey)) do
        if selectedBoss == ALL_BOSSES or selectedBoss == bossIndex then
            for _, itemID in ipairs(encounter.items) do
                local existing = index[itemID]
                if existing then
                    existing.boss = "mehrere Bosse"
                else
                    local element = {
                        itemID = itemID,
                        boss = encounter.name,
                        mine = mineCount[itemID] or 0,
                        others = otherCount[itemID] or 0,
                    }
                    index[itemID] = element
                    table.insert(elements, element)
                end
            end
        end
    end
    return elements
end

function refreshList()
    local s = ns.Session:Get()
    local hasList = s ~= nil and s.instanceKey ~= nil
    bossList:SetShown(hasList)
    content:SetShown(hasList)
    refreshButton:SetShown(IsInGroup and IsInGroup() and not ns.Session:IsMaster())

    if not s then
        statusText:SetText("Keine Sitzung")
        emptyText:SetText("Noch keine Soft-Reserve-Sitzung.\nDer Raidlead muss eine Sitzung anlegen.")
        emptyText:Show()
        return
    end
    local state = s.locked and "|cffff6060gesperrt|r" or "|cff60ff60offen|r"
    statusText:SetText(string.format("%s – Raidlead %s – %s",
        s.instanceName or "keine Instanz", UI.ShortName(s.leader or "?"), state))
    if not hasList then
        emptyText:SetText("Der Raidlead hat noch keine Instanz gewählt.")
        emptyText:Show()
        return
    end
    emptyText:Hide()

    if s.instanceKey ~= lastInstanceKey then
        lastInstanceKey = s.instanceKey
        selectedBoss = ALL_BOSSES
    end
    local encounters = ns.LootData:GetDisplayEncounters(s.instanceKey)
    if selectedBoss > #encounters then
        selectedBoss = ALL_BOSSES
    end

    -- „Meine Reserves“ bestimmt, wo die Loot-Liste beginnt
    local shownRows = refreshMyReserves(s)
    lootHeader:ClearAllPoints()
    lootHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -18 - shownRows * ROW_HEIGHT - 12)
    lootHeader:SetText(selectedBoss == ALL_BOSSES and "Loot aller Bosse"
        or ("Loot von " .. encounters[selectedBoss].name))
    itemList:ClearAllPoints()
    itemList:SetPoint("TOPLEFT", lootHeader, "BOTTOMLEFT", 0, -6)
    itemList:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -20, 0)

    local mineCount = countOwn()
    bossList:SetDataProvider(CreateDataProvider(buildBossElements(s, mineCount)),
        ScrollBoxConstants.RetainScrollPosition)
    itemList:SetDataProvider(CreateDataProvider(buildItemElements(s, mineCount)),
        ScrollBoxConstants.RetainScrollPosition)
end

panel:HookScript("OnShow", function()
    if not ns.Session:Get() then
        ns.Comm:RequestState()
    end
    refreshList()
end)

-- entprellt: ein voller Stand vom Raidlead löst viele SESSION_CHANGED aus
local refreshIfShown = UI.Debounce(function()
    if panel:IsVisible() then
        refreshList()
    end
end)
ns:On("SESSION_CHANGED", refreshIfShown)
ns:On("LOOT_ITEMS_CHANGED", refreshIfShown)
ns:On("ROLE_CHANGED", refreshIfShown)
