-- Prüft ingame, welche (nicht dokumentierten) APIs in WoW: Forever vorhanden sind.
-- Ergebnis landet im Debug-Log (Kategorie "Probe").
local _, ns = ...

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
    "GetLootSourceInfo",
    "IsInGuild",
    "GetNumGuildMembers",
    "GetGuildRosterInfo",
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
        ns.Print(string.format("%s – %d Items, %d unbekannt", instance.name, total, #unknown))
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
    ns.Debug("Probe", "Realm", GetRealmName(), "| normalisiert", GetNormalizedRealmName(),
        "| Nachnamen anzeigen", C_PlayerInfo.ShouldDisplaySurname and C_PlayerInfo.ShouldDisplaySurname())
    local units = { "player" }
    local prefix = IsInRaid() and "raid" or "party"
    for i = 1, IsInRaid() and 40 or 4 do
        if UnitExists(prefix .. i) then
            table.insert(units, prefix .. i)
        end
    end
    for _, unit in ipairs(units) do
        local n1, n2 = UnitName(unit)
        local f1, f2 = UnitFullName(unit)
        local guid = UnitGUID(unit)
        local _, _, _, _, _, gName, gRealm = GetPlayerInfoByGUID(guid)
        ns.Debug("Probe", "Name", unit, "UnitName:", n1, "/", n2, "| UnitFullName:", f1, "/", f2,
            "| GUID-Info:", gName, "/", gRealm, "| FullName:", ns.FullName(unit))
    end
    probeEJ()
    local ejCount = 0
    for _, instance in ipairs(ns.LootData:GetInstances()) do
        if instance.providerID == "ej" then
            ejCount = ejCount + 1
        end
    end
    ns.Debug("Probe", "Instanzen aus dem EJ-Provider:", ejCount)
    probeItems()
    -- Besitz-Anzeige: zählt GetItemCount die Bank auch bei geschlossener Bank? (Ruhestein 6948 als Beispiel)
    ns.Debug("Probe", "GetItemCount Ruhestein – Taschen:", C_Item.GetItemCount(6948, false),
        "mit Bank:", C_Item.GetItemCount(6948, true), "| angelegt-Prüfung:", type(C_Item.IsEquippedItem))
    local owned, banked = ns.Owned:Summary()
    ns.Print(string.format("Besitz: %d Loot-Items im Besitz, davon %d in der Bank gemerkt", owned, banked))
    if #missing == 0 then
        ns.Print("Probe OK, alle APIs vorhanden.")
    else
        ns.Print("Probe – fehlend: " .. table.concat(missing, ", "))
    end
    ns.Print("Details im Debug-Log (nach /reload lesbar).")
end

-- Test-Reserves erfundener Spieler (nur zum Testen der Anzeigen ohne Gruppe).
function ns.AddFakeReserves()
    local s = ns.Session:Get()
    if IsInGroup and IsInGroup() then
        ns.Print("Testspieler nur ohne Gruppe.")
        return
    end
    if not s or not s.instanceKey or not ns.Session:IsOwner() then
        ns.Print("Erst eine eigene Sitzung mit Instanz anlegen.")
        return
    end
    local items = {}
    for _, encounter in ipairs(ns.LootData:GetDisplayEncounters(s.instanceKey)) do
        for _, itemID in ipairs(encounter.items) do
            table.insert(items, itemID)
        end
    end
    if #items == 0 then
        ns.Print("Die Instanz hat keine Loot-Daten.")
        return
    end
    local realm = GetNormalizedRealmName() or "Test"
    for i = 1, 5 do
        local picks = {}
        for _ = 1, s.maxReserves do
            table.insert(picks, items[math.random(#items)])
        end
        -- source "fake": wird nie an die Gruppe gesendet
        ns.Session:ApplyRemoteReserves("Testspieler" .. i .. "-" .. realm, picks, "fake")
    end
    ns.Print("5 Testspieler mit Reserves eingetragen.")
end
