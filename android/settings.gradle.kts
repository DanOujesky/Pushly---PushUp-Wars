pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        // LiveKit's audio routing library (com.github.davidliu:audioswitch) is only on JitPack (D-065).
        maven("https://jitpack.io") {
            content { includeGroup("com.github.davidliu") }
        }
    }
}

rootProject.name = "Pushly"

include(":app")
include(":core:alarm")
include(":core:common")
include(":core:designsystem")
include(":core:network")
include(":engine:pose")
include(":engine:rep")
include(":feature:alarm")
include(":feature:onboarding")
include(":feature:profile")
include(":feature:stats")
include(":feature:social")
include(":feature:clan")
include(":feature:battle")
include(":feature:wakeflow")
