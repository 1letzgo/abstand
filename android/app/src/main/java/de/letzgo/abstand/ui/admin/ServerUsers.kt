package de.letzgo.abstand.ui.admin

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import de.letzgo.abstand.data.AbsAdminMediaProgressRow
import de.letzgo.abstand.data.AbsAdminUserDetail
import de.letzgo.abstand.data.AbsAdminUserSummary
import de.letzgo.abstand.data.AbsListeningSession
import de.letzgo.abstand.model.AdminStore
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.AppType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.TabDestination
import de.letzgo.abstand.ui.TabNavigator
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandCard
import de.letzgo.abstand.ui.components.AbstandCardBottomProgress
import de.letzgo.abstand.ui.components.AbstandEmptyScreen
import de.letzgo.abstand.ui.components.AbstandGroupedCard
import de.letzgo.abstand.ui.components.AbstandInlineNotice
import de.letzgo.abstand.ui.components.AbstandLoadingSpinner
import de.letzgo.abstand.ui.components.AbstandSectionEmptyState
import de.letzgo.abstand.ui.components.CoverImage
import de.letzgo.abstand.ui.components.ServerAdminMetricTile
import de.letzgo.abstand.ui.components.ServerAdminSection
import de.letzgo.abstand.ui.components.SettingsCardNavRow
import de.letzgo.abstand.ui.components.SettingsSubpageScaffold
import de.letzgo.abstand.ui.components.abstandCardListRowFrame
import de.letzgo.abstand.ui.formatPlaybackTime
import de.letzgo.abstand.ui.medium
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import de.letzgo.abstand.ui.components.AbstandBadge
import de.letzgo.abstand.ui.components.AbstandBadgeTone

/** iOS: `ServerUsersListView`. */
data object ServerUsersDestination : TabDestination {
    override val key = "admin/users"

    @Composable
    override fun Content(navigator: TabNavigator) = ServerUsersListScreen(navigator)
}

@Composable
fun ServerUsersListScreen(navigator: TabNavigator, admin: AdminStore = AdminStore.shared) {
    var users by remember { mutableStateOf<List<AbsAdminUserSummary>>(emptyList()) }
    var onlineIds by remember { mutableStateOf<Set<String>>(emptySet()) }
    var loading by remember { mutableStateOf(false) }
    var loadError by remember { mutableStateOf<String?>(null) }

    suspend fun reload() {
        loading = true
        try {
            coroutineScope {
                val u = async { admin.fetchServerUsers() }
                val o = async { admin.fetchServerOnlineUserIds() }
                users = u.await()
                onlineIds = o.await()
            }
            loadError = null
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            loadError = e.message ?: "Could not load users"
        } finally {
            loading = false
        }
    }
    LaunchedEffect(Unit) { reload() }

    AdminRefreshBox(onRefresh = { reload() }) {
        SettingsSubpageScaffold(title = "Users", onBack = { navigator.pop() }) {
            when {
                loading && users.isEmpty() -> item(key = "loading") { AbstandLoadingSpinner() }
                loadError != null && users.isEmpty() -> item(key = "error") {
                    AbstandEmptyScreen(title = "Could not load users", icon = SF.person2Slash, description = loadError, modifier = Modifier.height(EmptyScreenHeight))
                }
                else -> item(key = "users") {
                    ServerAdminSection("Users") {
                        Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.stackSpacing)) {
                            if (users.isEmpty()) AbstandSectionEmptyState("No users.")
                            users.forEach { user ->
                                AbstandGroupedCard(onClick = { navigator.push(ServerUserDetailDestination(user.id, user.username)) }) {
                                    ServerUserListRow(user, isOnline = user.id in onlineIds)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/** iOS: `ServerUserListRow`. */
@Composable
private fun ServerUserListRow(user: AbsAdminUserSummary, isOnline: Boolean) {
    val palette = Theme.palette
    Row(
        Modifier.abstandCardListRowFrame(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.rowSpacing),
    ) {
        Box(
            Modifier.size(ServerAdminLayoutMetrics.userStatusDotSize).clip(CircleShape)
                .background(if (isOnline) AppTheme.success else palette.textSecondary.copy(alpha = 0.35f)),
        )
        Text(user.username, style = AppType.bodyLarge.medium, color = palette.textPrimary)
        if (user.isRoot) {
            AbstandBadge("root", tone = AbstandBadgeTone.Accent)
        } else {
            user.typeLabel?.let { Text(it, style = AppType.labelSmall, color = palette.textSecondary) }
        }
        Box(Modifier.weight(1f))
        Icon(SF.chevronRight, contentDescription = null, tint = palette.textSecondary, modifier = Modifier.size(ChevronSize))
    }
}

/** iOS: `ServerUserDetailView`. */
data class ServerUserDetailDestination(val userId: String, val username: String) : TabDestination {
    override val key = "admin/user/$userId"

    @Composable
    override fun Content(navigator: TabNavigator) = ServerUserDetailScreen(userId, username, navigator)
}

@Composable
fun ServerUserDetailScreen(userId: String, username: String, navigator: TabNavigator, admin: AdminStore = AdminStore.shared) {
    var detail by remember { mutableStateOf<AbsAdminUserDetail?>(null) }
    var loading by remember { mutableStateOf(false) }
    var loadError by remember { mutableStateOf<String?>(null) }
    suspend fun reload() {
        loading = true
        try {
            detail = admin.fetchServerUserDetail(userId)
            loadError = null
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            loadError = e.message ?: "Could not load user"
        } finally {
            loading = false
        }
    }
    LaunchedEffect(userId) { reload() }

    AdminRefreshBox(onRefresh = { reload() }) {
        SettingsSubpageScaffold(title = username, onBack = { navigator.pop() }) {
            val d = detail
            when {
                loading && d == null -> item(key = "loading") { AbstandLoadingSpinner() }
                loadError != null && d == null -> item(key = "error") {
                    AbstandInlineNotice(loadError!!, Modifier.padding(vertical = AppTheme.Layout.emptyStateVerticalPadding), isError = true)
                }
                d != null -> {
                    val rows = d.mediaProgressSorted
                    item(key = "header") { UserHeaderBlock(d) }
                    item(key = "summary") {
                        Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing)) {
                            ServerAdminMetricTile("${rows.count { it.isInProgress }}", "In Progress", Modifier.weight(1f), valueColor = Theme.accent)
                            ServerAdminMetricTile("${rows.count { it.isFinished }}", "Finished", Modifier.weight(1f), valueColor = AppTheme.success)
                            ServerAdminMetricTile("${rows.size}", "Total", Modifier.weight(1f))
                        }
                    }
                    item(key = "sessions") {
                        AbstandGroupedCard {
                            SettingsCardNavRow(
                                icon = SF.clockArrowCirclepath,
                                title = "Recent Sessions",
                                onClick = { navigator.push(ServerUserSessionsDestination(userId, username)) },
                            )
                        }
                    }
                    if (rows.isNotEmpty()) {
                        item(key = "progress") {
                            ServerAdminSection("Library Progress") {
                                rows.forEach { row -> androidx.compose.runtime.key(row.id) { AdminProgressRowCard(row) } }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun UserHeaderBlock(detail: AbsAdminUserDetail) {
    val palette = Theme.palette
    Row(
        Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.inlineSpacing),
    ) {
        Text(detail.lastSeenCaption(), style = AppType.bodyMedium, color = palette.textSecondary)
        detail.typeLabel?.let { type ->
            AbstandBadge(type)
        }
    }
}

/**
 * Fortschrittszeile eines Users (iOS: `BookRowCard` mit `progressOverride`, ohne Wiedergabe- und
 * Download-Steuerung) — Cover, Titel, Autor, Fortschritt, unterer Fortschrittsstreifen.
 */
@Composable
private fun AdminProgressRowCard(row: AbsAdminMediaProgressRow) {
    val palette = Theme.palette
    val side = AppTheme.Layout.libraryRowCoverSide
    AbstandCard(Modifier.fillMaxWidth(), shape = RoundedCornerShape(AppTheme.Layout.cardCornerRadius)) {
        Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.libraryRowCardInset)) {
            CoverImage(itemId = row.libraryItemId, modifier = Modifier.size(side))
            Column(
                Modifier.weight(1f).height(side).padding(vertical = AppTheme.Layout.libraryRowTextInset).padding(end = AppTheme.Layout.libraryRowTextInset),
                verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.hairlineSpacing),
            ) {
                Text(row.resolvedDisplayTitle, style = AppType.titleMedium, color = palette.textPrimary, maxLines = 1)
                Text(row.resolvedDisplayAuthor, style = AppType.bodySmall, color = palette.textSecondary, maxLines = 1)
                Box(Modifier.weight(1f))
                Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.inlineSpacing)) {
                    Text(row.progressCaption, style = AppType.bodyMedium, color = if (row.isFinished) AppTheme.success else Theme.accent)
                    Text(row.timeCaption(), style = AppType.bodyMedium, color = palette.textSecondary, maxLines = 1)
                }
            }
        }
        AbstandCardBottomProgress(row.displayProgressFraction)
    }
}

/** iOS: `ServerUserListeningSessionsView`. */
data class ServerUserSessionsDestination(val userId: String, val username: String) : TabDestination {
    override val key = "admin/user/$userId/sessions"

    @Composable
    override fun Content(navigator: TabNavigator) = ServerUserListeningSessionsScreen(userId, navigator)
}

@Composable
fun ServerUserListeningSessionsScreen(userId: String, navigator: TabNavigator, admin: AdminStore = AdminStore.shared) {
    var sessions by remember { mutableStateOf<List<AbsListeningSession>>(emptyList()) }
    var loading by remember { mutableStateOf(false) }
    var loadError by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(userId) {
        loading = true
        try {
            sessions = admin.fetchServerUserListeningSessions(userId).sessions
            loadError = null
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            loadError = e.message
        } finally {
            loading = false
        }
    }
    val palette = Theme.palette
    SettingsSubpageScaffold(title = "Recent Sessions", onBack = { navigator.pop() }, spacing = AppTheme.Layout.stackSpacing) {
        when {
            loading && sessions.isEmpty() -> item(key = "loading") { AbstandLoadingSpinner() }
            sessions.isEmpty() -> item(key = "empty") {
                AbstandEmptyScreen(title = "No sessions", icon = SF.clock, description = loadError, modifier = Modifier.height(EmptyScreenHeight))
            }
            else -> sessions.forEach { s ->
                item(key = s.id) {
                    AbstandGroupedCard {
                        Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.tightSpacing)) {
                            Text(s.libraryItemId.ifEmpty { s.id }, style = AppType.bodyMedium.medium, color = palette.textPrimary)
                            Text("${formatPlaybackTime(s.startTime)} → ${formatPlaybackTime(s.currentTime)}", style = AppType.bodySmall, color = palette.textSecondary)
                        }
                    }
                }
            }
        }
    }
}

/** Höhe eines ganzflächigen Leerzustands innerhalb der Liste. */
internal val EmptyScreenHeight = AppTheme.Layout.loadingVerticalPadding * 8
private val ChevronSize = AppTheme.Layout.coverBadgeSize
