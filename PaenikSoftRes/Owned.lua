-- Besitz-Anzeige: Hat der eigene Charakter ein Item schon (Taschen, angelegt, Bank)?
-- Taschen und Ausrüstung kommen live aus C_Item.GetItemCount. Die Bank ist nur sicher bekannt, solange
-- sie offen ist: Beim Öffnen werden alle Items der Loot-Tabellen geprüft und pro Charakter in
-- db.ownedBank[Name-Realm] = { [itemID] = Anzahl } gemerkt (gilt bis zum nächsten Bankbesuch).
-- Änderungen melden OWNED_CHANGED.
local _, ns = ...

local Owned = {}
ns.Owned = Owned

local bankOpen = false
local notifyScheduled = false

local function notify()
    if notifyScheduled then return end
    notifyScheduled = true
    C_Timer.After(0.5, function()
        notifyScheduled = false
        ns:Fire("OWNED_CHANGED")
    end)
end

local function bankCache()
    local db = ns.db
    if not db then return nil end
    db.ownedBank = db.ownedBank or {}
    local me = ns.FullName("player")
    db.ownedBank[me] = db.ownedBank[me] or {}
    return db.ownedBank[me]
end

-- Alle ItemIDs der Loot-Tabellen (Bosse + Auffüll-Items)
local function allLootItems()
    local items = {}
    for _, instance in ipairs(ns.LootData:GetInstances()) do
        for _, encounter in ipairs(ns.LootData:GetEncounters(instance.fullKey)) do
            for _, itemID in ipairs(encounter.items) do
                items[itemID] = true
            end
        end
        for _, itemID in ipairs(ns.LootData:GetFiller(instance.fullKey)) do
            items[itemID] = true
        end
    end
    return items
end

local function scanBank()
    local cache = bankCache()
    if not cache then return end
    wipe(cache)
    local found = 0
    for itemID in pairs(allLootItems()) do
        local inBank = C_Item.GetItemCount(itemID, true) - C_Item.GetItemCount(itemID, false)
        if inBank > 0 then
            cache[itemID] = inBank
            found = found + 1
        end
    end
    ns.Debug("Owned", "Bank geprüft, Loot-Items in der Bank:", found)
    notify()
end

-- Wo liegt das Item? Liste aus "angelegt", "Taschen", "Bank"; nil = nicht im Besitz
function Owned:GetPlaces(itemID)
    if not itemID then return nil end
    local places = {}
    local equipped = C_Item.IsEquippedItem(itemID) and 1 or 0
    if equipped > 0 then
        table.insert(places, "angelegt")
    end
    local carried = C_Item.GetItemCount(itemID, false) -- Taschen, laut API inkl. angelegter Items
    if carried > equipped then
        table.insert(places, "Taschen")
    end
    local cache = bankCache()
    local inBank = bankOpen and (C_Item.GetItemCount(itemID, true) - carried) or (cache and cache[itemID] or 0)
    if inBank > 0 then
        table.insert(places, "Bank")
    end
    return #places > 0 and places or nil
end

function Owned:Has(itemID)
    return self:GetPlaces(itemID) ~= nil
end

-- "Taschen, Bank" für Tooltips und Rückfragen
function Owned:PlacesText(itemID)
    local places = self:GetPlaces(itemID)
    return places and table.concat(places, ", ") or nil
end

function ns:BANKFRAME_OPENED()
    bankOpen = true
    scanBank()
end

function ns:BANKFRAME_CLOSED()
    bankOpen = false -- kein erneuter Scan: bei geschlossener Bank zählt GetItemCount sie evtl. nicht mehr
end

function ns:PLAYERBANKSLOTS_CHANGED()
    if bankOpen then
        scanBank()
    end
end

function ns:BAG_UPDATE_DELAYED()
    if bankOpen then
        scanBank() -- Taschen ↔ Bank verschoben
    else
        notify()
    end
end

function ns:PLAYER_EQUIPMENT_CHANGED()
    notify()
end

ns:RegisterEvent("BANKFRAME_OPENED")
ns:RegisterEvent("BANKFRAME_CLOSED")
ns:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
ns:RegisterEvent("BAG_UPDATE_DELAYED")
ns:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")

-- Für /paeniksoftres probe: wie viele Loot-Items besitzt der Charakter, wie viele davon laut Bank-Speicher
function Owned:Summary()
    local owned, banked = 0, 0
    local cache = bankCache() or {}
    for itemID in pairs(allLootItems()) do
        if self:Has(itemID) then
            owned = owned + 1
        end
        if (cache[itemID] or 0) > 0 then
            banked = banked + 1
        end
    end
    return owned, banked
end
