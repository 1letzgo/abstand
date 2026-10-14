package de.letzgo.abstand.ui.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.spring
import androidx.compose.animation.expandHorizontally
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkHorizontally
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxHeight
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.IosType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.semibold
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

/** iOS: `AbstandExpandingDockChip` — Kreis (inaktiv) bzw. Kapsel mit Label (aktiv). */
@Composable
private fun ExpandingDockChip(item: AbstandBrowseStripItem, isSelected: Boolean, onClick: () -> Unit) {
    val dock = AppTheme.ExpandingDock
    val colors = AppTheme.ExpandingDock.Colors.of(Theme.palette, Theme.accent)
    val shape = if (isSelected) RoundedCornerShape(percent = 50) else CircleShape
    Surface(
        onClick = onClick,
        shape = shape,
        color = if (isSelected) colors.activeBackground else colors.inactiveBackground,
        contentColor = if (isSelected) colors.activeForeground else colors.inactiveForeground,
        shadowElevation = if (isSelected) AppTheme.CardElevation.Subtle.shadowElevation else 0.dp,
        modifier = Modifier
            .height(dock.activeHeight)
            .animateContentSize(spring(dampingRatio = 0.72f, stiffness = dock.selectionAnimation.stiffness))
            .semantics {
                selected = isSelected
                contentDescription = item.label
                stateDescription = if (isSelected) "Selected" else ""
            },
    ) {
        Row(
            Modifier.padding(
                start = if (isSelected) dock.activeLeadingPadding else dock.inactiveIconSideInset,
                end = if (isSelected) dock.activeTrailingPadding else dock.inactiveIconSideInset,
            ).fillMaxHeight(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(dock.iconLabelSpacing),
        ) {
            if (item.coverItemId != null) {
                Box(Modifier.size(if (isSelected) dock.activeCoverSize else dock.iconSize).clip(CircleShape)) {
                    CoverImage(itemId = item.coverItemId, modifier = Modifier.fillMaxSize())
                }
            } else {
                Icon(
                    item.icon, contentDescription = null,
                    modifier = Modifier.size(dock.iconSize),
                    tint = if (isSelected) colors.activeForeground else colors.inactiveForeground.copy(alpha = dock.inactiveIconOpacity),
                )
            }
            AnimatedVisibility(
                visible = isSelected,
                enter = fadeIn() + expandHorizontally(),
                exit = fadeOut() + shrinkHorizontally(),
            ) {
                Text(item.label, style = IosType.subheadline.semibold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
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
            BrowseStripDropdownPill(libraryPickerItems, libraryPickerSelectionId, SF.booksVerticalFill, "Library", onSelectLibrary)
            BrowseStripDropdownPill(secondaryItems, secondarySelectionId, SF.squareGrid2x2, secondaryAccessibilityLabel, onSelectSecondary)
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

/** iOS: `AbstandBrowseStripDropdownPill` — Akzent-Kapsel mit aktuellem Eintrag, Tippen öffnet das Menü. */
@Composable
private fun RowScope.BrowseStripDropdownPill(
    items: List<AbstandBrowseStripItem>,
    selectionId: String,
    fallbackIcon: ImageVector,
    accessibilityLabel: String,
    onSelect: (String) -> Unit,
) {
    val dock = AppTheme.ExpandingDock
    val colors = AppTheme.ExpandingDock.Colors.of(Theme.palette, Theme.accent)
    val current = items.firstOrNull { it.id == selectionId } ?: items.firstOrNull()
    var expanded by remember { mutableStateOf(false) }
    Box(Modifier.weight(1f)) {
        Surface(
            onClick = { expanded = true },
            shape = RoundedCornerShape(percent = 50),
            color = colors.activeBackground,
            contentColor = colors.activeForeground,
            modifier = Modifier.fillMaxWidth().height(dock.activeHeight).semantics {
                contentDescription = "$accessibilityLabel: ${current?.label.orEmpty()}"
            },
        ) {
            Row(
                Modifier.padding(start = dock.activeLeadingPadding, end = dock.activeTrailingPadding),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(dock.iconLabelSpacing),
            ) {
                Icon(current?.icon ?: fallbackIcon, contentDescription = null, modifier = Modifier.size(dock.iconSize))
                Text(
                    current?.label.orEmpty(), style = IosType.subheadline.semibold, maxLines = 1,
                    overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
                )
                Icon(SF.chevronUpChevronDown, contentDescription = null, modifier = Modifier.size(dock.iconSize))
            }
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            items.forEach { item ->
                DropdownMenuItem(
                    text = { Text(item.label) },
                    leadingIcon = { Icon(item.icon, contentDescription = null) },
                    trailingIcon = if (item.id == selectionId) ({ Icon(SF.checkmark, contentDescription = "Selected") }) else null,
                    onClick = {
                        expanded = false
                        if (item.id != selectionId) onSelect(item.id)
                    },
                )
            }
        }
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
