-- Datenquellen für Instanzen und Loot.
-- Ein Provider liefert:
--   provider.id                  eindeutige Kennung ("static", "ej", ...)
--   provider:IsAvailable()       true, wenn Daten geliefert werden können
--   provider:GetInstances()      { { key, name, isRaid, maxPlayers }, ... }
--   provider:GetEncounters(key)  { { name, displayID?, items = { itemID, ... } }, ... }
-- Nach außen werden Instanzen über "providerID:key" angesprochen.
local _, ns = ...

local LootData = {}
ns.LootData = LootData

local providers = {}

function LootData:RegisterProvider(provider)
    table.insert(providers, provider)
end

local function splitKey(fullKey)
    if type(fullKey) ~= "string" then return nil end
    return fullKey:match("^([^:]+):(.+)$")
end

local function findProvider(id)
    for i = 1, #providers do
        if providers[i].id == id then
            return providers[i]
        end
    end
end

-- Alle Instanzen aller verfügbaren Provider, Raids zuerst, dann nach Name.
function LootData:GetInstances()
    local result = {}
    for i = 1, #providers do
        local provider = providers[i]
        if provider:IsAvailable() then
            for _, instance in ipairs(provider:GetInstances()) do
                table.insert(result, {
                    fullKey = provider.id .. ":" .. instance.key,
                    name = instance.name,
                    isRaid = instance.isRaid,
                    maxPlayers = instance.maxPlayers,
                    providerID = provider.id,
                })
            end
        end
    end
    table.sort(result, function(a, b)
        if a.isRaid ~= b.isRaid then
            return a.isRaid
        end
        return a.name < b.name
    end)
    return result
end

function LootData:GetInstance(fullKey)
    for _, instance in ipairs(self:GetInstances()) do
        if instance.fullKey == fullKey then
            return instance
        end
    end
end

function LootData:GetEncounters(fullKey)
    local providerID, key = splitKey(fullKey)
    local provider = providerID and findProvider(providerID)
    if not provider or not provider:IsAvailable() then
        return {}
    end
    return provider:GetEncounters(key) or {}
end

-- Auffüll-Items einer Instanz (optional, nur eigene Tabellen)
function LootData:GetFiller(fullKey)
    local providerID, key = splitKey(fullKey)
    local provider = providerID and findProvider(providerID)
    if provider and provider.GetFiller then
        return provider:GetFiller(key) or {}
    end
    return {}
end

-- Verfügbarkeit von Items ----------------------------------------------------------
-- Der Forever-Client kennt alle Classic-Items, der Server liefert aber nicht für alle Daten.
-- ITEM_DATA_LOAD_RESULT(itemID, false) → Item wird in den Listen ausgeblendet.
local MIN_ITEMS = 6 -- Bosse mit weniger verfügbaren Items werden aufgefüllt

local failedItems = {}
local requestedItems = {}
local displayCache = {}

function LootData:IsItemAvailable(itemID)
    return not failedItems[itemID] and C_Item.DoesItemExistByID(itemID)
end

local function requestLoad(itemID)
    if requestedItems[itemID] then return end
    requestedItems[itemID] = true
    if C_Item.DoesItemExistByID(itemID) and not C_Item.IsItemDataCachedByID(itemID) then
        C_Item.RequestLoadItemDataByID(itemID)
    end
end

local fireItemsChanged = function()
    wipe(displayCache)
    ns:Fire("LOOT_ITEMS_CHANGED")
end
local itemsChangedScheduled = false

function ns:ITEM_DATA_LOAD_RESULT(itemID, success)
    if success == false and requestedItems[itemID] and not failedItems[itemID] then
        failedItems[itemID] = true
        ns.Debug("LootData", "Item vom Server unbekannt:", itemID)
        if not itemsChangedScheduled then
            itemsChangedScheduled = true
            C_Timer.After(0.5, function()
                itemsChangedScheduled = false
                fireItemsChanged()
            end)
        end
    end
end
ns:RegisterEvent("ITEM_DATA_LOAD_RESULT")

-- Encounter für die Anzeige: nicht verfügbare Items entfernt, knappe Bosse aufgefüllt.
-- Liefert dieselbe Struktur wie GetEncounters (plus filled = Anzahl Auffüll-Items).
function LootData:GetDisplayEncounters(fullKey)
    if displayCache[fullKey] then
        return displayCache[fullKey]
    end
    local encounters = self:GetEncounters(fullKey)
    local filler = self:GetFiller(fullKey)

    local used = {}
    local result = {}
    for index, encounter in ipairs(encounters) do
        local items = {}
        for _, itemID in ipairs(encounter.items) do
            requestLoad(itemID)
            if self:IsItemAvailable(itemID) then
                table.insert(items, itemID)
                used[itemID] = true
            end
        end
        result[index] = { name = encounter.name, displayID = encounter.displayID, items = items, filled = 0 }
    end

    local nextFiller = 1
    for _, encounter in ipairs(result) do
        while #encounter.items < MIN_ITEMS and nextFiller <= #filler do
            local itemID = filler[nextFiller]
            nextFiller = nextFiller + 1
            requestLoad(itemID)
            if not used[itemID] and self:IsItemAvailable(itemID) then
                table.insert(encounter.items, itemID)
                encounter.filled = encounter.filled + 1
                used[itemID] = true
            end
        end
    end
    displayCache[fullKey] = result
    return result
end

-- Anzahl der Bosse und der verschiedenen (angezeigten) Items einer Instanz.
function LootData:GetStats(fullKey)
    local encounters = self:GetDisplayEncounters(fullKey)
    local seen, count = {}, 0
    for _, encounter in ipairs(encounters) do
        for _, itemID in ipairs(encounter.items) do
            if not seen[itemID] then
                seen[itemID] = true
                count = count + 1
            end
        end
    end
    return #encounters, count
end

-- Eigene Tabellen (Data/Instances/*.lua)
local staticInstances = {}

local StaticProvider = { id = "static" }

function StaticProvider:IsAvailable()
    return true
end

function StaticProvider:GetInstances()
    local list = {}
    for _, instance in ipairs(staticInstances) do
        table.insert(list, {
            key = instance.key,
            name = instance.name,
            isRaid = instance.isRaid,
            maxPlayers = instance.maxPlayers,
        })
    end
    return list
end

function StaticProvider:GetEncounters(key)
    for _, instance in ipairs(staticInstances) do
        if instance.key == key then
            return instance.encounters
        end
    end
end

function StaticProvider:GetFiller(key)
    for _, instance in ipairs(staticInstances) do
        if instance.key == key then
            return instance.filler
        end
    end
end

function LootData:RegisterStaticInstance(instance)
    table.insert(staticInstances, instance)
end

LootData:RegisterProvider(StaticProvider)
