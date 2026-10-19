package app.pushly.core.common

/** Small persistent flags (guest mode, welcome seen). Android: SharedPreferences; tests: [InMemoryKeyValueStore]. */
interface KeyValueStore {
    fun getBoolean(key: String, default: Boolean = false): Boolean
    fun putBoolean(key: String, value: Boolean)
}

class InMemoryKeyValueStore : KeyValueStore {
    private val values = mutableMapOf<String, Boolean>()
    override fun getBoolean(key: String, default: Boolean): Boolean = values[key] ?: default
    override fun putBoolean(key: String, value: Boolean) {
        values[key] = value
    }
}
