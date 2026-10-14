package de.letzgo.abstand.ui

import android.app.Activity
import androidx.compose.animation.core.SpringSpec
import androidx.compose.animation.core.spring
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat
import de.letzgo.abstand.data.Keys
import de.letzgo.abstand.data.Prefs
import kotlin.math.PI
import kotlin.math.ceil

/**
 * iOS: `AppTheme` — zentrale Farben und Abstände. Werte 1:1 aus AppTheme.swift (pt → dp).
 * Farben in Views **nicht** von hier, sondern über [Theme.palette] / [Theme.accent] lesen
 * (die statischen iOS-Felder `AppTheme.card/textPrimary/…` haben hier kein Gegenstück).
 */
object AppTheme {
    /** Dark-Mode-Akzent (Standard Gelb 251,192,45). */
    val defaultAccent = Color(251 / 255f, 192 / 255f, 45 / 255f)
    /** Light-Mode-Akzent (Standard #00374A). */
    val defaultLightAccent = Color(0 / 255f, 55 / 255f, 74 / 255f)
    /** iOS: `AppTheme.danger` (0.92, 0.32, 0.32). */
    val danger = Color(0.92f, 0.32f, 0.32f)
    /** iOS: `AppTheme.success` (0.35, 0.82, 0.55). */
    val success = Color(0.35f, 0.82f, 0.55f)
    /** Warnfarbe — iOS nutzt dafür System-Orange (`.orange`, dunkle Variante #FF9F0A). */
    val warning = Color(0xFFFF9F0A)
    /**
     * Schrift/Symbole auf Cover-Overlays (dunkle Pillen, Scrims) — bewusst Weiß und
     * paletten-unabhängig (iOS: `.foregroundStyle(.white)` auf `coverPlayBadgeBackground`).
     */
    val coverOverlayForeground = Color.White
    /** iOS: Vorlese-Markierung im eBook (System-Gelb #FFCC00), unabhängig von Palette/Akzent. */
    val narrationHighlight = Color(0xFFFFCC00)

    /**
     * iOS: `coverScrimGradient` — Lesbarkeits-Scrim am Cover-Fuß, bewusst hart schwarz und
     * paletten-unabhängig. Läuft von unten (45 % Schwarz) nach oben (transparent); Höhe setzt
     * die Aufrufstelle (typisch [Layout.coverScrimHeight]).
     */
    val coverScrimGradient: Brush = Brush.verticalGradient(
        0f to Color.Black.copy(alpha = 0f),
        1f to Color.Black.copy(alpha = 0.45f),
    )

    /** iOS: `AppTheme.CardElevation` — Schatten-Metriken (Farbe aus [AppColorPalette]). */
    enum class CardElevation(val radius: Dp, val y: Dp) {
        /** Browse-Icon-Kacheln, kleine Chips. */
        Subtle(Layout.cardShadowRadiusSubtle, Layout.cardShadowYSubtle),
        /** Library-Zeilen, Achievements, Stats-Karten. */
        Standard(Layout.cardShadowRadius, Layout.cardShadowY),
        /** Continue-Hero-Karten. */
        Hero(Layout.heroCardShadowRadius, Layout.heroCardShadowY);

        /**
         * Android-Schatten kennt nur eine Höhe statt Radius + y-Versatz → Material-Elevation-Stufen
         * (Level 1/2/3 = 1/3/6 dp), optisch am nächsten an den iOS-Schatten.
         */
        val shadowElevation: Dp get() = when (this) {
            Subtle -> 1.dp
            Standard -> 3.dp
            Hero -> 6.dp
        }
    }

    /** iOS: `AppTheme.ExpandingDock` — Home-Browse „Expanding Dock“. */
    object ExpandingDock {
        const val inactiveIconOpacity = 0.72f
        val itemSpacing = 10.dp
        val horizontalPadding = 18.dp
        val verticalPadding = 4.dp
        val circleSize = 46.dp
        val iconSize = 21.dp
        val activeCoverSize = 28.dp
        val activeHeight = 46.dp
        val activeLeadingPadding = 14.dp
        val activeTrailingPadding = 18.dp
        val iconLabelSpacing = 9.dp
        const val centerWhenFewThreshold = 4
        /** Überblendung am fixierten ersten Chip; zugleich Abstand zum ersten scrollenden Chip. */
        val pinnedChipFadeWidth = 12.dp
        /** Zweiseitiger Media-Kind-Umschalter (Audiobooks ↔ Podcasts) in der Library-Leiste. */
        val binarySwitchInnerPadding = 4.dp
        val binarySwitchSegmentWidth = 42.dp
        /** iOS: `.spring(response: 0.32, dampingFraction: 0.72)` → Steifigkeit (2π/response)². */
        val selectionAnimation: SpringSpec<Float> =
            spring(dampingRatio = 0.72f, stiffness = ((2 * PI / 0.32) * (2 * PI / 0.32)).toFloat())
        val inactiveIconSideInset: Dp get() = (circleSize - iconSize) / 2

        /** iOS: `ExpandingDock.Colors` — theme-abhängige Dock-Farben. */
        data class Colors(
            val activeBackground: Color,
            val activeForeground: Color,
            val inactiveBackground: Color,
            val inactiveForeground: Color,
            val activeShadow: Color,
        ) {
            companion object {
                fun of(palette: AppColorPalette, accent: Color, inactiveBackground: Color? = null) = Colors(
                    activeBackground = accent,
                    activeForeground = palette.foregroundOnAccent(accent),
                    inactiveBackground = inactiveBackground ?: palette.card,
                    inactiveForeground = palette.textSecondary,
                    activeShadow = palette.cardShadow,
                )
            }
        }
    }

    /** iOS: `AppTheme.Layout` — Raster für Tabs, Listen und Karten. Namen und Werte identisch. */
    object Layout {
        /** Tab-Inhalt horizontal. */
        val tabPaddingH = 16.dp
        /** Abstand von der oberen Safe Area zum ersten fixen Element. */
        val tabPaddingTop = 16.dp
        /** Abstand unter dem Großtitel zur nächsten Kopfzeile. */
        val tabTitleToHeaderBlockSpacing = 16.dp
        /** Zwischen Hauptblöcken (Regale, Suchbereich ↔ Liste). */
        val sectionSpacing = 22.dp
        /** Home-Dashboard: Abstand zwischen Kategorie-Regalen. */
        val homeSectionSpacing = 32.dp
        /** Kategoriezeile ↔ erste Zeile / Karten innerhalb eines Blocks. */
        val withinSectionSpacing = 10.dp

        // Basis-Abstände: rowSpacing (Icon ↔ Text), stackSpacing (untereinander), tightSpacing (Titel ↔ Untertitel).
        /** Horizontal in einer Zeile: Icon/Cover ↔ Textspalte ↔ Trailing-Control. */
        val rowSpacing = 12.dp
        /** Vertikal zwischen eng zusammengehörigen Elementen. */
        val stackSpacing = 8.dp
        /** Horizontal zwischen eng zusammengehörigen Elementen einer Zeile (Status + Text). */
        val inlineSpacing = 8.dp
        /** Titel ↔ direkt zugehöriger Untertitel/Wert. */
        val tightSpacing = 4.dp
        /** Kleinster Abstand: Badge-Innenabstand, Icon ↔ Zahl. */
        val hairlineSpacing = 2.dp
        /** Chips, Pills, kompakte Meta-Zeilen. */
        val compactSpacing = 6.dp
        /** Innenabstand von Karten (rundum). */
        val cardPadding = 14.dp
        /** Standard-Innenabstand von Screens/Sheets außerhalb der Tab-Roots. */
        val screenPadding = 16.dp
        /** Großer Abstand zwischen unabhängigen Blöcken in Sheets/Overlays. */
        val blockSpacing = 24.dp
        /** Haarlinien-Versatz (Trenner). */
        val hairlineWidth = 1.dp
        /** Dünne Konturlinie (Karten-/Kreis-Umrandung). */
        val hairlineStrokeWidth = 0.5.dp
        /** Kräftigere Konturlinie (aktiver Zustand). */
        val boldStrokeWidth = 2.dp
        /** Abstand/Innenabstand in Mini-Badges und Legenden-Punkten. */
        val badgeSpacing = 3.dp
        /** Vertikaler Innenabstand von Pills auf Covern. */
        val pillVerticalPadding = 5.dp
        /** Innenabstand von Overlay-Karten über Vollbild-Inhalten. */
        val overlayPadding = 20.dp
        /** Horizontaler Außenabstand modaler Popups. */
        val modalHorizontalPadding = 28.dp
        /** Vertikaler Innenabstand ganzseitiger Lade-/Leerzustände. */
        val loadingVerticalPadding = 48.dp

        // Feste Maße
        /** Mindestgröße für Touch-Ziele; auch quadratische Cover-Thumbs in Zeilen. */
        val minTapTarget = 44.dp
        /** Runde Icon-Buttons im Overlay-Chrome. */
        val iconButtonSize = 40.dp
        /** Kompakte Icon-Buttons / Breite kleiner Download-Fortschrittsbalken. */
        val compactIconButtonSize = 36.dp
        /** Icon-Spalte in kompakten Zeilen. */
        val compactIconColumnWidth = 22.dp
        /** Kreis-Badges auf Covern (Play, eBook). */
        val coverBadgeSize = 18.dp
        /** Höhe des Gradient-Scrims am Cover-Fuß. */
        val coverScrimHeight = 72.dp
        /** Label-Spalte in Meta-Zeilen. */
        val metaLabelColumnWidth = 112.dp
        /** Trailing-Wertespalte in Meta-/Aktionszeilen. */
        val metaValueColumnMinWidth = 88.dp
        /** Vertikaler Innenabstand einer Inhaltszeile ohne Kartenrahmen. */
        val rowVerticalPadding = 8.dp
        /** Icon-Spalte in Settings-/Admin-Kartenzeilen. */
        val settingsIconColumnWidth = 28.dp
        /** Leerzustand innerhalb eines Scroll-Bereichs (vertikal). */
        val emptyStateVerticalPadding = 32.dp
        /** Detail: Titelblock → Play. */
        val detailPlayButtonTopPadding = 10.dp
        /** Detail: Play → Metadaten. */
        val detailPlayButtonBottomPadding = 12.dp
        /** Detail: Play → erster Meta-Block. */
        val detailMetaAfterPlaySpacing = 18.dp
        /** Innenabstand Detail-Sektionskarten. */
        val detailSectionCardPadding = 14.dp
        val detailSectionCardCornerRadius = 12.dp
        /** Zusatz unter Scroll-Inhalten vor dem Mini-Player ([LocalScrollBottomInset] kommt dazu). */
        val scrollBottomInsetBase = 24.dp

        /** Kompakte Kachel in der Podcast-„Shows“-Leiste. */
        val podcastShelfCoverCorner = 12.dp
        /** Textfelder, Suchfeld-Chrome und kleine Control-Karten. */
        val fieldCornerRadius = podcastShelfCoverCorner
        /** Kleine Cover-Thumbs / Chips in Metadata-Sheets. */
        val chipCornerRadius = 6.dp
        /** Reader-Chrome-Hinweis. */
        val readerChromeCornerRadius = 20.dp
        /** Level-Badge auf Achievement-Karten. */
        val achievementBadgeCornerRadius = 10.dp

        /** Abstand Strip ↔ Großtitel oben. */
        val horizontalBrowseStripToTitleSpacing = 4.dp
        /** Abstand Strip ↔ Scroll-Inhalt unten. */
        val horizontalBrowseStripToContentSpacing = 10.dp
        val horizontalBrowseStripVerticalPadding = 4.dp

        /** „Continue listening“-Karten. */
        val continueHeroCardCornerRadius = 16.dp
        /** Fallback-Breite, bis die Viewport-Messung steht. */
        val continueHeroCardWidth = 176.dp
        /** Compact (Phone): 1½ Karten sichtbar. */
        const val continueHeroVisibleCardsCompact = 1.5f
        /** Regular (Tablet): Basis + 2 zusätzliche sichtbare Karten. */
        const val homeCarouselRegularVisibleCardsBonus = 2f
        val continueHeroCardMinWidth = 140.dp
        val continueHeroCardMaxWidth = 220.dp
        val continueHeroCoverMaxHeight = 176.dp

        /** Home-Regale (Cover-Cards, Maß von „New episodes“): Compact 2¼, Regular +2. */
        const val homeNewestEpisodesVisibleCardsCompact = 2.25f
        val homeNewestEpisodesCardMinWidth = 120.dp
        val homeNewestEpisodesCardMaxWidth = 220.dp
        val homeNewestEpisodesCardFallbackWidth = 160.dp

        /** Home-Kompaktkarten (alle Regale außer „Continue listening“): ~3/4 der Regalbreite. */
        const val homeCompactCardWidthFraction = 3f / 4f
        val homeCompactCardMinWidth = 240.dp
        val homeCompactCardMaxWidth = 400.dp
        val homeCompactCardFallbackWidth = 260.dp
        /** Cover-Seite der Home-Kompaktkarten. */
        val homeCompactCardCoverSide = 80.dp

        /** Abstand Titel ↔ Autor/Show. */
        val continueHeroMetadataTitleDetailSpacing = 2.dp
        val continueHeroMetadataVerticalPadding = 8.dp
        /** Genau zwei Zeilen `headline`. */
        val continueHeroMetadataTitleFixedHeight = 44.dp
        /** Eine Zeile `.footnote` für Autor/Show. */
        val continueHeroMetadataDetailFixedHeight = 20.dp
        val continueHeroMetadataPlayPillTopPadding = 8.dp
        val continueHeroMetadataPlayPillIntrinsicHeight = 34.dp
        val continueHeroMetadataExtraBottomPadding = 10.dp
        /** Fester Textblock unter dem Cover — alle Continue-Hero-Karten gleich hoch. */
        val continueHeroMetadataBlockHeight: Dp = continueHeroMetadataVerticalPadding +
            continueHeroMetadataTitleFixedHeight + continueHeroMetadataTitleDetailSpacing +
            continueHeroMetadataDetailFixedHeight + continueHeroMetadataPlayPillTopPadding +
            continueHeroMetadataPlayPillIntrinsicHeight + continueHeroMetadataExtraBottomPadding
        /** Gesamthöhe Continue-Hero-Karte. */
        val continueHeroCardTotalHeight: Dp = continueHeroCoverMaxHeight + continueHeroMetadataBlockHeight
        /** Metadaten unter dem Cover ohne Play-Pille. */
        val libraryHeroMetadataBlockHeight: Dp = continueHeroMetadataVerticalPadding +
            continueHeroMetadataTitleFixedHeight + continueHeroMetadataTitleDetailSpacing +
            continueHeroMetadataDetailFixedHeight + continueHeroMetadataExtraBottomPadding

        val cardCornerRadius = 14.dp
        /** Karten-Schatten (siehe [CardElevation]). */
        val cardShadowRadiusSubtle = 6.dp
        val cardShadowYSubtle = 2.dp
        val cardShadowRadius = 10.dp
        val cardShadowY = 4.dp
        val heroCardShadowRadius = 14.dp
        val heroCardShadowY = 6.dp
        /** Mindesthöhe für Zeilen in gruppierten Karten. */
        val listRowMinHeight = 50.dp
        /** Horizontaler Innenabstand in Settings-Karten. */
        val settingsCardInsetHPadding = 16.dp
        /** Vertikaler Innenabstand in Settings-Karten. */
        val settingsCardInsetVPadding = 8.dp
        /** Vertikaler Abstand um Trennlinien zwischen Settings-Zeilen. */
        val settingsCardDividerSpacing = 6.dp
        /** Library-Zeilen — gleiche Abrundung wie Browse-/Podcast-Icon-Kacheln. */
        val libraryRowCornerRadius = podcastShelfCoverCorner
        val coverCornerRadius = 11.dp

        /** Cover in Library-Zeilen: festes 1:1. */
        val libraryRowCoverSide = 100.dp
        /** Abstand Cover ↔ Textspalte in Library-Zeilen. */
        val libraryRowCardInset = 10.dp
        /** Titel oben / Laufzeit unten. */
        val libraryRowTextInset = 6.dp
        /** Höhe des Fortschrittsstreifens am unteren Kartenrand. */
        val libraryRowBottomProgressHeight = 4.dp

        /** Max. Breite für Formulare (Login, Sheets) auf großen Screens. */
        val readableFormMaxWidth = 480.dp
        /** Platzhalterhöhe für Home-Browse, bis Continue-Regale vorliegen. */
        val homeBrowseBootstrapMinHeight = 220.dp
        /** iOS: `facetTileGridColumns` (`GridItem(.adaptive(minimum: 160))`) → `GridCells.Adaptive(facetTileMinWidth)`. */
        val facetTileMinWidth = 160.dp

        /** iOS: `homeCompactCardWidth(forViewportWidth:)`. */
        fun homeCompactCardWidth(viewport: Dp): Dp {
            if (viewport <= 1.dp) return homeCompactCardFallbackWidth
            return (viewport * homeCompactCardWidthFraction).coerceIn(homeCompactCardMinWidth, homeCompactCardMaxWidth)
        }

        /** iOS: `continueHeroVisibleCards(horizontalSizeClass:)` — [isRegular] = iPad-/Tablet-Breite. */
        fun continueHeroVisibleCards(isRegular: Boolean): Float =
            homeCarouselVisibleCards(continueHeroVisibleCardsCompact, isRegular)

        /** iOS: `continueHeroCardWidth(forViewportWidth:horizontalSizeClass:)`. */
        fun continueHeroCardWidth(viewport: Dp, isRegular: Boolean = false): Dp = homeCarouselCardWidth(
            viewport, continueHeroVisibleCards(isRegular), continueHeroCardMinWidth, continueHeroCardMaxWidth,
            continueHeroCardWidth, isRegular,
        )

        fun homeNewestEpisodesVisibleCards(isRegular: Boolean): Float =
            homeCarouselVisibleCards(homeNewestEpisodesVisibleCardsCompact, isRegular)

        /** iOS: `homeNewestEpisodesCardWidth(forViewportWidth:horizontalSizeClass:)`. */
        fun homeNewestEpisodesCardWidth(viewport: Dp, isRegular: Boolean = false): Dp = homeCarouselCardWidth(
            viewport, homeNewestEpisodesVisibleCards(isRegular), homeNewestEpisodesCardMinWidth,
            homeNewestEpisodesCardMaxWidth, homeNewestEpisodesCardFallbackWidth, isRegular,
        )

        private fun homeCarouselVisibleCards(compact: Float, isRegular: Boolean): Float =
            if (isRegular) compact + homeCarouselRegularVisibleCardsBonus else compact

        /** `(Viewport − Gaps×Spacing) / sichtbare Karten`; Max-Breite nur auf Regular. */
        private fun homeCarouselCardWidth(
            viewport: Dp, visibleCards: Float, minWidth: Dp, maxWidth: Dp, fallback: Dp, isRegular: Boolean,
        ): Dp {
            val cards = maxOf(1f, visibleCards)
            if (viewport <= 0.dp) return fallback
            val gaps = maxOf(0f, ceil(cards) - 1)
            val ideal = maxOf(minWidth, (viewport - withinSectionSpacing * gaps) / cards)
            return if (isRegular) minOf(maxWidth, ideal) else ideal
        }
    }
}

/**
 * iOS: Appearance-Teil von `AppModel` (`appearanceMode`, `appearanceAccentColor`,
 * `setAppearanceAccentColor`, `resetAppearanceAccentToDefault`) + `AppearanceStore`.
 * Compose-State: jede Änderung rekomponiert alle Leser von [Theme.palette]/[Theme.accent]
 * (ersetzt `appearanceThemeRevision`). Akzent je Slot (Dark/Light) wie iOS.
 */
object Appearance {
    var mode by mutableStateOf(AppearanceMode.fromRaw(Prefs.string(Keys.appearanceMode)))
        private set
    var accentDark by mutableStateOf(Color.Unspecified)
        private set
    var accentLight by mutableStateOf(Color.Unspecified)
        private set

    init {
        migrateAccentKeysIfNeeded()
        accentDark = loadAccent(AppearanceAccentSlot.Dark)
        accentLight = loadAccent(AppearanceAccentSlot.Light)
    }

    /** iOS: `appearanceMode.didSet` → `persist()`. */
    fun updateMode(value: AppearanceMode) {
        if (value == mode) return
        mode = value
        Prefs.setString(Keys.appearanceMode, value.raw)
    }

    /** Akzent des Slots, der für [systemDark] gerade aktiv ist. */
    fun accent(systemDark: Boolean): Color = accentFor(AppearanceAccentSlot.slotFor(mode, systemDark))

    fun accentFor(slot: AppearanceAccentSlot): Color =
        if (slot == AppearanceAccentSlot.Dark) accentDark else accentLight

    /** iOS: `setAppearanceAccentColor(_:)` — schreibt in den aktuell aufgelösten Slot. */
    fun updateAccent(color: Color, systemDark: Boolean) {
        val slot = AppearanceAccentSlot.slotFor(mode, systemDark)
        if (AccentRgbCodec.equal(color, accentFor(slot))) return
        if (slot == AppearanceAccentSlot.Dark) accentDark = color else accentLight = color
        Prefs.setString(slot.prefsKey, AccentRgbCodec.format(color))
    }

    /** iOS: `resetAppearanceAccentToDefault()`. */
    fun resetAccentToDefault(systemDark: Boolean) {
        updateAccent(AppearanceAccentSlot.slotFor(mode, systemDark).defaultAccent, systemDark)
    }

    /** iOS: `appearanceAccentMatchesDefault`. */
    fun accentMatchesDefault(systemDark: Boolean): Boolean {
        val slot = AppearanceAccentSlot.slotFor(mode, systemDark)
        return AccentRgbCodec.equal(accentFor(slot), slot.defaultAccent)
    }

    /** iOS: `AppearanceStore.migrateAccentKeysIfNeeded()` — Legacy-Key → Dark-Slot, Light-Default schreiben. */
    private fun migrateAccentKeysIfNeeded() {
        if (Prefs.string(Keys.appearanceAccentRGBDark) == null) {
            val legacy = Prefs.string(Keys.appearanceAccentRGB)
            if (legacy != null && AccentRgbCodec.parse(legacy) != null) Prefs.setString(Keys.appearanceAccentRGBDark, legacy)
        }
        if (Prefs.string(Keys.appearanceAccentRGBLight) == null) {
            Prefs.setString(Keys.appearanceAccentRGBLight, AccentRgbCodec.format(AppTheme.defaultLightAccent))
        }
    }

    /** iOS: `AppearanceStore.loadAccentColor(slot:)`. */
    private fun loadAccent(slot: AppearanceAccentSlot): Color =
        Prefs.string(slot.prefsKey)?.let(AccentRgbCodec::parse) ?: slot.defaultAccent
}

/** Aufgelöste Appearance für den aktuellen Kompositions-Teilbaum (von [AbstandTheme] gesetzt). */
private data class ResolvedAppearance(val palette: AppColorPalette, val accent: Color, val systemDark: Boolean)

private val LocalResolvedAppearance = staticCompositionLocalOf {
    ResolvedAppearance(AppColorPalette.derived(AppTheme.defaultAccent, true), AppTheme.defaultAccent, true)
}

/**
 * Zusätzlicher Scroll-Abstand unten für den Mini-Player (iOS: `nowPlayingAccessoryScrollBottomInset`).
 * Setzt die Tab-Shell; Scaffolds addieren ihn zu [AppTheme.Layout.scrollBottomInsetBase].
 */
val LocalScrollBottomInset = compositionLocalOf { 0.dp }

/** iOS: `\.abstandCardShadowEnabled` — in horizontalen Reihen `false` (kein Schatten-„Streifen“). */
val LocalAbstandCardShadowEnabled = compositionLocalOf { true }

/** Zugriff auf Palette und Akzent in Composables (iOS: `model.appearancePalette`, `\.themeAccent`). */
object Theme {
    /** iOS: `model.appearancePalette`. */
    val palette: AppColorPalette
        @Composable get() = LocalResolvedAppearance.current.palette

    /** iOS: `model.appearanceAccentColor` / `\.themeAccent`. */
    val accent: Color
        @Composable get() = LocalResolvedAppearance.current.accent

    /** iOS: `palette.foregroundOnAccent(themeAccent)`. */
    val onAccent: Color
        @Composable get() = LocalResolvedAppearance.current.let { it.palette.foregroundOnAccent(it.accent) }

    /** System-Hell/Dunkel (für [Appearance.updateAccent] im System-Modus). */
    val systemDark: Boolean
        @Composable get() = LocalResolvedAppearance.current.systemDark
}

/**
 * iOS: `.preferredColorScheme` + `.tint` + `themeAccentFromAppModel` am Root. Baut das
 * Material-ColorScheme aus der abstand-Palette (Dark: feste Grauflächen, Light: akzentgetönt),
 * setzt die iOS-Typografie und die Statusleisten-Icons passend zum Modus.
 */
@Composable
fun AbstandTheme(content: @Composable () -> Unit) {
    val systemDark = isSystemInDarkTheme()
    val isDark = Appearance.mode.isDarkLike(systemDark)
    val accent = Appearance.accent(systemDark)
    val palette = AppColorPalette.derived(accent, isDark)
    val onAccent = palette.foregroundOnAccent(accent)
    val outline = palette.textSecondary.copy(alpha = 0.25f).compositeOver(palette.card)
    val accentContainer = accent.copy(alpha = 0.24f).compositeOver(palette.background)
    val scheme = if (isDark) darkColorScheme(
        primary = accent, onPrimary = onAccent, primaryContainer = accentContainer, onPrimaryContainer = palette.textPrimary,
        secondary = accent, onSecondary = onAccent, secondaryContainer = accentContainer, onSecondaryContainer = palette.textPrimary,
        tertiary = accent, onTertiary = onAccent,
        background = palette.background, onBackground = palette.textPrimary,
        surface = palette.background, onSurface = palette.textPrimary,
        surfaceVariant = palette.card, onSurfaceVariant = palette.textSecondary, surfaceTint = palette.card,
        surfaceContainerLowest = palette.background, surfaceContainerLow = palette.card, surfaceContainer = palette.card,
        surfaceContainerHigh = palette.card, surfaceContainerHighest = palette.card,
        inverseSurface = palette.textPrimary, inverseOnSurface = palette.background, inversePrimary = accent,
        error = AppTheme.danger, onError = Color.White, outline = outline, outlineVariant = outline,
    ) else lightColorScheme(
        primary = accent, onPrimary = onAccent, primaryContainer = accentContainer, onPrimaryContainer = palette.textPrimary,
        secondary = accent, onSecondary = onAccent, secondaryContainer = accentContainer, onSecondaryContainer = palette.textPrimary,
        tertiary = accent, onTertiary = onAccent,
        background = palette.background, onBackground = palette.textPrimary,
        surface = palette.background, onSurface = palette.textPrimary,
        surfaceVariant = palette.card, onSurfaceVariant = palette.textSecondary, surfaceTint = palette.card,
        surfaceContainerLowest = palette.background, surfaceContainerLow = palette.card, surfaceContainer = palette.card,
        surfaceContainerHigh = palette.card, surfaceContainerHighest = palette.card,
        inverseSurface = palette.textPrimary, inverseOnSurface = palette.background, inversePrimary = accent,
        error = AppTheme.danger, onError = Color.White, outline = outline, outlineVariant = outline,
    )

    // Statusleisten-/Navigationsleisten-Icons folgen dem App-Modus, nicht nur dem System.
    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as? Activity)?.window ?: return@SideEffect
            WindowCompat.getInsetsController(window, view).apply {
                isAppearanceLightStatusBars = !isDark
                isAppearanceLightNavigationBars = !isDark
            }
        }
    }

    CompositionLocalProvider(LocalResolvedAppearance provides ResolvedAppearance(palette, accent, systemDark)) {
        MaterialTheme(colorScheme = scheme, typography = IosType.material, content = content)
    }
}

