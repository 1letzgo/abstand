package de.letzgo.abstand.ui.admin

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import de.letzgo.abstand.data.ServerM4BEncodeJob
import de.letzgo.abstand.model.AdminStore
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.IosType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.TabDestination
import de.letzgo.abstand.ui.TabNavigator
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandCardEmptyState
import de.letzgo.abstand.ui.components.AbstandGroupedCard
import de.letzgo.abstand.ui.components.AbstandInlineNotice
import de.letzgo.abstand.ui.components.ServerAdminSection
import de.letzgo.abstand.ui.components.SettingsCardActionRow
import de.letzgo.abstand.ui.components.SettingsSubpageScaffold
import de.letzgo.abstand.ui.components.abstandCardListRowFrame
import de.letzgo.abstand.ui.medium
import de.letzgo.abstand.ui.semibold
import kotlinx.coroutines.launch

/** iOS: `ServerM4BProgressView` — laufende/letzte M4B-Encodes, Media-Cache leeren. */
data object ServerM4BDestination : TabDestination {
    override val key = "admin/m4b"

    @Composable
    override fun Content(navigator: TabNavigator) = ServerM4BProgressScreen(onBack = { navigator.pop() })
}

@Composable
fun ServerM4BProgressScreen(onBack: () -> Unit, model: AppModel = AppModel.shared, admin: AdminStore = AdminStore.prepared()) {
    val jobs by admin.m4bEncodeJobs.collectAsState()
    val percents by admin.m4bEncodeProgressStore.percentById.collectAsState()
    val reachable by model.session.isNetworkReachable.collectAsState()
    var confirmPurge by remember { mutableStateOf(false) }
    var purgeBusy by remember { mutableStateOf(false) }
    var purgeMessage by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val active = jobs.filter { it.isActive }
    val recent = jobs.filter { !it.isActive }

    SettingsSubpageScaffold(title = "M4B Converter", onBack = onBack) {
        purgeMessage?.let { msg -> item(key = "purgeMessage") { AbstandInlineNotice(msg) } }
        item(key = "mediaCache") {
            ServerAdminSection("Media Cache") {
                AbstandGroupedCard {
                    SettingsCardActionRow(
                        icon = SF.trash,
                        title = "Delete media cache",
                        subtitle = "Clears /metadata/cache/items (originals after M4B merge).",
                        tint = AppTheme.danger,
                        enabled = reachable && !purgeBusy,
                        isBusy = purgeBusy,
                        onClick = { confirmPurge = true },
                    )
                }
            }
        }
        item(key = "conversions") {
            ServerAdminSection("Conversions") {
                if (jobs.isEmpty()) {
                    AbstandGroupedCard {
                        AbstandCardEmptyState(title = "No conversions yet.", message = "Start one from a book’s More menu.")
                    }
                } else {
                    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.stackSpacing)) {
                        (active + recent.take(RECENT_LIMIT)).forEach { job ->
                            AbstandGroupedCard {
                                M4BJobRow(job, percents[job.id], onCancel = { scope.launch { admin.cancelM4BEncode(job.id) } })
                            }
                        }
                        if (recent.isNotEmpty()) {
                            TextButton(
                                onClick = { admin.clearFinishedM4BEncodeJobs() },
                                modifier = Modifier.fillMaxWidth().wrapContentWidth(Alignment.End),
                            ) { Text("Clear finished", style = IosType.subheadline.medium, color = Theme.accent) }
                        }
                    }
                }
            }
        }
    }

    if (confirmPurge) {
        AlertDialog(
            onDismissRequest = { confirmPurge = false },
            title = { Text("Delete media cache?") },
            text = { Text("This removes cached item files on the server (including backed-up originals after M4B conversion).") },
            confirmButton = {
                TextButton(onClick = {
                    confirmPurge = false
                    scope.launch {
                        purgeBusy = true
                        val ok = try { admin.purgeServerItemsMediaCache() } finally { purgeBusy = false }
                        if (ok) purgeMessage = "Media cache purged."
                    }
                }) { Text("Delete", color = AppTheme.danger) }
            },
            dismissButton = { TextButton(onClick = { confirmPurge = false }) { Text("Cancel") } },
        )
    }
}

@Composable
private fun M4BJobRow(job: ServerM4BEncodeJob, percent: Double?, onCancel: () -> Unit) {
    val palette = Theme.palette
    Row(
        Modifier.abstandCardListRowFrame(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.rowSpacing),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.tightSpacing)) {
            Text(job.title, style = IosType.body.medium, color = palette.textPrimary, maxLines = 2)
            Text(job.author, style = IosType.caption, color = palette.textSecondary, maxLines = 1)
            Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.inlineSpacing), verticalAlignment = Alignment.CenterVertically) {
                Text(M4BLogic.statusLabel(job, percent), style = IosType.caption.semibold, color = statusColor(job))
                val message = job.message
                if (!job.isActive && !message.isNullOrEmpty() && message != "Done") {
                    Text(message, style = IosType.caption2, color = palette.textSecondary)
                }
            }
        }
        if (job.isActive) {
            TextButton(onClick = onCancel) { Text("Cancel", style = IosType.subheadline.medium, color = AppTheme.danger) }
        }
    }
}

@Composable
private fun statusColor(job: ServerM4BEncodeJob): Color = when (job.status) {
    ServerM4BEncodeJob.Status.running -> Theme.accent
    ServerM4BEncodeJob.Status.finished -> AppTheme.success
    ServerM4BEncodeJob.Status.failed, ServerM4BEncodeJob.Status.cancelled -> AppTheme.danger
}

/** Reine Texte des M4B-Managers (testbar). */
object M4BLogic {
    /** iOS: `jobStatusLabel` — „Converting 42%“ / „Converting…“ / Endstatus. */
    fun statusLabel(job: ServerM4BEncodeJob, percent: Double?): String = when (job.status) {
        ServerM4BEncodeJob.Status.running -> if (percent != null) "Converting ${Math.round(percent)}%" else "Converting…"
        ServerM4BEncodeJob.Status.finished -> "Finished"
        ServerM4BEncodeJob.Status.failed -> "Failed"
        ServerM4BEncodeJob.Status.cancelled -> "Cancelled"
    }
}

/** iOS: `recentJobs.prefix(12)`. */
private const val RECENT_LIMIT = 12
