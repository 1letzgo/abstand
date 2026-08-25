import Combine
import Foundation
import Network
import os
import ReadiumShared
import SwiftData
import SwiftUI
import UIKit

/// Katalog-/Podcast-Domäne von `AppModel` — mechanisch aus AppModel.swift ausgelagert
/// (Struktur-Plan Schritt 2a: MARK-Auslagerung ohne Verhaltensänderung).
extension AppModel {
  /// SwiftUI-`Picker`/`tag` für „keine Bibliothek“ (persistiert als `Keys.librarySelectionNone`).
  static var libraryPickerNoneTag: String { Keys.librarySelectionNone }

  // MARK: - Catalog
  // MARK: - Catalog

  func reloadLibrary(reset: Bool, preserveOtherCachedPages: Bool = false) async {
    guard let lib = booksCatalogLibrary else {
      if mayUseServerNetwork, startShelves.isEmpty {
        await loadStartDashboard()
      }
      return
    }
    libraryReloadSerial &+= 1
    let reloadSerial = libraryReloadSerial
    let expectedLibraryId = lib.id
    let expectedSortKey = catalogSortField.apiSortParameter
    let expectedAscending = catalogSortField == .random ? true : !catalogSortDescending
    let expectedFilter = activeLibraryFilter

    // Lokale DB nur für die SOFORT-Anzeige, bevor der Server antwortet — und nur wenn der
    // Cache-Slug (Sort/Filter) exakt passt. Online kein Superset-Fallback: der würde kurz die
    // ganze lokale Lib in Client-Sortierung zeigen und gleich durch Server-Seite 0 ersetzt
    // (Flash beim Sort-/Filterwechsel). Offline: Superset erlaubt.
    // Ein echter Reset holt unten IMMER Seite 0 frisch vom Server — die Antwort ist verbindlich.
    var didWarmFromExactLocalCatalog = false
    if reset {
      didWarmFromExactLocalCatalog = loadLibraryFromLocalStore(
        allowSupersetFallback: !isNetworkReachable
      )
    }
    guard mayUseServerNetwork else {
      if reset, !didWarmFromExactLocalCatalog {
        _ = loadLibraryFromLocalStore(allowSupersetFallback: true)
      }
      return
    }
    guard let c = client else {
      if reset, !didWarmFromExactLocalCatalog {
        _ = loadLibraryFromLocalStore(allowSupersetFallback: true)
      }
      if startShelves.isEmpty { await loadStartDashboard() }
      return
    }
    if !isNetworkReachable {
      if reset, !didWarmFromExactLocalCatalog {
        _ = loadLibraryFromLocalStore(allowSupersetFallback: true)
      }
      refreshDownloadedShelfFromManifests()
      applyCachedStartDashboard()
      return
    }
    isLoadingLibrary = true
    defer {
      if libraryReloadSerial == reloadSerial {
        isLoadingLibrary = false
      }
    }
    // Kein passender Sort/Filter-Cache: alte Liste nicht stehen lassen und keinen Superset
    // blenden — Spinner bis Server-Seite 0 da ist. Stille Background-Refreshes behalten die Liste.
    if reset, !preserveOtherCachedPages, !didWarmFromExactLocalCatalog {
      var transaction = Transaction()
      transaction.disablesAnimations = true
      withTransaction(transaction) {
        books = []
        libraryTotal = 0
        libraryPage = 0
      }
    }
    do {
      if reset {
        libraryPage = 0
      }
      let pageIndex = libraryPage
      let (page, _) = try await c.libraryItems(
        libraryId: expectedLibraryId,
        page: pageIndex,
        limit: Self.libraryCatalogPageLimit,
        sort: expectedSortKey,
        ascending: expectedAscending,
        minified: true,
        filter: expectedFilter
      )
      guard libraryReloadSerial == reloadSerial,
        !offlineHomeUIActive,
        booksCatalogLibrary?.id == expectedLibraryId,
        catalogSortField.apiSortParameter == expectedSortKey,
        (catalogSortField == .random ? true : !catalogSortDescending) == expectedAscending,
        activeLibraryFilter == expectedFilter
      else { return }
      let pageBooks = page.results.filter(\.isUsableLibraryCatalogRow)
      if let store = currentLocalLibraryStore() {
        if reset, preserveOtherCachedPages {
          do { try await store.refreshCatalogFirstPagePreservingRest(
            libraryId: expectedLibraryId, sortField: expectedSortKey, ascending: expectedAscending,
            filterKey: expectedFilter,
            total: page.total, items: pageBooks)
          } catch {
            AppLog.library.warning("LocalStore refreshCatalogFirstPagePreservingRest failed: \(error.localizedDescription, privacy: .public)")
          }
        } else if reset {
          do { try await store.replaceCatalogFirstPage(
            libraryId: expectedLibraryId, sortField: expectedSortKey, ascending: expectedAscending,
            filterKey: expectedFilter,
            total: page.total, items: pageBooks)
          } catch {
            AppLog.library.warning(
              "LocalStore replaceCatalogFirstPage failed: \(error.localizedDescription, privacy: .public)")
          }
        } else {
          do { try await store.appendCatalogPage(
            libraryId: expectedLibraryId, total: page.total, items: pageBooks)
          } catch {
            AppLog.library.warning(
              "LocalStore appendCatalogPage failed: \(error.localizedDescription, privacy: .public)")
          }
        }
      }
      guard libraryReloadSerial == reloadSerial, !offlineHomeUIActive else { return }
      if reset, preserveOtherCachedPages {
        // Stiller Hintergrund-Refresh (z. B. nach Bootstrap): nur die ersten `pageBooks.count`
        // Positionen mit der frischen Server-Reihenfolge ersetzen, bereits gescrollte Folgeseiten
        // bleiben unangetastet — sonst würde die Liste während eines unbeauftragten Refreshs
        // sichtbar auf Seite 0 zurückschrumpfen.
        mergeServerFirstPageIntoLocalBooksPreservingRest(pageBooks, total: page.total)
      } else if reset {
        // Echter Reset (Pull-to-Refresh, Sort-/Filterwechsel): Server-Seite 0 ist verbindlich.
        let unchanged =
          pageBooks.count == books.count
          && zip(pageBooks, books).allSatisfy { $0.id == $1.id && $0.updatedAt == $1.updatedAt }
        if !unchanged { books = pageBooks }
        libraryTotal = page.total
      } else {
        books.append(contentsOf: pageBooks)
        libraryTotal = page.total
      }
      libraryPage = page.page + 1
      if reset {
        lastBooksCatalogServerSyncAt = Date()
      }
    } catch {
      publishErrorUnlessBenignCancellation(error)
    }
    guard libraryReloadSerial == reloadSerial, !offlineHomeUIActive else { return }
    if startShelves.isEmpty {
      await loadStartDashboard()
    }
  }

  // MARK: - Podcasts

  // MARK: - Podcasts

  func loadPodcastEpisodeListeningSessions(
    _ episode: ABSPodcastEpisodeListItem,
    showMediaId: String? = nil,
    maxPages: Int = 20
  ) async -> [ABSListeningSession] {
    let bid = episode.libraryItemId.trimmingCharacters(in: .whitespacesAndNewlines)
    let eid = episode.episodeId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !bid.isEmpty, !eid.isEmpty else { return [] }
    let cached = cachedListeningSessions(libraryItemId: bid, episodeId: eid)
    guard let c = client, isNetworkReachable, mayUseServerNetwork else {
      return cached ?? []
    }
    let mediaKey = showMediaId
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .flatMap { $0.isEmpty ? nil : $0 }

    func collectPaged(_ load: (Int) async throws -> ABSListeningSessionsPayload) async throws
      -> [ABSListeningSession]
    {
      var collected: [ABSListeningSession] = []
      collected.reserveCapacity(16)
      var page = 0
      while page < maxPages {
        let res = try await load(page)
        collected.append(contentsOf: res.sessions)
        page += 1
        if page >= res.numPages || res.sessions.isEmpty { break }
      }
      return collected
    }

    func legacy() async -> [ABSListeningSession] {
      await loadPodcastEpisodeListeningSessionsLegacyFiltered(
        client: c,
        libraryItemId: bid,
        episodeId: eid,
        showMediaId: mediaKey,
        maxPages: maxPages)
    }

    do {
      let rows = try await collectPaged { p in
        try await c.listeningSessionsForLibraryItem(
          libraryItemId: bid, episodeId: eid, itemsPerPage: 100, page: p)
      }
      let sorted: [ABSListeningSession]
      if !rows.isEmpty {
        sorted = rows.sorted { $0.startedAt > $1.startedAt }
      } else {
        sorted = await legacy()
      }
      persistListeningSessions(libraryItemId: bid, episodeId: eid, sessions: sorted)
      return sorted
    } catch {
      let legacyRows = await legacy()
      if !legacyRows.isEmpty {
        persistListeningSessions(libraryItemId: bid, episodeId: eid, sessions: legacyRows)
        return legacyRows
      }
      return cached ?? []
    }
  }

  private func loadPodcastEpisodeListeningSessionsLegacyFiltered(
    client: ABSAPIClient,
    libraryItemId bid: String,
    episodeId eid: String,
    showMediaId: String?,
    maxPages: Int
  ) async -> [ABSListeningSession] {
    var collected: [ABSListeningSession] = []
    collected.reserveCapacity(16)
    var page = 0
    let mid = showMediaId
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .flatMap { $0.isEmpty ? nil : $0 }
    let eidLower = eid.lowercased()
    while page < maxPages {
      do {
        let res = try await client.listeningSessionsMe(itemsPerPage: 100, page: page)
        let filtered = res.sessions.filter { s in
          let sEp = s.episodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
          guard !sEp.isEmpty, sEp.lowercased() == eidLower else { return false }
          if s.libraryItemId == bid { return true }
          if let mid, let raw = s.bookId {
            let b = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !b.isEmpty, b == mid { return true }
          }
          return false
        }
        collected.append(contentsOf: filtered)
        page += 1
        if page >= res.numPages { break }
      } catch {
        break
      }
    }
    return collected.sorted { $0.startedAt > $1.startedAt }
  }

  func loadPodcastEpisodeDetail(_ episode: ABSPodcastEpisodeListItem) async -> ABSPodcastEpisodeExpandedDetail? {
    guard let c = client, isNetworkReachable else {
      return cachedPodcastEpisodeDetail(episode) ?? Self.emptyPodcastEpisodeDetail(episode)
    }
    do {
      let show = try await c.item(id: episode.libraryItemId, expanded: true)
      persistBookDetail(show)
      return Self.makePodcastEpisodeDetail(episode: episode, show: show)
    } catch {
      return cachedPodcastEpisodeDetail(episode) ?? Self.emptyPodcastEpisodeDetail(episode)
    }
  }
}
