// Pure Kotlin/JVM module — no Android dependencies, so it is unit-testable anywhere (doc 03 §3).
plugins {
    alias(libs.plugins.kotlin.jvm)
}

kotlin { jvmToolchain(17) }

dependencies {
    testImplementation(libs.junit)
}
