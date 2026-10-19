package app.pushly.core.common

import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Locates repository files from unit tests (Gradle runs tests with the module directory as working dir). */
object RepoFile {
    fun read(relative: String): String {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            val candidate = File(dir, relative)
            if (candidate.exists()) return candidate.readText()
            dir = dir.parentFile
        }
        error("Not found from ${File("").absolutePath}: $relative")
    }
}

private val json = Json { ignoreUnknownKeys = true }

/** Same vectors as iOS AccountRulesTests (CLAUDE.md §4.1). */
class SharedVectorsTest {
    @Serializable data class UsernameCase(val name: String, val error: String?)
    @Serializable data class BirthYearCase(val birthYear: Int, val currentYear: Int, val error: String?)
    @Serializable data class VersionCase(val app: String, val minSupported: String, val updateRequired: Boolean)
    @Serializable data class Vectors(val usernames: List<UsernameCase>, val birthYears: List<BirthYearCase>, val versions: List<VersionCase>)

    private val vectors = json.decodeFromString(Vectors.serializer(), RepoFile.read("shared/test-vectors/account/rules.json"))

    @Test
    fun usernames() {
        for (v in vectors.usernames) assertEquals("username ${v.name}", v.error, AccountRules.usernameError(v.name)?.wire)
    }

    @Test
    fun birthYears() {
        for (v in vectors.birthYears) {
            assertEquals("birth year ${v.birthYear}", v.error, AccountRules.birthYearError(v.birthYear, v.currentYear)?.wire)
        }
    }

    @Test
    fun versions() {
        for (v in vectors.versions) {
            assertEquals("${v.app} vs ${v.minSupported}", v.updateRequired, AppVersion.updateRequired(v.app, v.minSupported))
        }
    }

    @Test
    fun birthYearPickerStartsAtMinimumAge() {
        val years = AccountRules.selectableBirthYears(2026)
        assertEquals(2010, years.first())
        assertTrue(years.all { AccountRules.birthYearError(it, 2026) == null })
    }

    @Test
    fun emailPlausibility() {
        assertTrue(EmailRules.isPlausible("  Dan@Example.com "))
        assertFalse(EmailRules.isPlausible("not-an-email"))
    }

    @Test
    fun decodesProfileFixture() {
        val p = json.decodeFromString(Profile.serializer(), RepoFile.read("shared/contracts/fixtures/profile.json"))
        assertEquals("AnaFit", p.username)
        assertTrue(p.onboardingCompleted)
        assertEquals("CZ", p.country)
        assertEquals(2000, p.birthYear)
        assertEquals(ProfileVisibility.Public, p.profileVisibility)
        assertEquals(7, p.level)
    }

    @Test
    fun remoteConfigFromFixture() {
        val rows = json.decodeFromString(ListSerializer(AppConfigRow.serializer()), RepoFile.read("shared/contracts/fixtures/app_config.json"))
        val config = RemoteConfig.fromRows(rows, "android")
        assertEquals("1.0.0", config.minSupportedVersion)
        assertEquals(false, config.killSwitches["battles"])
    }

    @Test
    fun patchOmitsNullFields() {
        val encoder = Json { explicitNulls = false }
        val text = encoder.encodeToString(ProfilePatch.serializer(), ProfilePatch(username = "Dan", birthYear = 2000))
        assertEquals("""{"username":"Dan","birth_year":2000}""", text)
    }
}
