package de.letzgo.abstand.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
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

/** iOS: `AbstandBrowseStripItem` — Eintrag im Browse-Streifen (Symbol oder Cover). */
data class AbstandBrowseStripItem(
    val id: String,
    val label: String,
    val icon: ImageVector,
    /** Optional: Cover statt Symbol (z. B. Podcast-Sendungen). */
    val coverItemId: String? = null,
)

/**
 * Bereichsumschalter unter der Titelzeile mit den Dropdown-Pills aus iOS `AbstandPinnedBrowseStrip`:
 * eigene Zeile über die volle Breite, links die Bibliothek, rechts der Bereich (50/50) — **immer**
 * beide, auch bei nur einer aktiven Bibliothek (die Pill zeigt dann deren Namen). Ohne
 * Bibliotheksauswahl (Settings) füllt die Bereichs-Pill die Zeile allein.
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
            .padding(horizontal = AppTheme.Layout.tabPaddingH, vertical = dock.verticalPadding),
        horizontalArrangement = Arrangement.spacedBy(dock.itemSpacing),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (onSelectLibrary != null && libraryItems.isNotEmpty()) {
            AbstandDropdownPill(libraryItems, librarySelectionId, onSelectLibrary, Modifier.weight(1f), SF.booksVerticalFill, "Library")
            AbstandDropdownPill(items, selectionId, select, Modifier.weight(1f), SF.squareGrid2x2, sectionAccessibilityLabel)
        } else {
            AbstandDropdownPill(items, selectionId, select, Modifier.weight(1f), SF.squareGrid2x2, sectionAccessibilityLabel)
        }
    }
}

/**
 * iOS: `AbstandExpandingDockBrowseStrip`. Android: [AbstandBrowsePills]; [pinnedLeadingItem]
 * (Podcast „New“) steht als erster Eintrag im Menü.
 */
@Composable
fun AbstandExpandingDockBrowseStrip(
    items: List<AbstandBrowseStripItem>,
    selectionId: String,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
    pinnedLeadingItem: AbstandBrowseStripItem? = null,
) {
    val ordered = if (pinnedLeadingItem == null) items else listOf(pinnedLeadingItem) + items.filter { it.id != pinnedLeadingItem.id }
    AbstandBrowsePills(ordered, selectionId, onSelect, modifier)
}

/**
 * iOS: `AbstandPinnedBrowseStrip` — zwei Dropdown-Pills (Bibliothek | Bereich), siehe [AbstandBrowsePills].
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
    val ordered = if (pinnedLeadingItem == null) secondaryItems
    else listOf(pinnedLeadingItem) + secondaryItems.filter { it.id != pinnedLeadingItem.id }
    AbstandBrowsePills(
        items = ordered,
        selectionId = secondarySelectionId,
        onSelect = onSelectSecondary,
        modifier = modifier,
        libraryItems = libraryPickerItems,
        librarySelectionId = libraryPickerSelectionId,
        onSelectLibrary = onSelectLibrary,
        sectionAccessibilityLabel = secondaryAccessibilityLabel,
    )
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
