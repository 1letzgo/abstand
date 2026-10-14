package de.letzgo.abstand.ui

import java.util.Locale
import kotlin.math.roundToInt

/** iOS: `formatPlaybackTime(_:)` (AppTheme.swift) — `m:ss` bzw. `h:mm:ss`. */
fun formatPlaybackTime(seconds: Double): String {
    if (!seconds.isFinite() || seconds < 0) return "0:00"
    val s = seconds.roundToInt()
    val h = s / 3600
    val m = (s % 3600) / 60
    val r = s % 60
    return if (h > 0) String.format(Locale.US, "%d:%02d:%02d", h, m, r) else String.format(Locale.US, "%d:%02d", m, r)
}

/** iOS: `formatPlaybackDurationShortHuman(_:)` — z. B. „2 hrs 15 min“, unter einer Minute „< 1 min“. */
fun formatPlaybackDurationShortHuman(seconds: Double): String {
    if (!seconds.isFinite() || seconds < 0) return "< 1 min"
    val s = seconds.roundToInt()
    val h = s / 3600
    val m = (s % 3600) / 60
    if (h == 0 && m == 0) return "< 1 min"
    val parts = mutableListOf<String>()
    if (h > 0) parts += if (h == 1) "1 hr" else "$h hrs"
    if (m > 0) parts += if (m == 1) "1 min" else "$m min"
    return parts.joinToString(" ")
}
