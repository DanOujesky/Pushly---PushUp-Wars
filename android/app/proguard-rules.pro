# Release shrinking rules. Add keep rules for reflection-based libraries here.

# MediaPipe Tasks: native code calls back into Java classes by name; options/results are protobuf-lite.
-keep class com.google.mediapipe.** { *; }
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.mediapipe.**
-dontwarn com.google.protobuf.**
# AutoValue / javax annotations referenced by MediaPipe but not shipped.
-dontwarn javax.annotation.**
-dontwarn com.google.auto.value.**

# kotlinx.serialization (supabase-kt, our models).
-keepattributes *Annotation*, InnerClasses, Signature
-keepclassmembers class **$$serializer { *; }
-keepclasseswithmembers class * { kotlinx.serialization.KSerializer serializer(...); }
-keep,includedescriptorclasses class app.pushly.**$$serializer { *; }
-keepclassmembers @kotlinx.serialization.Serializable class app.pushly.** {
    *** Companion;
    kotlinx.serialization.KSerializer serializer(...);
}

# Ktor (supabase-kt) optional platform classes.
-dontwarn org.slf4j.**
-dontwarn io.ktor.**
