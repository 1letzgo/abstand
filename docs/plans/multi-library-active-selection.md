# Plan: Mehrere aktive Libraries (Settings, Library-Dropdown, Continue Listening)

> Status: **implementiert** auf Branch `cursor/multi-library-plan-c089` (Phasen 0–4).

## Ziel

Heute gibt es zwei feste Slots: eine Books-Library und eine Podcasts-Library. Die Library-Ansicht schaltet zwischen den Medientypen um; Continue Listening und Home filtern auf genau diese beiden IDs.

Zielbild:

1. **Alle Server-Libraries** aus `GET /api/libraries` nutzen können.
2. In **Settings** alle Libraries sehen, **aktivieren/deaktivieren** und **Reihenfolge** festlegen.
3. In der **Library-Ansicht** statt Binary-Umschalter (Audiobooks/Podcasts) ein **Dropdown** zur Auswahl der Library.
4. **Continue Listening** holt/filtert Daten von **allen aktiven** Libraries, nicht nur von zwei Slots.

---

## Ist-Zustand (kurz)

| Bereich | Heute |
|---|---|
| Persistenz | `abstand_books_library_id` / `abstand_podcasts_library_id` (+ Sentinel `__abstand_no_library__`); pro Account in `ABSStoredAccount` |
| Settings | Zwei Picker: „Books library“ / „Podcasts library“ inkl. „None“ (`SettingsAccountView` in `ServerAdminViews.swift`) |
| Library-UI | `mediaCatalogKind` + `AbstandExpandingDockBinarySwitch` über `visibleMediaCatalogKinds` |
| Katalog | Eine aktive Books- bzw. Podcasts-Library → `reloadLibrary` / `reloadPodcastLibrary` |
| Continue Listening | `GET /api/me/items-in-progress` (global), danach Filter auf `selectedBooksLibrary` / `selectedPodcastLibrary` |
| Home-Regale | `GET /api/libraries/:id/personalized` nur für `selectedBooksLibrary` |
| Modell | `ABSLibrary` mit `mediaType` (`book` / `podcast`), `displayOrder` |

Zentrale Stellen: `AppModel.swift` (`selectedBooksLibrary`, `selectedPodcastLibrary`, `loadStartDashboard`, `inProgressAudiobookCandidates`, `inProgressPodcastEpisodeCandidates`, `purgeForeignContinueListeningItems`), `MainRootView.swift`, `ServerAdminViews.swift`, `ABSStoredAccount.swift`.

---

## Zielmodell

### Zwei getrennte Konzepte

1. **Aktive Libraries** (Settings)  
   Geordnete Liste aller bekannten Server-Libraries inkl. `enabled`.  
   Steuert Continue Listening, Download-Zugehörigkeit zum Account-Kontext, Sichtbarkeit im Library-Dropdown.

2. **Fokussierte Library** (Library-Tab)  
   Die gerade im Katalog angezeigte Library.  
   Steuert Katalog-Load, Browse-Sections, Navigation-Titel.

Medientyp (Book vs. Podcast) leitet sich aus `ABSLibrary.mediaType` der fokussierten Library ab — kein separater Binary-Kind-Switcher mehr nötig.

### Persistenz-Vorschlag

Neues account-gebundenes Preference-Modell, z. B.:

```swift
struct LibraryActivationPreference: Codable, Identifiable, Equatable {
  var libraryId: String
  var enabled: Bool
  var sortOrder: Int
  var id: String { libraryId }
}
```

Speicherorte:

- UserDefaults-Key z. B. `abstand_library_activations` (JSON-Array)
- `ABSStoredAccount`: neues Feld `libraryActivations: [LibraryActivationPreference]?` (oder kompakte Variante: `enabledLibraryIdsOrdered: [String]`)

Migration von Altbestand:

| Alt | Neu |
|---|---|
| `booksLibraryId` gesetzt | diese Library `enabled = true` |
| `podcastsLibraryId` gesetzt | diese Library `enabled = true` |
| Sentinel „None“ für Books/Podcasts | keine Library dieses Typs aktiv |
| übrige Server-Libraries | **ebenfalls `enabled = true`** (passt zu „alle Libraries nutzen“); Reihenfolge: zuerst bisherige Books-, dann Podcasts-Auswahl, danach Rest nach Server-`displayOrder` |
| fehlende Preference | nach erstem `libraries()`-Fetch: alle Libraries aktiv, Sortierung = Server-`displayOrder` |

Alte Keys vorerst als Fallback lesen, danach auf neues Modell schreiben (`migrateLibraryActivationsIfNeeded`).

### AppModel-State (inkrementell)

Nicht in einem Rutsch alle `selectedBooksLibrary`/`selectedPodcastLibrary`-Aufrufe entfernen — zu invasiv.

Stattdessen:

```text
libraries: [ABSLibrary]                          // Serverliste
libraryActivations: [LibraryActivationPreference]
activeLibraries: [ABSLibrary]                    // enabled ∩ libraries, nach sortOrder
focusedLibrary: ABSLibrary?                      // Katalog-Auswahl
```

Kompatibilitäts-Layer (Übergang):

- `selectedBooksLibrary` = fokussierte Book-Library **oder** letzte aktive Book-Library
- `selectedPodcastLibrary` = fokussierte Podcast-Library **oder** letzte aktive Podcast-Library

Viele bestehende Katalog-/Detail-Pfade bleiben so vorerst lauffähig. Continue Listening und Settings nutzen explizit `activeLibraries` / `activeLibraryIdSet`.

`activeLibraryIdSet()` heute mischt bereits selektierte IDs **und alle** `libraries` (für Downloads). Nach Umbau: **nur noch aktivierte** IDs — sonst greifen Deaktivierungen nicht.

---

## UI

### Settings

Ersetzt die beiden Picker („Books library“ / „Podcasts library“) durch **eine** Section „Libraries“:

- Liste aller Libraries vom Server (Name + Media-Type-Hinweis)
- Toggle aktiv/inaktiv
- Drag-Reorder für `sortOrder`
- Leerer Server: bestehender Empty-State-Text
- Offline: Liste aus lokalem `LocalLibrariesSnapshot`; Änderungen lokal speichern, Sync bei nächstem Online-Fetch reconcilen (unbekannte IDs behalten, neue Libraries default aktiv ans Ende)

Optional später: „None“-Äquivalent = alle Toggles aus → Library-Tab leer / Fallback auf Start.

`showPodcastsTab` kann abgeleitet werden: `activeLibraries.contains(where: \.isPodcastLibrary)` — separaten Schalter entfernen oder nur noch als Legacy-Cache nutzen.

### Library-Ansicht

Ersetzt `AbstandExpandingDockBinarySwitch` / `mediaKindStripItems` durch ein **Dropdown** (an `AbstandBrowseStripIconMenu` oder neues `LibraryPickerMenu` angelehnt):

- Optionen = `activeLibraries` in Settings-Reihenfolge
- Auswahl setzt `focusedLibrary` und lädt den passenden Katalog neu
- Secondary Strip (Books-Browse / Podcast-Shows) bleibt unverändert und hängt am Medientyp der fokussierten Library
- Navigation-Titel: Library-Name (oder Name + Typ), nicht mehr nur „Audiobooks“/„Podcasts“
- Bei nur einer aktiven Library: Dropdown ausblenden oder disabled anzeigen (wie heute bei einem sichtbaren Kind)

`mediaCatalogKind` wird abgeleitet aus `focusedLibrary?.isPodcastLibrary` bzw. bleibt als internes Mapping für bestehende `switch`-Zweige.

---

## Continue Listening

### Datenquellen

| Quelle | Rolle nach Umbau |
|---|---|
| `GET /api/me/items-in-progress` | bleibt global; Filter auf **aktive** Library-IDs |
| lokaler Fortschritt / Downloads | Kandidaten aus allen aktiven Libraries |
| `GET /api/libraries/:id/personalized` | **nicht** zwingend Teil dieses Features; Continue Listening hängt nicht daran |

### Code-Änderungen (Kern)

In `AppModel`:

1. `inProgressAudiobookCandidates(from:)` — Filter `libraryId ∈ activeBookLibraryIds` (statt `== selectedBooksLibrary.id`); Items ohne `libraryId` nur behalten, wenn eindeutig zuordenbar / bisherige Toleranz bewusst dokumentieren.
2. `inProgressPodcastEpisodeCandidates(from:)` — analog mit `activePodcastLibraryIds`.
3. `localContinueAudiobookBookCandidates()` / `localContinuePodcastEpisodeCandidates()` — gleiche ID-Mengen.
4. `purgeForeignContinueListeningItems()` — gegen aktive Menge filtern, nicht gegen die zwei Slot-IDs.
5. `activeLibraryIdSet()` — nur aktivierte Libraries (Download-Zugehörigkeit konsistent halten).
6. Merge/Sort/Dedupe der bestehenden Continue-Shelf-Pipeline unverändert lassen (`makeContinueListeningShelf`, `ABSStartShelfMergedRow.merged`).

### Laden

`loadStartDashboard` braucht für Continue Listening **keinen** N-fachen Personalized-Call.  
`items-in-progress` einmal laden + gegen aktive IDs filtern reicht.

Optional (eigener Folge-Schritt, nicht blockierend): Personalized-Regale (Continue Series, Recommended, …) über mehrere Book-Libraries mergen — separates Scope-Item.

### Offline / Cache

`LocalHomeShelvesSnapshot` ist heute an `selectedBooksLibrary.id` gebunden. Für Continue Listening reicht oft Rebuild aus lokalem Progress.  
Mindestens: Cache-Key oder Merge so anpassen, dass Continue-Items anderer aktiver Libraries nach Deaktivieren verschwinden und nach Aktivieren wieder erscheinen (Force-Refresh / `repairContinueListeningShelfFromLocalProgressOnly`).

---

## Phasen

### Phase 0 — Datenmodell & Migration

- `LibraryActivationPreference` (+ Encoding)
- UserDefaults + `ABSStoredAccount`-Feld
- `migrateLibraryActivationsIfNeeded()` aus Books/Podcasts-IDs
- Reconcile nach `libraries()`-Fetch (neue IDs anhängen, entfernte IDs droppen)
- Unit-/Smoke-Tests für Migration und Reconcile (soweit Test-Harness vorhanden)

**Akzeptanz:** Bestehende Accounts behalten ihre bisherige Books-/Podcasts-Auswahl als aktiv; weitere Libraries sind aktiv und sortiert.

### Phase 1 — Continue Listening auf aktive Libraries

- Candidate-Filter + `purgeForeign…` + `activeLibraryIdSet` umstellen
- Manuell: zwei Book-Libraries + eine Podcast-Library → Continue zeigt Einträge aus allen aktiven; Deaktivieren entfernt sie nach Refresh

**Akzeptanz:** Continue Listening spiegelt die aktivierte Menge, unabhängig vom Library-Dropdown.

### Phase 2 — Settings-UI

- Section „Libraries“ mit Toggle + Reorder
- Alte Zwei-Picker entfernen
- Änderungen triggern Continue-Refresh und ggf. Focus-Clamp (`focusedLibrary` muss aktiv bleiben)

**Akzeptanz:** Reihenfolge und Toggles persistieren über App-Neustart und Account-Wechsel.

### Phase 3 — Library-Dropdown

- Binary-Switch durch Library-Dropdown ersetzen
- `focusedLibrary` treibt Katalog-Root (Books- vs. Podcasts-Shell)
- `visibleMediaCatalogKinds` / `clampMediaCatalogKindIfNeeded` an aktive Libraries anbinden
- CarPlay / Deep-Links / `navigateToMedia`: auf Focus oder erste aktive Library des Typs mappen

**Akzeptanz:** Umschalten zwischen ≥2 aktiven Libraries (auch gleiches Medium) funktioniert; Secondary Browse-Strip bleibt korrekt.

### Phase 4 — Aufräumen

- Tote Zwei-Slot-Picker-APIs entfernen oder auf Kompatibilitäts-Layer reduzieren
- README-Claim „two libraries at once“ aktualisieren
- Optional: Personalized-Home über mehrere Book-Libraries

---

## Risiken & Entscheidungen

| Thema | Empfehlung |
|---|---|
| Default für bisher ungenutzte Libraries | alle aktiv (Feature-Intent) |
| Mehrere Book-Libraries im Katalog | Dropdown wählt **eine** fokussierte Library; kein gemischter Katalog |
| Continue Listening UI | ein gemischtes Regal (wie heute), sortiert nach `lastUpdate` |
| Personalized-Home | vorerst eine Primary-Book-Library (Focus oder erste aktive Book-Library); Merge später |
| `showPodcastsTab` | ableiten aus aktiven Podcast-Libraries |
| Guest / keine Libraries | Library-Tab wie heute → Start |
| Performance Continue | ein Request (`items-in-progress`); kein N× personalized für Continue |

---

## Betroffene Dateien (erwartet)

- `abstand/AppModel.swift` — State, Migration, Continue-Filter, Focus
- `abstand/ABSStoredAccount.swift` — Persistenz
- `abstand/ServerAdminViews.swift` — Settings-Section
- `abstand/MainRootView.swift` — Dropdown statt Binary-Switch
- `abstand/AbstandExpandingDockBrowseStrip.swift` — ggf. neues Picker-Control
- `abstand/LibraryToolbarState.swift` — Titel / Attach an Focus
- `abstand/LocalLibraryModels.swift` / `LocalLibraryStore.swift` — Cache-Keys falls nötig
- `abstand/CarPlayCoordinator.swift` — Mapping auf aktive/fokussierte Libraries
- `README.md` — Produktbeschreibung

---

## Explizit außerhalb dieses Plans

- Gemischter Multi-Library-Katalog in einer Liste
- Server-seitiges Umbenennen/Löschen von Libraries (Admin bleibt wie heute)
- Änderungen am ABS-Server-API-Vertrag
- Vollständiges Personalized-Shelf-Merging über N Book-Libraries (Folge-Issue)

---

## Umsetzungs-Checkliste (Kurz)

1. Preference-Modell + Migration
2. Continue Listening Filter → aktive IDs
3. Settings: Liste, Toggle, Reorder
4. Library: Dropdown + Focus
5. Clamp/Navigation/CarPlay anpassen
6. Legacy-Picker entfernen, Docs aktualisieren
