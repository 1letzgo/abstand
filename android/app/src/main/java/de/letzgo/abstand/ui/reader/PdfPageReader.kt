package de.letzgo.abstand.ui.reader

import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import androidx.compose.foundation.Image
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import de.letzgo.abstand.ui.AppTheme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.Closeable
import java.io.File

/**
 * PDF-Quelle über `android.graphics.pdf.PdfRenderer` (iOS: Readium `PDFNavigatorViewController`).
 * Der Renderer ist nicht threadsicher — alle Zugriffe laufen seriell.
 */
class PdfDocumentSource(file: File) : Closeable {
    private val descriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    private val renderer = PdfRenderer(descriptor)
    private val lock = Mutex()

    @OptIn(ExperimentalCoroutinesApi::class)
    private val dispatcher = Dispatchers.IO.limitedParallelism(1)
    private var closed = false

    val pageCount: Int = renderer.pageCount

    /** Seite in Breite [widthPx] rendern (weißer Grund wie gedrucktes Papier). */
    suspend fun render(index: Int, widthPx: Int): Bitmap? = withContext(dispatcher) {
        lock.withLock {
            if (closed || index !in 0 until pageCount || widthPx <= 0) return@withLock null
            runCatching {
                renderer.openPage(index).use { page ->
                    val height = (widthPx.toLong() * page.height / maxOf(1, page.width)).toInt().coerceAtLeast(1)
                    val bitmap = Bitmap.createBitmap(widthPx, height, Bitmap.Config.ARGB_8888)
                    bitmap.eraseColor(android.graphics.Color.WHITE)
                    page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                    bitmap
                }
            }.getOrNull()
        }
    }

    override fun close() {
        // Nicht während eines Renderns schließen.
        kotlinx.coroutines.runBlocking {
            lock.withLock {
                if (closed) return@withLock
                closed = true
                runCatching { renderer.close() }
                runCatching { descriptor.close() }
            }
        }
    }
}

/** Steuerung des PDF-Readers: aktuelle Seite und Sprünge (Fortschritts-Slider, Reset, Server-Position). */
class PdfReaderController(val pageCount: Int, initialPage: Int) {
    var currentPage: Int = initialPage.coerceIn(0, maxOf(0, pageCount - 1))
        internal set
    private val _requests = MutableSharedFlow<Int>(extraBufferCapacity = 4)
    internal val requests: SharedFlow<Int> = _requests.asSharedFlow()

    fun goTo(page: Int) {
        _requests.tryEmit(page.coerceIn(0, maxOf(0, pageCount - 1)))
    }
}

/** Typisches Seitenverhältnis (A4), bis die Seite gerendert ist. */
private const val PLACEHOLDER_PAGE_ASPECT = 0.707f

/** Rand-Taps: Anteil der Breite (mindestens [ReaderMetrics.minEdgeTapWidth]) wie iOS. */
private const val EDGE_FRACTION = 0.3f

@Composable
internal fun PdfPageReader(
    source: PdfDocumentSource,
    controller: PdfReaderController,
    continuous: Boolean,
    onPageChanged: (Int) -> Unit,
    onToggleChrome: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val pageChanged by rememberUpdatedState(onPageChanged)
    val toggle by rememberUpdatedState(onToggleChrome)
    val scope = rememberCoroutineScope()
    val minEdgePx = with(LocalDensity.current) { ReaderMetrics.minEdgeTapWidth.toPx() }
    if (continuous) {
        val listState = rememberLazyListState(controller.currentPage)
        LaunchedEffect(listState) {
            snapshotFlow { listState.firstVisibleItemIndex }.distinctUntilChanged().collect {
                controller.currentPage = it
                pageChanged(it)
            }
        }
        LaunchedEffect(controller) { controller.requests.collect { listState.scrollToItem(it) } }
        LazyColumn(
            state = listState,
            modifier = modifier.fillMaxSize().pointerInput(Unit) { detectTapGestures { toggle() } },
            verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.stackSpacing),
        ) {
            items(controller.pageCount) { index -> PdfPage(source, index, Modifier.fillMaxWidth()) }
        }
    } else {
        val pagerState = rememberPagerState(controller.currentPage) { controller.pageCount }
        LaunchedEffect(pagerState) {
            snapshotFlow { pagerState.currentPage }.distinctUntilChanged().collect {
                controller.currentPage = it
                pageChanged(it)
            }
        }
        LaunchedEffect(controller) { controller.requests.collect { pagerState.scrollToPage(it) } }
        HorizontalPager(
            state = pagerState,
            modifier = modifier.fillMaxSize().pointerInput(Unit) {
                detectTapGestures { offset ->
                    // Links/rechts am Rand → Seite zurück/vor; Mitte → Steuerung (iOS-Verhalten).
                    val edge = maxOf(minEdgePx, size.width * EDGE_FRACTION)
                    when {
                        offset.x < edge -> scope.launch { pagerState.animateScrollToPage((pagerState.currentPage - 1).coerceAtLeast(0)) }
                        offset.x > size.width - edge -> scope.launch {
                            pagerState.animateScrollToPage((pagerState.currentPage + 1).coerceAtMost(controller.pageCount - 1))
                        }
                        else -> toggle()
                    }
                }
            },
        ) { index ->
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { PdfPage(source, index, Modifier.fillMaxWidth()) }
        }
    }
}

@Composable
private fun PdfPage(source: PdfDocumentSource, index: Int, modifier: Modifier) {
    BoxWithConstraints(modifier) {
        val widthPx = constraints.maxWidth
        val bitmap by produceState<Bitmap?>(null, source, index, widthPx) { value = source.render(index, widthPx) }
        val bmp = bitmap
        if (bmp != null) {
            Image(
                bitmap = bmp.asImageBitmap(),
                contentDescription = null,
                contentScale = ContentScale.FillWidth,
                modifier = Modifier.fillMaxWidth().aspectRatio(bmp.width.toFloat() / bmp.height),
            )
        } else {
            Box(Modifier.fillMaxWidth().aspectRatio(PLACEHOLDER_PAGE_ASPECT))
        }
    }
}
