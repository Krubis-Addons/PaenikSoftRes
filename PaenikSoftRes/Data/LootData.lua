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

-- Anzahl der Bosse und der verschiedenen Items einer Instanz.
function LootData:GetStats(fullKey)
    local encounters = self:GetEncounters(fullKey)
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

function LootData:RegisterStaticInstance(instance)
    table.insert(staticInstances, instance)
end

LootData:RegisterProvider(StaticProvider)
