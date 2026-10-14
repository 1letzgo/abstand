package de.letzgo.abstand.ui.detail

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.graphics.drawscope.clipRect
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
import de.letzgo.abstand.ui.IosType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.bold
import de.letzgo.abstand.ui.components.abstandCardChrome
import de.letzgo.abstand.ui.components.abstandCardElevation
import de.letzgo.abstand.ui.semibold

/** iOS: `DetailHeroLayoutMetrics`. */
object DetailHeroLayoutMetrics {
    val coverTopPadding: Dp = AppTheme.Layout.tightSpacing
    val squareCoverMaxWidth = 280.dp
    val coverCornerRadius = 8.dp
    val titleTopSpacing: Dp = AppTheme.Layout.detailMetaAfterPlaySpacing
    val heroInfoLineSpacing = 5.dp
    val sideControlSize = 52.dp
    val compactSideControlSize = 46.dp
    val primaryControlHeight = 52.dp
    val compactPrimaryControlHeight = 48.dp
    const val singlePrimaryWidthFraction = 0.54f
    val actionRowSpacing = 16.dp
    val compactActionRowSpacing: Dp = AppTheme.Layout.withinSectionSpacing
    val borderWidth = 1.5.dp
}

/** iOS: `DetailMetaLayoutMetrics`. */
object DetailMetaLayoutMetrics {
    val thumbnailSize = 44.dp
    val labelToContentSpacing: Dp = AppTheme.Layout.compactSpacing
    val labelIconSpacing = 5.dp
    val linkRowSpacing: Dp = AppTheme.Layout.withinSectionSpacing
    val disclosureContentTopPadding: Dp = AppTheme.Layout.compactSpacing
    val sectionCardSpacing: Dp = AppTheme.Layout.withinSectionSpacing
    const val descriptionCollapsedLineLimit = 4
    val labelIconSize = 11.dp
}

/** iOS: `DetailMetaLabelIcon.systemImage(for:)`. */
fun detailMetaLabelIcon(title: String): ImageVector? = when (title.trim().lowercase()) {
    "author" -> SF.personFill
    "narrator", "narrators" -> SF.micFill
    "series" -> SF.booksVerticalFill
    "publisher" -> SF.building2Fill
    "duration", "total runtime" -> SF.clockFill
    "year", "first release" -> SF.calendar
    "genres" -> SF.squareGrid2x2Fill
    "tags" -> SF.tagFill
    "description", "about" -> SF.textAlignleft
    "show", "feed type" -> SF.dotRadiowavesLeftAndRight
    "host", "hosts" -> SF.personWave2Fill
    "subtitle" -> SF.textQuote
    "published" -> SF.calendarBadgeClock
    "categories" -> SF.folderFill
    "episode" -> SF.waveform
    "show notes" -> SF.docText
    "chapters", "episodes" -> SF.listBullet
    "bookmarks" -> SF.bookmarkFill
    "listening history" -> SF.clockArrowCirclepath
    "language" -> SF.globe
    "rss feed", "feed" -> SF.dotRadiowavesUpForward
    "links" -> SF.link
    else -> null
}

/** iOS: `\.detailSectionCardBackground` — Kartenfläche aus dem Cover-Tint (`null` = Palette-`card`). */
val LocalDetailSectionCardBackground = compositionLocalOf<Color?> { null }

private val DetailSectionCardShape = RoundedCornerShape(AppTheme.Layout.detailSectionCardCornerRadius)

/** iOS: `DetailHeroCoverFrame` — Cover max. 280 dp, zentriert, 8-dp-Ecken, leichter Schatten. */
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
        Text(title, style = IosType.title.bold, color = palette.textPrimary, textAlign = TextAlign.Center)
        if (authorLinks.isNotEmpty()) {
            Row(horizontalArrangement = Arrangement.Center) {
                authorLinks.forEachIndexed { idx, (id, name) ->
                    if (idx > 0) Text(", ", style = IosType.title3, color = palette.textPrimary)
                    Text(
                        name, style = IosType.title3, color = Theme.accent,
                        modifier = Modifier.clickable(enabled = onAuthorTap != null) { onAuthorTap?.invoke(id, name) },
                    )
                }
            }
        } else {
            subtitle?.trim()?.takeIf { it.isNotEmpty() && it != "—" }?.let {
                Text(it, style = IosType.title3, color = palette.textPrimary, textAlign = TextAlign.Center)
            }
        }
        if (tertiaryLine.isNotEmpty()) {
            Text(tertiaryLine, style = IosType.subheadline, color = palette.textSecondary, textAlign = TextAlign.Center)
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

/** iOS: `DetailHeroCircularButton` — Kreis mit Akzent-Kontur, gefüllt wenn „fertig". */
@Composable
fun DetailHeroCircularButton(icon: ImageVector, isFinished: Boolean, enabled: Boolean, size: Dp, description: String, onClick: () -> Unit) {
    val accent = Theme.accent
    val palette = Theme.palette
    val stroke = if (enabled) accent else palette.textSecondary
    val iconColor = when {
        !enabled -> palette.textSecondary
        isFinished -> Theme.onAccent
        else -> accent
    }
    Box(
        Modifier.size(size).clip(CircleShape)
            .then(if (isFinished && enabled) Modifier.background(accent) else Modifier.border(DetailHeroLayoutMetrics.borderWidth, stroke, CircleShape))
            .clickable(enabled = enabled, onClick = onClick)
            .semantics { contentDescription = description },
        contentAlignment = Alignment.Center,
    ) { Icon(icon, contentDescription = null, tint = iconColor) }
}

/**
 * iOS: `DetailHeroPrimaryButton` — Kapsel mit Akzent-Kontur, Fortschritt füllt von links; die
 * Beschriftung wechselt unter der Füllung auf `onAccent`. „Fertig" = komplett gefüllt.
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
    val accent = Theme.accent
    val onAccent = Theme.onAccent
    val fill = if (isFinished) 1f else progress01.toFloat().coerceIn(0f, 1f)
    val height = if (compact) DetailHeroLayoutMetrics.compactPrimaryControlHeight else DetailHeroLayoutMetrics.primaryControlHeight
    val textStyle = if (compact) IosType.subheadline.semibold else IosType.headline
    val stateText = when {
        isFinished -> "Finished"
        fill < 0.001f -> "Not started"
        kind == DetailHeroPrimaryKind.Read -> "${(fill * 100).toInt()} percent read"
        else -> "${(fill * 100).toInt()} percent listened"
    }

    @Composable
    fun Label(color: Color) {
        Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
            Icon(kind.icon, null, tint = color, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(AppTheme.Layout.compactSpacing))
            Text(kind.title, style = textStyle, color = color, maxLines = 1)
        }
    }

    Box(
        modifier.height(height).clip(CircleShape)
            .border(DetailHeroLayoutMetrics.borderWidth, if (enabled) accent else accent.copy(alpha = 0.4f), CircleShape)
            .clickable(enabled = enabled, onClick = onClick)
            .semantics {
                contentDescription = kind.accessibilityLabel
                stateDescription = stateText
            },
    ) {
        Label(accent)
        Box(
            Modifier.fillMaxSize().drawWithContent {
                clipRect(right = size.width * fill) { this@drawWithContent.drawContent() }
            }.background(accent),
        ) { Label(onAccent) }
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
    val color = Theme.palette.textSecondary
    Row(horizontalArrangement = Arrangement.spacedBy(DetailMetaLayoutMetrics.labelIconSpacing), verticalAlignment = Alignment.CenterVertically) {
        detailMetaLabelIcon(title)?.let { Icon(it, null, tint = color, modifier = Modifier.size(DetailMetaLayoutMetrics.labelIconSize)) }
        Text(title.uppercase(), style = IosType.footnote.semibold, color = color)
    }
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
    Text(text, style = IosType.body, color = Theme.palette.textPrimary, modifier = Modifier.fillMaxWidth())
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
            text, style = IosType.body, color = Theme.palette.textPrimary,
            maxLines = if (expanded) Int.MAX_VALUE else DetailMetaLayoutMetrics.descriptionCollapsedLineLimit,
            overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
        )
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
            TextButton(onClick = onToggle) { Text(if (expanded) "Less" else "More", style = IosType.subheadline.semibold, color = Theme.accent) }
        }
    }
}

/** iOS: `DetailMetaLink` — Akzent-Text, öffnet eine Entity. */
@Composable
fun DetailMetaLink(title: String, onClick: () -> Unit) {
    Text(
        title, style = IosType.body, color = Theme.accent,
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
                modifier = Modifier.size(18.dp).rotate(if (expanded) 90f else 0f),
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
            CircularProgressIndicator(
                progress = { progress.toFloat() }, color = accent, strokeWidth = 2.dp,
                modifier = Modifier.size(20.dp).semantics { contentDescription = "Downloading" },
            )
        }
        storageId in queued -> Box(Modifier.size(AppTheme.Layout.minTapTarget), contentAlignment = Alignment.Center) {
            Icon(SF.circleDashed, contentDescription = "Queued", tint = accent)
        }
        storageId in downloaded -> IconButton(onClick = onRemoveDownload, enabled = enabled) {
            Icon(SF.arrowDownCircleBadgeXmark, contentDescription = "Remove offline copy", tint = accent)
        }
        else -> IconButton(onClick = onStartDownload, enabled = enabled) {
            Icon(SF.arrowDownCircle, contentDescription = "Download", tint = accent)
        }
    }
}
