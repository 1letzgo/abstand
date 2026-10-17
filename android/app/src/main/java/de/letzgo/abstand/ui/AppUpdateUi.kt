package de.letzgo.abstand.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.material3.Text
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import de.letzgo.abstand.data.AppUpdate
import de.letzgo.abstand.ui.components.AbstandDialog
import de.letzgo.abstand.ui.components.AbstandProgressBar
import kotlinx.coroutines.launch
import java.io.File

/**
 * Android-eigen (wie stede): neue Version von GitHub — lädt die APK in der App (mit Fortschritt und
 * Prüfsumme) und übergibt sie dem Paketinstaller. Fehlt die Freigabe „Install unknown apps“, führt
 * der Dialog dorthin und installiert, sobald man zurückkommt.
 */
@Composable
fun AppUpdateDialog(release: AppUpdate.Release, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val palette = Theme.palette
    var progress by remember { mutableStateOf<Float?>(null) }
    var downloading by remember { mutableStateOf(false) }
    var file by remember { mutableStateOf<File?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var waitingForPermission by remember { mutableStateOf(false) }

    fun installOrAsk(apk: File) {
        if (AppUpdate.canInstall(context)) {
            waitingForPermission = false
            AppUpdate.install(context, apk)
        } else {
            waitingForPermission = true
            AppUpdate.openInstallPermission(context)
        }
    }

    // Zurück aus den Einstellungen: mit Freigabe gleich installieren.
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(waitingForPermission) {
        if (!waitingForPermission) return@LaunchedEffect
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            file?.let { if (AppUpdate.canInstall(context)) installOrAsk(it) }
        }
    }

    AbstandDialog(
        title = "New version available",
        onDismiss = {
            if (downloading) return@AbstandDialog
            if (file == null) AppUpdate.skip(release)
            onDismiss()
        },
        confirmLabel = when {
            file != null -> "Install"
            error != null -> "Try again"
            else -> "Update"
        },
        onConfirm = {
            val apk = file
            if (apk != null) {
                installOrAsk(apk)
            } else {
                scope.launch {
                    downloading = true
                    error = null
                    progress = null
                    runCatching { AppUpdate.download(context, release) { progress = it } }
                        .onSuccess { file = it; installOrAsk(it) }
                        .onFailure { error = it.message ?: "The new version could not be downloaded." }
                    downloading = false
                }
            }
        },
        confirmEnabled = !downloading,
        dismissLabel = if (downloading) null else "Later",
        dismissOnConfirm = false,
    ) {
        Text(release.name, style = AppType.titleSmall, color = palette.textPrimary)
        if (release.notes.isNotEmpty()) Text(release.notes, style = AppType.bodyMedium, color = palette.textSecondary)
        when {
            error != null -> Text(error!!, style = AppType.bodyMedium, color = AppTheme.danger)
            downloading -> {
                Text("Downloading…", style = AppType.bodyMedium, color = palette.textSecondary)
                AbstandProgressBar((progress ?: 0f).toDouble())
            }
            waitingForPermission -> Text(
                "Allow abstand to install apps in the Android settings, then come back.",
                style = AppType.bodyMedium, color = palette.textSecondary,
            )
            file != null -> Text(
                "Downloaded. Android will ask whether to install the new version.",
                style = AppType.bodyMedium, color = palette.textSecondary,
            )
        }
    }
}

/** Prüft beim Start (höchstens alle sechs Stunden) und zeigt den Hinweis. */
@Composable
fun AppUpdateCheck() {
    val context = LocalContext.current
    var release by remember { mutableStateOf<AppUpdate.Release?>(null) }
    LaunchedEffect(Unit) { release = AppUpdate.checkOnLaunch(context) }
    release?.let { AppUpdateDialog(it) { release = null } }
}
