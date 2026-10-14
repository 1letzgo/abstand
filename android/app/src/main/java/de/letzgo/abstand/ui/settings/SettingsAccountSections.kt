package de.letzgo.abstand.ui.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.lazy.LazyColumn
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import de.letzgo.abstand.data.AbsStoredAccount
import de.letzgo.abstand.data.AbsLibrary
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.model.SessionStore
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandCardEmptyState
import de.letzgo.abstand.ui.components.AbstandGroupedCard
import de.letzgo.abstand.ui.components.ServerAdminSection
import de.letzgo.abstand.ui.components.SettingsCardActionRow
import de.letzgo.abstand.ui.components.SettingsCardDivider
import de.letzgo.abstand.ui.components.SettingsCardInfoRow
import de.letzgo.abstand.ui.components.SettingsCardPickerRow
import de.letzgo.abstand.ui.components.SettingsCardToggleRow
import de.letzgo.abstand.ui.components.SettingsMetricCard
import de.letzgo.abstand.ui.components.TabRootScaffold
import de.letzgo.abstand.ui.login.AddAccountSheet
import kotlinx.coroutines.launch

/**
 * Settings-Tab (vorläufig): nur die Account-Sektionen aus iOS `ServerAdminViews.swift`
 * (`Accounts`, `Account`) plus Offline-Schalter. Weitere Sektionen ergänzt der Settings-Port.
 */
@Composable
fun SettingsTabRoot(session: SessionStore = AppModel.shared.session) {
    TabRootScaffold(title = "Settings") { padding ->
        LazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = padding,
            verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.sectionSpacing),
        ) {
            item(key = "accounts") { SettingsAccountsSection(session) }
            item(key = "account") { SettingsAccountSection(session) }
            item(key = "connection") { SettingsConnectionSection(session) }
        }
    }
}

/** iOS: `ServerAdminSection(title: "Accounts")` — gespeicherte Accounts, Wechsel, „Add account“. */
@Composable
fun SettingsAccountsSection(session: SessionStore) {
    val accounts by session.storedAccounts.collectAsState()
    val activeKey by session.activeAccountKey.collectAsState()
    val switching by session.isSwitchingAccount.collectAsState()
    val scope = rememberCoroutineScope()
    var showAddAccount by remember { mutableStateOf(false) }
    var accountPendingLogout by remember { mutableStateOf<AbsStoredAccount?>(null) }

    ServerAdminSection("Accounts") {
        AbstandGroupedCard {
            accounts.forEachIndexed { index, account ->
                if (index > 0) SettingsCardDivider()
                val isActive = account.accountKey == activeKey
                Column(
                    Modifier
                        .fillMaxWidth()
                        .alpha(if (switching) DisabledAlpha else 1f)
                        .clickable(enabled = !switching) {
                            if (!isActive) scope.launch { session.switchToAccount(account.accountKey) }
                        },
                ) {
                    SettingsCardInfoRow(
                        icon = if (isActive) SF.personCropCircleFill else SF.personCropCircle,
                        title = account.displayUsername,
                        subtitle = account.displayServerHost,
                        trailingIcon = if (isActive) SF.checkmarkCircleFill else null,
                        trailingTint = Theme.accent,
                    )
                }
            }
            if (accounts.isNotEmpty()) SettingsCardDivider()
            SettingsCardActionRow(icon = SF.plusCircleFill, title = "Add account", onClick = { showAddAccount = true }, enabled = !switching)
            // iOS: Kontextmenü „Log out“ je Account — Android: Entfernen-Zeile für nicht aktive Accounts.
            accounts.filter { it.accountKey != activeKey }.forEach { account ->
                SettingsCardDivider()
                SettingsCardActionRow(
                    icon = SF.minusCircle,
                    title = "Log out ${account.displayUsername}",
                    subtitle = account.displayServerHost,
                    onClick = { accountPendingLogout = account },
                    tint = AppTheme.danger,
                    enabled = !switching,
                )
            }
        }
    }

    if (showAddAccount) AddAccountSheet(onDismiss = { showAddAccount = false }, session = session)

    accountPendingLogout?.let { account ->
        AlertDialog(
            onDismissRequest = { accountPendingLogout = null },
            title = { Text("Log out?") },
            text = { Text("Remove ${account.displayUsername} from @${account.displayServerHost}?") },
            confirmButton = {
                TextButton(onClick = {
                    session.removeStoredAccount(account.accountKey)
                    accountPendingLogout = null
                }) { Text("Log out", color = AppTheme.danger) }
            },
            dismissButton = { TextButton(onClick = { accountPendingLogout = null }) { Text("Cancel") } },
        )
    }
}

/** iOS: `ServerAdminSection(title: "Account")` — Benutzer, Typ, Primary-Bibliotheken, aktive Bibliotheken, Log out. */
@Composable
fun SettingsAccountSection(session: SessionStore) {
    val username by session.sessionUsername.collectAsState()
    val userType by session.sessionUserType.collectAsState()
    val libraries by session.libraries.collectAsState()
    val selectedBooks by session.selectedBooksLibrary.collectAsState()
    val selectedPodcasts by session.selectedPodcastLibrary.collectAsState()
    val activeBooks by session.activeBooksLibraryIds.collectAsState()
    val activePodcasts by session.activePodcastLibraryIds.collectAsState()
    var confirmLogout by remember { mutableStateOf(false) }
    val typeLabel = remember(userType) { session.sessionAccountTypeLabel }

    ServerAdminSection("Account") {
        Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing)) {
            SettingsMetricCard(SF.personFill, "Username", username, Modifier.weight(1f))
            SettingsMetricCard(SF.personBadgeKeyFill, "Account Type", typeLabel, Modifier.weight(1f))
        }

        val bookLibraries = remember(libraries) { session.sortedBookLibraries }
        AbstandGroupedCard {
            if (bookLibraries.isEmpty()) {
                AbstandCardEmptyState(title = "No book libraries on this server.")
            } else {
                val noneSelected = session.booksLibraryPreferenceIsNone
                LibraryPrimaryPicker(
                    title = "Primary books library",
                    icon = SF.booksVerticalFill,
                    libraries = bookLibraries,
                    selected = if (noneSelected) null else selectedBooks,
                    onSelect = { lib -> if (lib == null) session.clearBooksLibrarySelection() else session.selectBooksLibrary(lib) },
                )
                if (!noneSelected) {
                    SettingsCardDivider()
                    bookLibraries.forEachIndexed { index, lib ->
                        if (index > 0) SettingsCardDivider()
                        SettingsCardToggleRow(
                            icon = SF.booksVertical,
                            title = lib.name,
                            checked = lib.id in activeBooks,
                            onCheckedChange = { session.setBooksLibraryActive(lib.id, it) },
                        )
                    }
                }
            }
        }

        val podcastLibraries = remember(libraries) { session.sortedPodcastLibraries }
        AbstandGroupedCard {
            if (podcastLibraries.isEmpty()) {
                AbstandCardEmptyState(title = "No podcast libraries on this server.")
            } else {
                val noneSelected = session.podcastsLibraryPreferenceIsNone
                LibraryPrimaryPicker(
                    title = "Primary podcasts library",
                    icon = SF.micFill,
                    libraries = podcastLibraries,
                    selected = if (noneSelected) null else selectedPodcasts,
                    onSelect = { lib -> if (lib == null) session.clearPodcastLibrarySelection() else session.selectPodcastLibrary(lib) },
                )
                if (!noneSelected) {
                    SettingsCardDivider()
                    podcastLibraries.forEachIndexed { index, lib ->
                        if (index > 0) SettingsCardDivider()
                        SettingsCardToggleRow(
                            icon = SF.mic,
                            title = lib.name,
                            checked = lib.id in activePodcasts,
                            onCheckedChange = { session.setPodcastLibraryActive(lib.id, it) },
                        )
                    }
                }
            }
        }

        AbstandGroupedCard {
            SettingsCardActionRow(
                icon = SF.rectanglePortraitAndArrowRight,
                title = "Log out",
                onClick = { confirmLogout = true },
                tint = AppTheme.danger,
            )
        }
    }

    if (confirmLogout) {
        AlertDialog(
            onDismissRequest = { confirmLogout = false },
            title = { Text("Log out?") },
            confirmButton = {
                TextButton(onClick = {
                    confirmLogout = false
                    session.logout()
                }) { Text("Log out", color = AppTheme.danger) }
            },
            dismissButton = { TextButton(onClick = { confirmLogout = false }) { Text("Cancel") } },
        )
    }
}

/** Picker mit „None“-Eintrag (iOS: `AppModel.libraryPickerNoneTag`). */
@Composable
private fun LibraryPrimaryPicker(
    title: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    libraries: List<AbsLibrary>,
    selected: AbsLibrary?,
    onSelect: (AbsLibrary?) -> Unit,
) {
    val options: List<AbsLibrary?> = listOf<AbsLibrary?>(null) + libraries
    SettingsCardPickerRow(
        icon = icon,
        title = title,
        selection = libraries.firstOrNull { it.id == selected?.id },
        options = options,
        label = { it?.name ?: "None" },
        onSelect = onSelect,
    )
}

/** Verbindung: Server, Erreichbarkeit, Offline-Modus (iOS: Offline-Schalter im Home-Toolbar/Settings). */
@Composable
fun SettingsConnectionSection(session: SessionStore) {
    val server by session.serverURL.collectAsState()
    val reachable by session.isServerReachable.collectAsState()
    val offline by session.offlineHomeMode.collectAsState()
    val offlineAuto by session.offlineHomeModeAuto.collectAsState()
    ServerAdminSection("Server") {
        AbstandGroupedCard {
            SettingsCardInfoRow(
                icon = SF.serverRack,
                title = server.ifEmpty { "—" },
                subtitle = when {
                    offline || offlineAuto -> "Offline mode"
                    reachable -> "Connected"
                    else -> "Not connected"
                },
                trailingIcon = if (reachable && !offline && !offlineAuto) SF.checkmarkCircleFill else SF.icloudSlash,
                trailingTint = if (reachable && !offline && !offlineAuto) AppTheme.success else null,
            )
            SettingsCardDivider()
            SettingsCardToggleRow(
                icon = SF.icloudSlash,
                title = "Offline mode",
                subtitle = "Only downloaded titles; progress syncs when you go back online.",
                checked = offline || offlineAuto,
                onCheckedChange = { enabled -> if (enabled) session.setOfflineHomeMode(true) else session.exitOfflineHomeUI() },
            )
        }
    }
}

private const val DisabledAlpha = 0.45f
