package de.letzgo.abstand.data

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import okhttp3.ConnectionPool
import okhttp3.Dispatcher
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.Request
import java.net.Socket
import java.security.KeyStore
import java.security.cert.X509Certificate
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLEngine
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509ExtendedTrustManager
import javax.net.ssl.X509TrustManager

/**
 * HTTP-Stack (iOS: `AbstandHTTPSession` + `AbstandTrustDelegate`). Ein OkHttp-Client für API,
 * Player (Media3) und Downloads; Cover (Coil) über einen Geschwister-Client mit eigenem Dispatcher.
 * Jeder Request an einen Server mit gespeicherten Custom-Headern bekommt sie automatisch
 * (iOS: `AbstandCustomHeadersStore.apply(to:)`), ebenso den Bearer-Token, wenn er an den aktiven
 * Server geht und noch keinen `Authorization`-Header trägt.
 */
object Net {
    /** Liefert Origin + Bearer der aktiven Session (gesetzt vom Session-Store). */
    @Volatile var activeBearer: (() -> Pair<String, String>?)? = null

    private val serverInterceptor = Interceptor { chain ->
        val request = chain.request()
        val builder = request.newBuilder()
        CustomHeadersStore.headers(request.url).forEach { (name, value) ->
            if (request.header(name) == null) builder.header(name, value)
        }
        // Login/Logout/Refresh tragen wie auf iOS keinen Bearer (eigene Token-Header).
        val path = request.url.encodedPath
        val isAuthEndpoint = path.endsWith("/login") || path.endsWith("/logout") || path.endsWith("/auth/refresh")
        if (!isAuthEndpoint && request.header("Authorization") == null) {
            activeBearer?.invoke()?.let { (origin, token) ->
                if (CustomHeadersStore.originKey(request.url) == origin && token.isNotBlank()) {
                    builder.header("Authorization", "Bearer $token")
                }
            }
        }
        chain.proceed(builder.build())
    }

    private const val CONNECT_TIMEOUT_SECONDS = 10L
    private const val READ_TIMEOUT_SECONDS = 60L

    private val pool = ConnectionPool()

    private val debugLog: ((String) -> Unit)? =
        if (de.letzgo.abstand.BuildConfig.DEBUG) { msg -> android.util.Log.d("AbstandNet", msg) } else null

    val dns = AbstandDns(log = debugLog)

    /** Basis-Client: API, Media3, Downloads. Alle anderen Clients sind `client.newBuilder()…`. */
    val client: OkHttpClient by lazy { build() }

    /** Cover auf eigenem Dispatcher, damit API-Calls nicht hinter Dutzenden Thumbnails warten. */
    val imageClient: OkHttpClient by lazy {
        client.newBuilder().dispatcher(Dispatcher().apply { maxRequestsPerHost = 8 }).build()
    }

    private fun build(): OkHttpClient {
        val trust = LocalTrustManager(systemTrustManager())
        val ssl = SSLContext.getInstance("TLS").apply { init(null, arrayOf(trust), null) }
        return OkHttpClient.Builder()
            .connectTimeout(CONNECT_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .readTimeout(READ_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            // Happy Eyeballs wie iOS-URLSession.
            .fastFallback(true)
            .dns(dns)
            .eventListenerFactory { NetEventListener(dns, debugLog) }
            .dispatcher(Dispatcher().apply { maxRequestsPerHost = 16 })
            .connectionPool(pool)
            .sslSocketFactory(ssl.socketFactory, trust)
            .hostnameVerifier { host, session ->
                LocalHosts.acceptsSelfSigned(host) ||
                    javax.net.ssl.HttpsURLConnection.getDefaultHostnameVerifier().verify(host, session)
            }
            .addInterceptor(serverInterceptor)
            .build()
    }

    /** Beim Account-/Serverwechsel: laufende Requests abbrechen, Pool leeren. */
    fun resetConnections() {
        runCatching { client.dispatcher.cancelAll(); imageClient.dispatcher.cancelAll(); pool.evictAll() }
        dns.forgetFailures()
    }

    @Volatile private var defaultNetwork: Network? = null

    /** Leert den Pool bei Netzwechsel (WLAN ↔ Mobil, VPN): alte Sockets würden nur scheitern. */
    fun watchNetworkChanges(context: Context) {
        val cm = context.getSystemService(ConnectivityManager::class.java) ?: return
        runCatching {
            cm.registerDefaultNetworkCallback(object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    val previous = defaultNetwork
                    defaultNetwork = network
                    if (previous != null && previous != network) onNetworkChanged()
                }

                override fun onLost(network: Network) {
                    if (network == defaultNetwork) onNetworkChanged()
                }
            })
        }
    }

    private fun onNetworkChanged() {
        pool.evictAll()
        dns.forgetFailures()
    }

    private fun systemTrustManager(): X509TrustManager {
        val factory = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm())
        factory.init(null as KeyStore?)
        return factory.trustManagers.filterIsInstance<X509TrustManager>().first()
    }

    /** iOS: `AbstandHTTPSession.authorizedRequest(url:token:)`. */
    fun authorizedRequest(url: String, token: String?): Request.Builder =
        Request.Builder().url(url).apply {
            token?.trim()?.takeIf { it.isNotEmpty() }?.let { header("Authorization", "Bearer $it") }
        }

    /** iOS: `AbstandHTTPSession.authorizedAssetHeaders` — Header für Media3-Datenquellen. */
    fun authorizedAssetHeaders(token: String, url: String): Map<String, String> {
        val headers = url.toHttpUrlOrNull()?.let { CustomHeadersStore.headers(it) }.orEmpty().toMutableMap()
        headers["Authorization"] = "Bearer $token"
        return headers
    }
}

/** iOS: `AbstandTrustDelegate.acceptsSelfSigned(host:)` — LAN, mDNS, Tailscale, private IPv6. */
object LocalHosts {
    fun acceptsSelfSigned(rawHost: String): Boolean {
        var host = rawHost.lowercase().trim('[', ']')
        host.indexOf('%').takeIf { it >= 0 }?.let { host = host.substring(0, it) }
        if (host == "localhost" || host.endsWith(".local")) return true
        if (host.contains(":")) return isLocalIPv6(host)
        val octets = host.split(".").mapNotNull { it.toIntOrNull() }
        if (octets.size != 4 || octets.any { it !in 0..255 }) return false
        val (a, b) = octets[0] to octets[1]
        return a == 127 || a == 10 || (a == 192 && b == 168) || (a == 172 && b in 16..31) || (a == 100 && b in 64..127)
    }

    private fun isLocalIPv6(host: String): Boolean {
        if (host == "::1") return true
        val first = host.split(":").firstOrNull()?.toIntOrNull(16) ?: return false
        return (first and 0xFE00) == 0xFC00 || (first and 0xFFC0) == 0xFE80
    }
}

/** Erst Systemprüfung; eine fehlerhafte Kette wird nur für lokale Hosts akzeptiert (wie iOS). */
private class LocalTrustManager(private val system: X509TrustManager) : X509ExtendedTrustManager() {
    override fun checkServerTrusted(chain: Array<out X509Certificate>, authType: String, socket: Socket?) {
        val host = (socket as? javax.net.ssl.SSLSocket)?.handshakeSession?.peerHost ?: socket?.inetAddress?.hostAddress
        check(chain, authType, host)
    }
    override fun checkServerTrusted(chain: Array<out X509Certificate>, authType: String, engine: SSLEngine?) =
        check(chain, authType, engine?.peerHost)
    override fun checkServerTrusted(chain: Array<out X509Certificate>, authType: String) = check(chain, authType, null)

    private fun check(chain: Array<out X509Certificate>, authType: String, host: String?) {
        try {
            system.checkServerTrusted(chain, authType)
        } catch (e: Exception) {
            if (host == null || !LocalHosts.acceptsSelfSigned(host)) throw e
        }
    }

    override fun checkClientTrusted(chain: Array<out X509Certificate>, authType: String, socket: Socket?) = system.checkClientTrusted(chain, authType)
    override fun checkClientTrusted(chain: Array<out X509Certificate>, authType: String, engine: SSLEngine?) = system.checkClientTrusted(chain, authType)
    override fun checkClientTrusted(chain: Array<out X509Certificate>, authType: String) = system.checkClientTrusted(chain, authType)
    override fun getAcceptedIssuers(): Array<X509Certificate> = system.acceptedIssuers
}

/** iOS: `ServerHTTPHeader`. */
@Serializable
data class ServerHTTPHeader(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val value: String,
) {
    val trimmedName get() = name.trim()
    val trimmedValue get() = value.trim()

    /** Nur RFC-7230-Token-Zeichen, nicht reserviert, Wert vorhanden. */
    val isUsable: Boolean
        get() {
            val n = trimmedName
            if (n.isEmpty() || trimmedValue.isEmpty()) return false
            if (n.lowercase() in reservedNames) return false
            return n.all { it in TOKEN_CHARS } && '\n' !in trimmedValue && '\r' !in trimmedValue
        }

    companion object {
        private const val TOKEN_CHARS = "!#$%&'*+-.^_`|~0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
        val reservedNames = setOf(
            "host", "content-length", "content-type", "connection", "transfer-encoding",
            "upgrade", "range", "accept-encoding", "te", "trailer", "keep-alive", "proxy-connection",
            "authorization",
        )

        fun sanitized(headers: List<ServerHTTPHeader>) =
            headers.filter { it.isUsable }.map { it.copy(name = it.trimmedName, value = it.trimmedValue) }
    }
}

/**
 * iOS: `AbstandCustomHeadersStore` — Custom-Header je Server-Origin (Schema+Host+Port) in
 * [Secrets]. Fremde Hosts (Podcast-Verzeichnis, Feed-Cover) bekommen sie nie.
 */
object CustomHeadersStore {
    private const val PREFIX = "de.letzgo.abstand.customHeaders|"
    private val cache = ConcurrentHashMap<String, List<ServerHTTPHeader>>()
    private val serializer = ListSerializer(ServerHTTPHeader.serializer())

    fun originKey(url: HttpUrl): String = "${url.scheme}://${url.host.lowercase()}:${url.port}"

    fun originKeyForServer(raw: String): String? = ServerUrl.normalize(raw)?.let { originKey(it) }

    fun load(forServer: String): List<ServerHTTPHeader> = originKeyForServer(forServer)?.let(::loadOrigin).orEmpty()

    fun save(headers: List<ServerHTTPHeader>, forServer: String): Boolean {
        val key = originKeyForServer(forServer) ?: return false
        val clean = ServerHTTPHeader.sanitized(headers)
        cache.remove(key)
        Secrets.set(PREFIX + key, if (clean.isEmpty()) null else AbsJson.encoder.encodeToString(serializer, clean))
        return true
    }

    fun headers(url: HttpUrl): Map<String, String> =
        loadOrigin(originKey(url)).associate { it.name to it.value }

    private fun loadOrigin(key: String): List<ServerHTTPHeader> = cache.getOrPut(key) {
        Secrets.get(PREFIX + key)?.let { runCatching { AbsJson.decoder.decodeFromString(serializer, it) }.getOrNull() }.orEmpty()
    }
}

/** iOS: `ABSAPIClient.normalizeServerURL`. */
object ServerUrl {
    fun normalize(raw: String): HttpUrl? {
        var s = raw.trim()
        if (s.isEmpty()) return null
        if (!s.contains("://")) s = "https://$s"
        while (s.endsWith("/")) s = s.dropLast(1)
        return s.toHttpUrlOrNull()
    }
}
