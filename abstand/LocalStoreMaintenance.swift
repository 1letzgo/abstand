import Foundation
import SQLite3
import os

/// Wartung des SwiftData-Stores (`LocalLibrary.v2.store`).
///
/// SwiftData schreibt für jede Änderung eine Zeile in die Persistent-History (`ACHANGE`/`ATRANSACTION`)
/// und räumt sie nie auf. Der frühere Voll-Ersatz der Progress-Tabelle hat so über 100 Mio. History-Zeilen
/// erzeugt — Stores mit mehreren GB, obwohl die eigentlichen Daten nur wenige MB groß sind. Die History
/// wird von niemandem gelesen (kein CloudKit, keine Widgets), darf also gelöscht werden.
nonisolated enum LocalStoreMaintenance {
  /// Ab dieser Größe gilt ein Store als aufgebläht — gesunde Stores liegen bei wenigen MB bis
  /// niedrigen zweistelligen MB.
  static let oversizeThresholdBytes: Int64 = 256 * 1024 * 1024

  private static let busyPaths = OSAllocatedUnfairLock(initialState: Set<String>())

  /// Läuft für diesen Store gerade eine Bereinigung? Dann darf er nicht geöffnet werden.
  static func isCompacting(_ storeURL: URL) -> Bool {
    busyPaths.withLock { $0.contains(storeURL.standardizedFileURL.path) }
  }

  /// Startet die Bereinigung im Hintergrund, wenn der Store aufgebläht ist. `true`, wenn sie läuft
  /// (oder gerade gestartet wurde) — der Store ist dann vorübergehend nicht verfügbar.
  @discardableResult
  static func compactInBackgroundIfOversized(_ storeURL: URL) -> Bool {
    let path = storeURL.standardizedFileURL.path
    if isCompacting(storeURL) { return true }
    guard fileSize(at: storeURL) > oversizeThresholdBytes else { return false }
    busyPaths.withLock { _ = $0.insert(path) }
    Task.detached(priority: .utility) {
      let before = fileSize(at: storeURL)
      let ok = compact(storeURL)
      let after = fileSize(at: storeURL)
      busyPaths.withLock { _ = $0.remove(path) }
      AppLog.bootstrap.notice(
        "SwiftData store compact \(ok ? "ok" : "failed", privacy: .public): \(before / 1_048_576) MB → \(after / 1_048_576) MB")
    }
    return true
  }

  /// Aufgeblähte Stores anderer Accounts/alter Server-URLs (nicht der aktive) löschen. Sie sind nur ein
  /// Server-Spiegel und werden beim nächsten Login dieses Accounts neu aufgebaut. Bereinigen statt
  /// Löschen scheitert bei zweistelligen GB: VACUUM braucht Minuten, die App lebt im Hintergrund nicht
  /// so lange. Der aktive Store wird dagegen verkleinert (`compactInBackgroundIfOversized`).
  static func discardOversizedOtherStores(accountsDirectory: URL, excluding active: URL) {
    let fm = FileManager.default
    let activePath = active.standardizedFileURL.path
    guard let servers = try? fm.contentsOfDirectory(at: accountsDirectory, includingPropertiesForKeys: nil)
    else { return }
    for server in servers {
      var directories = [server]
      let users = server.appendingPathComponent("users", isDirectory: true)
      directories += (try? fm.contentsOfDirectory(at: users, includingPropertiesForKeys: nil)) ?? []
      for directory in directories {
        let store = directory.appendingPathComponent("LocalLibrary.v2.store")
        let path = store.standardizedFileURL.path
        guard path != activePath, fm.fileExists(atPath: store.path),
          fileSize(at: store) > oversizeThresholdBytes, !isCompacting(store)
        else { continue }
        // Während des Löschens darf niemand den Store öffnen (`isCompacting` sperrt `openContainer`).
        busyPaths.withLock { _ = $0.insert(path) }
        let size = fileSize(at: store)
        for url in [
          store,
          store.appendingPathExtension("wal"),
          store.appendingPathExtension("shm"),
          directory.appendingPathComponent(".LocalLibrary.v2_SUPPORT", isDirectory: true),
        ] {
          try? fm.removeItem(at: url)
        }
        busyPaths.withLock { _ = $0.remove(path) }
        AppLog.bootstrap.notice("Oversized inactive SwiftData store removed: \(size / 1_048_576) MB")
      }
    }
  }

  /// `CFNetworkDownload_*.tmp`: Zwischendateien abgebrochener Downloads. iOS räumt sie nicht zuverlässig
  /// auf — bei jedem Kaltstart entstehen sonst GB an totem Speicher. Nur alte Dateien löschen, damit ein
  /// laufender Download nie angetastet wird.
  static func removeStaleDownloadTempFiles(olderThan age: TimeInterval = 3600) {
    let fm = FileManager.default
    let temp = fm.temporaryDirectory
    guard let files = try? fm.contentsOfDirectory(
      at: temp, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])
    else { return }
    var removed: Int64 = 0
    for url in files where url.lastPathComponent.hasPrefix("CFNetworkDownload_") {
      let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
      guard let modified = values?.contentModificationDate, Date().timeIntervalSince(modified) > age else {
        continue
      }
      let size = Int64(values?.fileSize ?? 0)
      if (try? fm.removeItem(at: url)) != nil { removed += size }
    }
    if removed > 0 {
      AppLog.bootstrap.notice("Stale download temp files removed: \(removed / 1_048_576) MB")
    }
  }

  // MARK: - Intern

  private static func fileSize(at url: URL) -> Int64 {
    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    return size ?? 0
  }

  /// History leeren und den Store verkleinern. Die Nutzdaten bleiben unberührt.
  private static func compact(_ storeURL: URL) -> Bool {
    var db: OpaquePointer?
    guard sqlite3_open_v2(storeURL.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db else {
      sqlite3_close(db)
      return false
    }
    defer { sqlite3_close(db) }
    sqlite3_busy_timeout(db, 15_000)
    func run(_ sql: String) -> Bool { sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK }

    _ = run("PRAGMA wal_checkpoint(TRUNCATE);")
    // Fehlt eine Tabelle (Store ohne History), ist das kein Fehler.
    _ = run("DELETE FROM ACHANGE;")
    _ = run("DELETE FROM ATRANSACTION;")
    let vacuumed = run("VACUUM;")
    _ = run("PRAGMA wal_checkpoint(TRUNCATE);")
    return vacuumed
  }
}
