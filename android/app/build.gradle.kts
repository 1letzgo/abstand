import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("com.google.devtools.ksp")
}

// Optionaler Debug-Server für den Emulator (android/local.properties, nie committen):
//   abstand.debug.server=https://abs.example.org
//   abstand.debug.user=…
//   abstand.debug.password=…
val localProps = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun localString(key: String) = "\"" + (localProps.getProperty(key) ?: "").replace("\"", "\\\"") + "\""

fun gitCommitCount(): Int = runCatching {
    providers.exec { commandLine("git", "rev-list", "--count", "HEAD") }.standardOutput.asText.get().trim().toInt()
}.getOrDefault(1)

/** Eine Versionsquelle für beide Plattformen: `MARKETING_VERSION` aus dem Xcode-Projekt. */
fun iosMarketingVersion(): String = runCatching {
    val pbx = rootProject.file("../abstand.xcodeproj/project.pbxproj").readText()
    Regex("MARKETING_VERSION = ([^;]+);").find(pbx)!!.groupValues[1].trim()
}.getOrDefault("0.0")

android {
    namespace = "de.letzgo.abstand"
    compileSdk = 36
    defaultConfig {
        applicationId = "de.letzgo.abstand"
        minSdk = 26
        targetSdk = 36
        // Monoton ohne manuelles Hochzählen: Anzahl Commits (-PabstandVersionCode=… überschreibt).
        versionCode = (project.findProperty("abstandVersionCode") as String?)?.toIntOrNull() ?: gitCommitCount()
        versionName = iosMarketingVersion()
        buildConfigField("String", "DEBUG_SERVER", "\"\"")
        buildConfigField("String", "DEBUG_USER", "\"\"")
        buildConfigField("String", "DEBUG_PASSWORD", "\"\"")
    }
    // Verteilung: `sideload` = eigene APK, `play` = Google Play (vorbereitet, noch ohne Unterschiede).
    flavorDimensions += "distribution"
    productFlavors {
        create("sideload") { dimension = "distribution" }
        create("play") { dimension = "distribution" }
    }
    sourceSets {
        // Golden-Files, die iOS und Android gemeinsam nutzen (gleiche Dekodierung/Logik beweisen).
        getByName("test").resources.srcDir("../../shared/fixtures")
    }
    // Upload-Key liegt außerhalb von Repo und iCloud; ohne ihn ist der Release-Build unsigniert.
    val signingFile = file("${System.getProperty("user.home")}/Library/Application Support/abstand-signing/keystore.properties")
    signingConfigs {
        if (signingFile.exists()) create("upload") {
            val props = Properties().apply { signingFile.inputStream().use { load(it) } }
            storeFile = file(props.getProperty("storeFile"))
            storePassword = props.getProperty("storePassword")
            keyAlias = props.getProperty("keyAlias")
            keyPassword = props.getProperty("keyPassword")
        }
    }
    buildTypes {
        debug {
            // Gleicher Key wie Release: Debug und Release installieren übereinander ohne Datenverlust.
            signingConfigs.findByName("upload")?.let { signingConfig = it }
            buildConfigField("String", "DEBUG_SERVER", localString("abstand.debug.server"))
            buildConfigField("String", "DEBUG_USER", localString("abstand.debug.user"))
            buildConfigField("String", "DEBUG_PASSWORD", localString("abstand.debug.password"))
        }
        release {
            ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a") }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfigs.findByName("upload")?.let { signingConfig = it }
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true; buildConfig = true }
    packaging { jniLibs { useLegacyPackaging = true } }
    testOptions { unitTests.isReturnDefaultValues = true }
}

ksp { arg("room.schemaLocation", "$projectDir/schemas") }

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.12.01")
    implementation(composeBom)
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-process:2.8.7")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.animation:animation")
    implementation("com.squareup.okhttp3:okhttp:5.3.2")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    implementation("io.coil-kt.coil3:coil-compose:3.0.4")
    implementation("io.coil-kt.coil3:coil-network-okhttp:3.0.4")
    val media3 = "1.5.1"
    implementation("androidx.media3:media3-exoplayer:$media3")
    implementation("androidx.media3:media3-exoplayer-hls:$media3")
    implementation("androidx.media3:media3-datasource-okhttp:$media3")
    implementation("androidx.media3:media3-session:$media3")
    val room = "2.6.1"
    implementation("androidx.room:room-runtime:$room")
    implementation("androidx.room:room-ktx:$room")
    ksp("androidx.room:room-compiler:$room")
    implementation("androidx.work:work-runtime-ktx:2.10.0")
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
    testImplementation("junit:junit:4.13.2")
}
