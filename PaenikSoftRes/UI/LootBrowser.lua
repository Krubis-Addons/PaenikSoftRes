-- Loot-Browser: Loot aller Dungeons und Raids ansehen, unabhängig von einer Soft-Reserve-Sitzung.
-- Links Instanzwahl und Bossliste (wie im Raider-Tab), rechts die Items; Klick setzt ein Item auf die
-- Wunschliste. Gewählte Instanz in db.browserInstance (Account).
local _, ns = ...

local UI = ns.UI
local panel = UI.GetPanel(UI.TAB_LOOT)

local ROW_HEIGHT = 26
local SIDEBAR_WIDTH = 190
local ALL_BOSSES = UI.ALL_BOSSES
local WISHLIST = UI.WISHLIST

local selectedBoss = ALL_BOSSES
local refresh -- forward

local onItemLoaded = UI.Debounce(function() refresh() end)

-- Instanz: gespeicherte Wahl, sonst die der angezeigten Sitzung, sonst die erste
local function currentInstance()
    local instances = ns.LootData:GetInstances()
    local wanted = ns.db and ns.db.browserInstance
    if not wanted then
        local s = ns.Session:GetViewed()
        wanted = s and s.instanceKey
    end
    for _, instance in ipairs(instances) do
        if instance.fullKey == wanted then
            return instance
        end
    end
    return instances[1]
end

-- Kopfzeile ---------------------------------------------------------------

local instanceDropdown = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
instanceDropdown:SetWidth(SIDEBAR_WIDTH + 60)
instanceDropdown:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 2)
instanceDropdown:SetDefaultText("Keine Loot-Daten")

local function isInstanceSelected(fullKey)
    local instance = currentInstance()
    return instance ~= nil and instance.fullKey == fullKey
end

local function selectInstance(fullKey)
    ns.db.browserInstance = fullKey
    selectedBoss = ALL_BOSSES
    refresh()
end

instanceDropdown:SetupMenu(function(_, root)
    local lastIsRaid
    for _, instance in ipairs(ns.LootData:GetInstances()) do
        if instance.isRaid ~= lastIsRaid then
            root:CreateTitle(instance.isRaid and "Raids" or "Dungeons")
            lastIsRaid = instance.isRaid
        end
        root:CreateRadio(instance.name, isInstanceSelected, selectInstance, instance.fullKey)
    end
end)

local infoText = UI.CreateText(panel, nil, nil, "GameFontNormal")
infoText:ClearAllPoints()
infoText:SetPoint("LEFT", instanceDropdown, "RIGHT", 14, 0)

local emptyText = UI.CreateText(panel, nil, nil, "GameFontHighlight")
emptyText:ClearAllPoints()
emptyText:SetPoint("TOPLEFT", instanceDropdown, "BOTTOMLEFT", 0, -20)
emptyText:SetText("Keine Loot-Daten vorhanden.")
emptyText:Hide()

-- Linke Seite: Bosse --------------------------------------------------------

local function onBossClick(row)
    selectedBoss = row.bossIndex
    refresh()
end

local function initBossRow(row, data)
    data.info = UI.WishCountText(data.wished)
    UI.InitBossRow(row, data, data.index == selectedBoss, onBossClick)
end

local bossList = UI.CreateScrollList(panel, UI.BOSS_ROW_HEIGHT, initBossRow)
bossList:SetPoint("TOPLEFT", instanceDropdown, "BOTTOMLEFT", 0, -10)
bossList:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)
bossList:SetWidth(SIDEBAR_WIDTH)

-- Rechte Seite: Items -------------------------------------------------------

local content = CreateFrame("Frame", nil, panel)
content:SetPoint("TOPLEFT", bossList, "TOPRIGHT", 22, 0)
content:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)

local lootHeader = UI.CreateText(content, nil, nil, "GameFontNormal")

local function itemLink(itemID)
    local _, link = C_Item.GetItemInfo(itemID)
    return link
end

local function onItemClick(row, mouseButton)
    if not row.itemID then return end
    -- Shift: im Chat verlinken, Strg: anprobieren (Blizzard-Standard)
    if mouseButton == "LeftButton" and (IsModifiedClick("CHATLINK") or IsModifiedClick("DRESSUP")) then
        local link = itemLink(row.itemID)
        if link then
            HandleModifiedItemClick(link)
        end
        return
    end
    ns.Wishlist:Toggle(row.itemID)
end

local function onItemEnter(row)
    if not row.itemID then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(row.itemID)
    local places = ns.Owned:PlacesText(row.itemID)
    GameTooltip:AddLine(" ")
    if places then
        GameTooltip:AddLine("Bereits im Besitz: " .. places, 0.4, 0.8, 1)
    end
    GameTooltip:AddLine(ns.Wishlist:Has(row.itemID) and "Klick: von der Wunschliste entfernen"
        or "Klick: auf die Wunschliste", 0.6, 0.8, 1)
    GameTooltip:AddLine("Shift-Klick: im Chat verlinken, Strg-Klick: anprobieren", 0.6, 0.8, 1)
    GameTooltip:Show()
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
        row:RegisterForClicks("LeftButtonUp")
        row:SetScript("OnClick", onItemClick)
        row:SetScript("OnEnter", onItemEnter)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    row.itemID = data.itemID
    local wished = ns.Wishlist:Has(data.itemID)
    local name, icon = UI.GetItemDisplay(data.itemID, onItemLoaded)
    row.icon:SetTexture(icon)
    row.name:SetText(wished and (ns.Wishlist.Icon() .. " " .. name) or name)
    local info = {}
    if ns.Owned:Has(data.itemID) then
        table.insert(info, UI.OWNED_TEXT)
    end
    if selectedBoss == ALL_BOSSES or selectedBoss == WISHLIST then
        table.insert(info, "|cff999999" .. data.boss .. "|r")
    end
    row.info:SetText(table.concat(info, "  "))
    if wished then
        row.bg:SetColorTexture(1, 0.82, 0, 0.1)
    else
        row.bg:SetColorTexture(0, 0, 0, 0)
    end
end

local itemList = UI.CreateScrollList(content, ROW_HEIGHT, initItemRow)
itemList:SetPoint("TOPLEFT", lootHeader, "BOTTOMLEFT", 0, -6)
itemList:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -20, 0)

-- Daten aufbauen -------------------------------------------------------------

local function buildBossElements(encounters)
    local allItems = {}
    for _, encounter in ipairs(encounters) do
        for _, itemID in ipairs(encounter.items) do
            table.insert(allItems, itemID)
        end
    end
    local elements = {
        { index = WISHLIST, name = "Wunschliste", wished = ns.Wishlist:CountIn(allItems) },
        { index = ALL_BOSSES, name = "Alle Bosse" },
    }
    for index, encounter in ipairs(encounters) do
        table.insert(elements, {
            index = index,
            name = encounter.name,
            displayID = encounter.displayID,
            wished = ns.Wishlist:CountIn(encounter.items),
        })
    end
    return elements
end

local function buildItemElements(encounters)
    local elements, seen = {}, {}
    for bossIndex, encounter in ipairs(encounters) do
        if selectedBoss == ALL_BOSSES or selectedBoss == WISHLIST or selectedBoss == bossIndex then
            for _, itemID in ipairs(encounter.items) do
                local existing = seen[itemID]
                if existing then
                    existing.boss = "mehrere Bosse"
                elseif selectedBoss ~= WISHLIST or ns.Wishlist:Has(itemID) then
                    local element = { itemID = itemID, boss = encounter.name }
                    seen[itemID] = element
                    table.insert(elements, element)
                end
            end
        end
    end
    return elements
end

local regenerateMenu = UI.Debounce(function()
    if not instanceDropdown:IsMenuOpen() then
        instanceDropdown:GenerateMenu()
    end
end, 0)

function refresh()
    if not ns.db then return end
    regenerateMenu()
    local instance = currentInstance()
    bossList:SetShown(instance ~= nil)
    content:SetShown(instance ~= nil)
    emptyText:SetShown(instance == nil)
    if not instance then
        infoText:SetText("")
        return
    end
    local encounters = ns.LootData:GetDisplayEncounters(instance.fullKey)
    if selectedBoss > #encounters then
        selectedBoss = ALL_BOSSES
    end
    local bosses, items = ns.LootData:GetStats(instance.fullKey)
    infoText:SetText(string.format("%s – %d Bosse, %d Items", instance.isRaid and "Raid" or "Dungeon",
        bosses, items))

    if selectedBoss == WISHLIST then
        lootHeader:SetText("Deine Wunschliste in " .. instance.name)
    elseif selectedBoss == ALL_BOSSES then
        lootHeader:SetText("Loot aller Bosse")
    else
        lootHeader:SetText("Loot von " .. encounters[selectedBoss].name)
    end

    bossList:SetDataProvider(CreateDataProvider(buildBossElements(encounters)),
        ScrollBoxConstants.RetainScrollPosition)
    itemList:SetDataProvider(CreateDataProvider(buildItemElements(encounters)),
        ScrollBoxConstants.RetainScrollPosition)
end

panel:HookScript("OnShow", refresh)

local refreshIfShown = UI.Debounce(function()
    if panel:IsVisible() then
        refresh()
    end
end)
ns:On("WISHLIST_CHANGED", refreshIfShown)
ns:On("OWNED_CHANGED", refreshIfShown)
ns:On("LOOT_ITEMS_CHANGED", refreshIfShown)
