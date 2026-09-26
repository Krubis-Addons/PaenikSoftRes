-- Minimap-Button: Klick öffnet/schließt das Hauptfenster, Ziehen verschiebt ihn um die Minimap.
local _, ns = ...

local button = CreateFrame("Button", nil, Minimap)
button:SetSize(31, 31)
button:SetFrameStrata("MEDIUM")
button:SetFrameLevel(8)
button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
button:RegisterForDrag("LeftButton")
button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

-- Dunkler, runder Hintergrund (das Icon ist teilweise transparent)
local background = button:CreateTexture(nil, "BACKGROUND")
background:SetSize(21, 21)
background:SetPoint("TOPLEFT", 6, -5)
background:SetColorTexture(0.05, 0.05, 0.05, 1)
local backgroundMask = button:CreateMaskTexture()
backgroundMask:SetAllPoints(background)
backgroundMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE",
    "CLAMPTOBLACKADDITIVE")
background:AddMaskTexture(backgroundMask)

local icon = button:CreateTexture(nil, "ARTWORK")
icon:SetSize(17, 17)
icon:SetPoint("TOPLEFT", 7, -6)
icon:SetTexture(ns.UI.ICON)

local border = button:CreateTexture(nil, "OVERLAY")
border:SetSize(53, 53)
border:SetPoint("TOPLEFT")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

local function updatePosition()
    local angle = math.rad(ns.db.minimap.angle or 225)
    local radius = Minimap:GetWidth() / 2 + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

-- OnUpdate nur während des Ziehens
local function onDragUpdate()
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    ns.db.minimap.angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
    updatePosition()
end

button:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", onDragUpdate)
    GameTooltip:Hide()
end)

button:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    ns.Debug("Minimap", "Position", ns.db.minimap.angle)
end)

button:SetScript("OnClick", function(_, mouseButton)
    if mouseButton == "RightButton" then
        ns.OpenOptions()
    else
        ns.ToggleMainFrame()
    end
end)

button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(ns.TITLE)
    GameTooltip:AddLine("Klick: Fenster öffnen/schließen", 1, 1, 1)
    GameTooltip:AddLine("Rechtsklick: Optionen", 1, 1, 1)
    GameTooltip:AddLine("Ziehen: Button verschieben", 1, 1, 1)
    GameTooltip:Show()
end)

button:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

function ns.SetMinimapButtonShown(shown)
    ns.db.minimap.hide = not shown
    button:SetShown(shown)
end

ns:On("DB_READY", function()
    ns.db.minimap = ns.db.minimap or {}
    updatePosition()
    button:SetShown(not ns.db.minimap.hide)
end)
