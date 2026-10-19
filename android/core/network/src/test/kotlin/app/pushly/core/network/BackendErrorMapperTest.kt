package app.pushly.core.network

import app.pushly.core.common.AppErrorCode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException

/** Same table as iOS ModelTests.errorMapping. */
class BackendErrorMapperTest {
    @Test
    fun postgresCodes() {
        assertEquals(AppErrorCode.Conflict, BackendErrorMapper.map("23505", "").code)
        assertEquals(AppErrorCode.ValidationFailed, BackendErrorMapper.map("22023", "minimum age is 16").code)
        assertEquals(AppErrorCode.Unknown, BackendErrorMapper.map(null, "?").code)
        assertEquals(AppErrorCode.ValidationFailed, BackendErrorMapper.map(RuntimeException("code 22023: invalid username")).code)
    }

    @Test
    fun networkErrorsAreRetryable() {
        val e = BackendErrorMapper.map(IOException("offline"))
        assertEquals(AppErrorCode.Network, e.code)
        assertTrue(e.retryable)
    }

    @Test
    fun backendConfigRequiresUrlAndKey() {
        assertNull(BackendConfig.fromBuild("", ""))
        assertNull(BackendConfig.fromBuild("https://x.supabase.co", " "))
        assertEquals("https://x.supabase.co", BackendConfig.fromBuild("https://x.supabase.co", "key")?.url)
    }
}
