-- Import von Soft Reserves aus externen Quellen.
-- softres.it: CSV-Export (Kopfzeile z. B. "ItemId,Name,Class,Note,Plus"), eine Zeile pro Reserve,
-- oder „Gargul Export“ (Base64 + zlib + JSON, entpackt mit LibDeflate aus Libs/).
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

local playerKey = ns.PlayerKeyForName
local INVALID_NAME = ns.INVALID_NAME_PATTERN

-- Ergebnis eines Imports: result = { reserves = { [key] = { itemID, ... } }, players, count,
--   notInGroup = { key, ... }, notInInstance, skipped, format }
--   importNames = { [vorläufiger Schlüssel] = Name aus dem Export }
local function newResult(format)
    return {
        reserves = {}, players = 0, count = 0, notInGroup = {}, notInInstance = 0, skipped = 0,
        importNames = {},
        format = format,
        itemSet = ns.Session:GetInstanceItemSet(),
        seen = {},
    }
end

local function addReserve(result, name, itemID)
    name = type(name) == "string" and strtrim(name) or nil
    if not itemID or itemID <= 0 or not name or name == "" or name:find(INVALID_NAME) then
        result.skipped = result.skipped + 1
        return
    end
    local key, inGroup = playerKey(name)
    if not result.seen[key] then
        result.seen[key] = true
        result.players = result.players + 1
        result.reserves[key] = {}
        if not inGroup then
            table.insert(result.notInGroup, key)
            result.importNames[key] = name
        end
    end
    table.insert(result.reserves[key], itemID)
    result.count = result.count + 1
    if result.itemSet and not result.itemSet[itemID] then
        result.notInInstance = result.notInInstance + 1
    end
end

local function finishResult(result)
    result.itemSet, result.seen = nil, nil
    if result.count == 0 then
        return nil, "Keine gültigen Reserves gefunden."
    end
    return result
end

-- softres.it „CSV“-Export
function Import.ParseSoftresCSV(text)
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

    local result = newResult("CSV")
    for i = 2, #lines do
        local fields = splitCSVLine(lines[i])
        addReserve(result, fields[nameColumn], tonumber(fields[itemColumn]))
    end
    return finishResult(result)
end

-- Base64 (Standardalphabet) -------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local b64Value = {}
for i = 1, #B64 do
    b64Value[B64:sub(i, i)] = i - 1
end

local function decodeBase64(text)
    text = text:gsub("%s", ""):gsub("=+$", "")
    local out, bits, bitCount = {}, 0, 0
    for i = 1, #text do
        local value = b64Value[text:sub(i, i)]
        if not value then
            return nil
        end
        bits = bits * 64 + value
        bitCount = bitCount + 6
        if bitCount >= 8 then
            bitCount = bitCount - 8
            local byte = math.floor(bits / 2 ^ bitCount)
            out[#out + 1] = string.char(byte)
            bits = bits - byte * 2 ^ bitCount
        end
    end
    return table.concat(out)
end

-- Minimaler JSON-Parser (Objekte, Arrays, Strings, Zahlen, true/false/null) ------------
local function utf8Char(code)
    if code < 0x80 then
        return string.char(code)
    elseif code < 0x800 then
        return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
    elseif code < 0x10000 then
        return string.char(0xE0 + math.floor(code / 0x1000), 0x80 + math.floor(code / 0x40) % 0x40,
            0x80 + code % 0x40)
    end
    return string.char(0xF0 + math.floor(code / 0x40000), 0x80 + math.floor(code / 0x1000) % 0x40,
        0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
end

local ESCAPES = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

local function decodeJSON(text)
    local pos = 1

    local function fail(message)
        error({ json = message .. " (Position " .. pos .. ")" })
    end

    local function skipSpace()
        pos = text:find("[^ \t\r\n]", pos) or (#text + 1)
    end

    local parseValue

    local function parseString()
        pos = pos + 1 -- öffnendes Anführungszeichen
        local parts = {}
        while true do
            local stop = text:find('["\\]', pos)
            if not stop then fail("String nicht beendet") end
            parts[#parts + 1] = text:sub(pos, stop - 1)
            if text:sub(stop, stop) == '"' then
                pos = stop + 1
                return table.concat(parts)
            end
            local escape = text:sub(stop + 1, stop + 1)
            if escape == "u" then
                local code = tonumber(text:sub(stop + 2, stop + 5), 16)
                if not code then fail("Ungültiges \\u") end
                pos = stop + 6
                -- Surrogatpaar zusammenfügen
                if code >= 0xD800 and code <= 0xDBFF and text:sub(pos, pos + 1) == "\\u" then
                    local low = tonumber(text:sub(pos + 2, pos + 5), 16)
                    if low and low >= 0xDC00 and low <= 0xDFFF then
                        code = 0x10000 + (code - 0xD800) * 0x400 + (low - 0xDC00)
                        pos = pos + 6
                    end
                end
                parts[#parts + 1] = utf8Char(code)
            else
                parts[#parts + 1] = ESCAPES[escape] or escape
                pos = stop + 2
            end
        end
    end

    local function parseNumber()
        local number = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
        if not number or number == "" then fail("Zahl erwartet") end
        pos = pos + #number
        return tonumber(number)
    end

    local function parseArray()
        pos = pos + 1
        local array = {}
        skipSpace()
        if text:sub(pos, pos) == "]" then
            pos = pos + 1
            return array
        end
        while true do
            array[#array + 1] = parseValue()
            skipSpace()
            local char = text:sub(pos, pos)
            pos = pos + 1
            if char == "]" then return array end
            if char ~= "," then fail("',' oder ']' erwartet") end
        end
    end

    local function parseObject()
        pos = pos + 1
        local object = {}
        skipSpace()
        if text:sub(pos, pos) == "}" then
            pos = pos + 1
            return object
        end
        while true do
            skipSpace()
            if text:sub(pos, pos) ~= '"' then fail("Schlüssel erwartet") end
            local key = parseString()
            skipSpace()
            if text:sub(pos, pos) ~= ":" then fail("':' erwartet") end
            pos = pos + 1
            object[key] = parseValue()
            skipSpace()
            local char = text:sub(pos, pos)
            pos = pos + 1
            if char == "}" then return object end
            if char ~= "," then fail("',' oder '}' erwartet") end
        end
    end

    function parseValue()
        skipSpace()
        local char = text:sub(pos, pos)
        if char == "{" then return parseObject() end
        if char == "[" then return parseArray() end
        if char == '"' then return parseString() end
        if text:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true
        end
        if text:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false
        end
        if text:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return nil
        end
        return parseNumber()
    end

    local ok, result = pcall(parseValue)
    if not ok then
        return nil, type(result) == "table" and result.json or tostring(result)
    end
    return result
end

-- softres.it „Gargul Export“: Base64 → zlib → JSON
function Import.ParseSoftresGargul(text)
    local LibDeflate = LibStub and LibStub:GetLibrary("LibDeflate", true)
    if not LibDeflate then
        return nil, "LibDeflate fehlt – Gargul-Export kann nicht gelesen werden."
    end
    local raw = decodeBase64(text)
    if not raw or raw == "" then
        return nil, "Weder CSV noch Gargul-Export erkannt (Base64 ungültig)."
    end
    local ok, json = pcall(LibDeflate.DecompressZlib, LibDeflate, raw)
    if not ok or not json then
        return nil, "Gargul-Export konnte nicht entpackt werden. Bitte vollständig kopieren."
    end
    local data, err = decodeJSON(json)
    if type(data) ~= "table" or type(data.softreserves) ~= "table" then
        return nil, "Gargul-Export ungültig" .. (err and (": " .. err) or ".")
    end

    local result = newResult("Gargul")
    for _, entry in ipairs(data.softreserves) do
        if type(entry) == "table" and type(entry.items) == "table" then
            for _, item in ipairs(entry.items) do
                local itemID = type(item) == "table" and tonumber(item.id) or tonumber(item)
                addReserve(result, entry.name, itemID)
            end
        end
    end

    -- Hard Reserves: fest vergebene Items (für wen: Feld "for", sonst Notiz)
    result.hardReserveList = {}
    for _, entry in ipairs(type(data.hardreserves) == "table" and data.hardreserves or {}) do
        local itemID = type(entry) == "table" and tonumber(entry.id)
        if itemID and itemID > 0 then
            local note = entry["for"] or entry.note or ""
            table.insert(result.hardReserveList, { itemID = itemID, note = tostring(note) })
        end
    end
    result.hardReserves = #result.hardReserveList
    if result.count == 0 and result.hardReserves > 0 then
        result.itemSet, result.seen = nil, nil
        return result -- nur Hard Reserves ist auch ein gültiger Import
    end
    return finishResult(result)
end

-- Erkennt das Format: CSV enthält Kommas, der Gargul-Export (Base64) nicht
function Import.ParseSoftres(text)
    if not text or strtrim(text) == "" then
        return nil, "Kein Text eingefügt."
    end
    if text:find(",", 1, true) then
        return Import.ParseSoftresCSV(text)
    end
    return Import.ParseSoftresGargul(strtrim(text))
end

-- Import ausführen (nur Raidlead mit eigener Sitzung)
function Import.Apply(result, replaceAll)
    local ok, players, count = ns.Session:ImportReserves(result.reserves, Import.SOURCE_SOFTRES, replaceAll,
        result.importNames)
    if not ok then
        return false, players
    end
    -- Hard Reserves (Gargul-Export): beim Ersetzen die bisherigen verwerfen
    local s = ns.Session:Get()
    local hrList = result.hardReserveList or {}
    if replaceAll and s and s.hardReserves then
        for itemID in pairs(CopyTable(s.hardReserves)) do
            ns.Session:RemoveHardReserve(s, itemID)
        end
    end
    for _, hr in ipairs(hrList) do
        ns.Session:SetHardReserve(s, hr.itemID, hr.note)
    end
    ns.Print(string.format("softres.it-Import (%s): %d Spieler, %d Reserves%s %s.", result.format or "?", players,
        count, #hrList > 0 and (", " .. #hrList .. " Hard Reserves") or "",
        replaceAll and "übernommen (alte Reserves ersetzt)" or "zusammengeführt"))
    return true
end
