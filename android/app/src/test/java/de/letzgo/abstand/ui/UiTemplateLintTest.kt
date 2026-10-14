package de.letzgo.abstand.ui

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * „Lint“ für das Design-System (android/README.md, android/UI_TEMPLATES.txt): Menüs, Dialoge,
 * Sheets, Icon-/Text-Buttons, Chips, Segment-Umschalter und Fortschrittsanzeigen werden nur in
 * `ui/components/` aus Material-Widgets gebaut — überall sonst die `Abstand*`-Vorlagen nutzen.
 * Rohe `Color(0x…)`-Literale gehören nur in Theme.kt/Palette.kt.
 */
class UiTemplateLintTest {

    private val sourceRoot: File = listOf("src/main/java", "app/src/main/java", "android/app/src/main/java")
        .map(::File).firstOrNull { it.isDirectory }
        ?: error("Quellbaum nicht gefunden (Arbeitsverzeichnis: ${File(".").absolutePath})")

    /** Material-/Compose-Widgets, die nur die Vorlagen in ui/components verwenden dürfen. */
    private val templateOnlyWidgets = listOf(
        "DropdownMenu", "DropdownMenuItem", "ExposedDropdownMenuBox",
        "AlertDialog", "BasicAlertDialog", "Dialog", "Popup", "ModalBottomSheet",
        "IconButton", "FilledIconButton", "FilledTonalIconButton", "OutlinedIconButton",
        "TextButton", "OutlinedButton",
        "FilterChip", "AssistChip", "InputChip", "SuggestionChip",
        "SegmentedButton", "SingleChoiceSegmentedButtonRow",
        "LinearProgressIndicator", "CircularProgressIndicator",
        "OutlinedTextField", "TextField",
    )

    private val widgetCall = Regex("(?<![A-Za-z0-9_])(${templateOnlyWidgets.joinToString("|")})\\s*\\(")
    private val colorHexLiteral = Regex("(?<![A-Za-z0-9_])Color\\(\\s*0x")

    private fun kotlinFiles(): List<File> = sourceRoot.walkTopDown().filter { it.isFile && it.extension == "kt" }.toList()

    private fun relative(file: File): String = file.relativeTo(sourceRoot).invariantSeparatorsPath

    /** Quelltextzeilen ohne Kommentare und Imports (KDoc darf die Widgets erwähnen). */
    private fun codeLines(file: File): List<Pair<Int, String>> {
        var inBlockComment = false
        return file.readLines().mapIndexedNotNull { idx, raw ->
            var line = raw
            if (inBlockComment) {
                val end = line.indexOf("*/")
                if (end < 0) return@mapIndexedNotNull null
                line = line.substring(end + 2)
                inBlockComment = false
            }
            val start = line.indexOf("/*")
            if (start >= 0) {
                val end = line.indexOf("*/", start + 2)
                if (end < 0) {
                    inBlockComment = true
                    line = line.substring(0, start)
                } else {
                    line = line.substring(0, start) + line.substring(end + 2)
                }
            }
            line = line.substringBefore("//")
            if (line.trimStart().startsWith("import ")) null else (idx + 1) to line
        }
    }

    @Test
    fun materialChromeOnlyInsideComponents() {
        val files = kotlinFiles()
        assertTrue("Keine Kotlin-Dateien gefunden", files.isNotEmpty())
        val violations = files
            .filterNot { relative(it).startsWith("de/letzgo/abstand/ui/components/") }
            .flatMap { file ->
                codeLines(file).mapNotNull { (line, text) ->
                    widgetCall.find(text)?.let { "${relative(file)}:$line → ${it.groupValues[1]}( — Vorlage aus ui/components nutzen" }
                }
            }
        assertTrue(
            "Rohe Material-Widgets außerhalb von ui/components (siehe android/UI_TEMPLATES.txt):\n" + violations.joinToString("\n"),
            violations.isEmpty(),
        )
    }

    @Test
    fun hexColorLiteralsOnlyInThemeAndPalette() {
        val allowed = setOf("de/letzgo/abstand/ui/Theme.kt", "de/letzgo/abstand/ui/Palette.kt")
        val violations = kotlinFiles()
            .filterNot { relative(it) in allowed }
            .flatMap { file ->
                codeLines(file).mapNotNull { (line, text) ->
                    if (colorHexLiteral.containsMatchIn(text)) "${relative(file)}:$line" else null
                }
            }
        assertTrue(
            "Color(0x…)-Literale außerhalb von Theme.kt/Palette.kt — Farbe in AppTheme/Palette definieren:\n" + violations.joinToString("\n"),
            violations.isEmpty(),
        )
    }
}
