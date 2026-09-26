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

-- Spielerschlüssel immer als "Name-Realm"
function ns.FullName(unit)
    local name, realm = UnitFullName(unit or "player")
    if not name then return nil end
    if not realm or realm == "" then
        realm = GetNormalizedRealmName()
    end
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

function ns:PLAYER_LOGIN()
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
    elseif msg == "" or msg == "toggle" then
        frame:SetShown(not frame:IsShown())
    elseif msg == "debug" then
        ns.debugEnabled = not ns.debugEnabled
        print(addonName .. ": Debug " .. (ns.debugEnabled and "an" or "aus"))
    elseif msg == "lead" or msg == "raider" then
        setForceRole(msg)
    elseif msg == "auto" then
        setForceRole(nil)
    elseif msg == "probe" then
        ns.RunProbe()
    else
        print(addonName .. ": Befehle: show, hide, toggle, lead, raider, auto, probe, debug")
    end
end
