-- Hauptfenster mit den Tabs "Raider", "Raidlead" und "Übersicht".
-- Inhalte: UI/RaiderPanel.lua, UI/LeadPanel.lua, UI/OverviewPanel.lua
local _, ns = ...

local UI = {}
ns.UI = UI

-- Lootbeutel-Icon (Kleiner brauner Beutel), Fallback falls das Item im Client fehlt
UI.ICON = C_Item.GetItemIconByID(4496) or "Interface\\Icons\\INV_Misc_Bag_08"

UI.TAB_RAIDER = 1
UI.TAB_LEAD = 2
UI.TAB_OVERVIEW = 3

local mainFrame = CreateFrame("Frame", nil, UIParent, "PortraitFrameTemplate")
mainFrame:SetSize(760, 540)
mainFrame:SetPoint("CENTER")
mainFrame:SetFrameStrata("HIGH")
mainFrame:SetToplevel(true)
mainFrame:EnableMouse(true)
mainFrame:SetMovable(true)
mainFrame:RegisterForDrag("LeftButton")
mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)
mainFrame:SetClampedToScreen(true)
mainFrame.TitleContainer.TitleText:SetText(ns.TITLE)
mainFrame:SetPortraitToAsset(UI.ICON)
mainFrame.CloseButton:SetScript("OnClick", function()
    mainFrame:Hide()
end)
mainFrame:Hide()
ns.mainFrame = mainFrame

function ns.ToggleMainFrame()
    mainFrame:SetShown(not mainFrame:IsShown())
end

-- Inhaltsbereiche pro Tab
local function createPanel()
    local panel = CreateFrame("Frame", nil, mainFrame)
    panel:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 20, -70)
    panel:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -20, 20)
    panel:Hide()
    return panel
end

local panels = {
    [UI.TAB_RAIDER] = createPanel(),
    [UI.TAB_LEAD] = createPanel(),
    [UI.TAB_OVERVIEW] = createPanel(),
}

function UI.GetPanel(tabID)
    return panels[tabID]
end

function UI.CreateText(parent, anchor, offsetY, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    if anchor then
        fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offsetY or -6)
    else
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    end
    fs:SetJustifyH("LEFT")
    return fs
end

function UI.CreateButton(parent, text, width, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 140, 24)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

-- Scrollbare Liste; initializer(row, elementData) füllt eine (wiederverwendete) Zeile.
function UI.CreateScrollList(parent, rowHeight, initializer)
    local scrollBox = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
    local scrollBar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(rowHeight)
    view:SetElementInitializer("Button", initializer)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    return scrollBox
end

-- Anzeige eines Items: farbiger Name + Icon. Lädt fehlende Item-Daten nach
-- und ruft dann onLoaded auf (entprellt pro Aufrufer).
function UI.GetItemDisplay(itemID, onLoaded)
    if not C_Item.DoesItemExistByID(itemID) then
        return "|cffff4040Item " .. itemID .. " (unbekannt)|r", 134400 -- Fragezeichen-Icon
    end
    local _, _, _, _, icon = C_Item.GetItemInfoInstant(itemID)
    local name = C_Item.GetItemNameByID(itemID)
    if not name then
        if onLoaded then
            Item:CreateFromItemID(itemID):ContinueOnItemLoad(onLoaded)
        end
        return "|cff808080Item " .. itemID .. "|r", icon
    end
    local quality = C_Item.GetItemQualityByID(itemID)
    local _, _, _, hex = C_Item.GetItemQualityColor(quality or 1)
    return "|c" .. (hex or "ffffffff") .. name .. "|r", icon
end

-- Führt fn höchstens einmal pro Frame-Tick aus (für Nachlade-Callbacks).
function UI.Debounce(fn, delay)
    local scheduled = false
    return function()
        if scheduled then return end
        scheduled = true
        C_Timer.After(delay or 0.1, function()
            scheduled = false
            fn()
        end)
    end
end

-- Kurzname ohne eigenen Realm
function UI.ShortName(fullName)
    local realm = GetNormalizedRealmName()
    if realm then
        local short = fullName:match("^(.-)%-" .. realm:gsub("%p", "%%%0") .. "$")
        if short then return short end
    end
    return fullName
end

-- SR-Inhaber eines Items als farbiger Text; nil, wenn niemand reserviert hat.
-- Grün = ich, weiß = in der Gruppe, grau = nicht in der Gruppe (nur ohne Gruppe egal).
function UI.FormatHolders(itemID)
    local holders = ns.Session:GetReservesForItem(itemID)
    if not next(holders) then return nil, 0 end
    local me = ns.FullName("player")
    local inGroup = IsInGroup and IsInGroup()
    local names, total = {}, 0
    for player, count in pairs(holders) do
        total = total + count
        local text = UI.ShortName(player) .. (count > 1 and (" x" .. count) or "")
        local color = "ffffffff"
        if player == me then
            color = "ff40ff40"
        elseif inGroup and not ns.UnitForName(player) then
            color = "ff808080"
        end
        table.insert(names, { sort = player, text = "|c" .. color .. text .. "|r" })
    end
    table.sort(names, function(a, b) return a.sort < b.sort end)
    local parts = {}
    for i, entry in ipairs(names) do
        parts[i] = entry.text
    end
    return table.concat(parts, ", "), total
end

-- Farbcodes entfernen (Chat erlaubt nur Links)
function UI.StripColors(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- Tabs
local function selectTab(id)
    PanelTemplates_SetTab(mainFrame, id)
    for tabID, panel in pairs(panels) do
        panel:SetShown(tabID == id)
    end
end

local function createTab(id, text)
    local tab = CreateFrame("Button", nil, mainFrame, "PanelTabButtonTemplate")
    tab:SetID(id)
    tab:SetText(text)
    tab:SetScript("OnClick", function(self)
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
        selectTab(self:GetID())
    end)
    return tab
end

local raiderTab = createTab(UI.TAB_RAIDER, "Raider")
raiderTab:SetPoint("TOPLEFT", mainFrame, "BOTTOMLEFT", 12, 2)
createTab(UI.TAB_LEAD, "Raidlead")
createTab(UI.TAB_OVERVIEW, "Übersicht")
PanelTemplates_SetNumTabs(mainFrame, 3)
selectTab(UI.TAB_RAIDER)

local function refresh()
    local isLead = ns.Roles:IsLead()
    PanelTemplates_SetTabEnabled(mainFrame, UI.TAB_LEAD, isLead)
    if not isLead and mainFrame.selectedTab == UI.TAB_LEAD then
        selectTab(UI.TAB_RAIDER)
    end
end

mainFrame:HookScript("OnShow", refresh)
ns:On("ROLE_CHANGED", refresh)
ns:On("DB_READY", refresh)
