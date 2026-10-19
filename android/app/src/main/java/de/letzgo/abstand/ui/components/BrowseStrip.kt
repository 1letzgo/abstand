package de.letzgo.abstand.ui.components

import androidx.compose.material3.TabRowDefaults.tabIndicatorOffset
import androidx.compose.material3.TabRowDefaults
import androidx.compose.material3.Tab
import androidx.compose.material3.PrimaryScrollableTabRow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.Surface
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.material3.HorizontalDivider
import androidx.compose.foundation.layout.Column
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.AppType
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.draw.clip
import androidx.compose.material3.Text
import androidx.compose.material3.Icon
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
import androidx.compose.animation.animateContentSize
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
 * links die Bibliothek als kompakte Pill (nur Symbol + Chevron, Namen im Menü), daneben der Bereich
 * über die restliche Breite — **immer** beide, auch bei nur einer aktiven Bibliothek. Ohne
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
            .padding(start = AppTheme.Layout.tabPaddingH, end = AppTheme.Layout.stackSpacing, top = dock.verticalPadding, bottom = dock.verticalPadding),
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
    actions: (@Composable RowScope.() -> Unit)? = null,
    scrollToTopTrigger: Any? = null,
    onRefresh: (suspend () -> Unit)? = null,
    strip: @Composable () -> Unit = {},
    sectionSpacing: Dp = AppTheme.Layout.sectionSpacing,
    /**
     * `true`: Liste ohne horizontales Padding — Sektionen setzen `tabPaddingH` selbst, horizontale
     * Reihen laufen randlos mit Innenabstand (Material-„uncontained carousel“).
     */
    fullBleed: Boolean = false,
    /** Optional eigener Listen-Zustand (Home: Pill springt zu Regalen und folgt der Scroll-Position). */
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
        header = if (showsStrip) strip else null,
    ) { padding ->
        holder.SaveableStateProvider(selection) {
            val ownState = rememberLazyListState()
            val state = listState ?: ownState
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

/**
 * Bereichsumschalter als Icon-Tabs (wie stashy `NativeTabStrip`): nur Symbol, der aktive Tab
 * Symbol + Label mit Akzent-Indikator — für Bereiche ohne Bibliothek (Settings), wo eine Pill
 * mehr Platz kostet als sie bringt.
 */
@Composable
fun AbstandBrowseIconTabs(
    items: List<AbstandBrowseStripItem>,
    selectionId: String,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (items.isEmpty()) return
    val haptics = LocalHapticFeedback.current
    val selectedIndex = items.indexOfFirst { it.id == selectionId }.coerceAtLeast(0)
    CompactIconTabs(
        items, selectedIndex,
        { item ->
            if (item.id != selectionId) {
                haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                onSelect(item.id)
            }
        },
        pinFirst = false,
        modifier = modifier.fillMaxWidth(),
    )
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
    Column(modifier) {
    Row(Modifier.fillMaxWidth().heightIn(min = AppTheme.Layout.minTapTarget), verticalAlignment = Alignment.CenterVertically) {
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
    // M3 Tabs: Trennlinie outlineVariant unter der Leiste.
    HorizontalDivider(thickness = AppTheme.Layout.hairlineWidth, color = Theme.palette.scheme.outlineVariant)
    }
}

/**
 * M3 Primary Tab (Symbol über Label, 64 dp): gewählt `primary` mit 3-dp-Indikator, sonst
 * `onSurfaceVariant`. Label immer sichtbar (statt iOS-Dock „nur aktiv mit Label“).
 */
@Composable
private fun CompactIconTab(item: AbstandBrowseStripItem, isSelected: Boolean, onSelect: (AbstandBrowseStripItem) -> Unit) {
    val accent = Theme.accent
    val color = if (isSelected) accent else Theme.palette.textSecondary
    Box(
        Modifier
            .heightIn(min = AppTheme.Layout.primaryTabHeight)
            .clickable(role = Role.Tab) { onSelect(item) }
            .semantics { selected = isSelected }
            .padding(horizontal = AppTheme.Layout.rowSpacing),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            Modifier.padding(vertical = AppTheme.Layout.stackSpacing),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.hairlineSpacing),
        ) {
            Icon(item.icon, contentDescription = null, tint = color, modifier = Modifier.size(AppTheme.Layout.iconSize))
            Text(item.label, style = AppType.titleSmall, color = color, maxLines = 1)
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
 * iOS: `AbstandExpandingDockBrowseStrip` / `SettingsIconStrip` — Bereichs-Buttons: alle in derselben
 * eckigen Form (abgerundetes Rechteck, gleiche Höhe); inaktiv nur Symbol auf tonaler Fläche, der
 * aktive Bereich farblich markiert (Akzent) mit Symbol + Label. Horizontal scrollbar, der aktive
 * Bereich wird ins Bild gescrollt.
 */
@Composable
fun AbstandDockButtons(
    items: List<AbstandBrowseStripItem>,
    selectionId: String,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (items.isEmpty()) return
    val haptics = LocalHapticFeedback.current
    val dock = AppTheme.ExpandingDock
    val state = rememberLazyListState()
    val selectedIndex = items.indexOfFirst { it.id == selectionId }
    LaunchedEffect(selectedIndex) { if (selectedIndex >= 0) state.animateScrollToItem((selectedIndex - 1).coerceAtLeast(0)) }
    LazyRow(
        modifier.fillMaxWidth(),
        state = state,
        contentPadding = PaddingValues(start = AppTheme.Layout.tabPaddingH, end = AppTheme.Layout.stackSpacing, top = dock.verticalPadding, bottom = dock.verticalPadding),
        horizontalArrangement = Arrangement.spacedBy(dock.itemSpacing),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        items(items.size, key = { items[it].id }) { i ->
            val item = items[i]
            DockSectionButton(item, item.id == selectionId) {
                if (item.id != selectionId) {
                    haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    onSelect(item.id)
                }
            }
        }
    }
}

/** Ein Bereichs-Button: eckige Fläche, aktiv in Akzentfarbe mit Label, inaktiv nur Symbol. */
@Composable
private fun DockSectionButton(item: AbstandBrowseStripItem, isSelected: Boolean, onClick: () -> Unit) {
    val dock = AppTheme.ExpandingDock
    val palette = Theme.palette
    val container = if (isSelected) Theme.accent else palette.scheme.secondaryContainer
    val content = if (isSelected) Theme.onAccent else palette.scheme.onSecondaryContainer
    Surface(
        onClick = onClick,
        shape = RoundedCornerShape(AppTheme.Layout.cornerSmall),
        color = container,
        contentColor = content,
        modifier = Modifier
            .height(dock.activeHeight)
            .widthIn(min = dock.activeHeight)
            .animateContentSize()
            .semantics {
                selected = isSelected
                role = Role.Tab
                contentDescription = item.label
            },
    ) {
        Row(
            Modifier.padding(horizontal = if (isSelected) dock.activeLeadingPadding else 0.dp),
            horizontalArrangement = Arrangement.spacedBy(dock.iconLabelSpacing, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(item.icon, contentDescription = null, modifier = Modifier.size(dock.iconSize))
            if (isSelected) Text(item.label, style = AppType.labelLarge, maxLines = 1)
        }
    }
}

/**
 * Standard-Material-3-Tabs (`PrimaryScrollableTabRow`, Text-Tabs, 48 dp — gleiche Höhe wie die
 * Pill-Leisten der anderen Tabs) als Bereichsumschalter in der Kopfzeile. Akzent für das aktive
 * Label und den Indikator, kein Trenner (die Kopfzeile hat keinen).
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
                color = accent,
            )
        },
        divider = {},
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
