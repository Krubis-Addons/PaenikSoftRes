-- Rollenlogik: Raidlead oder Raider.
local _, ns = ...

local Roles = {}
ns.Roles = Roles

function Roles:IsLead()
    local forced = ns.db and ns.db.forceRole
    if forced then
        return forced == "lead"
    end
    if not (IsInGroup and IsInGroup()) then
        return true -- solo: zum Testen immer Raidlead
    end
    -- In der Gruppe ist nur der Gruppenleiter Raidlead (eindeutige Hoheit über die Sitzung).
    return UnitIsGroupLeader("player") and true or false
end

function Roles:GetRoleName()
    return self:IsLead() and "Raidlead" or "Raider"
end

local lastIsLead

local function checkRole()
    local isLead = Roles:IsLead()
    if isLead ~= lastIsLead then
        lastIsLead = isLead
        ns.Debug("Roles", "Rolle:", Roles:GetRoleName())
        ns:Fire("ROLE_CHANGED")
    end
end

function ns:GROUP_ROSTER_UPDATE()
    ns.InvalidateRoster() -- Namens-Nachschlagetabellen in Core.lua neu aufbauen
    checkRole()
    ns:Fire("ROSTER_CHANGED")
end

function ns:PARTY_LEADER_CHANGED()
    checkRole()
end

-- Namen können nach dem Beitritt noch unbekannt sein und später nachgeliefert werden
function ns:UNIT_NAME_UPDATE()
    ns.InvalidateRoster()
end

ns:On("LOGIN", function()
    ns.InvalidateRoster()
    checkRole()
end)
ns:RegisterEvent("GROUP_ROSTER_UPDATE")
ns:RegisterEvent("PARTY_LEADER_CHANGED")
ns:RegisterEvent("UNIT_NAME_UPDATE")
