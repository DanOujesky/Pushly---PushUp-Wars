// Camera → MediaPipe Pose Landmarker → RepEngine PoseFrame (doc 05 §2–3). The only module that touches CameraX and
// MediaPipe; :engine:rep stays pure. Models come from shared/pose-models (no copies in the repo).
plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
}

android {
    namespace = "app.pushly.engine.pose"
    compileSdk = 36
    defaultConfig { minSdk = 29 }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    sourceSets["main"].assets.srcDir(rootProject.file("../shared/pose-models"))
    androidResources { noCompress += "task" }
}

kotlin {
    compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) }
}

dependencies {
    api(project(":engine:rep"))
    implementation(project(":core:common"))
    api(libs.camera.core)
    implementation(libs.camera.camera2)
    api(libs.camera.lifecycle)
    api(libs.camera.view)
    implementation(libs.mediapipe.tasks.vision)
    implementation(libs.androidx.core.ktx)
    testImplementation(libs.junit)
}
