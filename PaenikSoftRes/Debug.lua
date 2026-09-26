-- Debug-Log in den SavedVariables, damit Claude es nach /reload lesen kann.
local addonName, ns = ...

local MAX_ENTRIES = 500
local entries = {}
-- In der Ladephase immer an; nach ADDON_LOADED gilt die Einstellung db.debug (Core.lua, Standard aus)
ns.debugEnabled = true

local function safeToString(v)
    if issecretvalue and issecretvalue(v) then
        return "<secret>"
    end
    return tostring(v)
end

function ns.Debug(category, ...)
    if not ns.debugEnabled then return end
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = safeToString((select(i, ...)))
    end
    entries[#entries + 1] = {
        t = date("%H:%M:%S"),
        gt = GetTime(),
        cat = category,
        msg = table.concat(parts, " "),
    }
    if #entries > MAX_ENTRIES then
        table.remove(entries, 1)
    end
end

-- SavedVariables werden erst nach dem Laden der Dateien befüllt,
-- daher erst bei ADDON_LOADED an die globale Variable hängen.
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name ~= addonName then return end
    PaenikSoftResDebugLog = {
        session = date("%Y-%m-%d %H:%M:%S"),
        build = select(4, GetBuildInfo()),
        entries = entries,
    }
    self:UnregisterEvent("ADDON_LOADED")
end)
