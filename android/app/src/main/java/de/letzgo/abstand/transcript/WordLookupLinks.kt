package de.letzgo.abstand.transcript

import java.net.URLEncoder

/** Web-Ziele des Wort-Sheets (Android-Ersatz für Systemwörterbuch/Translation-Framework). */
object WordLookupLinks {
    private fun encode(value: String): String = URLEncoder.encode(value, "UTF-8").replace("+", "%20")

    /** Google Translate; ohne Quellsprache automatische Erkennung. */
    fun translateUrl(term: String, sourceLanguage: String?, targetLanguage: String): String {
        val sl = sourceLanguage?.trim()?.lowercase()?.takeIf { it.isNotEmpty() } ?: "auto"
        return "https://translate.google.com/?sl=${encode(sl)}&tl=${encode(targetLanguage.trim().lowercase())}" +
            "&text=${encode(term)}&op=translate"
    }

    fun searchUrl(term: String): String = "https://www.google.com/search?q=${encode(term)}"
}
