package de.letzgo.abstand.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

/** iOS: `AppTheme` (Platzhalter, wird aus AppTheme.swift portiert). */
object AppTheme {
    /** Dark-Mode-Akzent (Standard Gelb). */
    val defaultAccent = Color(251, 192, 45)
    /** Light-Mode-Akzent (Standard #00374A). */
    val defaultLightAccent = Color(0, 55, 74)
}

@Composable
fun AbstandTheme(content: @Composable () -> Unit) {
    val scheme = if (isSystemInDarkTheme()) darkColorScheme(primary = AppTheme.defaultAccent)
    else lightColorScheme(primary = AppTheme.defaultLightAccent)
    MaterialTheme(colorScheme = scheme, content = content)
}
