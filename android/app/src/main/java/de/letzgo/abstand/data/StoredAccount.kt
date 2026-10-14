package de.letzgo.abstand.data

import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonPrimitive
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

// iOS: ABSStoredAccount.swift

/** iOS: `ABSStoredAccount` — persistierter Audiobookshelf-Account (Token + Metadaten für schnellen Wechsel). */
@kotlinx.serialization.Serializable(with = AbsStoredAccountSerializer::class)
data class AbsStoredAccount(
    var accountKey: String,
    var serverURL: String,
    var token: String,
    /** Refresh-Token für `/auth/refresh`; `null` bei Legacy-Sessions (altes, nicht ablaufendes Token). */
    var refreshToken: String? = null,
    var userId: String,
    var username: String,
    var userType: String?,
    var booksLibraryId: String?,
    var podcastsLibraryId: String?,
    var ebooksLibraryId: String?,
    /** Aktive Books-Library-IDs (inkl. Primary); `null` = noch nicht migriert. */
    var activeBooksLibraryIds: List<String>? = null,
    /** Aktive Podcast-Library-IDs (inkl. Primary); `null` = noch nicht migriert. */
    var activePodcastLibraryIds: List<String>? = null,
    /** Millisekunden seit 1970 (iOS: `Date`, kodiert über `ABSJSON` als Int64-Millisekunden). */
    var lastUsedAt: Long,
) {
    val id: String get() = accountKey

    val displayServerHost: String
        get() = AbsApiClient.normalizeServerURL(serverURL)?.toHttpUrlOrNull()?.host ?: serverURL

    val displayUsername: String
        get() = username.swiftTrim().ifEmpty { "Account" }

    companion object {
        fun makeKey(serverURL: String, userId: String): String {
            val normalized = AbsApiClient.normalizeServerURL(serverURL)?.lowercase() ?: serverURL.swiftTrim().lowercase()
            return "$normalized|${userId.swiftTrim()}"
        }
    }
}

object AbsStoredAccountSerializer : SwiftObjectSerializer<AbsStoredAccount>("ABSStoredAccount") {
    override fun decode(c: JObj) = AbsStoredAccount(
        accountKey = c.string("accountKey"),
        serverURL = c.string("serverURL"),
        token = c.string("token"),
        refreshToken = c.stringOrNull("refreshToken"),
        userId = c.string("userId"),
        username = c.string("username"),
        userType = c.stringOrNull("userType"),
        booksLibraryId = c.stringOrNull("booksLibraryId"),
        podcastsLibraryId = c.stringOrNull("podcastsLibraryId"),
        ebooksLibraryId = c.stringOrNull("ebooksLibraryId"),
        activeBooksLibraryIds = c.listOrNull("activeBooksLibraryIds", ElementDecoder.string),
        activePodcastLibraryIds = c.listOrNull("activePodcastLibraryIds", ElementDecoder.string),
        lastUsedAt = c.long("lastUsedAt"),
    )

    override fun encode(v: AbsStoredAccount) = jsonObjectOf {
        put("accountKey", JsonPrimitive(v.accountKey))
        put("serverURL", JsonPrimitive(v.serverURL))
        put("token", JsonPrimitive(v.token))
        putIfPresent("refreshToken", v.refreshToken)
        put("userId", JsonPrimitive(v.userId))
        put("username", JsonPrimitive(v.username))
        putIfPresent("userType", v.userType)
        putIfPresent("booksLibraryId", v.booksLibraryId)
        putIfPresent("podcastsLibraryId", v.podcastsLibraryId)
        putIfPresent("ebooksLibraryId", v.ebooksLibraryId)
        putStrings("activeBooksLibraryIds", v.activeBooksLibraryIds)
        putStrings("activePodcastLibraryIds", v.activePodcastLibraryIds)
        put("lastUsedAt", JsonPrimitive(v.lastUsedAt))
    }
}

/**
 * iOS: `ABSStoredAccountsPersistence` — JSON-Array unter [Keys.storedAccounts], aktiver Account
 * unter [Keys.activeAccountKey]. iOS speichert `Data`, Android denselben JSON-Text als String-Pref.
 */
object AbsStoredAccountsPersistence {
    const val accountsKey = Keys.storedAccounts
    const val activeAccountKey = Keys.activeAccountKey

    private val listSerializer = ListSerializer(AbsStoredAccountSerializer)

    fun decodeAccounts(json: String?): List<AbsStoredAccount> {
        if (json.isNullOrEmpty()) return emptyList()
        return runCatching { AbsJson.decoder.decodeFromString(listSerializer, json) }.getOrDefault(emptyList())
    }

    fun encodeAccounts(accounts: List<AbsStoredAccount>): String = AbsJson.encoder.encodeToString(listSerializer, accounts)

    fun loadAccounts(): List<AbsStoredAccount> = decodeAccounts(Prefs.string(accountsKey))

    fun saveAccounts(accounts: List<AbsStoredAccount>) {
        Prefs.setString(accountsKey, encodeAccounts(accounts))
    }

    fun loadActiveAccountKey(): String? = Prefs.string(activeAccountKey)

    fun saveActiveAccountKey(key: String?) {
        Prefs.setString(activeAccountKey, key?.takeIf { it.isNotEmpty() })
    }
}
