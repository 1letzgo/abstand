package de.letzgo.abstand.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.data.AbsApiClient
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.model.MainTab
import de.letzgo.abstand.model.PlayerWiring
import de.letzgo.abstand.model.SessionStore
import de.letzgo.abstand.ui.components.AbstandAlert
import de.letzgo.abstand.ui.components.AbstandEmptyScreen
import de.letzgo.abstand.ui.components.CoverEnvironment
import de.letzgo.abstand.ui.components.LocalCoverEnvironment
import de.letzgo.abstand.ui.components.TabRootScaffold
import de.letzgo.abstand.ui.detail.BookDetailDestination
import de.letzgo.abstand.ui.home.HomeTabRoot
import de.letzgo.abstand.ui.library.BooksLibraryTabRoot
import de.letzgo.abstand.ui.login.LoginScreen
import de.letzgo.abstand.ui.permissions.NotificationPermissionHost
import de.letzgo.abstand.ui.player.MiniPlayerDock
import de.letzgo.abstand.ui.player.NowPlayingOverlay
import de.letzgo.abstand.ui.player.miniPlayerDockHeight
import de.letzgo.abstand.ui.player.rememberTranscriptReadAlong
import de.letzgo.abstand.ui.podcasts.PodcastsTabRoot
import de.letzgo.abstand.ui.reader.EbookReaderOverlay
import de.letzgo.abstand.ui.search.SearchTabRoot
import de.letzgo.abstand.ui.settings.SettingsTabRoot

/** Tab-Symbole (iOS: `MainRootView` `.tabItem { Label(…, systemImage:) }`). */
val MainTab.icon: ImageVector
    get() = when (this) {
        MainTab.start -> SF.houseFill
        MainTab.library -> SF.booksVerticalFill
        MainTab.podcasts -> SF.micFill
        MainTab.settings -> SF.gearshapeFill
        MainTab.search -> SF.magnifyingglass
    }

/**
 * iOS: `AppRootContainer` — abgemeldet [LoginScreen], angemeldet die Tab-Shell. Setzt den
 * Cover-Kontext der Session ([LocalCoverEnvironment]).
 */
@Composable
fun AppRoot(model: AppModel = AppModel.shared) {
    val session = model.session
    val loggedIn by session.isLoggedIn.collectAsState()
    val serverURL by session.serverURL.collectAsState()
    val activeAccountKey by session.activeAccountKey.collectAsState()
    val username by session.sessionUsername.collectAsState()
    val coverRevision by session.coverImageCacheRevision.collectAsState()
    val tokenRevision by session.tokenRevision.collectAsState()
    val coverEnvironment = remember(loggedIn, serverURL, activeAccountKey, username, coverRevision, tokenRevision) {
        CoverEnvironment(
            serverBaseURL = AbsApiClient.normalizeServerURL(serverURL),
            accountDir = if (loggedIn) session.cacheAccountDir() else null,
            revision = coverRevision,
        )
    }
    CompositionLocalProvider(LocalCoverEnvironment provides coverEnvironment) {
        if (loggedIn) {
            // eBook-Reader als Vollbild-Overlay über den Tabs (iOS: `fullScreenCover(item: $model.ebookReaderSession)`).
            Box(Modifier.fillMaxSize()) {
                MainTabShell(session, model.player)
                EbookReaderOverlay()
                // Android-eigen: neue APK aus GitHub-Releases (nur sideload-Flavor).
                AppUpdateCheck()
            }
        } else {
            LoginScreen(session)
        }
    }
}

/**
 * iOS: `MainTabShellView(MainRootView)` — Material-`NavigationBar` mit Home, Books, Podcasts,
 * Settings, Search; jeder Tab mit eigenem Back-Stack. Sichtbarkeit von Books/Podcasts folgt den
 * gecachten Flags, die der Session-Store erst nach dem Bootstrap umschaltet — die Tab-Struktur
 * bleibt während des Starts stabil. Tab-Inhalte bleiben beim Wechsel erhalten (Zustand je Tab).
 */
@Composable
private fun MainTabShell(session: SessionStore, player: PlayerWiring) {
    val palette = Theme.palette
    val selected by session.mainTab.collectAsState()
    val showBooks by session.showAudiobooksTab.collectAsState()
    val showPodcasts by session.showPodcastsTab.collectAsState()
    val epoch by session.accountSessionEpoch.collectAsState()
    val visibleTabs = MainTab.entries.filter {
        when (it) {
            MainTab.library -> showBooks
            MainTab.podcasts -> showPodcasts
            else -> true
        }
    }
    // Navigatoren je Tab; nach Accountwechsel frisch (iOS: `accountSessionEpoch` invalidiert Tab-Views).
    val navigators = remember(epoch) { MainTab.entries.associateWith { TabNavigator(it) } }
    val stateHolder = rememberSaveableStateHolder()
    val current = if (selected in visibleTabs) selected else MainTab.start

    // System-Zurück an der Wurzel eines anderen Tabs → Home (Android-Konvention; iOS hat kein Zurück).
    BackHandler(enabled = current != MainTab.start && navigators.getValue(current).backStack.isEmpty()) {
        session.selectMainTab(MainTab.start)
    }

    // Mini-Player sichtbar → Listen bekommen unten Platz (iOS: `nowPlayingAccessoryScrollBottomInset`).
    var miniPlayerVisible by remember { mutableStateOf(false) }
    val scrollBottomInset by animateDpAsState(if (miniPlayerVisible) miniPlayerDockHeight else 0.dp, label = "miniPlayerInset")

    Box(Modifier.fillMaxSize()) {
    Scaffold(
        containerColor = palette.background,
        contentColor = palette.textPrimary,
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        bottomBar = {
            // M3-Standardrollen: Leiste surfaceContainer, Indicator secondaryContainer,
            // aktives Symbol onSecondaryContainer, Labels onSurface / onSurfaceVariant.
            NavigationBar {
                visibleTabs.forEach { tab ->
                    NavigationBarItem(
                        selected = tab == current,
                        onClick = {
                            // Erneutes Tippen auf den aktiven Tab: zurück zur Wurzel (iOS-Verhalten).
                            if (tab == current) navigators.getValue(tab).popToRoot() else session.selectMainTab(tab)
                        },
                        icon = { Icon(tab.icon, contentDescription = null) },
                        label = { Text(tab.label) },
                    )
                }
            }
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(bottom = padding.calculateBottomPadding())) {
            val navigator = navigators.getValue(current)
            stateHolder.SaveableStateProvider("$epoch/${current.name}") {
                CompositionLocalProvider(LocalTabNavigator provides navigator, LocalScrollBottomInset provides scrollBottomInset) {
                    TabStackHost(navigator) { TabRootContent(current) }
                }
            }
            // iOS: `tabViewBottomAccessory` — immer komponiert, nur Sichtbarkeit animiert.
            MiniPlayerDock(player, Modifier.align(Alignment.BottomCenter), onVisibleChange = { miniPlayerVisible = it })
        }
    }
    // iOS: Vollbild-Player über Tabs und Tab-Leiste (FullScreenOverlayPresenter / Zoom aus dem Mini-Player).
    NowPlayingOverlay(player, readAlong = rememberTranscriptReadAlong(), onOpenEbook = BookDetailDestination.defaultOpenEbook)
    }

    NotificationPermissionHost()
    AppIntegration.MetadataSheetsHost()
    ErrorAlert(session)
}

/** Wurzel je Tab — Home und Suche portiert, Books/Podcasts noch Platzhalter (Settings: Account-Sektionen). */
@Composable
private fun TabRootContent(tab: MainTab) {
    when (tab) {
        MainTab.settings -> SettingsTabRoot()
        MainTab.start -> HomeTabRoot()
        MainTab.library -> BooksLibraryTabRoot()
        MainTab.podcasts -> PodcastsTabRoot()
        MainTab.search -> SearchTabRoot()
    }
}

@Composable
private fun PlaceholderTabRoot(tab: MainTab, description: String) {
    TabRootScaffold(title = tab.label) { padding ->
        AbstandEmptyScreen(title = tab.label, icon = tab.icon, description = description, modifier = Modifier.padding(padding))
    }
}

/** iOS: Root-Alert für `errorMessage`. */
@Composable
private fun ErrorAlert(session: SessionStore) {
    val message by session.errorMessage.collectAsState()
    val text = message ?: return
    AbstandAlert("Error", onDismiss = { session.setErrorMessage(null) }, message = text)
}
