package de.letzgo.abstand.data

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/**
 * iOS: `UserDefaults.standard`. Gleiche Key-Strings wie iOS ([Keys] = `AppModel.Keys`), damit
 * Einstellungslogik 1:1 portiert werden kann. Token und Server-URL liegen wie auf iOS bewusst
 * hier und nicht in [Secrets] (Projektentscheidung).
 */
object Prefs {
    lateinit var prefs: SharedPreferences
        private set
    lateinit var appContext: Context
        private set

    fun init(context: Context) {
        appContext = context.applicationContext
        prefs = context.getSharedPreferences("abstand", Context.MODE_PRIVATE)
        Secrets.init(context)
    }

    fun string(key: String): String? = prefs.getString(key, null)
    fun setString(key: String, value: String?) = prefs.edit().apply { if (value == null) remove(key) else putString(key, value) }.apply()
    /** Synchron (`commit`) für Daten, die einen sofortigen Prozess-Kill überleben müssen. */
    fun commitString(key: String, value: String?) =
        prefs.edit().apply { if (value == null) remove(key) else putString(key, value) }.commit()
    fun bool(key: String, default: Boolean = false) = prefs.getBoolean(key, default)
    fun setBool(key: String, value: Boolean) = prefs.edit().putBoolean(key, value).apply()
    fun int(key: String, default: Int = 0) = prefs.getInt(key, default)
    fun setInt(key: String, value: Int) = prefs.edit().putInt(key, value).apply()
    fun long(key: String, default: Long = 0) = prefs.getLong(key, default)
    fun setLong(key: String, value: Long) = prefs.edit().putLong(key, value).apply()
    fun double(key: String, default: Double = 0.0): Double =
        if (prefs.contains(key)) java.lang.Double.longBitsToDouble(prefs.getLong(key, 0)) else default
    fun setDouble(key: String, value: Double) = prefs.edit().putLong(key, java.lang.Double.doubleToRawLongBits(value)).apply()
    fun has(key: String) = prefs.contains(key)
    fun remove(key: String) = prefs.edit().remove(key).apply()
}

/** iOS: `AppModel.Keys` — identische Strings. */
object Keys {
    const val server = "abstand_server_url"
    const val token = "abstand_token"
    /** Rotierendes Refresh-Token (JWT-Auth ab Server v2.26); leer bei Legacy-Sessions. */
    const val refreshToken = "abstand_refresh_token"
    const val sessionUserId = "abstand_session_user_id"
    const val userDefaultLibraryId = "abstand_user_default_library_id"
    /** Legacy; wird nach [booksLibrary] migriert. */
    const val library = "abstand_library_id"
    const val booksLibrary = "abstand_books_library_id"
    const val ebooksLibrary = "abstand_ebooks_library_id"
    const val podcastsLibrary = "abstand_podcasts_library_id"
    /** Bewusst keine Bibliothek gewählt (Tabs ausblenden, kein Auto-Pick). */
    const val librarySelectionNone = "__abstand_no_library__"
    const val activeBooksLibraryIds = "abstand_active_books_library_ids"
    const val activePodcastLibraryIds = "abstand_active_podcast_library_ids"
    const val downloads = "abstand_downloaded_ids"
    const val lastPlayedItemId = "abstand_last_played_library_item_id"
    const val startDisabledCategories = "abstand_start_disabled_categories"
    const val startCategoryOrder = "abstand_start_category_order"
    const val homeBrowseCategory = "abstand_home_browse_category"
    const val hasCachedLaunchArtifacts = "abstand_has_cached_launch_artifacts"
    const val ebookBrowseOrderPrefix = "abstand_ebook_browse_order_"
    const val catalogSortField = "abstand_catalog_sort_field"
    const val catalogSortDescending = "abstand_catalog_sort_descending"
    const val podcastCatalogSortField = "abstand_podcast_catalog_sort_field"
    const val podcastCatalogSortDescending = "abstand_podcast_catalog_sort_descending"
    const val podcastEpisodeSortField = "abstand_podcast_episode_sort_field"
    const val podcastEpisodeSortDescending = "abstand_podcast_episode_sort_descending"
    const val legacyCatalogItemsSort = "abstand_catalog_items_sort"
    const val smartDlAutoWifi = "abstand_smart_dl_auto_wifi"
    const val readAlongPrefetch = "abstand_read_along_prefetch"
    const val smartDlRemoveWhenFinished = "abstand_smart_dl_remove_when_finished"
    const val offlineHomeMode = "abstand_offline_home_mode"
    const val openPlayerWhenStartPlaying = "abstand_open_player_when_start_playing"
    const val pendingOfflineListeningSeconds = "abstand_pending_offline_listening_seconds"
    const val localFinishedProgressKeys = "abstand_local_finished_progress_keys"
    const val discardedProgressKeys = "abstand_discarded_progress_keys"
    const val pendingLocalProgressSyncKeys = "abstand_pending_local_progress_sync_keys"
    const val browseAuthorsSortField = "abstand_browse_authors_sort_field"
    const val browseAuthorsSortDescending = "abstand_browse_authors_sort_desc"
    const val browseNarratorsSortField = "abstand_browse_narrators_sort_field"
    const val browseNarratorsSortDescending = "abstand_browse_narrators_sort_desc"
    const val browseSeriesSortField = "abstand_browse_series_sort_field"
    const val browseSeriesSortDescending = "abstand_browse_series_sort_desc"
    const val browseCollectionsSortField = "abstand_browse_collections_sort_field"
    const val browseCollectionsSortDescending = "abstand_browse_collections_sort_desc"
    const val browseGenresSortField = "abstand_browse_genres_sort_field"
    const val browseGenresSortDescending = "abstand_browse_genres_sort_desc"
    const val browseTagsSortField = "abstand_browse_tags_sort_field"
    const val browseTagsSortDescending = "abstand_browse_tags_sort_desc"
    const val showPodcastsTab = "abstand_show_podcasts_tab"
    const val showAudiobooksTab = "abstand_show_audiobooks_tab"
    /** Akzentfarbe als „r,g,b“ (0…1) in sRGB. */
    const val appearanceAccentRGB = "abstand_appearance_accent_rgb"
    const val appearanceAccentRGBDark = "abstand_appearance_accent_rgb_dark"
    const val appearanceAccentRGBLight = "abstand_appearance_accent_rgb_light"
    const val appearanceMode = "abstand_appearance_mode"
    /** Android-only (kein iOS-Gegenstück): Dynamic Color an/aus. */
    const val appearanceDynamicColor = "abstand_appearance_dynamic_color"
    const val libraryBookCardStyle = "abstand_library_book_card_style"
    const val libraryPodcastCardStyle = "abstand_library_podcast_card_style"
    const val translationTargetLanguageCode = "abstand_translation_target_language"

    // iOS: `ABSStoredAccountsPersistence`
    const val storedAccounts = "abstand_stored_accounts"
    const val activeAccountKey = "abstand_active_account_key"
}

/** iOS: Keychain — Werte mit Keystore-Masterkey verschlüsselt (Custom-Header je Server). */
object Secrets {
    private lateinit var prefs: SharedPreferences

    fun init(context: Context) {
        prefs = try {
            val key = MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build()
            EncryptedSharedPreferences.create(
                context, "abstand_secure", key,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
            )
        } catch (e: Exception) {
            // Keystore defekt (selten, z. B. nach Restore): private Prefs als Fallback.
            context.getSharedPreferences("abstand_secure_fallback", Context.MODE_PRIVATE)
        }
    }

    fun get(key: String): String? = prefs.getString(key, null)
    fun set(key: String, value: String?) { prefs.edit().apply { if (value.isNullOrEmpty()) remove(key) else putString(key, value) }.commit() }
}
