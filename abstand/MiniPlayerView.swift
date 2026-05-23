import AVKit
import Combine
import SwiftUI
import UIKit

// MARK: - Abspielgeschwindigkeit (Label, locale Zahlenformat)

private func miniPlayerFormatPlaybackRate(_ rate: Float) -> String {
  let n = NSNumber(value: rate)
  let f = NumberFormatter()
  f.locale = Locale.autoupdatingCurrent
  f.minimumFractionDigits = 0
  f.maximumFractionDigits = 2
  f.numberStyle = .decimal
  let s = f.string(from: n) ?? String(format: "%g", rate)
  return "\(s)×"
}

// MARK: - Metriken (geteilt mit Bibliothekskarten-Buttons)

enum MiniPlayerMetrics {
  /// Bibliothekszeile: 82×82; Mini-Player-Cover = 1,5×
  static let coverSide: CGFloat = AppTheme.Layout.libraryRowCoverSide * 1.5
  static let controlMinHeight: CGFloat = 30
  static let controlCorner: CGFloat = 7

  /// Mini-Player: ±Seek, Kapitel (ohne Play-Orb).
  static let miniPlayerTransportHeight: CGFloat = 44
  /// Schlummer / Tempo / AirPlay: eine flache Zeile mit Text.
  static let miniPlayerSecondaryRowHeight: CGFloat = 28
  /// Weicher Play-Kreis (Durchmesser); Zeilenhöhe richtet sich danach.
  static let miniPlayerPlayOrb: CGFloat = 52

  /// Now-Playing-Sheet: Abstand Cover zu links/rechts/oben (gleich).
  static let fullPlayerCoverInset: CGFloat = 24

  /// Eine Zeile: Sleep · Transport · AirPlay (Höhe = max(Transport, Play-Orb)).
  static var miniPlayerControlsTotalHeight: CGFloat {
    max(miniPlayerTransportHeight, miniPlayerPlayOrb)
  }
}

/// Obere Steuerzeile + Beschriftung im Vollplayer unten: gleiche Primärhöhe für alle Spalten.
enum FullPlayerUtilityBarLayout {
  static let primaryRowHeight: CGFloat = 44
  static let rowSpacing: CGFloat = 4
}


// MARK: - Player-Layout (SwiftUI-typische Komponenten)

private enum PlayerChromeLayout {
  static let miniBarMaxHeight: CGFloat = 56
  static let miniCover: CGFloat = 40
  /// Kompaktes Cover in `tabViewBottomAccessory` (System-Miniplayer-Größe).
  static let tabAccessoryCover: CGFloat = 32
  static let skipBackward: Double = 15
  static let skipForward: Double = 30
}

private func authorDashTitleLine(for book: ABSBook) -> String {
  let a = book.displayAuthorsCardLine.trimmingCharacters(in: .whitespacesAndNewlines)
  let t = book.displayTitle
  if a.isEmpty || a == "—" { return t }
  return "\(a) – \(t)"
}

/// Untertitel der Floating-Bar: nur Restzeit (kompakt, ohne Sekunden).
private func floatingBarRemainingSubtitle(total: Double, position: Double) -> String {
  formatPlaybackDurationShortHuman(max(0, total - position))
}

/// `AVRoutePickerView` meldet in SwiftUI oft keine sinnvolle Intrinsic-Größe — ohne feste Bounds
/// frisst die Spalte die ganze Zeile bzw. vertikalen Platz.
private final class InlineRoutePickerView: AVRoutePickerView {
  override var intrinsicContentSize: CGSize { CGSize(width: 44, height: 44) }
}

private struct FullPlayerAirPlayButton: UIViewRepresentable {
  func makeUIView(context: Context) -> InlineRoutePickerView {
    let v = InlineRoutePickerView()
    v.prioritizesVideoDevices = false
    v.tintColor = .white
    v.activeTintColor = .white
    v.backgroundColor = .clear
    v.clipsToBounds = true
    return v
  }

  func updateUIView(_ uiView: InlineRoutePickerView, context: Context) {}
}

/// Sleep-Menü-Label: Countdown per `TimelineView` — Endzeit ändert sich nicht jede Sekunde, daher kein Menu-Flackern.
private struct SleepTimerUtilityMenuLabel: View {
  let endDate: Date?

  var body: some View {
    VStack(spacing: FullPlayerUtilityBarLayout.rowSpacing) {
      Group {
        if let end = endDate {
          TimelineView(.periodic(from: .now, by: 1)) { _ in
            Text(formatPlaybackTime(max(0, end.timeIntervalSinceNow)))
              .font(.subheadline.weight(.medium))
              .monospacedDigit()
              .foregroundStyle(AppTheme.accent)
          }
        } else {
          Text("Off")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
        }
      }
      .frame(
        maxWidth: .infinity,
        minHeight: FullPlayerUtilityBarLayout.primaryRowHeight,
        maxHeight: FullPlayerUtilityBarLayout.primaryRowHeight,
        alignment: .center
      )
      Text("Sleep", comment: "Player control label")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .contentShape(Rectangle())
  }
}

/// Untere Steuerzeile: von `globalPosition`-Ticks entkoppelt, damit `Menu` nicht flackert.
private struct FullPlayerUtilityBar: View, Equatable {
  @EnvironmentObject private var model: AppModel

  let playbackRate: Float
  let sleepEndDate: Date?
  let activeAudiobookId: String?
  let offlineStorageId: String?
  let isDownloaded: Bool
  let isDownloading: Bool
  let downloadProgressBucket: Int
  let bookmarkMenuItems: [PlayerBookmarkMenuItem]
  let isLoggedIn: Bool

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.playbackRate == rhs.playbackRate
      && lhs.sleepEndDate == rhs.sleepEndDate
      && lhs.activeAudiobookId == rhs.activeAudiobookId
      && lhs.offlineStorageId == rhs.offlineStorageId
      && lhs.isDownloaded == rhs.isDownloaded
      && lhs.isDownloading == rhs.isDownloading
      && lhs.downloadProgressBucket == rhs.downloadProgressBucket
      && lhs.bookmarkMenuItems == rhs.bookmarkMenuItems
      && lhs.isLoggedIn == rhs.isLoggedIn
  }

  var body: some View {
    HStack(spacing: 0) {
      Menu {
        ForEach(PlaybackController.playbackRatePresets, id: \.self) { r in
          Button {
            model.applyPlaybackSpeed(r)
          } label: {
            HStack {
              Text(miniPlayerFormatPlaybackRate(r))
              Spacer(minLength: 8)
              if playbackRate == r {
                Image(systemName: "checkmark")
                  .foregroundStyle(AppTheme.accent)
              }
            }
          }
        }
      } label: {
        VStack(spacing: FullPlayerUtilityBarLayout.rowSpacing) {
          Text(miniPlayerFormatPlaybackRate(playbackRate))
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(
              maxWidth: .infinity,
              minHeight: FullPlayerUtilityBarLayout.primaryRowHeight,
              maxHeight: FullPlayerUtilityBarLayout.primaryRowHeight,
              alignment: .center
            )
          Text("Tempo", comment: "Player control label")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
      }

      Menu {
        Button("Off") { model.applySleepTimer(minutes: nil) }
        Button("15 Min") { model.applySleepTimer(minutes: 15) }
        Button("30 Min") { model.applySleepTimer(minutes: 30) }
        Button("45 Min") { model.applySleepTimer(minutes: 45) }
        Button("60 Min") { model.applySleepTimer(minutes: 60) }
      } label: {
        SleepTimerUtilityMenuLabel(endDate: sleepEndDate)
      }

      PlayerBookmarkUtilityControl(
        activeAudiobookId: activeAudiobookId,
        menuItems: bookmarkMenuItems
      )

      VStack(spacing: FullPlayerUtilityBarLayout.rowSpacing) {
        FullPlayerAirPlayButton()
          .frame(width: 44, height: 44)
          .frame(
            maxWidth: .infinity,
            minHeight: FullPlayerUtilityBarLayout.primaryRowHeight,
            maxHeight: FullPlayerUtilityBarLayout.primaryRowHeight,
            alignment: .center
          )
        Text("AirPlay", comment: "Player control label")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity)
      .contentShape(Rectangle())

      downloadControl
        .frame(maxWidth: .infinity)
    }
    .padding(.vertical, 8)
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private var downloadControl: some View {
    if offlineStorageId != nil {
      if isDownloaded {
        Button {
          model.removeLocalDownloadForActivePlayback()
        } label: {
          VStack(spacing: FullPlayerUtilityBarLayout.rowSpacing) {
            Image(systemName: "arrow.down.circle.fill")
              .font(.title3)
              .foregroundStyle(Color.white)
              .frame(
                maxWidth: .infinity,
                minHeight: FullPlayerUtilityBarLayout.primaryRowHeight,
                maxHeight: FullPlayerUtilityBarLayout.primaryRowHeight,
                alignment: .center
              )
            Text("Download", comment: "Player download control caption")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isLoggedIn)
        .accessibilityLabel("Remove download")
      } else if isDownloading {
        VStack(spacing: FullPlayerUtilityBarLayout.rowSpacing) {
          ProgressView(value: Double(downloadProgressBucket) / 20.0)
            .tint(.white)
            .scaleEffect(x: 1, y: 0.9, anchor: .center)
            .frame(
              maxWidth: .infinity,
              minHeight: FullPlayerUtilityBarLayout.primaryRowHeight,
              maxHeight: FullPlayerUtilityBarLayout.primaryRowHeight,
              alignment: .center
            )
          Text("Download", comment: "Player download control caption")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Download in progress")
      } else {
        Button {
          model.startDownloadForActivePlayback()
        } label: {
          VStack(spacing: FullPlayerUtilityBarLayout.rowSpacing) {
            Image(systemName: "arrow.down.circle")
              .font(.title3)
              .foregroundStyle(Color.white)
              .frame(
                maxWidth: .infinity,
                minHeight: FullPlayerUtilityBarLayout.primaryRowHeight,
                maxHeight: FullPlayerUtilityBarLayout.primaryRowHeight,
                alignment: .center
              )
            Text("Download", comment: "Player download control caption")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isLoggedIn)
        .accessibilityLabel("Download")
      }
    }
  }
}

// MARK: - Vollansicht (Now Playing)

struct NowPlayingDetailView: View {
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var player: PlaybackController
  @Environment(\.verticalSizeClass) private var verticalSizeClass

  @State private var scrubLocal: Double?

  private var showIdlePlaceholder: Bool {
    player.showMiniPlayerPlaceholder && player.activeBook == nil && !model.isPlayerConnectionLoading
  }

  private var showsConnectionLoading: Bool {
    model.isPlayerConnectionLoading && player.activeBook == nil
  }

  var body: some View {
    ZStack {
      fullPlayerBackground
        .accessibilityHidden(true)
        .ignoresSafeArea()

      Group {
        if verticalSizeClass == .compact {
          landscapeLayout
        } else {
          portraitLayout
        }
      }
    }
    .preferredColorScheme(.dark)
  }

  private var fullPlayerBackground: some View {
    let top = player.miniPlayerBarFillColor
    let dark = Color(white: 0.1)
    return LinearGradient(colors: [top, dark], startPoint: .top, endPoint: .bottom)
  }

  private var portraitLayout: some View {
    VStack(spacing: 0) {
      if let b = player.activeBook {
        fullPlayerArtwork(book: b)
        Spacer(minLength: 24)
        VStack(spacing: 32) {
          chapterTitleArea(book: b)
          TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            playbackColumn(book: b)
          }
        }
        .frame(maxWidth: 800)
        Spacer(minLength: 24)
        fullPlayerUtilityBar
        Spacer(minLength: 8)
      } else if showsConnectionLoading {
        connectionLoadingPlaceholder
      } else if showIdlePlaceholder {
        idlePlaceholder
      }
    }
    .padding(.horizontal, MiniPlayerMetrics.fullPlayerCoverInset)
    .padding(.top, MiniPlayerMetrics.fullPlayerCoverInset)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  private var landscapeLayout: some View {
    HStack(alignment: .top, spacing: MiniPlayerMetrics.fullPlayerCoverInset) {
      if let b = player.activeBook {
        fullPlayerArtwork(book: b)
          .containerRelativeFrame(.horizontal) { w, _ in w * 0.4 }
        VStack(spacing: 24) {
          Spacer()
          chapterTitleArea(book: b)
          TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            playbackColumn(book: b)
          }
          fullPlayerUtilityBar
          Spacer()
        }
        .frame(maxWidth: .infinity)
      } else {
        restoringOrIdleInLandscape
      }
    }
    .padding(.horizontal, MiniPlayerMetrics.fullPlayerCoverInset)
    .padding(.top, MiniPlayerMetrics.fullPlayerCoverInset)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  private var restoringOrIdleInLandscape: some View {
    Group {
      if showsConnectionLoading {
        connectionLoadingPlaceholder
      } else if showIdlePlaceholder {
        idlePlaceholder
      }
    }
  }

  private func chapterTitleArea(book: ABSBook) -> some View {
    let authors = book.displayAuthors.trimmingCharacters(in: .whitespacesAndNewlines)
    return VStack(alignment: .center, spacing: 8) {
      Text(book.displayTitle)
        .font(.title2.weight(.bold))
        .foregroundStyle(AppTheme.textPrimary)
        .multilineTextAlignment(.center)
        .lineLimit(3)
        .frame(maxWidth: .infinity)
      if !authors.isEmpty, authors != "—" {
        Text(authors)
          .font(.title3)
          .foregroundStyle(AppTheme.textSecondary)
          .multilineTextAlignment(.center)
          .lineLimit(2)
          .frame(maxWidth: .infinity)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 8)
    .accessibilityElement(children: .combine)
  }

  private func scrubberCenterCaption(book: ABSBook) -> String {
    let chapters = player.chapterCount
    guard chapters > 0 else { return "" }
    let raw = player.currentChapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    if !raw.isEmpty { return raw }
    let ord = player.currentChapterOrdinal
    if ord > 0 { return "Chapter \(ord)" }
    return "—"
  }

  private func fullPlayerArtwork(book: ABSBook) -> some View {
    let dur = max(player.totalDuration, 1)
    let pos = player.globalPosition
    let pct = min(100, max(0, Int((pos / dur * 100).rounded())))
    let corner: CGFloat = 24
    return CoverImageView(
      url: model.coverURL(for: book.id),
      token: model.token,
      itemId: book.id,
      cacheAccount: model.coverImageCacheAccountDirectory(),
      cacheRevision: model.coverImageCacheRevision,
      contentMode: .fit
    )
    .aspectRatio(1, contentMode: .fit)
    .frame(maxWidth: 400)
    .frame(maxWidth: .infinity)
    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: corner, style: .continuous)
        .strokeBorder(.separator.opacity(0.35), lineWidth: 0.5)
    }
    .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
    .overlay(alignment: .topTrailing) {
      Text(verbatim: "\(pct)%")
        .font(.caption.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(.primary)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay {
          Capsule(style: .continuous)
            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        }
        .padding(.top, 12)
        .padding(.trailing, 12)
        .accessibilityLabel("Fortschritt \(pct) Prozent")
    }
  }

  private func playbackColumn(book: ABSBook) -> some View {
    VStack(spacing: 32) {
      scrubberSection(book: book)
      transportControls
    }
  }

  private func scrubberSection(book: ABSBook) -> some View {
    let dur = max(player.totalDuration, 1)
    let pos = scrubLocal ?? player.globalPosition
    let centerCaption = scrubberCenterCaption(book: book)
    return VStack(alignment: .leading, spacing: 10) {
      Slider(
        value: Binding(
          get: { pos },
          set: { scrubLocal = $0 }
        ),
        in: 0 ... dur,
        onEditingChanged: { editing in
          if !editing, let s = scrubLocal {
            player.seek(global: s)
            scrubLocal = nil
          }
        }
      )
      .tint(AppTheme.accent)
      .controlSize(.regular)
      .padding(.top, 6)
      .accessibilityLabel("Playback position")

      HStack {
        Text(formatPlaybackTime(pos))
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        if !centerCaption.isEmpty {
          Text(centerCaption)
            .font(.caption)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        } else {
          Spacer()
            .frame(maxWidth: .infinity)
        }
        Spacer()
        Text(formatPlaybackTime(max(0, dur - pos)))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .monospacedDigit()
    }
  }

  private var transportControls: some View {
    let hasChapters = player.chapterCount > 0
    let isBusy = player.activeBook != nil && player.isBuffering
    return HStack(spacing: 0) {
      if hasChapters {
        Button {
          player.skipToPreviousChapter()
        } label: {
          Image(systemName: "backward.end")
            .font(.title2)
            .symbolVariant(.fill)
        }
        .disabled(!player.canSkipToPreviousChapter)
        .accessibilityLabel("Previous chapter")
        Spacer(minLength: 8)
      }

      Button {
        player.skip(seconds: -PlayerChromeLayout.skipBackward)
      } label: {
        Image(systemName: "gobackward.15")
          .font(hasChapters ? .title2 : .largeTitle)
      }
      .disabled(isBusy)
      .accessibilityLabel("Back 15 seconds")

      Spacer(minLength: 8)

      Button {
        player.togglePlayPause()
      } label: {
        Group {
          if isBusy {
            ProgressView()
              .controlSize(.large)
          } else {
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
              .font(.system(size: 40))
              .symbolVariant(.fill)
          }
        }
        .frame(width: 64, height: 64)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .clipShape(Circle())
      .disabled(player.activeBook == nil)

      Spacer(minLength: 8)

      Button {
        player.skip(seconds: PlayerChromeLayout.skipForward)
      } label: {
        Image(systemName: "goforward.30")
          .font(hasChapters ? .title2 : .largeTitle)
      }
      .disabled(isBusy)
      .accessibilityLabel("Forward 30 seconds")

      if hasChapters {
        Spacer(minLength: 8)
        Button {
          player.skipToNextChapter()
        } label: {
          Image(systemName: "forward.end")
            .font(.title2)
            .symbolVariant(.fill)
        }
        .disabled(!player.canSkipToNextChapter)
        .accessibilityLabel("Next chapter")
      }
    }
    .buttonStyle(.borderless)
  }

  private var fullPlayerUtilityBar: some View {
    let sid = model.currentPlaybackOfflineStorageId()
    let isDownloading = sid != nil && model.downloads.activeItemId == sid
    let audiobookId: String? = {
      guard let id = player.activeBook?.id else { return nil }
      let ep = player.activePlaybackEpisodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return ep.isEmpty ? id : nil
    }()
    return FullPlayerUtilityBar(
      playbackRate: player.playbackRate,
      sleepEndDate: player.sleepEndDate,
      activeAudiobookId: audiobookId,
      offlineStorageId: sid,
      isDownloaded: sid.map { model.downloadedItemIds.contains($0) } ?? false,
      isDownloading: isDownloading,
      downloadProgressBucket: isDownloading ? Int(model.downloads.progress * 20) : -1,
      bookmarkMenuItems: audiobookId.map { id in
        model.bookmarks(for: id).map(PlayerBookmarkMenuItem.init)
      } ?? [],
      isLoggedIn: model.isLoggedIn
    )
    .equatable()
  }

  private var connectionLoadingPlaceholder: some View {
    ContentUnavailableView {
      ProgressView()
    } description: {
      Text(model.isRestoringLaunchPlayback ? "Loading last position…" : "Loading…")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var idlePlaceholder: some View {
    ContentUnavailableView(
      "Nothing playing",
      systemImage: "waveform",
      description: Text("Choose an audiobook in the library.")
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

// MARK: - Tab bar accessory artwork (equatable: ignore high-frequency playback ticks)

private struct FloatingBarCoverEquatable: View, Equatable {
  var itemId: String
  var coverURL: URL?
  var coverToken: String
  var coverCacheAccount: URL?
  var coverRevision: Int

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.itemId == rhs.itemId && lhs.coverRevision == rhs.coverRevision
      && lhs.coverURL == rhs.coverURL && lhs.coverToken == rhs.coverToken
      && lhs.coverCacheAccount == rhs.coverCacheAccount
  }

  var body: some View {
    let side = PlayerChromeLayout.tabAccessoryCover
    let plateRadius: CGFloat = 6
    CoverImageView(
      url: coverURL,
      token: coverToken,
      itemId: itemId,
      cacheAccount: coverCacheAccount,
      cacheRevision: coverRevision
    )
    .frame(width: side, height: side)
    .clipShape(RoundedRectangle(cornerRadius: plateRadius, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: plateRadius, style: .continuous)
        .strokeBorder(.quaternary, lineWidth: 0.5)
    }
  }
}

/// Ein Snapshot für die Tab-Bar — wie AudioBooth `MiniBookPlayer` (Equatable, keine Position-Ticks).
struct TabAccessoryMiniPlayerSnapshot: Equatable {
  let activeBookId: String?
  let coverRevision: Int
  let coverURL: URL?
  let coverToken: String
  let coverCacheAccount: URL?
  let primaryLine: String
  let subtitleText: String?
  /// Restzeit in ganzen Minuten — Snapshot ändert sich nur bei Minutenwechsel (nicht bei Position-Ticks).
  let remainingMinuteBucket: Int?
  let showsRestoringCover: Bool
  /// App-Start / `play`: noch kein `activeBook`, Verbindung oder Session wird aufgebaut.
  let showsConnectionLoading: Bool
  let isPlaying: Bool
  let isBuffering: Bool
  let canTogglePlayback: Bool

  static let hidden = TabAccessoryMiniPlayerSnapshot(
    activeBookId: nil,
    coverRevision: 0,
    coverURL: nil,
    coverToken: "",
    coverCacheAccount: nil,
    primaryLine: "",
    subtitleText: nil,
    remainingMinuteBucket: nil,
    showsRestoringCover: false,
    showsConnectionLoading: false,
    isPlaying: false,
    isBuffering: false,
    canTogglePlayback: false
  )

  @MainActor
  static func make(model: AppModel) -> TabAccessoryMiniPlayerSnapshot {
    let player = model.player
    if let book = player.activeBook {
      let total = max(player.totalDuration, 1)
      let remainingSeconds = max(0, total - player.globalPosition)
      let caption = floatingBarRemainingSubtitle(total: total, position: player.globalPosition)
      let connecting = player.isBuffering || model.isPreparingPlayback
      return TabAccessoryMiniPlayerSnapshot(
        activeBookId: book.id,
        coverRevision: model.coverImageCacheRevision,
        coverURL: model.coverURL(for: book.id),
        coverToken: model.token,
        coverCacheAccount: model.coverImageCacheAccountDirectory(),
        primaryLine: authorDashTitleLine(for: book),
        subtitleText: connecting ? "Loading…" : caption,
        remainingMinuteBucket: connecting ? nil : Int(remainingSeconds / 60),
        showsRestoringCover: connecting,
        showsConnectionLoading: false,
        isPlaying: player.isPlaying,
        isBuffering: player.isBuffering,
        canTogglePlayback: !model.isPlayerConnectionLoading && !connecting
      )
    }
    if model.isPlayerConnectionLoading {
      return TabAccessoryMiniPlayerSnapshot(
        activeBookId: nil,
        coverRevision: model.coverImageCacheRevision,
        coverURL: nil,
        coverToken: model.token,
        coverCacheAccount: model.coverImageCacheAccountDirectory(),
        primaryLine: "Loading…",
        subtitleText: nil,
        remainingMinuteBucket: nil,
        showsRestoringCover: true,
        showsConnectionLoading: true,
        isPlaying: false,
        isBuffering: false,
        canTogglePlayback: false
      )
    }
    return .hidden
  }
}

/// Sichtbarkeit + Mini-Player-Snapshot — entkoppelt von `AppModel` (vgl. AudioBooth `PlayerManager`).
@MainActor
final class FloatingAccessoryGate: ObservableObject {
  // Kein @Published — wir senden objectWillChange manuell, damit beide Felder
  // atomar in einem einzigen SwiftUI-Rebuild landen statt in zwei getrennten.
  private(set) var chromeVisible = false
  private(set) var snapshot = TabAccessoryMiniPlayerSnapshot.hidden

  fileprivate func apply(chromeVisible: Bool, snapshot: TabAccessoryMiniPlayerSnapshot) {
    guard chromeVisible != self.chromeVisible || snapshot != self.snapshot else { return }
    objectWillChange.send()
    self.chromeVisible = chromeVisible
    self.snapshot = snapshot
  }
}

/// Nur Player-relevante Updates — nicht an `AppModel.books`, Downloads, Suche, … gekoppelt.
@MainActor
final class FloatingPlayerChromeController: ObservableObject {
  let gate = FloatingAccessoryGate()

  private weak var model: AppModel?
  private var cancellables = Set<AnyCancellable>()
  private var lastOpenNowPlayingUptime: TimeInterval = 0

  func openNowPlaying() {
    let now = ProcessInfo.processInfo.systemUptime
    guard now - lastOpenNowPlayingUptime > 0.35 else { return }
    lastOpenNowPlayingUptime = now
    model?.requestPresentNowPlayingSheet()
  }

  func skipBackward() {
    model?.player.skip(seconds: -PlayerChromeLayout.skipBackward)
  }

  func togglePlayPause() {
    model?.player.togglePlayPause()
  }

  func dismissPlayback() {
    Task { await model?.dismissPlayer() }
  }

  func bind(model: AppModel) {
    self.model = model
    cancellables.removeAll()
    let player = model.player

    // Sofort: Play/Pause, Buchwechsel, Buffering/Verbindung (Loading-Zeile).
    Publishers.MergeMany(
      player.$activeBook.map { _ in () }.eraseToAnyPublisher(),
      player.$activePlaybackEpisodeId.map { _ in () }.eraseToAnyPublisher(),
      player.$isPlaying.map { _ in () }.eraseToAnyPublisher(),
      player.$isBuffering.map { _ in () }.eraseToAnyPublisher(),
      player.$showMiniPlayerPlaceholder.map { _ in () }.eraseToAnyPublisher(),
      model.$isRestoringLaunchPlayback.map { _ in () }.eraseToAnyPublisher(),
      model.$isPreparingPlayback.map { _ in () }.eraseToAnyPublisher(),
      model.$offlineHomeMode.map { _ in () }.eraseToAnyPublisher(),
      model.$offlineHomeModeAuto.map { _ in () }.eraseToAnyPublisher()
    )
    .receive(on: DispatchQueue.main)
    .sink { [weak self] in self?.refresh() }
    .store(in: &cancellables)

    // Restzeit nur 1× pro Minute (keine Position-/Duration-Ticks).
    Timer.publish(every: 60, on: .main, in: .common)
      .autoconnect()
      .sink { [weak self] _ in
        guard let self, model.player.activeBook != nil else { return }
        self.refresh()
      }
      .store(in: &cancellables)

    refresh()
  }

  private func refresh() {
    guard let model else { return }
    let next = TabAccessoryMiniPlayerSnapshot.make(model: model)
    let visible =
      !model.offlineHomeUIActive
      && (next.activeBookId != nil || next.showsConnectionLoading)
    gate.apply(chromeVisible: visible, snapshot: next)
  }
}

extension FloatingPlayerChromeController {
  var playbackController: PlaybackController? { model?.player }
}

/// `tabViewBottomAccessory` — stabiler Inhalt wie AudioBooth `MiniBookPlayer` (`.equatable()`).
struct FloatingAccessoryLayer: View {
  @ObservedObject var gate: FloatingAccessoryGate
  let chrome: FloatingPlayerChromeController
  let sheetPresented: Bool
  let keyboardVisible: Bool

  private var showsFloatingPlayer: Bool {
    !sheetPresented && !keyboardVisible && gate.chromeVisible
  }

  var body: some View {
    if showsFloatingPlayer, chrome.playbackController != nil {
      TabAccessoryMiniPlayer(snapshot: gate.snapshot, chrome: chrome)
        .equatable()
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
  }
}

/// Vorbild: [AudioBooth `MiniBookPlayer`](https://github.com/AudioBooth/AudioBooth/blob/main/AudioBooth/AudioBooth/Screens/BookPlayer/MiniBookPlayer.swift)
private struct TabAccessoryMiniPlayer: View, Equatable {
  let snapshot: TabAccessoryMiniPlayerSnapshot
  let chrome: FloatingPlayerChromeController

  @Environment(\.tabViewBottomAccessoryPlacement) private var placement

  private static let rowMinHeight: CGFloat = 48
  private static let accessoryTransportSide: CGFloat = 44

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.snapshot == rhs.snapshot
  }

  var body: some View {
    HStack(alignment: .center, spacing: 0) {
      Button {
        chrome.openNowPlaying()
      } label: {
        openRegionLabel
          .frame(maxWidth: .infinity, minHeight: Self.rowMinHeight, alignment: .leading)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .layoutPriority(1)
      .accessibilityLabel("Open now playing")
      .accessibilityHint("Shows the full player")

      if showsTransportControls {
        transportControls
          .fixedSize(horizontal: true, vertical: false)
      }
    }
    .frame(maxWidth: .infinity, minHeight: Self.rowMinHeight + 16, alignment: .center)
    .padding(.horizontal, 12)
    .contentShape(Rectangle())
  }

  private var showsTransportControls: Bool {
    placement != .inline && snapshot.canTogglePlayback
  }

  /// Nur Anzeige — Tap auf gesamte linke Fläche über umschließenden `Button` (`.plain`).
  private var openRegionLabel: some View {
    HStack(spacing: 0) {
      miniCover
      VStack(alignment: .leading, spacing: 2) {
        Text(snapshot.primaryLine)
          .font(.footnote)
          .fontWeight(.medium)
          .foregroundStyle(.primary)
          .lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)
        if let subtitle = snapshot.subtitleText {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fontWeight(.medium)
            .lineLimit(1)
        }
      }
      .padding(.leading, 10)
      Spacer(minLength: 0)
    }
  }

  private var transportControls: some View {
    let busy = snapshot.canTogglePlayback && snapshot.isBuffering
    let playDiameter: CGFloat = 36
    return HStack(spacing: 8) {
      Button {
        chrome.skipBackward()
      } label: {
        Image(systemName: "gobackward.15")
          .font(.system(size: 18, weight: .medium))
          .foregroundStyle(.primary)
          .frame(width: Self.accessoryTransportSide, height: Self.accessoryTransportSide)
          .contentShape(Rectangle())
      }
      .disabled(busy)
      .buttonStyle(.borderless)
      .accessibilityLabel("Back 15 seconds")

      Button {
        chrome.togglePlayPause()
      } label: {
        ZStack {
          Circle()
            .fill(Color.accentColor)
            .frame(width: playDiameter, height: playDiameter)
          if busy {
            ProgressView()
              .progressViewStyle(.circular)
              .tint(.white)
              .scaleEffect(0.72)
          } else {
            Image(systemName: snapshot.isPlaying ? "pause.fill" : "play.fill")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(.white)
          }
        }
        .frame(width: Self.accessoryTransportSide, height: Self.accessoryTransportSide)
        .contentShape(Rectangle())
      }
      .buttonStyle(.borderless)
      .accessibilityLabel(snapshot.isPlaying ? "Pause" : "Play")
    }
  }

  @ViewBuilder
  private var miniCover: some View {
    let side = PlayerChromeLayout.tabAccessoryCover
    let plateRadius: CGFloat = 6
    if let id = snapshot.activeBookId {
      FloatingBarCoverEquatable(
        itemId: id,
        coverURL: snapshot.coverURL,
        coverToken: snapshot.coverToken,
        coverCacheAccount: snapshot.coverCacheAccount,
        coverRevision: snapshot.coverRevision
      )
      .contextMenu {
        Button(role: .destructive) {
          chrome.dismissPlayback()
        } label: {
          Label("Stop playback", systemImage: "xmark.circle")
        }
      }
    } else if snapshot.showsRestoringCover {
      RoundedRectangle(cornerRadius: plateRadius, style: .continuous)
        .fill(.quaternary.opacity(0.5))
        .frame(width: side, height: side)
        .overlay { ProgressView() }
    } else {
      RoundedRectangle(cornerRadius: plateRadius, style: .continuous)
        .fill(.quaternary.opacity(0.5))
        .frame(width: side, height: side)
        .overlay {
          Image(systemName: "waveform")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
  }
}


/// Umrandete Aktions-Buttons (Bibliothekskarte), optisch an den Mini-Player angelehnt.
struct LibraryCardActionButtonStyle: ButtonStyle {
  enum Variant {
    case neutral
    case accent
    case danger
    /// Lokale Kopie vorhanden — dezenter Akzent-Hintergrund (nicht mit „deaktiviert“ verwechseln).
    case downloaded
    /// Als fertig markiert — dezenter Erfolgs-Hintergrund (wie Häkchen in Listenzeilen).
    case finished
  }

  var variant: Variant = .neutral
  var minHeight: CGFloat = MiniPlayerMetrics.controlMinHeight
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    let stroke: Color = {
      switch variant {
      case .neutral:
        return AppTheme.textSecondary.opacity(isEnabled ? 0.42 : 0.22)
      case .accent:
        return AppTheme.accent.opacity(isEnabled ? 0.55 : 0.22)
      case .danger:
        return AppTheme.danger.opacity(isEnabled ? 0.55 : 0.22)
      case .downloaded:
        return AppTheme.accent.opacity(isEnabled ? 0.72 : 0.5)
      case .finished:
        return AppTheme.success.opacity(isEnabled ? 0.72 : 0.5)
      }
    }()
    let fill: Color = {
      switch variant {
      case .neutral: return .clear
      case .accent: return AppTheme.accent.opacity(0.12)
      case .danger: return AppTheme.danger.opacity(0.12)
      case .downloaded: return AppTheme.accent.opacity(0.28)
      case .finished: return AppTheme.success.opacity(0.28)
      }
    }()

    return configuration.label
      .fixedSize(horizontal: true, vertical: true)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(
        RoundedRectangle(cornerRadius: MiniPlayerMetrics.controlCorner, style: .continuous)
          .fill(fill)
      )
      .overlay(
        RoundedRectangle(cornerRadius: MiniPlayerMetrics.controlCorner, style: .continuous)
          .stroke(stroke, lineWidth: 1)
      )
      .opacity(
        isEnabled
          ? (configuration.isPressed ? 0.72 : 1)
          : 0.38
      )
      .contentShape(RoundedRectangle(cornerRadius: MiniPlayerMetrics.controlCorner, style: .continuous))
      .frame(minHeight: minHeight)
  }
}

// MARK: - Offline-Home: Mini-Player-Karte (Cover links, über „Downloaded“)

/// Fortschrittsstreifen am Kartenrand — wie Library-Zeilen / Continue-Hero.
private struct OfflinePlayerEdgeProgress: View {
  let value: Double

  var body: some View {
    GeometryReader { geo in
      let w = max(0, geo.size.width)
      let t = min(1, max(0, value))
      ZStack(alignment: .leading) {
        Rectangle().fill(Color.white.opacity(0.14))
        Rectangle().fill(AppTheme.accent).frame(width: w * t)
      }
    }
    .frame(height: AppTheme.Layout.libraryRowBottomProgressHeight)
  }
}

/// Kompakte Wiedergabe-Karte auf der Offline-Home — ersetzt `tabViewBottomAccessory` + Tab-Bar.
struct OfflineHomeMiniPlayerCard: View {
  @ObservedObject var gate: FloatingAccessoryGate
  let chrome: FloatingPlayerChromeController
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var player: PlaybackController

  @State private var confirmMarkFinished = false
  @State private var confirmMarkUnfinished = false

  private var snapshot: TabAccessoryMiniPlayerSnapshot { gate.snapshot }

  var body: some View {
    cardBody
      .alert("Mark as finished?", isPresented: $confirmMarkFinished) {
        Button("Cancel", role: .cancel) {}
        Button("Mark as finished") {
          Task { await offlineApplyMarkFinished() }
        }
      } message: {
        Text("Your current position will be saved as complete.")
      }
      .alert("Mark as not finished?", isPresented: $confirmMarkUnfinished) {
        Button("Cancel", role: .cancel) {}
        Button("Mark as not finished") {
          Task { await offlineApplyMarkUnfinished() }
        }
      } message: {
        Text("You can resume from your saved position.")
      }
  }

  private var cardBody: some View {
    let inset = AppTheme.Layout.libraryRowCardInset
    let shape = RoundedRectangle(
      cornerRadius: AppTheme.Layout.libraryRowCornerRadius, style: .continuous)

    return VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: inset) {
        Button {
          chrome.openNowPlaying()
        } label: {
          HStack(alignment: .top, spacing: inset) {
            offlineCover
            metadataColumn
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open now playing")
        .accessibilityHint("Shows the full player")

        if showsTransport {
          offlineTransportRow
        } else if snapshot.showsConnectionLoading {
          HStack(spacing: 8) {
            ProgressView()
              .tint(AppTheme.accent)
            Text("Loading…")
              .font(.subheadline)
              .foregroundStyle(AppTheme.textSecondary)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }

        if showsProgress {
          offlineProgressTimeRow(
            totalDuration: max(player.totalDuration, 1),
            position: min(max(0, player.globalPosition), max(player.totalDuration, 1))
          )
        }
      }
      .padding(inset)
      .overlay(alignment: .topTrailing) {
        HStack(spacing: 6) {
          offlineMarkFinishedCornerButton
          offlineSleepTimerCornerButton
        }
        .padding(inset)
      }

      if showsProgress {
        OfflinePlayerEdgeProgress(value: player.globalPosition / max(player.totalDuration, 1))
          .allowsHitTesting(false)
          .accessibilityLabel("Playback progress")
      }
    }
    .fixedSize(horizontal: false, vertical: true)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(AppTheme.card)
    .clipShape(shape)
    .contentShape(shape)
  }

  private var showsTransport: Bool {
    player.activeBook != nil || snapshot.showsConnectionLoading
  }

  private var offlineTransportRow: some View {
    let hasChapters = player.chapterCount > 0
    let isBusy = player.activeBook != nil && player.isBuffering
    let playDiameter = MiniPlayerMetrics.miniPlayerPlayOrb
    let sideSlot = MiniPlayerMetrics.controlMinHeight
    let rowHeight = max(playDiameter, sideSlot)
    return HStack(alignment: .center, spacing: 0) {
      offlineTransportChapterSlot(
        isLeading: true,
        hasChapters: hasChapters,
        side: sideSlot
      )
      .frame(maxWidth: .infinity, maxHeight: rowHeight)

      offlineTransportControlButton(
        systemName: "gobackward.15",
        label: "Back 15 seconds",
        disabled: isBusy || player.activeBook == nil
      ) {
        player.skip(seconds: -PlayerChromeLayout.skipBackward)
      }
      .frame(maxWidth: .infinity, maxHeight: rowHeight)

      Button {
        chrome.togglePlayPause()
      } label: {
        ZStack {
          Circle()
            .fill(AppTheme.accent)
            .frame(width: playDiameter, height: playDiameter)
          if isBusy {
            ProgressView()
              .progressViewStyle(.circular)
              .tint(.black.opacity(0.85))
              .scaleEffect(0.85)
          } else {
            Image(systemName: snapshot.isPlaying ? "pause.fill" : "play.fill")
              .font(.system(size: 18, weight: .semibold))
              .foregroundStyle(Color.black.opacity(0.88))
          }
        }
      }
      .buttonStyle(.plain)
      .disabled(!snapshot.canTogglePlayback)
      .accessibilityLabel(snapshot.isPlaying ? "Pause" : "Play")
      .frame(maxWidth: .infinity, maxHeight: rowHeight)

      offlineTransportControlButton(
        systemName: "goforward.30",
        label: "Forward 30 seconds",
        disabled: isBusy || player.activeBook == nil
      ) {
        player.skip(seconds: PlayerChromeLayout.skipForward)
      }
      .frame(maxWidth: .infinity, maxHeight: rowHeight)

      offlineTransportChapterSlot(
        isLeading: false,
        hasChapters: hasChapters,
        side: sideSlot
      )
      .frame(maxWidth: .infinity, maxHeight: rowHeight)
    }
    .frame(maxWidth: .infinity)
    .frame(height: rowHeight)
  }

  @ViewBuilder
  private func offlineTransportChapterSlot(isLeading: Bool, hasChapters: Bool, side: CGFloat) -> some View {
    HStack {
      Spacer(minLength: 0)
      Group {
        if hasChapters {
          if isLeading {
            offlineTransportControlButton(
              systemName: "backward.end.fill",
              label: "Previous chapter",
              disabled: !player.canSkipToPreviousChapter
            ) {
              player.skipToPreviousChapter()
            }
          } else {
            offlineTransportControlButton(
              systemName: "forward.end.fill",
              label: "Next chapter",
              disabled: !player.canSkipToNextChapter
            ) {
              player.skipToNextChapter()
            }
          }
        } else {
          Color.clear
            .frame(width: side, height: side)
            .accessibilityHidden(true)
        }
      }
      Spacer(minLength: 0)
    }
    .frame(height: side)
  }

  private var offlineActiveAudiobookId: String? {
    guard let book = player.activeBook else { return nil }
    let ep = player.activePlaybackEpisodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return ep.isEmpty ? book.id : nil
  }

  private var offlineActivePodcastEpisode: ABSPodcastEpisodeListItem? {
    model.podcastEpisodeForActivePlayback()
  }

  private var offlineActiveItemIsFinished: Bool {
    if let episode = offlineActivePodcastEpisode {
      return model.progressByItemId[episode.progressLookupKey]?.isFinished == true
    }
    if let bookId = offlineActiveAudiobookId {
      return model.progressByItemId[bookId]?.isFinished == true
    }
    return false
  }

  private var offlineMarkFinishedCornerButton: some View {
    let finished = offlineActiveItemIsFinished
    return Button {
      if finished {
        confirmMarkUnfinished = true
      } else {
        confirmMarkFinished = true
      }
    } label: {
      Image(systemName: finished ? "arrow.uturn.backward.circle" : "checkmark.circle")
        .font(.callout)
        .foregroundStyle(finished ? AppTheme.success : AppTheme.accent)
    }
    .buttonStyle(
      LibraryCardActionButtonStyle(
        variant: finished ? .finished : .accent,
        minHeight: 36
      )
    )
    .disabled(player.activeBook == nil)
    .frame(width: 36, height: 36)
    .accessibilityLabel(finished ? "Mark as not finished" : "Mark as finished")
  }

  private func offlineApplyMarkFinished() async {
    if let episode = offlineActivePodcastEpisode {
      await model.markPodcastEpisodeFinished(episode)
    } else if let bookId = offlineActiveAudiobookId {
      await model.markFinished(bookId: bookId)
    }
  }

  private func offlineApplyMarkUnfinished() async {
    if let episode = offlineActivePodcastEpisode {
      await model.markPodcastEpisodeUnfinished(episode)
    } else if let bookId = offlineActiveAudiobookId {
      await model.markUnfinished(bookId: bookId)
    }
  }

  private var offlineSleepTimerCornerButton: some View {
    let sleepActive = player.sleepEndDate != nil
    return Menu {
      Button("Off") { model.applySleepTimer(minutes: nil) }
      Button("15 Min") { model.applySleepTimer(minutes: 15) }
      Button("30 Min") { model.applySleepTimer(minutes: 30) }
      Button("45 Min") { model.applySleepTimer(minutes: 45) }
      Button("60 Min") { model.applySleepTimer(minutes: 60) }
    } label: {
      Image(systemName: sleepActive ? "moon.fill" : "moon")
        .font(.callout)
        .foregroundStyle(sleepActive ? AppTheme.accent : AppTheme.textPrimary)
    }
    .buttonStyle(
      LibraryCardActionButtonStyle(
        variant: sleepActive ? .accent : .neutral,
        minHeight: 36
      )
    )
    .disabled(player.activeBook == nil)
    .frame(width: 36, height: 36)
    .accessibilityLabel("Sleep timer")
    .accessibilityHint(sleepActive ? "Timer active" : "Set sleep timer")
  }

  private func offlineTransportControlButton(
    systemName: String,
    label: String,
    disabled: Bool,
    action: @escaping () -> Void
  ) -> some View {
    HStack {
      Spacer(minLength: 0)
      Button(action: action) {
        Image(systemName: systemName)
          .font(.title3.weight(.medium))
          .foregroundStyle(AppTheme.textPrimary)
          .frame(width: MiniPlayerMetrics.controlMinHeight, height: MiniPlayerMetrics.controlMinHeight)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(disabled)
      .opacity(disabled ? 0.35 : 1)
      .accessibilityLabel(label)
      Spacer(minLength: 0)
    }
  }

  @ViewBuilder
  private var offlineCover: some View {
    let side = AppTheme.Layout.libraryRowCoverSide
    let radius = AppTheme.Layout.libraryRowCornerRadius
    if let id = snapshot.activeBookId {
      CoverImageView(
        url: snapshot.coverURL,
        token: snapshot.coverToken,
        itemId: id,
        cacheAccount: snapshot.coverCacheAccount,
        cacheRevision: snapshot.coverRevision
      )
      .frame(width: side, height: side)
      .scaledToFill()
      .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    } else if snapshot.showsRestoringCover {
      RoundedRectangle(cornerRadius: radius, style: .continuous)
        .fill(AppTheme.background)
        .frame(width: side, height: side)
        .overlay { ProgressView().tint(AppTheme.accent) }
    } else {
      RoundedRectangle(cornerRadius: radius, style: .continuous)
        .fill(AppTheme.background)
        .frame(width: side, height: side)
        .overlay {
          Image(systemName: "waveform")
            .font(.title3)
            .foregroundStyle(AppTheme.textSecondary)
        }
    }
  }

  private var metadataColumn: some View {
    VStack(alignment: .leading, spacing: 4) {
      if let book = player.activeBook {
        Text(book.displayTitle)
          .font(.headline.weight(.semibold))
          .foregroundStyle(AppTheme.textPrimary)
          .lineLimit(2)
          .multilineTextAlignment(.leading)
        let author = book.displayAuthorsCardLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if !author.isEmpty, author != "—" {
          Text(author)
            .font(.caption)
            .foregroundStyle(AppTheme.textSecondary)
            .lineLimit(1)
        }
        if let chapter = offlineChapterCaption {
          Text(chapter)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(AppTheme.textSecondary)
            .lineLimit(1)
        }
      } else {
        Text(snapshot.primaryLine)
          .font(.headline.weight(.semibold))
          .foregroundStyle(AppTheme.textPrimary)
          .lineLimit(2)
      }
      if !showsProgress, let subtitle = snapshot.subtitleText {
        Text(subtitle)
          .font(.caption.monospacedDigit())
          .foregroundStyle(AppTheme.accent)
          .lineLimit(1)
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .padding(.trailing, player.activeBook != nil ? 80 : 0)
  }

  private var offlineChapterCaption: String? {
    guard player.chapterCount > 0 else { return nil }
    let ord = player.currentChapterOrdinal
    guard ord > 0 else { return nil }
    return "\(ord)/\(player.chapterCount)"
  }

  private var showsProgress: Bool {
    player.activeBook != nil && player.totalDuration > 0
  }

  private func offlineProgressTimeRow(totalDuration dur: Double, position pos: Double) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text(formatPlaybackTime(dur))
        .frame(maxWidth: .infinity, alignment: .leading)
      offlineSleepTimerCountdownLabel
        .frame(minWidth: 52)
      Text(formatPlaybackTime(max(0, dur - pos)))
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .font(.caption.monospacedDigit())
    .foregroundStyle(AppTheme.textSecondary)
  }

  @ViewBuilder
  private var offlineSleepTimerCountdownLabel: some View {
    if let end = player.sleepEndDate {
      TimelineView(.periodic(from: .now, by: 1)) { _ in
        Text(formatPlaybackTime(max(0, end.timeIntervalSinceNow)))
          .foregroundStyle(AppTheme.accent)
          .lineLimit(1)
          .minimumScaleFactor(0.85)
          .frame(maxWidth: .infinity)
      }
    } else {
      Color.clear
        .frame(minWidth: 52, minHeight: 1)
        .accessibilityHidden(true)
    }
  }
}

