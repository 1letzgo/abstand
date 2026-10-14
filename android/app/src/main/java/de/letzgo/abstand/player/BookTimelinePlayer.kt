@file:OptIn(UnstableApi::class)

package de.letzgo.abstand.player

import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.DeviceInfo
import androidx.media3.common.FlagSet
import androidx.media3.common.ForwardingPlayer
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Metadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.Timeline
import androidx.media3.common.TrackSelectionParameters
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.common.text.CueGroup
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer

/**
 * Sicht der MediaSession (Benachrichtigung, Sperrbildschirm, Bluetooth, Android Auto) auf die
 * Wiedergabe — iOS: `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` in `PlaybackController`.
 *
 * ExoPlayer spielt die Spuren eines Hörbuchs als Playlist; nach außen erscheint das Buch wie auf iOS
 * als **ein** Medium mit Gesamtdauer und globaler Position. Transportbefehle laufen über den
 * [PlaybackController] (Play holt bei Bedarf die Session neu, Seek rechnet global → Spur).
 * Vor/Zurück (Kopfhörer-Doppelklick, Benachrichtigung) = Skip-Intervalle wie die iOS-Remote-Commands.
 */
class BookTimelinePlayer(private val exo: ExoPlayer, private val controller: PlaybackController) : ForwardingPlayer(exo) {

    private val wrappers = LinkedHashMap<Player.Listener, TranslatingListener>()

    private val isActive: Boolean get() = controller.activeBook.value != null && exo.mediaItemCount > 0

    // MARK: - Logisches Medium

    private fun logicalMediaId(): String {
        val book = controller.activeBook.value ?: return ""
        val ep = controller.activePlaybackEpisodeId.value
        return if (ep.isNullOrEmpty()) "book|${book.id}" else "episode|${book.id}|$ep"
    }

    private fun logicalMetadata(): MediaMetadata {
        val book = controller.activeBook.value ?: return MediaMetadata.EMPTY
        val isEpisode = !controller.activePlaybackEpisodeId.value.isNullOrEmpty()
        val total = controller.totalDuration.value
        return MediaMetadata.Builder()
            .setTitle(book.displayTitle)
            .setArtist(book.displayAuthors)
            .setArtworkUri(controller.nowPlayingArtworkUri())
            .setDurationMs(if (total > 0) (total * 1000).toLong() else null)
            .setMediaType(if (isEpisode) MediaMetadata.MEDIA_TYPE_PODCAST_EPISODE else MediaMetadata.MEDIA_TYPE_AUDIO_BOOK)
            .setIsPlayable(true)
            .setIsBrowsable(false)
            .build()
    }

    private fun logicalMediaItem(): MediaItem? {
        if (controller.activeBook.value == null) return null
        return MediaItem.Builder().setMediaId(logicalMediaId()).setMediaMetadata(logicalMetadata()).build()
    }

    private fun totalDurationMs(): Long {
        val total = controller.totalDuration.value
        return if (total > 0) (total * 1000).toLong() else C.TIME_UNSET
    }

    private fun logicalTimeline(): Timeline {
        if (!isActive) return Timeline.EMPTY
        val item = logicalMediaItem() ?: return Timeline.EMPTY
        return SingleBookTimeline(logicalMediaId(), item, totalDurationMs())
    }

    /** Neues Buch / geänderte Metadaten / Abriss: Session-Zustand neu einlesen lassen. */
    fun notifyLogicalItemChanged() {
        val timeline = logicalTimeline()
        val item = currentMediaItem
        val metadata = mediaMetadata
        val events = Player.Events(
            FlagSet.Builder().addAll(
                Player.EVENT_TIMELINE_CHANGED, Player.EVENT_MEDIA_ITEM_TRANSITION, Player.EVENT_MEDIA_METADATA_CHANGED,
            ).build(),
        )
        for ((listener, _) in wrappers.toList()) {
            listener.onTimelineChanged(timeline, Player.TIMELINE_CHANGE_REASON_PLAYLIST_CHANGED)
            listener.onMediaItemTransition(item, Player.MEDIA_ITEM_TRANSITION_REASON_PLAYLIST_CHANGED)
            listener.onMediaMetadataChanged(metadata)
            listener.onEvents(this, events)
        }
    }

    fun notifySeekIncrementsChanged() {
        for ((listener, _) in wrappers.toList()) {
            listener.onSeekBackIncrementChanged(seekBackIncrement)
            listener.onSeekForwardIncrementChanged(seekForwardIncrement)
        }
    }

    // MARK: - Listener (Spur-Ereignisse → Buch-Ereignisse)

    override fun addListener(listener: Player.Listener) {
        if (wrappers.containsKey(listener)) return
        val wrapper = TranslatingListener(listener)
        wrappers[listener] = wrapper
        exo.addListener(wrapper)
    }

    override fun removeListener(listener: Player.Listener) {
        wrappers.remove(listener)?.let { exo.removeListener(it) }
    }

    private fun translate(info: Player.PositionInfo): Player.PositionInfo {
        if (!isActive) return info
        val globalMs = (controller.globalTimeForSession(info.mediaItemIndex, info.positionMs / 1000.0) * 1000).toLong()
        return Player.PositionInfo(
            logicalMediaId(), 0, logicalMediaItem(), logicalMediaId(), 0, globalMs, globalMs, C.INDEX_UNSET, C.INDEX_UNSET,
        )
    }

    private inner class TranslatingListener(private val target: Player.Listener) : Player.Listener {
        override fun onEvents(player: Player, events: Player.Events) = target.onEvents(this@BookTimelinePlayer, events)
        override fun onTimelineChanged(timeline: Timeline, reason: Int) = target.onTimelineChanged(logicalTimeline(), reason)
        override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
            // Spurwechsel innerhalb eines Buchs sind kein Medienwechsel.
            if (isActive && reason != Player.MEDIA_ITEM_TRANSITION_REASON_PLAYLIST_CHANGED) return
            target.onMediaItemTransition(currentMediaItem, reason)
        }
        override fun onTracksChanged(tracks: Tracks) = target.onTracksChanged(tracks)
        // ID3-Tags der Spurdateien nicht durchreichen — Buchtitel/Autor bleiben.
        override fun onMediaMetadataChanged(mediaMetadata: MediaMetadata) = target.onMediaMetadataChanged(this@BookTimelinePlayer.mediaMetadata)
        override fun onPlaylistMetadataChanged(mediaMetadata: MediaMetadata) = target.onPlaylistMetadataChanged(mediaMetadata)
        override fun onIsLoadingChanged(isLoading: Boolean) = target.onIsLoadingChanged(isLoading)
        override fun onAvailableCommandsChanged(availableCommands: Player.Commands) =
            target.onAvailableCommandsChanged(this@BookTimelinePlayer.availableCommands)
        override fun onTrackSelectionParametersChanged(parameters: TrackSelectionParameters) = target.onTrackSelectionParametersChanged(parameters)
        override fun onPlaybackStateChanged(playbackState: Int) = target.onPlaybackStateChanged(playbackState)
        override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) = target.onPlayWhenReadyChanged(playWhenReady, reason)
        override fun onPlaybackSuppressionReasonChanged(playbackSuppressionReason: Int) =
            target.onPlaybackSuppressionReasonChanged(playbackSuppressionReason)
        override fun onIsPlayingChanged(isPlaying: Boolean) = target.onIsPlayingChanged(isPlaying)
        override fun onRepeatModeChanged(repeatMode: Int) = target.onRepeatModeChanged(repeatMode)
        override fun onShuffleModeEnabledChanged(shuffleModeEnabled: Boolean) = target.onShuffleModeEnabledChanged(shuffleModeEnabled)
        override fun onPlayerError(error: PlaybackException) = target.onPlayerError(error)
        override fun onPlayerErrorChanged(error: PlaybackException?) = target.onPlayerErrorChanged(error)
        override fun onPositionDiscontinuity(oldPosition: Player.PositionInfo, newPosition: Player.PositionInfo, reason: Int) {
            // Automatischer Spurwechsel ist auf der Buch-Zeitachse lückenlos — kein Sprung.
            if (isActive && reason == Player.DISCONTINUITY_REASON_AUTO_TRANSITION) return
            target.onPositionDiscontinuity(translate(oldPosition), translate(newPosition), reason)
        }
        override fun onPlaybackParametersChanged(playbackParameters: PlaybackParameters) = target.onPlaybackParametersChanged(playbackParameters)
        override fun onSeekBackIncrementChanged(seekBackIncrementMs: Long) = target.onSeekBackIncrementChanged(seekBackIncrement)
        override fun onSeekForwardIncrementChanged(seekForwardIncrementMs: Long) = target.onSeekForwardIncrementChanged(seekForwardIncrement)
        override fun onMaxSeekToPreviousPositionChanged(maxSeekToPreviousPositionMs: Long) =
            target.onMaxSeekToPreviousPositionChanged(maxSeekToPreviousPositionMs)
        override fun onAudioSessionIdChanged(audioSessionId: Int) = target.onAudioSessionIdChanged(audioSessionId)
        override fun onAudioAttributesChanged(audioAttributes: AudioAttributes) = target.onAudioAttributesChanged(audioAttributes)
        override fun onVolumeChanged(volume: Float) = target.onVolumeChanged(volume)
        override fun onSkipSilenceEnabledChanged(skipSilenceEnabled: Boolean) = target.onSkipSilenceEnabledChanged(skipSilenceEnabled)
        override fun onDeviceInfoChanged(deviceInfo: DeviceInfo) = target.onDeviceInfoChanged(deviceInfo)
        override fun onDeviceVolumeChanged(volume: Int, muted: Boolean) = target.onDeviceVolumeChanged(volume, muted)
        override fun onVideoSizeChanged(videoSize: VideoSize) = target.onVideoSizeChanged(videoSize)
        override fun onSurfaceSizeChanged(width: Int, height: Int) = target.onSurfaceSizeChanged(width, height)
        override fun onRenderedFirstFrame() = target.onRenderedFirstFrame()
        override fun onCues(cueGroup: CueGroup) = target.onCues(cueGroup)
        override fun onMetadata(metadata: Metadata) = target.onMetadata(metadata)
    }

    // MARK: - Zeitachse

    override fun getCurrentTimeline(): Timeline = logicalTimeline()
    override fun getCurrentMediaItemIndex(): Int = 0
    override fun getCurrentPeriodIndex(): Int = 0
    override fun getMediaItemCount(): Int = if (isActive) 1 else 0
    override fun getCurrentMediaItem(): MediaItem? = if (isActive) logicalMediaItem() else null
    override fun getMediaItemAt(index: Int): MediaItem = logicalMediaItem() ?: exo.getMediaItemAt(index)
    override fun getMediaMetadata(): MediaMetadata = if (controller.activeBook.value != null) logicalMetadata() else MediaMetadata.EMPTY
    override fun getDuration(): Long = if (isActive) totalDurationMs() else C.TIME_UNSET
    override fun getContentDuration(): Long = duration
    override fun getCurrentPosition(): Long = if (isActive) controller.globalPositionMsForSession() else 0
    override fun getContentPosition(): Long = currentPosition
    override fun getBufferedPosition(): Long = if (isActive) controller.bufferedGlobalPositionMsForSession() else 0
    override fun getContentBufferedPosition(): Long = bufferedPosition
    override fun getBufferedPercentage(): Int {
        val d = duration
        if (d == C.TIME_UNSET || d <= 0) return 0
        return ((bufferedPosition * 100) / d).toInt().coerceIn(0, 100)
    }
    override fun hasNextMediaItem(): Boolean = false
    override fun hasPreviousMediaItem(): Boolean = false
    override fun getNextMediaItemIndex(): Int = C.INDEX_UNSET
    override fun getPreviousMediaItemIndex(): Int = C.INDEX_UNSET
    override fun isCurrentMediaItemSeekable(): Boolean = isActive
    override fun isCurrentMediaItemDynamic(): Boolean = false
    override fun isCurrentMediaItemLive(): Boolean = false

    // MARK: - Befehle

    override fun getAvailableCommands(): Player.Commands {
        val builder = exo.availableCommands.buildUpon()
            .removeAll(Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM, Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM)
        if (isActive) {
            builder.addAll(
                Player.COMMAND_SEEK_TO_NEXT, Player.COMMAND_SEEK_TO_PREVIOUS,
                Player.COMMAND_SEEK_BACK, Player.COMMAND_SEEK_FORWARD,
                Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM, Player.COMMAND_SEEK_TO_DEFAULT_POSITION,
            )
        } else {
            builder.removeAll(
                Player.COMMAND_SEEK_TO_NEXT, Player.COMMAND_SEEK_TO_PREVIOUS,
                Player.COMMAND_SEEK_BACK, Player.COMMAND_SEEK_FORWARD, Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM,
            )
        }
        // Medien setzen bleibt erlaubt: Android Auto startet Titel über `setMediaItems` (→ Session-Callback).
        builder.addAll(Player.COMMAND_SET_MEDIA_ITEM, Player.COMMAND_CHANGE_MEDIA_ITEMS, Player.COMMAND_PLAY_PAUSE, Player.COMMAND_PREPARE)
        return builder.build()
    }

    override fun isCommandAvailable(command: Int): Boolean = availableCommands.contains(command)

    override fun play() = controller.play()
    override fun pause() = controller.pause()
    override fun setPlayWhenReady(playWhenReady: Boolean) = if (playWhenReady) controller.play() else controller.pause()

    /** Session ruft nach `setMediaItems` ein `prepare()` — der Controller bereitet selbst vor. */
    override fun prepare() {
        if (exo.mediaItemCount > 0 && exo.playbackState == Player.STATE_IDLE) exo.prepare()
    }

    override fun stop() = controller.pause()

    override fun seekTo(positionMs: Long) = controller.seek(positionMs / 1000.0)
    override fun seekTo(mediaItemIndex: Int, positionMs: Long) = controller.seek(positionMs / 1000.0)
    override fun seekToDefaultPosition() = controller.seek(0.0)
    override fun seekToDefaultPosition(mediaItemIndex: Int) = controller.seek(0.0)
    override fun getSeekBackIncrement(): Long = controller.skipBackwardSeconds.value * 1000L
    override fun getSeekForwardIncrement(): Long = controller.skipForwardSeconds.value * 1000L
    override fun seekBack() = controller.skipBackward()
    override fun seekForward() = controller.skipForward()
    override fun seekToPrevious() = controller.skipBackward()
    override fun seekToNext() = controller.skipForward()
    override fun seekToPreviousMediaItem() = controller.skipBackward()
    override fun seekToNextMediaItem() = controller.skipForward()

    override fun setPlaybackSpeed(speed: Float) = controller.setPlaybackRate(speed)
    override fun setPlaybackParameters(playbackParameters: PlaybackParameters) = controller.setPlaybackRate(playbackParameters.speed)

    // Medienlisten setzt allein der Controller; Android-Auto-Wünsche laufen über den Session-Callback.
    override fun setMediaItems(mediaItems: MutableList<MediaItem>) {}
    override fun setMediaItems(mediaItems: MutableList<MediaItem>, resetPosition: Boolean) {}
    override fun setMediaItems(mediaItems: MutableList<MediaItem>, startIndex: Int, startPositionMs: Long) {}
    override fun setMediaItem(mediaItem: MediaItem) {}
    override fun setMediaItem(mediaItem: MediaItem, startPositionMs: Long) {}
    override fun setMediaItem(mediaItem: MediaItem, resetPosition: Boolean) {}
    override fun addMediaItem(mediaItem: MediaItem) {}
    override fun addMediaItem(index: Int, mediaItem: MediaItem) {}
    override fun addMediaItems(mediaItems: MutableList<MediaItem>) {}
    override fun addMediaItems(index: Int, mediaItems: MutableList<MediaItem>) {}
    override fun moveMediaItem(currentIndex: Int, newIndex: Int) {}
    override fun moveMediaItems(fromIndex: Int, toIndex: Int, newIndex: Int) {}
    override fun replaceMediaItem(index: Int, mediaItem: MediaItem) {}
    override fun replaceMediaItems(fromIndex: Int, toIndex: Int, mediaItems: MutableList<MediaItem>) {}
    override fun removeMediaItem(index: Int) {}
    override fun removeMediaItems(fromIndex: Int, toIndex: Int) {}
    override fun clearMediaItems() {}
}

/** Ein Fenster, eine Periode: das ganze Buch auf der globalen Zeitachse. */
private class SingleBookTimeline(private val uid: Any, private val item: MediaItem, private val durationMs: Long) : Timeline() {
    private val durationUs: Long get() = if (durationMs == C.TIME_UNSET) C.TIME_UNSET else durationMs * 1000

    override fun getWindowCount(): Int = 1

    override fun getWindow(windowIndex: Int, window: Window, defaultPositionProjectionUs: Long): Window =
        window.set(
            uid, item, null, C.TIME_UNSET, C.TIME_UNSET, C.TIME_UNSET,
            /* isSeekable = */ true, /* isDynamic = */ false, null,
            /* defaultPositionUs = */ 0, durationUs, 0, 0, 0,
        )

    override fun getPeriodCount(): Int = 1

    override fun getPeriod(periodIndex: Int, period: Period, setIds: Boolean): Period =
        period.set(uid, uid, 0, durationUs, 0)

    override fun getIndexOfPeriod(uid: Any): Int = if (uid == this.uid) 0 else C.INDEX_UNSET

    override fun getUidOfPeriod(periodIndex: Int): Any = uid
}
