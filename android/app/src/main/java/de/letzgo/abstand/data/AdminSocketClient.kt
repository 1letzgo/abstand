package de.letzgo.abstand.data

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import java.util.concurrent.TimeUnit

/** iOS: `ABSAdminSocketClient.Event`. */
sealed class AdminSocketEvent {
    data class TaskProgress(val libraryItemId: String, val percent: Double) : AdminSocketEvent()
    data class TaskFinished(val libraryItemId: String, val action: String, val failed: Boolean) : AdminSocketEvent()
    data object Connected : AdminSocketEvent()
    data object Disconnected : AdminSocketEvent()
}

/**
 * Reiner Protokollteil von iOS `ABSAdminSocketClient` (Engine.IO v4 / Socket.IO-Pakete) — ohne
 * Netz testbar. [handlePacket] liefert die zu sendenden Antworten und erkannte Events.
 */
object AdminSocketProtocol {
    /**
     * [livenessTimeoutMs]: aus dem Engine.IO-Open-Paket (`pingInterval + pingTimeout`). In v4 pingt
     * nur der Server; bleibt so lange jedes Paket aus, gilt die Verbindung als tot.
     */
    data class PacketResult(val replies: List<String> = emptyList(), val events: List<AdminSocketEvent> = emptyList(), val livenessTimeoutMs: Long? = null)

    /** Standard-Frist ohne Open-Paket (Engine.IO-Defaults 25 s + 20 s). */
    const val DEFAULT_LIVENESS_TIMEOUT_MS = 45_000L

    /** iOS: `socketIOWebSocketURL(from:)` — `ws(s)://host[/pfad]/socket.io/?EIO=4&transport=websocket`. */
    fun socketIOWebSocketURL(serverURL: String): String? {
        val url = serverURL.toHttpUrlOrNull() ?: return null
        val scheme = if (url.isHttps) "wss" else "ws"
        val path = url.encodedPath.trimEnd('/')
        val hostPart = if (url.host.contains(':')) "[${url.host}]" else url.host
        val defaultPort = if (url.isHttps) 443 else 80
        val portPart = if (url.port != defaultPort) ":${url.port}" else ""
        return "$scheme://$hostPart$portPart$path/socket.io/?EIO=4&transport=websocket"
    }

    /** `42["name", …args]` — Socket.IO-Event. */
    fun eventFrame(name: String, vararg arguments: String): String =
        "42" + JsonArray(listOf(JsonPrimitive(name)) + arguments.map { JsonPrimitive(it) }).toString()

    /** iOS: `handlePacket` — Engine.IO `0` open, `2` ping, `4` message (Socket.IO `0` connect, `2` event). */
    fun handlePacket(raw: String, token: String): PacketResult {
        if (raw.isEmpty()) return PacketResult()
        val type = raw.first().digitToIntOrNull() ?: return PacketResult()
        val body = raw.substring(1)
        return when (type) {
            0 -> {
                val json = runCatching { AbsJson.decoder.parseToJsonElement(body) as? JsonObject }.getOrNull()
                val interval = json?.get("pingInterval")?.jsonPrimitive?.doubleOrNull
                val timeout = json?.get("pingTimeout")?.jsonPrimitive?.doubleOrNull ?: 20_000.0
                // Socket.IO-Namespace verbinden.
                PacketResult(
                    replies = listOf("40"),
                    livenessTimeoutMs = interval?.let { (maxOf(5_000.0, it) + maxOf(1_000.0, timeout)).toLong() },
                )
            }
            2 -> PacketResult(replies = listOf("3"))
            4 -> {
                val sio = body.firstOrNull()?.digitToIntOrNull() ?: return PacketResult()
                val payload = body.substring(1)
                when (sio) {
                    // Namespace verbunden → Auth.
                    0 -> PacketResult(replies = listOf(eventFrame("auth", token)), events = listOf(AdminSocketEvent.Connected))
                    2 -> PacketResult(events = listOfNotNull(parseEventPayload(payload)))
                    else -> PacketResult()
                }
            }
            else -> PacketResult()
        }
    }

    /** iOS: `parseEventPayload` — `task_progress` / `task_finished` (`task_started` wird ignoriert). */
    fun parseEventPayload(payload: String): AdminSocketEvent? {
        val arr = runCatching { AbsJson.decoder.parseToJsonElement(payload) as? JsonArray }.getOrNull() ?: return null
        val name = (arr.firstOrNull() as? JsonPrimitive)?.takeIf { it.isString }?.content ?: return null
        val obj = arr.getOrNull(1) as? JsonObject ?: return null
        return when (name) {
            "task_progress" -> {
                val lid = obj.stringValue("libraryItemId")?.trim().orEmpty()
                if (lid.isEmpty()) return null
                val p = obj["progress"] as? JsonPrimitive ?: return null
                val percent = p.doubleOrNull ?: return null
                AdminSocketEvent.TaskProgress(lid, percent.coerceIn(0.0, 100.0))
            }
            "task_finished" -> {
                val action = obj.stringValue("action") ?: ""
                val lid = (obj["data"] as? JsonObject)?.stringValue("libraryItemId")?.trim().orEmpty()
                if (lid.isEmpty()) return null
                val failed = (obj["isFailed"] as? JsonPrimitive)?.booleanOrNull ?: false
                AdminSocketEvent.TaskFinished(lid, action, failed)
            }
            else -> null
        }
    }

    /** iOS: Reconnect-Backoff 2, 4, 8 … max. 60 s. */
    fun reconnectDelaySeconds(attempt: Int): Int = minOf(60, 2 shl minOf(attempt, 5))

    private fun JsonObject.stringValue(key: String): String? =
        (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
}

/**
 * iOS: `ABSAdminSocketClient` — minimaler Socket.IO-/Engine.IO-v4-Client über OkHttp-WebSocket
 * ([Net.client]: LAN-Trust + Custom-Header) für Admin-Events (M4B-Encode-Fortschritt). Events
 * kommen auf dem Main-Thread.
 */
class AdminSocketClient(private val http: OkHttpClient = Net.client) {
    var onEvent: ((AdminSocketEvent) -> Unit)? = null
    /** Aktuelles Token beim (Re-)Connect — ein früheres JWT kann nach Stunden rotiert sein. */
    var tokenProvider: (() -> String)? = null

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val wsClient: OkHttpClient by lazy { http.newBuilder().readTimeout(0, TimeUnit.MILLISECONDS).build() }
    private var webSocket: WebSocket? = null
    private var token = ""
    private var baseURL: String? = null
    private var wantsConnection = false
    private var reconnectAttempt = 0
    private var reconnectJob: Job? = null
    /** iOS: `livenessTask` — Server-Pings bleiben aus → Socket abbrechen, `onFailure` reconnectet. */
    private var livenessTimeoutMs = AdminSocketProtocol.DEFAULT_LIVENESS_TIMEOUT_MS
    private var livenessJob: Job? = null

    fun connect(serverURL: String, token: String) {
        val trimmed = token.trim()
        if (trimmed.isEmpty()) return
        // Schon mit demselben Server verbunden (zweiter Encode-Job): nicht neu aufbauen.
        if (wantsConnection && webSocket != null && baseURL == serverURL) return
        wantsConnection = true
        this.token = trimmed
        baseURL = serverURL
        disconnectSocketOnly()
        val wsURL = AdminSocketProtocol.socketIOWebSocketURL(serverURL) ?: return
        val request = runCatching { Request.Builder().url(wsURL).build() }.getOrNull() ?: return
        lateinit var own: WebSocket
        own = wsClient.newWebSocket(request, object : WebSocketListener() {
            override fun onMessage(webSocket: WebSocket, text: String) {
                scope.launch { if (this@AdminSocketClient.webSocket === own) handle(text) }
            }

            override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                val text = bytes.utf8()
                scope.launch { if (this@AdminSocketClient.webSocket === own) handle(text) }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                scope.launch { onSocketEnded(own) }
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                scope.launch { onSocketEnded(own) }
            }
        })
        webSocket = own
        armLivenessWatchdog(own)
    }

    private fun armLivenessWatchdog(socket: WebSocket) {
        livenessJob?.cancel()
        val timeout = livenessTimeoutMs
        livenessJob = scope.launch {
            delay(timeout)
            if (webSocket === socket) socket.cancel()
        }
    }

    fun disconnect() {
        wantsConnection = false
        reconnectAttempt = 0
        disconnectSocketOnly()
        onEvent?.invoke(AdminSocketEvent.Disconnected)
    }

    private fun disconnectSocketOnly() {
        livenessJob?.cancel()
        livenessJob = null
        reconnectJob?.cancel()
        reconnectJob = null
        webSocket?.close(1001, null)
        webSocket = null
    }

    private fun handle(text: String) {
        val result = AdminSocketProtocol.handlePacket(text, token)
        result.livenessTimeoutMs?.let { livenessTimeoutMs = it }
        webSocket?.let { armLivenessWatchdog(it) }
        result.replies.forEach { webSocket?.send(it) }
        result.events.forEach { event ->
            if (event is AdminSocketEvent.Connected) reconnectAttempt = 0
            onEvent?.invoke(event)
        }
    }

    /** Verbindung beendet: nur die aktuelle Instanz reconnectet (mit Backoff), ersetzte bleiben still. */
    private fun onSocketEnded(own: WebSocket) {
        if (webSocket !== own) return
        val base = baseURL
        if (!wantsConnection || base == null) {
            webSocket = null
            onEvent?.invoke(AdminSocketEvent.Disconnected)
            return
        }
        val delaySeconds = AdminSocketProtocol.reconnectDelaySeconds(reconnectAttempt)
        reconnectAttempt += 1
        reconnectJob?.cancel()
        reconnectJob = scope.launch {
            delay(delaySeconds * 1000L)
            if (!wantsConnection || webSocket !== own) return@launch
            val fresh = tokenProvider?.invoke()?.trim().orEmpty()
            webSocket = null
            connect(base, fresh.ifEmpty { token })
        }
    }
}
