@file:OptIn(UnstableApi::class)

package de.letzgo.abstand.player

import android.app.PendingIntent
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.CommandButton
import androidx.media3.session.LibraryResult
import androidx.media3.session.MediaConstants
import androidx.media3.session.MediaLibraryService
import androidx.media3.session.MediaSession
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionError
import androidx.media3.session.SessionResult
import com.google.common.collect.ImmutableList
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.SettableFuture
import de.letzgo.abstand.data.AbsStartShelfMergedRow
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch
import java.util.concurrent.ConcurrentHashMap

/**
 * Hintergrund-Wiedergabe + Medienbenachrichtigung + Android Auto (iOS: `audio`-Background-Mode,
 * `MPNowPlayingInfoCenter`/`MPRemoteCommandCenter`, `CarPlaySceneDelegate` + `CarPlayCoordinator`).
 *
 * Hostet die `MediaLibrarySession` um [PlaybackController.sessionPlayer]. Media3 hält den Dienst
 * beim Abspielen im Vordergrund (Standard-Benachrichtigung mit Cover über [CoverBitmapLoader]).
 * Browse-Baum für Android Auto wie die CarPlay-Tabs: „Continue“ und „Downloads“ (plus optionale
 * Bücher/Podcasts, wenn [BrowseSource] sie liefert).
 */
class AbstandPlaybackService : MediaLibraryService() {
    private var session: MediaLibrarySession? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    /** Zuletzt gelieferte Zeilen je Media-ID — Abspielwünsche aus dem Auto ohne zweiten Netz-Roundtrip. */
    private val rowsByMediaId = ConcurrentHashMap<String, AbsStartShelfMergedRow>()

    override fun onCreate() {
        super.onCreate()
        val controller = PlaybackController.shared(this)
        val launch = packageManager.getLaunchIntentForPackage(packageName)?.let {
            PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }
        val builder = MediaLibrarySession.Builder(this, controller.sessionPlayer, LibraryCallback(controller))
            .setBitmapLoader(CoverBitmapLoader(this))
            .setMediaButtonPreferences(mediaButtons(controller))
        launch?.let { builder.setSessionActivity(it) }
        session = builder.build()
        // Skip-Intervalle / Tempo im Knopf-Layout aktuell halten.
        scope.launch {
            combine(controller.skipBackwardSeconds, controller.skipForwardSeconds, controller.playbackRate) { _, _, _ -> }
                .distinctUntilChanged()
                .collect { session?.setMediaButtonPreferences(mediaButtons(controller)) }
        }
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaLibrarySession? = session

    override fun onTaskRemoved(rootIntent: Intent?) {
        // App weggewischt ohne laufende Wiedergabe: Dienst beenden (wie iOS ohne aktive Audio-Session).
        val player = session?.player
        if (player == null || !player.playWhenReady || player.mediaItemCount == 0) stopSelf()
    }

    override fun onDestroy() {
        scope.cancel()
        session?.release()
        session = null
        super.onDestroy()
    }

    private inner class LibraryCallback(private val controller: PlaybackController) : MediaLibrarySession.Callback {

        override fun onConnect(session: MediaSession, controllerInfo: MediaSession.ControllerInfo): MediaSession.ConnectionResult {
            val sessionCommands = MediaSession.ConnectionResult.DEFAULT_SESSION_AND_LIBRARY_COMMANDS.buildUpon()
                .add(SessionCommand(COMMAND_PLAYBACK_RATE, Bundle.EMPTY))
                .build()
            return MediaSession.ConnectionResult.AcceptedResultBuilder(session)
                .setAvailableSessionCommands(sessionCommands)
                .build()
        }

        override fun onCustomCommand(
            session: MediaSession,
            controllerInfo: MediaSession.ControllerInfo,
            customCommand: SessionCommand,
            args: Bundle,
        ): ListenableFuture<SessionResult> {
            if (customCommand.customAction == COMMAND_PLAYBACK_RATE) {
                // iOS: `CPNowPlayingPlaybackRateButton` → nächstes Tempo-Preset.
                controller.advancePlaybackRate()
                return Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
            }
            return Futures.immediateFuture(SessionResult(SessionError.ERROR_NOT_SUPPORTED))
        }

        override fun onGetLibraryRoot(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            params: LibraryParams?,
        ): ListenableFuture<LibraryResult<MediaItem>> {
            val extras = Bundle().apply {
                putInt(MediaConstants.EXTRAS_KEY_CONTENT_STYLE_PLAYABLE, MediaConstants.EXTRAS_VALUE_CONTENT_STYLE_LIST_ITEM)
                putInt(MediaConstants.EXTRAS_KEY_CONTENT_STYLE_BROWSABLE, MediaConstants.EXTRAS_VALUE_CONTENT_STYLE_LIST_ITEM)
            }
            val root = folderItem(AutoBrowseTree.ROOT_ID, "abstand", extras)
            return Futures.immediateFuture(LibraryResult.ofItem(root, LibraryParams.Builder().setExtras(extras).build()))
        }

        override fun onGetItem(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            mediaId: String,
        ): ListenableFuture<LibraryResult<MediaItem>> {
            val row = rowsByMediaId[mediaId]
                ?: return Futures.immediateFuture(LibraryResult.ofError(SessionError.ERROR_BAD_VALUE))
            return Futures.immediateFuture(LibraryResult.ofItem(playableItem(row), null))
        }

        override fun onGetChildren(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            parentId: String,
            page: Int,
            pageSize: Int,
            params: LibraryParams?,
        ): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> = future {
            val source = browseSource
            val items: List<MediaItem> = when {
                source == null || !source.isLoggedIn -> listOf(messageItem(AutoBrowseTree.MESSAGE_SIGN_IN))
                parentId == AutoBrowseTree.ROOT_ID -> {
                    val hasBooks = !source.libraryBookRows().isNullOrEmpty()
                    val hasPodcasts = !source.podcastEpisodeRows().isNullOrEmpty()
                    AutoBrowseTree.rootChildIds(hasBooks, hasPodcasts).map { folderItem(it, AutoBrowseTree.tabTitle(it), null) }
                }
                parentId == AutoBrowseTree.CONTINUE_ID ->
                    rowItems(source.continueListeningRows(), AutoBrowseTree.CONTINUE_SECTION_TITLE, AutoBrowseTree.MESSAGE_NOTHING_IN_PROGRESS)
                parentId == AutoBrowseTree.DOWNLOADS_ID ->
                    rowItems(source.downloadedRows(), AutoBrowseTree.DOWNLOADS_SECTION_TITLE, AutoBrowseTree.MESSAGE_NO_DOWNLOADS)
                parentId == AutoBrowseTree.BOOKS_ID ->
                    rowItems(source.libraryBookRows().orEmpty(), null, AutoBrowseTree.MESSAGE_EMPTY)
                parentId == AutoBrowseTree.PODCASTS_ID ->
                    rowItems(source.podcastEpisodeRows().orEmpty(), null, AutoBrowseTree.MESSAGE_EMPTY)
                else -> emptyList()
            }
            LibraryResult.ofItemList(ImmutableList.copyOf(items), params)
        }

        override fun onSetMediaItems(
            mediaSession: MediaSession,
            controller: MediaSession.ControllerInfo,
            mediaItems: MutableList<MediaItem>,
            startIndex: Int,
            startPositionMs: Long,
        ): ListenableFuture<MediaSession.MediaItemsWithStartPosition> = future {
            val requested = mediaItems.getOrNull(startIndex.coerceAtLeast(0)) ?: mediaItems.firstOrNull()
            startRequested(requested)
            val player = mediaSession.player
            MediaSession.MediaItemsWithStartPosition(
                listOfNotNull(player.currentMediaItem ?: requested), 0, C.TIME_UNSET,
            )
        }

        override fun onAddMediaItems(
            mediaSession: MediaSession,
            controller: MediaSession.ControllerInfo,
            mediaItems: MutableList<MediaItem>,
        ): ListenableFuture<MutableList<MediaItem>> = future {
            startRequested(mediaItems.firstOrNull())
            listOfNotNull(mediaSession.player.currentMediaItem ?: mediaItems.firstOrNull()).toMutableList()
        }

        override fun onPlaybackResumption(
            mediaSession: MediaSession,
            controller: MediaSession.ControllerInfo,
        ): ListenableFuture<MediaSession.MediaItemsWithStartPosition> = future {
            val source = browseSource
            if (mediaSession.player.currentMediaItem == null && source != null) source.restoreLastPlayback()
            val item = mediaSession.player.currentMediaItem ?: throw UnsupportedOperationException("Nothing to resume")
            MediaSession.MediaItemsWithStartPosition(listOf(item), 0, mediaSession.player.currentPosition)
        }

        /** iOS: `item.handler` → `model.play(book:)` / `playPodcastEpisode`. */
        private suspend fun startRequested(item: MediaItem?) {
            val mediaId = item?.mediaId ?: return
            if (AutoBrowseTree.isMessageId(mediaId)) return
            // Bereits laufender Titel: nur fortsetzen (Session ruft danach `play()`).
            if (mediaId == controller.sessionPlayer.currentMediaItem?.mediaId) return
            val row = rowsByMediaId[mediaId] ?: return
            browseSource?.play(row)
        }
    }

    // MARK: - Items

    private fun rowItems(rows: List<AbsStartShelfMergedRow>, groupTitle: String?, emptyMessage: String): List<MediaItem> {
        val clamped = AutoBrowseTree.clamped(rows)
        if (clamped.isEmpty()) return listOf(messageItem(emptyMessage))
        return clamped.map { row ->
            rowsByMediaId[AutoBrowseTree.mediaId(row)] = row
            playableItem(row, groupTitle)
        }
    }

    private fun playableItem(row: AbsStartShelfMergedRow, groupTitle: String? = null): MediaItem {
        val source = browseSource
        val progress = source?.progress(AutoBrowseTree.progressKey(row))
        val extras = Bundle().apply {
            putInt(MediaConstants.EXTRAS_KEY_COMPLETION_STATUS, AutoBrowseTree.completionStatus(progress))
            AutoBrowseTree.completionFraction(progress)?.let { putDouble(MediaConstants.EXTRAS_KEY_COMPLETION_PERCENTAGE, it) }
            groupTitle?.let { putString(MediaConstants.EXTRAS_KEY_CONTENT_STYLE_GROUP_TITLE, it) }
        }
        val isEpisode = row is AbsStartShelfMergedRow.PodcastEpisode
        val metadata = MediaMetadata.Builder()
            .setTitle(AutoBrowseTree.title(row))
            .setArtist(AutoBrowseTree.subtitle(row))
            .setArtworkUri(source?.coverUrl(AutoBrowseTree.coverItemId(row))?.let(Uri::parse))
            .setIsPlayable(true)
            .setIsBrowsable(false)
            .setMediaType(if (isEpisode) MediaMetadata.MEDIA_TYPE_PODCAST_EPISODE else MediaMetadata.MEDIA_TYPE_AUDIO_BOOK)
            .setExtras(extras)
            .build()
        return MediaItem.Builder().setMediaId(AutoBrowseTree.mediaId(row)).setMediaMetadata(metadata).build()
    }

    private fun folderItem(id: String, title: String, extras: Bundle?): MediaItem =
        MediaItem.Builder()
            .setMediaId(id)
            .setMediaMetadata(
                MediaMetadata.Builder()
                    .setTitle(title)
                    .setIsBrowsable(true)
                    .setIsPlayable(false)
                    .setMediaType(MediaMetadata.MEDIA_TYPE_FOLDER_MIXED)
                    .apply { extras?.let { setExtras(it) } }
                    .build(),
            )
            .build()

    /** iOS: `messageSection` — deaktivierte Zeile mit Hinweistext. */
    private fun messageItem(text: String): MediaItem =
        MediaItem.Builder()
            .setMediaId(AutoBrowseTree.messageId(text))
            .setMediaMetadata(MediaMetadata.Builder().setTitle(text).setIsBrowsable(false).setIsPlayable(false).build())
            .build()

    private fun mediaButtons(controller: PlaybackController): List<CommandButton> {
        val back = controller.skipBackwardSeconds.value
        val forward = controller.skipForwardSeconds.value
        return listOf(
            CommandButton.Builder(skipBackIcon(back))
                .setPlayerCommand(Player.COMMAND_SEEK_BACK)
                .setDisplayName(PlaybackSkipDefaults.accessibilityLabel(backward = true, seconds = back))
                .setSlots(CommandButton.SLOT_BACK)
                .build(),
            CommandButton.Builder(skipForwardIcon(forward))
                .setPlayerCommand(Player.COMMAND_SEEK_FORWARD)
                .setDisplayName(PlaybackSkipDefaults.accessibilityLabel(backward = false, seconds = forward))
                .setSlots(CommandButton.SLOT_FORWARD)
                .build(),
            CommandButton.Builder(CommandButton.ICON_PLAYBACK_SPEED)
                .setSessionCommand(SessionCommand(COMMAND_PLAYBACK_RATE, Bundle.EMPTY))
                .setDisplayName("Speed ${formatRate(controller.playbackRate.value)}×")
                .setSlots(CommandButton.SLOT_OVERFLOW)
                .build(),
        )
    }

    private fun <T> future(block: suspend () -> T): ListenableFuture<T> {
        val f = SettableFuture.create<T>()
        scope.launch {
            try {
                f.set(block())
            } catch (e: Throwable) {
                f.setException(e)
            }
        }
        return f
    }

    companion object {
        /** Datenquelle für Android Auto — vom Integrator in `Application.onCreate` gesetzt. */
        @Volatile var browseSource: BrowseSource? = null

        const val COMMAND_PLAYBACK_RATE = "de.letzgo.abstand.PLAYBACK_RATE"

        private fun skipBackIcon(seconds: Int): Int = when (seconds) {
            5 -> CommandButton.ICON_SKIP_BACK_5
            10 -> CommandButton.ICON_SKIP_BACK_10
            15 -> CommandButton.ICON_SKIP_BACK_15
            30 -> CommandButton.ICON_SKIP_BACK_30
            else -> CommandButton.ICON_SKIP_BACK
        }

        private fun skipForwardIcon(seconds: Int): Int = when (seconds) {
            5 -> CommandButton.ICON_SKIP_FORWARD_5
            10 -> CommandButton.ICON_SKIP_FORWARD_10
            15 -> CommandButton.ICON_SKIP_FORWARD_15
            30 -> CommandButton.ICON_SKIP_FORWARD_30
            else -> CommandButton.ICON_SKIP_FORWARD
        }

        private fun formatRate(rate: Float): String =
            if (rate == rate.toInt().toFloat()) rate.toInt().toString() else rate.toString()
    }
}
