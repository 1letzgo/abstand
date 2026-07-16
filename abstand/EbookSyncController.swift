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
  private var activeLibraryItemId: String?
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

  /// Nur Alignment vorbereiten (kein Reader, kein Sync-Mode).
  /// `downloadRoot` erlaubt Prep ohne aktiven Player (Prepare-Queue).
  func prepareAlignment(
    player: PlaybackController?,
    libraryItemId: String,
    ebookFileURL: URL,
    ebookFormat: ABSEbookFormat,
    downloadRoot: URL? = nil,
    preferredLanguageTag: String? = nil
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

    // Bereits gültiger Cache → sofort als vorbereitet markieren.
    if hasValidCachedAlignment(
      player: player,
      libraryItemId: libraryItemId,
      ebookFileURL: ebookFileURL,
      downloadRoot: downloadRoot
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
          preferredLanguageTag: languageTag
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
    isSyncModeActive = true
    player.setReadAlongHighFrequencyTicks(true)

    do {
      let map = try await ensureAlignmentMap(
        player: player,
        libraryItemId: libraryItemId,
        ebookFileURL: ebookFileURL
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
    isSyncModeActive = false
    activeSentenceId = nil
    activeWordIndex = nil
    lastHighlightSentenceId = nil
    lastHighlightWordIndex = nil
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
    let time = player.liveGlobalPlaybackPosition
    guard let sentence = map.sentence(atGlobalTime: time) else { return }
    let word = map.word(atGlobalTime: time, in: sentence)
    let wordIndex = word?.index
    if sentence.id != activeSentenceId || wordIndex != activeWordIndex {
      activeSentenceId = sentence.id
      activeWordIndex = wordIndex
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
    return map.sentence(atGlobalTime: player.liveGlobalPlaybackPosition)
  }

  // MARK: - Prep

  func hasValidCachedAlignment(
    player: PlaybackController?,
    libraryItemId: String,
    ebookFileURL: URL,
    downloadRoot: URL? = nil
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
      !cached.sentences.isEmpty
    else { return false }
    return true
  }

  /// Aktualisiert `preparedLibraryItemId`, wenn Cache für das Item gültig ist.
  func refreshPreparedState(
    player: PlaybackController?,
    libraryItemId: String,
    ebookFileURL: URL,
    downloadRoot: URL? = nil
  ) {
    if hasValidCachedAlignment(
      player: player,
      libraryItemId: libraryItemId,
      ebookFileURL: ebookFileURL,
      downloadRoot: downloadRoot
    ) {
      preparedLibraryItemId = libraryItemId
    } else if preparedLibraryItemId == libraryItemId {
      preparedLibraryItemId = nil
    }
  }

  private func resolveAudioContexts(
    player: PlaybackController?,
    downloadRoot: URL?
  ) -> [PlayerTranscriptionAudioContext] {
    if let downloadRoot {
      return PlaybackController.makeLocalTranscriptionAudioContexts(root: downloadRoot)
    }
    guard let player else { return [] }
    return player.makeLocalTranscriptionAudioContexts(
      overlapping: 0...(max(player.totalDuration, 1))
    )
  }

  private func alignmentFingerprints(
    player: PlaybackController?,
    libraryItemId: String,
    ebookFileURL: URL,
    downloadRoot: URL? = nil
  ) -> (ebookHash: String, audioHash: String)? {
    _ = libraryItemId
    let ebookHash = EbookAudioAlignmentStore.fileFingerprint(url: ebookFileURL)
    let contexts = resolveAudioContexts(player: player, downloadRoot: downloadRoot)
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
    preferredLanguageTag: String? = nil
  ) async throws -> EbookAudioAlignmentMap {
    let ebookHash = EbookAudioAlignmentStore.fileFingerprint(url: ebookFileURL)
    let contexts = resolveAudioContexts(player: player, downloadRoot: downloadRoot)
    guard !contexts.isEmpty else { throw EbookSyncError.audioUnavailable }
    let audioHash = EbookAudioAlignmentStore.audioFingerprint(
      trackURLs: contexts.map(\.assetURL),
      trackOffsets: contexts.map(\.trackGlobalOffset)
    )
    let languageTag = preferredLanguageTag ?? player?.preferredTranscriptionLanguageTag

    if let cached = EbookAudioAlignmentStore.load(
      account: accountURL,
      userId: userId,
      libraryItemId: libraryItemId
    ),
      cached.ebookFileHash == ebookHash,
      cached.audioFingerprint == audioHash,
      !cached.sentences.isEmpty
    {
      preparedLibraryItemId = libraryItemId
      return cached
    }

    isPreparing = true
    preparingLibraryItemId = libraryItemId
    prepProgress = 0
    prepStatusMessage = String(localized: "Preparing ebook sync…", comment: "Ebook sync prep")
    defer {
      isPreparing = false
      preparingLibraryItemId = nil
      // Status-/Progress nach erfolgreicher Prep kurz stehen lassen (UI), sonst leeren.
      if Task.isCancelled {
        prepProgress = nil
        prepStatusMessage = nil
      } else {
        prepProgress = nil
      }
    }

    let map = try await aligner.align(
      libraryItemId: libraryItemId,
      ebookFileURL: ebookFileURL,
      contexts: contexts,
      preferredLanguageTag: languageTag,
      ebookFileHash: ebookHash,
      audioFingerprint: audioHash
    ) { [weak self] progress in
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
      if (window.__absSyncInstalled === \(chapterIndex)) {
        return { installed: true, count: document.querySelectorAll('span.abs-sync-sentence').length };
      }
      if (!document.getElementById('abs-sync-style')) {
        var style = document.createElement('style');
        style.id = 'abs-sync-style';
        style.textContent = `
          span.abs-sync-sentence.abs-sync-active {
            background: rgba(255, 196, 0, 0.28);
            border-radius: 2px;
          }
          span.abs-sync-word.abs-sync-word-active {
            background: rgba(255, 140, 0, 0.45);
            border-radius: 2px;
          }
        `;
        document.head.appendChild(style);
      }

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

  static func highlightScript(sentenceId: String?, wordIndex: Int?, sentenceText: String? = nil) -> String {
    let sid = sentenceId?.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "'", with: "\\'")
      .replacingOccurrences(of: "\n", with: " ") ?? ""
    let needle = (sentenceText ?? "")
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "'", with: "\\'")
      .replacingOccurrences(of: "\n", with: " ")
    let word = wordIndex.map(String.init) ?? ""
    return """
    (function() {
      document.querySelectorAll('span.abs-sync-sentence.abs-sync-active').forEach(function(el) {
        el.classList.remove('abs-sync-active');
      });
      document.querySelectorAll('span.abs-sync-word.abs-sync-word-active').forEach(function(el) {
        el.classList.remove('abs-sync-word-active');
      });
      var sid = '\(sid)';
      var needle = '\(needle)';
      if (!sid && !needle) return false;
      var sentence = sid
        ? (document.getElementById(sid) || document.querySelector('span[data-abs-sentence-id=\"' + sid + '\"]'))
        : null;
      if (!sentence && needle) {
        var all = document.querySelectorAll('span.abs-sync-sentence');
        var norm = function(s) { return (s || '').toLowerCase().replace(/\\s+/g, ' ').replace(/^\\s+|\\s+$/g, ''); };
        var target = norm(needle);
        for (var i = 0; i < all.length; i++) {
          if (norm(all[i].textContent).indexOf(target) !== -1 || target.indexOf(norm(all[i].textContent)) !== -1) {
            sentence = all[i];
            break;
          }
        }
      }
      if (!sentence) return false;
      sentence.classList.add('abs-sync-active');
      var w = '\(word)';
      if (w !== '') {
        var wordEl = sentence.querySelector('span.abs-sync-word[data-abs-word-index=\"' + w + '\"]');
        if (wordEl) {
          wordEl.classList.add('abs-sync-word-active');
          try { wordEl.scrollIntoView({ block: 'center', inline: 'nearest', behavior: 'smooth' }); } catch (e) {}
          return true;
        }
      }
      try { sentence.scrollIntoView({ block: 'center', inline: 'nearest', behavior: 'smooth' }); } catch (e) {}
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
