package de.letzgo.abstand.transcript

import android.content.Context
import android.util.Log
import de.letzgo.abstand.data.absLocale
import de.letzgo.abstand.logic.PlayerTeleprompterLayout
import de.letzgo.abstand.logic.PlayerTeleprompterMetrics
import de.letzgo.abstand.logic.PlayerTranscriptLibrary
import de.letzgo.abstand.logic.PlayerTranscriptLine
import de.letzgo.abstand.logic.PlayerTranscriptLineAccumulator
import de.letzgo.abstand.logic.PlayerTranscriptTimeline
import de.letzgo.abstand.logic.PlayerTranscriptTrackCache
import de.letzgo.abstand.logic.PlayerTranscriptWord
import de.letzgo.abstand.logic.PlayerTranscriptWordLookup
import de.letzgo.abstand.logic.speech.SpeechModelCatalog
import de.letzgo.abstand.logic.speech.SpeechModelStore
import de.letzgo.abstand.logic.speech.SpeechTranscriberAvailability
import de.letzgo.abstand.logic.speech.SpeechTranscriptionLocaleResolver
import de.letzgo.abstand.player.PlaybackController
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.util.Locale
import kotlin.math.abs
import kotlin.math.max

/** iOS: `PlayerLiveTranscriptionError` (Texte identisch, wo die Plattform gleich ist). */
object PlayerLiveTranscriptionError {
    const val noActivePlayback = "Nothing is playing."
    const val localeNotSupported =
        "Speech recognition is not available for this language on this device. Try setting the book language in Audiobookshelf."
    const val modelDownloadFailed = "Could not download the speech model. Check your connection and try again."
    const val conversionFailed = "Audio could not be prepared for transcription."
    const val audioSourceUnavailable = "No audio source for transcription."
    const val streamingPlaybackUnavailable =
        "Read along needs a fully downloaded audiobook. Finish the download and try again."
    const val transcriptionProgressStalled = "Transcription stopped making progress. Try again."
    const val recognizerUnavailable = "Speech recognition is not available on this device."
}

/** iOS: `PlayerTranscriptWordLookupSelection` — beim Tippen eingefroren. */
data class PlayerTranscriptWordLookupSelection(
    val word: PlayerTranscriptWord,
    val term: String,
    val sourceLocale: Locale?,
) {
    /** Zeitanker statt volatiler Wort-IDs. */
    val id: String get() = PlayerTranscriptWordLookup.selectionId(term, word.globalStart)
}

/**
 * Android: Vosk-Modelle werden nie ungefragt geladen (iOS lädt `SpeechTranscriber`-Assets über
 * `AssetInventory` automatisch). Solange dieses Angebot steht, wartet der Start auf
 * [PlayerLiveTranscriptionController.approveSpeechModelDownload].
 */
data class SpeechModelOffer(val languageName: String, val sizeText: String)

/**
 * iOS: `PlayerLiveTranscriptionController` — Read Along / Teleprompter. Kein Live-Feed: beim Start
 * wird das Transkript des aktuellen Tracks aus dem Cache geladen, nur die noch nicht abgedeckte
 * Strecke wird produziert (ungedrosselt, vor der Abspielposition). Sprünge und Track-Wechsel setzen
 * die Produktion an der neuen Stelle auf. Ein Prozess-Singleton, nur auf dem Main-Thread benutzen.
 */
class PlayerLiveTranscriptionController private constructor(private val appContext: Context) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val player: PlaybackController get() = PlaybackController.shared(appContext)

    // MARK: - Veröffentlichter Zustand

    private val _isTeleprompterModeActive = MutableStateFlow(false)
    /** Nutzer hat Read Along eingeschaltet — steuert UI und Lebenszyklus. */
    val isTeleprompterModeActive: StateFlow<Boolean> = _isTeleprompterModeActive.asStateFlow()
    private val _isEnabled = MutableStateFlow(false)
    val isEnabled: StateFlow<Boolean> = _isEnabled.asStateFlow()
    private val _isPreparing = MutableStateFlow(false)
    val isPreparing: StateFlow<Boolean> = _isPreparing.asStateFlow()
    private val _isSessionBusy = MutableStateFlow(false)
    val isSessionBusy: StateFlow<Boolean> = _isSessionBusy.asStateFlow()
    private val _isTeleprompterReady = MutableStateFlow(false)
    val isTeleprompterReady: StateFlow<Boolean> = _isTeleprompterReady.asStateFlow()
    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()
    private val _transcriptLines = MutableStateFlow<List<PlayerTranscriptLine>>(emptyList())
    val transcriptLines: StateFlow<List<PlayerTranscriptLine>> = _transcriptLines.asStateFlow()
    private val _modelDownloadProgress = MutableStateFlow<Double?>(null)
    val modelDownloadProgress: StateFlow<Double?> = _modelDownloadProgress.asStateFlow()
    private val _speechModelOffer = MutableStateFlow<SpeechModelOffer?>(null)
    val speechModelOffer: StateFlow<SpeechModelOffer?> = _speechModelOffer.asStateFlow()
    private val _localeFallbackNotice = MutableStateFlow<String?>(null)
    val localeFallbackNotice: StateFlow<String?> = _localeFallbackNotice.asStateFlow()
    private val _wordLookupSelection = MutableStateFlow<PlayerTranscriptWordLookupSelection?>(null)
    /** Wort-Lookup-Sheet (am stabilen Player-Root präsentiert, nicht an der Teleprompter-View). */
    val wordLookupSelection: StateFlow<PlayerTranscriptWordLookupSelection?> = _wordLookupSelection.asStateFlow()
    private val _teleprompterSyncGeneration = MutableStateFlow(0L)
    val teleprompterSyncGeneration: StateFlow<Long> = _teleprompterSyncGeneration.asStateFlow()
    private val _teleprompterSyncedPlaybackTime = MutableStateFlow(0.0)
    val teleprompterSyncedPlaybackTime: StateFlow<Double> = _teleprompterSyncedPlaybackTime.asStateFlow()

    private val _recapText = MutableStateFlow<String?>(null)
    val recapText: StateFlow<String?> = _recapText.asStateFlow()
    private val _recapErrorMessage = MutableStateFlow<String?>(null)
    val recapErrorMessage: StateFlow<String?> = _recapErrorMessage.asStateFlow()
    private val _isGeneratingRecap = MutableStateFlow(false)
    val isGeneratingRecap: StateFlow<Boolean> = _isGeneratingRecap.asStateFlow()
    private val _recapFallbackNotice = MutableStateFlow<String?>(null)
    val recapFallbackNotice: StateFlow<String?> = _recapFallbackNotice.asStateFlow()
    private val _recapShowsTranscript = MutableStateFlow(false)
    /** Android immer `true`: es gibt kein On-Device-Sprachmodell für die Zusammenfassung. */
    val recapShowsTranscript: StateFlow<Boolean> = _recapShowsTranscript.asStateFlow()

    /** iOS: `isReadAlongAvailable` — Vosk läuft auf jedem Gerät. */
    val isReadAlongAvailable: Boolean get() = SpeechTranscriberAvailability.isSupported()

    /** iOS: `canGenerateRecap` (Apple Intelligence). Android: Recap = Transkript der letzten 5 Minuten. */
    val canGenerateRecap: Boolean get() = true

    /** Sprache der laufenden Transkription (Wort-Übersetzung). */
    val transcriptionLocale: Locale? get() = activeContext?.localeIdentifier?.let(Locale::forLanguageTag)

    // MARK: - Interner Zustand

    /** Erkennungswörter des aktiven Tracks — der Teleprompter zeigt immer das Transkript (iOS gleich). */
    private var finalizedWords: List<PlayerTranscriptWord> = emptyList()
    private var recapBookId: String? = null
    private var recapPlaybackTime: Double? = null
    private var recapGeneration = 0
    private val lineAccumulator = PlayerTranscriptLineAccumulator()
    private var reflowFontSize = 0.0
    private var reflowWidth = 0.0
    private var activeContext: PlayerTranscriptionAudioContext? = null
    private var activeModel: SpeechModelCatalog.Entry? = null

    private var trackCache: PlayerTranscriptTrackCache? = null
    private var activeTrackKey: String? = null
    private var activeTrackDuration = 0.0
    private var productionRunId = 0
    private var productionJob: Job? = null
    private var isActivatingTrack = false
    private var trackActivationGeneration = 0
    private var productionStartLocalTime = 0.0
    private var productionThroughLocalTime = 0.0
    private var isProducingTranscript = false

    private var pendingStartupSyncTicks = 0
    private var enableJob: Job? = null
    private var stopJob: Job? = null
    private var sessionGeneration = 0
    private var activeTranscriptionBookId: String? = null
    private var modelApproval: CompletableDeferred<Unit>? = null

    init {
        // iOS: `handlePlaybackTick` aus dem Player-Tick (Position ändert sich nur bei Wiedergabe/Sprung).
        scope.launch {
            player.globalPosition.collect { if (_isTeleprompterModeActive.value && _isEnabled.value) handlePlaybackTick() }
        }
        // iOS: `playBook` → `disable()`, `tearDownPlayer` → `playbackDidStop()` — anderes Medium beendet die Session.
        scope.launch {
            combine(player.activeBook, player.activePlaybackEpisodeId) { book, ep ->
                book?.let { PlaybackTranscription.storageId(it.id, ep) }
            }.distinctUntilChanged().collect { storageId ->
                if (!_isTeleprompterModeActive.value) return@collect
                val active = activeTranscriptionBookId
                if (storageId == null || (active != null && active != storageId)) disable()
            }
        }
    }

    // MARK: - Öffentliche Steuerung

    /** iOS: `isReadAlongDownloadReady` — Button nur bei vollständig geladenem Titel aktiv. */
    fun isReadAlongDownloadReady(): Boolean = PlaybackTranscription.isReadAlongDownloadReady(player)

    /** iOS: `notifyPlaybackTrackAdvanced` — schneller Handoff bei Track-Wechsel. */
    fun notifyPlaybackTrackAdvanced() {
        if (_isTeleprompterModeActive.value && _isEnabled.value) followPlaybackPosition()
    }

    /** iOS: `toggle(player:)` — ein laufender Start zählt als „an" (Tap bricht ihn ab). */
    fun toggle() {
        if (!isReadAlongAvailable) return
        if (_isTeleprompterModeActive.value || _isEnabled.value || _isSessionBusy.value) {
            _errorMessage.value = null
            disable()
            return
        }
        startTeleprompterMode()
    }

    /**
     * iOS: `startTeleprompterMode(player:)` — UI sofort an, Session asynchron. Jedes Einschalten
     * beginnt eine neue Session (vorherige wird vorher abgeräumt).
     */
    fun startTeleprompterMode() {
        if (!isReadAlongAvailable) return
        _errorMessage.value = null
        if (player.activeBook.value == null) {
            _errorMessage.value = PlayerLiveTranscriptionError.noActivePlayback
            return
        }
        if (!isReadAlongDownloadReady()) {
            _errorMessage.value = PlayerLiveTranscriptionError.streamingPlaybackUnavailable
            return
        }
        sessionGeneration += 1
        val generation = sessionGeneration
        _isTeleprompterModeActive.value = true
        _isSessionBusy.value = true
        _isPreparing.value = true
        val previousEnable = enableJob
        val previousStop = stopJob
        enableJob = scope.launch {
            previousEnable?.cancel()
            previousEnable?.join()
            previousStop?.join()
            stopSession()
            resetTranscriptContent()
            if (sessionGeneration != generation) return@launch
            runEnableSession(generation)
        }
    }

    /** iOS: `disable()` — Modus beenden, Produktion stoppen und sichern (idempotent). */
    fun disable(resetError: Boolean = true) {
        if (resetError) _errorMessage.value = null
        sessionGeneration += 1
        enableJob?.cancel()
        enableJob = null
        modelApproval?.cancel()
        modelApproval = null
        finishTeleprompterMode(resetContent = true)
        val previous = stopJob
        stopJob = scope.launch {
            previous?.join()
            stopSession()
        }
    }

    /** Android: Download des angebotenen Sprachmodells nach ausdrücklichem Tap. */
    fun approveSpeechModelDownload() {
        modelApproval?.complete(Unit)
    }

    /** Fehlerkarte verworfen. */
    fun dismissError() {
        _errorMessage.value = null
    }

    fun selectWordForLookup(word: PlayerTranscriptWord) {
        if (word.isWhitespaceOnly) return
        val term = PlayerTranscriptWordLookup.normalizedTerm(word.text)
        if (term.isEmpty()) return
        _wordLookupSelection.value = PlayerTranscriptWordLookupSelection(word, term, transcriptionLocale)
    }

    fun clearWordLookupSelection() {
        _wordLookupSelection.value = null
    }

    // MARK: - Session-Lebenszyklus

    private suspend fun runEnableSession(generation: Int) {
        _isPreparing.value = true
        _isSessionBusy.value = true
        try {
            if (!sessionIsCurrent(generation)) return
            startSession(generation)
            if (!sessionIsCurrent(generation)) {
                stopSession()
                return
            }
            setSessionRunning(true)
            pendingStartupSyncTicks = 15
            syncTeleprompterToPlayback(PlaybackTranscription.livePosition(player))
        } catch (c: CancellationException) {
            if (sessionGeneration == generation && !_isEnabled.value && _isTeleprompterModeActive.value) {
                sessionGeneration += 1
                finishTeleprompterMode(resetContent = true)
                withContext(NonCancellable) { stopSession() }
            }
            throw c
        } catch (t: Throwable) {
            if (sessionGeneration != generation) return
            Log.w(TAG, "read along start failed", t)
            _errorMessage.value = userMessage(t)
            sessionGeneration += 1
            finishTeleprompterMode(resetContent = true)
            stopSession()
        } finally {
            // Ein neuerer Start hat die Flags schon für sich gesetzt — nicht zurücksetzen.
            if (sessionGeneration == generation) {
                _isPreparing.value = false
                _isSessionBusy.value = false
            }
        }
    }

    private fun userMessage(t: Throwable): String = when (t) {
        is SessionFailure -> t.message ?: PlayerLiveTranscriptionError.audioSourceUnavailable
        is SpeechTranscriptionLocaleResolver.LocaleNotSupportedException -> PlayerLiveTranscriptionError.localeNotSupported
        is UnsatisfiedLinkError -> PlayerLiveTranscriptionError.recognizerUnavailable
        is PlayerTranscriptProducerException -> t.message ?: PlayerLiveTranscriptionError.conversionFailed
        else -> t.localizedMessage ?: PlayerLiveTranscriptionError.audioSourceUnavailable
    }

    private class SessionFailure(message: String) : Exception(message)

    /** iOS: `startSession` — Cache laden, fehlende Strecke produzieren. */
    private suspend fun startSession(generation: Int) {
        if (!sessionIsCurrent(generation)) return
        resetTranscriptContent()
        activeTranscriptionBookId = PlaybackTranscription.transcriptionStorageId(player)
        if (player.activeBook.value == null) throw SessionFailure(PlayerLiveTranscriptionError.noActivePlayback)
        val context = withContext(Dispatchers.IO) {
            // `isUsingLocalTrackFiles` liest das Manifest — nicht auf dem Main-Thread.
            PlaybackTranscription.isReadAlongDownloadReady(player)
        }.let { ready ->
            if (!ready) throw SessionFailure(PlayerLiveTranscriptionError.streamingPlaybackUnavailable)
            PlaybackTranscription.makeTranscriptionAudioContext(player)
                ?: throw SessionFailure(PlayerLiveTranscriptionError.audioSourceUnavailable)
        }
        if (!sessionIsCurrent(generation)) return

        val languageTag = PlaybackTranscription.preferredTranscriptionLanguageTag(player)
        val selection = TranscriptionModelSelection.select(languageTag)
        _localeFallbackNotice.value = if (selection.usedFallback) {
            "Using ${languageName(selection.locale)} speech recognition (book language not installed)."
        } else null

        ensureSpeechModel(selection.entry, generation)
        if (!sessionIsCurrent(generation)) return
        activeModel = selection.entry
        activateTrack(context.copy(localeIdentifier = selection.localeIdentifier), generation)
    }

    /**
     * iOS: `ensureSpeechModel(locale:)` — Android lädt nur nach ausdrücklicher Zustimmung
     * ([approveSpeechModelDownload]); bis dahin steht [speechModelOffer].
     */
    private suspend fun ensureSpeechModel(entry: SpeechModelCatalog.Entry, generation: Int) {
        if (SpeechModelStore.isInstalled(appContext, entry)) return
        val approval = CompletableDeferred<Unit>()
        modelApproval = approval
        _speechModelOffer.value = SpeechModelOffer(entry.displayName, entry.sizeText)
        _isPreparing.value = false
        try {
            approval.await()
        } finally {
            _speechModelOffer.value = null
            if (modelApproval === approval) modelApproval = null
        }
        if (!sessionIsCurrent(generation)) return
        _isPreparing.value = true
        _modelDownloadProgress.value = 0.0
        try {
            SpeechModelStore.download(appContext, entry) { p ->
                scope.launch { if (_modelDownloadProgress.value != null) _modelDownloadProgress.value = p }
            }
        } catch (c: CancellationException) {
            throw c
        } catch (t: Throwable) {
            Log.w(TAG, "speech model download failed", t)
            throw SessionFailure(PlayerLiveTranscriptionError.modelDownloadFailed)
        } finally {
            _modelDownloadProgress.value = null
        }
    }

    /** iOS: `activateTrack` — Cache laden, anzeigen, Produktion anstoßen. */
    private suspend fun activateTrack(context: PlayerTranscriptionAudioContext, generation: Int) {
        // Alten Lauf erst abwarten: sein Abbruchpfad persistiert noch für den alten Track.
        productionJob?.let { running ->
            productionJob = null
            running.cancel()
            running.join()
        }
        trackActivationGeneration += 1
        val activation = trackActivationGeneration
        val bookId = activeTranscriptionBookId ?: ""
        val trackKey = PlaybackTranscription.transcriptionTrackKey(player)
        val trackDuration = PlaybackTranscription.currentTranscriptionTrackDuration(player)
        PlayerTranscriptLibrary.activeAccount = TranscriptAccount.current()
        val loaded = PlayerTranscriptLibrary.cache(bookId, context.trackIndex, context.localeIdentifier)
        if (!sessionIsCurrent(generation) || trackActivationGeneration != activation) return
        activeContext = context
        activeTrackKey = trackKey
        activeTrackDuration = trackDuration
        finalizedWords = emptyList()
        lineAccumulator.reset()
        trackCache = loaded ?: PlayerTranscriptTrackCache(localeIdentifier = context.localeIdentifier, trackIndex = context.trackIndex)

        rebuildDisplayFromCache()
        val playbackLocal = PlaybackTranscription.localPlaybackSeconds(player, context.trackGlobalOffset)
        startProduction(playbackLocal - PRE_ROLL_SECONDS, generation)
        syncTeleprompterToPlayback(PlaybackTranscription.livePosition(player))
    }

    private fun rebuildDisplayFromCache() {
        val cache = trackCache
        val context = activeContext
        if (cache == null || context == null) {
            finalizedWords = emptyList()
            lineAccumulator.reset()
            publishWords()
            return
        }
        finalizedWords = PlayerTranscriptTimeline.recognizedWords(cache, context.trackIndex, context.trackGlobalOffset)
        lineAccumulator.rebuildLines(finalizedWords, lineAccumulator.maxCharactersPerLine)
        publishWords()
    }

    // MARK: - Produktion

    /** iOS: `startProduction(fromLocalTime:generation:)` — Lücke für Lücke bis zum Track-Ende. */
    private fun startProduction(fromLocalTime: Double, generation: Int) {
        val context = activeContext ?: return
        val cache = trackCache ?: return
        val model = activeModel ?: return
        val start: Double = cache.firstUncoveredTime(max(0.0, fromLocalTime), activeTrackDuration) ?: run {
            isProducingTranscript = false
            return
        }
        // Nur bis zum nächsten transkribierten Segment, danach an der nächsten Lücke weiter (iOS gleich).
        val end = cache.nextCoveredStart(start)
        productionJob?.cancel()
        productionRunId += 1
        val runId = productionRunId
        val trackIndex = context.trackIndex
        val localeId = context.localeIdentifier
        val bookId = activeTranscriptionBookId ?: ""
        productionStartLocalTime = start
        productionThroughLocalTime = start
        isProducingTranscript = true

        productionJob = scope.launch {
            // Hintergrund-Vorproduktion pausiert, solange der Teleprompter selbst produziert.
            PlayerTranscriptLibrary.beginPriorityWork()
            val pending = ArrayList<PlayerTranscriptTrackCache.Word>()
            var through = start
            var segmentStart = start
            var sawWords = false
            try {
                PlayerTranscriptProducer.transcribe(appContext, context.assetFile, start, end, model).collect { batch ->
                    if (!sessionIsCurrent(generation) || activeContext?.trackIndex != trackIndex) throw CancellationException()
                    if (batch.words.isNotEmpty()) {
                        sawWords = true
                        pending.addAll(batch.words.map { PlayerTranscriptTrackCache.Word(it.text, it.start, it.end) })
                        appendProducedWords(batch.words, trackIndex)
                    }
                    through = max(through, batch.processedThrough)
                    productionThroughLocalTime = through
                    if (through - segmentStart >= PlayerTranscriptLibrary.TRANSCRIPT_PERSIST_INTERVAL_SECONDS) {
                        persistProducedSegment(segmentStart, through, pending.toList(), bookId, trackIndex, localeId)
                        pending.clear()
                        segmentStart = through
                    }
                }
                persistProducedSegment(segmentStart, through, pending.toList(), bookId, trackIndex, localeId)
                // Lauf durch, aber kein einziges Wort — sonst bliebe die Karte dauerhaft im Ladezustand.
                if (productionRunId == runId && !sawWords && _transcriptLines.value.isEmpty() && sessionIsCurrent(generation)) {
                    scope.launch { failTeleprompterSession(PlayerLiveTranscriptionError.transcriptionProgressStalled, generation) }
                }
                if (end != null && productionRunId == runId && sessionIsCurrent(generation) && activeContext?.trackIndex == trackIndex) {
                    scope.launch { if (productionRunId == runId) startProduction(end, generation) }
                }
            } catch (c: CancellationException) {
                withContext(NonCancellable) {
                    persistProducedSegment(segmentStart, through, pending.toList(), bookId, trackIndex, localeId)
                }
                throw c
            } catch (t: Throwable) {
                withContext(NonCancellable) {
                    persistProducedSegment(segmentStart, through, pending.toList(), bookId, trackIndex, localeId)
                }
                Log.w(TAG, "read along production failed", t)
                // Nur melden, wenn nichts angezeigt werden kann — sonst läuft der Cache-Teil weiter.
                if (_transcriptLines.value.isEmpty() && sessionIsCurrent(generation)) {
                    val message = userMessage(t)
                    scope.launch { failTeleprompterSession(message, generation) }
                }
            } finally {
                PlayerTranscriptLibrary.endPriorityWork()
                if (productionRunId == runId && sessionIsCurrent(generation) && activeContext?.trackIndex == trackIndex) {
                    isProducingTranscript = false
                }
            }
        }
    }

    /** iOS: `appendProducedWords` — Normalfall anhängen, sonst einsortieren und neu umbrechen. */
    private fun appendProducedWords(words: List<PlayerTranscriptProducedWord>, trackIndex: Int) {
        val context = activeContext ?: return
        if (context.trackIndex != trackIndex || words.isEmpty()) return
        val offset = context.trackGlobalOffset
        val tail = finalizedWords.lastOrNull()?.globalStart ?: -1.0
        val mapped = words.mapIndexed { index, word ->
            PlayerTranscriptWord(
                id = "p-$trackIndex-${Math.round(word.start * 1000)}-$index",
                text = word.text + " ",
                globalStart = offset + word.start,
                globalEnd = max(offset + word.start, offset + word.end),
            )
        }
        val firstStart = mapped.first().globalStart
        if (firstStart > tail) {
            finalizedWords = finalizedWords + mapped
            lineAccumulator.appendFinalizedWords(mapped)
        } else {
            finalizedWords = TranscriptWordMerge.mergedByTime(finalizedWords + mapped)
            lineAccumulator.rebuildLines(finalizedWords, lineAccumulator.maxCharactersPerLine)
        }
        publishWords()
    }

    /** iOS: `persistProducedSegment` — mit den beim Produktionsstart eingefangenen Werten. */
    private suspend fun persistProducedSegment(
        start: Double,
        end: Double,
        words: List<PlayerTranscriptTrackCache.Word>,
        bookId: String,
        trackIndex: Int,
        localeIdentifier: String,
    ) {
        if (!(end > start) || bookId.isEmpty()) return
        val merged = PlayerTranscriptLibrary.mergeAndSave(
            PlayerTranscriptTrackCache.Segment(start, end, words), bookId, trackIndex, localeIdentifier,
        )
        if (activeContext?.trackIndex == trackIndex) trackCache = merged
    }

    /** iOS: `followPlaybackPosition` — Track-Wechsel und Sprünge. */
    private fun followPlaybackPosition() {
        if (!_isTeleprompterModeActive.value || !_isEnabled.value) return
        val context = activeContext ?: return
        val generation = sessionGeneration
        if (PlaybackTranscription.transcriptionTrackKey(player) != activeTrackKey) {
            if (isActivatingTrack) return
            isActivatingTrack = true
            scope.launch {
                try {
                    if (!sessionIsCurrent(generation)) return@launch
                    val fresh = PlaybackTranscription.makeTranscriptionAudioContext(player) ?: return@launch
                    if (!sessionIsCurrent(generation)) return@launch
                    activateTrack(fresh.copy(localeIdentifier = context.localeIdentifier), generation)
                } finally {
                    isActivatingTrack = false
                }
            }
            return
        }
        val playbackLocal = PlaybackTranscription.localPlaybackSeconds(player, context.trackGlobalOffset)
        val cache = trackCache ?: return
        if (!TranscriptFollowPolicy.shouldRestartProduction(
                playbackLocal = playbackLocal,
                covered = cache.covers(playbackLocal),
                isProducing = isProducingTranscript,
                productionStart = productionStartLocalTime,
                productionThrough = productionThroughLocalTime,
            )
        ) return
        startProduction(playbackLocal - PRE_ROLL_SECONDS, generation)
    }

    /** iOS: `stopSession()` — Produktion stoppen, bisherigen Stand sichern. */
    private suspend fun stopSession() {
        val job = productionJob
        productionJob = null
        job?.cancel()
        job?.join()
        isProducingTranscript = false
        trackCache = null
        activeContext = null
        activeTrackKey = null
        productionStartLocalTime = 0.0
        productionThroughLocalTime = 0.0
    }

    private fun failTeleprompterSession(message: String, generation: Int) {
        if (sessionGeneration != generation || !_isTeleprompterModeActive.value) return
        _errorMessage.value = message
        disable(resetError = false)
    }

    private fun sessionIsCurrent(generation: Int): Boolean = _isTeleprompterModeActive.value && sessionGeneration == generation

    private fun setSessionRunning(running: Boolean) {
        if (_isEnabled.value != running) _isEnabled.value = running
    }

    private fun finishTeleprompterMode(resetContent: Boolean) {
        pendingStartupSyncTicks = 0
        _isTeleprompterModeActive.value = false
        setSessionRunning(false)
        _isPreparing.value = false
        _isSessionBusy.value = false
        if (resetContent) resetTranscriptContent()
        _isTeleprompterReady.value = false
        _teleprompterSyncGeneration.value = 0
        _teleprompterSyncedPlaybackTime.value = 0.0
        _modelDownloadProgress.value = null
        _speechModelOffer.value = null
        _localeFallbackNotice.value = null
        activeTranscriptionBookId = null
    }

    private fun handlePlaybackTick() {
        followPlaybackPosition()
        refreshTeleprompterReadiness()
        if (pendingStartupSyncTicks > 0) {
            pendingStartupSyncTicks -= 1
            syncTeleprompterToPlayback(PlaybackTranscription.livePosition(player))
        }
    }

    private fun resetTranscriptContent() {
        finalizedWords = emptyList()
        lineAccumulator.reset()
        _transcriptLines.value = emptyList()
        _isTeleprompterReady.value = false
        reflowFontSize = 0.0
        reflowWidth = 0.0
    }

    private fun publishWords() {
        _transcriptLines.value = if (finalizedWords.isEmpty()) emptyList() else lineAccumulator.publishedLines()
        refreshTeleprompterReadiness()
    }

    /** iOS: `refreshTeleprompterReadiness` — bereit, sobald Text für die aktuelle Stelle vorliegt. */
    private fun refreshTeleprompterReadiness() {
        if (!_isTeleprompterModeActive.value) {
            if (_isTeleprompterReady.value) _isTeleprompterReady.value = false
            return
        }
        val playback = PlaybackTranscription.livePosition(player)
        val lines = _transcriptLines.value
        val progressEnd = finalizedWords.lastOrNull()?.globalEnd ?: 0.0
        val ready = lines.isNotEmpty() &&
            (progressEnd >= playback - 1 || lines.any { it.globalStart <= playback && it.globalEnd >= playback })
        if (ready == _isTeleprompterReady.value) return
        _isTeleprompterReady.value = ready
        if (ready) syncTeleprompterToPlayback(playback)
    }

    /** iOS: `updateTeleprompterContentWidth` — Umbruch an Breite (dp) und Schriftgröße anpassen. */
    fun updateTeleprompterContentWidth(width: Double, layout: PlayerTeleprompterLayout = PlayerTeleprompterMetrics.defaultLayout) {
        val limit = PlayerTeleprompterMetrics.characterLimit(width, layout)
        val layoutChanged = abs(reflowFontSize - layout.fontSize) > 0.01 || abs(reflowWidth - width) > 0.01
        val limitChanged = lineAccumulator.maxCharactersPerLine != limit
        if (!layoutChanged && !limitChanged) return
        reflowFontSize = layout.fontSize
        reflowWidth = width
        if (finalizedWords.isEmpty()) {
            lineAccumulator.maxCharactersPerLine = limit
            return
        }
        lineAccumulator.rebuildLines(finalizedWords, limit)
        publishWords()
    }

    /** iOS: `syncTeleprompterToPlayback(at:)` — Anzeige-Uhr der View zurücksetzen. */
    fun syncTeleprompterToPlayback(playbackGlobalTime: Double) {
        _teleprompterSyncedPlaybackTime.value = max(0.0, playbackGlobalTime)
        _teleprompterSyncGeneration.value += 1
        refreshTeleprompterReadiness()
    }

    fun activeWordHit(globalTime: Double): PlayerTranscriptTimeline.WordHit? =
        PlayerTranscriptTimeline.activeWordHit(_transcriptLines.value, globalTime)

    fun fractionalActiveLinePosition(globalTime: Double): Double =
        PlayerTranscriptTimeline.fractionalActiveLinePosition(_transcriptLines.value, globalTime)

    // MARK: - Recap

    /**
     * iOS: `generateRecap(player:)` — die letzten fünf Minuten aus den lokalen Dateien (Cache zuerst,
     * Lücken werden nachproduziert). Android hat kein On-Device-Sprachmodell für Zusammenfassungen
     * (iOS: Apple Intelligence) — angezeigt wird deshalb immer das Transkript (iOS-Fallbackpfad).
     */
    fun generateRecap() {
        if (_isGeneratingRecap.value) return
        val end = PlaybackTranscription.livePosition(player)
        val bookId = PlaybackTranscription.transcriptionStorageId(player)
        val cachedText = _recapText.value
        val cachedTime = recapPlaybackTime
        if (cachedText != null && recapBookId == bookId && cachedTime != null &&
            end >= cachedTime && end - cachedTime < RECAP_CACHE_PLAYBACK_SECONDS
        ) {
            _recapErrorMessage.value = null
            return
        }
        recapGeneration += 1
        val generation = recapGeneration
        _isGeneratingRecap.value = true
        _recapText.value = null
        _recapErrorMessage.value = null
        _recapFallbackNotice.value = null
        _recapShowsTranscript.value = false
        scope.launch {
            PlayerTranscriptLibrary.beginPriorityWork()
            try {
                val outcome = withTimeoutOrNull((RECAP_GENERATION_TIMEOUT_SECONDS * 1000).toLong()) { buildRecap(end, bookId) }
                if (generation != recapGeneration) return@launch
                when {
                    outcome == null -> _recapErrorMessage.value = "Recap took too long. Please try again later."
                    outcome.error != null -> {
                        _recapText.value = null
                        _recapErrorMessage.value = outcome.error
                    }
                    else -> {
                        _recapText.value = outcome.text
                        _recapShowsTranscript.value = true
                        _recapFallbackNotice.value = outcome.notice
                        recapBookId = bookId
                        recapPlaybackTime = end
                    }
                }
            } catch (c: CancellationException) {
                throw c
            } catch (t: Throwable) {
                Log.w(TAG, "recap failed", t)
                if (generation == recapGeneration) {
                    _recapText.value = null
                    _recapErrorMessage.value = "The on-device recap could not be created. Please try again."
                }
            } finally {
                PlayerTranscriptLibrary.endPriorityWork()
                if (generation == recapGeneration) _isGeneratingRecap.value = false
            }
        }
    }

    private class RecapOutcome(val text: String? = null, val notice: String? = null, val error: String? = null)

    private suspend fun buildRecap(end: Double, bookId: String?): RecapOutcome {
        val ready = withContext(Dispatchers.IO) { PlaybackTranscription.isReadAlongDownloadReady(player) }
        if (!ready) return RecapOutcome(error = "Download the audiobook to create an on-device recap.")
        val range = max(0.0, end - RECAP_WINDOW_SECONDS)..end
        val sources = PlaybackTranscription.localTranscriptionTrackSources(player).filter {
            it.globalRange.endInclusive >= range.start && it.globalRange.start <= range.endInclusive
        }
        if (sources.isEmpty()) return RecapOutcome(error = "The last five minutes of audio are unavailable for transcription.")
        val languageTag = PlaybackTranscription.preferredTranscriptionLanguageTag(player)
        val selection = try {
            TranscriptionModelSelection.select(languageTag)
        } catch (e: SpeechTranscriptionLocaleResolver.LocaleNotSupportedException) {
            return RecapOutcome(error = PlayerLiveTranscriptionError.localeNotSupported)
        }
        if (!SpeechModelStore.isInstalled(appContext, selection.entry)) {
            return RecapOutcome(
                error = "Download the ${selection.entry.displayName} speech model (${selection.entry.sizeText}) in read along first.",
            )
        }
        val notices = ArrayList<String>()
        if (selection.usedFallback && absLocale(fromABSMetadataLanguage = languageTag) != null) {
            notices.add("Recap transcribed in ${languageName(selection.locale)} (book language not installed).")
        }
        PlayerTranscriptLibrary.activeAccount = TranscriptAccount.current()
        val transcript = PlayerTranscriptProduction.transcriptText(
            appContext, bookId ?: "", sources, range, selection.entry, selection.localeIdentifier,
        )
        if (transcript.isEmpty()) return RecapOutcome(error = "No speech was recognized in the last five minutes. Try again later.")
        notices.add("On-device summaries aren't available on Android — showing the transcript instead.")
        return RecapOutcome(text = transcript, notice = notices.joinToString("\n"))
    }

    private fun languageName(locale: Locale): String =
        locale.getDisplayLanguage(Locale.getDefault()).takeIf { it.isNotEmpty() }
            ?.replaceFirstChar { it.titlecase(Locale.getDefault()) } ?: locale.toLanguageTag()

    companion object {
        private const val TAG = "ReadAlong"
        const val PRE_ROLL_SECONDS = 4.0
        /** Ein Recap bleibt für mindestens eine weitere Hörminute gültig. */
        const val RECAP_CACHE_PLAYBACK_SECONDS = 60.0
        const val RECAP_GENERATION_TIMEOUT_SECONDS = 90.0
        const val RECAP_WINDOW_SECONDS = 300.0

        @Volatile private var instance: PlayerLiveTranscriptionController? = null

        fun shared(context: Context): PlayerLiveTranscriptionController =
            instance ?: synchronized(this) {
                instance ?: PlayerLiveTranscriptionController(context.applicationContext).also { instance = it }
            }

        fun sharedOrNull(): PlayerLiveTranscriptionController? = instance
    }
}

/**
 * Reine Entscheidungen des Controllers (JUnit-testbar).
 * iOS: `followPlaybackPosition` — Produktion nur neu aufsetzen, wenn die Wiedergabe nicht abgedeckt
 * ist und der laufende Lauf nicht ohnehin auf diese Stelle zuläuft.
 */
object TranscriptFollowPolicy {
    /** So weit darf die Wiedergabe vor dem Produktionsstand liegen, bevor neu aufgesetzt wird. */
    const val PRODUCTION_FOLLOW_TOLERANCE_SECONDS = 30.0

    fun shouldRestartProduction(
        playbackLocal: Double,
        covered: Boolean,
        isProducing: Boolean,
        productionStart: Double,
        productionThrough: Double,
    ): Boolean {
        if (covered) return false
        if (isProducing && playbackLocal >= productionStart - 1 &&
            playbackLocal <= productionThrough + PRODUCTION_FOLLOW_TOLERANCE_SECONDS
        ) return false
        return true
    }
}

/** iOS: `PlayerLiveTranscriptionController.mergedByTime`. */
object TranscriptWordMerge {
    /** Nach Startzeit sortieren (stabil) und Wörter im selben Zeitfenster nur einmal behalten. */
    fun mergedByTime(words: List<PlayerTranscriptWord>): List<PlayerTranscriptWord> {
        val sorted = words.sortedBy { it.globalStart }
        val out = ArrayList<PlayerTranscriptWord>(sorted.size)
        for (word in sorted) {
            val last = out.lastOrNull()
            if (last != null && abs(last.globalStart - word.globalStart) < 0.05 && last.text == word.text) continue
            out.add(word)
        }
        return out
    }
}
