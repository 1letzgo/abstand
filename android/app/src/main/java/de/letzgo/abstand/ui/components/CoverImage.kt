package de.letzgo.abstand.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import de.letzgo.abstand.data.AbsApiClient
import de.letzgo.abstand.data.CoverImageTier
import de.letzgo.abstand.store.CoverImageCache
import de.letzgo.abstand.store.CoverRequest
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import java.io.File

/**
 * Cover-Kontext der aktiven Session (iOS: `model.serverURL`, `model.coverImageCacheAccountDirectory()`,
 * `model.coverImageCacheRevision` als View-Parameter). Von `AppRoot` aus dem Session-Store gesetzt,
 * damit Zellen nicht an den ganzen Store gekoppelt werden (iOS-Regel `appearanceThemeRevision`).
 */
data class CoverEnvironment(
    /** Normalisierte Server-URL (`null` vor Login). */
    val serverBaseURL: String?,
    /** `<account>`-Verzeichnis für den Disk-Cache; `null` = kein Persistenz-Cache. */
    val accountDir: File?,
    /** iOS: `coverImageCacheRevision` — Standard-Revision für alle Cover. */
    val revision: Int = 0,
)

val LocalCoverEnvironment = staticCompositionLocalOf { CoverEnvironment(serverBaseURL = null, accountDir = null) }

/** iOS: `CoverImageContentMode`. */
enum class CoverImageContentMode {
    /** Füllt den Rahmen, Beschnitt aus der Mitte (Karten, Mini-Player). */
    Fill,
    /** Komplettes Cover sichtbar, Briefkasten nach Bedarf. */
    Fit,
}

/**
 * iOS: `CoverImageView` für ein Library-Item — URL aus Server + [tier] (`/api/items/:id/cover?width=…`),
 * Cache-Scope `itemId` bzw. `itemId#cover-hero`. Lädt über [CoverImageCache]/[de.letzgo.abstand.store.CoverImageLoader]
 * (Memory → Account-Disk → Netz, ein Ladevorgang pro Key); offline aus dem Disk-Cache.
 */
@Composable
fun CoverImage(
    itemId: String,
    modifier: Modifier = Modifier,
    tier: CoverImageTier = CoverImageTier.thumbnail,
    contentMode: CoverImageContentMode = CoverImageContentMode.Fill,
    cacheRevision: Int = LocalCoverEnvironment.current.revision,
    contentDescription: String? = null,
) {
    val env = LocalCoverEnvironment.current
    val url = env.serverBaseURL?.let { AbsApiClient.itemCoverURL(it, itemId, tier) }
    CoverImage(
        url = url,
        cacheScopeId = CoverImageCache.scopeId(itemId, tier),
        modifier = modifier,
        cacheRevision = cacheRevision,
        contentMode = contentMode,
        contentDescription = contentDescription,
    )
}

/**
 * iOS: `CoverImageView(url:token:itemId:cacheAccount:cacheScopeId:cacheRevision:requiresAuthorization:contentMode:)`
 * — freie URL (z. B. Feed-/Verzeichnis-Cover mit [requiresAuthorization] = `false`).
 */
@Composable
fun CoverImage(
    url: String?,
    cacheScopeId: String,
    modifier: Modifier = Modifier,
    cacheRevision: Int = 0,
    requiresAuthorization: Boolean = true,
    contentMode: CoverImageContentMode = CoverImageContentMode.Fill,
    contentDescription: String? = null,
) {
    val env = LocalCoverEnvironment.current
    val context = LocalContext.current
    val key = CoverImageCache.cacheKey(cacheScopeId, cacheRevision)
    // Bild gehört zu genau diesem Key: wiederverwendete Zelle mit anderem Item zeigt kein fremdes Cover.
    var loaded by remember(key, url) { mutableStateOf(false) }
    val request = remember(key, url, env.accountDir, requiresAuthorization) {
        if (url.isNullOrEmpty() || cacheScopeId.isEmpty()) null
        else CoverImageCache.imageRequest(context, CoverRequest(key, url, env.accountDir, requiresAuthorization))
    }
    val fill = contentMode == CoverImageContentMode.Fill
    Box(
        modifier
            .clipToBounds()
            .then(if (fill) Modifier.fillMaxSize() else Modifier.sizeIn(minWidth = AppTheme.Layout.minTapTarget, minHeight = AppTheme.Layout.minTapTarget)),
        contentAlignment = Alignment.Center,
    ) {
        if (!loaded) CoverPlaceholder(Modifier.matchParentSize())
        if (request != null) {
            AsyncImage(
                model = request,
                contentDescription = contentDescription,
                contentScale = if (fill) ContentScale.Crop else ContentScale.Fit,
                onSuccess = { loaded = true },
                onError = { loaded = false },
                modifier = if (fill) Modifier.matchParentSize() else Modifier.fillMaxSize(),
            )
        }
    }
}

/** Platzhalter ohne Bild: Kartenfläche + geschlossenes Buch (iOS: `book.closed.fill`, `title3`). */
@Composable
private fun CoverPlaceholder(modifier: Modifier) {
    val palette = Theme.palette
    Box(modifier.background(palette.card), contentAlignment = Alignment.Center) {
        Icon(SF.bookClosedFill, contentDescription = null, tint = palette.textSecondary, modifier = Modifier.sizeIn(maxWidth = PlaceholderIconSize, maxHeight = PlaceholderIconSize))
    }
}

/** iOS: `.font(.title3)` des Platzhalter-Symbols (~20 pt). */
private val PlaceholderIconSize = 24.dp

/**
 * iOS: `SquareCoverImageView` — 1:1-Cover, Bild zentriert (`.fit`), Letterboxing mit [tint].
 * iOS leitet den Tint aus dem Cover ab (`CoverDerivedTintLoader`, Teil von `ContinueHeroTintCache`);
 * bis dieser portiert ist, reicht der Aufrufer ihn herein (Standard: Kartenfarbe wie iOS vor dem Laden).
 */
@Composable
fun SquareCoverImage(
    itemId: String,
    modifier: Modifier = Modifier,
    tier: CoverImageTier = CoverImageTier.thumbnail,
    tint: Color = Theme.palette.card,
    cacheRevision: Int = LocalCoverEnvironment.current.revision,
) {
    Box(modifier.background(tint), contentAlignment = Alignment.Center) {
        CoverImage(
            itemId = itemId,
            modifier = Modifier.fillMaxSize(),
            tier = tier,
            contentMode = CoverImageContentMode.Fit,
            cacheRevision = cacheRevision,
        )
    }
}
