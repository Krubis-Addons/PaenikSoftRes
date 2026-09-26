-- Provider auf Basis des Encounter Journals.
-- In der Forever-Beta ist das EJ per Spielregel abgeschaltet (EJ_GetNumTiers() == 0),
-- dann meldet der Provider sich als nicht verfügbar und die eigenen Tabellen greifen.
local _, ns = ...

local EJProvider = { id = "ej" }

local function hasAPI()
    return type(EJ_GetNumTiers) == "function"
        and type(EJ_SelectTier) == "function"
        and type(EJ_GetInstanceByIndex) == "function"
        and type(EJ_SelectInstance) == "function"
        and type(EJ_GetEncounterInfoByIndex) == "function"
        and type(EJ_SelectEncounter) == "function"
        and type(EJ_GetNumLoot) == "function"
        and C_EncounterJournal and C_EncounterJournal.GetLootInfoByIndex
end

function EJProvider:IsAvailable()
    if not hasAPI() then return false end
    local ok, numTiers = pcall(EJ_GetNumTiers)
    return ok and type(numTiers) == "number" and numTiers > 0
end

function EJProvider:GetInstances()
    local list = {}
    for tier = 1, EJ_GetNumTiers() do
        EJ_SelectTier(tier)
        for _, isRaid in ipairs({ true, false }) do
            local index = 1
            local instanceID, name = EJ_GetInstanceByIndex(index, isRaid)
            while instanceID do
                table.insert(list, {
                    key = tostring(instanceID),
                    name = name,
                    isRaid = isRaid,
                })
                index = index + 1
                instanceID, name = EJ_GetInstanceByIndex(index, isRaid)
            end
        end
    end
    ns.Debug("LootData", "EJ-Instanzen:", #list)
    return list
end

-- Loot wird evtl. erst nachgeladen (EJ_LOOT_DATA_RECIEVED). Offen, bis das EJ in Forever aktiv ist.
-- Cache: jeder Aufruf verstellt sonst die EJ-Auswahl der Blizzard-UI.
local encounterCache = {}

function EJProvider:GetEncounters(key)
    if encounterCache[key] then
        return encounterCache[key]
    end
    local instanceID = tonumber(key)
    if not instanceID then return {} end
    EJ_SelectInstance(instanceID)
    local encounters = {}
    local index = 1
    local name, _, encounterID = EJ_GetEncounterInfoByIndex(index, instanceID)
    while encounterID do
        EJ_SelectEncounter(encounterID)
        local items = {}
        for i = 1, EJ_GetNumLoot() do
            local info = C_EncounterJournal.GetLootInfoByIndex(i)
            if info and info.itemID then
                table.insert(items, info.itemID)
            end
        end
        local displayID
        if type(EJ_GetCreatureInfo) == "function" then
            displayID = select(4, EJ_GetCreatureInfo(1, encounterID))
        end
        table.insert(encounters, { name = name, displayID = displayID, items = items })
        index = index + 1
        name, _, encounterID = EJ_GetEncounterInfoByIndex(index, instanceID)
    end
    if #encounters > 0 then
        encounterCache[key] = encounters
    end
    return encounters
end

ns.LootData:RegisterProvider(EJProvider)
