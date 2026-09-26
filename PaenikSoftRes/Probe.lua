-- Prüft ingame, welche (nicht dokumentierten) APIs in WoW: Forever vorhanden sind.
-- Ergebnis landet im Debug-Log (Kategorie "Probe").
local addonName, ns = ...

local GLOBALS = {
    "EJ_GetNumTiers",
    "EJ_SelectTier",
    "EJ_GetInstanceByIndex",
    "EJ_SelectInstance",
    "EJ_GetEncounterInfoByIndex",
    "EJ_SelectEncounter",
    "EJ_SetDifficulty",
    "EJ_GetNumLoot",
    "GetNumLootItems",
    "GetLootSlotLink",
    "GetLootSlotInfo",
    "RandomRoll",
    "GetRaidRosterInfo",
    "IsInGroup",
    "IsInRaid",
}

local function probeEJ()
    if type(EJ_GetNumTiers) ~= "function" or type(EJ_GetInstanceByIndex) ~= "function" then
        return
    end
    local ok, numTiers = pcall(EJ_GetNumTiers)
    ns.Debug("Probe", "EJ_GetNumTiers:", ok, numTiers)
    if type(EJ_SelectTier) == "function" then
        pcall(EJ_SelectTier, 1)
    end
    for _, isRaid in ipairs({ true, false }) do
        for index = 1, 3 do
            local okI, instanceID, name = pcall(EJ_GetInstanceByIndex, index, isRaid)
            ns.Debug("Probe", "EJ_GetInstanceByIndex", index, isRaid and "raid" or "dungeon", okI, instanceID, name)
            if not okI or not instanceID then break end
        end
    end
end

-- Prüft, ob alle ItemIDs der Loot-Daten im Client bekannt sind.
local function probeItems()
    for _, instance in ipairs(ns.LootData:GetInstances()) do
        local total, unknown = 0, {}
        for _, encounter in ipairs(ns.LootData:GetEncounters(instance.fullKey)) do
            for _, itemID in ipairs(encounter.items) do
                total = total + 1
                if not C_Item.GetItemInfoInstant(itemID) then
                    table.insert(unknown, itemID)
                end
            end
        end
        ns.Debug("Probe", "Items", instance.fullKey, instance.name, "gesamt", total, "unbekannt", #unknown,
            table.concat(unknown, ","))
        print(string.format("%s: %s – %d Items, %d unbekannt", addonName, instance.name, total, #unknown))
    end
end

function ns.RunProbe()
    local missing = {}
    for _, name in ipairs(GLOBALS) do
        local kind = type(_G[name])
        ns.Debug("Probe", name, kind)
        if kind ~= "function" then
            table.insert(missing, name)
        end
    end
    ns.Debug("Probe", "C_EncounterJournal:", type(C_EncounterJournal), "C_ChatInfo.SendAddonMessage:",
        type(C_ChatInfo and C_ChatInfo.SendAddonMessage))
    probeEJ()
    local ejCount = 0
    for _, instance in ipairs(ns.LootData:GetInstances()) do
        if instance.providerID == "ej" then
            ejCount = ejCount + 1
        end
    end
    ns.Debug("Probe", "Instanzen aus dem EJ-Provider:", ejCount)
    probeItems()
    if #missing == 0 then
        print(addonName .. ": Probe OK, alle APIs vorhanden.")
    else
        print(addonName .. ": Probe – fehlend: " .. table.concat(missing, ", "))
    end
    print(addonName .. ": Details im Debug-Log (nach /reload lesbar).")
end
