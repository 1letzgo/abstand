package de.letzgo.abstand.ui.player

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.CoverImageTier
import de.letzgo.abstand.data.swiftTrim
import de.letzgo.abstand.model.PlayerWiring
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.IosType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.bold
import de.letzgo.abstand.ui.components.AbstandEmptyScreen
import de.letzgo.abstand.ui.components.AbstandLoadingSpinner
import de.letzgo.abstand.ui.components.CoverImage
import de.letzgo.abstand.ui.components.CoverImageContentMode

/** Hat das Buch ein eBook (Reader-Knopf im Vollplayer)? */
private val AbsBook.hasEbook: Boolean
    get() = media.ebookFile != null || !media.ebookFormat.isNullOrBlank()

/**
 * iOS: `NowPlayingDetailView` — Vollbild-Player: großes Cover (bzw. aufgeklapptes Panel), Titel/Autor,
 * Buch- und Kapitel-Scrubber, Panel-Knöpfe (Beschreibung, Bookmarks, Kapitel, Read along), Transport,
 * Utility-Leiste (EQ, Tempo, Sleep, Ausgabe, Download).
 *
 * @param readAlong Teleprompter + Recap (iOS: `ReadAlongPanelButton`, `readAlongKaraokeCard`);
 *   `null` blendet Read along und Recap aus.
 * @param onOpenEbook „Open ebook“ für Bücher mit eBook; `null` blendet den Knopf aus.
 */
@Composable
fun NowPlayingScreen(
    wiring: PlayerWiring,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
    readAlong: NowPlayingReadAlong? = null,
    onOpenEbook: ((AbsBook) -> Unit)? = null,
) {
    val player = wiring.player
    val palette = Theme.palette
    val book by player.activeBook.collectAsState()
    val episodeId by player.activePlaybackEpisodeId.collectAsState()
    val preparing by wiring.isPreparingPlayback.collectAsState()
    // iOS: Startzustand aus dem Player — laufender Teleprompter öffnet direkt die Read-along-Karte.
    var panel by rememberSaveable {
        mutableStateOf(if (readAlong?.isModeActive?.value == true) FullPlayerCoverPanel.readAlong else FullPlayerCoverPanel.artwork)
    }
    var downloadWarning by remember { mutableStateOf(false) }
    var recapOpen by remember { mutableStateOf(false) }
    // Titelwechsel: zurück zum Cover (Panels gehören zum vorherigen Titel).
    LaunchedEffect(book?.id, episodeId) { if (panel != FullPlayerCoverPanel.readAlong) panel = FullPlayerCoverPanel.artwork }
    if (readAlong == null && panel == FullPlayerCoverPanel.readAlong) panel = FullPlayerCoverPanel.artwork

    BoxWithConstraints(
        modifier
            .fillMaxSize()
            .background(palette.background)
            .windowInsetsPadding(WindowInsets.safeDrawing)
            .padding(horizontal = MiniPlayerMetrics.fullPlayerCoverInset),
    ) {
        val landscape = maxWidth > maxHeight
        Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
            DismissGrabber(onDismiss)
            val b = book
            if (b == null) {
                Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                    if (preparing) {
                        AbstandLoadingSpinner()
                    } else {
                        AbstandEmptyScreen(title = "Nothing playing", icon = SF.waveform, description = "Choose an audiobook in the library.")
                    }
                }
                return@Column
            }
            val isAudiobook = episodeId.isNullOrBlank()
            val panelKinds = buildList {
                add(FullPlayerCoverPanel.description)
                if (isAudiobook) add(FullPlayerCoverPanel.bookmarks)
                if (isAudiobook) add(FullPlayerCoverPanel.chapters)
                if (readAlong != null) add(FullPlayerCoverPanel.readAlong)
            }
            // iOS: Read along/Recap nur mit vollständigem Download — sonst Hinweis statt Panel.
            val onPanelButton: (FullPlayerCoverPanel) -> Unit = { k ->
                if (k == FullPlayerCoverPanel.readAlong && readAlong != null) {
                    if (!readAlong.isDownloadReady()) {
                        downloadWarning = true
                    } else {
                        readAlong.toggle()
                        panel = if (panel == k) FullPlayerCoverPanel.artwork else k
                    }
                } else {
                    panel = if (panel == k) FullPlayerCoverPanel.artwork else k
                }
            }
            val onRecap: (() -> Unit)? = readAlong?.recapSheet?.let {
                {
                    if (!readAlong.isDownloadReady()) {
                        downloadWarning = true
                    } else {
                        // Teleprompter-Karte hat Vorrang — erst schließen (beendet die Session).
                        if (panel == FullPlayerCoverPanel.readAlong) panel = FullPlayerCoverPanel.artwork
                        recapOpen = true
                    }
                }
            }
            val ebookAction = onOpenEbook?.takeIf { isAudiobook && b.hasEbook }
            val expanded = panel != FullPlayerCoverPanel.artwork
            val header: @Composable (Modifier) -> Unit = { m -> PlayerHeaderArea(wiring, b, panel, readAlong, m) }
            val controls: @Composable ColumnScope.() -> Unit = {
                PanelControlRow(
                    panelKinds, panel, onToggle = onPanelButton, onRecap = onRecap,
                    readAlongDimmed = readAlong != null && !readAlong.isDownloadReady(),
                    onOpenEbook = ebookAction?.let { { it(b) } },
                )
                FullPlayerTransportRow(wiring, Modifier.padding(top = if (panelKinds.isEmpty()) MiniPlayerMetrics.spacingAbovePlayRow else AppTheme.Layout.tightSpacing))
                FullPlayerUtilityBar(wiring)
            }
            if (landscape) {
                Row(Modifier.weight(1f).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(MiniPlayerMetrics.fullPlayerCoverInset)) {
                    header(Modifier.weight(1f).fillMaxHeight())
                    Column(Modifier.weight(1f).fillMaxHeight()) {
                        Spacer(Modifier.weight(1f))
                        if (!expanded) {
                            TitleArea(wiring, b)
                            FullPlayerScrubberSection(wiring)
                            Spacer(Modifier.weight(1f))
                        }
                        controls()
                    }
                }
            } else {
                Column(Modifier.weight(1f).widthIn(max = MiniPlayerMetrics.fullPlayerContentMaxWidth).fillMaxWidth()) {
                    header(Modifier.weight(1f).fillMaxWidth())
                    if (!expanded) {
                        TitleArea(wiring, b)
                        FullPlayerScrubberSection(wiring)
                    }
                }
                Column(Modifier.widthIn(max = MiniPlayerMetrics.fullPlayerContentMaxWidth).fillMaxWidth()) { controls() }
            }
        }
    }
    if (downloadWarning) ReadAlongDownloadWarning { downloadWarning = false }
    if (recapOpen) readAlong?.recapSheet?.invoke { recapOpen = false }
}

/** iOS: Alert „Download required“ (Read along / Recap ohne vollständigen Download). */
@Composable
private fun ReadAlongDownloadWarning(onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Download required") },
        text = { Text("Read along and recap only work when the audiobook or podcast is fully downloaded.") },
        confirmButton = { TextButton(onClick = onDismiss) { Text("OK") } },
    )
}

/** iOS: Sheet-Drag-Griff (36 × 5) — Tippen schließt. */
@Composable
private fun DismissGrabber(onDismiss: () -> Unit) {
    Box(
        Modifier
            .fillMaxWidth()
            .height(AppTheme.Layout.minTapTarget / 2)
            .clickable(onClick = onDismiss)
            .semantics { contentDescription = "Close player" },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .size(MiniPlayerMetrics.dismissGrabberWidth, MiniPlayerMetrics.dismissGrabberHeight)
                .background(Theme.palette.textSecondary.copy(alpha = GRABBER_ALPHA), CircleShape),
        )
    }
}

private const val GRABBER_ALPHA = 0.5f

/** iOS: `playerHeaderArea` — Cover oder aufgeklapptes Panel, mit Überblendung. */
@Composable
private fun PlayerHeaderArea(
    wiring: PlayerWiring,
    book: AbsBook,
    panel: FullPlayerCoverPanel,
    readAlong: NowPlayingReadAlong?,
    modifier: Modifier,
) {
    AnimatedContent(
        targetState = panel,
        transitionSpec = { fadeIn() togetherWith fadeOut() },
        modifier = modifier.padding(vertical = AppTheme.Layout.stackSpacing),
        label = "nowPlayingPanel",
    ) { p ->
        when (p) {
            FullPlayerCoverPanel.artwork -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Box(
                    Modifier
                        .padding(MiniPlayerMetrics.fullPlayerCoverCardMargin / 2)
                        .aspectRatio(1f, matchHeightConstraintsFirst = true)
                        .clip(RoundedCornerShape(MiniPlayerMetrics.coverCornerRadius))
                        .background(Theme.palette.card),
                ) {
                    CoverImage(
                        itemId = book.id,
                        tier = CoverImageTier.hero,
                        contentMode = CoverImageContentMode.Fit,
                        modifier = Modifier.fillMaxSize(),
                        contentDescription = book.displayTitle,
                    )
                }
            }
            FullPlayerCoverPanel.description -> FullPlayerPanelCard { DescriptionPanel(book) }
            FullPlayerCoverPanel.chapters -> FullPlayerPanelCard { ChaptersPanel(wiring) }
            FullPlayerCoverPanel.bookmarks -> FullPlayerPanelCard { BookmarksPanel(wiring, book.id) }
            FullPlayerCoverPanel.readAlong -> FullPlayerPanelCard {
                if (readAlong != null) {
                    Column(Modifier.fillMaxSize()) {
                        Box(Modifier.weight(1f).fillMaxWidth()) { readAlong.content() }
                        // iOS: ±-Schriftgröße unten rechts auf der Teleprompter-Karte.
                        Row(
                            Modifier.fillMaxWidth().padding(AppTheme.Layout.stackSpacing),
                            horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.stackSpacing, Alignment.End),
                        ) {
                            CompactPanelButton(SF.textformatSizeSmaller, "Smaller text", readAlong.decreaseFont)
                            CompactPanelButton(SF.textformatSizeLarger, "Larger text", readAlong.increaseFont)
                        }
                    }
                }
            }
        }
    }
}

/** iOS: `fullPlayerTitleArea` — Titel (`title2.bold`), darunter Show (Folge) bzw. Autor. */
@Composable
private fun TitleArea(wiring: PlayerWiring, book: AbsBook) {
    val palette = Theme.palette
    val episodeId by wiring.player.activePlaybackEpisodeId.collectAsState()
    val secondary = run {
        val show = if (episodeId.isNullOrBlank()) null else wiring.podcastEpisodeForActivePlayback()?.showTitle?.swiftTrim()
        if (!show.isNullOrEmpty() && show != "—") show else book.displayAuthors.swiftTrim()
    }
    Column(
        Modifier.fillMaxWidth().padding(bottom = MiniPlayerMetrics.titleToScrubberSpacing),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.tightSpacing),
    ) {
        Text(book.displayTitle, style = IosType.title2.bold, color = palette.textPrimary, maxLines = 3, overflow = TextOverflow.Ellipsis)
        if (secondary.isNotEmpty() && secondary != "—") {
            Text(secondary, style = IosType.title3, color = palette.textSecondary, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** iOS: `fullPlayerPanelControlRow` — Panel-Knöpfe gleichmäßig verteilt (+ „Open ebook“). */
@Composable
private fun PanelControlRow(
    kinds: List<FullPlayerCoverPanel>,
    active: FullPlayerCoverPanel,
    onToggle: (FullPlayerCoverPanel) -> Unit,
    onRecap: (() -> Unit)?,
    readAlongDimmed: Boolean,
    onOpenEbook: (() -> Unit)?,
) {
    if (kinds.isEmpty() && onOpenEbook == null) return
    Row(
        Modifier
            .fillMaxWidth()
            .padding(top = MiniPlayerMetrics.scrubberVerticalSpacing, bottom = MiniPlayerMetrics.spacingAbovePlayRow),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        kinds.forEach { k ->
            val on = active == k
            when (k) {
                FullPlayerCoverPanel.description -> FullPlayerPanelButton(SF.docText, on, if (on) "Hide description" else "Show description") { onToggle(k) }
                FullPlayerCoverPanel.bookmarks -> FullPlayerPanelButton(SF.textBookClosed, on, if (on) "Hide bookmarks" else "Show bookmarks") { onToggle(k) }
                FullPlayerCoverPanel.chapters -> FullPlayerPanelButton(SF.listBullet, on, if (on) "Hide chapters" else "Show chapters") { onToggle(k) }
                FullPlayerCoverPanel.readAlong -> {
                    // iOS: Recap steht vor Read along (beide brauchen den Download, gedimmt ohne).
                    onRecap?.let { recap -> FullPlayerPanelButton(SF.sparkles, false, "Recap of the last 5 minutes", dimmed = readAlongDimmed, onClick = recap) }
                    FullPlayerPanelButton(SF.textWordSpacing, on, if (on) "Stop read-along transcript" else "Start read-along transcript", dimmed = readAlongDimmed) { onToggle(k) }
                }
                FullPlayerCoverPanel.artwork -> Unit
            }
        }
        onOpenEbook?.let { FullPlayerPanelButton(SF.bookClosedFill, false, "Open ebook", it) }
    }
}
