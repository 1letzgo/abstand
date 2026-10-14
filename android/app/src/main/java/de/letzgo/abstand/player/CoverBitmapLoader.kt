@file:OptIn(UnstableApi::class)

package de.letzgo.abstand.player

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.util.BitmapLoader
import androidx.media3.common.util.UnstableApi
import coil3.SingletonImageLoader
import coil3.request.ImageRequest
import coil3.request.allowHardware
import coil3.toBitmap
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.SettableFuture
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.io.IOException

/**
 * iOS: `loadNowPlayingArtwork` / `makeNowPlayingArtwork` (Hero-Cover, max. 512 px) und
 * `CarPlayCoordinator.loadArtwork`. Lädt über Coil — gleicher Cache (offline verfügbar) und gleicher
 * OkHttp-Client (Trust, Custom-Header, Bearer) wie die Cover in der App.
 */
class CoverBitmapLoader(private val context: Context) : BitmapLoader {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun supportsMimeType(mimeType: String): Boolean = mimeType.startsWith("image/")

    override fun decodeBitmap(data: ByteArray): ListenableFuture<Bitmap> {
        val future = SettableFuture.create<Bitmap>()
        scope.launch {
            val bmp = BitmapFactory.decodeByteArray(data, 0, data.size)
            if (bmp != null) future.set(bmp) else future.setException(IOException("Could not decode artwork"))
        }
        return future
    }

    override fun loadBitmap(uri: Uri): ListenableFuture<Bitmap> {
        val future = SettableFuture.create<Bitmap>()
        scope.launch {
            try {
                val request = ImageRequest.Builder(context)
                    .data(uri.toString())
                    .size(MAX_SIDE_PX)
                    .allowHardware(false)
                    .build()
                val bitmap = SingletonImageLoader.get(context).execute(request).image?.toBitmap()
                if (bitmap != null) future.set(bitmap) else future.setException(IOException("No artwork for $uri"))
            } catch (e: Exception) {
                future.setException(e)
            }
        }
        return future
    }

    private companion object {
        /** iOS: `scaleImage(_:maxSide: 512)`. */
        const val MAX_SIDE_PX = 512
    }
}
