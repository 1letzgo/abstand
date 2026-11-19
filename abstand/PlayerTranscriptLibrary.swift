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
        // Abgelehnt (alter Stand bliebe sonst durch weniger Abdeckendes ersetzt): nichts schreiben.
        guard cache.insert(segment: segment) else { return (cache, known?.stamp) }
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
  /// Ein Transkript mit unverfeinerten Wortanfängen (alte Version) gilt hier als leer: Die
  /// Vorproduktion erzeugt es nach und nach neu; bis dahin zeigt die Anzeige es mit Heuristik.
  static func nextGap(
    bookId: String,
    source: PlayerTranscriptTrackSource,
    locale: Locale,
    from: Double
  ) async -> (start: Double, end: Double?)? {
    let empty = PlayerTranscriptTrackCache(
      localeIdentifier: locale.identifier(.bcp47), trackIndex: source.trackIndex)
    let loaded = await cache(bookId: bookId, trackIndex: source.trackIndex, locale: locale)
    let existing = loaded.flatMap { $0.isOnsetRefined ? $0 : nil } ?? empty
    guard let start = existing.firstUncoveredTime(from: from, duration: source.duration) else { return nil }
    return (start, existing.nextCoveredStart(after: start))
  }

  /// Eine Lücke der Vorproduktion füllen: mit Vor-/Nachlauf produzieren und speichern. Hat der Producer
  /// belegbar bis zum Ende des Bereichs gefüttert (finaler Batch) und endet die Datei vor dem Bereichsende
  /// (Server-Dauer länger als das Dekodierbare), wird der Rest ohne Wörter als abgedeckt eingetragen —
  /// sonst bliebe die Lücke offen und jeder Lauf öffnete Datei und Sprachmodell erneut.
  /// Abbruch endet IMMER als Fehler (nie als „nichts produziert"), und vor dem Markieren prüft
  /// `isCurrent`, dass der Lauf noch gilt. Rückgabe: Sekunde, ab der die nächste Lücke gesucht wird.
  /// `batches` nur für Tests (Producer-Ersatz).
  static func fillGap(
    bookId: String,
    source: PlayerTranscriptTrackSource,
    locale: Locale,
    gapStart: Double,
    gapEnd: Double?,
    priority: TaskPriority = .utility,
    isCurrent: () -> Bool,
    onBatch: ((PlayerTranscriptProductionBatch) throws -> Void)? = nil,
    batches: ((PlayerTranscriptRunWindow) -> AsyncThrowingStream<PlayerTranscriptProductionBatch, Error>)? = nil
  ) async throws -> Double {
    let window = PlayerTranscriptRunWindow(gapStart: gapStart, gapEnd: gapEnd)
    let stream =
      batches?(window)
      ?? PlayerTranscriptProducer.transcribe(
        assetURL: source.assetURL, startSeconds: window.runStart, endSeconds: window.runEnd,
        locale: locale, priority: priority)
    let result = try await persistProduction(
      batches: stream, bookId: bookId, trackIndex: source.trackIndex, locale: locale, window: window,
      onBatch: onBatch)
    // Vor jedem Markieren: Lauf weder abgebrochen noch überholt.
    try Task.checkCancellation()
    guard isCurrent() else { throw CancellationError() }
    let rangeEnd = gapEnd ?? source.duration
    let markFrom = max(gapStart, result.through)
    if rangeEnd > markFrom {
      DebugLogCollector.shared.log(
        String(
          format: "readAlong prefetch: track=%d audio ends at %.2f (fed), range ends %.2f — rest marked without words",
          source.trackIndex, result.fedThrough, rangeEnd))
      await mergeAndSave(
        segment: PlayerTranscriptTrackCache.Segment(start: markFrom, end: rangeEnd, words: []),
        bookId: bookId, trackIndex: source.trackIndex, locale: locale)
    }
    return max(result.through, rangeEnd)
  }

  /// Batches eines Laufs einsammeln und inkrementell speichern (auch bei Abbruch das Bisherige).
  /// Übernommen werden nur Wörter, die in der Lücke beginnen (`PlayerTranscriptRunWindow.keeps`).
  /// Kehrt nur zurück, wenn der Producer den Bereich ganz gefüttert hat (finaler Batch) — Abbruch wirft
  /// `CancellationError`, ein Ende ohne finalen Batch `endedWithoutFinalBatch`.
  static func persistProduction(
    batches: AsyncThrowingStream<PlayerTranscriptProductionBatch, Error>,
    bookId: String,
    trackIndex: Int,
    locale: Locale,
    window: PlayerTranscriptRunWindow,
    onBatch: ((PlayerTranscriptProductionBatch) throws -> Void)? = nil
  ) async throws -> PlayerTranscriptProductionResult {
    var pending: [PlayerTranscriptTrackCache.Word] = []
    // Gespeichert wird ab Lückenanfang — der Vorlauf gehört dem Segment davor.
    var through = window.gapStart
    // Inkrementell statt kumulativ: jedes Zwischenspeichern schreibt nur das seit dem letzten
    // Persist Produzierte. Vorher übergab jeder Intervall-Schreibvorgang alle Wörter des Laufs
    // erneut — Merge- und Schreibkosten wuchsen quadratisch mit der Lauflänge.
    var segmentStart = window.gapStart
    var fedThrough: Double?

    func persist() async {
      guard through > segmentStart else { return }
      await mergeAndSave(
        segment: PlayerTranscriptTrackCache.Segment(
          start: segmentStart, end: through, words: pending),
        bookId: bookId,
        trackIndex: trackIndex,
        locale: locale
      )
      pending.removeAll()
      segmentStart = through
    }

    do {
      for try await batch in batches {
        try Task.checkCancellation()
        pending.append(
          contentsOf: batch.words.lazy.filter { window.keeps(start: $0.start) }.map {
            PlayerTranscriptTrackCache.Word(t: $0.text, s: $0.start, e: $0.end)
          })
        through = max(through, batch.processedThrough)
        if batch.isFinalBatch { fedThrough = batch.processedThrough }
        // Der Aufrufer darf hier abbrechen (Vorrang-Arbeit, Stromsparmodus, heißes Gerät) —
        // das Bisherige wird im `catch` gesichert, nichts geht verloren.
        try onBatch?(batch)
        if through - segmentStart >= Self.transcriptPersistIntervalSeconds {
          await persist()
        }
      }
      // Ein abgebrochener Lauf beendet den Stream REGULÄR (`for try await` liefert dann einfach nil,
      // am Mac nachgebaut). Ohne diese Prüfung hielte der Aufrufer „nichts produziert" für „hier ist
      // keine Sprache" und trüge den Rest des Tracks als abgedeckt ein (Gerätefund).
      try Task.checkCancellation()
      guard let fedThrough else { throw PlayerTranscriptProducerError.endedWithoutFinalBatch }
      await persist()
      return PlayerTranscriptProductionResult(through: through, fedThrough: fedThrough)
    } catch {
      // Auch bei Abbruch sichern — die Rechenzeit ist bereits verbraucht. Gespeichert wird nur bis
      // zum Ende des letzten echten Ergebnisses, nie mehr Abdeckung als belegt.
      await persist()
      throw error
    }
  }
}

/// Ergebnis eines vollständig durchgelaufenen Produktionslaufs.
struct PlayerTranscriptProductionResult: Sendable {
  /// Bis hierher (lokale Track-Sekunde) ist gespeichert.
  let through: Double
  /// Bis hierher wurde Audio gefüttert (Bereichs- oder Dateiende) — Beleg, dass der Lauf den Bereich
  /// ganz gesehen hat.
  let fedThrough: Double
}
