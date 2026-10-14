package de.letzgo.abstand.ui.home

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.data.AbsUserMediaProgress
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.model.DownloadBadgeState
import de.letzgo.abstand.model.DownloadStatusSource
import de.letzgo.abstand.model.NowPlayingState
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.IosType
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.CoverImage
import de.letzgo.abstand.ui.components.CoverImageContentMode
import de.letzgo.abstand.ui.components.LocalCoverEnvironment
import de.letzgo.abstand.ui.semibold

/**
 * Cover-abgeleitete Kartenfarbe (iOS: `CoverDerivedTintLoader` / `ContinueHeroTintCache`).
 * Platzhalter: Kartenfarbe der Palette — der Integrator ersetzt das durch die echte Ableitung aus
 * dem Cover (Farbmathematik liegt im `logic/`-Port).
 */
@Composable
fun coverTint(@Suppress("UNUSED_PARAMETER") itemId: String): Color = Theme.palette.card

/** iOS: `LibraryRowLayout` — gemeinsame Maße der Listen-/Kompaktkarten. */
object LibraryRowLayout {
    val coverSide: Dp = AppTheme.Layout.libraryRowCoverSide
    /** Gleicher Radius wie die Home-Cover-Cards. */
    val cornerRadius: Dp = AppTheme.Layout.continueHeroCardCornerRadius
    val cardInset: Dp = AppTheme.Layout.libraryRowCardInset
    val textInset: Dp = AppTheme.Layout.libraryRowTextInset
    /** Beendete Titel: Cover/Text zurückgenommen. */
    const val finishedContentOpacity = 0.35f
    val cardShape: Shape = RoundedCornerShape(cornerRadius)
    /** iOS: `coverClipShape` — links gerundet, rechts gerade. */
    val coverClipShape: Shape = RoundedCornerShape(topStart = cornerRadius, bottomStart = cornerRadius)

    fun bodyBottomInset(showsProgressBar: Boolean): Dp =
        if (showsProgressBar) textInset + AppTheme.Layout.libraryRowBottomProgressHeight else textInset
}

/**
 * iOS: `libraryRowCardChrome` — Kartenfläche mit dezenter Kante statt Schatten, Tap öffnet.
 * (Füllung + Form + Kante gebündelt wie `abstandCardChrome`; in horizontalen Reihen ohne Schatten.)
 */
fun Modifier.libraryRowCardChrome(fill: Color, outline: Color, onClick: (() -> Unit)?): Modifier = this
    .clip(LibraryRowLayout.cardShape)
    .background(fill)
    .border(AppTheme.Layout.hairlineWidth, outline, LibraryRowLayout.cardShape)
    .let { if (onClick != null) it.clickable(onClick = onClick) else it }

/** iOS: `LibraryRowCollapsedMetaLine` — „AUTHOR  Name“ (Label in Versalien, Wert ein-/zweizeilig). */
@Composable
fun LibraryRowCollapsedMetaLine(
    label: String,
    value: String?,
    modifier: Modifier = Modifier,
    valueMaxLines: Int = 2,
    labelColor: Color? = null,
    valueColor: Color? = null,
) {
    val palette = Theme.palette
    val line = value?.trim().orEmpty()
    val empty = line.isEmpty() || line == "—"
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.compactSpacing)) {
        Text(
            label.uppercase(),
            style = IosType.footnote.semibold,
            color = labelColor ?: palette.textSecondary,
            maxLines = 1,
            modifier = Modifier.alignByBaseline(),
        )
        Text(
            if (empty) "—" else line,
            style = IosType.footnote,
            color = if (empty) labelColor ?: palette.textSecondary else valueColor ?: palette.textPrimary,
            maxLines = valueMaxLines,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f).alignByBaseline(),
        )
    }
}

/** iOS: `ContinueListeningHeroCoverPill` — dunkle Kapsel auf Covern (Typ, Download, Anzahl). */
@Composable
fun CoverPill(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(
        modifier
            .padding(CoverPillMetrics.inset)
            .clip(RoundedCornerShape(percent = 50))
            .background(Theme.palette.coverPlayBadgeBackground)
            .padding(horizontal = AppTheme.Layout.compactSpacing, vertical = AppTheme.Layout.pillVerticalPadding),
        contentAlignment = Alignment.Center,
    ) { content() }
}

/** iOS: `ContinueListeningHeroCoverPillMetrics`. */
object CoverPillMetrics {
    val inset = 8.dp
    val iconSize = 12.dp
    val downloadSpinnerSize = 13.dp
}

/** Icon in einer [CoverPill] (bewusst Weiß: liegt auf der dunklen Kapsel, nicht auf der Palette). */
@Composable
fun CoverPillIcon(icon: ImageVector, contentDescription: String?) {
    Icon(icon, contentDescription = contentDescription, tint = Color.White, modifier = Modifier.size(CoverPillMetrics.iconSize))
}

/** Platzhalter für Serien/Autoren ohne Bild (iOS: `HomeEntityCoverPlaceholder`). */
@Composable
fun HomeEntityCoverPlaceholder(icon: ImageVector, modifier: Modifier = Modifier) {
    val palette = Theme.palette
    Box(modifier.fillMaxSize().background(palette.card), contentAlignment = Alignment.Center) {
        Icon(icon, contentDescription = null, tint = palette.textSecondary, modifier = Modifier.size(PlaceholderIconSize))
    }
}

private val PlaceholderIconSize = 28.dp

/** iOS: `model.authorImageURL(authorId:)` als Cover (1:1, Mitte beschnitten), Cache-Scope `author:<id>`. */
@Composable
fun AuthorImage(authorId: String, modifier: Modifier = Modifier) {
    val base = LocalCoverEnvironment.current.serverBaseURL
    val url = base?.let { (if (it.endsWith("/")) it else "$it/") + "api/authors/$authorId/image" }
    CoverImage(url = url, cacheScopeId = "author:$authorId", modifier = modifier, contentMode = CoverImageContentMode.Fill)
}

/** Fortschritt eines Mediums (iOS: `LibraryBookRowLiveState.progress`). */
@Composable
fun rememberProgress(progressKey: String): AbsUserMediaProgress? {
    val map by AppModel.shared.home.progressByItemId.collectAsState()
    return map[progressKey]
}

/** Download-Badge-Zustand (iOS: `rowLive.isDownloaded/isDownloading/downloadProgress`). */
@Composable
fun rememberDownloadBadge(itemId: String, episodeId: String? = null): DownloadBadgeState {
    val source = AppModel.shared.downloadStatus
    val states by source.states.collectAsState()
    val key = remember(itemId, episodeId) { DownloadStatusSource.storageId(itemId, episodeId) }
    return states[key] ?: DownloadBadgeState()
}

/** Spielt dieses Medium gerade (iOS: `playbackActivePublisher`). */
@Composable
fun rememberNowPlaying(): NowPlayingState {
    val state by AppModel.shared.playbackLauncher.nowPlaying.collectAsState()
    return state
}

/** Overlay-Ausrichtung oben links/rechts auf Covern. */
@Composable
fun BoxScope.TopCornerSlot(alignment: Alignment, content: @Composable () -> Unit) {
    Box(Modifier.align(alignment)) { content() }
}
