import Foundation
import AVFoundation
import MediaToolbox
import CoreAudio
import os

// MARK: - EQ-Presets

/// Equalizer-Vorlagen für die Wiedergabe. Jede Preset beschreibt eine Kaskade
/// von Biquad-Filtern nach dem RBJ-Cookbook.
/// Werte bewusst konservativ — Hörbücher/Podcasts brauchen dezent, nicht aggressiv.
enum AudioEQPreset: String, CaseIterable, Identifiable {
  /// Neutral — kein Eingriff in das Signal.
  case flat
  /// Sprachverständlichkeit: Hochpass (Rumpeln weg), Presence-Boost, leichte Höhenanhebung.
  case voiceFocus
  /// Warme Stimme/Instrumente: Bass-Shelf.
  case bassBoost
  /// Mehr Luft/Klarheit: Höhen-Shelf.
  case trebleBoost

  var id: String { rawValue }

  var label: String {
    switch self {
    case .flat: return "Flat"
    case .voiceFocus: return "Voice Focus"
    case .bassBoost: return "Bass Boost"
    case .trebleBoost: return "Treble Boost"
    }
  }

  var systemImage: String {
    switch self {
    case .flat: return "slider.horizontal.3"
    case .voiceFocus: return "person.wave.2"
    case .bassBoost: return "speaker.wave.1"
    case .trebleBoost: return "speaker.wave.3"
    }
  }

  /// Biquad-Kette für diese Preset. Reihenfolge = kaskadierungs-Reihenfolge.
  var filters: [AudioEQBiquadFilter] {
    switch self {
    case .flat:
      return []
    case .voiceFocus:
      return [
        .init(type: .highPass, frequency: 80, gain: 0, q: 0.707),
        .init(type: .peaking, frequency: 2500, gain: 4.0, q: 1.0),
        .init(type: .highShelf, frequency: 6000, gain: 3.0, q: 0.707),
      ]
    case .bassBoost:
      return [
        .init(type: .lowShelf, frequency: 100, gain: 6.0, q: 0.707),
      ]
    case .trebleBoost:
      return [
        .init(type: .highShelf, frequency: 5000, gain: 5.0, q: 0.707),
      ]
    }
  }

  /// Gespeicherte Preset aus UserDefaults laden (Default `.flat`).
  static func loadSaved(key: String = "abstand_eq_preset") -> AudioEQPreset {
    guard let raw = UserDefaults.standard.string(forKey: key),
          let preset = AudioEQPreset(rawValue: raw) else { return .flat }
    return preset
  }
}

// MARK: - Biquad-Beschreibung

/// Ein Biquad-Filterabschnitt (Second-Order-Section) nach RBJ-Cookbook.
struct AudioEQBiquadFilter {
  enum Kind {
    case lowPass
    case highPass
    case peaking
    case lowShelf
    case highShelf
  }

  let type: Kind
  /// Eckfrequenz in Hz.
  let frequency: Double
  /// Verstärkung in dB (für peaking/lowShelf/highShelf).
  let gain: Double
  /// Güte (bandwidth).
  let q: Double
}

/// Berechnete Biquad-Koeffizienten (Direkt-Form-I, normalisiert auf a0=1).
/// y[n] = b0*x[n] + b1*x[n-1] + b2*x[n-2] - a1*y[n-1] - a2*y[n-2]
struct AudioEQBiquadCoefficients {
  let b0: Double
  let b1: Double
  let b2: Double
  let a1: Double
  let a2: Double

  /// RBJ-Cookbook-Formeln bei gegebener Sample-Rate.
  static func compute(filter: AudioEQBiquadFilter, sampleRate: Double) -> AudioEQBiquadCoefficients {
    let sr = max(sampleRate, 1.0)
    let w0 = 2.0 * .pi * filter.frequency / sr
    let cosW0 = cos(w0)
    let sinW0 = sin(w0)
    let A = pow(10.0, filter.gain / 40.0)
    let alpha = sinW0 / (2.0 * max(filter.q, 0.0001))

    var b0 = 1.0, b1 = 0.0, b2 = 0.0, a0 = 1.0, a1 = 0.0, a2 = 0.0

    switch filter.type {
    case .lowPass:
      b0 = (1 - cosW0) / 2
      b1 = 1 - cosW0
      b2 = (1 - cosW0) / 2
      a0 = 1 + alpha
      a1 = -2 * cosW0
      a2 = 1 - alpha
    case .highPass:
      b0 = (1 + cosW0) / 2
      b1 = -(1 + cosW0)
      b2 = (1 + cosW0) / 2
      a0 = 1 + alpha
      a1 = -2 * cosW0
      a2 = 1 - alpha
    case .peaking:
      b0 = 1 + alpha * A
      b1 = -2 * cosW0
      b2 = 1 - alpha * A
      a0 = 1 + alpha / A
      a1 = -2 * cosW0
      a2 = 1 - alpha / A
    case .lowShelf:
      let sqrtA = sqrt(A)
      b0 = A * ((A + 1) - (A - 1) * cosW0 + 2 * sqrtA * alpha)
      b1 = 2 * A * ((A - 1) - (A + 1) * cosW0)
      b2 = A * ((A + 1) - (A - 1) * cosW0 - 2 * sqrtA * alpha)
      a0 = (A + 1) + (A - 1) * cosW0 + 2 * sqrtA * alpha
      a1 = -2 * ((A - 1) + (A + 1) * cosW0)
      a2 = (A + 1) + (A - 1) * cosW0 - 2 * sqrtA * alpha
    case .highShelf:
      let sqrtA = sqrt(A)
      b0 = A * ((A + 1) + (A - 1) * cosW0 + 2 * sqrtA * alpha)
      b1 = -2 * A * ((A - 1) + (A + 1) * cosW0)
      b2 = A * ((A + 1) + (A - 1) * cosW0 - 2 * sqrtA * alpha)
      a0 = (A + 1) - (A - 1) * cosW0 + 2 * sqrtA * alpha
      a1 = 2 * ((A - 1) - (A + 1) * cosW0)
      a2 = (A + 1) - (A - 1) * cosW0 - 2 * sqrtA * alpha
    }

    return .init(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
  }
}

// MARK: - DSP-Prozessor

/// Biquad-Kaskade pro Kanal mit Zustandsspeicher (Direct-Form-I transposed).
/// LOCK-FREI auf dem Realtime-Audio-Thread: `process` nimmt keine Locks und allokriert keinen
/// Speicher — Voraussetzung für Core-Audio-Realtime-Safety (sonst Clicks/Deadlock/Crash).
/// Reconfigure tauscht einen atomaren Zeiger auf eine unveränderliche Koeffizienten-Tabelle.
final class AudioEQProcessor {
  /// Immutable Biquad-Koeffizienten-Tabelle + kanalbezogener Zustandspuffer.
  /// Wird als Ganzes atomar getauscht — `process` liest nur einen stabilen Snapshot.
  private final class Configuration {
    let coefficients: [AudioEQBiquadCoefficients]
    /// [Kanal][Stage] — Direct-Form-I transposed Zustände. Feste Puffer, keine Reallokation.
    let states: UnsafeMutablePointer<StageState>
    let stageCount: Int
    let channelCount: Int

    init(coefficients: [AudioEQBiquadCoefficients], channelCount: Int) {
      self.coefficients = coefficients
      self.stageCount = coefficients.count
      self.channelCount = channelCount
      let count = max(1, channelCount) * max(1, coefficients.count)
      states = .allocate(capacity: count)
      states.initialize(repeating: StageState(), count: count)
    }

    deinit {
      states.deinitialize(count: max(1, channelCount) * max(1, stageCount))
      states.deallocate()
    }

    func copyStates(from other: Configuration) {
      guard stageCount == other.stageCount, channelCount == other.channelCount else { return }
      let count = max(1, channelCount) * max(1, stageCount)
      states.update(from: other.states, count: count)
    }
  }

  /// Zustand pro Biquad (Direct-Form-I transposed).
  struct StageState {
    var z1: Double = 0
    var z2: Double = 0
  }

  /// Atomic-Swap-Konfiguration. `process` hält eine starke Referenz auf den gelesenen Snapshot.
  private var heap: Configuration

  init() {
    heap = Configuration(coefficients: [], channelCount: 2)
  }

  /// Konfiguriert die Filterkette neu. Aufrufbar vom Main-Thread oder aus `prepare` (Audio-Pipeline).
  /// Kein Lock — `process` hält den alten Snapshot per starker Referenz, bis der Callback fertig ist.
  func configure(filters: [AudioEQBiquadFilter], sampleRate: Double, channelCount: Int) {
    let coeffs = filters.map { AudioEQBiquadCoefficients.compute(filter: $0, sampleRate: sampleRate) }
    let newConfig = Configuration(coefficients: coeffs, channelCount: max(1, channelCount))
    let previous = heap
    if previous.stageCount == newConfig.stageCount,
      previous.channelCount == newConfig.channelCount,
      newConfig.stageCount > 0
    {
      newConfig.copyStates(from: previous)
    }
    heap = newConfig
  }

  /// Verarbeitet deinterleaved Float32-Puffer (ein `AudioBuffer` pro Kanal, wie `MTAudioProcessingTap`).
  func process(buffers: UnsafeMutableAudioBufferListPointer, frameCount: AVAudioFrameCount) {
    let config = heap
    let stages = config.stageCount
    guard stages > 0 else { return }
    let frames = Int(frameCount)
    guard frames > 0 else { return }
    let channelCount = min(buffers.count, config.channelCount)

    for ch in 0..<channelCount {
      guard let data = buffers[ch].mData else { continue }
      let buffer = data.assumingMemoryBound(to: Float.self)
      let base = ch * stages
      for frame in 0..<frames {
        var sample = Double(buffer[frame])
        for stage in 0..<stages {
          let c = config.coefficients[stage]
          let sPtr = config.states.advanced(by: base + stage)
          // Direct-Form-II transposed (RBJ):
          //   y  = b0*x + z1
          //   z1 = b1*x - a1*y + z2
          //   z2 = b2*x - a2*y
          let y = c.b0 * sample + sPtr.pointee.z1
          sPtr.pointee.z1 = c.b1 * sample - c.a1 * y + sPtr.pointee.z2
          sPtr.pointee.z2 = c.b2 * sample - c.a2 * y
          sample = y
        }
        // Soft-Clip gegen gelegentliche Übersteuerung durch Shelving-Boosts.
        if sample > 1.0 { sample = 1.0 }
        else if sample < -1.0 { sample = -1.0 }
        buffer[frame] = Float(sample)
      }
    }
  }

  deinit {
    // `heap` wird durch ARC freigegeben.
  }
}

// MARK: - MTAudioProcessingTap Factory

/// Hält Processor + Preset zusammen, damit die C-Callbacks keinen Swift-Kontext capturen müssen.
/// Preset-Wechsel sind live (ohne Tap-Rebuild) möglich — `reconfigure` tauscht nur die Filter,
/// der Tap und sein Audio-Render-Pfad bleiben unangetastet (verhindert Race/Crash beim Swappen
/// des `audioMix` während der Audio-Realtime-Thread läuft).
final class AudioEQTapContext {
  let processor: AudioEQProcessor
  private(set) var preset: AudioEQPreset
  /// Letzte bekannte Sample-Rate aus `prepare`-Callback. Für Live-Reconfigure gebraucht.
  private var lastSampleRate: Double = 44100
  /// Letzte bekannte Kanalzahl aus `prepare`/`process`. Für Live-Reconfigure gebraucht.
  private var lastChannelCount: Int = 2

  init(processor: AudioEQProcessor, preset: AudioEQPreset) {
    self.processor = processor
    self.preset = preset
  }

  /// Wird aus `prepare`-Callback aufgerufen — initialisiert Processor mit Sample-Rate + Kanälen.
  func prepare(processingFormat: UnsafePointer<AudioStreamBasicDescription>) {
    lastSampleRate = processingFormat.pointee.mSampleRate
    lastChannelCount = Int(processingFormat.pointee.mChannelsPerFrame)
    processor.configure(
      filters: preset.filters, sampleRate: lastSampleRate, channelCount: lastChannelCount)
  }

  /// Live-Preset-Wechsel — nur Filterkoeffizienten tauschen (thread-sicher im Processor).
  func reconfigure(preset: AudioEQPreset) {
    self.preset = preset
    processor.configure(
      filters: preset.filters, sampleRate: lastSampleRate, channelCount: lastChannelCount)
  }
}

/// Erzeugt einen `MTAudioProcessingTap`, der rohe PCM-Samples durch einen `AudioEQProcessor` leitet.
///
/// Lifecycle: Das `init`-Callback retained den Context (`passRetained`) und speichert ihn als
/// Tap-Storage. Das `finalize`-Callback releast ihn wieder. Damit hat der Tap eine EIGENE
/// ARC-Referenz — der PlaybackController darf seinen `eqTapContext` jederzeit auf `nil` setzen,
/// ohne dass der Audio-Realtime-Thread ins Leere greift (use-after-free-Wurzel behoben).
enum AudioEQTapFactory {

  /// Erzeugt einen Tap. Der Context wird vom Tap retained — Aufrufer darf seine eigene Ref
  /// nach dem Erzeugen freigeben.
  static func makeTap(context: AudioEQTapContext) -> MTAudioProcessingTap? {
    let clientPtr = Unmanaged.passRetained(context).toOpaque()

    var callbacks = MTAudioProcessingTapCallbacks(
      version: kMTAudioProcessingTapCallbacksVersion_0,
      clientInfo: clientPtr,
      init: { _, clientInfo, tapStorageOut in
        // Storage = clientInfo (retained) — Tap hält eigene Ref, Audio-Thread sicher.
        tapStorageOut.pointee = clientInfo
      },
      finalize: { tap in
        // Tap wird freigegeben — mit ihm unsere retained Ref auf den Context.
        let raw = MTAudioProcessingTapGetStorage(tap)
        Unmanaged<AudioEQTapContext>.fromOpaque(raw).release()
      },
      prepare: { tap, _, processingFormat in
        let raw = MTAudioProcessingTapGetStorage(tap)
        let ctx = Unmanaged<AudioEQTapContext>.fromOpaque(raw).takeUnretainedValue()
        ctx.prepare(processingFormat: processingFormat)
      },
      unprepare: { _ in },
      process: { tap, numberFrames, _, bufferListInOut, numberFramesOut, flagsOut in
        let raw = MTAudioProcessingTapGetStorage(tap)
        let ctx = Unmanaged<AudioEQTapContext>.fromOpaque(raw).takeUnretainedValue()

        // WICHTIG: Die Buffer-Zeiger in `bufferListInOut` sind beim Aufruf NULL. Erst
        // `MTAudioProcessingTapGetSourceAudio` füllt sie mit den Quell-Frames (system-owned,
        // nur während des Callbacks gültig). Ohne diesen Aufruf liefert der Player stumm.
        var sourceFlags: MTAudioProcessingTapFlags = 0
        var sourceFrames: CMItemCount = 0
        let status = MTAudioProcessingTapGetSourceAudio(
          tap,
          numberFrames,
          bufferListInOut,
          &sourceFlags,
          nil,
          &sourceFrames
        )
        guard status == noErr else {
          numberFramesOut.pointee = 0
          return
        }

        // In-place Verarbeitung der gelieferten Quell-Frames. MTAudioProcessingTap liefert
        // deinterleaved Float32 — pro Buffer ein Kanal.
        let frames = AVAudioFrameCount(sourceFrames)
        if frames > 0 {
          let buffers = UnsafeMutableAudioBufferListPointer(bufferListInOut)
          if buffers.count > 0 {
            ctx.processor.process(buffers: buffers, frameCount: frames)
          }
        }

        // StartOfStream/EndOfStream-Flags durchreichen.
        flagsOut.pointee = sourceFlags
        numberFramesOut.pointee = sourceFrames
      }
    )

    var tapRef: MTAudioProcessingTap?
    let status = withUnsafePointer(to: &callbacks) { cbPtr -> OSStatus in
      MTAudioProcessingTapCreate(
        kCFAllocatorDefault,
        cbPtr,
        kMTAudioProcessingTapCreationFlag_PostEffects,
        &tapRef
      )
    }
    // Bei Misserfolg müssen wir die oben retained Ref wieder freigeben.
    if status != noErr || tapRef == nil {
      Unmanaged<AudioEQTapContext>.fromOpaque(clientPtr).release()
    }
    guard status == noErr, let tap = tapRef else {
      os_log(.error, "EQ-Tap-Erzeugung fehlgeschlagen: %{public}d", status)
      return nil
    }
    return tap
  }
}
