package app.pushly.core.common

/**
 * Account rules (doc 02 PS-03, doc 16 §2). Mirrors iOS `AccountRules`, tools/reference/pushly_ref/account.py and the
 * server; verified against shared/test-vectors/account/rules.json.
 */
object AccountRules {
    const val MIN_AGE = 16
    const val MIN_BIRTH_YEAR = 1900

    private val USERNAME = Regex("^[A-Za-z0-9_.]{3,20}$")
    private val PLACEHOLDER = Regex("^u_[0-9a-f]{12}$")

    enum class UsernameError(val wire: String) { TooShort("tooShort"), TooLong("tooLong"), InvalidCharacters("invalidCharacters"), Reserved("reserved") }

    enum class BirthYearError(val wire: String) { Invalid("invalid"), TooYoung("tooYoung") }

    /** Length counts Unicode code points (like the server and the Python reference). */
    fun usernameError(name: String): UsernameError? {
        val length = name.codePointCount(0, name.length)
        return when {
            length < 3 -> UsernameError.TooShort
            length > 20 -> UsernameError.TooLong
            !USERNAME.matches(name) -> UsernameError.InvalidCharacters
            PLACEHOLDER.matches(name) -> UsernameError.Reserved
            else -> null
        }
    }

    fun birthYearError(birthYear: Int, currentYear: Int): BirthYearError? = when {
        birthYear < MIN_BIRTH_YEAR || birthYear > currentYear -> BirthYearError.Invalid
        currentYear - birthYear < MIN_AGE -> BirthYearError.TooYoung
        else -> null
    }

    /** Birth years offered in the picker, newest allowed first. */
    fun selectableBirthYears(currentYear: Int): List<Int> = ((MIN_BIRTH_YEAR + 6)..(currentYear - MIN_AGE)).reversed()
}

/** Semantic app version (`major.minor.patch`; a build suffix after a space is ignored). */
data class AppVersion(val major: Int, val minor: Int, val patch: Int) : Comparable<AppVersion> {
    override fun compareTo(other: AppVersion): Int =
        compareValuesBy(this, other, AppVersion::major, AppVersion::minor, AppVersion::patch)

    companion object {
        fun parse(value: String): AppVersion? {
            val core = value.trim().split(" ").firstOrNull() ?: return null
            val parts = core.split(".")
            if (parts.size !in 1..3 || parts.any { p -> p.isEmpty() || !p.all { it in '0'..'9' } }) return null
            val numbers = parts.map { it.toIntOrNull() ?: return null } + List(3 - parts.size) { 0 }
            return AppVersion(numbers[0], numbers[1], numbers[2])
        }

        /** Unparseable versions never force an update. */
        fun updateRequired(app: String, minSupported: String): Boolean {
            val a = parse(app) ?: return false
            val m = parse(minSupported) ?: return false
            return a < m
        }
    }
}

object EmailRules {
    private val PLAUSIBLE = Regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]{2,}$")

    /** Deliberately loose: the server validates; this only enables the button. */
    fun isPlausible(email: String): Boolean = PLAUSIBLE.matches(email.trim())
}
