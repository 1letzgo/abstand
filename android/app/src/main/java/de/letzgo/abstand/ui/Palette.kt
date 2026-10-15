package de.letzgo.abstand.ui

import androidx.compose.material3.ColorScheme
import androidx.compose.ui.graphics.Color
import java.util.Locale
import kotlin.math.abs
import kotlin.math.pow

// Reine Farb-Logik ohne Compose-Runtime/Prefs — per JUnit testbar (AppearanceColorTest).

/** iOS: `AppearanceMode` — gleiche Raw-Values unter `abstand_appearance_mode`, Standard `.dark`. */
enum class AppearanceMode(val raw: String, val label: String) {
    Dark("dark", "Dark"),
    Light("light", "Light"),
    System("system", "System");

    /** iOS: `AppColorPalette.palette(for:system:accent:)` — Auflösung von `.system`. */
    fun isDarkLike(systemDark: Boolean): Boolean = when (this) {
        Dark -> true
        Light -> false
        System -> systemDark
    }

    companion object {
        /** iOS: `AppearanceMode.load(from:)` — unbekannt/fehlend → `.dark`. */
        fun fromRaw(raw: String?): AppearanceMode = entries.firstOrNull { it.raw == raw } ?: Dark
    }
}

/** iOS: `AppearanceAccentSlot` — Akzent pro Paletten-Familie; System nutzt aufgelöst Dark oder Light. */
enum class AppearanceAccentSlot(val prefsKey: String) {
    Dark("abstand_appearance_accent_rgb_dark"),
    Light("abstand_appearance_accent_rgb_light");

    /** iOS: `defaultAccent`. */
    val defaultAccent: Color get() = if (this == Dark) AppTheme.defaultAccent else AppTheme.defaultLightAccent

    companion object {
        /** iOS: `AppearanceAccentSlot.slot(for:system:)`. */
        fun slotFor(mode: AppearanceMode, systemDark: Boolean): AppearanceAccentSlot =
            if (mode.isDarkLike(systemDark)) Dark else Light
    }
}

/** sRGB-Komponenten 0…1 (iOS: `(r: Double, g: Double, b: Double)`-Tupel). */
data class Rgb(val r: Double, val g: Double, val b: Double) {
    fun toColor(alpha: Float = 1f): Color = Color(
        r.coerceIn(0.0, 1.0).toFloat(), g.coerceIn(0.0, 1.0).toFloat(), b.coerceIn(0.0, 1.0).toFloat(), alpha,
    )

    companion object {
        /** iOS: `rgbComponents(from:)` — Compose-Farben sind immer sRGB, daher nie `nil`. */
        fun of(color: Color): Rgb = Rgb(color.red.toDouble(), color.green.toDouble(), color.blue.toDouble())
    }
}

/** iOS: `AppearanceStore` (reiner Teil) — Format „r,g,b“ (0…1, vier Nachkommastellen). */
object AccentRgbCodec {
    /** iOS: `persistAccentColor` — `String(format: "%.4f,%.4f,%.4f", …)`; POSIX-Punkt statt Locale-Komma. */
    fun format(color: Color): String {
        val c = Rgb.of(color)
        return String.format(Locale.US, "%.4f,%.4f,%.4f", c.r, c.g, c.b)
    }

    /** iOS: `color(fromAccentRGBString:)` — genau drei parsebare Zahlen, sonst `null`. */
    fun parse(raw: String): Color? {
        val parts = raw.split(',').mapNotNull { it.trim().toDoubleOrNull() }
        if (parts.size != 3) return null
        // iOS akzeptiert Extended-sRGB; Compose wirft außerhalb 0…1 → kappen.
        return Rgb(parts[0], parts[1], parts[2]).toColor()
    }

    /** iOS: `accentColorsEqual` — Toleranz 0,002 je Kanal. */
    fun equal(lhs: Color, rhs: Color): Boolean {
        val a = Rgb.of(lhs)
        val b = Rgb.of(rhs)
        val eps = 0.002
        return abs(a.r - b.r) < eps && abs(a.g - b.g) < eps && abs(a.b - b.b) < eps
    }
}

/**
 * iOS: `AppColorPalette` — UI-Farben unter iOS-Namen. Android: abgeleitet aus dem Material-3-
 * [scheme] ([MaterialScheme.from], Akzent = Seed und exakt `primary`; oder Dynamic Color):
 * `background` = surface, `card` = surfaceContainerHigh, `textPrimary` = onSurface,
 * `textSecondary` = onSurfaceVariant, `progressTrack` = secondaryContainer. Dark nutzt damit
 * getönte M3-Flächen statt der festen iOS-Grautöne (#353535 / #454545).
 */
data class AppColorPalette(
    val isDarkLike: Boolean,
    val background: Color,
    val card: Color,
    val textPrimary: Color,
    val textSecondary: Color,
    /** Fortschritts-/Slider-Track (M3: secondaryContainer). */
    val progressTrack: Color,
    /** Schatten unter Hero-Karten (Continue Listening). */
    val heroCardShadow: Color,
    /** Schatten für Listen- und Gruppen-Karten. */
    val cardShadow: Color,
    /** Play-/Read-Badge auf Cover-Thumbnails (Library-Zeilen). */
    val coverPlayBadgeBackground: Color,
    /** Vollständiges Material-3-Farbschema (alle Rollen inkl. Surface-Container-Leiter). */
    val scheme: ColorScheme,
) {
    /** iOS: `foregroundOnAccent(_:)` — lesbare Schrift auf voller Akzentfläche. */
    fun foregroundOnAccent(accent: Color): Color = onAccent(accent, isDarkLike, textPrimary)

    /** iOS: `readableTextOnTintedCard(_:)` — (primär, sekundär) auf Cover-getönten Karten. */
    fun readableTextOnTintedCard(tint: Color): Pair<Color, Color> {
        val c = Rgb.of(tint)
        return if (relativeLuminance(c.r, c.g, c.b) > 0.48) {
            // Helle/kräftige Tönung → dunkle Schrift.
            rgb255(22, 22, 24) to rgb255(70, 70, 78)
        } else {
            // Dunkle Tönung → helle Schrift (sekundär etwas weicher).
            Color.White to Color.White.copy(alpha = 0.78f)
        }
    }

    companion object {
        private val darkOnAccent = rgb255(42, 32, 24)

        /** iOS-Regel `foregroundOnAccent`: helle Akzente (Luminanz > 0,55) bekommen dunkle Schrift. */
        fun onAccent(accent: Color, isDarkLike: Boolean, textPrimary: Color): Color {
            val c = Rgb.of(accent)
            if (relativeLuminance(c.r, c.g, c.b) > 0.55) {
                return if (isDarkLike) darkOnAccent else textPrimary
            }
            return Color.White
        }

        /** iOS: `palette(for:system:accent:)`. */
        fun palette(mode: AppearanceMode, systemDark: Boolean, accent: Color): AppColorPalette =
            derived(accent, mode.isDarkLike(systemDark))

        /** iOS: `derived(from:isDarkLike:)` — Android: M3-Schema aus dem Akzent als Seed. */
        fun derived(accent: Color, isDarkLike: Boolean): AppColorPalette {
            val textPrimary = MaterialScheme.palettes(accent).neutral.tone(if (isDarkLike) 90 else 10)
            val onSeed = onAccent(accent, isDarkLike, textPrimary)
            return fromScheme(MaterialScheme.from(accent, isDarkLike, onSeed), isDarkLike)
        }

        /** Palette aus einem fertigen M3-Schema (Seed-Schema oder Dynamic Color). */
        fun fromScheme(scheme: ColorScheme, isDarkLike: Boolean): AppColorPalette = AppColorPalette(
            isDarkLike = isDarkLike,
            background = scheme.surface,
            card = scheme.surfaceContainerHigh,
            textPrimary = scheme.onSurface,
            textSecondary = scheme.onSurfaceVariant,
            progressTrack = scheme.secondaryContainer,
            heroCardShadow = Color.Black.copy(alpha = if (isDarkLike) 0.32f else 0.1f),
            cardShadow = Color.Black.copy(alpha = if (isDarkLike) 0.36f else 0.1f),
            coverPlayBadgeBackground = Color(0.38f, 0.38f, 0.38f, 0.88f),
            scheme = scheme,
        )

        /** iOS: `mix(base:accent:accentWeight:)`. */
        fun mix(base: Rgb, accent: Rgb, accentWeight: Double): Color {
            val w = accentWeight.coerceIn(0.0, 1.0)
            val inv = 1 - w
            return Rgb(base.r * inv + accent.r * w, base.g * inv + accent.g * w, base.b * inv + accent.b * w).toColor()
        }

        /** iOS: `relativeLuminance` — WCAG-Luminanz (sRGB), 0…1. */
        fun relativeLuminance(r: Double, g: Double, b: Double): Double {
            fun channel(v: Double) = if (v <= 0.03928) v / 12.92 else ((v + 0.055) / 1.055).pow(2.4)
            return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
        }

        /** `Color(red: x / 255, …)` der iOS-Quelle. */
        fun rgb255(r: Int, g: Int, b: Int): Color = Color(r / 255f, g / 255f, b / 255f)
    }
}
