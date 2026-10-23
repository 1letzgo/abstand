package de.letzgo.abstand.model

import de.letzgo.abstand.data.AbsLibrary

/**
 * Android-eigen (iOS hat getrennte Books-/Podcasts-Tabs): kombinierte Bibliotheks-Auswahl der
 * fixierten Bibliotheksleiste auf Home — alle aktiven Books- und Podcast-Bibliotheken in einem Menü.
 * IDs: `b:<libraryId>` (Books) bzw. `p:<libraryId>` (Podcasts), gemerkt unter [prefsKey].
 */
object HomeLibraryLogic {
    /** Gemerkte Home-Bibliothek (Android-eigener Key). */
    const val prefsKey = "abstand_android_home_library"

    private const val booksPrefix = "b:"
    private const val podcastsPrefix = "p:"

    /** Eintrag der kombinierten Auswahl. */
    data class Choice(val id: String, val library: AbsLibrary, val isPodcast: Boolean)

    fun booksChoiceId(libraryId: String): String = booksPrefix + libraryId.trim()

    fun podcastChoiceId(libraryId: String): String = podcastsPrefix + libraryId.trim()

    /** Books-Bibliotheken zuerst, dann Podcasts — jeweils in der Reihenfolge der aktiven IDs. */
    fun choices(bookLibraries: List<AbsLibrary>, podcastLibraries: List<AbsLibrary>): List<Choice> =
        bookLibraries.map { Choice(booksChoiceId(it.id), it, isPodcast = false) } +
            podcastLibraries.map { Choice(podcastChoiceId(it.id), it, isPodcast = true) }

    /**
     * Gewählte Bibliothek: gespeicherte ID, sonst die fokussierte Books-Bibliothek, sonst die
     * fokussierte Podcast-Bibliothek, sonst der erste Eintrag.
     */
    fun resolve(
        choices: List<Choice>,
        storedId: String?,
        focusedBooksLibraryId: String? = null,
        focusedPodcastLibraryId: String? = null,
    ): Choice? {
        if (choices.isEmpty()) return null
        storedId?.trim()?.takeIf { it.isNotEmpty() }?.let { id -> choices.firstOrNull { it.id == id }?.let { return it } }
        focusedBooksLibraryId?.let { id -> choices.firstOrNull { it.id == booksChoiceId(id) }?.let { return it } }
        focusedPodcastLibraryId?.let { id -> choices.firstOrNull { it.id == podcastChoiceId(id) }?.let { return it } }
        return choices.first()
    }
}
