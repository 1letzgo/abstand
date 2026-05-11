# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build

```bash
# Build for simulator
xcodebuild -project abstand.xcodeproj -scheme abstand \
  -destination 'platform=iOS Simulator,name=iPhone 16' build

# Build for device (requires signing)
xcodebuild -project abstand.xcodeproj -scheme abstand \
  -destination 'generic/platform=iOS' build
```

No test targets exist. No linter is configured.

## Architecture

Abstand is an iOS audiobook/podcast player for [Audiobookshelf](https://www.audiobookshelf.org/) servers. All source files live flat in `abstand/` — no subdirectory structure.

### Central state: `AppModel`

`AppModel` (`@MainActor ObservableObject`) is the god object. It:
- Owns `ABSAPIClient?` (created on login, nil when logged out)
- Owns `PlaybackController` and `DownloadManager` (always live; their `objectWillChange` is forwarded to AppModel)
- Holds all `@Published` UI state: libraries, catalog, search results, progress, expand state
- Persists credentials and preferences to `UserDefaults` (all keys in the private `Keys` enum in `AppModel.swift`)
- Coordinates disk cache reads/writes via `LibraryDiskCache`

Entry point `abstandApp.swift` injects `AppModel` as `@EnvironmentObject`. `AppRootContainer` shows `LoginView` or `MainRootView` based on `model.isLoggedIn`.

### Network: `ABSAPIClient` (actor)

Swift `actor` — all Audiobookshelf API calls go through here. Created with `(baseURL:, token:)` on login. `AppModel.client` is the sole instance. Static helper `normalizeServerURL(_:)` is used everywhere a server URL needs validation.

### Playback: `PlaybackController` (`@MainActor ObservableObject`)

Wraps `AVPlayer` for multi-track audiobooks and podcast episodes. Manages:
- Audio session lifecycle (`ensureAudioSessionForPlayback`)
- Now Playing / lock screen controls (`MPNowPlayingInfoCenter`)
- Chapter tracking, sleep timer, playback rate (persisted to `UserDefaults`)
- Server session sync (`playSessionId` → `isRemotePlaySessionActive`)
- Entry: `playBook(client:book:resumeAt:localDownloadRoot:episodeId:autoPlay:)`

### Downloads: `DownloadManager` (`@MainActor ObservableObject`)

Downloads tracks sequentially into `Documents/Downloads/<itemId>/`. Writes `download.json` (`ABSDownloadManifest`) alongside tracks. `ABSBook.fromDownloadManifest(_:)` reconstructs a book stub for offline playback without network. Podcast episodes use `podcastEpisodeOfflineStorageId()` (derived from `progressLookupKey`) as the folder name instead of `libraryItemId`.

### Disk cache: `LibraryDiskCache` (enum namespace)

Caches raw server JSON (catalog pages, personalized shelves, podcast episodes, progress) in Application Support under `ABStandLibraryCache/accounts/<SHA256(serverURL)>/`. Loaded synchronously on launch for instant UI before network responses arrive. Cleared on logout.

Cover images have a separate cache managed by `CoverImageCache`, also scoped to the account directory.

### Models

All API models in `ABSModels.swift`, prefixed `ABS`. `ABSBook` is used for both audiobooks and podcast-show stubs. `ABSPodcastEpisodeListItem` has a `progressLookupKey` (e.g. `<libraryItemId>/ep/<episodeId>`) used as the canonical key in `AppModel.progressByItemId` and for deduplication.

### JSON

`ABSJSON.swift` provides shared `decoder()` / `encoder()` with `convertFromSnakeCase` strategy. Use these everywhere instead of plain `JSONDecoder()`.

### Language note

Inline comments in this codebase are written in German.
