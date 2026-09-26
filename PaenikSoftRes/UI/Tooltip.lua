-- Item-Tooltips um die Soft Reserves der aktuellen Sitzung ergänzen.
-- TooltipDataProcessor statt Hook auf Blizzard-Funktionen: kein Taint.
local _, ns = ...

local UI = ns.UI

local function onItemTooltip(tooltip, data)
    if not data or not ns.Session:Get() then return end
    local itemID = data.id
    if issecretvalue and issecretvalue(itemID) then return end
    if type(itemID) ~= "number" then return end
    local hr = ns.Session:GetHardReserve(itemID)
    if hr then
        tooltip:AddLine(" ")
        tooltip:AddLine("|cffff5050Hard Reserve:|r " .. (hr.note ~= "" and hr.note or "fest vergeben"), 1, 1, 1, true)
        return
    end
    local holders, total = UI.FormatHolders(itemID)
    if holders then
        tooltip:AddLine(" ")
        tooltip:AddLine(string.format("|cffffd100Soft Reserve (%d):|r %s", total, holders), 1, 1, 1, true)
    end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onItemTooltip)
else
    ns.Debug("Tooltip", "TooltipDataProcessor nicht verfügbar")
end
