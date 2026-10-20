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
include(":feature:wakeflow")
