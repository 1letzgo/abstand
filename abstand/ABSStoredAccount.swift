import Foundation

/// Persistierter Audiobookshelf-Account (Token + Metadaten für schnellen Wechsel).
struct ABSStoredAccount: Codable, Identifiable, Equatable {
  var accountKey: String
  var serverURL: String
  var token: String
  var userId: String
  var username: String
  var userType: String?
  var booksLibraryId: String?
  var podcastsLibraryId: String?
  var ebooksLibraryId: String?
  /// Aktive Books-Library-IDs (inkl. Primary); `nil` = noch nicht migriert.
  var activeBooksLibraryIds: [String]? = nil
  /// Aktive Podcast-Library-IDs (inkl. Primary); `nil` = noch nicht migriert.
  var activePodcastLibraryIds: [String]? = nil
  var lastUsedAt: Date

  var id: String { accountKey }

  static func makeKey(serverURL: String, userId: String) -> String {
    let normalized =
      ABSAPIClient.normalizeServerURL(serverURL)?.absoluteString.lowercased()
      ?? serverURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let uid = userId.trimmingCharacters(in: .whitespacesAndNewlines)
    return "\(normalized)|\(uid)"
  }

  var displayServerHost: String {
    ABSAPIClient.normalizeServerURL(serverURL)?.host ?? serverURL
  }

  var displayUsername: String {
    let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? "Account" : name
  }
}

enum ABSStoredAccountsPersistence {
  static let accountsKey = "abstand_stored_accounts"
  static let activeAccountKey = "abstand_active_account_key"

  static func loadAccounts() -> [ABSStoredAccount] {
    guard let data = UserDefaults.standard.data(forKey: accountsKey) else { return [] }
    return (try? ABSJSON.decoder().decode([ABSStoredAccount].self, from: data)) ?? []
  }

  static func saveAccounts(_ accounts: [ABSStoredAccount]) {
    guard let data = try? ABSJSON.encoder().encode(accounts) else { return }
    UserDefaults.standard.set(data, forKey: accountsKey)
  }

  static func loadActiveAccountKey() -> String? {
    UserDefaults.standard.string(forKey: activeAccountKey)
  }

  static func saveActiveAccountKey(_ key: String?) {
    if let key, !key.isEmpty {
      UserDefaults.standard.set(key, forKey: activeAccountKey)
    } else {
      UserDefaults.standard.removeObject(forKey: activeAccountKey)
    }
  }
}
