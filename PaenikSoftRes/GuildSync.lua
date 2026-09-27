-- Gilden-Synchronisation: Raider können ohne Gruppe bis zum Anmeldeschluss reservieren.
-- Alles über unsichtbare Addon-Nachrichten im Kanal GUILD bzw. per Whisper (kein Chat-Spam).
--
-- Der Raidlead veröffentlicht einzelne Sitzungen (session.published). Jedes Addon in der Gilde speichert
-- eine Kopie (db.guildSessions) und gibt sie an später eingeloggte Mitglieder weiter. Anmeldungen der
-- Raider liegen lokal (db.signups) und gehen per Whisper an den Raidlead, sobald er online ist.
--
-- Nachrichten (Präfix PSR, Felder mit "^"):
--   GR^sid^ver^leader^instKey^instName^max^dup^locked^deadline^name^updatedAt^killed   Regeln (Gilde)
--   GH^sid^ver^leeren^itemID=Notiz;...  Hard Reserves
--   GF^sid^ver^n                  voller Stand der Reserves folgt, in n GP-Stücken
--   GP^sid^ver^Name-Realm=id,id;...   bestätigte Reserves (Stück)
--   GD^sid^ver^leader             Sitzung gelöscht/zurückgezogen (Löschmarke, wird weitergegeben)
--   GQ                            Login-Abfrage: wer hat Sitzungen?
--   GS^sid^signedAt^id,id         (Whisper an den Raidlead) Anmeldung eines Raiders
--   GA^sid^signedAt^outdated      (Whisper an den Raider) Anmeldung verarbeitet (outdated=1: neuere Auswahl vorhanden)
--   GX^sid^signedAt^Text          (Whisper an den Raider) Anmeldung abgelehnt
--   GU^sid^Spieler^signedAt^id,id (Gilde) Anmeldung, von allen gespeichert und an den Raidlead
--                                 weitergereicht, sobald er online ist (auch ohne den Raider)
--   GC^sid^Spieler^signedAt^Status^Text (Gilde, vom Raidlead) Ergebnis: a = angenommen,
--                                 o = überholt, x = abgelehnt; Mitglieder verwerfen die Weitergabe
--   GK^rank^version^setBy          (Gilde) Raidleiter ab Gildenrang (nur vom Gildenmeister, weitergegeben)
-- Weitergegebene Anmeldungen werden bewusst ohne Echtheitsprüfung übernommen (Entscheidung des Nutzers).
local _, ns = ...

local GuildSync = {}
ns.GuildSync = GuildSync

local Signup = {}
ns.Signup = Signup

local Comm = ns.Comm

local PUBLISH_DELAY = 5            -- Sekunden: Änderungen sammeln, dann einmal verteilen
local REPUBLISH_MIN = 30           -- Raidlead: dieselbe Sitzung höchstens alle 30 s auf Nachfrage verteilen
local REPLY_DELAY_MIN, REPLY_DELAY_MAX = 1, 4
local SUPPRESS_WINDOW = 10         -- Sekunden: gleiche Version schon gehört → nicht erneut senden
local RESEND_AFTER = 20            -- Sekunden bis eine Anmeldung erneut gesendet wird
local SEEN_ONLINE_WINDOW = 300     -- Nachricht in den letzten 5 Min. → gilt als online (nur ohne Roster-Info)
local LATE_WINDOW = 24 * 3600      -- rechtzeitig abgegebene Anmeldungen bis 24 h nach Schluss annehmen
local KEEP_AFTER_DEADLINE = 3 * 24 * 3600
local KEEP_WITHOUT_DEADLINE = 14 * 24 * 3600
local KEEP_TOMBSTONE = 14 * 24 * 3600

local function enabled()
    return ns.db ~= nil and ns.db.guildSync ~= false and IsInGuild ~= nil and IsInGuild()
end

local function copies()
    ns.char.guildSessions = ns.char.guildSessions or {}
    return ns.char.guildSessions
end

local function signups()
    ns.char.signups = ns.char.signups or {}
    return ns.char.signups
end

local function me()
    return ns.FullName("player")
end

local function ownSession(sid)
    return ns.char.sessions and ns.char.sessions[sid or ""]
end

local function sameItems(a, b)
    if #a ~= #b then return false end
    local x, y = CopyTable(a), CopyTable(b)
    table.sort(x)
    table.sort(y)
    for i = 1, #x do
        if x[i] ~= y[i] then return false end
    end
    return true
end

local function parseItemIDs(text)
    local ids = {}
    for id in (text or ""):gmatch("%d+") do
        table.insert(ids, tonumber(id))
    end
    return ids
end

-- Online-Status über den Gildenroster ----------------------------------------------------
-- Vor jedem Whisper prüfen: an Offline-Spieler erzeugt WoW eine sichtbare Fehlermeldung.
local rosterStatus = {} -- [Name-Realm] = true (online) / false (offline oder nur mobil)
local lastSeen = {}     -- [Name-Realm] = GetTime() der letzten Addon-Nachricht (Fallback ohne Roster)
local rosterRank = {}   -- [Name-Realm] = Gildenrang-Index (0 = Gildenmeister)

local function keyFromGUID(guid)
    if ns.IsSecret(guid) or not guid then return nil end
    local _, _, _, _, _, name, realm = GetPlayerInfoByGUID(guid)
    if ns.IsSecret(name) or ns.IsSecret(realm) or not name or name == "" then return nil end
    realm = (realm and realm ~= "") and ns.NormalizeRealm(realm) or GetNormalizedRealmName()
    return realm and (name .. "-" .. realm) or name
end

local function refreshRoster()
    if not (GetNumGuildMembers and GetGuildRosterInfo) then return end
    wipe(rosterStatus)
    wipe(rosterRank)
    for i = 1, GetNumGuildMembers() do
        local name, _, rankIndex, _, _, _, _, _, isOnline, _, _, _, _, isMobile, _, _, guid = GetGuildRosterInfo(i)
        if not ns.IsSecret(isOnline) and not ns.IsSecret(isMobile) then
            local key = keyFromGUID(guid)
            if not key and not ns.IsSecret(name) and name then
                key = name:find("-", 1, true) and name or (name .. "-" .. (GetNormalizedRealmName() or ""))
            end
            if key then
                rosterStatus[key] = (isOnline and not isMobile) and true or false
                if not ns.IsSecret(rankIndex) then
                    rosterRank[key] = rankIndex
                end
            end
        end
    end
end

function GuildSync:IsOnline(player)
    local status = rosterStatus[player]
    if status ~= nil then
        return status -- der Roster weiß es: auch „offline“ gilt, egal wann zuletzt eine Nachricht kam
    end
    return lastSeen[player] ~= nil and GetTime() - lastSeen[player] < SEEN_ONLINE_WINDOW
end

-- Gemeinsame Raidleiter ------------------------------------------------------------------
-- Der Gildenmeister legt fest, ab welchem Gildenrang man Raidleiter ist (ns.char.guildConfig =
-- { rank, version, setBy }, rank = höchster erlaubter Rang-Index, -1 = aus). Verteilt als
--   GK^rank^version^setBy        (Gilde; nur vom Gildenmeister gesetzt, von allen weitergegeben)
-- Raidleiter dürfen alle veröffentlichten Gildensitzungen übernehmen (GuildSync:Adopt), bearbeiten und
-- leiten. Wer ändert, verteilt eine neue Version (Session:Touch setzt leader = Ändernder); andere Raidleiter,
-- die dieselbe Sitzung halten, übernehmen neuere Versionen (syncOwnFromCopy). Die neueste Änderung gewinnt.

local function guildConfig()
    return ns.char and ns.char.guildConfig
end

local function myRankIndex()
    if not GetGuildInfo then return nil end
    local _, _, rankIndex = GetGuildInfo("player")
    if ns.IsSecret(rankIndex) then return nil end
    return rankIndex
end

function GuildSync:IsGuildMaster()
    return myRankIndex() == 0
end

-- Höchster Rang-Index, der als Raidleiter gilt; nil = aus (nur der Ersteller bearbeitet seine Sitzungen)
function GuildSync:GetRaidLeaderRank()
    local cfg = guildConfig()
    if not cfg or (cfg.rank or -1) < 0 then return nil end
    return cfg.rank
end

function GuildSync:IsRaidLeader(player)
    local maxRank = self:GetRaidLeaderRank()
    if not maxRank or not player then return false end
    local rank = rosterRank[player]
    if rank == nil and player == me() then
        rank = myRankIndex()
    end
    return rank ~= nil and rank <= maxRank
end

-- Rang-Namen der Gilde (Index 0 = Gildenmeister) für die Einstellung
function GuildSync:GetRankNames()
    local names = {}
    if not (GuildControlGetNumRanks and GuildControlGetRankName) then return names end
    for i = 1, GuildControlGetNumRanks() do
        local name = GuildControlGetRankName(i)
        names[i - 1] = (not ns.IsSecret(name) and name) or ("Rang " .. i)
    end
    return names
end

local heardConfig = 0 -- GetTime() der zuletzt gehörten Einstellung (Weitergabe nicht doppelt senden)

local function sendConfig(cfg)
    Comm:SendGuild("GK", cfg.rank, cfg.version, cfg.setBy)
    heardConfig = GetTime()
end

-- Nur der Gildenmeister; rank = höchster Rang-Index oder nil (aus)
function GuildSync:SetRaidLeaderRank(rank)
    if not self:IsGuildMaster() then return false end
    local cfg = { rank = rank or -1, version = GetServerTime(), setBy = me() }
    ns.char.guildConfig = cfg
    if enabled() then
        sendConfig(cfg)
    end
    ns.Debug("Guild", "Raidleiter ab Rang", cfg.rank)
    ns:Fire("GUILD_CONFIG_CHANGED")
    return true
end

Comm:RegisterHandler("GK", function(sender, f)
    if not enabled() then return end
    local rank, version, setBy = tonumber(f[3]), tonumber(f[4]) or 0, f[5]
    if not rank or not setBy then return end
    heardConfig = GetTime()
    local cfg = guildConfig()
    if cfg and (cfg.version or 0) >= version then return end
    -- nur Einstellungen des Gildenmeisters (laut Gildenroster) übernehmen
    if rosterRank[setBy] ~= 0 then
        ns.Debug("Guild", "GK ignoriert, nicht vom Gildenmeister:", setBy, "via", sender)
        return
    end
    ns.char.guildConfig = { rank = rank, version = version, setBy = setBy }
    ns.Debug("Guild", "Raidleiter ab Rang", rank, "von", setBy)
    ns:Fire("GUILD_CONFIG_CHANGED")
    ns:Fire("SESSION_CHANGED")
end)

-- Neuere Version einer Sitzung, die ich selbst halte, von einem anderen Raidleiter übernehmen
-- (Regeln, Reserves, Hard Reserves, gelegte Bosse; Verlauf und Beute bleiben lokal)
local function syncOwnFromCopy(sid)
    local copy, own = copies()[sid], ownSession(sid)
    if not copy or not own or copy.deleted or not copy.complete then return end
    if (copy.version or 0) <= (own.version or 0) or copy.leader == me() then return end
    if not GuildSync:IsRaidLeader(copy.leader) then
        ns.Debug("Guild", "Fremde Änderung ignoriert, kein Raidleiter:", copy.leader, sid)
        return
    end
    for _, key in ipairs({ "instanceKey", "instanceName", "maxReserves", "allowDuplicates", "locked", "deadline",
        "name", "leader", "version", "updatedAt" }) do
        own[key] = copy[key]
    end
    own.nameAuto = false
    own.published = true
    own.killed = copy.killed and CopyTable(copy.killed) or nil
    own.hardReserves = copy.hardReserves and CopyTable(copy.hardReserves) or nil
    own.reserves = CopyTable(copy.reserves or {})
    ns.Print(string.format("Sitzung „%s“ wurde von %s geändert und übernommen.", own.name or sid,
        ns.UI.ShortName(copy.leader)))
    ns:Fire("SESSION_CHANGED")
    if ns.char.activeSessionId == sid then
        ns:Fire("SESSION_FULL_SYNC") -- führe ich damit gerade die Gruppe, bekommt sie den neuen Stand
    end
end

-- Gildensitzung eines anderen Raidleiters übernehmen: wird eigene (aktive) Sitzung, bearbeitbar und leitbar
function GuildSync:Adopt(sid)
    if not self:IsRaidLeader(me()) then return false, "Du bist kein Raidleiter der Gilde" end
    local copy = copies()[sid]
    if not copy or copy.deleted or not copy.complete then return false, "Sitzung noch nicht vollständig empfangen" end
    if not ownSession(sid) then
        local s = {
            id = sid,
            createdAt = GetServerTime(),
            nameAuto = false,
            published = true,
            reserves = CopyTable(copy.reserves or {}),
            hardReserves = copy.hardReserves and CopyTable(copy.hardReserves) or nil,
            killed = copy.killed and CopyTable(copy.killed) or nil,
        }
        for _, key in ipairs({ "instanceKey", "instanceName", "maxReserves", "allowDuplicates", "locked",
            "deadline", "name", "leader", "version", "updatedAt" }) do
            s[key] = copy[key]
        end
        ns.char.sessions = ns.char.sessions or {}
        ns.char.sessions[sid] = s
        ns.Debug("Guild", "Sitzung übernommen", sid, "von", copy.leader)
    end
    ns.Session:SetActive(sid)
    ns:Fire("SESSION_CHANGED")
    return true
end

-- Veröffentlichte Gildensitzungen anderer Raidleiter, die ich übernehmen kann
function GuildSync:ListAdoptable()
    local list = {}
    if not enabled() or not self:IsRaidLeader(me()) then return list end
    for sid, copy in pairs(copies()) do
        if not copy.deleted and copy.complete and copy.leader ~= me() and not ownSession(sid) then
            table.insert(list, copy)
        end
    end
    table.sort(list, function(a, b) return (a.deadline or math.huge) < (b.deadline or math.huge) end)
    return list
end

-- Verteilen einer Sitzung (eigene oder vollständige Kopie) --------------------------------

local function buildChunks(s)
    local head = table.concat({ Comm.VERSION, "GP", s.id, s.version or 0 }, Comm.SEP) .. Comm.SEP
    local chunks, chunk, length = {}, {}, #head
    local players = {}
    for player, list in pairs(s.reserves) do
        if not (list[1] and list[1].source == "fake") then
            table.insert(players, player)
        end
    end
    table.sort(players)
    for _, player in ipairs(players) do
        local entry = player .. "=" .. table.concat(ns.Session:GetReservedItemIDs(player, s), ",")
        if #head + #entry <= Comm.MAX_LEN then
            if length + #entry + 1 > Comm.MAX_LEN then
                table.insert(chunks, table.concat(chunk, ";"))
                chunk, length = {}, #head
            end
            table.insert(chunk, entry)
            length = length + #entry + 1
        end
    end
    if #chunk > 0 then
        table.insert(chunks, table.concat(chunk, ";"))
    end
    return chunks
end

local heard = {} -- [sid] = { version, time }: zuletzt im Kanal gehörte Version (Unterdrückung)

local function recentlyHeard(sid, version)
    local entry = heard[sid]
    return entry ~= nil and entry.version >= version and GetTime() - entry.time < SUPPRESS_WINDOW
end

local function sendSessionFull(s)
    local chunks = buildChunks(s)
    local version = s.version or 0
    Comm:SendGuild("GR", s.id, version, s.leader, s.instanceKey or "", Comm.Sanitize(s.instanceName),
        s.maxReserves or 1, s.allowDuplicates and 1 or 0, s.locked and 1 or 0, s.deadline or 0,
        Comm.Sanitize(s.name), s.updatedAt or 0, ns.Session:KilledToString(s))
    -- Hard Reserves (erstes Stück leert beim Empfänger)
    local hrChunks, hrChunk, hrLength = {}, {}, 60
    for _, entry in ipairs(ns.Session:HardReservesToList(s)) do
        if hrLength + #entry + 1 > Comm.MAX_LEN then
            table.insert(hrChunks, table.concat(hrChunk, ";"))
            hrChunk, hrLength = {}, 60
        end
        table.insert(hrChunk, entry)
        hrLength = hrLength + #entry + 1
    end
    if #hrChunk > 0 then
        table.insert(hrChunks, table.concat(hrChunk, ";"))
    end
    for i, chunk in ipairs(hrChunks) do
        Comm:SendGuild("GH", s.id, version, i == 1 and 1 or 0, chunk)
    end
    Comm:SendGuild("GF", s.id, version, #chunks)
    for _, chunk in ipairs(chunks) do
        Comm:SendGuild("GP", s.id, version, chunk)
    end
    heard[s.id] = { version = version, time = GetTime() }
    ns.Debug("Guild", "Sitzung verteilt", s.id, "Version", version, #chunks, "Stücke")
end

local function sendTombstone(sid, tombstone)
    Comm:SendGuild("GD", sid, tombstone.version or 0, tombstone.leader or "")
end

-- Raidlead: veröffentlichte Sitzungen verteilen -----------------------------------------------
local publishScheduled = {}
local lastPublished = {} -- [sid] = GetTime()

local function schedulePublish(s, delay)
    if publishScheduled[s.id] then return end
    publishScheduled[s.id] = true
    C_Timer.After(delay or PUBLISH_DELAY, function()
        publishScheduled[s.id] = nil
        local current = ownSession(s.id)
        if current and current.published and enabled() then
            sendSessionFull(current)
            lastPublished[s.id] = GetTime()
        end
    end)
end

function GuildSync:SetPublished(s, published)
    if not ns.Session:IsOwnSession(s) then return end
    s.published = published and true or false
    ns.Session:Touch(s) -- neue Version: wird verteilt bzw. dient als Version der Löschmarke
    if not s.published and enabled() then
        sendTombstone(s.id, { version = s.version, leader = s.leader })
    end
    ns.Debug("Guild", "Veröffentlicht", s.id, s.published)
    ns:Fire("SESSION_CHANGED")
end

ns:On("OWN_SESSION_CHANGED", function(s)
    if s.published then
        schedulePublish(s)
    end
end)

ns:On("OWN_SESSION_DELETED", function(s)
    if s.published and enabled() then
        sendTombstone(s.id, { version = (s.version or 0) + 1, leader = s.leader })
    end
end)

-- Anzahl der über die Gilde eingegangenen Anmeldungen einer eigenen Sitzung
function GuildSync:CountGuildSignups(s)
    local count = 0
    for _, list in pairs(s.reserves) do
        if list[1] and list[1].source == "guild" then
            count = count + 1
        end
    end
    return count
end

-- Raider: Anmeldungen ------------------------------------------------------------------------
local lastSent = {} -- [sid] = GetTime() (bewusst nicht gespeichert: GetTime beginnt nach Neustart bei 0)

local function trySend(sid)
    local signup = signups()[sid]
    local copy = copies()[sid]
    if not signup or signup.status ~= "pending" or not copy or copy.deleted or not enabled() then return end
    if not GuildSync:IsOnline(copy.leader) then return end
    if lastSent[sid] and GetTime() - lastSent[sid] < RESEND_AFTER then return end
    lastSent[sid] = GetTime()
    Comm:SendWhisper(copy.leader, "GS", sid, signup.signedAt, table.concat(signup.items, ","))
    ns.Debug("Guild", "Anmeldung gesendet", sid, copy.leader)
end

-- Ausstehende Anmeldungen nachreichen (optional nur für einen Raidlead), leicht verzögert
local function sendPending(leader)
    for sid, signup in pairs(signups()) do
        local copy = copies()[sid]
        if signup.status == "pending" and copy and (not leader or copy.leader == leader) then
            C_Timer.After(1 + math.random() * 2, function() trySend(sid) end)
        end
    end
end

-- Art der Sitzung aus Sicht des Spielers: "own", "group" oder "guild"
function Signup:Kind(s)
    if not s then return nil end
    if ns.Session:IsOwnSession(s) then return "own" end
    if s == ns.Session:GetRemote() and s == ns.Session:Get() then return "group" end
    return "guild"
end

-- Eigene gewünschte Items in der Sitzung s (eigene Anmeldung oder bestätigter Stand)
function Signup:GetOwn(s)
    local kind = self:Kind(s)
    if kind == "group" then
        return ns.Comm:GetOwnReserves()
    elseif kind == "guild" then
        local signup = signups()[s.id]
        if signup and signup.status ~= "rejected" then
            return CopyTable(signup.items)
        end
    end
    return ns.Session:GetReservedItemIDs(me(), s)
end

-- Status der eigenen Anmeldung: "confirmed", "pending" oder "rejected" (+ Grund)
function Signup:GetStatus(s)
    local kind = self:Kind(s)
    if kind == "group" then
        return ns.Comm:IsRequestPending() and "pending" or "confirmed"
    elseif kind == "guild" then
        local signup = signups()[s.id]
        if signup then
            return signup.status, signup.reason
        end
    end
    return "confirmed"
end

function Signup:Submit(s, itemIDs)
    local kind = self:Kind(s)
    if kind == "own" then
        return ns.Session:SetPlayerReserves(me(), itemIDs, "ingame", s)
    elseif kind == "group" then
        return ns.Comm:SubmitOwnReserves(itemIDs)
    end
    if not enabled() then
        return false, "Gilden-Synchronisation ist aus"
    end
    local ok, err = ns.Session:ValidateReserves(itemIDs, me(), s)
    if not ok then return false, err end
    signups()[s.id] = { items = CopyTable(itemIDs), signedAt = GetServerTime(), status = "pending" }
    lastSent[s.id] = nil
    trySend(s.id)
    GuildSync:BroadcastOwnSignup(s.id) -- andere reichen sie weiter, falls der Raidlead gerade offline ist
    ns:Fire("SESSION_CHANGED")
    return true
end

-- Empfang ----------------------------------------------------------------------------------------

local function markSeen(sender)
    lastSeen[sender] = GetTime()
end

-- Regeln einer veröffentlichten Sitzung
Comm:RegisterHandler("GR", function(sender, f)
    if not enabled() then return end
    markSeen(sender)
    local sid, version, leader = f[3], tonumber(f[4]) or 0, f[5]
    if not sid or not leader or leader == "" then return end
    heard[sid] = { version = version, time = GetTime() }

    if leader == me() then
        -- Eine Kopie meiner eigenen Sitzung kommt zurück
        local own = ownSession(sid)
        if not own or not own.published then
            -- gelöscht oder zurückgezogen: Löschmarke mit höherer Version verteilen
            sendTombstone(sid, { version = version + 1, leader = leader })
        elseif version > (own.version or 0) then
            -- meine Version ist zurückgefallen (z. B. Absturz ohne Speichern): überholen und neu verteilen.
            -- Nur bei echt neuerer Version – eine Weitergabe meines aktuellen Stands ist normal.
            own.version = version
            ns.Session:Touch(own)
        end
        return
    end

    local copy = copies()[sid]
    if copy and (copy.version or 0) >= version then return end -- gleich alt oder älter (auch Löschmarken)
    copy = { id = sid, reserves = {}, guildCopy = true }
    copy.version = version
    copy.leader = leader
    copy.instanceKey = f[6] ~= "" and f[6] or nil
    copy.instanceName = f[7] ~= "" and f[7] or nil
    copy.maxReserves = tonumber(f[8]) or 1
    copy.allowDuplicates = f[9] == "1"
    copy.locked = f[10] == "1"
    copy.deadline = tonumber(f[11]) ~= 0 and tonumber(f[11]) or nil
    copy.name = f[12] ~= "" and f[12] or nil
    copy.updatedAt = tonumber(f[13]) or GetServerTime()
    copy.killed = ns.Session:KilledFromString(f[14])
    copy.receivedAt = GetServerTime()
    copy.complete = false -- erst mit allen GP-Stücken vollständig
    copies()[sid] = copy
    ns.Debug("Guild", "Sitzung empfangen", sid, "Version", version, "von", sender)
    if sender == leader then
        sendPending(leader) -- der Raidlead ist online
        GuildSync:RelayTo(leader) -- und bekommt weitergegebene Anmeldungen
    end
    ns:Fire("SESSION_CHANGED")
end)

-- Hard Reserves einer Kopie (gleiche Version; wiederholte Weitergaben liefern dieselben Daten)
Comm:RegisterHandler("GH", function(sender, f)
    if not enabled() then return end
    markSeen(sender)
    local copy = copies()[f[3] or ""]
    if not copy or copy.deleted or copy.version ~= tonumber(f[4]) then return end
    if f[5] == "1" then
        copy.hardReserves = nil
    end
    ns.Session:ApplyHardReserveEntries(copy, f[6])
    ns:Fire("SESSION_CHANGED")
end)

-- Voller Stand folgt: nur annehmen, wenn die eigene Kopie dieser Version noch unvollständig ist
-- (sonst könnte ein Mitglied mit lückenhaftem Stand eine vollständige Kopie leeren)
Comm:RegisterHandler("GF", function(sender, f)
    if not enabled() then return end
    markSeen(sender)
    local copy = copies()[f[3] or ""]
    if not copy or copy.deleted or copy.version ~= tonumber(f[4]) then return end
    if copy.complete and sender ~= copy.leader then return end
    wipe(copy.reserves)
    copy.expected = tonumber(f[5]) or 0
    copy.received = 0
    copy.complete = copy.expected == 0
    if copy.complete then
        syncOwnFromCopy(f[3])
    end
end)

Comm:RegisterHandler("GP", function(sender, f)
    if not enabled() then return end
    markSeen(sender)
    local copy = copies()[f[3] or ""]
    if not copy or copy.deleted or copy.complete or not copy.expected or copy.version ~= tonumber(f[4]) then
        return
    end
    for entry in (f[5] or ""):gmatch("[^;]+") do
        local player, ids = entry:match("^(.-)=(.*)$")
        if player then
            local list = {}
            for i, itemID in ipairs(parseItemIDs(ids)) do
                list[i] = { itemID = itemID, source = "guild" }
            end
            copy.reserves[player] = #list > 0 and list or nil
        end
    end
    copy.received = (copy.received or 0) + 1
    copy.complete = copy.received >= copy.expected
    if copy.complete then
        syncOwnFromCopy(f[3])
    end
    ns:Fire("SESSION_CHANGED")
end)

-- Löschmarke: vom Raidlead oder weitergegeben (Version entscheidet)
Comm:RegisterHandler("GD", function(sender, f)
    if not enabled() then return end
    markSeen(sender)
    local sid, version, leader = f[3], tonumber(f[4]) or 0, f[5]
    if not sid or leader == me() then return end
    local copy = copies()[sid]
    if copy and (copy.version or 0) >= version then return end
    if not copy and sender ~= leader then return end -- fremde Löschmarken nur für bekannte Sitzungen
    copies()[sid] = { id = sid, deleted = true, version = version, leader = leader, deletedAt = GetServerTime() }
    signups()[sid] = nil
    ns.Debug("Guild", "Sitzung zurückgezogen", sid)
    ns:Fire("SESSION_CHANGED")
end)

-- Login-Abfrage eines Mitglieds
Comm:RegisterHandler("GQ", function(sender)
    if not enabled() then return end
    markSeen(sender)
    -- Raidleiter-Einstellung weitergeben (zufällig verzögert, nur wenn sie nicht gerade jemand gesendet hat)
    local cfg = guildConfig()
    if cfg then
        C_Timer.After(REPLY_DELAY_MIN + math.random() * (REPLY_DELAY_MAX - REPLY_DELAY_MIN), function()
            if GetTime() - heardConfig > SUPPRESS_WINDOW then
                sendConfig(cfg)
            end
        end)
    end
    -- eigene veröffentlichte Sitzungen (gedrosselt, falls viele Mitglieder kurz hintereinander einloggen)
    for _, s in pairs(ns.char.sessions or {}) do
        if s.published and not (lastPublished[s.id] and GetTime() - lastPublished[s.id] < REPUBLISH_MIN) then
            schedulePublish(s, 0.5 + math.random())
        end
    end
    -- Fragt ein Raidlead nach, für den wir Anmeldungen anderer bereithalten: weiterreichen
    for sid, bySession in pairs(ns.char.relaySignups or {}) do
        local copy = copies()[sid]
        if copy and copy.leader == sender and next(bySession) then
            GuildSync:RelayTo(sender)
            break
        end
    end
    -- Weitergabe von Kopien: nicht während eines Raids (Sende-Queue frei halten)
    if (IsInGroup and IsInGroup()) or (IsInInstance and IsInInstance()) then return end
    for sid, copy in pairs(copies()) do
        if copy.deleted or copy.complete then
            local delay = REPLY_DELAY_MIN + math.random() * (REPLY_DELAY_MAX - REPLY_DELAY_MIN)
            C_Timer.After(delay, function()
                local current = copies()[sid]
                if not current or recentlyHeard(sid, current.version or 0) then return end
                if current.deleted then
                    sendTombstone(sid, current)
                    heard[sid] = { version = current.version or 0, time = GetTime() }
                elseif current.complete then
                    sendSessionFull(current)
                end
            end)
        end
    end
end)

-- Raidlead: eine Anmeldung verarbeiten (direkt per Whisper oder über die Gilde weitergegeben).
-- Liefert "a" (angenommen/unverändert), "o" (überholt durch neuere Auswahl) oder "x" (abgelehnt) + Text.
local function processSignup(player, sid, signedAt, ids)
    if not enabled() then
        return "x", "Gilden-Synchronisation beim Raidlead ist aus"
    end
    local s = ownSession(sid)
    if not s or not s.published then
        return "x", "Sitzung nicht (mehr) veröffentlicht"
    end
    local now = GetServerTime()
    -- Abgabezeit plausibel halten: nicht in der Zukunft, nicht vor Anlage der Sitzung
    local effective = math.max(math.min(signedAt, now), s.createdAt or 0)
    if s.deadline and now > s.deadline + LATE_WINDOW then
        return "x", "Anmeldung zu spät übertragen"
    end
    -- Eine neuere Auswahl dieses Spielers (z. B. in der Gruppe) hat Vorrang
    local changedAt = s.changedAt and s.changedAt[player]
    if changedAt and changedAt > effective then
        return "o"
    end
    -- Unveränderte Liste: nur bestätigen, nicht neu verteilen
    if sameItems(ns.Session:GetReservedItemIDs(player, s), ids) and (#ids > 0 or s.reserves[player] == nil) then
        return "a"
    end
    local ok, err = ns.Session:SetPlayerReserves(player, ids, "guild", s, effective)
    if not ok then
        return "x", err
    end
    ns.Debug("Guild", "Anmeldung angenommen", sid, player)
    return "a"
end

-- Ergebnis an die Gilde melden: Mitglieder verwerfen die weitergegebene Anmeldung,
-- der Raider (falls online) sieht den Status
local function announceResult(sid, player, signedAt, status, text)
    Comm:SendGuild("GC", sid, player, signedAt, status, Comm.Sanitize(text or ""))
end

-- Anmeldung eines Raiders (Whisper an den Raidlead)
Comm:RegisterHandler("GS", function(sender, f)
    markSeen(sender)
    local sid, signedAt = f[3] or "", tonumber(f[4]) or GetServerTime()
    local status, text = processSignup(sender, sid, signedAt, parseItemIDs(f[5]))
    if status == "x" then
        Comm:SendWhisper(sender, "GX", sid, signedAt, Comm.Sanitize(text))
    else
        Comm:SendWhisper(sender, "GA", sid, signedAt, status == "o" and 1 or 0)
    end
    if enabled() then
        announceResult(sid, sender, signedAt, status, text)
    end
end)

-- Weitergabe von Anmeldungen über andere Gildenmitglieder ----------------------------------
-- db.relaySignups[sid][Spieler] = { items, signedAt }: fremde, noch offene Anmeldungen, die dieses Addon
-- an den Raidlead weiterreicht, sobald er online ist (auch wenn der Raider selbst offline ist).
local function relays()
    ns.char.relaySignups = ns.char.relaySignups or {}
    return ns.char.relaySignups
end

local heardRelay = {} -- ["sid|Spieler|signedAt"] = GetTime(): im Kanal gehört → nicht doppelt senden

local function relayKey(sid, player, signedAt)
    return sid .. "|" .. player .. "|" .. tostring(signedAt)
end

local function storeRelay(sid, player, signedAt, ids)
    local copy = copies()[sid]
    if not copy or copy.deleted or player == me() then return end
    local bySession = relays()[sid] or {}
    local existing = bySession[player]
    if existing and existing.signedAt >= signedAt then return end -- pro Spieler gilt die neueste
    bySession[player] = { items = ids, signedAt = signedAt }
    relays()[sid] = bySession
end

local function broadcastRelay(sid, player, entry)
    local key = relayKey(sid, player, entry.signedAt)
    if heardRelay[key] and GetTime() - heardRelay[key] < SUPPRESS_WINDOW then return end
    heardRelay[key] = GetTime()
    Comm:SendGuild("GU", sid, player, entry.signedAt, table.concat(entry.items, ","))
end

-- Raidlead ist online: gespeicherte Anmeldungen für seine Sitzungen weiterreichen (zufällig verzögert,
-- damit nicht alle gleichzeitig senden; wer die Anmeldung schon im Kanal gehört hat, schweigt)
local relayScheduled = {}

function GuildSync:RelayTo(leader)
    if relayScheduled[leader] or not enabled() then return end
    relayScheduled[leader] = true
    C_Timer.After(2 + math.random() * 6, function()
        relayScheduled[leader] = nil
        if not GuildSync:IsOnline(leader) then return end
        for sid, bySession in pairs(relays()) do
            local copy = copies()[sid]
            if copy and not copy.deleted and copy.leader == leader then
                for player, entry in pairs(bySession) do
                    broadcastRelay(sid, player, entry)
                end
            end
        end
    end)
end

-- Anmeldung in der Gilde: Mitglieder speichern sie zum Weiterreichen, der Raidlead verarbeitet sie
Comm:RegisterHandler("GU", function(sender, f)
    if not enabled() then return end
    markSeen(sender)
    local sid, player, signedAt = f[3] or "", f[4] or "", tonumber(f[5]) or 0
    if player == "" then return end
    local ids = parseItemIDs(f[6])
    heardRelay[relayKey(sid, player, signedAt)] = GetTime()
    if ownSession(sid) then
        -- Weitergegebene Anmeldungen werden ohne Echtheitsprüfung übernommen (bewusste Entscheidung)
        local status, text = processSignup(player, sid, signedAt, ids)
        announceResult(sid, player, signedAt, status, text)
    else
        storeRelay(sid, player, signedAt, ids)
    end
end)

-- Ergebnis des Raidleads: Weitergabe erledigt; eigene Anmeldung aktualisieren
Comm:RegisterHandler("GC", function(sender, f)
    if not enabled() then return end
    markSeen(sender)
    local sid, player, signedAt, status = f[3] or "", f[4] or "", tonumber(f[5]) or 0, f[6]
    local copy = copies()[sid]
    if not copy or copy.leader ~= sender then return end
    local bySession = relays()[sid]
    if bySession and bySession[player] and bySession[player].signedAt <= signedAt then
        bySession[player] = nil
    end
    if player == me() then
        local signup = signups()[sid]
        if signup and signup.signedAt == signedAt then
            if status == "o" then
                signups()[sid] = nil
            elseif status == "x" then
                signup.status = "rejected"
                signup.reason = f[7]
            else
                signup.status = "confirmed"
                signup.reason = nil
            end
            ns:Fire("SESSION_CHANGED")
        end
    end
end)

-- Eigene Anmeldung zusätzlich in der Gilde verteilen, damit andere sie weiterreichen können
function GuildSync:BroadcastOwnSignup(sid)
    local signup = signups()[sid]
    if signup and signup.status == "pending" and enabled() then
        broadcastRelay(sid, me(), signup)
    end
end

-- Anmeldung verarbeitet
Comm:RegisterHandler("GA", function(sender, f)
    local copy = copies()[f[3] or ""]
    local signup = signups()[f[3] or ""]
    if not copy or not signup or copy.leader ~= sender or signup.signedAt ~= tonumber(f[4]) then return end
    if f[5] == "1" then
        signups()[copy.id] = nil -- es gibt eine neuere Auswahl (z. B. aus der Gruppe): Anmeldung überholt
    else
        signup.status = "confirmed"
        signup.reason = nil
    end
    ns.Debug("Guild", "Anmeldung bestätigt", copy.id, f[5])
    ns:Fire("SESSION_CHANGED")
end)

-- Anmeldung abgelehnt (nur, wenn sie zur aktuellen Anmeldung gehört)
Comm:RegisterHandler("GX", function(sender, f)
    local copy = copies()[f[3] or ""]
    local signup = signups()[f[3] or ""]
    if not copy or not signup or copy.leader ~= sender or signup.signedAt ~= tonumber(f[4]) then return end
    signup.status = "rejected"
    signup.reason = f[5]
    ns.Print("Anmeldung für „" .. (copy.name or "?") .. "“ abgelehnt: " .. (f[5] or "?"))
    ns:Fire("SESSION_CHANGED")
end)

-- Lebenszyklus -------------------------------------------------------------------------------------

-- Alte Kopien und Löschmarken entfernen (am vom Raidlead gemeldeten Stand gemessen)
local function prune()
    local now = GetServerTime()
    for sid, copy in pairs(copies()) do
        local expired
        if copy.deleted then
            expired = now > (copy.deletedAt or 0) + KEEP_TOMBSTONE
        elseif copy.deadline then
            expired = now > copy.deadline + KEEP_AFTER_DEADLINE
        else
            expired = now > (copy.updatedAt or copy.receivedAt or 0) + KEEP_WITHOUT_DEADLINE
        end
        if expired then
            copies()[sid] = nil
        end
    end
    for sid in pairs(signups()) do
        local copy = copies()[sid]
        if not copy or copy.deleted then
            signups()[sid] = nil
        end
    end
    -- Weitergaben: nur für bekannte Sitzungen und nicht über die Nachfrist hinaus
    for sid, bySession in pairs(relays()) do
        local copy = copies()[sid]
        if not copy or copy.deleted or (copy.deadline and now > copy.deadline + LATE_WINDOW) or not next(bySession) then
            relays()[sid] = nil
        end
    end
end

-- Erste Synchronisation, sobald die Gildenzugehörigkeit bekannt ist (bei PLAYER_LOGIN oft noch nicht)
local initialSyncDone = false

local function initialSync()
    if initialSyncDone or not enabled() then return end
    initialSyncDone = true
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    end
    C_Timer.After(2 + math.random() * 3, function()
        if not enabled() then return end
        Comm:SendGuild("GQ")
        for _, s in pairs(ns.char.sessions or {}) do
            if s.published then
                schedulePublish(s, 1)
            end
        end
        -- eigene offene Anmeldungen erneut in die Gilde geben (andere reichen sie weiter)
        for sid in pairs(signups()) do
            GuildSync:BroadcastOwnSignup(sid)
        end
    end)
    ns:Fire("SESSION_CHANGED")
end

function ns:GUILD_ROSTER_UPDATE()
    refreshRoster()
    initialSync()
    sendPending()
    -- ist ein Raidlead online, für den wir Anmeldungen anderer bereithalten? (RelayTo ist entprellt)
    for sid, bySession in pairs(relays()) do
        local copy = copies()[sid]
        if copy and next(bySession) and GuildSync:IsOnline(copy.leader) then
            GuildSync:RelayTo(copy.leader)
        end
    end
end

function ns:PLAYER_GUILD_UPDATE()
    initialSync()
    ns:Fire("SESSION_CHANGED")
end

ns:On("LOGIN", function()
    prune()
    C_Timer.After(3, initialSync)
end)

-- Gruppenbeitritt (Raidstart): spätestens jetzt ausstehende Anmeldungen senden
ns:On("ROSTER_CHANGED", function()
    sendPending()
end)

-- Gilden-Synchronisation in den Optionen eingeschaltet
ns:On("SESSION_CHANGED", function()
    if not initialSyncDone then
        initialSync()
    end
end)

ns:RegisterEvent("GUILD_ROSTER_UPDATE")
ns:RegisterEvent("PLAYER_GUILD_UPDATE")
