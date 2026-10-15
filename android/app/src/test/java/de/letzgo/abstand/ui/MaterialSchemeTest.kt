package de.letzgo.abstand.ui

import androidx.compose.material3.ColorScheme
import androidx.compose.ui.graphics.Color
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Prüft das Material-3-Schema aus dem Akzent ([MaterialScheme], [TonalColor]). */
class MaterialSchemeTest {
    private fun contrast(a: Color, b: Color): Double {
        fun lum(c: Color) = AppColorPalette.relativeLuminance(c.red.toDouble(), c.green.toDouble(), c.blue.toDouble())
        val (hi, lo) = lum(a).coerceAtLeast(lum(b)) to lum(a).coerceAtMost(lum(b))
        return (hi + 0.05) / (lo + 0.05)
    }

    private val darkScheme: ColorScheme get() = AppColorPalette.derived(AppTheme.defaultAccent, true).scheme
    private val lightScheme: ColorScheme get() = AppColorPalette.derived(AppTheme.defaultLightAccent, false).scheme

    @Test fun lchRoundTrip() {
        val c = TonalColor.fromLch(50.0, 30.0, 120.0)
        val lch = TonalColor.toLch(c)
        assertEquals(50.0, lch.l, 1.0)
        assertEquals(30.0, lch.c, 1.5)
        assertEquals(120.0, lch.h, 2.0)
    }

    @Test fun paletteHitsTonesInsideGamut() {
        val palette = MaterialScheme.palettes(AppTheme.defaultAccent).primary
        for (t in listOf(0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 99, 100)) {
            assertEquals("tone $t", t.toDouble(), TonalColor.tone(palette.tone(t)), 1.0)
        }
        assertEquals(Color.White, palette.tone(100))
    }

    @Test fun accentStaysPrimary() {
        assertEquals(AppTheme.defaultAccent, darkScheme.primary)
        assertEquals(AppTheme.defaultLightAccent, lightScheme.primary)
        assertEquals(AppTheme.defaultAccent, darkScheme.surfaceTint)
    }

    @Test fun surfaceContainerLadder() {
        val d = darkScheme
        val dark = listOf(d.surfaceContainerLowest, d.surfaceContainerLow, d.surfaceContainer, d.surfaceContainerHigh, d.surfaceContainerHighest)
            .map(TonalColor::tone)
        assertEquals(dark.sorted(), dark)
        val l = lightScheme
        val light = listOf(l.surfaceContainerLowest, l.surfaceContainerLow, l.surfaceContainer, l.surfaceContainerHigh, l.surfaceContainerHighest)
            .map(TonalColor::tone)
        assertEquals(light.sortedDescending(), light)
    }

    @Test fun textContrastMeetsWcag() {
        for (s in listOf(darkScheme, lightScheme)) {
            assertTrue(contrast(s.onSurface, s.surface) >= 7.0)
            assertTrue(contrast(s.onSurfaceVariant, s.surfaceContainerHigh) >= 4.5)
            assertTrue(contrast(s.onSecondaryContainer, s.secondaryContainer) >= 4.5)
            assertTrue(contrast(s.onPrimaryContainer, s.primaryContainer) >= 4.5)
            assertTrue(contrast(s.onPrimary, s.primary) >= 4.5)
            assertTrue(contrast(s.outline, s.surface) >= 3.0)
        }
    }

    @Test fun grayAccentGivesNeutralPalettes() {
        val p = MaterialScheme.palettes(Color(0.5f, 0.5f, 0.5f))
        assertEquals(0.0, p.secondary.chroma, 0.0)
        assertEquals(0.0, p.tertiary.chroma, 0.0)
        assertEquals(0.0, p.neutral.chroma, 0.0)
    }
}
