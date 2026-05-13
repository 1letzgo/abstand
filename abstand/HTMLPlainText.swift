import Foundation

/// Entfernt HTML und bereinigt typische Podcast-/RSS-Floskeln: viele Leerzeilen → höchstens eine Leerzeile zwischen Absätzen.
func absPlainText(fromHTML html: String?) -> String {
  guard var s = html?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return "" }
  s = s.replacingOccurrences(of: "\r\n", with: "\n")
  s = s.replacingOccurrences(of: "\r", with: "\n")
  s = s.replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
  s = s.replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
  s = s.replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
  s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
  s = absCollapseExcessBlankLines(in: s)
  return s.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Trimmt jede Zeile und lässt zwischen Inhaltszeilen maximal **eine** Leerzeile zu (zwei `\n` hintereinander).
private func absCollapseExcessBlankLines(in text: String) -> String {
  let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
  var out: [String] = []
  out.reserveCapacity(lines.count)
  for line in lines {
    if line.isEmpty {
      if out.last?.isEmpty == true { continue }
      out.append("")
    } else {
      out.append(line)
    }
  }
  while out.first?.isEmpty == true { out.removeFirst() }
  while out.last?.isEmpty == true { out.removeLast() }
  return out.joined(separator: "\n")
}
