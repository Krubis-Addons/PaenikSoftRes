-- Loot-Filter für Raider-Tab und Loot-Browser: nach Rüstungsart/Typ und Slot, Schnellwahl „Für meine Klasse“.
-- Daten ohne Serverabfrage aus C_Item.GetItemInfoInstant (itemEquipLoc, classID, subClassID).
-- Filterstand pro Charakter in ns.char.lootFilter = { types = { [Typ] = true }, slots = { [Slot] = true },
-- myClass = true }; leere Menge = keine Einschränkung. Änderungen melden LOOT_FILTER_CHANGED.
local _, ns = ...

local LootFilter = {}
ns.LootFilter = LootFilter

local ARMOR = Enum.ItemClass and Enum.ItemClass.Armor or 4
local WEAPON = Enum.ItemClass and Enum.ItemClass.Weapon or 2
local A = Enum.ItemArmorSubclass or { Generic = 0, Cloth = 1, Leather = 2, Mail = 3, Plate = 4, Shield = 6,
    Libram = 7, Idol = 8, Totem = 9, Relic = 11 }
local W = Enum.ItemWeaponSubclass or { Axe1H = 0, Axe2H = 1, Bows = 2, Guns = 3, Mace1H = 4, Mace2H = 5,
    Polearm = 6, Sword1H = 7, Sword2H = 8, Staff = 10, Unarmed = 13, Dagger = 15, Thrown = 16, Crossbow = 18,
    Wand = 19 }

-- Typen in Menü-Reihenfolge
LootFilter.TYPES = {
    { key = "cloth", text = "Stoff" },
    { key = "leather", text = "Leder" },
    { key = "mail", text = "Kette" },
    { key = "plate", text = "Platte" },
    { key = "shield", text = "Schild" },
    { key = "weapon", text = "Waffe" },
    { key = "jewelry", text = "Schmuck (Hals, Ring, Schmuckstück)" },
    { key = "back", text = "Umhang" },
    { key = "relic", text = "Relikt" },
    { key = "other", text = "Sonstiges" },
}

-- Slots in Menü-Reihenfolge; equipLocs = zugehörige INVTYPE_*-Werte
LootFilter.SLOTS = {
    { key = "head", text = "Kopf", equipLocs = { "INVTYPE_HEAD" } },
    { key = "neck", text = "Hals", equipLocs = { "INVTYPE_NECK" } },
    { key = "shoulder", text = "Schultern", equipLocs = { "INVTYPE_SHOULDER" } },
    { key = "back", text = "Rücken", equipLocs = { "INVTYPE_CLOAK" } },
    { key = "chest", text = "Brust", equipLocs = { "INVTYPE_CHEST", "INVTYPE_ROBE" } },
    { key = "wrist", text = "Handgelenke", equipLocs = { "INVTYPE_WRIST" } },
    { key = "hands", text = "Hände", equipLocs = { "INVTYPE_HAND" } },
    { key = "waist", text = "Taille", equipLocs = { "INVTYPE_WAIST" } },
    { key = "legs", text = "Beine", equipLocs = { "INVTYPE_LEGS" } },
    { key = "feet", text = "Füße", equipLocs = { "INVTYPE_FEET" } },
    { key = "finger", text = "Finger", equipLocs = { "INVTYPE_FINGER" } },
    { key = "trinket", text = "Schmuckstück", equipLocs = { "INVTYPE_TRINKET" } },
    { key = "onehand", text = "Einhand", equipLocs = { "INVTYPE_WEAPON", "INVTYPE_WEAPONMAINHAND",
        "INVTYPE_WEAPONOFFHAND" } },
    { key = "twohand", text = "Zweihand", equipLocs = { "INVTYPE_2HWEAPON" } },
    { key = "offhand", text = "Schildhand / Nebenhand", equipLocs = { "INVTYPE_SHIELD", "INVTYPE_HOLDABLE" } },
    { key = "ranged", text = "Distanz / Relikt", equipLocs = { "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT",
        "INVTYPE_THROWN", "INVTYPE_RELIC" } },
    { key = "other", text = "Nicht ausrüstbar", equipLocs = {} },
}

local slotByEquipLoc = {}
for _, slot in ipairs(LootFilter.SLOTS) do
    for _, equipLoc in ipairs(slot.equipLocs) do
        slotByEquipLoc[equipLoc] = slot.key
    end
end

local ARMOR_TYPE = { [A.Cloth] = "cloth", [A.Leather] = "leather", [A.Mail] = "mail", [A.Plate] = "plate",
    [A.Shield] = "shield", [A.Libram] = "relic", [A.Idol] = "relic", [A.Totem] = "relic", [A.Relic] = "relic" }
local JEWELRY = { INVTYPE_NECK = true, INVTYPE_FINGER = true, INVTYPE_TRINKET = true }

-- Typ und Slot eines Items (nil, falls der Client das Item nicht kennt)
function LootFilter.Classify(itemID)
    local id, _, _, equipLoc, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    if not id then return nil end
    local slot = slotByEquipLoc[equipLoc or ""] or "other"
    local itemType = "other"
    if equipLoc == "INVTYPE_CLOAK" then
        itemType = "back"
    elseif JEWELRY[equipLoc] then
        itemType = "jewelry"
    elseif classID == WEAPON then
        itemType = "weapon"
    elseif classID == ARMOR then
        itemType = ARMOR_TYPE[subClassID] or "other"
    end
    return itemType, slot, classID, subClassID
end

-- „Für meine Klasse“ (Classic-Waffenfertigkeiten): Hauptrüstungsart, Schild/Relikt, erlaubte Waffenarten.
-- Umhänge und Schmuck passen allen Klassen.
local CLASS_RULES = {
    WARRIOR = { armor = "plate", shield = true, weapons = { W.Axe1H, W.Axe2H, W.Mace1H, W.Mace2H, W.Sword1H,
        W.Sword2H, W.Polearm, W.Staff, W.Dagger, W.Unarmed, W.Bows, W.Guns, W.Crossbow, W.Thrown } },
    PALADIN = { armor = "plate", shield = true, relic = true, weapons = { W.Axe1H, W.Axe2H, W.Mace1H, W.Mace2H,
        W.Sword1H, W.Sword2H, W.Polearm } },
    HUNTER = { armor = "mail", weapons = { W.Axe1H, W.Axe2H, W.Sword1H, W.Sword2H, W.Polearm, W.Staff, W.Dagger,
        W.Unarmed, W.Bows, W.Guns, W.Crossbow, W.Thrown } },
    ROGUE = { armor = "leather", weapons = { W.Dagger, W.Unarmed, W.Sword1H, W.Mace1H, W.Bows, W.Guns,
        W.Crossbow, W.Thrown } },
    PRIEST = { armor = "cloth", weapons = { W.Dagger, W.Mace1H, W.Staff, W.Wand } },
    SHAMAN = { armor = "mail", shield = true, relic = true, weapons = { W.Axe1H, W.Axe2H, W.Mace1H, W.Mace2H,
        W.Dagger, W.Unarmed, W.Staff } },
    MAGE = { armor = "cloth", weapons = { W.Dagger, W.Sword1H, W.Staff, W.Wand } },
    WARLOCK = { armor = "cloth", weapons = { W.Dagger, W.Sword1H, W.Staff, W.Wand } },
    DRUID = { armor = "leather", relic = true, weapons = { W.Dagger, W.Unarmed, W.Mace1H, W.Mace2H, W.Staff } },
}
for _, rule in pairs(CLASS_RULES) do
    rule.weaponSet = {}
    for _, subClassID in ipairs(rule.weapons) do
        rule.weaponSet[subClassID] = true
    end
end

local function classRule()
    local _, classFile = UnitClass("player")
    return classFile and CLASS_RULES[classFile]
end

-- Hat die eigene Klasse eine bekannte Regel? (sonst ist „Für meine Klasse“ ausgegraut)
function LootFilter.HasClassRule()
    return classRule() ~= nil
end

local function fitsClass(rule, itemType, subClassID)
    if itemType == "weapon" then
        return rule.weaponSet[subClassID] == true
    elseif itemType == "shield" then
        return rule.shield == true
    elseif itemType == "relic" then
        return rule.relic == true
    elseif itemType == "cloth" or itemType == "leather" or itemType == "mail" or itemType == "plate" then
        return itemType == rule.armor
    end
    return true -- Umhang, Schmuck, Sonstiges
end

-- Filterstand -----------------------------------------------------------------------

local function state()
    ns.char.lootFilter = ns.char.lootFilter or {}
    local f = ns.char.lootFilter
    f.types = f.types or {}
    f.slots = f.slots or {}
    return f
end

function LootFilter:IsActive()
    local f = state()
    return f.myClass == true or next(f.types) ~= nil or next(f.slots) ~= nil
end

-- Anzahl gesetzter Einschränkungen (für die Beschriftung)
function LootFilter:Count()
    local f, n = state(), 0
    for _ in pairs(f.types) do n = n + 1 end
    for _ in pairs(f.slots) do n = n + 1 end
    return n + (f.myClass and 1 or 0)
end

local function changed()
    ns:Fire("LOOT_FILTER_CHANGED")
end

function LootFilter:HasType(key) return state().types[key] == true end
function LootFilter:HasSlot(key) return state().slots[key] == true end
function LootFilter:IsMyClass() return state().myClass == true end

function LootFilter:ToggleType(key)
    local types = state().types
    types[key] = not types[key] or nil
    changed()
end

function LootFilter:ToggleSlot(key)
    local slots = state().slots
    slots[key] = not slots[key] or nil
    changed()
end

function LootFilter:ToggleMyClass()
    local f = state()
    f.myClass = not f.myClass or nil
    changed()
end

function LootFilter:Reset()
    ns.char.lootFilter = {}
    changed()
end

-- Passt das Item zum Filter? Unbekannte Items (vom Client nicht klassifizierbar) zeigen wir immer.
function LootFilter:Matches(itemID)
    if not self:IsActive() then return true end
    local itemType, slot, _, subClassID = LootFilter.Classify(itemID)
    if not itemType then return true end
    local f = state()
    if next(f.types) and not f.types[itemType] then return false end
    if next(f.slots) and not f.slots[slot] then return false end
    if f.myClass then
        local rule = classRule()
        if rule and not fitsClass(rule, itemType, subClassID) then return false end
    end
    return true
end

-- Zusatz für die Überschrift der Loot-Liste: „ (n von m Items, gefiltert)“, ohne Filter leer
function LootFilter:HeaderSuffix(shown, total)
    if not self:IsActive() then return "" end
    return string.format("  |cffffd100(%d von %d Items, gefiltert)|r", shown, total)
end

-- Dropdown (Mehrfachauswahl) für Raider-Tab und Loot-Browser; beide teilen den Filterstand
function LootFilter:CreateDropdown(parent)
    local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    dropdown:SetWidth(150)
    dropdown:SetupMenu(function(_, root)
        root:CreateCheckbox("Für meine Klasse", function() return self:IsMyClass() end,
            function() self:ToggleMyClass() end)
        root:CreateTitle("Typ")
        for _, entry in ipairs(LootFilter.TYPES) do
            root:CreateCheckbox(entry.text, function(key) return self:HasType(key) end,
                function(key) self:ToggleType(key) end, entry.key)
        end
        root:CreateTitle("Slot")
        for _, entry in ipairs(LootFilter.SLOTS) do
            root:CreateCheckbox(entry.text, function(key) return self:HasSlot(key) end,
                function(key) self:ToggleSlot(key) end, entry.key)
        end
        root:CreateDivider()
        root:CreateButton("Filter zurücksetzen", function() self:Reset() end)
    end)
    -- Feste Beschriftung statt Auswahltext (OverrideText): „Filter: aus“ bzw. „Filter (n)“
    local function updateText()
        if not ns.char then return end
        dropdown:OverrideText(self:IsActive() and ("|cffffd100Filter (" .. self:Count() .. ")|r") or "Filter: aus")
    end
    dropdown:OverrideText("Filter: aus")
    ns:On("LOOT_FILTER_CHANGED", updateText)
    ns:On("LOGIN", updateText)
    return dropdown
end
