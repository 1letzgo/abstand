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
| `ui/AppRoot.kt` | `abstandApp` / `AppRootContainer` / `MainTabShellView` |

(Extended as screens are ported.)

## Conventions

- JSON only through `AbsJson.decoder` / `.encoder` / `.decoderListeningStats` — never `Json { }`.
- Network only through `Net.client` / `Net.imageClient` (LAN self-signed TLS, custom headers per
  server origin, bearer for the active server) and `ApiClient` for API calls.
- Colours only from the palette (`Theme.palette`, accent); spacing only from the tokens.
- `AppModel` is not ported as one object: state lives in focused stores (session, catalog,
  podcasts, home, player, stats) exposing `StateFlow`s, method names follow iOS.
- Inline comments German, user-facing strings English (like iOS).
