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

**The Android app is its own product and the UI test bed:** layout/design ideas are tried here first and may diverge from iOS; proven ones are collected in `UI_IDEAS_FOR_IOS.txt` and ported to iOS later. Logic, data, API and bug fixes stay in parity with iOS.

**Baseline: behave like the iOS app, look like a standard Material 3 app** — same screens (exception: no tab bar — Home is the only root, Books/Podcasts live in the Home library bar, Search/Settings are pushed), order, labels
(English UI), defaults, features, accent and screen structure as iOS; colors are a Material 3
scheme generated from the iOS accent (accent = seed = `primary`, see `UI_TEMPLATES.txt` → "Material 3 colors"); dimensions, spacing,
typography and component sizes follow **Material 3** (4-dp grid, 48-dp touch targets, M3 type
scale). The token *names* stay the iOS ones (`AppTheme.Layout.rowSpacing`, `cardPadding`, …) so call
sites remain comparable; only their Android values differ (table: `UI_TEMPLATES.txt` → "Material 3
metrics"). Android-native widgets (top app bars, navigation bar, cards, sheets) with the iOS structure. When porting a screen, read the Swift
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

## Releases (GitHub, in-app update)

Android builds are published as GitHub releases of the public repo `1letzgo/abstand`, tag
`abstand-android-<versionCode>`, one `.apk` asset — the app (`data/AppUpdate.kt`, `sideload` flavor
only) checks them on launch (at most every 6 h) and under Settings › Debug › App, downloads the APK,
verifies the GitHub SHA-256 digest and hands it to the package installer (same logic as stede).

1. Commit everything, `./gradlew assembleSideloadRelease` (R8-minified, signed with the stable
   debug key `~/.android/debug.keystore` — never change it, or installed apps reject the update).
2. `versionCode` = commit count, so every new commit yields a higher code; never reuse a tag.
3. Push `main`, then
   `gh release create abstand-android-<code> abstand-<versionName>-<code>.apk --repo 1letzgo/abstand --target main --title "abstand <versionName> (<code>) – Android" --notes "<short German changelog>"`.
4. Verify the asset digest (`gh release view … --json assets`) equals the local `shasum -a 256`.

The `play` flavor (Google Play) never checks GitHub and is signed with the upload key.

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
| `ui/Theme.kt`, `ui/components/` | `AppTheme`, `AppAppearance`, shared view building blocks (UI templates, see Conventions + `UI_TEMPLATES.txt`) |
| `ui/components/Menus.kt`, `Overlays.kt`, `Pills.kt`, `Progress.kt`, `Rows.kt` | SwiftUI `Menu`/`Picker(.menu)`, `.alert`/`.sheet`, cover pills/badges/chips, `ProgressView`, list rows/segmented `Picker` |
| `ui/Icons.kt` | SF Symbols mapping |
| `ui/AppRoot.kt`, `ui/TabNavigation.kt` | `abstandApp` / `AppRootContainer` / `MainTabShellView` / `MainRootView` (tabs, per-tab `NavigationStack`) — Android: no tab bar, one navigator with Home as root; Search/Settings are pushed (`ShellRoute` requests from `SessionStore.openSearch()/openSettings()/openHome()`) |
| `store/LocalLibraryModels.kt`, `store/LocalLibraryDao.kt` (Room, schema in `app/schemas/`) | `LocalLibraryModels.swift` (SwiftData `@Model`s, schema V4) |
| `store/LocalLibraryStore.kt` (`LocalLibraryStore`, `LocalLibraryStoreManager`) | `LocalLibraryStore.swift` |
| `store/LocalLibraryQueries.kt` | `LocalLibraryQueries` (in `LocalLibraryStore.swift`) |
| `store/LocalStoreMaintenance.kt` | `LocalStoreMaintenance.swift` |
| `store/AccountCacheDirectory.kt` | `AccountCacheDirectory.swift` |
| `store/ActiveLibraryIdsStore.kt` | `ActiveLibraryIdsStore.swift` |
| `store/EbookLocalStore.kt` | `EbookLocalStore.swift` |
| `store/CoverImageCache.kt` (`CoverImageCache`, `CoverImageLoader`, Coil fetcher) | `CoverImageCache.swift`, `CoverImageLoader.swift` |
| `ui/components/CoverImage.kt` | `CoverImageView.swift` (`CoverImageView`, `SquareCoverImageView`) |
| `model/AppModel.kt` (facade), `model/SessionParticipant.kt` (`ShellRoute` ≙ `MainTab`, extension points) | `AppModel` (split into stores) |
| `model/SessionStore.kt`, `model/SessionLogic.kt` | `AppModelSessionAuth.swift` + bootstrap/login/account/library parts of `AppModel.swift` |
| `ui/login/LoginScreen.kt` | `LoginView.swift` |
| `ui/login/ServerCustomHeadersEditor.kt` | `ServerCustomHeadersEditor.swift` |
| `ui/settings/SettingsAccountSections.kt` | Accounts/Account sections of `ServerAdminViews.swift` |
| `player/PlaybackController.kt`, `player/PlaybackTimeline.kt`, `player/SleepTimer.kt`, `player/LocalAwareMediaSourceFactory.kt` | `PlaybackController` (+ `localTrackAsset(url:)`, `SleepTimerMode`, `ABSPlaybackSkipDefaults`, sleep menu presets) |
| `player/BookTimelinePlayer.kt`, `player/AbstandPlaybackService.kt`, `player/CoverBitmapLoader.kt` | `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter`, `AudioSessionController`, `CarPlaySceneDelegate` |
| `player/AutoBrowseTree.kt` | `CarPlayCoordinator` (Android Auto browse tree) |
| `player/LocalDownloadSwitch.kt` | decision part of `AppModel.applyLocalPlaybackIfDownloadMatchesCurrent` (switch to local files when the streamed item's download finishes) |
| `player/AudioEq.kt` | `AudioEQProcessor` (`AudioEQPreset`, biquads → Media3 `AudioProcessor`) |
| `player/PlaybackHost.kt`, `player/PlaybackHostBridge.kt`, `player/PendingOfflineListening.kt` | `AppModel` player wiring (progress, completion, smart download, offline listening seconds) |
| `downloads/DownloadManager.kt`, `downloads/DownloadQueue.kt`, `downloads/DownloadWorker.kt` | `DownloadManager` (WorkManager `dataSync` worker) |
| `downloads/PodcastAutoDownloadInterval.kt` | `PodcastAutoDownloadSchedule` |
| `downloads/DownloadMaintenance.kt` | `LocalStoreMaintenance.removeStaleDownloadTempFiles` |
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
| `model/PodcastStore.kt` (`PodcastStore`, `PodcastDirectoryState`, `PodcastShowAdminState`) | `AppModelCatalogPodcasts.swift`, `AppModelPodcastDirectory.swift`, podcast parts of `AppModel.swift` |
| `model/PodcastLogic.kt` (`PodcastLogic`, `PodcastCatalogSortField`, `PodcastEpisodeSortField`, `PodcastAutoDownloadInterval`) | static podcast helpers in `AppModel.swift`, `CatalogBrowseTypes.swift`, `PodcastAutoDownloadSchedule.swift` |
| `ui/podcasts/PodcastActions.kt` | player/download bridge (`playPodcastEpisode`, `startDownloadPodcastEpisode`, `downloadedItemIds`) |
| `ui/podcasts/PodcastsBrowseSection.kt` | podcasts root content in `MainRootView.swift` + `PodcastCatalogToolbarContent` (`LibraryToolbarState.swift`) — Android: list builder + toolbar for the Home library bar (no Podcasts tab) |
| `ui/podcasts/PodcastEpisodeRows.kt` | `PodcastEpisodeRowCard` (`LibraryCardViews.swift`; badges/play pill via `AbstandStatusBadges`/`AbstandPlayPill`) |
| `ui/podcasts/PodcastTabSheets.kt` | `PodcastTabSheets.swift` (Add podcast: search, charts, storefront) + `AbstandCatalogSortToolbarMenu` |
| `ui/podcasts/PodcastDirectoryShowView.kt` | `PodcastDirectoryShowView.swift` |
| `ui/podcasts/PodcastEpisodeDetailView.kt`, `ui/podcasts/PodcastDetailComponents.kt` | `PodcastEpisodeDetailView.swift`, detail building blocks from `DetailHeroViews.swift` |
| `ui/podcasts/PodcastShowSettingsScreen.kt` | `ServerAdminPodcastShowView` + `PodcastRssFeedDraftRow` (`ServerAdminViews.swift`, `LibraryCardViews.swift`) |
| `model/HomeStore.kt` (`HomeStore`), `model/HomeShelfLogic.kt` (pure, tested) | Home parts of `AppModel.swift` (`startShelves`, `loadStartDashboard`, Continue listening/reading, New episodes, `startCategoryOrder`/`startDisabledCategories`/`homeBrowseCategory`, `progressByItemId`) |
| `model/SearchStore.kt`, `model/SearchLogic.kt` (pure, tested) | search parts of `AppModel.swift` (`scheduleUnifiedSearch`, `performSearch`, `performPodcastLibrarySearch`, local-first results) |
| `model/PlaybackLauncher.kt` (`PlaybackLauncher`, `NowPlayingState`, `DownloadStatusSource`) | card → player/download bridge (`model.play`, `player.$isPlaying`, `LibraryBookRowLiveState` download flags) |
| `ui/home/HomeDashboardViews.kt` | `HomeDashboardViews.swift` (`HomeTabRootView`, `StartDashboardView`, Home carousels) — Android: Home is the combined library view (title row with Offline/Search/Settings, Continue-listening pager, sticky library bar with Books + Podcasts and the remaining shelves in its section menu) |
| `model/HomeLibraryLogic.kt` (pure, tested) | — (Android-only: combined Books/Podcasts library choice of the Home library bar) |
| `ui/home/HomeCompactCards.kt` | `HomeCompactCards.swift` |
| `ui/home/ContinueListeningHeroViews.kt` | `ContinueListeningHeroViews.swift` + `ContinueListeningHeroBookCard`/`…PodcastCard` (LibraryCardViews.swift) |
| `ui/home/HomeCardSupport.kt` | cover-tint placeholder, author image, live-state helpers (`LibraryRowLayout` lives in `ui/library/LibraryCards.kt`, `LibraryRowCollapsedMetaLine` and cover pills in `ui/components/`) |
| `ui/home/HomeShelfSettings.kt` | `SettingsAppearanceHomeView` (ServerAdminViews.swift) |
| `ui/components/BrowseStrip.kt` | `AbstandExpandingDockBrowseStrip.swift` (`AbstandPinnedBrowseStrip` → `AbstandBrowsePills`), `AbstandFixedBrowseStripSectionsLayout` (AppTheme.swift) |
| `ui/search/SearchTabViews.kt` | `SearchTabViews.swift` — Android: `SearchDestination` pushed from the Home header (no Search tab) |
| `ui/destinations/Destinations.kt` | Home/Search `navigationDestination` targets → `ui/detail/` screens, `PodcastEpisodeDetailView`, show filter in the Home library bar |
| `model/AppSettings.kt` (`AppSettings`, `TranslationTargetLanguage`) | simple `@Published` settings of `AppModel`, `TranslationTargetLanguage` (`AppAppearance.swift`); no card-style setting on Android (`LibraryBookCardStyle`/`LibraryPodcastCardStyle` have no counterpart — only the compact row exists) |
| `model/AdminStore.kt` (`AdminStore`, `AdminLogic`) | server-admin part of `AppModel` (users, library stats/scan, M4B encode + polling, media-cache purge, `changeAccountPassword`) |
| `model/StatsStore.kt` (`StatsStore`, `StatsLogicExt`) | listening-stats part of `AppModel` (`loadListeningStats`, achievements snapshot, stats navigation stubs) |
| `data/AdminSocketClient.kt` (`AdminSocketClient`, `AdminSocketProtocol`) | `ABSAdminSocketClient.swift` (OkHttp WebSocket) |
| `ui/settings/SettingsHub.kt`, `SettingsIconStrip.kt` | `SettingsHubRootView`, `SettingsHubSection`, `SettingsIconStrip` (`ServerAdminViews.swift`) — Android: `SettingsDestination` pushed from the Home header (no Settings tab) |
| `ui/settings/SettingsAccountSections.kt`, `SettingsAccountPages.kt` | `SettingsAccountView`, `SettingsChangePasswordView` (+ Android-only connection/custom-headers page) |
| `ui/settings/SettingsAppearance.kt` | `SettingsAppearanceView`, `SettingsAppearanceHomeView`, `SettingsHomeShelfCard` |
| `ui/settings/SettingsPlayback.kt` | `SettingsPlaybackView` (Playback + Teleprompter) |
| `ui/settings/SettingsDownloads.kt` | Downloads/Cache hub sections, `SettingsDownloadsManageView`, `DownloadManageRow` |
| `ui/settings/DebugLog.kt` | `DebugLogCollector.swift`, `DebugLogExportView` (share via `ACTION_SEND`) |
| `ui/settings/SettingsIntegration.kt` | hooks into other stores (home shelves, transcript prefetch status, download removal) |
| `ui/admin/ServerAdminMenu.kt`, `ServerUsers.kt`, `ServerLibraries.kt`, `ServerM4B.kt` | `serverSettingsMenuSections`, `ServerUsersListView`, `ServerUserDetailView`, `ServerUserListeningSessionsView`, `ServerLibrariesListView`, `ServerLibraryDetailView`, `ServerM4BProgressView` |
| `ui/stats/StatsScreen.kt` | `StatsTabView.swift`, `SettingsStatsSectionView` |
| `ui/stats/StatsHeatmap.kt` | `StatsHeatmapViews.swift` (`ListeningMonthHeatmapCard`, `StatsTimelineMetricCard`) |
| `ui/stats/ListeningAchievementCard.kt` | `ListeningAchievementCard` (`ListeningAchievements.swift`) |
| `ui/metadata/MetadataActions.kt` | metadata/cover/chapter actions of `AppModel` (`applyMetadataMatch`, `applyCoverURL`, `applyItemChapters`, …) |
| `ui/metadata/EditMetadataSheet.kt`, `MatchMetadataSheet.kt`, `ChaptersEditorSheet.kt` | `EditMetadataSheet.swift`, `MatchMetadataSheet.swift`, `ChaptersEditorSheet.swift` |
| `ui/permissions/NotificationPermission.kt` | — (Android 13+ `POST_NOTIFICATIONS`, asked once — Settings root or first playback/download start) |
| `model/ProgressStore.kt` | `progressByItemId`/`bookmarks`, `applyUserProgress`/`mergedUserMediaProgress`, guard keys (local finished/discarded/pending sync), progress persistence of `AppModel.swift` |
| `model/CatalogStore.kt` (`CatalogStore`, `CatalogSortState`, `CatalogFilterState`, `BrowseListsState`) | catalog/browse parts of `AppModel.swift` + `AppModelCatalogPodcasts.reloadLibrary`, book actions (detail load, mark finished, reset, bookmarks, delete) |
| `model/EntityDetailLoader.kt` | `reloadEntityDetail`/`loadMoreEntityDetailIfNeeded`/`applyEntityDetailFromLocalCache` (per screen instead of shared `entityDetail*`) |
| `logic/CatalogLogic.kt`, `logic/BookDetailLogic.kt` | pure catalog/entity/detail helpers of `AppModel.swift`, `BookDetailView.swift`, `BookListeningDetailSections.swift` |
| `ui/library/BooksLibraryToolbar.kt`, `ui/library/BooksBrowseSections.kt` | `BooksLibraryToolbarContent` (`LibraryToolbarState.swift`), books root content of `MainRootView` / `MainRootBrowseSections.swift` — Android: list builder + toolbar for the Home library bar (no Books tab) |
| `ui/library/LibraryCards.kt` | `LibraryCardViews.swift` (book row only — no cover card on Android, browse entity row, facet tile, badges, play pills) |
| `ui/library/LibraryToolbarMenus.kt` | `LibrarySortToolbars.swift`, `LibraryFilterViews.swift` |
| `ui/library/LibraryPlayback.kt` | `AppModel.play(book:)`, `jumpToBookmark`, `continueHeroPlayPillToggle` |
| `ui/detail/BookDetailScreen.kt`, `ui/detail/BookDetailSections.kt` | `BookDetailView.swift`, `BookListeningDetailSections.swift`, `BookmarksUI.swift` |
| `ui/detail/DetailHeroViews.kt`, `ui/detail/CoverTint.kt` | `DetailHeroViews.swift` (hero, action bar, meta cards, toolbar download item, cover tint) |
| `ui/detail/EntityDetailScreen.kt`, `ui/detail/DetailDestinations.kt` | `BooksEntityDetailViews.swift`, `booksEntityDetailNavigation` / `navigationDestination`s |
| `transcript/PlaybackTranscriptionSupport.kt` (`PlaybackTranscription`, `PlayerTranscriptionAudioContext`) | transcription extension of `PlaybackController` (`transcriptionStorageId`, `transcriptionTrackKey`, `makeTranscriptionAudioContext`, `localTranscriptionTrackSources`, language override) |
| `transcript/PlayerTranscriptionAudioConverter.kt` | `PlayerTranscriptionAudioConverter.swift` + `AVAssetReader` part of `PlayerTranscriptProducer` (MediaExtractor/MediaCodec → 16 kHz mono) |
| `transcript/PlayerTranscriptProducer.kt` (`PlayerTranscriptProducer`, `VoskResult`) | `PlayerTranscriptProducer.swift` (Vosk instead of `SpeechAnalyzer`/`SpeechTranscriber`) |
| `transcript/PlayerTranscriptProduction.kt` | `PlayerTranscriptLibrary.produceAndPersist` / `transcriptText` (gap filling) |
| `transcript/PlayerLiveTranscriptionController.kt` (+ `TranscriptFollowPolicy`, `TranscriptWordMerge`) | `PlayerLiveTranscriptionController.swift` |
| `transcript/TranscriptionModelSelection.kt` | `SpeechTranscriptionLocaleResolver.resolve` + `ensureSpeechModel` (language → Vosk model) |
| `transcript/PlayerTranscriptPrefetcher.kt` (`PlayerTranscriptPrefetcher`, `PrefetchPlanner`, `TranscriptPrefetchWorker`) | `PlayerTranscriptPrefetcher.swift` (`BGProcessingTask` → WorkManager unique work `de.letzgo.abstand.transcripts`, charging + battery not low), `AppModel.downloadedTranscriptJobs` |
| `transcript/TeleprompterEbookText.kt` | `TeleprompterEbookText.swift` (`TeleprompterEbookTextProvider`; EPUB opening plugged in by the reader via `indexLoader`) |
| `transcript/TranscriptSettings.kt` (`TranscriptSettings`, `TranslationTargetLanguage`), `transcript/TranscriptAccount.kt`, `transcript/WordLookupLinks.kt` | Teleprompter section of `ServerAdminViews.swift`, `TranslationTargetLanguage` (AppAppearance.swift), `PlayerTranscriptCacheStore.activeAccount` |
| `ui/transcript/TranscriptTeleprompter.kt` (`TranscriptTeleprompter`, `TeleprompterFontSize`) | `PlayerTranscriptTeleprompter.swift` (`PlayerLiveTranscriptPanelView`) |
| `ui/transcript/TranscriptWordLookupSheet.kt` | `PlayerTranscriptWordLookup.swift` (sheet; Translate/Search the web instead of system dictionary/Translation) |
| `ui/transcript/TranscriptRecapSheet.kt` (`TranscriptRecapSheet`, `TranscriptRecapContent`) | `PlayerTranscriptRecapSheet.swift` (`PlayerTranscriptRecapCard`) |
| `model/PlayerWiring.kt` | player parts of `AppModel` (`playPodcastEpisode`, `restoreLastPlayedOnLaunch`, `markFinished` from playback, `dismissPlayer`, bookmark create/delete, `requestPresentNowPlayingSheet`, `syncOfflineProgressToServer` subset); implements `PlaybackHost`, `BrowseSource`, `PlaybackLauncher`, `PodcastActions` |
| `model/DownloadWiring.kt` | download parts of `AppModel` (`downloadedItemIds` per account, `persistDownloads`, `removeLocalDownload`, `downloadManifestBelongsToActiveAccount`); implements `DownloadHost`, `DownloadStatusSource` |
| `ui/player/MiniPlayer.kt`, `ui/player/PlayerChrome.kt` | `FloatingPlayerChrome.swift` (`TabAccessoryMiniPlayer`, `FloatingAccessoryGate`, snapshot), `MiniPlayerMetrics` |
| `ui/player/NowPlayingScreen.kt`, `ui/player/NowPlayingControls.kt`, `ui/player/NowPlayingPanels.kt` | `NowPlayingDetailView` in `MiniPlayerView.swift` (cover/panels, scrubbers, transport, utility bar, sleep/speed/EQ menus, chapters/bookmarks/description panels) |
| `ui/player/NowPlayingReadAlong.kt` | `ReadAlongPanelButton`, recap button, teleprompter ± (`MiniPlayerView.swift`) |
| `ui/player/NowPlayingPresenter.kt` | `NowPlayingZoomPresenter.swift` + `FullScreenOverlayPresenter` (zoom from the mini player, drag-to-dismiss) |
| `ui/player/AudioOutputSwitcher.kt` | `FullPlayerAirPlayButton` (`AVRoutePickerView` → system output switcher) |
| `ui/AppIntegration.kt` | cross-feature wiring (detail admin sheets, Stats navigation, `bookUpdated`, Settings hooks, transcript prefetch) |
| `reader/ReadiumReaderService.kt` (`ReadiumReaderService`, `EbookTextIndexProvider`) | `ReadiumReaderService.swift` (Readium Kotlin 3.1.2 streamer, initial locator, locator persistence, EPUB preferences), `TeleprompterEbookTextProvider.swift` + `EbookReadAlongIndex.build(publication:)` |
| `reader/ReaderProgressLogic.kt` (pure, tested) | `ReadiumReaderProgressInfo`, `ReadiumReaderDelegate.bookWidePageProgress`, `ServerPositionOffer`, eBook progress rules of `AppModel` |
| `reader/EbookProgressSync.kt` | eBook progress part of `AppModel` (`scheduleEbookProgressSync`, `flushEbookProgressSync`, `serverEbookFractionForReader`, `markEbookAsFinished`, `resetEbookReadingProgress`) |
| `reader/EbookReaderLauncher.kt` (`EbookReaderLauncher.open(itemId)`, `EbookReaderSession`) | `AppModel.openAttachedEbook`, `ebookReaderSession` / `EbookReaderPresentation` |
| `reader/EbookNarrationJumpController.kt` | `EbookNarrationJumpController` (EbookReadAlong.swift) |
| `ui/reader/ReaderScreen.kt` (`EbookReaderOverlay`, `ReaderScreen`, `EbookServerPositionBanner`) | `ReadiumReaderView.swift`, `fullScreenCover` in `MainRootView` |
| `ui/reader/ReaderNavigatorHost.kt` (`ReaderFragments`, `EpubNavigatorHost`) | `ReadiumNavigatorHost` / `ReaderNavigatorContainerViewController` |
| `ui/reader/PdfPageReader.kt` (`PdfDocumentSource`, `PdfPageReader`) | Readium `PDFNavigatorViewController` (Android: platform `PdfRenderer`, Readium has no PDF engine on Maven Central) |

(Extended as screens are ported.)

## Conventions

- JSON only through `AbsJson.decoder` / `.encoder` / `.decoderListeningStats` — never `Json { }`.
- Network only through `Net.client` / `Net.imageClient` (LAN self-signed TLS, custom headers per
  server origin, bearer for the active server) and `ApiClient` for API calls.
- Colours only from the palette (`Theme.palette`, accent); spacing only from the tokens. `Color(0x…)`
  literals live only in `ui/Theme.kt` / `ui/Palette.kt` (`UiTemplateLintTest` fails otherwise).
- **Material 3 metrics:** `AppTheme.Layout` keeps the iOS token names but carries M3 values (margins
  16 dp compact / 24 dp from 600 dp width via `tabPaddingH`, touch targets 48, list rows 56/72/88,
  cards 12-dp corners, chips 32, buttons 40, menus 48-dp items, dialogs/sheets 28-dp corners, top app
  bar 64, mini player 64) plus M3-only tokens (`cornerExtraSmall…cornerExtraLarge`, `iconSize`,
  `smallIconSize`, `buttonHeight`, `chipHeight`, `menuItemHeight`, `listItem*Height`, …). Screen-local
  `*Metrics` objects use multiples of 4 dp; `UiTemplateLintTest` fails on off-grid `.dp` literals
  outside `ui/components/`/`Theme.kt` (hairlines 0.5/1 dp allowed).
- **Typography:** `AppType` (`ui/Typography.kt`) = the M3 type scale (`MaterialTheme.typography`,
  Roboto); the KDoc maps each iOS Dynamic-Type role (`.headline` → `titleMedium`, `.subheadline` →
  `bodyMedium`, …). No `fontSize =`/`NN.sp` literals outside `Typography.kt` (lint).
- **UI templates — never hand-build menus, sheets or dialogs.** Every recurring element comes from
  `ui/components/` (inventory with former call sites: `android/UI_TEMPLATES.txt`). Material 3 widgets are
  used only inside those templates; `UiTemplateLintTest` fails on raw `DropdownMenu`, `AlertDialog`,
  `Dialog`, `ModalBottomSheet`, `IconButton`, `TextButton`, chips, `SegmentedButton`, progress
  indicators or text fields anywhere else.
  - Menus: `AbstandMenu(expanded, onDismiss) { section("Sort by") { … }; picker(options, selected, label, onSelect, title, icon); item(label, onClick, icon, selected, destructive, enabled); divider() }`,
    anchors `AbstandMenuButton(icon, description) { … }` (toolbar ⋮/sort/filter) and `AbstandMenuBox(anchor = { open -> … }) { … }`
    (pill/text/long-press anchors), one-liner pickers `AbstandPickerMenu` / `AbstandPickerValueMenu`,
    browse/library pills `AbstandDropdownPill`. Card surface, card corners, hero shadow, hairline edge,
    M3 metrics (48-dp items, 12-dp padding, 4-dp corners), accent checkmark for the selection, `AppTheme.danger` for destructive items.
  - Dialogs: `AbstandAlert(title, onDismiss, message)` (OK only), `AbstandConfirmDialog(title, confirmLabel, onConfirm, onDismiss, message, destructive = true)`,
    `AbstandDialog(…) { content }` for inputs (e.g. `AbstandInsetTextField`), `AbstandBlockingProgressDialog(text)`.
  - Sheets: `AbstandSheet(title, onDismiss, onConfirm, cancelLabel)` (bottom sheet with grabber), `MetadataSheetScaffold` (full-screen forms).
  - Buttons: `AbstandPrimaryButton`, `AbstandProminentButton` (`destructive`), `AbstandIconButton` (Plain/Tonal/Filled,
    container `iconButtonSize` 40 / `compactIconButtonSize` 32, always ≥ 48-dp touch target), `AbstandTextButton`, `AbstandPlayPill`.
  - Pills/badges/chips: `AbstandCoverPill(Icon|Text)`, `AbstandCoverCornerBadge`, `AbstandStatusBadges`,
    `AbstandBadge` (Neutral/Accent), `AbstandChip` (filter/category), `AbstandBrowsePills` / `AbstandDropdownPill` (library bar).
  - Progress/state: `AbstandProgressBar`, `AbstandCardBottomProgress`, `AbstandProgressRing`, `AbstandInlineSpinner`, `AbstandLoadingSpinner`,
    `AbstandLabeledLoadingState`, `AbstandEmptyScreen` / `AbstandSectionEmptyState` / `AbstandCardEmptyState`.
  - Rows/text: `AbstandListRow` (leading/below/trailing slots), `SettingsCard*Row`, `AbstandDivider`, `AbstandCapsLabel`,
    `TabContentSectionTitle`, `LibraryRowCollapsedMetaLine`, `AbstandSegmentedControl`.
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
- Read along: Vosk (`com.alphacephei:vosk-android`) like stashy's AI subtitles — speech models are
  downloaded only after an explicit tap (`filesDir/speech-models/`); transcripts use the iOS cache
  format/paths, keyed by the Vosk model's language tag (`de`, `en`, `en-GB` …). Call
  `TranscriptSettings.install(context)` once in `Application.onCreate` (foreground prefetch + WorkManager).
- Downloads: `filesDir/Downloads/<storage id>/` with `download.json` byte-identical to iOS
  (`shared/fixtures/download_manifest.json`); the queue is persisted and run by one WorkManager worker.
- eBooks: open only through `EbookReaderLauncher.open(itemId)` (or `open(book)`); `AppRoot` shows
  `EbookReaderOverlay` above the shell. The page-exact Readium locator stays local (`EbookLocalStore`,
  same JSON files as iOS); the server only gets `ebookProgress` via `EbookProgressSync` — never while
  the "read further elsewhere" offer is open. No automatic page sync / read-along (see `CLAUDE.md`).
