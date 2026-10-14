package de.letzgo.abstand.logic

import java.text.Normalizer

/**
 * Nachbau der Foundation-/Swift-String-Semantik, die die Abgleich-Logik braucht (iOS: `String`,
 * `Character`, `CharacterSet`, `String.folding(options:locale:)`). Reine JVM-APIs, damit dieselben
 * Ergebnisse in JUnit und auf dem Gerät entstehen.
 *
 * Genauigkeit gegen Foundation wird mit `shared/fixtures/alignment/unicode_tables.json` (aus Swift
 * erzeugt) geprüft — Abweichungen bleiben nur bei Zeichen, die die Unicode-Version des JDK anders
 * kennt als macOS/iOS.
 */
object FoundationText {

    // MARK: Zeichenklassen

    /** Swift `Character.isLetter || isNumber` für den ersten Skalar (`isAlphabetic` / `numericType != nil`). */
    fun isWordScalar(cp: Int): Boolean {
        if (Character.isAlphabetic(cp)) return true
        // Seit Unicode 14 `Other_Alphabetic` (JDK 17 kennt Unicode 13).
        if (cp in 0x0363..0x036F || cp in 0x1DD3..0x1DE6 || cp == 0x0C04 || cp == 0x0F82 || cp == 0x0F83 || cp == 0x11080 || cp == 0x11081) return true
        return when (Character.getType(cp).toByte()) {
            Character.DECIMAL_DIGIT_NUMBER, Character.LETTER_NUMBER, Character.OTHER_NUMBER -> true
            // Han-Zahlzeichen (kPrimaryNumeric) sind ohnehin alphabetisch.
            else -> false
        }
    }

    /** `CharacterSet.alphanumerics`: Kategorien L*, M*, N* (Apple ohne Tangut). */
    fun isAlphanumeric(cp: Int): Boolean = if (cp in 0x17000..0x187FF || cp in 0x18D00..0x18D08) false else when (Character.getType(cp).toByte()) {
        Character.UPPERCASE_LETTER, Character.LOWERCASE_LETTER, Character.TITLECASE_LETTER,
        Character.MODIFIER_LETTER, Character.OTHER_LETTER,
        Character.NON_SPACING_MARK, Character.COMBINING_SPACING_MARK, Character.ENCLOSING_MARK,
        Character.DECIMAL_DIGIT_NUMBER, Character.LETTER_NUMBER, Character.OTHER_NUMBER -> true
        else -> false
    }

    /** `CharacterSet.punctuationCharacters`: Kategorie P*. */
    fun isPunctuation(cp: Int): Boolean = when (Character.getType(cp).toByte()) {
        Character.CONNECTOR_PUNCTUATION, Character.DASH_PUNCTUATION, Character.START_PUNCTUATION,
        Character.END_PUNCTUATION, Character.INITIAL_QUOTE_PUNCTUATION, Character.FINAL_QUOTE_PUNCTUATION,
        Character.OTHER_PUNCTUATION -> true
        else -> false
    }

    /** Unicode-Eigenschaft `White_Space` (Swift `Character.isWhitespace` am ersten Skalar). */
    fun isWhiteSpaceScalar(cp: Int): Boolean = when (cp) {
        in 0x09..0x0D, 0x20, 0x85, 0xA0, 0x1680, in 0x2000..0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000 -> true
        else -> false
    }

    /** `CharacterSet.whitespacesAndNewlines`: Kategorie Z*, U+0009–U+000D, U+0085. */
    fun isWhitespaceOrNewline(cp: Int): Boolean {
        if (cp in 0x09..0x0D || cp == 0x85) return true
        return when (Character.getType(cp).toByte()) {
            Character.SPACE_SEPARATOR, Character.LINE_SEPARATOR, Character.PARAGRAPH_SEPARATOR -> true
            else -> false
        }
    }

    /** Swift `trimmingCharacters(in: .whitespacesAndNewlines)`. */
    fun trimmingWhitespacesAndNewlines(s: String): String = trimming(s, ::isWhitespaceOrNewline)

    /** `trimmingCharacters(in:)` mit beliebiger Skalar-Menge. */
    fun trimming(s: String, predicate: (Int) -> Boolean): String {
        var start = 0
        var end = s.length
        while (start < end) {
            val cp = s.codePointAt(start)
            if (!predicate(cp)) break
            start += Character.charCount(cp)
        }
        while (end > start) {
            val cp = s.codePointBefore(end)
            if (!predicate(cp)) break
            end -= Character.charCount(cp)
        }
        return s.substring(start, end)
    }

    // MARK: Grapheme-Cluster (Swift `Character`)

    private val otherGraphemeExtend = intArrayOf(
        0x09BE, 0x09D7, 0x0B3E, 0x0B57, 0x0BBE, 0x0BD7, 0x0CC2, 0x0CD5, 0x0CD6, 0x0D3E, 0x0D57, 0x0DCF,
        0x0DDF, 0x1B35, 0x200C, 0x302E, 0x302F, 0xFF9E, 0xFF9F, 0x1133E, 0x11357, 0x114B0, 0x114BD,
        0x115AF, 0x11930, 0x1D165, 0x1D16E, 0x1D16F, 0x1D170, 0x1D171, 0x1D172,
    )

    /** Unicode `Grapheme_Extend` (Mn, Me, Other_Grapheme_Extend) — CF `kCFUniCharGraphemeExtendCharacterSet`. */
    fun isGraphemeExtend(cp: Int): Boolean {
        val type = Character.getType(cp).toByte()
        if (type == Character.NON_SPACING_MARK || type == Character.ENCLOSING_MARK) return true
        if (cp in 0xE0020..0xE007F) return true
        return otherGraphemeExtend.binarySearch(cp) >= 0
    }

    private fun isPrepend(cp: Int): Boolean = when (cp) {
        in 0x0600..0x0605, 0x06DD, 0x070F, 0x0890, 0x0891, 0x08E2, 0x0D4E, 0x110BD, 0x110CD,
        0x111C2, 0x111C3, 0x1193F, 0x11941, 0x11A3A, in 0x11A84..0x11A89, 0x11D46, 0x11F02 -> true
        else -> false
    }

    private enum class Hangul { L, V, T, LV, LVT, NONE }

    private fun hangul(cp: Int): Hangul = when (cp) {
        in 0x1100..0x115F, in 0xA960..0xA97C -> Hangul.L
        in 0x1160..0x11A7, in 0xD7B0..0xD7C6 -> Hangul.V
        in 0x11A8..0x11FF, in 0xD7CB..0xD7FB -> Hangul.T
        in 0xAC00..0xD7A3 -> if ((cp - 0xAC00) % 28 == 0) Hangul.LV else Hangul.LVT
        else -> Hangul.NONE
    }

    private fun isRegionalIndicator(cp: Int) = cp in 0x1F1E6..0x1F1FF

    /** `Indic_Conjunct_Break=Linker` (Virama). */
    private fun isConjunctLinker(cp: Int) = cp == 0x094D || cp == 0x09CD || cp == 0x0ACD || cp == 0x0B4D || cp == 0x0C4D || cp == 0x0D4D

    /** `Indic_Conjunct_Break=Consonant` (Unicode 15.1). */
    private fun isConjunctConsonant(cp: Int): Boolean = when (cp) {
        in 0x0915..0x0939, in 0x0958..0x095F, in 0x0978..0x097F,
        in 0x0995..0x09A8, in 0x09AA..0x09B0, 0x09B2, in 0x09B6..0x09B9, 0x09DC, 0x09DD, 0x09DF, 0x09F0, 0x09F1,
        in 0x0A95..0x0AA8, in 0x0AAA..0x0AB0, 0x0AB2, 0x0AB3, in 0x0AB5..0x0AB9, 0x0AF9,
        in 0x0B15..0x0B28, in 0x0B2A..0x0B30, 0x0B32, 0x0B33, in 0x0B35..0x0B39, 0x0B5C, 0x0B5D, 0x0B5F, 0x0B71,
        in 0x0C15..0x0C28, in 0x0C2A..0x0C39, in 0x0C58..0x0C5A,
        in 0x0D15..0x0D3A -> true
        else -> false
    }

    /** Kein Umbruch zwischen [prev] und [next] (vereinfachte UAX #29-Regeln GB3–GB9b, GB12/13). */
    private fun continuesCluster(prev: Int, next: Int, riCount: Int): Boolean {
        if (prev == 0x0D && next == 0x0A) return true
        if (prev == 0x0D || prev == 0x0A || next == 0x0D || next == 0x0A) return false
        if (Character.getType(prev).toByte() == Character.CONTROL || Character.getType(next).toByte() == Character.CONTROL) return false
        val hp = hangul(prev)
        val hn = hangul(next)
        if (hp == Hangul.L && (hn == Hangul.L || hn == Hangul.V || hn == Hangul.LV || hn == Hangul.LVT)) return true
        if ((hp == Hangul.LV || hp == Hangul.V) && (hn == Hangul.V || hn == Hangul.T)) return true
        if ((hp == Hangul.LVT || hp == Hangul.T) && hn == Hangul.T) return true
        if (isGraphemeExtend(next) || next == 0x200D || next in 0x1F3FB..0x1F3FF) return true
        if (Character.getType(next).toByte() == Character.COMBINING_SPACING_MARK || next == 0x0E33 || next == 0x0EB3) return true
        if (isPrepend(prev)) return true
        if (isRegionalIndicator(prev) && isRegionalIndicator(next)) return riCount % 2 == 1
        // GB11 (Emoji-ZWJ-Folgen): ZWJ + Bildzeichen.
        if (prev == 0x200D && Character.getType(next).toByte() == Character.OTHER_SYMBOL) return true
        return false
    }

    /** UTF-16-Startindizes der Grapheme-Cluster (letzter Eintrag = `s.length`). */
    fun clusterBoundaries(s: CharSequence): IntArray {
        val out = ArrayList<Int>()
        var i = 0
        var prev = -1
        var riCount = 0
        // GB9c: 0 = kein Konsonant, 1 = Konsonant (+ Extend), 2 = Konsonant + Virama
        var conjunct = 0
        while (i < s.length) {
            val cp = Character.codePointAt(s, i)
            val joinsConjunct = conjunct == 2 && isConjunctConsonant(cp)
            if (prev < 0 || (!joinsConjunct && !continuesCluster(prev, cp, riCount))) {
                out.add(i)
                riCount = 0
            }
            riCount = if (isRegionalIndicator(cp)) riCount + 1 else 0
            conjunct = when {
                isConjunctConsonant(cp) -> 1
                conjunct >= 1 && isConjunctLinker(cp) -> 2
                conjunct >= 1 && (isGraphemeExtend(cp) || cp == 0x200D) -> conjunct
                else -> 0
            }
            prev = cp
            i += Character.charCount(cp)
        }
        out.add(s.length)
        return out.toIntArray()
    }

    /** Swift `String.count`. */
    fun characterCount(s: CharSequence): Int = if (s.isEmpty()) 0 else clusterBoundaries(s).size - 1

    /** Swift `String.last` als Teilstring (oder `null`). */
    fun lastCharacter(s: String): String? {
        if (s.isEmpty()) return null
        val b = clusterBoundaries(s)
        return s.substring(b[b.size - 2], s.length)
    }

    /** Swift `Character.isWhitespace` (erster Skalar). */
    fun characterIsWhitespace(character: String): Boolean =
        character.isNotEmpty() && isWhiteSpaceScalar(character.codePointAt(0))

    /** Swift `allSatisfy(\.isWhitespace)` über die Characters. */
    fun allWhitespace(s: String): Boolean {
        val b = clusterBoundaries(s)
        for (k in 0 until b.size - 1) if (!isWhiteSpaceScalar(s.codePointAt(b[k]))) return false
        return true
    }

    // MARK: Faltung (CFStringFold, [.caseInsensitive, .diacriticInsensitive], locale nil)

    private fun nfd(cp: Int): String = Normalizer.normalize(String(Character.toChars(cp)), Normalizer.Form.NFD)

    private fun isCanonicalDecomposable(cp: Int): Boolean {
        val s = String(Character.toChars(cp))
        return !Normalizer.isNormalized(s, Normalizer.Form.NFD)
    }

    /** Volle Case-Folding-Abbildung eines Skalars (`kCFUniCharCaseFold`); `null` = keine Änderung. */
    fun caseFold(cp: Int): IntArray? {
        when (cp) {
            0x0131, in 0x1C80..0x1C88 -> return null
            0x1E9E -> return intArrayOf(0x73, 0x73)
        }
        val upper = String(Character.toChars(cp)).uppercase(java.util.Locale.ROOT)
        val sb = StringBuilder()
        var i = 0
        while (i < upper.length) {
            val u = upper.codePointAt(i)
            sb.append(String(Character.toChars(u)).lowercase(java.util.Locale.ROOT))
            i += Character.charCount(u)
        }
        val folded = sb.toString().codePoints().toArray()
        if (folded.size == 1 && folded[0] == cp) return null
        return folded
    }

    /**
     * Ein Cluster ab [index]: Rückgabe der gefalteten Skalare (leer = unverändert) und der verbrauchten
     * UTF-16-Länge — 1:1 nach `__CFStringFoldCharacterClusterAtIndex`.
     */
    private fun foldCluster(s: String, index: Int, out: ArrayList<Int>): Int {
        out.clear()
        var character = s.codePointAt(index)
        var current = index + Character.charCount(character)
        var filled = 0

        if (character < 0x80) {
            if (character in 'A'.code..'Z'.code) {
                character += 'a'.code - 'A'.code
                out.add(character)
                filled = 1
            }
        } else {
            // Zerlegen
            if (isCanonicalDecomposable(character)) {
                val original = character
                val decomposed = nfd(character).codePoints().toArray()
                character = decomposed[0]
                if (character < 0x0510) {
                    out.add(character)
                    filled = 1 // Lateinisch/Griechisch/Kyrillisch: nur der Grundbuchstabe
                } else {
                    character = original
                    filled = 0
                }
            }
            // Groß/klein falten
            val filterNonBase = character < 0x0510
            val folded = caseFold(character)
            if (folded != null) {
                if (filled > 0) filled--
                out.clear()
                for (c in folded) {
                    character = c
                    if (!filterNonBase || !isGraphemeExtend(c)) {
                        out.add(c)
                        filled++
                    }
                }
            }
        }

        // Folgende Kombinationszeichen einsammeln
        var doFill = character >= 0x0510
        if (filled == 0) {
            out.clear()
            out.add(character)
            if (doFill) {
                if (current < s.length) {
                    val nonBase = s.codePointAt(current)
                    if (isGraphemeExtend(nonBase)) {
                        filled = 1
                        if (nonBase > 0x050F) {
                            appendDecomposed(nonBase, out)
                            filled = out.size
                        }
                        current += Character.charCount(nonBase)
                    } else {
                        doFill = false
                    }
                } else {
                    doFill = false
                }
            }
        }
        while (current < s.length) {
            val c = s.codePointAt(current)
            if (!isGraphemeExtend(c)) break
            if (doFill) {
                appendDecomposed(c, out)
                filled = out.size
            } else if (filled == 0) {
                filled = 1
            }
            current += Character.charCount(c)
        }
        if (filled == 0) return 0
        while (out.size > filled) out.removeAt(out.size - 1)
        if (out.size > 1) prioritySortTrailingMarks(out)
        return current - index
    }

    private fun appendDecomposed(cp: Int, out: ArrayList<Int>) {
        if (isCanonicalDecomposable(cp)) nfd(cp).codePoints().forEach { out.add(it) } else out.add(cp)
    }

    /** Kanonische Kombinationsklasse 1 (Overlay) — Referenz für [cccComparison]. */
    private val ccc1 = intArrayOf(
        0x0334, 0x0335, 0x0336, 0x0337, 0x0338, 0x1CD4, 0x1CE2, 0x1CE3, 0x1CE4, 0x1CE5, 0x1CE6, 0x1CE7, 0x1CE8,
        0x20D2, 0x20D3, 0x20D8, 0x20D9, 0x20DA, 0x20E5, 0x20E6, 0x20EA, 0x20EB, 0x10A39, 0x16AF0, 0x16AF1,
        0x16AF2, 0x16AF3, 0x16AF4, 0x1BC9E, 0x1D167, 0x1D168, 0x1D169,
    )

    private fun reorders(a: Int, b: Int): Boolean {
        val s = StringBuilder().appendCodePoint(a).appendCodePoint(b).toString()
        val n = Normalizer.normalize(s, Normalizer.Form.NFD)
        return n == StringBuilder().appendCodePoint(b).appendCodePoint(a).toString()
    }

    /** 0, 1 oder „> 1" (2) — die JVM hat keine API für die Kombinationsklasse. */
    private fun cccBucket(cp: Int): Int = when {
        ccc1.binarySearch(cp) >= 0 -> 1
        reorders(cp, 0x0334) -> 2
        else -> 0
    }

    /** Vergleich nach kanonischer Kombinationsklasse (über die NFD-Umordnung bestimmt). */
    private fun cccComparison(a: Int, b: Int): Int {
        val ba = cccBucket(a)
        val bb = cccBucket(b)
        if (ba != bb || ba < 2) return ba.compareTo(bb)
        if (reorders(a, b)) return 1
        if (reorders(b, a)) return -1
        return 0
    }

    /** `CFUniCharPrioritySort` über die Marken am Ende: stabil nach Kombinationsklasse (0 zuerst). */
    private fun prioritySortTrailingMarks(out: ArrayList<Int>) {
        var start = out.size - 1
        while (start > 0 && isGraphemeExtend(out[start])) start--
        if (out.size - start <= 1) return
        // Stabile Einfügesortierung wie CF (Bubble nach Priorität).
        for (i in start + 1 until out.size) {
            val v = out[i]
            var j = i - 1
            while (j >= start && cccComparison(out[j], v) > 0) {
                out[j + 1] = out[j]
                j--
            }
            out[j + 1] = v
        }
    }

    /** Swift `folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)`. */
    fun foldCaseAndDiacritics(s: String): String {
        val sb = StringBuilder(s.length)
        val buffer = ArrayList<Int>(8)
        var i = 0
        while (i < s.length) {
            val consumed = foldCluster(s, i, buffer)
            if (consumed > 0) {
                for (c in buffer) sb.appendCodePoint(c)
                i += consumed
            } else {
                // Unverändert: eine UTF-16-Einheit weiter (wie CFStringFold)
                sb.append(s[i])
                i += 1
            }
        }
        return sb.toString()
    }
}
