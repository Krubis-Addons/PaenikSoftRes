# PaenikSoftRes – Roadmap

| # | Iteration | Inhalt |
|---|---|---|
| 2 | Datenmodell, Rollen, UI-Gerüst, API-Probe | Sitzung + Reserve-API, Rollenerkennung, Fenster mit Tabs, `/paeniksoftres probe` |
| 3 | Raidlead: Regeln | Instanzauswahl über Provider-Schicht (`Data/LootData.lua`): EJ-Provider (in der Beta leer, `EncounterJournalDisabled=1`) + eigene Tabellen (Start: Molten Core). Max. SRs (1–5), doppelte Items, Sitzung sperren/öffnen. Schwierigkeitsgrade entfallen vorerst. |
| 4 | Raider: Auswahl + Sync | Raider-Tab mit Boss-Filter und Item-Liste (Klick = reservieren), Übersicht-Tab (Reserves pro Item), Sync-Protokoll `PSR` (`R`/`F`/`P`/`E`/`Q`/`S`/`X`) mit Sende-Queue (Throttle/Lockdown), Sitzungsübernahme bei Wechsel der Gruppenleitung. |
| 5 | Loot-Anzeige | Panel neben dem Lootfenster (`UI/LootPanel.lua`, ab Qualität „Ungewöhnlich“) mit SR-Inhabern (grün = ich, grau = nicht in der Gruppe), „Ansagen“/„Alle ansagen“ für den Raidlead im Gruppenchat; Tooltip-Zeile „Soft Reserve“ über `TooltipDataProcessor`. |
| 6 | Roll-Runden | Der Lead startet eine Runde für ein Item (aus dem Loot-Panel oder per Link) → `ROLL_START` an den Raid. Raider bekommen ein Popup mit den Buttons SR/MS/OS/Transmog/Passen → `RandomRoll(1,100)`, das Ergebnis wird aus `CHAT_MSG_SYSTEM` gelesen (lokalisiertes Muster aus `RANDOM_ROLL_RESULT`). Priorität SR > MS > OS > TM; der Lead beendet die Runde → Gewinner wird angezeigt (optional im Raidchat), Historie wird gespeichert. |
| 7 | softres.it-Import | Import-Dialog (mehrzeilige EditBox, Kopieren & Einfügen) für den CSV- bzw. Gargul-Export von softres.it → Übernahme in `db.session.reserves`, Mischbetrieb mit Ingame-Reserves (Quelle markieren). HTTP ist nicht möglich, also nur Einfügen. Das Format wird zu Beginn der Iteration recherchiert. |
| 8 | Feinschliff | Minimap-/Addon-Compartment-Button, Optionen, Review mit `wow-reviewer`, `.toc`-Metadaten. |

Status: Iterationen 1–5 umgesetzt. Offen aus Iteration 3: Bestätigungsdialog vor „Neu starten“/Instanzwechsel, wenn schon Reserves existieren; weitere Instanz-Tabellen, sobald klar ist, welche Inhalte Forever hat.
