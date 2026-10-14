package de.letzgo.abstand.ui.admin

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.model.AdminStore
import de.letzgo.abstand.ui.LocalTabNavigator
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.components.AbstandGroupedCard
import de.letzgo.abstand.ui.components.ServerAdminSection
import de.letzgo.abstand.ui.components.SettingsCardNavRow
import kotlinx.coroutines.launch

/** iOS: `serverSettingsMenuSections` — Hub-Bereich „Server“ (nur Root): Users, Libraries, Tools. */
fun LazyListScope.serverSettingsMenuSections(admin: AdminStore) {
    item(key = "server/users") {
        val navigator = LocalTabNavigator.current
        ServerAdminSection("Users") {
            AbstandGroupedCard {
                SettingsCardNavRow(icon = SF.person2Fill, title = "Users", onClick = { navigator?.push(ServerUsersDestination) })
            }
        }
    }
    item(key = "server/libraries") {
        val navigator = LocalTabNavigator.current
        ServerAdminSection("Libraries") {
            AbstandGroupedCard {
                SettingsCardNavRow(icon = SF.booksVerticalFill, title = "Libraries", onClick = { navigator?.push(ServerLibrariesDestination) })
            }
        }
    }
    item(key = "server/tools") {
        val navigator = LocalTabNavigator.current
        val jobs by admin.m4bEncodeJobs.collectAsState()
        val activeCount = jobs.count { it.isActive }
        ServerAdminSection("Tools") {
            AbstandGroupedCard {
                SettingsCardNavRow(
                    icon = SF.hourglass,
                    title = "M4B Converter",
                    subtitle = if (activeCount > 0) "$activeCount running" else null,
                    onClick = { navigator?.push(ServerM4BDestination) },
                )
            }
        }
    }
}

/** iOS: `ServerAdminLayoutMetrics`. */
internal object ServerAdminLayoutMetrics {
    val userStatusDotSize = 8.dp
    val compactMetaLabelColumnWidth = 72.dp
}

/** Pull-to-Refresh um eine Admin-Unterseite (iOS: `.refreshable`). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun AdminRefreshBox(onRefresh: suspend () -> Unit, content: @Composable () -> Unit) {
    val scope = rememberCoroutineScope()
    var refreshing by remember { mutableStateOf(false) }
    PullToRefreshBox(
        isRefreshing = refreshing,
        onRefresh = {
            scope.launch {
                refreshing = true
                try { onRefresh() } finally { refreshing = false }
            }
        },
        modifier = Modifier.fillMaxSize(),
    ) { content() }
}
