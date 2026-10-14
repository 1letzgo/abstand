package de.letzgo.abstand.ui.library

import android.content.Context
import de.letzgo.abstand.data.AbsAudioBookmark
import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsDownloadManifest
import de.letzgo.abstand.data.AbsProgressPatch
import de.letzgo.abstand.data.Keys
import de.letzgo.abstand.data.Prefs
import de.letzgo.abstand.data.swiftTrim
import de.letzgo.abstand.downloads.DownloadManager
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.model.ProgressStore
import de.letzgo.abstand.player.PlaybackController
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/**
 * iOS: `AppModel.play(book:resumeAtOverride:autoPlay:)`, `jumpToBookmark` und
 * `continueHeroPlayPillToggle` — Wiedergabe-Einstieg für Bücher-Tab und Detailseiten. Löst den
 * lokalen Download auf (`DownloadManager.resolvedLocalDownloadForPlayback`), sonst Streaming über
 * den Session-Client, und startet `PlaybackController.playBook`.
 */
object LibraryPlayback {
    /** iOS: `isActivelyPlayingMedia(libraryItemId:episodeId:)`. */
    fun isActiveMedia(context: Context, libraryItemId: String, episodeId: String? = null): Boolean {
        val player = PlaybackController.shared(context)
        val active = player.activeBook.value ?: return false
        if (active.id != libraryItemId) return false
        return player.activePlaybackEpisodeId.value?.swiftTrim().orEmpty() == episodeId?.swiftTrim().orEmpty()
    }

    /**
     * iOS: `continueHeroPlayPillToggle` — aktiver Titel: Pause/Weiter; sonst (oder „fertig")
     * Neustart über [play].
     */
    fun toggle(context: Context, book: AbsBook, isFinished: Boolean, model: AppModel = AppModel.shared) {
        val player = PlaybackController.shared(context)
        val isCurrent = isActiveMedia(context, book.id)
        when {
            isCurrent && player.isPlaying.value -> player.pause()
            isCurrent && !isFinished -> player.play()
            else -> model.scope.launch { play(context, book, resumeAtOverride = if (isFinished) 0.0 else null) }
        }
    }

    /** iOS: `play(book:resumeAtOverride:autoPlay:)`. */
    suspend fun play(
        context: Context,
        book: AbsBook,
        resumeAtOverride: Double? = null,
        autoPlay: Boolean = true,
        model: AppModel = AppModel.shared,
    ) {
        val session = model.session
        val progress = model.progress
        val downloaded = model.catalog.downloadedItemIds.value
        val localInfo = withContext(Dispatchers.IO) { DownloadManager.resolvedLocalDownloadForPlayback(book, downloaded) }
        val local = localInfo?.root
        if (session.offlineHomeUIActive && local == null) {
            session.setErrorMessage("Download this title to play it offline.")
            return
        }
        val client = session.clientForOfflineLocalPlayback() ?: return
        session.setErrorMessage(null)
        progress.ensureLocalProgressLoaded()
        val playbackItemId = localInfo?.libraryItemId ?: book.id
        val episodeId = localInfo?.episodeId
        val key = ProgressStore.progressKey(playbackItemId, episodeId)

        // iOS: `resolvedPlaybackStart` — Override, sonst nach „fertig" von vorn, sonst gespeicherte Position.
        val (resume, restart) = when {
            resumeAtOverride != null -> maxOf(0.0, resumeAtOverride) to (resumeAtOverride <= 0.001)
            progress.isLocallyMarkedFinished(key) -> 0.0 to true
            else -> (progress.progress(key)?.currentTime ?: 0.0) to false
        }
        val online = session.mayUseServerNetwork && session.isNetworkReachable.value
        if (restart) {
            // iOS: `preparePlaybackRestartFromBeginning` — lokal zurücksetzen, PATCH nicht abwarten.
            progress.clearLocallyFinishedProgressKey(key)
            if (progress.progress(key) != null) {
                progress.applyLocalMarkUnfinished(playbackItemId, episodeId)
                progress.markPendingLocalProgressSync(key)
            }
            if (online) {
                model.scope.launch {
                    runCatching { client.patchProgress(playbackItemId, episodeId, AbsProgressPatch(currentTime = 0.0, progress = 0.0, isFinished = false)) }
                }
            }
        }
        try {
            var resolved = book
            val manifest = local?.let { withContext(Dispatchers.IO) { AbsDownloadManifest.load(it) } }
            if (manifest != null) {
                val fromManifest = AbsBook.fromDownloadManifest(manifest)
                // Download vorhanden: Metadaten nur kurz nachladen — schlechter Empfang blockiert nicht.
                val expanded = if (online && !book.media.metadata.hasRichMetadata) {
                    withTimeoutOrNull(2_000) { runCatching { client.item(playbackItemId, expanded = true) }.getOrNull() }
                } else null
                resolved = (expanded ?: book).mergingLocalDownloadPlayback(fromManifest)
            } else if (online) {
                val needsExpanded = local != null || book.media.tracks.isNullOrEmpty() || book.media.chapters.isNullOrEmpty()
                if (needsExpanded) runCatching { client.item(playbackItemId, expanded = true) }.getOrNull()?.let { resolved = it }
            }
            PlaybackController.shared(context).playBook(
                client = client,
                book = resolved,
                resumeAt = resume,
                localDownloadRoot = local,
                episodeId = episodeId,
                autoPlay = autoPlay,
                attemptServerPlaySession = online,
                preferClientResumePosition = restart || resumeAtOverride != null,
            )
            Prefs.setString(Keys.lastPlayedItemId, resolved.id)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            session.publishErrorUnlessBenignCancellation(e)
        }
    }

    /** iOS: `jumpToBookmark(_:autoPlay:)` — gleiches Hörbuch: nur Seek, sonst laden und abspielen. */
    suspend fun jumpToBookmark(context: Context, bookmark: AbsAudioBookmark, autoPlay: Boolean = true, model: AppModel = AppModel.shared) {
        val lid = bookmark.libraryItemId.swiftTrim().ifEmpty { return }
        val at = bookmark.time.toDouble()
        val player = PlaybackController.shared(context)
        if (player.activeBook.value?.id == lid && player.activePlaybackEpisodeId.value.isNullOrBlank()) {
            player.seek(at)
            if (autoPlay) player.play()
            return
        }
        val client = model.session.client ?: return
        try {
            val detail = client.item(lid, expanded = true)
            play(context, detail, resumeAtOverride = at, autoPlay = autoPlay, model = model)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            model.session.publishErrorUnlessBenignCancellation(e)
        }
    }
}
