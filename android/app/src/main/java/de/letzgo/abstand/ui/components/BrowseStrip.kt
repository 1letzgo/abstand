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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.material3.Text
import androidx.compose.material3.TabRowDefaults.tabIndicatorOffset
import androidx.compose.material3.TabRowDefaults
import androidx.compose.material3.Tab
import androidx.compose.material3.PrimaryScrollableTabRow
import androidx.compose.material3.HorizontalDivider
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
 * Android: Bereichsumschalter unter der Top App Bar als Material-3-**scrollbare Primary-Tabs**
 * (48 dp, Text-Labels, Akzent-Indikator unter dem Label). Ersetzt den iOS-Expanding-Dock
 * (`AbstandExpandingDockBrowseStrip`: Kreis-Symbole + wachsende Kapsel), der auf Android zu viel
 * Höhe kostet. [leading] = optionales Element links vor den Tabs (z. B. Bibliotheks-Picker).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AbstandBrowseTabs(
    items: List<AbstandBrowseStripItem>,
    selectionId: String,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
    leading: (@Composable () -> Unit)? = null,
) {
    if (items.isEmpty()) return
    val haptics = LocalHapticFeedback.current
    val palette = Theme.palette
    val accent = Theme.accent
    val selectedIndex = items.indexOfFirst { it.id == selectionId }.coerceAtLeast(0)
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        if (leading != null) Box(Modifier.padding(start = AppTheme.Layout.tabPaddingH)) { leading() }
        PrimaryScrollableTabRow(
            selectedTabIndex = selectedIndex,
            modifier = Modifier.weight(1f),
            containerColor = palette.background,
            contentColor = accent,
            edgePadding = AppTheme.Layout.tabPaddingH,
            indicator = {
                TabRowDefaults.PrimaryIndicator(
                    Modifier.tabIndicatorOffset(selectedIndex, matchContentSize = true),
                    width = Dp.Unspecified,
                    color = accent,
                )
            },
            divider = { HorizontalDivider(color = palette.textSecondary.copy(alpha = TAB_DIVIDER_ALPHA)) },
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
                    text = { Text(item.label, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                    selectedContentColor = accent,
                    unselectedContentColor = palette.textSecondary,
                )
            }
        }
    }
}

private const val TAB_DIVIDER_ALPHA = 0.2f

/**
 * iOS: `AbstandExpandingDockBrowseStrip`. Android: [AbstandBrowseTabs]; [pinnedLeadingItem]
 * (Podcast „New“) wird zum ersten Tab.
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
    AbstandBrowseTabs(ordered, selectionId, onSelect, modifier)
}

/**
 * iOS: `AbstandPinnedBrowseStrip` — Android: [AbstandBrowseTabs]; bei mehreren Bibliotheken steht
 * ein kompakter Bibliotheks-Picker links vor den Tabs.
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
    @Suppress("UNUSED_PARAMETER") secondaryAccessibilityLabel: String = "Browse",
) {
    val ordered = if (pinnedLeadingItem == null) secondaryItems
    else listOf(pinnedLeadingItem) + secondaryItems.filter { it.id != pinnedLeadingItem.id }
    // Mehrere Bibliotheken: kompakter Bibliotheks-Picker links vor den Tabs (iOS: 50/50-Pills).
    val leading: (@Composable () -> Unit)? = if (onSelectLibrary != null && libraryPickerItems.size > 1) {
        {
            AbstandDropdownPill(
                libraryPickerItems, libraryPickerSelectionId, onSelectLibrary,
                Modifier.widthIn(max = AppTheme.Layout.browseLibraryPickerMaxWidth), SF.booksVerticalFill, "Library",
            )
        }
    } else {
        null
    }
    AbstandBrowseTabs(ordered, secondarySelectionId, onSelectSecondary, modifier, leading)
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
