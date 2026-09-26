@~/.claude/wow-rules.md

# Addon: PaenikSoftRes (Anzeigename „PÄNIK SoftRes“, `ns.TITLE`)

## Worum geht es
Das Addon ist ein Soft Reserve Addon zum Management der Soft Reserves eines Raids. Es gibt verschiedene Rollen mit unterschiedlichen Funktionen. Ziel des Addons ist es ein Tool zu schaffen um das vergeben von Loot zu erleichtern und eine Ingame Oberfläche zu schaffen für Raider und Raidlead ohne auf externe Quellen angewiesen zu sein.
Es soll Möglichkeiten geschaffen werden externe Quellen anzubinden um einen Übergang zu erleichtern oder einen Mischbetrieb zu ermöglichen.


## Projektdetails
- Addon-Code: `PaenikSoftRes/` (per Junction im Spiel verlinkt)
- Zielversion: WoW: Forever (Interface 16001) – bei Bedarf anpassen
- SavedVariables: `PaenikSoftResDB` (Einstellungen), `PaenikSoftResDebugLog` (Debug-Log)
- Slash-Befehl: `/paeniksoftres`


Es soll ein Nutzer und ein Raidlead Mode geben.

Der Raidlead kann die Soft Reserve Regeln festlegen (Welcher Dungeon/Raid, wie viele Soft Reserves pro User...) 

Nutzer können aus einer Liste von Verfügbaren Loot eines Ausgewählten Dungon/Raids eine Auswahl treffen.

Es soll eine Schnittstelle geben um andere Soft Reserve System anzubinden:
- https://softres.it

Es gibt ein Oberfläche beim Looten mit den Soft Reserve Informationen pro Item. Die Raidlead rolle kann eine Roll Runde starten und beenden. Nutzen haben eine Oberfläche zum Rollen der Items (Mainspec, Secondspec, Transmog). 

## Besonderheiten dieses Addons
- Roadmap und Status der Iterationen: `ROADMAP.md`
- Datenmodell: mehrere Sitzungen `db.sessions[id]`, aktive `db.activeSessionId` (wird an die Gruppe verteilt), Spiegel beim Raider `db.remoteSession` (siehe Kopf von `Session.lua`). `Session:Get()` liefert die aktuelle (Raidlead: aktive eigene, Raider in der Gruppe: Spiegel) – immer darüber zugreifen. Spielerschlüssel immer `Name-Realm` über `ns.FullName(unit)`.
- Interne Ereignisse über `ns:On(name, fn)` / `ns:Fire(name, ...)`: `DB_READY`, `LOGIN`, `SESSION_CHANGED`, `ROLE_CHANGED`.
- Rolle (`ns.Roles:IsLead()`): `db.forceRole` (Slash `lead|raider|auto`) > solo = Raidlead > in der Gruppe nur der Gruppenleiter. Maßgebliche Master-Liste nur bei `Session:IsMaster()` (Besitzer + Raidlead); ein neuer Gruppenleiter kann eine fremde Sitzung übernehmen (`Session:TakeOver`).
- Verfügbarkeit: Der Forever-Server kennt nicht alle Classic-Items. `LootData:GetDisplayEncounters` blendet Items mit `ITEM_DATA_LOAD_RESULT` = false aus und füllt Bosse unter 6 Items aus `filler` der Instanz auf. UI immer über GetDisplayEncounters, Validierung (Session) über alle Items + filler.
- Loot-Daten über Provider (`Data/LootData.lua`): EJ-Provider (in der Beta per `EncounterJournalDisabled=1` leer) + eigene Tabellen in `Data/Instances/` (ItemIDs aus AtlasLootClassic). Instanzen heißen `providerID:key` (z. B. `static:mc`). Sync über Addon-Messages, Präfix `PSR`, Protokoll im Kopf von `Comm.lua`. Regeln (`R`) nur vom Gruppenleiter annehmen; voller Stand = `R` + `F` + `P`-Chunks.
- Spielernamen: Forever hat Nachnamen. `UnitName`/`UnitFullName` liefern dann (Vorname, Nachname) statt (Name, Realm). `ns.FullName` baut „Vorname Nachname-Realm“ (Realm über `GetPlayerInfoByGUID`, sonst `GetNormalizedRealmName`), passend zum Absender von CHAT_MSG_ADDON (z. B. „Krubi Shooty-ClassicBetaPvE2“). Alte Schlüssel („Krubi-Shooty“) migriert `migratePlayerKeys` in Core.lua.
- Nicht dokumentierte Globals (z. B. `EJ_*`, `GetLootSlotLink`, `IsInGroup`) vor der Nutzung mit `/paeniksoftres probe` ingame prüfen.
- SavedVariables: laut forever-addon-kit wurden sie in der Beta nie geladen. Am 2026-09-26 war die Sitzung nach dem Neustart aber vorhanden (Log: „Sitzung vorhanden: true“), das Laden funktioniert also inzwischen. Kein Workaround nötig.
- Minimap-Button ohne Bibliothek (`UI/MinimapButton.lua`), Position in `db.minimap.angle`; Icon `ns.UI.ICON` = Loot-Mauszeiger `Interface\Cursor\LootAll` (Sack), auch als Fensterporträt und in der .toc.
- Würfelrunden: Protokoll im Kopf von `Rolls.lua` (RS/RD/RE/RC über `Comm:RegisterHandler`). Kategorie ergibt sich aus dem Würfelbereich (SR/MS /roll, OS /roll 50, Transmog /roll 25) – funktioniert auch ohne Addon; RD meldet nur „Passen“.
- Import: `Import.ParseSoftres` (erkennt softres.it-CSV oder Gargul-Export) → `Session:ImportReserves(reserves, "softres", replaceAll)`; Limits/Instanz werden beim Import bewusst nicht geprüft. Namenszuordnung für Import und Würfe: `ns.ResolvePlayerName` (Core.lua).
- Testhilfen (nur mit aktivem Debug, Einstellung `db.debug`, Standard aus – für Log-Auswertung in den Optionen oder mit `/paeniksoftres debug` einschalten): `probe`, `fake` (5 Testspieler, nur ohne Gruppe, `source = "fake"`, wird nie gesendet), `loottest` (Loot-Panel ohne Leiche), `lead`/`raider`/`auto`.
- Gruppenliste: `ns.UnitForName` / `ns.ResolvePlayerName` nutzen eine Nachschlagetabelle (Core.lua), neu aufgebaut bei `GROUP_ROSTER_UPDATE`/`UNIT_NAME_UPDATE` (Roles.lua, feuert `ROSTER_CHANGED`). Secret Values immer vor Wahrheitstests prüfen (`ns.IsSecret`).
- Import-Namen, die noch keinem Gruppenmitglied zugeordnet sind, tragen `importName`; `Session:ResolveImportedPlayers` zieht sie bei `ROSTER_CHANGED` auf den echten Schlüssel um.
- Rückfragen über `UI.Confirm(text, onAccept, condition)` (eigener Frame, keine `StaticPopupDialogs`).
- Bibliotheken in `Libs/` (unverändert, von luacheck ausgenommen): LibStub, LibDeflate (zlib-Lizenz, für den Gargul-Export von softres.it), LibSerialize (MIT, für Gargul-Nachrichten).
- Gargul-Kompatibilität (`GargulCompat.lua`, Protokoll im Dateikopf): `Rolls:Start` sendet zusätzlich eine Gargul-Startnachricht (Präfix `GargulComm2`, AceComm-Stückelung von Hand über `Comm:SendRaw`), damit Raider nur mit Gargul dessen Würfelfenster bekommen; Knöpfe mit unseren Bereichen (100/50/25), die Würfe wertet Rolls.lua wie jeden /roll aus. Nicht gesendet, wenn Gargul beim Raidlead selbst geladen ist. Option `db.gargulCompat`, Selbsttest `/paeniksoftres gargultest`.
- Testdaten: `Data/Instances/ForeverDungeons.lua` (7 Forever-Beta-Dungeons, aus ForeverDungeonJournal v1.1 bzw. dessen SOURCES.txt).
- Anmeldeschluss: `session.deadline` (Zeitstempel, `GetServerTime`/`time()`). `Session:IsLocked()` = manuell gesperrt ODER Schluss erreicht – immer statt `s.locked` prüfen. Beim Raidlead sperrt ein Timer die Sitzung zum Schluss und sagt es an; „Öffnen“ danach entfernt den Schluss. Übertragen als 10. Feld der `R`-Nachricht.
- Gilden-Synchronisation (`GuildSync.lua`, Protokoll im Dateikopf, Kanal GUILD, unsichtbar): veröffentlichte eigene Sitzungen (`session.published`, `version` via `Session:Touch`) werden als Kopien in `db.guildSessions` gehalten und von allen Mitgliedern weitergegeben; Löschmarken (`deleted`) verhindern Wiederkehr. Anmeldungen der Raider in `db.signups` (pending/confirmed/rejected), Bestätigung per `GA`. Vor jedem Whisper Online-Prüfung über den Gildenroster (sonst sichtbare „Spieler nicht gefunden“-Meldung). Raider-Tab/Übersicht nutzen `Session:GetViewed()` und `ns.Signup` (own/group/guild).
- Anmeldeschluss sperrt nicht hart (`locked` bleibt false), damit rechtzeitig abgegebene Gilden-Anmeldungen (`signedAt`) auch danach angenommen werden (bis 24 h). Sende-Queue: GUILD-Nachrichten haben die niedrigste Priorität.
- Weitergabe von Anmeldungen (A3): Raider verteilen ausstehende Anmeldungen als `GU` in der Gilde; alle speichern sie in `db.relaySignups` und reichen sie weiter, wenn der Raidlead online kommt. Der Raidlead meldet das Ergebnis als `GC` an die Gilde. Bewusst ohne Echtheitsprüfung (Nutzerentscheidung).
- Gelegte Bosse: `session.killed[encounterIndex]` (Index wie `LootData:GetDisplayEncounters`), markiert per Rechtsklick in der Bossliste (Raidlead, eigene Sitzung). `Session:GetKilledOnlyItems(s)` = nicht mehr reservierbar. `Session:Continue()` legt eine Fortsetzungssitzung (gleiche ID) an. Sync: 12. Feld von `R`, 14. Feld von `GR`.
- Hard Reserves: `session.hardReserves[itemID] = { note }`, gesetzt per Rechtsklick auf ein Item im Raider-Tab (Raidlead, eigene Sitzung; `UI.Prompt`). `Session:SetHardReserve` entfernt SRs auf dem Item. Nicht reservierbar (`ValidateReserves`), Würfeln nur nach Rückfrage (`Rolls:StartChecked`). Sync: `H` (Gruppe, erstes Stück leert), `GH` (Gilde). Gargul-Import übernimmt `hardreserves` („for“ als Notiz).
