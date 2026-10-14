package de.letzgo.abstand.store

import de.letzgo.abstand.data.Prefs
import de.letzgo.abstand.data.swiftTrim
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap

/** SHA-256 als Kleinbuchstaben-Hex (iOS: `SHA256.hash(...).map { "%02x" }.joined()`). */
fun sha256Hex(value: String): String =
    MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }

/**
 * iOS: `AccountCacheDirectory` — Account-Cache-Wurzel für dateibasierte Subsysteme (Downloads-Index,
 * Cover, eBook-Lokaldaten, Transkripte). Gleiches Pfadschema wie iOS:
 * `filesDir/ABStandLibraryCache/accounts/<sha256(serverURL)>/users/<sha256(userId)>`.
 */
object AccountCacheDirectory {
    const val ROOT_DIR_NAME = "ABStandLibraryCache"

    /** Überschreibbar für Tests; Standard `filesDir/ABStandLibraryCache`. */
    @Volatile var baseDirOverride: File? = null

    private val baseDir: File get() = baseDirOverride ?: File(Prefs.appContext.filesDir, ROOT_DIR_NAME)

    /**
     * Ergebnis je (Server, User) gemerkt — läuft u. a. in Composables (Cover-Cache-Pfade je Karte);
     * ungecacht kostete jeder Aufruf zwei SHA-256 + zwei `mkdirs`. Account-Verzeichnisse werden nie als
     * Ganzes gelöscht, der Cache kann also nicht auf ein fehlendes Verzeichnis zeigen.
     */
    private val memo = ConcurrentHashMap<String, File>()

    /** Server-URL (+ optional User) — getrennte Caches pro Audiobookshelf-Nutzer auf demselben Host. */
    fun accountDir(serverURL: String, userId: String? = null): File {
        val key = serverURL + "\u0000" + (userId ?: "")
        memo[key]?.let { return it }
        val dir = accountDirPath(baseDir, serverURL, userId)
        dir.mkdirs()
        memo[key] = dir
        return dir
    }

    /** Reiner Pfadaufbau ohne Anlegen (testbar). Leere/whitespace User-ID → Server-Wurzel. */
    fun accountDirPath(base: File, serverURL: String, userId: String?): File {
        val serverRoot = File(File(base, "accounts"), sha256Hex(serverURL))
        val trimmedUser = userId?.swiftTrim().orEmpty()
        if (trimmedUser.isEmpty()) return serverRoot
        return File(File(serverRoot, "users"), sha256Hex(trimmedUser))
    }

    /** Nur Tests: Memo leeren (z. B. nach Wechsel von [baseDirOverride]). */
    fun resetMemoForTests() = memo.clear()
}
