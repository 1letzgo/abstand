package de.letzgo.abstand.data

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS: `AbstandTrustDelegate.acceptsSelfSigned(host:)` — nur echte private Hosts. */
class LocalHostsTest {
    @Test
    fun privateHostsAccepted() {
        for (h in listOf("localhost", "nas.local", "127.0.0.1", "10.0.0.1", "192.168.1.5", "172.16.0.1", "172.31.255.255", "100.64.0.1", "[::1]", "fd00::1", "fe80::1%en0")) {
            assertTrue(h, LocalHosts.acceptsSelfSigned(h))
        }
    }

    @Test
    fun publicNamesWithIpPrefixRejected() {
        for (h in listOf(
            "10.0.0.1.example.com", "192.168.1.5.nip.io", "10.0.0.1.", ".10.0.0.1", "10..0.1", "10.0.0",
            "10.0.0.1.2", "10.0.0.0256", "10.0.0.256", "+10.0.0.1", "10.0.0.-1", "10.0.0.٣", "8.8.8.8",
            "172.32.0.1", "example.com",
        )) {
            assertFalse(h, LocalHosts.acceptsSelfSigned(h))
        }
    }
}
