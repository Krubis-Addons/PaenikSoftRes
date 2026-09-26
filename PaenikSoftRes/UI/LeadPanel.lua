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

-- Fremde Sitzung (z. B. nach Übergabe der Gruppenleitung): übernehmen inkl. Reserves
local takeOverButton = UI.CreateButton(panel, "Sitzung übernehmen", 160, function()
    ns.Session:TakeOver(ns.FullName("player"))
end)
takeOverButton:SetPoint("LEFT", newButton, "RIGHT", 8, 0)

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

-- Würfelzeit: Zeitfenster für Würfelrunden (persönliche Einstellung des Raidleads)
local ROLL_DURATIONS = { 0, 15, 20, 30, 45, 60, 90, 120 }

local durationLabel = createLabel("Würfelzeit:", lockButton, -18)

local durationDropdown = CreateFrame("DropdownButton", nil, rules, "WowStyle1DropdownTemplate")
durationDropdown:SetWidth(160)
durationDropdown:SetPoint("LEFT", durationLabel, "RIGHT", 0, 0)

local function durationText(seconds)
    return seconds == 0 and "Manuell (Raidlead beendet)" or (seconds .. " Sekunden")
end

durationDropdown:SetupMenu(function(_, root)
    for _, seconds in ipairs(ROLL_DURATIONS) do
        root:CreateRadio(durationText(seconds),
            function(value) return ((ns.db and ns.db.rollDuration) or 0) == value end,
            function(value)
                ns.db.rollDuration = value
                ns.Debug("LeadPanel", "Würfelzeit", value)
            end,
            seconds)
    end
end)

local durationHint = UI.CreateText(rules, durationLabel, -10, "GameFontHighlightSmall")
durationHint:SetText("Mit Zeitfenster endet die Runde automatisch; vorzeitiges Beenden bleibt möglich.")

-- Unten: Sitzung neu starten / verwerfen
local restartButton = UI.CreateButton(rules, "Neu starten", 140, function()
    ns.Session:New(ns.FullName("player"))
end)
restartButton:SetPoint("BOTTOMLEFT", rules, "BOTTOMLEFT", 0, 4)

local resetButton = UI.CreateButton(rules, "Sitzung verwerfen", 140, function()
    ns.Session:Reset()
end)
resetButton:SetPoint("LEFT", restartButton, "RIGHT", 8, 0)

local importButton = UI.CreateButton(rules, "softres.it-Import", 150, function()
    ns.ShowImportDialog()
end)
importButton:SetPoint("LEFT", resetButton, "RIGHT", 8, 0)

local function refresh()
    local s = ns.Session:Get()
    local isOwner = ns.Session:IsOwner()
    newButton:SetShown(not isOwner)
    takeOverButton:SetShown(s ~= nil and not isOwner)
    rules:SetShown(isOwner)
    if not s then
        sessionText:SetText("Keine Sitzung. Lege eine neue Sitzung an, um die Regeln festzulegen.")
        return
    end
    if not isOwner then
        sessionText:SetText(string.format(
            "Die aktuelle Sitzung gehört %s.\nÜbernimm sie mit allen Reserves oder lege eine neue an.",
            UI.ShortName(s.leader or "?")))
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
    durationDropdown:SignalUpdate()

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
ns:On("LOOT_ITEMS_CHANGED", refresh)
ns:On("DB_READY", refresh)
