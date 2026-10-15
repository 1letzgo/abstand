package de.letzgo.abstand.ui.login

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Text
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import de.letzgo.abstand.BuildConfig
import de.letzgo.abstand.data.CustomHeadersStore
import de.letzgo.abstand.data.ServerHTTPHeader
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.model.SessionStore
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.AppType
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.bold
import de.letzgo.abstand.ui.components.AbstandLabeledTextField
import de.letzgo.abstand.ui.components.AbstandPrimaryButton
import de.letzgo.abstand.ui.components.MetadataSheetScaffold
import de.letzgo.abstand.ui.components.abstandScrollScreenBackground
import de.letzgo.abstand.ui.semibold
import kotlinx.coroutines.launch

/**
 * iOS: `LoginView` (Root, abgemeldet) — Titel, Server/User/Passwort, einklappbare Custom-Header,
 * „Sign in“. Pull-to-Refresh versucht den Bootstrap mit gespeicherten Credentials erneut.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LoginScreen(session: SessionStore = AppModel.shared.session) {
    val scope = rememberCoroutineScope()
    var refreshing by remember { mutableStateOf(false) }
    PullToRefreshBox(
        isRefreshing = refreshing,
        onRefresh = {
            scope.launch {
                refreshing = true
                try {
                    session.bootstrapFromStoredCredentials()
                } finally {
                    refreshing = false
                }
            }
        },
        modifier = Modifier.fillMaxSize().abstandScrollScreenBackground(),
    ) {
        Box(
            Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing).imePadding().verticalScroll(rememberScrollState()),
            contentAlignment = Alignment.TopCenter,
        ) {
            LoginForm(
                session = session,
                addAccountMode = false,
                onFinished = {},
                modifier = Modifier
                    .widthIn(max = AppTheme.Layout.readableFormMaxWidth)
                    .fillMaxWidth()
                    .padding(AppTheme.Layout.blockSpacing),
            )
        }
    }
}

/** iOS: `LoginView(addAccountMode: true)` als Sheet — Felder leer, nach Erfolg schließen. */
@Composable
fun AddAccountSheet(onDismiss: () -> Unit, session: SessionStore = AppModel.shared.session) {
    MetadataSheetScaffold(title = "Add account", onCancel = onDismiss, spacing = AppTheme.Layout.blockSpacing) {
        LoginForm(session = session, addAccountMode = true, onFinished = onDismiss)
    }
}

/** Gemeinsamer Inhalt von [LoginScreen] und [AddAccountSheet] (iOS: Body von `LoginView`). */
@Composable
private fun LoginForm(session: SessionStore, addAccountMode: Boolean, onFinished: () -> Unit, modifier: Modifier = Modifier) {
    val palette = Theme.palette
    val scope = rememberCoroutineScope()
    val globalError by session.errorMessage.collectAsState()
    var addAccountError by rememberSaveable { mutableStateOf<String?>(null) }
    var server by rememberSaveable { mutableStateOf("") }
    var username by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    // Custom-Header für diesen Server (verschlüsselt) — vor dem Login gespeichert, damit schon der Login-Request sie trägt.
    var customHeaders by remember { mutableStateOf<List<ServerHTTPHeader>>(emptyList()) }

    LaunchedEffect(Unit) {
        if (addAccountMode) {
            server = ""
            username = ""
            password = ""
        } else if (server.isEmpty()) {
            server = session.serverURL.value
            // Debug-Build: Testserver aus local.properties vorbelegen (nie automatisch absenden).
            if (BuildConfig.DEBUG && BuildConfig.DEBUG_SERVER.isNotEmpty() && session.storedAccounts.value.isEmpty()) {
                if (server.isEmpty()) server = BuildConfig.DEBUG_SERVER
                if (username.isEmpty()) username = BuildConfig.DEBUG_USER
                if (password.isEmpty()) password = BuildConfig.DEBUG_PASSWORD
            }
        }
        customHeaders = CustomHeadersStore.load(server)
    }

    fun submit() {
        if (busy || server.isEmpty() || username.isEmpty() || password.isEmpty()) return
        scope.launch {
            busy = true
            try {
                // Header-Werte gehören in den verschlüsselten Speicher, nie in die normalen Prefs.
                CustomHeadersStore.save(customHeaders, server)
                if (addAccountMode) {
                    addAccountError = null
                    val failure = session.addStoredAccount(server, username, password)
                    if (failure != null) addAccountError = failure else onFinished()
                } else {
                    session.login(server, username, password)
                }
            } finally {
                busy = false
            }
        }
    }

    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.blockSpacing)) {
        Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.compactSpacing)) {
            if (!addAccountMode) {
                Text("Abstand", style = AppType.headlineMedium.bold, color = palette.textPrimary)
                Text("Audiobookshelf", style = AppType.titleLarge.semibold, color = Theme.accent)
            }
            Text(
                if (addAccountMode) "Sign in with another Audiobookshelf account." else "Sign in with your Audiobookshelf account.",
                style = AppType.bodyMedium,
                color = palette.textSecondary,
            )
        }

        Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.cardPadding)) {
            AbstandLabeledTextField(
                title = "Server URL", value = server, onValueChange = { server = it },
                keyboardType = KeyboardType.Uri, imeAction = ImeAction.Next, enabled = !busy,
            )
            AbstandLabeledTextField(
                title = "Username", value = username, onValueChange = { username = it },
                keyboardType = KeyboardType.Email, imeAction = ImeAction.Next, enabled = !busy,
            )
            AbstandLabeledTextField(
                title = "Password", value = password, onValueChange = { password = it }, isSecure = true,
                imeAction = ImeAction.Go, onSubmit = ::submit, enabled = !busy,
            )
            ServerCustomHeadersDisclosure(customHeaders) { customHeaders = it }
        }

        val err = if (addAccountMode) addAccountError else globalError
        if (!err.isNullOrEmpty()) Text(err, style = AppType.bodySmall, color = AppTheme.danger)

        AbstandPrimaryButton(
            text = if (addAccountMode) "Add account" else "Sign in",
            onClick = ::submit,
            enabled = server.isNotEmpty() && username.isNotEmpty() && password.isNotEmpty(),
            isBusy = busy,
        )
    }
}
