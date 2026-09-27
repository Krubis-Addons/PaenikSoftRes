-- Sync zwischen Raidlead und Raidern über Addon-Messages (Präfix "PSR").
-- Maßgeblich ist nur die Sitzung des Gruppenleiters, der sie besitzt (Session:IsMaster()).
-- Raider spiegeln sie und schicken Wünsche per Whisper an ihn.
--
-- Nachrichten (Felder getrennt durch "^", Version zuerst):
--   1^R^sid^leader^instKey^instName^max^dup^locked^deadline^name^killed   Lead → Gruppe: Regeln
--                                    (deadline 0 = keiner, killed = gelegte Bosse "1,4,7")
--   1^F^sid                                           Lead → Gruppe: voller Stand folgt (Reserves leeren)
--   1^P^sid^Name-Realm=id,id;Name-Realm=...           Lead → Gruppe: Reserves (mehrere Spieler)
--   1^H^sid^leeren(1/0)^itemID=Notiz;...              Lead → Gruppe: Hard Reserves
--   1^L^sid^leeren(1/0)^öffnen(1/0)^Leiche^itemID=lootKey;...  Lead → Gruppe: gelootete Items (Beute),
--                                    Leiche = zuletzt gelootete (GUID; „Soft Reserves“-Fenster zeigt nur sie)
--   1^E^sid                                           Lead → Gruppe: Sitzung beendet
--   1^Q                                               Raider → Gruppe: Stand anfordern
--   1^S^sid^id,id                                     Raider → Lead (gezielt): eigene Reserves
--   1^X^sid^Text                                      Lead → Raider (gezielt): abgelehnt
-- „Gezielt“ heißt: 1^@^Empfänger^Typ^... über Gruppe (Empfänger in der Gruppe) bzw. Gilde, nie WHISPER
-- (Whisper-Ziele mit Forever-Nachnamen kamen nicht an). Auch GuildSync und Rolls nutzen das über
-- Comm:SendWhisper / SendWhisperThen.
local _, ns = ...

local Comm = {}
ns.Comm = Comm

local PREFIX = "PSR"
local VERSION = "1"
local SEP = "^"
local MAX_LEN = 250          -- Limit von SendAddonMessage: 255 Byte
local SEND_INTERVAL = 0.3    -- Abstand zwischen zwei Nachrichten
local RETRY_DELAY = 2        -- Wartezeit nach Throttle/Lockdown
local MAX_RETRIES = 30       -- danach wird eine Nachricht verworfen
local REQUEST_TIMEOUT = 5    -- Sekunden bis „keine Antwort vom Raidlead“

local function sanitize(text)
    return (tostring(text or ""):gsub("[%^;=,]", " "))
end

local groupChannel = ns.GroupChannel
local unitForName = ns.UnitForName

local function isGroupLeader(fullName)
    local unit = unitForName(fullName)
    return unit ~= nil and UnitIsGroupLeader(unit) and true or false
end

-- Sende-Queue -------------------------------------------------------------
-- Respektiert Throttle und Addon-Message-Sperre (Midnight: Instanz + Kampf).
local queue = {}
local sending = false

local function processQueue()
    local entry = queue[1]
    if not entry then
        sending = false
        return
    end
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, entry.prefix or PREFIX, entry.text, entry.chatType,
        entry.target)
    local R = Enum.SendAddonMessageResult or {}
    local retry = ok and (result == R.AddonMessageThrottle or result == R.ChannelThrottle
        or result == R.AddOnMessageLockdown)

    if retry and entry.retries < MAX_RETRIES then
        entry.retries = entry.retries + 1
        ns.Debug("Comm", "Senden verzögert, Ergebnis", result, "Versuch", entry.retries)
        C_Timer.After(RETRY_DELAY, processQueue)
        return
    end

    table.remove(queue, 1)
    if ok and (result == nil or result == true or result == R.Success) then
        if entry.onSent then
            entry.onSent()
        end
    else
        ns.Debug("Comm", "Senden fehlgeschlagen:", ok and result or "Fehler: " .. tostring(result),
            entry.chatType, entry.target, entry.text)
    end
    C_Timer.After(SEND_INTERVAL, processQueue)
end

-- prefix nil = eigenes Präfix; text ist dann bereits fertig (fremdes Protokoll, z. B. Gargul)
local function enqueue(prefix, chatType, target, onSent, text)
    local entry = { prefix = prefix, text = text, chatType = chatType, target = target, onSent = onSent, retries = 0 }
    -- Gilden-Nachrichten haben die niedrigste Priorität: Gruppe und Whisper (z. B. Würfelrunden)
    -- werden vor wartende Gilden-Nachrichten gestellt. queue[1] wird gerade gesendet und bleibt vorn.
    local position = #queue + 1
    if chatType ~= "GUILD" then
        for i = 2, #queue do
            if queue[i].chatType == "GUILD" then
                position = i
                break
            end
        end
    end
    table.insert(queue, position, entry)
    if prefix then
        ns.Debug("Comm", "->", prefix, chatType, target or "", #text, "Byte")
    else
        ns.Debug("Comm", "->", chatType, target or "", text)
    end
    if not sending then
        sending = true
        processQueue()
    end
end

local function queueMessage(chatType, target, onSent, ...)
    if not chatType then return end
    enqueue(nil, chatType, target, onSent, table.concat({ VERSION, ... }, SEP))
end

local function send(chatType, target, ...)
    queueMessage(chatType, target, nil, ...)
end

-- Gezielte Nachricht an einen Spieler. Kein WHISPER: dessen Zielname ist bei Forever-Nachnamen
-- unzuverlässig (im Gruppentest kamen Whisper-Nachrichten nie an). Stattdessen über Gruppe bzw.
-- Gilde mit Empfängerfeld:
--   1^@^Empfänger^Typ^...   – nur der Empfänger verarbeitet sie (siehe CHAT_MSG_ADDON)
-- Gibt false zurück, wenn der Empfänger über keinen Kanal erreichbar ist.
local function directedChannel(target)
    if unitForName(target) then
        return groupChannel()
    end
    if IsInGuild and IsInGuild() then
        return "GUILD"
    end
end

local function sendTo(target, onSent, ...)
    local channel = directedChannel(target)
    if not channel then
        ns.Debug("Comm", "Empfänger nicht erreichbar (weder Gruppe noch Gilde):", target)
        return false
    end
    queueMessage(channel, nil, onSent, "@", target, ...)
    return true
end

-- Lead: Nachrichten bauen -------------------------------------------------

local function sendRules()
    local s = ns.Session:Get()
    local channel = groupChannel()
    if not s or not channel then return end
    send(channel, nil, "R", s.id, s.leader, s.instanceKey or "", sanitize(s.instanceName),
        s.maxReserves, s.allowDuplicates and 1 or 0, s.locked and 1 or 0, s.deadline or 0, sanitize(s.name),
        ns.Session:KilledToString(s))
end

local function isFakePlayer(s, player)
    local list = s.reserves[player]
    return list and list[1] and list[1].source == "fake"
end

-- Reserves mehrerer Spieler, auf mehrere Nachrichten verteilt.
local function sendPlayers(players)
    local s = ns.Session:Get()
    local channel = groupChannel()
    if not s or not channel then return end
    local head = table.concat({ VERSION, "P", s.id }, SEP) .. SEP
    local chunk = {}
    local length = #head
    local function flush()
        if #chunk > 0 then
            send(channel, nil, "P", s.id, table.concat(chunk, ";"))
            chunk, length = {}, #head
        end
    end
    for _, player in ipairs(players) do
        if not isFakePlayer(s, player) then
            local entry = player .. "=" .. table.concat(ns.Session:GetReservedItemIDs(player), ",")
            if #head + #entry > MAX_LEN then
                -- z. B. ein Import mit sehr vielen Items: passt in keine Nachricht
                ns.Debug("Comm", "Reserves zu lang für eine Nachricht, nicht gesendet:", player, #entry)
            else
                if length + #entry + 1 > MAX_LEN then
                    flush()
                end
                table.insert(chunk, entry)
                length = length + #entry + 1
            end
        end
    end
    flush()
end

-- Komplette Liste der Hard Reserves; das erste Stück leert beim Empfänger die alte Liste
local function sendHardReserves()
    local s = ns.Session:Get()
    local channel = groupChannel()
    if not s or not channel then return end
    local head = table.concat({ VERSION, "H", s.id, 1 }, SEP) .. SEP
    local chunk, length, first = {}, #head, true
    local function flush(force)
        if #chunk > 0 or force then
            send(channel, nil, "H", s.id, first and 1 or 0, table.concat(chunk, ";"))
            chunk, length, first = {}, #head, false
        end
    end
    for _, entry in ipairs(ns.Session:HardReservesToList(s)) do
        if length + #entry + 1 > MAX_LEN then
            flush()
        end
        table.insert(chunk, entry)
        length = length + #entry + 1
    end
    flush(first) -- ohne Einträge trotzdem einmal senden (leert die Liste)
end

-- Verteilliste in Stücken; das erste leert beim Empfänger, open = 1: Raider öffnen das Fenster (Raidlead lootet)
local function sendLootList(open)
    local s = ns.Session:Get()
    local channel = groupChannel()
    if not s or not channel then return end
    local corpse = s.currentCorpse or ""
    local head = table.concat({ VERSION, "L", s.id, 1, 1, corpse }, SEP) .. SEP
    local chunk, length, first = {}, #head, true
    local function flush(force)
        if #chunk > 0 or force then
            send(channel, nil, "L", s.id, first and 1 or 0, open and 1 or 0, corpse, table.concat(chunk, ";"))
            chunk, length, first = {}, #head, false
        end
    end
    for _, entry in ipairs(ns.Session:LootListToEntries(s)) do
        if length + #entry + 1 > MAX_LEN then
            flush()
        end
        table.insert(chunk, entry)
        length = length + #entry + 1
    end
    flush(first) -- ohne Einträge trotzdem einmal senden (leert die Liste)
end

local function sendFullState()
    local s = ns.Session:Get()
    local channel = groupChannel()
    if not s or not channel then return end
    sendRules()
    send(channel, nil, "F", s.id)
    sendHardReserves()
    if ns.Roles:IsDistributor() then
        sendLootList(false) -- bei separatem Plündermeister sendet er die Liste selbst
    end
    local players = {}
    for player in pairs(s.reserves) do
        table.insert(players, player)
    end
    table.sort(players)
    sendPlayers(players)
end

-- Entprellen: mehrere Änderungen kurz hintereinander → wenige Nachrichten.
local pendingRules, pendingPlayers, pendingFull, pendingHR = false, {}, false, false
local pendingLoot, pendingLootOpen = false, false

local function flushPending()
    if ns.Session:IsMaster() and groupChannel() then
        if pendingFull then
            sendFullState()
        else
            if pendingRules then
                sendRules()
            end
            if pendingHR then
                sendHardReserves()
            end
            local players = {}
            for player in pairs(pendingPlayers) do
                table.insert(players, player)
            end
            if #players > 0 then
                sendPlayers(players)
            end
        end
    end
    -- Beute-Liste sendet der Verteiler (Raidlead bzw. Plündermeister), auch ohne eigene Sitzung
    if pendingLoot and not pendingFull and ns.Roles:IsDistributor() and groupChannel() then
        sendLootList(pendingLootOpen)
    end
    pendingRules, pendingFull, pendingHR = false, false, false
    pendingLoot, pendingLootOpen = false, false
    wipe(pendingPlayers)
end

local flushScheduled = false
local function scheduleFlush(delay)
    if flushScheduled then return end
    flushScheduled = true
    C_Timer.After(delay or 0.5, function()
        flushScheduled = false
        flushPending()
    end)
end

ns:On("SESSION_RULES_CHANGED", function()
    pendingRules = true
    scheduleFlush()
end)

ns:On("SESSION_RESERVES_CHANGED", function(player)
    pendingPlayers[player] = true
    scheduleFlush()
end)

ns:On("SESSION_FULL_SYNC", function()
    pendingFull = true
    scheduleFlush()
end)

ns:On("SESSION_HR_CHANGED", function()
    pendingHR = true
    scheduleFlush()
end)

-- Verteilliste geändert (LootList); open = true: Raider sollen das Fenster öffnen
ns:On("SESSION_LOOT_CHANGED", function(open)
    pendingLoot = true
    pendingLootOpen = pendingLootOpen or open == true
    scheduleFlush()
end)

ns:On("SESSION_ENDED", function(sessionID)
    local channel = groupChannel()
    if channel and ns.Roles:IsLead() then
        send(channel, nil, "E", sessionID)
    end
end)

-- Raider: eigene Reserves einreichen ---------------------------------------
-- pendingOwn ist die zuletzt eingereichte, noch nicht bestätigte eigene Liste.
-- Weitere Klicks bauen darauf auf, damit schnelle Klicks nichts verlieren.
local requestTimer
local pendingOwn

local function clearPending()
    if requestTimer then
        requestTimer:Cancel()
        requestTimer = nil
    end
    pendingOwn = nil
end

function Comm:GetOwnReserves()
    if pendingOwn then
        return CopyTable(pendingOwn)
    end
    return ns.Session:GetReservedItemIDs(ns.FullName("player"))
end

function Comm:IsRequestPending()
    return pendingOwn ~= nil
end

function Comm:SubmitOwnReserves(itemIDs)
    local me = ns.FullName("player")
    local s = ns.Session:Get()
    if not s then return false, "Keine Sitzung" end
    if ns.Session:IsOwner() and (ns.Roles:IsLead() or not groupChannel()) then
        return ns.Session:SetPlayerReserves(me, itemIDs)
    end
    if ns.Session:IsOwner() then
        return false, "Du bist nicht mehr Raidlead. Aktualisiere, um die Sitzung des Raidleads zu laden."
    end
    -- Vorab lokal prüfen, damit der Raider sofort eine Rückmeldung bekommt.
    local ok, err = ns.Session:ValidateReserves(itemIDs, me)
    if not ok then return false, err end
    -- Eine ältere Gilden-Anmeldung für diese Sitzung ist damit überholt
    if ns.char.signups then
        ns.char.signups[s.id] = nil
    end

    if not directedChannel(s.leader) then
        return false, "Raidlead nicht erreichbar (nicht in Gruppe oder Gilde)"
    end
    pendingOwn = CopyTable(itemIDs)
    if requestTimer then
        requestTimer:Cancel()
        requestTimer = nil
    end
    sendTo(s.leader, function()
        -- Timeout erst ab dem tatsächlichen Senden
        if requestTimer then
            requestTimer:Cancel()
        end
        requestTimer = C_Timer.NewTimer(REQUEST_TIMEOUT, function()
            requestTimer = nil
            pendingOwn = nil
            ns.Print("Keine Antwort vom Raidlead (" .. s.leader .. "). Ist " .. ns.TITLE .. " bei ihm aktiv?")
            ns:Fire("SESSION_CHANGED")
        end)
    end, "S", s.id, table.concat(itemIDs, ","))
    ns:Fire("SESSION_CHANGED")
    return true
end

function Comm:RequestState()
    local channel = groupChannel()
    if channel then
        send(channel, nil, "Q")
    end
end

-- Empfang -----------------------------------------------------------------

local function splitFields(text)
    local fields = {}
    for field in (text .. SEP):gmatch("(.-)%" .. SEP) do
        table.insert(fields, field)
    end
    return fields
end

local function parseItemIDs(text)
    local ids = {}
    for id in (text or ""):gmatch("%d+") do
        table.insert(ids, tonumber(id))
    end
    return ids
end

local function normalizeSender(sender)
    if sender:find("-", 1, true) then
        return sender
    end
    local realm = GetNormalizedRealmName()
    return realm and (sender .. "-" .. realm) or sender
end

local handlers = {}

-- Regeln: nur vom Gruppenleiter, und nie, wenn man selbst die Master-Liste hat
function handlers.R(sender, f)
    if f[4] ~= sender or not isGroupLeader(sender) then
        ns.Debug("Comm", "R ignoriert, Absender nicht Gruppenleiter:", sender)
        return
    end
    if ns.Session:IsMaster() then
        ns.Debug("Comm", "R ignoriert, eigene Master-Liste", sender)
        return
    end
    local s = ns.Session:Get()
    if s and s.id ~= f[3] then
        ns.Debug("Comm", "Sitzung", s.id, "wird durch Sitzung von", sender, "ersetzt")
        clearPending()
    end
    ns.Session:ApplyRemoteSession({
        id = f[3],
        leader = f[4],
        instanceKey = f[5] ~= "" and f[5] or nil,
        instanceName = f[6] ~= "" and f[6] or nil,
        maxReserves = tonumber(f[7]) or 1,
        allowDuplicates = f[8] == "1",
        locked = f[9] == "1",
        deadline = tonumber(f[10]) ~= 0 and tonumber(f[10]) or nil,
        name = f[11] ~= "" and f[11] or nil,
        killed = ns.Session:KilledFromString(f[12]),
    })
end

local function isFromSessionLeader(sender, sessionID)
    local s = ns.Session:Get()
    return s ~= nil and s.id == sessionID and s.leader == sender and not ns.Session:IsOwner()
end

-- Voller Stand folgt
function handlers.F(sender, f)
    if isFromSessionLeader(sender, f[3]) then
        ns.Session:ApplyRemoteFullReset(f[3])
    end
end

-- Hard Reserves vom Raidlead (f[4] = 1: vorher leeren)
function handlers.H(sender, f)
    if isFromSessionLeader(sender, f[3]) then
        ns.Session:ApplyRemoteHardReserves(f[3], f[5], f[4] == "1")
    end
end

-- Verteilliste vom Raidlead: L^sid^leeren^öffnen^Leiche^itemID=lootKey;...
function handlers.L(sender, f)
    -- vom Verteiler (Gruppenleiter bzw. Plündermeister); auch der Raidlead übernimmt sie in seine Sitzung
    local s = ns.Session:Get()
    if not s or s.id ~= f[3] or not ns.Roles:IsDistributorName(sender) then return end
    local fresh = ns.Session:ApplyRemoteLootList(f[3], f[7], f[4] == "1", f[6])
    if f[5] == "1" and fresh > 0 then
        ns:Fire("LOOT_LIST_OPEN")
    end
end

-- Reserves vom Raidlead
function handlers.P(sender, f)
    if not isFromSessionLeader(sender, f[3]) then return end
    local me = ns.FullName("player")
    for entry in (f[4] or ""):gmatch("[^;]+") do
        local player, ids = entry:match("^(.-)=(.*)$")
        if player then
            if player == me then
                clearPending() -- vor dem Übernehmen, damit die UI den neuen Stand zeigt
            end
            ns.Session:ApplyRemoteReserves(player, parseItemIDs(ids))
        end
    end
end

-- Sitzung beendet
function handlers.E(sender, f)
    if isFromSessionLeader(sender, f[3]) then
        clearPending()
        ns.Session:ApplyRemoteEnd(f[3])
    end
end

-- Stand angefordert: nur die Master-Liste antwortet
function handlers.Q()
    if ns.Session:IsMaster() then
        pendingFull = true
        scheduleFlush(2)
    end
    -- separater Plündermeister: seine Beute-Liste nachreichen
    if ns.Roles:IsDistributor() and not ns.Session:IsMaster() and ns.Session:Get() then
        pendingLoot = true
        scheduleFlush(2)
    end
end

-- Reserve-Wunsch eines Raiders
function handlers.S(sender, f)
    local s = ns.Session:Get()
    if not ns.Session:IsMaster() or s.id ~= f[3] then
        ns.Debug("Comm", "S ignoriert, keine passende Master-Liste", sender, f[3])
        return
    end
    if not unitForName(sender) then
        ns.Debug("Comm", "S abgelehnt, Absender nicht in der Gruppe:", sender)
        sendTo(sender, nil, "X", f[3], "Nicht in der Gruppe")
        return
    end
    local ok, err = ns.Session:SetPlayerReserves(sender, parseItemIDs(f[4]))
    if not ok then
        sendTo(sender, nil, "X", f[3], sanitize(err))
        -- aktuellen Stand zurückschicken, damit der Raider synchron bleibt
        pendingPlayers[sender] = true
        scheduleFlush()
    end
end

-- Ablehnung vom Raidlead
function handlers.X(sender, f)
    if not isFromSessionLeader(sender, f[3]) then return end
    clearPending()
    ns.Print("Raidlead hat abgelehnt: " .. (f[4] or "?"))
    ns:Fire("SESSION_CHANGED")
end

-- Spieler, von denen in dieser Spielsitzung eine Addon-Nachricht kam (Raider senden beim
-- Gruppenbeitritt eine Stand-Anfrage Q). Nur ein Anhaltspunkt: wer noch nichts gesendet hat, fehlt.
local addonUsers = {}

function Comm:HasAddon(player)
    return player == ns.FullName("player") or addonUsers[player] == true
end

function ns:CHAT_MSG_ADDON(prefix, text, _, sender)
    -- In Midnight können Chat-Werte Secrets sein: dann nicht anfassen.
    if issecretvalue and (issecretvalue(prefix) or issecretvalue(text) or issecretvalue(sender)) then
        return
    end
    if prefix ~= PREFIX then return end
    sender = normalizeSender(sender)
    if sender == ns.FullName("player") then return end
    addonUsers[sender] = true
    local f = splitFields(text)
    if f[1] ~= VERSION then
        ns.Debug("Comm", "Unbekannte Version von", sender, f[1])
        return
    end
    -- Gezielte Nachricht (1^@^Empfänger^Typ^...): nur für uns bestimmt, sonst ignorieren
    if f[2] == "@" then
        if (f[3] or ""):lower() ~= ns.FullName("player"):lower() then return end
        table.remove(f, 2)
        table.remove(f, 2)
    end
    ns.Debug("Comm", "<-", sender, text)
    local handler = handlers[f[2]]
    if handler then
        handler(sender, f)
    end
end

-- Gruppenbeitritt, Login, Rollenwechsel: Stand anfordern, wenn man nicht selbst Master ist
local requestScheduled = false
local function requestStateSoon()
    if requestScheduled then return end
    requestScheduled = true
    C_Timer.After(2, function()
        requestScheduled = false
        if groupChannel() and not ns.Session:IsMaster() then
            Comm:RequestState()
        end
    end)
end

function ns:GROUP_JOINED()
    requestStateSoon()
end

ns:On("LOGIN", requestStateSoon)
ns:On("ROLE_CHANGED", requestStateSoon)

-- Schnittstelle für weitere Module (z. B. Rolls.lua) -----------------------------

-- Nachricht an die Gruppe (nichts, wenn nicht in einer Gruppe)
function Comm:SendGroup(...)
    send(groupChannel(), nil, ...)
end

function Comm:SendWhisper(target, ...)
    return sendTo(target, nil, ...)
end

-- Nachricht an alle Online-Gildenmitglieder mit Addon (unsichtbar, kein Chat)
function Comm:SendGuild(...)
    if IsInGuild and IsInGuild() then
        send("GUILD", nil, ...)
    end
end

Comm.VERSION = VERSION
Comm.SEP = SEP
Comm.MAX_LEN = MAX_LEN

-- Wie SendWhisper, ruft onSent auf, sobald die Nachricht tatsächlich gesendet wurde
-- Fertige Nachricht mit fremdem Präfix über dieselbe Queue (Reihenfolge und Throttle bleiben erhalten)
function Comm:SendRaw(prefix, chatType, text)
    if not chatType then return end
    enqueue(prefix, chatType, nil, nil, text)
end

function Comm:SendWhisperThen(target, onSent, ...)
    return sendTo(target, onSent, ...)
end

-- handler(sender, fields); fields[1] = Version, fields[2] = Typ, ab fields[3] die Daten
function Comm:RegisterHandler(msgType, handler)
    assert(not handlers[msgType], "Nachrichtentyp bereits vergeben: " .. msgType)
    handlers[msgType] = handler
end

Comm.IsGroupLeader = isGroupLeader
Comm.Sanitize = sanitize

C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
ns:RegisterEvent("CHAT_MSG_ADDON")
ns:RegisterEvent("GROUP_JOINED")
