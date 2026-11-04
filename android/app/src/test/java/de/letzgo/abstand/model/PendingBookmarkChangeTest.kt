package de.letzgo.abstand.model

import de.letzgo.abstand.data.AbsApiError
import de.letzgo.abstand.data.AbsAudioBookmark
import de.letzgo.abstand.data.AbsJson
import de.letzgo.abstand.data.PendingBookmarkChange
import de.letzgo.abstand.data.PendingBookmarkChange.Kind
import kotlinx.serialization.builtins.ListSerializer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PendingBookmarkChangeTest {
    private val server = AbsAudioBookmark("a", "Server", 10, 1)

    @Test
    fun serverRefreshKeepsPendingCreate() {
        val pending = PendingBookmarkChange(Kind.create, "a", 20, "Offline", 2)
        val merged = PendingBookmarkChange.overlaying(listOf(pending), listOf(server))
        assertEquals(listOf(10, 20), merged.map { it.time })
    }

    @Test
    fun pendingCreateAlreadyOnServerStaysUnique() {
        val pending = PendingBookmarkChange(Kind.create, "a", 10, "Offline", 2)
        val merged = PendingBookmarkChange.overlaying(listOf(pending), listOf(server))
        assertEquals(listOf("Offline"), merged.map { it.title })
    }

    @Test
    fun pendingDeleteHidesServerRow() {
        val pending = PendingBookmarkChange(Kind.delete, "a", 10, "Server", 1)
        assertTrue(PendingBookmarkChange.overlaying(listOf(pending), listOf(server)).isEmpty())
    }

    @Test
    fun sortedByItemThenTime() {
        val changes = listOf(
            PendingBookmarkChange(Kind.create, "b", 1, "x"),
            PendingBookmarkChange(Kind.create, "a", 5, "y"),
        )
        val merged = PendingBookmarkChange.overlaying(changes, listOf(server))
        assertEquals(listOf("a-5", "a-10", "b-1"), merged.map { it.id })
    }

    @Test
    fun jsonRoundTrip() {
        val serializer = ListSerializer(PendingBookmarkChange.serializer())
        val changes = listOf(PendingBookmarkChange(Kind.delete, "a", 10, "t", 3), PendingBookmarkChange(Kind.create, "b", 1, "u"))
        assertEquals(changes, AbsJson.decoder.decodeFromString(serializer, AbsJson.encoder.encodeToString(serializer, changes)))
    }

    @Test
    fun onlyLasting4xxIsPermanent() {
        assertTrue(ProgressStore.isPermanentBookmarkRejection(AbsApiError.HttpStatus(404, null)))
        assertTrue(ProgressStore.isPermanentBookmarkRejection(AbsApiError.HttpStatus(400, null)))
        for (code in listOf(401, 403, 408, 429, 500, 503)) {
            assertFalse(ProgressStore.isPermanentBookmarkRejection(AbsApiError.HttpStatus(code, null)))
        }
        assertFalse(ProgressStore.isPermanentBookmarkRejection(java.io.IOException("offline")))
    }
}
