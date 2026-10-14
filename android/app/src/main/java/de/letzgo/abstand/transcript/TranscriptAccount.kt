package de.letzgo.abstand.transcript

import de.letzgo.abstand.model.AppModel
import java.io.File

/**
 * iOS: `PlayerTranscriptCacheStore.updateActiveAccount` (vom `AppModel` gesetzt). Android leitet das
 * Account-Verzeichnis bei Bedarf aus der Session ab — so braucht der Transkript-Teil keinen Haken im
 * Session-Lebenszyklus und sieht nach einem Accountwechsel sofort das richtige Verzeichnis.
 */
object TranscriptAccount {
    fun current(): File? = runCatching { AppModel.shared.session.cacheAccountDir() }.getOrNull()
}
