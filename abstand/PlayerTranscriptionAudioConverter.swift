import AVFoundation

/// PCM-Konvertierung für `SpeechAnalyzer` (Zielformat vom Framework).
final class PlayerTranscriptionAudioConverter {
  private let converter: AVAudioConverter

  init?(sourceFormat: AVAudioFormat, targetFormat: AVAudioFormat) {
    guard let c = AVAudioConverter(from: sourceFormat, to: targetFormat) else { return nil }
    converter = c
  }

  func convert(_ buffer: AVAudioPCMBuffer, to targetFormat: AVAudioFormat) throws -> AVAudioPCMBuffer {
    let outCapacity = AVAudioFrameCount(
      Double(buffer.frameLength) * targetFormat.sampleRate / buffer.format.sampleRate
    ) + 32
    guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: max(outCapacity, 4096))
    else {
      throw PlayerLiveTranscriptionError.conversionFailed
    }

    var error: NSError?
    var consumed = false
    let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
      if consumed {
        outStatus.pointee = .noDataNow
        return nil
      }
      consumed = true
      outStatus.pointee = .haveData
      return buffer
    }

    converter.convert(to: out, error: &error, withInputFrom: inputBlock)
    if let error { throw error }
    return out
  }
}
