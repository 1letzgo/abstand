package de.letzgo.abstand.transcript

import android.content.Context
import android.util.Log
import de.letzgo.abstand.logic.PlayerTranscriptLibrary
import de.letzgo.abstand.logic.PlayerTranscriptRunWindow
import de.letzgo.abstand.logic.PlayerTranscriptTrackCache
import de.letzgo.abstand.logic.PlayerTranscriptTrackSource
import de.letzgo.abstand.logic.speech.SpeechModelCatalog
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.withContext
import java.io.File
import java.util.concurrent.CancellationException

/** iOS: `PlayerTranscriptProductionResult` — Ergebnis eines vollständig durchgelaufenen Produktionslaufs. */
data class PlayerTranscriptProductionResult(
    /** Bis hierher (lokale Track-Sekunde) ist gespeichert. */
    val through: Double,
    /** Bis hierher wurde Audio gefüttert (Bereichs- oder Dateiende) — Beleg, dass der Lauf den Bereich ganz sah. */
    val fedThrough: Double,
)

/** iOS: `PlayerTranscriptProducerError.endedWithoutFinalBatch` — nie als „fertig" werten. */
class PlayerTranscriptEndedWithoutFinalBatch : IllegalStateException("transcript producer ended without final batch")

/**
 * iOS: produzierender Teil von `PlayerTranscriptLibrary` (`fillGap`, `persistProduction`). Lesen/Mergen/Speichern
 * liegt in `logic/PlayerTranscriptLibrary`.
 */
object PlayerTranscriptProduction {
    private const val TAG = "TranscriptProduction"

    /**
     * iOS: `fillGap` — eine Lücke der Vorproduktion füllen: mit Vor-/Nachlauf produzieren und speichern. Hat der
     * Producer belegbar bis zum Ende des Bereichs gefüttert (finaler Batch) und endet die Datei vor dem
     * Bereichsende, wird der Rest ohne Wörter als abgedeckt eingetragen. Abbruch endet immer als
     * `CancellationException` (nie als „nichts produziert"); vor dem Markieren prüft [isCurrent], dass der Lauf
     * noch gilt. Rückgabe: Sekunde, ab der die nächste Lücke gesucht wird. [batches] nur für Tests.
     */
    suspend fun fillGap(
        context: Context?,
        bookId: String,
        source: PlayerTranscriptTrackSource,
        model: SpeechModelCatalog.Entry?,
        localeIdentifier: String,
        gapStart: Double,
        gapEnd: Double?,
        isCurrent: () -> Boolean,
        account: File? = PlayerTranscriptLibrary.activeAccount,
        onBatch: (suspend (PlayerTranscriptProductionBatch) -> Unit)? = null,
        batches: ((PlayerTranscriptRunWindow) -> Flow<PlayerTranscriptProductionBatch>)? = null,
    ): Double {
        val window = PlayerTranscriptRunWindow(gapStart, gapEnd)
        val flow = batches?.invoke(window)
            ?: PlayerTranscriptProducer.transcribe(context!!, File(source.assetPath), window.runStart, window.runEnd, model!!)
        val result = persistProduction(flow, bookId, source.trackIndex, localeIdentifier, window, account, onBatch)
        // Vor jedem Markieren: Lauf weder abgebrochen noch überholt.
        currentCoroutineContext().ensureActive()
        if (!isCurrent()) throw CancellationException("prefetch run superseded")
        val rangeEnd = gapEnd ?: source.duration
        val markFrom = maxOf(gapStart, result.through)
        if (rangeEnd > markFrom) {
            runCatching {
                Log.i(TAG, "track=${source.trackIndex} audio ends at ${result.fedThrough} (fed), range ends $rangeEnd — rest marked without words")
            }
            PlayerTranscriptLibrary.mergeAndSave(
                PlayerTranscriptTrackCache.Segment(markFrom, rangeEnd, emptyList()),
                bookId, source.trackIndex, localeIdentifier, account,
            )
        }
        return maxOf(result.through, rangeEnd)
    }

    /**
     * iOS: `persistProduction` — Batches eines Laufs einsammeln und inkrementell speichern (alle
     * [PlayerTranscriptLibrary.TRANSCRIPT_PERSIST_INTERVAL_SECONDS] und am Ende — auch bei Abbruch das Bisherige).
     * Übernommen werden nur Wörter, die in der Lücke beginnen ([PlayerTranscriptRunWindow.keeps]). Kehrt nur
     * zurück, wenn der Producer den Bereich ganz gefüttert hat; [onBatch] darf werfen (Pause).
     */
    suspend fun persistProduction(
        batches: Flow<PlayerTranscriptProductionBatch>,
        bookId: String,
        trackIndex: Int,
        localeIdentifier: String,
        window: PlayerTranscriptRunWindow,
        account: File? = PlayerTranscriptLibrary.activeAccount,
        onBatch: (suspend (PlayerTranscriptProductionBatch) -> Unit)? = null,
    ): PlayerTranscriptProductionResult {
        val pending = ArrayList<PlayerTranscriptTrackCache.Word>()
        // Gespeichert wird ab Lückenanfang — der Vorlauf gehört dem Segment davor.
        var through = window.gapStart
        var segmentStart = window.gapStart
        var fedThrough: Double? = null

        suspend fun persist() {
            if (!(through > segmentStart)) return
            PlayerTranscriptLibrary.mergeAndSave(
                PlayerTranscriptTrackCache.Segment(segmentStart, through, pending.toList()),
                bookId, trackIndex, localeIdentifier, account,
            )
            pending.clear()
            segmentStart = through
        }

        try {
            batches.collect { batch ->
                currentCoroutineContext().ensureActive()
                pending.addAll(
                    batch.words.filter { window.keeps(it.start) }.map { PlayerTranscriptTrackCache.Word(it.text, it.start, it.end) },
                )
                through = maxOf(through, batch.processedThrough)
                if (batch.isFinalBatch) fedThrough = batch.processedThrough
                onBatch?.invoke(batch)
                if (through - segmentStart >= PlayerTranscriptLibrary.TRANSCRIPT_PERSIST_INTERVAL_SECONDS) persist()
            }
            // iOS: ein abgebrochener Stream endet dort regulär — hier wie dort nie als „Lauf durch" werten.
            currentCoroutineContext().ensureActive()
            val fed = fedThrough ?: throw PlayerTranscriptEndedWithoutFinalBatch()
            persist()
            return PlayerTranscriptProductionResult(through, fed)
        } catch (t: Throwable) {
            // Auch bei Abbruch sichern — gespeichert wird nur bis zum Ende des letzten echten Ergebnisses.
            withContext(NonCancellable) { persist() }
            throw t
        }
    }
}
