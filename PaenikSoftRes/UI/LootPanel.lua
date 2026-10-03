-- Zwei Fenster über die gelooteten Items der Sitzung (session.lootList, Einträge { itemID, lootKey }):
--  • „Soft Reserves“: nur die Items der zuletzt gelooteten Leiche (session.currentCorpse). Lootet der Raidlead,
--    öffnet es sich bei allen (Einstellung db.lootPanel) – jeder sieht Drops und SRs; der Raidlead würfelt direkt
--    oder lootet die Items für später. Bleibt offen, bis es geschlossen wird. /psr loot, Shift-Klick Minimap.
--  • „Beute“: alle gelooteten Items der Sitzung; verrollte sind markiert (oder ausgeblendet). Von hier startet der
--    Raidlead Würfelrunden für Items im Inventar; Items aus den Taschen lassen sich hineinziehen. /psr beute,
--    Knopf in der Übersicht.
-- Die Liste geht über die Nachricht L an die Gruppe (Comm.lua); Raider sehen beide Fenster nur lesend.
local _, ns = ...

local UI = ns.UI

local ROW_HEIGHT = 34
local WIDTH = 380
local MAX_ROWS = 8
local TOP = 44       -- Titelleiste + Infozeile
local TOOLBAR = 40   -- Knopfleiste
local UNCOMMON = 2 -- Qualität „Ungewöhnlich“ (fester Wert, siehe ns.LOOT_QUALITIES in Core.lua)

-- Loot ab Qualität (Einstellung db.lootMinQuality, Liste ns.LOOT_QUALITIES in Core.lua)
local function minQuality()
    return ns.db and ns.db.lootMinQuality or UNCOMMON
end

-- Anzeige: Items unter der Qualität ausblenden; selbst hineingezogene Taschen-Items immer zeigen,
-- Items ohne bekannte Qualität (noch nicht geladen) ebenfalls
local function qualityShown(entry)
    if ns.Session.LootCorpse(entry.lootKey) == "bag" then return true end
    local quality = C_Item.GetItemQualityByID(entry.itemID)
    return quality == nil or quality >= minQuality()
end

-- Darf dieser Spieler die Liste bearbeiten und verrollen? Der Verteiler (Raidlead bzw. bei Plündermeister-
-- Verteilung der Plündermeister, wie im Spiel), sofern er die Sitzung hat (eigene oder Gruppen-Spiegel).
local function canEdit()
    return ns.Session:Get() ~= nil and ns.Roles:IsDistributor()
end

-- „ – X verteilt“ für Raider (bei Plündermeister-Verteilung der Plündermeister)
local function distributorText()
    local distributor = ns.Roles:GetDistributor()
    return distributor and (" – " .. UI.ShortName(distributor) .. " verteilt") or " – der Raidlead verteilt"
end

local function notifyChanged(open)
    ns:Fire("SESSION_LOOT_CHANGED", open)
end

local function itemLink(itemID)
    local _, link = C_Item.GetItemInfo(itemID)
    return link or ("item:" .. itemID)
end

local function isRolled(entry)
    return #ns.Rolls:GetAwards(entry.lootKey) > 0
end

-- Items aus den Taschen (Cursor) aufnehmen (Beute-Fenster)
local bagCounter = 0

local function addFromCursor()
    local infoType, itemID = GetCursorInfo()
    if infoType ~= "item" or not itemID then return end
    ClearCursor()
    if not canEdit() then
        ns.Print("Nur der Verteiler (Raidlead bzw. Plündermeister) kann Items zur Beute hinzufügen.")
        return
    end
    bagCounter = bagCounter + 1
    local key = string.format("bag:%d:%d:%d", itemID, GetServerTime(), bagCounter)
    if ns.Session:AddLootEntries(ns.Session:Get(), { { itemID = itemID, lootKey = key } }) > 0 then
        notifyChanged(false)
    end
end

-- Plündermeister: Item der offenen Leiche direkt dem Gewinner zuteilen --------------------------
-- (GiveMasterLoot/GetMasterLootCandidate, in Forever vorhanden; mit /psr probe prüfbar)

-- Slot des Eintrags in der gerade offenen Leiche (nil: Leiche zu oder Item schon weg)
local function corpseSlot(entry)
    if type(GetLootSourceInfo) ~= "function" or GetNumLootItems() == 0 then return nil end
    local corpse = ns.Session.LootCorpse(entry.lootKey)
    local wanted = tonumber(entry.lootKey:match(":(%d+)$")) or 1
    local count, last = 0, nil
    for slot = 1, GetNumLootItems() do
        local link = GetLootSlotLink(slot)
        local guid = GetLootSourceInfo(slot)
        if link and not ns.IsSecret(link) and not ns.IsSecret(guid) and guid == corpse
            and C_Item.GetItemInfoInstant(link) == entry.itemID then
            count = count + 1
            last = slot
            if count >= wanted then
                return slot
            end
        end
    end
    -- gleiches Item schon teilweise verteilt: das verbleibende nehmen
    return last
end

-- Bin ich Plündermeister für diesen Slot? (dann gibt es Kandidaten)
local function canMasterLoot(slot)
    if not slot or type(GetMasterLootCandidate) ~= "function" or type(GiveMasterLoot) ~= "function" then
        return false
    end
    local first = GetMasterLootCandidate(slot, 1)
    return first ~= nil and not ns.IsSecret(first)
end

local function giveToWinner(entry, award)
    local slot = corpseSlot(entry)
    if not canMasterLoot(slot) then
        ns.Print("Das Item liegt nicht mehr in der offenen Leiche.")
        return
    end
    for index = 1, 40 do
        local name = GetMasterLootCandidate(slot, index)
        if name and not ns.IsSecret(name) and ns.ResolvePlayerName(name) == award.winner then
            UI.Confirm(string.format("%s an %s zuteilen?", (UI.GetItemDisplay(entry.itemID)),
                UI.ShortName(award.winner)), function()
                -- Slot erneut bestimmen: die Leiche kann sich inzwischen geändert haben
                local current = corpseSlot(entry)
                if current then
                    GiveMasterLoot(current, index)
                    award.traded = true
                    award.tradedAt = GetServerTime()
                    ns.Debug("Loot", "Zugeteilt", entry.itemID, award.winner)
                    ns:Fire("SESSION_CHANGED")
                end
            end)
            return
        end
    end
    ns.Print(UI.ShortName(award.winner) .. " kann das Item nicht erhalten (nicht in Reichweite oder nicht "
        .. "berechtigt).")
end

-- Zeilen (für beide Fenster gleich) --------------------------------------------------------

local function showRowMenu(row)
    local entry = row.entry
    if not entry or not canEdit() then return end
    MenuUtil.CreateContextMenu(row, function(_, root)
        root:CreateTitle(UI.StripColors((UI.GetItemDisplay(entry.itemID))))
        root:CreateButton("Verrollen (Würfelrunde starten)", function()
            ns.Rolls:StartChecked(entry.itemID, itemLink(entry.itemID), entry.lootKey)
        end)
        root:CreateButton("Aus der Beute entfernen", function()
            if ns.Session:RemoveLootEntry(ns.Session:Get(), entry.lootKey) then
                notifyChanged(false)
            end
        end)
    end)
end

local function initRow(row, entry)
    if not row.icon then
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(ROW_HEIGHT - 6, ROW_HEIGHT - 6)
        row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.roll = UI.CreateButton(row, "Verrollen", 76, function(self)
            local parent = self:GetParent()
            local e = parent.entry
            if not e then return end
            if parent.award and parent.canAssign then
                giveToWinner(e, parent.award) -- Plündermeister: dem Gewinner zuteilen
            else
                ns.Rolls:StartChecked(e.itemID, itemLink(e.itemID), e.lootKey)
            end
        end)
        row.roll:SetHeight(20)
        row.roll:SetScript("OnEnter", function(self)
            local parent = self:GetParent()
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            if parent.award and parent.canAssign then
                GameTooltip:SetText("Zuteilen")
                GameTooltip:AddLine("Gibt das Item als Plündermeister direkt an den Gewinner.", 1, 1, 1, true)
            else
                GameTooltip:SetText(parent.award and "Erneut verrollen" or "Verrollen")
                GameTooltip:AddLine("Startet eine Würfelrunde für die Gruppe um dieses Item (Ansage im Chat). "
                    .. "Du würfelst dabei nicht selbst.", 1, 1, 1, true)
            end
            GameTooltip:Show()
        end)
        row.roll:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
        row:RegisterForClicks("RightButtonUp")
        row:SetScript("OnClick", showRowMenu)
        row:SetScript("OnEnter", function(self)
            if not self.entry then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(itemLink(self.entry.itemID))
            if canEdit() then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Rechtsklick: verrollen oder aus der Beute entfernen", 0.6, 0.8, 1)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    row.entry = entry
    row:SetScript("OnReceiveDrag", row.acceptDrop and addFromCursor or nil)
    local name, icon = UI.GetItemDisplay(entry.itemID)
    row.icon:SetTexture(icon)
    row.name:SetText(ns.Wishlist:Has(entry.itemID) and (ns.Wishlist.Icon() .. " " .. name) or name)
    -- Stand des Items: wird ausgewürfelt > vergeben (letztes Ergebnis) > Hard Reserve > SR-Inhaber
    local awards = ns.Rolls:GetAwards(entry.lootKey)
    local award = awards[#awards]
    local hr = ns.Session:GetHardReserve(entry.itemID)
    -- Entschieden, Item liegt noch in der offenen Leiche und ich bin Plündermeister: „Zuteilen“
    row.award = award
    row.canAssign = award ~= nil and award.winner ~= nil and not award.traded and canMasterLoot(corpseSlot(entry))
    if ns.Rolls:IsRolling(entry.itemID, entry.lootKey) then
        row.holders:SetText("|cffffd100wird ausgewürfelt …|r")
        row.bg:SetColorTexture(1, 0.82, 0, 0.12)
        row.roll:SetText("Verrollen")
    elseif award then
        row.holders:SetText(string.format("|cff40ff40Verrollt:|r %s (%s, %d)%s", UI.ShortName(award.winner or "?"),
            ns.Rolls.LABEL[award.category] or award.category or "?", award.roll or 0,
            award.traded and "  |cff60ff60übergeben|r" or ""))
        row.bg:SetColorTexture(0.1, 0.6, 0.1, 0.2)
        row.roll:SetText(row.canAssign and "Zuteilen" or "Erneut")
    elseif hr then
        row.holders:SetText("|cffff5050HR: " .. (hr.note ~= "" and hr.note or "fest vergeben") .. "|r")
        row.bg:SetColorTexture(0.6, 0.1, 0.1, 0.2)
        row.roll:SetText("Verrollen")
    else
        local holders, total = UI.FormatHolders(entry.itemID)
        if holders then
            row.holders:SetText(string.format("|cffffd100SR (%d):|r %s", total, holders))
        else
            row.holders:SetText("|cff808080kein SR – freier Wurf|r")
        end
        row.bg:SetColorTexture(0, 0, 0, 0)
        row.roll:SetText("Verrollen")
    end
    row.roll:SetShown(canEdit())
end

-- Fenster-Vorlage -------------------------------------------------------------------------
-- config = { title, posKey (db-Feld der Position), entries(s) → Liste, info(s, entries, editable) → Text,
--            empty(editable) → Text, acceptDrop (Taschen-Items annehmen), toolbar(frame) (nur Raidlead) }
local function createWindow(config)
    local window = {}
    local frame = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(WIDTH, 160)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame.TitleText:SetText(config.title)
    frame:Hide()
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint(1)
        ns.db[config.posKey] = { point = point, relativePoint = relativePoint, x = x, y = y }
    end)
    if config.acceptDrop then
        frame:SetScript("OnReceiveDrag", addFromCursor)
        frame:SetScript("OnMouseUp", function()
            if GetCursorInfo() == "item" then
                addFromCursor()
            end
        end)
    end
    window.frame = frame

    local infoText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    infoText:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -30)
    infoText:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
    infoText:SetJustifyH("LEFT")
    infoText:SetWordWrap(false)

    local emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -TOP - 8)
    emptyText:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
    emptyText:SetJustifyH("LEFT")

    local list = UI.CreateScrollList(frame, ROW_HEIGHT, function(row, entry)
        row.acceptDrop = config.acceptDrop
        initRow(row, entry)
    end)

    local toolbar = CreateFrame("Frame", nil, frame)
    toolbar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 8)
    toolbar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 8)
    toolbar:SetHeight(24)
    if config.toolbar then
        config.toolbar(toolbar, window)
    end

    function window:Anchor()
        frame:ClearAllPoints()
        local pos = ns.db[config.posKey]
        if pos then
            frame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
        elseif config.anchor then
            config.anchor(frame)
        else
            frame:SetPoint("LEFT", UIParent, "CENTER", 120, 0)
        end
    end

    function window:Refresh()
        local s = ns.Session:Get()
        local editable = canEdit()
        local entries = s and config.entries(s) or {}
        local showToolbar = config.toolbar ~= nil and (editable or config.toolbarForAll)
        toolbar:SetShown(showToolbar)
        infoText:SetText(s and config.info(s, entries, editable) or "Keine Sitzung.")
        emptyText:SetShown(#entries == 0)
        emptyText:SetText(config.empty(editable))
        local rows = math.max(1, math.min(#entries, MAX_ROWS))
        list:ClearAllPoints()
        list:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -TOP)
        list:SetPoint("RIGHT", frame, "RIGHT", #entries > MAX_ROWS and -28 or -10, 0)
        list:SetHeight(rows * ROW_HEIGHT)
        list:SetShown(#entries > 0)
        frame:SetHeight(TOP + rows * ROW_HEIGHT + (showToolbar and TOOLBAR or 12))
        list:SetDataProvider(CreateDataProvider(entries), ScrollBoxConstants.RetainScrollPosition)
    end

    function window:Show()
        if not frame:IsShown() then
            self:Anchor()
        end
        self:Refresh()
        frame:Show()
    end

    function window:Toggle()
        if frame:IsShown() then
            frame:Hide()
        else
            self:Show()
        end
    end

    function window:ResetPosition()
        ns.db[config.posKey] = nil
        if frame:IsShown() then
            self:Anchor()
        end
    end

    local refreshIfShown = UI.Debounce(function()
        if frame:IsShown() then
            window:Refresh()
        end
    end)
    for _, event in ipairs({ "SESSION_CHANGED", "ROLL_CHANGED", "ROSTER_CHANGED", "ROLE_CHANGED", "LOOT_QUALITY_CHANGED",
        "DISTRIBUTOR_CHANGED",
        "WISHLIST_CHANGED" }) do
        ns:On(event, refreshIfShown)
    end
    return window
end

-- „Soft Reserves“: Items der zuletzt gelooteten Leiche ------------------------------------------

local softResWindow = createWindow({
    title = "Soft Reserves",
    posKey = "lootPanelPos",
    entries = function(s)
        local result = {}
        for _, entry in ipairs(s.lootList or {}) do
            if s.currentCorpse and ns.Session.LootCorpse(entry.lootKey) == s.currentCorpse and qualityShown(entry) then
                table.insert(result, entry)
            end
        end
        return result
    end,
    info = function(_, entries, editable)
        return #entries .. " Items der letzten Leiche"
            .. (editable and " – verrollen oder für später looten (Beute)" or distributorText())
    end,
    empty = function() return "Noch keine Leiche gelootet." end,
    anchor = function(frame)
        if LootFrame and LootFrame:IsShown() then
            frame:SetPoint("TOPLEFT", LootFrame, "TOPRIGHT", 6, 0)
        else
            frame:SetPoint("LEFT", UIParent, "CENTER", 120, 0)
        end
    end,
})

-- „Beute“: alle gelooteten Items, zum späteren Verrollen aus dem Inventar -------------------------

local hideRolled -- Häkchen „Verrollte ausblenden“ (nur Anzeige, nicht gespeichert)

local beuteWindow = createWindow({
    title = "Beute",
    posKey = "beutePanelPos",
    acceptDrop = true,
    entries = function(s)
        local result = {}
        for _, entry in ipairs(s.lootList or {}) do
            if qualityShown(entry) and not (hideRolled and hideRolled:GetChecked() and isRolled(entry)) then
                table.insert(result, entry)
            end
        end
        return result
    end,
    info = function(s, _, editable)
        local rolled = 0
        for _, entry in ipairs(s.lootList or {}) do
            if isRolled(entry) then rolled = rolled + 1 end
        end
        return string.format("%d Items, %d verrollt%s", #(s.lootList or {}), rolled,
            editable and " – Items aus den Taschen hierher ziehen" or "")
    end,
    empty = function(editable)
        return editable and "Noch keine Beute. Beim Looten kommen die Items der Leiche dazu, oder zieh Items aus "
            .. "den Taschen hierher." or "Noch keine Beute."
    end,
    toolbar = function(bar, window)
        hideRolled = CreateFrame("CheckButton", nil, bar, "UICheckButtonTemplate")
        hideRolled:SetSize(22, 22)
        hideRolled:SetPoint("LEFT", bar, "LEFT", -2, 0)
        hideRolled.Text:SetText("Verrollte ausblenden")
        hideRolled.Text:SetFontObject("GameFontHighlightSmall")
        hideRolled:SetScript("OnClick", function() window:Refresh() end)
        local clearButton = UI.CreateButton(bar, "Liste leeren", 110, function()
            local s = ns.Session:Get()
            UI.Confirm("Beute-Liste leeren?\nWürfel-Ergebnisse im Verlauf bleiben erhalten.", function()
                if ns.Session:ClearLootList(s) then
                    notifyChanged(false)
                end
            end)
        end)
        clearButton:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    end,
})

-- Öffentliche Funktionen ------------------------------------------------------------------

function ns.ShowLootPanel() softResWindow:Show() end
function ns.ToggleLootPanel() softResWindow:Toggle() end
function ns.ToggleBeutePanel() beuteWindow:Toggle() end

function ns.ResetLootPanelPosition()
    softResWindow:ResetPosition()
    beuteWindow:ResetPosition()
end

-- Leiche geöffnet: Raidlead übernimmt ihre Items und zeigt sie (bei allen) im „Soft Reserves“-Fenster
local function readCorpse()
    local entries, seen, corpse = {}, {}, nil
    for slot = 1, GetNumLootItems() do
        local link = GetLootSlotLink(slot)
        if not ns.IsSecret(link) and link then
            local _, _, _, _, quality = GetLootSlotInfo(slot)
            local itemID = C_Item.GetItemInfoInstant(link)
            if itemID and (quality == nil or quality >= minQuality()) then
                -- Leiche + Item (+ laufende Nummer bei gleichen Items) als Schlüssel für das Würfel-Ergebnis
                local guid = type(GetLootSourceInfo) == "function" and GetLootSourceInfo(slot) or nil
                if ns.IsSecret(guid) or not guid then
                    guid = "loot" .. GetServerTime()
                end
                corpse = corpse or guid
                local base = guid .. ":" .. itemID
                seen[base] = (seen[base] or 0) + 1
                table.insert(entries, { itemID = itemID, lootKey = base .. ":" .. seen[base] })
            end
        end
    end
    return entries, corpse
end

local function onLootOpened()
    local s = ns.Session:Get()
    if not s or not canEdit() then return end
    local entries, corpse = readCorpse()
    if not corpse then return end -- nichts Verteilbares (nur graue/weiße Items)
    ns.Session:SetCurrentCorpse(s, corpse)
    local added = ns.Session:AddLootEntries(s, entries)
    notifyChanged(added > 0)
    ns.Debug("Loot", "Leiche", corpse, "neue Items:", added)
    if ns.db.lootPanel then
        softResWindow:Show()
    end
end

function ns:LOOT_OPENED()
    -- Das Lootfenster wird im selben Frame aufgebaut: einen Tick warten, dann andocken
    C_Timer.After(0, onLootOpened)
end

-- Raider: der Raidlead hat eine Leiche mit neuen Items gelootet
ns:On("LOOT_LIST_OPEN", function()
    if ns.db.lootPanel then
        softResWindow:Show()
    end
end)

ns:On("DB_READY", function()
    if ns.db.lootPanel == nil then
        ns.db.lootPanel = true
    end
end)

-- Zuteilen-Knöpfe hängen an der offenen Leiche: bei Änderungen neu zeichnen
local refreshSoftRes = UI.Debounce(function()
    if softResWindow.frame:IsShown() then
        softResWindow:Refresh()
    end
end)

function ns:LOOT_SLOT_CLEARED()
    refreshSoftRes()
end

function ns:LOOT_CLOSED()
    refreshSoftRes()
end

ns:RegisterEvent("LOOT_OPENED")
ns:RegisterEvent("LOOT_SLOT_CLEARED")
ns:RegisterEvent("LOOT_CLOSED")

-- Test ohne Leiche (/psr loottest, nur ohne Gruppe): Items der Reserves als „Leiche“ eintragen
function ns.ShowLootTest()
    local s = ns.Session:Get()
    if not s or not canEdit() then
        ns.Print("Keine eigene Sitzung.")
        return
    end
    if IsInGroup and IsInGroup() then
        ns.Print("Loot-Test nur ohne Gruppe (die Beute würde an die Gruppe gehen).")
        return
    end
    local corpse = "test" .. GetServerTime()
    local entries, seen = {}, {}
    for _, reserves in pairs(s.reserves) do
        for _, entry in ipairs(reserves) do
            if not seen[entry.itemID] and #entries < 6 then
                seen[entry.itemID] = true
                table.insert(entries, { itemID = entry.itemID, lootKey = corpse .. ":" .. entry.itemID .. ":1" })
            end
        end
    end
    ns.Session:SetCurrentCorpse(s, corpse)
    local added = ns.Session:AddLootEntries(s, entries)
    ns.Print("Loot-Test: Leiche mit " .. added .. " Items.")
    softResWindow:Show()
end
