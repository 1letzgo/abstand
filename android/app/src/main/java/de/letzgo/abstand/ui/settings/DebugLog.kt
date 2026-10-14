package de.letzgo.abstand.ui.settings

import android.content.Context
import android.content.Intent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.IosType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandCardEmptyState
import de.letzgo.abstand.ui.components.AbstandGroupedCard
import de.letzgo.abstand.ui.components.AbstandProminentButton
import de.letzgo.abstand.ui.components.ServerAdminSection
import de.letzgo.abstand.ui.components.SettingsCardDivider
import de.letzgo.abstand.ui.components.SettingsCardInfoRow
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.util.UUID

/**
 * iOS: `DebugLogCollector` — In-Memory-Ringpuffer (500 Einträge) für Felddiagnose, bewusst auch im
 * Release aktiv. Kein beobachtbarer Zustand: die Export-Ansicht liest per Snapshot.
 */
object DebugLogCollector {
    data class Entry(val id: String = UUID.randomUUID().toString(), val timestampMillis: Long, val message: String)

    @Volatile var isCollecting = true
    private const val MAX_ENTRIES = 500
    private val buffer = ArrayDeque<Entry>()

    /** iOS: `log(_:)` mit `@autoclosure` — die Message wird nur bei aktivem Sammeln gebaut. */
    fun log(message: () -> String) {
        if (!isCollecting) return
        val entry = Entry(timestampMillis = System.currentTimeMillis(), message = message())
        synchronized(buffer) {
            buffer.addLast(entry)
            while (buffer.size > MAX_ENTRIES) buffer.removeFirst()
        }
    }

    fun log(message: String) = log { message }

    /** Snapshot (Kopie). */
    val entries: List<Entry> get() = synchronized(buffer) { buffer.toList() }

    /** iOS: `exportText` — ISO-8601 mit Millisekunden + Message, eine Zeile pro Eintrag. */
    val exportText: String get() = exportText(entries)

    fun exportText(entries: List<Entry>): String =
        entries.joinToString("\n") { "${DateTimeFormatter.ISO_INSTANT.format(Instant.ofEpochMilli(it.timestampMillis))} ${it.message}" }

    fun clear() = synchronized(buffer) { buffer.clear() }
}

/** Teilen per System-Sheet (iOS: `ShareSheet` / `UIActivityViewController`). */
fun shareDebugLog(context: Context, text: String) {
    val send = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_SUBJECT, "abstand debug log")
        putExtra(Intent.EXTRA_TEXT, text)
    }
    context.startActivity(Intent.createChooser(send, "Export").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
}

/** iOS: `DebugLogExportView` — Sektion „Debug Log“. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun DebugLogSection() {
    val context = LocalContext.current
    val palette = Theme.palette
    var entries by remember { mutableStateOf<List<DebugLogCollector.Entry>>(emptyList()) }
    LaunchedEffect(Unit) { entries = DebugLogCollector.entries }
    ServerAdminSection("Debug Log") {
        AbstandGroupedCard {
            SettingsCardInfoRow(
                icon = SF.docTextMagnifyingglass,
                title = "Collected entries",
                subtitle = if (entries.size == 1) "1 entry" else "${entries.size} entries",
            )
            SettingsCardDivider()
            // Drei gleichrangige, kurze Aktionen nebeneinander (wie iOS).
            FlowRow(
                Modifier.fillMaxWidth().padding(vertical = AppTheme.Layout.rowVerticalPadding),
                horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing),
                verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.stackSpacing),
            ) {
                AbstandProminentButton(
                    text = "Export", icon = SF.squareAndArrowUp, enabled = entries.isNotEmpty(),
                    onClick = { shareDebugLog(context, DebugLogCollector.exportText) },
                )
                AbstandProminentButton(text = "Refresh", icon = SF.arrowClockwise, onClick = { entries = DebugLogCollector.entries })
                // Destruktiv: Prominent-Stil mit Danger statt Akzent (iOS: `themeAccent` lokal auf Danger).
                AbstandProminentButton(
                    text = "Clear", icon = SF.trash, enabled = entries.isNotEmpty(), destructive = true,
                    onClick = { DebugLogCollector.clear(); entries = emptyList() },
                )
            }
        }
        if (entries.isEmpty()) {
            AbstandGroupedCard {
                AbstandCardEmptyState(title = "No log entries yet.", message = "Entries appear here while the app runs.")
            }
        } else {
            AbstandGroupedCard {
                Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.tightSpacing)) {
                    entries.takeLast(LAST_VISIBLE).forEach { entry ->
                        Text(
                            entry.message,
                            style = IosType.caption.copy(fontFamily = FontFamily.Monospace),
                            color = palette.textSecondary,
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                }
            }
        }
    }
}

/** iOS: `entries.suffix(50)`. */
private const val LAST_VISIBLE = 50
