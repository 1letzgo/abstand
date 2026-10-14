plugins {
    id("com.android.application") version "8.10.1" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.1.0" apply false
    id("org.jetbrains.kotlin.plugin.serialization") version "2.1.0" apply false
    id("com.google.devtools.ksp") version "2.1.0-1.0.29" apply false
}

// Build-Output außerhalb von iCloud Drive (iCloud-Sync zerlegt den Dex-Merge, siehe stede/stashy).
// Je Checkout-Pfad ein eigenes Verzeichnis, damit sich Git-Worktrees nicht in die Quere kommen.
val checkoutKey = rootDir.absolutePath.hashCode().toUInt().toString(16)
allprojects {
    layout.buildDirectory.set(file("${System.getProperty("user.home")}/Library/Caches/abstand-android/$checkoutKey/${project.name}"))
}
