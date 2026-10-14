package de.letzgo.abstand

import android.os.Bundle
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.fragment.app.FragmentActivity
import de.letzgo.abstand.ui.AbstandTheme
import de.letzgo.abstand.ui.AppRoot
import de.letzgo.abstand.ui.reader.ReaderFragments

/** `FragmentActivity` (statt `ComponentActivity`): der Readium-EPUB-Navigator ist ein Fragment. */
class MainActivity : FragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.auto(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.auto(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT),
        )
        // Vor `super.onCreate`: wiederhergestellte Reader-Fragmente brauchen die Readium-Fabrik.
        supportFragmentManager.fragmentFactory = ReaderFragments.fragmentFactory
        super.onCreate(savedInstanceState)
        ReaderFragments.removeRestored(supportFragmentManager)
        setContent { AbstandTheme { AppRoot() } }
    }
}
