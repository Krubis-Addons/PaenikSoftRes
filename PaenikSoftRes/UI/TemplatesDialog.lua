-- Fenster „Regelmäßige Raids“: Vorlagen (Templates.lua) anlegen, bearbeiten und löschen.
-- Links die Liste der Vorlagen, rechts die Felder der gewählten; Änderungen gelten sofort.
local _, ns = ...

local UI = ns.UI
local Templates = ns.Templates

local LIST_WIDTH = 210
local ROW_HEIGHT = 36
local LABEL_WIDTH = 120

local frame = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
frame:SetSize(620, 440)
frame:SetPoint("CENTER")
frame:SetFrameStrata("DIALOG")
frame:SetToplevel(true)
frame:SetClampedToScreen(true)
frame:EnableMouse(true)
frame:SetMovable(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame.TitleText:SetText("Regelmäßige Raids")
frame:Hide()

local selectedID
local refresh -- forward

local function selected()
    return Templates:Get(selectedID)
end

local function update(fields)
    local t = selected()
    if t then
        Templates:Update(t, fields)
    end
end

-- Linke Seite: Liste ---------------------------------------------------------------

local function onRowClick(row)
    selectedID = row.templateID
    refresh()
end

local function initRow(row, t)
    if not row.name then
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints()
        row.highlight:SetColorTexture(1, 1, 1, 0.08)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -4)
        row.name:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.info = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.info:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 6, 4)
        row.info:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.info:SetJustifyH("LEFT")
        row.info:SetWordWrap(false)
        row:SetScript("OnClick", onRowClick)
    end
    row.templateID = t.id
    row.name:SetText(t.enabled and t.name or ("|cff808080" .. t.name .. " (aus)|r"))
    row.info:SetText(string.format("%s %02d:%02d – %s", Templates.WEEKDAYS[t.weekday]:sub(1, 2), t.hour, t.minute,
        t.instanceName or "keine Instanz"))
    if t.id == selectedID then
        row.bg:SetColorTexture(1, 0.82, 0, 0.18)
    else
        row.bg:SetColorTexture(0, 0, 0, 0)
    end
end

local list = UI.CreateScrollList(frame, ROW_HEIGHT, initRow)
list:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -32)
list:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 44)
list:SetWidth(LIST_WIDTH)

local newButton = UI.CreateButton(frame, "Neue Vorlage", LIST_WIDTH, function()
    -- Regeln der aktiven eigenen Sitzung übernehmen, falls vorhanden
    local s = ns.Session:IsOwner() and ns.Session:Get() or nil
    selectedID = Templates:New(s).id
    refresh()
end)
newButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 12)

-- Rechte Seite: Felder -------------------------------------------------------------

local editor = CreateFrame("Frame", nil, frame)
editor:SetPoint("TOPLEFT", list, "TOPRIGHT", 34, 0)
editor:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 12)

local emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
emptyText:SetPoint("TOPLEFT", editor, "TOPLEFT", 0, -10)
emptyText:SetPoint("RIGHT", editor, "RIGHT")
emptyText:SetJustifyH("LEFT")
emptyText:SetText("Noch keine Vorlage.\n\n„Neue Vorlage“ übernimmt Instanz und Regeln der aktiven Sitzung. "
    .. "„Sitzung anlegen“ erstellt die Sitzung für den nächsten Termin. Mit „Aktiv“ legt das Addon danach jeden "
    .. "folgenden Termin selbst an (im Spiel jede Minute geprüft, höchstens 7 Tage im Voraus). Die aktive "
    .. "Sitzung der Gruppe wird dabei nicht gewechselt.")

local function label(text, anchor, offsetY)
    local fs = UI.CreateText(editor, anchor, offsetY, "GameFontNormal")
    fs:SetWidth(LABEL_WIDTH)
    fs:SetText(text)
    if not anchor then
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", editor, "TOPLEFT", 0, -6)
    end
    return fs
end

local function dropdown(anchor, width)
    local dd = CreateFrame("DropdownButton", nil, editor, "WowStyle1DropdownTemplate")
    dd:SetWidth(width)
    dd:SetPoint("LEFT", anchor, "RIGHT", 0, 0)
    return dd
end

-- Name
local nameLabel = label("Name:")
local nameBox = CreateFrame("EditBox", nil, editor, "InputBoxTemplate")
nameBox:SetSize(200, 20)
nameBox:SetPoint("LEFT", nameLabel, "RIGHT", 6, 0)
nameBox:SetAutoFocus(false)
nameBox:SetMaxLetters(30)
local function saveName(self)
    local name = strtrim((self:GetText() or ""):gsub("[%^;=,|]", "") or "")
    local t = selected()
    if t and name ~= "" and name ~= t.name then
        update({ name = name })
    elseif t then
        self:SetText(t.name)
    end
end
nameBox:SetScript("OnEnterPressed", function(self)
    saveName(self)
    self:ClearFocus()
end)
nameBox:SetScript("OnEditFocusLost", saveName)
nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

-- Instanz
local instanceLabel = label("Instanz:", nameLabel, -18)
local instanceDropdown = dropdown(instanceLabel, 220)
instanceDropdown:SetDefaultText("Instanz wählen")
instanceDropdown:SetupMenu(function(_, root)
    local lastIsRaid
    for _, instance in ipairs(ns.LootData:GetInstances()) do
        if instance.isRaid ~= lastIsRaid then
            root:CreateTitle(instance.isRaid and "Raids" or "Dungeons")
            lastIsRaid = instance.isRaid
        end
        root:CreateRadio(instance.name,
            function(value) local t = selected() return t ~= nil and t.instanceKey == value.fullKey end,
            function(value) update({ instanceKey = value.fullKey, instanceName = value.name }) end,
            instance)
    end
end)

-- Max. SRs + doppelte Items
local maxLabel = label("Max. SRs:", instanceLabel, -18)
local maxDropdown = dropdown(maxLabel, 70)
maxDropdown:SetupMenu(function(_, root)
    for n = 1, ns.Session.MAX_RESERVES_LIMIT do
        root:CreateRadio(tostring(n),
            function(value) local t = selected() return t ~= nil and t.maxReserves == value end,
            function(value) update({ maxReserves = value }) end, n)
    end
end)

local duplicatesCheck = CreateFrame("CheckButton", nil, editor, "UICheckButtonTemplate")
duplicatesCheck:SetPoint("LEFT", maxDropdown, "RIGHT", 10, 0)
duplicatesCheck.Text:SetText("Mehrfach erlaubt")
duplicatesCheck.Text:SetFontObject("GameFontHighlight")
duplicatesCheck:SetScript("OnClick", function(self) update({ allowDuplicates = self:GetChecked() and true or false }) end)

-- Termin: Wochentag + Uhrzeit
local dayLabel = label("Termin:", maxLabel, -18)
local dayDropdown = dropdown(dayLabel, 130)
dayDropdown:SetupMenu(function(_, root)
    for i = 1, 7 do
        local weekday = i % 7 -- Montag zuerst
        root:CreateRadio(Templates.WEEKDAYS[weekday],
            function(value) local t = selected() return t ~= nil and t.weekday == value end,
            function(value) update({ weekday = value }) end, weekday)
    end
end)

local timeDropdown = CreateFrame("DropdownButton", nil, editor, "WowStyle1DropdownTemplate")
timeDropdown:SetWidth(90)
timeDropdown:SetPoint("LEFT", dayDropdown, "RIGHT", 8, 0)
timeDropdown:SetupMenu(function(_, root)
    root:SetScrollMode(260)
    for minutes = 0, 23 * 60 + 30, 30 do
        root:CreateRadio(string.format("%02d:%02d", math.floor(minutes / 60), minutes % 60),
            function(value) local t = selected() return t ~= nil and t.hour * 60 + t.minute == value end,
            function(value) update({ hour = math.floor(value / 60), minute = value % 60 }) end, minutes)
    end
end)

-- Anmeldeschluss relativ zum Termin
local deadlineLabel = label("Anmeldeschluss:", dayLabel, -18)
local deadlineDropdown = dropdown(deadlineLabel, 180)
deadlineDropdown:SetupMenu(function(_, root)
    for _, hours in ipairs(Templates.DEADLINE_HOURS) do
        local text
        if hours < 0 then
            text = "Kein Anmeldeschluss"
        elseif hours == 0 then
            text = "Bei Raidbeginn"
        else
            text = Templates.HoursText(hours) .. " vor dem Raid"
        end
        root:CreateRadio(text,
            function(value)
                local t = selected()
                return t ~= nil and (t.deadlineHours or Templates.DEADLINE_NONE) == value
            end,
            function(value) update({ deadlineHours = value }) end, hours)
    end
end)

-- Zeitpunkt für den Folgetermin (Automatik): so viele Stunden nach Raidbeginn
local createAfterLabel = label("Folgetermin:", deadlineLabel, -18)
local createAfterDropdown = dropdown(createAfterLabel, 220)
createAfterDropdown:SetupMenu(function(_, root)
    root:SetScrollMode(260)
    for _, hours in ipairs(Templates.CREATE_AFTER_HOURS) do
        root:CreateRadio(hours == 0 and "bei Raidbeginn anlegen"
            or (Templates.HoursText(hours) .. " nach Raidbeginn anlegen"),
            function(value) local t = selected() return t ~= nil and Templates.CreateAfterHours(t) == value end,
            function(value) update({ createAfterHours = value }) end, hours)
    end
end)
createAfterDropdown:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Folgetermin anlegen")
    GameTooltip:AddLine("Mit „Aktiv“ legt das Addon die Sitzung für die nächste Woche so viele Stunden nach "
        .. "Beginn des letzten Raids an. War die vergangene Sitzung aktiv, wird die neue aktiv (nicht in einer "
        .. "Gruppe).", 1, 1, 1, true)
    GameTooltip:Show()
end)
createAfterDropdown:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Veröffentlichen + aktiv
local publishCheck = CreateFrame("CheckButton", nil, editor, "UICheckButtonTemplate")
publishCheck:SetPoint("TOPLEFT", createAfterLabel, "BOTTOMLEFT", -4, -14)
publishCheck.Text:SetText("Für die Gilde veröffentlichen")
publishCheck.Text:SetFontObject("GameFontHighlight")
publishCheck:SetScript("OnClick", function(self) update({ publish = self:GetChecked() and true or false }) end)

local enabledCheck = CreateFrame("CheckButton", nil, editor, "UICheckButtonTemplate")
enabledCheck:SetPoint("TOPLEFT", publishCheck, "BOTTOMLEFT", 0, -2)
enabledCheck.Text:SetText("Aktiv: künftige Termine automatisch anlegen")
enabledCheck.Text:SetFontObject("GameFontHighlight")
enabledCheck:SetScript("OnClick", function(self) update({ enabled = self:GetChecked() and true or false }) end)

local nextText = UI.CreateText(editor, enabledCheck, -12, "GameFontHighlightSmall")
nextText:SetPoint("RIGHT", editor, "RIGHT")
nextText:SetJustifyH("LEFT")

local deleteButton = UI.CreateButton(editor, "Vorlage löschen", 140, function()
    local t = selected()
    if not t then return end
    UI.Confirm("Vorlage „" .. t.name .. "“ löschen?\nBereits angelegte Sitzungen bleiben erhalten.", function()
        Templates:Delete(t)
        selectedID = nil
        refresh()
    end)
end)
deleteButton:SetPoint("BOTTOMLEFT", editor, "BOTTOMLEFT", 0, 0)

-- Ohne kommende Sitzung: „Sitzung anlegen“ (erstmalig oder erneut nach dem Löschen).
-- Mit kommender Sitzung: „Aktualisieren“ – aktiv, sobald Vorlage und Sitzung voneinander abweichen.
local sessionButton = UI.CreateButton(editor, "Sitzung anlegen", 150, function()
    local t = selected()
    if not t then return end
    local s = Templates:GetUpcomingSession(t)
    if not s then
        local ok, err = Templates:CreateNow(t)
        if not ok then
            ns.Print("Keine Sitzung angelegt: " .. (err or "?"))
        end
        return
    end
    local function apply()
        local ok, err = Templates:UpdateSession(t)
        if not ok then
            ns.Print("Nicht aktualisiert: " .. (err or "?"))
        end
    end
    -- Instanzwechsel verwirft die Reserves der Sitzung
    UI.Confirm("Die Instanz der Sitzung ändert sich.\nAlle bisherigen Reserves werden verworfen.", apply,
        t.instanceKey ~= s.instanceKey and next(s.reserves) ~= nil)
end)
sessionButton:SetPoint("LEFT", deleteButton, "RIGHT", 8, 0)
sessionButton:SetScript("OnEnter", function(self)
    local t = selected()
    local s = t and Templates:GetUpcomingSession(t)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    if s then
        GameTooltip:SetText("Sitzung aktualisieren")
        local diffs = Templates:Differences(t, s)
        GameTooltip:AddLine(#diffs > 0 and ("Überträgt die Änderungen der Vorlage auf „" .. s.name .. "“: "
            .. table.concat(diffs, ", ")) or "Die Sitzung entspricht der Vorlage.", 1, 1, 1, true)
    else
        GameTooltip:SetText("Sitzung anlegen")
        GameTooltip:AddLine("Legt die Sitzung für den nächsten Termin jetzt an – auch erneut, falls sie gelöscht "
            .. "wurde. Unabhängig von „Aktiv“.", 1, 1, 1, true)
    end
    GameTooltip:Show()
end)
sessionButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Aktualisieren -----------------------------------------------------------------------

function refresh()
    if not frame:IsShown() then return end
    local templates = Templates:List()
    if not selected() then
        selectedID = templates[1] and templates[1].id
    end
    list:SetDataProvider(CreateDataProvider(templates), ScrollBoxConstants.RetainScrollPosition)

    local t = selected()
    editor:SetShown(t ~= nil)
    emptyText:SetShown(t == nil)
    if not t then return end

    if not nameBox:HasFocus() then
        nameBox:SetText(t.name or "")
        nameBox:SetCursorPosition(0)
    end
    duplicatesCheck:SetChecked(t.allowDuplicates)
    publishCheck:SetShown(IsInGuild and IsInGuild() or false)
    publishCheck:SetChecked(t.publish)
    enabledCheck:SetChecked(t.enabled)
    -- Auswahltext neu auswerten; kein GenerateMenu, da refresh auch aus einer Menü-Antwort kommt
    for _, dd in ipairs({ instanceDropdown, maxDropdown, dayDropdown, timeDropdown, deadlineDropdown,
        createAfterDropdown }) do
        dd:SignalUpdate()
    end

    local raidAt = Templates:NextOccurrence(t)
    local upcoming = Templates:GetUpcomingSession(t)
    local diffs = upcoming and Templates:Differences(t, upcoming) or {}
    if upcoming then
        sessionButton:SetText("Aktualisieren")
        sessionButton:SetEnabled(t.instanceKey ~= nil and #diffs > 0)
    else
        sessionButton:SetText("Sitzung anlegen")
        sessionButton:SetEnabled(t.instanceKey ~= nil and raidAt ~= nil)
    end
    local text
    if not t.instanceKey then
        text = "|cffff6060Erst eine Instanz wählen.|r"
    elseif upcoming and #diffs > 0 then
        text = "Sitzung „" .. upcoming.name .. "“ – |cffffd100weicht ab (" .. table.concat(diffs, ", ")
            .. ").|r Mit „Aktualisieren“ übernehmen."
    elseif upcoming then
        text = "Sitzung „" .. upcoming.name .. "“ – |cff60ff60entspricht der Vorlage.|r"
    elseif raidAt then
        text = "Nächster Termin: " .. UI.FormatDate(raidAt) .. " – "
        if (t.createdUpTo or 0) >= raidAt then
            -- Für diesen Termin wurde schon einmal angelegt, die Sitzung existiert aber nicht mehr
            text = text .. "|cffffd100die Sitzung für diesen Termin wurde gelöscht|r und wird nicht automatisch "
                .. "neu angelegt. Mit „Sitzung anlegen“ neu erstellen."
        elseif t.enabled and t.createdUpTo then
            local due = t.createdUpTo + Templates.CreateAfterHours(t) * 3600
            text = text .. "noch keine Sitzung. Wird automatisch angelegt"
                .. (due > GetServerTime() and (" ab " .. UI.FormatDate(due) .. ".") or ".")
        else
            text = text .. "noch keine Sitzung. Mit „Sitzung anlegen“ erstellen."
        end
    end
    local auto
    if not t.enabled then
        auto = "Automatik aus: Sitzungen nur über „Sitzung anlegen“."
    elseif t.createdUpTo then
        auto = "Automatik an: jeder folgende Termin wird automatisch angelegt."
    else
        auto = "Automatik an: startet, sobald die erste Sitzung mit „Sitzung anlegen“ erstellt ist."
    end
    nextText:SetText((text or "") .. "\n" .. auto .. "\n\n" .. Templates:Describe(t))
end

frame:SetScript("OnShow", refresh)
ns:On("TEMPLATES_CHANGED", function() refresh() end)
ns:On("SESSION_CHANGED", function() refresh() end)

function ns.ShowTemplates()
    frame:Show()
    frame:Raise()
end
