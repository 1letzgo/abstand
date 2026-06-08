import Speech

/// Read-along braucht `SpeechTranscriber` (Hardware ab iPhone 12).
enum SpeechTranscriberAvailability {
  static func isSupported() async -> Bool {
    guard SpeechTranscriber.isAvailable else { return false }
    return !(await SpeechTranscriber.supportedLocales).isEmpty
  }
}
