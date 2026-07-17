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
  @Published private(set) var activeWordIndex: Int?
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
  private var lastHighlightSentenceId: String?
  private var lastHighlightWordIndex: Int?
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
    activeWordIndex = nil
    lastHighlightSentenceId = nil
    lastHighlightWordIndex = nil
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

  /// Speech-`audioTimeRange` liegt typischerweise vor dem hörbaren Wort — stark nachziehen.
  private static let highlightLagSeconds: Double = 4.0

  func handlePlaybackTick(player: PlaybackController) {
    guard isSyncModeActive, let map = alignmentMap else { return }
    let live = player.liveGlobalPlaybackPosition
    maybeExtendAlignmentWindow(player: player, map: map, time: live)
    // Zusätzlich Wort-Mitte nutzen: Lookup leicht hinter dem Wortanfang.
    let time = max(0, live - Self.highlightLagSeconds)
    guard let sentence = map.sentence(atGlobalTime: time) else { return }
    let word = map.word(atGlobalTime: time, in: sentence)
    let wordIndex = word?.index
    if sentence.id != activeSentenceId || wordIndex != activeWordIndex {
      activeSentenceId = sentence.id
      activeWordIndex = wordIndex
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

  /// Tippen auf einen Satz im EPUB → Audio-Seek.
  func seekAudio(toSentenceId sentenceId: String, player: PlaybackController) {
    guard let map = alignmentMap,
      let sentence = map.sentences.first(where: { $0.id == sentenceId })
    else { return }
    player.seek(global: sentence.globalStart)
    activeSentenceId = sentence.id
    activeWordIndex = sentence.words.first?.index
    syncGeneration &+= 1
  }

  func activeSentence(for player: PlaybackController) -> AlignedSentence? {
    guard let map = alignmentMap else { return nil }
    let time = max(0, player.liveGlobalPlaybackPosition - Self.highlightLagSeconds)
    return map.sentence(atGlobalTime: time)
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
  /// Injiziert Satz-Spans und CSS; liefert Anzahl gemarkter Sätze.
  static func installMarkupScript(chapterIndex: Int) -> String {
    """
    (function() {
      var existing = document.querySelectorAll('span.abs-sync-sentence').length;
      if (window.__absSyncInstalled === \(chapterIndex) && existing > 0) {
        return { installed: true, count: existing };
      }
      // Alte Spans nach DOM-Reload / Kapitelwechsel entfernen.
      document.querySelectorAll('span.abs-sync-word').forEach(function(el) {
        var t = document.createTextNode(el.textContent || '');
        el.parentNode && el.parentNode.replaceChild(t, el);
      });
      document.querySelectorAll('span.abs-sync-sentence').forEach(function(el) {
        var t = document.createTextNode(el.textContent || '');
        el.parentNode && el.parentNode.replaceChild(t, el);
      });
      var style = document.getElementById('abs-sync-style');
      if (!style) {
        style = document.createElement('style');
        style.id = 'abs-sync-style';
        document.head.appendChild(style);
      }
      style.textContent = `
        span.abs-sync-sentence.abs-sync-active {
          background: rgba(255, 196, 0, 0.38) !important;
          border-radius: 2px;
          box-decoration-break: clone;
          -webkit-box-decoration-break: clone;
        }
        span.abs-sync-word.abs-sync-word-active {
          background: rgba(255, 140, 0, 0.62) !important;
          border-radius: 2px;
          box-decoration-break: clone;
          -webkit-box-decoration-break: clone;
        }
      `;

      function splitSentences(text) {
        var parts = [];
        var current = '';
        for (var i = 0; i < text.length; i++) {
          var ch = text[i];
          current += ch;
          if ('.!?…'.indexOf(ch) !== -1) {
            var t = current.replace(/^\\s+|\\s+$/g, '');
            if (t.length >= 2) parts.push(t);
            current = '';
          }
        }
        var tail = current.replace(/^\\s+|\\s+$/g, '');
        if (tail) parts.push(tail);
        return parts.filter(function(s) {
          var words = s.split(/\\s+/).filter(Boolean);
          return words.length >= 2 || s.length >= 12;
        });
      }

      function wrapWords(sentenceEl, sentenceId) {
        var text = sentenceEl.textContent || '';
        var tokens = text.split(/(\\s+)/);
        sentenceEl.textContent = '';
        var wordIndex = 0;
        tokens.forEach(function(tok) {
          if (!tok) return;
          if (/^\\s+$/.test(tok)) {
            sentenceEl.appendChild(document.createTextNode(tok));
            return;
          }
          var span = document.createElement('span');
          span.className = 'abs-sync-word';
          span.setAttribute('data-abs-word-index', String(wordIndex));
          span.setAttribute('data-abs-sentence-id', sentenceId);
          span.textContent = tok;
          sentenceEl.appendChild(span);
          wordIndex += 1;
        });
      }

      var roots = Array.prototype.slice.call(document.querySelectorAll('p, div, li, h1, h2, h3, h4, h5, h6'));
      var sentenceIndex = 0;
      roots.forEach(function(node) {
        if (node.closest('span.abs-sync-sentence')) return;
        if (node.querySelector('p, div, li, h1, h2, h3, h4, h5, h6')) return;
        var text = (node.textContent || '').replace(/\\s+/g, ' ').replace(/^\\s+|\\s+$/g, '');
        if (!text) return;
        var sentences = splitSentences(text);
        if (!sentences.length) return;
        node.textContent = '';
        sentences.forEach(function(sentenceText, idx) {
          if (idx > 0) node.appendChild(document.createTextNode(' '));
          var span = document.createElement('span');
          var sid = 'abs-s-' + \(chapterIndex) + '-' + sentenceIndex;
          span.id = sid;
          span.className = 'abs-sync-sentence';
          span.setAttribute('data-abs-sentence-id', sid);
          span.setAttribute('data-abs-sentence-text', sentenceText);
          span.textContent = sentenceText;
          wrapWords(span, sid);
          node.appendChild(span);
          sentenceIndex += 1;
        });
      });
      window.__absSyncInstalled = \(chapterIndex);
      return { installed: true, count: sentenceIndex };
    })();
    """
  }

  static func highlightScript(
    sentenceId: String?,
    wordIndex: Int?,
    sentenceText: String? = nil,
    scrollIntoView: Bool = true
  ) -> String {
    let sid = sentenceId?.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "'", with: "\\'")
      .replacingOccurrences(of: "\n", with: " ") ?? ""
    let needle = (sentenceText ?? "")
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "'", with: "\\'")
      .replacingOccurrences(of: "\n", with: " ")
    let word = wordIndex.map(String.init) ?? ""
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
      function tokenPrefixScore(a, b) {
        var ta = a.split(' ').filter(Boolean);
        var tb = b.split(' ').filter(Boolean);
        if (!ta.length || !tb.length) return 0;
        var n = Math.min(8, ta.length, tb.length);
        var hits = 0;
        for (var i = 0; i < n; i++) {
          if (ta[i] === tb[i]) hits += 1;
        }
        return hits / n;
      }
      function bringIntoView(el) {
        if (!el) return;
        var root = document.scrollingElement || document.documentElement;
        var rect = el.getBoundingClientRect();
        var vw = Math.max(1, window.innerWidth);
        var vh = Math.max(1, window.innerHeight);
        // Nur scrollen wenn wirklich außerhalb — kein ständiges Re-Centern.
        var visible =
          rect.top < vh * 0.9 && rect.bottom > vh * 0.1 &&
          rect.left < vw * 0.92 && rect.right > vw * 0.08;
        if (visible) return;
        var vertical = root.scrollHeight > root.clientHeight * 1.2;
        if (vertical) {
          try { el.scrollIntoView({ block: 'nearest', inline: 'nearest', behavior: 'auto' }); } catch (e) {
            try { el.scrollIntoView(false); } catch (e2) {}
          }
          return;
        }
        // Paginierte Spalten: nur bei echter Seitenänderung, ohne smooth (vermeidet Oszillation).
        var curPage = Math.floor((Math.abs(window.scrollX) + 1) / vw);
        var elCenter = window.scrollX + rect.left + (rect.width * 0.5);
        var targetPage = Math.floor(elCenter / vw);
        if (targetPage < 0) targetPage = 0;
        if (targetPage === curPage) return;
        window.scrollTo(targetPage * vw, 0);
      }
      document.querySelectorAll('span.abs-sync-sentence.abs-sync-active').forEach(function(el) {
        el.classList.remove('abs-sync-active');
      });
      document.querySelectorAll('span.abs-sync-word.abs-sync-word-active').forEach(function(el) {
        el.classList.remove('abs-sync-word-active');
      });
      var sid = '\(sid)';
      var needle = '\(needle)';
      if (!sid && !needle) return false;
      var all = document.querySelectorAll('span.abs-sync-sentence');
      if (!all.length) return false;
      var sentence = null;
      // Text zuerst — IDs aus Extractor und DOM-Splitter können divergieren.
      if (needle) {
        var target = norm(needle);
        var bestScore = 0;
        for (var i = 0; i < all.length; i++) {
          var raw = all[i].getAttribute('data-abs-sentence-text') || all[i].textContent || '';
          var cand = norm(raw);
          if (!cand) continue;
          if (cand === target) { sentence = all[i]; bestScore = 1; break; }
          var score = tokenPrefixScore(target, cand);
          if (cand.indexOf(target) !== -1 || target.indexOf(cand) !== -1) {
            score = Math.max(score, Math.min(cand.length, target.length) / Math.max(cand.length, target.length));
          }
          if (score > bestScore) { bestScore = score; sentence = all[i]; }
        }
        if (bestScore < 0.45) sentence = null;
      }
      if (!sentence && sid) {
        sentence = document.getElementById(sid)
          || document.querySelector('span[data-abs-sentence-id=\"' + sid + '\"]');
      }
      if (!sentence) return false;
      sentence.classList.add('abs-sync-active');
      var w = '\(word)';
      var focusEl = sentence;
      if (w !== '') {
        var wordEl = sentence.querySelector('span.abs-sync-word[data-abs-word-index=\"' + w + '\"]');
        if (wordEl) {
          wordEl.classList.add('abs-sync-word-active');
          focusEl = wordEl;
        }
      }
      if (\(doScroll)) bringIntoView(focusEl);
      return true;
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
        var sentence = t.closest ? t.closest('span.abs-sync-sentence') : null;
        if (!sentence) return;
        window.__absSyncLastTapSentenceId = sentence.getAttribute('data-abs-sentence-id') || sentence.id || null;
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
