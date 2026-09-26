-- Import von Soft Reserves aus externen Quellen.
-- softres.it: CSV-Export (Kopfzeile z. B. "ItemId,Name,Class,Note,Plus"), eine Zeile pro Reserve.
-- Kein HTTP im Spiel möglich: der Raidlead kopiert den Export in den Import-Dialog.
local _, ns = ...

local Import = {}
ns.Import = Import

Import.SOURCE_SOFTRES = "softres"

-- Eine CSV-Zeile in Felder zerlegen (Felder in "..." dürfen Kommas und "" enthalten)
local function splitCSVLine(line)
    local fields = {}
    local pos, len = 1, #line
    while pos <= len + 1 do
        local char = line:sub(pos, pos)
        if char == '"' then
            local value, i = {}, pos + 1
            while i <= len do
                local c = line:sub(i, i)
                if c == '"' then
                    if line:sub(i + 1, i + 1) == '"' then
                        table.insert(value, '"')
                        i = i + 2
                    else
                        i = i + 1
                        break
                    end
                else
                    table.insert(value, c)
                    i = i + 1
                end
            end
            table.insert(fields, table.concat(value))
            local nextComma = line:find(",", i, true)
            pos = nextComma and (nextComma + 1) or (len + 2)
        else
            local nextComma = line:find(",", pos, true)
            if nextComma then
                table.insert(fields, line:sub(pos, nextComma - 1))
                pos = nextComma + 1
            else
                table.insert(fields, line:sub(pos))
                pos = len + 2
            end
        end
    end
    for i, field in ipairs(fields) do
        fields[i] = strtrim(field)
    end
    return fields
end

-- Name aus softres.it in unseren Schlüssel umwandeln: Gruppenmitglied, sonst "Name-Realm"
local function playerKey(name)
    local key = ns.ResolvePlayerName(name)
    if key then
        return key, true
    end
    if name:find("-", 1, true) then
        return name, false
    end
    -- softres.it schreibt Namen oft klein: ersten Buchstaben groß (nur ASCII sicher)
    local pretty = name:sub(1, 1):upper() .. name:sub(2)
    local realm = GetNormalizedRealmName()
    return realm and (pretty .. "-" .. realm) or pretty, false
end

-- Liefert result = { reserves = { [key] = { itemID, ... } }, players, count,
--   notInGroup = { key, ... }, notInInstance = Anzahl } oder nil, Fehlertext
function Import.ParseSoftresCSV(text)
    if not text or strtrim(text) == "" then
        return nil, "Kein Text eingefügt."
    end
    local lines = {}
    for line in text:gmatch("[^\r\n]+") do
        if strtrim(line) ~= "" then
            table.insert(lines, line)
        end
    end
    if #lines < 2 then
        return nil, "Zu wenige Zeilen: erwartet wird die Kopfzeile und mindestens eine Reserve."
    end

    -- Spalten über die Kopfzeile finden (Groß-/Kleinschreibung egal)
    local columns = {}
    for index, field in ipairs(splitCSVLine(lines[1])) do
        columns[field:lower()] = index
    end
    local itemColumn = columns.itemid or columns["item id"] or columns.id
    local nameColumn = columns.name or columns.player
    if not itemColumn or not nameColumn then
        return nil, "Kopfzeile nicht erkannt: Spalten „ItemId“ und „Name“ werden benötigt (CSV-Export von softres.it)."
    end

    local result = { reserves = {}, players = 0, count = 0, notInGroup = {}, notInInstance = 0, skipped = 0 }
    local itemSet = ns.Session:GetInstanceItemSet()
    local seenPlayer = {}
    for i = 2, #lines do
        local fields = splitCSVLine(lines[i])
        local itemID = tonumber(fields[itemColumn])
        local name = fields[nameColumn]
        if itemID and itemID > 0 and name and name ~= "" then
            local key, inGroup = playerKey(name)
            if not seenPlayer[key] then
                seenPlayer[key] = true
                result.players = result.players + 1
                result.reserves[key] = {}
                if not inGroup and (IsInGroup and IsInGroup()) then
                    table.insert(result.notInGroup, key)
                end
            end
            table.insert(result.reserves[key], itemID)
            result.count = result.count + 1
            if itemSet and not itemSet[itemID] then
                result.notInInstance = result.notInInstance + 1
            end
        else
            result.skipped = result.skipped + 1
        end
    end
    if result.count == 0 then
        return nil, "Keine gültigen Reserves gefunden."
    end
    return result
end

-- Import ausführen (nur Raidlead mit eigener Sitzung)
function Import.Apply(result, replaceAll)
    local ok, players, count = ns.Session:ImportReserves(result.reserves, Import.SOURCE_SOFTRES, replaceAll)
    if not ok then
        return false, players
    end
    ns.Print(string.format("softres.it-Import: %d Spieler, %d Reserves %s.", players, count,
        replaceAll and "übernommen (alte Reserves ersetzt)" or "zusammengeführt"))
    return true
end
