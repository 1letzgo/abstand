import Foundation

extension AppModel {
  enum Keys {
  static let server = "abstand_server_url"
  static let token = "abstand_token"
  /// Letzter `authorize`-User — für Readium/eBook-Fortschritt vor erneutem `/authorize`.
  static let sessionUserId = "abstand_session_user_id"
  /// Server-Standardbibliothek aus letztem `/authorize` (Lazy-Bootstrap ohne erneutes Authorize).
  static let userDefaultLibraryId = "abstand_user_default_library_id"
  /// Legacy; wird nach `booksLibrary` migriert.
  static let library = "abstand_library_id"
  static let booksLibrary = "abstand_books_library_id"
  static let ebooksLibrary = "abstand_ebooks_library_id"
  static let podcastsLibrary = "abstand_podcasts_library_id"
  /// Bewusst keine Bibliothek gewählt (Tabs ausblenden, kein Auto-Pick).
  static let librarySelectionNone = "__abstand_no_library__"
  /// Zusätzlich zur Primary aktivierte Books-Libraries (JSON `[String]`), account-gebunden.
  static let activeBooksLibraryIds = "abstand_active_books_library_ids"
  /// Zusätzlich zur Primary aktivierte Podcast-Libraries (JSON `[String]`), account-gebunden.
  static let activePodcastLibraryIds = "abstand_active_podcast_library_ids"
  static let downloads = "abstand_downloaded_ids"
  static let lastPlayedItemId = "abstand_last_played_library_item_id"
  static let startDisabledCategories = "abstand_start_disabled_categories"
  /// Nutzer-Reihenfolge der Home-Regale (JSON `[String]`); Continue listening bleibt immer zuerst.
  static let startCategoryOrder = "abstand_start_category_order"
  static let homeBrowseCategory = "abstand_home_browse_category"
  static let catalogSortField = "abstand_catalog_sort_field"
  static let catalogSortDescending = "abstand_catalog_sort_descending"
  /// Sortierung nur Podcast-Bibliothek (Shows-Leiste + Fallback `libraryItems` für Folgen).
  static let podcastCatalogSortField = "abstand_podcast_catalog_sort_field"
  static let podcastCatalogSortDescending = "abstand_podcast_catalog_sort_descending"
  /// Früher: kombinierter `CatalogItemsSort`-RawValue (Migration einmalig).
  static let legacyCatalogItemsSort = "abstand_catalog_items_sort"
  static let smartDlAutoWifi = "abstand_smart_dl_auto_wifi"
  static let smartDlRemoveWhenFinished = "abstand_smart_dl_remove_when_finished"
  /// Nur Home mit „Heruntergeladen“; andere Tabs ausgeblendet.
  static let offlineHomeMode = "abstand_offline_home_mode"
  /// Vollplayer-Sheet beim Start der Wiedergabe (nicht im Offline-Home).
  static let openPlayerWhenStartPlaying = "abstand_open_player_when_start_playing"
  /// Kumulierte Hörsekunden ohne Play-Session (lokale Downloads), später per Session-Flush (Absorb).
  static let pendingOfflineListeningSeconds = "abstand_pending_offline_listening_seconds"
  /// Fortschrittsschlüssel, die offline/lokal als fertig markiert wurden (bis Server bestätigt).
  static let localFinishedProgressKeys = "abstand_local_finished_progress_keys"
  /// Reset Progress: Keys, die lokal verworfen wurden und nicht aus Cache/`authorize` zurückkehren dürfen.
  static let discardedProgressKeys = "abstand_discarded_progress_keys"
  static let browseAuthorsSortField = "abstand_browse_authors_sort_field"
  static let browseAuthorsSortDescending = "abstand_browse_authors_sort_desc"
  static let browseNarratorsSortField = "abstand_browse_narrators_sort_field"
  static let browseNarratorsSortDescending = "abstand_browse_narrators_sort_desc"
  static let browseSeriesSortField = "abstand_browse_series_sort_field"
  static let browseSeriesSortDescending = "abstand_browse_series_sort_desc"
  static let browseCollectionsSortField = "abstand_browse_collections_sort_field"
  static let browseCollectionsSortDescending = "abstand_browse_collections_sort_desc"
  static let browseGenresSortField = "abstand_browse_genres_sort_field"
  static let browseGenresSortDescending = "abstand_browse_genres_sort_desc"
  static let browseTagsSortField = "abstand_browse_tags_sort_field"
  static let browseTagsSortDescending = "abstand_browse_tags_sort_desc"
  /// Podcast-Tab in der Tab-Leiste (gecacht; unabhängig vom Bootstrap-Fetch).
  static let showPodcastsTab = "abstand_show_podcasts_tab"
  /// Audiobooks-Tab in der Tab-Leiste (gecacht; unabhängig vom Bootstrap-Fetch).
  static let showAudiobooksTab = "abstand_show_audiobooks_tab"
  /// Akzentfarbe als „r,g,b“ (0…1) in sRGB.
  static let appearanceAccentRGB = "abstand_appearance_accent_rgb"
  static let appearanceAccentRGBDark = "abstand_appearance_accent_rgb_dark"
  static let appearanceAccentRGBLight = "abstand_appearance_accent_rgb_light"
  static let appearanceMode = "abstand_appearance_mode"
  static let libraryBookCardStyle = "abstand_library_book_card_style"
  static let libraryPodcastCardStyle = "abstand_library_podcast_card_style"
  static let translationTargetLanguageCode = "abstand_translation_target_language"
}
}
