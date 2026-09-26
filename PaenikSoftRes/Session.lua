-- Datenmodell der Soft-Reserve-Sitzungen (ohne UI).
-- Der Raidlead kann mehrere Sitzungen verwalten (mehrere Raids); eine davon ist aktiv und wird an die
-- Gruppe synchronisiert. Raider spiegeln die aktive Sitzung des Gruppenleiters.
--   ns.db.sessions        = { [id] = session }   eigene Sitzungen
--   ns.db.activeSessionId = id                   aktive eigene Sitzung
--   ns.db.remoteSession   = session              Spiegel vom Gruppenleiter (nur Raider)
-- session = {
--     id, leader, createdAt,
--     name, nameAuto,  -- Anzeigename; nameAuto = true, solange er automatisch vergeben ist
--     instanceKey,     -- "providerID:key", siehe Data/LootData.lua
--     instanceName,
--     maxReserves, allowDuplicates, locked,
--     deadline,        -- optionaler Anmeldeschluss (GetServerTime-Zeitstempel), danach gesperrt
--     reserves = { ["Name-Realm"] = { { itemID = 123, source = "ingame" }, ... } },
--     history,         -- vergebene Items (Rolls.lua)
-- }
local _, ns = ...

local Session = {}
ns.Session = Session

Session.MAX_RESERVES_LIMIT = 5
local MAX_NAME_LENGTH = 40

local RULE_KEYS = {
    instanceKey = true,
    instanceName = true,
    maxReserves = true,
    allowDuplicates = true,
    locked = true,
    deadline = true, -- 0 entfernt den Anmeldeschluss
}

-- Ereignisse:
--   SESSION_CHANGED                 bei jeder Änderung (für die UI)
--   SESSION_RULES_CHANGED           aktive eigene Sitzung: neu angelegt oder Regeln geändert
--   SESSION_RESERVES_CHANGED(player) aktive eigene Sitzung: Reserves eines Spielers geändert
--   SESSION_FULL_SYNC               aktive eigene Sitzung komplett neu verteilen (z. B. Wechsel)
--   SESSION_ENDED(sessionID)        eigene Sitzung verworfen
-- Übernahmen vom Raidlead (Apply*) lösen nur SESSION_CHANGED aus, damit nichts zurückgesendet wird.
local function changed(reason, ...)
    ns.Debug("Session", reason, ...)
    ns:Fire("SESSION_CHANGED")
end

-- Eigene Sitzung wurde geändert: Version erhöhen (für die Gilden-Synchronisation, GuildSync.lua)
function Session:Touch(s)
    if not s then return end
    s.version = (s.version or 0) + 1
    s.updatedAt = GetServerTime()
    ns:Fire("OWN_SESSION_CHANGED", s)
end

local function ownSessions()
    if not ns.db then return {} end
    ns.db.sessions = ns.db.sessions or {}
    return ns.db.sessions
end

local function ownActive()
    local db = ns.db
    return db and db.activeSessionId and db.sessions and db.sessions[db.activeSessionId] or nil
end

-- Die „aktuelle“ Sitzung: für Raider in einer Gruppe der Spiegel des Gruppenleiters,
-- sonst die aktive eigene Sitzung.
function Session:Get()
    if not ns.db then return nil end
    if not ns.Roles:IsLead() then
        return ns.db.remoteSession
    end
    return ownActive()
end

function Session:GetRemote()
    return ns.db and ns.db.remoteSession
end

-- Eigene Sitzungen, älteste zuerst
function Session:List()
    local list = {}
    for _, s in pairs(ownSessions()) do
        table.insert(list, s)
    end
    table.sort(list, function(a, b) return (a.createdAt or 0) < (b.createdAt or 0) end)
    return list
end

-- Sitzungen, die im Raider-Tab wählbar sind: Gruppensitzung, eigene, Gildenkopien.
-- Einträge { session = s, kind = "group" | "own" | "guild" }
function Session:ListViewable()
    local list = {}
    local current = self:Get()
    local remote = self:GetRemote()
    local groupID
    if remote and current == remote then
        table.insert(list, { session = remote, kind = "group" })
        groupID = remote.id
    end
    for _, s in ipairs(self:List()) do
        table.insert(list, { session = s, kind = "own" })
    end
    local guild = {}
    local myKey = ns.FullName("player")
    local guildSessions = (ns.db and ns.db.guildSync ~= false) and ns.db.guildSessions or {}
    for id, s in pairs(guildSessions) do
        if id ~= groupID and s.leader ~= myKey and not s.deleted then
            table.insert(guild, s)
        end
    end
    table.sort(guild, function(a, b) return (a.deadline or math.huge) < (b.deadline or math.huge) end)
    for _, s in ipairs(guild) do
        table.insert(list, { session = s, kind = "guild" })
    end
    return list
end

-- Im Raider-Tab und in der Übersicht angezeigte Sitzung (Auswahl db.viewSessionId, sonst die aktuelle)
-- (direkte Suche statt ListViewable: wird sehr oft aufgerufen, z. B. bei jedem Tooltip)
function Session:GetViewed()
    if not ns.db then return nil end
    local current = self:Get()
    local remote = self:GetRemote()
    local isGroup = remote ~= nil and current == remote
    local wanted = ns.db.viewSessionId
    if wanted then
        if isGroup and remote.id == wanted then
            return remote, "group"
        end
        local own = ns.db.sessions and ns.db.sessions[wanted]
        if own then
            return own, "own"
        end
        local copy = ns.db.guildSync ~= false and ns.db.guildSessions and ns.db.guildSessions[wanted]
        if copy and not copy.deleted and copy.leader ~= ns.FullName("player") then
            return copy, "guild"
        end
    end
    -- Nichts (mehr) gewählt: aktuelle Sitzung (Raidlead: aktive, Raider in der Gruppe: Gruppensitzung)
    if current then
        return current, isGroup and "group" or "own"
    end
    local first = self:ListViewable()[1]
    return first and first.session, first and first.kind
end

function Session:SetViewed(id)
    ns.db.viewSessionId = id
    ns:Fire("SESSION_CHANGED")
end

function Session:GetActiveID()
    return ns.db and ns.db.activeSessionId
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

local function isLocked(s)
    return s.locked == true or (s.deadline ~= nil and GetServerTime() >= s.deadline)
end

-- Gesperrt: manuell gesperrt oder Anmeldeschluss erreicht (gilt auch bei Raidern ohne Nachricht vom Lead)
function Session:IsLocked(s)
    s = s or self:Get()
    return s ~= nil and isLocked(s)
end

-- Automatischer Name: „Instanz – Tag“
local function autoName(s)
    local day = ns.UI and ns.UI.FormatDate and ns.UI.FormatDate(s.createdAt or GetServerTime(), false) or ""
    return (s.instanceName or "Neue Sitzung") .. " – " .. day
end

local function newSession(leader)
    local now = GetServerTime()
    local s = {
        id = string.format("%s-%d-%d", leader or "?", now, math.random(100, 999)),
        leader = leader,
        createdAt = now,
        maxReserves = 1,
        allowDuplicates = true,
        locked = false,
        reserves = {},
        nameAuto = true,
    }
    s.name = autoName(s)
    return s
end

-- Neue Sitzung anlegen und aktivieren (die bisherige bleibt erhalten)
function Session:New(leader)
    local s = newSession(leader)
    ownSessions()[s.id] = s
    ns.db.activeSessionId = s.id
    changed("Neue Sitzung", s.id)
    Session:Touch(s)
    ns:Fire("SESSION_RULES_CHANGED")
    return s
end

-- Eigene Sitzung aktivieren: sie wird ab jetzt an die Gruppe verteilt
function Session:SetActive(id)
    if not ownSessions()[id] or ns.db.activeSessionId == id then return false end
    ns.db.activeSessionId = id
    changed("Aktive Sitzung", id)
    ns:Fire("SESSION_FULL_SYNC")
    return true
end

-- Aktive eigene Sitzung löschen; danach ist keine Sitzung aktiv
function Session:Reset()
    local s = ownActive()
    if not s then return end
    ownSessions()[s.id] = nil
    ns.db.activeSessionId = nil
    changed("Sitzung verworfen", s.id)
    ns:Fire("OWN_SESSION_DELETED", s)
    ns:Fire("SESSION_ENDED", s.id)
end

function Session:Rename(name)
    local s = ownActive()
    if not s then return false end
    name = strtrim((name or ""):gsub("[%^;=,|]", "") or "") -- Klammern: nur der erste Rückgabewert von gsub
    if name == "" then
        s.nameAuto = true
        s.name = autoName(s)
    else
        s.nameAuto = false
        s.name = name:sub(1, MAX_NAME_LENGTH)
    end
    changed("Sitzung umbenannt", s.name)
    Session:Touch(s)
    ns:Fire("SESSION_RULES_CHANGED")
    return true
end

-- Neuer Gruppenleiter übernimmt die gespiegelte Sitzung des bisherigen Leads als eigene Sitzung.
function Session:TakeOver(leader)
    local old = self:GetRemote()
    if not old or old.leader == leader then return false end
    local reserves = {}
    for player, list in pairs(old.reserves) do
        reserves[player] = CopyTable(list)
    end
    local s = newSession(leader)
    s.instanceKey = old.instanceKey
    s.instanceName = old.instanceName
    s.maxReserves = old.maxReserves or 1
    s.allowDuplicates = old.allowDuplicates
    s.locked = old.locked
    s.deadline = old.deadline
    s.reserves = reserves
    s.history = old.history and CopyTable(old.history) or nil
    s.name = old.name or autoName(s)
    s.nameAuto = old.name == nil
    ownSessions()[s.id] = s
    ns.db.activeSessionId = s.id
    changed("Sitzung übernommen von", old.leader)
    Session:Touch(s)
    ns:Fire("SESSION_FULL_SYNC")
    return true
end

-- Regeln auf eine eigene Sitzung anwenden; nur die aktive wird an die Gruppe verteilt
local function applyRules(s, rules)
    -- Reserves gehören zu einer Instanz: bei einem Wechsel verfallen sie.
    if rules.instanceKey ~= nil and rules.instanceKey ~= s.instanceKey and next(s.reserves) then
        wipe(s.reserves)
        ns.Debug("Session", "Instanz gewechselt, Reserves verworfen")
    end
    local parts = {}
    for key, value in pairs(rules) do
        if RULE_KEYS[key] then
            if key == "deadline" and value == 0 then
                value = nil
            end
            s[key] = value
            table.insert(parts, key .. "=" .. tostring(value))
        end
    end
    if rules.instanceName and s.nameAuto then
        s.name = autoName(s)
    end
    changed("Regeln geändert:", table.concat(parts, ", "))
    Session:Touch(s)
    if s == ownActive() then
        ns:Fire("SESSION_RULES_CHANGED")
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
    applyRules(s, rules)
    return true
end

function Session:SetLocked(locked)
    local s = self:Get()
    if not locked and s and s.deadline and GetServerTime() >= s.deadline then
        -- Wieder öffnen nach dem Anmeldeschluss: Schluss entfernen, sonst sperrt er sofort erneut
        return self:SetRules({ locked = false, deadline = 0 })
    end
    return self:SetRules({ locked = locked and true or false })
end

-- Anmeldeschluss überwachen: eigene Sitzungen sperren (die aktive wird verteilt und angesagt),
-- beim Spiegel des Raiders nur die Anzeige aktualisieren.
local deadlineTimers = {} -- [session] = { timer, deadline }

local function onDeadline(s)
    deadlineTimers[s] = nil
    if not s.deadline or GetServerTime() < s.deadline then return end
    -- Die Sitzung wird NICHT hart gesperrt: der Anmeldeschluss sperrt über IsLocked() ohnehin, und
    -- rechtzeitig abgegebene Gilden-Anmeldungen (signedAt) müssen auch danach noch angenommen werden.
    if s.leader == ns.FullName("player") and ownSessions()[s.id] and not s.locked then
        if s == ownActive() and Session:IsMaster() then
            ns.Print("Anmeldeschluss erreicht – die Soft Reserves sind geschlossen.")
            if ns.GroupChannel() then
                ns.SendGroupChat("Soft Reserves sind geschlossen (Anmeldeschluss erreicht).")
            end
        else
            ns.Print("Anmeldeschluss erreicht für „" .. (s.name or "?") .. "“.")
        end
    end
    ns:Fire("SESSION_CHANGED")
end

-- Timer nur für Anmeldeschlüsse in der Zukunft (sonst würde ein vergangener Schluss immer wieder feuern)
local function scheduleDeadlines()
    local now = GetServerTime()
    local wanted = {}
    local function consider(s)
        if s and s.deadline and not s.locked and not s.deleted and s.deadline > now then
            wanted[s] = s.deadline
        end
    end
    for _, s in pairs(ownSessions()) do
        consider(s)
    end
    consider(Session:GetRemote())
    for _, s in pairs(ns.db and ns.db.guildSessions or {}) do
        consider(s)
    end
    -- nicht mehr benötigte oder geänderte Timer abbrechen
    for s, entry in pairs(deadlineTimers) do
        if wanted[s] ~= entry.deadline then
            entry.timer:Cancel()
            deadlineTimers[s] = nil
        end
    end
    for s, deadline in pairs(wanted) do
        if not deadlineTimers[s] then
            local timer = C_Timer.NewTimer(deadline - now + 1, function()
                onDeadline(s)
            end)
            deadlineTimers[s] = { timer = timer, deadline = deadline }
        end
    end
end

ns:On("SESSION_CHANGED", scheduleDeadlines)
ns:On("LOGIN", scheduleDeadlines)

-- Umstellung von einer Einzelsitzung (db.session, bis DB-Version 1) auf mehrere Sitzungen
function Session:MigrateSingleSession()
    local old = ns.db.session
    if not old then return end
    ns.db.session = nil
    if old.leader == ns.FullName("player") then
        old.name = old.name or autoName(old)
        old.nameAuto = old.nameAuto ~= false
        ownSessions()[old.id] = old
        ns.db.activeSessionId = old.id
        ns.Debug("Session", "Migration: eigene Sitzung übernommen", old.id)
    else
        ns.db.remoteSession = old
        ns.Debug("Session", "Migration: Spiegel übernommen", old.id)
    end
    changed("Migration abgeschlossen")
end

-- Die folgenden Funktionen arbeiten auf der Sitzung s; ohne s auf der aktuellen (Session:Get()).
function Session:GetReserves(player, s)
    s = s or self:Get()
    return s and s.reserves[player]
end

function Session:CountReserves(player, s)
    local list = self:GetReserves(player, s)
    return list and #list or 0
end

-- ItemIDs der Reserves eines Spielers als einfache Liste.
function Session:GetReservedItemIDs(player, s)
    local ids = {}
    local list = self:GetReserves(player, s)
    if list then
        for i = 1, #list do
            ids[i] = list[i].itemID
        end
    end
    return ids
end

-- Menge aller ItemIDs der gewählten Instanz (gecacht pro instanceKey).
local itemSetCache = {}

function Session:GetInstanceItemSet(s)
    s = s or self:Get()
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

-- Prüft eine komplette Reserve-Liste gegen die Regeln der Sitzung s.
-- player (optional): Verkleinern einer bestehenden Liste ist immer erlaubt,
-- auch wenn der Raidlead das Limit inzwischen gesenkt hat.
-- signedAt (optional): Abgabezeitpunkt einer Anmeldung über die Gilde; der Anmeldeschluss wird dann
-- gegen diesen Zeitpunkt statt gegen „jetzt“ geprüft.
function Session:ValidateReserves(itemIDs, player, s, signedAt)
    s = s or self:Get()
    if not s then return false, "Keine Sitzung" end
    if s.locked then return false, "Sitzung ist gesperrt" end
    if s.deadline and (signedAt or GetServerTime()) >= s.deadline then
        return false, "Anmeldeschluss erreicht"
    end
    if not s.instanceKey then return false, "Keine Instanz gewählt" end
    local current = player and self:CountReserves(player, s) or 0
    if #itemIDs > s.maxReserves and #itemIDs >= current then
        return false, "Limit erreicht (" .. s.maxReserves .. ")"
    end
    local itemSet = self:GetInstanceItemSet(s) or {}
    -- Items, die der Spieler schon hat (z. B. aus einem softres.it-Import mit eigenen Regeln),
    -- bleiben erlaubt – sonst könnte er seine Liste nicht mehr bearbeiten.
    local existing = {}
    if player then
        for _, itemID in ipairs(self:GetReservedItemIDs(player, s)) do
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

-- Setzt die Reserves eines Spielers in einer eigenen Sitzung (geprüft).
-- s (optional, Standard: aktuelle Sitzung), signedAt (optional, Anmeldung über die Gilde).
function Session:SetPlayerReserves(player, itemIDs, source, s, signedAt)
    s = s or self:Get()
    if not s or s.leader ~= ns.FullName("player") then return false, "Nicht Besitzer der Sitzung" end
    local ok, err = self:ValidateReserves(itemIDs, player, s, signedAt)
    if not ok then
        ns.Debug("Session", "Reserves abgelehnt", player, err)
        return false, err
    end
    if #itemIDs == 0 then
        s.reserves[player] = nil
    else
        local list = {}
        local receivedAt = signedAt and GetServerTime() or nil
        for i, itemID in ipairs(itemIDs) do
            list[i] = { itemID = itemID, source = source or "ingame", signedAt = signedAt, receivedAt = receivedAt }
        end
        s.reserves[player] = list
    end
    -- Zeitpunkt der letzten Auswahl je Spieler: eine ältere Gilden-Anmeldung darf eine neuere
    -- Auswahl (z. B. in der Gruppe) nicht überschreiben
    s.changedAt = s.changedAt or {}
    s.changedAt[player] = signedAt or GetServerTime()
    changed("Reserves gesetzt", player, table.concat(itemIDs, ","))
    Session:Touch(s)
    if s == ownActive() then
        ns:Fire("SESSION_RESERVES_CHANGED", player)
    end
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
    Session:Touch(s)
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
        Session:Touch(s)
        ns:Fire("SESSION_RESERVES_CHANGED", move.from) -- leert den vorläufigen Eintrag bei den Raidern
        ns:Fire("SESSION_RESERVES_CHANGED", move.to)
    end
end

ns:On("ROSTER_CHANGED", function()
    Session:ResolveImportedPlayers()
end)

-- Übernahme der Regeln vom Raidlead (Spiegel der Master-Liste).
function Session:ApplyRemoteSession(info)
    local s = self:GetRemote()
    if not s or s.id ~= info.id then
        s = { id = info.id, reserves = {} }
        ns.db.remoteSession = s
    elseif info.instanceKey ~= s.instanceKey then
        wipe(s.reserves)
    end
    s.name = info.name
    s.leader = info.leader
    s.instanceKey = info.instanceKey
    s.instanceName = info.instanceName
    s.maxReserves = info.maxReserves
    s.allowDuplicates = info.allowDuplicates
    s.locked = info.locked
    s.deadline = info.deadline
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
    local s = self:GetRemote()
    if s and s.id == sessionID then
        ns.db.remoteSession = nil
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
