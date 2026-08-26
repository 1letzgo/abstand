import Combine
import Foundation
import Network
import os
import ReadiumShared
import SwiftData
import SwiftUI
import UIKit

/// Session/Auth- und Bootstrap-Domäne von `AppModel` — mechanisch aus AppModel.swift ausgelagert
/// (Struktur-Plan Schritt 2a: MARK-Auslagerung ohne Verhaltensänderung).
extension AppModel {
  // MARK: - Session / Auth
  // MARK: - Session / Auth

  func bootstrapFromStoredCredentials() async {
    if Task.isCancelled { return }
    let sp = AppLog.launchSignposter.beginInterval("bootstrap")
    defer { AppLog.launchSignposter.endInterval("bootstrap", sp) }
    guard ABSAPIClient.normalizeServerURL(serverURL) != nil, !token.isEmpty else { return }
    bootstrapSupersededByOffline = false

    // SwiftData-Store für den aktiven Account öffnen/wechseln (noch ohne Domänen-Daten, siehe Migrationsplan).
    if let localStore = currentLocalLibraryStore() {
      Task.detached(priority: .utility) {
        await localStore.markOpened()
      }
    }

    if offlineHomeMode {
      isAppBootstrapInProgress = false
      scheduleFinishDeferredLaunchLocalRestore()
      await bootstrapLocalSessionOnly()
      scheduleDeferredWorkAfterConnect()
      return
    }

    // Nur Downloads-Manifest früh — Katalog/Prewarm erst nach Connect + Home/Player.
    scheduleFinishDeferredLaunchLocalRestore()

    // Continue-Cache aus init fertig anwenden, bevor Cache-vs-Network entschieden wird.
    await waitForHomeContinueLaunchRestoreIfNeeded()
    guard !bootstrapSupersededByOffline else { return }

    // `scheduleHomeLaunchRestoreFromLocalStore()` in init — Home/Katalog sofort aus Cache.
    let hadCachedBootstrap = hasCachedBootstrapContent
    if !hadCachedBootstrap {
      isAppBootstrapInProgress = true
    }
    defer {
      if !bootstrapSupersededByOffline {
        isAppBootstrapInProgress = false
        flushTabVisibilityAfterBootstrap()
      }
      bootstrapSupersededByOffline = false
    }
    restoreServerClientIfNeeded()

    if hadCachedBootstrap {
      // LocalStore: Netzwerk parallel; Overlay bleibt bis Floating Bar bereit.
      deferredBootstrapNetworkTask?.cancel()
      deferredBootstrapNetworkTask = Task(priority: .utility) { @MainActor in
        await self.performDeferredBootstrapNetworkRefresh()
      }
      await finishLaunchPresentationAfterBootstrap()
      return
    }

    // Ohne Cache: Overlay bis Continue online (ggf. nach Authorize-Fallback).
    await performDeferredBootstrapNetworkRefresh()
    guard !bootstrapSupersededByOffline, !offlineHomeUIActive else { return }
    await finishLaunchPresentationAfterBootstrap()
  }

  /// Home-Refresh und Mini-Player nach Bootstrap — blockiert Kaltstart nur ohne Cache.
  private func finishLaunchPresentationAfterBootstrap() async {
    guard !bootstrapSupersededByOffline, !offlineHomeUIActive else { return }
    // Continue-Cache zuerst fertig anwenden — sonst force-Network bevor Shelves da sind.
    await waitForHomeContinueLaunchRestoreIfNeeded()
    guard !bootstrapSupersededByOffline, !offlineHomeUIActive else { return }
    let hadCachedHome = !startShelves.isEmpty
    async let home = loadStartDashboard(
      skipAuthorizeRefresh: true,
      force: !hadCachedHome
    )
    async let player: Void = restoreLastPlayedOnLaunch()
    _ = await (home, player)
    await waitForLaunchFloatingPlayerReady()
    floatingChrome.syncChrome()
    if hadCachedHome {
      // Server-Abgleich im Hintergrund — local-first: kein Continue-Replace, Continue reading bleibt.
      Task(priority: .utility) { @MainActor in
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard !self.offlineHomeUIActive, !self.bootstrapSupersededByOffline else { return }
        await self.loadStartDashboard(skipAuthorizeRefresh: true, force: true)
      }
    }
    scheduleDeferredWorkAfterConnect()
  }

  /// Katalog-Caches, Tab-Prewarm und Server-Reload — erst nach Connect, Home und Player.
  private func scheduleDeferredWorkAfterConnect() {
    guard !suppressDeferredWorkAfterBootstrap else { return }
    scheduleDeferredCatalogLocalRestoreAfterBootstrap()
    scheduleSecondaryTabPrewarm()
    scheduleDeferredCatalogReloadAfterBootstrap()
  }

  /// Laufende Bootstrap-/Katalog-Tasks abbrechen (Account-Wechsel, Logout, Offline während Bootstrap).
  func cancelDeferredBootstrapWork() {
    bootstrapCatalogReloadTask?.cancel()
    bootstrapCatalogReloadTask = nil
    deferredCatalogLocalRestoreTask?.cancel()
    deferredCatalogLocalRestoreTask = nil
    launchLocalRestoreTask?.cancel()
    launchLocalRestoreTask = nil
    homeLaunchLocalRestoreTask?.cancel()
    homeLaunchLocalRestoreTask = nil
    deferredBootstrapNetworkTask?.cancel()
    deferredBootstrapNetworkTask = nil
    deferredBootstrapAuthorizeTask?.cancel()
    deferredBootstrapAuthorizeTask = nil
    deferredLibrariesFetchTask?.cancel()
    deferredLibrariesFetchTask = nil
    storedCredentialsBootstrapTask?.cancel()
    storedCredentialsBootstrapTask = nil
    startDashboardPostProcessingTask?.cancel()
    startDashboardPostProcessingTask = nil
    booksToolbarSortReloadTask?.cancel()
    booksToolbarSortReloadTask = nil
    podcastCatalogSortReloadTask?.cancel()
    podcastCatalogSortReloadTask = nil
    searchTask?.cancel()
    searchTask = nil
    podcastSearchTask?.cancel()
    podcastSearchTask = nil
    podcastDirectorySearchTask?.cancel()
    podcastDirectorySearchTask = nil
    podcastLibrarySearchTask?.cancel()
    podcastLibrarySearchTask = nil
    libraryReloadSerial &+= 1
    startDashboardGeneration &+= 1
    authorizeApplyGeneration &+= 1
    deferredBooksCatalogLocalRestoreScheduled = false
    deferredBrowseListsLocalRestoreScheduled = false
    shouldPrewarmSecondaryTabs = false
  }

  /// Nach Account-Wechsel: LocalStore + Server-Kataloge für alle Tabs neu aufbauen.
  private func reloadAllViewsAfterAccountSwitch() async {
    guard !offlineHomeUIActive else { return }
    cancelDeferredBootstrapWork()
    await finishDeferredLaunchLocalRestore()
    async let settings: Bool = reloadSettingsTab(reloadCatalogs: true)
    async let home = loadStartDashboard(skipAuthorizeRefresh: true, force: true)
    _ = await (settings, home)
    scheduleSecondaryTabPrewarm()
  }

  /// Floating Bar: kurz stabilisieren bis Titel/Controls sichtbar (oder kein Resume).
  private func waitForLaunchFloatingPlayerReady() async {
    guard !bootstrapSupersededByOffline, !offlineHomeUIActive else { return }
    var stableReadyStreak = 0
    for _ in 0..<120 {
      if bootstrapSupersededByOffline || offlineHomeUIActive { return }
      floatingChrome.syncChrome()
      if isLaunchFloatingPlayerReadyForInteraction() {
        stableReadyStreak += 1
        if stableReadyStreak >= 3 {
          try? await Task.sleep(nanoseconds: 150_000_000)
          floatingChrome.syncChrome()
          return
        }
      } else {
        stableReadyStreak = 0
      }
      // Kein Resume — Restore abgeschlossen, Floating Bar entfällt.
      if !isRestoringLaunchPlayback, !isPreparingPlayback, player.activeBook == nil {
        return
      }
      try? await Task.sleep(nanoseconds: 50_000_000)
    }
  }

  private func isLaunchFloatingPlayerReadyForInteraction() -> Bool {
    guard !isRestoringLaunchPlayback, !isPreparingPlayback else { return false }
    guard player.activeBook != nil else { return true }
    guard player.isPlaybackControlsReady else { return false }
    let snap = TabAccessoryMiniPlayerSnapshot.make(model: self)
    guard snap.activeBookId != nil, snap.canTogglePlayback, !snap.showsConnectionLoading else { return false }
    let title = snap.primaryLine.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty, title != "Loading…" else { return false }
    return floatingChrome.gate.chromeVisible
  }

  /// Lazy-Bootstrap: Continue ohne `/authorize`; Authorize nur bei fehlgeschlagenem Continue-Refresh.
  /// URLSession mit `waitsForConnectivity = true` queued Requests automatisch — kein `NWPathMonitor`-Polling nötig.
  /// Nach erfolgreichem Continue: `/authorize` deferred nachladen für User-Type/Admin-Status.
  private func performDeferredBootstrapNetworkRefresh() async {
    let sp = AppLog.launchSignposter.beginInterval("refreshBootstrap")
    defer { AppLog.launchSignposter.endInterval("refreshBootstrap", sp) }
    isDeferredBootstrapNetworkRefreshInProgress = true
    defer { isDeferredBootstrapNetworkRefreshInProgress = false }

    if bootstrapSupersededByOffline || offlineHomeUIActive { return }

    guard ABSAPIClient.normalizeServerURL(serverURL) != nil, !token.isEmpty else { return }
    restoreServerClientIfNeeded()
    guard client != nil else { return }
    offlineHomeModeAuto = false

    let forceContinue = !hasCachedBootstrapContent
    var result = await loadStartDashboard(skipAuthorizeRefresh: true, force: forceContinue)
    if needsAuthorizeFallbackForContinue(result, attemptedOnline: result.attemptedNetwork) {
      await refreshProgressFromServer()
      guard !bootstrapSupersededByOffline, !offlineHomeUIActive else { return }
      result = await loadStartDashboard(skipAuthorizeRefresh: true, force: true)
      if !result.appliedOnline, let error = result.error, !hasCachedBootstrapContent {
        isRestoringLaunchPlayback = false
        player.setMiniPlayerPlaceholder(false)
        publishErrorUnlessBenignCancellation(error)
        if !isAuthHTTPStatus(error) {
          isServerReachable = false
          offlineHomeModeAuto = true
          mainTab = .start
          await prepareForOfflineHomeMode()
          await bootstrapLocalSessionOnly()
          await reloadLibraryViewsForModeTransition()
        }
        return
      }
    }

    guard !bootstrapSupersededByOffline, !offlineHomeUIActive else { return }

    if !result.attemptedNetwork {
      // Cache bereits vorhanden → `loadStartDashboard` hat früh zurückgegeben, ohne
      // tatsächlich einen Request zu starten. Erreichbarkeit darf dann nicht einfach
      // angenommen werden — echter Probe-Call statt Blindvertrauen.
      await probeServerConnection()
      guard isServerReachable else { return }
      // Bereits per `probeServerConnection()` autorisiert — kein zweiter `/authorize`-Call nötig,
      // aber Bibliotheksliste im Hintergrund trotzdem wie im Normalpfad nachziehen.
      scheduleDeferredLibrariesFetchFromServer()
      return
    }

    isServerReachable = true
    // `/authorize` deferred: User-Type (admin/root), Media-Progress, Bookmarks.
    // Nicht blockierend für Home — läuft parallel zum Libraries-Fetch.
    deferredBootstrapAuthorizeTask?.cancel()
    deferredBootstrapAuthorizeTask = Task(priority: .utility) { @MainActor [weak self] in
      guard let self, let c = self.client else { return }
      let epoch = self.accountSessionEpoch
      self.authorizeApplyGeneration &+= 1
      let authorizeGeneration = self.authorizeApplyGeneration
      do {
        let auth = try await c.authorize()
        guard !Task.isCancelled,
          !self.bootstrapSupersededByOffline,
          !self.offlineHomeUIActive,
          self.accountSessionEpoch == epoch,
          self.authorizeApplyGeneration == authorizeGeneration
        else { return }
        self.applyAuthorizeSession(auth)
      } catch {
        if !AbstandErrorFilter.isBenignCancellation(error) {
          AppLog.bootstrap.warning("Deferred authorize failed: \(error.localizedDescription, privacy: .public)")
        }
      }
    }
    scheduleDeferredLibrariesFetchFromServer()
  }

  func isAuthHTTPStatus(_ error: Error?) -> Bool {
    guard let error else { return false }
    guard case ABSAPIError.httpStatus(let code, _) = error else { return false }
    return code == 401 || code == 403
  }

  private func hasCachedContinueInLocalStore() -> Bool {
    guard let context = currentLocalLibraryMainContext() else { return false }
    var progressDescriptor = FetchDescriptor<LocalProgress>()
    progressDescriptor.fetchLimit = 1
    if !((try? context.fetch(progressDescriptor)) ?? []).isEmpty { return true }
    guard let libId = selectedBooksLibrary?.id.trimmingCharacters(in: .whitespacesAndNewlines),
      !libId.isEmpty
    else { return false }
    if let cached = LocalLibraryQueries.homeShelves(context: context, libraryId: libId) {
      return cached.contains { isHomeContinueCategory($0.category) && ($0.hasBooks || $0.hasPodcastEpisodes) }
    }
    return false
  }

  /// Gewählte Podcast-Bibliothek oder gespeicherter Stub (Kaltstart vor Katalog-Restore).
  func resolvedPodcastLibraryId() -> String? {
    if let id = selectedPodcastLibrary?.id.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
      return id
    }
    let stored =
      UserDefaults.standard.string(forKey: Keys.podcastsLibrary)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if stored.isEmpty || stored == Keys.librarySelectionNone { return nil }
    return stored
  }

  private func hasOpenProgressExpectingContinue() -> Bool {
    progressByItemId.values.contains {
      !$0.isFinished && $0.currentTime > Self.continueListeningMinPositionSeconds
    }
  }

  private func continueShelfHasVisibleItems() -> Bool {
    guard let idx = preferredHomeContinueShelfIndex() else { return false }
    let shelf = startShelves[idx]
    return !shelf.books.isEmpty || !shelf.podcastEpisodes.isEmpty
  }

  /// Entscheidet, ob nach fehlgeschlagenem Token-Continue ein `/authorize` nötig ist.
  private func needsAuthorizeFallbackForContinue(
    _ result: ContinueRefreshAttemptResult,
    attemptedOnline: Bool
  ) -> Bool {
    if isAuthHTTPStatus(result.error) { return true }
    guard attemptedOnline else { return false }
    if !result.appliedOnline {
      if hasCachedContinueInLocalStore() || hasCachedBootstrapContent { return false }
      return true
    }
    repairContinueListeningShelfFromLocalProgressOnly()
    syncContinueListeningShelvesWithProgress()
    if hasOpenProgressExpectingContinue(), !continueShelfHasVisibleItems() {
      return true
    }
    return false
  }

  /// Bibliotheksliste nach Lazy-Bootstrap — nicht blockierend für Home/Overlay.
  private func scheduleDeferredLibrariesFetchFromServer() {
    deferredLibrariesFetchTask?.cancel()
    deferredLibrariesFetchTask = Task(priority: .utility) { @MainActor [weak self] in
      await self?.refreshLibrariesFromServerInBackground()
    }
  }

  private func refreshLibrariesFromServerInBackground() async {
    guard !bootstrapSupersededByOffline, !offlineHomeUIActive else { return }
    guard mayUseServerNetwork, isNetworkReachable else { return }
    let epoch = accountSessionEpoch
    restoreServerClientIfNeeded()
    guard let c = client else { return }
    do {
      let list = try await c.libraries()
      guard !Task.isCancelled,
        !bootstrapSupersededByOffline,
        !offlineHomeUIActive,
        accountSessionEpoch == epoch
      else { return }
      applyLibrariesFromServer(list)
      let defaultLibId = UserDefaults.standard.string(forKey: Keys.userDefaultLibraryId)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      await resolveLibrariesAfterServerFetch(
        userDefaultLibraryId: (defaultLibId?.isEmpty == false) ? defaultLibId : nil
      )
    } catch {
      AppLog.bootstrap.warning(
        "Deferred libraries fetch failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  var hasCachedBootstrapContent: Bool {
    if !startShelves.isEmpty || !books.isEmpty || !podcastEpisodes.isEmpty { return true }
    return hasCachedLaunchArtifactsFlag()
  }

  func cachedLaunchArtifactsDefaultsKey() -> String {
    if let key = activeAccountKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
      return "\(Keys.hasCachedLaunchArtifacts).\(key)"
    }
    return Keys.hasCachedLaunchArtifacts
  }

  /// Persistiertes Kaltstart-Signal statt SwiftData-Fetch: `hasCachedBootstrapContent` steckt in der
  /// `.task(id:)`-Interpolation von `StartDashboardView` und wird im Bootstrap ausgewertet, bevor der
  /// LocalStore-Restore durch ist. Ein Fetch an dieser Stelle ist teuer und macht den Pfad timing-abhängig
  /// (mal `force: true` mit Overlay, mal local-first).
  private func hasCachedLaunchArtifactsFlag() -> Bool {
    guard cacheAccountURL() != nil else { return false }
    let key = cachedLaunchArtifactsDefaultsKey()
    if let stored = UserDefaults.standard.object(forKey: key) as? Bool { return stored }
    // Erster Start nach dem Update: einmalig aus dem LocalStore ableiten und merken.
    let available = hasCachedLaunchArtifactsInLocalStore()
    UserDefaults.standard.set(available, forKey: key)
    return available
  }

  /// Flag nachziehen — sowohl nach Persists als auch nach dem Restore, der den echten Zustand kennt.
  func setHasCachedLaunchArtifacts(_ available: Bool) {
    guard cacheAccountURL() != nil else { return }
    UserDefaults.standard.set(available, forKey: cachedLaunchArtifactsDefaultsKey())
  }

  /// LocalStore-Artefakte für schnellen Kaltstart (auch wenn Regale im Speicher noch leer sind).
  private func hasCachedLaunchArtifactsInLocalStore() -> Bool {
    guard cacheAccountURL() != nil else { return false }
    if hasCachedContinueInLocalStore() { return true }
    guard let context = currentLocalLibraryMainContext() else { return false }
    var descriptor = FetchDescriptor<LocalProgress>()
    descriptor.fetchLimit = 1
    return ((try? context.fetch(descriptor)) ?? []).isEmpty == false
  }

  /// Bootstrap direkt nach init — `.task` auf der Root-View kommt oft erst Sekunden später.
  func scheduleBootstrapFromStoredCredentials() {
    storedCredentialsBootstrapTask?.cancel()
    storedCredentialsBootstrapTask = Task(priority: .userInitiated) { @MainActor [weak self] in
      await self?.bootstrapFromStoredCredentials()
    }
  }

  /// Katalog-Caches aus LocalStore — gestaffelt nach Bootstrap, nicht beim Tab-Wechsel.
  func scheduleDeferredCatalogLocalRestoreAfterBootstrap() {
    guard !deferredBooksCatalogLocalRestoreScheduled else { return }
    deferredBooksCatalogLocalRestoreScheduled = true
    deferredCatalogLocalRestoreTask?.cancel()
    deferredCatalogLocalRestoreTask = Task(priority: .utility) { @MainActor [weak self] in
      // Ein Yield statt fixem Sleep — Home-Frame hat Vorrang, LocalStore-Restore folgt sofort danach.
      await Task.yield()
      try? await Task.sleep(nanoseconds: 500_000_000)
      await Task.yield()
      guard let self, !Task.isCancelled, !self.offlineHomeUIActive, !self.bootstrapSupersededByOffline else { return }
      if self.books.isEmpty {
        await self.restoreBooksCatalogPagesFromLocalStoreAsync()
      }
      await Task.yield()
      guard !Task.isCancelled else { return }
      if !self.deferredBrowseListsLocalRestoreScheduled {
        self.deferredBrowseListsLocalRestoreScheduled = true
        self.restoreAllBrowseListsFromLocalStore()
      }
      await Task.yield()
      guard !Task.isCancelled else { return }
      if self.podcastEpisodes.isEmpty, self.podcastShows.isEmpty {
        self.restorePodcastCatalogFromLocalStore()
      }
      await Task.yield()
      guard !Task.isCancelled else { return }
      guard let account = self.cacheAccountURL() else { return }
      // Ganz am Ende der Idle-Kette, außerhalb des MainActor-Takts: alte/verwaiste Cover
      // (nach Revision-Wechsel) begrenzen, ohne den Start zu belasten.
      Task.detached(priority: .background) {
        CoverImageCache.pruneStaleEntries(account: account)
      }
    }
  }

  /// Tab-Views nach kurzer Idle-Phase vorbauen — Wechsel ohne Erst-Mount-Ruckler.
  private func scheduleSecondaryTabPrewarm() {
    Task { @MainActor [weak self] in
      await Task.yield()
      try? await Task.sleep(nanoseconds: 500_000_000)
      self?.shouldPrewarmSecondaryTabs = true
    }
  }

  /// Bibliotheks-Kataloge nach Bootstrap — niedrige Priorität, Home bleibt bedienbar.
  private func scheduleDeferredCatalogReloadAfterBootstrap() {
    bootstrapCatalogReloadTask?.cancel()
    bootstrapCatalogReloadTask = Task(priority: .utility) { @MainActor [weak self] in
      // Statt eines geschätzten Fix-Delays: auf den LocalStore-Restore warten (der eigentliche
      // Vorlauf, den wir abpuffern wollen) und danach nur noch eine kurze Sicherheitsspanne.
      await self?.deferredCatalogLocalRestoreTask?.value
      try? await Task.sleep(nanoseconds: 1_500_000_000)
      await Task.yield()
      guard let self, !Task.isCancelled, !self.offlineHomeUIActive, !self.bootstrapSupersededByOffline else { return }
      // Bücher- und Podcast-Katalog sind unabhängig — parallel laden.
      // `preserveOtherCachedPages`: stiller Hintergrund-Refresh mit unverändertem Sort/Filter —
      // Folgeseiten im LocalStore nicht wegen der frischen Seite 0 wegwerfen.
      async let books: Void = self.reloadLibrary(reset: true, preserveOtherCachedPages: true)
      async let podcasts: Void = self.reloadPodcastLibrary(reset: true)
      _ = await (books, podcasts)
    }
  }

  /// App-Start / Auto-Offline: nur LocalStore und Downloads, kein Netzwerk.
  private func bootstrapLocalSessionOnly() async {
    ensureLocalProgressLoaded()
    await loadStartDashboard()
    // Offline-Kaltstart: Resume aus dem letzten lokalen Fortschritt — ohne diesen Aufruf bleibt der
    // Floating Player leer, obwohl der Titel heruntergeladen ist (`restoreLastPlayedOnLaunch` hängt
    // sonst allein am Online-Pfad `finishLaunchPresentationAfterBootstrap`).
    await restoreLastPlayedOnLaunch()
    isRestoringLaunchPlayback = false
    player.setMiniPlayerPlaceholder(false)
    floatingChrome.syncChrome()
  }

  /// Vor Offline-Modus: aktuelle Position lokal + Play-Session an den Server, dann Netzwerk trennen.
  func prepareForOfflineHomeMode() async {
    recordActivePlaybackProgressLocally(markPendingServerSync: true)
    // Synchron persistieren — sonst kann ein schneller App-Kill den async Write verlieren.
    await persistProgressToLocalStoreNow()

    // Offline-UI ist hier bereits aktiv → `mayUseServerNetwork` ist false. Client/apiClient
    // leben noch bis zum Suspend am Ende — letzte Session/PATCH trotzdem absetzen.
    if isNetworkReachable, client != nil {
      await player.flushPendingPlaySessionSync()
      guard offlineHomeUIActive else { return }
      if player.isRemotePlaySessionActive, let c = client, let book = player.activeBook {
        let dur = player.totalDuration
        if dur > 0 {
          let pos = player.globalPosition
          let prog = min(1, max(0, pos / dur))
          try? await c.patchProgress(
            libraryItemId: book.id,
            episodeId: player.activePlaybackEpisodeId,
            patch: ABSProgressPatch(
              currentTime: pos, duration: dur, progress: prog, isFinished: nil
            )
          )
          if let key = activePlaybackProgressLookupKey() {
            pendingLocalProgressSyncKeys.remove(key)
          }
        }
      }
    }

    // Was die Session nicht mehr absetzen konnte (kein Netz / Fehler) → Offline-Hörzeit parken,
    // bevor tearDown/suspend `pendingListenSeconds` verwerfen.
    let leftover = player.consumePendingListenSeconds()
    if leftover > 0, let key = activePlaybackProgressLookupKey() {
      addPendingOfflineListeningSeconds(progressKey: key, seconds: leftover)
    }

    guard offlineHomeUIActive else { return }
    await adaptActivePlaybackForOfflineHomeMode()
    guard offlineHomeUIActive else { return }
    isServerReachable = false
    player.suspendServerNetworkingForOfflineMode()
    client = nil
  }

  /// Stream-Wiedergabe ohne Download beenden; bei lokalem Download auf Dateien umschalten.
  private func adaptActivePlaybackForOfflineHomeMode() async {
    guard player.activeBook != nil else { return }
    if player.isUsingLocalTrackFiles { return }

    let position = player.globalPosition
    let wasPlaying = player.isPlaying
    // Position nochmals lokal — tearDown setzt globalPosition auf 0.
    recordActivePlaybackProgressLocally(markPendingServerSync: true)

    if let episode = podcastEpisodeForActivePlayback() {
      let storageKey = podcastEpisodeOfflineStorageId(episode)
      if localDownloadRoot(for: storageKey) != nil {
        player.tearDownPlayer()
        await playPodcastEpisode(episode, autoPlay: wasPlaying, resumeAtOverride: position)
        floatingChrome.syncChrome()
        return
      }
    } else if let book = player.activeBook, resolvedLocalDownloadForPlayback(book: book) != nil {
      player.tearDownPlayer()
      await play(book: book, resumeAtOverride: position, autoPlay: wasPlaying)
      floatingChrome.syncChrome()
      return
    }

    await dismissPlayer(idlePlaceholder: false)
    floatingChrome.syncChrome()
  }

  func restoreServerClientIfNeeded() {
    guard client == nil,
      let url = ABSAPIClient.normalizeServerURL(serverURL),
      !token.isEmpty
    else { return }
    client = ABSAPIClient(baseURL: url, token: token)
  }

  /// Client nur für lokale Wiedergabe (kein Authorize); entsteht nach `suspendServerClientForOfflineHome`.
  func clientForOfflineLocalPlayback() -> ABSAPIClient? {
    if let c = client { return c }
    guard let url = ABSAPIClient.normalizeServerURL(serverURL), !token.isEmpty else { return nil }
    return ABSAPIClient(baseURL: url, token: token)
  }

  func login(server: String, username: String, password: String) async {
    errorMessage = nil
    guard let url = ABSAPIClient.normalizeServerURL(server) else {
      errorMessage = "Please enter a valid server URL."
      return
    }
    if isLoggedIn {
      syncStoredAccountFromSession()
    }
    defer { refreshDownloadedShelfFromManifests() }
    bootstrapSupersededByOffline = false
    isAppBootstrapInProgress = true
    defer {
      if !bootstrapSupersededByOffline {
        isAppBootstrapInProgress = false
        flushTabVisibilityAfterBootstrap()
      }
      bootstrapSupersededByOffline = false
    }
    offlineHomeModeAuto = false
    var serverSessionEstablished = false
    do {
      let res = try await ABSAPIClient.login(server: url, username: username, password: password)
      if bootstrapSupersededByOffline || offlineHomeUIActive { return }
      token = res.user.token
      serverURL = server.trimmingCharacters(in: .whitespacesAndNewlines)
      UserDefaults.standard.set(serverURL, forKey: Keys.server)
      UserDefaults.standard.set(token, forKey: Keys.token)
      let c = ABSAPIClient(baseURL: url, token: token)
      client = c
      serverSessionEstablished = true
      applyAuthorizeSession(res)
      syncStoredAccountFromSession()
      loadDownloadedItemIdsForActiveAccount()
      isServerReachable = true
      applyLibrariesFromServer(try await c.libraries())
      if bootstrapSupersededByOffline || offlineHomeUIActive { return }
      await resolveLibrariesAfterServerFetch(userDefaultLibraryId: res.userDefaultLibraryId)
      if bootstrapSupersededByOffline || offlineHomeUIActive { return }
      mainTab = .start
      await finishLaunchPresentationAfterBootstrap()
    } catch {
      if bootstrapSupersededByOffline || offlineHomeUIActive { return }
      isRestoringLaunchPlayback = false
      player.setMiniPlayerPlaceholder(false)
      publishErrorUnlessBenignCancellation(error)
      if serverSessionEstablished {
        isServerReachable = true
        mainTab = .start
        await finishLaunchPresentationAfterBootstrap()
        return
      }
      isServerReachable = false
    }
  }

  /// Entfernt den aktiven Account und wechselt zum nächsten gespeicherten — oder zeigt Login.
  func logout() {
    guard let key = activeAccountKey ?? resolvedStoredAccountKey() else {
      clearInMemorySessionState(clearCredentials: true)
      return
    }
    removeStoredAccount(accountKey: key)
  }

  /// Account aus der Liste entfernen; bei aktivem Account wie `logout()` zum nächsten wechseln.
  func removeStoredAccount(accountKey: String) {
    let key = accountKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else { return }
    let removingActive = key == activeAccountKey
    if removingActive { syncStoredAccountFromSession() }
    storedAccounts.removeAll { $0.accountKey == key }
    persistStoredAccounts()
    guard removingActive else { return }
    if let next = storedAccounts.first {
      Task { await switchToAccount(next.accountKey) }
      return
    }
    activeAccountKey = nil
    ABSStoredAccountsPersistence.saveActiveAccountKey(nil)
    clearInMemorySessionState(clearCredentials: true)
  }

  func isActiveStoredAccount(_ account: ABSStoredAccount) -> Bool {
    account.accountKey == activeAccountKey
  }

  func switchToAccount(_ accountKey: String) async {
    guard !isSwitchingAccount else { return }
    guard accountKey != activeAccountKey,
      let account = storedAccounts.first(where: { $0.accountKey == accountKey })
    else { return }
    isSwitchingAccount = true
    defer { isSwitchingAccount = false }
    syncStoredAccountFromSession()
    persistDownloads(skipRefresh: true)
    CoverImageCache.evictMemory()
    coverImageCacheRevision &+= 1
    clearInMemorySessionState(clearCredentials: false)
    serverURL = account.serverURL
    token = account.token
    UserDefaults.standard.set(serverURL, forKey: Keys.server)
    UserDefaults.standard.set(token, forKey: Keys.token)
    activeAccountKey = accountKey
    ABSStoredAccountsPersistence.saveActiveAccountKey(accountKey)
    // Vor Authorize: UserId setzen, damit LocalStore und Home sofort zum richtigen Account zeigen.
    let switchedUserId = account.userId.trimmingCharacters(in: .whitespacesAndNewlines)
    if !switchedUserId.isEmpty {
      sessionUserId = switchedUserId
      UserDefaults.standard.set(switchedUserId, forKey: Keys.sessionUserId)
    }
    sessionUsername = account.username
    sessionUserType = account.userType ?? "user"
    applyLibraryPreferencesFromStoredAccount(account)
    loadDownloadedItemIdsForActiveAccount()
    // Discard-/Finished-Keys des neuen Accounts laden, bevor Home-Restore Progress merged.
    loadLocalFinishedProgressKeys()
    loadDiscardedProgressKeys()
    if let cacheRoot = cacheAccountURL() {
      EbookLocalStore.updateActiveSession(account: cacheRoot, userId: switchedUserId.isEmpty ? nil : switchedUserId)
      PlayerTranscriptCacheStore.updateActiveAccount(cacheRoot)
    }
    restoreHomeLaunchStateFromLocalStore(libraryIdOverride: account.booksLibraryId)
    isAppBootstrapInProgress = true
    storedCredentialsBootstrapTask?.cancel()
    storedCredentialsBootstrapTask = nil
    suppressDeferredWorkAfterBootstrap = true
    defer { suppressDeferredWorkAfterBootstrap = false }
    await bootstrapFromStoredCredentials()
    accountSessionEpoch &+= 1
    await reloadAllViewsAfterAccountSwitch()
  }

  static func bootstrapStoredAccountsState() -> (accounts: [ABSStoredAccount], activeKey: String?) {
    var accounts = ABSStoredAccountsPersistence.loadAccounts()
    if accounts.isEmpty {
      accounts = migrateLegacySingleAccountIntoStore()
    }
    var activeKey = ABSStoredAccountsPersistence.loadActiveAccountKey()
    if activeKey == nil, let first = accounts.first {
      activeKey = first.accountKey
      ABSStoredAccountsPersistence.saveActiveAccountKey(activeKey)
    }
    if let currentKey = activeKey, !accounts.contains(where: { $0.accountKey == currentKey }),
      let fallback = accounts.first
    {
      activeKey = fallback.accountKey
      ABSStoredAccountsPersistence.saveActiveAccountKey(activeKey)
    }
    return (accounts, activeKey)
  }

  private static func migrateLegacySingleAccountIntoStore() -> [ABSStoredAccount] {
    let server = UserDefaults.standard.string(forKey: Keys.server)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let token = UserDefaults.standard.string(forKey: Keys.token)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let userId = UserDefaults.standard.string(forKey: Keys.sessionUserId)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard ABSAPIClient.normalizeServerURL(server) != nil, !token.isEmpty, !userId.isEmpty else { return [] }
    let account = ABSStoredAccount(
      accountKey: ABSStoredAccount.makeKey(serverURL: server, userId: userId),
      serverURL: server,
      token: token,
      userId: userId,
      username: "",
      userType: nil,
      booksLibraryId: UserDefaults.standard.string(forKey: Keys.booksLibrary),
      podcastsLibraryId: UserDefaults.standard.string(forKey: Keys.podcastsLibrary),
      ebooksLibraryId: UserDefaults.standard.string(forKey: Keys.booksLibrary),
      lastUsedAt: Date()
    )
    ABSStoredAccountsPersistence.saveAccounts([account])
    ABSStoredAccountsPersistence.saveActiveAccountKey(account.accountKey)
    return [account]
  }

  func syncStoredAccountFromSession() {
    syncStoredAccountFromSession(markActive: true)
  }

  func syncStoredAccountFromSession(markActive: Bool) {
    guard ABSAPIClient.normalizeServerURL(serverURL) != nil, !token.isEmpty else { return }
    let userId = sessionUserId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !userId.isEmpty else { return }
    let key = ABSStoredAccount.makeKey(serverURL: serverURL, userId: userId)
    let booksLib = UserDefaults.standard.string(forKey: Keys.booksLibrary)
    let podcastsLib = UserDefaults.standard.string(forKey: Keys.podcastsLibrary)
    let activeBooks = activeBooksLibraryIds
    let activePods = activePodcastLibraryIds
    if let idx = storedAccounts.firstIndex(where: { $0.accountKey == key }) {
      storedAccounts[idx].token = token
      storedAccounts[idx].serverURL = serverURL
      storedAccounts[idx].userId = userId
      storedAccounts[idx].username = sessionUsername
      storedAccounts[idx].userType = sessionUserType.isEmpty ? nil : sessionUserType
      storedAccounts[idx].booksLibraryId = booksLib
      storedAccounts[idx].podcastsLibraryId = podcastsLib
      storedAccounts[idx].ebooksLibraryId = booksLib
      storedAccounts[idx].activeBooksLibraryIds = activeBooks
      storedAccounts[idx].activePodcastLibraryIds = activePods
    } else if let legacyIdx = activeAccountKey.flatMap({ key in storedAccounts.firstIndex(where: { $0.accountKey == key }) }),
      storedAccounts[legacyIdx].userId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      // Migration: userId war beim ersten Speichern noch leer — Eintrag umbenennen.
      storedAccounts[legacyIdx].accountKey = key
      storedAccounts[legacyIdx].token = token
      storedAccounts[legacyIdx].serverURL = serverURL
      storedAccounts[legacyIdx].userId = userId
      storedAccounts[legacyIdx].username = sessionUsername
      storedAccounts[legacyIdx].userType = sessionUserType.isEmpty ? nil : sessionUserType
      storedAccounts[legacyIdx].booksLibraryId = booksLib
      storedAccounts[legacyIdx].podcastsLibraryId = podcastsLib
      storedAccounts[legacyIdx].ebooksLibraryId = booksLib
      storedAccounts[legacyIdx].activeBooksLibraryIds = activeBooks
      storedAccounts[legacyIdx].activePodcastLibraryIds = activePods
    } else {
      storedAccounts.append(
        ABSStoredAccount(
          accountKey: key,
          serverURL: serverURL,
          token: token,
          userId: userId,
          username: sessionUsername,
          userType: sessionUserType.isEmpty ? nil : sessionUserType,
          booksLibraryId: booksLib,
          podcastsLibraryId: podcastsLib,
          ebooksLibraryId: booksLib,
          activeBooksLibraryIds: activeBooks,
          activePodcastLibraryIds: activePods,
          lastUsedAt: Date()
        ))
    }
    if markActive {
      activeAccountKey = key
      ABSStoredAccountsPersistence.saveActiveAccountKey(key)
    }
    persistStoredAccounts()
  }

  /// Neuen Account speichern, ohne die aktuelle Session zu wechseln.
  func addStoredAccount(server: String, username: String, password: String) async -> Bool {
    errorMessage = nil
    guard let url = ABSAPIClient.normalizeServerURL(server) else {
      errorMessage = "Please enter a valid server URL."
      return false
    }
    syncStoredAccountFromSession()
    let preserveActiveKey = activeAccountKey
    do {
      let res = try await ABSAPIClient.login(server: url, username: username, password: password)
      upsertStoredAccountFromUser(
        res.user,
        serverURL: server.trimmingCharacters(in: .whitespacesAndNewlines),
        markActive: false
      )
      activeAccountKey = preserveActiveKey
      ABSStoredAccountsPersistence.saveActiveAccountKey(preserveActiveKey)
      persistStoredAccounts()
      return true
    } catch {
      publishErrorUnlessBenignCancellation(error)
      return false
    }
  }

}
