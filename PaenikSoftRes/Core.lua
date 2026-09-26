local addonName, ns = ...

local DB_VERSION = 1

local defaults = {
    version = DB_VERSION,
    showOnLogin = true,
    -- forceRole: nil = automatisch, "lead" oder "raider" (zum Testen)
    -- session: aktuelle Soft-Reserve-Sitzung, siehe Session.lua
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
    print("|cff33ff99" .. addonName .. "|r: " .. tostring(msg))
end

-- Spielerschlüssel "Vorname[ Nachname]-Realm", im selben Format wie der Absender von CHAT_MSG_ADDON
-- (z. B. "Krubi Shooty-ClassicBetaPvE2").
-- Forever kennt Nachnamen: UnitName liefert dann ("Krubi", "Shooty") – der zweite Wert ist
-- der Nachname, nicht der Realm. Den Realm liefert GetPlayerInfoByGUID ("" = eigener Realm).
local function normalizeRealm(realm)
    return realm and (realm:gsub("[%s%-]", "")) or nil
end

function ns.FullName(unit)
    unit = unit or "player"
    local name, second = UnitName(unit)
    if not name or (issecretvalue and (issecretvalue(name) or issecretvalue(second))) then
        return nil
    end
    local realm
    local guid = UnitGUID(unit)
    if guid and not (issecretvalue and issecretvalue(guid)) then
        local _, _, _, _, _, _, guidRealm = GetPlayerInfoByGUID(guid)
        if guidRealm and guidRealm ~= "" and not (issecretvalue and issecretvalue(guidRealm)) then
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
    eventFrame:UnregisterEvent("ADDON_LOADED")
    ns.Debug("Core", "Datenbank initialisiert, Sitzung vorhanden:", ns.db.session ~= nil)
    ns:Fire("DB_READY")
end

-- Gruppen-Unit zu einem "Name-Realm" suchen (nil, wenn nicht in der Gruppe).
function ns.UnitForName(fullName)
    if fullName == ns.FullName("player") then
        return "player"
    end
    local prefix, count
    if IsInRaid and IsInRaid() then
        prefix, count = "raid", 40
    elseif IsInGroup and IsInGroup() then
        prefix, count = "party", 4
    else
        return nil
    end
    for i = 1, count do
        local unit = prefix .. i
        if UnitExists(unit) and ns.FullName(unit) == fullName then
            return unit
        end
    end
end

-- Chat-Kanal der aktuellen Gruppe (nil ohne Gruppe)
function ns.GroupChannel()
    if IsInRaid and IsInRaid() then
        return "RAID"
    elseif IsInGroup and IsInGroup() then
        return "PARTY"
    end
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
    print(addonName .. ": Rolle " .. (role or "automatisch"))
end

SLASH_PAENIKSOFTRES1 = "/paeniksoftres"
SlashCmdList.PAENIKSOFTRES = function(msg)
    msg = strtrim(msg or ""):lower()
    local frame = ns.mainFrame
    if msg == "show" then
        frame:Show()
    elseif msg == "hide" then
        frame:Hide()
    elseif msg == "minimap" then
        local hidden = ns.db.minimap.hide
        ns.SetMinimapButtonShown(hidden)
        print(addonName .. ": Minimap-Button " .. (hidden and "an" or "aus"))
    elseif msg == "" or msg == "toggle" then
        frame:SetShown(not frame:IsShown())
    elseif msg == "debug" then
        ns.debugEnabled = not ns.debugEnabled
        print(addonName .. ": Debug " .. (ns.debugEnabled and "an" or "aus"))
    elseif msg == "lead" or msg == "raider" then
        setForceRole(msg)
    elseif msg == "auto" then
        setForceRole(nil)
    elseif msg == "loottest" then
        ns.ShowLootTest()
    elseif msg == "lootpanel" then
        ns.db.lootPanel = not ns.db.lootPanel
        print(addonName .. ": Loot-Panel " .. (ns.db.lootPanel and "an" or "aus"))
    elseif msg == "fake" then
        ns.AddFakeReserves()
    elseif msg == "probe" then
        ns.RunProbe()
    else
        print(addonName .. ": Befehle: show, hide, toggle, minimap, lootpanel, loottest, lead, raider, auto, probe, fake, debug")
    end
end
