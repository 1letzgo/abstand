package de.letzgo.abstand.ui.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import de.letzgo.abstand.model.AdminStore
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.model.SessionStore
import de.letzgo.abstand.model.StatsStore
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.admin.serverSettingsMenuSections
import de.letzgo.abstand.ui.components.TabRootScaffold
import de.letzgo.abstand.ui.permissions.RequestNotificationPermissionOnce
import de.letzgo.abstand.ui.stats.statsHubSections
import kotlinx.coroutines.launch

/** iOS: `SettingsHubSection` — Bereiche der Settings-Icon-Leiste (Raw-Value = Label). */
enum class SettingsHubSection(val label: String, val icon: ImageVector) {
    appearance("Appearance", SF.paintbrushFill),
    playback("Playback", SF.playCircle),
    downloads("Downloads", SF.arrowDownCircle),
    account("Account", SF.personCropCircle),
    stats("Stats", SF.chartBarFill),
    server("Server", SF.serverRack),
    debug("Debug", SF.ladybug);

    companion object {
        /** iOS: `stripOrder` — Stats zuerst in der Leiste und zugleich Startseite. */
        fun stripOrder(isServerRoot: Boolean, offlineHome: Boolean): List<SettingsHubSection> = buildList {
            addAll(listOf(stats, account, appearance, playback))
            if (!offlineHome) add(downloads)
            if (isServerRoot) add(server)
            add(debug)
        }
    }
}

/**
 * iOS: `SettingsHubRootView` — Settings-Tab: Icon-Leiste unter dem Titel, darunter der Inhalt des
 * gewählten Bereichs. Pull-to-Refresh lädt Account (Bibliotheken) bzw. Stats neu.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsTabRoot(model: AppModel = AppModel.shared) {
    val session = model.session
    val isServerRoot by session.isServerRoot.collectAsState()
    val offline by session.offlineHomeMode.collectAsState()
    val offlineAuto by session.offlineHomeModeAuto.collectAsState()
    val offlineUI = offline || offlineAuto
    val sections = SettingsHubSection.stripOrder(isServerRoot, offlineUI)
    var hubSection by rememberSaveable { mutableStateOf(SettingsHubSection.stats) }
    // iOS: `clampHubSectionIfNeeded`.
    val current = if (hubSection in sections) hubSection else sections.first()
    val stats = remember { StatsStore.shared }
    val admin = remember { AdminStore.prepared() }
    val scope = rememberCoroutineScope()
    var refreshing by remember { mutableStateOf(false) }

    RequestNotificationPermissionOnce()

    LaunchedEffect(current, offlineUI) {
        if (offlineUI) return@LaunchedEffect
        when (current) {
            SettingsHubSection.account, SettingsHubSection.downloads -> session.reloadSettingsTab(reloadCatalogs = false)
            SettingsHubSection.stats -> {
                stats.prepareListeningAchievementsForStatsTab()
                stats.loadListeningStats()
            }
            else -> Unit
        }
    }

    TabRootScaffold(
        title = "Settings",
        header = {
            SettingsIconStrip(
                items = sections.map { SettingsStripItem(it, it.label, it.icon) },
                selection = current,
                onSelect = { hubSection = it },
            )
        },
    ) { padding ->
        PullToRefreshBox(
            isRefreshing = refreshing,
            onRefresh = {
                scope.launch {
                    if (offlineUI) return@launch
                    refreshing = true
                    try {
                        when (current) {
                            SettingsHubSection.account -> session.reloadSettingsTab(reloadCatalogs = false)
                            SettingsHubSection.stats -> stats.loadListeningStats()
                            else -> Unit
                        }
                    } finally {
                        refreshing = false
                    }
                }
            },
            modifier = Modifier.fillMaxSize(),
        ) {
            LazyColumn(
                Modifier.fillMaxSize(),
                contentPadding = padding,
                verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.sectionSpacing),
            ) {
                settingsHubSectionBody(current, session, admin)
            }
        }
    }
}

/** iOS: `settingsHubSectionBody(_:)`. */
private fun LazyListScope.settingsHubSectionBody(section: SettingsHubSection, session: SessionStore, admin: AdminStore) {
    when (section) {
        SettingsHubSection.appearance -> settingsAppearanceSections()
        SettingsHubSection.playback -> settingsPlaybackSections()
        SettingsHubSection.downloads -> settingsDownloadsSections(session)
        SettingsHubSection.account -> {
            item(key = "accounts") { SettingsAccountsSection(session) }
            item(key = "account") { SettingsAccountSection(session) }
            item(key = "connection") { SettingsConnectionSection(session) }
        }
        SettingsHubSection.stats -> statsHubSections()
        SettingsHubSection.server -> serverSettingsMenuSections(admin)
        SettingsHubSection.debug -> item(key = "debug") { DebugLogSection() }
    }
}
