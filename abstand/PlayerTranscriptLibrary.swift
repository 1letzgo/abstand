import AVFoundation
import Foundation
import Speech

/// Eine lokale Track-Datei mit ihrer Lage im Hörbuch — Grundlage für die Vorproduktion.
struct PlayerTranscriptTrackSource: Sendable {
  let trackIndex: Int
  let assetURL: URL
  let globalOffset: Double
  let duration: Double

  var globalRange: ClosedRange<Double> { globalOffset...(globalOffset + max(0, duration)) }
}

/// Gemeinsamer Zugriff auf persistierte Transkripte: liest aus dem Cache und produziert nur,
/// was dort noch fehlt. Teleprompter und Hintergrund-Vorproduktion teilen sich damit
/// dieselben Daten — jede Sekunde Audio wird höchstens einmal durch die Spracherkennung geschickt.
@MainActor
enum PlayerTranscriptLibrary {
  /// Vordergrund-Arbeit (Teleprompter) läuft; die Hintergrund-Vorproduktion pausiert
  /// solange. Zwei parallele `SpeechAnalyzer` würden sich Speicher und Rechenzeit wegnehmen.
  private(set) static var priorityWorkCount = 0

  static var isPriorityWorkActive: Bool { priorityWorkCount > 0 }

  static func beginPriorityWork() { priorityWorkCount += 1 }

  static func endPriorityWork() { priorityWorkCount = max(0, priorityWorkCount - 1) }

  /// Transkriptdatei lesen. Das JSON eines Tracks ist schnell ein paar hundert Kilobyte —
  /// Lesen und Dekodieren gehören deshalb vom MainActor herunter, sonst ruckelt die Wiedergabe-UI
  /// bei jedem Track-Wechsel und bei jedem Zwischenspeichern der Vorproduktion. Ein zuletzt gelesener
  /// oder geschriebener Stand wird ohne Dekodieren wiederverwendet, solange die Datei unverändert ist.
  static func cache(
    bookId: String,
    trackIndex: Int,
    locale: Locale
  ) async -> PlayerTranscriptTrackCache? {
    let account = PlayerTranscriptCacheStore.activeAccount
    let localeId = locale.identifier(.bcp47)
    let key = chainKey(bookId: bookId, trackIndex: trackIndex, localeId: localeId)
    let known = memo[key]
    let loaded = await Task.detached(priority: .utility) { () -> MemoEntry? in
      if let known,
        PlayerTranscriptCacheStore.transcriptStamp(
          account: account, bookId: bookId, trackIndex: trackIndex, localeIdentifier: localeId) == known.stamp
      {
        return known
      }
      return PlayerTranscriptCacheStore.loadStamped(
        account: account, bookId: bookId, trackIndex: trackIndex, localeIdentifier: localeId
      ).map { MemoEntry(cache: $0.cache, stamp: $0.stamp) }
    }.value
    remember(loaded, forKey: key)
    return loaded?.cache
  }

  /// Zuletzt gelesener/geschriebener Stand je Transkriptdatei samt Datei-Stempel. Nur wenige
  /// Einträge — bei Ein-Datei-Hörbüchern ist ein Transkript mehrere MB groß.
  nonisolated private struct MemoEntry: Sendable {
    let cache: PlayerTranscriptTrackCache
    let stamp: PlayerTranscriptFileStamp
  }

  private static let maxMemoEntries = 2
  private static var memo: [String: MemoEntry] = [:]
  /// Zuletzt genutzt am Ende.
  private static var memoOrder: [String] = []

  private static func remember(_ entry: MemoEntry?, forKey key: String) {
    memoOrder.removeAll { $0 == key }
    guard let entry else {
      memo[key] = nil
      return
    }
    memo[key] = entry
    memoOrder.append(key)
    while memoOrder.count > maxMemoEntries {
      memo[memoOrder.removeFirst()] = nil
    }
  }

  private static func chainKey(bookId: String, trackIndex: Int, localeId: String) -> String {
    "\(bookId)|\(trackIndex)|\(localeId)"
  }

  /// Zwischenspeichern nach so vielen produzierten Audiosekunden. Liegt hier (nicht im
  /// UI-Controller): der geteilte Service definiert den Persist-Takt für alle Schreiber.
  static let transcriptPersistIntervalSeconds: Double = 120

  /// Schreib-Ketten pro Transkriptdatei — serialisiert konkurrierende load→insert→save-Zyklen
  /// (Teleprompter-Produktion, Hintergrund-Vorproduktion). Ohne diese
  /// Serialisierung gewinnt der letzte Schreiber und verwirft die Segmente des anderen.
  private static var mergeChains: [String: Task<PlayerTranscriptTrackCache, Never>] = [:]
  private static var mergeChainGenerations: [String: UInt64] = [:]
  private static var mergeGenerationCounter: UInt64 = 0

  /// Segment atomar in die Transkriptdatei mergen: wartet auf einen laufenden Schreibvorgang
  /// derselben Datei, dann insert→save off-main. Der zusammengeführte Stand bleibt im Speicher;
  /// dekodiert wird nur, wenn die Datei inzwischen von außen geändert wurde (Stempel).
  /// Gibt den zusammengeführten Stand zurück.
  @discardableResult
  static func mergeAndSave(
    segment: PlayerTranscriptTrackCache.Segment,
    bookId: String,
    trackIndex: Int,
    locale: Locale
  ) async -> PlayerTranscriptTrackCache {
    let localeId = locale.identifier(.bcp47)
    let account = PlayerTranscriptCacheStore.activeAccount
    let chainKey = chainKey(bookId: bookId, trackIndex: trackIndex, localeId: localeId)
    let previous = mergeChains[chainKey]
    let task = Task<PlayerTranscriptTrackCache, Never> {
      _ = await previous?.value
      // Erst nach dem Vorgänger lesen — er hat den Speicherstand gerade fortgeschrieben.
      let known = memo[chainKey]
      let (merged, stamp) = await Task.detached(priority: .utility) {
        () -> (PlayerTranscriptTrackCache, PlayerTranscriptFileStamp?) in
        var cache: PlayerTranscriptTrackCache
        if let known,
          PlayerTranscriptCacheStore.transcriptStamp(
            account: account, bookId: bookId, trackIndex: trackIndex, localeIdentifier: localeId)
            == known.stamp
        {
          cache = known.cache
        } else {
          cache =
            PlayerTranscriptCacheStore.load(
              account: account, bookId: bookId, trackIndex: trackIndex, localeIdentifier: localeId)
            ?? PlayerTranscriptTrackCache(localeIdentifier: localeId, trackIndex: trackIndex)
        }
        cache.insert(segment: segment)
        return (cache, PlayerTranscriptCacheStore.save(cache, account: account, bookId: bookId))
      }.value
      // Nicht geschrieben (kein Account, Schreibfehler): nichts merken, nächstes Mal von der Platte.
      remember(stamp.map { MemoEntry(cache: merged, stamp: $0) }, forKey: chainKey)
      return merged
    }
    mergeGenerationCounter &+= 1
    let generation = mergeGenerationCounter
    mergeChains[chainKey] = task
    mergeChainGenerations[chainKey] = generation
    let merged = await task.value
    // Nur den eigenen Eintrag räumen — ein inzwischen angehängter Nachfolger bleibt stehen.
    if mergeChainGenerations[chainKey] == generation {
      mergeChains.removeValue(forKey: chainKey)
      mergeChainGenerations.removeValue(forKey: chainKey)
    }
    return merged
  }

  /// Fehlt im Track noch etwas ab `from`? Liefert die erste offene lokale Sekunde und den Beginn des
  /// nächsten schon transkribierten Segments danach (Ende der Lücke) — aus einem Lesevorgang.
  static func nextGap(
    bookId: String,
    source: PlayerTranscriptTrackSource,
    locale: Locale,
    from: Double
  ) async -> (start: Double, end: Double?)? {
    let existing =
      await cache(bookId: bookId, trackIndex: source.trackIndex, locale: locale)
      ?? PlayerTranscriptTrackCache(
        localeIdentifier: locale.identifier(.bcp47), trackIndex: source.trackIndex)
    guard let start = existing.firstUncoveredTime(from: from, duration: source.duration) else { return nil }
    return (start, existing.nextCoveredStart(after: start))
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
    priority: TaskPriority = .userInitiated,
    onBatch: ((PlayerTranscriptProductionBatch) throws -> Void)? = nil
  ) async throws -> Double {
    var pending: [PlayerTranscriptTrackCache.Word] = []
    var through = start
    // Inkrementell statt kumulativ: jedes Zwischenspeichern schreibt nur das seit dem letzten
    // Persist Produzierte. Vorher übergab jeder Intervall-Schreibvorgang alle Wörter des Laufs
    // erneut — Merge- und Schreibkosten wuchsen quadratisch mit der Lauflänge.
    var segmentStart = start

    func persist() async {
      guard through > segmentStart else { return }
      await mergeAndSave(
        segment: PlayerTranscriptTrackCache.Segment(
          start: segmentStart, end: through, words: pending),
        bookId: bookId,
        trackIndex: source.trackIndex,
        locale: locale
      )
      pending.removeAll()
      segmentStart = through
    }

    do {
      for try await batch in PlayerTranscriptProducer.transcribe(
        assetURL: source.assetURL, startSeconds: start, endSeconds: end, locale: locale,
        priority: priority)
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
        if through - segmentStart >= Self.transcriptPersistIntervalSeconds {
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
}
