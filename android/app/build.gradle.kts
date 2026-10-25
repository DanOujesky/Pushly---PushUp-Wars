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

// Firebase (push only, P6-06) without the google-services plugin: values from app/google-services.json (gitignored;
// CI writes it from the GOOGLE_SERVICES_JSON secret) or FIREBASE_* properties. Each package (app.pushly,
// app.pushly.debug) uses its own Firebase app when the file has one. Missing = a build without push.
@Suppress("UNCHECKED_CAST")
fun firebaseFor(pkg: String): Map<String, String> {
    val file = file("google-services.json")
    if (!file.exists()) return emptyMap()
    val root = groovy.json.JsonSlurper().parse(file) as Map<String, Any?>
    val project = root["project_info"] as? Map<String, Any?> ?: emptyMap()
    val clients = (root["client"] as? List<Map<String, Any?>>).orEmpty()
    fun packageOf(c: Map<String, Any?>) =
        ((c["client_info"] as? Map<String, Any?>)?.get("android_client_info") as? Map<String, Any?>)?.get("package_name")
    val client = clients.firstOrNull { packageOf(it) == pkg } ?: clients.firstOrNull { packageOf(it) == "app.pushly" } ?: emptyMap()
    return mapOf(
        "FIREBASE_PROJECT_ID" to (project["project_id"] as? String).orEmpty(),
        "FIREBASE_SENDER_ID" to (project["project_number"] as? String).orEmpty(),
        "FIREBASE_APP_ID" to ((client["client_info"] as? Map<String, Any?>)?.get("mobilesdk_app_id") as? String).orEmpty(),
        "FIREBASE_API_KEY" to ((client["api_key"] as? List<Map<String, Any?>>)?.firstOrNull()?.get("current_key") as? String).orEmpty(),
    )
}
/** Google's public test AdMob app id (doc 13 §1): used until the real one is set. */
val TEST_ADMOB_APP_ID = "ca-app-pub-3940256099942544~3347511713"

val firebaseKeys = listOf("FIREBASE_PROJECT_ID", "FIREBASE_SENDER_ID", "FIREBASE_APP_ID", "FIREBASE_API_KEY")
fun firebaseValue(pkg: String, name: String): String = firebaseFor(pkg)[name]?.takeIf { it.isNotBlank() } ?: secret(name)

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
        for (name in firebaseKeys) buildConfigField("String", name, "\"${firebaseValue("app.pushly", name)}\"")
        // Google sign-in (D-061): the web client ID is public; Android needs its OAuth client (SHA-1) before enabling.
        buildConfigField("String", "GOOGLE_WEB_CLIENT_ID", "\"${secret("GOOGLE_WEB_CLIENT_ID")}\"")
        buildConfigField("boolean", "GOOGLE_SIGN_IN_ANDROID", secret("GOOGLE_SIGN_IN_ANDROID").ifBlank { "false" })
        // Ads + Pushly Pro (doc 13, D-073): public client IDs from local.properties / CI variables; blank = Google's
        // test IDs and no purchases. Debug and staging always use test ads (never click your own real ads).
        manifestPlaceholders["admobAppId"] = secret("ADMOB_ANDROID_APP_ID").ifBlank { TEST_ADMOB_APP_ID }
        buildConfigField("String", "ADMOB_BANNER_ID", "\"${secret("ADMOB_ANDROID_BANNER_ID")}\"")
        buildConfigField("String", "ADMOB_INTERSTITIAL_ID", "\"${secret("ADMOB_ANDROID_INTERSTITIAL_ID")}\"")
        buildConfigField("String", "REVENUECAT_ANDROID_KEY", "\"${secret("REVENUECAT_ANDROID_KEY")}\"")
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
            manifestPlaceholders["admobAppId"] = TEST_ADMOB_APP_ID
            buildConfigField("String", "ADMOB_BANNER_ID", "\"\"")
            buildConfigField("String", "ADMOB_INTERSTITIAL_ID", "\"\"")
            buildConfigField("String", "PUSHLY_ENV", "\"local\"")
            for (name in firebaseKeys) buildConfigField("String", name, "\"${firebaseValue("app.pushly.debug", name)}\"")
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
    implementation(project(":feature:stats"))
    implementation(project(":feature:social"))
    implementation(project(":feature:clan"))
    implementation(project(":feature:battle"))
    implementation(project(":feature:shop"))
    implementation(libs.lifecycle.viewmodel.compose)
    implementation(libs.lifecycle.runtime.compose)
    implementation(libs.firebase.messaging)
    implementation(libs.credentials)
    implementation(libs.credentials.play.services)
    implementation(libs.googleid)

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
