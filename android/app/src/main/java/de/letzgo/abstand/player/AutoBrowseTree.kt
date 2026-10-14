package de.letzgo.abstand.player

import de.letzgo.abstand.data.AbsStartShelfMergedRow
import de.letzgo.abstand.data.AbsUserMediaProgress

/**
 * iOS: Template-Aufbau in `CarPlayCoordinator` (Tabs „Continue“ und „Downloads“, Meldungszeilen,
 * Fahrzeuggrenzen). Reine Logik (IDs, Texte, Fortschritt) — die Media3-Items baut
 * [AbstandPlaybackService].
 */
object AutoBrowseTree {
    const val ROOT_ID = "abstand_root"
    const val CONTINUE_ID = "abstand_continue"
    const val DOWNLOADS_ID = "abstand_downloads"
    /** Zusätzlich zu CarPlay, nur wenn [BrowseSource.libraryBookRows] Zeilen liefert. */
    const val BOOKS_ID = "abstand_books"
    /** Zusätzlich zu CarPlay, nur wenn [BrowseSource.podcastEpisodeRows] Zeilen liefert. */
    const val PODCASTS_ID = "abstand_podcasts"
    private const val MESSAGE_PREFIX = "abstand_message|"

    /** iOS: `defaultMaximumItemCount` — Fahrzeuge lehnen zu lange Listen ab. */
    const val MAX_ITEMS = 48

    const val CONTINUE_TAB_TITLE = "Continue"
    const val DOWNLOADS_TAB_TITLE = "Downloads"
    const val BOOKS_TAB_TITLE = "Books"
    const val PODCASTS_TAB_TITLE = "Podcasts"
    const val CONTINUE_SECTION_TITLE = "Continue listening"
    const val DOWNLOADS_SECTION_TITLE = "Downloaded"

    const val MESSAGE_SIGN_IN = "Sign in on your phone to use abstand in the car."
    const val MESSAGE_NOTHING_IN_PROGRESS = "Nothing in progress. Start listening on your phone."
    const val MESSAGE_NO_DOWNLOADS = "No downloads yet. Download on your phone to listen offline."
    const val MESSAGE_EMPTY = "Nothing here yet."

    /** Abspielbare Referenz hinter einer Media-ID. */
    sealed class MediaRef {
        data class Book(val libraryItemId: String) : MediaRef()
        data class Episode(val libraryItemId: String, val episodeId: String) : MediaRef()
    }

    /** Stabile Media-ID (Trennzeichen `|`, weil IDs `-` enthalten). Gleiches Schema wie [BookTimelinePlayer]. */
    fun mediaId(row: AbsStartShelfMergedRow): String = when (row) {
        is AbsStartShelfMergedRow.Book -> "book|${row.book.id}"
        is AbsStartShelfMergedRow.PodcastEpisode -> "episode|${row.episode.libraryItemId}|${row.episode.episodeId}"
    }

    fun parse(mediaId: String): MediaRef? {
        val parts = mediaId.split("|")
        return when {
            parts.size == 2 && parts[0] == "book" && parts[1].isNotEmpty() -> MediaRef.Book(parts[1])
            parts.size == 3 && parts[0] == "episode" && parts[1].isNotEmpty() && parts[2].isNotEmpty() ->
                MediaRef.Episode(parts[1], parts[2])
            else -> null
        }
    }

    fun messageId(text: String): String = MESSAGE_PREFIX + text

    fun isMessageId(mediaId: String): Boolean = mediaId.startsWith(MESSAGE_PREFIX)

    /** Fortschritts-Key wie `ABSUserMediaProgress.progressLookupKey` (Markierung „spielt gerade“, Balken). */
    fun progressKey(row: AbsStartShelfMergedRow): String = when (row) {
        is AbsStartShelfMergedRow.Book -> row.book.id
        is AbsStartShelfMergedRow.PodcastEpisode -> row.episode.progressLookupKey
    }

    /** Cover-ID: bei Folgen die Sendung. */
    fun coverItemId(row: AbsStartShelfMergedRow): String = when (row) {
        is AbsStartShelfMergedRow.Book -> row.book.id
        is AbsStartShelfMergedRow.PodcastEpisode -> row.episode.libraryItemId
    }

    fun title(row: AbsStartShelfMergedRow): String = when (row) {
        is AbsStartShelfMergedRow.Book -> row.book.displayTitle
        is AbsStartShelfMergedRow.PodcastEpisode -> row.episode.episodeTitle
    }

    /** iOS: `detail` — Autor bzw. Sendung (Fallback Autorzeile). */
    fun subtitle(row: AbsStartShelfMergedRow): String = when (row) {
        is AbsStartShelfMergedRow.Book -> row.book.displayAuthors
        is AbsStartShelfMergedRow.PodcastEpisode -> row.episode.showTitle.ifEmpty { row.episode.authorLine }
    }

    /** iOS: `item.playbackProgress` — nur mit bekannter Dauer; `null` = kein Balken. */
    fun completionFraction(progress: AbsUserMediaProgress?): Double? {
        if (progress == null || progress.duration <= 0) return null
        return progress.progress.coerceIn(0.0, 1.0)
    }

    /** Media3-`EXTRAS_VALUE_COMPLETION_STATUS_*`: 0 = neu, 1 = angefangen, 2 = fertig. */
    fun completionStatus(progress: AbsUserMediaProgress?): Int = when {
        progress == null -> 0
        progress.isFinished -> 2
        progress.currentTime > 0 || progress.progress > 0 -> 1
        else -> 0
    }

    /** Wurzel-Tabs in iOS-Reihenfolge; die optionalen nur mit Inhalt. */
    fun rootChildIds(hasBooks: Boolean, hasPodcasts: Boolean): List<String> =
        buildList {
            add(CONTINUE_ID)
            if (hasBooks) add(BOOKS_ID)
            if (hasPodcasts) add(PODCASTS_ID)
            add(DOWNLOADS_ID)
        }

    fun tabTitle(id: String): String = when (id) {
        CONTINUE_ID -> CONTINUE_TAB_TITLE
        DOWNLOADS_ID -> DOWNLOADS_TAB_TITLE
        BOOKS_ID -> BOOKS_TAB_TITLE
        PODCASTS_ID -> PODCASTS_TAB_TITLE
        else -> ""
    }

    /** iOS: `clamped(_:)` — höchstens [MAX_ITEMS] Zeilen. */
    fun <T> clamped(rows: List<T>, max: Int = MAX_ITEMS): List<T> = rows.take(maxOf(1, max))
}
