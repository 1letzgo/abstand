package de.letzgo.abstand.ui

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/**
 * iOS: Dynamic-Type-Stile (`Font.largeTitle` … `.caption2`) in der Standardgröße „Large“
 * (pt → sp, Zeilenhöhe wie iOS). Views nutzen diese Namen, damit Port und Original dieselbe
 * Rolle tragen: `Font.title3.bold()` → `IosType.title3.bold`. Systemskalierung läuft über sp.
 */
object IosType {
    val largeTitle = TextStyle(fontSize = 34.sp, lineHeight = 41.sp)
    val title = TextStyle(fontSize = 28.sp, lineHeight = 34.sp)
    val title2 = TextStyle(fontSize = 22.sp, lineHeight = 28.sp)
    val title3 = TextStyle(fontSize = 20.sp, lineHeight = 25.sp)
    /** iOS: `.headline` (17 pt semibold). */
    val headline = TextStyle(fontSize = 17.sp, lineHeight = 22.sp, fontWeight = FontWeight.SemiBold)
    val body = TextStyle(fontSize = 17.sp, lineHeight = 22.sp)
    val callout = TextStyle(fontSize = 16.sp, lineHeight = 21.sp)
    val subheadline = TextStyle(fontSize = 15.sp, lineHeight = 20.sp)
    val footnote = TextStyle(fontSize = 13.sp, lineHeight = 18.sp)
    val caption = TextStyle(fontSize = 12.sp, lineHeight = 16.sp)
    val caption2 = TextStyle(fontSize = 11.sp, lineHeight = 13.sp)

    /**
     * Material-Typografie aus den iOS-Größen, damit auch Material-Komponenten (TopAppBar,
     * NavigationBar, Buttons, Dialoge) die iOS-Maße tragen.
     */
    val material: Typography = Typography().let { m ->
        Typography(
            displayLarge = m.displayLarge,
            displayMedium = m.displayMedium,
            displaySmall = m.displaySmall,
            headlineLarge = largeTitle.bold,
            headlineMedium = title.bold,
            headlineSmall = title2.bold,
            titleLarge = title3.semibold,
            titleMedium = headline,
            titleSmall = subheadline.semibold,
            bodyLarge = body,
            bodyMedium = subheadline,
            bodySmall = footnote,
            labelLarge = subheadline.medium,
            labelMedium = caption.medium,
            labelSmall = caption2.medium,
        )
    }
}

/** iOS: `.bold()`. */
val TextStyle.bold: TextStyle get() = copy(fontWeight = FontWeight.Bold)
/** iOS: `.weight(.semibold)`. */
val TextStyle.semibold: TextStyle get() = copy(fontWeight = FontWeight.SemiBold)
/** iOS: `.weight(.medium)`. */
val TextStyle.medium: TextStyle get() = copy(fontWeight = FontWeight.Medium)
