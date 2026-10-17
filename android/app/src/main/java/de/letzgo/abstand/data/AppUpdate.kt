package de.letzgo.abstand.data

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import de.letzgo.abstand.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import okhttp3.Request
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.TimeUnit

/**
 * Android-eigen (wie stede `AppUpdate`): Updates für APKs außerhalb von Google Play. Neue Versionen
 * liegen als Releases im öffentlichen Repo 1letzgo/abstand, Tag `abstand-android-<versionCode>` mit
 * der APK als Asset. Nur der `sideload`-Flavor prüft, lädt die APK in der App (Prüfsumme gegen den
 * GitHub-Digest) und übergibt sie dem Paketinstaller; Play-Builds und Play-Installationen fragen nie.
 */
object AppUpdate {
    private const val RELEASES = "https://api.github.com/repos/1letzgo/abstand/releases?per_page=30"
    const val TAG_PREFIX = "abstand-android-"
    private const val LAST_CHECK = "abstand_update_last_check"
    private const val SKIPPED = "abstand_update_skipped_version_code"
    private const val CHECK_INTERVAL_MS = 6 * 3600_000L

    /** [sha256] aus dem Asset-Digest von GitHub, zum Prüfen des Downloads. */
    data class Release(val versionCode: Int, val name: String, val notes: String, val apkUrl: String, val pageUrl: String, val sha256: String?)

    @Serializable internal data class GitRelease(
        @SerialName("tag_name") val tag: String,
        val name: String? = null,
        val body: String? = null,
        val draft: Boolean = false,
        val prerelease: Boolean = false,
        @SerialName("html_url") val htmlUrl: String = "",
        val assets: List<Asset> = emptyList(),
    )

    @Serializable internal data class Asset(
        val name: String,
        @SerialName("browser_download_url") val url: String,
        val digest: String? = null,
    )

    /** Prüft dieser Build überhaupt? Nur `sideload` und nicht aus Google Play installiert. */
    fun isEnabled(context: Context) = BuildConfig.SIDELOAD && !fromPlayStore(context)

    /** Von Google Play installiert? Dann gibt es keine Prüfung. */
    fun fromPlayStore(context: Context): Boolean = runCatching {
        val installer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            context.packageManager.getInstallSourceInfo(context.packageName).installingPackageName
        } else {
            @Suppress("DEPRECATION") context.packageManager.getInstallerPackageName(context.packageName)
        }
        installer == "com.android.vending"
    }.getOrDefault(false)

    /** Neueste veröffentlichte Version aus der Release-Liste, wenn sie neuer ist als [installedCode]. */
    internal fun newest(releases: List<GitRelease>, installedCode: Int): Release? = releases.asSequence()
        .filter { !it.draft && !it.prerelease && it.tag.startsWith(TAG_PREFIX) }
        .mapNotNull { r ->
            val code = r.tag.removePrefix(TAG_PREFIX).toIntOrNull() ?: return@mapNotNull null
            val apk = r.assets.firstOrNull { it.name.endsWith(".apk") } ?: return@mapNotNull null
            Release(code, r.name ?: r.tag, r.body.orEmpty().trim(), apk.url, r.htmlUrl, apk.digest?.removePrefix("sha256:"))
        }
        .maxByOrNull { it.versionCode }
        ?.takeIf { it.versionCode > installedCode }

    /** Fragt GitHub; neuere Version oder `null`. Wirft bei Netzfehlern. */
    suspend fun newer(): Release? = withContext(Dispatchers.IO) {
        val request = Request.Builder().url(RELEASES).header("Accept", "application/vnd.github+json").build()
        val body = Net.client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) error("HTTP ${response.code}")
            response.body.string()
        }
        newest(AbsJson.decoder.decodeFromString(ListSerializer(GitRelease.serializer()), body), BuildConfig.VERSION_CODE)
    }

    /** Beim Start höchstens alle sechs Stunden, und nicht für eine Version, die „Later“ bekam. */
    suspend fun checkOnLaunch(context: Context): Release? {
        if (!isEnabled(context)) return null
        val now = System.currentTimeMillis()
        if (now - Prefs.long(LAST_CHECK) < CHECK_INTERVAL_MS) return null
        val release = runCatching { newer() }.getOrNull()
        Prefs.setLong(LAST_CHECK, now)
        return release?.takeIf { it.versionCode > Prefs.int(SKIPPED) }
    }

    fun skip(release: Release) = Prefs.setInt(SKIPPED, release.versionCode)

    /** Lädt die APK nach `cache/updates/` und prüft sie gegen den Digest von GitHub. */
    suspend fun download(context: Context, release: Release, progress: (Float?) -> Unit): File = withContext(Dispatchers.IO) {
        val dir = File(context.cacheDir, "updates").apply { mkdirs(); listFiles()?.forEach { it.delete() } }
        val file = File(dir, "abstand-${release.versionCode}.apk")
        val digest = MessageDigest.getInstance("SHA-256")
        // Mobil kann die APK länger brauchen als die üblichen Timeouts.
        val client = Net.client.newBuilder().readTimeout(10, TimeUnit.MINUTES).callTimeout(10, TimeUnit.MINUTES).build()
        client.newCall(Request.Builder().url(release.apkUrl).build()).execute().use { response ->
            if (!response.isSuccessful) error("HTTP ${response.code}")
            val total = response.body.contentLength()
            val buffer = ByteArray(64 * 1024)
            var done = 0L
            response.body.byteStream().use { input ->
                file.outputStream().use { out ->
                    while (true) {
                        val n = input.read(buffer)
                        if (n < 0) break
                        out.write(buffer, 0, n)
                        digest.update(buffer, 0, n)
                        done += n
                        progress(total.takeIf { it > 0 }?.let { done.toFloat() / it })
                    }
                }
            }
        }
        val hash = digest.digest().joinToString("") { "%02x".format(it) }
        if (release.sha256 != null && !release.sha256.equals(hash, ignoreCase = true)) {
            file.delete()
            error("The downloaded file is damaged.")
        }
        file
    }

    /** Darf die App Pakete installieren? Sonst erst die Freigabe in den Android-Einstellungen. */
    fun canInstall(context: Context) = Build.VERSION.SDK_INT < Build.VERSION_CODES.O || context.packageManager.canRequestPackageInstalls()

    fun openInstallPermission(context: Context) = context.startActivity(
        Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
    )

    /** Übergibt die APK dem Paketinstaller; Android fragt dann „Install?“. */
    fun install(context: Context, file: File) {
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.updates", file)
        context.startActivity(
            Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }
}
