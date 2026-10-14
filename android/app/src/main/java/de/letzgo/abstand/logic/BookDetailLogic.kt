package de.letzgo.abstand.logic

import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsBookMediaMetadata
import de.letzgo.abstand.data.AbsChapter
import de.letzgo.abstand.data.AbsSeries
import de.letzgo.abstand.data.AbsUserMediaProgress
import de.letzgo.abstand.data.absPlainText
import de.letzgo.abstand.data.swiftTrim
import de.letzgo.abstand.ui.formatPlaybackDurationShortHuman
import de.letzgo.abstand.ui.formatPlaybackTime

/** iOS: `BookChapterPlayState` (BookListeningDetailSections.swift). */
enum class BookChapterPlayState {
    NotStarted, InProgress, Completed;

    companion object {
        /** iOS: `resolve(chapter:progress:)` — 0,75 s Toleranz an den Kapitelgrenzen. */
        fun resolve(chapter: AbsChapter, progress: AbsUserMediaProgress?): BookChapterPlayState {
            if (progress?.isFinished == true) return Completed
            val t = progress?.currentTime ?: 0.0
            val eps = 0.75
            if (t + eps >= chapter.end) return Completed
            if (t + eps >= chapter.start) return InProgress
            return NotStarted
        }
    }
}

/**
 * Reine Ableitungen aus iOS `BookDetailView.swift` (Hero-Zeilen, Meta-Karten, Toolbar-Zustände)
 * und `LibraryCardViews.swift` (Restlaufzeit der Play-Pille).
 */
object BookDetailLogic {
    /** iOS: `trimmedMetaValue` — leer/„—" = keiner. */
    fun trimmedMetaValue(value: String?): String? {
        val t = value?.swiftTrim() ?: return null
        if (t.isEmpty() || t == "—") return null
        return t
    }

    /** iOS: `publishedDisplayLine` — „Verlag - Jahr". */
    fun publishedDisplayLine(publisher: String?, year: String?): String? = when {
        publisher != null && year != null -> "$publisher - $year"
        publisher != null -> publisher
        year != null -> year
        else -> null
    }

    /** iOS: `hasSeriesContent`. */
    fun hasSeriesContent(m: AbsBookMediaMetadata): Boolean =
        !m.series.isNullOrEmpty() || !m.resolvedSeriesDisplay?.swiftTrim().isNullOrEmpty()

    /** iOS: `seriesDisplayLine(for:)` — „Name (Sequenz)". */
    fun seriesDisplayLine(s: AbsSeries): String {
        val q = s.sequence?.swiftTrim().orEmpty()
        return if (q.isNotEmpty()) "${s.name} ($q)" else s.name
    }

    /** iOS: `bookAboutText` — Plaintext aus `descriptionPlain`/`description`. */
    fun aboutText(m: AbsBookMediaMetadata): String? = absPlainText(m.descriptionPlain ?: m.description).ifEmpty { null }

    /** iOS: `resolvedGenres`. */
    fun genres(m: AbsBookMediaMetadata): List<String> = m.genres.orEmpty().map { it.swiftTrim() }.filter { it.isNotEmpty() }

    /** iOS: `resolvedTags`. */
    fun tags(book: AbsBook): List<String> = book.media.tags.orEmpty().map { it.swiftTrim() }.filter { it.isNotEmpty() }

    /** iOS: `heroAuthorLinks` — (ID, Name); ohne Autor-IDs der Name als ID (öffnet die Namenssuche). */
    fun heroAuthorLinks(book: AbsBook): List<Pair<String, String>> {
        val m = book.media.metadata
        m.authors?.takeIf { it.isNotEmpty() }?.let { list -> return list.map { it.id to it.name } }
        m.authorName?.swiftTrim()?.takeIf { it.isNotEmpty() }?.let { return listOf(it to it) }
        val line = book.displayAuthors.swiftTrim()
        if (line.isEmpty() || line == "—") return emptyList()
        return listOf(line to line)
    }

    /** iOS: `bookDurationLabel` — „—" ohne Dauer. */
    fun durationLabel(book: AbsBook, progress: AbsUserMediaProgress?): String {
        val sec = book.media.duration ?: progress?.duration ?: 0.0
        if (sec <= 0) return "—"
        return formatPlaybackTime(sec)
    }

    /** iOS: Hero-Tertiärzeile (Dauer · Jahr); bei reinen eBooks ohne „—". */
    fun tertiaryParts(book: AbsBook, progress: AbsUserMediaProgress?): List<String> {
        val parts = listOf(durationLabel(book, progress), book.media.metadata.publishedYear ?: "")
        return if (book.isPureEbookLibraryItem) parts.filter { it != "—" } else parts
    }

    /** iOS: `tertiaryLine` von `DetailHeroInfoSection`. */
    fun tertiaryLine(parts: List<String>): String =
        parts.map { it.swiftTrim() }.filter { it.isNotEmpty() && it != "—" }.joinToString(" · ")

    /** iOS: `bookPlayProgress01`. */
    fun playProgress01(progress: AbsUserMediaProgress?, bookDuration: Double?): Double {
        val p = progress ?: return 0.0
        if (p.isFinished) return 1.0
        if (p.duration > 0) return p.progress.coerceIn(0.0, 1.0)
        val total = bookDuration ?: 0.0
        if (total > 0) return (p.currentTime / total).coerceIn(0.0, 1.0)
        return 0.0
    }

    /** iOS: `canDiscardListeningProgress` (Toolbar „Reset listening progress"). */
    fun canDiscardListeningProgress(progress: AbsUserMediaProgress?, isPureEbook: Boolean): Boolean {
        if (isPureEbook) return false
        val p = progress ?: return false
        if (p.isFinished) return true
        if (p.currentTime > 1) return true
        if (p.duration > 0 && p.progress > 0.001) return true
        return false
    }

    /** iOS: `ebookDisplayProgressFraction` ohne Override — Maximum aus Server-Zeile und Gerät. */
    fun ebookDisplayFraction(serverFraction: Double?, localFraction: Double?): Double? {
        val f = listOfNotNull(serverFraction, localFraction).maxOrNull() ?: return null
        if (!(f > 0.005)) return null
        val clamped = f.coerceIn(0.0, 1.0)
        return if (clamped >= 0.995) 1.0 else clamped
    }

    /** iOS: `playPillRemainingCaption` — Restlaufzeit für die Play-Pille der Cover-Karte. */
    fun remainingCaption(totalDurationSeconds: Double, progress: AbsUserMediaProgress?): String {
        val total = maxOf(0.0, totalDurationSeconds)
        if (total <= 0) return formatPlaybackDurationShortHuman(0.0)
        val p = progress ?: return formatPlaybackDurationShortHuman(total)
        if (p.isFinished) return formatPlaybackDurationShortHuman(0.0)
        val elapsed = when {
            p.currentTime > 0 -> minOf(total, p.currentTime)
            p.duration > 0 && p.progress > 0 && p.progress <= 1 -> minOf(total, p.progress * p.duration)
            else -> 0.0
        }
        return formatPlaybackDurationShortHuman(maxOf(0.0, total - elapsed))
    }

    /** iOS: `defaultBookmarkTitle(atSeconds:)`. */
    fun defaultBookmarkTitle(time: Int): String {
        val t = maxOf(0, time)
        return if (t >= 3600) formatPlaybackDurationShortHuman(t.toDouble()) else formatPlaybackTime(t.toDouble())
    }

    /** iOS: `DetailMetaExpandableTextBlock.offersExpansion` (> 200 Zeichen oder ≥ Zeilenlimit Umbrüche). */
    fun offersExpansion(text: String, collapsedLineLimit: Int = 4): Boolean =
        text.length > 200 || text.count { it == '\n' } >= collapsedLineLimit

    /** iOS: `ListeningHistoryRow` — relativer Start/Ende der Sitzung im Balken (0…1). */
    fun sessionRange(duration: Double, startTime: Double, currentTime: Double): Pair<Double, Double> {
        val denom = maxOf(duration, currentTime, startTime, 1.0)
        return (startTime / denom) to (currentTime / denom)
    }
}
