package app.pushly.core.common

/** Server error codes (doc 12) plus client-side failures. Mirrors iOS `AppErrorCode`. */
enum class AppErrorCode(val wire: String) {
    Unauthenticated("UNAUTHENTICATED"),
    Forbidden("FORBIDDEN"),
    ValidationFailed("VALIDATION_FAILED"),
    NotFound("NOT_FOUND"),
    Conflict("CONFLICT"),
    RateLimited("RATE_LIMITED"),
    IntegrityFailed("INTEGRITY_FAILED"),
    UpgradeRequired("UPGRADE_REQUIRED"),
    Internal("INTERNAL"),
    Network("NETWORK"),
    Unknown("UNKNOWN");

    companion object {
        fun fromWire(value: String): AppErrorCode = entries.firstOrNull { it.wire == value } ?: Unknown
    }
}

class AppError(
    val code: AppErrorCode,
    override val message: String,
    retryable: Boolean? = null,
) : Exception(message) {
    /** Whether the outbox may retry (doc 03 §5). */
    val retryable: Boolean = retryable ?: (code in setOf(AppErrorCode.RateLimited, AppErrorCode.Internal, AppErrorCode.Network))
}
