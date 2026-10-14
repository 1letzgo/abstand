package de.letzgo.abstand.data

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.json.JsonPrimitive
import java.io.InterruptedIOException
import java.net.ConnectException
import java.net.NoRouteToHostException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import kotlin.math.roundToInt

// iOS: AppModelSupportTypes.swift

/** iOS: `ContinueRefreshAttemptResult` — Ergebnis eines Online-Continue-Refreshs. */
data class ContinueRefreshAttemptResult(
    var appliedOnline: Boolean = false,
    var error: Throwable? = null,
    /**
     * `true`, sobald `loadStartDashboard` tatsächlich einen Request gestartet hat (nicht nur früh per
     * Cache/Guard zurückgekehrt ist).
     */
    var attemptedNetwork: Boolean = false,
)

/** iOS: `AbstandErrorFilter` — abgebrochene Requests/Tasks nicht als Fehlerdialog anzeigen. */
object AbstandErrorFilter {
    fun isBenignCancellationMessage(message: String): Boolean {
        val desc = message.swiftTrim().lowercase()
        if (desc.isEmpty()) return false
        if (desc == "cancelled" || desc == "canceled") return true
        if (desc.contains("cancelled") || desc.contains("canceled")) return true
        if (desc.contains("error -999")) return true
        return false
    }

    fun isBenignCancellation(error: Throwable): Boolean {
        if (error is CancellationException) return true
        // OkHttp: `Call.cancel()` → IOException("Canceled") (iOS: `URLError.cancelled`).
        if (error is java.io.IOException && error !is InterruptedIOException && error.message == "Canceled") return true
        error.cause?.let { if (it !== error && isBenignCancellation(it)) return true }
        if (isBenignCancellationMessage(error.message ?: "")) return true
        return false
    }

    /** Timeouts/Netz-Hiccups beim Kaltstart mit Cache — kein Fehlerdialog. */
    fun isTransientNetworkError(error: Throwable): Boolean {
        when (error) {
            is SocketTimeoutException, is ConnectException, is UnknownHostException, is NoRouteToHostException -> return true
            is InterruptedIOException -> if (error.message?.lowercase()?.contains("timeout") == true) return true
        }
        val desc = (error.message ?: "").lowercase()
        return desc.contains("timed out") || desc.contains("timeout")
    }
}

/** iOS: `ServerM4BEncodeJob` — laufende/abgeschlossene M4B-Encode-Jobs. */
@kotlinx.serialization.Serializable(with = ServerM4BEncodeJobSerializer::class)
data class ServerM4BEncodeJob(
    var id: String,
    var title: String,
    var author: String,
    /** Millisekunden seit 1970 (iOS: `Date`). */
    var startedAt: Long,
    var status: Status,
    var message: String? = null,
) {
    enum class Status(val rawValue: String) {
        running("running"), finished("finished"), failed("failed"), cancelled("cancelled");

        companion object {
            fun from(raw: String) = entries.firstOrNull { it.rawValue == raw }
        }
    }

    val isActive: Boolean get() = status == Status.running
}

object ServerM4BEncodeJobSerializer : SwiftObjectSerializer<ServerM4BEncodeJob>("ServerM4BEncodeJob") {
    override fun decode(c: JObj) = ServerM4BEncodeJob(
        id = c.string("id"),
        title = c.string("title"),
        author = c.string("author"),
        startedAt = c.long("startedAt"),
        status = ServerM4BEncodeJob.Status.from(c.string("status")) ?: SwiftJson.mismatch("status", "Status"),
        message = c.stringOrNull("message"),
    )

    override fun encode(v: ServerM4BEncodeJob) = jsonObjectOf {
        put("id", JsonPrimitive(v.id))
        put("title", JsonPrimitive(v.title))
        put("author", JsonPrimitive(v.author))
        put("startedAt", JsonPrimitive(v.startedAt))
        put("status", JsonPrimitive(v.status.rawValue))
        putIfPresent("message", v.message)
    }
}

/**
 * iOS: `M4BEncodeProgressStore` — %-Updates für M4B-Encode, eigener Zustand, damit Book Detail
 * nicht bei jedem Tick neu zeichnet. Veröffentlicht nur ganze Prozent.
 */
class M4BEncodeProgressStore {
    private val _percentById = MutableStateFlow<Map<String, Double>>(emptyMap())
    val percentById: StateFlow<Map<String, Double>> = _percentById.asStateFlow()
    private val lastPublishedWholePercent = HashMap<String, Int>()

    fun setPercent(id: String, percent: Double) {
        val whole = percent.coerceIn(0.0, 100.0).roundedSwift().toInt()
        if (lastPublishedWholePercent[id] == whole) return
        lastPublishedWholePercent[id] = whole
        _percentById.value = _percentById.value + (id to whole.toDouble())
    }

    fun percentLabel(id: String): String? = _percentById.value[id]?.let { "${it.roundToInt()}%" }

    fun clear(id: String) {
        if (_percentById.value[id] == null && lastPublishedWholePercent[id] == null) return
        _percentById.value = _percentById.value - id
        lastPublishedWholePercent.remove(id)
    }

    fun clearAll() {
        if (_percentById.value.isEmpty() && lastPublishedWholePercent.isEmpty()) return
        _percentById.value = emptyMap()
        lastPublishedWholePercent.clear()
    }
}
