package de.letzgo.abstand.ui.reader

import android.content.Context
import android.content.ContextWrapper
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.fragment.app.FragmentActivity
import androidx.fragment.app.FragmentContainerView
import androidx.fragment.app.FragmentFactory
import androidx.fragment.app.FragmentManager
import de.letzgo.abstand.R
import org.readium.r2.navigator.epub.EpubNavigatorFragment

/**
 * Fragment-Verwaltung für den Readium-EPUB-Navigator (iOS: `ReadiumNavigatorHost` /
 * `ReaderNavigatorContainerViewController`).
 *
 * Der Navigator lebt im Fragment-Manager der Activity. Nach Activity-Neuaufbau würde Android ihn
 * wiederherstellen — ohne Publikation. Deshalb liefert [fragmentFactory] dafür Readiums Dummy und
 * [removeRestored] entfernt ihn sofort wieder; der Reader baut sich aus dem gespeicherten Locator neu.
 */
object ReaderFragments {
    const val TAG = "abstand-reader-navigator"

    private val dummyFactory: FragmentFactory by lazy { EpubNavigatorFragment.createDummyFactory() }

    /** Activity-Fabrik (vor `super.onCreate` setzen). */
    val fragmentFactory: FragmentFactory = object : FragmentFactory() {
        override fun instantiate(classLoader: ClassLoader, className: String) =
            if (className == EpubNavigatorFragment::class.java.name) {
                dummyFactory.instantiate(classLoader, className)
            } else {
                super.instantiate(classLoader, className)
            }
    }

    /** Direkt nach `super.onCreate`: wiederhergestellte Navigatoren entfernen, bevor sie Views bauen. */
    fun removeRestored(fm: FragmentManager) {
        val stale = fm.fragments.filter { it is EpubNavigatorFragment || it.tag == TAG }
        if (stale.isEmpty()) return
        val tx = fm.beginTransaction()
        stale.forEach(tx::remove)
        tx.commitNowAllowingStateLoss()
    }
}

/** Füllt die Fläche mit dem Navigator-Fragment; beim Verlassen wird es entfernt. */
@Composable
internal fun EpubNavigatorHost(fragment: EpubNavigatorFragment, modifier: Modifier = Modifier) {
    val activity = LocalContext.current.findFragmentActivity() ?: return
    AndroidView(
        modifier = modifier,
        factory = { ctx -> FragmentContainerView(ctx).apply { id = R.id.abstand_reader_navigator_container } },
    )
    DisposableEffect(fragment) {
        val fm = activity.supportFragmentManager
        // Asynchron: der Container hängt erst nach dem Anwenden der Komposition im View-Baum.
        fm.beginTransaction()
            .setReorderingAllowed(true)
            .replace(R.id.abstand_reader_navigator_container, fragment, ReaderFragments.TAG)
            .commitAllowingStateLoss()
        // Transaktionen laufen in Reihenfolge — auch ein noch ausstehendes `replace` wird so aufgehoben.
        onDispose { if (!fm.isDestroyed) fm.beginTransaction().remove(fragment).commitAllowingStateLoss() }
    }
}

private tailrec fun Context.findFragmentActivity(): FragmentActivity? = when (this) {
    is FragmentActivity -> this
    is ContextWrapper -> baseContext.findFragmentActivity()
    else -> null
}
