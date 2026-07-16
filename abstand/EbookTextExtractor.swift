import Foundation
import ReadiumShared
import ReadiumStreamer

/// Extrahiert Kapitel/Sätze aus einem lokalen EPUB für Forced Alignment.
enum EbookTextExtractor {
  /// Öffnet ein lokales EPUB und liefert geordnete Sätze mit stabilen IDs.
  static func extractChapters(from localFileURL: URL) async throws -> [EbookExtractedChapter] {
    guard let absolute = FileURL(url: localFileURL) else {
      throw EbookSyncError.ebookUnavailable
    }
    let httpClient = DefaultHTTPClient()
    let assetRetriever = AssetRetriever(httpClient: httpClient)
    let publicationOpener = PublicationOpener(
      parser: DefaultPublicationParser(
        httpClient: httpClient,
        assetRetriever: assetRetriever,
        pdfFactory: DefaultPDFDocumentFactory()
      )
    )

    let asset: Asset
    switch await assetRetriever.retrieve(url: absolute) {
    case let .success(a): asset = a
    case .failure:
      throw EbookSyncError.extractionFailed
    }

    let publication: Publication
    switch await publicationOpener.open(asset: asset, allowUserInteraction: false, sender: nil) {
    case let .success(pub): publication = pub
    case .failure:
      throw EbookSyncError.extractionFailed
    }
    guard publication.conforms(to: .epub) else {
      throw EbookSyncError.epubRequired
    }

    var chapters: [EbookExtractedChapter] = []
    for (chapterIndex, link) in publication.readingOrder.enumerated() {
      guard let resource = publication.get(link) else { continue }
      let html: String
      switch await resource.read() {
      case let .success(data):
        guard let decoded = String(data: data, encoding: .utf8)
          ?? String(data: data, encoding: .isoLatin1)
        else { continue }
        html = decoded
      case .failure:
        continue
      }

      let plain = plainText(fromHTML: html)
      let sentences = splitSentences(plain)
      guard !sentences.isEmpty else { continue }

      let href = Self.hrefKey(link.url().string)
      var extracted: [EbookExtractedSentence] = []
      for (sentenceIndex, text) in sentences.enumerated() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        extracted.append(
          EbookExtractedSentence(
            id: sentenceId(chapterIndex: chapterIndex, sentenceIndex: sentenceIndex),
            href: href,
            chapterIndex: chapterIndex,
            sentenceIndex: sentenceIndex,
            text: trimmed
          )
        )
      }
      guard !extracted.isEmpty else { continue }
      chapters.append(
        EbookExtractedChapter(
          href: href,
          chapterIndex: chapterIndex,
          title: link.title,
          sentences: extracted
        )
      )
    }

    guard !chapters.isEmpty else { throw EbookSyncError.extractionFailed }
    return chapters
  }

  static func sentenceId(chapterIndex: Int, sentenceIndex: Int) -> String {
    "abs-s-\(chapterIndex)-\(sentenceIndex)"
  }

  static func hrefKey(_ href: String) -> String {
    if let hash = href.firstIndex(of: "#") {
      return String(href[..<hash])
    }
    return href
  }

  static func normalizeForMatch(_ text: String) -> String {
    let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    let scalars = folded.unicodeScalars.map { scalar -> Character in
      if CharacterSet.alphanumerics.contains(scalar) { return Character(scalar) }
      return " "
    }
    let collapsed = String(scalars)
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
    return collapsed
  }

  static func tokens(from text: String) -> [String] {
    normalizeForMatch(text)
      .split(separator: " ")
      .map(String.init)
      .filter { !$0.isEmpty }
  }

  // MARK: - HTML / sentence helpers

  private static func plainText(fromHTML html: String) -> String {
    var text = html
    // Drop scripts/styles entirely.
    text = text.replacingOccurrences(
      of: #"(?is)<script\b[^>]*>.*?</script>"#,
      with: " ",
      options: .regularExpression
    )
    text = text.replacingOccurrences(
      of: #"(?is)<style\b[^>]*>.*?</style>"#,
      with: " ",
      options: .regularExpression
    )
    // Block boundaries → whitespace/newline so sentence splitting stays sane.
    text = text.replacingOccurrences(
      of: #"(?i)</(p|div|h[1-6]|li|tr|br|blockquote|section|article)>"#,
      with: "\n",
      options: .regularExpression
    )
    text = text.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
    text = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
    text = decodeHTMLEntities(text)
    text = text.replacingOccurrences(of: #"[ \t\f\r]+"#, with: " ", options: .regularExpression)
    text = text.replacingOccurrences(of: #"\n{2,}"#, with: "\n", options: .regularExpression)
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func decodeHTMLEntities(_ text: String) -> String {
    var out = text
    let named: [(String, String)] = [
      ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
      ("&quot;", "\""), ("&apos;", "'"), ("&#39;", "'"),
    ]
    for (entity, replacement) in named {
      out = out.replacingOccurrences(of: entity, with: replacement)
    }
    // Numeric entities &#123; / &#x1F;
    if let regex = try? NSRegularExpression(pattern: #"&#(\d+);"#) {
      let ns = out as NSString
      let matches = regex.matches(in: out, range: NSRange(location: 0, length: ns.length)).reversed()
      for match in matches {
        guard match.numberOfRanges >= 2 else { continue }
        let num = ns.substring(with: match.range(at: 1))
        if let value = Int(num), let scalar = UnicodeScalar(value) {
          out = (out as NSString).replacingCharacters(in: match.range, with: String(Character(scalar)))
        }
      }
    }
    return out
  }

  private static func splitSentences(_ text: String) -> [String] {
    let cleaned = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else { return [] }

    var sentences: [String] = []
    var current = ""
    for ch in cleaned {
      current.append(ch)
      if ".!?…".contains(ch) {
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 2 {
          sentences.append(trimmed)
        }
        current = ""
      }
    }
    let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
    if !tail.isEmpty {
      sentences.append(tail)
    }
    // Drop tiny fragments (page numbers, single letters).
    return sentences.filter { EbookTextExtractor.tokens(from: $0).count >= 2 || $0.count >= 12 }
  }
}
