// Alarm domain (doc 04): AlarmSchedule model, validation, occurrence computation and the OS alarm plan.
// Pure Kotlin/JVM — no Android dependencies — and verified against shared/test-vectors (same files as iOS AlarmDomain).
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) }
}

dependencies {
    api(libs.kotlinx.serialization.json)
    testImplementation(libs.junit)
}
