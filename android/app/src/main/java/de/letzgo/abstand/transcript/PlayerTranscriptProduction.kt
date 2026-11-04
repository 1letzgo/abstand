package de.letzgo.abstand.transcript

import android.content.Context
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
}
