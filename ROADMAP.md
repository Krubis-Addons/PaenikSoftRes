# PaenikSoftRes – Roadmap

| # | Iteration | Inhalt |
|---|---|---|
| 2 | Datenmodell, Rollen, UI-Gerüst, API-Probe | Sitzung + Reserve-API, Rollenerkennung, Fenster mit Tabs, `/paeniksoftres probe` |
| 3 | Raidlead: Regeln | Instanzauswahl über Provider-Schicht (`Data/LootData.lua`): EJ-Provider (in der Beta leer, `EncounterJournalDisabled=1`) + eigene Tabellen. Max. SRs (1–5), doppelte Items, Sitzung sperren/öffnen. Schwierigkeitsgrade entfallen vorerst. |
| 4 | Raider: Auswahl + Sync | Raider-Tab mit Bossliste (Porträts) und Item-Liste (Klick = reservieren), Übersicht-Tab (Reserves pro Item), Sync-Protokoll `PSR` (`R`/`F`/`P`/`E`/`Q`/`S`/`X`) mit Sende-Queue (Throttle/Lockdown), Sitzungsübernahme bei Wechsel der Gruppenleitung. |
| 5 | Loot-Anzeige | Panel neben dem Lootfenster (`UI/LootPanel.lua`, ab Qualität „Ungewöhnlich“, verschiebbar) mit SR-Inhabern und Gewinnern; Tooltip-Zeile „Soft Reserve“ über `TooltipDataProcessor`. |
| 6 | Roll-Runden | `Rolls.lua` + `UI/RollFrames.lua`: SR-Runde bzw. offene Runde, Kategorie über Würfelbereich (MS 100, OS 50, Transmog 25), Würfelzeit, freier Wurf wenn alle Berechtigten passen, Nachwurf bei Gleichstand, Verlauf. |
| 7 | softres.it-Import | `Import.lua` + `UI/ImportDialog.lua`: CSV-Export von softres.it, Vorschau, „Ersetzen“ oder „Zusammenführen“ (Mischbetrieb), Quelle `softres` (Übersicht hellblau). |
| 8 | Feinschliff | Bestätigungsdialoge (`UI.Confirm`), Optionen-Seite im Blizzard-Menü (`UI/Options.lua`), Debug-Log und Testbefehle standardmäßig aus, Gargul-Export-Import (LibDeflate in `Libs/`), Forever-Dungeons als Testdaten (`Data/Instances/ForeverDungeons.lua`), Gesamt-Review mit `wow-reviewer` und dessen Befunde behoben. |

Status: Iterationen 1–8 umgesetzt, dazu Anmeldeschluss, mehrere Sitzungen und Gilden-Synchronisation (Anmeldung ohne Gruppe), Weitergabe von Anmeldungen über die Gilde, ID fortführen (gelegte Bosse) und Hard Reserves, Gargul-Würfelfenster für Raider ohne dieses Addon, Besitz-Anzeige in der SR-Auswahl, Wunschliste, Sitzungsdaten pro Charakter, Loot-Browser, Reserves vom Raidlead für Spieler ohne Addon, regelmäßige Raids (Vorlagen mit automatischen Folgeterminen).

Offen / später:
- Encounter-Journal-Provider (`Data/EJProvider.lua`), sobald Blizzard das EJ in Forever aktiviert: Loot nachladen (`EJ_LOOT_DATA_RECIEVED` → Anzeige-Cache leeren), `EJ_ResetLootFilter()` vor dem Auslesen, Instanzliste cachen.
- Weitere Instanz-Tabellen, sobald klar ist, welche Raids Forever zum Launch hat.
- Tests in einer echten Gruppe: Sync zwischen zwei Spielern, fremde Namen, Gleichstand/Nachwurf, Loot-Panel an einer echten Leiche.
- Feldtest 2026-09-27: Einige Raider sahen beim Verteilen kein Fenster – vermutlich nur das „Soft Reserves“-Fenster am Lootfenster (erscheint nur bei dem, der die Leiche öffnet). Beim nächsten Raid prüfen, ob das Würfelfenster bei allen aufgeht (Debug-Log eines betroffenen Raiders).
- Tests in einer Gruppe mit Gargul-Nutzern: Gargul-Würfelfenster öffnet/schließt sich, Würfe kommen an.

Ideen (später umsetzen):
- **Gewinner manuell wählen:** Option (pro Runde oder als Einstellung), dass der Gewinner nicht automatisch der höchste Wurf ist: Beim Beenden wählt der Raidlead im Leitfenster aus der Liste aller Würfelnden (mit Kategorie und Wurf) den Gewinner; Ansage, `RE`, Verlauf und Wunschliste laufen danach wie beim automatischen Gewinner.
- **Loot-Filter (Raider-Tab + Loot-Browser):** Filter-Dropdown über der Item-Liste nach Rüstungsklasse (Stoff/Leder/Kette/Platte, Schilde, Waffenarten, Sonstiges) und Slot (Kopf, Hals, Schultern, … Waffe, Schildhand, Distanz). Daten ohne Serverabfrage aus `C_Item.GetItemInfoInstant` (`itemEquipLoc`, `classID`/`subClassID`, Konstanten `Enum.ItemClass`/`Enum.ItemArmorSubclass`). Schnellwahl „Für meine Klasse“ (tragbare Rüstung/Waffen je Klasse), Filter-Stand pro Charakter gespeichert und in beiden Ansichten geteilt; Hinweis im Kopf „n von m Items (gefiltert)“.
- **„Soft Reserves“-Fenster überarbeiten (separat öffnen, aus dem Inventar verwürfeln):** siehe Umsetzungsidee unten.

## Umsetzungsidee: „Soft Reserves“-Fenster separat öffnen und Items aus dem Inventar verwürfeln

Ausgangslage: `UI/LootPanel.lua` zeigt sich nur bei `LOOT_OPENED` und listet die Items der geöffneten Leiche.
Hat der Raidlead Items schon aufgehoben (z. B. alles gelootet, nach dem Kampf verteilen), kann er sie nur
noch per `/paeniksoftres roll <Item>` auswürfeln.

**1. Fenster separat öffnen**
- Neue Wege zum Öffnen: Knopf „Loot verteilen“ im Raidlead-Tab und in der Übersicht, Slash
  `/paeniksoftres loot`, Shift-Klick auf den Minimap-Button.
- Das Fenster bekommt zwei Ansichten (Reiter oben im Fenster): **Leiche** (wie bisher, nur solange eine
  Leiche offen ist) und **Beute** (Items im Inventar des Raidleads, siehe 2). Ohne offene Leiche startet es
  in „Beute“.
- Raider können das Fenster ebenfalls öffnen; sie sehen „Beute“ nur lesend (SR-Inhaber, Gewinner,
  „wird ausgewürfelt“), ohne Würfeln-Knöpfe. Dafür schickt der Raidlead die Beute-Liste an die Gruppe
  (neue Nachricht, z. B. `B^sid^itemID:lootKey,...` in Stücken wie `P`).

**2. Beute-Liste (Items des Raidleads im Inventar)**
- Erfassen beim Looten: eigene Loot-Meldungen (`CHAT_MSG_LOOT`, nur eigene) bzw. beim Schließen der Leiche die
  aufgehobenen Slots aus `LOOT_SLOT_CLEARED` merken. Aufgenommen werden Items der Sitzungs-Instanz
  (`Session:GetInstanceItemSet`) ab Qualität „Ungewöhnlich“, dazu jedes Item mit SR/HR.
- Gespeichert pro Sitzung in `session.bagLoot = { { itemID, lootKey, lootedAt, awardedTo, traded } }`
  (`lootKey` = „bag:“ + fortlaufende Nummer oder Item-GUID), damit Gewinner und Status über `/reload`
  erhalten bleiben und dieselbe Gewinner-Anzeige wie bei Leichen funktioniert (`Rolls:GetAwards(lootKey)`).
- Manuell hinzufügen: Item aus den Taschen auf das Fenster ziehen (`OnReceiveDrag` + `GetCursorInfo`, keine
  Hooks an Blizzard-Taschen → kein Taint) oder `/paeniksoftres roll <Item>` legt es mit an.
- Entfernen: Rechtsklick „Aus der Liste entfernen“; automatisch, wenn das Item nicht mehr in den Taschen ist
  (Handel/Brief, Prüfung über `C_Item.GetItemCount` bei `BAG_UPDATE_DELAYED`) → Status „übergeben“.
- Zeile zeigt wie bei der Leiche: SR-Inhaber / HR / Gewinner, Knopf „Würfeln“ (bzw. „Erneut“), dazu
  die verbleibende Handelszeit für gebundene Items (Classic: 2 h nach dem Looten).

**3. Verwürfeln und Übergeben**
- „Würfeln“ ruft `Rolls:StartChecked(itemID, link, lootKey)` wie bei der Leiche; Ansage, Gargul-Fenster und
  Ergebnis laufen unverändert.
- Nach der Runde steht der Gewinner in der Zeile („an X übergeben“). Optional später: Öffnet der Raidlead
  einen Handel mit dem Gewinner, weist das Fenster auf das Item hin bzw. legt es auf Klick in den Handel.

**Vorab recherchieren (wow-api-recherche, ingame mit `probe` prüfen)**
- Format von `CHAT_MSG_LOOT` für eigene Beute auf Forever (Secret Values? Lokalisierung `LOOT_ITEM_SELF`).
- Handelszeit gebundener Items: Tooltip-Zeile (`BIND_TRADE_TIME_REMAINING`) über `C_TooltipInfo.GetBagItem`.
- Item-GUID/Position in den Taschen (`C_Item.GetItemGUID`, `ItemLocation`) für einen stabilen `lootKey`.
- Ob Item-Übergabe in den Handel (`C_Container.PickupContainerItem` + `ClickTradeButton`) außerhalb des Kampfs
  erlaubt ist.

**Schritte:** (a) Fenster separat öffnen + manuelle Beute-Liste per Drag & Drop, (b) automatische Erfassung
beim Looten + Übergabe-Status, (c) Beute-Liste für Raider (Sync), (d) optional Handels-Hilfe.
