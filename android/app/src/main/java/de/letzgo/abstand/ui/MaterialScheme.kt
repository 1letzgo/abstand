package de.letzgo.abstand.ui

import androidx.compose.material3.ColorScheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.ui.graphics.Color
import kotlin.math.atan2
import kotlin.math.cbrt
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.sin

// Reine Farb-Logik ohne Compose-Runtime — per JUnit testbar (MaterialSchemeTest).
// Android-only (kein iOS-Gegenstück): Material-3-Farbrollen aus dem abstand-Akzent.

/**
 * CIE-L*C*h-Farbe (D65). [l] ist zugleich der M3-„Ton“ (0 = Schwarz, 100 = Weiß): Material 3
 * definiert Töne über L*, deshalb trifft eine Palette hier dieselben Helligkeitsstufen wie HCT.
 */
data class Lch(val l: Double, val c: Double, val h: Double)

/** sRGB ↔ CIELAB/LCh mit Gamut-Mapping (Chroma wird reduziert, bis die Farbe in sRGB liegt). */
object TonalColor {
    private const val XN = 0.95047
    private const val YN = 1.0
    private const val ZN = 1.08883
    private const val EPSILON = 216.0 / 24389.0
    private const val KAPPA = 24389.0 / 27.0

    fun toLch(color: Color): Lch {
        val r = linearize(color.red.toDouble())
        val g = linearize(color.green.toDouble())
        val b = linearize(color.blue.toDouble())
        val x = 0.4124564 * r + 0.3575761 * g + 0.1804375 * b
        val y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
        val z = 0.0193339 * r + 0.1191920 * g + 0.9503041 * b
        val fx = labF(x / XN)
        val fy = labF(y / YN)
        val fz = labF(z / ZN)
        val l = 116 * fy - 16
        val a = 500 * (fx - fy)
        val bb = 200 * (fy - fz)
        val h = Math.toDegrees(atan2(bb, a)).let { if (it < 0) it + 360 else it }
        return Lch(l, hypot(a, bb), h)
    }

    /** M3-Ton einer Farbe (= L*). */
    fun tone(color: Color): Double = toLch(color).l

    /** Farbe mit Ton [l], Farbton [h] und höchstens Chroma [c] — so viel Chroma, wie sRGB zulässt. */
    fun fromLch(l: Double, c: Double, h: Double): Color {
        val tone = l.coerceIn(0.0, 100.0)
        linearRgb(tone, c, h)?.let { return toColor(it) }
        var lo = 0.0
        var hi = c
        repeat(24) {
            val mid = (lo + hi) / 2
            if (linearRgb(tone, mid, h) != null) lo = mid else hi = mid
        }
        return toColor(linearRgb(tone, lo, h) ?: linearRgb(tone, 0.0, h)!!)
    }

    /** Lineares sRGB oder `null`, wenn außerhalb des Gamuts. */
    private fun linearRgb(l: Double, c: Double, h: Double): DoubleArray? {
        val rad = Math.toRadians(h)
        val a = c * cos(rad)
        val b = c * sin(rad)
        val fy = (l + 16) / 116
        val fx = fy + a / 500
        val fz = fy - b / 200
        val x = XN * labFInv(fx)
        val y = YN * (if (l > KAPPA * EPSILON) fy.pow(3) else l / KAPPA)
        val z = ZN * labFInv(fz)
        val rgb = doubleArrayOf(
            3.2404542 * x - 1.5371385 * y - 0.4985314 * z,
            -0.9692660 * x + 1.8760108 * y + 0.0415560 * z,
            0.0556434 * x - 0.2040259 * y + 1.0572252 * z,
        )
        val tol = 1e-4
        return if (rgb.all { it >= -tol && it <= 1 + tol }) rgb else null
    }

    private fun toColor(lin: DoubleArray): Color = Color(
        delinearize(lin[0]).toFloat(), delinearize(lin[1]).toFloat(), delinearize(lin[2]).toFloat(),
    )

    private fun linearize(v: Double) = if (v <= 0.04045) v / 12.92 else ((v + 0.055) / 1.055).pow(2.4)
    private fun delinearize(v: Double): Double {
        val c = v.coerceIn(0.0, 1.0)
        return if (c <= 0.0031308) 12.92 * c else 1.055 * c.pow(1 / 2.4) - 0.055
    }
    private fun labF(t: Double) = if (t > EPSILON) cbrt(t) else (KAPPA * t + 16) / 116
    private fun labFInv(f: Double): Double { val f3 = f * f * f; return if (f3 > EPSILON) f3 else (116 * f - 16) / KAPPA }
}

/** M3-Tonal-Palette: ein Farbton, ein Chroma, Töne 0…100. */
class TonalPalette(val hue: Double, val chroma: Double) {
    fun tone(t: Double): Color = TonalColor.fromLch(t, chroma, hue)
    fun tone(t: Int): Color = tone(t.toDouble())
}

/**
 * Material-3-ColorScheme aus dem abstand-Akzent („Fidelity“): der Akzent bleibt exakt `primary`
 * (Nutzerwahl wie iOS), alle übrigen Rollen kommen aus Tonal-Paletten nach den M3-Tonstufen
 * (Primary/Secondary/Tertiary/Neutral/Neutral-Variant, Surface-Container-Leiter 4…22 bzw. 87…100).
 * Error-Rollen sind die M3-Baseline-Werte. Tabelle: `android/UI_TEMPLATES.txt` → „Material 3 colors“.
 */
object MaterialScheme {
    /** Chroma der Nebenpaletten (CIELAB-Einheiten, entspricht etwa den M3-TonalSpot-Werten). */
    const val primaryMinChroma = 36.0
    const val secondaryChroma = 16.0
    const val tertiaryChroma = 24.0
    const val tertiaryHueShift = 60.0
    const val neutralChroma = 4.0
    const val neutralVariantChroma = 8.0
    /** Unterhalb gilt der Akzent als Grau → alle Paletten neutral (kein erfundener Farbton). */
    const val achromaticThreshold = 5.0

    data class Palettes(
        val primary: TonalPalette,
        val secondary: TonalPalette,
        val tertiary: TonalPalette,
        val neutral: TonalPalette,
        val neutralVariant: TonalPalette,
    )

    fun palettes(seed: Color): Palettes {
        val lch = TonalColor.toLch(seed)
        val gray = lch.c < achromaticThreshold
        val h = lch.h
        fun c(v: Double) = if (gray) 0.0 else v
        return Palettes(
            primary = TonalPalette(h, if (gray) lch.c else max(lch.c, primaryMinChroma)),
            secondary = TonalPalette(h, c(secondaryChroma)),
            tertiary = TonalPalette((h + tertiaryHueShift) % 360, c(tertiaryChroma)),
            neutral = TonalPalette(h, c(neutralChroma)),
            neutralVariant = TonalPalette(h, c(neutralVariantChroma)),
        )
    }

    /** [onSeed] = lesbare Schrift auf dem Akzent (iOS-Regel `foregroundOnAccent`). */
    fun from(seed: Color, isDark: Boolean, onSeed: Color): ColorScheme {
        val p = palettes(seed)
        val n = p.neutral
        val nv = p.neutralVariant
        return if (isDark) darkColorScheme(
            primary = seed, onPrimary = onSeed,
            primaryContainer = p.primary.tone(30), onPrimaryContainer = p.primary.tone(90),
            inversePrimary = p.primary.tone(40),
            secondary = p.secondary.tone(80), onSecondary = p.secondary.tone(20),
            secondaryContainer = p.secondary.tone(30), onSecondaryContainer = p.secondary.tone(90),
            tertiary = p.tertiary.tone(80), onTertiary = p.tertiary.tone(20),
            tertiaryContainer = p.tertiary.tone(30), onTertiaryContainer = p.tertiary.tone(90),
            background = n.tone(6), onBackground = n.tone(90),
            surface = n.tone(6), onSurface = n.tone(90),
            surfaceVariant = nv.tone(30), onSurfaceVariant = nv.tone(80),
            surfaceTint = seed,
            inverseSurface = n.tone(90), inverseOnSurface = n.tone(20),
            error = Color(0xFFFFB4AB), onError = Color(0xFF690005),
            errorContainer = Color(0xFF93000A), onErrorContainer = Color(0xFFFFDAD6),
            outline = nv.tone(60), outlineVariant = nv.tone(30), scrim = Color.Black,
            surfaceBright = n.tone(24), surfaceDim = n.tone(6),
            surfaceContainerLowest = n.tone(4), surfaceContainerLow = n.tone(10),
            surfaceContainer = n.tone(12), surfaceContainerHigh = n.tone(17),
            surfaceContainerHighest = n.tone(22),
        ) else lightColorScheme(
            primary = seed, onPrimary = onSeed,
            primaryContainer = p.primary.tone(90), onPrimaryContainer = p.primary.tone(10),
            inversePrimary = p.primary.tone(80),
            secondary = p.secondary.tone(40), onSecondary = p.secondary.tone(100),
            secondaryContainer = p.secondary.tone(90), onSecondaryContainer = p.secondary.tone(10),
            tertiary = p.tertiary.tone(40), onTertiary = p.tertiary.tone(100),
            tertiaryContainer = p.tertiary.tone(90), onTertiaryContainer = p.tertiary.tone(10),
            background = n.tone(98), onBackground = n.tone(10),
            surface = n.tone(98), onSurface = n.tone(10),
            surfaceVariant = nv.tone(90), onSurfaceVariant = nv.tone(30),
            surfaceTint = seed,
            inverseSurface = n.tone(20), inverseOnSurface = n.tone(95),
            error = Color(0xFFBA1A1A), onError = Color.White,
            errorContainer = Color(0xFFFFDAD6), onErrorContainer = Color(0xFF410002),
            outline = nv.tone(50), outlineVariant = nv.tone(80), scrim = Color.Black,
            surfaceBright = n.tone(98), surfaceDim = n.tone(87),
            surfaceContainerLowest = n.tone(100), surfaceContainerLow = n.tone(96),
            surfaceContainer = n.tone(94), surfaceContainerHigh = n.tone(92),
            surfaceContainerHighest = n.tone(90),
        )
    }
}
