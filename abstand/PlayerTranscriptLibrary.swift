import AVFoundation
import Foundation
import Speech

/// Eine lokale Track-Datei mit ihrer Lage im Hörbuch — Grundlage für Vorproduktion und Recap.
struct PlayerTranscriptTrackSource: Sendable {
  let trackIndex: Int
  let assetURL: URL
  let globalOffset: Double
  let duration: Double

  var globalRange: ClosedRange<Double> { globalOffset...(globalOffset + max(0, duration)) }
}

/// Gemeinsamer Zugriff auf persistierte Transkripte: liest aus dem Cache und produziert nur,
/// was dort noch fehlt. Teleprompter, Recap und Hintergrund-Vorproduktion teilen sich damit
/// dieselben Daten — jede Sekunde Audio wird höchstens einmal durch die Spracherkennung geschickt.
@MainActor
enum PlayerTranscriptLibrary {
  /// Vordergrund-Arbeit (Teleprompter, Recap) läuft; die Hintergrund-Vorproduktion pausiert
  /// solange. Zwei parallele `SpeechAnalyzer` würden sich Speicher und Rechenzeit wegnehmen.
  private(set) static var priorityWorkCount = 0

  static var isPriorityWorkActive: Bool { priorityWorkCount > 0 }

  static func beginPriorityWork() { priorityWorkCount += 1 }

  static func endPriorityWork() { priorityWorkCount = max(0, priorityWorkCount - 1) }
  /// Wortliste eines Tracks aus dem Cache (lokale Track-Sekunden).
  static func cachedWords(
    bookId: String,
    trackIndex: Int,
    locale: Locale
  ) async -> [PlayerTranscriptTrackCache.Word] {
    await cache(bookId: bookId, trackIndex: trackIndex, locale: locale)?.allWords ?? []
  }

  /// Transkriptdatei lesen. Das JSON eines Tracks ist schnell ein paar hundert Kilobyte —
  /// Lesen und Dekodieren gehören deshalb vom MainActor herunter, sonst ruckelt die Wiedergabe-UI
  /// bei jedem Track-Wechsel und bei jedem Zwischenspeichern der Vorproduktion.
  static func cache(
    bookId: String,
    trackIndex: Int,
    locale: Locale
  ) async -> PlayerTranscriptTrackCache? {
    let account = PlayerTranscriptCacheStore.activeAccount
    let localeId = locale.identifier(.bcp47)
    return await loadOffMain(
      account: account, bookId: bookId, trackIndex: trackIndex, localeIdentifier: localeId)
  }

  nonisolated private static func loadOffMain(
    account: URL?,
    bookId: String,
    trackIndex: Int,
    localeIdentifier: String
  ) async -> PlayerTranscriptTrackCache? {
    await Task.detached(priority: .utility) {
      PlayerTranscriptCacheStore.load(
        account: account,
        bookId: bookId,
        trackIndex: trackIndex,
        localeIdentifier: localeIdentifier
      )
    }.value
  }

  nonisolated private static func saveOffMain(
    _ cache: PlayerTranscriptTrackCache,
    account: URL?,
    bookId: String
  ) async {
    await Task.detached(priority: .utility) {
      PlayerTranscriptCacheStore.save(cache, account: account, bookId: bookId)
    }.value
  }

  /// Transkriptdatei schreiben (JSON-Kodierung off-main, siehe `cache(bookId:trackIndex:locale:)`).
  static func save(_ cache: PlayerTranscriptTrackCache, bookId: String) async {
    await saveOffMain(cache, account: PlayerTranscriptCacheStore.activeAccount, bookId: bookId)
  }

  /// Fehlt im Track noch etwas ab `from`? Liefert die erste offene lokale Sekunde.
  static func firstUncoveredTime(
    bookId: String,
    source: PlayerTranscriptTrackSource,
    locale: Locale,
    from: Double
  ) async -> Double? {
    let existing =
      await cache(bookId: bookId, trackIndex: source.trackIndex, locale: locale)
      ?? PlayerTranscriptTrackCache(
        localeIdentifier: locale.identifier(.bcp47), trackIndex: source.trackIndex)
    return existing.firstUncoveredTime(from: from, duration: source.duration)
  }

  /// Einen Track-Bereich produzieren und persistieren. Läuft ungedrosselt; der Aufrufer
  /// entscheidet über Priorität und Abbruch.
  @discardableResult
  static func produceAndPersist(
    bookId: String,
    source: PlayerTranscriptTrackSource,
    locale: Locale,
    fromLocalTime start: Double,
    toLocalTime end: Double?,
    onBatch: ((PlayerTranscriptProductionBatch) throws -> Void)? = nil
  ) async throws -> Double {
    let producer = PlayerTranscriptProducer()
    var pending: [PlayerTranscriptTrackCache.Word] = []
    var through = start
    var lastPersist = start

    let account = PlayerTranscriptCacheStore.activeAccount

    func persist() async {
      guard through > start else { return }
      var cache =
        await loadOffMain(
          account: account,
          bookId: bookId,
          trackIndex: source.trackIndex,
          localeIdentifier: locale.identifier(.bcp47)
        )
        ?? PlayerTranscriptTrackCache(
          localeIdentifier: locale.identifier(.bcp47), trackIndex: source.trackIndex)
      cache.insert(
        segment: PlayerTranscriptTrackCache.Segment(start: start, end: through, words: pending))
      await saveOffMain(cache, account: account, bookId: bookId)
    }

    do {
      for try await batch in producer.transcribe(
        assetURL: source.assetURL, startSeconds: start, endSeconds: end, locale: locale)
      {
        try Task.checkCancellation()
        pending.append(
          contentsOf: batch.words.map {
            PlayerTranscriptTrackCache.Word(t: $0.text, s: $0.start, e: $0.end)
          })
        through = max(through, batch.processedThrough)
        // Der Aufrufer darf hier abbrechen (Vorrang-Arbeit, Stromsparmodus, heißes Gerät) —
        // das Bisherige wird im `catch` gesichert, nichts geht verloren.
        try onBatch?(batch)
        if through - lastPersist >= PlayerLiveTranscriptionController.transcriptPersistIntervalSeconds {
          lastPersist = through
          await persist()
        }
      }
      await persist()
      return through
    } catch {
      // Auch bei Abbruch sichern — die Rechenzeit ist bereits verbraucht.
      await persist()
      throw error
    }
  }

  /// Zusammenhängender Transkripttext für einen globalen Zeitbereich (Recap).
  /// Was im Cache liegt, wird gelesen; nur echte Lücken werden nachproduziert und dabei gesichert.
  static func transcriptText(
    bookId: String,
    sources: [PlayerTranscriptTrackSource],
    globalRange: ClosedRange<Double>,
    locale: Locale
  ) async throws -> String {
    var parts: [String] = []

    for source in sources.sorted(by: { $0.globalOffset < $1.globalOffset }) {
      let localStart = max(0, globalRange.lowerBound - source.globalOffset)
      let localEnd = min(
        source.duration > 0 ? source.duration : globalRange.upperBound - source.globalOffset,
        globalRange.upperBound - source.globalOffset
      )
      guard localEnd > localStart else { continue }

      // Lücken im gewünschten Bereich schließen (höchstens ein Lauf je Lücke).
      var cursor = localStart
      while let gapStart = await firstUncoveredTime(
        bookId: bookId, source: source, locale: locale, from: cursor),
        gapStart < localEnd
      {
        try Task.checkCancellation()
        let produced = try await produceAndPersist(
          bookId: bookId,
          source: source,
          locale: locale,
          fromLocalTime: gapStart,
          toLocalTime: localEnd
        )
        // Kein Fortschritt (z. B. Stille bis zum Ende) → Endlosschleife vermeiden.
        guard produced > gapStart + 0.5 else { break }
        cursor = produced
      }

      let words = await cachedWords(bookId: bookId, trackIndex: source.trackIndex, locale: locale)
        .filter { $0.e >= localStart && $0.s <= localEnd }
      guard !words.isEmpty else { continue }
      parts.append(words.map(\.t).joined(separator: " "))
    }

    return parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
