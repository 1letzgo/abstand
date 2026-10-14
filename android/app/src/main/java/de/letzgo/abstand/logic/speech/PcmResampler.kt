package de.letzgo.abstand.logic.speech

import kotlin.math.max

/**
 * Interleaved 16-Bit-PCM beliebiger Rate/Kanalzahl → 16 kHz mono für die Erkennung (iOS:
 * `PlayerTranscriptionAudioConverter`; übernommen aus stashy `PcmResampler`). Lineare Interpolation,
 * zustandsbehaftet über Puffergrenzen, damit Chunk-Grenzen nicht knacken.
 */
class PcmResampler(private val sourceRate: Int, private val channels: Int, private val targetRate: Int = 16_000) {
    private val step = sourceRate.toDouble() / targetRate
    private var position = 0.0 // nächste Ausgabeposition in Quell-Frames relativ zu `previous`
    private var previous = 0f
    private var hasPrevious = false

    fun process(input: ShortArray, length: Int = input.size): ShortArray {
        val frames = length / max(1, channels)
        if (frames == 0) return ShortArray(0)
        val mono = FloatArray(frames + 1)
        // Index 0 ist der letzte Frame des vorigen Puffers; Quell-Frame k liegt bei mono[k + 1].
        mono[0] = if (hasPrevious) previous else 0f
        for (f in 0 until frames) {
            var sum = 0f
            for (c in 0 until channels) sum += input[f * channels + c]
            mono[f + 1] = sum / channels
        }
        if (!hasPrevious) { mono[0] = mono[1]; position = 1.0 }
        val out = ShortArray(((frames - position) / step).toInt().coerceAtLeast(0) + 2)
        var n = 0
        // Interpoliert mono[i] … mono[i + 1]; stoppt vor dem letzten Frame, der übertragen wird.
        while (position < frames && n < out.size) {
            val i = position.toInt()
            val frac = (position - i).toFloat()
            val a = mono[i]
            val b = mono[i + 1]
            out[n++] = (a + (b - a) * frac).toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
            position += step
        }
        previous = mono[frames]
        hasPrevious = true
        position -= frames
        return if (n == out.size) out else out.copyOf(n)
    }

    /** [seconds] Stille in 16 kHz (iOS `makeSilence`). */
    fun silence(seconds: Double): ShortArray = ShortArray((seconds * targetRate).toInt().coerceAtLeast(1))
}
