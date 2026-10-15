package de.letzgo.abstand.ui

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * „Lint“ für das Design-System (android/README.md, android/UI_TEMPLATES.txt): Menüs, Dialoge,
 * Sheets, Icon-/Text-Buttons, Chips, Segment-Umschalter und Fortschrittsanzeigen werden nur in
 * `ui/components/` aus Material-Widgets gebaut — überall sonst die `Abstand*`-Vorlagen nutzen.
 * Rohe `Color(0x…)`-Literale gehören nur in Theme.kt/Palette.kt/MaterialScheme.kt. Maße folgen dem Material-3-
 * 4-dp-Raster (`.dp`-Literale außerhalb von ui/components/Theme nur als Vielfache von 4, Haarlinien
 * 0,5/1 dp ausgenommen), Schriftgrößen nur aus `AppType` (keine `fontSize = 17`/`17.sp`-Literale).
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
    private val dpLiteral = Regex("(?<![A-Za-z0-9_.])(\\d+(?:\\.\\d+)?)\\.dp\\b")
    private val spLiteral = Regex("(?<![A-Za-z0-9_.])\\d+(?:\\.\\d+)?\\.sp\\b")
    private val fontSizeLiteral = Regex("fontSize\\s*=\\s*\\d")

    /** Haarlinien (Trenner/Konturen) und 0 dp dürfen vom 4-dp-Raster abweichen. */
    private val allowedOffGridDp = setOf(0.0, 0.5, 1.0)

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
        val allowed = setOf("de/letzgo/abstand/ui/Theme.kt", "de/letzgo/abstand/ui/Palette.kt", "de/letzgo/abstand/ui/MaterialScheme.kt")
        val violations = kotlinFiles()
            .filterNot { relative(it) in allowed }
            .flatMap { file ->
                codeLines(file).mapNotNull { (line, text) ->
                    if (colorHexLiteral.containsMatchIn(text)) "${relative(file)}:$line" else null
                }
            }
        assertTrue(
            "Color(0x…)-Literale außerhalb von Theme.kt/Palette.kt/MaterialScheme.kt — Farbe in AppTheme/Palette definieren:\n" + violations.joinToString("\n"),
            violations.isEmpty(),
        )
    }

    @Test
    fun dpLiteralsFollowMaterialGrid() {
        val exempt = listOf("de/letzgo/abstand/ui/components/", "de/letzgo/abstand/ui/Theme.kt")
        val violations = kotlinFiles()
            .filterNot { f -> exempt.any { relative(f).startsWith(it) } }
            .flatMap { file ->
                codeLines(file).flatMap { (line, text) ->
                    dpLiteral.findAll(text).mapNotNull { m ->
                        val v = m.groupValues[1].toDouble()
                        if (v in allowedOffGridDp || v % 4.0 == 0.0) null else "${relative(file)}:$line → ${m.value}"
                    }.toList()
                }
            }
        assertTrue(
            ".dp-Literale außerhalb des M3-4-dp-Rasters — Token aus AppTheme.Layout nehmen oder auf ein Vielfaches von 4 runden:\n" +
                violations.joinToString("\n"),
            violations.isEmpty(),
        )
    }

    @Test
    fun fontSizesOnlyFromTypeScale() {
        val allowed = setOf("de/letzgo/abstand/ui/Typography.kt")
        val violations = kotlinFiles()
            .filterNot { relative(it) in allowed }
            .flatMap { file ->
                codeLines(file).mapNotNull { (line, text) ->
                    if (fontSizeLiteral.containsMatchIn(text) || spLiteral.containsMatchIn(text)) "${relative(file)}:$line" else null
                }
            }
        assertTrue(
            "Schriftgrößen-Literale außerhalb von Typography.kt — AppType (M3-Typeskala) nutzen:\n" + violations.joinToString("\n"),
            violations.isEmpty(),
        )
    }
}
