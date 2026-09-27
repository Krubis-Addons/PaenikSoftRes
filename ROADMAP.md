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

Status: Iterationen 1–8 umgesetzt, dazu Anmeldeschluss, mehrere Sitzungen und Gilden-Synchronisation (Anmeldung ohne Gruppe), Weitergabe von Anmeldungen über die Gilde, ID fortführen (gelegte Bosse) und Hard Reserves, Gargul-Würfelfenster für Raider ohne dieses Addon, Besitz-Anzeige in der SR-Auswahl, Wunschliste, Sitzungsdaten pro Charakter, Loot-Browser, Reserves vom Raidlead für Spieler ohne Addon, regelmäßige Raids (Vorlagen mit automatischen Folgeterminen), Loot-Filter, Gewinner manuell wählen, Gewinne beim Handeln einlegen, „Soft Reserves“-Fenster (letzte Leiche, für alle) und „Beute“-Fenster (später aus dem Inventar verrollen), Plündermeister-Zuteilung, Lootqualität.

Offen / später:
- Encounter-Journal-Provider (`Data/EJProvider.lua`), sobald Blizzard das EJ in Forever aktiviert: Loot nachladen (`EJ_LOOT_DATA_RECIEVED` → Anzeige-Cache leeren), `EJ_ResetLootFilter()` vor dem Auslesen, Instanzliste cachen.
- Weitere Instanz-Tabellen, sobald klar ist, welche Raids Forever zum Launch hat.
- Tests in einer echten Gruppe: Sync zwischen zwei Spielern, fremde Namen, Gleichstand/Nachwurf, Loot-Panel an einer echten Leiche.
- Feldtest 2026-09-27: Einige Raider sahen beim Verteilen kein Fenster – vermutlich nur das „Soft Reserves“-Fenster am Lootfenster (erscheint nur bei dem, der die Leiche öffnet). Beim nächsten Raid prüfen, ob das Würfelfenster bei allen aufgeht (Debug-Log eines betroffenen Raiders).
- Gewinne beim Handeln einlegen (`Trade.lua`, noch ungetestet): automatisches Einlegen beim Öffnen des Handels (blockiert Forever `UseContainerItem` ohne Tastendruck? sonst Knopf „Gewinne einlegen“), Markierung „übergeben“ nach dem Handel, `/psr probe` für `GetTradePlayerItemLink`.
- Tests in einer Gruppe mit Gargul-Nutzern: Gargul-Würfelfenster öffnet/schließt sich, Würfe kommen an.
- Loot-Fenster in der Gruppe: „Soft Reserves“ öffnet sich bei allen Raidern, wenn der Raidlead lootet (Nachricht L); Plündermeister „Zuteilen“ nach der Würfelrunde; Beute-Liste bei Raidern.

Ideen (später umsetzen):

