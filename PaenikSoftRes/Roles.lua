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
    checkRole()
end

function ns:PARTY_LEADER_CHANGED()
    checkRole()
end

ns:On("LOGIN", checkRole)
ns:RegisterEvent("GROUP_ROSTER_UPDATE")
ns:RegisterEvent("PARTY_LEADER_CHANGED")
