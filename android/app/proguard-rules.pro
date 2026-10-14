# kotlinx.serialization: generierte Serializer der @Serializable-Klassen behalten.
-keepattributes *Annotation*, InnerClasses, Signature, EnclosingMethod
-dontnote kotlinx.serialization.**
-keepclassmembers class kotlinx.serialization.json.** { *** Companion; }
-keepclasseswithmembers class kotlinx.serialization.json.** { kotlinx.serialization.KSerializer serializer(...); }
-keep,includedescriptorclasses class de.letzgo.abstand.**$$serializer { *; }
-keepclassmembers class de.letzgo.abstand.** { *** Companion; }
-keepclasseswithmembers class de.letzgo.abstand.** { kotlinx.serialization.KSerializer serializer(...); }

-dontwarn okhttp3.internal.platform.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
