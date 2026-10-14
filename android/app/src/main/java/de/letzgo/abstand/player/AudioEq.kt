@file:OptIn(UnstableApi::class)

package de.letzgo.abstand.player

import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import de.letzgo.abstand.data.Prefs
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

// iOS: AudioEQProcessor.swift

/**
 * iOS: `AudioEQPreset` — Kaskaden von Biquad-Filtern (RBJ-Cookbook), bewusst dezent für Sprache.
 * `rawValue`s identisch zu iOS (gespeichert unter `abstand_eq_preset`).
 */
enum class AudioEQPreset(val rawValue: String, val label: String) {
    flat("flat", "Flat"),
    voiceFocus("voiceFocus", "Voice Focus"),
    bassBoost("bassBoost", "Bass Boost"),
    trebleBoost("trebleBoost", "Treble Boost");

    /** Reihenfolge = Kaskadierungs-Reihenfolge. */
    val filters: List<AudioEQBiquadFilter>
        get() = when (this) {
            flat -> emptyList()
            voiceFocus -> listOf(
                AudioEQBiquadFilter(AudioEQBiquadFilter.Kind.highPass, 80.0, 0.0, 0.707),
                AudioEQBiquadFilter(AudioEQBiquadFilter.Kind.peaking, 2500.0, 4.0, 1.0),
                AudioEQBiquadFilter(AudioEQBiquadFilter.Kind.highShelf, 6000.0, 3.0, 0.707),
            )
            bassBoost -> listOf(AudioEQBiquadFilter(AudioEQBiquadFilter.Kind.lowShelf, 100.0, 6.0, 0.707))
            trebleBoost -> listOf(AudioEQBiquadFilter(AudioEQBiquadFilter.Kind.highShelf, 5000.0, 5.0, 0.707))
        }

    companion object {
        const val DEFAULTS_KEY = "abstand_eq_preset"

        fun fromRaw(raw: String?): AudioEQPreset? = entries.firstOrNull { it.rawValue == raw }

        /** iOS: `loadSaved(key:)` — Default `.flat`. */
        fun loadSaved(): AudioEQPreset = fromRaw(Prefs.string(DEFAULTS_KEY)) ?: flat
    }
}

/** iOS: `AudioEQBiquadFilter` — ein Second-Order-Abschnitt. */
data class AudioEQBiquadFilter(val type: Kind, val frequency: Double, val gain: Double, val q: Double) {
    enum class Kind { lowPass, highPass, peaking, lowShelf, highShelf }
}

/** iOS: `AudioEQBiquadCoefficients` — normalisiert auf a0 = 1. */
data class AudioEQBiquadCoefficients(val b0: Double, val b1: Double, val b2: Double, val a1: Double, val a2: Double) {
    companion object {
        /** RBJ-Cookbook-Formeln bei gegebener Sample-Rate (identisch zu iOS). */
        fun compute(filter: AudioEQBiquadFilter, sampleRate: Double): AudioEQBiquadCoefficients {
            val sr = maxOf(sampleRate, 1.0)
            val w0 = 2.0 * PI * filter.frequency / sr
            val cosW0 = cos(w0)
            val sinW0 = sin(w0)
            val a = 10.0.pow(filter.gain / 40.0)
            val alpha = sinW0 / (2.0 * maxOf(filter.q, 0.0001))
            var b0 = 1.0; var b1 = 0.0; var b2 = 0.0; var a0 = 1.0; var a1 = 0.0; var a2 = 0.0
            when (filter.type) {
                AudioEQBiquadFilter.Kind.lowPass -> {
                    b0 = (1 - cosW0) / 2; b1 = 1 - cosW0; b2 = (1 - cosW0) / 2
                    a0 = 1 + alpha; a1 = -2 * cosW0; a2 = 1 - alpha
                }
                AudioEQBiquadFilter.Kind.highPass -> {
                    b0 = (1 + cosW0) / 2; b1 = -(1 + cosW0); b2 = (1 + cosW0) / 2
                    a0 = 1 + alpha; a1 = -2 * cosW0; a2 = 1 - alpha
                }
                AudioEQBiquadFilter.Kind.peaking -> {
                    b0 = 1 + alpha * a; b1 = -2 * cosW0; b2 = 1 - alpha * a
                    a0 = 1 + alpha / a; a1 = -2 * cosW0; a2 = 1 - alpha / a
                }
                AudioEQBiquadFilter.Kind.lowShelf -> {
                    val sqrtA = sqrt(a)
                    b0 = a * ((a + 1) - (a - 1) * cosW0 + 2 * sqrtA * alpha)
                    b1 = 2 * a * ((a - 1) - (a + 1) * cosW0)
                    b2 = a * ((a + 1) - (a - 1) * cosW0 - 2 * sqrtA * alpha)
                    a0 = (a + 1) + (a - 1) * cosW0 + 2 * sqrtA * alpha
                    a1 = -2 * ((a - 1) + (a + 1) * cosW0)
                    a2 = (a + 1) + (a - 1) * cosW0 - 2 * sqrtA * alpha
                }
                AudioEQBiquadFilter.Kind.highShelf -> {
                    val sqrtA = sqrt(a)
                    b0 = a * ((a + 1) + (a - 1) * cosW0 + 2 * sqrtA * alpha)
                    b1 = -2 * a * ((a - 1) + (a + 1) * cosW0)
                    b2 = a * ((a + 1) + (a - 1) * cosW0 - 2 * sqrtA * alpha)
                    a0 = (a + 1) - (a - 1) * cosW0 + 2 * sqrtA * alpha
                    a1 = 2 * ((a - 1) - (a + 1) * cosW0)
                    a2 = (a + 1) - (a - 1) * cosW0 - 2 * sqrtA * alpha
                }
            }
            return AudioEQBiquadCoefficients(b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0)
        }
    }
}

/**
 * iOS: `AudioEQProcessor` (Biquad-Kaskade je Kanal, Direct-Form-II transposed, Soft-Clip) — hier als
 * Media3-[AudioProcessor] in der Audio-Sink-Kette von ExoPlayer statt `MTAudioProcessingTap`.
 * Dieselben Filter wie iOS auf jedem Gerät (statt geräteabhängiger `audiofx.Equalizer`-Bänder).
 *
 * Arbeitet auf 16-Bit-PCM (Standard der `DefaultAudioSink`, andere Formate → inaktiv). Ein
 * Preset-Wechsel tauscht nur die Koeffizienten-Tabelle (`@Volatile`), der Prozessor bleibt aktiv —
 * kein Rebuild der Audio-Pipeline während der Wiedergabe (bei `flat` reiner Durchlauf).
 */
class BiquadEqAudioProcessor(initial: AudioEQPreset) : BaseAudioProcessor() {
    @Volatile var preset: AudioEQPreset = initial

    /** Unveränderliche Tabelle + Zustände je (Kanal, Stufe). */
    private class Config(val preset: AudioEQPreset, val sampleRate: Int, val channels: Int) {
        val coefficients = preset.filters.map { AudioEQBiquadCoefficients.compute(it, sampleRate.toDouble()) }
        val stages = coefficients.size
        val z1 = DoubleArray(maxOf(1, channels * stages))
        val z2 = DoubleArray(maxOf(1, channels * stages))

        fun copyStates(from: Config) {
            if (from.stages != stages || from.channels != channels || stages == 0) return
            from.z1.copyInto(z1); from.z2.copyInto(z2)
        }
    }

    private var config: Config? = null

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        if (inputAudioFormat.encoding != C.ENCODING_PCM_16BIT) return AudioProcessor.AudioFormat.NOT_SET
        return inputAudioFormat
    }

    override fun onFlush() {
        // Neues Format / Seek: Filterzustände zurücksetzen.
        config = null
    }

    override fun onReset() {
        config = null
    }

    private fun currentConfig(): Config {
        val format = inputAudioFormat
        val wanted = preset
        val existing = config
        if (existing != null && existing.preset == wanted && existing.sampleRate == format.sampleRate &&
            existing.channels == format.channelCount
        ) return existing
        val fresh = Config(wanted, format.sampleRate, format.channelCount)
        existing?.let { fresh.copyStates(it) }
        config = fresh
        return fresh
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val remaining = inputBuffer.remaining()
        if (remaining == 0) return
        val out = replaceOutputBuffer(remaining)
        val cfg = currentConfig()
        if (cfg.stages == 0) {
            out.put(inputBuffer)
            out.flip()
            return
        }
        val input = inputBuffer.order(ByteOrder.nativeOrder())
        val channels = maxOf(1, cfg.channels)
        val stages = cfg.stages
        val coeffs = cfg.coefficients
        var ch = 0
        while (input.remaining() >= 2) {
            var sample = input.getShort() / 32768.0
            val base = ch * stages
            for (s in 0 until stages) {
                val c = coeffs[s]
                val i = base + s
                // Direct-Form-II transposed (RBJ): y = b0*x + z1; z1 = b1*x - a1*y + z2; z2 = b2*x - a2*y
                val y = c.b0 * sample + cfg.z1[i]
                cfg.z1[i] = c.b1 * sample - c.a1 * y + cfg.z2[i]
                cfg.z2[i] = c.b2 * sample - c.a2 * y
                sample = y
            }
            // Soft-Clip gegen gelegentliche Übersteuerung durch Shelving-Boosts.
            if (sample > 1.0) sample = 1.0 else if (sample < -1.0) sample = -1.0
            out.putShort((sample * 32767.0).roundToInt().toShort())
            ch = (ch + 1) % channels
        }
        out.flip()
    }
}
