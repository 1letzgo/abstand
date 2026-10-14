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
| `player/PlaybackController.kt`, `player/PlaybackTimeline.kt`, `player/SleepTimer.kt` | `PlaybackController` (+ `SleepTimerMode`, `ABSPlaybackSkipDefaults`, sleep menu presets) |
| `player/BookTimelinePlayer.kt`, `player/AbstandPlaybackService.kt`, `player/CoverBitmapLoader.kt` | `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter`, `AudioSessionController`, `CarPlaySceneDelegate` |
| `player/AutoBrowseTree.kt` | `CarPlayCoordinator` (Android Auto browse tree) |
| `player/AudioEq.kt` | `AudioEQProcessor` (`AudioEQPreset`, biquads → Media3 `AudioProcessor`) |
| `player/PlaybackHost.kt`, `player/PlaybackHostBridge.kt`, `player/PendingOfflineListening.kt` | `AppModel` player wiring (progress, completion, smart download, offline listening seconds) |
| `downloads/DownloadManager.kt`, `downloads/DownloadQueue.kt`, `downloads/DownloadWorker.kt` | `DownloadManager` (WorkManager `dataSync` worker) |
| `downloads/PodcastAutoDownloadInterval.kt` | `PodcastAutoDownloadSchedule` |
| `downloads/DownloadMaintenance.kt` | `LocalStoreMaintenance.removeStaleDownloadTempFiles` |
| `ui/AppRoot.kt` | `abstandApp` / `AppRootContainer` / `MainTabShellView` |
| `logic/FoundationText.kt` | Foundation string semantics (`folding`, `CharacterSet`, `Character`) used by the alignment |
| `logic/EbookReadAlong.kt` (`ReadAlongText`, `EbookReadAlongIndex`, `EbookNarrationJump`) | `EbookReadAlong.swift` (index + narration-jump logic of `EbookNarrationJumpController`), `TeleprompterEbookText.swift` (index input) |
| `logic/EbookAudioAlignment.kt` | `EbookAudioAlignment.swift` (builder, gap aligner, `a<track>-<locale>.bin`) |
| `logic/PlayerTranscriptCacheStore.kt` | `PlayerTranscriptCacheStore.swift`, `PlayerTranscriptWord`/`PlayerTranscriptLine` |
| `logic/PlayerTranscriptLibrary.kt` | `PlayerTranscriptLibrary.swift` (cache access, merge chain, recap text), `EbookAlignmentStore.loadOrBuild` |
| `logic/PlayerTranscriptLineAccumulator.kt` | `PlayerTranscriptLineAccumulator.swift` |
| `logic/PlayerTranscriptTeleprompter.kt` | `PlayerTranscriptTeleprompter.swift` metrics, timeline/merge parts of `PlayerLiveTranscriptionController`, `PlayerTranscriptWordLookup.swift` (pure parts) |
| `logic/speech/SpeechTranscriptionLocaleResolver.kt` | `SpeechTranscriptionLocaleResolver.swift`, `SpeechTranscriberAvailability.swift` (Vosk catalog instead of `SpeechTranscriber`) |
| `logic/speech/SpeechModelCatalog.kt`, `SpeechModelStore.kt`, `PcmResampler.kt` | `SpeechTranscriber` locales / `AssetInventory`, `PlayerTranscriptionAudioConverter` (from stashy) |
| `logic/ListeningAchievements.kt` | `ListeningAchievements.swift` (model, not the card view) |
| `logic/StatsLogic.kt` | pure parts of `StatsTabView.swift` / `StatsHeatmapViews.swift` (heatmaps themselves: `data/ModelsStats.kt`) |
| `logic/ContinueHeroTintCache.kt` | `ContinueHeroTintCache.swift`, colour math of `DetailHeroViews.swift` |
| `logic/CatalogBrowseTypes.kt` | `CatalogBrowseTypes.swift`, `BooksLibraryToolbarSnapshot` (`LibraryToolbarState.swift`) |
| `logic/LibraryRowLiveState.kt` | `LibraryRowLiveState.swift` (pure parts) |

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
- Playback: one process-wide `PlaybackController.shared(context)` (iOS `AppModel.player`), main thread
  only. ExoPlayer plays a book's tracks as a playlist; the MediaSession sees the whole book as one item
  with the global timeline (`BookTimelinePlayer`). Audio focus / becoming-noisy are ExoPlayer's — no
  extra session activation logic. App state reaches the player only through `PlaybackHost`,
  `BrowseSource` (Android Auto) and `DownloadHost`.
- Downloads: `filesDir/Downloads/<storage id>/` with `download.json` byte-identical to iOS
  (`shared/fixtures/download_manifest.json`); the queue is persisted and run by one WorkManager worker.
