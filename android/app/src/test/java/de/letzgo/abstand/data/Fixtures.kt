package de.letzgo.abstand.data

/** Lädt Golden-Files aus `shared/fixtures` (Test-Ressourcen, siehe app/build.gradle.kts). */
object Fixtures {
    fun text(path: String): String {
        val url = Fixtures::class.java.classLoader!!.getResource(path) ?: error("Fixture fehlt: $path")
        return url.readText()
    }

    fun api(name: String): String = text("api/$name")
}
