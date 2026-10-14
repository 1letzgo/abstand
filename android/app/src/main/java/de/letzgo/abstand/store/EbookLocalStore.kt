package de.letzgo.abstand.store

import de.letzgo.abstand.data.AbsEbookFormat
import de.letzgo.abstand.data.AbsJson
import de.letzgo.abstand.data.Prefs
import de.letzgo.abstand.data.swiftTrim
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import java.io.File

/** iOS: `EpubReaderTheme`. */
enum class EpubReaderTheme(val rawValue: String, val displayName: String) {
    light("light", "Light"),
    sepia("sepia", "Sepia"),
    dark("dark", "Dark");

    companion object {
        fun fromRaw(raw: String?) = entries.firstOrNull { it.rawValue == raw }
    }
}

/** iOS: `EpubReaderSettings` — Leseeinstellungen (global, Prefs; gleiche Keys wie iOS). */
object EpubReaderSettings {
    /** Readium-Schriftgröße als Faktor (1.0 = 100 %). */
    private const val fontScaleKey = "abstand_epub_font_scale"
    private const val legacyFontSizeKey = "abstand_epub_font_size"
    private const val themeKey = "abstand_epub_reader_theme"
    private const val continuousScrollKey = "abstand_epub_continuous_scroll"

    const val defaultFontSize = 1.0
    const val minFontSize = 0.7
    const val maxFontSize = 1.8
    const val fontSizeStep = 0.1

    fun loadTheme(): EpubReaderTheme = EpubReaderTheme.fromRaw(Prefs.string(themeKey)) ?: EpubReaderTheme.light

    fun saveTheme(theme: EpubReaderTheme) = Prefs.setString(themeKey, theme.rawValue)

    fun loadFontSize(): Double {
        if (Prefs.has(fontScaleKey)) {
            val v = Prefs.double(fontScaleKey)
            return if (v in minFontSize..maxFontSize) v else defaultFontSize
        }
        if (Prefs.has(legacyFontSizeKey)) resetFontSizeToDefault()
        return defaultFontSize
    }

    fun saveFontSize(size: Double) {
        Prefs.setDouble(fontScaleKey, size.coerceIn(minFontSize, maxFontSize))
        Prefs.remove(legacyFontSizeKey)
    }

    fun resetFontSizeToDefault() {
        Prefs.setDouble(fontScaleKey, defaultFontSize)
        Prefs.remove(legacyFontSizeKey)
    }

    /** Dauerscroll statt Seitenweise-Umblättern. */
    fun loadContinuousScroll(): Boolean = Prefs.bool(continuousScrollKey)

    fun saveContinuousScroll(enabled: Boolean) = Prefs.setBool(continuousScrollKey, enabled)
}

/** `AbsEbookFormat` als `rawValue`-String (iOS: `ABSEbookFormat: String, Codable`). */
object AbsEbookFormatRawSerializer : KSerializer<AbsEbookFormat> {
    override val descriptor = PrimitiveSerialDescriptor("ABSEbookFormat", PrimitiveKind.STRING)
    override fun serialize(encoder: Encoder, value: AbsEbookFormat) = encoder.encodeString(value.rawValue)
    override fun deserialize(decoder: Decoder): AbsEbookFormat {
        val raw = decoder.decodeString()
        return AbsEbookFormat.entries.firstOrNull { it.rawValue == raw } ?: throw IllegalArgumentException("Unknown ebook format $raw")
    }
}

/** iOS: `EbookDownloadMeta` — Metadaten zu einer lokal gecachten E-Book-Datei. */
@Serializable
data class EbookDownloadMeta(
    val libraryItemId: String,
    val ino: String,
    @Serializable(with = AbsEbookFormatRawSerializer::class) val format: AbsEbookFormat,
    val title: String? = null,
)

/**
 * iOS: `EbookLocalStore` — lokale E-Book-Dateien (EPUB/PDF) pro Account; Lesestand pro angemeldetem
 * User unter `<account>/ebooks/reading/<userId>/`. Gleiche Dateinamen wie iOS.
 *
 * Abweichung: Readium-Locatoren werden als JSON-Text gespeichert/geliefert ([loadReadiumLocatorJson]);
 * der Reader-Port (Readium Kotlin) parst sie selbst. Die iOS-Migration aus alten UserDefaults-Keys
 * (`abstand_readium_loc_*` …) entfällt — Android hatte diese Keys nie.
 */
object EbookLocalStore {
    @Volatile private var activeAccount: File? = null
    @Volatile private var activeUserId: String? = null

    private val knownFormatsLock = Any()
    private var knownFormatsByItemId: MutableMap<String, String> = HashMap()
    private var knownFormatsLoadedForSessionKey: String? = null

    private val stringMapSerializer = MapSerializer(String.serializer(), String.serializer())
    private val intMapSerializer = MapSerializer(String.serializer(), Int.serializer())
    private val doubleMapSerializer = MapSerializer(String.serializer(), Double.serializer())

    /** Nach Login / `applyAuthorizeUser` setzen; bei Logout `null`. */
    fun updateActiveSession(account: File?, userId: String?) {
        val uid = userId?.swiftTrim().orEmpty()
        activeAccount = account
        activeUserId = uid.ifEmpty { null }
        synchronized(knownFormatsLock) {
            knownFormatsLoadedForSessionKey = null
            knownFormatsByItemId = HashMap()
        }
    }

    private fun requireSession(): Pair<File, String>? {
        val account = activeAccount ?: return null
        val uid = activeUserId ?: return null
        return account to uid
    }

    private fun readingProgressDir(account: File, userId: String): File =
        File(File(File(account, "ebooks"), "reading"), userId).also { it.mkdirs() }

    private fun locatorFile(account: File, userId: String, libraryItemId: String, format: AbsEbookFormat) =
        File(readingProgressDir(account, userId), "$libraryItemId.${format.rawValue}.locator.json")

    private fun pageProgressFile(account: File, userId: String, libraryItemId: String, format: AbsEbookFormat) =
        File(readingProgressDir(account, userId), "$libraryItemId.${format.rawValue}.pages.json")

    private fun progressFractionFile(account: File, userId: String, libraryItemId: String) =
        File(readingProgressDir(account, userId), "$libraryItemId.ebook_fraction.json")

    // MARK: - Bekannte Formate

    private fun knownFormatsFile(account: File, userId: String) = File(readingProgressDir(account, userId), "known_formats.json")

    private fun loadKnownFormatsIfNeeded(account: File, userId: String) {
        val sessionKey = "${account.name}|$userId"
        if (knownFormatsLoadedForSessionKey == sessionKey) return
        knownFormatsLoadedForSessionKey = sessionKey
        val f = knownFormatsFile(account, userId)
        knownFormatsByItemId = runCatching {
            AbsJson.decoder.decodeFromString(stringMapSerializer, f.readText()).toMutableMap()
        }.getOrDefault(HashMap())
    }

    private fun persistKnownFormats(account: File, userId: String) {
        val text = runCatching { AbsJson.encoder.encodeToString(stringMapSerializer, knownFormatsByItemId) }.getOrNull() ?: return
        writeAtomically(knownFormatsFile(account, userId), text.toByteArray())
    }

    fun rememberKnownFormat(format: AbsEbookFormat, libraryItemId: String) {
        val (account, userId) = requireSession() ?: return
        synchronized(knownFormatsLock) {
            loadKnownFormatsIfNeeded(account, userId)
            if (knownFormatsByItemId[libraryItemId] == format.rawValue) return
            knownFormatsByItemId[libraryItemId] = format.rawValue
            persistKnownFormats(account, userId)
        }
    }

    fun knownFormat(libraryItemId: String): AbsEbookFormat? {
        val (account, userId) = requireSession() ?: return null
        val raw = synchronized(knownFormatsLock) {
            loadKnownFormatsIfNeeded(account, userId)
            knownFormatsByItemId[libraryItemId]
        } ?: return null
        return AbsEbookFormat.entries.firstOrNull { it.rawValue == raw }
    }

    /** Bereits heruntergeladene Dateien / Meta-JSON → [knownFormat], damit EPUB/PDF-Filter ohne Öffnen greifen. */
    fun syncKnownFormatsFromDisk(account: File?) {
        val dir = File(account ?: return, "ebooks")
        val files = dir.listFiles() ?: return
        for (f in files) {
            val name = f.name
            if (name.endsWith(".meta.json")) {
                val stem = name.removeSuffix(".meta.json")
                val dot = stem.lastIndexOf('.').takeIf { it >= 0 } ?: continue
                val itemId = stem.substring(0, dot)
                val fmt = formatFromExtension(stem.substring(dot + 1)) ?: continue
                rememberKnownFormat(fmt, itemId)
                continue
            }
            if (!f.isFile) continue
            val fmt = formatFromExtension(f.extension) ?: continue
            val itemId = f.nameWithoutExtension
            if (itemId.isEmpty()) continue
            rememberKnownFormat(fmt, itemId)
        }
    }

    private fun formatFromExtension(ext: String): AbsEbookFormat? = AbsEbookFormat.entries.firstOrNull { it.rawValue == ext.lowercase() }

    // MARK: - Dateien

    private fun metaFile(account: File, libraryItemId: String, format: AbsEbookFormat) =
        File(File(account, "ebooks"), "$libraryItemId.${format.rawValue}.meta.json")

    fun ebookFile(account: File, libraryItemId: String, format: AbsEbookFormat): File =
        File(File(account, "ebooks"), "$libraryItemId.${format.rawValue}")

    fun hasCachedEbook(account: File?, libraryItemId: String, format: AbsEbookFormat): Boolean =
        account != null && ebookFile(account, libraryItemId, format).exists()

    /** Bereits heruntergeladene Datei (EPUB vor PDF). */
    fun cachedEbookIfPresent(account: File?, libraryItemId: String): Pair<File, AbsEbookFormat>? {
        account ?: return null
        for (format in AbsEbookFormat.entries) {
            val f = ebookFile(account, libraryItemId, format)
            if (f.exists()) return f to format
        }
        return null
    }

    fun cachedEbookFileByteCount(account: File?, libraryItemId: String): Long? =
        cachedEbookIfPresent(account, libraryItemId)?.first?.length()

    fun saveDownloadMeta(account: File, meta: EbookDownloadMeta) {
        ensureAccountDirs(account)
        writeAtomically(metaFile(account, meta.libraryItemId, meta.format), AbsJson.encoder.encodeToString(EbookDownloadMeta.serializer(), meta).toByteArray())
    }

    fun loadDownloadMeta(account: File, libraryItemId: String, format: AbsEbookFormat): EbookDownloadMeta? = runCatching {
        AbsJson.decoder.decodeFromString(EbookDownloadMeta.serializer(), metaFile(account, libraryItemId, format).readText())
    }.getOrNull()

    fun ensureAccountDirs(account: File) {
        File(account, "ebooks").mkdirs()
    }

    // MARK: - Readium-Locator

    /** Seitengenauer Readium-Stand (JSON-Text, iOS: `Locator`). */
    fun loadReadiumLocatorJson(libraryItemId: String, format: AbsEbookFormat): String? {
        val (account, userId) = requireSession() ?: return null
        return runCatching { locatorFile(account, userId, libraryItemId, format).readText() }.getOrNull()?.ifEmpty { null }
    }

    /** Server bekommt parallel nur `ebookProgress`-Prozent. Explizit gelesene Bücher frieren den Stand ein. */
    fun saveReadiumLocatorJson(json: String, libraryItemId: String, format: AbsEbookFormat) {
        val (account, userId) = requireSession() ?: return
        val id = libraryItemId.swiftTrim()
        if (id.isEmpty() || isMarkedFinished(id)) return
        writeAtomically(locatorFile(account, userId, id, format), json.toByteArray())
    }

    fun clearReadiumLocator(libraryItemId: String, format: AbsEbookFormat) {
        val (account, userId) = requireSession() ?: return
        locatorFile(account, userId, libraryItemId, format).delete()
        clearPageProgress(libraryItemId, format)
    }

    // MARK: - Seiten

    /** Buchweite Seiten (EPUB, gerendert) — für Listen-Metadaten und Resume-Hilfe. */
    fun savePageProgress(current: Int, total: Int, libraryItemId: String, format: AbsEbookFormat) {
        val (account, userId) = requireSession() ?: return
        val id = libraryItemId.swiftTrim()
        if (id.isEmpty() || total <= 0) return
        val payload = mapOf("current" to current.coerceIn(1, total), "total" to total)
        writeAtomically(pageProgressFile(account, userId, id, format), AbsJson.encoder.encodeToString(intMapSerializer, payload).toByteArray())
    }

    fun loadPageProgress(libraryItemId: String, format: AbsEbookFormat): Pair<Int, Int>? {
        val (account, userId) = requireSession() ?: return null
        val dict = runCatching {
            AbsJson.decoder.decodeFromString(intMapSerializer, pageProgressFile(account, userId, libraryItemId, format).readText())
        }.getOrNull() ?: return null
        val total = dict["total"]?.takeIf { it > 0 } ?: return null
        val current = dict["current"] ?: return null
        return current.coerceIn(1, total) to total
    }

    fun clearPageProgress(libraryItemId: String, format: AbsEbookFormat) {
        val (account, userId) = requireSession() ?: return
        pageProgressFile(account, userId, libraryItemId, format).delete()
    }

    // MARK: - Lesefortschritt (Bruchteil)

    /**
     * On-Device-Hilfs-Fortschritt (0…1) — ergänzt Server-`ebookProgress`. [markFinished] nur bei
     * explizitem „Mark as read“: dann bleibt der Stand gegen niedrigere Werte geschützt.
     */
    fun saveProgressFraction(fraction: Double, libraryItemId: String, markFinished: Boolean = false, now: Long = System.currentTimeMillis()) {
        val (account, userId) = requireSession() ?: return
        val id = libraryItemId.swiftTrim()
        if (id.isEmpty()) return
        val incoming = fraction.coerceIn(0.0, 1.0)
        val wasMarkedFinished = isMarkedFinished(id)
        if (!markFinished && wasMarkedFinished && incoming < 0.995) return
        val payload = mapOf(
            "fraction" to incoming,
            "updatedAt" to now.toDouble(),
            "finished" to if (markFinished || (wasMarkedFinished && incoming >= 0.995)) 1.0 else 0.0,
        )
        writeAtomically(progressFractionFile(account, userId, id), AbsJson.encoder.encodeToString(doubleMapSerializer, payload).toByteArray())
    }

    /** Alle lokal gespeicherten Lesefortschritte im offenen Bereich — für Continue-reading ohne Server-Zeile. */
    fun inProgressLibraryItemIds(minFraction: Double = 0.005, maxFraction: Double = 0.995): List<String> {
        val (account, userId) = requireSession() ?: return emptyList()
        val suffix = ".ebook_fraction.json"
        val files = readingProgressDir(account, userId).listFiles() ?: return emptyList()
        return files.mapNotNull { f ->
            if (!f.name.endsWith(suffix)) return@mapNotNull null
            val itemId = f.name.removeSuffix(suffix).swiftTrim()
            if (itemId.isEmpty()) return@mapNotNull null
            val fraction = loadProgressFraction(itemId) ?: return@mapNotNull null
            itemId.takeIf { fraction > minFraction && fraction < maxFraction }
        }
    }

    private fun loadFractionDict(libraryItemId: String): Map<String, Double>? {
        val (account, userId) = requireSession() ?: return null
        val id = libraryItemId.swiftTrim()
        if (id.isEmpty()) return null
        return runCatching {
            AbsJson.decoder.decodeFromString(doubleMapSerializer, progressFractionFile(account, userId, id).readText())
        }.getOrNull()
    }

    /** Explizit „als gelesen markiert“ (nicht nur ≥ 99,5 % gelesen). */
    fun isMarkedFinished(libraryItemId: String): Boolean {
        val dict = loadFractionDict(libraryItemId) ?: return false
        dict["finished"]?.let { return it >= 1 }
        // Altbestand ohne Flag: „Mark as read“ schrieb exakt 1.0.
        return (dict["fraction"] ?: 0.0) >= 0.9999
    }

    fun loadProgressFraction(libraryItemId: String): Double? {
        val f = loadFractionDict(libraryItemId)?.get("fraction") ?: return null
        if (!f.isFinite() || f <= 0.001) return null
        return f.coerceIn(0.0, 1.0)
    }

    fun clearProgressFraction(libraryItemId: String) {
        val (account, userId) = requireSession() ?: return
        val id = libraryItemId.swiftTrim()
        if (id.isEmpty()) return
        progressFractionFile(account, userId, id).delete()
    }

    /** iOS: `Data.write(to:options: .atomic)` — temporär schreiben, dann umbenennen. */
    private fun writeAtomically(target: File, bytes: ByteArray) {
        runCatching {
            target.parentFile?.mkdirs()
            val tmp = File(target.parentFile, ".${target.name}.tmp")
            tmp.writeBytes(bytes)
            if (!tmp.renameTo(target)) {
                target.delete()
                tmp.renameTo(target)
            }
        }
    }
}

/** iOS: `EbookPageDisplayInfo` — Seitenanzeige für eBook-Listenkarten. */
data class EbookPageDisplayInfo(val current: Int?, val total: Int) {
    val coverLabel: String get() = if (current != null && current > 0) "$current/$total" else "$total"
    val metadataLabel: String get() = if (current != null && current > 0) "Page $current of $total" else "$total pages"
}
