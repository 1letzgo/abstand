package de.letzgo.abstand.model

import android.content.Context
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import java.util.concurrent.CopyOnWriteArrayList

/**
 * iOS: `AppModel` — auf Android **kein** God-Object, sondern die Fassade, die die fokussierten Stores
 * besitzt und verdrahtet. Singleton aus [de.letzgo.abstand.AbstandApplication]; der Konstruktor macht
 * keine Platten-/Netzarbeit (wie iOS `AppModel.init` nach der Cache-first-Umstellung) — [start] stößt
 * Account-Restore und Bootstrap an.
 *
 * Erweiterung durch spätere Ports (Home, Katalog, Podcasts, Player, Downloads, Stats):
 * eigenen Store als Property hier ergänzen (z. B. `val home = HomeStore(this)`) und, wo er an
 * Bootstrap/Login/Accountwechsel teilnehmen muss, [SessionParticipant] implementieren und im
 * Konstruktor per [register] anmelden — **vor** [start].
 */
class AppModel(context: Context) {
    val appContext: Context = context.applicationContext

    /** Main-gebundener Scope (iOS: `@MainActor`-Tasks des AppModel). */
    val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private val participants = CopyOnWriteArrayList<SessionParticipant>()

    /** Session, Accounts, Bibliothekswahl, Offline-Modus, Tabs (iOS: `AppModelSessionAuth` + Teile von `AppModel`). */
    val session = SessionStore(appContext, scope, participants)

    /** Fortschritt + Lesezeichen (iOS: `progressByItemId`, `bookmarks`) und Bücher-Katalog/Browse. */
    val progress = ProgressStore(this).also { participants.add(it) }

    /** Podcasts-Tab, Verzeichnis, RSS/Admin (iOS: `AppModelCatalogPodcasts`/`AppModelPodcastDirectory`). */
    val podcasts = PodcastStore(this).also { register(it) }

    /**
     * Brücke zum Player (Play/Pause auf Karten, Now Playing). No-op, bis der Player-Port eine
     * Implementierung setzt — vor [start] zuweisen.
     */
    var playbackLauncher: PlaybackLauncher = PlaybackLauncher.None

    /** Brücke zu den Downloads (Karten-Badges, Offline-Home). No-op bis zum Download-Port. */
    var downloadStatus: DownloadStatusSource = DownloadStatusSource.None

    /** Home-Dashboard, Continue listening, Regal-Einstellungen, Fortschritt (iOS: Home-Teile von `AppModel`). */
    val home = HomeStore(this).also { register(it) }

    /** Einheitliche Suche über Bücher und Podcasts (iOS: Such-Teile von `AppModel`). */
    val search = SearchStore(this).also { register(it) }

    /** Bücher-Katalog/Browse (iOS: Katalog-Teile von `AppModel`). */
    val catalog = CatalogStore(this).also { participants.add(it) }

    /** Teilnehmer für Bootstrap-/Session-Lebenszyklus anmelden (Reihenfolge = Aufrufreihenfolge). */
    fun register(participant: SessionParticipant) {
        if (participant !in participants) participants.add(participant)
    }

    fun unregister(participant: SessionParticipant) {
        participants.remove(participant)
    }

    /** Einmalig nach dem Erzeugen: Accounts laden, Events abonnieren, Cache-first-Bootstrap starten. */
    fun start() = session.start()

    companion object {
        @Volatile private var instance: AppModel? = null

        /** Das App-weite Modell (gesetzt in `AbstandApplication.onCreate`). */
        val shared: AppModel get() = instance ?: error("AppModel not initialized — AbstandApplication.onCreate must run first")

        internal fun install(model: AppModel) {
            instance = model
        }
    }
}
