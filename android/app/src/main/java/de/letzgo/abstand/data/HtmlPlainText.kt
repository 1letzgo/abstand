package de.letzgo.abstand.data

// iOS: HTMLPlainText.swift

private val brTag = Regex("<br>", RegexOption.IGNORE_CASE)
private val brSelfClosing = Regex("<br/>", RegexOption.IGNORE_CASE)
private val pClose = Regex("</p>", RegexOption.IGNORE_CASE)
private val anyTag = Regex("<[^>]+>")

/**
 * iOS: `absPlainText(fromHTML:)` — entfernt HTML und bereinigt typische Podcast-/RSS-Floskeln:
 * viele Leerzeilen → höchstens eine Leerzeile zwischen Absätzen.
 */
fun absPlainText(html: String?): String {
    var s = html?.swiftTrim() ?: return ""
    if (s.isEmpty()) return ""
    s = s.replace("\r\n", "\n")
    s = s.replace("\r", "\n")
    s = s.replace(brTag, "\n")
    s = s.replace(brSelfClosing, "\n")
    s = s.replace(pClose, "\n\n")
    s = s.replace(anyTag, "")
    s = absCollapseExcessBlankLines(s)
    return s.swiftTrim()
}

/** Trimmt jede Zeile und lässt zwischen Inhaltszeilen maximal **eine** Leerzeile zu (zwei `\n` hintereinander). */
private fun absCollapseExcessBlankLines(text: String): String {
    // iOS: `.whitespaces` — innerhalb einer Zeile gibt es keine Umbrüche mehr.
    val lines = text.split("\n").map { line -> line.trim { it.isWhitespace() || it == ' ' } }
    val out = ArrayList<String>(lines.size)
    for (line in lines) {
        if (line.isEmpty()) {
            if (out.lastOrNull()?.isEmpty() == true) continue
            out.add("")
        } else {
            out.add(line)
        }
    }
    while (out.firstOrNull()?.isEmpty() == true) out.removeAt(0)
    while (out.lastOrNull()?.isEmpty() == true) out.removeAt(out.size - 1)
    return out.joinToString("\n")
}
