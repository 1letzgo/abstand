package de.letzgo.abstand.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Prüft die 1:1 aus AppAppearance.swift / AppearanceStore.swift portierte Farblogik. */
class AppearanceColorTest {
    // Compose speichert sRGB mit 8 Bit je Kanal → Toleranz eine halbe Stufe.
    private val eps = 0.5 / 255 + 1e-6

    private fun assertRgb(expected: Rgb, actual: Color) {
        val a = Rgb.of(actual)
        assertEquals("r", expected.r, a.r, eps)
        assertEquals("g", expected.g, a.g, eps)
        assertEquals("b", expected.b, a.b, eps)
    }

    @Test fun accentFormatMatchesSwiftFormat() {
        assertEquals("0.8784,0.3882,0.3098", AccentRgbCodec.format(AppTheme.defaultAccent))
        assertEquals("0.7020,0.1490,0.1176", AccentRgbCodec.format(AppTheme.defaultLightAccent))
    }

    @Test fun accentRoundTrip() {
        val colors = listOf(AppTheme.defaultAccent, AppTheme.defaultLightAccent, Color(0.1f, 0.5f, 0.9f), Color.White, Color.Black)
        for (c in colors) {
            val parsed = AccentRgbCodec.parse(AccentRgbCodec.format(c))
            assertNotNull(parsed)
            assertTrue(AccentRgbCodec.equal(c, parsed!!))
        }
    }

    @Test fun accentParseLikeSwift() {
        assertRgb(Rgb(0.25, 0.5, 0.75), AccentRgbCodec.parse(" 0.25 , 0.5,0.75 ")!!)
        assertNull(AccentRgbCodec.parse("0.1,0.2"))
        assertNull(AccentRgbCodec.parse("0.1,0.2,0.3,0.4"))
        assertNull(AccentRgbCodec.parse(""))
        // Nicht parsebare Teile fallen weg (Swift `compactMap`) — zählt nur, was übrig bleibt.
        assertNotNull(AccentRgbCodec.parse("0.1,x,0.2,0.3"))
        // Extended-sRGB-Werte werden gekappt statt zu werfen.
        assertRgb(Rgb(1.0, 0.0, 0.5), AccentRgbCodec.parse("1.2,-0.1,0.5")!!)
    }

    @Test fun accentEqualTolerance() {
        assertTrue(AccentRgbCodec.equal(Color(0.5f, 0.5f, 0.5f), Color(0.5f, 0.5f, 0.5f)))
        assertFalse(AccentRgbCodec.equal(Color(0.5f, 0.5f, 0.5f), Color(0.51f, 0.5f, 0.5f)))
    }

    @Test fun modeRawValues() {
        // Paper: Standard hell.
        assertEquals(AppearanceMode.Light, AppearanceMode.fromRaw(null))
        assertEquals(AppearanceMode.Light, AppearanceMode.fromRaw("sepia"))
        assertEquals(AppearanceMode.Light, AppearanceMode.fromRaw("light"))
        assertEquals(AppearanceMode.System, AppearanceMode.fromRaw("system"))
        assertEquals(AppearanceAccentSlot.Dark, AppearanceAccentSlot.slotFor(AppearanceMode.System, systemDark = true))
        assertEquals(AppearanceAccentSlot.Light, AppearanceAccentSlot.slotFor(AppearanceMode.System, systemDark = false))
        assertEquals(AppearanceAccentSlot.Dark, AppearanceAccentSlot.slotFor(AppearanceMode.Dark, systemDark = false))
        assertEquals("abstand_appearance_accent_rgb_dark", AppearanceAccentSlot.Dark.prefsKey)
        assertEquals("abstand_appearance_accent_rgb_light", AppearanceAccentSlot.Light.prefsKey)
    }

    /** Paper: feste Tinte-Flächen als M3-Rollen (Dark). */
    @Test fun darkPaletteUsesInkSurfaces() {
        val p = AppColorPalette.derived(AppTheme.defaultAccent, isDarkLike = true)
        assertTrue(p.isDarkLike)
        assertRgb(Rgb(27 / 255.0, 25 / 255.0, 21 / 255.0), p.background)
        assertRgb(Rgb(239 / 255.0, 232 / 255.0, 218 / 255.0), p.textPrimary)
        assertEquals(p.scheme.surface, p.background)
        assertEquals(p.scheme.surfaceContainerHigh, p.card)
        assertEquals(p.scheme.secondaryContainer, p.progressTrack)
        assertEquals(p.scheme.outlineVariant, p.rule)
        assertEquals(0.36f, p.cardShadow.alpha, 0.005f)
        assertEquals(0.32f, p.heroCardShadow.alpha, 0.005f)
    }

    /** Paper: warmes Papier mit Tinte (Light). */
    @Test fun lightPaletteUsesPaperSurfaces() {
        val p = AppColorPalette.derived(AppTheme.defaultLightAccent, isDarkLike = false)
        assertFalse(p.isDarkLike)
        assertRgb(Rgb(243 / 255.0, 238 / 255.0, 227 / 255.0), p.background)
        assertRgb(Rgb(31 / 255.0, 27 / 255.0, 22 / 255.0), p.textPrimary)
        assertEquals(0.1f, p.cardShadow.alpha, 0.005f)
    }

    @Test fun foregroundOnAccent() {
        val dark = AppColorPalette.derived(AppTheme.defaultAccent, true)
        val light = AppColorPalette.derived(AppTheme.defaultLightAccent, false)
        // Helle Akzente (Luminanz > 0,55) → dunkle Schrift; Zinnober ist dunkel genug → Weiß.
        val yellow = Color(251 / 255f, 192 / 255f, 45 / 255f)
        assertRgb(Rgb(42 / 255.0, 32 / 255.0, 24 / 255.0), dark.foregroundOnAccent(yellow))
        assertEquals(light.textPrimary, light.foregroundOnAccent(yellow))
        assertEquals(Color.White, light.foregroundOnAccent(AppTheme.defaultLightAccent))
        assertEquals(Color.White, dark.foregroundOnAccent(AppTheme.defaultAccent))
    }

    @Test fun relativeLuminance() {
        assertEquals(1.0, AppColorPalette.relativeLuminance(1.0, 1.0, 1.0), 1e-9)
        assertEquals(0.0, AppColorPalette.relativeLuminance(0.0, 0.0, 0.0), 1e-9)
        assertEquals(0.584, AppColorPalette.relativeLuminance(251 / 255.0, 192 / 255.0, 45 / 255.0), 0.005)
    }

    @Test fun readableTextOnTintedCard() {
        val p = AppColorPalette.derived(AppTheme.defaultAccent, true)
        val (primaryOnLight, _) = p.readableTextOnTintedCard(Color.White)
        assertRgb(Rgb(22 / 255.0, 22 / 255.0, 24 / 255.0), primaryOnLight)
        val (primaryOnDark, secondaryOnDark) = p.readableTextOnTintedCard(Color.Black)
        assertEquals(Color.White, primaryOnDark)
        assertEquals(0.78f, secondaryOnDark.alpha, 0.005f)
    }

    /** Android-Werte nach Material 3 (Namen wie iOS `AppTheme.Layout`, Tabelle in UI_TEMPLATES.txt). */
    @Test fun layoutTokensFollowMaterial3() {
        val l = AppTheme.Layout
        assertEquals(16.dp, l.rowSpacing)
        assertEquals(8.dp, l.stackSpacing)
        assertEquals(4.dp, l.tightSpacing)
        assertEquals(8.dp, l.withinSectionSpacing)
        assertEquals(24.dp, l.sectionSpacing)
        assertEquals(16.dp, l.cardPadding)
        assertEquals(16.dp, l.screenPadding)
        assertEquals(48.dp, l.minTapTarget)
        assertEquals(56.dp, l.listRowMinHeight)
        assertEquals(12.dp, l.cardCornerRadius)
        // 12 + 48 + 4 + 20 + 8 + 40 + 12
        assertEquals(144.dp, l.continueHeroMetadataBlockHeight)
        assertEquals(320.dp, l.continueHeroCardTotalHeight)
    }

    @Test fun carouselWidthsMatchIosFormula() {
        val l = AppTheme.Layout
        // Compact: (390 − 8·1) / 1.5 ≈ 254.67, keine Max-Kappe.
        assertEquals(254.67f, l.continueHeroCardWidth(390.dp).value, 0.01f)
        // Regular (+2 → 3.5 Karten): (1024 − 8·3) / 3.5 ≈ 285.7 → Kappe 220.
        assertEquals(220f, l.continueHeroCardWidth(1024.dp, isRegular = true).value, 0.01f)
        assertEquals(l.continueHeroCardWidth, l.continueHeroCardWidth(0.dp))
    }

    @Test fun playbackTimeFormatting() {
        assertEquals("0:00", formatPlaybackTime(-1.0))
        assertEquals("1:05", formatPlaybackTime(65.4))
        assertEquals("1:01:01", formatPlaybackTime(3661.0))
        assertEquals("< 1 min", formatPlaybackDurationShortHuman(59.0))
        assertEquals("1 hr 1 min", formatPlaybackDurationShortHuman(3660.0))
        assertEquals("2 hrs 15 min", formatPlaybackDurationShortHuman(8100.0))
    }
}
