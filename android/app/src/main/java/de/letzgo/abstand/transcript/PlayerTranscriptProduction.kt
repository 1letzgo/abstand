package de.letzgo.abstand.transcript

import android.content.Context
import de.letzgo.abstand.logic.FoundationText
import de.letzgo.abstand.logic.PlayerTranscriptLibrary
import de.letzgo.abstand.logic.PlayerTranscriptTrackCache
import de.letzgo.abstand.logic.PlayerTranscriptTrackSource
import de.letzgo.abstand.logic.speech.SpeechModelCatalog
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import java.io.File
import kotlin.coroutines.coroutineContext

/**
 * iOS: produzierender Teil von `PlayerTranscriptLibrary` (`produceAndPersist`, `transcriptText`
 * mit Lückenfüllung). Lesen/Mergen/Speichern liegt in `logic/PlayerTranscriptLibrary`.
 */
object PlayerTranscriptProduction {
    /**
     * iOS: `produceAndPersist` — einen Track-Bereich produzieren und inkrementell persistieren
     * (alle [PlayerTranscriptLibrary.TRANSCRIPT_PERSIST_INTERVAL_SECONDS] und am Ende — auch bei Abbruch).
     * [onBatch] darf werfen (z. B. `CancellationException` bei Vorrang-Arbeit). Rückgabe: erreichte Zeit.
     */
    suspend fun produceAndPersist(
        context: Context,
        bookId: String,
        source: PlayerTranscriptTrackSource,
        model: SpeechModelCatalog.Entry,
        localeIdentifier: String,
        fromLocalTime: Double,
        toLocalTime: Double?,
        onBatch: (suspend (PlayerTranscriptProductionBatch) -> Unit)? = null,
    ): Double {
        val pending = ArrayList<PlayerTranscriptTrackCache.Word>()
        var through = fromLocalTime
        var segmentStart = fromLocalTime

        suspend fun persist() {
            if (!(through > segmentStart)) return
            PlayerTranscriptLibrary.mergeAndSave(
                PlayerTranscriptTrackCache.Segment(segmentStart, through, pending.toList()),
                bookId, source.trackIndex, localeIdentifier,
            )
            pending.clear()
            segmentStart = through
        }

        try {
            PlayerTranscriptProducer.transcribe(context, File(source.assetPath), fromLocalTime, toLocalTime, model).collect { batch ->
                coroutineContext.ensureActive()
                pending.addAll(batch.words.map { PlayerTranscriptTrackCache.Word(it.text, it.start, it.end) })
                through = maxOf(through, batch.processedThrough)
                onBatch?.invoke(batch)
                if (through - segmentStart >= PlayerTranscriptLibrary.TRANSCRIPT_PERSIST_INTERVAL_SECONDS) persist()
            }
            persist()
            return through
        } catch (t: Throwable) {
            // Auch bei Abbruch sichern — die Rechenzeit ist bereits verbraucht.
            withContext(NonCancellable) { persist() }
            throw t
        }
    }

    /**
     * iOS: `PlayerTranscriptLibrary.transcriptText` — zusammenhängender Text für einen globalen
     * Zeitbereich (Recap). Was im Cache liegt, wird gelesen; nur echte Lücken werden nachproduziert.
     */
    suspend fun transcriptText(
        context: Context,
        bookId: String,
        sources: List<PlayerTranscriptTrackSource>,
        globalRange: ClosedFloatingPointRange<Double>,
        model: SpeechModelCatalog.Entry,
        localeIdentifier: String,
    ): String {
        val parts = ArrayList<String>()
        for (source in sources.sortedBy { it.globalOffset }) {
            val window = PlayerTranscriptLibrary.localWindow(source, globalRange) ?: continue
            var cursor = window.start
            while (true) {
                val gapStart = PlayerTranscriptLibrary.firstUncoveredTime(bookId, source, localeIdentifier, cursor) ?: break
                if (gapStart >= window.endInclusive) break
                coroutineContext.ensureActive()
                // Nur die Lücke selbst — am nächsten vorhandenen Segment aufhören (iOS gleich).
                val gapEnd = PlayerTranscriptLibrary.nextCoveredStart(bookId, source, localeIdentifier, gapStart)
                val produced = produceAndPersist(
                    context, bookId, source, model, localeIdentifier, gapStart,
                    minOf(window.endInclusive, gapEnd ?: window.endInclusive),
                )
                // Kein Fortschritt (z. B. Stille bis zum Ende) → Endlosschleife vermeiden.
                if (!(produced > gapStart + 0.5)) break
                cursor = produced
            }
            val words = PlayerTranscriptLibrary.cachedWords(bookId, source.trackIndex, localeIdentifier)
                .filter { it.e >= window.start && it.s <= window.endInclusive }
            if (words.isEmpty()) continue
            parts.add(words.joinToString(" ") { it.t })
        }
        return FoundationText.trimmingWhitespacesAndNewlines(parts.joinToString(" "))
    }
}
