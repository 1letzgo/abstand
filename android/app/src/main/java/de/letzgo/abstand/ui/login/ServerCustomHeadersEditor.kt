package de.letzgo.abstand.ui.login

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.data.ServerHTTPHeader
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.AppType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme

/**
 * iOS: `ServerCustomHeadersEditor` — je Zeile Name + Wert (verdeckt), Entfernen-Button, „Add header“
 * und Hinweis. Ungültige Zeilen werden beim Speichern verworfen ([ServerHTTPHeader.sanitized]),
 * angefangene zeigen ihren Fehler direkt darunter.
 */
@Composable
fun ServerCustomHeadersEditor(headers: List<ServerHTTPHeader>, onHeadersChange: (List<ServerHTTPHeader>) -> Unit) {
    val palette = Theme.palette
    Column(Modifier.fillMaxWidth().animateContentSize(), verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing)) {
        headers.forEach { header ->
            Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.inlineSpacing), verticalAlignment = Alignment.Top) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.stackSpacing)) {
                    HeaderField("Header name", header.name, isSecure = false) { v ->
                        onHeadersChange(headers.map { if (it.id == header.id) it.copy(name = v) else it })
                    }
                    HeaderField("Value", header.value, isSecure = true) { v ->
                        onHeadersChange(headers.map { if (it.id == header.id) it.copy(value = v) else it })
                    }
                    headerProblem(header)?.let { Text(it, style = AppType.bodySmall, color = AppTheme.danger) }
                }
                Box(
                    Modifier
                        .size(AppTheme.Layout.minTapTarget)
                        .clip(RoundedCornerShape(AppTheme.Layout.minTapTarget / 2))
                        .clickable { onHeadersChange(headers.filterNot { it.id == header.id }) }
                        .semantics { contentDescription = "Remove header" },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(SF.minusCircleFill, contentDescription = null, tint = AppTheme.danger, modifier = Modifier.size(RemoveIconSize))
                }
            }
        }

        Row(
            Modifier.clickable { onHeadersChange(headers + ServerHTTPHeader(name = "", value = "")) },
            horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.compactSpacing),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(SF.plusCircleFill, contentDescription = null, tint = Theme.accent)
            Text("Add header", style = AppType.titleMedium, color = Theme.accent)
        }

        Text(
            "Sent with every request to this server, e.g. for SSO or a reverse proxy that needs its own token. Stored encrypted on this device.",
            style = AppType.bodySmall,
            color = palette.textSecondary,
        )
    }
}

@Composable
private fun HeaderField(placeholder: String, value: String, isSecure: Boolean, onValueChange: (String) -> Unit) {
    val palette = Theme.palette
    Box(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(AppTheme.Layout.fieldCornerRadius))
            .background(palette.card)
            .padding(AppTheme.Layout.rowSpacing),
    ) {
        if (value.isEmpty()) Text(placeholder, style = AppType.bodyLarge, color = palette.textSecondary.copy(alpha = 0.55f))
        BasicTextField(
            value = value,
            onValueChange = onValueChange,
            singleLine = true,
            textStyle = AppType.bodyLarge.copy(
                color = palette.textPrimary,
                fontFamily = if (isSecure) null else FontFamily.Monospace,
            ),
            cursorBrush = SolidColor(Theme.accent),
            visualTransformation = if (isSecure) PasswordVisualTransformation() else VisualTransformation.None,
            keyboardOptions = KeyboardOptions(
                capitalization = KeyboardCapitalization.None,
                autoCorrectEnabled = false,
                keyboardType = if (isSecure) KeyboardType.Password else KeyboardType.Ascii,
            ),
            modifier = Modifier.fillMaxWidth().semantics { contentDescription = placeholder },
        )
    }
}

/** Nur für begonnene Zeilen; leere Zeilen werden beim Speichern ignoriert. */
internal fun headerProblem(header: ServerHTTPHeader): String? {
    val name = header.trimmedName
    if (name.isEmpty() && header.trimmedValue.isEmpty()) return null
    if (name.isEmpty()) return "Enter a header name."
    if (name.lowercase() in ServerHTTPHeader.reservedNames) return "$name is managed by the app and can't be set."
    if (header.trimmedValue.isEmpty()) return "Enter a value."
    if (!header.isUsable) return "Header names may only contain letters, digits and - _ . ! # $ % & ' * + ^ ` | ~"
    return null
}

/**
 * iOS: `ServerCustomHeadersDisclosure` — einklappbare Custom-Header-Karte für Login / „Add account“,
 * standardmäßig zu; gespeicherte Header klappen sie auf.
 */
@Composable
fun ServerCustomHeadersDisclosure(headers: List<ServerHTTPHeader>, onHeadersChange: (List<ServerHTTPHeader>) -> Unit) {
    val palette = Theme.palette
    val usableCount = ServerHTTPHeader.sanitized(headers).size
    var isExpanded by rememberSaveable { mutableStateOf(false) }
    // Schon gespeicherte Header sofort sichtbar machen.
    LaunchedEffect(Unit) { if (usableCount > 0) isExpanded = true }
    val chevronRotation by animateFloatAsState(if (isExpanded) 180f else 0f, tween(DisclosureAnimationMillis), label = "chevron")
    Column(Modifier.fillMaxWidth().animateContentSize(tween(DisclosureAnimationMillis)), verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing)) {
        Row(
            Modifier
                .fillMaxWidth()
                .clickable { isExpanded = !isExpanded }
                .semantics {
                    contentDescription = "Custom headers"
                    stateDescription = if (isExpanded) "Expanded" else "Collapsed"
                },
            horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.compactSpacing),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("Custom headers", style = AppType.labelMedium, color = palette.textSecondary)
            if (usableCount > 0) Text("$usableCount", style = AppType.labelSmall, color = palette.textSecondary)
            Spacer(Modifier.weight(1f))
            Icon(SF.chevronDown, contentDescription = null, tint = palette.textSecondary, modifier = Modifier.size(ChevronSize).rotate(chevronRotation))
        }
        AnimatedVisibility(visible = isExpanded, enter = fadeIn(), exit = fadeOut()) {
            ServerCustomHeadersEditor(headers, onHeadersChange)
        }
    }
}

private const val DisclosureAnimationMillis = 280
private val RemoveIconSize = 24.dp
private val ChevronSize = 16.dp
