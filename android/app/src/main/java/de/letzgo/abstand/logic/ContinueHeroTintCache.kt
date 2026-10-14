package de.letzgo.abstand.logic

import de.letzgo.abstand.data.AbsJson
import kotlinx.serialization.Serializable
import java.io.File

/** RGB-Tripel 0…1 (iOS: `(r: Double, g: Double, b: Double)`). */
@Serializable
data class CoverRgb(val r: Double, val g: Double, val b: Double)

/**
 * Farbmathe aus iOS `DetailHeroViews.swift` (`coverAverageRGB`, `coverDominantBackgroundTint`,
 * `continueListeningCardTint`, `detailSectionCardTint`, `detailSectionControlActiveTint`) ohne
 * Farb-Typen: Paletten-Hintergrund und `isDarkLike` kommen als Parameter.
 */
object CoverTintMath {
    /**
     * iOS: `coverAverageRGB` (CIAreaAverage ohne Farbraum, RGBA8) — Mittel der Kanäle über alle Pixel,
     * auf 8 Bit gerundet und durch 255 geteilt. [argbPixels] wie `Bitmap.getPixels` (ARGB, nicht
     * vormultipliziert); Alpha wird wie bei Core Image vormultipliziert gemittelt.
     */
    fun averageRgb(argbPixels: IntArray): CoverRgb? {
        if (argbPixels.isEmpty()) return null
        var r = 0.0; var g = 0.0; var b = 0.0; var a = 0.0
        for (p in argbPixels) {
            val alpha = ((p ushr 24) and 0xFF) / 255.0
            r += ((p ushr 16) and 0xFF) / 255.0 * alpha
            g += ((p ushr 8) and 0xFF) / 255.0 * alpha
            b += (p and 0xFF) / 255.0 * alpha
            a += alpha
        }
        val n = argbPixels.size.toDouble()
        // Core Image rendert das vormultiplizierte Mittel nach RGBA8 (entmultipliziert bei Alpha < 1).
        val meanA = a / n
        fun channel(sum: Double): Double {
            val v = if (meanA > 0) (sum / n) / meanA else 0.0
            return Math.round(minOf(1.0, maxOf(0.0, v)) * 255.0) / 255.0
        }
        return CoverRgb(channel(r), channel(g), channel(b))
    }

    /** Detail-/Player-Hintergrund (mix 0.34 / floor 0.045 dunkel, Papier-Gewicht 0.3 hell). */
    fun coverDominantBackgroundTint(avg: CoverRgb, isDarkLike: Boolean, paper: CoverRgb): CoverRgb =
        if (isDarkLike) {
            CoverRgb(minOf(1.0, avg.r * 0.34 + 0.045), minOf(1.0, avg.g * 0.34 + 0.045), minOf(1.0, avg.b * 0.34 + 0.045))
        } else {
            blend(avg, paper, 0.3)
        }

    /** Continue-Listening-Karten: stärkere Tönung (mix 0.62 / floor 0.06 dunkel, Gewicht 0.55 hell). */
    fun continueListeningCardTint(avg: CoverRgb, isDarkLike: Boolean, paper: CoverRgb): CoverRgb =
        if (isDarkLike) {
            CoverRgb(minOf(1.0, avg.r * 0.62 + 0.06), minOf(1.0, avg.g * 0.62 + 0.06), minOf(1.0, avg.b * 0.62 + 0.06))
        } else {
            blend(avg, paper, 0.55)
        }

    /** Kartenfläche auf Cover-Tint-Hintergrund. */
    fun detailSectionCardTint(tint: CoverRgb, isDarkLike: Boolean, paper: CoverRgb): CoverRgb {
        if (isDarkLike) {
            return CoverRgb(minOf(1.0, tint.r * 1.15 + 0.065), minOf(1.0, tint.g * 1.15 + 0.065), minOf(1.0, tint.b * 1.15 + 0.065))
        }
        fun channel(t: Double, p: Double) = minOf(1.0, (t * 0.52 + p * 0.48) * 0.93)
        return CoverRgb(channel(tint.r, paper.r), channel(tint.g, paper.g), channel(tint.b, paper.b))
    }

    /** Aktiver Panel-Steuerbutton auf Cover-Tint-Hintergrund. */
    fun detailSectionControlActiveTint(card: CoverRgb, isDarkLike: Boolean): CoverRgb {
        if (isDarkLike) {
            return CoverRgb(minOf(1.0, card.r * 1.2 + 0.08), minOf(1.0, card.g * 1.2 + 0.08), minOf(1.0, card.b * 1.2 + 0.08))
        }
        fun channel(v: Double) = maxOf(0.0, minOf(1.0, v * 0.86))
        return CoverRgb(channel(card.r), channel(card.g), channel(card.b))
    }

    private fun blend(cover: CoverRgb, paper: CoverRgb, coverWeight: Double): CoverRgb {
        val paperWeight = 1 - coverWeight
        return CoverRgb(
            cover.r * coverWeight + paper.r * paperWeight,
            cover.g * coverWeight + paper.g * paperWeight,
            cover.b * coverWeight + paper.b * paperWeight,
        )
    }
}

/**
 * iOS: `ContinueHeroTintCache` (Ordner `heroTintAvg`) und `DetailCoverAverageRGBCache`
 * (`detailCoverAvgRGB`): roher Cover-Durchschnitt je Item als `<sha256(key)>.json` `{r,g,b}`.
 */
class CoverAverageRgbCache private constructor(private val subdir: String, private val usesRevision: Boolean) {
    private fun dir(account: File) = File(account, subdir)

    /** `revision` 0 → `itemId`, sonst `itemId#r<revision>` (verfällt mit Cover-Änderung). */
    fun cacheKey(itemId: String, revision: Int): String =
        if (!usesRevision || revision == 0) itemId else "$itemId#r$revision"

    fun fileFor(account: File, itemId: String, revision: Int = 0): File =
        File(dir(account), PlayerTranscriptCacheStore.sha256Hex(cacheKey(itemId, revision)) + ".json")

    fun load(account: File?, itemId: String, revision: Int = 0): CoverRgb? {
        account ?: return null
        val f = fileFor(account, itemId, revision)
        if (!f.exists()) return null
        return runCatching { AbsJson.decoder.decodeFromString(CoverRgb.serializer(), f.readText()) }.getOrNull()
    }

    fun save(account: File?, itemId: String, revision: Int = 0, rgb: CoverRgb) {
        account ?: return
        runCatching {
            val f = fileFor(account, itemId, revision)
            f.parentFile?.mkdirs()
            f.writeText(AbsJson.encoder.encodeToString(CoverRgb.serializer(), rgb))
        }
    }

    fun clearAll(account: File) {
        dir(account).deleteRecursively()
        dir(account).mkdirs()
    }

    companion object {
        /** iOS: `ContinueHeroTintCache`. */
        val continueHero = CoverAverageRgbCache("heroTintAvg", usesRevision = true)
        /** iOS: `DetailCoverAverageRGBCache` (ohne Revision). */
        val detailCover = CoverAverageRgbCache("detailCoverAvgRGB", usesRevision = false)
    }
}
