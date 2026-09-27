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

-- Verteiler: wer Loot verteilt (Leiche erfassen, verrollen, zuteilen) – wie im Spiel: Ist die Plündermethode
-- „Plündermeister“, verteilt der Plündermeister, sonst der Gruppenleiter. Solo: man selbst.
-- Sitzung, Regeln und Reserves bleiben immer beim Raidlead (IsLead).
local function lootMethod()
    if C_PartyInfo and C_PartyInfo.GetLootMethod then
        return C_PartyInfo.GetLootMethod()
    end
    if type(GetLootMethod) == "function" then
        return GetLootMethod()
    end
end

local MASTER_LOOT = Enum.LootMethod and Enum.LootMethod.Masterlooter or 2

-- Unit des Plündermeisters oder nil (keine Plündermeister-Verteilung)
local function masterLooterUnit()
    local method, partyID, raidID = lootMethod()
    if ns.IsSecret(method) or not (method == MASTER_LOOT or method == "master") then return nil end
    if IsInRaid and IsInRaid() and raidID and not ns.IsSecret(raidID) then
        return "raid" .. raidID
    end
    if partyID and not ns.IsSecret(partyID) then
        return partyID == 0 and "player" or ("party" .. partyID)
    end
end

local function groupLeaderUnit()
    if UnitIsGroupLeader("player") then return "player" end
    local prefix, count = "party", 4
    if IsInRaid and IsInRaid() then
        prefix, count = "raid", 40
    end
    for i = 1, count do
        local unit = prefix .. i
        if UnitExists(unit) and UnitIsGroupLeader(unit) then
            return unit
        end
    end
end

-- Schlüssel (Name-Realm) des Verteilers; nil ohne Gruppe
function Roles:GetDistributor()
    if not (IsInGroup and IsInGroup()) then return nil end
    local unit = masterLooterUnit() or groupLeaderUnit()
    return unit and ns.FullName(unit) or nil
end

function Roles:IsDistributor()
    local forced = ns.db and ns.db.forceRole
    if forced then
        return forced == "lead"
    end
    if not (IsInGroup and IsInGroup()) then
        return true
    end
    return self:GetDistributor() == ns.FullName("player")
end

-- Kommt eine Nachricht (Würfelrunde, Beute) vom aktuellen Verteiler?
function Roles:IsDistributorName(player)
    return player ~= nil and player == self:GetDistributor()
end

-- Verteilt gerade ein Plündermeister, der nicht der Gruppenleiter ist? (für Hinweise in der UI)
function Roles:HasSeparateMasterLooter()
    local unit = masterLooterUnit()
    return unit ~= nil and not UnitIsGroupLeader(unit)
end

local lastIsLead, lastDistributor

local function checkRole()
    local isLead = Roles:IsLead()
    if isLead ~= lastIsLead then
        lastIsLead = isLead
        ns.Debug("Roles", "Rolle:", Roles:GetRoleName())
        ns:Fire("ROLE_CHANGED")
    end
    local distributor = Roles:IsDistributor()
    if distributor ~= lastDistributor then
        lastDistributor = distributor
        ns.Debug("Roles", "Verteiler:", distributor, Roles:GetDistributor() or "solo")
        ns:Fire("DISTRIBUTOR_CHANGED")
    end
end

-- Plündermethode oder Plündermeister geändert
function ns:PARTY_LOOT_METHOD_CHANGED()
    checkRole()
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
ns:RegisterEvent("PARTY_LOOT_METHOD_CHANGED")
