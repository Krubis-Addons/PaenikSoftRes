-- Wunschliste: Items, die der eigene Charakter gern hätte. Rein lokal (kein Sync, keine Regelwirkung),
-- pro Charakter in db.wishlist[Name-Realm] = { [itemID] = true }. Änderungen melden WISHLIST_CHANGED.
local _, ns = ...

local Wishlist = {}
ns.Wishlist = Wishlist

local ATLAS = "auctionhouse-icon-favorite"

-- Stern als Textmarkierung; ohne Atlas im Client ein gelbes „W“
function Wishlist.Icon(size)
    size = size or 14
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(ATLAS) then
        return CreateAtlasMarkup(ATLAS, size, size)
    end
    return "|cffffd100W|r"
end

-- Stern auf eine Textur setzen (Bossliste); false, wenn der Atlas fehlt
function Wishlist.SetIconTexture(texture)
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(ATLAS) then
        texture:SetAtlas(ATLAS)
        return true
    end
    return false
end

local function list()
    local db = ns.db
    if not db then return nil end
    db.wishlist = db.wishlist or {}
    local me = ns.FullName("player")
    db.wishlist[me] = db.wishlist[me] or {}
    return db.wishlist[me]
end

function Wishlist:Has(itemID)
    local items = list()
    return items ~= nil and itemID ~= nil and items[itemID] == true
end

function Wishlist:Set(itemID, wanted)
    local items = list()
    if not items or not itemID then return end
    items[itemID] = wanted and true or nil
    ns.Debug("Wishlist", wanted and "hinzugefügt" or "entfernt", itemID)
    ns:Fire("WISHLIST_CHANGED")
end

function Wishlist:Toggle(itemID)
    self:Set(itemID, not self:Has(itemID))
    return self:Has(itemID)
end

-- Anzahl der Wunsch-Items in einer Liste von ItemIDs (doppelte zählen einmal)
function Wishlist:CountIn(itemIDs)
    local count, seen = 0, {}
    for _, itemID in ipairs(itemIDs) do
        if not seen[itemID] and self:Has(itemID) then
            seen[itemID] = true
            count = count + 1
        end
    end
    return count
end
