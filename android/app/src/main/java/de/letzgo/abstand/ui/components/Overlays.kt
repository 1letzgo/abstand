package de.letzgo.abstand.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.AppType
import de.letzgo.abstand.ui.Theme

// Dialoge und Sheets (iOS: `.alert`, `.confirmationDialog`, `.sheet`). Nie rohes `AlertDialog`,
// `Dialog` oder `ModalBottomSheet` außerhalb von ui/components bauen.

/** Maße der Overlay-Chromes (Material 3). */
object AbstandOverlayMetrics {
    /** M3-Dialog: Ecken extra-large (28 dp). */
    val dialogShape: Shape = RoundedCornerShape(AppTheme.Layout.cornerExtraLarge)
    /** M3-Bottom-Sheet: obere Ecken extra-large (28 dp). */
    val sheetShape: Shape = RoundedCornerShape(topStart = AppTheme.Layout.cornerExtraLarge, topEnd = AppTheme.Layout.cornerExtraLarge)
    /** M3-Griff 32 × 4 dp (iOS: 36 × 5). */
    val grabberWidth = AppTheme.Layout.dragHandleWidth
    val grabberHeight = AppTheme.Layout.dragHandleHeight
    /** M3-Bottom-Sheet: Titel, Inhalt und Aktionszeile 24 dp seitlich/unten. */
    val sheetPadding = 24.dp
    /** Zusatzabstand über der Aktionszeile (zum Zeilenabstand des Inhalts). */
    val sheetActionsTopPadding = 8.dp
}

/**
 * Basis-Dialog im App-Stil (M3: 28-dp-Ecken, 24 dp Innenabstand): Karte (`palette.card`), Titel
 * `headlineSmall`, Text `bodyMedium`/`textSecondary`, Aktionen als [AbstandTextButton] — M3: alle
 * Aktionen (Bestätigen, Abbrechen, neutral) als Text-Buttons in `primary`, nur ein [destructive]
 * Bestätigen in `error`. [content] ersetzt/ergänzt den Text (Eingabefeld,
 * Regler). [dismissOnConfirm] = `false` lässt den Dialog nach Bestätigen offen (z. B. bis eine
 * Server-Antwort da ist). [neutralLabel] = dritte Aktion links neben Abbrechen.
 */
@Composable
fun AbstandDialog(
    title: String,
    onDismiss: () -> Unit,
    confirmLabel: String,
    onConfirm: () -> Unit,
    message: String? = null,
    destructive: Boolean = false,
    confirmEnabled: Boolean = true,
    dismissLabel: String? = "Cancel",
    dismissOnConfirm: Boolean = true,
    neutralLabel: String? = null,
    onNeutral: (() -> Unit)? = null,
    content: (@Composable ColumnScope.() -> Unit)? = null,
) {
    val palette = Theme.palette
    AlertDialog(
        onDismissRequest = onDismiss,
        shape = AbstandOverlayMetrics.dialogShape,
        containerColor = palette.card,
        tonalElevation = 0.dp,
        titleContentColor = palette.textPrimary,
        textContentColor = palette.textSecondary,
        title = { Text(title, style = AppType.headlineSmall, color = palette.textPrimary, modifier = Modifier.semantics { heading() }) },
        text = if (message != null || content != null) {
            {
                Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing)) {
                    if (message != null) Text(message, style = AppType.bodyMedium, color = palette.textSecondary)
                    content?.invoke(this)
                }
            }
        } else null,
        confirmButton = {
            AbstandTextButton(
                confirmLabel,
                onClick = {
                    if (dismissOnConfirm) onDismiss()
                    onConfirm()
                },
                enabled = confirmEnabled,
                destructive = destructive,
                emphasized = true,
            )
        },
        dismissButton = if (dismissLabel != null || neutralLabel != null) {
            {
                Row {
                    if (neutralLabel != null && onNeutral != null) {
                        AbstandTextButton(neutralLabel, onNeutral)
                    }
                    if (dismissLabel != null) AbstandTextButton(dismissLabel, onDismiss)
                }
            }
        } else null,
    )
}

/** iOS: `.alert(title, message:)` mit nur „OK“ — Fehler und Hinweise. */
@Composable
fun AbstandAlert(title: String, onDismiss: () -> Unit, message: String? = null, buttonLabel: String = "OK") {
    AbstandDialog(
        title = title, onDismiss = onDismiss, confirmLabel = buttonLabel, onConfirm = {},
        message = message, dismissLabel = null,
    )
}

/**
 * iOS: Bestätigungs-Alert („Delete …?“, „Log out?“) — Abbrechen + Bestätigen. Standard
 * [destructive] (rote Aktion); für harmlose Bestätigungen (`Go offline`) `false` setzen.
 * [onConfirm] läuft nach dem Schließen.
 */
@Composable
fun AbstandConfirmDialog(
    title: String,
    confirmLabel: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
    message: String? = null,
    destructive: Boolean = true,
) {
    AbstandDialog(
        title = title, onDismiss = onDismiss, confirmLabel = confirmLabel, onConfirm = onConfirm,
        message = message, destructive = destructive,
    )
}

/** iOS: blockierendes Popup mit Spinner (z. B. „Deleting book“) — nicht wegtippbar. */
@Composable
fun AbstandBlockingProgressDialog(text: String) {
    Dialog(onDismissRequest = {}, properties = DialogProperties(dismissOnBackPress = false, dismissOnClickOutside = false)) {
        val palette = Theme.palette
        Column(
            Modifier
                .abstandCardChrome(palette.card, AbstandOverlayMetrics.dialogShape, AppTheme.CardElevation.Hero)
                .padding(AppTheme.Layout.dialogPadding),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.screenPadding),
        ) {
            CircularProgressIndicator(
                color = Theme.accent, strokeWidth = AbstandSpinnerSize.Large.strokeWidth,
                modifier = Modifier.size(AbstandSpinnerSize.Large.diameter),
            )
            Text(text, style = AppType.titleMedium, color = palette.textPrimary, textAlign = TextAlign.Center)
        }
    }
}

/** Sheet-Griff (M3 32 × 4 dp, iOS 36 × 5; `textSecondary` mit [AppTheme.grabberAlpha]). */
@Composable
fun AbstandSheetGrabber(modifier: Modifier = Modifier) {
    Box(
        modifier
            .size(AbstandOverlayMetrics.grabberWidth, AbstandOverlayMetrics.grabberHeight)
            .background(Theme.palette.textSecondary.copy(alpha = AppTheme.grabberAlpha), CircleShape),
    )
}

/**
 * M3 Modal Bottom Sheet (iOS: `.sheet` mit `.presentationDetents`): Griff, optionaler Titel
 * (`titleLarge`, linksbündig, 24 dp seitlich), Inhalt und — nur wenn es eine Bestätigung gibt
 * ([onConfirm]) — unten rechtsbündig „Cancel“ als Text-Button ([cancelLabel], schließt) plus
 * Filled Button ([confirmLabel]; [destructive] in `error`). Ohne Bestätigung keine Buttons:
 * Schließen per Wischen/Scrim/Zurück. Unterer Rand respektiert die Navigationsleiste
 * (Standard-`windowInsets` des Sheets). Ganzseitige Formulare mit Tastatur gehören in
 * [MetadataSheetScaffold] (Vollbild-Dialog), nicht hierher.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AbstandSheet(
    title: String?,
    onDismiss: () -> Unit,
    onConfirm: (() -> Unit)? = null,
    confirmLabel: String = "Done",
    confirmEnabled: Boolean = true,
    isBusy: Boolean = false,
    destructive: Boolean = false,
    cancelLabel: String = "Cancel",
    spacing: Dp = AppTheme.Layout.withinSectionSpacing,
    content: @Composable ColumnScope.() -> Unit,
) {
    val palette = Theme.palette
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        shape = AbstandOverlayMetrics.sheetShape,
        containerColor = palette.scheme.surfaceContainerLow,
        contentColor = palette.textPrimary,
        tonalElevation = 0.dp,
        dragHandle = {
            Box(Modifier.padding(vertical = AppTheme.Layout.screenPadding)) { AbstandSheetGrabber() }
        },
    ) {
        Column(
            Modifier.fillMaxWidth().padding(
                start = AbstandOverlayMetrics.sheetPadding,
                end = AbstandOverlayMetrics.sheetPadding,
                bottom = AbstandOverlayMetrics.sheetPadding,
            ),
            verticalArrangement = Arrangement.spacedBy(spacing),
        ) {
            if (title != null) {
                Text(
                    title, style = AppType.titleLarge, color = palette.textPrimary,
                    modifier = Modifier.fillMaxWidth().semantics { heading() },
                )
            }
            content()
            if (onConfirm != null) {
                Row(
                    Modifier.fillMaxWidth().padding(top = AbstandOverlayMetrics.sheetActionsTopPadding),
                    horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.inlineSpacing, Alignment.End),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    AbstandTextButton(cancelLabel, onDismiss)
                    AbstandProminentButton(
                        confirmLabel, onConfirm,
                        enabled = confirmEnabled, isBusy = isBusy, destructive = destructive,
                    )
                }
            }
        }
    }
}
