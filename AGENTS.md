# AGENTS.md — stand, 12. Mai 2026

## Build

```bash
# Für Simulator bauen (Name an verfügbarere Simulatoren anpassen):
xcodebuild -project abstand.xcodeproj -scheme abstand \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# Für Gerät (erfordert Signing):
xcodebuild -project abstand.xcodeproj -scheme abstand \
  -destination 'generic/platform=iOS' build
```

Keine Tests, kein Linter.

## Code-Struktur

Alle `.swift`-Dateien flach in `abstand/` — keine Unterordner.

### Schlüssel-Dateien

| Datei | Zweck |
|---|---|
| `abstandApp.swift` | Einstieg: `@main`, inject `AppModel` als `@EnvironmentObject` |
| `AppModel.swift` | God `@MainActor ObservableObject`: API-Client, Playback, Downloads, gesamter UI-State |
| `MainRootView.swift` | `TabView` mit Home/Books/Podcasts/Search/Settings, alle NavigationStacks |
| `ABSAPIClient.swift` | `actor` — sämtliche Audiobookshelf-API-Aufrufe |
| `PlaybackController.swift` | `@MainActor ObservableObject` um `AVPlayer` |
| `DownloadManager.swift` | `@MainActor ObservableObject`, sequentielles Track-Download |
| `ABSModels.swift` | Alle API-Modelle mit `ABS`-Prefix |
| `AppTheme.swift` | Farben (`background`, `card`, `accent` …) und Layout-Konstanten |
| `ABSJSON.swift` | `decoder()` / `encoder()` mit `convertFromSnakeCase` |
| `LibraryDiskCache.swift` | JSON-Cache auf Disk (Server-Antworten, Progress) |
| `CoverImageCache.swift` | Ein Cover-Bild-Cache pro Account |
| `LoginView.swift` | Login-Screen |
| `MiniPlayerView.swift` | Floating-Player-Bar + NowPlayingDetailView |

### Theme

```swift
AppTheme.background       // #121212
AppTheme.card             // #252525
AppTheme.accent           // #FBC02D (gelb)
```

Niemals `Color`-Literale oder andere Farben verwenden.

### Konventionen

- `ABSJSON.decoder()` / `ABSJSON.encoder()` statt `JSONDecoder()` / `JSONEncoder()` (snake_case)
- Inline-Kommentare sind auf Deutsch
- `ABSBook` wird sowohl für Hörbücher als auch für Podcast-Show-Stubs genutzt
- `progressLookupKey` (Format: `<libraryItemId>/ep/<episodeId>`) ist der kanonische Key in `progressByItemId`

## Bekannte Einschränkungen

- Simulator-Namen ändern sich mit Xcode-Versionen: `iPhone 17` für aktuelles Setup
- `ContentView.swift` ist ein unbenutzter Platzhalter (nur für Preview)
