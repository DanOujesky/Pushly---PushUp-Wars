import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}

// Backend settings: local.properties (per machine) > environment variables (CI) > backend.properties (committed, public).
fun propertiesFrom(name: String) = Properties().apply {
    rootProject.file(name).takeIf { it.exists() }?.inputStream()?.use { load(it) }
}
val localProperties = propertiesFrom("local.properties")
val publicBackend = propertiesFrom("backend.properties")
fun secret(name: String): String =
    localProperties.getProperty(name) ?: System.getenv(name)?.takeIf { it.isNotBlank() } ?: publicBackend.getProperty(name) ?: ""

android {
    namespace = "app.pushly"
    compileSdk = 36

    defaultConfig {
        applicationId = "app.pushly"
        minSdk = 29
        targetSdk = 36
        // CI sets the build number (Play needs a new versionCode for every upload).
        versionCode = System.getenv("PUSHLY_VERSION_CODE")?.toIntOrNull() ?: 1
        versionName = "0.1.0"
        buildConfigField("String", "SUPABASE_URL", "\"${secret("SUPABASE_URL")}\"")
        buildConfigField("String", "SUPABASE_ANON_KEY", "\"${secret("SUPABASE_ANON_KEY")}\"")
    }

    // Upload key for Google Play (CI secrets only; docs/RELEASING.md). Without it the release build is unsigned.
    val uploadKeystore = System.getenv("PUSHLY_KEYSTORE")?.let { file(it) }?.takeIf { it.exists() }
    signingConfigs {
        if (uploadKeystore != null) {
            create("upload") {
                storeFile = uploadKeystore
                storePassword = System.getenv("PUSHLY_KEYSTORE_PASSWORD")
                keyAlias = "upload"
                keyPassword = System.getenv("PUSHLY_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            buildConfigField("String", "PUSHLY_ENV", "\"local\"")
        }
        create("staging") {
            initWith(getByName("debug"))
            applicationIdSuffix = ".staging"
            buildConfigField("String", "PUSHLY_ENV", "\"staging\"")
            matchingFallbacks += listOf("debug")
        }
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            buildConfigField("String", "PUSHLY_ENV", "\"prod\"")
            if (uploadKeystore != null) signingConfig = signingConfigs.getByName("upload")
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) }
}

dependencies {
    implementation(project(":core:common"))
    implementation(project(":core:designsystem"))
    implementation(project(":engine:rep"))
    implementation(project(":core:network"))
    implementation(project(":feature:alarm"))
    implementation(project(":feature:wakeflow"))
    implementation(project(":feature:onboarding"))
    implementation(project(":feature:profile"))
    implementation(libs.lifecycle.viewmodel.compose)
    implementation(libs.lifecycle.runtime.compose)

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.compose.material3)
    debugImplementation(libs.compose.ui.tooling)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
}
