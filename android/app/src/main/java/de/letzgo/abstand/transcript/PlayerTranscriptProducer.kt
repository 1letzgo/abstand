package de.letzgo.abstand.transcript

import android.content.Context
import de.letzgo.abstand.data.AbsJson
import de.letzgo.abstand.logic.SpeechEnvelopeTracker
import de.letzgo.abstand.logic.SpeechOnsetRefinementBatcher
import de.letzgo.abstand.logic.SpeechOnsetWord
import de.letzgo.abstand.logic.speech.SpeechModelCatalog
import de.letzgo.abstand.logic.speech.SpeechModelStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonPrimitive
import org.vosk.LibVosk
import org.vosk.LogLevel
import org.vosk.Recognizer
import java.io.File
import kotlin.math.max

/** iOS: `PlayerTranscriptProducedWord` — lokale Track-Sekunden. */
data class PlayerTranscriptProducedWord(val text: String, val start: Double, val end: Double)

/** iOS: `PlayerTranscriptProductionBatch`. */
data class PlayerTranscriptProductionBatch(
    val words: List<PlayerTranscriptProducedWord>,
    /** Bis hierher (lokale Track-Sekunde) ist der Bereich abgearbeitet. */
    val processedThrough: Double,
    val isFinalBatch: Boolean,
)

/**
 * iOS: `PlayerTranscriptProducer` — erzeugt Transkripte für einen Track-Bereich so schnell das Gerät
 * kann, entkoppelt von der Wiedergabe. Statt `SpeechAnalyzer` läuft Vosk: die Erkennung arbeitet
 * synchron im Fütter-Thread, deshalb braucht es keine `FeedGate`-Drossel — jede Endpunkt-Erkennung
 * (Pause im Sprachfluss) liefert einen Batch finalisierter Wörter. Wortanfänge nach Sprechpausen werden
 * wie auf iOS per [de.letzgo.abstand.logic.SpeechOnsetRefiner] auf den akustischen Einsatz gelegt.
 */
object PlayerTranscriptProducer {
    /** JNI-Aufrufe kurz halten: 0,25 s je `acceptWaveForm`. */
    private const val SLICE = 4_000

    fun transcribe(
        context: Context,
        assetFile: File,
        startSeconds: Double,
        endSeconds: Double?,
        model: SpeechModelCatalog.Entry,
    ): Flow<PlayerTranscriptProductionBatch> = flow {
        SpeechModelStore.withModel(context.applicationContext, model) { voskModel ->
            runCatching { LibVosk.setLogLevel(LogLevel.WARNINGS) }
            val recognizer = Recognizer(voskModel, PlayerTranscriptionAudioConverter.SAMPLE_RATE.toFloat())
            try {
                recognizer.setWords(true)
                var anchor = max(0.0, startSeconds)
                var analyzedSamples = 0L
                fun analyzedThrough() = anchor + analyzedSamples.toDouble() / PlayerTranscriptionAudioConverter.SAMPLE_RATE
                // iOS: Hüllkurve des gefütterten Audios — Wortanfänge nach Sprechpausen auf den echten Einsatz.
                val envelope = SpeechEnvelopeTracker()
                // iOS gleich: das letzte Wort eines Ergebnisses bleibt bis zum nächsten zurück — erst dann ist
                // bekannt, ob dessen Ende auf den Beginn der folgenden Pause gehört.
                val batcher = SpeechOnsetRefinementBatcher()
                val refine = { words: List<SpeechOnsetWord>, previous: SpeechOnsetWord? -> envelope.refine(words, previous) }
                fun refined(words: List<PlayerTranscriptProducedWord>, last: Boolean): List<PlayerTranscriptProducedWord> {
                    val out = batcher.add(words.map { SpeechOnsetWord(it.text, it.start, it.end) }, refine) +
                        (if (last) batcher.finish(refine) else emptyList())
                    return out.map { PlayerTranscriptProducedWord(it.text, it.start, it.end) }
                }

                val reached = PlayerTranscriptionAudioConverter.decode(
                    assetFile, startSeconds, endSeconds,
                    onAnchor = {
                        anchor = it
                        envelope.setOrigin(it)
                    },
                    onPcm = { pcm ->
                        // Vor dem Erkennen: ein Ergebnis betrifft nie Audio, das die Hüllkurve nicht kennt.
                        envelope.append(pcm, pcm.size, PlayerTranscriptionAudioConverter.SAMPLE_RATE)
                        var offset = 0
                        while (offset < pcm.size) {
                            val n = minOf(SLICE, pcm.size - offset)
                            val slice = if (offset == 0 && n == pcm.size) pcm else pcm.copyOfRange(offset, offset + n)
                            val endpoint = recognizer.acceptWaveForm(slice, n)
                            analyzedSamples += n
                            offset += n
                            if (endpoint) {
                                val words = refined(VoskResult.words(recognizer.result, anchor), last = false)
                                if (words.isNotEmpty()) {
                                    emit(PlayerTranscriptProductionBatch(words, words.last().end, isFinalBatch = false))
                                }
                            }
                        }
                    },
                )
                // Ohne Finalisieren bliebe der letzte Satz im Erkenner hängen.
                val tail = refined(VoskResult.words(recognizer.finalResult, anchor), last = true)
                val through = max(analyzedThrough(), reached)
                if (tail.isNotEmpty()) emit(PlayerTranscriptProductionBatch(tail, through, isFinalBatch = false))
                emit(PlayerTranscriptProductionBatch(emptyList(), through, isFinalBatch = true))
            } finally {
                runCatching { recognizer.close() }
            }
        }
    }.flowOn(Dispatchers.Default)
}

/** Vosk-JSON (`{"result":[{"word":…,"start":…,"end":…}],"text":…}`) → Wörter (aus stashy `VoskResult`). */
object VoskResult {
    /** Wörter in Erkenner-Sekunden + [offset]; leer bei Stille oder Ergebnis ohne Wortzeiten. */
    fun words(raw: String?, offset: Double = 0.0): List<PlayerTranscriptProducedWord> {
        if (raw.isNullOrBlank()) return emptyList()
        val root = runCatching { AbsJson.decoder.parseToJsonElement(raw) as? JsonObject }.getOrNull() ?: return emptyList()
        val list = root["result"] as? JsonArray ?: return emptyList()
        return list.mapNotNull { e ->
            val o = e as? JsonObject ?: return@mapNotNull null
            val word = o["word"]?.jsonPrimitive?.contentOrNull?.trim()?.takeIf { it.isNotEmpty() } ?: return@mapNotNull null
            // Kaldi markiert unbekannte Wörter so — nie anzeigen.
            if (word == "[unk]" || word == "<unk>") return@mapNotNull null
            val start = o["start"]?.jsonPrimitive?.doubleOrNull ?: return@mapNotNull null
            val end = o["end"]?.jsonPrimitive?.doubleOrNull ?: start
            PlayerTranscriptProducedWord(word, offset + start, offset + max(start, end))
        }
    }
}
