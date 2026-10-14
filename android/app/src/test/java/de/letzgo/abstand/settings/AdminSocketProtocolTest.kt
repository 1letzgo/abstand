package de.letzgo.abstand.settings

import de.letzgo.abstand.data.AdminSocketEvent
import de.letzgo.abstand.data.AdminSocketProtocol
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS `ABSAdminSocketClient` — Engine.IO-v4/Socket.IO-Rahmen und Event-Parsing. */
class AdminSocketProtocolTest {
    @Test
    fun webSocketUrlKeepsPathAndSwitchesScheme() {
        assertEquals(
            "wss://abs.example.org/socket.io/?EIO=4&transport=websocket",
            AdminSocketProtocol.socketIOWebSocketURL("https://abs.example.org"),
        )
        assertEquals(
            "ws://192.168.1.5:13378/abs/socket.io/?EIO=4&transport=websocket",
            AdminSocketProtocol.socketIOWebSocketURL("http://192.168.1.5:13378/abs/"),
        )
        assertNull(AdminSocketProtocol.socketIOWebSocketURL("not a url"))
    }

    @Test
    fun openPingAndNamespaceConnect() {
        val open = AdminSocketProtocol.handlePacket("0{\"sid\":\"x\",\"pingInterval\":25000,\"pingTimeout\":20000}", "tok")
        assertEquals(listOf("40"), open.replies)
        assertEquals(45_000L, open.livenessTimeoutMs)
        assertEquals(listOf("3"), AdminSocketProtocol.handlePacket("2", "tok").replies)
        val connected = AdminSocketProtocol.handlePacket("40{\"sid\":\"y\"}", "tok\"en")
        assertEquals(listOf("42[\"auth\",\"tok\\\"en\"]"), connected.replies)
        assertEquals(listOf(AdminSocketEvent.Connected), connected.events)
        assertTrue(AdminSocketProtocol.handlePacket("", "t").replies.isEmpty())
        assertTrue(AdminSocketProtocol.handlePacket("x", "t").events.isEmpty())
    }

    @Test
    fun taskProgressAcceptsNumbersAndStringsAndClamps() {
        assertEquals(
            listOf(AdminSocketEvent.TaskProgress("li_1", 42.5)),
            AdminSocketProtocol.handlePacket("42[\"task_progress\",{\"libraryItemId\":\" li_1 \",\"progress\":42.5}]", "t").events,
        )
        assertEquals(
            AdminSocketEvent.TaskProgress("li_2", 17.0),
            AdminSocketProtocol.parseEventPayload("[\"task_progress\",{\"libraryItemId\":\"li_2\",\"progress\":\"17\"}]"),
        )
        assertEquals(
            AdminSocketEvent.TaskProgress("li_3", 100.0),
            AdminSocketProtocol.parseEventPayload("[\"task_progress\",{\"libraryItemId\":\"li_3\",\"progress\":140}]"),
        )
        assertNull(AdminSocketProtocol.parseEventPayload("[\"task_progress\",{\"libraryItemId\":\"\",\"progress\":1}]"))
        assertNull(AdminSocketProtocol.parseEventPayload("[\"task_progress\",{\"libraryItemId\":\"a\"}]"))
    }

    @Test
    fun taskFinishedReadsNestedItemAndFailure() {
        assertEquals(
            AdminSocketEvent.TaskFinished("li_9", "encode-m4b", true),
            AdminSocketProtocol.parseEventPayload("[\"task_finished\",{\"action\":\"encode-m4b\",\"isFailed\":true,\"data\":{\"libraryItemId\":\"li_9\"}}]"),
        )
        assertEquals(
            AdminSocketEvent.TaskFinished("li_9", "", false),
            AdminSocketProtocol.parseEventPayload("[\"task_finished\",{\"data\":{\"libraryItemId\":\"li_9\"}}]"),
        )
        // `task_started` wird erkannt, aber nicht gemeldet (wie iOS).
        assertNull(AdminSocketProtocol.parseEventPayload("[\"task_started\",{\"data\":{\"libraryItemId\":\"li_9\"}}]"))
        assertNull(AdminSocketProtocol.parseEventPayload("not json"))
    }

    @Test
    fun reconnectBackoffCapsAtSixtySeconds() {
        assertEquals(listOf(2, 4, 8, 16, 32, 60, 60), (0..6).map { AdminSocketProtocol.reconnectDelaySeconds(it) })
    }
}
