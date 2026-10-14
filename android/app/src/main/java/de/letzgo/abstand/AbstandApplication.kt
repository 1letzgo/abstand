package de.letzgo.abstand

import android.app.Application
import coil3.ImageLoader
import coil3.PlatformContext
import coil3.SingletonImageLoader
import coil3.disk.DiskCache
import coil3.memory.MemoryCache
import coil3.network.okhttp.OkHttpNetworkFetcherFactory
import de.letzgo.abstand.data.Net
import de.letzgo.abstand.data.Prefs
import de.letzgo.abstand.downloads.DownloadManager
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.ui.AppIntegration
import de.letzgo.abstand.store.CoverRequestFetcher
import de.letzgo.abstand.store.CoverRequestKeyer
import okio.Path.Companion.toOkioPath

/** iOS: `abstandApp`. Nur billige Initialisierung — Platten-/Netzarbeit läuft im Bootstrap. */
class AbstandApplication : Application(), SingletonImageLoader.Factory {
    override fun onCreate() {
        super.onCreate()
        Prefs.init(this)
        Net.watchNetworkChanges(this)
        val model = AppModel(this)
        AppModel.install(model)
        // Player, Downloads, Android Auto — vor `start()`, damit Launch-Restore und Worker-Neustart sie vorfinden.
        DownloadManager.init(this)
        model.player.attach()
        AppIntegration.install(model)
        model.start()
    }

    // Server-Cover (iOS: `CoverImageCache`/`CoverImageLoader`) über `CoverRequest` mit eigenem
    // Account-Disk-Cache; übrige Bilder (externe Feeds) über den gemeinsamen OkHttp-Client + Coil-Disk-Cache.
    override fun newImageLoader(context: PlatformContext): ImageLoader =
        ImageLoader.Builder(context)
            .components {
                add(CoverRequestFetcher.Factory())
                add(CoverRequestKeyer())
                add(OkHttpNetworkFetcherFactory(callFactory = { Net.imageClient }))
            }
            // iOS: 100 MB dekodierte Bytes, max. 300 Cover — hier anteilig am App-Speicher.
            .memoryCache { MemoryCache.Builder().maxSizePercent(context, 0.2).build() }
            .diskCache {
                DiskCache.Builder()
                    .directory(cacheDir.resolve("AbstandCoverCache").toOkioPath())
                    .maxSizeBytes(300L * 1024 * 1024)
                    .build()
            }
            .build()
}
