package de.letzgo.abstand.ui.player

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextOverflow
import de.letzgo.abstand.data.AbsAudioBookmark
import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsListeningSession
import de.letzgo.abstand.data.absPlainText
import de.letzgo.abstand.model.PlayerWiring
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.AppType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandCardEmptyState
import de.letzgo.abstand.ui.components.AbstandDialog
import de.letzgo.abstand.ui.components.AbstandIconButton
import de.letzgo.abstand.ui.components.AbstandInsetTextField
import de.letzgo.abstand.ui.components.AbstandProminentButton
import de.letzgo.abstand.ui.detail.ListeningHistorySessionList
import de.letzgo.abstand.ui.formatPlaybackTime
import de.letzgo.abstand.ui.semibold
import kotlinx.coroutines.launch
import de.letzgo.abstand.ui.components.AbstandListRow
import de.letzgo.abstand.ui.components.AbstandIconButtonStyle

/** iOS: `FullPlayerCoverPanel` — was den Cover-Bereich ersetzt (+ Read-along, iOS: Teleprompter-Zustand). */
enum class FullPlayerCoverPanel { artwork, description, bookmarks, chapters, sessions, readAlong }

/**
 * iOS: `FullPlayerCoverOverlayButton` — runder Panel-Knopf (aktiv: Akzent-Füllung).
 */
@Composable
fun FullPlayerPanelButton(icon: ImageVector, active: Boolean, accessibilityLabel: String, onClick: () -> Unit) =
    FullPlayerPanelButton(icon, active, accessibilityLabel, dimmed = false, onClick = onClick)

/** [dimmed]: antippbar (für den Hinweis), aber optisch zurückgenommen (iOS: `opacity(0.45)`). */
@Composable
fun FullPlayerPanelButton(icon: ImageVector, active: Boolean, accessibilityLabel: String, dimmed: Boolean, onClick: () -> Unit) {
    AbstandIconButton(
        icon, accessibilityLabel, onClick = onClick,
        modifier = Modifier.alpha(if (dimmed) DIMMED_ALPHA else 1f),
        style = if (active) AbstandIconButtonStyle.Filled else AbstandIconButtonStyle.Tonal,
        size = MiniPlayerMetrics.panelControlButtonSize,
        tint = if (active) Theme.onAccent else Theme.palette.textPrimary,
    )
}

private const val DIMMED_ALPHA = 0.45f

/** iOS: kompakte Kreise auf der Teleprompter-Karte (±). */
@Composable
fun CompactPanelButton(icon: ImageVector, accessibilityLabel: String, onClick: () -> Unit) {
    AbstandIconButton(
        icon, accessibilityLabel, onClick = onClick,
        style = AbstandIconButtonStyle.Tonal,
        size = AppTheme.Layout.compactIconButtonSize,
        tint = Theme.palette.textPrimary,
        containerColor = Theme.palette.background,
    )
}

/** iOS: `fullPlayerExpandedCoverCard` — Kartenfläche des aufgeklappten Panels (volle Höhe). */
@Composable
fun FullPlayerPanelCard(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(
        modifier
            .fillMaxSize()
            .clip(RoundedCornerShape(MiniPlayerMetrics.coverSurfaceCornerRadius))
            .background(Theme.palette.card),
    ) { content() }
}

/** iOS: Description-Panel (`resolvedBookDescriptionText`). */
@Composable
fun DescriptionPanel(book: AbsBook) {
    val palette = Theme.palette
    val text = remember(book.id, book.media.metadata.description) {
        book.media.metadata.descriptionPlain?.trim()?.ifEmpty { null } ?: absPlainText(book.media.metadata.description).trim()
    }
    if (text.isEmpty()) {
        AbstandCardEmptyState("No description", Modifier.padding(AppTheme.Layout.cardPadding))
        return
    }
    Text(
        text,
        style = AppType.bodyLarge,
        color = palette.textPrimary,
        modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(AppTheme.Layout.cardPadding),
    )
}

/** iOS: Kapitel-Panel — aktuelles Kapitel hervorgehoben, Tippen springt an den Anfang. */
@Composable
fun ChaptersPanel(wiring: PlayerWiring) {
    val player = wiring.player
    val palette = Theme.palette
    val book by player.activeBook.collectAsState()
    val ordinal by player.currentChapterOrdinal.collectAsState()
    val chapters = remember(book?.id, book?.media?.chapters) { player.sortedChapters }
    if (chapters.isEmpty()) {
        AbstandCardEmptyState("No chapters", Modifier.padding(AppTheme.Layout.cardPadding))
        return
    }
    val current = (ordinal - 1).coerceAtLeast(0)
    val listState = rememberLazyListState(initialFirstVisibleItemIndex = (current - 2).coerceAtLeast(0))
    LazyColumn(state = listState, modifier = Modifier.fillMaxSize()) {
        itemsIndexed(chapters, key = { i, c -> "${c.id}-$i" }) { i, c ->
            val active = i == current
            Row(
                Modifier
                    .fillMaxWidth()
                    .clickable { player.seek(c.start) }
                    .padding(horizontal = AppTheme.Layout.cardPadding, vertical = AppTheme.Layout.rowVerticalPadding),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.rowSpacing),
            ) {
                Text(
                    c.title.trim().ifEmpty { "Chapter ${i + 1}" },
                    style = if (active) AppType.bodyLarge.semibold else AppType.bodyLarge,
                    color = if (active) Theme.accent else palette.textPrimary,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                Text(formatPlaybackTime(c.start), style = AppType.bodySmall, color = palette.textSecondary)
            }
        }
    }
}

/**
 * iOS: Sessions-Panel („Listening history“) — `ListeningHistorySessionList` der aktuellen Folge bzw. des
 * Buchs; geladen beim Öffnen des Panels (iOS: `.task(id: coverPanel)`), Tippen startet ab Session-Start.
 */
@Composable
fun SessionsPanel(wiring: PlayerWiring, isEpisode: Boolean) {
    val reachable by wiring.networkReachable.collectAsState()
    val book by wiring.player.activeBook.collectAsState()
    val episodeId by wiring.player.activePlaybackEpisodeId.collectAsState()
    var sessions by remember(book?.id, episodeId) { mutableStateOf<List<AbsListeningSession>>(emptyList()) }
    LaunchedEffect(book?.id, episodeId) { sessions = wiring.loadListeningSessionsForActivePlayback() }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(AppTheme.Layout.cardPadding)) {
        ListeningHistorySessionList(
            sessions = sessions,
            isNetworkReachable = reachable,
            emptyOnlineText = if (isEpisode) "No listening sessions recorded for this episode yet." else "No listening sessions recorded for this book yet.",
            emptyOfflineText = "No listening history cached yet.",
            onJump = wiring::playFromListeningSessionStart,
        )
    }
}

/** iOS: `bookmarksCoverCard` — Liste oben, „Add“ unten rechts; Tippen springt, Löschen mit Rückfrage. */
@Composable
fun BookmarksPanel(wiring: PlayerWiring, audiobookId: String) {
    val palette = Theme.palette
    val scope = rememberCoroutineScope()
    val all by wiring.bookmarks.collectAsState()
    val list = remember(all, audiobookId) { all.filter { it.libraryItemId == audiobookId }.sortedBy { it.time } }
    var adding by remember { mutableStateOf(false) }
    var deleting by remember { mutableStateOf<AbsAudioBookmark?>(null) }
    var busy by remember { mutableStateOf(false) }

    Column(Modifier.fillMaxSize()) {
        if (list.isEmpty()) {
            Box(Modifier.weight(1f).fillMaxWidth()) {
                AbstandCardEmptyState("No bookmarks", Modifier.padding(AppTheme.Layout.cardPadding), message = "Add a bookmark at the current position.")
            }
        } else {
            LazyColumn(Modifier.weight(1f).fillMaxWidth()) {
                itemsIndexed(list, key = { _, b -> b.id }) { _, b ->
                    AbstandListRow(
                        title = b.title.ifBlank { "Bookmark" },
                        subtitle = formatPlaybackTime(b.time.toDouble()),
                        onClick = { wiring.player.seek(b.time.toDouble()) },
                        titleMaxLines = 2,
                        modifier = Modifier.padding(start = AppTheme.Layout.cardPadding),
                    ) {
                        AbstandIconButton(SF.trash, "Delete bookmark", onClick = { deleting = b }, tint = AppTheme.danger)
                    }
                }
            }
        }
        Row(Modifier.fillMaxWidth().padding(AppTheme.Layout.cardPadding), horizontalArrangement = Arrangement.End) {
            AbstandProminentButton(text = "Add", icon = SF.plus, onClick = { adding = true }, isBusy = busy)
        }
    }

    if (adding) {
        var title by remember { mutableStateOf("") }
        AbstandDialog(
            title = "Add Bookmark",
            onDismiss = { adding = false },
            confirmLabel = "Add",
            onConfirm = {
                busy = true
                scope.launch {
                    wiring.addBookmarkAtCurrentPosition(title)
                    busy = false
                }
            },
        ) {
            AbstandInsetTextField(value = title, placeholder = "Title (optional)", label = "Bookmark title", onValueChange = { title = it })
        }
    }
    deleting?.let { b ->
        AbstandDialog(
            title = "Delete Bookmark?",
            onDismiss = { deleting = null },
            message = b.title.ifBlank { formatPlaybackTime(b.time.toDouble()) },
            confirmLabel = "Delete",
            destructive = true,
            dismissOnConfirm = false,
            onConfirm = {
                deleting = null
                scope.launch { wiring.deleteBookmark(b) }
            },
        )
    }
}
