-- Fenster für Würfelrunden:
--   Popup für alle Spieler: Kategorie wählen und würfeln
--   Leitfenster für den Raidlead: Würfe live verfolgen, Runde beenden oder abbrechen
local _, ns = ...

local UI = ns.UI
local Rolls = ns.Rolls

local CATEGORY_COLOR = {
    SR = "ff40ff40",
    MS = "ffffffff",
    OS = "ffa0c8ff",
    TM = "ffd0a0ff",
    PASS = "ff808080",
    NOSR = "ff808080",
}

local function colored(category)
    return "|c" .. (CATEGORY_COLOR[category] or "ffffffff") .. (Rolls.LABEL[category] or category or "?") .. "|r"
end

local function resultText(result)
    if not result then return "" end
    if result.winner then
        return string.format("Gewinner: |cffffd100%s|r (%s, %d)", UI.ShortName(result.winner),
            colored(result.category), result.roll or 0)
    elseif result.category == "TIE" then
        return "|cffff6060Gleichstand – der Raidlead startet eine neue Runde.|r"
    end
    return "Niemand hat gewürfelt."
end

-- Restzeit einer Runde als Text ("" ohne Zeitfenster)
local function remainingText(round)
    if not round or not round.endsAt or round.result or round.ended then return "" end
    local left = math.max(0, math.ceil(round.endsAt - GetTime()))
    local color = left <= 5 and "ffff6060" or "ffffd100"
    return string.format("|c%snoch %d s|r", color, left)
end

local function makeMovable(frame)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
end

local function createItemHeader(frame)
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(36, 36)
    icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -32)
    local name = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -2)
    name:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    local info = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    info:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 8, 2)
    info:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
    info:SetJustifyH("LEFT")
    info:SetWordWrap(false)

    -- Tooltip über dem Icon
    local hover = CreateFrame("Frame", nil, frame)
    hover:SetAllPoints(icon)
    hover:SetScript("OnEnter", function(self)
        if frame.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(frame.itemID)
            GameTooltip:Show()
        end
    end)
    hover:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return icon, name, info
end

local function holdersText(round)
    if not round.restricted then
        if round.freeReason then
            return "Freier Wurf (" .. round.freeReason .. ")"
        end
        return "Offene Runde: Mainspec > Secondspec > Transmog"
    end
    local names = {}
    for player in pairs(round.holders) do
        table.insert(names, UI.ShortName(player))
    end
    table.sort(names)
    if round.category == "SR" then
        return "Nur SR: " .. table.concat(names, ", ")
    end
    return "Nachwurf (" .. (Rolls.LABEL[round.category] or "?") .. "): " .. table.concat(names, ", ")
end

-- Popup für alle -----------------------------------------------------------------------

local popup = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
popup:SetSize(390, 150)
popup:SetPoint("TOP", UIParent, "TOP", 0, -140)
popup:SetFrameStrata("DIALOG")
popup.TitleText:SetText("Würfelrunde")
makeMovable(popup)
popup:Hide()

local popupIcon, popupName, popupInfo = createItemHeader(popup)
local popupStatus = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
popupStatus:SetPoint("TOPLEFT", popupIcon, "BOTTOMLEFT", 0, -10)
popupStatus:SetPoint("RIGHT", popup, "RIGHT", -12, 0)
popupStatus:SetJustifyH("LEFT")

local popupTime = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
popupTime:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -12, -32)

-- Restzeit sekündlich aktualisieren, solange eine Runde mit Zeitfenster läuft
local popupTicker
local function updatePopupTime()
    local round = Rolls:GetActiveRound()
    local text = remainingText(round)
    popupTime:SetText(text)
    if text == "" and popupTicker then
        popupTicker:Cancel()
        popupTicker = nil
    end
end

local dismissedRoundID -- vom Spieler geschlossene Runde

popup.CloseButton:HookScript("OnClick", function()
    local round = Rolls:GetActiveRound()
    dismissedRoundID = round and round.id
end)

local popupButtons = {}
local function createPopupButton(category, text)
    local button = UI.CreateButton(popup, text, 88, function()
        Rolls:Declare(category)
    end)
    button:SetHeight(22)
    popupButtons[category] = button
    return button
end

createPopupButton("SR", "SR würfeln")
-- Nachwurf: würfelt in der Kategorie der Runde
local rerollButton = UI.CreateButton(popup, "Würfeln", 88, function()
    local round = Rolls:GetActiveRound()
    if round and round.category then
        Rolls:Declare(round.category)
    end
end)
rerollButton:SetHeight(22)
popupButtons.ROLL = rerollButton
createPopupButton("MS", "Main (100)")
createPopupButton("OS", "Second (50)")
createPopupButton("TM", "Transmog (25)")
createPopupButton("PASS", "Passen")

local function layoutButtons(categories)
    for _, button in pairs(popupButtons) do
        button:Hide()
    end
    local previous
    for _, category in ipairs(categories) do
        local button = popupButtons[category]
        button:ClearAllPoints()
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else
            button:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 12, 10)
        end
        button:Show()
        button:Enable()
        previous = button
    end
end

local refreshPopup
local onPopupItemLoaded = UI.Debounce(function() refreshPopup() end)

function refreshPopup()
    local round = Rolls:GetActiveRound()
    -- Runde beendet: Popup schließt sofort (Gewinner steht im Chat und im Loot-Panel)
    if not round or round.id == dismissedRoundID or round.result then
        popup:Hide()
        return
    end
    popup.itemID = round.itemID
    local name, icon = UI.GetItemDisplay(round.itemID, onPopupItemLoaded)
    popupIcon:SetTexture(icon)
    popupName:SetText(ns.Wishlist:Has(round.itemID) and (ns.Wishlist.Icon() .. " " .. name) or name)
    popupInfo:SetText(holdersText(round))
    popupName:SetPoint("RIGHT", popup, "RIGHT", round.endsAt and -70 or -12, 0)
    updatePopupTime()
    if round.endsAt and not round.result and not popupTicker then
        popupTicker = C_Timer.NewTicker(1, updatePopupTime)
    end

    if round.declared then
        layoutButtons({})
        popupStatus:SetText("Deine Wahl: " .. colored(round.declared) .. " – warte auf das Ergebnis …")
    elseif round.restricted then
        if not Rolls:CanRollRestricted() then
            layoutButtons({})
            popupStatus:SetText("|cff999999Du bist in dieser Runde nicht berechtigt.|r")
        elseif round.category == "SR" then
            layoutButtons({ "SR", "PASS" })
            popupStatus:SetText("Du hast dieses Item reserviert.")
        else
            layoutButtons({ "ROLL", "PASS" })
            popupStatus:SetText("Nachwurf wegen Gleichstand.")
        end
    else
        layoutButtons({ "MS", "OS", "TM", "PASS" })
        popupStatus:SetText("Wähle deine Kategorie:")
    end
    popup:Show()
end

-- Leitfenster für den Raidlead ------------------------------------------------------------

local ROW_HEIGHT = 20

local leadFrame = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
leadFrame:SetSize(340, 340)
leadFrame:SetPoint("RIGHT", UIParent, "RIGHT", -220, 40)
leadFrame:SetFrameStrata("HIGH")
leadFrame.TitleText:SetText("Würfelrunde – Raidlead")
makeMovable(leadFrame)
leadFrame:Hide()

local leadIcon, leadName, leadInfo = createItemHeader(leadFrame)
local leadTimer = leadFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
leadTimer:SetPoint("TOPLEFT", leadIcon, "BOTTOMLEFT", 0, -8)
local leadResult = leadFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
leadResult:SetPoint("BOTTOMLEFT", leadFrame, "BOTTOMLEFT", 14, 40)
leadResult:SetPoint("RIGHT", leadFrame, "RIGHT", -12, 0)
leadResult:SetJustifyH("LEFT")

-- Manuelle Runde: Klick auf einen Spieler mit Wurf wählt ihn (nach Rückfrage) als Gewinner
local function onStandingClick(row)
    local data = row.data
    if not data or not data.roll or not Rolls:CanChooseWinner() then return end
    local round = Rolls:GetLeadRound()
    local itemName = round and UI.GetItemDisplay(round.itemID) or "?"
    UI.Confirm(string.format("%s gewinnt %s?\n%s, Wurf %d", UI.ShortName(data.player), itemName,
        Rolls.LABEL[data.category] or data.category or "?", data.roll), function()
        Rolls:ChooseWinner(data.player)
    end)
end

local function initStandingRow(row, data)
    if not row.name then
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints()
        row.highlight:SetColorTexture(1, 1, 1, 0.1)
        row:SetScript("OnClick", onStandingClick)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.name:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.name:SetWidth(140)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.category = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.category:SetPoint("LEFT", row.name, "RIGHT", 4, 0)
        row.roll = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.roll:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    end
    row.data = data
    -- Hervorhebung beim Überfahren nur, wenn der Spieler wählbar ist
    row.highlight:SetShown(data.roll ~= nil and Rolls:CanChooseWinner())
    row.name:SetText(UI.ShortName(data.player))
    row.category:SetText(colored(data.category))
    -- Wurf mit Bereich, z. B. "37 / 50"
    row.roll:SetText(data.roll and (data.roll .. " |cff999999/ " .. (data.max or 100) .. "|r") or "|cff808080–|r")
    if data.isWinner then
        row.bg:SetColorTexture(1, 0.82, 0, 0.2)
    else
        row.bg:SetColorTexture(0, 0, 0, 0)
    end
end

local standingsList = UI.CreateScrollList(leadFrame, ROW_HEIGHT, initStandingRow)
standingsList:SetPoint("TOPLEFT", leadTimer, "BOTTOMLEFT", 0, -8)
standingsList:SetPoint("BOTTOMRIGHT", leadFrame, "BOTTOMRIGHT", -30, 62)

local endButton = UI.CreateButton(leadFrame, "Beenden", 100, function() Rolls:End() end)
endButton:SetPoint("BOTTOMLEFT", leadFrame, "BOTTOMLEFT", 12, 10)
local cancelButton = UI.CreateButton(leadFrame, "Abbrechen", 100, function() Rolls:Cancel() end)
cancelButton:SetPoint("LEFT", endButton, "RIGHT", 6, 0)
local closeButton = UI.CreateButton(leadFrame, "Schließen", 100, function() Rolls:Dismiss() end)
closeButton:SetPoint("BOTTOMRIGHT", leadFrame, "BOTTOMRIGHT", -12, 10)
local rerollLeadButton = UI.CreateButton(leadFrame, "Nachwurf", 100, function() Rolls:Reroll() end)
rerollLeadButton:SetPoint("BOTTOMLEFT", leadFrame, "BOTTOMLEFT", 12, 10)

-- X: eine beendete Runde gilt damit als erledigt; eine laufende Runde bleibt bestehen
leadFrame.CloseButton:HookScript("OnClick", function()
    local round = Rolls:GetLeadRound()
    if round and round.ended then
        Rolls:Dismiss()
    elseif round then
        ns.Print("Die Würfelrunde läuft weiter. „Würfeln“ im Loot-Panel zeigt das Fenster wieder.")
    end
end)

local ticker

local function updateTimer()
    local round = Rolls:GetLeadRound()
    if not round then return end
    local count = 0
    for _, entry in pairs(round.rolls) do
        if entry.roll then count = count + 1 end
    end
    if round.choosing and not round.ended then
        leadTimer:SetText(string.format("Würfe geschlossen – %d Würfe", count))
    elseif round.endsAt and not round.ended then
        leadTimer:SetText(string.format("%s – %d Würfe (endet automatisch)", remainingText(round), count))
    else
        local elapsed = math.floor(GetTime() - round.startedAt)
        leadTimer:SetText(string.format("Laufzeit %d:%02d – %d Würfe", math.floor(elapsed / 60), elapsed % 60, count))
    end
end

local refreshLead
local onLeadItemLoaded = UI.Debounce(function() refreshLead() end)

function refreshLead()
    local round = Rolls:GetLeadRound()
    if not round then
        leadFrame:Hide()
        if ticker then ticker:Cancel() ticker = nil end
        return
    end
    leadFrame.itemID = round.itemID
    local name, icon = UI.GetItemDisplay(round.itemID, onLeadItemLoaded)
    leadIcon:SetTexture(icon)
    leadName:SetText(name)
    leadInfo:SetText(holdersText(round))

    local standings = Rolls:GetStandings()
    local winner, tie = Rolls:GetWinner()
    for _, entry in ipairs(standings) do
        entry.isWinner = winner ~= nil and entry.player == winner.player
    end
    standingsList:SetDataProvider(CreateDataProvider(standings), ScrollBoxConstants.RetainScrollPosition)

    local choosing = Rolls:IsChoosing()
    endButton:SetShown(not round.ended and not choosing)
    endButton:SetText(round.manual and "Würfeln beenden" or "Beenden")
    cancelButton:SetShown(not round.ended)
    closeButton:SetShown(round.ended == true)
    rerollLeadButton:SetShown(round.ended == true and round.tied ~= nil)
    if round.ended then
        leadResult:SetText(resultText(round.result))
        if ticker then ticker:Cancel() ticker = nil end
    elseif choosing then
        leadResult:SetText("|cffffd100Würfeln beendet – Klick auf einen Spieler wählt den Gewinner.|r")
        if ticker then ticker:Cancel() ticker = nil end
    else
        if round.manual then
            leadResult:SetText("|cff999999Gewinner manuell: Klick auf einen Spieler wählt ihn.|r"
                .. (tie and "  |cffff6060Gleichstand|r" or ""))
        else
            leadResult:SetText(tie and "|cffff6060Gleichstand an der Spitze|r" or "")
        end
        if not ticker then
            ticker = C_Timer.NewTicker(1, updateTimer)
        end
    end
    updateTimer()
    leadFrame:Show()
end

ns:On("ROLL_CHANGED", function()
    refreshPopup()
    refreshLead()
end)
