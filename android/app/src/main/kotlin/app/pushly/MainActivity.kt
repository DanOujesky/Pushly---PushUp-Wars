package app.pushly

import android.content.Intent
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import app.pushly.core.common.PLog
import app.pushly.core.designsystem.PushlyTheme
import app.pushly.core.designsystem.generated.SpacingTokens

class MainActivity : ComponentActivity() {
    private val router = AppRouter()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        installLogging()
        enableEdgeToEdge()
        handleIntent(intent)
        setContent {
            PushlyTheme { RootScreen(router) }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        intent?.dataString?.let(router::handle)
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
private fun RootScreen(router: AppRouter) {
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
        val spec = tabs.first { it.tab == selected }
        PlaceholderScreen(
            title = stringResource(spec.label),
            subtitle = stringResource(spec.subtitle),
            modifier = Modifier.padding(padding),
        )
    }
}

/** Temporary tab content until each feature is built (roadmap P0-08). */
@Composable
private fun PlaceholderScreen(title: String, subtitle: String, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.fillMaxSize().padding(SpacingTokens.Gutter),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(title, style = MaterialTheme.typography.displaySmall)
        Text(
            subtitle,
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
    }
}

@Preview
@Composable
private fun RootPreview() {
    PushlyTheme { RootScreen(AppRouter()) }
}
