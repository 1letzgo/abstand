package de.letzgo.abstand.ui

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.data.AbsApiClient
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.model.PlayerWiring
import de.letzgo.abstand.model.SessionStore
import de.letzgo.abstand.model.ShellRoute
import de.letzgo.abstand.ui.components.AbstandAlert
import de.letzgo.abstand.ui.components.CoverEnvironment
import de.letzgo.abstand.ui.components.LocalCoverEnvironment
import de.letzgo.abstand.ui.detail.BookDetailDestination
import de.letzgo.abstand.ui.home.HomeTabRoot
import de.letzgo.abstand.ui.login.LoginScreen
import de.letzgo.abstand.ui.permissions.NotificationPermissionHost
import de.letzgo.abstand.ui.player.MiniPlayerDock
import de.letzgo.abstand.ui.player.NowPlayingOverlay
import de.letzgo.abstand.ui.player.miniPlayerDockHeight
import de.letzgo.abstand.ui.player.rememberTranscriptReadAlong
import de.letzgo.abstand.ui.reader.EbookReaderOverlay
import de.letzgo.abstand.ui.search.SearchDestination
import de.letzgo.abstand.ui.settings.SettingsDestination

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
 * iOS: `MainTabShellView(MainRootView)` — Android ohne Tab-Leiste: Home ist die einzige Wurzel,
 * Search und Settings öffnen sich als gepushte Seiten ([SessionStore.shellRouteRequests]; Symbole
 * in der Home-Kopfzeile). Books und Podcasts stecken als Bibliotheksleiste in Home. Ein Navigator,
 * nach Accountwechsel frisch. Der Mini-Player dockt unten über der System-Navigationsleiste an.
 */
@Composable
private fun MainTabShell(session: SessionStore, player: PlayerWiring) {
    val palette = Theme.palette
    val epoch by session.accountSessionEpoch.collectAsState()
    // Nach Accountwechsel frisch (iOS: `accountSessionEpoch` invalidiert Tab-Views).
    val navigator = remember(epoch) { TabNavigator() }
    val stateHolder = rememberSaveableStateHolder()

    // iOS: `mainTab = …` → Search/Settings pushen bzw. zurück zur Home-Wurzel.
    LaunchedEffect(navigator) {
        session.shellRouteRequests.collect { route ->
            when (route) {
                ShellRoute.home -> navigator.popToRoot()
                ShellRoute.search -> navigator.pushUnlessOnTop(SearchDestination())
                ShellRoute.settings -> navigator.pushUnlessOnTop(SettingsDestination)
            }
        }
    }
    // iOS: Search-Tab `onDisappear` — Suche leeren, sobald die Such-Seite nicht mehr im Stack liegt
    // (eine daraus gepushte Detailseite zählt nicht als Verlassen).
    val searchOpen = navigator.backStack.any { it is SearchDestination }
    LaunchedEffect(searchOpen) { AppModel.shared.search.setScreenOpen(searchOpen) }

    // Ohne Tab-Leiste zeichnet der Inhalt bis an den unteren Rand: Listen bekommen unten Platz für
    // System-Navigationsleiste + Mini-Player (iOS: `nowPlayingAccessoryScrollBottomInset`).
    var miniPlayerVisible by remember { mutableStateOf(false) }
    val navigationBarInset = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()
    val miniPlayerInset by animateDpAsState(if (miniPlayerVisible) miniPlayerDockHeight else 0.dp, label = "miniPlayerInset")
    val scrollBottomInset = navigationBarInset + miniPlayerInset

    Box(Modifier.fillMaxSize().background(palette.background)) {
        stateHolder.SaveableStateProvider("$epoch/home") {
            CompositionLocalProvider(LocalTabNavigator provides navigator, LocalScrollBottomInset provides scrollBottomInset) {
                TabStackHost(navigator) { HomeTabRoot() }
            }
        }
        // iOS: `tabViewBottomAccessory` — immer komponiert, nur Sichtbarkeit animiert.
        MiniPlayerDock(player, Modifier.align(Alignment.BottomCenter), onVisibleChange = { miniPlayerVisible = it })
        // iOS: Vollbild-Player über allem (FullScreenOverlayPresenter / Zoom aus dem Mini-Player).
        NowPlayingOverlay(player, readAlong = rememberTranscriptReadAlong(), onOpenEbook = BookDetailDestination.defaultOpenEbook)
    }

    NotificationPermissionHost()
    AppIntegration.MetadataSheetsHost()
    ErrorAlert(session)
}

/** iOS: Root-Alert für `errorMessage`. */
@Composable
private fun ErrorAlert(session: SessionStore) {
    val message by session.errorMessage.collectAsState()
    val text = message ?: return
    AbstandAlert("Error", onDismiss = { session.setErrorMessage(null) }, message = text)
}
