import Combine
import Foundation
import ReadiumNavigator
import ReadiumShared
import Speech
import SwiftUI

/// Orchestriert Prep (Alignment) und Runtime-Sync zwischen Hörbuch und EPUB-Reader.
@MainActor
final class EbookSyncController: ObservableObject {
  @Published private(set) var isSyncModeActive = false
  @Published private(set) var isPreparing = false
  @Published private(set) var prepProgress: Double?
  @Published private(set) var prepStatusMessage: String?
  @Published private(set) var errorMessage: String?
  @Published private(set) var alignmentMap: EbookAudioAlignmentMap?
  @Published private(set) var activeSentenceId: String?
  /// Wie Teleprompter: sync-Initialwert aus Speech, async Refresh via `refreshAvailability()`.
  @Published private(set) var isSyncAvailable = SpeechTranscriber.isAvailable
  /// Erhöht bei Seek-/Start-Sync — Reader setzt Highlight hart zurück.
  @Published private(set) var syncGeneration: UInt = 0
  /// Library-Item, für das gerade Alignment vorbereitet wird (ohne Sync-Mode).
  @Published private(set) var preparingLibraryItemId: String?
  /// Letztes erfolgreich vorbereitetes (oder als Cache gültig erkanntes) Item.
  @Published private(set) var preparedLibraryItemId: String?

  private let aligner = EbookAudioAligner()
  private weak var boundPlayer: PlaybackController?
  private var prepTask: Task<Void, Never>?
  private var extendTask: Task<Void, Never>?
  private var activeLibraryItemId: String?
  private var activeEbookFileURL: URL?
  private var accountURL: URL?
  private var userId: String?

  func configureSession(account: URL?, userId: String?) {
    self.accountURL = account
    self.userId = userId
  }

  func refreshAvailability() async {
    isSyncAvailable = await SpeechTranscriberAvailability.isSupported()
  }

  var canStartSync: Bool {
    isSyncAvailable && !isPreparing
  }

  func isPrepared(libraryItemId: String) -> Bool {
    preparedLibraryItemId == libraryItemId
  }

  func isPreparingItem(_ libraryItemId: String) -> Bool {
    isPreparing && preparingLibraryItemId == libraryItemId
  }

  /// Ob die geladene/gecachte Map die Hörposition abdeckt (Fenster-Prep).
  func alignmentMapCovers(libraryItemId: String, globalTime: Double) -> Bool {
    if let map = alignmentMap, map.libraryItemId == libraryItemId {
      return map.covers(globalTime: globalTime)
    }
    guard preparedLibraryItemId == libraryItemId,
      let cached = EbookAudioAlignmentStore.load(
        account: accountURL, userId: userId, libraryItemId: libraryItemId)
    else { return false }
    return cached.covers(globalTime: globalTime)
  }

  /// Nur Alignment vorbereiten (kein Reader, kein Sync-Mode).
  /// `downloadRoot` erlaubt Prep ohne aktiven Player (Prepare-Queue).
  /// Transkribiert nur ein Fenster um `anchorGlobalTime` (Hörfortschritt), nicht das ganze Buch.
  func prepareAlignment(
    player: PlaybackController?,
    libraryItemId: String,
    ebookFileURL: URL,
    ebookFormat: ABSEbookFormat,
    downloadRoot: URL? = nil,
    preferredLanguageTag: String? = nil,
    anchorGlobalTime: Double = 0,
    totalDurationHint: Double? = nil
  ) async {
    errorMessage = nil
    guard ebookFormat == .epub else {
      errorMessage = EbookSyncError.epubRequired.localizedDescription
      return
    }
    guard isSyncAvailable else {
      errorMessage = EbookSyncError.speechUnavailable.localizedDescription
      return
    }
    let hasLocalAudio =
      downloadRoot != nil || player?.isReadAlongDownloadReady == true
    guard hasLocalAudio else {
      errorMessage = EbookSyncError.downloadRequired.localizedDescription
      return
    }

    // Bereits gültiger Cache um den Anker → sofort als vorbereitet markieren.
    if hasValidCachedAlignment(
      player: player,
      libraryItemId: libraryItemId,
      ebookFileURL: ebookFileURL,
      downloadRoot: downloadRoot,
      anchorGlobalTime: anchorGlobalTime
    ) {
      preparedLibraryItemId = libraryItemId
      prepStatusMessage = String(localized: "Ready for Read & Listen", comment: "Ebook sync prep")
      return
    }

    if isPreparing, preparingLibraryItemId == libraryItemId, let prepTask {
      await prepTask.value
      return
    }

    prepTask?.cancel()
    let languageTag = preferredLanguageTag ?? player?.preferredTranscriptionLanguageTag
    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        let map = try await self.ensureAlignmentMap(
          player: player,
          libraryItemId: libraryItemId,
          ebookFileURL: ebookFileURL,
          downloadRoot: downloadRoot,
          preferredLanguageTag: languageTag,
          anchorGlobalTime: anchorGlobalTime,
          totalDurationHint: totalDurationHint
        )
        self.alignmentMap = map
        self.preparedLibraryItemId = libraryItemId
        self.prepStatusMessage = String(
          localized: "Ready for Read & Listen", comment: "Ebook sync prep")
      } catch is CancellationError {
        // cancelled
      } catch {
        self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        if self.preparedLibraryItemId == libraryItemId {
          self.preparedLibraryItemId = nil
        }
      }
    }
    prepTask = task
    await task.value
    if prepTask == task { prepTask = nil }
  }

  /// Startet Prep bei Bedarf und aktiviert den Sync-Mode.
  func startSyncMode(
    player: PlaybackController,
    libraryItemId: String,
    ebookFileURL: URL,
    ebookFormat: ABSEbookFormat
  ) async {
    errorMessage = nil
    guard ebookFormat == .epub else {
      errorMessage = EbookSyncError.epubRequired.localizedDescription
      return
    }
    guard isSyncAvailable else {
      errorMessage = EbookSyncError.speechUnavailable.localizedDescription
      return
    }
    guard player.isReadAlongDownloadReady else {
      errorMessage = EbookSyncError.downloadRequired.localizedDescription
      return
    }

    // Läuft bereits Prep für dieses Buch → darauf warten statt parallel.
    if isPreparing, preparingLibraryItemId == libraryItemId, let prepTask {
      await prepTask.value
    }

    boundPlayer = player
    activeLibraryItemId = libraryItemId
    activeEbookFileURL = ebookFileURL
    isSyncModeActive = true
    player.setReadAlongHighFrequencyTicks(true)

    do {
      let map = try await ensureAlignmentMap(
        player: player,
        libraryItemId: libraryItemId,
        ebookFileURL: ebookFileURL,
        anchorGlobalTime: player.liveGlobalPlaybackPosition,
        totalDurationHint: player.totalDuration
      )
      alignmentMap = map
      preparedLibraryItemId = libraryItemId
      syncGeneration &+= 1
      handlePlaybackTick(player: player)
    } catch is CancellationError {
      // cancelled
    } catch {
      errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      await stopSyncMode()
    }
  }

  func stopSyncMode() async {
    cancelPreparation()
    extendTask?.cancel()
    extendTask = nil
    isSyncModeActive = false
    activeSentenceId = nil
    activeEbookFileURL = nil
    boundPlayer?.setReadAlongHighFrequencyTicks(
      boundPlayer?.liveTranscription.isTeleprompterModeActive == true
    )
    boundPlayer = nil
  }

  /// Bricht eine laufende Vorbereitung ab.
  func cancelPreparation() {
    prepTask?.cancel()
    prepTask = nil
    isPreparing = false
    preparingLibraryItemId = nil
    prepProgress = nil
    prepStatusMessage = nil
  }

  func handlePlaybackTick(player: PlaybackController) {
    guard isSyncModeActive, let map = alignmentMap else { return }
    let live = player.liveGlobalPlaybackPosition
    maybeExtendAlignmentWindow(player: player, map: map, time: live)
    // Absatz-Markierung: Audiozeit direkt nutzen (kein Wort-Lag, kein 4s-Offset).
    guard let sentence = map.sentence(atGlobalTime: live) else {
      if activeSentenceId != nil { activeSentenceId = nil }
      return
    }
    if sentence.id != activeSentenceId {
      activeSentenceId = sentence.id
    }
  }

  /// Lädt das nächste Audio-Fenster nach, bevor der Cache endet.
  private func maybeExtendAlignmentWindow(
    player: PlaybackController,
    map: EbookAudioAlignmentMap,
    time: Double
  ) {
    guard let end = map.coveredGlobalEnd, let ebookURL = activeEbookFileURL,
      let libraryItemId = activeLibraryItemId
    else { return }
    // ~90 s vor Fensterende nachladen.
    guard end - time < 90, end - time > -30 else { return }
    let total = max(player.totalDuration, end)
    guard end < total - 15 else { return }
    guard extendTask == nil, !isPreparing else { return }
    extendTask = Task { @MainActor [weak self] in
      guard let self else { return }
      defer { self.extendTask = nil }
      do {
        let next = try await self.ensureAlignmentMap(
          player: player,
          libraryItemId: libraryItemId,
          ebookFileURL: ebookURL,
          preferredLanguageTag: player.preferredTranscriptionLanguageTag,
          anchorGlobalTime: min(total, end + 30),
          totalDurationHint: player.totalDuration,
          showProgress: false,
          forceRebuild: true
        )
        guard self.isSyncModeActive, self.activeLibraryItemId == libraryItemId else { return }
        if let current = self.alignmentMap {
          self.alignmentMap = current.merging(with: next)
        } else {
          self.alignmentMap = next
        }
        try? EbookAudioAlignmentStore.save(
          self.alignmentMap!, account: self.accountURL, userId: self.userId)
        // Kein syncGeneration-Bump — sonst erzwingt der Reader einen Scroll-Jump.
        self.handlePlaybackTick(player: player)
      } catch is CancellationError {
        // cancelled
      } catch {
        // Hintergrund-Extend still — laufender Sync bleibt mit bisherigem Fenster nutzbar.
      }
    }
  }

  /// Tippen auf einen Satz im EPUB → Audio-Seek (derzeit ungenutzt; Tap-Seek deaktiviert).
  func seekAudio(toSentenceId sentenceId: String, player: PlaybackController) {
    guard let map = alignmentMap,
      let sentence = map.sentences.first(where: { $0.id == sentenceId })
    else { return }
    player.seek(global: sentence.globalStart)
    activeSentenceId = sentence.id
    syncGeneration &+= 1
  }

  func activeSentence(for player: PlaybackController) -> AlignedSentence? {
    guard let map = alignmentMap else { return nil }
    return map.sentence(atGlobalTime: player.liveGlobalPlaybackPosition)
  }

  // MARK: - Prep

  func hasValidCachedAlignment(
    player: PlaybackController?,
    libraryItemId: String,
    ebookFileURL: URL,
    downloadRoot: URL? = nil,
    anchorGlobalTime: Double = 0
  ) -> Bool {
    guard
      let fingerprints = alignmentFingerprints(
        player: player,
        libraryItemId: libraryItemId,
        ebookFileURL: ebookFileURL,
        downloadRoot: downloadRoot
      )
    else { return false }
    guard
      let cached = EbookAudioAlignmentStore.load(
        account: accountURL, userId: userId, libraryItemId: libraryItemId),
      cached.ebookFileHash == fingerprints.ebookHash,
      cached.audioFingerprint == fingerprints.audioHash,
      !cached.sentences.isEmpty,
      cached.covers(globalTime: anchorGlobalTime)
    else { return false }
    return true
  }

  /// Aktualisiert `preparedLibraryItemId`, wenn Cache für das Item gültig ist.
  func refreshPreparedState(
    player: PlaybackController?,
    libraryItemId: String,
    ebookFileURL: URL,
    downloadRoot: URL? = nil,
    anchorGlobalTime: Double = 0
  ) {
    if hasValidCachedAlignment(
      player: player,
      libraryItemId: libraryItemId,
      ebookFileURL: ebookFileURL,
      downloadRoot: downloadRoot,
      anchorGlobalTime: anchorGlobalTime
    ) {
      preparedLibraryItemId = libraryItemId
    } else if preparedLibraryItemId == libraryItemId {
      preparedLibraryItemId = nil
    }
  }

  private func resolveTotalDuration(
    player: PlaybackController?,
    downloadRoot: URL?,
    hint: Double?
  ) -> Double {
    if let hint, hint > 1 { return hint }
    if let downloadRoot, let manifest = ABSDownloadManifest.load(from: downloadRoot) {
      if let total = manifest.totalDuration, total > 1 { return total }
      let sum = manifest.tracks.reduce(0) { $0 + $1.duration }
      if sum > 1 { return sum }
    }
    if let player, player.totalDuration > 1 { return player.totalDuration }
    return 1
  }

  private func resolveAudioContexts(
    player: PlaybackController?,
    downloadRoot: URL?,
    overlapping: ClosedRange<Double>
  ) -> [PlayerTranscriptionAudioContext] {
    if let downloadRoot {
      return PlaybackController.makeLocalTranscriptionAudioContexts(
        root: downloadRoot,
        overlapping: overlapping
      )
    }
    guard let player else { return [] }
    return player.makeLocalTranscriptionAudioContexts(overlapping: overlapping)
  }

  /// Fingerprint über alle lokalen Tracks (unabhängig vom Prep-Fenster).
  private func alignmentFingerprints(
    player: PlaybackController?,
    libraryItemId: String,
    ebookFileURL: URL,
    downloadRoot: URL? = nil
  ) -> (ebookHash: String, audioHash: String)? {
    _ = libraryItemId
    let ebookHash = EbookAudioAlignmentStore.fileFingerprint(url: ebookFileURL)
    let fullRange = 0...(max(resolveTotalDuration(player: player, downloadRoot: downloadRoot, hint: nil), 1))
    let contexts = resolveAudioContexts(
      player: player, downloadRoot: downloadRoot, overlapping: fullRange)
    guard !contexts.isEmpty else { return nil }
    let audioHash = EbookAudioAlignmentStore.audioFingerprint(
      trackURLs: contexts.map(\.assetURL),
      trackOffsets: contexts.map(\.trackGlobalOffset)
    )
    return (ebookHash, audioHash)
  }

  private func ensureAlignmentMap(
    player: PlaybackController?,
    libraryItemId: String,
    ebookFileURL: URL,
    downloadRoot: URL? = nil,
    preferredLanguageTag: String? = nil,
    anchorGlobalTime: Double = 0,
    totalDurationHint: Double? = nil,
    showProgress: Bool = true,
    forceRebuild: Bool = false
  ) async throws -> EbookAudioAlignmentMap {
    let ebookHash = EbookAudioAlignmentStore.fileFingerprint(url: ebookFileURL)
    let totalDuration = resolveTotalDuration(
      player: player, downloadRoot: downloadRoot, hint: totalDurationHint)
    let audioWindow = EbookSyncPrepWindow.range(
      around: max(0, anchorGlobalTime),
      totalDuration: totalDuration
    )
    let contexts = resolveAudioContexts(
      player: player, downloadRoot: downloadRoot, overlapping: audioWindow)
    guard !contexts.isEmpty else { throw EbookSyncError.audioUnavailable }

    let fullContexts = resolveAudioContexts(
      player: player,
      downloadRoot: downloadRoot,
      overlapping: 0...totalDuration
    )
    let audioHash = EbookAudioAlignmentStore.audioFingerprint(
      trackURLs: (fullContexts.isEmpty ? contexts : fullContexts).map(\.assetURL),
      trackOffsets: (fullContexts.isEmpty ? contexts : fullContexts).map(\.trackGlobalOffset)
    )
    let languageTag = preferredLanguageTag ?? player?.preferredTranscriptionLanguageTag

    if !forceRebuild,
      let cached = EbookAudioAlignmentStore.load(
        account: accountURL,
        userId: userId,
        libraryItemId: libraryItemId
      ),
      cached.ebookFileHash == ebookHash,
      cached.audioFingerprint == audioHash,
      !cached.sentences.isEmpty,
      cached.covers(globalTime: anchorGlobalTime)
    {
      preparedLibraryItemId = libraryItemId
      return cached
    }

    if showProgress {
      isPreparing = true
      preparingLibraryItemId = libraryItemId
      prepProgress = 0
      prepStatusMessage = String(localized: "Preparing ebook sync…", comment: "Ebook sync prep")
    }
    defer {
      if showProgress {
        isPreparing = false
        preparingLibraryItemId = nil
        prepProgress = nil
        if Task.isCancelled {
          prepStatusMessage = nil
        }
      }
    }

    let map = try await aligner.align(
      libraryItemId: libraryItemId,
      ebookFileURL: ebookFileURL,
      contexts: contexts,
      preferredLanguageTag: languageTag,
      ebookFileHash: ebookHash,
      audioFingerprint: audioHash,
      audioWindow: audioWindow
    ) { [weak self] progress in
      guard showProgress else { return }
      self?.prepProgress = progress.fraction
      self?.prepStatusMessage = progress.statusMessage
    }

    try EbookAudioAlignmentStore.save(map, account: accountURL, userId: userId)
    preparedLibraryItemId = libraryItemId
    return map
  }
}

// MARK: - Readium JS bridge helpers

enum EbookSyncHighlightBridge {
  /// Markiert Blatt-Absätze (p/li/h*) ohne Text umzuschreiben; liefert Anzahl.
  static func installMarkupScript(chapterIndex: Int) -> String {
    """
    (function() {
      var existing = document.querySelectorAll('.abs-sync-para[data-abs-para-id]').length;
      if (window.__absSyncInstalled === \(chapterIndex) && existing > 0) {
        return { installed: true, count: existing };
      }
      // Altes Satz-/Wort-Markup und Anker entfernen (DOM-Reload / Migration).
      document.querySelectorAll('span.abs-sync-word, span.abs-sync-sentence').forEach(function(el) {
        var t = document.createTextNode(el.textContent || '');
        el.parentNode && el.parentNode.replaceChild(t, el);
      });
      document.querySelectorAll('span.abs-sync-para-anchor').forEach(function(el) {
        el.parentNode && el.parentNode.removeChild(el);
      });
      document.querySelectorAll('.abs-sync-para').forEach(function(el) {
        el.classList.remove('abs-sync-para', 'abs-sync-active');
        el.removeAttribute('data-abs-para-id');
        el.removeAttribute('data-abs-para-text');
      });
      var style = document.getElementById('abs-sync-style');
      if (!style) {
        style = document.createElement('style');
        style.id = 'abs-sync-style';
        document.head.appendChild(style);
      }
      style.textContent = `
        .abs-sync-para.abs-sync-active {
          background: rgba(255, 196, 0, 0.34) !important;
          border-radius: 2px;
          box-decoration-break: clone;
          -webkit-box-decoration-break: clone;
        }
        span.abs-sync-para-anchor {
          display: inline;
          width: 0;
          height: 0;
          overflow: hidden;
          font-size: 0;
          line-height: 0;
        }
      `;

      var roots = Array.prototype.slice.call(
        document.querySelectorAll('p, div, li, h1, h2, h3, h4, h5, h6, blockquote')
      );
      var paraIndex = 0;
      roots.forEach(function(node) {
        if (node.classList.contains('abs-sync-para')) return;
        if (node.closest && node.closest('.abs-sync-para')) return;
        // Nur Blatt-Blöcke — Container mit verschachtelten Absätzen überspringen.
        if (node.querySelector('p, div, li, h1, h2, h3, h4, h5, h6, blockquote')) return;
        var text = (node.textContent || '').replace(/\\s+/g, ' ').replace(/^\\s+|\\s+$/g, '');
        if (!text || text.length < 8) return;
        var pid = 'abs-p-' + \(chapterIndex) + '-' + paraIndex;
        node.classList.add('abs-sync-para');
        node.setAttribute('data-abs-para-id', pid);
        node.setAttribute('data-abs-para-text', text);
        // Fragment-Anker für Readium go(to:) — bestehende EPUB-IDs nicht überschreiben.
        var hasAnchor = false;
        for (var c = node.firstChild; c; c = c.nextSibling) {
          if (c.nodeType === 1 && c.classList && c.classList.contains('abs-sync-para-anchor')) {
            hasAnchor = true;
            break;
          }
        }
        if (!hasAnchor) {
          var anchor = document.createElement('span');
          anchor.id = pid;
          anchor.className = 'abs-sync-para-anchor';
          anchor.setAttribute('aria-hidden', 'true');
          node.insertBefore(anchor, node.firstChild);
        }
        paraIndex += 1;
      });
      window.__absSyncInstalled = \(chapterIndex);
      return { installed: true, count: paraIndex };
    })();
    """
  }

  /// Hebt den passenden Absatz hervor. Rückgabe: `{ applied, visible, scrolled, paraId }`.
  static func highlightScript(
    sentenceText: String?,
    scrollIntoView: Bool = true
  ) -> String {
    let needle = (sentenceText ?? "")
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "'", with: "\\'")
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: "\r", with: " ")
    let doScroll = scrollIntoView ? "true" : "false"
    return """
    (function() {
      function norm(s) {
        return (s || '').toLowerCase()
          .replace(/[“”„"']/g, '')
          .replace(/[.,;:!?…()\\[\\]{}\\-—–]/g, ' ')
          .replace(/\\s+/g, ' ')
          .replace(/^\\s+|\\s+$/g, '');
      }
      function tokenOverlap(a, b) {
        var ta = a.split(' ').filter(Boolean);
        var tb = b.split(' ').filter(Boolean);
        if (!ta.length || !tb.length) return 0;
        var setB = {};
        for (var i = 0; i < tb.length; i++) setB[tb[i]] = true;
        var hits = 0;
        var n = Math.min(ta.length, 24);
        for (var j = 0; j < n; j++) {
          if (setB[ta[j]]) hits += 1;
        }
        return hits / n;
      }
      function isComfortablyVisible(el) {
        var rect = el.getBoundingClientRect();
        var vw = Math.max(1, window.innerWidth);
        var vh = Math.max(1, window.innerHeight);
        var midY = rect.top + rect.height * 0.35;
        var midX = rect.left + Math.min(rect.width, vw) * 0.5;
        return midY >= vh * 0.12 && midY <= vh * 0.78
          && midX >= vw * 0.05 && midX <= vw * 0.95
          && rect.bottom > vh * 0.08 && rect.top < vh * 0.92;
      }
      function bringIntoView(el) {
        if (!el) return { scrolled: false, visible: false };
        if (isComfortablyVisible(el)) {
          return { scrolled: false, visible: true };
        }
        try {
          el.scrollIntoView({ block: 'center', inline: 'center', behavior: 'auto' });
        } catch (e1) {
          try { el.scrollIntoView(true); } catch (e2) {}
        }
        // Fallback paginiert: Spalten per scrollLeft der scrollbaren Vorfahren.
        if (!isComfortablyVisible(el)) {
          var rect = el.getBoundingClientRect();
          var vw = Math.max(1, window.innerWidth);
          var vh = Math.max(1, window.innerHeight);
          var node = el.parentElement;
          while (node && node !== document.body) {
            var style = window.getComputedStyle(node);
            var ox = style.overflowX;
            var oy = style.overflowY;
            var canX = (ox === 'auto' || ox === 'scroll' || ox === 'overlay')
              && node.scrollWidth > node.clientWidth + 8;
            var canY = (oy === 'auto' || oy === 'scroll' || oy === 'overlay')
              && node.scrollHeight > node.clientHeight + 8;
            if (canY) {
              var top = el.getBoundingClientRect().top - node.getBoundingClientRect().top + node.scrollTop;
              node.scrollTop = Math.max(0, top - node.clientHeight * 0.35);
            }
            if (canX) {
              var left = el.getBoundingClientRect().left - node.getBoundingClientRect().left + node.scrollLeft;
              var page = Math.floor((left + 1) / Math.max(1, node.clientWidth));
              node.scrollLeft = page * node.clientWidth;
            }
            node = node.parentElement;
          }
          // window-Ebene (Readium scroll/paginated oft hier).
          if (!isComfortablyVisible(el)) {
            rect = el.getBoundingClientRect();
            var root = document.scrollingElement || document.documentElement;
            var vertical = root.scrollHeight > root.clientHeight * 1.15;
            if (vertical) {
              var y = window.scrollY + rect.top - vh * 0.3;
              window.scrollTo(window.scrollX, Math.max(0, y));
            } else {
              var elCenter = window.scrollX + rect.left + rect.width * 0.5;
              var targetPage = Math.floor(elCenter / vw);
              if (targetPage < 0) targetPage = 0;
              window.scrollTo(targetPage * vw, 0);
            }
          }
        }
        return { scrolled: true, visible: isComfortablyVisible(el) };
      }

      document.querySelectorAll('.abs-sync-para.abs-sync-active').forEach(function(el) {
        el.classList.remove('abs-sync-active');
      });
      // Legacy-Klassen aufräumen.
      document.querySelectorAll('span.abs-sync-sentence.abs-sync-active, span.abs-sync-word.abs-sync-word-active')
        .forEach(function(el) {
          el.classList.remove('abs-sync-active', 'abs-sync-word-active');
        });

      var needle = '\(needle)';
      if (!needle) return { applied: false, visible: false, scrolled: false, paraId: null };
      var all = document.querySelectorAll('.abs-sync-para[data-abs-para-id]');
      if (!all.length) return { applied: false, visible: false, scrolled: false, paraId: null };

      var target = norm(needle);
      var best = null;
      var bestScore = 0;
      for (var i = 0; i < all.length; i++) {
        var raw = all[i].getAttribute('data-abs-para-text') || all[i].textContent || '';
        var cand = norm(raw);
        if (!cand) continue;
        var score = 0;
        if (cand.indexOf(target) !== -1) {
          score = 0.92 + Math.min(0.08, target.length / Math.max(cand.length, 1));
        } else if (target.indexOf(cand) !== -1 && cand.length >= 24) {
          score = 0.7;
        } else {
          score = tokenOverlap(target, cand);
          // Präfix der ersten Wörter im Absatz gewichten.
          var prefix = tokenOverlap(target, cand.split(' ').slice(0, 16).join(' '));
          score = Math.max(score, prefix * 0.95);
        }
        if (score > bestScore) { bestScore = score; best = all[i]; }
      }
      if (!best || bestScore < 0.35) {
        return { applied: false, visible: false, scrolled: false, paraId: null };
      }
      best.classList.add('abs-sync-active');
      var paraId = best.getAttribute('data-abs-para-id') || null;
      var scrollResult = { scrolled: false, visible: isComfortablyVisible(best) };
      if (\(doScroll)) {
        scrollResult = bringIntoView(best);
      }
      return {
        applied: true,
        visible: !!scrollResult.visible,
        scrolled: !!scrollResult.scrolled,
        paraId: paraId
      };
    })();
    """
  }

  static func tappedSentenceIdScript() -> String {
    """
    (function() {
      if (window.__absSyncTapBound) return true;
      window.__absSyncLastTapSentenceId = null;
      document.addEventListener('click', function(ev) {
        var t = ev.target;
        if (!t) return;
        var para = t.closest ? t.closest('.abs-sync-para') : null;
        if (!para) return;
        window.__absSyncLastTapSentenceId = para.getAttribute('data-abs-para-id') || null;
      }, true);
      window.__absSyncTapBound = true;
      return true;
    })();
    """
  }

  static func consumeTapScript() -> String {
    """
    (function() {
      var id = window.__absSyncLastTapSentenceId || null;
      window.__absSyncLastTapSentenceId = null;
      return id;
    })();
    """
  }
}

/// Ergebnis eines Highlight-/Scroll-Versuchs im EPUB-DOM.
struct EbookSyncHighlightApplyResult: Equatable, Sendable {
  var applied: Bool
  var visible: Bool
  var scrolled: Bool
  var paraId: String?

  static let failed = EbookSyncHighlightApplyResult(
    applied: false, visible: false, scrolled: false, paraId: nil)
}
