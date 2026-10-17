package de.letzgo.abstand.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AppUpdateTest {
    private fun release(tag: String, apk: Boolean = true, draft: Boolean = false, prerelease: Boolean = false, digest: String? = "sha256:ab") =
        AppUpdate.GitRelease(
            tag = tag, name = tag, body = " notes ", draft = draft, prerelease = prerelease, htmlUrl = "https://x/$tag",
            assets = if (apk) listOf(AppUpdate.Asset("abstand.apk", "https://x/$tag.apk", digest)) else emptyList(),
        )

    @Test
    fun picksHighestNewerVersionCode() {
        val r = AppUpdate.newest(listOf(release("abstand-android-500"), release("abstand-android-510"), release("abstand-android-505")), 499)!!
        assertEquals(510, r.versionCode)
        assertEquals("ab", r.sha256)
        assertEquals("notes", r.notes)
    }

    @Test
    fun ignoresOlderDraftsPrereleasesForeignTagsAndMissingApk() {
        val list = listOf(
            release("abstand-android-499"),
            release("abstand-android-600", draft = true),
            release("abstand-android-601", prerelease = true),
            release("stede-android-700"),
            release("abstand-android-602", apk = false),
            release("abstand-android-x"),
        )
        assertNull(AppUpdate.newest(list, 499))
    }
}
