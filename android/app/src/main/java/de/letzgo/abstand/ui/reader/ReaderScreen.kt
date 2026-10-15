@file:OptIn(ExperimentalReadiumApi::class, ExperimentalLayoutApi::class)

package de.letzgo.abstand.ui.reader

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsIgnoringVisibility
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import de.letzgo.abstand.data.AbsEbookFormat
import de.letzgo.abstand.data.Prefs
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.player.PlaybackController
import de.letzgo.abstand.reader.BookPageProgress
import de.letzgo.abstand.reader.EbookNarrationJumpController
import de.letzgo.abstand.reader.EbookProgressRules
import de.letzgo.abstand.reader.EbookProgressSync
import de.letzgo.abstand.reader.EbookReaderLauncher
import de.letzgo.abstand.reader.EbookReaderSession
import de.letzgo.abstand.reader.EpubBookPageEstimator
import de.letzgo.abstand.reader.ReaderProgressInfo
import de.letzgo.abstand.reader.ReadiumReaderService
import de.letzgo.abstand.reader.RenderedPageInfo
import de.letzgo.abstand.reader.ServerPositionOffer
import de.letzgo.abstand.store.EbookLocalStore
import de.letzgo.abstand.store.EpubReaderSettings
import de.letzgo.abstand.store.EpubReaderTheme
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.AppType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandAlert
import de.letzgo.abstand.ui.components.AbstandDialog
import de.letzgo.abstand.ui.components.AbstandEmptyScreen
import de.letzgo.abstand.ui.components.AbstandIconButton
import de.letzgo.abstand.ui.components.AbstandInlineSpinner
import de.letzgo.abstand.ui.components.AbstandLoadingSpinner
import de.letzgo.abstand.ui.components.AbstandMenuBox
import de.letzgo.abstand.ui.components.AbstandProminentButton
import de.letzgo.abstand.ui.semibold
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch
import org.json.JSONObject
import org.readium.r2.navigator.epub.EpubNavigatorFactory
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.input.InputListener
import org.readium.r2.navigator.input.TapEvent
import org.readium.r2.navigator.util.DirectionalNavigationAdapter
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.services.locateProgression
import org.readium.r2.shared.publication.services.positions
import org.readium.r2.shared.util.AbsoluteUrl
import de.letzgo.abstand.ui.components.AbstandTextButton

/** iOS: `ReaderChromeMetrics` + Reader-Farben (feste Lesefarben wie Readium, nicht App-Palette). */
internal object ReaderMetrics {
    /** Höhe des dünnen passiven Lesefortschrittsbalkens. */
    val passiveProgressBarHeight = 3.dp
    /** Max. Breite des Hinweis-Overlays für die Reading-Controls. */
    val chromeHintMaxWidth = 320.dp
    /** Mindestbreite der Rand-Tap-Zonen (iOS: 80 pt). */
    val minEdgeTapWidth = 80.dp
    /** Deckkraft der Chrome-Flächen (iOS: `.ultraThinMaterial`). */
    const val chromeSurfaceAlpha = 0.92f
    /** Markierung der zuletzt gehörten Wörter (iOS: `.systemYellow`). */
    val narrationHighlight = AppTheme.narrationHighlight
    const val passiveProgressAlpha = 0.75f
    const val secondaryTextAlpha = 0.72f
    /** Nach Layout-Umbruch (Schriftgröße, Theme) neu messen (iOS: 450 ms). */
    const val relayoutRefreshDelayMs = 450L
    const val chromeHintSeenKey = "abstand_ebook_reader_chrome_hint_seen"
}

/** Reader-Hintergrund je Theme (Readium-Lesefarben, damit Chrome und Seite übereinstimmen). */
private fun EpubReaderTheme.background(): Color = Color(ReadiumReaderService.readiumTheme(this).backgroundColor)
private fun EpubReaderTheme.foreground(): Color = Color(ReadiumReaderService.readiumTheme(this).contentColor)
private val EpubReaderTheme.icon get() = when (this) {
    EpubReaderTheme.light -> SF.sunMax
    EpubReaderTheme.sepia -> SF.textPage
    EpubReaderTheme.dark -> SF.moon
}

/** Für `ui/AppRoot.kt`: zeigt den Reader über den Tabs, solange [EbookReaderLauncher.session] gesetzt ist. */
@Composable
fun EbookReaderOverlay() {
    val session by EbookReaderLauncher.session.collectAsState()
    val s = session ?: return
    key(s.openedAt) { ReaderScreen(s, onClose = EbookReaderLauncher::close) }
}

private sealed interface LoadedReader {
    class Epub(val publication: Publication, val fragment: EpubNavigatorFragment, val positionCount: Int?) : LoadedReader
    class Pdf(val source: PdfDocumentSource, val controller: PdfReaderController) : LoadedReader
}

private const val PAGE_INFO_SCRIPT = """
(function() {
  var root = document.scrollingElement;
  if (!root) return null;
  var vw = window.innerWidth, vh = window.innerHeight;
  if (vw <= 0 || vh <= 0) return null;
  var vertical = root.scrollHeight > root.clientHeight * 1.25;
  var total, cur;
  if (vertical) {
    total = Math.max(1, Math.ceil(root.scrollHeight / vh));
    cur = Math.min(total, Math.max(1, Math.floor((window.scrollY + vh * 0.5) / vh)));
  } else {
    total = Math.max(1, Math.ceil(root.scrollWidth / vw));
    var x = Math.abs(window.scrollX);
    cur = Math.min(total, Math.max(1, Math.floor(x / vw) + 1));
  }
  return { current: cur, total: total };
})();
"""

/**
 * iOS: `ReadiumReaderView` — Vollbild-Overlay mit eigenem Chrome: oben Schließen + Titel, unten
 * Fortschritts-Slider, Schriftgröße, Sprung zur Hörposition, Dauerscroll, Theme, Optionen. Tippen in
 * die Seitenmitte blendet die Steuerung ein; Ränder blättern.
 *
 * Lokaler Locator (seitengenau) bei jeder Positionsänderung; `ebookProgress` zum Server über
 * [EbookProgressSync] — nicht, solange das Server-Positions-Angebot offen ist.
 */
@Composable
fun ReaderScreen(session: EbookReaderSession, onClose: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val id = session.libraryItemId
    val format = session.format

    var readerTheme by remember { mutableStateOf(EpubReaderSettings.loadTheme()) }
    var fontSize by remember { mutableDoubleStateOf(EpubReaderSettings.loadFontSize()) }
    var continuousScroll by remember { mutableStateOf(EpubReaderSettings.loadContinuousScroll()) }
    var loaded by remember { mutableStateOf<LoadedReader?>(null) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var showChrome by remember { mutableStateOf(false) }
    var readProgress by remember { mutableDoubleStateOf(0.0) }
    var readProgressLabel by remember { mutableStateOf("0 %") }
    var bookPageProgress by remember { mutableStateOf<BookPageProgress?>(null) }
    var isScrubbing by remember { mutableStateOf(false) }
    var scrubProgress by remember { mutableFloatStateOf(0f) }
    var actionInProgress by remember { mutableStateOf(false) }
    var confirmReset by remember { mutableStateOf(false) }
    var confirmFinish by remember { mutableStateOf(false) }
    var showsChromeHint by remember { mutableStateOf(false) }
    // Server steht deutlich weiter als der lokale Locator: Angebot statt stillem Überschreiben.
    // Solange es offen ist, geht kein Fortschritt zum Server.
    var serverOffer by remember { mutableStateOf<ServerPositionOffer?>(null) }
    var narrationJump by remember { mutableStateOf<EbookNarrationJumpController?>(null) }
    var pdfPage by remember { mutableIntStateOf(0) }
    val estimator = remember { EpubBookPageEstimator() }

    val epub = loaded as? LoadedReader.Epub
    val pdf = loaded as? LoadedReader.Pdf
    val positionCount = epub?.positionCount ?: pdf?.controller?.pageCount

    fun applyProgress(fraction: Double, position: Int?, pages: BookPageProgress?) {
        if (pages != null) bookPageProgress = pages
        readProgress = if (pages != null) pages.percent / 100.0 else fraction
        // Aus dem aktuellen Zustand (nicht aus der Komposition) — beim Laden ist `loaded` gerade erst gesetzt.
        val count = when (val reader = loaded) {
            is LoadedReader.Epub -> reader.positionCount
            is LoadedReader.Pdf -> reader.controller.pageCount
            null -> null
        }
        readProgressLabel = ReaderProgressInfo.label(fraction, format, position, count, bookPageProgress)
    }

    /** iOS: `publishProgressUpdate` + `fetchRenderedPageInfo` (EPUB) — gerenderte Seiten messen. */
    suspend fun refreshEpubDisplay(reader: LoadedReader.Epub, locator: Locator) {
        val fraction = ReadiumReaderService.fraction(locator)
        val pages = renderedPageInfo(reader.fragment)?.let {
            estimator.bookWidePageProgress(locator.href.toString(), fraction, it)
        }
        if (pages != null) EbookLocalStore.savePageProgress(pages.current, pages.total, id, format)
        applyProgress(fraction, locator.locations.position, pages)
    }

    /** iOS: `navigator(_:locationDidChange:)` + `.readiumReaderProgressDidChange`-Empfänger. */
    fun onLocationChanged(locator: Locator) {
        ReadiumReaderService.persistLocation(locator, id, format)
        if (isScrubbing) return
        val fraction = ReadiumReaderService.fraction(locator)
        val reader = loaded
        if (reader is LoadedReader.Epub) {
            scope.launch { refreshEpubDisplay(reader, locator) }
        } else {
            applyProgress(fraction, locator.locations.position, null)
        }
        narrationJump?.readerLocationDidChange()
        // Offenes Server-Angebot: der (ältere) lokale Stand darf den Server nicht überschreiben.
        if (serverOffer == null) EbookProgressSync.schedule(id, fraction)
    }

    suspend fun seekToProgression(progression: Double) {
        val f = progression.coerceIn(0.0, 1.0)
        actionInProgress = true
        try {
            when (val reader = loaded) {
                is LoadedReader.Epub -> {
                    val target = reader.publication.locateProgression(f)
                        ?: reader.publication.positions().let { p -> p.getOrNull(EbookProgressRules.positionIndex(f, p.size)) }
                    if (target != null) reader.fragment.go(target, animated = false)
                }
                is LoadedReader.Pdf -> reader.controller.goTo((f * reader.controller.pageCount).toInt())
                null -> Unit
            }
        } finally {
            actionInProgress = false
        }
    }

    fun applyEpubPreferences() {
        val reader = loaded as? LoadedReader.Epub ?: return
        estimator.invalidate()
        reader.fragment.submitPreferences(ReadiumReaderService.epubPreferences())
        scope.launch {
            delay(ReaderMetrics.relayoutRefreshDelayMs)
            refreshEpubDisplay(reader, reader.fragment.currentLocator.value)
        }
    }

    fun applyReaderTheme(theme: EpubReaderTheme) {
        if (readerTheme == theme) return
        readerTheme = theme
        EpubReaderSettings.saveTheme(theme)
        applyEpubPreferences()
    }

    // MARK: Laden (iOS: `loadNavigator`)
    LaunchedEffect(session.openedAt) {
        try {
            val saved = ReadiumReaderService.loadLocator(id, format)
            val resumeTarget = if (saved == null) session.serverResumeProgression ?: EbookProgressSync.resumeProgression(id) else null
            when (format) {
                AbsEbookFormat.epub -> {
                    val publication = ReadiumReaderService.openPublication(session.file)
                    val positions = runCatching { publication.positions() }.getOrDefault(emptyList())
                    estimator.configure(publication.readingOrder.map { it.url().toString() })
                    val initial = ReadiumReaderService.resolveInitialLocator(publication, saved, resumeTarget)
                    val fragment = makeEpubFragment(context, publication, initial, onToggleChrome = { showChrome = !showChrome })
                    val reader = LoadedReader.Epub(publication, fragment, positions.size.takeIf { it > 0 })
                    loaded = reader
                    applyProgress(ReadiumReaderService.fraction(fragment.currentLocator.value), fragment.currentLocator.value.locations.position, null)
                    narrationJump?.stop()
                    narrationJump = EbookNarrationJumpController(id, scope, { (loaded as? LoadedReader.Epub)?.fragment }, ReaderMetrics.narrationHighlight.toArgb())
                }
                AbsEbookFormat.pdf -> {
                    val source = PdfDocumentSource(session.file)
                    val count = source.pageCount
                    val start = saved?.let { ReadiumReaderService.pdfPageIndex(it, count) }
                        ?: EbookProgressRules.usableResumeProgression(resumeTarget)?.let { (it * count).toInt() }
                        ?: 0
                    loaded = LoadedReader.Pdf(source, PdfReaderController(count, start))
                    pdfPage = start
                    val loc = ReadiumReaderService.pdfLocator(session.file, start, count)
                    applyProgress(ReadiumReaderService.fraction(loc), loc.locations.position, null)
                }
            }
            // Lokaler Locator vorhanden, Server aber weiter: anbieten statt stumm die alte Seite zu öffnen.
            serverOffer = EbookProgressRules.serverPositionOffer(
                saved?.let(ReadiumReaderService::fraction),
                EbookProgressSync.serverFractionForReader(id),
            )
            if (!Prefs.bool(ReaderMetrics.chromeHintSeenKey)) showsChromeHint = true
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            loadError = e.message ?: "The eBook file could not be opened."
        }
    }

    // EPUB: Positionsänderungen (der erste Wert ist der Startwert, keine Nutzer-Navigation).
    LaunchedEffect(epub) {
        val reader = epub ?: return@LaunchedEffect
        reader.fragment.currentLocator.drop(1).collect { onLocationChanged(it) }
    }

    DisposableEffect(loaded) {
        val current = loaded
        onDispose {
            when (current) {
                is LoadedReader.Epub -> current.publication.close()
                is LoadedReader.Pdf -> current.source.close()
                null -> Unit
            }
        }
    }
    DisposableEffect(Unit) { onDispose { narrationJump?.stop() } }

    BackHandler { onClose() }
    ReaderSystemBars(theme = readerTheme, visible = showChrome)

    val foreground = readerTheme.foreground()
    val secondary = foreground.copy(alpha = ReaderMetrics.secondaryTextAlpha)
    val background = readerTheme.background()
    val chromeSurface = background.copy(alpha = ReaderMetrics.chromeSurfaceAlpha)

    Box(
        Modifier.fillMaxSize().background(background)
            // Overlay schluckt alle Touches (darunter liegen die Tabs).
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {},
    ) {
        // Inhalt: nur Notch/Home-Indicator freihalten — keine zusätzlichen Leser-Ränder.
        Box(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.systemBarsIgnoringVisibility.only(WindowInsetsSides.Vertical))) {
            when {
                loadError != null -> AbstandEmptyScreen(
                    title = "Could not open",
                    icon = SF.exclamationmarkTriangle,
                    description = loadError,
                )
                epub != null -> EpubNavigatorHost(epub.fragment, Modifier.fillMaxSize())
                pdf != null -> PdfPageReader(
                    source = pdf.source,
                    controller = pdf.controller,
                    continuous = continuousScroll,
                    onPageChanged = { page ->
                        if (page != pdfPage) {
                            pdfPage = page
                            onLocationChanged(ReadiumReaderService.pdfLocator(session.file, page, pdf.controller.pageCount))
                        }
                    },
                    onToggleChrome = { showChrome = !showChrome },
                )
                else -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { AbstandLoadingSpinner() }
            }
        }

        if (loaded != null && loadError == null) {
            ReaderChromeOverlay(
                visible = showChrome,
                progress = readProgress,
                top = {
                    ReaderTopChrome(session, foreground, secondary, chromeSurface, onClose)
                },
                bottom = {
                    ReaderBottomChrome(
                        format = format,
                        foreground = foreground,
                        secondary = secondary,
                        surface = chromeSurface,
                        progress = if (isScrubbing) scrubProgress else readProgress.toFloat(),
                        caption = if (isScrubbing) ReaderProgressInfo.scrubCaption(scrubProgress.toDouble(), format, positionCount) else readProgressLabel,
                        sliderEnabled = !actionInProgress,
                        onScrub = { value ->
                            if (!isScrubbing) isScrubbing = true
                            scrubProgress = value
                        },
                        onScrubFinished = {
                            val target = scrubProgress.toDouble()
                            isScrubbing = false
                            scope.launch { seekToProgression(target) }
                        },
                        fontSize = fontSize,
                        onFontSize = { delta ->
                            fontSize = (fontSize + delta).coerceIn(EpubReaderSettings.minFontSize, EpubReaderSettings.maxFontSize)
                            EpubReaderSettings.saveFontSize(fontSize)
                            applyEpubPreferences()
                        },
                        narrationJump = narrationJump,
                        continuousScroll = continuousScroll,
                        onToggleScroll = {
                            continuousScroll = !continuousScroll
                            EpubReaderSettings.saveContinuousScroll(continuousScroll)
                            applyEpubPreferences()
                        },
                        readerTheme = readerTheme,
                        onTheme = ::applyReaderTheme,
                        isFinished = (EbookProgressSync.displayFraction(id) ?: 0.0) >= 0.995,
                        actionInProgress = actionInProgress,
                        onMarkFinished = { confirmFinish = true },
                        onReset = { confirmReset = true },
                    )
                },
            )
        }

        if (showsChromeHint && serverOffer == null) {
            ReaderChromeHint(foreground, secondary, chromeSurface) {
                Prefs.setBool(ReaderMetrics.chromeHintSeenKey, true)
                showsChromeHint = false
            }
        }

        val offer = serverOffer
        AnimatedVisibility(
            visible = offer != null && !showChrome,
            enter = slideInVertically { it } + fadeIn(),
            exit = slideOutVertically { it } + fadeOut(),
            modifier = Modifier.align(Alignment.BottomCenter),
        ) {
            if (offer != null) {
                EbookServerPositionBanner(
                    offer = offer,
                    foreground = foreground,
                    secondary = secondary,
                    surface = chromeSurface,
                    onStay = { serverOffer = null },
                    onContinue = {
                        serverOffer = null
                        scope.launch { seekToProgression(offer.serverFraction) }
                    },
                )
            }
        }
    }

    if (confirmReset) {
        AbstandDialog(
            title = "Reset reading position?",
            onDismiss = { confirmReset = false },
            message = "This removes your saved position for this book. You cannot undo this.",
            confirmLabel = "Reset",
            destructive = true,
            dismissOnConfirm = false,
            onConfirm = {
                confirmReset = false
                scope.launch {
                    actionInProgress = true
                    try {
                        EbookProgressSync.reset(id, format)
                        when (val reader = loaded) {
                            is LoadedReader.Epub -> ReadiumReaderService.startLocator(reader.publication)?.let { reader.fragment.go(it) }
                            is LoadedReader.Pdf -> reader.controller.goTo(0)
                            null -> Unit
                        }
                        readProgress = 0.0
                        readProgressLabel = "0 %"
                        bookPageProgress = null
                    } finally {
                        actionInProgress = false
                    }
                }
            },
        )
    }
    if (confirmFinish) {
        AbstandDialog(
            title = "Mark as finished?",
            onDismiss = { confirmFinish = false },
            message = "Your reading progress will be saved as complete.",
            confirmLabel = "Mark as finished",
            dismissOnConfirm = false,
            onConfirm = {
                confirmFinish = false
                scope.launch {
                    actionInProgress = true
                    try {
                        EbookProgressSync.markFinished(id, format)
                    } finally {
                        actionInProgress = false
                    }
                }
            },
        )
    }
}

/** EPUB-Navigator mit Einstellungen, Rand-Taps (blättern) und Mitte-Tap (Steuerung). */
private fun makeEpubFragment(
    context: android.content.Context,
    publication: Publication,
    initial: Locator?,
    onToggleChrome: () -> Unit,
): EpubNavigatorFragment {
    val listener = object : EpubNavigatorFragment.Listener {
        override fun onExternalLinkActivated(url: AbsoluteUrl) {
            runCatching {
                context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url.toString())).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
        }
    }
    val factory = EpubNavigatorFactory(publication).createFragmentFactory(
        initialLocator = initial,
        initialPreferences = ReadiumReaderService.epubPreferences(),
        listener = listener,
    )
    val fragment = factory.instantiate(context.classLoader, EpubNavigatorFragment::class.java.name) as EpubNavigatorFragment
    // Links/rechts am Rand → zurück/weiter (im Dauerscroll ignoriert der Adapter Taps selbst).
    fragment.addInputListener(DirectionalNavigationAdapter(fragment, animatedTransition = true))
    val minEdge = ReaderMetrics.minEdgeTapWidth.value * context.resources.displayMetrics.density
    fragment.addInputListener(object : InputListener {
        override fun onTap(event: TapEvent): Boolean {
            val width = fragment.view?.width?.toFloat() ?: return false
            val edge = maxOf(minEdge, width * 0.3f)
            if (event.point.x > edge && event.point.x < width - edge) {
                onToggleChrome()
                return true
            }
            return false
        }
    })
    return fragment
}

/** Seiten im aktuellen EPUB-Abschnitt per JS (iOS: `fetchRenderedPageInfo`). */
private suspend fun renderedPageInfo(fragment: EpubNavigatorFragment): RenderedPageInfo? {
    if (!fragment.isAdded) return null
    val raw = runCatching { fragment.evaluateJavascript(PAGE_INFO_SCRIPT) }.getOrNull() ?: return null
    val json = runCatching { JSONObject(raw) }.getOrNull() ?: return null
    val total = json.optInt("total", 0)
    if (total <= 0) return null
    return RenderedPageInfo(json.optInt("current", 1).coerceIn(1, total), total)
}

/** iOS: `.statusBarHidden(!showReaderChrome)` + `.preferredColorScheme` des Reader-Themes. */
@Composable
private fun ReaderSystemBars(theme: EpubReaderTheme, visible: Boolean) {
    val view = LocalView.current
    val window = remember(view) {
        generateSequence(view.context) { (it as? android.content.ContextWrapper)?.baseContext }
            .filterIsInstance<Activity>().firstOrNull()?.window
    }
    val controller = remember(window) { window?.let { WindowCompat.getInsetsController(it, view) } }
    // Beim Schließen: Leisten zeigen und die Icon-Farben der App wiederherstellen.
    DisposableEffect(controller) {
        val c = controller ?: return@DisposableEffect onDispose {}
        val previousLight = c.isAppearanceLightStatusBars
        val previousLightNav = c.isAppearanceLightNavigationBars
        c.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        onDispose {
            c.show(WindowInsetsCompat.Type.systemBars())
            c.isAppearanceLightStatusBars = previousLight
            c.isAppearanceLightNavigationBars = previousLightNav
        }
    }
    SideEffect {
        val c = controller ?: return@SideEffect
        c.isAppearanceLightStatusBars = theme != EpubReaderTheme.dark
        c.isAppearanceLightNavigationBars = theme != EpubReaderTheme.dark
        if (visible) c.show(WindowInsetsCompat.Type.systemBars()) else c.hide(WindowInsetsCompat.Type.systemBars())
    }
}

@Composable
private fun ReaderChromeOverlay(
    visible: Boolean,
    progress: Double,
    top: @Composable () -> Unit,
    bottom: @Composable () -> Unit,
) {
    val accent = Theme.accent
    Box(Modifier.fillMaxSize()) {
        AnimatedVisibility(
            visible = visible,
            enter = slideInVertically { -it } + fadeIn(),
            exit = slideOutVertically { -it } + fadeOut(),
            modifier = Modifier.align(Alignment.TopCenter),
        ) { top() }
        AnimatedVisibility(
            visible = visible,
            enter = slideInVertically { it } + fadeIn(),
            exit = slideOutVertically { it } + fadeOut(),
            modifier = Modifier.align(Alignment.BottomCenter),
        ) { bottom() }
        if (!visible) {
            // Dezente Orientierung auch bei ausgeblendeter Steuerung.
            BoxWithConstraints(
                Modifier.align(Alignment.BottomStart).fillMaxWidth()
                    .windowInsetsPadding(WindowInsets.systemBarsIgnoringVisibility.only(WindowInsetsSides.Bottom))
                    .height(ReaderMetrics.passiveProgressBarHeight),
            ) {
                Box(
                    Modifier.width(maxWidth * progress.toFloat().coerceIn(0f, 1f)).fillMaxSize()
                        .background(accent.copy(alpha = ReaderMetrics.passiveProgressAlpha)),
                )
            }
        }
    }
}

/** Orientierung und Schließen oben; alle Leseaktionen liegen separat am unteren Rand. */
@Composable
private fun ReaderTopChrome(session: EbookReaderSession, foreground: Color, secondary: Color, surface: Color, onClose: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().background(surface)
            .windowInsetsPadding(WindowInsets.systemBarsIgnoringVisibility.only(WindowInsetsSides.Top))
            .padding(horizontal = AppTheme.Layout.screenPadding, vertical = AppTheme.Layout.withinSectionSpacing),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.rowSpacing),
    ) {
        ChromeIconButton(SF.xmarkCircleFill, "Close", foreground, onClick = onClose)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.hairlineSpacing)) {
            Text(session.title, style = AppType.bodyMedium.semibold, color = foreground, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (session.author.isNotEmpty()) {
                Text(session.author, style = AppType.bodySmall, color = secondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

/** Primäre Lesesteuerung bewusst am unteren Bildschirmrand für einhändige Bedienung. */
@Composable
private fun ReaderBottomChrome(
    format: AbsEbookFormat,
    foreground: Color,
    secondary: Color,
    surface: Color,
    progress: Float,
    caption: String,
    sliderEnabled: Boolean,
    onScrub: (Float) -> Unit,
    onScrubFinished: () -> Unit,
    fontSize: Double,
    onFontSize: (Double) -> Unit,
    narrationJump: EbookNarrationJumpController?,
    continuousScroll: Boolean,
    onToggleScroll: () -> Unit,
    readerTheme: EpubReaderTheme,
    onTheme: (EpubReaderTheme) -> Unit,
    isFinished: Boolean,
    actionInProgress: Boolean,
    onMarkFinished: () -> Unit,
    onReset: () -> Unit,
) {
    val accent = Theme.accent
    Column(
        Modifier.fillMaxWidth().background(surface)
            .windowInsetsPadding(WindowInsets.systemBarsIgnoringVisibility.only(WindowInsetsSides.Bottom))
            .padding(horizontal = AppTheme.Layout.screenPadding, vertical = AppTheme.Layout.withinSectionSpacing),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.tightSpacing)) {
            Slider(
                value = progress.coerceIn(0f, 1f),
                onValueChange = onScrub,
                onValueChangeFinished = onScrubFinished,
                enabled = sliderEnabled,
                colors = SliderDefaults.colors(thumbColor = accent, activeTrackColor = accent, inactiveTrackColor = secondary.copy(alpha = 0.3f)),
                modifier = Modifier.semantics { contentDescription = "Reading progress" },
            )
            Text(caption, style = AppType.bodySmall, color = secondary, maxLines = 1)
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.rowSpacing)) {
            if (format == AbsEbookFormat.epub) {
                Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.stackSpacing)) {
                    ChromeIconButton(
                        SF.textformatSizeSmaller, "Decrease font size", foreground, AppTheme.Layout.compactIconButtonSize,
                        enabled = fontSize > EpubReaderSettings.minFontSize,
                    ) { onFontSize(-EpubReaderSettings.fontSizeStep) }
                    ChromeIconButton(
                        SF.textformatSizeLarger, "Increase font size", foreground, AppTheme.Layout.compactIconButtonSize,
                        enabled = fontSize < EpubReaderSettings.maxFontSize,
                    ) { onFontSize(EpubReaderSettings.fontSizeStep) }
                }
            }
            Spacer(Modifier.weight(1f))
            if (narrationJump != null) NarrationJumpButton(narrationJump, foreground)
            ChromeIconButton(
                if (continuousScroll) SF.scroll else SF.bookPages,
                if (continuousScroll) "Continuous scroll, on" else "Continuous scroll, off",
                foreground,
            ) { onToggleScroll() }
            AbstandMenuBox(anchor = { open -> ChromeIconButton(readerTheme.icon, "Reader theme, ${readerTheme.displayName}", foreground, onClick = open) }) {
                picker(EpubReaderTheme.entries, readerTheme, { it.displayName }, onTheme, icon = { it.icon })
            }
            AbstandMenuBox(anchor = { open -> ChromeIconButton(SF.ellipsisCircle, "Reader options", foreground, onClick = open) }) {
                item(
                    if (isFinished) "Finished reading" else "Mark as finished", onMarkFinished,
                    icon = if (isFinished) SF.checkmarkCircleFill else SF.checkmarkCircle,
                    enabled = !actionInProgress && !isFinished,
                )
                item("Reset position", onReset, icon = SF.arrowCounterclockwise, destructive = true, enabled = !actionInProgress)
            }
        }
    }
}

@Composable
private fun ChromeIconButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    description: String,
    tint: Color,
    size: androidx.compose.ui.unit.Dp = AppTheme.Layout.iconButtonSize,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    AbstandIconButton(icon, description, onClick = onClick, enabled = enabled, size = size, tint = tint)
}

/**
 * iOS: `EbookNarrationJumpButton` — springt zur Seite der Hörposition und markiert die letzten Wörter;
 * nur sichtbar, wenn genau dieses Hörbuch im Player geladen ist.
 */
@Composable
private fun NarrationJumpButton(controller: EbookNarrationJumpController, foreground: Color) {
    val player = PlaybackController.shared(AppModel.shared.appContext)
    val activeBook by player.activeBook.collectAsState()
    val activeEpisode by player.activePlaybackEpisodeId.collectAsState()
    if (!controller.isAvailable(activeBook?.id, activeEpisode)) return
    val busy by controller.isBusy.collectAsState()
    val notice by controller.notice.collectAsState()
    if (busy) {
        Box(Modifier.size(AppTheme.Layout.iconButtonSize), contentAlignment = Alignment.Center) {
            AbstandInlineSpinner(color = foreground, size = AppTheme.Layout.blockSpacing, strokeWidth = AppTheme.Layout.boldStrokeWidth)
        }
    } else {
        ChromeIconButton(SF.headphones, "Go to audiobook position", foreground) { controller.jumpToNarration() }
    }
    notice?.let { text ->
        AbstandAlert("Can't jump to the audiobook position", onDismiss = controller::dismissNotice, message = text)
    }
}

@Composable
private fun ReaderChromeHint(foreground: Color, secondary: Color, surface: Color, onDismiss: () -> Unit) {
    Box(
        Modifier.fillMaxSize().padding(horizontal = AppTheme.Layout.blockSpacing)
            .windowInsetsPadding(WindowInsets.systemBarsIgnoringVisibility.only(WindowInsetsSides.Bottom)),
        contentAlignment = Alignment.BottomCenter,
    ) {
        Column(
            Modifier.padding(bottom = AppTheme.Layout.minTapTarget).widthIn(max = ReaderMetrics.chromeHintMaxWidth)
                .background(surface, RoundedCornerShape(AppTheme.Layout.readerChromeCornerRadius))
                .padding(AppTheme.Layout.overlayPadding),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing),
        ) {
            Icon(SF.handTap, contentDescription = null, tint = Theme.accent)
            Text("Reading controls", style = AppType.titleMedium, color = foreground)
            Text(
                "Tap the middle of the page to show reading controls and progress.",
                style = AppType.bodyMedium, color = secondary, textAlign = TextAlign.Center,
            )
            AbstandProminentButton(text = "Got it", onClick = onDismiss)
        }
    }
}

/**
 * iOS: `EbookServerPositionBanner` — „Auf einem anderen Gerät weitergelesen": zur Serverposition
 * springen oder hier bleiben. Der Server kennt nur einen Prozentwert, der Sprung ist ungefähr.
 */
@Composable
private fun EbookServerPositionBanner(
    offer: ServerPositionOffer,
    foreground: Color,
    secondary: Color,
    surface: Color,
    onStay: () -> Unit,
    onContinue: () -> Unit,
) {
    fun percent(f: Double) = "${ReaderProgressInfo.percent(f)} %"
    Column(
        Modifier.fillMaxWidth()
            .windowInsetsPadding(WindowInsets.systemBarsIgnoringVisibility.only(WindowInsetsSides.Bottom))
            .padding(horizontal = AppTheme.Layout.screenPadding)
            .padding(bottom = AppTheme.Layout.blockSpacing)
            .background(surface, RoundedCornerShape(AppTheme.Layout.continueHeroCardCornerRadius))
            .padding(AppTheme.Layout.cardPadding),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.rowSpacing)) {
            Icon(
                SF.arrowTriangle2Circlepath, contentDescription = null, tint = Theme.accent,
                modifier = Modifier.padding(top = AppTheme.Layout.hairlineSpacing).size(AppTheme.Layout.compactIconColumnWidth),
            )
            Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.tightSpacing)) {
                Text("You've read further elsewhere", style = AppType.bodyMedium.semibold, color = foreground)
                Text(
                    "Your synced position is at ${percent(offer.serverFraction)}, this device is at ${percent(offer.localFraction)}.",
                    style = AppType.bodySmall, color = secondary,
                )
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            AbstandTextButton("Stay here", onStay, Modifier.heightIn(min = AppTheme.Layout.minTapTarget), emphasized = true, compact = true, color = foreground)
            Spacer(Modifier.weight(1f))
            AbstandProminentButton(text = "Go to ${percent(offer.serverFraction)}", onClick = onContinue)
        }
    }
}
