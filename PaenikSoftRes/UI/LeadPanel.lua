-- Raidlead-Tab: Sitzung anlegen und Regeln festlegen.
local _, ns = ...

local UI = ns.UI
local panel = UI.GetPanel(UI.TAB_LEAD)

local LABEL_WIDTH = 150

local header = UI.CreateText(panel, nil, nil, "GameFontNormalLarge")
header:SetText("Raidlead")
local sessionText = UI.CreateText(panel, header, -10)

-- Ohne Sitzung: nur der Start-Button
local newButton = UI.CreateButton(panel, "Neue Sitzung", 140, function()
    ns.Session:New(ns.FullName("player"))
end)
newButton:SetPoint("TOPLEFT", sessionText, "BOTTOMLEFT", 0, -16)

-- Mit Sitzung: Regeln
local rules = CreateFrame("Frame", nil, panel)
rules:SetPoint("TOPLEFT", sessionText, "BOTTOMLEFT", 0, -16)
rules:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT")

local function createLabel(text, anchor, offsetY)
    local label = UI.CreateText(rules, anchor, offsetY, "GameFontNormal")
    label:SetWidth(LABEL_WIDTH)
    label:SetText(text)
    return label
end

-- Instanz
local instanceLabel = createLabel("Instanz:")
instanceLabel:ClearAllPoints()
instanceLabel:SetPoint("TOPLEFT", rules, "TOPLEFT", 0, -6)

local instanceDropdown = CreateFrame("DropdownButton", nil, rules, "WowStyle1DropdownTemplate")
instanceDropdown:SetWidth(220)
instanceDropdown:SetPoint("LEFT", instanceLabel, "RIGHT", 0, 0)
instanceDropdown:SetDefaultText("Instanz wählen")

local function isInstanceSelected(instance)
    local s = ns.Session:Get()
    return s ~= nil and s.instanceKey == instance.fullKey
end

local function selectInstance(instance)
    ns.Session:SetRules({ instanceKey = instance.fullKey, instanceName = instance.name })
end

instanceDropdown:SetupMenu(function(_, root)
    local instances = ns.LootData:GetInstances()
    if #instances == 0 then
        root:CreateTitle("Keine Instanzen verfügbar")
        return
    end
    local lastIsRaid
    for _, instance in ipairs(instances) do
        if instance.isRaid ~= lastIsRaid then
            root:CreateTitle(instance.isRaid and "Raids" or "Dungeons")
            lastIsRaid = instance.isRaid
        end
        root:CreateRadio(instance.name, isInstanceSelected, selectInstance, instance)
    end
end)

local instanceInfo = UI.CreateText(rules, instanceDropdown, -4, "GameFontHighlightSmall")

-- Max. SRs pro Spieler
local maxLabel = createLabel("Max. SRs pro Spieler:", instanceLabel, -34)

local maxDropdown = CreateFrame("DropdownButton", nil, rules, "WowStyle1DropdownTemplate")
maxDropdown:SetWidth(80)
maxDropdown:SetPoint("LEFT", maxLabel, "RIGHT", 0, 0)

local function isMaxSelected(n)
    local s = ns.Session:Get()
    return s ~= nil and s.maxReserves == n
end

local function selectMax(n)
    local ok, err = ns.Session:SetRules({ maxReserves = n })
    if not ok then
        ns.Debug("LeadPanel", "maxReserves abgelehnt:", err)
    end
end

maxDropdown:SetupMenu(function(_, root)
    for n = 1, ns.Session.MAX_RESERVES_LIMIT do
        root:CreateRadio(tostring(n), isMaxSelected, selectMax, n)
    end
end)

-- Gleiches Item mehrfach
local duplicatesCheck = CreateFrame("CheckButton", nil, rules, "UICheckButtonTemplate")
duplicatesCheck:SetPoint("TOPLEFT", maxLabel, "BOTTOMLEFT", -4, -14)
duplicatesCheck.Text:SetText("Gleiches Item darf mehrfach reserviert werden")
duplicatesCheck.Text:SetFontObject("GameFontHighlight")
duplicatesCheck:SetScript("OnClick", function(self)
    ns.Session:SetRules({ allowDuplicates = self:GetChecked() and true or false })
end)

-- Sperren / Öffnen
local lockText = UI.CreateText(rules, duplicatesCheck, -14, "GameFontNormal")

local lockButton = UI.CreateButton(rules, "Sperren", 140, function()
    local s = ns.Session:Get()
    if s then
        ns.Session:SetLocked(not s.locked)
    end
end)
lockButton:SetPoint("TOPLEFT", lockText, "BOTTOMLEFT", 0, -8)

-- Unten: Sitzung neu starten / verwerfen
local restartButton = UI.CreateButton(rules, "Neu starten", 140, function()
    ns.Session:New(ns.FullName("player"))
end)
restartButton:SetPoint("BOTTOMLEFT", rules, "BOTTOMLEFT", 0, 4)

local resetButton = UI.CreateButton(rules, "Sitzung verwerfen", 140, function()
    ns.Session:Reset()
end)
resetButton:SetPoint("LEFT", restartButton, "RIGHT", 8, 0)

local function refresh()
    local s = ns.Session:Get()
    newButton:SetShown(s == nil)
    rules:SetShown(s ~= nil)
    if not s then
        sessionText:SetText("Keine Sitzung. Lege eine neue Sitzung an, um die Regeln festzulegen.")
        return
    end

    local reserveCount = 0
    for _, list in pairs(s.reserves) do
        reserveCount = reserveCount + #list
    end
    sessionText:SetText(string.format("Sitzung von %s, %d Reserves", s.leader or "?", reserveCount))

    if s.instanceKey then
        local bosses, items = ns.LootData:GetStats(s.instanceKey)
        instanceInfo:SetText(string.format("%d Bosse, %d Items", bosses, items))
    else
        instanceInfo:SetText("Noch keine Instanz gewählt")
    end

    local editable = not s.locked
    instanceDropdown:SetEnabled(editable)
    maxDropdown:SetEnabled(editable)
    duplicatesCheck:SetEnabled(editable)
    duplicatesCheck:SetChecked(s.allowDuplicates)
    -- Auswahltext neu auswerten; kein GenerateMenu, da refresh auch aus einer Menü-Antwort kommt
    instanceDropdown:SignalUpdate()
    maxDropdown:SignalUpdate()

    if s.locked then
        lockText:SetText("Status: |cffff6060gesperrt|r – keine Änderungen an Regeln und Reserves")
        lockButton:SetText("Öffnen")
    else
        lockText:SetText("Status: |cff60ff60offen|r – Raider können reservieren")
        lockButton:SetText("Sperren")
    end
end

panel:HookScript("OnShow", refresh)
ns:On("SESSION_CHANGED", refresh)
ns:On("DB_READY", refresh)
