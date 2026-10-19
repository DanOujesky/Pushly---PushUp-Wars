// RepEngine is PURE (doc 03 §3): no Android, camera or MediaPipe imports here.
plugins {
    alias(libs.plugins.kotlin.jvm)
}

kotlin { jvmToolchain(17) }

dependencies {
    testImplementation(libs.junit)
}
