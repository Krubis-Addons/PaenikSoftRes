-- Würfelrunden: Der Raidlead startet eine Runde für ein Item, Raider wählen eine Kategorie
-- (SR / Mainspec / Secondspec / Transmog / Passen) und würfeln mit RandomRoll(1, 100/50/25).
-- Der Raidlead liest die Würfe aus CHAT_MSG_SYSTEM und beendet die Runde.
--
-- Beschränkte Runde (restricted): nur bestimmte Spieler dürfen würfeln, alle in derselben Kategorie.
--   - SR-Runde: Das Item hat Soft Reserves → nur SR-Inhaber, Kategorie "SR".
--   - Nachwurf: Gleichstand an der Spitze → nur die Spieler im Gleichstand, deren Kategorie.
-- Offene Runde: sonst gilt Mainspec > Secondspec > Transmog, jeweils höchster Wurf.
-- Passen alle anwesenden Berechtigten (oder läuft die Zeit ohne Wurf ab), wird daraus ein freier Wurf.
-- Die Kategorie ergibt sich aus dem Würfelbereich: MS /roll (1-100), OS /roll 50, Transmog /roll 25,
-- SR /roll (1-100). So können auch Spieler ohne Addon mitwürfeln.
--
-- Nachrichten (über Comm, Präfix PSR):
--   RS^rid^itemID^beschränkt(1/0)^Name;Name^Kategorie^Sekunden^Grund   Lead → Gruppe: Runde gestartet
--                                                      (Sekunden 0 = Ende durch Raidlead, Grund = freier Wurf)
--   RD^rid^PASS                                        Raider → Lead (Whisper): Spieler passt
--   RE^rid^Gewinner^Wurf^Kategorie^lootKey             Lead → Gruppe: Ergebnis (Gewinner leer = keiner/TIE)
--   RC^rid                                             Lead → Gruppe: Runde abgebrochen
local _, ns = ...

local Rolls = {}
ns.Rolls = Rolls

local RANK = { SR = 4, MS = 3, OS = 2, TM = 1 }
-- Würfelbereich je Kategorie: damit ist die Kategorie auch ohne Addon am Wurf erkennbar
local RANGE = { SR = 100, MS = 100, OS = 50, TM = 25 }
local OPEN_CATEGORY_BY_RANGE = { [100] = "MS", [50] = "OS", [25] = "TM" }
Rolls.RANGE = RANGE

-- Wählbare Würfelzeiten in Sekunden (0 = Raidlead beendet)
Rolls.DURATIONS = { 0, 15, 20, 30, 45, 60, 90, 120 }

function Rolls.DurationText(seconds)
    return seconds == 0 and "Manuell (Raidlead beendet)" or (seconds .. " Sekunden")
end

-- Chat-Befehl für eine Kategorie, z. B. "/roll 50"
function Rolls.RollCommand(category)
    local max = RANGE[category] or 100
    return max == 100 and "/roll" or ("/roll " .. max)
end
Rolls.LABEL = {
    SR = "Soft Reserve",
    MS = "Mainspec",
    OS = "Secondspec",
    TM = "Transmog",
    PASS = "Passen",
    NOSR = "nicht berechtigt",
}

local CHAT_LIMIT = 255

local leadRound   -- nur beim Raidlead: { id, itemID, link, restricted, category, holders, rolls, startedAt, ended, result }
local activeRound -- bei allen: { id, itemID, restricted, category, holders, leader, declared, result }

local function changed()
    ns:Fire("ROLL_CHANGED")
end

local function itemLink(itemID)
    local _, link = C_Item.GetItemInfo(itemID)
    return link or ("item:" .. itemID)
end

-- Muster für die lokalisierte Würfelnachricht, z. B.
-- enUS "%s rolls %d (%d-%d)", deDE "%1$s würfelt. Ergebnis: %2$d (%3$d-%4$d)"
local rollPattern
local function getRollPattern()
    if rollPattern then return rollPattern end
    local fmt = RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)"
    local p = fmt:gsub("%%%d%$", "%%")                      -- "%1$s" -> "%s"
    p = p:gsub("([%(%)%.%[%]%*%+%-%?%^%$])", "%%%1")        -- Sonderzeichen maskieren
    p = p:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
    rollPattern = "^" .. p .. "$"
    return rollPattern
end

local function holderSet(itemID)
    local set = {}
    for player in pairs(ns.Session:GetReservesForItem(itemID)) do
        set[player] = true
    end
    return set
end

-- Abfragen ---------------------------------------------------------------------------

function Rolls:GetActiveRound()
    return activeRound
end

function Rolls:GetLeadRound()
    return leadRound
end

-- Vergaben für ein Item einer bestimmten Leiche (aus dem Verlauf der Sitzung)
function Rolls:GetAwards(lootKey)
    local awards = {}
    local s = ns.Session:Get()
    if not lootKey or not s or not s.history then return awards end
    for _, entry in ipairs(s.history) do
        if entry.lootKey == lootKey then
            table.insert(awards, entry)
        end
    end
    return awards
end

-- Läuft gerade eine Runde für dieses Item (dieser Leiche)?
function Rolls:IsRolling(itemID, lootKey)
    local round = activeRound
    if not round or round.result or round.itemID ~= itemID then return false end
    return round.lootKey == nil or lootKey == nil or round.lootKey == lootKey
end

-- Sortierte Liste der Würfe: gültige zuerst (Kategorie, dann Wurf), danach der Rest.
function Rolls:GetStandings()
    local list = {}
    if not leadRound then return list end
    for player, entry in pairs(leadRound.rolls) do
        table.insert(list, {
            player = player,
            category = entry.category,
            roll = entry.roll,
            max = entry.max,
            rank = (entry.roll and RANK[entry.category]) or 0,
        })
    end
    table.sort(list, function(a, b)
        if a.rank ~= b.rank then return a.rank > b.rank end
        if (a.roll or 0) ~= (b.roll or 0) then return (a.roll or 0) > (b.roll or 0) end
        return a.player < b.player
    end)
    return list
end

-- Gewinner bestimmen; bei Gleichstand an der Spitze: nil, Liste der Spieler im Gleichstand
function Rolls:GetWinner()
    local standings = self:GetStandings()
    local first = standings[1]
    if not first or first.rank == 0 then
        return nil, nil
    end
    local tied = { first.player }
    for i = 2, #standings do
        local other = standings[i]
        if other.rank == first.rank and other.roll == first.roll then
            table.insert(tied, other.player)
        else
            break
        end
    end
    if #tied > 1 then
        return nil, tied
    end
    return first, nil
end

-- Raidlead: Runde starten / beenden ----------------------------------------------------

-- Kurznamen für die Chat-Ansage, gekürzt auf das verbleibende Zeichenbudget
local function namesForChat(players, budget)
    local names, length = {}, 0
    table.sort(players)
    for i, player in ipairs(players) do
        local short = ns.UI.ShortName(player)
        if length + #short + 2 > budget - 12 then
            table.insert(names, "… (+" .. (#players - i + 1) .. ")")
            break
        end
        table.insert(names, short)
        length = length + #short + 2
    end
    return table.concat(names, ", ")
end

local function stopTimer()
    if leadRound and leadRound.timer then
        leadRound.timer:Cancel()
        leadRound.timer = nil
    end
end

-- Berechtigte, die gerade in der Gruppe sind (ohne Gruppe: nur ich)
local function presentPlayers(holders)
    local present = {}
    for player in pairs(holders) do
        if ns.UnitForName(player) then
            present[player] = true
        end
    end
    return present
end

-- restrictTo (optional): nur diese Spieler, alle mit Kategorie category (Nachwurf)
-- freeReason (optional): offene Runde erzwingen, Grund steht in der Ansage
-- lootKey (optional): Leiche + Item ("GUID:itemID"), damit das Loot-Panel den Gewinner zuordnen kann
function Rolls:Start(itemID, link, restrictTo, category, freeReason, lootKey)
    if not ns.Roles:IsDistributor() then
        ns.Print("Nur der Verteiler kann eine Würfelrunde starten (Raidlead bzw. bei Plündermeister-Verteilung der "
            .. "Plündermeister).")
        return
    end
    if leadRound and not leadRound.ended then
        ns.Print("Es läuft bereits eine Würfelrunde. Erst beenden oder abbrechen.")
        changed() -- Leitfenster wieder zeigen, falls es geschlossen wurde
        return
    end
    leadRound = nil -- beendete Runde verwerfen
    link = link or itemLink(itemID)

    local holders, restricted = {}, false
    if restrictTo then
        restricted = true
        for _, player in ipairs(restrictTo) do
            holders[player] = true
        end
    elseif not freeReason then
        local allHolders = holderSet(itemID)
        if next(allHolders) then
            holders = presentPlayers(allHolders)
            if next(holders) then
                restricted, category = true, "SR"
            else
                freeReason = "kein SR-Inhaber anwesend"
            end
        end
    end
    if not restricted then
        category = nil
    end

    local duration = ns.db.rollDuration or 0
    leadRound = {
        id = GetServerTime() .. "-" .. math.random(100, 999),
        itemID = itemID,
        link = link,
        restricted = restricted,
        category = category,
        holders = holders,
        freeReason = freeReason,
        lootKey = lootKey,
        rolls = {},
        startedAt = GetTime(),
        duration = duration,
        manual = self:IsManualWinner(), -- Gewinner wählt der Raidlead (siehe ChooseWinner)
    }
    if duration > 0 then
        leadRound.endsAt = GetTime() + duration
        local id = leadRound.id
        leadRound.timer = C_Timer.NewTimer(duration, function()
            if leadRound and leadRound.id == id and not leadRound.ended then
                leadRound.timer = nil
                Rolls:End(true)
            end
        end)
    end

    -- Berechtigte mitsenden (Raider haben evtl. einen veralteten Stand), Nachricht < 255 Byte
    local sendNames, length = {}, 0
    for player in pairs(holders) do
        if length + #player + 1 < 150 then
            table.insert(sendNames, player)
            length = length + #player + 1
        end
    end
    ns.Comm:SendGroup("RS", leadRound.id, itemID, restricted and 1 or 0, table.concat(sendNames, ";"),
        category or "", duration, ns.Comm.Sanitize(freeReason or ""))
    -- Raider ohne dieses Addon, aber mit Gargul: Gargul-Würfelfenster öffnen
    ns.GargulCompat:SendStart(leadRound, duration)

    -- Ansage: wer darf würfeln, wie lange
    local players = {}
    for player in pairs(holders) do
        table.insert(players, player)
    end
    local timeText = duration > 0 and (" – " .. duration .. " s") or ""
    local openText = " – MS /roll, OS /roll 50, Transmog /roll 25" .. timeText
    if restricted then
        local suffix = " (" .. Rolls.RollCommand(category) .. timeText .. ")"
        local text = restrictTo and ("Nachwurf (" .. Rolls.LABEL[category] .. ") auf " .. link .. " für: ")
            or ("Würfeln auf " .. link .. " – nur SR: ")
        ns.SendGroupChat(text .. namesForChat(players, CHAT_LIMIT - #text - #suffix) .. suffix)
    elseif freeReason then
        ns.SendGroupChat("Freier Wurf auf " .. link .. " (" .. freeReason .. ")" .. openText)
    else
        ns.SendGroupChat("Würfeln auf " .. link .. openText)
    end

    activeRound = {
        id = leadRound.id,
        itemID = itemID,
        restricted = restricted,
        category = category,
        holders = holders,
        freeReason = freeReason,
        lootKey = lootKey,
        leader = ns.FullName("player"),
        endsAt = leadRound.endsAt,
    }
    ns.Debug("Rolls", "Runde gestartet", leadRound.id, itemID, "beschränkt:", restricted, category,
        "Zeit:", duration, freeReason or "")
    changed()
end

-- Beschränkte Runde ohne Interessenten → offene Runde für dasselbe Item
local function switchToFreeForAll(reason)
    local itemID, link, lootKey = leadRound.itemID, leadRound.link, leadRound.lootKey
    stopTimer()
    ns.Debug("Rolls", "Wechsel zu freiem Wurf:", reason)
    leadRound = nil
    activeRound = nil
    -- neue Runden-ID: ersetzt die alte Runde auch bei den Raidern
    Rolls:Start(itemID, link, nil, nil, reason, lootKey)
end

local function addHistory(itemID, winner, roll, category, lootKey)
    local s = ns.Session:Get()
    if not s then return end
    s.history = s.history or {}
    -- Erneut ausgewürfelt (gleiche Leiche, gleiches Item): das neue Ergebnis ersetzt das alte
    if lootKey then
        for i = #s.history, 1, -1 do
            if s.history[i].lootKey == lootKey then
                table.remove(s.history, i)
            end
        end
    end
    table.insert(s.history, {
        itemID = itemID,
        winner = winner,
        roll = roll,
        category = category,
        time = GetServerTime(),
        lootKey = lootKey,
    })
    -- Selbst gewonnen: Item von der eigenen Wunschliste nehmen
    if winner == ns.FullName("player") and ns.Wishlist:Has(itemID) then
        ns.Wishlist:Set(itemID, false)
        ns.Print(itemLink(itemID) .. " gewonnen – von der Wunschliste entfernt.")
    end
    ns:Fire("SESSION_CHANGED")
end

-- Gewinner manuell wählen (Einstellung db.manualWinner, beim Start der Runde übernommen):
-- „Beenden“ bzw. das Zeitfenster schließt nur die Würfe; der Raidlead wählt den Gewinner im Leitfenster
-- aus allen Würfelnden (Rolls:ChooseWinner). Auch während der Runde kann er direkt wählen.
function Rolls:IsManualWinner()
    return ns.db and ns.db.manualWinner == true
end

function Rolls:CanChooseWinner()
    return leadRound ~= nil and leadRound.manual == true and not leadRound.ended
end

function Rolls:IsChoosing()
    return leadRound ~= nil and leadRound.choosing == true and not leadRound.ended
end

local finish -- forward

-- byTimer: vom Zeitfenster beendet (nicht vom Raidlead)
function Rolls:End(byTimer)
    if not leadRound or leadRound.ended or leadRound.choosing then return end
    local winner, tied = self:GetWinner()
    if byTimer and leadRound.restricted and not winner and not tied then
        switchToFreeForAll("keine Würfe der Berechtigten")
        return
    end
    stopTimer()
    ns.GargulCompat:SendStop()
    if leadRound.manual and (winner or tied) then
        -- Würfe schließen, Raidlead wählt den Gewinner
        leadRound.choosing = true
        ns.SendGroupChat("Würfeln auf " .. leadRound.link .. " beendet – der Raidlead wählt den Gewinner.")
        ns.Debug("Rolls", "Runde geschlossen, Gewinner wird gewählt", leadRound.id)
        changed()
        return
    end
    finish(self, winner, tied)
end

-- Raidlead wählt den Gewinner (manuelle Runde): jeder mit einem Wurf ist wählbar
function Rolls:ChooseWinner(player)
    if not self:CanChooseWinner() then return false end
    local entry = leadRound.rolls[player]
    if not entry or not entry.roll then return false end
    if not leadRound.choosing then
        stopTimer()
        ns.GargulCompat:SendStop()
    end
    ns.Debug("Rolls", "Gewinner gewählt", leadRound.id, player)
    finish(self, { player = player, roll = entry.roll, category = entry.category }, nil, true)
    return true
end

-- Ergebnis verkünden, verteilen und speichern; chosen = vom Raidlead gewählt
function finish(self, winner, tied, chosen)
    local link = leadRound.link
    if winner then
        ns.SendGroupChat(string.format("Gewinner %s: %s (%s, %d)%s", link, ns.UI.ShortName(winner.player),
            Rolls.LABEL[winner.category] or winner.category, winner.roll, chosen and " – vom Raidlead gewählt" or ""))
        ns.Comm:SendGroup("RE", leadRound.id, winner.player, winner.roll, winner.category, leadRound.lootKey or "")
        addHistory(leadRound.itemID, winner.player, winner.roll, winner.category, leadRound.lootKey)
    elseif tied then
        local text = "Gleichstand bei " .. link .. ": "
        ns.SendGroupChat(text .. namesForChat(tied, CHAT_LIMIT - #text))
        ns.Comm:SendGroup("RE", leadRound.id, "", 0, "TIE")
    else
        ns.SendGroupChat("Niemand hat auf " .. link .. " gewürfelt.")
        ns.Comm:SendGroup("RE", leadRound.id, "", 0, "")
    end
    ns.Debug("Rolls", "Runde beendet", leadRound.id, winner and winner.player or (tied and "Gleichstand" or "niemand"))
    leadRound.ended = true
    leadRound.tied = tied
    leadRound.result = {
        winner = winner and winner.player,
        roll = winner and winner.roll,
        category = winner and winner.category or (tied and "TIE" or ""),
    }
    if activeRound and activeRound.id == leadRound.id then
        activeRound.result = leadRound.result
    end
    if tied then
        changed() -- Leitfenster bleibt offen für den Nachwurf
    else
        self:Dismiss() -- Runde erledigt: Fenster schließen sich
    end
end

-- Nach einem Gleichstand: Nachwurf nur für die Spieler im Gleichstand
function Rolls:Reroll()
    local round = leadRound
    if not round or not round.ended or not round.tied then return end
    local category = round.rolls[round.tied[1]].category
    self:Start(round.itemID, round.link, round.tied, category, nil, round.lootKey)
end

function Rolls:Cancel()
    if not leadRound then return end
    stopTimer()
    if not leadRound.ended then
        ns.GargulCompat:SendStop()
        ns.Comm:SendGroup("RC", leadRound.id)
        ns.SendGroupChat("Würfelrunde für " .. leadRound.link .. " abgebrochen.")
        ns.Debug("Rolls", "Runde abgebrochen", leadRound.id)
    end
    if activeRound and activeRound.id == leadRound.id then
        activeRound = nil
    end
    leadRound = nil
    changed()
end

-- Runde nach dem Ende aus der Anzeige entfernen
function Rolls:Dismiss()
    if leadRound and leadRound.ended then
        leadRound = nil
    end
    if activeRound and activeRound.result then
        activeRound = nil
    end
    changed()
end

-- Verteiler-Rolle verloren (Gruppenleitung abgegeben, anderer Plündermeister): eigene Runde verwerfen
ns:On("DISTRIBUTOR_CHANGED", function()
    if leadRound and not ns.Roles:IsDistributor() then
        ns.Print("Du verteilst den Loot nicht mehr – die Würfelrunde wurde verworfen.")
        stopTimer()
        ns.GargulCompat:SendStop()
        if activeRound and activeRound.id == leadRound.id then
            activeRound = nil
        end
        leadRound = nil
        changed()
    end
end)

-- Passen eines Spielers beim Raidlead eintragen (die übrigen Kategorien ergeben sich aus dem Würfelbereich)
local function applyPass(player)
    if not leadRound or leadRound.ended or leadRound.choosing then return end
    local entry = leadRound.rolls[player] or {}
    if entry.roll then return end -- schon gewürfelt: Passen zählt nicht mehr
    entry.category = "PASS"
    leadRound.rolls[player] = entry
    ns.Debug("Rolls", "Passt", player)

    -- Alle Berechtigten passen → freier Wurf
    if leadRound.restricted then
        for holder in pairs(leadRound.holders) do
            local other = leadRound.rolls[holder]
            if not other or other.category ~= "PASS" then
                changed()
                return
            end
        end
        switchToFreeForAll("alle Berechtigten passen")
        return
    end
    changed()
end

-- Raider (und Raidlead selbst): Kategorie wählen und würfeln -------------------------

function Rolls:Declare(category)
    local round = activeRound
    if not round or round.result or round.declared then return end
    round.declared = category
    if category == "PASS" then
        -- Passen kann der Raidlead nicht aus dem Chat lesen: per Nachricht melden
        if round.leader == ns.FullName("player") then
            applyPass(round.leader)
        else
            ns.Comm:SendWhisper(round.leader, "RD", round.id, "PASS")
        end
    else
        -- Die Kategorie ergibt sich beim Raidlead aus dem Würfelbereich (100/50/25)
        RandomRoll(1, RANGE[category] or 100)
    end
    changed()
end

-- Darf ich in dieser (beschränkten) Runde würfeln?
function Rolls:CanRollRestricted()
    local round = activeRound
    if not round or not round.restricted then return false end
    local me = ns.FullName("player")
    if round.holders[me] then return true end
    -- SR-Liste in RS kann gekürzt sein: eigene Reserve aus der Sitzung zählt auch
    return round.category == "SR" and ns.Session:GetReservesForItem(round.itemID)[me] ~= nil
end

-- Würfe aus dem Chat (nur beim Raidlead) ---------------------------------------------

function ns:CHAT_MSG_SYSTEM(text)
    -- nach „Beenden“ in einer manuellen Runde (Gewinner wird gewählt) zählen keine Würfe mehr
    if not leadRound or leadRound.ended or leadRound.choosing then return end
    if issecretvalue and issecretvalue(text) then
        if not leadRound.secretWarned then
            leadRound.secretWarned = true
            ns.Print("Würfe können gerade nicht gelesen werden (Kampfsperre).")
        end
        return
    end
    local name, roll, low, high = text:match(getRollPattern())
    if not name then return end
    ns.Debug("Rolls", "Würfelnachricht:", text)
    roll, low, high = tonumber(roll), tonumber(low), tonumber(high)
    local player = ns.ResolvePlayerName(name)
    if not player then
        ns.Debug("Rolls", "Wurf ignoriert, nicht in der Gruppe oder mehrdeutig:", name)
        return
    end
    -- Kategorie aus dem Würfelbereich: beschränkte Runde nur mit dem Bereich ihrer Kategorie,
    -- offene Runde 100 = Mainspec, 50 = Secondspec, 25 = Transmog
    local category
    if low == 1 then
        if leadRound.restricted then
            if high == RANGE[leadRound.category] then
                category = leadRound.holders[player] and leadRound.category or "NOSR"
            end
        else
            category = OPEN_CATEGORY_BY_RANGE[high]
        end
    end
    if not category then
        ns.Debug("Rolls", "Wurf ignoriert (falscher Bereich)", player, roll, low, high)
        return
    end
    local entry = leadRound.rolls[player] or {}
    if entry.roll or entry.category == "PASS" then
        ns.Debug("Rolls", "Weiterer Wurf ignoriert", player, roll)
        return
    end
    entry.roll = roll
    entry.max = high
    entry.category = category
    leadRound.rolls[player] = entry
    ns.Debug("Rolls", "Wurf", player, roll, entry.category)
    changed()
end

ns:RegisterEvent("CHAT_MSG_SYSTEM")

-- Nachrichten ------------------------------------------------------------------------------

ns.Comm:RegisterHandler("RS", function(sender, f)
    -- nur vom Verteiler (Gruppenleiter bzw. Plündermeister)
    if not ns.Roles:IsDistributorName(sender) then return end
    local holders = {}
    for player in (f[6] or ""):gmatch("[^;]+") do
        holders[player] = true
    end
    local category = f[7] ~= "" and f[7] or nil
    local duration = tonumber(f[8]) or 0
    activeRound = {
        id = f[3],
        itemID = tonumber(f[4]),
        restricted = f[5] == "1",
        category = category,
        holders = holders,
        freeReason = f[9] ~= "" and f[9] or nil,
        leader = sender,
        endsAt = duration > 0 and (GetTime() + duration) or nil,
    }
    ns.Debug("Rolls", "Runde vom Raidlead", f[3], f[4], category)
    changed()
end)

ns.Comm:RegisterHandler("RD", function(sender, f)
    if leadRound and leadRound.id == f[3] then
        if f[4] == "PASS" then
            applyPass(sender)
        end
    end
end)

ns.Comm:RegisterHandler("RE", function(sender, f)
    local round = activeRound
    if not round or round.id ~= f[3] or round.leader ~= sender then return end
    local winner = f[4] ~= "" and f[4] or nil
    round.result = { winner = winner, roll = tonumber(f[5]), category = f[6] }
    if winner then
        addHistory(round.itemID, winner, tonumber(f[5]), f[6], f[7] ~= "" and f[7] or nil)
    end
    changed()
end)

ns.Comm:RegisterHandler("RC", function(sender, f)
    if activeRound and activeRound.id == f[3] and activeRound.leader == sender then
        activeRound = nil
        ns.Print("Die Würfelrunde wurde abgebrochen.")
        changed()
    end
end)

-- Start mit Rückfrage, wenn das Item Hard Reserve ist
function Rolls:StartChecked(itemID, link, lootKey)
    local hr = ns.Session:GetHardReserve(itemID)
    ns.UI.Confirm("Dieses Item ist Hard Reserve für „" .. (hr and hr.note ~= "" and hr.note or "?")
        .. "“.\nTrotzdem auswürfeln?", function()
        Rolls:Start(itemID, link, nil, nil, nil, lootKey)
    end, hr ~= nil)
end

-- /paeniksoftres roll <Itemlink oder ItemID>
function ns.StartRollFromSlash(arg)
    local itemID = tonumber(arg) or (arg and arg ~= "" and C_Item.GetItemInfoInstant(arg))
    if not itemID then
        ns.Print("Aufruf: /paeniksoftres roll <Itemlink oder ItemID>")
        return
    end
    Rolls:StartChecked(itemID, arg:find("|H") and arg or nil)
end

ns:On("LOGIN", function()
    ns.Debug("Rolls", "Würfelmuster", getRollPattern())
end)
