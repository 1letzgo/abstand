package de.letzgo.abstand.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.outlined.LibraryBooks
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector

/** iOS: `AppModel.MainTab` — gleiche Labels, gleiche Reihenfolge. */
enum class MainTab(val label: String, val icon: ImageVector) {
    Start("Home", Icons.Filled.Home),
    Library("Books", Icons.Outlined.LibraryBooks),
    Podcasts("Podcasts", Icons.Filled.Mic),
    Settings("Settings", Icons.Filled.Settings),
    Search("Search", Icons.Filled.Search),
}

/** iOS: `AppRootContainer` + `MainTabShellView` (Scaffold-Platzhalter bis die Screens portiert sind). */
@Composable
fun AppRoot() {
    var tab by rememberSaveable { mutableStateOf(MainTab.Start) }
    Scaffold(
        bottomBar = {
            NavigationBar {
                MainTab.entries.forEach { t ->
                    NavigationBarItem(
                        selected = tab == t,
                        onClick = { tab = t },
                        icon = { Icon(t.icon, contentDescription = null) },
                        label = { Text(t.label) },
                    )
                }
            }
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
            Text(tab.label)
        }
    }
}
