-- Panel neben dem Lootfenster: Items der Leiche mit ihren Soft Reserves.
-- Der Raidlead kann die SRs pro Item oder für alle Items im Gruppenchat ansagen.
local addonName, ns = ...

local UI = ns.UI

local ROW_HEIGHT = 34
local WIDTH = 330
local MIN_QUALITY = Enum.ItemQuality and Enum.ItemQuality.Uncommon or 2 -- graue/weiße Items ausblenden

local panel = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
panel:SetSize(WIDTH, 100)
panel:SetFrameStrata("HIGH")
panel:SetClampedToScreen(true)
panel.TitleText:SetText("Soft Reserves")
panel:Hide()

local rows = {}
local lootItems = {} -- { { slot, itemID, link }, ... }

-- Ansage im Gruppenchat --------------------------------------------------------

local function announce(item)
    local channel = ns.GroupChannel()
    local holders = UI.FormatHolders(item.itemID)
    local text
    if holders then
        -- Farbcodes aus der Anzeige entfernen, Chat erlaubt nur Links
        text = item.link .. " – SR: " .. holders:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    else
        text = item.link .. " – kein SR"
    end
    if not channel then
        ns.Print(text)
        return
    end
    if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
        ns.Print("Chat ist gerade gesperrt (Kampf in der Instanz). Bitte später ansagen.")
        return
    end
    C_ChatInfo.SendChatMessage(text, channel)
end

-- Zeilen -------------------------------------------------------------------------

local function createRow(index)
    local row = CreateFrame("Frame", nil, panel)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -28 - (index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
    row:EnableMouse(true)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_HEIGHT - 6, ROW_HEIGHT - 6)
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)

    row.announce = UI.CreateButton(row, "Ansagen", 70, function(self)
        local item = self:GetParent().item
        if item then
            announce(item)
        end
    end)
    row.announce:SetHeight(20)
    row.announce:SetPoint("RIGHT", row, "RIGHT", 0, 0)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
    row.name:SetPoint("RIGHT", row.announce, "LEFT", -4, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.holders = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.holders:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 1)
    row.holders:SetPoint("RIGHT", row.announce, "LEFT", -4, 0)
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

local announceAll = UI.CreateButton(panel, "Alle ansagen", 100, function()
    for _, item in ipairs(lootItems) do
        if UI.FormatHolders(item.itemID) then
            announce(item)
        end
    end
end)
announceAll:SetHeight(20)

local function refresh()
    local isLead = ns.Roles:IsLead()
    local srCount = 0
    for index, item in ipairs(lootItems) do
        local row = rows[index] or createRow(index)
        rows[index] = row
        row.item = item
        local name, icon = UI.GetItemDisplay(item.itemID)
        row.icon:SetTexture(icon)
        row.name:SetText(name)
        local holders, total = UI.FormatHolders(item.itemID)
        if holders then
            srCount = srCount + 1
            row.holders:SetText(string.format("|cffffd100SR (%d):|r %s", total, holders))
        else
            row.holders:SetText("|cff808080kein SR – freier Wurf|r")
        end
        row.announce:SetShown(isLead)
        row:Show()
    end
    for index = #lootItems + 1, #rows do
        rows[index]:Hide()
        rows[index].item = nil
    end
    announceAll:ClearAllPoints()
    announceAll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 8)
    announceAll:SetShown(isLead and srCount > 0)
    local footer = (isLead and srCount > 0) and 30 or 10
    panel:SetHeight(28 + #lootItems * ROW_HEIGHT + footer)
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
                table.insert(lootItems, { slot = slot, itemID = itemID, link = link })
            end
        end
    end
end

local function anchorPanel()
    panel:ClearAllPoints()
    if LootFrame and LootFrame:IsShown() then
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

ns:On("SESSION_CHANGED", function()
    if panel:IsShown() then
        refresh()
    end
end)

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
                table.insert(lootItems, { itemID = entry.itemID, link = link or ("item:" .. entry.itemID) })
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
    ns.Print(addonName .. " Loot-Test: " .. #lootItems .. " Items")
end
