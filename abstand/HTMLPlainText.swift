import Foundation

func absPlainText(fromHTML html: String?) -> String {
  guard var s = html?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return "" }
  s = s.replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
  s = s.replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
  s = s.replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
  s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
  return s.trimmingCharacters(in: .whitespacesAndNewlines)
}
