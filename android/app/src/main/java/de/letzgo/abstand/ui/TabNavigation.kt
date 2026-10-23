package de.letzgo.abstand.ui

import androidx.activity.compose.BackHandler
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.staticCompositionLocalOf

/**
 * Gepushte Seite (iOS: `NavigationLink`-Ziel im `NavigationStack` des Tabs). Buch-Detail, Autor,
 * Serie, Search, Settings und deren Unterseiten implementieren es und rufen [TabNavigator.push] auf.
 */
interface TabDestination {
    /** Stabiler Schlüssel (für gespeicherten UI-Zustand der Seite, z. B. `book/<id>`). */
    val key: String

    @Composable
    fun Content(navigator: TabNavigator)
}

/**
 * Back-Stack der App (iOS: ein `NavigationStack` pro Tab). Android hat keine Tab-Leiste mehr, daher
 * genau ein Navigator; Wurzel = Home, nicht im Stack.
 */
@Stable
class TabNavigator {
    val backStack = mutableStateListOf<TabDestination>()

    val canPop: Boolean get() = backStack.isNotEmpty()

    fun push(destination: TabDestination) {
        backStack.add(destination)
    }

    /** `false`, wenn bereits an der Wurzel. */
    fun pop(): Boolean {
        if (backStack.isEmpty()) return false
        backStack.removeAt(backStack.lastIndex)
        return true
    }

    fun popToRoot() = backStack.clear()

    /** Pusht [destination], außer eine Seite derselben Art liegt schon oben (Doppeltippen). */
    fun pushUnlessOnTop(destination: TabDestination) {
        if (backStack.lastOrNull()?.let { it::class == destination::class } == true) return
        push(destination)
    }
}

/** Navigator der App-Shell (`null` außerhalb der Shell). */
val LocalTabNavigator = staticCompositionLocalOf<TabNavigator?> { null }

/** Zeigt Wurzel oder oberste Seite des Stacks; System-Zurück poppt. UI-Zustand je Seite bleibt erhalten. */
@Composable
fun TabStackHost(navigator: TabNavigator, root: @Composable () -> Unit) {
    val holder = rememberSaveableStateHolder()
    val top = navigator.backStack.lastOrNull()
    BackHandler(enabled = top != null) { navigator.pop() }
    if (top == null) {
        holder.SaveableStateProvider("root") { root() }
    } else {
        holder.SaveableStateProvider(top.key) { top.Content(navigator) }
    }
}
