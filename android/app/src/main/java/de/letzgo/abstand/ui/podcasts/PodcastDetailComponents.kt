package de.letzgo.abstand.ui.podcasts

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.pulltorefresh.PullToRefreshDefaults
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.AppType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.bold
import de.letzgo.abstand.ui.components.AbstandCard
import de.letzgo.abstand.ui.components.AbstandProminentButton
import de.letzgo.abstand.ui.semibold
import de.letzgo.abstand.ui.components.AbstandIconButton
import de.letzgo.abstand.ui.components.AbstandProgressBar

/** iOS: `DetailHeroLayoutMetrics` / `DetailMetaLayoutMetrics` (Ausschnitt für Podcast-Details). */
internal object PodcastDetailMetrics {
    val squareCoverMaxWidth = 280.dp
    val coverCornerRadius = 8.dp
    val heroInfoLineSpacing = 5.dp
    val sideControlSize = 52.dp
    val primaryControlHeight = 52.dp
    const val singlePrimaryWidthFraction = 0.54f
    val actionRowSpacing = 16.dp
    val labelToContentSpacing = AppTheme.Layout.compactSpacing
    val linkRowSpacing = AppTheme.Layout.withinSectionSpacing
    val sectionCardSpacing = AppTheme.Layout.withinSectionSpacing
    const val descriptionCollapsedLineLimit = 4
    const val descriptionExpandCharacterThreshold = 200
    val primaryProgressHeight = 3.dp
}

/** iOS: `DetailHeroCoverFrame` — quadratisches Cover, max. 280 dp breit, mittig. */
@Composable
internal fun PodcastDetailHeroCover(content: @Composable () -> Unit) {
    Box(Modifier.fillMaxWidth().padding(top = AppTheme.Layout.tightSpacing), contentAlignment = Alignment.Center) {
        Box(
            Modifier
                .widthIn(max = PodcastDetailMetrics.squareCoverMaxWidth)
                .fillMaxWidth()
                .aspectRatio(1f)
                .clip(RoundedCornerShape(PodcastDetailMetrics.coverCornerRadius)),
        ) { content() }
    }
}

/**
 * iOS: `DetailHeroInfoSection` — Titel, Untertitel (optional als Link), Tertiärzeile
 * („48:12 · 2026“, leere Teile fallen weg).
 */
@Composable
internal fun PodcastDetailHeroInfo(
    title: String,
    subtitle: String?,
    tertiaryParts: List<String>,
    onSubtitleClick: (() -> Unit)? = null,
) {
    val palette = Theme.palette
    Column(
        Modifier.fillMaxWidth().padding(top = AppTheme.Layout.detailMetaAfterPlaySpacing),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(PodcastDetailMetrics.heroInfoLineSpacing),
    ) {
        Text(
            title, style = AppType.headlineSmall.bold, color = palette.textPrimary, textAlign = TextAlign.Center,
            modifier = Modifier.semantics { heading() },
        )
        if (!subtitle.isNullOrEmpty()) {
            Text(
                subtitle,
                style = AppType.titleLarge,
                color = if (onSubtitleClick != null) Theme.accent else palette.textSecondary,
                textAlign = TextAlign.Center,
                modifier = if (onSubtitleClick != null) Modifier.clickable(onClick = onSubtitleClick) else Modifier,
            )
        }
        val tertiary = tertiaryParts.filter { it.isNotEmpty() }.joinToString(" · ")
        if (tertiary.isNotEmpty()) {
            Text(tertiary, style = AppType.bodyMedium, color = palette.textSecondary, textAlign = TextAlign.Center)
        }
    }
}

/**
 * iOS: `DetailHeroActionsBar` mit einer `DetailHeroMediaAction` — runder „Fertig“-Knopf links,
 * Play-/Pause-Pille mit Fortschritt rechts.
 */
@Composable
internal fun PodcastDetailPlayActions(
    isPlaying: Boolean,
    isFinished: Boolean,
    progress01: Double,
    onMark: () -> Unit,
    onPrimary: () -> Unit,
) {
    val palette = Theme.palette
    Row(
        Modifier.fillMaxWidth().padding(
            top = AppTheme.Layout.detailPlayButtonTopPadding,
            bottom = AppTheme.Layout.detailPlayButtonBottomPadding,
        ),
        horizontalArrangement = Arrangement.spacedBy(PodcastDetailMetrics.actionRowSpacing, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        AbstandIconButton(
            if (isFinished) SF.arrowUturnBackward else SF.checkmark,
            if (isFinished) "Mark as not finished" else "Mark as finished",
            onClick = onMark,
            size = PodcastDetailMetrics.sideControlSize,
            tint = palette.textPrimary,
        )
        Column(Modifier.fillMaxWidth(PodcastDetailMetrics.singlePrimaryWidthFraction)) {
            AbstandProminentButton(
                onClick = onPrimary,
                modifier = Modifier.fillMaxWidth().height(PodcastDetailMetrics.primaryControlHeight),
                capsule = true,
            ) {
                Icon(if (isPlaying) SF.pauseFill else SF.playFill, contentDescription = null)
                Box(Modifier.size(AppTheme.Layout.inlineSpacing))
                Text(if (isPlaying) "Pause" else if (isFinished) "Play again" else if (progress01 > 0) "Resume" else "Play")
            }
            if (progress01 > 0 && !isFinished) {
                AbstandProgressBar(
                    progress01, Modifier.padding(top = AppTheme.Layout.compactSpacing),
                    height = PodcastDetailMetrics.primaryProgressHeight,
                )
            }
        }
    }
}

/** iOS: `DetailDetailSectionCard` — Meta-Karte unter dem Hero. */
@Composable
internal fun PodcastDetailSectionCard(content: @Composable ColumnScope.() -> Unit) {
    AbstandCard(Modifier.fillMaxWidth(), shape = RoundedCornerShape(AppTheme.Layout.detailSectionCardCornerRadius)) {
        Column(
            Modifier.fillMaxWidth().padding(AppTheme.Layout.detailSectionCardPadding),
            verticalArrangement = Arrangement.spacedBy(PodcastDetailMetrics.sectionCardSpacing),
            content = content,
        )
    }
}

/** iOS: `DetailMetaField` — Überschrift (optional mit Symbol) + Inhalt. */
@Composable
internal fun PodcastDetailMetaField(title: String, icon: ImageVector? = null, content: @Composable ColumnScope.() -> Unit) {
    val palette = Theme.palette
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(PodcastDetailMetrics.labelToContentSpacing)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.compactSpacing)) {
            if (icon != null) Icon(icon, contentDescription = null, tint = palette.textSecondary, modifier = Modifier.size(MetaIconSize))
            Text(title, style = AppType.bodyMedium.semibold, color = palette.textSecondary)
        }
        content()
    }
}

/** iOS: `DetailMetaTextBlock`. */
@Composable
internal fun PodcastDetailMetaText(text: String) {
    Text(text, style = AppType.bodyLarge, color = Theme.palette.textPrimary, modifier = Modifier.fillMaxWidth())
}

/** iOS: `DetailMetaExpandableTextBlock` — 4 Zeilen, „More“/„Less“ ab ~200 Zeichen. */
@Composable
internal fun PodcastDetailExpandableText(text: String, expanded: MutableState<Boolean>) {
    val canExpand = text.length > PodcastDetailMetrics.descriptionExpandCharacterThreshold || text.count { it == '\n' } >= PodcastDetailMetrics.descriptionCollapsedLineLimit
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.tightSpacing)) {
        Text(
            text,
            style = AppType.bodyLarge,
            color = Theme.palette.textPrimary,
            maxLines = if (expanded.value || !canExpand) Int.MAX_VALUE else PodcastDetailMetrics.descriptionCollapsedLineLimit,
            overflow = TextOverflow.Ellipsis,
        )
        if (canExpand) {
            Text(
                if (expanded.value) "Less" else "More",
                style = AppType.bodyMedium.semibold,
                color = Theme.accent,
                modifier = Modifier.clickable { expanded.value = !expanded.value },
            )
        }
    }
}

/** iOS: `DetailMetaDisclosure` — Karte mit auf-/zuklappbarem Inhalt. */
@Composable
internal fun PodcastDetailDisclosure(title: String, expanded: MutableState<Boolean>, content: @Composable ColumnScope.() -> Unit) {
    val palette = Theme.palette
    PodcastDetailSectionCard {
        Row(
            Modifier.fillMaxWidth().clickable { expanded.value = !expanded.value },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(title, style = AppType.bodyMedium.semibold, color = palette.textSecondary, modifier = Modifier.weight(1f))
            Icon(
                if (expanded.value) SF.chevronDown else SF.chevronRight,
                contentDescription = if (expanded.value) "Collapse" else "Expand",
                tint = Theme.accent,
                modifier = Modifier.size(MetaIconSize),
            )
        }
        if (expanded.value) content()
    }
}

private val MetaIconSize = 16.dp

/**
 * Pull-to-Refresh (iOS: `.refreshable`) mit Indikator unterhalb der Top-Bar ([topInset]) in
 * Akzentfarbe — der Inhalt läuft unter der Bar durch, der Indikator nicht.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun PodcastPullToRefresh(
    refreshing: Boolean,
    onRefresh: () -> Unit,
    topInset: Dp,
    content: @Composable BoxScope.() -> Unit,
) {
    val state = rememberPullToRefreshState()
    PullToRefreshBox(
        isRefreshing = refreshing,
        onRefresh = onRefresh,
        modifier = Modifier.fillMaxSize(),
        state = state,
        indicator = {
            PullToRefreshDefaults.Indicator(
                state = state,
                isRefreshing = refreshing,
                modifier = Modifier.align(Alignment.TopCenter).padding(top = topInset),
                containerColor = Theme.palette.card,
                color = Theme.accent,
            )
        },
        content = content,
    )
}
