package de.letzgo.abstand.ui.player

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.media.MediaRouter2
import android.os.Build
import android.provider.Settings
import android.util.Log

/**
 * iOS: `FullPlayerAirPlayButton` (`AVRoutePickerView`) — Android: System-Ausgabe-Umschalter.
 * Android 14+: `MediaRouter2.showSystemOutputSwitcher()`; Android 11–13: Media-Output-Panel der
 * System-Einstellungen; älter: Bluetooth-Einstellungen. Keine zusätzliche Bibliothek nötig.
 */
object AudioOutputSwitcher {
    private const val TAG = "AbstandPlayer"
    /** Settings-Panel „Medienausgabe“ (Android 11+, `com.android.settings.panel.action.MEDIA_OUTPUT`). */
    private const val MEDIA_OUTPUT_PANEL = "com.android.settings.panel.action.MEDIA_OUTPUT"
    private const val EXTRA_PACKAGE_NAME = "com.android.settings.panel.extra.PACKAGE_NAME"

    fun show(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            if (runCatching { MediaRouter2.getInstance(context).showSystemOutputSwitcher() }.getOrDefault(false)) return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val panel = Intent(MEDIA_OUTPUT_PANEL)
                .putExtra(EXTRA_PACKAGE_NAME, context.packageName)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (start(context, panel)) return
        }
        start(context, Intent(Settings.ACTION_BLUETOOTH_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    private fun start(context: Context, intent: Intent): Boolean = try {
        context.startActivity(intent)
        true
    } catch (e: ActivityNotFoundException) {
        Log.w(TAG, "Output switcher unavailable: ${intent.action}")
        false
    } catch (e: SecurityException) {
        Log.w(TAG, "Output switcher not allowed: ${intent.action}")
        false
    }
}
