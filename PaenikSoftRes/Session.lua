-- Datenmodell einer Soft-Reserve-Sitzung (ohne UI).
-- ns.db.session = {
--     id, leader, createdAt,
--     instanceKey,    -- "providerID:key", siehe Data/LootData.lua
--     instanceName,
--     maxReserves, allowDuplicates, locked,
--     reserves = { ["Name-Realm"] = { { itemID = 123, source = "ingame" }, ... } },
-- }
local _, ns = ...

local Session = {}
ns.Session = Session

Session.MAX_RESERVES_LIMIT = 5

local RULE_KEYS = {
    instanceKey = true,
    instanceName = true,
    maxReserves = true,
    allowDuplicates = true,
    locked = true,
}

local function changed(reason, ...)
    ns.Debug("Session", reason, ...)
    ns:Fire("SESSION_CHANGED")
end

function Session:Get()
    return ns.db and ns.db.session
end

function Session:New(leader)
    ns.db.session = {
        id = string.format("%s-%d", leader or "?", GetServerTime()),
        leader = leader,
        createdAt = GetServerTime(),
        maxReserves = 1,
        allowDuplicates = true,
        locked = false,
        reserves = {},
    }
    changed("Neue Sitzung", ns.db.session.id)
    return ns.db.session
end

function Session:Reset()
    ns.db.session = nil
    changed("Sitzung verworfen")
end

function Session:SetRules(rules)
    local s = self:Get()
    if not s then return false, "Keine Sitzung" end
    if rules.maxReserves ~= nil then
        local n = tonumber(rules.maxReserves)
        if not n or n < 1 or n > self.MAX_RESERVES_LIMIT then
            return false, "Ungültige Anzahl SRs"
        end
    end
    -- Reserves gehören zu einer Instanz: bei einem Wechsel verfallen sie.
    if rules.instanceKey ~= nil and rules.instanceKey ~= s.instanceKey and next(s.reserves) then
        wipe(s.reserves)
        ns.Debug("Session", "Instanz gewechselt, Reserves verworfen")
    end
    local parts = {}
    for key, value in pairs(rules) do
        if RULE_KEYS[key] then
            s[key] = value
            table.insert(parts, key .. "=" .. tostring(value))
        end
    end
    changed("Regeln geändert:", table.concat(parts, ", "))
    return true
end

function Session:SetLocked(locked)
    return self:SetRules({ locked = locked and true or false })
end

function Session:GetReserves(player)
    local s = self:Get()
    return s and s.reserves[player]
end

function Session:CountReserves(player)
    local list = self:GetReserves(player)
    return list and #list or 0
end

function Session:AddReserve(player, itemID, source)
    local s = self:Get()
    if not s then return false, "Keine Sitzung" end
    if s.locked then return false, "Sitzung ist gesperrt" end
    if type(itemID) ~= "number" then return false, "Ungültige ItemID" end

    local list = s.reserves[player] or {}
    if #list >= s.maxReserves then
        return false, "Limit erreicht (" .. s.maxReserves .. ")"
    end
    if not s.allowDuplicates then
        for i = 1, #list do
            if list[i].itemID == itemID then
                return false, "Item bereits reserviert"
            end
        end
    end
    table.insert(list, { itemID = itemID, source = source or "ingame" })
    s.reserves[player] = list
    changed("Reserve hinzugefügt", player, itemID)
    return true
end

function Session:RemoveReserve(player, itemID)
    local s = self:Get()
    if not s then return false, "Keine Sitzung" end
    local list = s.reserves[player]
    if not list then return false, "Keine Reserve" end
    for i = #list, 1, -1 do
        if list[i].itemID == itemID then
            table.remove(list, i)
            if #list == 0 then
                s.reserves[player] = nil
            end
            changed("Reserve entfernt", player, itemID)
            return true
        end
    end
    return false, "Keine Reserve"
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
