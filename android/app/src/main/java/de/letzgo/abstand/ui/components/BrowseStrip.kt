package de.letzgo.abstand.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import kotlinx.coroutines.launch

/** iOS: `AbstandBrowseStripItem` — Eintrag im Browse-Streifen (Symbol oder Cover). */
data class AbstandBrowseStripItem(
    val id: String,
    val label: String,
    val icon: ImageVector,
    /** Optional: Cover statt Symbol (z. B. Podcast-Sendungen). */
    val coverItemId: String? = null,
)

/**
 * iOS: `AbstandExpandingDockBrowseStrip` — inaktive Kategorien als Kreis-Symbole, die aktive als
 * wachsende Kapsel mit Label (Material: tonale Kreise + Akzent-Kapsel, horizontal scrollend).
 * [pinnedLeadingItem] bleibt links stehen, der Rest scrollt darunter durch (Podcast „New“).
 */
@Composable
fun AbstandExpandingDockBrowseStrip(
    items: List<AbstandBrowseStripItem>,
    selectionId: String,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
    appliesLeadingPadding: Boolean = true,
    pinnedLeadingItem: AbstandBrowseStripItem? = null,
) {
    val haptics = LocalHapticFeedback.current
    val select: (String) -> Unit = { id ->
        if (id != selectionId) {
            haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
            onSelect(id)
        }
    }
    val dock = AppTheme.ExpandingDock
    val leading = if (appliesLeadingPadding) dock.horizontalPadding else 0.dp
    if (pinnedLeadingItem != null) {
        val background = Theme.palette.background
        val scrolling = items.filter { it.id != pinnedLeadingItem.id }
        Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.padding(start = leading, top = dock.verticalPadding, bottom = dock.verticalPadding)) {
                ExpandingDockChip(pinnedLeadingItem, pinnedLeadingItem.id == selectionId) { select(pinnedLeadingItem.id) }
            }
            Box(Modifier.weight(1f)) {
                LazyRow(
                    contentPadding = PaddingValues(
                        start = dock.pinnedChipFadeWidth, end = dock.horizontalPadding,
                        top = dock.verticalPadding, bottom = dock.verticalPadding,
                    ),
                    horizontalArrangement = Arrangement.spacedBy(dock.itemSpacing),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    items(scrolling, key = { it.id }) { item -> ExpandingDockChip(item, item.id == selectionId) { select(item.id) } }
                }
                // Überblendung zum fixierten Chip hin.
                Box(
                    Modifier
                        .align(Alignment.CenterStart)
                        .width(dock.pinnedChipFadeWidth)
                        .height(dock.activeHeight + dock.verticalPadding * 2)
                        .background(Brush.horizontalGradient(listOf(background, background.copy(alpha = 0f)))),
                )
            }
        }
        return
    }
    val centered = items.size < dock.centerWhenFewThreshold
    LazyRow(
        modifier = modifier.fillMaxWidth(),
        contentPadding = PaddingValues(start = leading, end = dock.horizontalPadding, top = dock.verticalPadding, bottom = dock.verticalPadding),
        horizontalArrangement = if (centered) {
            Arrangement.spacedBy(dock.itemSpacing, Alignment.CenterHorizontally)
        } else {
            Arrangement.spacedBy(dock.itemSpacing)
        },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        items(items, key = { it.id }) { item -> ExpandingDockChip(item, item.id == selectionId) { select(item.id) } }
    }
}

/** Dock-Chip eines Browse-Eintrags ([AbstandDockChip]). */
@Composable
private fun ExpandingDockChip(item: AbstandBrowseStripItem, isSelected: Boolean, onClick: () -> Unit) {
    AbstandDockChip(item.label, item.icon, isSelected, onClick, coverItemId = item.coverItemId)
}

/**
 * iOS: `AbstandPinnedBrowseStrip` — bei mehreren Bibliotheken zwei Dropdown-Pills (50/50:
 * Bibliothek | Sektion), sonst der scrollende Expanding-Dock-Streifen.
 */
@Composable
fun AbstandPinnedBrowseStrip(
    secondaryItems: List<AbstandBrowseStripItem>,
    secondarySelectionId: String,
    onSelectSecondary: (String) -> Unit,
    modifier: Modifier = Modifier,
    libraryPickerItems: List<AbstandBrowseStripItem> = emptyList(),
    libraryPickerSelectionId: String = "",
    onSelectLibrary: ((String) -> Unit)? = null,
    pinnedLeadingItem: AbstandBrowseStripItem? = null,
    secondaryAccessibilityLabel: String = "Browse",
) {
    if (onSelectLibrary != null && libraryPickerItems.size > 1) {
        Row(
            modifier.fillMaxWidth().padding(horizontal = AppTheme.Layout.tabPaddingH, vertical = AppTheme.ExpandingDock.verticalPadding),
            horizontalArrangement = Arrangement.spacedBy(AppTheme.ExpandingDock.itemSpacing),
        ) {
            AbstandDropdownPill(libraryPickerItems, libraryPickerSelectionId, onSelectLibrary, Modifier.weight(1f), SF.booksVerticalFill, "Library")
            AbstandDropdownPill(secondaryItems, secondarySelectionId, onSelectSecondary, Modifier.weight(1f), SF.squareGrid2x2, secondaryAccessibilityLabel)
        }
    } else {
        AbstandExpandingDockBrowseStrip(
            items = secondaryItems,
            selectionId = secondarySelectionId,
            onSelect = onSelectSecondary,
            modifier = modifier,
            pinnedLeadingItem = pinnedLeadingItem,
        )
    }
}

/**
 * iOS: `AbstandFixedBrowseStripSectionsLayout` — Großtitel → fixer Browse-Streifen → je Sektion
 * eine eigene scrollende Liste. Die Scroll-Position jeder besuchten Sektion bleibt erhalten
 * (Compose: ein `SaveableStateHolder` je Sektions-ID statt `ScrollPosition`-Map), Pull-to-Refresh
 * über [onRefresh]. [scrollToTopTrigger] (Sort/Filter) springt in der aktiven Sektion nach oben.
 * Die iOS-Workarounds (`relayoutTrigger`, `bottomInsetRevalidationTrigger`) braucht Compose nicht:
 * `LazyColumn` layoutet bei geänderter Höhe/Inset selbst neu.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun <ID : Any> AbstandFixedBrowseStripSectionsLayout(
    title: String,
    selection: ID,
    modifier: Modifier = Modifier,
    showsStrip: Boolean = true,
    actions: @Composable RowScope.() -> Unit = {},
    scrollToTopTrigger: Any? = null,
    onRefresh: (suspend () -> Unit)? = null,
    strip: @Composable () -> Unit = {},
    sectionSpacing: Dp = AppTheme.Layout.sectionSpacing,
    /**
     * `true`: Liste ohne horizontales Padding — Sektionen setzen `tabPaddingH` selbst, horizontale
     * Reihen laufen randlos mit Innenabstand (Material-„uncontained carousel“).
     */
    fullBleed: Boolean = false,
    sectionBody: LazyListScope.(ID) -> Unit,
) {
    val holder = rememberSaveableStateHolder()
    val scope = rememberCoroutineScope()
    var refreshing by remember { mutableStateOf(false) }
    TabRootScaffold(
        title = title,
        modifier = modifier,
        actions = actions,
        header = if (showsStrip) strip else null,
    ) { padding ->
        holder.SaveableStateProvider(selection) {
            val state = rememberLazyListState()
            LaunchedEffect(scrollToTopTrigger) {
                if (scrollToTopTrigger != null) state.scrollToItem(0)
            }
            val list = @Composable {
                LazyColumn(
                    state = state,
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = if (fullBleed) {
                        PaddingValues(top = padding.calculateTopPadding(), bottom = padding.calculateBottomPadding())
                    } else {
                        padding
                    },
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
