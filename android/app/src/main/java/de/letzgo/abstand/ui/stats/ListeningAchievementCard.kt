package de.letzgo.abstand.ui.stats

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.logic.ListeningAchievementState
import de.letzgo.abstand.logic.ListeningAchievementTier
import de.letzgo.abstand.ui.AppColorPalette
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.IosType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.bold
import de.letzgo.abstand.ui.components.AbstandCard
import de.letzgo.abstand.ui.components.AbstandCardBottomProgress

/** iOS: `ListeningAchievementCard`-Metriken. */
private object AchievementCardMetrics {
    val iconSlotWidth = 28.dp
    val compactIconSlotWidth = AppTheme.Layout.compactIconColumnWidth
    val compactBadgeEdge = 28.dp
    val regularBadgeEdge = 36.dp
    val regularIconSize = 21.dp
    val compactIconSize = 17.dp
    /** iOS: `DetailHeroLayoutMetrics.coverCornerRadius`. */
    val compactBadgeCorner = 8.dp
    val badgeBorderWidth = 1.5.dp
}

/** iOS: `ListeningAchievementTier.adaptiveTint(accent:palette:)`. */
fun ListeningAchievementTier.adaptiveTint(accent: Color, palette: AppColorPalette): Color =
    if (this == ListeningAchievementTier.LOCKED) palette.textSecondary.copy(alpha = 0.45f)
    else accent.copy(alpha = adaptiveTintOpacity(palette.isDarkLike).toFloat())

/**
 * iOS: `ListeningAchievementCard` — Abzeichen mit Level-Badge und Fortschritt zur nächsten Stufe;
 * Tippen erklärt die Stufen (Alert). [compact] = zwei Karten je Zeile (Stats › Level).
 */
@Composable
fun ListeningAchievementCard(achievement: ListeningAchievementState, modifier: Modifier = Modifier, compact: Boolean = false) {
    var showExplanation by rememberSaveable { mutableStateOf(false) }
    val palette = Theme.palette
    val tint = achievement.tier.adaptiveTint(Theme.accent, palette)
    val progress = if (achievement.tier == ListeningAchievementTier.LEVEL5) 1.0 else achievement.progressToNext
    val label = "${achievement.kind.title}, ${achievement.valueLine}, ${achievement.tier.accessibilityLabel}"
    AbstandCard(
        modifier.fillMaxWidth().let { if (compact) it.fillMaxHeight() else it }.clearAndSetSemantics { contentDescription = label },
        onClick = { showExplanation = true },
    ) {
        if (compact) {
            Column(Modifier.fillMaxWidth().fillMaxHeight()) {
                Column(
                    Modifier.padding(AppTheme.Layout.withinSectionSpacing),
                    verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.stackSpacing),
                ) {
                    Row(verticalAlignment = Alignment.Top) {
                        AchievementIcon(achievement, tint, AchievementCardMetrics.compactIconSize, AchievementCardMetrics.compactIconSlotWidth)
                        Spacer(Modifier.weight(1f))
                        LevelBadge(achievement.tier, tint, AchievementCardMetrics.compactBadgeEdge, IosType.headline.bold, AchievementCardMetrics.compactBadgeCorner)
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.hairlineSpacing)) {
                        Text(achievement.kind.title, style = IosType.headline, color = palette.textPrimary, maxLines = 2)
                        Text(achievement.valueLine, style = IosType.caption, color = palette.textSecondary, maxLines = 2)
                    }
                }
                Spacer(Modifier.weight(1f))
                AbstandCardBottomProgress(progress)
            }
        } else {
            Row(
                Modifier.fillMaxWidth().padding(AppTheme.Layout.cardPadding),
                verticalAlignment = Alignment.Top,
                horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.rowSpacing),
            ) {
                AchievementIcon(achievement, tint, AchievementCardMetrics.regularIconSize, AchievementCardMetrics.iconSlotWidth)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.hairlineSpacing)) {
                    Text(achievement.kind.title, style = IosType.headline, color = palette.textPrimary, maxLines = 1)
                    Text(achievement.valueLine, style = IosType.subheadline, color = palette.textSecondary, maxLines = 1)
                }
                LevelBadge(achievement.tier, tint, AchievementCardMetrics.regularBadgeEdge, IosType.title3.bold, AppTheme.Layout.achievementBadgeCornerRadius)
            }
            AbstandCardBottomProgress(progress)
        }
    }
    if (showExplanation) {
        AlertDialog(
            onDismissRequest = { showExplanation = false },
            title = { Text(achievement.kind.title) },
            text = { Text(achievement.kind.alertMessage(achievement)) },
            confirmButton = { TextButton(onClick = { showExplanation = false }) { Text("OK") } },
        )
    }
}

@Composable
private fun AchievementIcon(achievement: ListeningAchievementState, tint: Color, size: Dp, slotWidth: Dp) {
    Box(Modifier.width(slotWidth), contentAlignment = Alignment.Center) {
        Icon(SF.named(achievement.kind.systemImage) ?: SF.chartBarFill, contentDescription = null, tint = tint, modifier = Modifier.size(size))
    }
}

@Composable
private fun LevelBadge(tier: ListeningAchievementTier, tint: Color, edge: Dp, font: TextStyle, corner: Dp) {
    val palette = Theme.palette
    val level = tier.levelNumber
    if (level == null) {
        Box(Modifier.size(edge), contentAlignment = Alignment.Center) {
            Icon(SF.lockFill, contentDescription = tier.accessibilityLabel, tint = tint)
        }
        return
    }
    val shape = RoundedCornerShape(corner)
    val solid = tier.usesSolidBadgeFill
    Box(
        Modifier.size(edge)
            .background(tint.copy(alpha = tint.alpha * tier.badgeFillOpacity(palette.isDarkLike).toFloat()), shape)
            .let { if (solid) it else it.border(AchievementCardMetrics.badgeBorderWidth, tint, shape) },
        contentAlignment = Alignment.Center,
    ) {
        Text("$level", style = font, color = if (solid) palette.foregroundOnAccent(Theme.accent) else tint)
    }
}
