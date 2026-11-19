import Foundation

/// Eigene Primary-Bibliothek des eBooks-Tabs („Primary eBook library“ in Settings).
/// Verhält sich wie die Audiobook-Primary (`Keys.booksLibrary`): leer = automatisch (Server-Standard,
/// sonst erste Buch-Bibliothek), `Keys.librarySelectionNone` = bewusst keine → eBooks-Tab ausgeblendet.
/// Fokus (`focusedEbooksLibrary`) ist vom Audiobooks-Katalog entkoppelt.
extension AppModel {
  var ebooksLibraryPreferenceIsNone: Bool {
    Self.storedEbooksLibraryPreference() == Keys.librarySelectionNone
  }

  /// eBooks-Tab: Fokus, sonst Primary.
  var ebooksCatalogLibrary: ABSLibrary? { focusedEbooksLibrary ?? selectedEbooksLibrary }

  /// Bibliotheks-Picker der eBooks-Leiste: eBook-Primary zuerst, dann die eBook-Zusatzbibliotheken
  /// (eigene Auswahl in Settings › eBooks, unabhängig von den Audiobook-Zusatzbibliotheken).
  var ebooksPickerLibraries: [ABSLibrary] {
    var out: [ABSLibrary] = []
    if let primary = selectedEbooksLibrary {
      out.append(libraries.first(where: { $0.id == primary.id && $0.isBookLibrary }) ?? primary)
    }
    for lib in activeEbookLibraries where !out.contains(where: { $0.id == lib.id }) {
      out.append(lib)
    }
    return out
  }

  /// Aktive eBook-Bibliotheken in Nutzer-Reihenfolge (wie `activeBookLibraries`).
  var activeEbookLibraries: [ABSLibrary] {
    let order = Dictionary(uniqueKeysWithValues: activeEbooksLibraryIds.enumerated().map { ($1, $0) })
    return sortedBookLibraries
      .filter { order[$0.id] != nil }
      .sorted { (order[$0.id] ?? .max) < (order[$1.id] ?? .max) }
  }

  var activeEbooksLibraryIdSet: Set<String> {
    Set(activeEbooksLibraryIds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
  }

  func isEbooksLibraryActive(_ libraryId: String) -> Bool {
    let id = libraryId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isEmpty else { return false }
    return activeEbooksLibraryIdSet.contains(id)
  }

  /// Settings: eBook-Bibliothek aktivieren/deaktivieren — Gegenstück zu `setBooksLibraryActive`.
  /// Wird die eBook-Primary abgeschaltet, rückt die nächste aktive nach, sonst „None“.
  func setEbooksLibraryActive(_ libraryId: String, enabled: Bool) {
    let id = libraryId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isEmpty, sortedBookLibraries.contains(where: { $0.id == id }) else { return }
    migrateActiveEbooksLibraryIdsIfNeeded()
    var next = activeEbooksLibraryIds
    if enabled {
      if !next.contains(id) { next.append(id) }
      applyActiveEbooksLibraryIds(next)
      return
    }
    next.removeAll { $0 == id }
    if selectedEbooksLibrary?.id == id {
      if let replacement = next.first.flatMap({ rid in sortedBookLibraries.first(where: { $0.id == rid }) }) {
        applyActiveEbooksLibraryIds(next)
        selectEbooksLibrary(replacement)
      } else {
        applyActiveEbooksLibraryIds([])
        clearEbooksLibrarySelection()
      }
      return
    }
    applyActiveEbooksLibraryIds(next)
    if focusedEbooksLibrary?.id == id {
      focusedEbooksLibrary = selectedEbooksLibrary
    }
  }

  /// Settings: eBook-Primary setzen und persistieren (Audiobooks bleiben unberührt).
  func selectEbooksLibrary(_ lib: ABSLibrary) {
    guard lib.isBookLibrary else { return }
    if selectedEbooksLibrary?.id == lib.id {
      if selectedEbooksLibrary?.name != lib.name || selectedEbooksLibrary?.mediaType != lib.mediaType {
        selectedEbooksLibrary = lib
      }
      if focusedEbooksLibrary?.id != lib.id { focusedEbooksLibrary = lib }
      setShowEbooksTab(true)
      return
    }
    ebookCatalogQuickFilter = nil
    selectedEbooksLibrary = lib
    UserDefaults.standard.set(lib.id, forKey: Keys.ebooksLibrary)
    // Erst migrieren (übernimmt ggf. die Audiobook-Auswahl), dann Primary in die aktive Menge.
    migrateActiveEbooksLibraryIdsIfNeeded()
    var next = activeEbooksLibraryIds
    if !next.contains(lib.id) { next.insert(lib.id, at: 0) }
    applyActiveEbooksLibraryIds(next)
    // Listen lädt der eBooks-Tab selbst nach (`.task(id:)` auf `ebooksCatalogLibrary`).
    focusedEbooksLibrary = lib
    syncStoredAccountFromSession()
    setShowEbooksTab(true)
    refreshEbookContinueReadingShelf()
  }

  /// Settings „None“: eBook-Primary bewusst leeren → eBooks-Tab ausblenden.
  func clearEbooksLibrarySelection() {
    ebookCatalogQuickFilter = nil
    selectedEbooksLibrary = nil
    focusedEbooksLibrary = nil
    applyActiveEbooksLibraryIds([])
    UserDefaults.standard.set(Keys.librarySelectionNone, forKey: Keys.ebooksLibrary)
    syncStoredAccountFromSession()
    setShowEbooksTab(false)
    // „Continue reading“ hängt an der eBook-Primary — Regal entfernen.
    refreshEbookContinueReadingShelf()
  }

  // MARK: - eBook-Zusatzbibliotheken (Persistenz, Migration, Abgleich)

  private func activeEbooksLibraryIdsDefaultsKey() -> String {
    if let key = activeAccountKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
      return "\(Keys.activeEbooksLibraryIds).\(key)"
    }
    return Keys.activeEbooksLibraryIds
  }

  func applyActiveEbooksLibraryIds(_ ids: [String]) {
    var unique: [String] = []
    for raw in ids {
      let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      if !id.isEmpty, !unique.contains(id) { unique.append(id) }
    }
    activeEbooksLibraryIds = unique
    if let data = ActiveLibraryIdsStore.encode(unique) {
      UserDefaults.standard.set(data, forKey: activeEbooksLibraryIdsDefaultsKey())
    } else {
      UserDefaults.standard.removeObject(forKey: activeEbooksLibraryIdsDefaultsKey())
    }
    syncStoredAccountFromSession(markActive: false)
  }

  func loadActiveEbooksLibraryIdsFromUserDefaults() {
    activeEbooksLibraryIds = ActiveLibraryIdsStore.decode(
      UserDefaults.standard.data(forKey: activeEbooksLibraryIdsDefaultsKey()))
  }

  func removeActiveEbooksLibraryIdsFromUserDefaults() {
    UserDefaults.standard.removeObject(forKey: activeEbooksLibraryIdsDefaultsKey())
  }

  /// Account-Wechsel: gespeicherte Auswahl übernehmen; fehlt sie (Account vor diesem Update),
  /// bleibt der Key leer und die Migration übernimmt beim nächsten Abgleich die Audiobook-Auswahl.
  func applyActiveEbooksLibraryIdsFromStoredAccount(_ ids: [String]?) {
    if let ids {
      applyActiveEbooksLibraryIds(ids)
    } else {
      activeEbooksLibraryIds = []
      removeActiveEbooksLibraryIdsFromUserDefaults()
    }
  }

  /// Einmalig, solange für diesen Account noch nie eine eBook-Auswahl gespeichert wurde: die bisherigen
  /// Audiobook-Zusatzbibliotheken übernehmen (der eBooks-Picker zeigte bis dahin genau diese) — so ändert
  /// sich nach dem Update nichts Sichtbares. Danach sind beide Auswahlen unabhängig.
  func migrateActiveEbooksLibraryIdsIfNeeded() {
    guard UserDefaults.standard.data(forKey: activeEbooksLibraryIdsDefaultsKey()) == nil else { return }
    if ebooksLibraryPreferenceIsNone {
      applyActiveEbooksLibraryIds([])
      return
    }
    var ids = activeBooksLibraryIds
    if let primary = selectedEbooksLibrary?.id, !ids.contains(primary) {
      ids.insert(primary, at: 0)
    }
    applyActiveEbooksLibraryIds(ids)
  }

  /// Nach Server-Libraries (aus `reconcileActiveLibraryIdsWithServerLibraries`): migrieren, ungültige IDs
  /// entfernen, eBook-Primary sicherstellen — wie die Audiobook-Menge.
  func reconcileActiveEbooksLibraryIdsWithServerLibraries() {
    guard !libraries.isEmpty else { return }
    let valid = Set(sortedBookLibraries.map(\.id))
    guard !valid.isEmpty else { return }
    migrateActiveEbooksLibraryIdsIfNeeded()
    var ids = activeEbooksLibraryIds.filter { valid.contains($0) }
    if ebooksLibraryPreferenceIsNone {
      ids = []
    } else if let primary = selectedEbooksLibrary?.id, valid.contains(primary), !ids.contains(primary) {
      ids.insert(primary, at: 0)
    }
    if ids != activeEbooksLibraryIds {
      applyActiveEbooksLibraryIds(ids)
    }
    if let focused = focusedEbooksLibrary, !ebooksPickerLibraries.contains(where: { $0.id == focused.id }) {
      focusedEbooksLibrary = selectedEbooksLibrary
    }
  }

  /// Nav-Dropdown im eBooks-Tab: nur dessen Katalog-Fokus wechseln — keine Primary, kein Audiobooks-Katalog.
  func focusEbooksLibrary(_ lib: ABSLibrary) {
    guard lib.isBookLibrary, ebooksPickerLibraries.contains(where: { $0.id == lib.id }) else { return }
    if focusedEbooksLibrary?.id == lib.id {
      if focusedEbooksLibrary?.name != lib.name { focusedEbooksLibrary = lib }
      return
    }
    ebookCatalogQuickFilter = nil
    focusedEbooksLibrary = lib
  }

  /// Tab-Wechsel auf eBooks: Fokus zurück auf die eBook-Primary (wie Audiobooks).
  func resetFocusedEbooksLibraryToPrimary() {
    guard focusedEbooksLibrary?.id != selectedEbooksLibrary?.id else { return }
    focusedEbooksLibrary = selectedEbooksLibrary
  }

  /// Nach Server-Fetch: gleiche Auflösung wie die Audiobook-Primary in `resolveLibrariesAfterServerFetch`.
  func resolveEbooksLibraryAfterServerFetch(userDefaultLibraryId: String?) {
    let key = Self.storedEbooksLibraryPreference()
    if key == Keys.librarySelectionNone {
      selectedEbooksLibrary = nil
      focusedEbooksLibrary = nil
      setShowEbooksTab(false)
    } else if !key.isEmpty, let lib = libraries.first(where: { $0.id == key && $0.isBookLibrary }) {
      selectEbooksLibrary(lib)
    } else if let def = userDefaultLibraryId,
      let lib = libraries.first(where: { $0.id == def && $0.isBookLibrary })
    {
      selectEbooksLibrary(lib)
    } else if let first = sortedBookLibraries.first {
      selectEbooksLibrary(first)
    } else {
      selectedEbooksLibrary = nil
      focusedEbooksLibrary = nil
      UserDefaults.standard.set(Keys.librarySelectionNone, forKey: Keys.ebooksLibrary)
      setShowEbooksTab(false)
    }
    if let focused = focusedEbooksLibrary, !ebooksPickerLibraries.contains(where: { $0.id == focused.id }) {
      focusedEbooksLibrary = selectedEbooksLibrary
    }
    syncEbooksTabVisibilityFromLibraries()
  }

  /// Nach Server-Fetch: Tab-Sichtbarkeit mit Bibliotheksliste abgleichen und cachen.
  func syncEbooksTabVisibilityFromLibraries() {
    if isAppBootstrapInProgress { return }
    // Ohne geladene Bibliotheksliste (z. B. Offline-Kaltstart ohne Cache) gecachten Zustand behalten.
    if libraries.isEmpty { return }
    if ebooksLibraryPreferenceIsNone {
      setShowEbooksTab(false)
    } else {
      setShowEbooksTab(!sortedBookLibraries.isEmpty)
    }
  }

  /// Kaltstart: eBook-Primary aus UserDefaults (vor dem Server-Fetch). Nie gewählt → automatisch wie
  /// beim Server-Fetch, aber nur im Speicher (persistiert wird erst nach der Server-Auflösung).
  func restoreEbooksLibrarySelectionFromLocalStore() {
    if !libraries.isEmpty, sortedBookLibraries.isEmpty {
      selectedEbooksLibrary = nil
      focusedEbooksLibrary = nil
      return
    }
    let libId = Self.storedEbooksLibraryPreference()
    if libId == Keys.librarySelectionNone {
      selectedEbooksLibrary = nil
      focusedEbooksLibrary = nil
      return
    }
    let resolved: ABSLibrary?
    if libId.isEmpty {
      let def =
        UserDefaults.standard.string(forKey: Keys.userDefaultLibraryId)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      resolved =
        libraries.first(where: { $0.id == def && $0.isBookLibrary })
        ?? sortedBookLibraries.first
    } else {
      resolved =
        libraries.first(where: { $0.id == libId && $0.isBookLibrary })
        ?? ABSLibrary(id: libId, name: "eBooks", mediaType: "book", displayOrder: nil)
    }
    guard let resolved else { return }
    if activeEbooksLibraryIds.isEmpty {
      loadActiveEbooksLibraryIdsFromUserDefaults()
    }
    if selectedEbooksLibrary?.id != resolved.id || selectedEbooksLibrary?.name != resolved.name {
      selectedEbooksLibrary = resolved
    }
    if focusedEbooksLibrary == nil { focusedEbooksLibrary = resolved }
  }

  private func setShowEbooksTab(_ visible: Bool) {
    if isAppBootstrapInProgress { return }
    if showEbooksTab != visible {
      showEbooksTab = visible
    }
  }

  static func loadShowEbooksTabCached() -> Bool {
    if let cached = UserDefaults.standard.object(forKey: Keys.showEbooksTab) as? Bool {
      return cached
    }
    return storedEbooksLibraryPreference() != Keys.librarySelectionNone
  }

  private static func storedEbooksLibraryPreference() -> String {
    UserDefaults.standard.string(forKey: Keys.ebooksLibrary)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }
}
