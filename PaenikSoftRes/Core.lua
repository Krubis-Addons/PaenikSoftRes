local addonName, ns = ...

-- Anzeigename im Spiel (Ordner und SavedVariables heißen weiter PaenikSoftRes)
ns.TITLE = "PÄNIK SoftRes"

local DB_VERSION = 2 -- 2: mehrere Sitzungen (db.sessions statt db.session)

local defaults = {
    version = DB_VERSION,
    showOnLogin = true,
    debug = false, -- Debug-Log und Testbefehle (Optionen oder /paeniksoftres debug)
    guildSync = true, -- Gilden-Synchronisation (GuildSync.lua)
    gargulCompat = true, -- Würfelrunden auch an Gargul senden (GargulCompat.lua)
    autoTrade = true, -- gewonnene Items beim Handeln automatisch einlegen (Trade.lua)
    pastSessionDays = 14, -- vergangene Vorlagen-Sitzungen nach so vielen Tagen löschen (0 = nie, Templates.lua)
    -- forceRole: nil = automatisch, "lead" oder "raider" (zum Testen)
    -- sessions, activeSessionId, remoteSession: Soft-Reserve-Sitzungen, siehe Session.lua
}

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    local handler = ns[event]
    if handler then
        handler(ns, ...)
    end
end)

-- Unbekannte Events werfen in WoW: Forever beim Registrieren einen Fehler.
-- pcall verhindert, dass dadurch die ganze Datei abbricht.
function ns:RegisterEvent(event)
    local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
    if not ok then
        ns.Debug("Core", "Event nicht verfügbar:", event)
    end
    return ok
end

-- Interne Callbacks (SESSION_CHANGED, ROLE_CHANGED, ...)
local callbacks = {}

function ns:On(name, fn)
    callbacks[name] = callbacks[name] or {}
    table.insert(callbacks[name], fn)
end

function ns:Fire(name, ...)
    local list = callbacks[name]
    if not list then return end
    for i = 1, #list do
        list[i](...)
    end
end

function ns.Print(msg)
    print("|cff33ff99" .. ns.TITLE .. "|r: " .. tostring(msg))
end

-- Spielerschlüssel "Vorname[ Nachname]-Realm", im selben Format wie der Absender von CHAT_MSG_ADDON
-- (z. B. "Krubi Shooty-ClassicBetaPvE2").
-- Forever kennt Nachnamen: UnitName liefert dann ("Krubi", "Shooty") – der zweite Wert ist
-- der Nachname, nicht der Realm. Den Realm liefert GetPlayerInfoByGUID ("" = eigener Realm).
local function normalizeRealm(realm)
    return realm and (realm:gsub("[%s%-]", "")) or nil
end

-- Secret Values zuerst prüfen: schon ein Wahrheitstest auf einem Secret wirft einen Fehler.
local function isSecret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end
ns.IsSecret = isSecret
ns.NormalizeRealm = normalizeRealm

function ns.FullName(unit)
    unit = unit or "player"
    local name, second = UnitName(unit)
    if isSecret(name) or isSecret(second) or not name then
        return nil
    end
    local realm
    local guid = UnitGUID(unit)
    if not isSecret(guid) and guid then
        local _, _, _, _, _, _, guidRealm = GetPlayerInfoByGUID(guid)
        if not isSecret(guidRealm) and guidRealm and guidRealm ~= "" then
            realm = normalizeRealm(guidRealm)
        end
    end
    -- Ist der zweite Wert der Realm (Spieler von einem anderen Realm), gehört er nicht zum Namen.
    if second and second ~= "" and normalizeRealm(second) ~= realm then
        name = name .. " " .. second
    end
    realm = realm or GetNormalizedRealmName()
    if realm then
        return name .. "-" .. realm
    end
    return name
end

function ns:ADDON_LOADED(name)
    if name ~= addonName then return end
    PaenikSoftResDB = PaenikSoftResDB or {}
    for key, value in pairs(defaults) do
        if PaenikSoftResDB[key] == nil then
            PaenikSoftResDB[key] = value
        end
    end
    PaenikSoftResDB.version = DB_VERSION
    ns.db = PaenikSoftResDB
    -- Sitzungsdaten pro Charakter (siehe Kopf von Session.lua)
    PaenikSoftResCharDB = PaenikSoftResCharDB or {}
    ns.char = PaenikSoftResCharDB
    eventFrame:UnregisterEvent("ADDON_LOADED")
    ns.Debug("Core", "Datenbank initialisiert, Version", ns.db.version)
    -- Bis hierher wurde immer protokolliert (Ladephase), ab jetzt gilt die Einstellung
    ns.debugEnabled = ns.db.debug
    if not ns.db.debug and ns.db.forceRole then
        ns.db.forceRole = nil
    end
    ns:Fire("DB_READY")
end

-- Gruppenliste als Nachschlagetabellen, neu aufgebaut nach GROUP_ROSTER_UPDATE (Roles.lua) bzw. Login.
--   byKey  ["Name-Realm"] = unit
--   byName [kleingeschriebener Name/Vorname/Name-Realm] = Schlüssel, false = mehrdeutig
local roster

local function buildRoster()
    roster = { byKey = {}, byName = {} }
    local function add(unit)
        local key = ns.FullName(unit)
        if not key then return end
        roster.byKey[key] = unit
        local first = UnitName(unit)
        local aliases = { key, key:match("^(.*)%-[^%-]+$"), (not isSecret(first)) and first or nil }
        for i = 1, 3 do
            local alias = aliases[i]
            if alias then
                alias = alias:lower()
                local existing = roster.byName[alias]
                if existing == nil then
                    roster.byName[alias] = key
                elseif existing ~= key then
                    roster.byName[alias] = false
                end
            end
        end
    end
    add("player")
    local prefix, count
    if IsInRaid and IsInRaid() then
        prefix, count = "raid", 40
    elseif IsInGroup and IsInGroup() then
        prefix, count = "party", 4
    end
    if prefix then
        for i = 1, count do
            local unit = prefix .. i
            if UnitExists(unit) and not UnitIsUnit(unit, "player") then
                add(unit)
            end
        end
    end
end

function ns.InvalidateRoster()
    roster = nil
end

-- Gruppen-Unit zu einem "Name-Realm" suchen (nil, wenn nicht in der Gruppe; "player" für mich).
function ns.UnitForName(fullName)
    if not roster then buildRoster() end
    return roster.byKey[fullName]
end

-- Einen Namen (z. B. aus einer Würfelnachricht oder einem softres.it-Import) einem
-- Gruppenmitglied zuordnen. Erlaubt "Vorname", "Vorname Nachname" oder "Name-Realm"
-- (Forever-Nachnamen), ohne Groß-/Kleinschreibung. Nur eindeutige Treffer zählen.
function ns.ResolvePlayerName(name)
    if isSecret(name) or not name or name == "" then return nil end
    if not roster then buildRoster() end
    local key = roster.byName[name:lower()]
    if key == false then
        ns.Debug("Core", "Name mehrdeutig:", name)
        return nil
    end
    return key
end

-- Schlüssel aller Gruppenmitglieder außer dem eigenen, alphabetisch
function ns.GroupMembers()
    if not roster then buildRoster() end
    local me = ns.FullName("player")
    local list = {}
    for key in pairs(roster.byKey) do
        if key ~= me then
            table.insert(list, key)
        end
    end
    table.sort(list)
    return list
end

-- Loot ab Qualität für „Soft Reserves“ und „Beute“ (db.lootMinQuality), aufsteigend:
-- „Selten“ = Selten + Episch + Legendär. Hier, weil Menüs in UI-Dateien sie schon beim Laden brauchen.
do
    local Q = Enum.ItemQuality or { Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 }
    ns.LOOT_QUALITIES = {
        { value = Q.Uncommon, text = "Ungewöhnlich" },
        { value = Q.Rare, text = "Selten" },
        { value = Q.Epic, text = "Episch" },
        { value = Q.Legendary, text = "Legendär" },
    }
end

-- Diese Zeichen trennen Felder im Sync-Protokoll (Comm.lua) und dürfen nicht in Namen stehen
ns.INVALID_NAME_PATTERN = "[%^;=,|]"

-- Frei eingegebenen Namen (softres.it-Import, Raidlead-Eintrag) in unseren Schlüssel umwandeln:
-- Gruppenmitglied, sonst vorläufig "Name-Realm" (zweiter Rückgabewert false). Vorläufige Schlüssel
-- ordnet Session:ResolveImportedPlayers später dem echten Spieler zu
-- (Forever-Nachnamen: aus "krubi" wird dann "Krubi Shooty-Realm").
function ns.PlayerKeyForName(name)
    local key = ns.ResolvePlayerName(name)
    if key then
        return key, true
    end
    local base, realm = name:match("^(.-)%-(.+)$")
    if not base then
        base, realm = name, GetNormalizedRealmName()
    else
        realm = ns.NormalizeRealm(realm)
    end
    -- softres.it schreibt Namen oft klein: ersten Buchstaben groß (nur ASCII sicher)
    local pretty = base:sub(1, 1):upper() .. base:sub(2)
    return realm and (pretty .. "-" .. realm) or pretty, false
end

-- Chat-Kanal der aktuellen Gruppe (nil ohne Gruppe)
function ns.GroupChannel()
    if IsInRaid and IsInRaid() then
        return "RAID"
    elseif IsInGroup and IsInGroup() then
        return "PARTY"
    end
end

-- Nachricht in den Gruppenchat; ohne Gruppe nur lokal. Beachtet die Chat-Sperre (Midnight).
function ns.SendGroupChat(text)
    local channel = ns.GroupChannel()
    if not channel then
        ns.Print(text)
        return true
    end
    if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
        ns.Print("Chat ist gerade gesperrt (Kampf in der Instanz): " .. text)
        return false
    end
    C_ChatInfo.SendChatMessage(text, channel)
    return true
end

-- Migration: Schlüssel aus der Zeit mit UnitFullName ("Krubi-Bambubi") auf das neue Format umstellen.
local function migratePlayerKeys()
    local s = ns.db.session
    local oldName, oldRealm = UnitFullName("player")
    local me = ns.FullName("player")
    if not s or not oldName or not me then return end
    local oldKey = oldName .. "-" .. (oldRealm and oldRealm ~= "" and oldRealm or GetNormalizedRealmName() or "")
    if oldKey == me then return end
    if s.leader == oldKey then
        s.leader = me
        ns.Debug("Core", "Migration: Sitzungsleiter", oldKey, "->", me)
    end
    if s.reserves and s.reserves[oldKey] and not s.reserves[me] then
        s.reserves[me] = s.reserves[oldKey]
        s.reserves[oldKey] = nil
        ns.Debug("Core", "Migration: Reserves", oldKey, "->", me)
    end
end

function ns:PLAYER_LOGIN()
    migratePlayerKeys()
    ns.Session:MigrateSingleSession() -- nach den Namen: der Leiter muss schon im neuen Format sein
    ns.Session:MigrateToCharacter()
    ns.Debug("Core", "PLAYER_LOGIN, Interface", select(4, GetBuildInfo()), "Spieler", ns.FullName("player"))
    ns:Fire("LOGIN")
    if ns.db.showOnLogin and ns.mainFrame then
        ns.mainFrame:Show()
    end
end

ns:RegisterEvent("ADDON_LOADED")
ns:RegisterEvent("PLAYER_LOGIN")

local function setForceRole(role)
    ns.db.forceRole = role
    ns.Debug("Core", "forceRole gesetzt:", role)
    ns:Fire("ROLE_CHANGED")
    ns.Print("Rolle " .. (role or "automatisch"))
end

-- Debug-Log und Testbefehle ein-/ausschalten (Einstellung db.debug, Standard aus)
function ns.SetDebug(enabled)
    ns.db.debug = enabled and true or false
    ns.debugEnabled = ns.db.debug
    if not ns.db.debug and ns.db.forceRole then
        setForceRole(nil) -- erzwungene Testrolle nicht still weiterlaufen lassen
    end
    ns.Print("Debug-Log und Testbefehle " .. (ns.db.debug and "an" or "aus"))
end

-- Testbefehle nur mit aktivem Debug
local TEST_COMMANDS = {
    lead = function() setForceRole("lead") end,
    raider = function() setForceRole("raider") end,
    auto = function() setForceRole(nil) end,
    loottest = function() ns.ShowLootTest() end,
    fake = function() ns.AddFakeReserves() end,
    probe = function() ns.RunProbe() end,
    gargultest = function() ns.GargulCompat:SelfTest() end,
    vorlagetest = function(arg) ns.Templates:DebugTest(arg) end,
}

SLASH_PAENIKSOFTRES1 = "/paeniksoftres"
SLASH_PAENIKSOFTRES2 = "/psr" -- Kurzform
SlashCmdList.PAENIKSOFTRES = function(msg)
    local raw = strtrim(msg or "")
    local cmd, rest = raw:match("^(%S*)%s*(.*)$")
    msg = (cmd or ""):lower()
    local frame = ns.mainFrame
    if msg == "show" then
        frame:Show()
    elseif msg == "hide" then
        frame:Hide()
    elseif msg == "" or msg == "toggle" then
        frame:SetShown(not frame:IsShown())
    elseif msg == "options" or msg == "optionen" then
        ns.OpenOptions()
    elseif msg == "minimap" then
        local hidden = ns.db.minimap.hide
        ns.SetMinimapButtonShown(hidden)
        ns.Print("Minimap-Button " .. (hidden and "an" or "aus"))
    elseif msg == "debug" then
        ns.SetDebug(not ns.db.debug)
    elseif msg == "roll" then
        ns.StartRollFromSlash(rest)
    elseif msg == "loot" then
        ns.ToggleLootPanel()
    elseif msg == "beute" then
        ns.ToggleBeutePanel()
    elseif msg == "lootpanel" and rest:lower() == "reset" then
        ns.ResetLootPanelPosition()
        ns.Print("Loot-Panel dockt wieder am Lootfenster an.")
    elseif msg == "lootpanel" then
        ns.db.lootPanel = not ns.db.lootPanel
        ns.Print("Loot-Panel " .. (ns.db.lootPanel and "an" or "aus"))
    elseif TEST_COMMANDS[msg] then
        if ns.db.debug then
            TEST_COMMANDS[msg](rest:lower())
        else
            ns.Print("Testbefehl – erst mit /paeniksoftres debug freischalten.")
        end
    else
        ns.Print("Befehle: show, hide, toggle, options, minimap, loot, beute, roll <Item>, lootpanel [reset], debug")
        if ns.db.debug then
            ns.Print("Testbefehle: probe, fake, loottest, gargultest, vorlagetest [vorbei], lead, raider, auto")
        end
    end
end
