@~/.claude/wow-rules.md

# Addon: PaenikSoftRes

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
- Datenmodell: `ns.db.session` (siehe Kopfkommentar in `Session.lua`). Spielerschlüssel immer `Name-Realm` über `ns.FullName(unit)`.
- Interne Ereignisse über `ns:On(name, fn)` / `ns:Fire(name, ...)`: `DB_READY`, `LOGIN`, `SESSION_CHANGED`, `ROLE_CHANGED`.
- Rolle (`ns.Roles:IsLead()`): `db.forceRole` (Slash `lead|raider|auto`) > solo = Raidlead > in der Gruppe nur der Gruppenleiter. Maßgebliche Master-Liste nur bei `Session:IsMaster()` (Besitzer + Raidlead); ein neuer Gruppenleiter kann eine fremde Sitzung übernehmen (`Session:TakeOver`).
- Loot-Daten über Provider (`Data/LootData.lua`): EJ-Provider (in der Beta per `EncounterJournalDisabled=1` leer) + eigene Tabellen in `Data/Instances/` (ItemIDs aus AtlasLootClassic). Instanzen heißen `providerID:key` (z. B. `static:mc`). Sync über Addon-Messages, Präfix `PSR`, Protokoll im Kopf von `Comm.lua`. Regeln (`R`) nur vom Gruppenleiter annehmen; voller Stand = `R` + `F` + `P`-Chunks.
- Spielernamen: Forever hat Nachnamen. `UnitName`/`UnitFullName` liefern dann (Vorname, Nachname) statt (Name, Realm). `ns.FullName` baut „Vorname Nachname-Realm“ (Realm über `GetPlayerInfoByGUID`, sonst `GetNormalizedRealmName`), passend zum Absender von CHAT_MSG_ADDON (z. B. „Krubi Shooty-ClassicBetaPvE2“). Alte Schlüssel („Krubi-Shooty“) migriert `migratePlayerKeys` in Core.lua.
- Nicht dokumentierte Globals (z. B. `EJ_*`, `GetLootSlotLink`, `IsInGroup`) vor der Nutzung mit `/paeniksoftres probe` ingame prüfen.
- SavedVariables: laut forever-addon-kit wurden sie in der Beta nie geladen. Am 2026-09-26 war die Sitzung nach dem Neustart aber vorhanden (Log: „Sitzung vorhanden: true“), das Laden funktioniert also inzwischen. Kein Workaround nötig.
- Minimap-Button ohne Bibliothek (`UI/MinimapButton.lua`), Position in `db.minimap.angle`; Icon `ns.UI.ICON` (Kleiner brauner Beutel, ItemID 4496) auch als Fensterporträt.
- Testhilfen: `/paeniksoftres fake` trägt 5 Testspieler ein (nur ohne Gruppe, `source = "fake"`, wird nie gesendet); `/paeniksoftres loottest` zeigt das Loot-Panel mit vorhandenen Reserves ohne Leiche.
