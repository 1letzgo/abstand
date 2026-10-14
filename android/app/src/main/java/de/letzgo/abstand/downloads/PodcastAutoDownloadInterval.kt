package de.letzgo.abstand.downloads

/**
 * iOS: `PodcastAutoDownloadInterval` (PodcastAutoDownloadSchedule.swift) — Cron-Vorgaben (5 Felder)
 * für das serverseitige `autoDownloadSchedule` einer Podcast-Sendung. Der Server lädt neue Folgen in
 * die Bibliothek; ein Geräte-Download neuer Folgen existiert auf iOS nicht.
 */
enum class PodcastAutoDownloadInterval(val rawValue: String, val label: String, val cronExpression: String) {
    everyHour("everyHour", "Every hour", "0 * * * *"),
    every6Hours("every6Hours", "Every 6 hours", "0 */6 * * *"),
    every12Hours("every12Hours", "Every 12 hours", "0 */12 * * *"),
    daily("daily", "Daily", "0 0 * * *"),
    weekly("weekly", "Weekly", "0 0 * * 1");

    val id: String get() = rawValue

    companion object {
        val default = daily

        fun from(cron: String?): PodcastAutoDownloadInterval {
            val normalized = normalizeCron(cron)
            entries.firstOrNull { it.cronExpression == normalized }?.let { return it }
            val parts = normalized.split(Regex("\\s+")).filter { it.isNotEmpty() }
            if (parts.size < 5) return default
            val hour = parts[1]
            val dom = parts[2]
            val month = parts[3]
            val dow = parts[4]
            if (dom == "*" && month == "*" && dow != "*") return weekly
            // Stunden-Feld vor „täglich“ prüfen (wie iOS / `model/PodcastLogic.kt`).
            if (hour.startsWith("*/12")) return every12Hours
            if (hour.startsWith("*/6")) return every6Hours
            if (hour == "*") return everyHour
            if (dom == "*" && month == "*") return daily
            return default
        }

        private fun normalizeCron(cron: String?): String =
            cron?.trim()?.split(Regex("\\s+"))?.filter { it.isNotEmpty() }?.joinToString(" ") ?: ""
    }
}
