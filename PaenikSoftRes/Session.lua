-- Datenmodell einer Soft-Reserve-Sitzung (ohne UI).
-- ns.db.session = {
--     id, leader, createdAt,
--     instanceKey,    -- "providerID:key", siehe Data/LootData.lua
--     instanceName,
--     maxReserves, allowDuplicates, locked,
--     reserves = { ["Name-Realm"] = { { itemID = 123, source = "ingame" }, ... } },
-- }
local _, ns = ...

local Session = {}
ns.Session = Session

Session.MAX_RESERVES_LIMIT = 5

local RULE_KEYS = {
    instanceKey = true,
    instanceName = true,
    maxReserves = true,
    allowDuplicates = true,
    locked = true,
}

-- Ereignisse:
--   SESSION_CHANGED                 bei jeder Änderung (für die UI)
--   SESSION_RULES_CHANGED           eigene Sitzung: neu angelegt oder Regeln geändert
--   SESSION_RESERVES_CHANGED(player) eigene Sitzung: Reserves eines Spielers geändert
--   SESSION_ENDED(sessionID)        eigene Sitzung verworfen
-- Übernahmen vom Raidlead (Apply*) lösen nur SESSION_CHANGED aus, damit nichts zurückgesendet wird.
local function changed(reason, ...)
    ns.Debug("Session", reason, ...)
    ns:Fire("SESSION_CHANGED")
end

function Session:Get()
    return ns.db and ns.db.session
end

-- true, wenn die aktuelle Sitzung von diesem Spieler angelegt wurde (Master-Liste).
function Session:IsOwner()
    local s = self:Get()
    return s ~= nil and s.leader == ns.FullName("player")
end

-- true, wenn diese Sitzung die maßgebliche Master-Liste ist: eigene Sitzung und Raidlead.
function Session:IsMaster()
    return self:IsOwner() and ns.Roles:IsLead()
end

-- Neuer Gruppenleiter übernimmt die (gespiegelte) Sitzung des bisherigen Leads.
function Session:TakeOver(leader)
    local old = self:Get()
    if not old or old.leader == leader then return false end
    local reserves = {}
    for player, list in pairs(old.reserves) do
        reserves[player] = CopyTable(list)
    end
    ns.db.session = {
        id = string.format("%s-%d", leader, GetServerTime()),
        leader = leader,
        createdAt = GetServerTime(),
        instanceKey = old.instanceKey,
        instanceName = old.instanceName,
        maxReserves = old.maxReserves or 1,
        allowDuplicates = old.allowDuplicates,
        locked = old.locked,
        reserves = reserves,
        history = old.history and CopyTable(old.history) or nil,
    }
    changed("Sitzung übernommen von", old.leader)
    ns:Fire("SESSION_FULL_SYNC")
    return true
end

function Session:New(leader)
    local old = self:Get()
    ns.db.session = {
        id = string.format("%s-%d", leader or "?", GetServerTime()),
        leader = leader,
        createdAt = GetServerTime(),
        maxReserves = 1,
        allowDuplicates = true,
        locked = false,
        reserves = {},
    }
    changed("Neue Sitzung", ns.db.session.id)
    -- Alte Sitzung in der Gruppe beenden lassen, Regeln der neuen verteilen
    if old and old.leader == leader then
        ns:Fire("SESSION_ENDED", old.id)
    end
    ns:Fire("SESSION_RULES_CHANGED")
    return ns.db.session
end

function Session:Reset()
    local s = self:Get()
    local wasOwner = self:IsOwner()
    ns.db.session = nil
    changed("Sitzung verworfen")
    if s and wasOwner then
        ns:Fire("SESSION_ENDED", s.id)
    end
end

function Session:SetRules(rules)
    local s = self:Get()
    if not s then return false, "Keine Sitzung" end
    if not self:IsOwner() then return false, "Sitzung gehört " .. tostring(s.leader) end
    if rules.maxReserves ~= nil then
        local n = tonumber(rules.maxReserves)
        if not n or n < 1 or n > self.MAX_RESERVES_LIMIT then
            return false, "Ungültige Anzahl SRs"
        end
    end
    -- Reserves gehören zu einer Instanz: bei einem Wechsel verfallen sie.
    if rules.instanceKey ~= nil and rules.instanceKey ~= s.instanceKey and next(s.reserves) then
        wipe(s.reserves)
        ns.Debug("Session", "Instanz gewechselt, Reserves verworfen")
    end
    local parts = {}
    for key, value in pairs(rules) do
        if RULE_KEYS[key] then
            s[key] = value
            table.insert(parts, key .. "=" .. tostring(value))
        end
    end
    changed("Regeln geändert:", table.concat(parts, ", "))
    ns:Fire("SESSION_RULES_CHANGED")
    return true
end

function Session:SetLocked(locked)
    return self:SetRules({ locked = locked and true or false })
end

function Session:GetReserves(player)
    local s = self:Get()
    return s and s.reserves[player]
end

function Session:CountReserves(player)
    local list = self:GetReserves(player)
    return list and #list or 0
end

-- ItemIDs der Reserves eines Spielers als einfache Liste.
function Session:GetReservedItemIDs(player)
    local ids = {}
    local list = self:GetReserves(player)
    if list then
        for i = 1, #list do
            ids[i] = list[i].itemID
        end
    end
    return ids
end

-- Menge aller ItemIDs der gewählten Instanz (gecacht pro instanceKey).
local itemSetCache = {}

function Session:GetInstanceItemSet()
    local s = self:Get()
    if not s or not s.instanceKey then return nil end
    local set = itemSetCache[s.instanceKey]
    if not set then
        set = {}
        for _, encounter in ipairs(ns.LootData:GetEncounters(s.instanceKey)) do
            for _, itemID in ipairs(encounter.items) do
                set[itemID] = true
            end
        end
        -- Auffüll-Items sind ebenfalls wählbar (Obermenge, unabhängig vom Ladestand)
        for _, itemID in ipairs(ns.LootData:GetFiller(s.instanceKey)) do
            set[itemID] = true
        end
        -- Nur statische Daten cachen; EJ-Loot kann noch nachgeladen werden.
        if next(set) and s.instanceKey:find("^static:") then
            itemSetCache[s.instanceKey] = set
        end
    end
    return set
end

-- Prüft eine komplette Reserve-Liste gegen die Regeln.
-- player (optional): Verkleinern einer bestehenden Liste ist immer erlaubt,
-- auch wenn der Raidlead das Limit inzwischen gesenkt hat.
function Session:ValidateReserves(itemIDs, player)
    local s = self:Get()
    if not s then return false, "Keine Sitzung" end
    if s.locked then return false, "Sitzung ist gesperrt" end
    if not s.instanceKey then return false, "Keine Instanz gewählt" end
    local current = player and self:CountReserves(player) or 0
    if #itemIDs > s.maxReserves and #itemIDs >= current then
        return false, "Limit erreicht (" .. s.maxReserves .. ")"
    end
    local itemSet = self:GetInstanceItemSet() or {}
    -- Items, die der Spieler schon hat (z. B. aus einem softres.it-Import mit eigenen Regeln),
    -- bleiben erlaubt – sonst könnte er seine Liste nicht mehr bearbeiten.
    local existing = {}
    if player then
        for _, itemID in ipairs(self:GetReservedItemIDs(player)) do
            existing[itemID] = (existing[itemID] or 0) + 1
        end
    end
    local seen = {}
    for _, itemID in ipairs(itemIDs) do
        if type(itemID) ~= "number" then
            return false, "Ungültige ItemID: " .. tostring(itemID)
        end
        if (existing[itemID] or 0) > 0 then
            existing[itemID] = existing[itemID] - 1
        else
            if not itemSet[itemID] then
                return false, "Item gehört nicht zur Instanz: " .. itemID
            end
            if seen[itemID] and not s.allowDuplicates then
                return false, "Item darf nur einmal reserviert werden"
            end
        end
        seen[itemID] = true
    end
    return true
end

-- Setzt die Reserves eines Spielers in der eigenen Sitzung (geprüft).
function Session:SetPlayerReserves(player, itemIDs, source)
    if not self:IsOwner() then return false, "Nicht Besitzer der Sitzung" end
    local ok, err = self:ValidateReserves(itemIDs, player)
    if not ok then
        ns.Debug("Session", "Reserves abgelehnt", player, err)
        return false, err
    end
    local s = self:Get()
    if #itemIDs == 0 then
        s.reserves[player] = nil
    else
        local list = {}
        for i, itemID in ipairs(itemIDs) do
            list[i] = { itemID = itemID, source = source or "ingame" }
        end
        s.reserves[player] = list
    end
    changed("Reserves gesetzt", player, table.concat(itemIDs, ","))
    ns:Fire("SESSION_RESERVES_CHANGED", player)
    return true
end

-- Import aus einer externen Quelle (z. B. softres.it) in die eigene Sitzung.
-- reserves = { ["Name-Realm"] = { itemID, ... } }; replaceAll = true verwirft alle bisherigen Reserves,
-- sonst werden nur die Listen der importierten Spieler ersetzt (Mischbetrieb mit Ingame-Reserves).
-- Limits und Instanz werden bewusst nicht geprüft: die externe Quelle hat ihre eigenen Regeln.
-- importNames (optional) = { [vorläufiger Schlüssel] = Name aus dem Export } für Spieler, die noch
-- keinem Gruppenmitglied zugeordnet werden konnten (siehe ResolveImportedPlayers).
function Session:ImportReserves(reserves, source, replaceAll, importNames)
    local s = self:Get()
    if not s then return false, "Keine Sitzung" end
    if not self:IsOwner() then return false, "Sitzung gehört " .. tostring(s.leader) end
    if replaceAll then
        wipe(s.reserves)
    end
    local players, count = 0, 0
    for player, itemIDs in pairs(reserves) do
        local importName = importNames and importNames[player]
        local list = {}
        for i, itemID in ipairs(itemIDs) do
            list[i] = { itemID = itemID, source = source, importName = importName }
        end
        s.reserves[player] = #list > 0 and list or nil
        players = players + 1
        count = count + #list
    end
    changed("Import", source, players, "Spieler", count, "Reserves", replaceAll and "ersetzt" or "zusammengeführt")
    ns:Fire("SESSION_FULL_SYNC")
    self:ResolveImportedPlayers()
    return true, players, count
end

-- Importierte Spieler mit vorläufigem Schlüssel dem echten Gruppenmitglied zuordnen, sobald es
-- in der Gruppe ist (Import vor dem Einladen; Forever-Nachnamen fehlen im Export).
function Session:ResolveImportedPlayers()
    local s = self:Get()
    if not s or not self:IsOwner() then return end
    local moves = {}
    for player, list in pairs(s.reserves) do
        local importName = list[1] and list[1].importName
        if importName then
            local real = ns.ResolvePlayerName(importName)
            if real and real ~= player then
                table.insert(moves, { from = player, to = real })
            elseif real then
                for _, entry in ipairs(list) do
                    entry.importName = nil
                end
            end
        end
    end
    for _, move in ipairs(moves) do
        local list = s.reserves[move.from]
        s.reserves[move.from] = nil
        for _, entry in ipairs(list) do
            entry.importName = nil
        end
        if s.reserves[move.to] then
            -- Der Spieler hat schon eigene Reserves: der Import ergänzt sie
            for _, entry in ipairs(list) do
                table.insert(s.reserves[move.to], entry)
            end
        else
            s.reserves[move.to] = list
        end
        changed("Import zugeordnet", move.from, "->", move.to)
        ns:Fire("SESSION_RESERVES_CHANGED", move.from) -- leert den vorläufigen Eintrag bei den Raidern
        ns:Fire("SESSION_RESERVES_CHANGED", move.to)
    end
end

ns:On("ROSTER_CHANGED", function()
    Session:ResolveImportedPlayers()
end)

-- Übernahme der Regeln vom Raidlead (Spiegel der Master-Liste).
function Session:ApplyRemoteSession(info)
    local s = self:Get()
    if not s or s.id ~= info.id then
        s = { id = info.id, reserves = {} }
        ns.db.session = s
    elseif info.instanceKey ~= s.instanceKey then
        wipe(s.reserves)
    end
    s.leader = info.leader
    s.instanceKey = info.instanceKey
    s.instanceName = info.instanceName
    s.maxReserves = info.maxReserves
    s.allowDuplicates = info.allowDuplicates
    s.locked = info.locked
    changed("Sitzung vom Raidlead übernommen", info.id, info.leader)
end

function Session:ApplyRemoteReserves(player, itemIDs, source)
    local s = self:Get()
    if not s then return end
    if #itemIDs == 0 then
        s.reserves[player] = nil
    else
        local list = {}
        for i, itemID in ipairs(itemIDs) do
            list[i] = { itemID = itemID, source = source or "ingame" }
        end
        s.reserves[player] = list
    end
    changed("Reserves übernommen", player, table.concat(itemIDs, ","))
end

-- Vor einem vollständigen Stand vom Raidlead: alte Reserves verwerfen.
function Session:ApplyRemoteFullReset(sessionID)
    local s = self:Get()
    if s and s.id == sessionID then
        wipe(s.reserves)
        changed("Voller Stand vom Raidlead folgt", sessionID)
    end
end

function Session:ApplyRemoteEnd(sessionID)
    local s = self:Get()
    if s and s.id == sessionID then
        ns.db.session = nil
        changed("Sitzung vom Raidlead beendet", sessionID)
    end
end

-- Liefert { ["Name-Realm"] = Anzahl } für ein Item.
function Session:GetReservesForItem(itemID)
    local result = {}
    local s = self:Get()
    if not s then return result end
    for player, list in pairs(s.reserves) do
        for i = 1, #list do
            if list[i].itemID == itemID then
                result[player] = (result[player] or 0) + 1
            end
        end
    end
    return result
end
