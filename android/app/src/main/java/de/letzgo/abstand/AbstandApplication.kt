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
import okio.Path.Companion.toOkioPath

/** iOS: `abstandApp`. Nur billige Initialisierung — Platten-/Netzarbeit läuft im Bootstrap. */
class AbstandApplication : Application(), SingletonImageLoader.Factory {
    override fun onCreate() {
        super.onCreate()
        Prefs.init(this)
        Net.watchNetworkChanges(this)
    }

    // Cover-Cache (iOS: `CoverImageCache`) über den gemeinsamen OkHttp-Client (Trust + Header).
    override fun newImageLoader(context: PlatformContext): ImageLoader =
        ImageLoader.Builder(context)
            .components { add(OkHttpNetworkFetcherFactory(callFactory = { Net.imageClient })) }
            .memoryCache { MemoryCache.Builder().maxSizePercent(context, 0.2).build() }
            .diskCache {
                DiskCache.Builder()
                    .directory(cacheDir.resolve("AbstandCoverCache").toOkioPath())
                    .maxSizeBytes(300L * 1024 * 1024)
                    .build()
            }
            .build()
}
