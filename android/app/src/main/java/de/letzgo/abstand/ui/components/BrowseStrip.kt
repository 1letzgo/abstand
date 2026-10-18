package de.letzgo.abstand.ui.components

import androidx.compose.material3.TabRowDefaults.tabIndicatorOffset
import androidx.compose.material3.TabRowDefaults
import androidx.compose.material3.Tab
import androidx.compose.material3.PrimaryScrollableTabRow
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.material3.HorizontalDivider
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.AppType
import androidx.compose.ui.semantics.selected
import androidx.compose.material3.Text
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.calculateStartPadding
import androidx.compose.foundation.layout.calculateEndPadding
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.unit.Dp
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.SF
import kotlinx.coroutines.launch

/** iOS: `AbstandBrowseStripItem` — Eintrag im Bereichs-Menü der Dropdown-Pills. */
data class AbstandBrowseStripItem(
    val id: String,
    val label: String,
    val icon: ImageVector,
    /** Trenner im Menü vor diesem Eintrag (Gruppenwechsel). */
    val dividerBefore: Boolean = false,
)

/**
 * Bereichsumschalter mit den Dropdown-Pills aus iOS `AbstandPinnedBrowseStrip` / `AbstandExpandingDockBrowseStrip`
 * (Home-Bibliotheksleiste):
 * links die Bibliothek als kompakte Pill (nur Symbol + Chevron, Namen im Menü), daneben der Bereich
 * über die restliche Breite — **immer** beide, auch bei nur einer aktiven Bibliothek. Ohne
 * Bibliotheksauswahl füllt die Bereichs-Pill die Zeile allein.
 */
@Composable
fun AbstandBrowsePills(
    items: List<AbstandBrowseStripItem>,
    selectionId: String,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
    libraryItems: List<AbstandBrowseStripItem> = emptyList(),
    librarySelectionId: String = "",
    onSelectLibrary: ((String) -> Unit)? = null,
    sectionAccessibilityLabel: String = "Browse",
) {
    if (items.isEmpty()) return
    val haptics = LocalHapticFeedback.current
    val dock = AppTheme.ExpandingDock
    val select: (String) -> Unit = { id ->
        if (id != selectionId) {
            haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
            onSelect(id)
        }
    }
    Row(
        modifier
            .fillMaxWidth()
            // Kein vertikaler Innenabstand: die Pills tragen selbst das 48-dp-Touch-Ziel
            // (minimumInteractiveComponentSize), die Zeilenhöhe bleibt damit 48 dp wie zuvor.
            .padding(start = AppTheme.Layout.tabPaddingH, end = AppTheme.Layout.stackSpacing),
        horizontalArrangement = Arrangement.spacedBy(dock.itemSpacing),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (onSelectLibrary != null && libraryItems.isNotEmpty()) {
            // Bibliothek kompakt (nur Symbol), der Bereich bekommt die restliche Breite.
            AbstandDropdownPill(libraryItems, librarySelectionId, onSelectLibrary, Modifier, SF.booksVerticalFill, "Library", iconOnly = true)
            AbstandDropdownPill(items, selectionId, select, Modifier.weight(1f), SF.squareGrid2x2, sectionAccessibilityLabel)
        } else {
            AbstandDropdownPill(items, selectionId, select, Modifier.weight(1f), SF.squareGrid2x2, sectionAccessibilityLabel)
        }
    }
}

/**
 * iOS: `AbstandFixedBrowseStripSectionsLayout` — Titelzeile → fester Bereich ([belowStrip]) → je
 * Sektion eine eigene scrollende Liste. Android (nur Home): die Titelzeile zeigt [title] und
 * [actions], der fixe Browse-Streifen von iOS ist entfallen — Home setzt stattdessen Continue
 * listening + Bibliotheksleiste in [belowStrip]. Die Scroll-Position jeder besuchten Sektion
 * bleibt erhalten (Compose: ein `SaveableStateHolder` je Sektions-ID statt `ScrollPosition`-Map),
 * Pull-to-Refresh über [onRefresh]. [scrollToTopTrigger] (Sort/Filter) springt in der aktiven
 * Sektion nach oben. Die iOS-Workarounds (`relayoutTrigger`, `bottomInsetRevalidationTrigger`)
 * braucht Compose nicht: `LazyColumn` layoutet bei geänderter Höhe/Inset selbst neu.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun <ID : Any> AbstandFixedBrowseStripSectionsLayout(
    title: String,
    selection: ID,
    modifier: Modifier = Modifier,
    actions: (@Composable RowScope.() -> Unit)? = null,
    scrollToTopTrigger: Any? = null,
    onRefresh: (suspend () -> Unit)? = null,
    /** Fester Bereich unter der Titelzeile (scrollt nicht mit). */
    belowStrip: (@Composable () -> Unit)? = null,
    sectionSpacing: Dp = AppTheme.Layout.sectionSpacing,
    /** Optional eigener Listen-Zustand (Home: Bereichswechsel springt nach oben). */
    listState: LazyListState? = null,
    sectionBody: LazyListScope.(ID) -> Unit,
) {
    val holder = rememberSaveableStateHolder()
    val scope = rememberCoroutineScope()
    var refreshing by remember { mutableStateOf(false) }
    TabRootScaffold(
        title = title,
        modifier = modifier,
        actions = actions,
        belowHeader = belowStrip,
        showsTitleRow = true,
    ) { padding ->
        holder.SaveableStateProvider(selection) {
            val ownState = rememberLazyListState()
            val state = listState ?: ownState
            LaunchedEffect(scrollToTopTrigger) {
                if (scrollToTopTrigger != null) state.scrollToItem(0)
            }
            val list = @Composable {
                // Liste beginnt UNTER der (deckenden) Kopfzeile statt dahinter — sonst kleben
                // `stickyHeader`s unsichtbar hinter der Kopfzeile (Home: Bibliotheksleiste).
                val layoutDirection = androidx.compose.ui.platform.LocalLayoutDirection.current
                LazyColumn(
                    state = state,
                    modifier = Modifier.fillMaxSize().padding(top = padding.calculateTopPadding()),
                    contentPadding = PaddingValues(
                        start = padding.calculateStartPadding(layoutDirection),
                        end = padding.calculateEndPadding(layoutDirection),
                        bottom = padding.calculateBottomPadding(),
                    ),
                    verticalArrangement = Arrangement.spacedBy(sectionSpacing),
                ) { sectionBody(selection) }
            }
            if (onRefresh != null) {
                PullToRefreshBox(
                    isRefreshing = refreshing,
                    onRefresh = {
                        scope.launch {
                            refreshing = true
                            try {
                                onRefresh()
                            } finally {
                                refreshing = false
                            }
                        }
                    },
                    modifier = Modifier.fillMaxSize(),
                ) { list() }
            } else {
                list()
            }
        }
    }
}

/**
 * Standard-Material-3-Tabs (`PrimaryScrollableTabRow`, Text-Tabs, 48 dp — gleiche Höhe wie die
 * Home-Bibliotheksleiste) als Bereichsumschalter in der Settings-Kopfzeile. Akzent für das aktive
 * Label und den Indikator (M3: 3 dp, [AppTheme.Layout.browseTabIndicatorHeight]), darunter der
 * M3-Trenner (1 dp `outlineVariant`).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AbstandMaterialTabs(
    items: List<AbstandBrowseStripItem>,
    selectionId: String,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (items.isEmpty()) return
    val haptics = LocalHapticFeedback.current
    val accent = Theme.accent
    val selectedIndex = items.indexOfFirst { it.id == selectionId }.coerceAtLeast(0)
    PrimaryScrollableTabRow(
        selectedTabIndex = selectedIndex,
        modifier = modifier.fillMaxWidth(),
        containerColor = Theme.palette.background,
        contentColor = accent,
        edgePadding = AppTheme.Layout.tabPaddingH,
        indicator = {
            TabRowDefaults.PrimaryIndicator(
                Modifier.tabIndicatorOffset(selectedIndex, matchContentSize = true),
                width = Dp.Unspecified,
                height = AppTheme.Layout.browseTabIndicatorHeight,
                color = accent,
            )
        },
        divider = { HorizontalDivider(thickness = AppTheme.Layout.hairlineWidth, color = Theme.palette.scheme.outlineVariant) },
    ) {
        items.forEachIndexed { index, item ->
            Tab(
                selected = index == selectedIndex,
                onClick = {
                    if (item.id != selectionId) {
                        haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                        onSelect(item.id)
                    }
                },
                text = { Text(item.label, style = AppType.titleSmall, maxLines = 1) },
                selectedContentColor = accent,
                unselectedContentColor = Theme.palette.textSecondary,
            )
        }
    }
}
