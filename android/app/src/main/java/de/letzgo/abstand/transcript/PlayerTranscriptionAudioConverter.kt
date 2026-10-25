package de.letzgo.abstand.transcript

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import de.letzgo.abstand.logic.speech.PcmResampler
import kotlinx.coroutines.ensureActive
import java.io.File
import java.nio.ByteOrder
import kotlin.coroutines.coroutineContext
import kotlin.math.max

/** iOS: `PlayerTranscriptProducerError`. */
class PlayerTranscriptProducerException(message: String) : Exception(message) {
    companion object {
        fun audioUnavailable() = PlayerTranscriptProducerException("No audio source for transcription.")
        fun conversionFailed() = PlayerTranscriptProducerException("Audio could not be prepared for transcription.")
    }
}

/**
 * iOS: `AVAssetReader` + `PlayerTranscriptionAudioConverter` — liest eine lokale Track-Datei ab
 * [startSeconds] mit MediaExtractor/MediaCodec und liefert 16 kHz mono PCM ([PcmResampler]) für die
 * Erkennung (Dekodierschleife aus stashy `TranscodeAudioSource.decode`). Ungedrosselt: der Aufrufer
 * (Vosk) verarbeitet synchron, Gegendruck entsteht von selbst.
 *
 * Läuft im Kontext des Aufrufers (kein eigener Dispatcher-Wechsel), damit ein `flow { }` aus den
 * Callbacks heraus emittieren darf.
 */
object PlayerTranscriptionAudioConverter {
    const val SAMPLE_RATE = 16_000

    /**
     * Dekodiert `[startSeconds, endSeconds)` (lokale Track-Sekunden). [onAnchor] einmal mit der
     * Track-Zeit des ersten gelieferten Samples, [onPcm] mit 16-kHz-Mono-Blöcken.
     * Rückgabe: Track-Zeit, bis zu der dekodiert wurde.
     */
    suspend fun decode(
        file: File,
        startSeconds: Double,
        endSeconds: Double?,
        onAnchor: suspend (Double) -> Unit,
        onPcm: suspend (ShortArray) -> Unit,
    ): Double {
        if (!file.isFile) throw PlayerTranscriptProducerException.audioUnavailable()
        val start = max(0.0, startSeconds)
        val end = endSeconds?.takeIf { it > start }
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        var reached = start
        try {
            try {
                extractor.setDataSource(file.absolutePath)
            } catch (e: Exception) {
                throw PlayerTranscriptProducerException.audioUnavailable()
            }
            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: throw PlayerTranscriptProducerException.audioUnavailable()
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            val isMp3 = format.getString(MediaFormat.KEY_MIME) == MediaFormat.MIMETYPE_AUDIO_MPEG
            // MP3: Track-Zeit = Paketzeit − Encoder-Delay. ExoPlayer schneidet das Delay (LAME-Header)
            // weg, seine Zeit 0 ist das erste echte Sample. Wir schneiden selbst (Keys aus dem Format,
            // sonst trimmt der Decoder ab dem Einstiegspunkt mitten in der Datei echte Frames weg).
            // AAC/MP4 bleibt unverändert: dort verschieben Extractor und ExoPlayer die Zeiten
            // gleichermaßen über die Edit-List — ein pauschales 2112-Sample-Priming wäre doppelt.
            val delaySeconds = if (isMp3) mp3EncoderDelaySeconds(format) else 0.0
            if (isMp3) {
                format.setInteger(KEY_ENCODER_DELAY, 0)
                format.setInteger(KEY_ENCODER_PADDING, 0)
                skipMp3Packets(extractor, start - MP3_PREROLL_SECONDS + delaySeconds)
            } else if (start > 0) {
                extractor.seekTo((start * 1_000_000).toLong(), MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            }
            val c = try {
                MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!).also {
                    it.configure(format, null, null, 0)
                    it.start()
                }
            } catch (e: Exception) {
                throw PlayerTranscriptProducerException.conversionFailed()
            }
            codec = c

            var sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var floatPcm = false
            var resampler = PcmResampler(sampleRate, channels, SAMPLE_RATE)
            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var anchored = false
            var idleRounds = 0

            while (true) {
                coroutineContext.ensureActive()
                if (!inputDone) {
                    val inIndex = c.dequeueInputBuffer(10_000)
                    if (inIndex >= 0) {
                        val buffer = c.getInputBuffer(inIndex)!!
                        val size = runCatching { extractor.readSampleData(buffer, 0) }.getOrDefault(-1)
                        val sampleTime = extractor.sampleTime
                        // Über das Bereichsende hinaus nichts mehr einspeisen.
                        if (size < 0 || (end != null && sampleTime >= 0 && sampleTime / 1_000_000.0 - delaySeconds >= end)) {
                            c.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            c.queueInputBuffer(inIndex, 0, size, sampleTime.coerceAtLeast(0), 0)
                            extractor.advance()
                        }
                    }
                }
                val outIndex = c.dequeueOutputBuffer(info, 10_000)
                when {
                    outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val f = c.outputFormat
                        sampleRate = f.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        channels = f.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        floatPcm = f.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
                            f.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT
                        resampler = PcmResampler(sampleRate, channels, SAMPLE_RATE)
                    }
                    outIndex >= 0 -> {
                        idleRounds = 0
                        val eos = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                        if (info.size > 0) {
                            val out = c.getOutputBuffer(outIndex)!!
                            out.position(info.offset); out.limit(info.offset + info.size)
                            val shorts: ShortArray = if (floatPcm) {
                                val fb = out.order(ByteOrder.nativeOrder()).asFloatBuffer()
                                ShortArray(fb.remaining()) { (fb.get(it) * 32767f).toInt().coerceIn(-32768, 32767).toShort() }
                            } else {
                                val sb = out.order(ByteOrder.nativeOrder()).asShortBuffer()
                                ShortArray(sb.remaining()).also { sb.get(it) }
                            }
                            c.releaseOutputBuffer(outIndex, false)
                            val ch = max(1, channels)
                            val rate = max(1, sampleRate)
                            val frames = shorts.size / ch
                            val sampleStart = info.presentationTimeUs / 1_000_000.0 - delaySeconds
                            val window = DecodeWindow.trim(sampleStart, frames, rate, start, end)
                            if (window != null) {
                                val slice = if (window.first == 0 && window.last == frames - 1) shorts
                                else shorts.copyOfRange(window.first * ch, (window.last + 1) * ch)
                                val pcm = resampler.process(slice)
                                if (!anchored) {
                                    anchored = true
                                    onAnchor(sampleStart + window.first.toDouble() / rate)
                                }
                                reached = max(reached, sampleStart + (window.last + 1).toDouble() / rate)
                                if (pcm.isNotEmpty()) onPcm(pcm)
                            }
                            if (end != null && sampleStart + frames.toDouble() / rate >= end) break
                        } else {
                            c.releaseOutputBuffer(outIndex, false)
                        }
                        if (eos) break
                    }
                    else -> if (inputDone && ++idleRounds > 200) break
                }
            }
        } finally {
            runCatching { codec?.stop() }
            runCatching { codec?.release() }
            runCatching { extractor.release() }
        }
        return reached
    }

    /** Vorlauf vor dem Ziel: MP3-Frames hängen über das Bit-Reservoir an Vorgängern (verworfen per [DecodeWindow]). */
    private const val MP3_PREROLL_SECONDS = 0.2
    private const val SKIP_CANCEL_CHECK_INTERVAL = 2_048

    // `MediaFormat.KEY_ENCODER_DELAY`/`KEY_ENCODER_PADDING` erst ab API 30 als Konstante.
    private const val KEY_ENCODER_DELAY = "encoder-delay"
    private const val KEY_ENCODER_PADDING = "encoder-padding"

    private fun mp3EncoderDelaySeconds(format: MediaFormat): Double {
        if (!format.containsKey(KEY_ENCODER_DELAY)) return 0.0
        val delay = runCatching { format.getInteger(KEY_ENCODER_DELAY) }.getOrDefault(0)
        val rate = runCatching { format.getInteger(MediaFormat.KEY_SAMPLE_RATE) }.getOrDefault(0)
        return if (delay > 0 && rate > 0) delay.toDouble() / rate else 0.0
    }

    /**
     * MP3 ohne `seekTo`: dessen Ziel schätzt der Extractor bei VBR aus Xing-TOC/Bitrate (Sekunden daneben),
     * und die Paketzeiten danach erben den Fehler. Sequenziell ab 0 zählt er Frames exakt — ohne Dekodieren
     * nur Header lesen und überspringen, bis das nächste Paket bei [targetPacketSeconds] liegt.
     */
    private suspend fun skipMp3Packets(extractor: MediaExtractor, targetPacketSeconds: Double) {
        if (targetPacketSeconds <= 0) return
        val targetUs = (targetPacketSeconds * 1_000_000).toLong()
        var count = 0
        while (true) {
            val time = extractor.sampleTime
            if (time < 0 || time >= targetUs) return
            if (!extractor.advance()) return
            if (++count % SKIP_CANCEL_CHECK_INTERVAL == 0) coroutineContext.ensureActive()
        }
    }
}

/** Reine Hilfe: welcher Frame-Bereich eines dekodierten Puffers liegt in `[start, end)`? */
object DecodeWindow {
    /** Frame-Indizes (inklusive) oder `null`, wenn der Puffer ganz außerhalb liegt. */
    fun trim(bufferStart: Double, frames: Int, sampleRate: Int, start: Double, end: Double?): IntRange? {
        if (frames <= 0) return null
        val rate = sampleRate.toDouble()
        val first = if (bufferStart >= start) 0 else kotlin.math.ceil((start - bufferStart) * rate - 1e-9).toInt()
        val lastExclusive = if (end == null) frames else kotlin.math.ceil((end - bufferStart) * rate - 1e-9).toInt().coerceAtMost(frames)
        if (first >= frames || lastExclusive <= first) return null
        return first until lastExclusive
    }
}
