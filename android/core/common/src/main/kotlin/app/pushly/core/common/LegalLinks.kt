package app.pushly.core.common

/** Public legal + support pages (GitHub Pages site built from docs/legal by tools/site). Same URLs on iOS. */
object LegalLinks {
    /** Version of the Terms / Privacy Policy accepted with "Get started" (docs/legal effective date). */
    const val VERSION = "2026-10-21"

    const val BASE = "https://danoujesky.github.io/Pushly---PushUp-Wars/"
    const val PRIVACY = BASE + "privacy.html"
    const val TERMS = BASE + "terms.html"
    const val COMMUNITY = BASE + "community.html"
    const val DELETE_ACCOUNT = BASE + "delete-account.html"
    const val SUPPORT = BASE + "support.html"
    const val SUPPORT_EMAIL = "dany.oujesky@gmail.com"
}
