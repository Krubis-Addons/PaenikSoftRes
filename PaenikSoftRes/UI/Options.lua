-- Optionen-Seite im Blizzard-Optionsmenü (Canvas-Layout: eigener Frame).
local _, ns = ...

local UI = ns.UI

local panel = CreateFrame("Frame")
panel:Hide()

local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
title:SetText(ns.TITLE)

local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
subtitle:SetText("Soft Reserves, Loot-Anzeige und Würfelrunden. Befehl: /paeniksoftres")

local refreshers = {}

-- Checkbox, die einen Wert liest (get) und schreibt (set)
local function createCheckbox(anchor, offsetY, label, tooltip, get, set)
    local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offsetY)
    check.Text:SetText(label)
    check.Text:SetFontObject("GameFontHighlight")
    check:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
    end)
    if tooltip then
        check:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        check:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    table.insert(refreshers, function() check:SetChecked(get()) end)
    return check
end

local showOnLogin = createCheckbox(subtitle, -20, "Hauptfenster beim Login öffnen", nil,
    function() return ns.db.showOnLogin end,
    function(value) ns.db.showOnLogin = value end)

local minimap = createCheckbox(showOnLogin, -4, "Minimap-Button anzeigen", nil,
    function() return not ns.db.minimap.hide end,
    function(value) ns.SetMinimapButtonShown(value) end)

local lootPanel = createCheckbox(minimap, -4, "„Soft Reserves“-Fenster beim Looten anzeigen",
    "Zeigt neben dem Lootfenster die Soft Reserves und Gewinner der Items.",
    function() return ns.db.lootPanel end,
    function(value) ns.db.lootPanel = value end)

local resetLootPos = UI.CreateButton(panel, "Position zurücksetzen", 170, function()
    ns.ResetLootPanelPosition()
    ns.Print("„Soft Reserves“-Fenster dockt wieder am Lootfenster an.")
end)
resetLootPos:SetPoint("LEFT", lootPanel.Text, "RIGHT", 16, 0)

-- Würfelzeit (Raidlead)
local durationLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
durationLabel:SetPoint("TOPLEFT", lootPanel, "BOTTOMLEFT", 4, -18)
durationLabel:SetText("Würfelzeit (als Raidlead):")

local durationDropdown = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
durationDropdown:SetWidth(200)
durationDropdown:SetPoint("LEFT", durationLabel, "RIGHT", 10, 0)
durationDropdown:SetupMenu(function(_, root)
    for _, seconds in ipairs(ns.Rolls.DURATIONS) do
        root:CreateRadio(ns.Rolls.DurationText(seconds),
            function(value) return ((ns.db and ns.db.rollDuration) or 0) == value end,
            function(value) ns.db.rollDuration = value end,
            seconds)
    end
end)
table.insert(refreshers, function() durationDropdown:SignalUpdate() end)

local debugCheck = createCheckbox(durationLabel, -18, "Debug-Log und Testbefehle",
    "Schreibt ein Protokoll in die SavedVariables (für die Fehlersuche) und schaltet die Testbefehle "
        .. "probe, fake, loottest, gargultest, lead, raider und auto frei.",
    function() return ns.db.debug end,
    function(value) ns.SetDebug(value) end)
debugCheck:ClearAllPoints()
debugCheck:SetPoint("TOPLEFT", durationLabel, "BOTTOMLEFT", -4, -18)

local guildCheck = createCheckbox(debugCheck, -4, "Gilden-Synchronisation",
    "Veröffentlichte Sitzungen über die Gilde empfangen und weitergeben, ohne Gruppe reservieren. "
        .. "Unsichtbare Addon-Nachrichten, kein Chat.",
    function() return ns.db.guildSync ~= false end,
    function(value)
        ns.db.guildSync = value
        ns:Fire("SESSION_CHANGED")
    end)

local gargulCheck = createCheckbox(guildCheck, -4, "Gargul-Würfelfenster öffnen (als Raidlead)",
    "Startet bei jeder Würfelrunde auch das Würfelfenster von Gargul – für Raider ohne dieses Addon. "
        .. "Wird nicht gesendet, wenn Gargul bei dir selbst geladen ist.",
    function() return ns.db.gargulCompat ~= false end,
    function(value) ns.db.gargulCompat = value end)

-- Vergangene Sitzungen aus regelmäßigen Raids aufräumen (Templates.lua)
local PAST_DAYS = { 0, 3, 7, 14, 30 }

local pastLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
pastLabel:SetPoint("TOPLEFT", gargulCheck, "BOTTOMLEFT", 4, -18)
pastLabel:SetText("Vergangene Sitzungen löschen:")

local pastDropdown = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
pastDropdown:SetWidth(160)
pastDropdown:SetPoint("LEFT", pastLabel, "RIGHT", 10, 0)
pastDropdown:SetupMenu(function(_, root)
    for _, days in ipairs(PAST_DAYS) do
        root:CreateRadio(days == 0 and "Nie" or ("nach " .. days .. " Tagen"),
            function(value) return ((ns.db and ns.db.pastSessionDays) or 0) == value end,
            function(value)
                ns.db.pastSessionDays = value
                ns.Templates:Cleanup()
            end,
            days)
    end
end)
pastDropdown:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Vergangene Sitzungen löschen")
    GameTooltip:AddLine("Sitzungen aus regelmäßigen Raids werden so viele Tage nach ihrem Termin gelöscht. "
        .. "Die aktive Sitzung bleibt immer erhalten.", 1, 1, 1, true)
    GameTooltip:Show()
end)
pastDropdown:SetScript("OnLeave", function() GameTooltip:Hide() end)
table.insert(refreshers, function() pastDropdown:SignalUpdate() end)

-- Blizzard ruft OnRefresh beim Anzeigen der Seite auf
function panel:OnRefresh()
    for _, refresh in ipairs(refreshers) do
        refresh()
    end
end
panel:SetScript("OnShow", panel.OnRefresh)

local category

ns:On("LOGIN", function()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
        ns.Debug("Options", "Settings-API nicht verfügbar")
        return
    end
    category = Settings.RegisterCanvasLayoutCategory(panel, ns.TITLE)
    Settings.RegisterAddOnCategory(category)
end)

-- Das Optionsmenü zu öffnen ist im Kampf geschützt: dann nach dem Kampf öffnen
local openAfterCombat = false

function ns.OpenOptions()
    if not (category and Settings.OpenToCategory) then
        ns.Print("Optionen sind nicht verfügbar.")
        return
    end
    if InCombatLockdown() then
        openAfterCombat = true
        ns.Print("Die Optionen öffnen sich nach dem Kampf.")
        return
    end
    Settings.OpenToCategory(category:GetID())
end

function ns:PLAYER_REGEN_ENABLED()
    if openAfterCombat then
        openAfterCombat = false
        ns.OpenOptions()
    end
end
ns:RegisterEvent("PLAYER_REGEN_ENABLED")
