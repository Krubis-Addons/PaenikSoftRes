-- Raidlead-Tab: Sitzungen verwalten (mehrere Raids) und Regeln der aktiven Sitzung festlegen.
local _, ns = ...

local UI = ns.UI
local panel = UI.GetPanel(UI.TAB_LEAD)

local LABEL_WIDTH = 150

local header = UI.CreateText(panel, nil, nil, "GameFontNormalLarge")
header:SetText("Raidlead")

-- Vorlagen für regelmäßige Raids (UI/TemplatesDialog.lua), auch ohne aktive Sitzung erreichbar
local templatesButton = UI.CreateButton(panel, "Regelmäßige Raids…", 170, function()
    ns.ShowTemplates()
end)
templatesButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 4)
templatesButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Regelmäßige Raids")
    GameTooltip:AddLine("Vorlagen, aus denen jede Woche automatisch die Sitzung für den nächsten Termin entsteht.",
        1, 1, 1, true)
    GameTooltip:Show()
end)
templatesButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Sitzungsauswahl: alle eigenen Sitzungen, die aktive wird an die Gruppe verteilt
local sessionLabel = UI.CreateText(panel, header, -14, "GameFontNormal")
sessionLabel:SetWidth(LABEL_WIDTH)
sessionLabel:SetText("Sitzung:")

local sessionDropdown = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
sessionDropdown:SetWidth(290)
sessionDropdown:SetPoint("LEFT", sessionLabel, "RIGHT", 0, 0)
sessionDropdown:SetDefaultText("Keine Sitzung")

local function newSession()
    ns.Session:New(ns.FullName("player"))
end

local function isSessionSelected(id)
    return ns.Session:GetActiveID() == id
end

local function selectSession(id)
    if isSessionSelected(id) then return end
    UI.Confirm("Aktive Sitzung der Gruppe wechseln?\nDie Gruppe bekommt die gewählte Sitzung.",
        function() ns.Session:SetActive(id) end,
        ns.GroupChannel() ~= nil)
end

-- Vergangene Sitzungen (Termin aus einer Vorlage hat begonnen) in einem Untermenü; die aktive steht immer oben
sessionDropdown:SetupMenu(function(_, root)
    local sessions = ns.Session:List()
    local now, activeID = GetServerTime(), ns.Session:GetActiveID()
    local past = {}
    for _, s in ipairs(sessions) do
        local text = (s.name or "?") .. "  " .. UI.LockStateText(s)
        if s.id ~= activeID and ns.Session.IsPast(s, now) then
            table.insert(past, { text = text, id = s.id })
        else
            if ns.Session.IsPast(s, now) then
                text = text .. "  |cff999999(Termin vorbei)|r" -- aktive bleibt oben, auch wenn vergangen
            end
            root:CreateRadio(text, isSessionSelected, selectSession, s.id)
        end
    end
    if #past > 0 then
        local pastMenu = root:CreateButton("Vergangene Sitzungen (" .. #past .. ")")
        for i = #past, 1, -1 do -- neueste zuerst
            pastMenu:CreateRadio(past[i].text, isSessionSelected, selectSession, past[i].id)
        end
    end
    if #sessions > 0 then
        root:CreateDivider()
    end
    root:CreateButton("Neue Sitzung anlegen", newSession)
end)

-- Name der aktiven Sitzung (Enter übernimmt, leer = automatischer Name)
local nameBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
nameBox:SetSize(170, 20)
nameBox:SetPoint("LEFT", sessionDropdown, "RIGHT", 14, 0)
nameBox:SetAutoFocus(false)
nameBox:SetMaxLetters(40)
nameBox:SetScript("OnEnterPressed", function(self)
    ns.Session:Rename(self:GetText())
    self:ClearFocus()
end)
nameBox:SetScript("OnEscapePressed", function(self)
    local s = ns.Session:Get()
    self:SetText(s and s.name or "")
    self:ClearFocus()
end)
nameBox:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Name der Sitzung")
    GameTooltip:AddLine("Enter übernimmt. Leer lassen für den automatischen Namen.", 1, 1, 1, true)
    GameTooltip:Show()
end)
nameBox:SetScript("OnLeave", function() GameTooltip:Hide() end)

local sessionText = UI.CreateText(panel, sessionLabel, -16)

-- Ohne aktive Sitzung: Start-Button
local newButton = UI.CreateButton(panel, "Neue Sitzung", 140, newSession)
newButton:SetPoint("TOPLEFT", sessionText, "BOTTOMLEFT", 0, -16)

-- Sitzung des bisherigen Gruppenleiters (nach Übergabe der Leitung): als eigene übernehmen
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
    local s = ns.Session:Get()
    if s and s.instanceKey == instance.fullKey then return end
    -- Die Dropdown-Auswahl bleibt bis zur Bestätigung auf der alten Instanz
    UI.Confirm("Instanz wechseln zu „" .. instance.name .. "“?\nAlle bisherigen Reserves werden verworfen.",
        function()
            ns.Session:SetRules({ instanceKey = instance.fullKey, instanceName = instance.name })
        end,
        s ~= nil and next(s.reserves) ~= nil)
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
    if ns.Session:Get() then
        ns.Session:SetLocked(not ns.Session:IsLocked())
    end
end)
lockButton:SetPoint("TOPLEFT", lockText, "BOTTOMLEFT", 0, -8)

-- Für die Gilde veröffentlichen: Raider können ohne Gruppe reservieren (GuildSync.lua)
local publishCheck = CreateFrame("CheckButton", nil, rules, "UICheckButtonTemplate")
publishCheck:SetPoint("LEFT", lockButton, "RIGHT", 20, 0)
publishCheck.Text:SetText("Für die Gilde veröffentlichen")
publishCheck.Text:SetFontObject("GameFontHighlight")
publishCheck:SetScript("OnClick", function(self)
    ns.GuildSync:SetPublished(ns.Session:Get(), self:GetChecked())
end)
publishCheck:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Für die Gilde veröffentlichen")
    GameTooltip:AddLine("Gildenmitglieder mit dem Addon sehen die Sitzung und können ohne Gruppe bis zum "
        .. "Anmeldeschluss reservieren. Ihre Anmeldungen kommen an, sobald ihr gleichzeitig online seid.",
        1, 1, 1, true)
    GameTooltip:Show()
end)
publishCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)

local guildInfo = rules:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
guildInfo:SetPoint("TOPLEFT", publishCheck.Text, "BOTTOMLEFT", 0, -2) -- darunter: rechts beginnt der Kasten „Würfeln“

-- Anmeldeschluss: optionaler Zeitpunkt, danach ist die Sitzung automatisch geschlossen
local DEFAULT_HOUR, DEFAULT_MIN = 20, 0

local deadlineLabel = createLabel("Anmeldeschluss:", lockButton, -18)

local dayDropdown = CreateFrame("DropdownButton", nil, rules, "WowStyle1DropdownTemplate")
dayDropdown:SetWidth(170)
dayDropdown:SetPoint("LEFT", deadlineLabel, "RIGHT", 0, 0)
dayDropdown:SetDefaultText("Kein Anmeldeschluss")

local timeDropdown = CreateFrame("DropdownButton", nil, rules, "WowStyle1DropdownTemplate")
timeDropdown:SetWidth(90)
timeDropdown:SetPoint("LEFT", dayDropdown, "RIGHT", 8, 0)
timeDropdown:SetDefaultText("--:--")

-- Zeitstempel aus lokalem Tag ("YYYY-MM-DD") und Uhrzeit
local function makeTimestamp(dayKey, hour, minute)
    local year, month, day = dayKey:match("^(%d+)-(%d+)-(%d+)$")
    return time({ year = tonumber(year), month = tonumber(month), day = tonumber(day),
        hour = hour, min = minute, sec = 0 })
end

local function currentDeadline()
    local s = ns.Session:Get()
    return s and s.deadline
end

local function applyDeadline(timestamp)
    if timestamp <= GetServerTime() then
        ns.Print("Der Anmeldeschluss liegt in der Vergangenheit.")
        return
    end
    ns.Session:SetRules({ deadline = timestamp })
end

local function isDaySelected(dayKey)
    local deadline = currentDeadline()
    if dayKey == "none" then
        return deadline == nil
    end
    return deadline ~= nil and date("%Y-%m-%d", deadline) == dayKey
end

local function selectDay(dayKey)
    if dayKey == "none" then
        ns.Session:SetRules({ deadline = 0 })
        return
    end
    local deadline = currentDeadline()
    local hour = deadline and tonumber(date("%H", deadline)) or DEFAULT_HOUR
    local minute = deadline and tonumber(date("%M", deadline)) or DEFAULT_MIN
    applyDeadline(makeTimestamp(dayKey, hour, minute))
end

dayDropdown:SetupMenu(function(_, root)
    root:CreateRadio("Kein Anmeldeschluss", isDaySelected, selectDay, "none")
    local year, month, day = tonumber(date("%Y")), tonumber(date("%m")), tonumber(date("%d"))
    for offset = 0, 13 do
        -- time() normalisiert Tage über das Monatsende hinaus
        local timestamp = time({ year = year, month = month, day = day + offset, hour = 12 })
        local prefix = offset == 0 and "Heute, " or (offset == 1 and "Morgen, " or "")
        root:CreateRadio(prefix .. UI.FormatDate(timestamp, false), isDaySelected, selectDay,
            date("%Y-%m-%d", timestamp))
    end
end)

local function isTimeSelected(minutes)
    local deadline = currentDeadline()
    return deadline ~= nil and tonumber(date("%H", deadline)) * 60 + tonumber(date("%M", deadline)) == minutes
end

local function selectTime(minutes)
    local hour, minute = math.floor(minutes / 60), minutes % 60
    local deadline = currentDeadline()
    local dayKey = deadline and date("%Y-%m-%d", deadline) or date("%Y-%m-%d")
    local timestamp = makeTimestamp(dayKey, hour, minute)
    if not deadline and timestamp <= GetServerTime() then
        -- noch kein Tag gewählt und die Uhrzeit ist heute schon vorbei: morgen
        timestamp = makeTimestamp(date("%Y-%m-%d", timestamp + 24 * 60 * 60), hour, minute)
    end
    applyDeadline(timestamp)
end

timeDropdown:SetupMenu(function(_, root)
    root:SetScrollMode(260)
    for minutes = 0, 23 * 60 + 30, 30 do
        root:CreateRadio(string.format("%02d:%02d", math.floor(minutes / 60), minutes % 60),
            isTimeSelected, selectTime, minutes)
    end
end)

-- Einstellungen für alle Sitzungen (persönlich, nicht Teil der Sitzung): eigener, abgesetzter Kasten rechts,
-- auch ohne aktive Sitzung sichtbar. Ebenfalls in den Optionen.
local GLOBAL_BOX_WIDTH = 250

local globalBox = CreateFrame("Frame", nil, panel)
globalBox:SetSize(GLOBAL_BOX_WIDTH, 196)
globalBox:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -74)
local globalBg = globalBox:CreateTexture(nil, "BACKGROUND")
globalBg:SetAllPoints()
globalBg:SetColorTexture(1, 1, 1, 0.05)
local globalBorder = globalBox:CreateTexture(nil, "BORDER")
globalBorder:SetPoint("TOPLEFT")
globalBorder:SetPoint("TOPRIGHT")
globalBorder:SetHeight(2)
globalBorder:SetColorTexture(1, 0.82, 0, 0.6)

local globalTitle = globalBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
globalTitle:SetPoint("TOPLEFT", globalBox, "TOPLEFT", 10, -10)
globalTitle:SetText("Würfeln")
local globalSubtitle = globalBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
globalSubtitle:SetPoint("TOPLEFT", globalTitle, "BOTTOMLEFT", 0, -3)
globalSubtitle:SetText("|cff999999Gilt für alle Sitzungen (deine Einstellung)|r")

-- Würfelzeit: Zeitfenster für Würfelrunden
local durationLabel = globalBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
durationLabel:SetPoint("TOPLEFT", globalSubtitle, "BOTTOMLEFT", 0, -16)
durationLabel:SetText("Würfelzeit:")

local durationDropdown = CreateFrame("DropdownButton", nil, globalBox, "WowStyle1DropdownTemplate")
durationDropdown:SetWidth(150)
durationDropdown:SetPoint("LEFT", durationLabel, "RIGHT", 8, 0)

durationDropdown:SetupMenu(function(_, root)
    for _, seconds in ipairs(ns.Rolls.DURATIONS) do
        root:CreateRadio(ns.Rolls.DurationText(seconds),
            function(value) return ((ns.db and ns.db.rollDuration) or 0) == value end,
            function(value)
                ns.db.rollDuration = value
                ns.Debug("LeadPanel", "Würfelzeit", value)
            end,
            seconds)
    end
end)

local durationHint = globalBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
durationHint:SetPoint("TOPLEFT", durationLabel, "BOTTOMLEFT", 0, -12)
durationHint:SetWidth(GLOBAL_BOX_WIDTH - 20)
durationHint:SetJustifyH("LEFT")
durationHint:SetText("Mit Zeitfenster endet die Runde automatisch; vorzeitiges Beenden bleibt möglich.")

-- Gewinner manuell wählen
local manualWinnerCheck = CreateFrame("CheckButton", nil, globalBox, "UICheckButtonTemplate")
manualWinnerCheck:SetPoint("TOPLEFT", durationHint, "BOTTOMLEFT", -4, -8)
manualWinnerCheck.Text:SetText("Gewinner manuell wählen")
manualWinnerCheck.Text:SetFontObject("GameFontHighlight")
manualWinnerCheck:SetScript("OnClick", function(self)
    ns.db.manualWinner = self:GetChecked() and true or false
end)
manualWinnerCheck:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Gewinner manuell wählen")
    GameTooltip:AddLine("Der Gewinner einer Würfelrunde wird nicht automatisch aus dem höchsten Wurf bestimmt: "
        .. "Im Leitfenster wählst du ihn per Klick aus allen Würfelnden. „Würfeln beenden“ bzw. das Zeitfenster "
        .. "schließt nur die Würfe. Gilt für neu gestartete Runden.", 1, 1, 1, true)
    GameTooltip:Show()
end)
manualWinnerCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Sitzungs- und Statustext enden links vom Kasten (sonst läuft ein langer Text darunter)
for _, text in ipairs({ sessionText, lockText }) do
    text:SetPoint("RIGHT", globalBox, "LEFT", -12, 0)
    text:SetJustifyH("LEFT")
end

-- Stand bei jedem Anzeigen übernehmen (auch in den Optionen änderbar)
globalBox:SetScript("OnShow", function()
    manualWinnerCheck:SetChecked(ns.db and ns.db.manualWinner == true)
    durationDropdown:SignalUpdate()
end)

-- Unten: weitere Sitzung anlegen / aktive löschen / Import
local restartButton = UI.CreateButton(rules, "Neue Sitzung", 140, newSession)
restartButton:SetPoint("BOTTOMLEFT", rules, "BOTTOMLEFT", 0, 4)

local resetButton = UI.CreateButton(rules, "Sitzung löschen", 140, function()
    local s = ns.Session:Get()
    UI.Confirm("Sitzung „" .. (s and s.name or "?") .. "“ löschen?\n"
        .. "Reserves und Verlauf gehen verloren, die Gruppe wird informiert.", function()
        ns.Session:Reset()
    end)
end)
resetButton:SetPoint("LEFT", restartButton, "RIGHT", 8, 0)

local importButton = UI.CreateButton(rules, "softres.it-Import", 150, function()
    ns.ShowImportDialog()
end)
importButton:SetPoint("LEFT", resetButton, "RIGHT", 8, 0)

-- Raid-ID in einer neuen Sitzung fortführen: gleiche Instanz und Regeln, gelegte Bosse bleiben markiert
local continueButton = UI.CreateButton(rules, "Fortführen", 120, function()
    UI.Confirm("Neue Sitzung für diese Raid-ID anlegen?\nInstanz, Regeln und gelegte Bosse werden übernommen, "
        .. "Reserves und Verlauf nicht.", function()
        ns.Session:Continue()
    end)
end)
continueButton:SetPoint("LEFT", importButton, "RIGHT", 8, 0)
continueButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Raid-ID fortführen")
    GameTooltip:AddLine("Gelegte Bosse markierst du per Rechtsklick in der Bossliste des Raider-Tabs.", 1, 1, 1, true)
    GameTooltip:Show()
end)
continueButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Anzeigetext des Sitzungs-Dropdowns neu erzeugen (neue/gelöschte Sitzungen); einen Frame verzögert,
-- weil refresh auch aus einer Menü-Antwort kommen kann
local regenerateSessionMenu = UI.Debounce(function()
    if not sessionDropdown:IsMenuOpen() then
        sessionDropdown:GenerateMenu()
    end
end, 0)

local function refresh()
    regenerateSessionMenu()
    local s = ns.Session:Get()
    local isOwner = ns.Session:IsOwner()
    local remote = ns.Session:GetRemote()
    -- Übernehmen nur in einer Gruppe (ein alter Spiegel bleibt nach dem Raid gespeichert)
    local canTakeOver = remote ~= nil and remote.leader ~= ns.FullName("player") and ns.GroupChannel() ~= nil
    newButton:SetShown(not isOwner)
    takeOverButton:SetShown(canTakeOver and not isOwner)
    rules:SetShown(isOwner)
    nameBox:SetShown(isOwner)
    if isOwner and not nameBox:HasFocus() then
        nameBox:SetText(s.name or "")
        nameBox:SetCursorPosition(0)
    end
    if not isOwner then
        if canTakeOver then
            sessionText:SetText(string.format("Keine aktive Sitzung. Die Gruppe nutzt noch die Sitzung von %s –"
                .. " übernimm sie mit allen Reserves oder lege eine neue an.", UI.ShortName(remote.leader or "?")))
        else
            sessionText:SetText("Keine aktive Sitzung. Wähle oben eine Sitzung oder lege eine neue an.")
        end
        return
    end

    local reserveCount = 0
    for _, list in pairs(s.reserves) do
        reserveCount = reserveCount + #list
    end
    local count = #ns.Session:List()
    sessionText:SetText(string.format("%d Reserves%s – diese Sitzung ist aktiv und wird an die Gruppe verteilt",
        reserveCount, count > 1 and (" (" .. count .. " Sitzungen insgesamt)") or ""))

    if s.instanceKey then
        local bosses, items = ns.LootData:GetStats(s.instanceKey)
        instanceInfo:SetText(string.format("%d Bosse, %d Items", bosses, items))
    else
        instanceInfo:SetText("Noch keine Instanz gewählt")
    end

    local locked = ns.Session:IsLocked()
    local editable = not locked
    instanceDropdown:SetEnabled(editable)
    maxDropdown:SetEnabled(editable)
    duplicatesCheck:SetEnabled(editable)
    dayDropdown:SetEnabled(editable)
    timeDropdown:SetEnabled(editable)
    duplicatesCheck:SetChecked(s.allowDuplicates)
    -- Auswahltext neu auswerten; kein GenerateMenu, da refresh auch aus einer Menü-Antwort kommt
    instanceDropdown:SignalUpdate()
    maxDropdown:SignalUpdate()
    durationDropdown:SignalUpdate()
    dayDropdown:SignalUpdate()
    timeDropdown:SignalUpdate()

    local inGuild = IsInGuild and IsInGuild() and ns.db.guildSync ~= false
    publishCheck:SetShown(inGuild)
    guildInfo:SetShown(inGuild and s.published == true)
    publishCheck:SetChecked(s.published == true)
    if s.published then
        guildInfo:SetText(string.format("|cff60ff60%d Anmeldungen über die Gilde|r",
            ns.GuildSync:CountGuildSignups(s)))
    end

    if locked then
        lockText:SetText("Status: " .. UI.LockStateText(s) .. " – keine Änderungen an Regeln und Reserves")
        lockButton:SetText("Öffnen")
    else
        lockText:SetText("Status: " .. UI.LockStateText(s) .. " – Raider können reservieren")
        lockButton:SetText("Sperren")
    end
end

panel:HookScript("OnShow", refresh)
ns:On("SESSION_CHANGED", refresh)
ns:On("LOOT_ITEMS_CHANGED", refresh)
ns:On("DB_READY", refresh)
