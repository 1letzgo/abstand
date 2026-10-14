package de.letzgo.abstand.ui

import androidx.activity.compose.BackHandler
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.staticCompositionLocalOf
import de.letzgo.abstand.model.MainTab

/**
 * Ziel innerhalb eines Tabs (iOS: `NavigationLink`-Ziel im `NavigationStack` des Tabs). Spätere
 * Ports (Buch-Detail, Autor, Serie, Settings-Unterseiten, …) implementieren es und rufen
 * [TabNavigator.push] auf.
 */
interface TabDestination {
    /** Stabiler Schlüssel (für gespeicherten UI-Zustand der Seite, z. B. `book/<id>`). */
    val key: String

    @Composable
    fun Content(navigator: TabNavigator)
}

/** Eigener Back-Stack je Tab (iOS: ein `NavigationStack` pro Tab). Wurzel = Tab-Root, nicht im Stack. */
@Stable
class TabNavigator(val tab: MainTab) {
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
}

/** Navigator des Tabs, in dem die aktuelle Seite liegt (`null` außerhalb der Tab-Shell). */
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
