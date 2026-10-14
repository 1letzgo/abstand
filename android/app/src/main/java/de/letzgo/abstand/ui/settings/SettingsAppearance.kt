package de.letzgo.abstand.ui.settings

import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import de.letzgo.abstand.data.AbsStartShelfLocalization
import de.letzgo.abstand.model.AppSettings
import de.letzgo.abstand.model.LibraryCardStyle
import de.letzgo.abstand.ui.Appearance
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.AppearanceMode
import de.letzgo.abstand.ui.IosType
import de.letzgo.abstand.ui.LocalTabNavigator
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.TabDestination
import de.letzgo.abstand.ui.TabNavigator
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandGroupedCard
import de.letzgo.abstand.ui.components.AbstandSectionEmptyState
import de.letzgo.abstand.ui.components.ServerAdminSection
import de.letzgo.abstand.ui.components.SettingsCardActionRow
import de.letzgo.abstand.ui.components.SettingsCardColorPickerRow
import de.letzgo.abstand.ui.components.SettingsCardIcon
import de.letzgo.abstand.ui.components.SettingsCardNavRow
import de.letzgo.abstand.ui.components.SettingsCardPickerRow
import de.letzgo.abstand.ui.components.SettingsCardSegmentedRow
import de.letzgo.abstand.ui.components.SettingsSubpageScaffold
import de.letzgo.abstand.ui.components.abstandCardListRowFrame
import de.letzgo.abstand.ui.components.abstandSwitchColors

/** iOS: `SettingsAppearanceView` — Sektionen „Theme“ und „Views“. */
fun LazyListScope.settingsAppearanceSections() {
    item(key = "theme") { SettingsThemeSection() }
    item(key = "views") { SettingsViewsSection() }
}

@Composable
private fun SettingsThemeSection() {
    val systemDark = Theme.systemDark
    val accent = Theme.accent
    ServerAdminSection("Theme") {
        AbstandGroupedCard {
            SettingsCardSegmentedRow(
                icon = SF.circleLefthalfFilled,
                title = "Appearance",
                selection = Appearance.mode,
                options = AppearanceMode.entries,
                label = { it.label },
                onSelect = { Appearance.updateMode(it) },
            )
        }
        AbstandGroupedCard {
            SettingsCardColorPickerRow(
                icon = SF.paintpaletteFill,
                title = "Accent color",
                color = accent,
                onColorChange = { Appearance.updateAccent(it, systemDark) },
            )
        }
        val matchesDefault = Appearance.accentMatchesDefault(systemDark)
        AbstandGroupedCard {
            SettingsCardActionRow(
                icon = SF.arrowCounterclockwise,
                title = "Reset to default",
                onClick = { Appearance.resetAccentToDefault(systemDark) },
                enabled = !matchesDefault,
            )
        }
    }
}

@Composable
private fun SettingsViewsSection() {
    val bookStyle by AppSettings.libraryBookCardStyle.collectAsState()
    val podcastStyle by AppSettings.libraryPodcastCardStyle.collectAsState()
    val navigator = LocalTabNavigator.current
    ServerAdminSection("Views") {
        AbstandGroupedCard {
            SettingsCardPickerRow(
                icon = SF.booksVerticalFill,
                title = "Book",
                selection = bookStyle,
                options = LibraryCardStyle.entries,
                label = { it.label },
                onSelect = { AppSettings.setLibraryBookCardStyle(it) },
            )
        }
        AbstandGroupedCard {
            SettingsCardPickerRow(
                icon = SF.micFill,
                title = "Podcast episode cards",
                selection = podcastStyle,
                options = LibraryCardStyle.entries,
                label = { it.label },
                onSelect = { AppSettings.setLibraryPodcastCardStyle(it) },
            )
        }
        if (SettingsIntegration.homeShelfSettings != null) {
            AbstandGroupedCard {
                SettingsCardNavRow(
                    icon = SF.houseFill,
                    title = "Home",
                    subtitle = "Show or hide shelves under Dashboard",
                    onClick = { navigator?.push(HomeShelvesDestination) },
                )
            }
        }
    }
}

/** iOS: `SettingsAppearanceHomeView` — Home-Regale schalten und per Griff umsortieren. */
data object HomeShelvesDestination : TabDestination {
    override val key = "settings/homeShelves"

    @Composable
    override fun Content(navigator: TabNavigator) = SettingsAppearanceHomeScreen(onBack = { navigator.pop() })
}

@Composable
fun SettingsAppearanceHomeScreen(onBack: () -> Unit) {
    val source = SettingsIntegration.homeShelfSettings
    SettingsSubpageScaffold(title = "Home", onBack = onBack) {
        item(key = "home") {
            ServerAdminSection("Home") {
                if (source == null) {
                    AbstandSectionEmptyState("Home shelves are not available.")
                } else {
                    HomeShelfList(source)
                }
            }
        }
    }
}

@Composable
private fun HomeShelfList(source: HomeShelfSettings) {
    val rows by source.categories.collectAsState()
    val disabled by source.disabledCategories.collectAsState()
    var dragging by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) { source.refreshLabels() }
    if (rows.isEmpty()) {
        AbstandSectionEmptyState("No shelves yet.")
        return
    }
    rows.forEach { (category, title) ->
        val isContinue = category == "recentlyListened"
        HomeShelfCard(
            category = category,
            title = title,
            enabled = category !in disabled,
            isContinueListening = isContinue,
            isDragging = dragging == category,
            onEnabledChange = { source.setEnabled(category, it) },
            onDragStart = { dragging = category },
            onDragEnd = { dragging = null },
            onDragStep = { direction ->
                // iOS: `dropEntered` — beim Überfahren der Nachbar-Karte tauschen (Continue bleibt oben).
                val ordered = source.categories.value.map { it.first }
                val idx = ordered.indexOf(category)
                val target = ordered.getOrNull(idx + direction)
                if (target != null && target != "recentlyListened") source.move(category, target)
            },
        )
    }
}

@Composable
private fun HomeShelfCard(
    category: String,
    title: String,
    enabled: Boolean,
    isContinueListening: Boolean,
    isDragging: Boolean,
    onEnabledChange: (Boolean) -> Unit,
    onDragStart: () -> Unit,
    onDragEnd: () -> Unit,
    onDragStep: (Int) -> Unit,
) {
    val palette = Theme.palette
    var cardHeight by remember { mutableIntStateOf(1) }
    var accumulated by remember { mutableFloatStateOf(0f) }
    val step by rememberUpdatedState(onDragStep)
    AbstandGroupedCard(Modifier.alpha(if (isDragging) DraggingAlpha else 1f).onSizeChanged { cardHeight = maxOf(1, it.height) }) {
        Row(
            Modifier.abstandCardListRowFrame(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.rowSpacing),
        ) {
            SettingsCardIcon(SF.named(AbsStartShelfLocalization.stripSystemImage(category)) ?: SF.rectangleStack)
            Text(title, style = IosType.body, color = palette.textPrimary, modifier = Modifier.weight(1f))
            Switch(checked = enabled, onCheckedChange = onEnabledChange, colors = abstandSwitchColors())
            if (!isContinueListening) {
                Box(
                    Modifier
                        .sizeIn(minWidth = AppTheme.Layout.minTapTarget, minHeight = AppTheme.Layout.minTapTarget)
                        .semantics { contentDescription = "Reorder" }
                        .pointerInput(category) {
                            detectDragGestures(
                                onDragStart = { accumulated = 0f; onDragStart() },
                                onDragEnd = { accumulated = 0f; onDragEnd() },
                                onDragCancel = { accumulated = 0f; onDragEnd() },
                            ) { change, amount ->
                                change.consume()
                                accumulated += amount.y
                                val threshold = cardHeight * DragSwapFraction
                                if (accumulated > threshold) { accumulated = 0f; step(1) }
                                if (accumulated < -threshold) { accumulated = 0f; step(-1) }
                            }
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(SF.line3Horizontal, contentDescription = null, tint = palette.textSecondary)
                }
            }
        }
    }
}

/** iOS: `.opacity(draggingCategory == category ? 0.72 : 1)`. */
private const val DraggingAlpha = 0.72f
/** Anteil der Kartenhöhe, ab dem beim Ziehen mit dem Nachbarn getauscht wird. */
private const val DragSwapFraction = 0.6f
