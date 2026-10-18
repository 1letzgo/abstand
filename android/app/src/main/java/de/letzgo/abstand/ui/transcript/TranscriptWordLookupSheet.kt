package de.letzgo.abstand.ui.transcript

import android.app.SearchManager
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Translate
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import de.letzgo.abstand.transcript.PlayerTranscriptWordLookupSelection
import de.letzgo.abstand.transcript.TranslationTargetLanguage
import de.letzgo.abstand.transcript.WordLookupLinks
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.AppType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandPrimaryButton
import de.letzgo.abstand.ui.components.AbstandProminentButton
import de.letzgo.abstand.ui.components.AbstandSheet
import de.letzgo.abstand.ui.components.MetadataSheetMenuPicker

/**
 * iOS: `PlayerTranscriptWordLookupSheet` — Wort aus dem Teleprompter nachschlagen/übersetzen.
 * Android hat weder Systemwörterbuch noch Translation-Framework: das Sheet übergibt das Wort an
 * „Translate" (Übersetzer-App bzw. Google Translate im Browser) und „Search the web"; die Zielsprache
 * bleibt wie auf iOS unter `Keys.translationTargetLanguageCode` gespeichert.
 */
@Composable
fun TranscriptWordLookupSheet(selection: PlayerTranscriptWordLookupSelection, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val palette = Theme.palette
    var target by remember { mutableStateOf(TranslationTargetLanguage.load()) }
    val options = remember { TranslationTargetLanguage.pickerOptions() }
    val samePair = TranslationTargetLanguage.sameLanguage(selection.sourceLocale, target)

    AbstandSheet(title = "Look up & translate", onDismiss = onDismiss) {
        Text(selection.term, style = AppType.headlineSmall, color = palette.textPrimary, modifier = Modifier.fillMaxWidth())

        selection.sourceLocale?.let { source ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.stackSpacing)) {
                Text("FROM", style = AppType.bodySmall.copy(fontWeight = FontWeight.SemiBold), color = palette.textSecondary)
                Text(TranslationTargetLanguage.displayName(source.language), style = AppType.bodyMedium, color = palette.textPrimary)
            }
        }
        Column(
            Modifier
                .fillMaxWidth()
                .background(palette.card, RoundedCornerShape(AppTheme.Layout.fieldCornerRadius))
                .padding(horizontal = AppTheme.Layout.cardPadding, vertical = AppTheme.Layout.rowSpacing),
        ) {
            MetadataSheetMenuPicker(
                title = "Target language",
                selection = target,
                options = options.map { it.first },
                label = { code -> options.firstOrNull { it.first == code }?.second ?: code },
                onSelect = { code ->
                    val normalized = TranslationTargetLanguage.normalized(code)
                    target = normalized
                    TranslationTargetLanguage.persist(normalized)
                },
            )
        }
        if (samePair) {
            Text(
                "Source and target language are the same — translation is not needed.",
                style = AppType.bodySmall,
                color = palette.textSecondary,
            )
        } else {
            AbstandPrimaryButton(onClick = {
                openTranslate(context, selection.term, selection.sourceLocale?.language, target)
            }) {
                Icon(Icons.Outlined.Translate, contentDescription = null, modifier = Modifier.size(LookupIconSize))
                Spacer(Modifier.size(AppTheme.Layout.inlineSpacing))
                Text("Translate")
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.rowSpacing)) {
            AbstandProminentButton(text = "Search the web", icon = SF.magnifyingglass, onClick = { openWebSearch(context, selection.term) })
            AbstandProminentButton(onClick = { copyToClipboard(context, selection.term) }) {
                Icon(Icons.Outlined.ContentCopy, contentDescription = null, modifier = Modifier.size(LookupIconSize))
                Spacer(Modifier.size(AppTheme.Layout.inlineSpacing))
                Text("Copy")
            }
        }
        Text(
            "There is no on-device dictionary on Android — translation and search open in another app.",
            style = AppType.bodySmall,
            color = palette.textSecondary,
        )
    }
}

private val LookupIconSize = AppTheme.Layout.smallIconSize

/** Übersetzer-App (`ACTION_TRANSLATE`, API 29+), sonst Google Translate im Browser. */
private fun openTranslate(context: Context, term: String, source: String?, target: String) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        val intent = Intent(Intent.ACTION_TRANSLATE).putExtra(Intent.EXTRA_TEXT, term).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (intent.resolveActivity(context.packageManager) != null) {
            runCatching { context.startActivity(intent) }.onSuccess { return }
        }
    }
    openUrl(context, WordLookupLinks.translateUrl(term, source, target))
}

private fun openWebSearch(context: Context, term: String) {
    val intent = Intent(Intent.ACTION_WEB_SEARCH).putExtra(SearchManager.QUERY, term).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    try {
        context.startActivity(intent)
    } catch (e: ActivityNotFoundException) {
        openUrl(context, WordLookupLinks.searchUrl(term))
    }
}

private fun openUrl(context: Context, url: String) {
    runCatching {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}

private fun copyToClipboard(context: Context, term: String) {
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager ?: return
    clipboard.setPrimaryClip(ClipData.newPlainText("Word", term))
}
