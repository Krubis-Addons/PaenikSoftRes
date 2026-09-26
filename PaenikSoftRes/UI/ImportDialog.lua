-- Dialog für den softres.it-Import: CSV einfügen, Vorschau prüfen, ersetzen oder zusammenführen.
local _, ns = ...

local UI = ns.UI

local dialog = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
dialog:SetSize(520, 420)
dialog:SetPoint("CENTER")
dialog:SetFrameStrata("DIALOG")
dialog:SetToplevel(true)
dialog:EnableMouse(true)
dialog:SetMovable(true)
dialog:RegisterForDrag("LeftButton")
dialog:SetScript("OnDragStart", dialog.StartMoving)
dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
dialog:SetClampedToScreen(true)
dialog.TitleText:SetText("softres.it-Import")
dialog:Hide()

local help = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
help:SetPoint("TOPLEFT", dialog, "TOPLEFT", 14, -32)
help:SetPoint("RIGHT", dialog, "RIGHT", -14, 0)
help:SetJustifyH("LEFT")
help:SetText("Auf softres.it den Raid öffnen, „CSV“ exportieren, den Text kopieren und hier mit Strg+V einfügen.")

-- Mehrzeiliges Eingabefeld (Blizzard-Template mit Rahmen und Scrollbalken)
local input = CreateFrame("ScrollFrame", nil, dialog, "InputScrollFrameTemplate")
input:SetPoint("TOPLEFT", help, "BOTTOMLEFT", 6, -12)
input:SetPoint("RIGHT", dialog, "RIGHT", -22, 0)
input:SetHeight(210)
-- OnLoad des Templates lief mit Breite 0: Breiten nachziehen
input.EditBox:SetWidth(470)
input.EditBox.Instructions:SetWidth(470)
input.EditBox:SetFontObject("GameFontHighlightSmall")
input.EditBox.Instructions:SetText("ItemId,Name,Class,Note,Plus …")
input.CharCount:Hide()

local preview = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
preview:SetPoint("TOPLEFT", input, "BOTTOMLEFT", -6, -14)
preview:SetPoint("RIGHT", dialog, "RIGHT", -14, 0)
preview:SetJustifyH("LEFT")
preview:SetJustifyV("TOP")
preview:SetHeight(70)

local parsed -- Ergebnis der letzten Vorschau

local replaceButton, mergeButton

local function updatePreview()
    local text = input.EditBox:GetText()
    local result, err = ns.Import.ParseSoftresCSV(text)
    parsed = result
    replaceButton:SetEnabled(result ~= nil)
    mergeButton:SetEnabled(result ~= nil)
    if not result then
        preview:SetText(text == "" and "" or ("|cffff6060" .. err .. "|r"))
        return
    end
    local lines = {
        string.format("|cff60ff60%d Spieler, %d Reserves erkannt.|r", result.players, result.count),
    }
    if #result.notInGroup > 0 then
        local names = {}
        for i = 1, math.min(#result.notInGroup, 6) do
            names[i] = UI.ShortName(result.notInGroup[i])
        end
        local more = #result.notInGroup > 6 and (" … (+" .. (#result.notInGroup - 6) .. ")") or ""
        table.insert(lines, string.format("|cffffd100Nicht in der Gruppe (%d):|r %s%s",
            #result.notInGroup, table.concat(names, ", "), more))
    end
    if result.notInInstance > 0 then
        table.insert(lines, string.format("|cffffd100%d Reserves gehören nicht zur gewählten Instanz.|r",
            result.notInInstance))
    end
    if result.skipped > 0 then
        table.insert(lines, string.format("|cff999999%d Zeilen übersprungen (ohne ItemId oder Name).|r", result.skipped))
    end
    preview:SetText(table.concat(lines, "\n"))
end

-- Vorschau nicht bei jedem Tastendruck neu berechnen
local schedulePreview = UI.Debounce(updatePreview, 0.3)
input.EditBox:HookScript("OnTextChanged", function()
    schedulePreview()
end)

local function apply(replaceAll)
    if not parsed then return end
    local ok, err = ns.Import.Apply(parsed, replaceAll)
    if not ok then
        preview:SetText("|cffff6060" .. tostring(err) .. "|r")
        return
    end
    dialog:Hide()
end

replaceButton = UI.CreateButton(dialog, "Ersetzen", 140, function() apply(true) end)
replaceButton:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 14, 12)
mergeButton = UI.CreateButton(dialog, "Zusammenführen", 140, function() apply(false) end)
mergeButton:SetPoint("LEFT", replaceButton, "RIGHT", 8, 0)
local cancelButton = UI.CreateButton(dialog, "Abbrechen", 110, function() dialog:Hide() end)
cancelButton:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -14, 12)

local function buttonTooltip(button, text)
    button:SetMotionScriptsWhileDisabled(true)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
buttonTooltip(replaceButton, "Alle bisherigen Reserves der Sitzung werden durch den Import ersetzt.")
buttonTooltip(mergeButton, "Nur die Reserves der importierten Spieler werden ersetzt; Ingame-Reserves anderer Spieler bleiben.")

function ns.ShowImportDialog()
    if not ns.Session:IsOwner() then
        ns.Print("Import nur für den Raidlead mit eigener Sitzung.")
        return
    end
    input.EditBox:SetText("")
    parsed = nil
    replaceButton:Disable()
    mergeButton:Disable()
    preview:SetText("")
    dialog:Show()
    input.EditBox:SetFocus()
end
