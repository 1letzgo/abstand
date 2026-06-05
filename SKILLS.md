# Skills zuerst lesen

**Pflicht für Cursor (und andere Agenten):** Bevor du planst, codest oder antwortest, prüfe, ob es einen passenden **Skill** gibt — und lies ihn **vollständig**, bevor du improvisierst.

## Ablauf (immer)

1. **Aufgabe einordnen** — Was wird gebaut, geändert oder debuggt? (Framework, Feature, Dateityp)
2. **Skills suchen** — zuerst lokal, dann global (siehe unten)
3. **Skill lesen** — `SKILL.md` des Treffers von Anfang bis Ende (nicht nur die Beschreibung)
4. **Skill befolgen** — Vorgaben, Checklisten und „Common Mistakes“ aus dem Skill haben Vorrang vor Allgemeinwissen
5. **Projekt-Kontext** — danach `AGENTS.md` (Build, Theme, Dateistruktur)

Wenn kein Skill passt: normal weiterarbeiten und kurz vermerken, dass keiner gefunden wurde.

## Wo Skills liegen

| Ort | Pfad | Inhalt |
|-----|------|--------|
| **Projekt (priorität)** | `.agent/skills/<name>/SKILL.md` | Apple-/iOS-Skills für dieses Repo (lokal, nicht im Git) |
| Cursor (global) | `~/.cursor/skills-cursor/` | Regeln, Skills anlegen, Cursor-Produkt |
| Agent (global) | `~/.agents/skills/` | z. B. caveman, compress, find-skills |
| Plugins | `~/.cursor/plugins/cache/.../skills/` | Je nach installiertem Plugin |

Discovery-Hilfe (global): Skill **find-skills** (`~/.agents/skills/find-skills/SKILL.md`), wenn unklar ist, ob es einen Skill gibt.

## Abstand — typische Aufgaben → Skill

| Thema / Dateien | Skill unter `.agent/skills/` |
|-----------------|------------------------------|
| Wiedergabe, `PlaybackController`, `AVPlayer`, Now Playing, Audio-Session | `avkit` |
| CarPlay, `CarPlayCoordinator` | `carplay` |
| Downloads im Hintergrund, `DownloadManager` | `background-processing` |
| SwiftUI-UI, Layout, Listen, Theme | `swiftui-patterns`, ggf. `swiftui-performance` |
| Navigation, `NavigationStack`, Sheets | `swiftui-navigation` |
| Netzwerk, API, `ABSAPIClient` | `ios-networking` |
| JSON, Modelle, `ABSJSON` | `swift-codable` |
| Concurrency, `@MainActor`, Tasks | `swift-concurrency` |
| eBook / Readium | `pdfkit` oder `swiftui-webkit` (je nach Aufgabe) |
| Push / lokale Benachrichtigungen | `push-notifications` |
| Barrierefreiheit | `ios-accessibility` |
| Lokalisierung | `ios-localization` |
| App Store / Version / Review | `app-store-review` |
| Debugging, Instruments, Performance | `debugging-instruments`, `metrickit` |
| Tests | `swift-testing` |
| Git-Commit / PR-Text (knapp) | global: `caveman-commit` (nur auf Wunsch) |

Bei Überschneidungen: **spezifischeren** Skill wählen (z. B. `avkit` vor generischem `swiftui-patterns`).

## Wichtig für dieses Projekt

- **Theme:** `AppTheme`, `model.appearancePalette`, `themeAccent` — keine freien `Color`-Literale (siehe `AGENTS.md`)
- **Plattform:** nur iOS/iPadOS
- **Skills ersetzen nicht** `AGENTS.md` — beides lesen

## Cursor-Regel

Zusätzlich gilt die always-on-Regel `.cursor/rules/skills-first.mdc` (lokal unter `.cursor/`, falls vorhanden).
