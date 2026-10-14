package de.letzgo.abstand.ui.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import de.letzgo.abstand.data.CustomHeadersStore
import de.letzgo.abstand.data.ServerHTTPHeader
import de.letzgo.abstand.model.AdminStore
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.IosType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.TabDestination
import de.letzgo.abstand.ui.TabNavigator
import de.letzgo.abstand.ui.components.AbstandGroupedCard
import de.letzgo.abstand.ui.components.AbstandInlineNotice
import de.letzgo.abstand.ui.components.AbstandPrimaryButton
import de.letzgo.abstand.ui.components.ServerAdminSection
import de.letzgo.abstand.ui.components.SettingsCardDivider
import de.letzgo.abstand.ui.components.SettingsCardInfoRow
import de.letzgo.abstand.ui.components.SettingsCardSecureFieldRow
import de.letzgo.abstand.ui.components.SettingsSubpageScaffold
import de.letzgo.abstand.ui.login.ServerCustomHeadersEditor
import kotlinx.coroutines.launch

/** iOS: `SettingsChangePasswordView` (Settings-Unterseite „Change Password“). */
data object ChangePasswordDestination : TabDestination {
    override val key = "settings/changePassword"

    @Composable
    override fun Content(navigator: TabNavigator) = SettingsChangePasswordScreen(onBack = { navigator.pop() })
}

@Composable
fun SettingsChangePasswordScreen(onBack: () -> Unit, model: AppModel = AppModel.shared) {
    val session = model.session
    val username by session.sessionUsername.collectAsState()
    val isServerRoot by session.isServerRoot.collectAsState()
    val offline by session.offlineHomeMode.collectAsState()
    val offlineAuto by session.offlineHomeModeAuto.collectAsState()
    var current by rememberSaveable { mutableStateOf("") }
    var new by rememberSaveable { mutableStateOf("") }
    var confirm by rememberSaveable { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf<Pair<String, Boolean>?>(null) }
    val scope = rememberCoroutineScope()
    val submitEnabled = !busy && !(offline || offlineAuto)

    SettingsSubpageScaffold(title = "Change Password", onBack = onBack) {
        item(key = "password") {
            ServerAdminSection("Password") {
                AbstandGroupedCard {
                    SettingsCardSecureFieldRow(SF.lockFill, "Current password", current, { current = it })
                    if (username.isNotEmpty()) {
                        SettingsCardDivider()
                        SettingsCardInfoRow(icon = SF.personFill, title = "Username", subtitle = username)
                    }
                    SettingsCardDivider()
                    SettingsCardSecureFieldRow(
                        SF.lockOpenFill, "New password", new, { new = it },
                        placeholder = if (isServerRoot) "Optional" else "Required",
                    )
                    SettingsCardDivider()
                    SettingsCardSecureFieldRow(
                        SF.lockFill, "Confirm password", confirm, { confirm = it },
                        placeholder = if (isServerRoot) "Optional" else "Required",
                    )
                }
                AbstandPrimaryButton(
                    text = "Save password",
                    enabled = submitEnabled,
                    isBusy = busy,
                    onClick = {
                        scope.launch {
                            status = null
                            busy = true
                            val err = try {
                                AdminStore.shared.changeAccountPassword(current, new, confirm)
                            } finally {
                                busy = false
                            }
                            if (err != null) {
                                status = err to true
                            } else {
                                status = "Password updated." to false
                                current = ""; new = ""; confirm = ""
                            }
                        }
                    },
                )
                status?.let { (text, isError) ->
                    Text(text, style = IosType.footnote, color = if (isError) AppTheme.danger else AppTheme.success, modifier = Modifier.fillMaxWidth())
                }
            }
        }
    }
}

/**
 * Android-Ergänzung: Custom-Header des aktiven Servers bearbeiten (iOS: nur im Login per
 * `ServerCustomHeadersEditor`). Speichern beim Verlassen und per Button.
 */
data object CustomHeadersDestination : TabDestination {
    override val key = "settings/customHeaders"

    @Composable
    override fun Content(navigator: TabNavigator) = SettingsCustomHeadersScreen(onBack = { navigator.pop() })
}

@Composable
fun SettingsCustomHeadersScreen(onBack: () -> Unit, model: AppModel = AppModel.shared) {
    val server by model.session.serverURL.collectAsState()
    var headers by remember(server) { mutableStateOf(CustomHeadersStore.load(server).ifEmpty { listOf(ServerHTTPHeader(name = "", value = "")) }) }
    var saved by remember { mutableStateOf(false) }
    SettingsSubpageScaffold(title = "Custom headers", onBack = onBack) {
        item(key = "headers") {
            ServerAdminSection("Headers") {
                AbstandGroupedCard {
                    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing)) {
                        ServerCustomHeadersEditor(headers) {
                            headers = it
                            saved = false
                        }
                    }
                }
                AbstandPrimaryButton(text = "Save", onClick = {
                    saved = CustomHeadersStore.save(headers, server)
                    de.letzgo.abstand.data.Net.resetConnections()
                })
                if (saved) AbstandInlineNotice("Headers saved. They apply to new requests to this server.")
            }
        }
    }
}
