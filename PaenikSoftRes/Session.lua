-- Datenmodell der Soft-Reserve-Sitzungen (ohne UI).
-- Der Raidlead kann mehrere Sitzungen verwalten (mehrere Raids); eine davon ist aktiv und wird an die
-- Gruppe synchronisiert. Raider spiegeln die aktive Sitzung des Gruppenleiters.
--   ns.char.sessions        = { [id] = session }   eigene Sitzungen
--   ns.char.activeSessionId = id                   aktive eigene Sitzung
--   ns.char.remoteSession   = session              Spiegel vom Gruppenleiter (nur Raider)
-- ns.char = PaenikSoftResCharDB (pro Charakter): Sitzungen, Spiegel, Anmeldungen, Gildenkopien.
-- ns.db = PaenikSoftResDB (Account): Einstellungen, Wunschliste/Bank-Speicher (nach Charakter geschlüsselt).
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
    ns.char.sessions = ns.char.sessions or {}
    return ns.char.sessions
end

local function ownActive()
    local char = ns.char
    return char and char.activeSessionId and char.sessions and char.sessions[char.activeSessionId] or nil
end

-- Die „aktuelle“ Sitzung: für Raider in einer Gruppe der Spiegel des Gruppenleiters,
-- sonst die aktive eigene Sitzung.
function Session:Get()
    if not ns.db then return nil end
    if not ns.Roles:IsLead() then
        return ns.char.remoteSession
    end
    return ownActive()
end

function Session:GetRemote()
    return ns.char and ns.char.remoteSession
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
    local guildSessions = (ns.db and ns.db.guildSync ~= false) and ns.char.guildSessions or {}
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
    local wanted = ns.char.viewSessionId
    if wanted then
        if isGroup and remote.id == wanted then
            return remote, "group"
        end
        local own = ns.char.sessions and ns.char.sessions[wanted]
        if own then
            return own, "own"
        end
        local copy = ns.db.guildSync ~= false and ns.char.guildSessions and ns.char.guildSessions[wanted]
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
    ns.char.viewSessionId = id
    ns:Fire("SESSION_CHANGED")
end

function Session:GetActiveID()
    return ns.char and ns.char.activeSessionId
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

-- Sitzung aus einer Vorlage für regelmäßige Raids (Templates.lua) für den Termin raidAt anlegen.
-- Wird nur aktiv, wenn gerade keine eigene Sitzung aktiv ist (die Gruppe wird nicht umgeschaltet).
-- Name einer Sitzung aus einer Vorlage, z. B. „MC Dienstag – Di, 30.09.“
function Session.TemplateSessionName(t, raidAt)
    return (t.name or t.instanceName or "Raid") .. " – " .. ns.UI.FormatDate(raidAt, false)
end

-- Anmeldeschluss einer Vorlage für den Termin raidAt (nil = keiner)
function Session.TemplateDeadline(t, raidAt)
    local hours = t.deadlineHours or -1 -- -1 = keiner, 0 = bei Raidbeginn
    return hours >= 0 and (raidAt - hours * 3600) or nil
end

function Session:CreateFromTemplate(t, raidAt)
    local s = newSession(ns.FullName("player"))
    s.instanceKey = t.instanceKey
    s.instanceName = t.instanceName
    s.maxReserves = t.maxReserves or 1
    s.allowDuplicates = t.allowDuplicates and true or false
    s.templateId = t.id
    s.raidAt = raidAt
    s.name = Session.TemplateSessionName(t, raidAt)
    s.nameAuto = false
    -- Schon verstrichener Schluss (Sitzung kurz vor dem Raid angelegt): Anmeldung bis Raidbeginn
    local deadline = Session.TemplateDeadline(t, raidAt)
    if deadline and deadline <= GetServerTime() then
        deadline = raidAt
    end
    if deadline and deadline > GetServerTime() then
        s.deadline = deadline
    end
    ownSessions()[s.id] = s
    if not ownActive() then
        ns.char.activeSessionId = s.id
    end
    changed("Sitzung aus Vorlage", t.id, s.id)
    Session:Touch(s)
    if s == ownActive() then
        ns:Fire("SESSION_RULES_CHANGED")
    end
    return s
end

-- Neue Sitzung anlegen und aktivieren (die bisherige bleibt erhalten)
function Session:New(leader)
    local s = newSession(leader)
    ownSessions()[s.id] = s
    ns.char.activeSessionId = s.id
    changed("Neue Sitzung", s.id)
    Session:Touch(s)
    ns:Fire("SESSION_RULES_CHANGED")
    return s
end

-- Eigene Sitzung aktivieren: sie wird ab jetzt an die Gruppe verteilt
function Session:SetActive(id)
    if not ownSessions()[id] or ns.char.activeSessionId == id then return false end
    ns.char.activeSessionId = id
    changed("Aktive Sitzung", id)
    ns:Fire("SESSION_FULL_SYNC")
    return true
end

-- Aktive eigene Sitzung löschen; danach ist keine Sitzung aktiv
function Session:Reset()
    local s = ownActive()
    if not s then return end
    ownSessions()[s.id] = nil
    ns.char.activeSessionId = nil
    changed("Sitzung verworfen", s.id)
    ns:Fire("OWN_SESSION_DELETED", s)
    ns:Fire("SESSION_ENDED", s.id)
end

-- Beliebige eigene Sitzung löschen (Aufräumen vergangener Sitzungen); die aktive über Reset,
-- damit die Gruppe informiert wird. Veröffentlichte bekommen eine Löschmarke (GuildSync).
function Session:DeleteSession(s)
    if not s or not ownSessions()[s.id] then return false end
    if s == ownActive() then
        self:Reset()
        return true
    end
    ownSessions()[s.id] = nil
    changed("Sitzung gelöscht", s.id)
    ns:Fire("OWN_SESSION_DELETED", s)
    return true
end

-- Vergangen = Sitzung mit Termin (aus einer Vorlage), deren Raid begonnen hat
function Session.IsPast(s, now)
    return s.raidAt ~= nil and s.raidAt <= (now or GetServerTime())
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
    ns.char.activeSessionId = s.id
    changed("Sitzung übernommen von", old.leader)
    Session:Touch(s)
    ns:Fire("SESSION_FULL_SYNC")
    return true
end

-- Gelegte Bosse (Index in LootData:GetEncounters) markieren; nur eigene Sitzungen
function Session:SetBossKilled(s, index, killed)
    if not s or s.leader ~= ns.FullName("player") or type(index) ~= "number" or index < 1 then return false end
    s.killed = s.killed or {}
    s.killed[index] = killed and true or nil
    changed("Boss gelegt", index, killed)
    Session:Touch(s)
    if s == ownActive() then
        ns:Fire("SESSION_RULES_CHANGED")
    end
    return true
end

function Session:IsBossKilled(s, index)
    return s ~= nil and s.killed ~= nil and s.killed[index] == true
end

-- Gelegte Bosse als Text "1,4,7" (Sync) und zurück
function Session:KilledToString(s)
    local list = {}
    for index in pairs(s and s.killed or {}) do
        table.insert(list, index)
    end
    table.sort(list)
    return table.concat(list, ",")
end

function Session:KilledFromString(text)
    local killed
    for index in (text or ""):gmatch("%d+") do
        killed = killed or {}
        killed[tonumber(index)] = true
    end
    return killed
end

-- Neue Sitzung, die dieselbe Raid-ID fortführt: gleiche Instanz und Regeln, gelegte Bosse bleiben
-- markiert; keine Reserves, kein Verlauf, kein Anmeldeschluss. Wird aktiv.
function Session:Continue()
    local old = ownActive()
    if not old then return false end
    local s = newSession(old.leader)
    s.instanceKey = old.instanceKey
    s.instanceName = old.instanceName
    s.maxReserves = old.maxReserves or 1
    s.allowDuplicates = old.allowDuplicates
    s.killed = old.killed and CopyTable(old.killed) or nil
    s.parentId = old.id
    s.name = (old.name or autoName(old)) .. " (Fortsetzung)"
    s.nameAuto = false
    ownSessions()[s.id] = s
    ns.char.activeSessionId = s.id
    changed("Sitzung fortgeführt", old.id, "->", s.id)
    Session:Touch(s)
    ns:Fire("SESSION_RULES_CHANGED")
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

-- Geänderte Vorlage auf eine ihrer Sitzungen übertragen (Knopf „Aktualisieren“). raidAt = neuer Termin.
-- Wie SetRules: ein Instanzwechsel verwirft die Reserves (die UI fragt vorher nach); die aktive Sitzung
-- wird an die Gruppe verteilt. Ein bereits verstrichener Anmeldeschluss wird nicht neu gesetzt.
function Session:ApplyTemplate(s, t, raidAt)
    if not s or s.leader ~= ns.FullName("player") then return false end
    local rules = {
        instanceKey = t.instanceKey,
        instanceName = t.instanceName,
        maxReserves = t.maxReserves or 1,
        allowDuplicates = t.allowDuplicates and true or false,
    }
    local deadline = Session.TemplateDeadline(t, raidAt)
    if deadline and deadline <= GetServerTime() then
        deadline = raidAt -- verstrichen: Anmeldung bis Raidbeginn
    end
    if not deadline then
        rules.deadline = 0
    elseif deadline > GetServerTime() then
        rules.deadline = deadline
    end
    s.raidAt = raidAt
    s.name = Session.TemplateSessionName(t, raidAt)
    s.nameAuto = false
    applyRules(s, rules)
    return true
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
    for _, s in pairs(ns.char and ns.char.guildSessions or {}) do
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
        ns.char.activeSessionId = old.id
        ns.Debug("Session", "Migration: eigene Sitzung übernommen", old.id)
    else
        ns.char.remoteSession = old
        ns.Debug("Session", "Migration: Spiegel übernommen", old.id)
    end
    changed("Migration abgeschlossen")
end

-- Umstellung account-weiter Sitzungsdaten (PaenikSoftResDB) auf pro Charakter (PaenikSoftResCharDB).
-- Eigene Sitzungen gehen an den Charakter, der sie angelegt hat (leader); die anderen bleiben liegen, bis
-- ihr Charakter sich einloggt. Spiegel, Gildenkopien und weitergereichte Anmeldungen bekommt der erste
-- Charakter (sie werden ohnehin neu synchronisiert). Eigene Anmeldungen (signups) lassen sich keinem
-- Charakter zuordnen und werden verworfen – sonst gingen sie unter falschem Namen an den Raidlead.
function Session:MigrateToCharacter()
    local db, char = ns.db, ns.char
    if not db or not char then return end
    local me = ns.FullName("player")
    local moved = 0
    if db.sessions then
        for id, s in pairs(db.sessions) do
            if s.leader == me then
                ownSessions()[id] = s
                db.sessions[id] = nil
                moved = moved + 1
                if db.activeSessionId == id then
                    char.activeSessionId = id
                    db.activeSessionId = nil
                end
            end
        end
        if next(db.sessions) == nil then
            db.sessions = nil
            db.activeSessionId = nil
        end
    end
    for _, key in ipairs({ "remoteSession", "viewSessionId", "relaySignups", "guildSessions" }) do
        if db[key] ~= nil then
            if char[key] == nil then
                char[key] = db[key]
            end
            db[key] = nil
        end
    end
    if db.signups then
        ns.Debug("Session", "Migration: account-weite Anmeldungen verworfen")
        db.signups = nil
    end
    if moved > 0 then
        changed("Migration: Sitzungen für diesen Charakter übernommen", moved)
    end
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

-- Hard Reserves: fest vergebene Items (session.hardReserves[itemID] = { note = "Empfänger/Notiz" }).
-- Nicht reservierbar, werden nicht ausgewürfelt.
local MAX_NOTE_LENGTH = 30

function Session:GetHardReserve(itemID, s)
    s = s or self:Get()
    return s and s.hardReserves and s.hardReserves[itemID]
end

-- Anzahl Soft Reserves auf einem Item (für die Rückfrage vor einem Hard Reserve)
function Session:CountReservesOnItem(itemID, s)
    local count = 0
    for _, list in pairs(s and s.reserves or {}) do
        for _, entry in ipairs(list) do
            if entry.itemID == itemID then
                count = count + 1
            end
        end
    end
    return count
end

local function hardReservesChanged(s, reason, ...)
    changed(reason, ...)
    Session:Touch(s)
    if s == ownActive() then
        ns:Fire("SESSION_HR_CHANGED")
    end
end

-- Hard Reserve setzen; vorhandene Soft Reserves auf dem Item werden entfernt
function Session:SetHardReserve(s, itemID, note)
    if not s or s.leader ~= ns.FullName("player") or type(itemID) ~= "number" then return false end
    note = strtrim((note or ""):gsub("[%^;=,|]", "") or ""):sub(1, MAX_NOTE_LENGTH)
    for player, list in pairs(s.reserves) do
        local removed = false
        for i = #list, 1, -1 do
            if list[i].itemID == itemID then
                table.remove(list, i)
                removed = true
            end
        end
        if removed then
            if #list == 0 then
                s.reserves[player] = nil
            end
            if s == ownActive() then
                ns:Fire("SESSION_RESERVES_CHANGED", player)
            end
        end
    end
    s.hardReserves = s.hardReserves or {}
    s.hardReserves[itemID] = { note = note }
    hardReservesChanged(s, "Hard Reserve gesetzt", itemID, note)
    return true
end

function Session:RemoveHardReserve(s, itemID)
    if not s or s.leader ~= ns.FullName("player") or not (s.hardReserves and s.hardReserves[itemID]) then
        return false
    end
    s.hardReserves[itemID] = nil
    hardReservesChanged(s, "Hard Reserve entfernt", itemID)
    return true
end

-- Hard Reserves als Text "itemID=Notiz;..." (Sync) und zurück
function Session:HardReservesToList(s)
    local list = {}
    for itemID, entry in pairs(s and s.hardReserves or {}) do
        table.insert(list, itemID .. "=" .. (entry.note or ""))
    end
    table.sort(list)
    return list
end

function Session:ApplyHardReserveEntries(s, text)
    s.hardReserves = s.hardReserves or {}
    for entry in (text or ""):gmatch("[^;]+") do
        local itemID, note = entry:match("^(%d+)=(.*)$")
        if itemID then
            s.hardReserves[tonumber(itemID)] = { note = note }
        end
    end
end

-- Items, die NUR von bereits gelegten Bossen droppen (nicht mehr reservierbar)
function Session:GetKilledOnlyItems(s)
    s = s or self:Get()
    local result = {}
    if not s or not s.instanceKey or not s.killed or not next(s.killed) then return result end
    local alive = {}
    for index, encounter in ipairs(ns.LootData:GetDisplayEncounters(s.instanceKey)) do
        if not s.killed[index] then
            for _, itemID in ipairs(encounter.items) do
                alive[itemID] = true
            end
        end
    end
    for index in pairs(s.killed) do
        local encounter = ns.LootData:GetDisplayEncounters(s.instanceKey)[index]
        for _, itemID in ipairs(encounter and encounter.items or {}) do
            if not alive[itemID] then
                result[itemID] = true
            end
        end
    end
    return result
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
    local killedOnly = self:GetKilledOnlyItems(s)
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
            if killedOnly[itemID] then
                return false, "Der Boss für dieses Item ist bereits gelegt"
            end
            if s.hardReserves and s.hardReserves[itemID] then
                return false, "Item ist Hard Reserve"
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

-- Raidlead trägt eine Reserve für einen Spieler ein (z. B. ohne dieses Addon). Quelle "lead".
-- Gesperrt/Anmeldeschluss gelten nicht (der Raidlead entscheidet); Instanz, gelegte Bosse, Hard
-- Reserves und doppelte Items werden geprüft. Über dem Limit: false, "limit", außer mit force.
-- importName (optional): eingegebener Name, solange der Spieler keinem Gruppenmitglied zugeordnet ist.
function Session:AddLeadReserve(s, player, itemID, importName, force)
    if not s or s.leader ~= ns.FullName("player") then return false, "Nicht Besitzer der Sitzung" end
    if not s.instanceKey then return false, "Keine Instanz gewählt" end
    local itemSet = self:GetInstanceItemSet(s) or {}
    if not itemSet[itemID] then return false, "Item gehört nicht zur Instanz" end
    if self:GetKilledOnlyItems(s)[itemID] then return false, "Der Boss für dieses Item ist bereits gelegt" end
    if s.hardReserves and s.hardReserves[itemID] then return false, "Item ist Hard Reserve" end
    local ids = self:GetReservedItemIDs(player, s)
    if not s.allowDuplicates then
        for _, id in ipairs(ids) do
            if id == itemID then
                return false, "Spieler hat das Item bereits reserviert"
            end
        end
    end
    if #ids >= s.maxReserves and not force then
        return false, "limit"
    end
    local list = s.reserves[player] or {}
    table.insert(list, { itemID = itemID, source = "lead", importName = importName })
    s.reserves[player] = list
    s.changedAt = s.changedAt or {}
    s.changedAt[player] = GetServerTime()
    changed("Reserve vom Raidlead eingetragen", player, itemID)
    Session:Touch(s)
    if s == ownActive() then
        ns:Fire("SESSION_RESERVES_CHANGED", player)
    end
    return true
end

-- Raidlead entfernt eine Reserve (ein Vorkommen des Items) eines Spielers aus seiner Sitzung.
function Session:RemovePlayerReserve(s, player, itemID)
    if not s or s.leader ~= ns.FullName("player") then return false end
    local list = s.reserves[player]
    if not list then return false end
    for i = #list, 1, -1 do
        if list[i].itemID == itemID then
            table.remove(list, i)
            if #list == 0 then
                s.reserves[player] = nil
            end
            s.changedAt = s.changedAt or {}
            s.changedAt[player] = GetServerTime()
            changed("Reserve vom Raidlead entfernt", player, itemID)
            Session:Touch(s)
            if s == ownActive() then
                ns:Fire("SESSION_RESERVES_CHANGED", player)
            end
            return true
        end
    end
    return false
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
        ns.char.remoteSession = s
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
    s.killed = info.killed
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
        s.hardReserves = nil
        changed("Voller Stand vom Raidlead folgt", sessionID)
    end
end

-- Hard Reserves vom Raidlead übernehmen (clear = vorher leeren)
function Session:ApplyRemoteHardReserves(sessionID, text, clear)
    local s = self:Get()
    if not s or s.id ~= sessionID then return end
    if clear then
        s.hardReserves = nil
    end
    self:ApplyHardReserveEntries(s, text)
    changed("Hard Reserves vom Raidlead", sessionID)
end

-- Verteilliste („Soft Reserves“-Fenster): Items, die der Raidlead verteilt – aus Leichen (beim Looten)
-- oder aus den Taschen (Drag & Drop). s.lootList = { { itemID, lootKey, addedAt }, ... }; lootKey verbindet
-- Eintrag und Würfel-Ergebnis (Verlauf). Kein Session:Touch: die Liste gehört nicht zur Gilden-Kopie.

-- entries = { { itemID, lootKey }, ... }; gibt die Anzahl neuer Einträge zurück
function Session:AddLootEntries(s, entries)
    if not s then return 0 end
    s.lootList = s.lootList or {}
    local known = {}
    for _, entry in ipairs(s.lootList) do
        known[entry.lootKey] = true
    end
    local added = 0
    for _, entry in ipairs(entries) do
        if entry.itemID and entry.lootKey and not known[entry.lootKey] then
            known[entry.lootKey] = true
            table.insert(s.lootList, { itemID = entry.itemID, lootKey = entry.lootKey, addedAt = GetServerTime() })
            added = added + 1
        end
    end
    if added > 0 then
        changed("Verteilliste ergänzt", added)
    end
    return added
end

function Session:RemoveLootEntry(s, lootKey)
    if not s or not s.lootList then return false end
    for i, entry in ipairs(s.lootList) do
        if entry.lootKey == lootKey then
            table.remove(s.lootList, i)
            changed("Verteilliste: Eintrag entfernt", lootKey)
            return true
        end
    end
    return false
end

function Session:ClearLootList(s)
    if not s or not s.lootList or #s.lootList == 0 then return false end
    s.lootList = {}
    changed("Verteilliste geleert")
    return true
end

-- „itemID=lootKey“-Einträge für die Nachricht L
function Session:LootListToEntries(s)
    local list = {}
    for _, entry in ipairs(s and s.lootList or {}) do
        table.insert(list, entry.itemID .. "=" .. entry.lootKey)
    end
    return list
end

-- Leiche eines Eintrags: Teil des lootKey vor dem ersten „:“ (GUID der Leiche; bei Taschen-Items „bag“)
function Session.LootCorpse(lootKey)
    return lootKey and lootKey:match("^([^:]+):") or nil
end

-- Zuletzt gelootete Leiche (Raidlead): das „Soft Reserves“-Fenster zeigt nur ihre Items
function Session:SetCurrentCorpse(s, corpse)
    if not s or s.currentCorpse == corpse then return end
    s.currentCorpse = corpse
    changed("Aktuelle Leiche", corpse)
end

-- Verteilliste vom Raidlead übernehmen; clear = erstes Stück (vorher leeren), corpse = zuletzt gelootete
-- Leiche. Gibt die Anzahl neuer Einträge zurück.
function Session:ApplyRemoteLootList(sessionID, text, clear, corpse)
    local s = self:Get()
    if not s or s.id ~= sessionID then return 0 end
    if corpse and corpse ~= "" then
        s.currentCorpse = corpse
    end
    local before = {}
    for _, entry in ipairs(s.lootList or {}) do
        before[entry.lootKey] = true
    end
    if clear then
        s.lootList = {}
    end
    local entries, fresh = {}, 0
    for part in (text or ""):gmatch("[^;]+") do
        local itemID, lootKey = part:match("^(%d+)=(.+)$")
        if itemID then
            table.insert(entries, { itemID = tonumber(itemID), lootKey = lootKey })
            if not before[lootKey] then
                fresh = fresh + 1
            end
        end
    end
    self:AddLootEntries(s, entries)
    changed("Verteilliste vom Raidlead", sessionID)
    return fresh
end

function Session:ApplyRemoteEnd(sessionID)
    local s = self:GetRemote()
    if s and s.id == sessionID then
        ns.char.remoteSession = nil
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
