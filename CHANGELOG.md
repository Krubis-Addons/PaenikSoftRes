# Changelog

Alle nennenswerten Änderungen an PÄNIK SoftRes. Versionen nach [Semantic Versioning](https://semver.org/lang/de/):
0.x = Beta (Gruppen- und Gildentests stehen teilweise aus), 1.0.0 nach erfolgreichen Gruppentests.

## [Unreleased]

## [0.10.0] – 2026-10-03

### Neu
- MoP Classic als Testumgebung (Interface 50504), Testraid Mogu'shan-Gewölbe (Normal/Heroisch).
- Befehl `/psr version`.

### Behoben
- Reiter des Hauptfensters in MoP Classic (die Classic-Fassung der Blizzard-Reiterfunktionen brauchte globale Namen).
- Lootqualität in MoP Classic (andere Enum-Schlüssel).

## [0.9.0] – 2026-10-03

Erste versionierte Fassung (Stand nach 29 Entwicklungsschritten).

### Funktionen
- Soft-Reserve-Sitzungen: mehrere Sitzungen, Regeln (Instanz, SR-Anzahl, doppelte Items), Anmeldeschluss,
  gelegte Bosse, Hard Reserves, Reserves vom Raidlead für Spieler ohne Addon.
- Raider-Tab mit Bossliste, Besitz-Anzeige, Wunschliste und Loot-Filter; Loot-Browser für alle Instanzen.
- Gruppen-Sync und Gilden-Synchronisation (Anmeldung ohne Gruppe, Weitergabe über die Gilde),
  gemeinsame Raidleiter über Gildenränge.
- Würfelrunden (SR / Mainspec / Secondspec / Transmog), Würfelzeit, Nachwurf, manuelle Gewinnerwahl,
  Gargul-Würfelfenster für Raider ohne dieses Addon.
- Loot-Fenster „Soft Reserves“ (letzte Leiche, für alle) und „Beute“ (später aus dem Inventar verrollen),
  Plündermeister als Verteiler mit „Zuteilen“, Mindestqualität, Gewinne beim Handeln einlegen.
- Regelmäßige Raids (Vorlagen mit automatischen Folgeterminen), Aufräumen vergangener Sitzungen.
- softres.it-Import (CSV und Gargul-Export).

### Noch ungetestet (Gruppe/Gilde)
Siehe „Offen / später“ in ROADMAP.md.
