package de.letzgo.abstand.ui.components

import androidx.compose.foundation.border
import androidx.compose.foundation.BorderStroke
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
import androidx.compose.foundation.layout.BoxWithConstraints
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
import androidx.compose.material3.minimumInteractiveComponentSize
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
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.AppType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.library.LibraryRowLayout

// Pillen, Badges und Chips — Cover-Overlays, Status-Labels, Filter-/Browse-Chips.

/** iOS: `ContinueListeningHeroCoverPillMetrics` + `LibraryCoverCornerBadge`. */
object AbstandCoverPillMetrics {
    /** Abstand der Pille zum Cover-Rand. */
    val inset = AppTheme.Layout.inlineSpacing
    val iconSize = 12.dp
    /** Fortschrittsring eines laufenden Downloads. */
    val spinnerSize = 12.dp
    /** Symbol im runden Eck-Badge ([AbstandCoverCornerBadge]). */
    val cornerBadgeIconSize = 12.dp
}

/** iOS: `ContinueListeningHeroCoverPill` — dunkle Kapsel auf Covern (Typ, Download, Anzahl). */
@Composable
fun AbstandCoverPill(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(
        modifier
            .padding(AbstandCoverPillMetrics.inset)
            .background(Theme.palette.coverPlayBadgeBackground, CircleShape)
            .padding(horizontal = AppTheme.Layout.inlineSpacing, vertical = AppTheme.Layout.pillVerticalPadding),
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
        Text(text, style = AppType.labelSmall, color = AppTheme.coverOverlayForeground, maxLines = 1)
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

/** Symbolgröße der Status-Badges (iOS: `.font(.caption)` ≈ 14 pt; M3-Raster 16 dp). */
private val StatusBadgeIconSize = 16.dp
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
    // M3: Akzent-Badge = secondaryContainer / onSecondaryContainer (statt Akzent mit 20 % Alpha).
    val foreground = if (tone == AbstandBadgeTone.Accent) palette.scheme.onSecondaryContainer else palette.textSecondary
    val container = when {
        containerColor != Color.Unspecified -> containerColor
        tone == AbstandBadgeTone.Accent -> palette.scheme.secondaryContainer
        else -> palette.card
    }
    Row(
        modifier
            .background(container, CircleShape)
            .padding(horizontal = AppTheme.Layout.inlineSpacing, vertical = AppTheme.Layout.tightSpacing),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.tightSpacing),
    ) {
        if (icon != null) Icon(icon, contentDescription = null, tint = foreground, modifier = Modifier.size(AbstandCoverPillMetrics.iconSize))
        Text(text, style = AppType.labelSmall, color = foreground, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/**
 * Filter-/Kategorie-Chip (iOS: Dock-Farben — aktiv Akzent, inaktiv `palette.card`). M3 Filter
 * Chip: 32 dp hoch, 8-dp-Ecken, 16 dp seitlich (8 dp mit Symbol), 18-dp-Symbole, `labelLarge`;
 * Trefferfläche 48 dp.
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
    // M3 Filter Chip: gewählt = secondaryContainer + Häkchen, sonst transparent mit outlineVariant-Rand.
    val leading = icon ?: if (selected) SF.checkmark else null
    Row(
        modifier
            .minimumInteractiveComponentSize()
            .height(AppTheme.Layout.chipHeight)
            .clip(AbstandChipShape)
            .background(if (selected) colors.activeBackground else Color.Transparent)
            .let { if (selected) it else it.border(AppTheme.Layout.hairlineWidth, Theme.palette.scheme.outlineVariant, AbstandChipShape) }
            .clickable(enabled = enabled, role = Role.Tab, onClick = onClick)
            .semantics { this.selected = selected }
            .padding(
                start = if (leading != null) AppTheme.Layout.inlineSpacing else AppTheme.Layout.screenPadding,
                end = if (trailingIcon != null) AppTheme.Layout.inlineSpacing else AppTheme.Layout.screenPadding,
            ),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.inlineSpacing),
    ) {
        if (leading != null) Icon(leading, contentDescription = null, tint = foreground, modifier = Modifier.size(AbstandChipIconSize))
        Text(label, style = AppType.labelLarge, color = foreground, maxLines = 1, overflow = TextOverflow.Ellipsis)
        if (trailingIcon != null) Icon(trailingIcon, contentDescription = null, tint = foreground, modifier = Modifier.size(AbstandChipIconSize))
    }
}

private val AbstandChipIconSize = AppTheme.Layout.smallIconSize
private val AbstandChipShape = RoundedCornerShape(AppTheme.Layout.cornerSmall)

/**
 * iOS: `AbstandExpandingDockChip` (Kreis → Akzent-Kapsel). Android: M3 Filter Chip mit immer
 * sichtbarem Label — gewählt secondaryContainer mit Häkchen (bzw. Cover), sonst outlineVariant-
 * Rand mit Symbol/Cover. Einziger Dock-Chip (Browse-Strip, Podcast-Shows).
 */
@Composable
fun AbstandDockChip(
    label: String,
    icon: ImageVector,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    coverItemId: String? = null,
    /** Aktiver Chip: Häkchen statt Symbol (Filter-Chip-Stil); `false` = Symbol bleibt (Dock-Buttons). */
    checkmarkWhenSelected: Boolean = true,
) {
    val dock = AppTheme.ExpandingDock
    val colors = AppTheme.ExpandingDock.Colors.of(Theme.palette, Theme.accent)
    val foreground = if (selected) colors.activeForeground else colors.inactiveForeground
    Surface(
        onClick = onClick,
        shape = AbstandChipShape,
        color = if (selected) colors.activeBackground else Color.Transparent,
        contentColor = foreground,
        border = if (selected) null else BorderStroke(AppTheme.Layout.hairlineWidth, Theme.palette.scheme.outlineVariant),
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
            Modifier.padding(start = dock.activeLeadingPadding, end = dock.activeTrailingPadding).fillMaxHeight(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(dock.iconLabelSpacing),
        ) {
            when {
                coverItemId != null -> Box(Modifier.size(dock.activeCoverSize).clip(CircleShape)) {
                    CoverImage(itemId = coverItemId, modifier = Modifier.fillMaxSize())
                }
                selected && checkmarkWhenSelected -> Icon(SF.checkmark, contentDescription = null, modifier = Modifier.size(dock.iconSize))
                else -> Icon(icon, contentDescription = null, modifier = Modifier.size(dock.iconSize))
            }
            Text(label, style = AppType.labelLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
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
    /** Kompakt: nur Symbol + Chevron, Breite nach Inhalt (Bibliotheks-Pill); Namen stehen im Menü. */
    iconOnly: Boolean = false,
) {
    val dock = AppTheme.ExpandingDock
    val colors = AppTheme.ExpandingDock.Colors.of(Theme.palette, Theme.accent)
    val current = items.firstOrNull { it.id == selectionId } ?: items.firstOrNull()
    var expanded by remember { mutableStateOf(false) }
    BoxWithConstraints(modifier) {
        val showLeadingIcon = iconOnly || maxWidth >= AppTheme.Layout.dropdownPillIconMinWidth
        Surface(
            onClick = { expanded = true },
            shape = AbstandChipShape,
            color = colors.activeBackground,
            contentColor = colors.activeForeground,
            modifier = (if (iconOnly) Modifier else Modifier.fillMaxWidth()).height(dock.activeHeight).semantics {
                contentDescription = "$accessibilityLabel: ${current?.label.orEmpty()}"
            },
        ) {
            Row(
                Modifier.padding(start = dock.activeLeadingPadding, end = dock.activeTrailingPadding),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(dock.iconLabelSpacing),
            ) {
                // Schmale Pill (zwei Pills + Aktionen in einer Zeile): Symbol weglassen, damit das Label passt.
                if (showLeadingIcon) Icon(current?.icon ?: fallbackIcon, contentDescription = null, modifier = Modifier.size(dock.iconSize))
                if (!iconOnly) {
                    Text(
                        current?.label ?: accessibilityLabel, style = AppType.labelLarge, maxLines = 1,
                        overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
                    )
                }
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

/**
 * Statische Akzent-Pill im Stil der Dropdown-Pills (Symbol + Label, ohne Chevron und Menü) —
 * Kopfzeile von Screens ohne Bereichsauswahl (Home).
 */
@Composable
fun AbstandStaticPill(label: String, icon: ImageVector, modifier: Modifier = Modifier) {
    val dock = AppTheme.ExpandingDock
    val colors = AppTheme.ExpandingDock.Colors.of(Theme.palette, Theme.accent)
    Surface(
        shape = RoundedCornerShape(percent = 50),
        color = colors.activeBackground,
        contentColor = colors.activeForeground,
        modifier = modifier.height(dock.activeHeight).semantics(mergeDescendants = true) { heading() },
    ) {
        Row(
            Modifier.padding(start = dock.activeLeadingPadding, end = dock.activeTrailingPadding),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(dock.iconLabelSpacing),
        ) {
            Icon(icon, contentDescription = null, modifier = Modifier.size(dock.iconSize))
            Text(label, style = AppType.labelLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}
