package app.pushly

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.viewmodel.compose.viewModel
import app.pushly.core.common.AppError
import app.pushly.core.common.AppErrorCode
import app.pushly.core.common.AuthCallback
import app.pushly.core.common.KeyValueStore
import app.pushly.core.common.PLog
import app.pushly.core.common.PushPrompt
import app.pushly.core.common.Reporter
import app.pushly.core.designsystem.ArenaBackground
import app.pushly.core.designsystem.LogoMark
import app.pushly.core.designsystem.Pill
import app.pushly.core.designsystem.PrimaryButton
import app.pushly.core.designsystem.PushlyTheme
import app.pushly.core.designsystem.ScreenTitle
import app.pushly.core.designsystem.TokenText
import app.pushly.core.designsystem.Wordmark
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.generated.TokenColor
import app.pushly.core.designsystem.generated.TypographyTokens
import app.pushly.core.designsystem.resolve
import app.pushly.core.designsystem.toTextStyle
import app.pushly.core.network.BackendConfig
import app.pushly.core.network.SupabaseBackend
import app.pushly.feature.alarm.AlarmSystem
import app.pushly.feature.alarm.WakeTab
import app.pushly.feature.battle.BattleHubScreen
import app.pushly.feature.battle.BattleHubViewModel
import app.pushly.feature.battle.BattlePlayer
import app.pushly.feature.clan.ClanTabScreen
import app.pushly.feature.clan.ClanViewModel
import app.pushly.feature.onboarding.ProfileSetupScreen
import app.pushly.feature.onboarding.ProfileSetupViewModel
import app.pushly.feature.onboarding.SignInScreen
import app.pushly.feature.onboarding.SignInViewModel
import app.pushly.feature.onboarding.WelcomeScreen
import app.pushly.feature.profile.AccountScreen
import app.pushly.feature.profile.AccountViewModel
import app.pushly.feature.profile.ProfileScreen
import app.pushly.feature.profile.ProfileViewModel
import app.pushly.feature.social.FriendsScreen
import app.pushly.feature.social.FriendsViewModel
import app.pushly.feature.social.RanksScreen
import app.pushly.feature.social.RanksViewModel
import app.pushly.feature.social.UserProfileScreen
import app.pushly.feature.social.UserProfileViewModel
import app.pushly.feature.stats.AchievementsScreen
import app.pushly.feature.stats.StatsScreen
import app.pushly.feature.stats.StatsViewModel
import app.pushly.feature.wakeflow.KeystoreDeviceKey
import app.pushly.feature.wakeflow.LogSigner
import app.pushly.feature.wakeflow.SessionServices
import app.pushly.push.PushRegistrar
import kotlinx.coroutines.launch

/** The device signer shared by rep logs and the push token (one device row per install, D-047). */
internal var pushSigner: LogSigner? = null

class MainActivity : ComponentActivity() {
    private val router = AppRouter()
    private lateinit var session: AppSession

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        session = createSession(applicationContext)
        if (BuildConfig.DEBUG) DebugScreens.apply(this, intent, session, router)
        // Dark-only arena look (D-033): light system-bar icons regardless of the system theme.
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
        )
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
        // Notification taps carry the deep link as an extra (FCM data `link`, doc 15 §3).
        val url = intent?.dataString ?: intent?.getStringExtra("link") ?: return
        if (AuthCallback.matches(url)) {
            lifecycleScope.launch { session.handleAuthCallback(url) }
        } else {
            router.handle(url)
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
        // Alarm sync only while signed in (P2-09); alarms themselves never need the server.
        AlarmSystem.get(context).sync.transport = {
            if (backend.currentUserId() != null) backend::syncAlarms else null
        }
        SessionServices.shared?.let { services ->
            // Signed envelopes with this install's key (D-047); the key is registered once per launch.
            val signer = LogSigner(KeystoreDeviceKey.loadOrCreate(), services.appVersion, backend::registerDevice)
            pushSigner = signer
            val send: suspend (String) -> String = { log -> backend.submitRepSession(signer.envelope(log)) }
            services.uploader.transport = { if (backend.currentUserId() != null) send else null }
            services.fetchServerMs = backend::serverTimeMs
            services.summary = { if (backend.currentUserId() != null) backend.wakeSummary() else throw AppError(AppErrorCode.Unauthenticated, "signed out") }
        }
        // Report anywhere (doc 16 §5): the designsystem's ReportAction calls this.
        Reporter.handler = { target, reason ->
            try {
                backend.report(target.json, reason)
                true
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                PLog.warning { "Report failed: ${e.message}" }
                false
            }
        }
        return AppSession(backend, backend, backend, store, BuildConfig.VERSION_NAME, stats = backend, social = backend, clans = backend, account = backend, battles = backend)
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
            AppSession.State.Launching -> LaunchScreen()
            AppSession.State.UpdateRequired -> ForceUpdateScreen()
            AppSession.State.Welcome -> WelcomeScreen(onContinue = session::welcomeFinished)
            AppSession.State.SignIn -> {
                val vm = viewModel(key = "signin") {
                    SignInViewModel(session.auth) { scope.launch { session.signedIn() } }
                }
                val linkFailed by session.linkSignInFailed.collectAsStateWithLifecycle()
                val activity = LocalContext.current
                SignInScreen(
                    vm,
                    linkFailed = linkFailed,
                    onGuest = session::continueAsGuest,
                    google = if (GoogleAuth.isEnabled) ({ GoogleAuth.signIn(activity) }) else null,
                )
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
        PushSetup(session, state)
    }
}

/** Push (P6-06): register the FCM token while signed in; in-context explainer → POST_NOTIFICATIONS (Android 13+). */
@Composable
private fun PushSetup(session: AppSession, state: AppSession.State) {
    val signedIn = state is AppSession.State.Main && state.profile != null
    LaunchedEffect(signedIn) {
        val account = session.account
        val signer = pushSigner
        if (signedIn && account != null && signer != null) PushRegistrar.register(account, signer) else PushRegistrar.clear()
    }
    val context = LocalContext.current
    val prefs = remember { context.getSharedPreferences("pushly.session", Context.MODE_PRIVATE) }
    var reason by remember { mutableStateOf<PushPrompt.Reason?>(null) }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { }
    DisposableEffect(Unit) {
        PushPrompt.handler = { r ->
            val needs = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
            if (needs && !prefs.getBoolean("push.explainerShown", false)) reason = r
        }
        onDispose { PushPrompt.handler = {} }
    }
    val r = reason ?: return
    fun answer(allow: Boolean) {
        reason = null
        prefs.edit().putBoolean("push.explainerShown", true).apply()
        if (allow && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
    }
    AlertDialog(
        containerColor = ColorTokens.BgElevated.resolve(),
        onDismissRequest = { answer(false) },
        title = {
            Text(stringResource(when (r) {
                PushPrompt.Reason.Friends -> R.string.push_title_friends
                PushPrompt.Reason.Clan -> R.string.push_title_clan
                PushPrompt.Reason.Battles -> R.string.push_title_battles
            }))
        },
        text = { Text(stringResource(R.string.push_text)) },
        confirmButton = { TextButton(onClick = { answer(true) }) { Text(stringResource(R.string.push_allow)) } },
        dismissButton = { TextButton(onClick = { answer(false) }) { Text(stringResource(R.string.push_not_now)) } },
    )
}

@Composable
private fun LaunchScreen() {
    val loading = stringResource(R.string.launch_loading)
    ArenaBackground(
        Modifier.semantics(mergeDescendants = true) { contentDescription = loading },
        glowAlignment = Alignment.Center,
        glowOffset = DpOffset(0.dp, 40.dp),
    ) {
        Column(
            Modifier.fillMaxSize(),
            verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xl - 4.dp, Alignment.CenterVertically),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            LogoMark(112.dp)
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                Wordmark(token = TypographyTokens.DisplayLogo)
                TokenText(stringResource(R.string.launch_tagline), TypographyTokens.LabelLogo, color = ColorTokens.TextTertiary.resolve())
            }
        }
        CircularProgressIndicator(
            color = ColorTokens.TextTertiary.resolve(),
            strokeWidth = 2.dp,
            modifier = Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(bottom = SpacingTokens.Xxxl).size(24.dp),
        )
    }
}

/** Shown when remote config says this version is no longer supported (doc 03 §7). */
@Composable
private fun ForceUpdateScreen() {
    val context = LocalContext.current
    ArenaBackground(glow = ColorTokens.BrandVolt, glowAlignment = Alignment.Center, glowOffset = DpOffset(0.dp, (-60).dp)) {
        Column(
            Modifier.fillMaxSize().safeDrawingPadding().padding(SpacingTokens.L),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Column(
                Modifier.weight(1f).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(SpacingTokens.L, Alignment.CenterVertically),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Spacer(Modifier.height(SpacingTokens.Xl))
                Box(
                    Modifier
                        .size(120.dp)
                        .clip(RoundedCornerShape(36.dp))
                        .background(ColorTokens.BgSurface.resolve())
                        .border(1.dp, ColorTokens.StrokeStrong.resolve(), RoundedCornerShape(36.dp))
                        .clearAndSetSemantics {},
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        painterResource(R.drawable.ic_update),
                        contentDescription = null,
                        tint = ColorTokens.BrandVoltText.resolve(),
                        modifier = Modifier.size(56.dp),
                    )
                }
                ScreenTitle(stringResource(R.string.update_title), textAlign = TextAlign.Center)
                TokenText(
                    stringResource(R.string.update_text),
                    TypographyTokens.Body,
                    color = ColorTokens.TextSecondary.resolve(),
                    textAlign = TextAlign.Center,
                    modifier = Modifier.widthIn(max = 320.dp),
                )
                Pill(stringResource(R.string.update_saved), color = ColorTokens.StateSuccessText)
            }
            PrimaryButton(stringResource(R.string.update_now), onClick = {
                val uri = Uri.parse("market://details?id=${context.packageName}")
                runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, uri)) }
                    .onFailure {
                        val web = Uri.parse("https://play.google.com/store/apps/details?id=${context.packageName}")
                        runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, web)) }
                    }
            })
        }
    }
}

private data class TabSpec(val tab: AppTab, val label: Int, val icon: Int, val subtitle: Int, val glow: TokenColor)

private val tabs = listOf(
    TabSpec(AppTab.Wake, R.string.tab_wake, R.drawable.ic_tab_wake, R.string.placeholder_wake, ColorTokens.BrandFlame),
    TabSpec(AppTab.Battle, R.string.tab_battle, R.drawable.ic_tab_battle, R.string.placeholder_battle, ColorTokens.BrandVolt),
    TabSpec(AppTab.Clan, R.string.tab_clan, R.drawable.ic_tab_clan, R.string.placeholder_clan, ColorTokens.BrandCyan),
    TabSpec(AppTab.Ranks, R.string.tab_ranks, R.drawable.ic_tab_ranks, R.string.placeholder_ranks, ColorTokens.LeagueGold),
    TabSpec(AppTab.Profile, R.string.tab_profile, R.drawable.ic_tab_profile, R.string.placeholder_profile, ColorTokens.BrandVolt),
)

@Composable
private fun MainTabs(session: AppSession, router: AppRouter, state: AppSession.State.Main) {
    val selected by router.selectedTab.collectAsState()
    Scaffold(
        containerColor = ColorTokens.BgBase.resolve(),
        bottomBar = {
            Column {
                HorizontalDivider(color = ColorTokens.StrokeSubtle.resolve())
                NavigationBar(containerColor = ColorTokens.BgSurface.resolve(), tonalElevation = 0.dp) {
                    tabs.forEach { spec ->
                        NavigationBarItem(
                            selected = selected == spec.tab,
                            onClick = { router.select(spec.tab) },
                            icon = { Icon(painterResource(spec.icon), contentDescription = null) },
                            label = { Text(stringResource(spec.label), style = TypographyTokens.Tab.toTextStyle()) },
                            colors = NavigationBarItemDefaults.colors(
                                selectedIconColor = ColorTokens.BrandFlameText.resolve(),
                                selectedTextColor = ColorTokens.BrandFlameText.resolve(),
                                indicatorColor = ColorTokens.BrandFlame.resolve().copy(alpha = 0.14f),
                                unselectedIconColor = ColorTokens.TextDisabled.resolve(),
                                unselectedTextColor = ColorTokens.TextDisabled.resolve(),
                            ),
                        )
                    }
                }
            }
        },
    ) { padding ->
        val profileKey by router.profile.collectAsState()
        val profileSocial = session.social.takeIf { state.profile != null }
        val key = profileKey
        if (key != null && profileSocial != null) {
            val vm = viewModel(key = "user-${key.userId}-${key.username}") { UserProfileViewModel(profileSocial, key.userId, key.username) }
            BackHandler { router.openProfile(null) }
            UserProfileScreen(vm, onBack = { router.openProfile(null) }, modifier = Modifier.padding(padding))
            return@Scaffold
        }
        val ranksService = session.social.takeIf { state.profile != null }
        val clanService = session.clans.takeIf { state.profile != null }
        val battleService = session.battles.takeIf { state.profile != null }
        if (selected == AppTab.Profile) {
            ProfileTab(session, router, state, Modifier.padding(padding))
        } else if (selected == AppTab.Wake) {
            WakeTab(Modifier.padding(padding))
        } else if (selected == AppTab.Battle && battleService != null) {
            val social = session.social
            val stats = session.stats
            val searchFn: (suspend (String) -> String)? = if (social != null) { q -> social.searchUsers(q) } else null
            val addFn: (suspend (String) -> Unit)? = if (social != null) { id -> social.sendFriendRequest(id) } else null
            val hubVm = viewModel(key = "battles-${state.profile?.id}") {
                BattleHubViewModel(
                    battleService, social?.let { s -> suspend { s.listFriends() } },
                    stats?.let { st -> suspend { st.battleStats() } },
                    searchFn, addFn,
                )
            }
            BattleHubScreen(hubVm, battleService, SessionServices.shared, Modifier.padding(padding),
                player = state.profile?.let { BattlePlayer(it.username, it.avatarPreset) })
        } else if (selected == AppTab.Clan && clanService != null) {
            val clanVm = viewModel(key = "clan-${state.profile?.id}") { ClanViewModel(clanService) }
            ClanTabScreen(clanVm, Modifier.padding(padding))
        } else if (selected == AppTab.Ranks && ranksService != null) {
            val ranksVm = viewModel(key = "ranks-${state.profile?.id}") { RanksViewModel(ranksService) }
            RanksScreen(ranksVm, Modifier.padding(padding))
        } else {
            val spec = tabs.first { it.tab == selected }
            PlaceholderScreen(spec, Modifier.padding(padding))
        }
    }
}

/** Profile, with Stats & achievements pushed on top (back returns to Profile). */
@Composable
private fun ProfileTab(session: AppSession, router: AppRouter, state: AppSession.State.Main, modifier: Modifier) {
    var page by rememberSaveable { mutableStateOf(ProfilePage.Profile) }
    val scope = rememberCoroutineScope()
    val statsService = session.stats.takeIf { state.profile != null }
    val socialService = session.social.takeIf { state.profile != null }
    if (page == ProfilePage.Friends && socialService != null) {
        val friendsVm = viewModel(key = "friends-${state.profile?.id}") { FriendsViewModel(socialService) }
        BackHandler { page = ProfilePage.Profile }
        FriendsScreen(friendsVm, state.profile?.username, onBack = { page = ProfilePage.Profile }, modifier = modifier,
            onOpenProfile = { id -> router.openProfile(AppRouter.ProfileKey(userId = id)) })
        return
    }
    val accountService = session.account.takeIf { state.profile != null }
    if (page == ProfilePage.Account && accountService != null) {
        val accountVm = viewModel(key = "account-${state.profile?.id}") { AccountViewModel(accountService) { session.signedOut() } }
        BackHandler { page = ProfilePage.Profile }
        AccountScreen(
            accountVm,
            onBack = { page = ProfilePage.Profile },
            onSignInAgain = {
                scope.launch {
                    runCatching { session.auth?.signOut() }
                    session.signedOut()
                }
            },
            modifier = modifier,
        )
        return
    }
    if (page == ProfilePage.Stats || page == ProfilePage.Achievements) if (statsService != null) {
        val statsVm = viewModel(key = "stats-${state.profile?.id}") { StatsViewModel(statsService) }
        BackHandler { page = if (page == ProfilePage.Achievements) ProfilePage.Stats else ProfilePage.Profile }
        if (page == ProfilePage.Stats) {
            StatsScreen(
                statsVm, onBack = { page = ProfilePage.Profile }, onAchievements = { page = ProfilePage.Achievements },
                modifier = modifier, onFight = { router.select(AppTab.Battle) },
            )
        } else {
            AchievementsScreen(statsVm, onBack = { page = ProfilePage.Stats }, modifier = modifier)
        }
        return
    }
    val vm = viewModel(key = "profile-${state.profile?.id ?: "guest"}") {
        ProfileViewModel(state.profile, session.profiles, session.auth, session::signedOut, session::createAccountFromGuest)
    }
    ProfileScreen(
        vm,
        appVersion = "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})",
        modifier = modifier,
        onOpenStats = statsService?.let { { page = ProfilePage.Stats } },
        onOpenFriends = socialService?.let { { page = ProfilePage.Friends } },
        onOpenAccount = accountService?.let { { page = ProfilePage.Account } },
    )
}

private enum class ProfilePage { Profile, Stats, Achievements, Friends, Account }

/** Temporary tab content until each feature is built (roadmap P0-08). */
@Composable
private fun PlaceholderScreen(spec: TabSpec, modifier: Modifier = Modifier) {
    ArenaBackground(modifier, glow = spec.glow, glowAlignment = Alignment.Center, glowOffset = DpOffset(0.dp, (-40).dp)) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(SpacingTokens.L),
            verticalArrangement = Arrangement.spacedBy(SpacingTokens.L, Alignment.CenterVertically),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Box(
                Modifier
                    .size(104.dp)
                    .clip(RoundedCornerShape(30.dp))
                    .background(ColorTokens.BgSurface.resolve())
                    .border(1.dp, ColorTokens.StrokeSubtle.resolve(), RoundedCornerShape(30.dp))
                    .clearAndSetSemantics {},
                contentAlignment = Alignment.Center,
            ) {
                Icon(painterResource(spec.icon), contentDescription = null, tint = spec.glow.resolve(), modifier = Modifier.size(44.dp))
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                ScreenTitle(stringResource(spec.label), textAlign = TextAlign.Center)
                TokenText(stringResource(spec.subtitle), TypographyTokens.Body, color = ColorTokens.TextSecondary.resolve(), textAlign = TextAlign.Center)
            }
            Pill(stringResource(R.string.coming_soon), color = ColorTokens.BrandFlameText)
        }
    }
}
