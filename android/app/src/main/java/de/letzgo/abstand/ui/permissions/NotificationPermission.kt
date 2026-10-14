package de.letzgo.abstand.ui.permissions

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import de.letzgo.abstand.data.Prefs

/**
 * Android 13+: `POST_NOTIFICATIONS` für Wiedergabe- und Download-Benachrichtigungen (iOS braucht
 * dafür keine Rückfrage). Höchstens **einmal** pro Installation fragen — nach Ablehnung entscheidet
 * der Nutzer in den Systemeinstellungen.
 */
object NotificationPermission {
    /** Android-only (kein iOS-Gegenstück in `AppModel.Keys`). */
    private const val ASKED_KEY = "abstand_android_notification_permission_asked"

    fun isRequired(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU

    fun isGranted(context: Context): Boolean =
        !isRequired() || ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    /** `true`, wenn jetzt gefragt werden soll (nötig, nicht erteilt, noch nie gefragt). */
    fun shouldAsk(context: Context): Boolean = isRequired() && !isGranted(context) && !Prefs.bool(ASKED_KEY)

    fun markAsked() = Prefs.setBool(ASKED_KEY, true)
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
