package de.letzgo.abstand.downloads

import android.util.Log
import java.io.File

/**
 * iOS: `LocalStoreMaintenance.removeStaleDownloadTempFiles` — Zwischendateien abgebrochener Downloads.
 * Auf Android schreibt `AbsApiClient.downloadAuthenticatedFile` nach `abs-dl-*.part` im Item-Ordner
 * (iOS: `CFNetworkDownload_*.tmp` im Temp-Ordner) — dazu verwaiste `download.json.tmp`/WIP-Temps.
 * Nur alte Dateien löschen, damit ein laufender Download nie angetastet wird.
 */
object DownloadMaintenance {
    private const val TAG = "AbstandDownloads"
    const val DEFAULT_MAX_AGE_MS = 3_600_000L

    /** Gehört die Datei zu den Download-Zwischendateien? */
    fun isDownloadTempFile(name: String): Boolean =
        (name.startsWith("abs-dl-") && name.endsWith(".part")) ||
            name == "download.json.tmp" || name == "${DownloadWip.FILENAME}.tmp"

    /** Löscht Zwischendateien älter als [maxAgeMs] unter den Item-Ordnern unter `downloadsRoot`; liefert die freigegebenen Bytes. */
    fun removeStaleDownloadTempFiles(downloadsRoot: File, maxAgeMs: Long = DEFAULT_MAX_AGE_MS, nowMs: Long = System.currentTimeMillis()): Long {
        var removed = 0L
        downloadsRoot.listFiles()?.filter { it.isDirectory }?.forEach { dir ->
            dir.listFiles()?.forEach { f ->
                if (f.isFile && isDownloadTempFile(f.name) && nowMs - f.lastModified() > maxAgeMs) {
                    val size = f.length()
                    if (f.delete()) removed += size
                }
            }
        }
        if (removed > 0) Log.i(TAG, "Stale download temp files removed: ${removed / 1_048_576} MB")
        return removed
    }

    /** Bequemer Einstieg für den App-Start (Hintergrund-Thread). */
    fun removeStaleDownloadTempFiles(): Long = removeStaleDownloadTempFiles(DownloadManager.downloadsRoot())
}
