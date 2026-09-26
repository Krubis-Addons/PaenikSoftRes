-- Gargul-Kompatibilität: Beim Start einer Würfelrunde öffnet sich bei Raidern mit Gargul (ohne dieses
-- Addon) das Gargul-Würfelfenster. Dessen Knöpfe rufen RandomRoll(min, max) auf; die Würfe landen wie
-- jeder /roll im Chat und werden von Rolls.lua ausgewertet (Kategorie über den Würfelbereich).
--
-- Protokoll (Gargul, Stand 2026): AceComm-Präfix "GargulComm2", Kanal RAID/PARTY.
--   Payload = { a = Aktion, b = Inhalt, d = Nachrichten-ID }
--   Text    = LibDeflate:EncodeForWoWAddonChannel(LibDeflate:CompressDeflate(LibSerialize:Serialize(Payload)))
--   Aktionen: 10 = Würfelrunde starten, b = { item = "item:12345", time = Sekunden, note = Text,
--             SupportedRolls = { { Name, min, max, Priorität, false, false }, ... } }
--             11 = Würfelrunde beenden (nur vom Starter angenommen)
-- Absender (c) und Versionen (v, m) werden bewusst weggelassen: Gargul setzt den Absender dann selbst aus
-- CHAT_MSG_ADDON und führt keine Versionsprüfung durch (keine „veraltet“-Meldungen).
-- AceComm stückelt Texte über 255 Byte: "\001" erstes, "\002" weitere, "\003" letztes Stück;
-- beginnt ein einzelner Text mit einem Steuerzeichen (\001–\009), wird "\004" vorangestellt.
local _, ns = ...

local GargulCompat = {}
ns.GargulCompat = GargulCompat

local PREFIX = "GargulComm2"
local ACTION_START = 10
local ACTION_STOP = 11
local MAX_LEN = 255
local MANUAL_TIME = 90 -- Fensterdauer bei manueller Würfelzeit (Raidlead beendet)
local MIN_TIME = 5     -- Gargul lehnt kürzere Zeiten beim Starter ab

local LibDeflate = LibStub and LibStub:GetLibrary("LibDeflate", true)
local LibSerialize = LibStub and LibStub:GetLibrary("LibSerialize", true)

local messageCounter = 0
-- Ende (GetTime) der zuletzt gesendeten Gargul-Runde. Gargul beendet sie danach selbst; ein zweiter
-- Stopp erzeugt bei den Empfängern eine sichtbare Warnung, ein Start derselben Runde davor wird ignoriert.
local expiresAt
local STOP_MARGIN = 1    -- so kurz vor dem Ende kein Stopp mehr senden
local RESTART_DELAY = 2  -- Abstand eines Neustarts zum Selbst-Ende der vorigen Runde
local startToken = 0

function GargulCompat:IsEnabled()
    return ns.db and ns.db.gargulCompat ~= false
end

-- Gargul beim Raidlead selbst geladen: unsere Nachricht käme bei ihm als eigene Runde an (Ansagen,
-- Raid-Warnung, eigenes Fenster). Dann senden wir nicht.
local function gargulLoadedHere()
    return C_AddOns ~= nil and C_AddOns.IsAddOnLoaded("Gargul") and true or false
end

local function encode(action, content)
    messageCounter = messageCounter + 1
    local payload = {
        a = action,
        b = content,
        d = string.format("PSR%d%d", GetServerTime(), messageCounter),
    }
    local ok, text = pcall(function()
        local serialized = LibSerialize:Serialize(payload)
        local compressed = LibDeflate:CompressDeflate(serialized, { level = 5 })
        return LibDeflate:EncodeForWoWAddonChannel(compressed)
    end)
    if not ok then
        ns.Debug("Gargul", "Kodieren fehlgeschlagen:", text)
        return nil
    end
    return text
end

-- Wie AceComm-3.0 SendCommMessage stückeln
local function sendAceComm(channel, text)
    local length = #text
    local forceMultipart = false
    if text:match("^[\001-\009]") then
        if length + 1 > MAX_LEN then
            forceMultipart = true
        else
            text = "\004" .. text
            length = length + 1
        end
    end
    if not forceMultipart and length <= MAX_LEN then
        ns.Comm:SendRaw(PREFIX, channel, text)
        return
    end
    local chunkLen = MAX_LEN - 1
    ns.Comm:SendRaw(PREFIX, channel, "\001" .. text:sub(1, chunkLen))
    local pos = 1 + chunkLen
    while pos + chunkLen <= length do
        ns.Comm:SendRaw(PREFIX, channel, "\002" .. text:sub(pos, pos + chunkLen - 1))
        pos = pos + chunkLen
    end
    ns.Comm:SendRaw(PREFIX, channel, "\003" .. text:sub(pos))
end

local function canSend()
    if not GargulCompat:IsEnabled() or not LibDeflate or not LibSerialize then
        return nil
    end
    local channel = ns.GroupChannel()
    if not channel then return nil end
    if gargulLoadedHere() then
        ns.Debug("Gargul", "Gargul ist selbst geladen – kein Gargul-Fenster gesendet")
        return nil
    end
    return channel
end

-- Kurzer Item-String ohne leere Felder am Ende, wie Gargul ihn erwartet ("item:12345")
local function itemString(itemID, link)
    local fromLink = type(link) == "string" and link:match("|H(item[:%d%-]+)")
    if fromLink then
        return (fromLink:gsub(":+$", ""))
    end
    return "item:" .. itemID
end


-- round: { itemID, link, restricted, category, holders, freeReason }
local function buildStart(round, time)
    local range, label = ns.Rolls.RANGE, ns.Rolls.LABEL
    local rolls, note
    if round.restricted then
        local category = round.category or "SR"
        rolls = { { label[category] or category, 1, range[category] or 100, 1, false, false } }
        local names = {}
        for player in pairs(round.holders or {}) do
            table.insert(names, ns.UI.ShortName(player))
        end
        table.sort(names)
        note = "Nur: " .. table.concat(names, ", ")
    else
        rolls = {
            { label.MS, 1, range.MS, 1, false, false },
            { label.OS, 1, range.OS, 2, false, false },
            { label.TM, 1, range.TM, 3, false, false },
        }
        note = round.freeReason and ("Freier Wurf (" .. round.freeReason .. ")") or nil
    end
    return encode(ACTION_START, {
        item = itemString(round.itemID, round.link),
        time = time,
        note = note,
        SupportedRolls = rolls,
    })
end

-- duration: Würfelzeit der Runde in Sekunden (0 = Raidlead beendet)
function GargulCompat:SendStart(round, duration)
    if not canSend() then return end
    -- Vorige Runde noch offen: erst beenden, sonst behält Gargul sie (gleiches Item) samt altem Timer.
    -- Gerade von selbst abgelaufen: kurz warten, bis Gargul sie sicher beendet hat.
    local delay = 0
    if expiresAt then
        local now = GetTime()
        if now < expiresAt - STOP_MARGIN then
            self:SendStop()
        elseif now < expiresAt + RESTART_DELAY then
            delay = expiresAt + RESTART_DELAY - now
        end
    end
    expiresAt = nil
    startToken = startToken + 1
    local token = startToken

    local function send()
        if token ~= startToken then return end -- inzwischen beendet oder neu gestartet
        local channel = canSend()
        if not channel then return end
        local time = duration > 0 and math.max(math.floor(duration - delay), MIN_TIME) or MANUAL_TIME
        local text = buildStart(round, time)
        if not text then return end
        sendAceComm(channel, text)
        expiresAt = GetTime() + time
        ns.Debug("Gargul", "Würfelrunde gesendet", round.itemID, "Zeit:", time, "beschränkt:", round.restricted)
    end
    if delay > 0 then
        C_Timer.After(delay, send)
    else
        send()
    end
end

function GargulCompat:SendStop()
    startToken = startToken + 1 -- verzögerten Start verwerfen
    local ends = expiresAt
    expiresAt = nil
    if not ends or GetTime() >= ends - STOP_MARGIN then return end -- Gargul beendet selbst
    local channel = canSend()
    if not channel then return end
    local text = encode(ACTION_STOP, nil)
    if text then
        sendAceComm(channel, text)
        ns.Debug("Gargul", "Würfelrunde beendet gesendet")
    end
end

-- Testbefehl (/paeniksoftres gargultest): Startnachricht bauen und wie Gargul wieder entpacken
function GargulCompat:SelfTest()
    if not LibDeflate or not LibSerialize then
        ns.Print("Gargul-Test: LibDeflate oder LibSerialize fehlt.")
        return
    end
    local text = buildStart({ itemID = 6948, restricted = false }, 30)
    if not text then
        ns.Print("Gargul-Test: Kodieren fehlgeschlagen (siehe Debug-Log).")
        return
    end
    local ok, success, payload = pcall(function()
        local compressed = LibDeflate:DecodeForWoWAddonChannel(text)
        local decompressed = LibDeflate:DecompressDeflate(compressed)
        return LibSerialize:Deserialize(decompressed)
    end)
    if not ok or not success or type(payload) ~= "table" or type(payload.b) ~= "table" then
        ns.Print("Gargul-Test: Entpacken fehlgeschlagen: " .. tostring(success))
        return
    end
    local parts = #text <= MAX_LEN and 1 or math.ceil(#text / (MAX_LEN - 1))
    ns.Print(string.format("Gargul-Test OK: Aktion %s, Item %s, Zeit %s, %d Würfelknöpfe, %d Byte (%d Nachricht(en))",
        tostring(payload.a), tostring(payload.b.item), tostring(payload.b.time), #(payload.b.SupportedRolls or {}),
        #text, parts))
    ns.Print("Gruppenkanal: " .. (ns.GroupChannel() or "keiner (solo – es wird nichts gesendet)")
        .. " | Gargul hier geladen: " .. (gargulLoadedHere() and "ja (es wird nichts gesendet)" or "nein")
        .. " | Option: " .. (self:IsEnabled() and "an" or "aus"))
end
