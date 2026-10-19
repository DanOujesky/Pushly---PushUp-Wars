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
include(":core:common")
include(":core:designsystem")
include(":core:network")
include(":engine:rep")
include(":feature:onboarding")
include(":feature:profile")
