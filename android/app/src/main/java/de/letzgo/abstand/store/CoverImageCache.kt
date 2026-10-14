package de.letzgo.abstand.store

import android.content.Context
import android.graphics.Bitmap
import coil3.ImageLoader
import coil3.SingletonImageLoader
import coil3.decode.DataSource
import coil3.decode.ImageSource
import coil3.fetch.FetchResult
import coil3.fetch.Fetcher
import coil3.fetch.SourceFetchResult
import coil3.key.Keyer
import coil3.request.CachePolicy
import coil3.request.ImageRequest
import coil3.request.Options
import coil3.request.SuccessResult
import coil3.request.allowHardware
import coil3.toBitmap
import de.letzgo.abstand.data.CoverImageTier
import de.letzgo.abstand.data.Net
import de.letzgo.abstand.data.awaitResult
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.withContext
import okhttp3.Request
import okio.Buffer
import okio.FileSystem
import java.io.File
import java.util.concurrent.ConcurrentHashMap

/** iOS: `CoverImageTier.cacheScopeSuffix` — Hero getrennt vom Thumbnail cachen. */
val CoverImageTier.cacheScopeSuffix: String?
    get() = when (this) {
        CoverImageTier.thumbnail -> null
        CoverImageTier.hero -> "cover-hero"
    }

/**
 * Coil-Datenmodell eines Covers (iOS: Parameter von `CoverImageView`/`CoverImageLoader.image`).
 * [key] = vollständiger Cache-Key (Scope inkl. Revision, z. B. `id#cover-hero#r42`).
 */
data class CoverRequest(
    val key: String,
    val url: String,
    val account: File?,
    /** `false` für externe URLs (z. B. Apple-Podcasts-Verzeichnis) — dort nie Server-Header. */
    val requiresAuthorization: Boolean = true,
)

/**
 * iOS: `CoverImageCache` — Cover-Dateien unter `<account>/covers/`, Dateiname = SHA-256(Key) + `.img`.
 * Speicher-Cache übernimmt Coil (Memory-Key = Cache-Key, siehe [CoverRequestKeyer]); Coils eigener
 * Disk-Cache ist für Cover aus, damit sie pro Account und offline verfügbar bleiben.
 */
object CoverImageCache {
    private const val SUBDIR = "covers"

    private fun coversDir(account: File): File = File(account, SUBDIR).also { it.mkdirs() }

    fun fileFor(account: File, itemId: String): File = File(coversDir(account), coverFileName(itemId))

    /** Reiner Dateiname (testbar). */
    fun coverFileName(itemId: String): String = sha256Hex(itemId) + ".img"

    /** Storage-Key für Memory-/Disk-Cache inkl. Revision. */
    fun cacheKey(scopeId: String, revision: Int): String = if (revision == 0) scopeId else "$scopeId#r$revision"

    /** Scope-ID eines Item-Covers je Tier (iOS: `cacheScopeId ?? itemId` bzw. `id#cover-hero`). */
    fun scopeId(itemId: String, tier: CoverImageTier): String = tier.cacheScopeSuffix?.let { "$itemId#$it" } ?: itemId

    fun loadFromDisk(account: File, itemId: String): ByteArray? {
        val f = fileFor(account, itemId)
        if (!f.exists()) return null
        // Zugriffszeit nachziehen — Grundlage für die LRU-Bereinigung (iOS: `contentAccessDateKey`).
        f.setLastModified(System.currentTimeMillis())
        return runCatching { f.readBytes() }.getOrNull()
    }

    fun saveToDisk(account: File, itemId: String, data: ByteArray) {
        val f = fileFor(account, itemId)
        val tmp = File(f.parentFile, ".${f.name}.tmp")
        tmp.writeBytes(data)
        if (!tmp.renameTo(f)) {
            f.delete()
            tmp.renameTo(f)
        }
    }

    /**
     * Hero-/Tint-Bild holen: Memory/Disk, dann Netz — über denselben Loader wie [de.letzgo.abstand.ui.components.CoverImage],
     * damit Detailansicht und Tint-Extraktion sich einen Ladevorgang teilen.
     */
    suspend fun loadHeroImage(context: Context, request: CoverRequest): Bitmap? {
        val loader = SingletonImageLoader.get(context)
        val result = loader.execute(imageRequest(context, request).newBuilder().allowHardware(false).build())
        return (result as? SuccessResult)?.image?.toBitmap()
    }

    /** Einheitlicher Coil-Request für ein Cover (Memory-Key = Cache-Key, kein Coil-Disk-Cache). */
    fun imageRequest(context: Context, request: CoverRequest): ImageRequest =
        ImageRequest.Builder(context)
            .data(request)
            .memoryCacheKey(request.key)
            .diskCachePolicy(CachePolicy.DISABLED)
            .build()

    /** In-Memory leeren (Account-Wechsel); Disk-Cache pro Server bleibt erhalten. */
    fun evictMemory(context: Context) {
        SingletonImageLoader.get(context).memoryCache?.clear()
        CoverImageLoader.resetMissingCache()
    }

    /** Entfernt alle Cover-Dateien dieses Kontos und leert den In-Memory-Cache. */
    fun clearAll(context: Context, account: File) {
        evictMemory(context)
        val dir = File(account, SUBDIR)
        dir.deleteRecursively()
        dir.mkdirs()
    }

    fun totalByteCount(account: File): Long = File(account, SUBDIR).listFiles()?.sumOf { it.length() } ?: 0L

    /**
     * Grobe LRU/TTL-Bereinigung: alles über [maxAgeDays] seit dem letzten Zugriff fliegt raus, danach
     * älteste Dateien, bis [maxTotalBytes] unterschritten ist. Für einen Hintergrund-Sweep, kein Live-Pfad.
     */
    fun pruneStaleEntries(
        account: File,
        maxAgeDays: Int = 45,
        maxTotalBytes: Long = 200L * 1024 * 1024,
        now: Long = System.currentTimeMillis(),
    ) {
        val files = coversDir(account).listFiles() ?: return
        val cutoff = now - maxAgeDays * 86_400_000L
        val survivors = ArrayList<File>(files.size)
        for (f in files) {
            if (f.lastModified() < cutoff) f.delete() else survivors.add(f)
        }
        var total = survivors.sumOf { it.length() }
        if (total <= maxTotalBytes) return
        for (f in survivors.sortedBy { it.lastModified() }) {
            if (total <= maxTotalBytes) break
            val size = f.length()
            if (f.delete()) total -= size
        }
    }
}

/**
 * iOS: `CoverImageLoader` — einziger Weg, ein Cover zu laden: Disk → Netzwerk, pro Cache-Key
 * **einmal** (parallele Interessenten teilen sich den Ladevorgang; ein abbrechender Aufrufer beendet
 * ihn nicht, damit ein weggescrolltes Cover trotzdem im Cache landet). 404/410 werden 10 min als
 * „kein Cover“ gemerkt.
 */
object CoverImageLoader {
    private const val MISSING_RETRY_DELAY_MS = 600_000L

    enum class Outcome { Image, Missing, Failed }

    class Loaded(val outcome: Outcome, val bytes: ByteArray?, val fromDisk: Boolean)

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val inFlight = ConcurrentHashMap<String, Deferred<Loaded>>()
    private val missingUntil = ConcurrentHashMap<String, Long>()

    /** Merker zurücksetzen (Account-Wechsel, „Clear cache“, Pull-to-Refresh). */
    fun resetMissingCache() = missingUntil.clear()

    /** Bytes für [request] besorgen (`null` = kein Bild / Fehler). */
    suspend fun load(request: CoverRequest): Loaded {
        val key = request.key
        missingUntil[key]?.let { until ->
            if (until > System.currentTimeMillis()) return Loaded(Outcome.Missing, null, false)
            missingUntil.remove(key)
        }
        val task = inFlight.computeIfAbsent(key) { scope.async { fetch(request) } }
        val result = try {
            task.await()
        } finally {
            if (task.isCompleted) inFlight.remove(key, task)
        }
        if (result.outcome == Outcome.Missing) missingUntil[key] = System.currentTimeMillis() + MISSING_RETRY_DELAY_MS
        return result
    }

    private suspend fun fetch(request: CoverRequest): Loaded {
        try {
            request.account?.let { account ->
                CoverImageCache.loadFromDisk(account, request.key)?.let { return Loaded(Outcome.Image, it, true) }
            }
            val http = Request.Builder().url(request.url).build()
            val res = Net.imageClient.awaitResult(http)
            if (res.code == 404 || res.code == 410) return Loaded(Outcome.Missing, null, false)
            if (!res.isSuccess || res.body.isEmpty()) return Loaded(Outcome.Failed, null, false)
            request.account?.let { account -> runCatching { CoverImageCache.saveToDisk(account, request.key, res.body) } }
            return Loaded(Outcome.Image, res.body, false)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            return Loaded(Outcome.Failed, null, false)
        }
    }
}

/** Coil-Fetcher für [CoverRequest] — delegiert an [CoverImageLoader]. */
class CoverRequestFetcher(private val data: CoverRequest) : Fetcher {
    override suspend fun fetch(): FetchResult {
        val loaded = withContext(Dispatchers.IO) { CoverImageLoader.load(data) }
        val bytes = loaded.bytes ?: throw IllegalStateException(
            if (loaded.outcome == CoverImageLoader.Outcome.Missing) "No cover for ${data.key}" else "Cover load failed for ${data.key}",
        )
        return SourceFetchResult(
            source = ImageSource(Buffer().write(bytes), FileSystem.SYSTEM),
            mimeType = null,
            dataSource = if (loaded.fromDisk) DataSource.DISK else DataSource.NETWORK,
        )
    }

    class Factory : Fetcher.Factory<CoverRequest> {
        override fun create(data: CoverRequest, options: Options, imageLoader: ImageLoader): Fetcher = CoverRequestFetcher(data)
    }
}

/** Memory-Key eines [CoverRequest] = sein Cache-Key (wie iOS `CoverImageCache.memory`). */
class CoverRequestKeyer : Keyer<CoverRequest> {
    override fun key(data: CoverRequest, options: Options): String = data.key
}
