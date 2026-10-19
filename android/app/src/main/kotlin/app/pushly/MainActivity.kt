package app.pushly

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.viewmodel.compose.viewModel
import app.pushly.core.common.AuthCallback
import app.pushly.core.common.KeyValueStore
import app.pushly.core.common.PLog
import app.pushly.core.designsystem.PushlyTheme
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.resolve
import app.pushly.core.network.BackendConfig
import app.pushly.core.network.SupabaseBackend
import app.pushly.feature.onboarding.ProfileSetupScreen
import app.pushly.feature.onboarding.ProfileSetupViewModel
import app.pushly.feature.onboarding.SignInScreen
import app.pushly.feature.onboarding.SignInViewModel
import app.pushly.feature.onboarding.WelcomeScreen
import app.pushly.feature.profile.ProfileScreen
import app.pushly.feature.profile.ProfileViewModel
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private val router = AppRouter()
    private lateinit var session: AppSession

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        installLogging()
        session = createSession(applicationContext)
        enableEdgeToEdge()
        handleIntent(intent)
        setContent {
            PushlyTheme { Root(session, router) }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        val url = intent?.dataString ?: return
        if (AuthCallback.matches(url)) {
            lifecycleScope.launch { session.handleAuthCallback(url) }
        } else {
            router.handle(url)
        }
    }

    private fun installLogging() {
        PLog.debugEnabled = BuildConfig.DEBUG
        PLog.sink = PLog.Sink { level, category, message ->
            val tag = "Pushly/${category.name}"
            when (level) {
                PLog.Level.Debug -> Log.d(tag, message)
                PLog.Level.Info -> Log.i(tag, message)
                PLog.Level.Warning -> Log.w(tag, message)
                PLog.Level.Error -> Log.e(tag, message)
            }
        }
    }

    private fun createSession(context: Context): AppSession {
        val store = SharedPreferencesStore(context)
        val config = BackendConfig.fromBuild(BuildConfig.SUPABASE_URL, BuildConfig.SUPABASE_ANON_KEY)
        if (config == null) {
            PLog.warning { "No backend configured — guest-only build" }
            return AppSession(null, null, null, store, BuildConfig.VERSION_NAME)
        }
        val backend = SupabaseBackend(config)
        return AppSession(backend, backend, backend, store, BuildConfig.VERSION_NAME)
    }
}

private class SharedPreferencesStore(context: Context) : KeyValueStore {
    private val prefs = context.getSharedPreferences("pushly.session", Context.MODE_PRIVATE)
    override fun getBoolean(key: String, default: Boolean): Boolean = prefs.getBoolean(key, default)
    override fun putBoolean(key: String, value: Boolean) {
        prefs.edit().putBoolean(key, value).apply()
    }
}

@Composable
private fun Root(session: AppSession, router: AppRouter) {
    val state by session.state.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) { session.start() }

    Box(Modifier.fillMaxSize().background(ColorTokens.BgBase.resolve())) {
        when (val s = state) {
            AppSession.State.Launching -> Centered { Text("Pushly", style = MaterialTheme.typography.displayMedium) }
            AppSession.State.UpdateRequired -> Centered {
                Text(stringResource(R.string.update_title), style = MaterialTheme.typography.headlineMedium)
                Text(stringResource(R.string.update_text), textAlign = TextAlign.Center, color = ColorTokens.TextSecondary.resolve())
            }
            AppSession.State.Welcome -> WelcomeScreen(onContinue = session::welcomeFinished)
            AppSession.State.SignIn -> {
                val vm = viewModel(key = "signin") {
                    SignInViewModel(session.auth) { scope.launch { session.signedIn() } }
                }
                val linkFailed by session.linkSignInFailed.collectAsStateWithLifecycle()
                SignInScreen(vm, linkFailed = linkFailed, onGuest = session::continueAsGuest)
            }
            is AppSession.State.ProfileSetup -> {
                val profiles = session.profiles
                if (profiles != null) {
                    val vm = viewModel(key = "setup-${s.profile.id}") {
                        ProfileSetupViewModel(s.profile, profiles, onCompleted = session::profileCompleted)
                    }
                    ProfileSetupScreen(vm)
                }
            }
            is AppSession.State.Main -> MainTabs(session, router, s)
        }
    }
}

@Composable
private fun Centered(content: @Composable () -> Unit) {
    Column(
        Modifier.fillMaxSize().padding(SpacingTokens.Gutter),
        verticalArrangement = Arrangement.spacedBy(SpacingTokens.M, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) { content() }
}

private data class TabSpec(val tab: AppTab, val label: Int, val icon: Int, val subtitle: Int)

private val tabs = listOf(
    TabSpec(AppTab.Wake, R.string.tab_wake, R.drawable.ic_tab_wake, R.string.placeholder_wake),
    TabSpec(AppTab.Battle, R.string.tab_battle, R.drawable.ic_tab_battle, R.string.placeholder_battle),
    TabSpec(AppTab.Clan, R.string.tab_clan, R.drawable.ic_tab_clan, R.string.placeholder_clan),
    TabSpec(AppTab.Ranks, R.string.tab_ranks, R.drawable.ic_tab_ranks, R.string.placeholder_ranks),
    TabSpec(AppTab.Profile, R.string.tab_profile, R.drawable.ic_tab_profile, R.string.placeholder_profile),
)

@Composable
private fun MainTabs(session: AppSession, router: AppRouter, state: AppSession.State.Main) {
    val selected by router.selectedTab.collectAsState()
    Scaffold(
        bottomBar = {
            NavigationBar {
                tabs.forEach { spec ->
                    NavigationBarItem(
                        selected = selected == spec.tab,
                        onClick = { router.select(spec.tab) },
                        icon = { Icon(painterResource(spec.icon), contentDescription = null) },
                        label = { Text(stringResource(spec.label)) },
                    )
                }
            }
        },
    ) { padding ->
        if (selected == AppTab.Profile) {
            val vm = viewModel(key = "profile-${state.profile?.id ?: "guest"}") {
                ProfileViewModel(state.profile, session.profiles, session.auth, session::signedOut, session::createAccountFromGuest)
            }
            ProfileScreen(vm, appVersion = "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})", modifier = Modifier.padding(padding))
        } else {
            val spec = tabs.first { it.tab == selected }
            Column(
                Modifier.fillMaxSize().padding(padding).padding(SpacingTokens.Gutter),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(stringResource(spec.label), style = MaterialTheme.typography.displaySmall)
                Text(stringResource(spec.subtitle), style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
            }
        }
    }
}
