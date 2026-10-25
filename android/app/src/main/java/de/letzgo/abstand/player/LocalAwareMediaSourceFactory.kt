package de.letzgo.abstand.player

import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.exoplayer.drm.DrmSessionManagerProvider
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.upstream.CmcdConfiguration
import androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.extractor.mp3.Mp3Extractor

/**
 * iOS: `PlaybackController.localTrackAsset(url:)` (`AVURLAssetPreferPreciseDurationAndTimingKey`).
 *
 * Lokale Dateien (`file://`) mit MP3-Index-Seeking: ohne schätzt ExoPlayer bei VBR-MP3 Dauer und
 * Seek-Ziele aus Xing-TOC bzw. Bitrate — Position und Teleprompter laufen dann sekundenweise
 * auseinander. Streams bleiben beim Standard: Index-Seeking müsste dort bis zum Ziel mitlesen.
 */
@OptIn(UnstableApi::class)
internal class LocalAwareMediaSourceFactory(dataSources: DataSource.Factory) : MediaSource.Factory {
    private val local = DefaultMediaSourceFactory(
        dataSources,
        DefaultExtractorsFactory().setMp3ExtractorFlags(Mp3Extractor.FLAG_ENABLE_INDEX_SEEKING),
    )
    private val remote = DefaultMediaSourceFactory(dataSources)

    override fun setCmcdConfigurationFactory(cmcdConfigurationFactory: CmcdConfiguration.Factory): MediaSource.Factory = apply {
        local.setCmcdConfigurationFactory(cmcdConfigurationFactory)
        remote.setCmcdConfigurationFactory(cmcdConfigurationFactory)
    }

    override fun setDrmSessionManagerProvider(drmSessionManagerProvider: DrmSessionManagerProvider): MediaSource.Factory = apply {
        local.setDrmSessionManagerProvider(drmSessionManagerProvider)
        remote.setDrmSessionManagerProvider(drmSessionManagerProvider)
    }

    override fun setLoadErrorHandlingPolicy(loadErrorHandlingPolicy: LoadErrorHandlingPolicy): MediaSource.Factory = apply {
        local.setLoadErrorHandlingPolicy(loadErrorHandlingPolicy)
        remote.setLoadErrorHandlingPolicy(loadErrorHandlingPolicy)
    }

    override fun getSupportedTypes(): IntArray = remote.supportedTypes

    override fun createMediaSource(mediaItem: MediaItem): MediaSource {
        val scheme = mediaItem.localConfiguration?.uri?.scheme
        val isLocalFile = scheme == null || scheme == "file"
        return (if (isLocalFile) local else remote).createMediaSource(mediaItem)
    }
}
