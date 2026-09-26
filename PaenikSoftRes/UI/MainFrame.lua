-- Hauptfenster mit den Tabs "Raider", "Raidlead", "Übersicht" und "Loot".
-- Inhalte: UI/RaiderPanel.lua, UI/LeadPanel.lua, UI/OverviewPanel.lua, UI/LootBrowser.lua
local _, ns = ...

local UI = {}
ns.UI = UI

-- Addon-Icon: der Loot-Mauszeiger (Sack), der beim Überfahren einer lootbaren Leiche erscheint
UI.ICON = "Interface\\Cursor\\LootAll"

UI.TAB_RAIDER = 1
UI.TAB_LEAD = 2
UI.TAB_OVERVIEW = 3
UI.TAB_LOOT = 4

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

-- Dunkler, runder Hintergrund hinter dem Porträt (das Icon ist teilweise transparent)
do
    local container = mainFrame.PortraitContainer
    local portrait = mainFrame:GetPortrait()
    local portraitBg = container:CreateTexture(nil, "OVERLAY", nil, -1)
    portraitBg:SetAllPoints(portrait)
    portraitBg:SetColorTexture(0.05, 0.05, 0.05, 1)
    if container.CircleMask then
        portraitBg:AddMaskTexture(container.CircleMask)
    end
end
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
    [UI.TAB_LOOT] = createPanel(),
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
    -- Wurde die Liste im selben Moment eingeblendet und befüllt, ist ihre Größe evtl. noch nicht
    -- berechnet und es erscheinen keine Zeilen. Einen Frame später mit gültiger Größe neu aufbauen.
    -- Der Balken hängt am Elternframe: mit der Liste aus- und einblenden (sonst bleibt er z. B. ohne
    -- Sitzung stehen und liegt über dem Hinweistext)
    scrollBox:HookScript("OnHide", function()
        scrollBar:Hide()
    end)
    scrollBox:HookScript("OnShow", function(self)
        scrollBar:Show()
        C_Timer.After(0, function()
            if self:IsVisible() then
                self:FullUpdate(ScrollBoxConstants.UpdateImmediately)
            end
        end)
    end)
    return scrollBox
end

-- Bossliste mit Porträts (Raider-Tab und Loot-Browser) ---------------------------------
UI.BOSS_ROW_HEIGHT = 40
UI.ALL_BOSSES = 0
UI.WISHLIST = -1 -- Eintrag „Wunschliste“ ganz oben
UI.OWNED_TEXT = "|cff66ccffIm Besitz|r"
local ALL_BOSSES_ICON = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local WISHLIST_FALLBACK_ICON = "Interface\\Icons\\INV_Misc_Note_01"
local PORTRAIT_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- data = { index, name, displayID, killed, info }; info = fertiger Text der zweiten Zeile.
-- row.bossIndex = data.index; onClick(row, mouseButton) nimmt Links- und Rechtsklicks.
function UI.InitBossRow(row, data, selected, onClick)
    if not row.portrait then
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints()
        row.highlight:SetColorTexture(1, 1, 1, 0.08)
        row.portrait = row:CreateTexture(nil, "ARTWORK")
        row.portrait:SetSize(UI.BOSS_ROW_HEIGHT - 6, UI.BOSS_ROW_HEIGHT - 6)
        row.portrait:SetPoint("LEFT", row, "LEFT", 3, 0)
        row.mask = row:CreateMaskTexture()
        row.mask:SetAllPoints(row.portrait)
        row.mask:SetTexture(PORTRAIT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        row.portrait:AddMaskTexture(row.mask)
        -- Wunschliste: Stern ohne runde Maske (die würde ihn beschneiden), mittig im Porträtbereich
        row.star = row:CreateTexture(nil, "ARTWORK")
        row.star:SetSize(24, 24)
        row.star:SetPoint("CENTER", row.portrait, "CENTER")
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.name:SetPoint("TOPLEFT", row.portrait, "TOPRIGHT", 6, -3)
        row.name:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.info = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.info:SetPoint("BOTTOMLEFT", row.portrait, "BOTTOMRIGHT", 6, 3)
        row.info:SetJustifyH("LEFT")
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end
    row:SetScript("OnClick", onClick)
    row.bossIndex = data.index
    local isWishlist = data.index == UI.WISHLIST
    row.portrait:SetShown(not isWishlist)
    row.star:SetShown(isWishlist)
    if isWishlist and not ns.Wishlist.SetIconTexture(row.star) then
        row.star:SetTexture(WISHLIST_FALLBACK_ICON)
    end
    if data.displayID then
        SetPortraitTextureFromCreatureDisplayID(row.portrait, data.displayID)
    else
        row.portrait:SetTexture(ALL_BOSSES_ICON)
    end
    row.portrait:SetDesaturated(data.killed == true)
    row.name:SetText(data.killed and ("|cff808080" .. data.name .. "|r") or data.name)
    row.info:SetText(data.info or "")
    if selected then
        row.bg:SetColorTexture(1, 0.82, 0, 0.18)
        row.name:SetFontObject("GameFontHighlight")
    else
        row.bg:SetColorTexture(0, 0, 0, 0)
        row.name:SetFontObject("GameFontNormal")
    end
end

-- Stern mit Anzahl für die zweite Zeile einer Boss-Zeile ("" bei 0)
function UI.WishCountText(count)
    if not count or count == 0 then return nil end
    return ns.Wishlist.Icon(10) .. "|cffffd100" .. count .. "|r"
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

-- Bestätigungsdialog (eigener Frame statt StaticPopupDialogs: keine Blizzard-Globals verändern)
local confirmFrame = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
confirmFrame:SetSize(380, 150)
confirmFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
confirmFrame:SetFrameStrata("FULLSCREEN_DIALOG")
confirmFrame:SetToplevel(true)
confirmFrame:EnableMouse(true)
confirmFrame.TitleText:SetText("Bitte bestätigen")
confirmFrame:Hide()

local confirmText = confirmFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
confirmText:SetPoint("TOPLEFT", confirmFrame, "TOPLEFT", 16, -36)
confirmText:SetPoint("BOTTOMRIGHT", confirmFrame, "BOTTOMRIGHT", -16, 44)
confirmText:SetJustifyH("CENTER")
confirmText:SetJustifyV("MIDDLE")

local confirmAction
local confirmYes = UI.CreateButton(confirmFrame, "Ja", 120, function()
    local action = confirmAction
    confirmAction = nil
    confirmFrame:Hide()
    if action then action() end
end)
confirmYes:SetPoint("BOTTOMRIGHT", confirmFrame, "BOTTOM", -6, 12)
local confirmNo = UI.CreateButton(confirmFrame, "Abbrechen", 120, function()
    confirmAction = nil
    confirmFrame:Hide()
end)
confirmNo:SetPoint("BOTTOMLEFT", confirmFrame, "BOTTOM", 6, 12)
confirmFrame:SetScript("OnHide", function()
    confirmAction = nil
end)

-- Fragt nach und führt onAccept nur bei „Ja“ aus. Ohne Nachfrage, wenn condition == false.
function UI.Confirm(text, onAccept, condition)
    if condition == false then
        onAccept()
        return
    end
    confirmText:SetText(text)
    confirmFrame:Show()
    confirmAction = onAccept -- nach Show: OnHide eines alten Dialogs räumt sonst auf
end

-- Eingabedialog: ein Textfeld, onAccept(text) bei „OK“ oder Enter
local promptFrame = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
promptFrame:SetSize(380, 150)
promptFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
promptFrame:SetFrameStrata("FULLSCREEN_DIALOG")
promptFrame:SetToplevel(true)
promptFrame:EnableMouse(true)
promptFrame.TitleText:SetText(ns.TITLE)
promptFrame:Hide()

local promptText = promptFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
promptText:SetPoint("TOPLEFT", promptFrame, "TOPLEFT", 16, -34)
promptText:SetPoint("RIGHT", promptFrame, "RIGHT", -16, 0)
promptText:SetJustifyH("CENTER")

local promptBox = CreateFrame("EditBox", nil, promptFrame, "InputBoxTemplate")
promptBox:SetSize(300, 22)
promptBox:SetPoint("TOP", promptText, "BOTTOM", 0, -12)
promptBox:SetAutoFocus(true)
promptBox:SetMaxLetters(30)

local promptAction
local function acceptPrompt()
    local action = promptAction
    promptAction = nil
    local text = promptBox:GetText()
    promptFrame:Hide()
    if action then action(text) end
end
promptBox:SetScript("OnEnterPressed", acceptPrompt)
promptBox:SetScript("OnEscapePressed", function() promptFrame:Hide() end)

local promptOK = UI.CreateButton(promptFrame, "OK", 120, acceptPrompt)
promptOK:SetPoint("BOTTOMRIGHT", promptFrame, "BOTTOM", -6, 12)
local promptCancel = UI.CreateButton(promptFrame, "Abbrechen", 120, function() promptFrame:Hide() end)
promptCancel:SetPoint("BOTTOMLEFT", promptFrame, "BOTTOM", 6, 12)
promptFrame:SetScript("OnHide", function()
    promptAction = nil
end)

function UI.Prompt(text, default, onAccept)
    promptText:SetText(text)
    promptBox:SetText(default or "")
    promptFrame:Show()
    promptAction = onAccept
    promptBox:SetFocus()
    promptBox:HighlightText()
end

-- Titel einer Sitzung: Name, bei eigenem Namen zusätzlich die Instanz
function UI.SessionTitle(s)
    local instance = s.instanceName or "keine Instanz"
    if s.name and s.name ~= "" and not s.nameAuto and not s.name:find(instance, 1, true) then
        return s.name .. " (" .. instance .. ")"
    end
    return s.name or instance
end

-- Zeitpunkt als "Sa, 27.09. 20:00" (Wochentage deutsch, date() liefert sie nur englisch)
local WEEKDAYS = { "So", "Mo", "Di", "Mi", "Do", "Fr", "Sa" }

function UI.FormatDate(timestamp, withTime)
    local weekday = WEEKDAYS[tonumber(date("%w", timestamp)) + 1]
    return weekday .. ", " .. date(withTime == false and "%d.%m." or "%d.%m. %H:%M", timestamp)
end

-- Status der Sitzung als farbiger Text: gesperrt / offen bis … / offen
function UI.LockStateText(s)
    if s.locked then
        return "|cffff6060gesperrt|r"
    elseif s.deadline and GetServerTime() >= s.deadline then
        return "|cffff6060geschlossen (Anmeldeschluss)|r"
    elseif s.deadline then
        return "|cff60ff60offen bis " .. UI.FormatDate(s.deadline) .. "|r"
    end
    return "|cff60ff60offen|r"
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
createTab(UI.TAB_LOOT, "Loot")
PanelTemplates_SetNumTabs(mainFrame, 4)
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
