-- Panel neben dem Lootfenster: Items der Leiche mit ihren Soft Reserves.
-- Der Raidlead startet von hier die Würfelrunde (die Ansage im Chat macht der Start).
-- Nach der Runde zeigt die Zeile den Gewinner (Zuordnung über lootKey = Leichen-GUID + ItemID).
local _, ns = ...

local UI = ns.UI

local ROW_HEIGHT = 34
local WIDTH = 340
local MIN_QUALITY = Enum.ItemQuality and Enum.ItemQuality.Uncommon or 2 -- graue/weiße Items ausblenden

local panel = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
panel:SetSize(WIDTH, 100)
panel:SetFrameStrata("HIGH")
panel:SetClampedToScreen(true)
panel.TitleText:SetText("Soft Reserves")
panel:Hide()

-- Verschiebbar (an der Titelleiste); eine eigene Position wird gespeichert und hat Vorrang
-- vor dem Andocken ans Lootfenster.
panel:EnableMouse(true)
panel:SetMovable(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", panel.StartMoving)
panel:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, x, y = self:GetPoint(1)
    ns.db.lootPanelPos = { point = point, relativePoint = relativePoint, x = x, y = y }
    ns.Debug("Loot", "Loot-Panel verschoben", point, relativePoint, x, y)
end)

local rows = {}
local lootItems = {} -- { { slot, itemID, link }, ... }

-- Zeilen -------------------------------------------------------------------------

local function createRow(index)
    local row = CreateFrame("Frame", nil, panel)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -28 - (index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
    row:EnableMouse(true)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_HEIGHT - 6, ROW_HEIGHT - 6)
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)

    row.roll = UI.CreateButton(row, "Würfeln", 70, function(self)
        local item = self:GetParent().item
        if item then
            ns.Rolls:Start(item.itemID, item.link, nil, nil, nil, item.lootKey)
        end
    end)
    row.roll:SetHeight(20)
    row.roll:SetPoint("RIGHT", row, "RIGHT", 0, 0)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
    row.name:SetPoint("RIGHT", row.roll, "LEFT", -4, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.holders = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.holders:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 1)
    row.holders:SetPoint("RIGHT", row.roll, "LEFT", -4, 0)
    row.holders:SetJustifyH("LEFT")
    row.holders:SetWordWrap(false)

    row:SetScript("OnEnter", function(self)
        if self.item then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.item.link)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    return row
end

local function refresh()
    local isLead = ns.Roles:IsLead()
    for index, item in ipairs(lootItems) do
        local row = rows[index] or createRow(index)
        rows[index] = row
        row.item = item
        local name, icon = UI.GetItemDisplay(item.itemID)
        row.icon:SetTexture(icon)
        row.name:SetText(name)
        -- Stand des Items: wird ausgewürfelt > vergeben (letztes Ergebnis) > SR-Inhaber
        local awards = ns.Rolls:GetAwards(item.lootKey)
        local award = awards[#awards]
        if ns.Rolls:IsRolling(item.itemID, item.lootKey) then
            row.holders:SetText("|cffffd100wird ausgewürfelt …|r")
            row.bg:SetColorTexture(1, 0.82, 0, 0.12)
            row.roll:SetText("Würfeln")
        elseif award then
            row.holders:SetText(string.format("|cff40ff40Gewonnen:|r %s (%s, %d)", UI.ShortName(award.winner or "?"),
                ns.Rolls.LABEL[award.category] or award.category or "?", award.roll or 0))
            row.bg:SetColorTexture(0.1, 0.6, 0.1, 0.2)
            row.roll:SetText("Erneut")
        else
            local holders, total = UI.FormatHolders(item.itemID)
            if holders then
                row.holders:SetText(string.format("|cffffd100SR (%d):|r %s", total, holders))
            else
                row.holders:SetText("|cff808080kein SR – freier Wurf|r")
            end
            row.bg:SetColorTexture(0, 0, 0, 0)
            row.roll:SetText("Würfeln")
        end
        row.roll:SetShown(isLead)
        row:Show()
    end
    for index = #lootItems + 1, #rows do
        rows[index]:Hide()
        rows[index].item = nil
    end
    panel:SetHeight(28 + #lootItems * ROW_HEIGHT + 10)
end

-- Loot einlesen --------------------------------------------------------------------

local function readLoot()
    wipe(lootItems)
    for slot = 1, GetNumLootItems() do
        local link = GetLootSlotLink(slot)
        if link and not (issecretvalue and issecretvalue(link)) then
            local _, _, _, _, quality = GetLootSlotInfo(slot)
            local itemID = C_Item.GetItemInfoInstant(link)
            if itemID and (quality == nil or quality >= MIN_QUALITY) then
                -- Leiche + Item als Schlüssel, damit der Gewinner beim erneuten Öffnen wieder erscheint
                local lootKey
                if type(GetLootSourceInfo) == "function" then
                    local guid = GetLootSourceInfo(slot)
                    if guid and not (issecretvalue and issecretvalue(guid)) then
                        lootKey = guid .. ":" .. itemID
                    end
                end
                table.insert(lootItems, { slot = slot, itemID = itemID, link = link, lootKey = lootKey })
            end
        end
    end
end

local function anchorPanel()
    panel:ClearAllPoints()
    local pos = ns.db.lootPanelPos
    if pos then
        panel:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
    elseif LootFrame and LootFrame:IsShown() then
        panel:SetPoint("TOPLEFT", LootFrame, "TOPRIGHT", 6, 0)
    else
        panel:SetPoint("LEFT", UIParent, "CENTER", 120, 0)
    end
end

local function update()
    local s = ns.Session:Get()
    if not s or not ns.db.lootPanel then
        panel:Hide()
        return
    end
    readLoot()
    if #lootItems == 0 then
        panel:Hide()
        return
    end
    refresh()
    anchorPanel()
    panel:Show()
    ns.Debug("Loot", "Loot-Panel mit", #lootItems, "Items")
end

function ns:LOOT_OPENED()
    -- Das Lootfenster wird im selben Frame aufgebaut: einen Tick warten, dann andocken
    C_Timer.After(0, update)
end

function ns:LOOT_SLOT_CLEARED()
    if panel:IsShown() then
        update()
    end
end

function ns:LOOT_CLOSED()
    panel:Hide()
end

local function refreshIfShown()
    if panel:IsShown() then
        refresh()
    end
end
ns:On("SESSION_CHANGED", refreshIfShown)
ns:On("ROLL_CHANGED", refreshIfShown)

ns:On("DB_READY", function()
    if ns.db.lootPanel == nil then
        ns.db.lootPanel = true
    end
end)

ns:RegisterEvent("LOOT_OPENED")
ns:RegisterEvent("LOOT_SLOT_CLEARED")
ns:RegisterEvent("LOOT_CLOSED")

-- Test ohne Leiche: /paeniksoftres loottest zeigt das Panel mit den eigenen Reserves
function ns.ShowLootTest()
    local s = ns.Session:Get()
    if not s then
        ns.Print("Keine Sitzung.")
        return
    end
    wipe(lootItems)
    local seen = {}
    for _, list in pairs(s.reserves) do
        for _, entry in ipairs(list) do
            if not seen[entry.itemID] and #lootItems < 6 then
                seen[entry.itemID] = true
                local _, link = C_Item.GetItemInfo(entry.itemID)
                table.insert(lootItems, {
                    itemID = entry.itemID,
                    link = link or ("item:" .. entry.itemID),
                    lootKey = "test:" .. entry.itemID,
                })
            end
        end
    end
    if #lootItems == 0 then
        ns.Print("Keine Reserves für den Test vorhanden.")
        return
    end
    refresh()
    anchorPanel()
    panel:Show()
    ns.Print("Loot-Test: " .. #lootItems .. " Items")
end
