package de.letzgo.abstand.transcript

import android.os.SystemClock
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import de.letzgo.abstand.logic.SpeechEnvelopeTracker
import de.letzgo.abstand.logic.SpeechOnsetRefinementBatcher
import de.letzgo.abstand.logic.SpeechOnsetWord
import de.letzgo.abstand.logic.speech.SpeechModelCatalog
import de.letzgo.abstand.logic.speech.SpeechModelStore
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.vosk.Recognizer
import java.io.File

/**
 * Messlauf (kein Regressionstest): wendet den Android-Transkriptpfad auf echte Hörbuch-Tracks an und
 * schreibt je Track ein JSON mit rohen Vosk-Wörtern, den Wörtern des echten [PlayerTranscriptProducer]
 * (verfeinert) und der 10-ms-Hüllkurve. Ohne Instrumentation-Argumente überspringt er sich.
 *
 * Argumente (`am instrument -e …`):
 * - `voskAudioDir`: Verzeichnis mit Audiodateien (`*.mp3`/`*.m4a`), lesbar für die App
 *   (z. B. `/sdcard/Android/data/de.letzgo.abstand/files/vosk/audio`)
 * - `voskModelDir`: entpacktes Modell `vosk-model-small-de-0.15` (wird ins App-Modellverzeichnis kopiert)
 * - `voskOutDir`: Ausgabeverzeichnis (Standard: `<voskAudioDir>/../out`)
 * - `voskTracks` (optional): kommagetrennte Dateinamen ohne Endung
 */
@RunWith(AndroidJUnit4::class)
class VoskTimingMeasurementTest {
    private val tag = "VoskTimingMeasurement"

    @Test
    fun measureTracks() {
        val args = InstrumentationRegistry.getArguments()
        val audioDir = args.getString("voskAudioDir")?.let(::File)
        val modelSource = args.getString("voskModelDir")?.let(::File)
        assumeTrue("voskAudioDir/voskModelDir nicht gesetzt — Messlauf übersprungen", audioDir != null && modelSource != null)
        audioDir!!; modelSource!!
        val outDir = File(args.getString("voskOutDir") ?: File(audioDir.parentFile, "out").path).apply { mkdirs() }
        val only = args.getString("voskTracks")?.split(',')?.map { it.trim() }?.filter { it.isNotEmpty() }?.toSet()

        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val entry = SpeechModelCatalog.entry("de") ?: error("kein deutsches Modell im Katalog")
        installModel(context, entry, modelSource)

        val files = audioDir.listFiles { f -> f.isFile && (f.name.endsWith(".mp3") || f.name.endsWith(".m4a")) }
            .orEmpty().sortedBy { it.name }
            .filter { only == null || it.nameWithoutExtension in only }
        assumeTrue("keine Audiodateien in $audioDir", files.isNotEmpty())

        for (file in files) {
            val out = File(outDir, file.nameWithoutExtension + ".json")
            if (out.exists()) continue
            val json = runBlocking { measure(context, entry, file) }
            val tmp = File(outDir, out.name + ".partial")
            tmp.writeText(json.toString())
            tmp.renameTo(out)
            Log.i(tag, "fertig ${file.name}: ${json.getJSONArray("raw").length()} Wörter, Producer ${json.getDouble("producerSeconds")} s")
        }
    }

    private fun installModel(context: android.content.Context, entry: SpeechModelCatalog.Entry, source: File) {
        if (SpeechModelStore.isInstalled(context, entry)) return
        val target = SpeechModelStore.modelDirectory(context, entry)
        target.deleteRecursively()
        check(source.copyRecursively(target, overwrite = true)) { "Modell nicht kopiert" }
        File(target, ".complete").writeText("ok")
    }

    private suspend fun measure(context: android.content.Context, entry: SpeechModelCatalog.Entry, file: File): JSONObject {
        // 1) Echter Producer (wie die App): verfeinerte Wörter je Batch.
        val t0 = SystemClock.elapsedRealtime()
        val batches = PlayerTranscriptProducer.transcribe(context, file, 0.0, null, entry).toList()
        val producerSeconds = (SystemClock.elapsedRealtime() - t0) / 1000.0
        val produced = batches.flatMap { it.words }

        // 2) Spiegel-Lauf mit denselben Bausteinen: rohe Vosk-Wörter (mit Batch-Nummer), volle Hüllkurve,
        //    und die Verfeinerung erneut — muss exakt dem Producer entsprechen (Gegenprobe).
        val rawWords = ArrayList<Pair<PlayerTranscriptProducedWord, Int>>()
        val mirrorRefined = ArrayList<SpeechOnsetWord>()
        val fullLevels = ArrayList<Float>()
        var anchor = 0.0
        var fed = 0L
        val t1 = SystemClock.elapsedRealtime()
        SpeechModelStore.withModel(context, entry) { model ->
            val recognizer = Recognizer(model, PlayerTranscriptionAudioConverter.SAMPLE_RATE.toFloat())
            try {
                recognizer.setWords(true)
                val envelope = SpeechEnvelopeTracker()
                val batcher = SpeechOnsetRefinementBatcher()
                val refine = { w: List<SpeechOnsetWord>, p: SpeechOnsetWord? -> envelope.refine(w, p) }
                val hop = Math.round(PlayerTranscriptionAudioConverter.SAMPLE_RATE * 0.01).toInt()
                var sum = 0.0
                var n = 0
                var batchIndex = 0
                fun take(raw: String?, last: Boolean) {
                    val words = VoskResult.words(raw, anchor)
                    words.forEach { rawWords += it to batchIndex }
                    if (words.isNotEmpty()) batchIndex += 1
                    mirrorRefined += batcher.add(words.map { SpeechOnsetWord(it.text, it.start, it.end) }, refine)
                    if (last) mirrorRefined += batcher.finish(refine)
                }
                PlayerTranscriptionAudioConverter.decode(
                    file, 0.0, null,
                    onAnchor = { anchor = it; envelope.setOrigin(it) },
                    onPcm = { pcm ->
                        envelope.append(pcm, pcm.size, PlayerTranscriptionAudioConverter.SAMPLE_RATE)
                        for (s in pcm) {
                            val v = s.toDouble() / 32768.0
                            sum += v * v; n += 1
                            if (n == hop) { fullLevels += SpeechEnvelopeTracker.level(sum, n); sum = 0.0; n = 0 }
                        }
                        var offset = 0
                        while (offset < pcm.size) {
                            val len = minOf(4_000, pcm.size - offset)
                            val slice = if (offset == 0 && len == pcm.size) pcm else pcm.copyOfRange(offset, offset + len)
                            val endpoint = recognizer.acceptWaveForm(slice, len)
                            fed += len
                            offset += len
                            if (endpoint) take(recognizer.result, last = false)
                        }
                    },
                )
                take(recognizer.finalResult, last = true)
            } finally {
                runCatching { recognizer.close() }
            }
        }
        val mirrorSeconds = (SystemClock.elapsedRealtime() - t1) / 1000.0

        fun arr(words: List<Triple<String, Double, Double>>, batch: List<Int>? = null) = JSONArray().apply {
            words.forEachIndexed { i, (t, s, e) ->
                put(JSONObject().put("t", t).put("s", s).put("e", e).apply { batch?.let { put("b", it[i]) } })
            }
        }
        val audioSeconds = fed.toDouble() / PlayerTranscriptionAudioConverter.SAMPLE_RATE
        return JSONObject()
            .put("file", file.name)
            .put("model", entry.modelName)
            .put("abi", android.os.Build.SUPPORTED_ABIS.joinToString(","))
            .put("anchor", anchor)
            .put("audioSeconds", audioSeconds)
            .put("producerSeconds", producerSeconds)
            .put("mirrorSeconds", mirrorSeconds)
            .put("batches", batches.size)
            .put("finalThrough", batches.lastOrNull()?.processedThrough ?: 0.0)
            .put("raw", arr(rawWords.map { Triple(it.first.text, it.first.start, it.first.end) }, rawWords.map { it.second }))
            .put("refined", arr(produced.map { Triple(it.text, it.start, it.end) }))
            .put("mirrorRefined", arr(mirrorRefined.map { Triple(it.text, it.start, it.end) }))
            .put("envelope", JSONObject().put("start", anchor).put("hop", 0.01).put("levels", JSONArray().apply {
                fullLevels.forEach { put(Math.round(it * 100) / 100.0) }
            }))
            .also { Log.i(tag, "${file.name}: ${"%.1f".format(audioSeconds)} s Audio, Producer ${producerSeconds}s, Spiegel ${mirrorSeconds}s") }
    }
}
