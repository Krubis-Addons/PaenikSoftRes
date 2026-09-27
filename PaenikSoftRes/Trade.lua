-- Gewonnene Items beim Handeln: Öffnet der Raidlead einen Handel mit einem Spieler, werden dessen gewonnene,
-- noch nicht übergebene Items aus den eigenen Sitzungen automatisch in das Handelsfenster gelegt
-- (C_Container.UseContainerItem bei offenem Handel, wie Rechtsklick). Zusätzlich ein Knopf am Handelsfenster,
-- falls das automatische Einlegen blockiert ist. Nach „Handel abgeschlossen“ werden die gehandelten Items im
-- Verlauf als übergeben markiert (entry.traded).
-- Einstellung db.autoTrade (Standard an).
local _, ns = ...

local Trade = {}
ns.Trade = Trade

local ADD_DELAY = 0.3        -- Abstand zwischen zwei Items (wie Gargul, sonst verschluckt der Client welche)
local MAX_TRADABLE = 6       -- Handelsplätze (der 7. wird nicht gehandelt)
local HISTORY_DAYS = 7       -- nur Gewinne der letzten Tage (danach ist gebundene Beute ohnehin nicht handelbar)

local partner                -- Schlüssel des Handelspartners (ns.FullName("npc"))
local addToken = 0           -- bricht eine laufende Einlege-Kette ab (neuer Handel/geschlossen)

function Trade:IsEnabled()
    return ns.db and ns.db.autoTrade ~= false
end

local function tradeOpen()
    return TradeFrame ~= nil and TradeFrame:IsShown()
end

-- Gewonnene, noch nicht übergebene Items eines Spielers aus allen eigenen Sitzungen: { entry, ... }
local function pendingWins(player)
    local list = {}
    if not player then return list end
    local since = GetServerTime() - HISTORY_DAYS * 86400
    for _, s in ipairs(ns.Session:List()) do
        for _, entry in ipairs(s.history or {}) do
            if entry.winner == player and not entry.traded and (entry.time or 0) >= since then
                table.insert(list, entry)
            end
        end
    end
    return list
end

function Trade:GetPendingFor(player)
    return pendingWins(player)
end

-- Item mit dieser ID in den Taschen finden, das noch nicht gesperrt ist (im Handel liegende sind gesperrt)
local function findInBags(itemID)
    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    for bag = 0, lastBag do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            if C_Container.GetContainerItemID(bag, slot) == itemID then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and not info.isLocked then
                    return bag, slot
                end
            end
        end
    end
end

-- ItemIDs, die gerade auf unserer Seite des Handels liegen
local function itemsInTrade()
    local ids = {}
    if type(GetTradePlayerItemLink) ~= "function" then return ids end
    for i = 1, MAX_TRADABLE do
        local link = GetTradePlayerItemLink(i)
        if link and not ns.IsSecret(link) then
            local itemID = C_Item.GetItemInfoInstant(link)
            if itemID then
                table.insert(ids, itemID)
            end
        end
    end
    return ids
end

-- Gewonnene Items nacheinander einlegen; manual = vom Knopf (Rückmeldung auch, wenn nichts zu tun ist)
function Trade:AddWonItems(manual)
    if not tradeOpen() or not partner then return end
    local wins = pendingWins(partner)
    if #wins == 0 then
        if manual then
            ns.Print(ns.UI.ShortName(partner) .. " hat keine offenen Gewinne.")
        end
        return
    end
    -- bereits eingelegte Items nicht doppelt nehmen
    local already = {}
    for _, itemID in ipairs(itemsInTrade()) do
        already[itemID] = (already[itemID] or 0) + 1
    end
    local queue = {}
    for _, entry in ipairs(wins) do
        if (already[entry.itemID] or 0) > 0 then
            already[entry.itemID] = already[entry.itemID] - 1
        else
            table.insert(queue, entry.itemID)
        end
    end
    addToken = addToken + 1
    local token, added, missing, index = addToken, 0, {}, 0
    local function step()
        if token ~= addToken or not tradeOpen() then return end
        index = index + 1
        local itemID = queue[index]
        if not itemID or #itemsInTrade() >= MAX_TRADABLE then
            if added > 0 then
                ns.Print(string.format("%d gewonnene(s) Item(s) für %s in den Handel gelegt.", added,
                    ns.UI.ShortName(partner)))
            end
            for _, id in ipairs(missing) do
                local _, link = C_Item.GetItemInfo(id)
                ns.Print("Nicht in den Taschen gefunden: " .. (link or ("Item " .. id)))
            end
            return
        end
        local bag, slot = findInBags(itemID)
        if bag then
            ns.Debug("Trade", "Lege ein", itemID, bag, slot)
            C_Container.UseContainerItem(bag, slot)
            added = added + 1
        else
            table.insert(missing, itemID)
        end
        C_Timer.After(ADD_DELAY, step)
    end
    step()
end

-- Handel abgeschlossen: gehandelte Items beim Partner als übergeben markieren
local lastTradeItems = {}

local function markTraded()
    if not partner then return end
    local wins = pendingWins(partner)
    local marked = 0
    for _, itemID in ipairs(lastTradeItems) do
        for _, entry in ipairs(wins) do
            if entry.itemID == itemID and not entry.traded then
                entry.traded = true
                entry.tradedAt = GetServerTime()
                marked = marked + 1
                break
            end
        end
    end
    if marked > 0 then
        ns.Debug("Trade", "Als übergeben markiert", partner, marked)
        ns:Fire("SESSION_CHANGED")
    end
end

-- Knopf am Handelsfenster (Fallback, falls das automatische Einlegen blockiert ist)
local tradeButton

local function ensureButton()
    if tradeButton or not TradeFrame then return end
    tradeButton = CreateFrame("Button", nil, TradeFrame, "UIPanelButtonTemplate")
    tradeButton:SetSize(150, 22)
    tradeButton:SetText("Gewinne einlegen")
    tradeButton:SetPoint("TOPRIGHT", TradeFrame, "BOTTOMRIGHT", 0, -2)
    tradeButton:SetScript("OnClick", function() Trade:AddWonItems(true) end)
    tradeButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(ns.TITLE)
        local wins = pendingWins(partner)
        GameTooltip:AddLine(#wins > 0 and ("Legt " .. #wins .. " gewonnene(s) Item(s) von " .. ns.UI.ShortName(partner)
            .. " in den Handel.") or "Keine offenen Gewinne für diesen Spieler.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    tradeButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function ns:TRADE_SHOW()
    partner = ns.FullName("npc")
    wipe(lastTradeItems)
    ns.Debug("Trade", "Handel mit", partner or "?")
    ensureButton()
    local wins = pendingWins(partner)
    if tradeButton then
        tradeButton:SetShown(#wins > 0)
    end
    if #wins > 0 and Trade:IsEnabled() then
        -- einen Moment warten, bis das Handelsfenster bereit ist
        C_Timer.After(ADD_DELAY, function() Trade:AddWonItems(false) end)
    end
end

-- Inhalt merken, solange der Handel offen ist (bei „Handel abgeschlossen“ ist er schon leer)
function ns:TRADE_PLAYER_ITEM_CHANGED()
    lastTradeItems = itemsInTrade()
end

function ns:TRADE_ACCEPT_UPDATE()
    lastTradeItems = itemsInTrade()
end

function ns:UI_INFO_MESSAGE(_, message)
    if ns.IsSecret(message) or not ERR_TRADE_COMPLETE then return end
    if message == ERR_TRADE_COMPLETE then
        markTraded()
    end
end

function ns:TRADE_CLOSED()
    addToken = addToken + 1 -- laufende Einlege-Kette abbrechen
end

ns:RegisterEvent("TRADE_SHOW")
ns:RegisterEvent("TRADE_CLOSED")
ns:RegisterEvent("TRADE_PLAYER_ITEM_CHANGED")
ns:RegisterEvent("TRADE_ACCEPT_UPDATE")
ns:RegisterEvent("UI_INFO_MESSAGE")
