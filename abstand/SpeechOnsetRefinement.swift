import AVFoundation
import Foundation

// Akustische Einsatz-Erkennung für Wortanfänge nach Sprechpausen.
//
// `SpeechTranscriber` legt die Grenze zwischen zwei Wörtern irgendwo in die Pause dazwischen (an
// einem echten deutschen Hörbuch gemessen: Median bei 73 % der Pausenlänge, große Streuung). Das
// Wort nach der Pause beginnt dadurch oft deutlich zu früh — Zeilenwechsel und Wortmarkierung im
// Read Along kamen vor dem Sprecher. Der Producer kennt das PCM, das er der Erkennung füttert;
// daraus führt er eine RMS-Hüllkurve mit und legt jeden Wortanfang, vor dem eine Stille liegt, auf
// den tatsächlichen Lautstärke-Einsatz.
//
// Reine Funktion ohne Isolation (`SpeechOnsetRefiner.refine`): Hüllkurve + Wortliste → Wortliste.
// Android spiegelt sie 1:1 (`logic/SpeechOnsetRefinement.kt`), samt denselben Konstanten.

/// Pegel (dBFS) je 10-ms-Fenster ab `startTime` (lokale Track-Sekunden).
nonisolated struct SpeechEnvelope: Sendable {
  let startTime: Double
  let levels: [Float]
}

nonisolated enum SpeechOnsetRefiner {
  /// Fensterlänge der Hüllkurve.
  static let hopSeconds: Double = 0.01
  /// Sprachpegel = Perzentil der Fensterpegel über diese Zeit vor dem Wortende.
  static let referenceWindowSeconds: Double = 10
  static let referencePercentile: Double = 0.95
  /// Stille = mehr als so viel unter dem Sprachpegel. Am echten Hörbuch eingestellt (26–32 dB
  /// geprüft): tiefer findet leises Grundrauschen nicht mehr als Stille, höher verschiebt
  /// Wörter ohne Pause.
  static let silenceBelowReferenceDB: Double = 28
  /// Liegt schon der Sprachpegel so tief, ist im Fenster nur Stille — nichts ändern.
  static let minimumReferenceDB: Double = -60
  /// Mindestdauer der Stille vor einem Einsatz.
  static let minimumSilenceSeconds: Double = 0.2
  /// Einsatz: von den nächsten 15 Fenstern (150 ms) liegen mindestens 9 über der Schwelle — kurze
  /// Spitzen (Atmer, Klick, Schmatzer) zählen zur Pause.
  static let stabilityFrames = 15
  static let stabilityMinimumAboveFrames = 9
  /// Einatmen vor dem Sprechen: Ein Einsatz, der höchstens bis `breathBelowReferenceDB` unter den
  /// Sprachpegel kommt und vor der eigentlichen Sprache (innerhalb `breathWindowFrames`) noch einmal
  /// unter die Stille-Schwelle fällt, ist ein Atmer — der Wortanfang kommt nach diesem Einbruch.
  /// Mindestens `breathMinimumFrames` lang, sonst zählt der Abschnitt schon als Anlaut.
  static let breathBelowReferenceDB: Double = 12
  static let breathWindowFrames = 60
  static let breathMinimumFrames = 10
  /// Wortanfang so weit vor den Einsatz: ein Fenster Spielraum (der Einsatz liegt irgendwo im ersten
  /// Fenster über der Schwelle). Gemessen 0–30 ms: jeder weitere Vorlauf lässt die Zeile entsprechend
  /// früher wechseln, ohne verspätete Wechsel zu verhindern (die kommen von Atmern und Erkennerfehlern).
  static let leadSeconds: Double = 0.01
  /// Höchstens so weit darf ein Anfang nach vorn wandern (Erkenner setzt ihn manchmal zu spät).
  static let maximumEarlierShiftSeconds: Double = 0.3
  /// Die Stille muss spätestens so kurz nach dem erkannten Wortanfang beginnen — sonst liegt sie
  /// hinter dem Wort (Pause nach einem Komma) und der Einsatz gehört schon zum nächsten Wort.
  static let silenceStartToleranceSeconds: Double = 0.15
  /// Ein Wort bleibt mindestens so lang; Anfänge bleiben so weit auseinander.
  static let minimumWordSeconds: Double = 0.08
  /// Wort (fast) ganz in der Pause: Der englische Erkenner setzt kurze Wörter nach einer Pause (he, as,
  /// said, The …) oft vollständig in die Stille — das rohe Ende liegt nur 0–0,08 s nach dem Einsatz oder
  /// sogar davor (35 min echter englischer Sprecher: 12–15 % der Einsätze, Deutsch < 1 %). Die Suche
  /// reicht deshalb bis so weit hinter das rohe Wortende; ein Einsatz dort verschiebt das ganze Wort.
  /// Begrenzt, damit ein Wort nicht über eine lange Stille an fremde Sprache gehängt wird (gemessen:
  /// 0,1–0,2 s verfehlten deutsche „…, ne?" mit Einsatz 0,21 s hinter dem Ende; 0,3–0,8 s gleich).
  static let lateOnsetSeconds: Double = 0.3
  /// Verschobenes Wort: Mindestlänge je Buchstabe (höchstens die rohe Dauer, mindestens
  /// `minimumWordSeconds`); das Ende reicht nie über den Anfang des Folgeworts.
  static let shiftedWordSecondsPerCharacter: Double = 0.06
  /// Verschoben wird nur, wenn die Stille spätestens so kurz nach dem rohen Anfang beginnt. Beginnt sie
  /// später, liegt am Wortanfang Schall — das Wort ist gesprochen (Erkenner setzt es zu spät) und der
  /// Einsatz hinter der Stille gehört zum Folgewort. Gemessen 0–0,06 s: ab 0,06 hängten sich deutsche
  /// Wörter mitten im Satz (ab, doch, nicht) an den nächsten Einsatz; 0,03 erreicht Englisch noch ganz.
  static let shiftedSilenceStartToleranceSeconds: Double = 0.03
  /// Nicht vor das Ende des Vorworts (minus diesen Rest) zurück — sonst rutscht ein Wort ohne
  /// Pause auf den Einsatz seines Vorgängers. Ausnahme „Pause im Vorwort“: Der Erkenner legt Wörter
  /// lückenlos aneinander, die Pause vor einem Wort steckt dann im Vorwort (rohes Ende = roher Anfang,
  /// dieser 0,1–0,3 s hinter dem Einsatz). Beginnt die Stille vor dem Einsatz mindestens
  /// `minimumWordSeconds` nach dem Anfang des Vorworts, klingt das Vorwort vor der Pause — die Sperre
  /// fällt, das Wort beginnt am Einsatz und das Vorwort endet am Beginn der Stille. Gerätefund (40
  /// deutsche Tracks): 8 von 29 um 0,15–0,4 s verspäteten Wortanfängen hingen an dieser Sperre; per
  /// Ausschnitt-Transkription gehörte der Einsatz bei 403 von 435 so verschobenen Wörtern zum Wort selbst,
  /// bei ~10 zum Vorwort (meist „und“, das der Erkenner vor die Pause legt — nicht trennbar über die
  /// Hüllkurve). Synthetik DE: Anteil > 0,1 s zu spät 4,8 % → 0,4 %, keine neuen zu frühen Anfänge.
  static let previousEndSlackSeconds: Double = 0.05
  /// So weit vor dem frühestmöglichen Anfang beginnt die Suche (Stille-Lauf mitzählen).
  static let scanBackSeconds: Double = 1
  /// Hüllkurve beginnt höchstens so spät: Lauf ab Track-Anfang (Ursprung = erster Ausgabe-PTS, ≈ 0).
  static let trackStartToleranceSeconds: Double = 0.05
  /// Histogramm der Pegel in 1-dB-Klassen ab hier (darunter = unterste Klasse).
  static let histogramFloorDB = -100

  /// Wörter (zeitlich sortiert) mit korrigierten Anfängen. Vor einem Wort mit erkennbarer Stille
  /// beginnt es am Einsatz danach (minus `leadSeconds`), höchstens bis `Ende − minimumWordSeconds`
  /// und nie vor dem Folgewort; das Vorwort endet dann am Beginn der Stille. Liegt der Einsatz erst
  /// dahinter (bis `lateOnsetSeconds` nach dem rohen Ende) und beginnt die Stille spätestens kurz nach
  /// dem rohen Anfang (`shiftedSilenceStartToleranceSeconds`), liegt das Wort ganz in der Pause: Es
  /// wandert als Ganzes an den Einsatz, höchstens bis `minimumWordSeconds` vor das nächste gesprochene
  /// Wort, dessen Anfang unverändert bleibt; das Ende wächst bei Bedarf auf eine Mindestlänge, nie über
  /// das Folgewort; Satzzeichen-Token dazwischen wandern mit. Wörter ohne Stille,
  /// reine Satzzeichen und Wörter außerhalb der Hüllkurve bleiben unverändert. Die Anfänge bleiben
  /// monoton. `previous`: letztes Wort vor der Liste (Batch-Grenze), mit bereits korrigiertem Anfang.
  /// Das erste Wort eines Laufs ab Track-Anfang (kein `previous`, Hüllkurve ab 0) zählt die Stille ab
  /// Track-Beginn in jeder Länge (siehe `onset`).
  static func refine(
    _ words: [PlayerTranscriptProducedWord],
    envelope: SpeechEnvelope,
    previous: PlayerTranscriptProducedWord? = nil
  ) -> [PlayerTranscriptProducedWord] {
    guard !words.isEmpty, !envelope.levels.isEmpty else { return words }
    let levels = envelope.levels
    let t0 = envelope.startTime
    let need = Int((minimumSilenceSeconds / hopSeconds).rounded())
    var starts = words.map(\.start)
    var ends = words.map(\.end)
    // Letztes gesprochenes Wort: (neuer Anfang, Ende wie erkannt, Index in `words` oder nil).
    var previousSpoken: (start: Double, end: Double, index: Int?)? = previous.map { ($0.start, $0.end, nil) }

    func frame(_ time: Double) -> Int { Int(((time - t0) / hopSeconds).rounded(.down)) }

    for i in words.indices {
      let s = words[i].start
      let e = words[i].end
      let spoken = isSpoken(words[i].text)
      guard spoken, s.isFinite, e.isFinite, e > s else {
        if spoken { previousSpoken = (s, e, i) }
        continue
      }
      var lower = s - maximumEarlierShiftSeconds
      if i > 0 { lower = max(lower, starts[i - 1]) }
      // Untergrenze ohne die Sperre am Vorwort-Ende („Pause im Vorwort“, siehe `previousEndSlackSeconds`).
      var unlockedLower: Double?
      if let previousSpoken {
        lower = max(lower, previousSpoken.start + minimumWordSeconds)
        let locked = max(lower, min(s, previousSpoken.end - previousEndSlackSeconds))
        if locked > lower { unlockedLower = lower }
        lower = locked
      }
      var upper = e - minimumWordSeconds
      if i + 1 < words.count { upper = min(upper, words[i + 1].start) }
      // Wort in der Pause: Anfang höchstens bis kurz vor das nächste gesprochene Wort (dessen Anfang
      // bleibt maßgeblich); Satzzeichen-Token dazwischen werden mitgeführt.
      let next = words.indices.suffix(from: i + 1).first { isSpoken(words[$0].text) }
      let nextStart = next.map { words[$0].start } ?? .infinity
      let shiftUpper = max(upper, nextStart - minimumWordSeconds)

      var found: (time: Double, silenceStart: Double, isLate: Bool)?
      if lower <= shiftUpper {
        found = onset(
          levels: levels, frame: frame, t0: t0, need: need, wordStart: s, wordEnd: e, lower: lower,
          isTrackStart: previousSpoken == nil && t0 <= trackStartToleranceSeconds)
        // Pause im Vorwort: früherer Einsatz vor der Sperre, wenn das Vorwort vor der Stille klingt
        // (dieselbe Bedingung, unter der das Vorwort unten auf den Stille-Beginn gekürzt wird).
        if let free = unlockedLower, let previousSpoken,
          let early = onset(
            levels: levels, frame: frame, t0: t0, need: need, wordStart: s, wordEnd: e, lower: free,
            isTrackStart: false),
          early.time < lower, !early.isLate,
          early.silenceStart >= previousSpoken.start + minimumWordSeconds
        {
          found = early
          lower = free
        }
      }
      if let onset = found,
        onset.isLate ? onset.silenceStart <= s + shiftedSilenceStartToleranceSeconds : lower <= upper
      {
        let target = max(onset.time - leadSeconds, lower)
        if !onset.isLate || target <= upper {
          starts[i] = min(target, upper)
        } else {
          // Ganzes Wort an den Einsatz: Ende mindestens Anfang + Mindestlänge, nie über das Folgewort.
          let start = min(target, shiftUpper)
          starts[i] = start
          if start > upper {
            let letters = words[i].text.reduce(0) { $1.isLetter || $1.isNumber ? $0 + 1 : $0 }
            let length = max(minimumWordSeconds, min(e - s, shiftedWordSecondsPerCharacter * Double(letters)))
            let end = max(e, min(start + length, nextStart))
            ends[i] = end
            // Satzzeichen-Token, die sonst vor dem Wort lägen, ans neue Ende mitnehmen.
            for j in (i + 1)..<(next ?? words.count) where starts[j] < end {
              starts[j] = end
              ends[j] = max(ends[j], end)
            }
          }
        }
        if let index = previousSpoken?.index, ends[index] > onset.silenceStart,
          onset.silenceStart >= starts[index] + minimumWordSeconds
        {
          ends[index] = onset.silenceStart
        }
      }
      previousSpoken = (starts[i], e, i)
    }
    return words.indices.map { i in
      starts[i] == words[i].start && ends[i] == words[i].end
        ? words[i]
        : PlayerTranscriptProducedWord(text: words[i].text, start: starts[i], end: ends[i])
    }
  }

  /// Erster stabiler Einsatz nach mindestens `minimumSilenceSeconds` Stille, der nicht vor `lower`
  /// und höchstens `lateOnsetSeconds` nach `wordEnd` liegt und dessen Stille spätestens kurz nach
  /// `wordStart` begann (bei einem Atmer: dessen Ende).
  ///
  /// Track-Anfang (`isTrackStart`: kein Vorwort, Hüllkurve ab Track-Sekunde 0, und die Suche reicht
  /// bis an ihren Anfang): Vor dem Track liegt kein Schall, die Stille ab dem ersten Fenster zählt
  /// also auch kürzer als `minimumSilenceSeconds`. Gerätefund (40 Tracks eines deutschen Hörbuchs):
  /// Der Erkenner setzt das erste Wort oft auf 0,00 s, die Sprache beginnt aber erst nach 0,08–0,45 s
  /// Stille (teils mit Atmer davor) — die Mindeststille verhinderte in 9 von 40 Tracks die Korrektur.
  /// Beginnt der Track sofort mit Pegel über der Schwelle, bleibt alles wie bisher; ebenso ein Lauf
  /// mitten im Track (dort ist vor der Hüllkurve unbekannt, was lag). Der Sprachpegel nimmt hier statt
  /// der kurzen Vorgeschichte die ersten `referenceWindowSeconds` der Hüllkurve (so weit vorhanden) —
  /// aus nur [0, Wortende] lag er bis 4 dB zu tief, und der Atmer davor galt als Sprache.
  private static func onset(
    levels: [Float],
    frame: (Double) -> Int,
    t0: Double,
    need: Int,
    wordStart s: Double,
    wordEnd e: Double,
    lower: Double,
    isTrackStart: Bool
  ) -> (time: Double, silenceStart: Double, isLate: Bool)? {
    let n = levels.count
    let windowFrames = Int((referenceWindowSeconds / hopSeconds).rounded())
    let scanStart = frame(lower - scanBackSeconds)
    let atEnvelopeStart = isTrackStart && scanStart <= 0
    var k1 = min(n, frame(e) + 1)
    let k0 = max(0, frame(e - referenceWindowSeconds))
    if atEnvelopeStart { k1 = max(k1, min(n, k0 + windowFrames)) }
    guard k1 - k0 >= 10 else { return nil }
    guard let reference = percentileLevel(levels[k0..<k1]), Double(reference) >= minimumReferenceDB
    else { return nil }
    let threshold = Double(reference) - silenceBelowReferenceDB
    // Bis hinter das rohe Ende: Wort (fast) ganz in der Pause (siehe `lateOnsetSeconds`).
    let last = min(n - 1, frame(e + lateOnsetSeconds))
    // Einsatz eines Atmers → Fenster nach dessen letztem Einbruch (sonst unverändert). Nur bis
    // `Ende − minimumWordSeconds`: dahinter war der „Atmer“ am Gerät meist das leise gesprochene Wort.
    let breathLast = min(n - 1, frame(e - minimumWordSeconds))
    func afterBreath(_ k: Int) -> Int {
      let speechLevel = Double(reference) - breathBelowReferenceDB
      guard
        let speech = (k..<min(n, k + breathWindowFrames)).first(where: { Double(levels[$0]) >= speechLevel }),
        speech - k >= breathMinimumFrames,
        let dip = (k + 1..<speech).last(where: { !(Double(levels[$0]) > threshold) }),
        dip + 1 <= breathLast
      else { return k }
      return dip + 1
    }
    var k = max(0, scanStart)
    // Fenster vor der Hüllkurve gelten als unbekannt (keine Stille) — Lauf beginnt bei 0. Ausnahme
    // Track-Anfang: eine Stille ab dem ersten Fenster (`k - run == 0`) reicht in jeder Länge.
    var run = 0
    while k <= last {
      defer { k += 1 }
      guard Double(levels[k]) > threshold else {
        run += 1
        continue
      }
      guard run >= need || (atEnvelopeStart && run > 0 && k - run == 0) else {
        run = 0
        continue
      }
      var above = 0
      for j in k..<min(n, k + stabilityFrames) where Double(levels[j]) > threshold { above += 1 }
      guard above >= stabilityMinimumAboveFrames else {
        // Kurze Spitze in der Pause (Atmer, Klick): gehört zur Stille.
        run += 1
        continue
      }
      let time = t0 + Double(k) * hopSeconds
      let silenceStart = t0 + Double(k - run) * hopSeconds
      if time >= lower, silenceStart <= s + silenceStartToleranceSeconds {
        return (t0 + Double(afterBreath(k)) * hopSeconds, silenceStart, k > breathLast)
      }
      run = 0
    }
    return nil
  }

  /// `referencePercentile` der Pegel über 1-dB-Klassen (Untergrenze der Klasse) — ganzzahlig und
  /// damit auf beiden Plattformen bitgleich.
  static func percentileLevel(_ slice: ArraySlice<Float>) -> Int? {
    guard !slice.isEmpty else { return nil }
    var histogram = [Int](repeating: 0, count: -histogramFloorDB + 1)
    for level in slice {
      let bin = min(0, max(histogramFloorDB, Int(Double(level).rounded(.down)))) - histogramFloorDB
      histogram[bin] += 1
    }
    let target = Int((referencePercentile * Double(slice.count)).rounded(.up))
    var cumulative = 0
    for (bin, count) in histogram.enumerated() {
      cumulative += count
      if cumulative >= target { return bin + histogramFloorDB }
    }
    return 0
  }

  /// Wort mit Schall: mindestens ein Buchstabe oder eine Ziffer (keine reinen Satzzeichen-Token).
  static func isSpoken(_ text: String) -> Bool {
    text.contains { $0.isLetter || $0.isNumber }
  }
}

/// Hüllkurve des gefütterten PCM während eines Producer-Laufs. Der Fütter-Task hängt an, der
/// Ergebnis-Task korrigiert finalisierte Wörter und gibt Älteres frei. Gehalten wird nur, was noch
/// gebraucht wird: ab ~12 s vor dem letzten korrigierten Wort, höchstens `maximumFrames`.
nonisolated final class SpeechEnvelopeTracker: @unchecked Sendable {
  /// 10 min — mehr Vorsprung erlaubt der Producer nicht (`maxTrueLeadSeconds` + Schub). Gekürzt
  /// wird blockweise, nicht bei jedem Puffer.
  static let maximumFrames = 60_000
  private static let trimChunkFrames = 6_000
  /// Vor dem frühesten Wort einer Liste mitgegeben (Referenzfenster + Suche zurück + Reserve).
  static let lookBackSeconds: Double = 11.5
  static let lookAheadSeconds: Double = 0.5

  private let lock = NSLock()
  private var origin: Double?
  private var levels: [Float] = []
  /// Index (ab Ursprung) von `levels[0]`.
  private var firstFrame = 0
  private var samplesPerFrame = 0
  private var sumOfSquares: Double = 0
  private var sampleCount = 0

  /// Track-Sekunde des ersten gefütterten Samples (wie `FeedGate.timelineOrigin`).
  func setOrigin(_ time: Double) {
    lock.lock()
    origin = time
    lock.unlock()
  }

  /// PCM anhängen — vor dem Füttern, damit die Hüllkurve nie hinter der Erkennung liegt.
  func append(_ buffer: AVAudioPCMBuffer) {
    let count = Int(buffer.frameLength)
    guard count > 0 else { return }
    let stride = buffer.format.isInterleaved ? max(1, Int(buffer.format.channelCount)) : 1
    lock.lock()
    defer { lock.unlock() }
    if samplesPerFrame == 0 {
      samplesPerFrame = max(1, Int((buffer.format.sampleRate * SpeechOnsetRefiner.hopSeconds).rounded()))
    }
    if let samples = buffer.floatChannelData?[0] {
      for i in 0..<count { accumulate(Double(samples[i * stride])) }
    } else if let samples = buffer.int16ChannelData?[0] {
      for i in 0..<count { accumulate(Double(samples[i * stride]) / 32768) }
    } else if let samples = buffer.int32ChannelData?[0] {
      for i in 0..<count { accumulate(Double(samples[i * stride]) / 2_147_483_648) }
    }
    if levels.count > Self.maximumFrames + Self.trimChunkFrames {
      let drop = levels.count - Self.maximumFrames
      levels.removeFirst(drop)
      firstFrame += drop
    }
  }

  private func accumulate(_ sample: Double) {
    sumOfSquares += sample * sample
    sampleCount += 1
    guard sampleCount == samplesPerFrame else { return }
    levels.append(Self.level(sumOfSquares: sumOfSquares, count: sampleCount))
    sumOfSquares = 0
    sampleCount = 0
  }

  /// dBFS eines Fensters (Untergrenze −140 dB für digitale Stille).
  static func level(sumOfSquares: Double, count: Int) -> Float {
    Float(20 * log10(max((sumOfSquares / Double(max(1, count))).squareRoot(), 1e-7)))
  }

  /// Wörter eines Ergebnisses korrigieren und Hüllkurve davor freigeben.
  func refine(
    _ words: [PlayerTranscriptProducedWord],
    previous: PlayerTranscriptProducedWord?
  ) -> [PlayerTranscriptProducedWord] {
    guard let earliest = words.lazy.map(\.start).min(), let latest = words.lazy.map(\.end).max()
    else { return words }
    let envelope: SpeechEnvelope? = {
      lock.lock()
      defer { lock.unlock() }
      guard let origin, !levels.isEmpty else { return nil }
      let hop = SpeechOnsetRefiner.hopSeconds
      let from = max(firstFrame, Int(((earliest - Self.lookBackSeconds - origin) / hop).rounded(.down)))
      let to = min(firstFrame + levels.count, Int(((latest + Self.lookAheadSeconds - origin) / hop).rounded(.up)))
      guard to > from else { return nil }
      let slice = Array(levels[(from - firstFrame)..<(to - firstFrame)])
      // Älteres als ~12 s vor dem letzten Wortanfang braucht kein späteres Ergebnis mehr.
      let keepFrom = Int(((words[words.count - 1].start - Self.lookBackSeconds - origin) / hop).rounded(.down))
      if keepFrom > firstFrame {
        let drop = min(levels.count, keepFrom - firstFrame)
        levels.removeFirst(drop)
        firstFrame += drop
      }
      return SpeechEnvelope(startTime: origin + Double(from) * hop, levels: slice)
    }()
    guard let envelope else { return words }
    return SpeechOnsetRefiner.refine(words, envelope: envelope, previous: previous)
  }
}

/// Hält das letzte gesprochene Wort jedes Ergebnis-Batches (samt folgender Satzzeichen-Token) zurück und
/// verfeinert es mit dem nächsten Batch zusammen. `SpeechOnsetRefiner` kürzt das Ende eines Worts auf den
/// Beginn der Pause vor dem Folgewort — das geht nur, wenn beide in derselben Liste stehen. Über eine
/// Batch-Grenze hinweg blieb das Ende sonst lang (Gerätefund: 20 Wort-Enden bis 0,59 s zu lang →
/// Absatzpausen und Zeilenspannen falsch). Ergebnis wie mit einer einzigen Liste über den ganzen Lauf;
/// jedes Wort kommt genau einmal heraus, in Reihenfolge. `finish` gibt das Zurückgehaltene aus.
nonisolated struct PlayerTranscriptRefinementBatcher {
  typealias Refine = ([PlayerTranscriptProducedWord], PlayerTranscriptProducedWord?) -> [PlayerTranscriptProducedWord]

  /// Letztes ausgegebenes gesprochenes Wort — Kontext für die nächste Liste, wie `refine` intern seinen
  /// Vorgänger führt: verfeinerter Anfang, erkanntes Ende.
  private var previous: PlayerTranscriptProducedWord?
  /// Zurückgehaltene Wörter, unverfeinert (werden mit dem nächsten Batch neu verfeinert — gleiche
  /// Hüllkurve, gleicher Vorgänger, also derselbe Anfang; nur das Ende kann jetzt gekürzt werden).
  private var held: [PlayerTranscriptProducedWord] = []

  /// Neuen Batch aufnehmen; liefert die fertigen Wörter (alles vor dem neuen letzten gesprochenen Wort).
  mutating func add(_ words: [PlayerTranscriptProducedWord], refine: Refine) -> [PlayerTranscriptProducedWord] {
    guard !words.isEmpty else { return [] }
    let batch = held + words
    guard let lastSpoken = batch.lastIndex(where: { SpeechOnsetRefiner.isSpoken($0.text) }) else {
      // Nur Satzzeichen: nichts zu verfeinern, mit dem nächsten Batch zusammen ausgeben.
      held = batch
      return []
    }
    // Satzzeichen direkt davor mit zurückhalten — dann endet die Ausgabe auf einem gesprochenen Wort und
    // das nächste `refine` sieht denselben Vorgänger wie eine durchgehende Liste.
    var holdFrom = lastSpoken
    while holdFrom > 0, !SpeechOnsetRefiner.isSpoken(batch[holdFrom - 1].text) { holdFrom -= 1 }
    let refined = refine(batch, previous)
    held = Array(batch[holdFrom...])
    let out = Array(refined[..<holdFrom])
    rememberPrevious(out, raw: batch)
    return out
  }

  /// Lauf zu Ende (oder abgebrochen): das Zurückgehaltene verfeinert ausgeben.
  mutating func finish(refine: Refine) -> [PlayerTranscriptProducedWord] {
    guard !held.isEmpty else { return [] }
    let batch = held
    held = []
    let out = refine(batch, previous)
    rememberPrevious(out, raw: batch)
    return out
  }

  private mutating func rememberPrevious(_ out: [PlayerTranscriptProducedWord], raw: [PlayerTranscriptProducedWord]) {
    guard let i = out.lastIndex(where: { SpeechOnsetRefiner.isSpoken($0.text) }) else { return }
    previous = PlayerTranscriptProducedWord(text: out[i].text, start: out[i].start, end: raw[i].end)
  }
}
