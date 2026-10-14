package de.letzgo.abstand.logic.speech

import android.content.Context
import de.letzgo.abstand.data.Net
import de.letzgo.abstand.data.awaitResponse
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import okhttp3.Request
import org.vosk.Model
import java.io.File
import java.io.InputStream
import java.util.zip.ZipInputStream
import kotlin.coroutines.coroutineContext

/**
 * Download/Installation und Laden der Vosk-Modelle (übernommen aus stashy `SpeechModelStore`).
 * Geladene Modelle bleiben im Speicher (Laden dauert Sekunden); Teleprompter und Vorproduktion
 * können parallel dasselbe Modell nutzen — ein Modell wird erst geschlossen, wenn niemand es mehr
 * benutzt und ein anderes geladen wurde (oder beim Löschen).
 */
object SpeechModelStore {
    private val mutex = Mutex()

    /** Geladene Modelle je Modellname und ihre aktiven Nutzer ([withModel]). */
    private val loaded = LinkedHashMap<String, Model>()
    private val users = HashMap<String, Int>()

    private fun root(context: Context) = File(context.filesDir, "speech-models")

    /** Verzeichnis des entpackten Modells (Argument für `org.vosk.Model(path)`). */
    fun modelDirectory(context: Context, entry: SpeechModelCatalog.Entry) = File(root(context), entry.modelName)

    fun isInstalled(context: Context, entry: SpeechModelCatalog.Entry): Boolean =
        File(modelDirectory(context, entry), ".complete").exists()

    /** Bytes aller geladenen Sprachmodelle (Einstellungen). */
    fun installedBytes(context: Context): Long = root(context).walkBottomUp().filter { it.isFile }.sumOf { it.length() }

    /** Alle Modelle löschen (Einstellungen). Geladene, unbenutzte Modelle werden vorher geschlossen. */
    suspend fun deleteAll(context: Context) = withContext(Dispatchers.IO) {
        mutex.withLock {
            closeUnused(keep = null)
            root(context).listFiles()?.forEach { dir ->
                // Ein gerade benutztes Modell bleibt liegen, bis seine Erkennung endet.
                if ((users[dir.name] ?: 0) == 0) dir.deleteRecursively()
            }
        }
    }

    /**
     * Lädt (und behält) ein installiertes Modell — Sekunden, deshalb off-main. Andere, gerade nicht
     * benutzte Modelle werden dabei geschlossen (Speicher). Wirft, wenn das Modell fehlt.
     */
    suspend fun load(context: Context, entry: SpeechModelCatalog.Entry): Model = withContext(Dispatchers.IO) {
        mutex.withLock { loadLocked(context, entry) }
    }

    /** [block] mit geladenem Modell; währenddessen wird es nicht geschlossen. */
    suspend fun <T> withModel(context: Context, entry: SpeechModelCatalog.Entry, block: suspend (Model) -> T): T {
        val model = withContext(Dispatchers.IO) {
            mutex.withLock {
                loadLocked(context, entry).also { users[entry.modelName] = (users[entry.modelName] ?: 0) + 1 }
            }
        }
        try {
            return block(model)
        } finally {
            withContext(kotlinx.coroutines.NonCancellable) {
                mutex.withLock { users[entry.modelName] = maxOf(0, (users[entry.modelName] ?: 1) - 1) }
            }
        }
    }

    private fun loadLocked(context: Context, entry: SpeechModelCatalog.Entry): Model {
        loaded[entry.modelName]?.let { return it }
        if (!isInstalled(context, entry)) throw IllegalStateException("Speech model is not downloaded")
        closeUnused(keep = entry.modelName)
        val model = Model(modelDirectory(context, entry).absolutePath)
        loaded[entry.modelName] = model
        return model
    }

    private fun closeUnused(keep: String?) {
        val it = loaded.entries.iterator()
        while (it.hasNext()) {
            val (name, model) = it.next()
            if (name == keep || (users[name] ?: 0) > 0) continue
            runCatching { model.close() }
            it.remove()
        }
    }

    /**
     * Lädt und entpackt [entry] (Zip mit einem Ordner auf oberster Ebene). [progress] bekommt 0…1.
     * Abbrechbar; ein halber Download hinterlässt nichts.
     */
    suspend fun download(context: Context, entry: SpeechModelCatalog.Entry, progress: (Double) -> Unit) = withContext(Dispatchers.IO) {
        mutex.withLock {
            if (isInstalled(context, entry)) return@withLock
            val target = modelDirectory(context, entry)
            val staging = File(root(context), entry.modelName + ".partial")
            staging.deleteRecursively(); staging.mkdirs()
            try {
                Net.client.awaitResponse(Request.Builder().url(entry.url).build()).use { response ->
                    if (!response.isSuccessful) throw IllegalStateException("Speech model download failed (HTTP ${response.code})")
                    val body = response.body
                    val total = body.contentLength().takeIf { it > 0 } ?: (entry.megabytes * 1_000_000L)
                    val counting = CountingStream(body.byteStream()) { read -> progress((read.toDouble() / total).coerceIn(0.0, 0.99)) }
                    ZipInputStream(counting.buffered()).use { zip ->
                        while (true) {
                            coroutineContext.ensureActive()
                            val e = zip.nextEntry ?: break
                            // Obersten Zip-Ordner abschneiden; Pfad-Traversal verweigern.
                            val rel = e.name.substringAfter('/', "").takeIf { it.isNotEmpty() } ?: continue
                            val out = File(staging, rel)
                            if (!out.canonicalPath.startsWith(staging.canonicalPath)) continue
                            if (e.isDirectory) { out.mkdirs(); continue }
                            out.parentFile?.mkdirs()
                            out.outputStream().use { zip.copyTo(it) }
                        }
                    }
                }
                File(staging, ".complete").writeText(entry.modelName)
                target.deleteRecursively()
                if (!staging.renameTo(target)) throw IllegalStateException("Could not install speech model")
                progress(1.0)
            } finally {
                staging.deleteRecursively()
            }
        }
    }

    private class CountingStream(private val inner: InputStream, private val onRead: (Long) -> Unit) : InputStream() {
        private var count = 0L
        private var lastReport = 0L
        private fun note(n: Int) {
            if (n > 0) {
                count += n
                if (count - lastReport > 256_000) { lastReport = count; onRead(count) }
            }
        }
        override fun read(): Int = inner.read().also { if (it >= 0) note(1) }
        override fun read(b: ByteArray, off: Int, len: Int): Int = inner.read(b, off, len).also { note(it) }
        override fun close() = inner.close()
    }
}
