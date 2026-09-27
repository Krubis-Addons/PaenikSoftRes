-- Regelmäßige Raids: Vorlagen, aus denen automatisch Sitzungen entstehen (z. B. „MC jeden Dienstag 20:00“).
-- Pro Charakter in ns.char.templates[id] = {
--     id, name, instanceKey, instanceName, maxReserves, allowDuplicates,
--     weekday (0 = So … 6 = Sa, wie date("%w")), hour, minute,
--     deadlineHours (Anmeldeschluss so viele Stunden vor dem Raid; 0 = bei Raidbeginn, -1 = keiner),
--     publish (für die Gilde veröffentlichen), enabled,
--     createdUpTo (Termin der zuletzt angelegten Sitzung – verhindert Doppelte, auch nach Löschen) }
-- Automatik (enabled, „Aktiv“), geprüft beim Login und jede Minute: Liegt der nächste Termin höchstens LEAD_DAYS entfernt und gibt es für ihn
-- noch keine Sitzung, wird sie angelegt (Session:CreateFromTemplate). Ein Addon läuft nur im Spiel, die
-- Sitzung entsteht also beim nächsten Login des Raidleads.
local _, ns = ...

local Templates = {}
ns.Templates = Templates

local LEAD_DAYS = 7
local CHECK_INTERVAL = 60 -- Sekunden; stündlich war für „0,5 h nach Raidbeginn“ zu grob

Templates.WEEKDAYS = { [0] = "Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag" }
Templates.DEADLINE_NONE = -1
Templates.DEADLINE_HOURS = { -1, 0, 0.5, 1, 2, 3, 6, 12, 24, 48 }
-- Folgetermin so viele Stunden nach Raidbeginn anlegen (halbe Stunden möglich)
Templates.CREATE_AFTER_HOURS = { 0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5, 5.5, 6, 8, 12, 24 }
Templates.DEFAULT_CREATE_AFTER = 3

function Templates.CreateAfterHours(t)
    return t.createAfterHours or Templates.DEFAULT_CREATE_AFTER
end

-- „3,5 h“
function Templates.HoursText(hours)
    return (tostring(hours):gsub("%.", ",")) .. " h"
end

local function all()
    ns.char.templates = ns.char.templates or {}
    -- Umstellung: früher hieß deadlineHours = 0 „kein Anmeldeschluss“, jetzt „bei Raidbeginn“
    if (ns.char.templatesVersion or 1) < 2 then
        for _, t in pairs(ns.char.templates) do
            if t.deadlineHours == 0 then
                t.deadlineHours = -1
            end
        end
        ns.char.templatesVersion = 2
    end
    return ns.char.templates
end

-- Vorlagen nach Wochentag (Mo zuerst) und Uhrzeit
function Templates:List()
    local list = {}
    for _, t in pairs(all()) do
        table.insert(list, t)
    end
    local function order(t)
        return ((t.weekday + 6) % 7) * 1440 + t.hour * 60 + t.minute
    end
    table.sort(list, function(a, b) return order(a) < order(b) end)
    return list
end

function Templates:Get(id)
    return id and all()[id]
end

-- Nächster Termin nach now (lokale Zeit wie beim Anmeldeschluss)
function Templates:NextOccurrence(t, now)
    now = now or GetServerTime()
    local today = date("*t", now)
    for offset = 0, 7 do
        local raidAt = time({ year = today.year, month = today.month, day = today.day + offset,
            hour = t.hour, min = t.minute, sec = 0 })
        if tonumber(date("%w", raidAt)) == t.weekday and raidAt > now then
            return raidAt
        end
    end
end

-- Kommende Sitzung der Vorlage (über templateId, Termin noch nicht erreicht); bei mehreren die früheste.
-- Zugeordnet über die ID, nicht über den Termin: nach einer Terminänderung bleibt es dieselbe Sitzung.
function Templates:GetUpcomingSession(t, now)
    now = now or GetServerTime()
    local best
    for _, s in ipairs(ns.Session:List()) do
        if s.templateId == t.id and (s.raidAt or 0) > now and (not best or s.raidAt < best.raidAt) then
            best = s
        end
    end
    return best
end

-- Termin, den die Sitzung s nach der Vorlage haben sollte: passt ihr Wochentag/ihre Uhrzeit noch, bleibt
-- ihr Termin; sonst der nächste Termin der Vorlage.
function Templates:ExpectedRaidAt(t, s)
    local d = date("*t", s.raidAt)
    if tonumber(date("%w", s.raidAt)) == t.weekday and d.hour == t.hour and d.min == t.minute then
        return s.raidAt
    end
    return self:NextOccurrence(t)
end

-- Abweichungen der Sitzung s von der Vorlage t als lesbare Liste (leer = aktuell)
function Templates:Differences(t, s)
    local diffs = {}
    local raidAt = self:ExpectedRaidAt(t, s) or s.raidAt
    if raidAt ~= s.raidAt then
        table.insert(diffs, "Termin")
    end
    if t.instanceKey ~= s.instanceKey then
        table.insert(diffs, "Instanz")
    end
    if (t.maxReserves or 1) ~= s.maxReserves then
        table.insert(diffs, "Max. SRs")
    end
    if (t.allowDuplicates and true or false) ~= (s.allowDuplicates and true or false) then
        table.insert(diffs, "Mehrfach erlaubt")
    end
    local deadline = ns.Session.TemplateDeadline(t, raidAt)
    -- ein verstrichener Schluss der Vorlage lässt sich nicht mehr setzen: dann nicht als Abweichung zählen
    if deadline ~= s.deadline and not (deadline and deadline <= GetServerTime()) then
        table.insert(diffs, "Anmeldeschluss")
    end
    if ns.Session.TemplateSessionName(t, raidAt) ~= s.name then
        table.insert(diffs, "Name")
    end
    if IsInGuild and IsInGuild() and (t.publish and true or false) ~= (s.published == true) then
        table.insert(diffs, "Veröffentlichung")
    end
    return diffs
end

-- now: Zeitpunkt für das Umschalten (nur im Testbefehl simuliert)
local function createSession(t, raidAt, now)
    local s = ns.Session:CreateFromTemplate(t, raidAt)
    if t.publish and IsInGuild and IsInGuild() then
        ns.GuildSync:SetPublished(s, true)
    end
    t.createdUpTo = math.max(t.createdUpTo or 0, raidAt)
    ns.Print("Regelmäßiger Raid: Sitzung „" .. s.name .. "“ angelegt.")
    -- Automatisch umschalten: ist die aktive Sitzung eine vergangene (Raid hat begonnen), wird die neue aktiv.
    -- Nicht in einer Gruppe – ein laufender Raid wird nie umgeschaltet.
    local active = ns.char.sessions and ns.char.sessions[ns.Session:GetActiveID() or ""]
    local inGroup = IsInGroup and IsInGroup()
    if active and active ~= s and not inGroup and ns.Session.IsPast(active, now) then
        ns.Session:SetActive(s.id)
        ns.Print("Aktive Sitzung ist jetzt „" .. s.name .. "“.")
    end
    return s
end

-- Vergangene Sitzungen (mit Termin, also aus Vorlagen) nach db.pastSessionDays Tagen löschen
-- (0 = nie). Die aktive Sitzung bleibt immer.
function Templates:Cleanup(now)
    local days = ns.db and ns.db.pastSessionDays or 0
    if days <= 0 then return 0 end
    now = now or GetServerTime()
    local activeID, removed = ns.Session:GetActiveID(), 0
    for _, s in ipairs(ns.Session:List()) do
        if s.raidAt and s.id ~= activeID and s.raidAt + days * 86400 < now then
            ns.Session:DeleteSession(s)
            removed = removed + 1
        end
    end
    if removed > 0 then
        ns.Print(string.format("%d vergangene Sitzung(en) gelöscht (älter als %d Tage).", removed, days))
    end
    return removed
end

-- Automatik („Aktiv“): nur Folgetermine. Die erste Sitzung entsteht immer über „Sitzung anlegen“
-- (createdUpTo gesetzt). Solange eine kommende Sitzung der Vorlage existiert, wird nichts angelegt; ist ihr
-- Termin vorbei, entsteht die nächste, sobald sie höchstens LEAD_DAYS entfernt ist. Ein Termin, für den schon
-- einmal angelegt wurde, wird nicht erneut angelegt – auch wenn die Sitzung gelöscht wurde.
-- Gibt die Anzahl neuer Sitzungen zurück.
-- Eine Vorlage zum Zeitpunkt now prüfen; true, wenn eine Sitzung angelegt wurde
-- (now ist nur im Testbefehl ein anderer Zeitpunkt als GetServerTime())
local function checkTemplate(t, now)
    if not (t.enabled and t.instanceKey and t.createdUpTo) or Templates:GetUpcomingSession(t, now) then
        return false
    end
    -- Folgetermin erst eine einstellbare Zeit nach Beginn des zuletzt angelegten Raids
    if now < t.createdUpTo + Templates.CreateAfterHours(t) * 3600 then
        return false
    end
    local raidAt = Templates:NextOccurrence(t, now)
    if raidAt and raidAt - now <= LEAD_DAYS * 86400 and t.createdUpTo < raidAt then
        createSession(t, raidAt, now)
        return true
    end
    return false
end

function Templates:Check()
    if not ns.char then return 0 end
    local now, created = GetServerTime(), 0
    for _, t in pairs(all()) do
        if checkTemplate(t, now) then
            created = created + 1
        end
    end
    self:Cleanup(now)
    if created > 0 then
        ns:Fire("SESSION_CHANGED")
    end
    return created
end

-- Knopf „Sitzung anlegen“: Sitzung für den nächsten Termin sofort anlegen – unabhängig von „Aktiv“ und
-- auch erneut, wenn sie gelöscht wurde. Nur wenn die Vorlage gerade keine kommende Sitzung hat.
function Templates:CreateNow(t)
    if not t.instanceKey then return false, "Erst eine Instanz wählen" end
    if self:GetUpcomingSession(t) then return false, "Es gibt bereits eine kommende Sitzung" end
    local raidAt = self:NextOccurrence(t)
    if not raidAt then return false, "Kein Termin" end
    local s = createSession(t, raidAt)
    ns:Fire("TEMPLATES_CHANGED")
    ns:Fire("SESSION_CHANGED")
    return true, s
end

-- Knopf „Aktualisieren“: Änderungen der Vorlage auf ihre kommende Sitzung übertragen
function Templates:UpdateSession(t)
    local s = self:GetUpcomingSession(t)
    if not s then return false, "Keine kommende Sitzung" end
    if not t.instanceKey then return false, "Erst eine Instanz wählen" end
    local raidAt = self:ExpectedRaidAt(t, s)
    if not raidAt then return false, "Kein Termin" end
    ns.Session:ApplyTemplate(s, t, raidAt)
    if IsInGuild and IsInGuild() and (t.publish and true or false) ~= (s.published == true) then
        ns.GuildSync:SetPublished(s, t.publish)
    end
    t.createdUpTo = math.max(t.createdUpTo or 0, raidAt)
    ns.Print("Regelmäßiger Raid: Sitzung „" .. s.name .. "“ aktualisiert.")
    ns:Fire("TEMPLATES_CHANGED")
    ns:Fire("SESSION_CHANGED")
    return true, s
end

-- Neue Vorlage, Regeln aus der Sitzung s (falls vorhanden); Standard: heute 20:00, Schluss 2 h vorher.
-- „Aktiv“ ist anfangs aus: die erste Sitzung legt der Raidlead mit „Sitzung anlegen“ an.
function Templates:New(s)
    local now = GetServerTime()
    local t = {
        id = string.format("T%d-%d", now, math.random(100, 999)),
        name = s and s.instanceName or "Raid",
        instanceKey = s and s.instanceKey,
        instanceName = s and s.instanceName,
        maxReserves = s and s.maxReserves or 1,
        allowDuplicates = s == nil or s.allowDuplicates == true,
        weekday = tonumber(date("%w", now)),
        hour = 20,
        minute = 0,
        deadlineHours = 2,
        createAfterHours = Templates.DEFAULT_CREATE_AFTER,
        publish = IsInGuild and IsInGuild() or false,
        enabled = false,
    }
    all()[t.id] = t
    ns.Debug("Templates", "Neue Vorlage", t.id, t.instanceKey)
    ns:Fire("TEMPLATES_CHANGED")
    return t
end

-- Felder ändern; Termin-relevante Änderungen prüfen sofort, ob eine Sitzung fällig ist
function Templates:Update(t, fields)
    for key, value in pairs(fields) do
        t[key] = value
    end
    ns.Debug("Templates", "Vorlage geändert", t.id)
    ns:Fire("TEMPLATES_CHANGED")
    self:Check()
end

function Templates:Delete(t)
    all()[t.id] = nil
    ns.Debug("Templates", "Vorlage gelöscht", t.id)
    ns:Fire("TEMPLATES_CHANGED")
end

-- Kurzbeschreibung, z. B. „Dienstag 20:00 – Molten Core, 2 SRs, Schluss 2 h vorher“
function Templates:Describe(t)
    local parts = {
        string.format("%s %02d:%02d", self.WEEKDAYS[t.weekday] or "?", t.hour, t.minute),
        t.instanceName or "keine Instanz",
        (t.maxReserves or 1) .. (t.maxReserves == 1 and " SR" or " SRs"),
    }
    local hours = t.deadlineHours or -1
    if hours == 0 then
        table.insert(parts, "Schluss bei Raidbeginn")
    elseif hours > 0 then
        table.insert(parts, "Schluss " .. self.HoursText(hours) .. " vorher")
    end
    table.insert(parts, "Folgetermin " .. self.HoursText(self.CreateAfterHours(t)) .. " nach Raidbeginn")
    return table.concat(parts, ", ")
end

ns:On("LOGIN", function()
    C_Timer.After(10, function() Templates:Check() end)
    C_Timer.NewTicker(CHECK_INTERVAL, function() Templates:Check() end)
end)

-- Testbefehl (/paeniksoftres vorlagetest [vorbei]): Automatik sofort prüfen.
-- „vorbei“ prüft jede Vorlage so, als wäre es 1 Minute nach dem Anlege-Zeitpunkt des Folgetermins
-- (Termin der kommenden Sitzung + „Folgetermin anlegen“-Stunden)
-- (simulierte Uhrzeit, die Sitzung selbst bleibt unverändert) – bei aktiven Vorlagen entsteht dann der
-- Folgetermin, genau wie nach dem echten Raid.
function Templates:DebugTest(arg)
    local created = 0
    for _, t in pairs(all()) do
        local now = GetServerTime()
        -- Anlege-Zeitpunkt des Folgetermins: zuletzt angelegter Termin + „Folgetermin anlegen“-Stunden
        local due = t.createdUpTo and (t.createdUpTo + self.CreateAfterHours(t) * 3600 + 60)
        if arg == "vorbei" and due and due > now then
            now = due
            ns.Print("Test: " .. t.name .. " – Uhrzeit simuliert: " .. ns.UI.FormatDate(now))
        end
        if checkTemplate(t, now) then
            created = created + 1
        end
    end
    if created > 0 then
        ns:Fire("SESSION_CHANGED")
    end
    ns.Print(string.format("Automatik geprüft: %d Sitzung(en) angelegt.", created))
    for _, t in ipairs(self:List()) do
        local upcoming = self:GetUpcomingSession(t)
        local state
        if not t.enabled then
            state = "Automatik aus"
        elseif not t.createdUpTo then
            state = "wartet auf die erste Sitzung über „Sitzung anlegen“"
        elseif upcoming then
            state = "kommende Sitzung: " .. upcoming.name
        else
            state = "keine kommende Sitzung (Termin schon angelegt oder gelöscht)"
        end
        ns.Print("  " .. t.name .. " – " .. state)
    end
    ns:Fire("TEMPLATES_CHANGED")
end
