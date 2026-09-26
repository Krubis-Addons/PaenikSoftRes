-- Raider-Tab: Boss-Liste mit Porträts (links), eigene Reserves und Loot des Bosses (rechts).
local _, ns = ...

local UI = ns.UI
local panel = UI.GetPanel(UI.TAB_RAIDER)

local ROW_HEIGHT = 26
local SIDEBAR_WIDTH = 190
local ALL_BOSSES = UI.ALL_BOSSES
local WISHLIST = UI.WISHLIST -- Eintrag „Wunschliste“ in der Bossliste
local OWNED_TEXT = UI.OWNED_TEXT

local selectedBoss = ALL_BOSSES
local lastInstanceKey
local refreshList -- forward

local onItemLoaded = UI.Debounce(function() refreshList() end)

-- Kopfzeile ---------------------------------------------------------------

-- Sitzungswahl: Gruppensitzung, eigene Sitzungen und über die Gilde veröffentlichte Sitzungen
local KIND_PREFIX = { group = "Gruppe: ", own = "", guild = "" }

local viewDropdown = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
viewDropdown:SetWidth(SIDEBAR_WIDTH + 60)
viewDropdown:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 2)
viewDropdown:SetDefaultText("Keine Sitzung")

local function isViewSelected(id)
    local s = ns.Session:GetViewed()
    return s ~= nil and s.id == id
end

local function selectView(id)
    ns.Session:SetViewed(id)
end

viewDropdown:SetupMenu(function(_, root)
    for _, entry in ipairs(ns.Session:ListViewable()) do
        local s = entry.session
        local text = KIND_PREFIX[entry.kind] .. (s.name or s.instanceName or "?")
        if entry.kind == "guild" then
            text = text .. " |cff999999(" .. UI.ShortName(s.leader or "?") .. ")|r"
        end
        root:CreateRadio(text, isViewSelected, selectView, s.id)
    end
end)

-- Anzeigetext neu erzeugen, wenn Sitzungen dazukommen (einen Frame verzögert, s. LeadPanel)
local regenerateViewMenu = UI.Debounce(function()
    if not viewDropdown:IsMenuOpen() then
        viewDropdown:GenerateMenu()
    end
end, 0)

local statusText = UI.CreateText(panel, nil, nil, "GameFontNormal")
statusText:ClearAllPoints()
statusText:SetPoint("LEFT", viewDropdown, "RIGHT", 12, 0)
statusText:SetWidth(330)

local refreshButton = UI.CreateButton(panel, "Aktualisieren", 110, function()
    ns.Comm:RequestState()
end)
refreshButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 4)

local emptyText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
emptyText:SetPoint("CENTER", panel, "CENTER", 0, -20)

-- Eigene Reserves ändern und einreichen ------------------------------------

local function submit(s, list)
    local ok, err = ns.Signup:Submit(s, list)
    if not ok then
        ns.Print(err)
    end
    refreshList()
end

local function canEdit()
    local s = ns.Session:GetViewed()
    if not s then return false end
    if ns.Session:IsLocked(s) then
        ns.Print(s.locked and "Die Sitzung ist gesperrt." or "Der Anmeldeschluss ist erreicht.")
        return false
    end
    return true
end

local function toggleItem(itemID, addAnother)
    if not canEdit() then return end
    local s = ns.Session:GetViewed()
    -- enthält eine noch unbestätigte Auswahl, damit schnelle Klicks nichts verlieren
    local list = ns.Signup:GetOwn(s)
    local position
    for i, id in ipairs(list) do
        if id == itemID then
            position = i
        end
    end

    if position and not addAnother then
        table.remove(list, position)
        submit(s, list)
        return
    elseif #list < s.maxReserves then
        table.insert(list, itemID)
    elseif s.maxReserves == 1 then
        list = { itemID } -- bei nur einem SR direkt tauschen
    else
        ns.Print("Limit erreicht (" .. s.maxReserves .. "). Erst ein Item entfernen.")
        return
    end
    -- Hinzufügen: bei einem Item im Besitz erst nachfragen
    local places = not position and ns.Owned:PlacesText(itemID)
    local name = UI.GetItemDisplay(itemID)
    UI.Confirm(string.format("Du besitzt %s bereits (%s).\nTrotzdem reservieren?", name, places or ""),
        function() submit(s, list) end, places and true or false)
end

local function removeAt(index)
    if not canEdit() then return end
    local s = ns.Session:GetViewed()
    local list = ns.Signup:GetOwn(s)
    if list[index] then
        table.remove(list, index)
        submit(s, list)
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
    local places = ns.Owned:PlacesText(itemID)
    if hint or places then
        GameTooltip:AddLine(" ")
    end
    if places then
        GameTooltip:AddLine("Bereits im Besitz: " .. places, 0.4, 0.8, 1)
    end
    for _, line in ipairs(hint or {}) do
        GameTooltip:AddLine(line, 0.6, 0.8, 1)
    end
    GameTooltip:Show()
end

local function hideTooltip()
    GameTooltip:Hide()
end

-- Linke Seite: Bosse mit Porträt -------------------------------------------

-- Raidlead: Rechtsklick auf einen Boss der eigenen Sitzung markiert ihn als gelegt (ID fortführen)
local function showBossMenu(row)
    local s = ns.Session:GetViewed()
    if not s or s.leader ~= ns.FullName("player") or not row.bossIndex or row.bossIndex < 1 then return end
    local index = row.bossIndex
    MenuUtil.CreateContextMenu(row, function(_, root)
        root:CreateTitle(row.name:GetText() or "")
        if ns.Session:IsBossKilled(s, index) then
            root:CreateButton("Markierung „gelegt“ aufheben", function()
                ns.Session:SetBossKilled(s, index, false)
            end)
        else
            root:CreateButton("Als gelegt markieren", function()
                ns.Session:SetBossKilled(s, index, true)
            end)
        end
    end)
end

local function onBossClick(row, mouseButton)
    if mouseButton == "RightButton" then
        showBossMenu(row)
        return
    end
    selectedBoss = row.bossIndex
    refreshList()
end

local function initBossRow(row, data)
    local info = {}
    if data.killed then
        table.insert(info, "|cff808080gelegt|r")
    end
    if data.mine > 0 then
        table.insert(info, "|cff40ff40" .. data.mine .. " reserviert|r")
    end
    table.insert(info, UI.WishCountText(data.wished))
    data.info = table.concat(info, "  ")
    UI.InitBossRow(row, data, data.index == selectedBoss, onBossClick)
end

local bossList = UI.CreateScrollList(panel, UI.BOSS_ROW_HEIGHT, initBossRow)
bossList:SetPoint("TOPLEFT", viewDropdown, "BOTTOMLEFT", 0, -10)
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

local function refreshMyReserves(s, kind)
    local list = ns.Signup:GetOwn(s)
    local text = string.format("Meine Reserves (%d/%d)", #list, s.maxReserves)
    local status, reason = ns.Signup:GetStatus(s)
    if status == "pending" and kind == "guild" then
        local online = ns.GuildSync:IsOnline(s.leader)
        text = text .. "  |cffffd100ausstehend|r |cff999999(Raidlead "
            .. (online and "online – wird gesendet" or "offline – wird über die Gilde weitergegeben") .. ")|r"
    elseif status == "pending" then
        text = text .. "  |cffffd100warte auf Raidlead …|r"
    elseif status == "rejected" then
        text = text .. "  |cffff6060abgelehnt: " .. (reason or "?") .. "|r"
    elseif kind == "guild" and #list > 0 then
        text = text .. "  |cff60ff60bestätigt|r"
    elseif ns.Session:IsLocked(s) or s.deadline then
        text = text .. "  " .. UI.LockStateText(s)
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
            local boss = "|cff999999" .. (bossNameForItem(s, itemID) or "") .. "|r"
            row.boss:SetText(ns.Owned:Has(itemID) and (OWNED_TEXT .. "  " .. boss) or boss)
            row.remove:Show()
            row.remove:SetEnabled(not ns.Session:IsLocked(s))
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

-- Rechtsklick auf ein Item: Wunschliste (alle); Raidlead der eigenen Sitzung zusätzlich Hard Reserve
local function showItemMenu(row)
    local s = ns.Session:GetViewed()
    if not s then return end
    local itemID = row.itemID
    local isOwner = s.leader == ns.FullName("player")
    local hr = ns.Session:GetHardReserve(itemID, s)
    MenuUtil.CreateContextMenu(row, function(_, root)
        root:CreateTitle(UI.StripColors(select(1, UI.GetItemDisplay(itemID)) or ""))
        root:CreateButton(ns.Wishlist:Has(itemID) and "Von der Wunschliste entfernen" or "Auf die Wunschliste",
            function() ns.Wishlist:Toggle(itemID) end)
        if not isOwner then return end
        root:CreateDivider()
        root:CreateButton(hr and "Hard Reserve ändern…" or "Hard Reserve setzen…", function()
            UI.Prompt("Hard Reserve für wen?\n|cff999999Name oder Notiz, z. B. „Gildenbank“|r", hr and hr.note or "",
                function(note)
                    local count = ns.Session:CountReservesOnItem(itemID, s)
                    UI.Confirm(string.format("%d Soft Reserve(s) auf diesem Item werden entfernt.", count), function()
                        ns.Session:SetHardReserve(s, itemID, note)
                    end, count > 0)
                end)
        end)
        if hr then
            root:CreateButton("Hard Reserve entfernen", function()
                ns.Session:RemoveHardReserve(s, itemID)
            end)
        end
    end)
end

local function onItemClick(row, mouseButton)
    if not row.itemID then return end
    if mouseButton == "RightButton" then
        showItemMenu(row)
        return
    end
    if IsAltKeyDown() then
        ns.Wishlist:Toggle(row.itemID)
        return
    end
    if row.hardReserve then
        ns.Print("Dieses Item ist Hard Reserve: " .. (row.hardReserve.note ~= "" and row.hardReserve.note or "fest vergeben"))
        return
    end
    if row.killed and not row.mine then
        ns.Print("Der Boss für dieses Item ist bereits gelegt.")
        return
    end
    toggleItem(row.itemID, IsShiftKeyDown())
end

local function onItemEnter(row)
    if not row.itemID then return end
    local hint
    if row.hardReserve then
        hint = { "Hard Reserve – nicht reservierbar" }
    elseif row.killed then
        hint = { "Boss bereits gelegt – nicht mehr reservierbar" }
    else
        hint = { "Klick: reservieren / entfernen" }
        local s = ns.Session:GetViewed()
        if s and s.allowDuplicates and s.maxReserves > 1 then
            table.insert(hint, "Shift-Klick: ein weiteres Mal reservieren")
        end
    end
    table.insert(hint, ns.Wishlist:Has(row.itemID) and "Alt-Klick: von der Wunschliste entfernen"
        or "Alt-Klick: auf die Wunschliste")
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
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", onItemClick)
        row:SetScript("OnEnter", onItemEnter)
        row:SetScript("OnLeave", hideTooltip)
    end
    row.itemID = data.itemID
    row.killed = data.killed
    row.hardReserve = data.hardReserve
    row.mine = data.mine > 0
    local name, icon = UI.GetItemDisplay(data.itemID, onItemLoaded)
    row.icon:SetTexture(icon)
    row.icon:SetDesaturated(data.killed == true)
    name = data.killed and ("|cff808080" .. UI.StripColors(name) .. "|r") or name
    row.name:SetText(data.wished and (ns.Wishlist.Icon() .. " " .. name) or name)

    local info = {}
    if data.hardReserve then
        local note = data.hardReserve.note ~= "" and data.hardReserve.note or "fest vergeben"
        table.insert(info, "|cffff5050Hard Reserve: " .. note .. "|r")
    end
    if data.killed then
        table.insert(info, "|cff808080Boss gelegt|r")
    end
    if data.owned then
        table.insert(info, OWNED_TEXT)
    end
    if data.mine > 0 then
        table.insert(info, data.mine > 1 and ("|cff40ff40Reserviert x" .. data.mine .. "|r") or "|cff40ff40Reserviert|r")
    end
    if data.others > 0 then
        table.insert(info, data.others .. " SR")
    end
    if (selectedBoss == ALL_BOSSES or selectedBoss == WISHLIST) and data.boss then
        table.insert(info, "|cff999999" .. data.boss .. "|r")
    end
    row.info:SetText(table.concat(info, "  "))
    if data.hardReserve then
        row.bg:SetColorTexture(0.6, 0.1, 0.1, 0.25)
    elseif data.mine > 0 then
        row.bg:SetColorTexture(0.1, 0.6, 0.1, 0.25)
    elseif data.wished then
        row.bg:SetColorTexture(1, 0.82, 0, 0.1)
    else
        row.bg:SetColorTexture(0, 0, 0, 0)
    end
end

local itemList = UI.CreateScrollList(content, ROW_HEIGHT, initItemRow)
itemList:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -20, 0)

-- Daten aufbauen -------------------------------------------------------------

local function countOwn()
    local mine = {}
    for _, itemID in ipairs(ns.Signup:GetOwn(ns.Session:GetViewed())) do
        mine[itemID] = (mine[itemID] or 0) + 1
    end
    return mine
end

local function buildBossElements(s, mineCount)
    local total = 0
    for _, count in pairs(mineCount) do
        total = total + count
    end
    local encounters = ns.LootData:GetDisplayEncounters(s.instanceKey)
    local allItems = {}
    for _, encounter in ipairs(encounters) do
        for _, itemID in ipairs(encounter.items) do
            table.insert(allItems, itemID)
        end
    end
    local elements = {
        { index = WISHLIST, name = "Wunschliste", mine = 0, wished = ns.Wishlist:CountIn(allItems) },
        { index = ALL_BOSSES, name = "Alle Bosse", mine = total },
    }
    for index, encounter in ipairs(encounters) do
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
            wished = ns.Wishlist:CountIn(encounter.items),
            killed = ns.Session:IsBossKilled(s, index),
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

    local killedOnly = ns.Session:GetKilledOnlyItems(s)
    local elements, index = {}, {}
    for bossIndex, encounter in ipairs(ns.LootData:GetDisplayEncounters(s.instanceKey)) do
        if selectedBoss == ALL_BOSSES or selectedBoss == WISHLIST or selectedBoss == bossIndex then
            for _, itemID in ipairs(encounter.items) do
                local existing = index[itemID]
                if existing then
                    existing.boss = "mehrere Bosse"
                elseif selectedBoss ~= WISHLIST or ns.Wishlist:Has(itemID) then
                    local element = {
                        itemID = itemID,
                        boss = encounter.name,
                        mine = mineCount[itemID] or 0,
                        others = otherCount[itemID] or 0,
                        killed = killedOnly[itemID] == true,
                        hardReserve = ns.Session:GetHardReserve(itemID, s),
                        owned = ns.Owned:Has(itemID),
                        wished = ns.Wishlist:Has(itemID),
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
    local s, kind = ns.Session:GetViewed()
    regenerateViewMenu()
    local hasList = s ~= nil and s.instanceKey ~= nil
    bossList:SetShown(hasList)
    content:SetShown(hasList)
    refreshButton:SetShown(kind == "group" or (IsInGroup and IsInGroup() and not s and not ns.Session:IsMaster()))

    if not s then
        statusText:SetText("Keine Sitzung")
        emptyText:SetText("Noch keine Soft-Reserve-Sitzung.\nDer Raidlead muss eine Sitzung anlegen oder für die Gilde"
            .. " veröffentlichen.")
        emptyText:Show()
        return
    end
    local leader = UI.ShortName(s.leader or "?")
    if kind == "guild" then
        leader = leader .. (ns.GuildSync:IsOnline(s.leader) and " |cff60ff60(online)|r" or " |cff999999(offline)|r")
    end
    statusText:SetText(string.format("Raidlead %s – %s", leader, UI.LockStateText(s)))
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
    local shownRows = refreshMyReserves(s, kind)
    lootHeader:ClearAllPoints()
    lootHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -18 - shownRows * ROW_HEIGHT - 12)
    if selectedBoss == WISHLIST then
        lootHeader:SetText("Deine Wunschliste |cff999999(Alt-Klick oder Rechtsklick auf ein Item zum Hinzufügen)|r")
    elseif selectedBoss == ALL_BOSSES then
        lootHeader:SetText("Loot aller Bosse")
    else
        lootHeader:SetText("Loot von " .. encounters[selectedBoss].name)
    end
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
ns:On("OWNED_CHANGED", refreshIfShown)
ns:On("WISHLIST_CHANGED", refreshIfShown)
ns:On("ROLE_CHANGED", refreshIfShown)
