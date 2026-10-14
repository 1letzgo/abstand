package de.letzgo.abstand.ui.detail

import android.graphics.Bitmap
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import de.letzgo.abstand.logic.CoverAverageRgbCache
import de.letzgo.abstand.logic.CoverRgb
import de.letzgo.abstand.logic.CoverTintMath
import de.letzgo.abstand.store.CoverImageCache
import de.letzgo.abstand.store.CoverRequest
import de.letzgo.abstand.ui.AppColorPalette
import de.letzgo.abstand.ui.Rgb
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.LocalCoverEnvironment
import de.letzgo.abstand.ui.components.abstandDetailScrollBackground
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Ergebnis der Cover-Tönung: Hintergrund (`abstandDetailScrollBackground`) und Kartenfläche. */
data class DetailCoverTint(val background: Color, val card: Color)

private fun CoverRgb.color(): Color = Rgb(r, g, b).toColor()

private fun Color.coverRgb(): CoverRgb = Rgb.of(this).let { CoverRgb(it.r, it.g, it.b) }

/** iOS: `coverDominantBackgroundTint(fromAverageRed:…)` + `detailSectionCardTint(forBackgroundTint:)`. */
fun detailCoverTint(avg: CoverRgb?, palette: AppColorPalette): DetailCoverTint {
    if (avg == null) return DetailCoverTint(palette.background, palette.card)
    val paper = palette.background.coverRgb()
    val bg = CoverTintMath.coverDominantBackgroundTint(avg, palette.isDarkLike, paper)
    val card = CoverTintMath.detailSectionCardTint(bg, palette.isDarkLike, paper)
    return DetailCoverTint(bg.color(), card.color())
}

/** iOS: `coverAverageRGB(from:)` — auf 32×32 verkleinert gemittelt (Area-Average-Näherung). */
private fun averageRgb(bitmap: Bitmap): CoverRgb? {
    val small = Bitmap.createScaledBitmap(bitmap, 32, 32, true)
    val pixels = IntArray(32 * 32)
    small.getPixels(pixels, 0, 32, 0, 0, 32, 32)
    return CoverTintMath.averageRgb(pixels)
}

/**
 * iOS: Cover-Tint der Detailseiten (`seedCoverTintFromLocalCache` + `loadCoverTint`): sofort aus dem
 * persistierten Durchschnitt (`DetailCoverAverageRGBCache`, nur bei [persistItemId]), dann aus dem
 * Hero-Cover über denselben Cache-Key wie das sichtbare Cover. Palette-Wechsel rechnen nur neu.
 */
@Composable
fun rememberDetailCoverTint(
    url: String?,
    cacheKey: String?,
    persistItemId: String? = null,
): DetailCoverTint {
    val context = LocalContext.current
    val env = LocalCoverEnvironment.current
    val palette = Theme.palette
    var avg by remember(persistItemId, cacheKey) {
        mutableStateOf(persistItemId?.let { CoverAverageRgbCache.detailCover.load(env.accountDir, it) })
    }
    LaunchedEffect(url, cacheKey) {
        if (url.isNullOrEmpty() || cacheKey.isNullOrEmpty()) return@LaunchedEffect
        val bitmap = runCatching { CoverImageCache.loadHeroImage(context, CoverRequest(cacheKey, url, env.accountDir)) }.getOrNull()
            ?: return@LaunchedEffect
        val rgb = withContext(Dispatchers.Default) { averageRgb(bitmap) } ?: return@LaunchedEffect
        avg = rgb
        if (persistItemId != null) withContext(Dispatchers.IO) { CoverAverageRgbCache.detailCover.save(env.accountDir, persistItemId, rgb = rgb) }
    }
    return remember(avg, palette) { detailCoverTint(avg, palette) }
}
