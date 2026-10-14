package de.letzgo.abstand.ui.permissions

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.core.content.ContextCompat
import de.letzgo.abstand.data.Prefs
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Android 13+: `POST_NOTIFICATIONS` beim ersten Start von Wiedergabe oder Download erfragen (Medien-
 * und Download-Benachrichtigung). iOS braucht dafür keine Erlaubnis — einmalig fragen, nie drängeln.
 * Model-Code ruft [requestIfNeeded]; [NotificationPermissionHost] in der Activity zeigt den System-Dialog.
 */
object NotificationPermission {
    /** Android-eigener Pref-Key (kein iOS-Gegenstück). */
    private const val ASKED_KEY = "abstand_android_notification_permission_asked"

    private val _pendingRequest = MutableStateFlow(false)
    val pendingRequest: StateFlow<Boolean> = _pendingRequest.asStateFlow()

    fun isGranted(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    /** Einmalig je Installation anfragen, wenn noch nicht erteilt. */
    fun requestIfNeeded(context: Context) {
        if (isGranted(context) || Prefs.bool(ASKED_KEY)) return
        _pendingRequest.value = true
    }

    internal fun markHandled() {
        Prefs.setBool(ASKED_KEY, true)
        _pendingRequest.value = false
    }
}

/** In der Tab-Shell einhängen: zeigt den Berechtigungsdialog, sobald [NotificationPermission.requestIfNeeded] ihn anfordert. */
@Composable
fun NotificationPermissionHost() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
    val pending by NotificationPermission.pendingRequest.collectAsState()
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        NotificationPermission.markHandled()
    }
    LaunchedEffect(pending) {
        if (pending) launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
    }
}
