package de.letzgo.abstand.model

import de.letzgo.abstand.data.AbsBook
import java.text.Collator

/**
 * iOS: `PodcastShowSorting` (PodcastShowSorting.swift) — Sortierung der Sendungs-Leiste im Podcasts-Tab.
 *
 * Die Server-Reihenfolge (`GET …/items?sort=`) ist nur ein Vorschlag; verbindlich ist diese reine
 * Funktion. Sie greift sofort nach der Auswahl im Menü, auf gecachte Zeilen (offline, beliebiger zuvor
 * gespeicherter Sortierschlüssel) und auf jede Server-Antwort.
 *
 * Regeln: fehlende Werte (kein Autor, unbekannte Folgenzahl, kein Datum) stehen in beiden Richtungen
 * hinten; Gleichstand → Titel aufsteigend → ursprüngliche Reihenfolge (stabil). [PodcastCatalogSortField.random]
 * lässt die Reihenfolge unverändert (die Mischung kommt vom Server bzw. aus dem Cache).
 */
object PodcastShowSorting {
    fun sorted(
        shows: List<AbsBook>,
        field: PodcastCatalogSortField,
        descending: Boolean,
        ignoreTitlePrefix: Boolean = false,
    ): List<AbsBook> {
        if (field == PodcastCatalogSortField.random || shows.size < 2) return shows
        data class Keyed(val offset: Int, val show: AbsBook, val key: Key, val title: String)
        val keyed = shows.mapIndexed { i, show ->
            Keyed(i, show, sortKey(show, field, ignoreTitlePrefix), titleKey(show, ignoreTitlePrefix))
        }
        return keyed.sortedWith { a, b ->
            val primary = when {
                a.key is Key.Missing && b.key is Key.Missing -> 0
                a.key is Key.Missing -> return@sortedWith 1
                b.key is Key.Missing -> return@sortedWith -1
                else -> compare(a.key, b.key).let { if (descending) -it else it }
            }
            if (primary != 0) return@sortedWith primary
            val byTitle = compareText(a.title, b.title)
            if (byTitle != 0) byTitle else a.offset.compareTo(b.offset)
        }.map { it.show }
    }

    /** Anzahl Folgen: `media.numEpisodes` (minified Katalog), sonst geladene Folgen. */
    fun episodeCount(show: AbsBook): Int? = show.media.numEpisodes ?: show.media.podcastEpisodes?.size

    sealed interface Key {
        data class Text(val value: String) : Key
        data class Number(val value: Double) : Key
        data object Missing : Key
    }

    fun sortKey(show: AbsBook, field: PodcastCatalogSortField, ignoreTitlePrefix: Boolean): Key = when (field) {
        PodcastCatalogSortField.title -> Key.Text(titleKey(show, ignoreTitlePrefix))
        PodcastCatalogSortField.author -> show.displayAuthors.trim().let { if (it.isEmpty() || it == "—") Key.Missing else Key.Text(it) }
        PodcastCatalogSortField.numEpisodes -> episodeCount(show)?.let { Key.Number(it.toDouble()) } ?: Key.Missing
        PodcastCatalogSortField.addedAt -> show.addedAt?.let { Key.Number(it.toDouble()) } ?: Key.Missing
        PodcastCatalogSortField.updatedAt -> show.updatedAt?.let { Key.Number(it.toDouble()) } ?: Key.Missing
        PodcastCatalogSortField.size -> show.media.size?.let { Key.Number(it.toDouble()) } ?: Key.Missing
        PodcastCatalogSortField.random -> Key.Missing
    }

    fun titleKey(show: AbsBook, ignoreTitlePrefix: Boolean): String {
        if (ignoreTitlePrefix) {
            val stripped = show.media.metadata.titleIgnorePrefix?.trim()
            if (!stripped.isNullOrEmpty()) return stripped
        }
        return show.displayTitle.trim()
    }

    private fun compare(a: Key, b: Key): Int = when {
        a is Key.Text && b is Key.Text -> compareText(a.value, b.value)
        a is Key.Number && b is Key.Number -> a.value.compareTo(b.value)
        else -> 0
    }

    private val collator: Collator get() = Collator.getInstance().apply { strength = Collator.PRIMARY }

    /** iOS: `compare(options: [.caseInsensitive, .diacriticInsensitive, .numeric])` — Zahlen numerisch. */
    fun compareText(a: String, b: String): Int {
        val ca = chunks(a)
        val cb = chunks(b)
        val c = collator
        for (i in 0 until minOf(ca.size, cb.size)) {
            val x = ca[i]
            val y = cb[i]
            val xNum = x.first().isDigit()
            val yNum = y.first().isDigit()
            val r = if (xNum && yNum) {
                x.trimStart('0').length.compareTo(y.trimStart('0').length).takeIf { it != 0 }
                    ?: x.trimStart('0').compareTo(y.trimStart('0'))
            } else {
                c.compare(x, y)
            }
            if (r != 0) return r
        }
        return ca.size.compareTo(cb.size)
    }

    private fun chunks(s: String): List<String> {
        if (s.isEmpty()) return emptyList()
        val out = mutableListOf<String>()
        val sb = StringBuilder()
        var digit = s.first().isDigit()
        for (ch in s) {
            if (ch.isDigit() != digit) {
                out += sb.toString()
                sb.clear()
                digit = ch.isDigit()
            }
            sb.append(ch)
        }
        out += sb.toString()
        return out
    }
}
