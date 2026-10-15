package de.letzgo.abstand.ui.components

import androidx.compose.foundation.background
import de.letzgo.abstand.ui.AppType
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.draw.clip
import androidx.compose.material3.Icon
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.clickable
import androidx.compose.animation.animateContentSize
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
 * Android (wie stashy `NativeTabStrip`): Bereichsumschalter **als Top-Leiste** — sitzt direkt unter
 * der Statusleiste (der Tab-Root hat keine Titelzeile, der Tab-Name steht in der Navigation Bar).
 * Icon-Tabs: nur Symbol, der aktive Tab Symbol + Label mit Akzent-Indikator; Einträge mit Cover
 * statt Symbol (Podcast-Sendungen) als Text-Tabs ([PrimaryScrollableTabRow]). [pinFirst]: erster
 * Eintrag bleibt links stehen (iOS `pinnedItemID`), [leading] = z. B. Bibliotheks-Picker.
 * Ersetzt den iOS-Expanding-Dock (`AbstandExpandingDockBrowseStrip`).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AbstandBrowseTabs(
    items: List<AbstandBrowseStripItem>,
    selectionId: String,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
    leading: (@Composable () -> Unit)? = null,
    pinFirst: Boolean = false,
) {
    if (items.isEmpty()) return
    val haptics = LocalHapticFeedback.current
    val palette = Theme.palette
    val accent = Theme.accent
    val selectedIndex = items.indexOfFirst { it.id == selectionId }.coerceAtLeast(0)
    val select: (AbstandBrowseStripItem) -> Unit = { item ->
        if (item.id != selectionId) {
            haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
            onSelect(item.id)
        }
    }
    Row(modifier.fillMaxWidth().heightIn(min = AppTheme.Layout.minTapTarget), verticalAlignment = Alignment.CenterVertically) {
        if (leading != null) Box(Modifier.padding(start = AppTheme.Layout.tabPaddingH)) { leading() }
        if (items.none { it.coverItemId != null }) {
            CompactIconTabs(items, selectedIndex, select, pinFirst && items.size > 1, Modifier.weight(1f))
        } else {
            PrimaryScrollableTabRow(
                selectedTabIndex = selectedIndex,
                modifier = Modifier.weight(1f),
                containerColor = Color.Transparent,
                contentColor = accent,
                edgePadding = AppTheme.Layout.stackSpacing,
                indicator = {
                    TabRowDefaults.PrimaryIndicator(
                        Modifier.tabIndicatorOffset(selectedIndex, matchContentSize = true),
                        width = Dp.Unspecified,
                        color = accent,
                    )
                },
                divider = {},
            ) {
                items.forEachIndexed { index, item ->
                    Tab(
                        selected = index == selectedIndex,
                        onClick = { select(item) },
                        text = { Text(item.label, style = AppType.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                        selectedContentColor = accent,
                        unselectedContentColor = palette.textSecondary,
                    )
                }
            }
        }
    }
}

/**
 * Icon-Tabs (stashy `CompactIconTabs`): eigene Zeile statt `ScrollableTabRow`, weil diese jedem
 * Tab 90 dp Mindestbreite gibt und reine Symbol-Tabs weit auseinanderzieht.
 */
@Composable
private fun CompactIconTabs(
    items: List<AbstandBrowseStripItem>,
    selectedIndex: Int,
    onSelect: (AbstandBrowseStripItem) -> Unit,
    pinFirst: Boolean,
    modifier: Modifier,
) {
    val scrolling = if (pinFirst) items.drop(1) else items
    val offset = if (pinFirst) 1 else 0
    val scrollIndex = (selectedIndex - offset).takeIf { it >= 0 }
    val state = rememberLazyListState()
    LaunchedEffect(scrollIndex) { scrollIndex?.let { state.animateScrollToItem((it - 1).coerceAtLeast(0)) } }
    Row(modifier.heightIn(min = AppTheme.Layout.minTapTarget), verticalAlignment = Alignment.CenterVertically) {
        if (pinFirst) {
            Spacer(Modifier.width(AppTheme.Layout.stackSpacing))
            CompactIconTab(items[0], selectedIndex == 0, onSelect)
        }
        LazyRow(
            Modifier.weight(1f).heightIn(min = AppTheme.Layout.minTapTarget),
            state = state,
            contentPadding = PaddingValues(horizontal = AppTheme.Layout.stackSpacing),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            items(scrolling.size, key = { scrolling[it].id }) { i ->
                CompactIconTab(scrolling[i], i + offset == selectedIndex, onSelect)
            }
        }
    }
}

@Composable
private fun CompactIconTab(item: AbstandBrowseStripItem, isSelected: Boolean, onSelect: (AbstandBrowseStripItem) -> Unit) {
    val accent = Theme.accent
    val color = if (isSelected) accent else Theme.palette.textSecondary
    Box(
        Modifier
            .heightIn(min = AppTheme.Layout.minTapTarget)
            .clip(RoundedCornerShape(AppTheme.Layout.cornerMedium))
            .clickable(role = Role.Tab) { onSelect(item) }
            .semantics { selected = isSelected }
            .padding(horizontal = AppTheme.Layout.rowSpacing),
        contentAlignment = Alignment.Center,
    ) {
        Row(
            Modifier.padding(vertical = AppTheme.Layout.compactSpacing).animateContentSize(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.inlineSpacing),
        ) {
            Icon(item.icon, if (isSelected) null else item.label, tint = color, modifier = Modifier.size(AppTheme.Layout.iconSize))
            if (isSelected) Text(item.label, style = AppType.titleSmall, color = color, maxLines = 1)
        }
        if (isSelected) {
            Box(
                Modifier
                    .align(Alignment.BottomCenter)
                    .width(AppTheme.Layout.browseTabIndicatorWidth)
                    .height(AppTheme.Layout.browseTabIndicatorHeight)
                    .background(accent, RoundedCornerShape(topStart = AppTheme.Layout.browseTabIndicatorHeight, topEnd = AppTheme.Layout.browseTabIndicatorHeight)),
            )
        }
    }
}

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
    AbstandBrowseTabs(ordered, selectionId, onSelect, modifier, pinFirst = pinnedLeadingItem != null)
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
    AbstandBrowseTabs(ordered, secondarySelectionId, onSelectSecondary, modifier, leading, pinFirst = pinnedLeadingItem != null)
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
