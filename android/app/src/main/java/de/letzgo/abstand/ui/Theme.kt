package de.letzgo.abstand.ui

import android.app.Activity
import android.os.Build
import androidx.compose.animation.core.SpringSpec
import androidx.compose.animation.core.spring
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat
import de.letzgo.abstand.data.Keys
import de.letzgo.abstand.data.Prefs
import kotlin.math.PI
import kotlin.math.ceil

/**
 * iOS: `AppTheme` — zentrale Farben und Abstände. Farben 1:1 aus AppTheme.swift, Abstände mit iOS-Namen und Material-3-Werten ([Layout]).
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

    /**
     * iOS: `AppTheme.CardElevation` (Schatten-Radius + y-Versatz). Android: Material-3-Elevation-
     * Stufen, Schattenfarbe aus [AppColorPalette].
     */
    enum class CardElevation(val shadowElevation: Dp) {
        /** Browse-Icon-Kacheln, kleine Chips (M3: tonal, kein Schatten). */
        Subtle(0.dp),
        /** Library-Zeilen, Achievements, Stats-Karten (M3 Filled Card: Level 0, Tiefe über surfaceContainer). */
        Standard(0.dp),
        /** Continue-Hero-Karten (M3 Elevated Card: Level 1). */
        Hero(1.dp),
    }

    /**
     * iOS: `AppTheme.ExpandingDock` — Home-Browse „Expanding Dock“. Android: Maße eines M3-Chips
     * (40 dp hoch, 8-dp-Abstände, 20-dp-Symbol, 24-dp-Avatar) statt der iOS-Kapsel (46 pt).
     */
    object ExpandingDock {
        // Android: M3 Filter Chips (32 dp, 8-dp-Ecke, Label immer sichtbar) statt Kreis → Kapsel.
        const val inactiveIconOpacity = 1f
        val itemSpacing = 8.dp
        val horizontalPadding = 16.dp
        val verticalPadding = 4.dp
        val circleSize = 32.dp
        val iconSize = 18.dp
        val activeCoverSize = 24.dp
        /** Cover im nicht gewählten Chip (Podcast-Shows). */
        val inactiveCoverSize = 24.dp
        val activeHeight = 32.dp
        val activeLeadingPadding = 8.dp
        val activeTrailingPadding = 16.dp
        val iconLabelSpacing = 8.dp
        const val centerWhenFewThreshold = 4
        /** Überblendung am fixierten ersten Chip; zugleich Abstand zum ersten scrollenden Chip. */
        val pinnedChipFadeWidth = 12.dp
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
                /** M3 Filter Chip: gewählt secondaryContainer / onSecondaryContainer, sonst onSurfaceVariant. */
                @Suppress("UNUSED_PARAMETER")
                fun of(palette: AppColorPalette, accent: Color, inactiveBackground: Color? = null) = Colors(
                    activeBackground = palette.scheme.secondaryContainer,
                    activeForeground = palette.scheme.onSecondaryContainer,
                    inactiveBackground = inactiveBackground ?: palette.scheme.surfaceContainerLow,
                    inactiveForeground = palette.textSecondary,
                    activeShadow = Color.Transparent,
                )
            }
        }
    }

    /**
     * iOS: `AppTheme.Layout`. **Namen** wie iOS (Aufrufstellen bleiben lesbar und vergleichbar),
     * **Werte** nach Material 3: 4-dp-Raster, 16-dp-Rand (Compact) bzw. 24 dp ab Medium-Breite,
     * 48-dp-Touch-Ziele, Listenzeilen 56/72/88 dp, Ecken nach der M3-Shape-Skala
     * (4/8/12/16/28). Tabelle M3-Wert ↔ iOS-Wert: `android/UI_TEMPLATES.txt` („Material 3 metrics“).
     */
    object Layout {
        // MARK: Material-3-Grundmaße (ohne iOS-Gegenstück)

        /** M3 Window-Size-Class: ab 600 dp Breite „Medium“ (24-dp-Ränder). */
        const val mediumWidthBreakpointDp = 600
        /** M3-Shape-Skala. */
        val cornerExtraSmall = 4.dp
        val cornerSmall = 8.dp
        val cornerMedium = 12.dp
        val cornerLarge = 16.dp
        val cornerExtraLarge = 28.dp
        /** M3-Standard-Symbolgröße (Listen, Toolbars, Menüs). */
        val iconSize = 24.dp
        /** M3-Symbol in Buttons, Chips, Segmented Buttons. */
        val smallIconSize = 18.dp
        /** M3 Primary Tab mit Symbol und Label. */
        val primaryTabHeight = 64.dp
        /** M3 Top App Bar (small/center-aligned). */
        val topAppBarHeight = 64.dp
        /** M3 Common Buttons (Filled/Tonal/Text). */
        val buttonHeight = 40.dp
        /** M3 Button-Innenabstand horizontal (Text-Button: [buttonTextHorizontalPadding]). */
        val buttonHorizontalPadding = 24.dp
        val buttonTextHorizontalPadding = 12.dp
        /** M3 Chips (Assist/Filter/Input/Suggestion). */
        val chipHeight = 32.dp
        /** M3 Menü-Eintrag: 48 dp hoch, 12 dp seitlich, Menü min. 112 / max. 280 dp breit. */
        val menuItemHeight = 48.dp
        val menuItemHorizontalPadding = 12.dp
        val menuMinWidth = 112.dp
        val menuMaxWidth = 280.dp
        /** M3 Listen: ein-/zwei-/dreizeilig. */
        val listItemOneLineHeight = 56.dp
        val listItemTwoLineHeight = 72.dp
        val listItemThreeLineHeight = 88.dp
        /** M3 Dialog: Innenabstand 24 dp, Ecken extra-large. */
        val dialogPadding = 24.dp
        /** M3 Bottom-Sheet-Griff (32 × 4 dp). */
        val dragHandleWidth = 32.dp
        val dragHandleHeight = 4.dp
        /** M3 Floating Action Button / großer Play-Knopf. */
        val fabSize = 56.dp
        val largeFabSize = 96.dp

        // MARK: Ränder und Abstände (iOS-Namen)

        /**
         * Tab-Inhalt horizontal = M3-Rand: 16 dp Compact, 24 dp ab [mediumWidthBreakpointDp]
         * (Medium/Expanded).
         */
        val tabPaddingH: Dp
            @Composable @ReadOnlyComposable
            get() = if (LocalConfiguration.current.screenWidthDp >= mediumWidthBreakpointDp) 24.dp else 16.dp
        /** Abstand von der oberen Safe Area zum ersten fixen Element. */
        val tabPaddingTop = 8.dp
        /** Abstand unter der Top-App-Bar zur nächsten Kopfzeile. */
        val tabTitleToHeaderBlockSpacing = 8.dp
        /** Zwischen Hauptblöcken (Regale, Suchbereich ↔ Liste). */
        val sectionSpacing = 24.dp
        /** Home-Dashboard: Abstand zwischen Kategorie-Regalen. */
        val homeSectionSpacing = 32.dp
        /** Kategoriezeile ↔ erste Zeile / Karten innerhalb eines Blocks; Karten-Abstand in Reihen. */
        val withinSectionSpacing = 8.dp

        /** Horizontal in einer Zeile: Icon/Cover ↔ Textspalte ↔ Trailing-Control (M3-Listen: 16). */
        val rowSpacing = 16.dp
        /** Vertikal zwischen eng zusammengehörigen Elementen. */
        val stackSpacing = 8.dp
        /** Horizontal zwischen eng zusammengehörigen Elementen einer Zeile (Status + Text). */
        val inlineSpacing = 8.dp
        /** Titel ↔ direkt zugehöriger Untertitel/Wert; Badge-Innenabstand. */
        val tightSpacing = 4.dp
        /** Kleinster Abstand (M3 `SegmentedGap`): Icon ↔ Zahl, Titel ↔ Detail in Karten. */
        val hairlineSpacing = 2.dp
        /** Chips, Pills, kompakte Meta-Zeilen. */
        val compactSpacing = 4.dp
        /** Innenabstand von Karten (rundum, M3: 16). */
        val cardPadding = 16.dp
        /** Standard-Innenabstand von Screens/Sheets außerhalb der Tab-Roots. */
        val screenPadding = 16.dp
        /** Großer Abstand zwischen unabhängigen Blöcken in Sheets/Overlays. */
        val blockSpacing = 24.dp
        /** Trenner und Konturlinien (M3 Divider/Outline: 1 dp). */
        val hairlineWidth = 1.dp
        /** Kräftigere Konturlinie (aktiver Zustand). */
        val boldStrokeWidth = 2.dp
        /** Vertikaler Innenabstand von Pills auf Covern. */
        val pillVerticalPadding = 4.dp
        /** Innenabstand von Overlay-Karten über Vollbild-Inhalten (= M3-Dialog-Innenabstand). */
        val overlayPadding = 24.dp
        /** Horizontaler Außenabstand modaler Popups / Leerzustände. */
        val modalHorizontalPadding = 24.dp
        /** Vertikaler Innenabstand ganzseitiger Lade-/Leerzustände. */
        val loadingVerticalPadding = 48.dp

        // MARK: Feste Maße

        /** M3-Mindest-Touch-Ziel (48 dp); auch Plain-Icon-Buttons. */
        val minTapTarget = 48.dp
        /** M3-Icon-Button-Container (40 dp, 24-dp-Symbol, liegt in einem 48-dp-Ziel). */
        val iconButtonSize = 40.dp
        /** Kompakte Icon-Buttons (Stepper, Feld-Löschen) / Breite kleiner Download-Balken. */
        val compactIconButtonSize = 32.dp
        /** Icon-Spalte in kompakten Zeilen. */
        val compactIconColumnWidth = 24.dp
        /** Kreis-Badges auf Covern (Play, eBook). */
        val coverBadgeSize = 20.dp
        /** Höhe des Gradient-Scrims am Cover-Fuß. */
        val coverScrimHeight = 72.dp
        /** Label-Spalte in Meta-Zeilen. */
        val metaLabelColumnWidth = 112.dp
        /** Trailing-Wertespalte in Meta-/Aktionszeilen. */
        val metaValueColumnMinWidth = 88.dp
        /** Vertikaler Innenabstand einer Inhaltszeile ohne Kartenrahmen (M3-Listen: 8). */
        val rowVerticalPadding = 8.dp
        /** Icon-Spalte in Settings-/Admin-Kartenzeilen (= M3-Listen-Symbol 24 dp). */
        val settingsIconColumnWidth = 24.dp
        /** Leerzustand innerhalb eines Scroll-Bereichs (vertikal). */
        val emptyStateVerticalPadding = 32.dp
        /** Detail: Titelblock → Play. */
        val detailPlayButtonTopPadding = 12.dp
        /** Detail: Play → Metadaten. */
        val detailPlayButtonBottomPadding = 12.dp
        /** Detail: Play → erster Meta-Block. */
        val detailMetaAfterPlaySpacing = 16.dp
        /** Innenabstand Detail-Sektionskarten. */
        val detailSectionCardPadding = 16.dp
        val detailSectionCardCornerRadius = cornerMedium
        /** Zusatz unter Scroll-Inhalten vor dem Mini-Player ([LocalScrollBottomInset] kommt dazu). */
        val scrollBottomInsetBase = 24.dp

        /** Textfelder (M3 Outlined/Filled: extra-small). Suchfeld: [searchFieldHeight], volle Rundung. */
        val fieldCornerRadius = cornerExtraSmall
        /** M3 Search Bar / Textfeld-Mindesthöhe. */
        val searchFieldHeight = 56.dp
        /** Kleine Cover-Thumbs / Chips in Metadata-Sheets (M3-Chip-Ecke). */
        val chipCornerRadius = cornerSmall
        /** Reader-Chrome-Hinweis. */
        val readerChromeCornerRadius = cornerLarge
        /** Level-Badge auf Achievement-Karten. */
        val achievementBadgeCornerRadius = cornerSmall

        /** Abstand Strip ↔ Top-App-Bar oben. */
        val horizontalBrowseStripToTitleSpacing = 4.dp
        /** Ab dieser Breite zeigt eine Dropdown-Pill ihr führendes Symbol (sonst nur Label + Chevron). */
        val dropdownPillIconMinWidth = 152.dp
        /** Akzent-Indikator unter dem aktiven Icon-Tab (M3 Primary-Tab-Indikator). */
        val browseTabIndicatorWidth = 32.dp
        val browseTabIndicatorHeight = 4.dp
        /** Abstand Strip ↔ Scroll-Inhalt unten. */
        val horizontalBrowseStripToContentSpacing = 8.dp
        val horizontalBrowseStripVerticalPadding = 4.dp

        /** „Continue listening“-Karten (M3 large). */
        val continueHeroCardCornerRadius = cornerLarge
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
        val continueHeroMetadataTitleDetailSpacing = 4.dp
        val continueHeroMetadataVerticalPadding = 12.dp
        /** Genau zwei Zeilen `titleMedium` (2 × 24 sp). */
        val continueHeroMetadataTitleFixedHeight = 48.dp
        /** Eine Zeile `bodySmall` für Autor/Show (16 sp + Luft). */
        val continueHeroMetadataDetailFixedHeight = 20.dp
        val continueHeroMetadataPlayPillTopPadding = 8.dp
        /** Play-Pille = M3-Button-Höhe. */
        val continueHeroMetadataPlayPillIntrinsicHeight = buttonHeight
        val continueHeroMetadataExtraBottomPadding = 12.dp
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

        /** M3-Karten: medium (12 dp). */
        val cardCornerRadius = cornerMedium
        /** Mindesthöhe für Zeilen in gruppierten Karten (M3 einzeilige Liste). */
        val listRowMinHeight = listItemOneLineHeight
        /** Horizontaler Innenabstand in Settings-Karten (M3-Listen: 16). */
        val settingsCardInsetHPadding = 16.dp
        /** Vertikaler Innenabstand in Settings-Karten. */
        val settingsCardInsetVPadding = 8.dp
        /** Vertikaler Abstand um Trennlinien zwischen Settings-Zeilen (M3: Zeilen tragen die Höhe). */
        val settingsCardDividerSpacing = 0.dp
        /** Library-Zeilen — gleiche Abrundung wie Karten. */
        val libraryRowCornerRadius = cornerMedium
        /** Cover-Ecken (M3 small). */
        val coverCornerRadius = cornerSmall

        /** Cover in Library-Zeilen: festes 1:1. */
        // Android kleiner als iOS (100 pt): Zeilen wirkten neben M3-Typo deutlich höher.
        val libraryRowCoverSide = 80.dp
        /** Abstand Cover ↔ Textspalte in Library-Zeilen. */
        val libraryRowCardInset = 12.dp
        /** Titel oben / Laufzeit unten. */
        val libraryRowTextInset = 8.dp
        /** Höhe des Fortschrittsstreifens am unteren Kartenrand (M3 Linear Progress: 4). */
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
    /** Android-only: Dynamic Color (Wallpaper-Farben, Android 12+) statt Akzent-Seed. Standard aus. */
    var dynamicColor by mutableStateOf(Prefs.bool(Keys.appearanceDynamicColor))
        private set

    /** Dynamic Color gibt es erst ab Android 12 (API 31). */
    val dynamicColorSupported: Boolean get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S

    fun updateDynamicColor(value: Boolean) {
        if (value == dynamicColor) return
        dynamicColor = value
        Prefs.setBool(Keys.appearanceDynamicColor, value)
    }

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

    /** iOS: `palette.foregroundOnAccent(themeAccent)` — Android: `colorScheme.onPrimary` (gleiche Regel, auch bei Dynamic Color korrekt). */
    val onAccent: Color
        @Composable get() = LocalResolvedAppearance.current.palette.scheme.onPrimary

    /** System-Hell/Dunkel (für [Appearance.updateAccent] im System-Modus). */
    val systemDark: Boolean
        @Composable get() = LocalResolvedAppearance.current.systemDark
}

/**
 * iOS: `.preferredColorScheme` + `.tint` + `themeAccentFromAppModel` am Root. Material-3-
 * ColorScheme aus dem Akzent als Seed ([MaterialScheme], Akzent bleibt exakt `primary`) oder per
 * Dynamic Color (Android 12+, [Appearance.dynamicColor]); [Theme.palette] liest dieselben Rollen.
 * Setzt die M3-Typeskala ([AppType]) und die Statusleisten-Icons passend zum Modus.
 */
@Composable
fun AbstandTheme(content: @Composable () -> Unit) {
    val systemDark = isSystemInDarkTheme()
    val isDark = Appearance.mode.isDarkLike(systemDark)
    val context = LocalContext.current
    // Dynamic Color (Android 12+): Wallpaper-Schema ersetzt den Akzent-Seed; sonst M3-Schema aus dem Akzent.
    val dynamicScheme = if (Appearance.dynamicColor && Appearance.dynamicColorSupported) {
        if (isDark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
    } else null
    val palette = dynamicScheme?.let { AppColorPalette.fromScheme(it, isDark) }
        ?: AppColorPalette.derived(Appearance.accent(systemDark), isDark)
    val scheme = palette.scheme
    val accent = scheme.primary

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
        MaterialTheme(colorScheme = scheme, typography = AppType.material, content = content)
    }
}

