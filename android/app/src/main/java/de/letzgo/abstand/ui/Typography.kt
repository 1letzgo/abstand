package de.letzgo.abstand.ui

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight

/**
 * Typografie der App = **Material-3-Typeskala** (Roboto/Systemschrift, Größen und Zeilenhöhen
 * aus `Typography()`), dieselben Stile wie `MaterialTheme.typography`. Views lesen nur von hier
 * (statisch, auch außerhalb von Composables nutzbar) — keine `fontSize = …`-Literale
 * (`UiTemplateLintTest`).
 *
 * Abbildung der iOS-Dynamic-Type-Rollen (Swift → Kotlin), damit Port und Original vergleichbar
 * bleiben:
 *
 * | iOS (pt)              | Android M3 (sp)                     |
 * |-----------------------|-------------------------------------|
 * | `.largeTitle` 34      | [headlineMedium] 28/36              |
 * | `.title` 28           | [headlineSmall] 24/32               |
 * | `.title2` 22          | [titleLarge] 22/28                  |
 * | `.title3` 20          | [titleLarge] 22/28                  |
 * | `.headline` 17 sb     | [titleMedium] 16/24 medium          |
 * | `.body` 17            | [bodyLarge] 16/24                   |
 * | `.callout` 16         | [bodyLarge] 16/24                   |
 * | `.subheadline` 15     | [bodyMedium] 14/20                  |
 * | `.footnote` 13        | [bodySmall] 12/16                   |
 * | `.caption` 12         | [bodySmall] 12/16                   |
 * | `.caption2` 11        | [labelSmall] 11/16 medium           |
 *
 * Gewichte wie iOS über [bold]/[semibold]/[medium] (`Font.title3.bold()` → `AppType.titleLarge.bold`).
 * Systemskalierung läuft über sp.
 */
object AppType {
    /** `MaterialTheme.typography` (M3-Standard, unverändert). */
    val material: Typography = Typography()

    val displayLarge: TextStyle get() = material.displayLarge
    val displayMedium: TextStyle get() = material.displayMedium
    val displaySmall: TextStyle get() = material.displaySmall
    /** iOS: — (größer als `.largeTitle`). */
    val headlineLarge: TextStyle get() = material.headlineLarge
    /** iOS: `.largeTitle`. */
    val headlineMedium: TextStyle get() = material.headlineMedium
    /** iOS: `.title`. */
    val headlineSmall: TextStyle get() = material.headlineSmall
    /** iOS: `.title2` / `.title3` — Sektionstitel, Top-App-Bar-Titel. */
    val titleLarge: TextStyle get() = material.titleLarge
    /** iOS: `.headline` — Karten-/Zeilentitel. */
    val titleMedium: TextStyle get() = material.titleMedium
    /** iOS: `.subheadline.weight(.semibold)` als Label (Chips, kompakte Titel). */
    val titleSmall: TextStyle get() = material.titleSmall
    /** iOS: `.body` / `.callout`. */
    val bodyLarge: TextStyle get() = material.bodyLarge
    /** iOS: `.subheadline` — Untertitel/Supporting Text in Listen. */
    val bodyMedium: TextStyle get() = material.bodyMedium
    /** iOS: `.footnote` / `.caption`. */
    val bodySmall: TextStyle get() = material.bodySmall
    /** Buttons, Tabs, Menü-Labels (M3 label large). */
    val labelLarge: TextStyle get() = material.labelLarge
    /** Kleine Labels, Badges (M3 label medium). */
    val labelMedium: TextStyle get() = material.labelMedium
    /** iOS: `.caption2`. */
    val labelSmall: TextStyle get() = material.labelSmall
}

/** iOS: `.bold()`. */
val TextStyle.bold: TextStyle get() = copy(fontWeight = FontWeight.Bold)
/** iOS: `.weight(.semibold)`. */
val TextStyle.semibold: TextStyle get() = copy(fontWeight = FontWeight.SemiBold)
/** iOS: `.weight(.medium)`. */
val TextStyle.medium: TextStyle get() = copy(fontWeight = FontWeight.Medium)
