package de.letzgo.abstand.ui.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.spring
import androidx.compose.animation.expandHorizontally
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkHorizontally
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.IosType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.medium
import de.letzgo.abstand.ui.semibold
import de.letzgo.abstand.ui.library.LibraryRowLayout

// Pillen, Badges und Chips — Cover-Overlays, Status-Labels, Filter-/Browse-Chips.

/** iOS: `ContinueListeningHeroCoverPillMetrics` + `LibraryCoverCornerBadge`. */
object AbstandCoverPillMetrics {
    /** Abstand der Pille zum Cover-Rand. */
    val inset = 8.dp
    val iconSize = 12.dp
    /** Fortschrittsring eines laufenden Downloads. */
    val spinnerSize = 13.dp
    /** Symbol im runden Eck-Badge ([AbstandCoverCornerBadge]). */
    val cornerBadgeIconSize = 11.dp
}

/** iOS: `ContinueListeningHeroCoverPill` — dunkle Kapsel auf Covern (Typ, Download, Anzahl). */
@Composable
fun AbstandCoverPill(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(
        modifier
            .padding(AbstandCoverPillMetrics.inset)
            .background(Theme.palette.coverPlayBadgeBackground, CircleShape)
            .padding(horizontal = AppTheme.Layout.compactSpacing, vertical = AppTheme.Layout.pillVerticalPadding),
        contentAlignment = Alignment.Center,
    ) { content() }
}

/** [AbstandCoverPill] mit Symbol (Medientyp, „Downloaded“). */
@Composable
fun AbstandCoverPillIcon(icon: ImageVector, contentDescription: String?, modifier: Modifier = Modifier) {
    AbstandCoverPill(modifier) {
        Icon(icon, contentDescription = contentDescription, tint = AppTheme.coverOverlayForeground, modifier = Modifier.size(AbstandCoverPillMetrics.iconSize))
    }
}

/** [AbstandCoverPill] mit kurzem Text („12 Books“, Rang). */
@Composable
fun AbstandCoverPillText(text: String, modifier: Modifier = Modifier) {
    AbstandCoverPill(modifier) {
        Text(text, style = IosType.caption2.semibold, color = AppTheme.coverOverlayForeground, maxLines = 1)
    }
}

/** iOS: `LibraryCoverCornerBadge` — kleiner runder Badge in einer Cover-Ecke (eBook, Play). */
@Composable
fun AbstandCoverCornerBadge(icon: ImageVector, contentDescription: String?, modifier: Modifier = Modifier) {
    Box(
        modifier.padding(AppTheme.Layout.tightSpacing).size(AppTheme.Layout.coverBadgeSize)
            .background(Theme.palette.coverPlayBadgeBackground, CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = contentDescription, tint = AppTheme.coverOverlayForeground, modifier = Modifier.size(AbstandCoverPillMetrics.cornerBadgeIconSize))
    }
}

/**
 * iOS: `ContinueListeningHeroOfflineBadge` — fertiger Download (Symbol) oder laufender Download
 * (Ring) als [AbstandCoverPill]; sonst nichts.
 */
@Composable
fun AbstandCoverDownloadBadge(isDownloaded: Boolean, isDownloading: Boolean, downloadProgress: Double, modifier: Modifier = Modifier) {
    when {
        isDownloaded -> AbstandCoverPillIcon(SF.arrowDownCircleFill, "Downloaded", modifier)
        isDownloading -> AbstandCoverPill(modifier) {
            AbstandProgressRing(
                downloadProgress,
                color = AppTheme.coverOverlayForeground,
                size = AbstandCoverPillMetrics.spinnerSize,
                contentDescription = "Downloading",
            )
        }
    }
}

/** Symbolgröße der Status-Badges (iOS: `.font(.caption)` ≈ 14 pt). */
private val StatusBadgeIconSize = 14.dp
/** iOS: `LibraryRowLayout.finishedContentOpacity` — „fertig“ zurückgenommen. */
private const val FinishedBadgeOpacity = 0.35f

/**
 * iOS: `LibraryRowStatusBadges` / `HomeCompactCardStatusBadges` — „fertig“ (gedimmt) + Download-
 * Status (Symbol bzw. kleiner Fortschrittsbalken) in `textSecondary`, für Buch-, Home- und
 * Folgen-Zeilen.
 */
@Composable
fun AbstandStatusBadges(isFinished: Boolean, isDownloaded: Boolean, isDownloading: Boolean, downloadProgress: Double, modifier: Modifier = Modifier) {
    val color = Theme.palette.textSecondary
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.compactSpacing), verticalAlignment = Alignment.CenterVertically) {
        if (isFinished) {
            Icon(SF.checkmarkCircleFill, "Finished", tint = color.copy(alpha = color.alpha * FinishedBadgeOpacity), modifier = Modifier.size(StatusBadgeIconSize))
        }
        if (isDownloaded) {
            Icon(SF.arrowDownCircleFill, "Saved offline", tint = color, modifier = Modifier.size(StatusBadgeIconSize))
        } else if (isDownloading) {
            AbstandProgressBar(
                downloadProgress, Modifier.width(AppTheme.Layout.compactIconButtonSize),
                trackColor = color.copy(alpha = 0.2f), fillColor = color, contentDescription = "Downloading",
            )
        }
    }
}

/** Farbgebung von [AbstandBadge]. */
enum class AbstandBadgeTone {
    /** `textSecondary` auf neutraler Fläche (Typ, Quelle, Genre). */
    Neutral,
    /** Akzent auf 20 % Akzent (Rolle „root“, „New“). */
    Accent,
}

/**
 * Kleines Kapsel-Label (Status, Rolle, Typ, Quelle). [containerColor] überschreibt die neutrale
 * Fläche (Standard `palette.card`; auf Karten `palette.background`).
 */
@Composable
fun AbstandBadge(
    text: String,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    tone: AbstandBadgeTone = AbstandBadgeTone.Neutral,
    containerColor: Color = Color.Unspecified,
) {
    val palette = Theme.palette
    val foreground = if (tone == AbstandBadgeTone.Accent) Theme.accent else palette.textSecondary
    val container = when {
        containerColor != Color.Unspecified -> containerColor
        tone == AbstandBadgeTone.Accent -> Theme.accent.copy(alpha = 0.2f)
        else -> palette.card
    }
    Row(
        modifier
            .background(container, CircleShape)
            .padding(horizontal = AppTheme.Layout.inlineSpacing, vertical = AppTheme.Layout.badgeSpacing),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.tightSpacing),
    ) {
        if (icon != null) Icon(icon, contentDescription = null, tint = foreground, modifier = Modifier.size(AbstandCoverPillMetrics.iconSize))
        Text(text, style = IosType.caption2.medium, color = foreground, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/**
 * Text-Chip in Kapselform für Filter- und Kategorie-Leisten (iOS: Dock-Farben — aktiv Akzent,
 * inaktiv `palette.card`). Mindesthöhe `minTapTarget`.
 */
@Composable
fun AbstandChip(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    trailingIcon: ImageVector? = null,
    enabled: Boolean = true,
) {
    val colors = AppTheme.ExpandingDock.Colors.of(Theme.palette, Theme.accent)
    val foreground = if (selected) colors.activeForeground else colors.inactiveForeground
    Row(
        modifier
            .heightIn(min = AppTheme.Layout.minTapTarget)
            .clip(CircleShape)
            .background(if (selected) colors.activeBackground else colors.inactiveBackground)
            .clickable(enabled = enabled, role = Role.Tab, onClick = onClick)
            .semantics { this.selected = selected }
            .padding(horizontal = AppTheme.ExpandingDock.horizontalPadding),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.compactSpacing),
    ) {
        if (icon != null) Icon(icon, contentDescription = null, tint = foreground, modifier = Modifier.size(AbstandChipIconSize))
        Text(label, style = IosType.subheadline.semibold, color = foreground, maxLines = 1, overflow = TextOverflow.Ellipsis)
        if (trailingIcon != null) Icon(trailingIcon, contentDescription = null, tint = foreground, modifier = Modifier.size(AbstandChipIconSize))
    }
}

private val AbstandChipIconSize = 18.dp

/**
 * iOS: `AbstandExpandingDockChip` — inaktiv runder Symbol-/Cover-Knopf, aktiv wachsende
 * Akzent-Kapsel mit Label. Einziger Dock-Chip (Browse-Strip, Settings-Strip, Podcast-Shows).
 */
@Composable
fun AbstandDockChip(
    label: String,
    icon: ImageVector,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    coverItemId: String? = null,
) {
    val dock = AppTheme.ExpandingDock
    val colors = AppTheme.ExpandingDock.Colors.of(Theme.palette, Theme.accent)
    Surface(
        onClick = onClick,
        shape = CircleShape,
        color = if (selected) colors.activeBackground else colors.inactiveBackground,
        contentColor = if (selected) colors.activeForeground else colors.inactiveForeground,
        shadowElevation = if (selected) AppTheme.CardElevation.Subtle.shadowElevation else 0.dp,
        modifier = modifier
            .height(dock.activeHeight)
            .animateContentSize(spring(dampingRatio = 0.72f, stiffness = dock.selectionAnimation.stiffness))
            .semantics {
                this.selected = selected
                role = Role.Tab
                contentDescription = label
                stateDescription = if (selected) "Selected" else ""
            },
    ) {
        Row(
            Modifier.padding(
                start = if (selected) dock.activeLeadingPadding else dock.inactiveIconSideInset,
                end = if (selected) dock.activeTrailingPadding else dock.inactiveIconSideInset,
            ).fillMaxHeight(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(dock.iconLabelSpacing),
        ) {
            if (coverItemId != null) {
                Box(Modifier.size(if (selected) dock.activeCoverSize else dock.iconSize).clip(CircleShape)) {
                    CoverImage(itemId = coverItemId, modifier = Modifier.fillMaxSize())
                }
            } else {
                Icon(
                    icon, contentDescription = null,
                    modifier = Modifier.size(dock.iconSize),
                    tint = if (selected) colors.activeForeground else colors.inactiveForeground.copy(alpha = dock.inactiveIconOpacity),
                )
            }
            AnimatedVisibility(
                visible = selected,
                enter = fadeIn() + expandHorizontally(),
                exit = fadeOut() + shrinkHorizontally(),
            ) {
                Text(label, style = IosType.subheadline.semibold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

/**
 * iOS: `AbstandBrowseStripDropdownPill` — Akzent-Kapsel mit aktuellem Eintrag; Tippen öffnet
 * ein [AbstandMenu] mit allen Einträgen (Bibliothek/Sektion, wenn mehrere Bibliotheken).
 */
@Composable
fun AbstandDropdownPill(
    items: List<AbstandBrowseStripItem>,
    selectionId: String,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
    fallbackIcon: ImageVector = SF.booksVerticalFill,
    accessibilityLabel: String = "Menu",
) {
    val dock = AppTheme.ExpandingDock
    val colors = AppTheme.ExpandingDock.Colors.of(Theme.palette, Theme.accent)
    val current = items.firstOrNull { it.id == selectionId } ?: items.firstOrNull()
    var expanded by remember { mutableStateOf(false) }
    Box(modifier) {
        Surface(
            onClick = { expanded = true },
            shape = RoundedCornerShape(percent = 50),
            color = colors.activeBackground,
            contentColor = colors.activeForeground,
            shadowElevation = AppTheme.CardElevation.Subtle.shadowElevation,
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
                    current?.label ?: accessibilityLabel, style = IosType.subheadline.semibold, maxLines = 1,
                    overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
                )
                Icon(SF.chevronUpChevronDown, contentDescription = null, modifier = Modifier.size(dock.iconSize))
            }
        }
        AbstandMenu(expanded, { expanded = false }) {
            items.forEach { entry ->
                item(entry.label, onClick = { if (entry.id != selectionId) onSelect(entry.id) }, icon = entry.icon, selected = entry.id == selectionId)
            }
        }
    }
}
