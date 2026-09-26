-- Hauptfenster mit den Tabs "Raider" und "Raidlead".
-- Der Inhalt des Raidlead-Tabs liegt in UI/LeadPanel.lua.
local addonName, ns = ...

local UI = {}
ns.UI = UI

UI.TAB_RAIDER = 1
UI.TAB_LEAD = 2

local mainFrame = CreateFrame("Frame", nil, UIParent, "PortraitFrameTemplate")
mainFrame:SetSize(500, 420)
mainFrame:SetPoint("CENTER")
mainFrame:SetFrameStrata("HIGH")
mainFrame:SetToplevel(true)
mainFrame:EnableMouse(true)
mainFrame:SetMovable(true)
mainFrame:RegisterForDrag("LeftButton")
mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)
mainFrame:SetClampedToScreen(true)
mainFrame.TitleContainer.TitleText:SetText(addonName)
mainFrame.CloseButton:SetScript("OnClick", function()
    mainFrame:Hide()
end)
mainFrame:Hide()
ns.mainFrame = mainFrame

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

-- Raider-Tab: Statusblock (die Auswahl folgt in Iteration 4)
local raiderPanel = panels[UI.TAB_RAIDER]
local raiderStatus = {}
raiderStatus.header = UI.CreateText(raiderPanel, nil, nil, "GameFontNormalLarge")
raiderStatus.header:SetText("Meine Soft Reserves")
raiderStatus.role = UI.CreateText(raiderPanel, raiderStatus.header, -10)
raiderStatus.session = UI.CreateText(raiderPanel, raiderStatus.role)
raiderStatus.instance = UI.CreateText(raiderPanel, raiderStatus.session)
raiderStatus.rules = UI.CreateText(raiderPanel, raiderStatus.instance)
raiderStatus.own = UI.CreateText(raiderPanel, raiderStatus.rules)

local function refreshRaiderStatus()
    local s = ns.Session:Get()
    raiderStatus.role:SetText("Rolle: " .. ns.Roles:GetRoleName())
    if not s then
        raiderStatus.session:SetText("Sitzung: keine")
        raiderStatus.instance:SetText("")
        raiderStatus.rules:SetText("")
        raiderStatus.own:SetText("")
        return
    end
    raiderStatus.session:SetText("Sitzung: " .. (s.leader or "?") .. (s.locked and " (gesperrt)" or " (offen)"))
    raiderStatus.instance:SetText("Instanz: " .. (s.instanceName or "nicht gewählt"))
    raiderStatus.rules:SetText(string.format("Max. SRs pro Spieler: %d, doppelte Items: %s",
        s.maxReserves, s.allowDuplicates and "ja" or "nein"))
    raiderStatus.own:SetText(string.format("Eigene Reserves: %d / %d",
        ns.Session:CountReserves(ns.FullName("player")), s.maxReserves))
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
PanelTemplates_SetNumTabs(mainFrame, 2)
selectTab(UI.TAB_RAIDER)

local function refresh()
    local isLead = ns.Roles:IsLead()
    PanelTemplates_SetTabEnabled(mainFrame, UI.TAB_LEAD, isLead)
    if not isLead and mainFrame.selectedTab == UI.TAB_LEAD then
        selectTab(UI.TAB_RAIDER)
    end
    refreshRaiderStatus()
end

mainFrame:HookScript("OnShow", refresh)
ns:On("SESSION_CHANGED", refresh)
ns:On("ROLE_CHANGED", refresh)
ns:On("DB_READY", refresh)
