package de.letzgo.abstand.ui.settings

import android.text.format.Formatter
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import de.letzgo.abstand.data.AbsDownloadManifest
import de.letzgo.abstand.downloads.DownloadManager
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.model.AppSettings
import de.letzgo.abstand.model.SessionStore
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.IosType
import de.letzgo.abstand.ui.LocalTabNavigator
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.TabDestination
import de.letzgo.abstand.ui.TabNavigator
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandCardEmptyState
import de.letzgo.abstand.ui.components.AbstandDialog
import de.letzgo.abstand.ui.components.AbstandGroupedCard
import de.letzgo.abstand.ui.components.CoverImage
import de.letzgo.abstand.ui.components.ServerAdminSection
import de.letzgo.abstand.ui.components.SettingsCardActionRow
import de.letzgo.abstand.ui.components.SettingsCardIcon
import de.letzgo.abstand.ui.components.SettingsCardInfoRow
import de.letzgo.abstand.ui.components.SettingsCardNavRow
import de.letzgo.abstand.ui.components.SettingsCardToggleRow
import de.letzgo.abstand.ui.components.SettingsSubpageScaffold
import de.letzgo.abstand.ui.medium
import java.io.File
import java.text.DateFormat
import java.util.Date
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** iOS: Hub-Bereich „Downloads“ — Sektionen „Downloads“ und „Cache“. */
fun LazyListScope.settingsDownloadsSections(session: SessionStore) {
    item(key = "downloads") { SettingsDownloadsSection(session) }
    item(key = "cache") { SettingsCacheSection(session) }
}

@Composable
private fun SettingsDownloadsSection(session: SessionStore) {
    val onWifi by AppSettings.smartDownloadOnWiFi.collectAsState()
    val removeFinished by AppSettings.smartDownloadRemoveWhenFinished.collectAsState()
    val active by DownloadManager.activeItemId.collectAsState()
    val queued by DownloadManager.queuedItemIds.collectAsState()
    val completed by DownloadManager.completedDownloadCount.collectAsState()
    val libraries by session.libraries.collectAsState()
    var savedCount by remember { mutableStateOf(0) }
    LaunchedEffect(active, queued, completed, libraries) {
        savedCount = withContext(Dispatchers.IO) { DownloadsLogic.savedDownloads(session).size }
    }
    val navigator = LocalTabNavigator.current
    ServerAdminSection("Downloads") {
        AbstandGroupedCard {
            SettingsCardToggleRow(
                icon = SF.arrowDownCircle,
                title = "Auto download on Wi‑Fi",
                checked = onWifi,
                onCheckedChange = { AppSettings.setSmartDownloadOnWiFi(it) },
            )
        }
        AbstandGroupedCard {
            SettingsCardToggleRow(
                icon = SF.checkmarkCircle,
                title = "Remove download when finished",
                checked = removeFinished,
                onCheckedChange = { AppSettings.setSmartDownloadRemoveWhenFinished(it) },
            )
        }
        AbstandGroupedCard {
            SettingsCardNavRow(
                icon = SF.listBulletBelowRectangle,
                title = "Manage downloads",
                subtitle = DownloadsLogic.manageDownloadsSubtitle(savedCount, if (active != null) 1 else 0, queued.size),
                onClick = { navigator?.push(ManageDownloadsDestination) },
            )
        }
    }
}

@Composable
private fun SettingsCacheSection(session: SessionStore) {
    val context = LocalContext.current
    val revision by session.coverImageCacheRevision.collectAsState()
    var bytes by remember { mutableLongStateOf(0L) }
    val hasAccount = session.cacheAccountDir() != null
    LaunchedEffect(revision) { bytes = withContext(Dispatchers.IO) { session.coverImageCacheByteCount() } }
    val label = when {
        !hasAccount -> "Cover art is cached after you sign in."
        bytes == 0L -> "No cover cache in use."
        else -> Formatter.formatFileSize(context, bytes)
    }
    ServerAdminSection("Cache") {
        AbstandGroupedCard {
            SettingsCardActionRow(
                icon = SF.photoOnRectangleAngled,
                title = "Clear cover cache",
                subtitle = label,
                trailingIcon = SF.trash,
                enabled = hasAccount,
                onClick = { session.clearCoverImageCache() },
            )
        }
    }
}

/** iOS: `DownloadManageRow` — gespeicherter Download (Manifest + Ordnergröße). */
data class DownloadManageRow(
    val storageId: String,
    val libraryItemId: String,
    val episodeId: String?,
    val title: String,
    val author: String?,
    val savedAtEpoch: Double,
    val totalDuration: Double?,
    val byteCount: Long,
) {
    val durationLabel: String? get() = totalDuration?.takeIf { it > 0 }?.let { DownloadsLogic.formatDuration(it) }

    val savedLabel: String
        get() = if (savedAtEpoch <= 0) "" else DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date((savedAtEpoch * 1000).toLong()))
}

/** Reine Hilfen der Download-Verwaltung (testbar). */
object DownloadsLogic {
    /** iOS: `manageDownloadsSubtitle` — „3 saved · 1 pending“. */
    fun manageDownloadsSubtitle(saved: Int, active: Int, queued: Int): String? {
        if (saved == 0 && active == 0 && queued == 0) return null
        val parts = mutableListOf<String>()
        if (saved > 0) parts += "$saved saved"
        val inFlight = active + queued
        if (inFlight > 0) parts += "$inFlight pending"
        return parts.joinToString(" · ").ifEmpty { null }
    }

    /** iOS: `DownloadManageRow.formatDuration` — „10h 23m“ bzw. „45m“. */
    fun formatDuration(seconds: Double): String {
        val total = Math.round(seconds).toInt()
        val h = total / 3600
        val m = (total % 3600) / 60
        return if (h > 0) "${h}h ${m}m" else "${m}m"
    }

    /**
     * Vereinfachtes iOS `downloadManifestBelongsToActiveAccount`: Manifest ohne Bibliothek gehört
     * immer dazu; sonst nur Bibliotheken dieses Servers (solange bekannt).
     */
    fun belongsToAccount(manifest: AbsDownloadManifest, libraryIds: Set<String>): Boolean {
        val lid = manifest.libraryId?.trim().orEmpty()
        if (lid.isEmpty() || libraryIds.isEmpty()) return true
        return lid in libraryIds
    }

    fun folderSize(dir: File): Long = dir.walkTopDown().filter { it.isFile && !it.name.startsWith(".") }.sumOf { it.length() }

    /** iOS: `reload()` — alle Manifeste, nach Speicherdatum (neu zuerst). Blockierend (IO). */
    fun savedDownloads(session: SessionStore): List<DownloadManageRow> {
        val libIds = session.libraries.value.map { it.id }.toSet()
        return DownloadManager.scanDownloads()
            .filter { belongsToAccount(it.manifest, libIds) }
            .map { d ->
                DownloadManageRow(
                    storageId = d.storageItemId,
                    libraryItemId = d.manifest.libraryItemId,
                    episodeId = d.manifest.episodeId,
                    title = d.manifest.displayTitle ?: "Unknown title",
                    author = d.manifest.displayAuthor,
                    savedAtEpoch = d.manifest.savedAtEpoch,
                    totalDuration = d.manifest.totalDuration,
                    byteCount = folderSize(d.folder),
                )
            }
            .sortedByDescending { it.savedAtEpoch }
    }
}

/** iOS: `SettingsDownloadsManageView` — laufende/wartende und gespeicherte Downloads. */
data object ManageDownloadsDestination : TabDestination {
    override val key = "settings/manageDownloads"

    @Composable
    override fun Content(navigator: TabNavigator) = SettingsDownloadsManageScreen(onBack = { navigator.pop() })
}

@Composable
fun SettingsDownloadsManageScreen(onBack: () -> Unit, model: AppModel = AppModel.shared) {
    val session = model.session
    val context = LocalContext.current
    val active by DownloadManager.activeItemId.collectAsState()
    val queued by DownloadManager.queuedItemIds.collectAsState()
    val progress by DownloadManager.progress.collectAsState()
    val completed by DownloadManager.completedDownloadCount.collectAsState()
    var rows by remember { mutableStateOf<List<DownloadManageRow>>(emptyList()) }
    var reloadTick by remember { mutableStateOf(0) }
    LaunchedEffect(active, queued, completed, reloadTick) {
        rows = withContext(Dispatchers.IO) { DownloadsLogic.savedDownloads(session) }
    }
    val remove: (String) -> Unit = { id ->
        SettingsIntegration.removeLocalDownload(id)
        reloadTick++
    }
    val totalBytes = rows.sumOf { it.byteCount }

    SettingsSubpageScaffold(title = "Downloads", onBack = onBack) {
        if (active != null || queued.isNotEmpty()) {
            item(key = "inProgress") {
                ServerAdminSection("In progress") {
                    active?.let { id ->
                        AbstandGroupedCard {
                            DownloadManageActiveRow(id, progress, isQueued = false, onCancel = { remove(id) })
                        }
                    }
                    queued.filter { it != active }.forEach { qid ->
                        AbstandGroupedCard {
                            DownloadManageActiveRow(qid, 0.0, isQueued = true, onCancel = { remove(qid) })
                        }
                    }
                }
            }
        }
        item(key = "savedTitle") {
            ServerAdminSection("Saved offline") {
                if (rows.isEmpty()) {
                    AbstandGroupedCard {
                        AbstandCardEmptyState(
                            title = "No downloads yet.",
                            message = "Downloads appear here once you save an audiobook or episode offline.",
                        )
                    }
                } else {
                    if (totalBytes > 0) {
                        AbstandGroupedCard {
                            SettingsCardInfoRow(icon = SF.internaldrive, title = "Total storage", subtitle = Formatter.formatFileSize(context, totalBytes))
                        }
                    }
                    rows.forEach { row ->
                        androidx.compose.runtime.key(row.storageId) {
                            AbstandGroupedCard { DownloadManageSavedRow(row, onDelete = { remove(row.storageId) }) }
                        }
                    }
                }
            }
        }
    }
}

/** iOS: `DownloadManageActiveRow`. */
@Composable
private fun DownloadManageActiveRow(storageId: String, progress: Double, isQueued: Boolean, onCancel: () -> Unit) {
    val palette = Theme.palette
    val entry = remember(storageId) { DownloadManager.catalogEntry(storageId) }
    Row(
        Modifier.fillMaxWidth().padding(vertical = AppTheme.Layout.rowVerticalPadding),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.rowSpacing),
    ) {
        if (entry != null) {
            DownloadCover(entry.libraryItemId)
        } else {
            SettingsCardIcon(if (isQueued) SF.circleDashed else SF.arrowDownCircle)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.tightSpacing)) {
            Text(
                entry?.title?.ifEmpty { null } ?: if (isQueued) "Waiting…" else "Downloading…",
                style = IosType.body.medium, color = palette.textPrimary, maxLines = 2,
            )
            entry?.subtitle?.takeIf { it.isNotEmpty() }?.let {
                Text(it, style = IosType.caption, color = palette.textSecondary, maxLines = 1)
            }
            when {
                isQueued -> Text("Queued", style = IosType.caption2, color = Theme.accent)
                // Balken nur bei Hörbüchern — Podcast-Folgen springen meist von 0 auf fertig.
                entry?.isPodcastEpisode != true -> LinearProgressIndicator(
                    progress = { progress.toFloat().coerceIn(0f, 1f) },
                    modifier = Modifier.fillMaxWidth().padding(top = AppTheme.Layout.hairlineWidth),
                    color = Theme.accent,
                    trackColor = palette.progressTrack,
                )
                else -> Text("Downloading…", style = IosType.caption2, color = palette.textSecondary)
            }
        }
        IconButton(onClick = onCancel) {
            Icon(SF.xmarkCircleFill, contentDescription = if (isQueued) "Remove from queue" else "Cancel download", tint = palette.textSecondary)
        }
    }
}

/** iOS: `DownloadManageSavedRow`. */
@Composable
private fun DownloadManageSavedRow(row: DownloadManageRow, onDelete: () -> Unit) {
    val palette = Theme.palette
    val context = LocalContext.current
    var confirm by remember { mutableStateOf(false) }
    Row(
        Modifier.fillMaxWidth().padding(vertical = AppTheme.Layout.rowVerticalPadding),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.rowSpacing),
    ) {
        DownloadCover(row.libraryItemId)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.tightSpacing)) {
            Text(row.title, style = IosType.body.medium, color = palette.textPrimary, maxLines = 2)
            row.author?.takeIf { it.isNotEmpty() }?.let { Text(it, style = IosType.caption, color = palette.textSecondary, maxLines = 1) }
            val meta = listOfNotNull(row.durationLabel, row.savedLabel.ifEmpty { null }).joinToString(" · ")
            if (meta.isNotEmpty()) Text(meta, style = IosType.caption2, color = palette.textSecondary, maxLines = 1)
        }
        Text(Formatter.formatFileSize(context, row.byteCount), style = IosType.caption, color = palette.textSecondary)
        IconButton(onClick = { confirm = true }) {
            Icon(SF.trash, contentDescription = "Delete download", tint = AppTheme.danger)
        }
    }
    if (confirm) {
        AbstandDialog(
            title = "Delete \"${row.title}\"?",
            onDismiss = { confirm = false },
            message = "This removes the offline copy from this device. The item stays on your server.",
            confirmLabel = "Delete",
            destructive = true,
            dismissOnConfirm = false,
            onConfirm = { confirm = false; onDelete() },
        )
    }
}

/** Quadratisches Cover (44 dp) wie iOS `minTapTarget`. */
@Composable
private fun DownloadCover(itemId: String) {
    Box(
        Modifier.size(AppTheme.Layout.minTapTarget).clip(RoundedCornerShape(AppTheme.Layout.coverCornerRadius)),
    ) {
        CoverImage(itemId = itemId, modifier = Modifier.size(AppTheme.Layout.minTapTarget))
    }
}
