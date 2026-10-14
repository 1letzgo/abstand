# abstand for Android

Kotlin/Compose port of the iOS app (same recipe as stashy and stede: a parallel native app that
mirrors the iOS code file by file, no KMP). The Audiobookshelf server is the shared backend.
What is language-neutral is shared 1:1:

- **Version:** `versionName` is read from `MARKETING_VERSION` in `../abstand.xcodeproj/project.pbxproj`;
  `versionCode` = `git rev-list --count HEAD`.
- **App icon:** generated from `abstand/Assets.xcassets/AppIcon.appiconset/8.png`.
- **Preference keys:** `data/Prefs.kt` `Keys` = iOS `AppModel.Keys` (identical `abstand_*` strings).
- **Wire formats:** API models, `download.json` manifests, transcript caches and Readium locators use
  the same field names as iOS.
- **Golden files:** `../shared/fixtures/` holds JSON samples and logic cases both platforms decode;
  the Android unit tests read them as test resources.

**Goal: behave and look as close to the iOS app as possible** — same tabs, order, labels (English
UI), defaults, spacing (`AppTheme.Layout` → `Tokens`). Android-native widgets (Material 3: top app
bars, navigation bar, cards, sheets) with the iOS structure. When porting a screen, read the Swift
view first and mirror its structure; name the iOS counterpart in the KDoc (`/** iOS: BookDetailView */`).

## Build

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
./gradlew assembleSideloadDebug testSideloadDebugUnitTest
./gradlew assembleSideloadRelease   # signed APK (needs the upload key, see below)
```

Build output lives outside iCloud (`~/Library/Caches/abstand-android/<checkout hash>`) — iCloud
sync breaks the dex merge. One directory per checkout, so git worktrees don't collide.

Signing: `~/Library/Application Support/abstand-signing/keystore.properties`
(`storeFile`, `storePassword`, `keyAlias`, `keyPassword`). Without it release builds are unsigned.
Debug builds use the same key when present, so debug and release install over each other.

Debug server for the emulator: `android/local.properties` (never committed)

```
abstand.debug.server=https://abs.example.org
abstand.debug.user=…
abstand.debug.password=…
```

## Flavors

| Flavor | Distribution |
|---|---|
| `sideload` | signed APK (current channel) |
| `play` | Google Play (prepared, no differences yet) |

## Layout (`app/src/main/java/de/letzgo/abstand/`)

| Android | iOS |
|---|---|
| `data/Prefs.kt` (`Prefs`, `Keys`, `Secrets`) | `UserDefaults`, `AppModel.Keys`, Keychain |
| `data/Net.kt` (`Net`, `LocalHosts`, `CustomHeadersStore`, `ServerUrl`) | `AbstandHTTPSession`, `AbstandTrustDelegate`, `AbstandCustomHeadersStore`, `normalizeServerURL` |
| `data/AbsJson.kt` | `ABSJSON` |
| `data/Models*.kt` | `ABSModels.swift` |
| `data/ApiClient.kt` | `ABSAPIClient` |
| `ui/Theme.kt`, `ui/components/` | `AppTheme`, `AppAppearance`, shared view building blocks |
| `ui/Icons.kt` | SF Symbols mapping |
| `ui/AppRoot.kt`, `ui/TabNavigation.kt` | `abstandApp` / `AppRootContainer` / `MainTabShellView` / `MainRootView` (tabs, per-tab `NavigationStack`) |
| `store/LocalLibraryModels.kt`, `store/LocalLibraryDao.kt` (Room, schema in `app/schemas/`) | `LocalLibraryModels.swift` (SwiftData `@Model`s, schema V4) |
| `store/LocalLibraryStore.kt` (`LocalLibraryStore`, `LocalLibraryStoreManager`) | `LocalLibraryStore.swift` |
| `store/LocalLibraryQueries.kt` | `LocalLibraryQueries` (in `LocalLibraryStore.swift`) |
| `store/LocalStoreMaintenance.kt` | `LocalStoreMaintenance.swift` |
| `store/AccountCacheDirectory.kt` | `AccountCacheDirectory.swift` |
| `store/ActiveLibraryIdsStore.kt` | `ActiveLibraryIdsStore.swift` |
| `store/EbookLocalStore.kt` | `EbookLocalStore.swift` |
| `store/CoverImageCache.kt` (`CoverImageCache`, `CoverImageLoader`, Coil fetcher) | `CoverImageCache.swift`, `CoverImageLoader.swift` |
| `ui/components/CoverImage.kt` | `CoverImageView.swift` (`CoverImageView`, `SquareCoverImageView`) |
| `model/AppModel.kt` (facade), `model/SessionParticipant.kt` (`MainTab`, extension points) | `AppModel` (split into stores) |
| `model/SessionStore.kt`, `model/SessionLogic.kt` | `AppModelSessionAuth.swift` + bootstrap/login/account/library parts of `AppModel.swift` |
| `ui/login/LoginScreen.kt` | `LoginView.swift` |
| `ui/login/ServerCustomHeadersEditor.kt` | `ServerCustomHeadersEditor.swift` |
| `ui/settings/SettingsAccountSections.kt` | Accounts/Account sections of `ServerAdminViews.swift` |
| `model/HomeStore.kt` (`HomeStore`), `model/HomeShelfLogic.kt` (pure, tested) | Home parts of `AppModel.swift` (`startShelves`, `loadStartDashboard`, Continue listening/reading, New episodes, `startCategoryOrder`/`startDisabledCategories`/`homeBrowseCategory`, `progressByItemId`) |
| `model/SearchStore.kt`, `model/SearchLogic.kt` (pure, tested) | search parts of `AppModel.swift` (`scheduleUnifiedSearch`, `performSearch`, `performPodcastLibrarySearch`, local-first results) |
| `model/PlaybackLauncher.kt` (`PlaybackLauncher`, `NowPlayingState`, `DownloadStatusSource`) | card → player/download bridge (`model.play`, `player.$isPlaying`, `LibraryBookRowLiveState` download flags) |
| `ui/home/HomeDashboardViews.kt` | `HomeDashboardViews.swift` (`HomeTabRootView`, `StartDashboardView`, Home carousels) |
| `ui/home/HomeCompactCards.kt` | `HomeCompactCards.swift` |
| `ui/home/ContinueListeningHeroViews.kt` | `ContinueListeningHeroViews.swift` + `ContinueListeningHeroBookCard`/`…PodcastCard` (LibraryCardViews.swift) |
| `ui/home/HomeCardSupport.kt` | `LibraryRowLayout`, `LibraryRowCollapsedMetaLine`, `ContinueListeningHeroCoverPill`, cover-tint placeholder |
| `ui/home/HomeShelfSettings.kt` | `SettingsAppearanceHomeView` (ServerAdminViews.swift) |
| `ui/components/BrowseStrip.kt` | `AbstandExpandingDockBrowseStrip.swift` (`AbstandPinnedBrowseStrip`, dropdown pills), `AbstandFixedBrowseStripSectionsLayout` (AppTheme.swift) |
| `ui/browse/BrowseFacetSections.kt` | `MainRootBrowseSections.swift`, `BrowseEntityRowCard`/`FacetBrowseTileCard`, `BooksBrowseSection` |
| `ui/search/SearchTabViews.kt` | `SearchTabViews.swift` |
| `ui/destinations/Destinations.kt` | detail `navigationDestination` targets (placeholders until the detail screens are ported) |

(Extended as screens are ported.)

## Conventions

- JSON only through `AbsJson.decoder` / `.encoder` / `.decoderListeningStats` — never `Json { }`.
- Network only through `Net.client` / `Net.imageClient` (LAN self-signed TLS, custom headers per
  server origin, bearer for the active server) and `ApiClient` for API calls.
- Colours only from the palette (`Theme.palette`, accent); spacing only from the tokens.
- Local persistence: one Room DB per account (`filesDir/ABStandLocalStore/accounts/<sha>/users/<sha>/`),
  file caches under `filesDir/ABStandLibraryCache/…` (same scheme as iOS). Playback tick → `upsertProgress`;
  `replaceAllProgress` only for a full server sync.
- New domain stores hook into bootstrap/login/account switching via `SessionParticipant`
  (`AppModel.register` before `start()`), never by adding catalog/home logic to `SessionStore`.
- `AppModel` is not ported as one object: state lives in focused stores (session, catalog,
  podcasts, home, player, stats) exposing `StateFlow`s, method names follow iOS.
- Inline comments German, user-facing strings English (like iOS).
