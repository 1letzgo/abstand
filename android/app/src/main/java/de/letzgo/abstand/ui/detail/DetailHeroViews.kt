package de.letzgo.abstand.ui.detail

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.downloads.DownloadManager
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.DetailMetaLabelIcon
import de.letzgo.abstand.ui.AppType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.abstandCardChrome
import de.letzgo.abstand.ui.components.abstandCardElevation
import de.letzgo.abstand.ui.components.AbstandIconButton
import de.letzgo.abstand.ui.components.AbstandProgressRing
import de.letzgo.abstand.ui.components.AbstandTextButton
import de.letzgo.abstand.ui.components.AbstandCapsLabel
import de.letzgo.abstand.ui.components.AbstandProminentButton
import de.letzgo.abstand.ui.components.AbstandIconButtonStyle

/** iOS: `DetailHeroLayoutMetrics`. */
object DetailHeroLayoutMetrics {
    val coverTopPadding: Dp = AppTheme.Layout.tightSpacing
    val squareCoverMaxWidth = 280.dp
    val coverCornerRadius = AppTheme.Layout.cornerMedium
    val titleTopSpacing: Dp = AppTheme.Layout.detailMetaAfterPlaySpacing
    val heroInfoLineSpacing = AppTheme.Layout.tightSpacing
    /** Runde Nebenaktionen und Play-Kapsel (M3: 56 dp wie FAB; kompakt 48 dp = Touch-Ziel). */
    val sideControlSize = AppTheme.Layout.fabSize
    val compactSideControlSize = AppTheme.Layout.minTapTarget
    val primaryControlHeight = AppTheme.Layout.fabSize
    val compactPrimaryControlHeight = AppTheme.Layout.minTapTarget
    const val singlePrimaryWidthFraction = 0.54f
    val actionRowSpacing = 16.dp
    val compactActionRowSpacing: Dp = AppTheme.Layout.withinSectionSpacing
}

/** iOS: `DetailMetaLayoutMetrics`. */
object DetailMetaLayoutMetrics {
    val labelToContentSpacing: Dp = AppTheme.Layout.compactSpacing
    val linkRowSpacing: Dp = AppTheme.Layout.withinSectionSpacing
    val disclosureContentTopPadding: Dp = AppTheme.Layout.compactSpacing
    val sectionCardSpacing: Dp = AppTheme.Layout.withinSectionSpacing
    const val descriptionCollapsedLineLimit = 4
}


/** iOS: `\.detailSectionCardBackground` — Kartenfläche aus dem Cover-Tint (`null` = Palette-`card`). */
val LocalDetailSectionCardBackground = compositionLocalOf<Color?> { null }

private val DetailSectionCardShape = RoundedCornerShape(AppTheme.Layout.detailSectionCardCornerRadius)

/** iOS: `DetailHeroCoverFrame` — Cover max. 280 dp, zentriert, 12-dp-Ecken (M3 medium), leichter Schatten. */
@Composable
fun DetailHeroCoverFrame(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val shape = RoundedCornerShape(DetailHeroLayoutMetrics.coverCornerRadius)
    Box(modifier.fillMaxWidth().padding(top = DetailHeroLayoutMetrics.coverTopPadding), contentAlignment = Alignment.Center) {
        Box(
            Modifier.widthIn(max = DetailHeroLayoutMetrics.squareCoverMaxWidth).fillMaxWidth().aspectRatio(1f)
                .abstandCardElevation(shape).clip(shape),
        ) { content() }
    }
}

/**
 * iOS: `DetailHeroInfoSection` — Titel (`title.bold`), Autoren als Akzent-Links (oder Untertitel),
 * Dauer · Jahr; zentriert.
 */
@Composable
fun DetailHeroInfoSection(
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    authorLinks: List<Pair<String, String>> = emptyList(),
    onAuthorTap: ((String, String) -> Unit)? = null,
    tertiaryLine: String = "",
) {
    val palette = Theme.palette
    Column(
        modifier.fillMaxWidth().padding(top = DetailHeroLayoutMetrics.titleTopSpacing),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(DetailHeroLayoutMetrics.heroInfoLineSpacing),
    ) {
        Text(title, style = AppType.headlineSmall, color = palette.textPrimary, textAlign = TextAlign.Center)
        if (authorLinks.isNotEmpty()) {
            Row(horizontalArrangement = Arrangement.Center) {
                authorLinks.forEachIndexed { idx, (id, name) ->
                    if (idx > 0) Text(", ", style = AppType.titleMedium, color = palette.textPrimary)
                    Text(
                        name, style = AppType.titleMedium, color = Theme.accent,
                        modifier = Modifier.clickable(enabled = onAuthorTap != null) { onAuthorTap?.invoke(id, name) },
                    )
                }
            }
        } else {
            subtitle?.trim()?.takeIf { it.isNotEmpty() && it != "—" }?.let {
                Text(it, style = AppType.titleMedium, color = palette.textPrimary, textAlign = TextAlign.Center)
            }
        }
        if (tertiaryLine.isNotEmpty()) {
            Text(tertiaryLine, style = AppType.bodyMedium, color = palette.textSecondary, textAlign = TextAlign.Center)
        }
    }
}

/** iOS: `DetailHeroPrimaryButton.Kind`. */
enum class DetailHeroPrimaryKind(val title: String, val accessibilityLabel: String) {
    Play("Play", "Play"),
    Pause("Pause", "Pause"),
    Read("Read", "Read eBook");

    val icon: ImageVector get() = when (this) {
        Play -> SF.playFill
        Pause -> SF.pauseFill
        Read -> SF.bookClosedFill
    }
}

/** iOS: `DetailHeroMediaAction` — Mark-Kreis + Primär-Pille einer Medienart (Hören/Lesen). */
data class DetailHeroMediaAction(
    val id: String,
    val markIcon: ImageVector,
    val markAccessibilityLabel: String,
    val markEnabled: Boolean,
    val onMark: () -> Unit,
    val kind: DetailHeroPrimaryKind,
    val progress01: Double,
    val isFinished: Boolean,
    val primaryEnabled: Boolean,
    val onPrimary: () -> Unit,
)

/**
 * iOS: `DetailHeroCircularButton` — Nebenaktion „fertig“ als M3 Tonal Icon Button (Toggle):
 * offen `surfaceContainerHighest`/`onSurfaceVariant`, „fertig“ (ausgewählt)
 * `secondaryContainer`/`onSecondaryContainer`; deaktiviert onSurface 12 %/38 % (Vorlage).
 */
@Composable
fun DetailHeroCircularButton(icon: ImageVector, isFinished: Boolean, enabled: Boolean, size: Dp, description: String, onClick: () -> Unit) {
    val scheme = Theme.palette.scheme
    AbstandIconButton(
        icon,
        description,
        onClick = onClick,
        enabled = enabled,
        style = AbstandIconButtonStyle.Tonal,
        size = size,
        tint = if (isFinished) scheme.onSecondaryContainer else scheme.onSurfaceVariant,
        containerColor = if (isFinished) scheme.secondaryContainer else scheme.surfaceContainerHighest,
    )
}

/** Deckkraft der Fortschritts-Überlagerung im gefüllten Play-Button (M3-State-Layer-Stufe „pressed“). */
private const val HeroProgressOverlayAlpha = 0.16f

/**
 * iOS: `DetailHeroPrimaryButton` — Hauptaktion der Detailseite als M3 Filled Button
 * ([AbstandProminentButton], Akzentfläche, `onAccent`-Beschriftung). Der Fortschritt liegt als
 * dezente `onAccent`-Überlagerung von links über der Fläche („fertig“ = ganz überlagert) und
 * steht zusätzlich in der `stateDescription`.
 */
@Composable
fun DetailHeroPrimaryButton(
    kind: DetailHeroPrimaryKind,
    progress01: Double,
    isFinished: Boolean,
    enabled: Boolean,
    compact: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val overlay = Theme.onAccent.copy(alpha = HeroProgressOverlayAlpha)
    val fill = if (isFinished) 1f else progress01.toFloat().coerceIn(0f, 1f)
    val height = if (compact) DetailHeroLayoutMetrics.compactPrimaryControlHeight else DetailHeroLayoutMetrics.primaryControlHeight
    val textStyle = if (compact) AppType.titleSmall else AppType.titleMedium
    val stateText = when {
        isFinished -> "Finished"
        fill < 0.001f -> "Not started"
        kind == DetailHeroPrimaryKind.Read -> "${(fill * 100).toInt()} percent read"
        else -> "${(fill * 100).toInt()} percent listened"
    }
    AbstandProminentButton(
        onClick = onClick,
        modifier = modifier
            .height(height)
            .clip(CircleShape)
            .drawWithContent {
                drawContent()
                if (enabled && fill > 0f) drawRect(overlay, size = size.copy(width = size.width * fill))
            }
            .semantics {
                contentDescription = kind.accessibilityLabel
                stateDescription = stateText
            },
        enabled = enabled,
        capsule = true,
    ) {
        Icon(kind.icon, null, modifier = Modifier.size(HeroLabelIconSize))
        Spacer(Modifier.width(AppTheme.Layout.compactSpacing))
        Text(kind.title, style = textStyle, maxLines = 1)
    }
}

/** iOS: `DetailHeroActionsBar` — eine Aktion: [Mark][Play][Platzhalter] zentriert; zwei: [Mark][Play][Read][Mark]. */
@Composable
fun DetailHeroActionsBar(actions: List<DetailHeroMediaAction>, modifier: Modifier = Modifier) {
    if (actions.isEmpty()) return
    if (actions.size > 1) {
        val side = DetailHeroLayoutMetrics.compactSideControlSize
        Row(
            modifier.fillMaxWidth().height(DetailHeroLayoutMetrics.compactPrimaryControlHeight),
            horizontalArrangement = Arrangement.spacedBy(DetailHeroLayoutMetrics.compactActionRowSpacing),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            val a = actions[0]
            val b = actions[1]
            DetailHeroCircularButton(a.markIcon, a.isFinished, a.markEnabled, side, a.markAccessibilityLabel, a.onMark)
            DetailHeroPrimaryButton(a.kind, a.progress01, a.isFinished, a.primaryEnabled, compact = true, Modifier.weight(1f), a.onPrimary)
            DetailHeroPrimaryButton(b.kind, b.progress01, b.isFinished, b.primaryEnabled, compact = true, Modifier.weight(1f), b.onPrimary)
            DetailHeroCircularButton(b.markIcon, b.isFinished, b.markEnabled, side, b.markAccessibilityLabel, b.onMark)
        }
    } else {
        val a = actions[0]
        val side = DetailHeroLayoutMetrics.sideControlSize
        BoxWithConstraints(modifier.fillMaxWidth().height(DetailHeroLayoutMetrics.primaryControlHeight)) {
            val primaryWidth = this.maxWidth * DetailHeroLayoutMetrics.singlePrimaryWidthFraction
            Row(
                Modifier.fillMaxSize(),
                horizontalArrangement = Arrangement.spacedBy(DetailHeroLayoutMetrics.actionRowSpacing, Alignment.CenterHorizontally),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                DetailHeroCircularButton(a.markIcon, a.isFinished, a.markEnabled, side, a.markAccessibilityLabel, a.onMark)
                DetailHeroPrimaryButton(
                    a.kind, a.progress01, a.isFinished, a.primaryEnabled, compact = false,
                    Modifier.width(primaryWidth), a.onPrimary,
                )
                Spacer(Modifier.size(side))
            }
        }
    }
}

/** Meta-Überschrift (Symbol + Versalien, `footnote.semibold`, `textSecondary`). */
@Composable
fun DetailMetaLabel(title: String) {
    AbstandCapsLabel(title, icon = DetailMetaLabelIcon.icon(title))
}

/** iOS: `DetailDetailSectionCard` — Meta-Karte mit Cover-Tint-Fläche ([LocalDetailSectionCardBackground]). */
@Composable
fun DetailSectionCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    val fill = LocalDetailSectionCardBackground.current ?: Theme.palette.card
    Column(
        modifier.fillMaxWidth()
            .abstandCardChrome(fill, DetailSectionCardShape, AppTheme.CardElevation.Subtle)
            .padding(AppTheme.Layout.detailSectionCardPadding),
        content = content,
    )
}

/** iOS: `DetailMetaField` — Label oben, Inhalt darunter. */
@Composable
fun DetailMetaField(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(DetailMetaLayoutMetrics.labelToContentSpacing)) {
        DetailMetaLabel(title)
        content()
    }
}

/** iOS: `DetailMetaTextBlock`. */
@Composable
fun DetailMetaTextBlock(text: String) {
    Text(text, style = AppType.bodyLarge, color = Theme.palette.textPrimary, modifier = Modifier.fillMaxWidth())
}

/** iOS: `DetailMetaExpandableTextBlock` — vier Zeilen, dann „More"/„Less". */
@Composable
fun DetailMetaExpandableTextBlock(text: String, expanded: Boolean, onToggle: () -> Unit) {
    if (!de.letzgo.abstand.logic.BookDetailLogic.offersExpansion(text, DetailMetaLayoutMetrics.descriptionCollapsedLineLimit)) {
        DetailMetaTextBlock(text)
        return
    }
    Column(Modifier.fillMaxWidth().animateContentSize(), verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.stackSpacing)) {
        Text(
            text, style = AppType.bodyLarge, color = Theme.palette.textPrimary,
            maxLines = if (expanded) Int.MAX_VALUE else DetailMetaLayoutMetrics.descriptionCollapsedLineLimit,
            overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
        )
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
            AbstandTextButton(if (expanded) "Less" else "More", onToggle, emphasized = true, compact = true)
        }
    }
}

/** iOS: `DetailMetaLink` — Akzent-Text, öffnet eine Entity. */
@Composable
fun DetailMetaLink(title: String, onClick: () -> Unit) {
    Text(
        title, style = AppType.bodyLarge, color = Theme.accent,
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = AppTheme.Layout.hairlineSpacing),
    )
}

/** iOS: `DetailMetaDisclosure` — aufklappbare Karte (Chapters, Bookmarks, Listening history). */
@Composable
fun DetailMetaDisclosure(title: String, expanded: Boolean, onToggle: () -> Unit, content: @Composable ColumnScope.() -> Unit) {
    val fill = LocalDetailSectionCardBackground.current ?: Theme.palette.card
    Column(
        Modifier.fillMaxWidth()
            .abstandCardChrome(fill, DetailSectionCardShape, AppTheme.CardElevation.Subtle)
            .animateContentSize(),
    ) {
        Row(
            Modifier.fillMaxWidth().clickable(onClick = onToggle).padding(AppTheme.Layout.detailSectionCardPadding),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(Modifier.weight(1f)) { DetailMetaLabel(title) }
            Icon(
                SF.chevronRight, contentDescription = if (expanded) "Collapse" else "Expand", tint = Theme.accent,
                modifier = Modifier.size(HeroLabelIconSize).rotate(if (expanded) 90f else 0f),
            )
        }
        if (expanded) {
            Column(
                Modifier.fillMaxWidth().padding(
                    start = AppTheme.Layout.detailSectionCardPadding, end = AppTheme.Layout.detailSectionCardPadding,
                    bottom = AppTheme.Layout.detailSectionCardPadding,
                ).padding(top = DetailMetaLayoutMetrics.disclosureContentTopPadding),
                content = content,
            )
        }
    }
}

/** Kartenflächen einer Detailseite in der Cover-Tint-Farbfamilie (iOS: `detailSectionCardsTinted`). */
@Composable
fun DetailSectionCardsTinted(card: Color, content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalDetailSectionCardBackground provides card, content = content)
}

/**
 * iOS: `DetailToolbarDownloadItem` — laufend: Fortschrittskreis; wartend: gestrichelter Kreis;
 * geladen: „Remove offline copy"; sonst „Download".
 */
@Composable
fun RowScope.DetailToolbarDownloadItem(storageId: String, onStartDownload: () -> Unit, onRemoveDownload: () -> Unit, enabled: Boolean = true) {
    val active by DownloadManager.activeItemId.collectAsState()
    val progress by DownloadManager.progress.collectAsState()
    val queued by DownloadManager.queuedItemIds.collectAsState()
    val downloaded by AppModel.shared.catalog.downloadedItemIds.collectAsState()
    val accent = Theme.accent
    when {
        active == storageId -> Box(Modifier.size(AppTheme.Layout.minTapTarget), contentAlignment = Alignment.Center) {
            AbstandProgressRing(progress, color = accent, contentDescription = "Downloading")
        }
        storageId in queued -> Box(Modifier.size(AppTheme.Layout.minTapTarget), contentAlignment = Alignment.Center) {
            Icon(SF.circleDashed, contentDescription = "Queued", tint = accent)
        }
        storageId in downloaded -> AbstandIconButton(
            SF.arrowDownCircleBadgeXmark,
            "Remove offline copy",
            onClick = onRemoveDownload,
            enabled = enabled,
            tint = accent,
        )
        else -> AbstandIconButton(SF.arrowDownCircle, "Download", onClick = onStartDownload, enabled = enabled, tint = accent)
    }
}

/** Symbol in Hero-Knopf-Labels und Disclosure-Chevrons. */
private val HeroLabelIconSize = AppTheme.Layout.smallIconSize
