package de.letzgo.abstand.store

import android.database.sqlite.SQLiteDatabase
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.io.File
import java.util.Collections

/**
 * iOS: `LocalStoreMaintenance` — Wartung des lokalen Stores (`LocalLibrary.v2.store`).
 *
 * iOS kämpft mit der SwiftData-Persistent-History (mehrere GB). Room führt keine History, ein
 * aufgeblähter Store entsteht hier nur durch freie Seiten nach großen Löschungen — die Logik bleibt
 * trotzdem gleich: aktiven Store im Hintergrund per `VACUUM` verkleinern (währenddessen nicht öffnen),
 * aufgeblähte Stores anderer Accounts löschen (reiner Server-Spiegel, wird neu aufgebaut).
 */
object LocalStoreMaintenance {
    /** Ab dieser Größe gilt ein Store als aufgebläht (gesunde Stores: wenige MB). */
    const val OVERSIZE_THRESHOLD_BYTES: Long = 256L * 1024 * 1024

    private val busyPaths: MutableSet<String> = Collections.synchronizedSet(HashSet())
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** Läuft für diesen Store gerade eine Bereinigung? Dann darf er nicht geöffnet werden. */
    fun isCompacting(storeFile: File): Boolean = storeFile.canonicalPathOrAbsolute() in busyPaths

    /**
     * Startet die Bereinigung im Hintergrund, wenn der Store aufgebläht ist. `true`, wenn sie läuft
     * (oder gerade gestartet wurde) — der Store ist dann vorübergehend nicht verfügbar.
     */
    fun compactInBackgroundIfOversized(storeFile: File): Boolean {
        val path = storeFile.canonicalPathOrAbsolute()
        if (path in busyPaths) return true
        if (fileSize(storeFile) <= OVERSIZE_THRESHOLD_BYTES) return false
        busyPaths.add(path)
        scope.launch {
            val before = fileSize(storeFile)
            val ok = compact(storeFile)
            val after = fileSize(storeFile)
            busyPaths.remove(path)
            Log.i(TAG, "store compact ${if (ok) "ok" else "failed"}: ${before / 1_048_576} MB → ${after / 1_048_576} MB")
        }
        return true
    }

    /** Aufgeblähte Stores anderer Accounts/alter Server-URLs (nicht der aktive) löschen. */
    fun discardOversizedOtherStores(accountsDirectory: File, active: File) {
        val activePath = active.canonicalPathOrAbsolute()
        val servers = accountsDirectory.listFiles() ?: return
        for (server in servers) {
            val directories = mutableListOf(server)
            File(server, "users").listFiles()?.let { directories.addAll(it) }
            for (directory in directories) {
                val store = File(directory, LocalLibraryStoreManager.STORE_FILE_NAME)
                val path = store.canonicalPathOrAbsolute()
                if (path == activePath || !store.exists() || fileSize(store) <= OVERSIZE_THRESHOLD_BYTES || isCompacting(store)) continue
                // Während des Löschens darf niemand den Store öffnen (`isCompacting` sperrt `store(...)`).
                busyPaths.add(path)
                val size = fileSize(store)
                storeFiles(store).forEach { it.delete() }
                busyPaths.remove(path)
                Log.i(TAG, "Oversized inactive store removed: ${size / 1_048_576} MB")
            }
        }
    }

    /**
     * iOS: `removeStaleDownloadTempFiles` (`CFNetworkDownload_*.tmp`). Android: abgebrochene
     * Download-Zwischendateien des API-Clients (`abs-dl-*.part`) unter [root], älter als [ageMillis].
     */
    fun removeStaleDownloadTempFiles(root: File, ageMillis: Long = 3_600_000L, now: Long = System.currentTimeMillis()) {
        var removed = 0L
        root.walkTopDown().maxDepth(3).filter { it.isFile && it.name.startsWith("abs-dl-") && it.name.endsWith(".part") }.forEach { f ->
            if (now - f.lastModified() > ageMillis) {
                val size = f.length()
                if (f.delete()) removed += size
            }
        }
        if (removed > 0) Log.i(TAG, "Stale download temp files removed: ${removed / 1_048_576} MB")
    }

    private fun fileSize(f: File): Long = if (f.exists()) f.length() else 0L

    private fun storeFiles(store: File): List<File> =
        listOf(store, File(store.path + "-wal"), File(store.path + "-shm"), File(store.path + "-journal"))

    /** Freie Seiten zurückgeben. Die Nutzdaten bleiben unberührt. */
    private fun compact(storeFile: File): Boolean = try {
        SQLiteDatabase.openDatabase(storeFile.path, null, SQLiteDatabase.OPEN_READWRITE).use { db ->
            runCatching { db.rawQuery("PRAGMA wal_checkpoint(TRUNCATE)", null).use { it.moveToFirst() } }
            db.execSQL("VACUUM")
            true
        }
    } catch (e: Exception) {
        false
    }

    private fun File.canonicalPathOrAbsolute(): String = runCatching { canonicalPath }.getOrDefault(absolutePath)

    private const val TAG = "LocalStoreMaintenance"
}
