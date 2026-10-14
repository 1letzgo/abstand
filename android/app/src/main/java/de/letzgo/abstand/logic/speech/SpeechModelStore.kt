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
import java.io.File
import java.io.InputStream
import java.util.zip.ZipInputStream
import kotlin.coroutines.coroutineContext

/**
 * Download/Installation der Vosk-Modelle (übernommen aus stashy `SpeechModelStore`). Das Laden des
 * Modells (`org.vosk.Model`) gehört zum Transkript-Producer und kommt mit der Vosk-Abhängigkeit; hier
 * liefert [modelDirectory] den Pfad dafür.
 */
object SpeechModelStore {
    private val mutex = Mutex()

    private fun root(context: Context) = File(context.filesDir, "speech-models")

    /** Verzeichnis des entpackten Modells (Argument für `org.vosk.Model(path)`). */
    fun modelDirectory(context: Context, entry: SpeechModelCatalog.Entry) = File(root(context), entry.modelName)

    fun isInstalled(context: Context, entry: SpeechModelCatalog.Entry): Boolean =
        File(modelDirectory(context, entry), ".complete").exists()

    /** Bytes aller geladenen Sprachmodelle (Einstellungen). */
    fun installedBytes(context: Context): Long = root(context).walkBottomUp().filter { it.isFile }.sumOf { it.length() }

    fun deleteAll(context: Context) {
        root(context).deleteRecursively()
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
