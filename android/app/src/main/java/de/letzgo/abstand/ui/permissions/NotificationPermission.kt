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
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import de.letzgo.abstand.data.Prefs
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Android 13+: `POST_NOTIFICATIONS` für Wiedergabe- und Download-Benachrichtigungen (iOS braucht
 * dafür keine Rückfrage). Höchstens **einmal** pro Installation fragen — nach Ablehnung entscheidet
 * der Nutzer in den Systemeinstellungen. Model-Code (Wiedergabe-/Download-Start) ruft
 * [requestIfNeeded]; [NotificationPermissionHost] in der Tab-Shell zeigt dann den System-Dialog.
 */
object NotificationPermission {
    /** Android-only (kein iOS-Gegenstück in `AppModel.Keys`). */
    private const val ASKED_KEY = "abstand_android_notification_permission_asked"

    private val _pendingRequest = MutableStateFlow(false)
    /** Ein Wiedergabe-/Download-Start hat die Rückfrage angefordert. */
    val pendingRequest: StateFlow<Boolean> = _pendingRequest.asStateFlow()

    fun isRequired(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU

    fun isGranted(context: Context): Boolean =
        !isRequired() || ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    /** `true`, wenn jetzt gefragt werden soll (nötig, nicht erteilt, noch nie gefragt). */
    fun shouldAsk(context: Context): Boolean = isRequired() && !isGranted(context) && !Prefs.bool(ASKED_KEY)

    fun markAsked() = Prefs.setBool(ASKED_KEY, true)

    /** Aus Model-Code beim ersten Start von Wiedergabe oder Download (ohne Activity-Zugriff). */
    fun requestIfNeeded(context: Context) {
        if (shouldAsk(context)) _pendingRequest.value = true
    }

    internal fun requestHandled() {
        markAsked()
        _pendingRequest.value = false
    }
}

/**
 * Fragt beim ersten Erscheinen einmalig nach der Benachrichtigungs-Berechtigung. Gedacht für die
 * Settings-Wurzel bzw. den ersten Start einer Wiedergabe/eines Downloads.
 */
@Composable
fun RequestNotificationPermissionOnce() {
    if (!NotificationPermission.isRequired()) return
    val context = LocalContext.current
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { }
    LaunchedEffect(Unit) {
        if (NotificationPermission.shouldAsk(context)) {
            NotificationPermission.markAsked()
            launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }
}

/** In der Tab-Shell: zeigt den System-Dialog, sobald [NotificationPermission.requestIfNeeded] ihn anfordert. */
@Composable
fun NotificationPermissionHost() {
    if (!NotificationPermission.isRequired()) return
    val pending by NotificationPermission.pendingRequest.collectAsState()
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { }
    LaunchedEffect(pending) {
        if (pending) {
            NotificationPermission.requestHandled()
            launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }
}
