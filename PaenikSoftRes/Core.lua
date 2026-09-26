local addonName, ns = ...

local defaults = {
    enabled = true,
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

function ns:ADDON_LOADED(name)
    if name ~= addonName then return end
    PaenikSoftResDB = PaenikSoftResDB or {}
    for key, value in pairs(defaults) do
        if PaenikSoftResDB[key] == nil then
            PaenikSoftResDB[key] = value
        end
    end
    ns.db = PaenikSoftResDB
    eventFrame:UnregisterEvent("ADDON_LOADED")
    ns.Debug("Core", "Datenbank initialisiert")
end

function ns:PLAYER_LOGIN()
    ns.Debug("Core", "PLAYER_LOGIN, Interface", select(4, GetBuildInfo()))
end

ns:RegisterEvent("ADDON_LOADED")
ns:RegisterEvent("PLAYER_LOGIN")

SLASH_PAENIKSOFTRES1 = "/paeniksoftres"
SlashCmdList.PAENIKSOFTRES = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "debug" then
        ns.debugEnabled = not ns.debugEnabled
        print(addonName .. ": Debug " .. (ns.debugEnabled and "an" or "aus"))
    else
        print(addonName .. ": Befehle: /paeniksoftres debug")
    end
end
