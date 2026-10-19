package de.letzgo.abstand.model

import de.letzgo.abstand.data.AbsLibrary
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HomeLibraryLogicTest {
    private val b1 = AbsLibrary("B1", "Books", "book")
    private val b2 = AbsLibrary("B2", "Kids", "book")
    private val p1 = AbsLibrary("P1", "Podcasts", "podcast")

    @Test
    fun choicesListBooksBeforePodcastsWithPrefixedIds() {
        val choices = HomeLibraryLogic.choices(listOf(b1, b2), listOf(p1))
        assertEquals(listOf("b:B1", "b:B2", "p:P1"), choices.map { it.id })
        assertFalse(choices[0].isPodcast)
        assertTrue(choices[2].isPodcast)
    }

    @Test
    fun resolvePrefersStoredThenFocusedThenFirst() {
        val choices = HomeLibraryLogic.choices(listOf(b1, b2), listOf(p1))
        assertEquals("p:P1", HomeLibraryLogic.resolve(choices, "p:P1", focusedBooksLibraryId = "B2")?.id)
        assertEquals("b:B2", HomeLibraryLogic.resolve(choices, "b:gone", focusedBooksLibraryId = "B2")?.id)
        assertEquals("p:P1", HomeLibraryLogic.resolve(choices, "", focusedPodcastLibraryId = "P1")?.id)
        assertEquals("b:B1", HomeLibraryLogic.resolve(choices, null)?.id)
        assertNull(HomeLibraryLogic.resolve(emptyList(), "b:B1"))
    }

    @Test
    fun choiceIdsTrimLibraryIds() {
        assertEquals("b:B1", HomeLibraryLogic.booksChoiceId(" B1 "))
        assertEquals("p:P1", HomeLibraryLogic.podcastChoiceId("P1\n"))
    }
}
