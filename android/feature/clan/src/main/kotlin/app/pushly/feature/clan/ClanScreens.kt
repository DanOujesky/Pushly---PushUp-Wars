package app.pushly.feature.clan

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.pushly.core.common.ReportTarget
import app.pushly.core.common.Reporter
import app.pushly.core.designsystem.ProBadge
import app.pushly.core.designsystem.AdBannerSlot
import app.pushly.core.designsystem.ArenaBackground
import app.pushly.core.designsystem.Avatar
import app.pushly.core.designsystem.BannerKind
import app.pushly.core.designsystem.InlineBanner
import app.pushly.core.designsystem.MinTouchTarget
import app.pushly.core.designsystem.Pill
import app.pushly.core.designsystem.PrimaryButton
import app.pushly.core.designsystem.ReportDialog
import app.pushly.core.designsystem.ScreenTitle
import app.pushly.core.designsystem.SectionLabel
import app.pushly.core.designsystem.SideViewNotice
import app.pushly.core.designsystem.TokenText
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.RadiusTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.generated.TokenColor
import app.pushly.core.designsystem.generated.TypographyTokens
import app.pushly.core.designsystem.resolve
import kotlinx.coroutines.delay

@Composable
private fun noticeText(n: ClanViewModel.Notice): String? = when (n) {
    ClanViewModel.Notice.None -> null
    ClanViewModel.Notice.Requested -> stringResource(R.string.clan_notice_requested)
    ClanViewModel.Notice.Taken -> stringResource(R.string.clan_notice_taken)
    ClanViewModel.Notice.InvalidName -> stringResource(R.string.clan_notice_invalid_name)
    ClanViewModel.Notice.InvalidTag -> stringResource(R.string.clan_notice_invalid_tag)
    ClanViewModel.Notice.Full -> stringResource(R.string.clan_notice_full)
    ClanViewModel.Notice.Requirements -> stringResource(R.string.clan_notice_requirements)
    ClanViewModel.Notice.AlreadyInClan -> stringResource(R.string.clan_notice_already)
    ClanViewModel.Notice.RateLimited -> stringResource(R.string.clan_notice_slow)
    ClanViewModel.Notice.Failed -> stringResource(R.string.clan_notice_failed)
    ClanViewModel.Notice.Rallied -> stringResource(R.string.clan_notice_rallied)
    ClanViewModel.Notice.RallyCooldown -> stringResource(R.string.clan_notice_rally_cooldown)
}

@Composable
private fun roleLabel(r: ClanRole): String = stringResource(
    when (r) {
        ClanRole.Leader -> R.string.clan_role_leader
        ClanRole.CoLeader -> R.string.clan_role_co_leader
        ClanRole.Elder -> R.string.clan_role_elder
        ClanRole.Member -> R.string.clan_role_member
    },
)

@Composable
internal fun ClanBadge(tag: String, size: Int = 56) {
    Box(
        Modifier
            .size(size.dp)
            .clip(RoundedCornerShape((size * 0.28f).dp))
            .background(Brush.linearGradient(listOf(ColorTokens.BrandCyan.resolve(), ColorTokens.BrandVolt.resolve()))),
        contentAlignment = Alignment.Center,
    ) { Text(tag, color = Color.White, fontWeight = FontWeight.Black, fontSize = (size * 0.26f).sp, maxLines = 1) }
}

@Composable
private fun SmallButton(text: String, color: TokenColor = ColorTokens.BrandFlame, enabled: Boolean = true, onClick: () -> Unit) {
    Box(
        Modifier
            .heightIn(min = MinTouchTarget)
            .clip(CircleShape)
            .background(color.resolve().copy(alpha = 0.18f))
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = SpacingTokens.M),
        contentAlignment = Alignment.Center,
    ) { TokenText(text, TypographyTokens.BodyS, color = color.resolve()) }
}

@Composable
private fun Card(content: @Composable () -> Unit) {
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(RadiusTokens.L)).background(ColorTokens.BgSurface.resolve()).padding(SpacingTokens.M),
        verticalArrangement = Arrangement.spacedBy(SpacingTokens.S),
    ) { content() }
}

/** Clan tab (doc 09 §4): clan home when in a clan, otherwise discovery + create. */
@Composable
fun ClanTabScreen(vm: ClanViewModel, modifier: Modifier = Modifier) {
    val s by vm.state.collectAsStateWithLifecycle()
    var chatOpen by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(vm) { vm.start() }
    val home = s.home
    ArenaBackground(modifier, glow = ColorTokens.BrandCyan, glowOffset = DpOffset(0.dp, (-260).dp)) {
        when {
            !s.loaded -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = ColorTokens.BrandFlame.resolve())
            }
            home != null && chatOpen -> {
                BackHandler { chatOpen = false }
                ClanChat(vm, s) { chatOpen = false }
            }
            home != null -> ClanHomeContent(vm, s, home) { chatOpen = true }
            else -> Discovery(vm, s)
        }
    }
}

@Composable
private fun Discovery(vm: ClanViewModel, s: ClanViewModel.UiState) {
    var creating by remember { mutableStateOf(false) }
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(SpacingTokens.L),
        verticalArrangement = Arrangement.spacedBy(SpacingTokens.M),
    ) {
        ScreenTitle(stringResource(R.string.clan_title), token = TypographyTokens.DisplayM)
        TokenText(stringResource(R.string.clan_pitch), TypographyTokens.Body, color = ColorTokens.TextSecondary.resolve())
        PrimaryButton(stringResource(R.string.clan_create), { creating = true })
        noticeText(s.notice)?.let { InlineBanner(it, BannerKind.Info) }
        WarChestsCard(vm, s)
        OutlinedTextField(
            value = s.query,
            onValueChange = vm::setQuery,
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            placeholder = { Text(stringResource(R.string.clan_search_hint)) },
            colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = ColorTokens.BrandFlame.resolve()),
        )
        SectionLabel(stringResource(if (s.query.isBlank()) R.string.clan_recommended else R.string.clan_results))
        Card {
            if (s.results.isEmpty()) TokenText(stringResource(R.string.clan_none), TypographyTokens.BodyS, color = ColorTokens.TextTertiary.resolve())
            s.results.forEach { c ->
                Row(
                    Modifier.fillMaxWidth().heightIn(min = MinTouchTarget),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(SpacingTokens.M),
                ) {
                    ClanBadge(c.tag, 44)
                    Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}) {
                        TokenText("${c.name} [${c.tag}]", TypographyTokens.TitleS, maxLines = 1)
                        TokenText(stringResource(R.string.clan_line, c.memberCount, c.maxMembers, c.rating), TypographyTokens.Caption,
                            color = ColorTokens.TextTertiary.resolve())
                    }
                    when {
                        c.requested -> Pill(stringResource(R.string.clan_requested))
                        c.joinPolicy != "invite_only" && c.memberCount < c.maxMembers ->
                            SmallButton(stringResource(if (c.joinPolicy == "open") R.string.clan_join else R.string.clan_ask), enabled = !s.busy) {
                                vm.join(c)
                            }
                    }
                }
            }
        }
        // clan discovery only — never in the clan chat (doc 13 §1)
        AdBannerSlot("clan_banner")
    }
    if (creating) CreateClanDialog(vm, s) { creating = false }
}

@Composable
private fun CreateClanDialog(vm: ClanViewModel, s: ClanViewModel.UiState, onClose: () -> Unit) {
    var name by remember { mutableStateOf("") }
    var tag by remember { mutableStateOf("") }
    var about by remember { mutableStateOf("") }
    var policy by remember { mutableStateOf("open") }
    AlertDialog(
        containerColor = ColorTokens.BgElevated.resolve(),
        onDismissRequest = onClose,
        title = { Text(stringResource(R.string.clan_new)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                OutlinedTextField(name, { name = it.take(24) }, label = { Text(stringResource(R.string.clan_name_hint)) }, singleLine = true)
                OutlinedTextField(tag, { tag = it.uppercase().filter { ch -> ch.isLetterOrDigit() }.take(5) },
                    label = { Text(stringResource(R.string.clan_tag_hint)) }, singleLine = true)
                OutlinedTextField(about, { about = it.take(200) }, label = { Text(stringResource(R.string.clan_about_hint)) })
                listOf("open" to R.string.clan_policy_open, "request" to R.string.clan_policy_request, "invite_only" to R.string.clan_policy_invite)
                    .forEach { (value, label) ->
                        Row(
                            Modifier.fillMaxWidth().heightIn(min = MinTouchTarget).selectable(policy == value, role = Role.RadioButton) { policy = value },
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            TokenText(if (policy == value) "● " else "○ ", TypographyTokens.Body)
                            TokenText(stringResource(label), TypographyTokens.Body)
                        }
                    }
                noticeText(s.notice)?.let { TokenText(it, TypographyTokens.Caption, color = ColorTokens.StateDanger.resolve()) }
            }
        },
        confirmButton = {
            TextButton(onClick = { vm.create(name, tag, about, policy, onClose) }, enabled = name.trim().length >= 3 && tag.length >= 3 && !s.busy) {
                Text(stringResource(R.string.clan_create_confirm))
            }
        },
        dismissButton = { TextButton(onClick = onClose) { Text(stringResource(R.string.clan_cancel)) } },
    )
}

@Composable
private fun ClanHomeContent(vm: ClanViewModel, s: ClanViewModel.UiState, home: ClanHome, openChat: () -> Unit) {
    var confirmLeave by remember { mutableStateOf(false) }
    val role = s.myRole ?: ClanRole.Member
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(SpacingTokens.L),
        verticalArrangement = Arrangement.spacedBy(SpacingTokens.M),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
            ClanBadge(home.summary.tag)
            Column(Modifier.semantics(mergeDescendants = true) {}) {
                TokenText(home.summary.name, TypographyTokens.Name)
                TokenText(stringResource(R.string.clan_header_line, home.summary.tag, home.summary.memberCount, home.summary.rating),
                    TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
            }
        }
        if (home.summary.description.isNotBlank()) TokenText(home.summary.description, TypographyTokens.Body, color = ColorTokens.TextSecondary.resolve())
        PrimaryButton(stringResource(R.string.clan_chat), openChat)
        noticeText(s.notice)?.let { InlineBanner(it, BannerKind.Info) }

        SectionLabel(stringResource(R.string.clan_war))
        Card {
            val war = home.war
            if (war == null) {
                TokenText(stringResource(if (home.summary.memberCount < 5) R.string.clan_war_need_five else R.string.clan_war_next_monday),
                    TypographyTokens.BodyS, color = ColorTokens.TextSecondary.resolve())
            } else {
                WarCard(war, home.summary.tag)
            }
        }
        home.war?.let { war ->
            val rally = war.rally
            if (war.status == "live" && rally != null) {
                PrimaryButton(
                    stringResource(if (rally.available) R.string.clan_rally else R.string.clan_rally_used),
                    vm::rally,
                    enabled = rally.available,
                )
            }
            if (war.days.any { it.us + it.them > 0 }) Card { WarDays(war) }
            if (war.top.isNotEmpty() || war.theirTop.isNotEmpty()) Card { WarChampions(war, home.summary.tag) }
            if (war.feed.isNotEmpty()) Card { WarFeed(war, home.summary.tag) }
        }

        WarChestsCard(vm, s)

        if (s.warHistory.isNotEmpty()) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                SectionLabel(stringResource(R.string.clan_war_history), Modifier.weight(1f))
                WarStreak.current(s.warHistory)?.takeIf { it.second > 1 }?.let { (letter, n) ->
                    Pill(stringResource(if (letter == "W") R.string.clan_streak_wins else R.string.clan_streak_losses, n),
                        color = if (letter == "W") ColorTokens.StateSuccessText else ColorTokens.TextSecondary)
                }
            }
            Card { s.warHistory.forEach { WarHistoryRow(it) } }
        }

        if (role.canAcceptRequests && home.requests.isNotEmpty()) {
            SectionLabel(stringResource(R.string.clan_requests))
            Card {
                home.requests.forEach { r ->
                    Row(Modifier.fillMaxWidth().heightIn(min = MinTouchTarget), verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                        Avatar(r.user.username, r.user.avatarPreset, size = 36.dp)
                        Column(Modifier.weight(1f)) {
                            TokenText(r.user.username, TypographyTokens.TitleS)
                            r.message?.takeIf { it.isNotBlank() }?.let { TokenText(it, TypographyTokens.Caption) }
                        }
                        SmallButton(stringResource(R.string.clan_accept), enabled = !s.busy) { vm.respond(r.user.id, true) }
                        SmallButton(stringResource(R.string.clan_decline), ColorTokens.TextSecondary, enabled = !s.busy) { vm.respond(r.user.id, false) }
                    }
                }
            }
        }

        SectionLabel(stringResource(R.string.clan_members))
        Card {
            home.members.sortedByDescending { it.warReps }.forEach { m -> MemberRow(vm, role, m) }
        }

        TextButton(onClick = { confirmLeave = true }, modifier = Modifier.fillMaxWidth().heightIn(min = MinTouchTarget)) {
            Text(stringResource(R.string.clan_leave), color = ColorTokens.StateDanger.resolve())
        }
    }
    if (confirmLeave) {
        AlertDialog(
            containerColor = ColorTokens.BgElevated.resolve(),
            onDismissRequest = { confirmLeave = false },
            title = { Text(stringResource(R.string.clan_leave_confirm, home.summary.name)) },
            text = { Text(stringResource(R.string.clan_leave_text)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmLeave = false
                    vm.leave()
                }) { Text(stringResource(R.string.clan_leave)) }
            },
            dismissButton = { TextButton(onClick = { confirmLeave = false }) { Text(stringResource(R.string.clan_cancel)) } },
        )
    }
}

@Composable
private fun MemberRow(vm: ClanViewModel, myRole: ClanRole, m: ClanHome.Member) {
    var menu by remember { mutableStateOf(false) }
    val other = ClanRole.of(m.role) ?: ClanRole.Member
    val roles = myRole.assignable(other)
    val canKick = myRole.canKick(other)
    val hasActions = roles.isNotEmpty() || canKick || myRole == ClanRole.Leader
    Box {
        Row(
            Modifier
                .fillMaxWidth()
                .heightIn(min = MinTouchTarget)
                .clickable(enabled = hasActions, role = Role.Button) { menu = true }
                .semantics(mergeDescendants = true) {},
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(SpacingTokens.M),
        ) {
            Avatar(m.user.username, m.user.avatarPreset, size = 40.dp)
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
                    TokenText(m.user.username, TypographyTokens.TitleS, maxLines = 1, modifier = Modifier.weight(1f, fill = false))
                    if (m.user.pro == true) ProBadge()
                }
                TokenText(roleLabel(other), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
            }
            Column(horizontalAlignment = Alignment.End) {
                TokenText(stringResource(R.string.clan_war_reps, m.warReps), TypographyTokens.BodyS)
                TokenText(stringResource(R.string.clan_today_reps, m.repsToday), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
            }
        }
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            roles.forEach { r ->
                DropdownMenuItem(text = { Text(stringResource(R.string.clan_make_role, roleLabel(r))) }, onClick = {
                    menu = false
                    vm.setRole(m.user.id, r)
                })
            }
            if (myRole == ClanRole.Leader) {
                DropdownMenuItem(text = { Text(stringResource(R.string.clan_make_leader)) }, onClick = {
                    menu = false
                    vm.transfer(m.user.id)
                })
            }
            if (canKick) {
                DropdownMenuItem(text = { Text(stringResource(R.string.clan_kick), color = ColorTokens.StateDanger.resolve()) }, onClick = {
                    menu = false
                    vm.kick(m.user.id)
                })
            }
        }
    }
}

@Composable
private fun WarCard(war: ClanWar, ourTag: String) {
    val total = maxOf(war.score.us + war.score.them, 1)
    val them = war.opponent
    val description = stringResource(R.string.clan_war_a11y, war.score.us, war.score.them)
    Column(Modifier.semantics(mergeDescendants = true) { contentDescription = description }, verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
        if (them != null) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                val gap = war.gap
                TokenText(
                    if (gap > 0) "+$gap" else if (gap < 0) "−${-gap}" else "=",
                    TypographyTokens.DisplayM,
                    color = (if (gap > 0) ColorTokens.StateSuccess else if (gap < 0) ColorTokens.StateDanger else ColorTokens.TextPrimary).resolve(),
                )
                Spacer(Modifier.width(SpacingTokens.S))
                TokenText(
                    stringResource(
                        when {
                            war.status == "finished" -> R.string.clan_war_final
                            gap > 0 -> R.string.clan_war_ahead
                            gap < 0 -> R.string.clan_war_behind
                            else -> R.string.clan_war_even
                        },
                    ),
                    TypographyTokens.LabelDisplay,
                    color = ColorTokens.TextSecondary.resolve(),
                    modifier = Modifier.weight(1f),
                )
                warTimeLeft(war)?.let { TokenText("⏱ $it", TypographyTokens.Caption, color = ColorTokens.BrandFlameText.resolve()) }
            }
        }
        Row {
            TokenText("[$ourTag] ${war.score.us}", TypographyTokens.TitleM, color = ColorTokens.BrandFlameText.resolve())
            Spacer(Modifier.weight(1f))
            TokenText(if (them != null) "${war.score.them} [${them.tag}]" else stringResource(R.string.clan_bye), TypographyTokens.TitleM,
                color = ColorTokens.BrandVoltText.resolve())
        }
        Row(Modifier.fillMaxWidth().height(10.dp), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            val us = (war.score.us.toFloat() / total).coerceIn(0.02f, 0.98f)
            Box(Modifier.weight(us).fillMaxSize().clip(CircleShape).background(ColorTokens.BrandFlame.resolve()))
            Box(Modifier.weight(1f - us).fillMaxSize().clip(CircleShape).background(ColorTokens.BrandVolt.resolve()))
        }
        TokenText(
            if (war.status == "finished") stringResource(R.string.clan_war_over)
            else stringResource(R.string.clan_war_today, war.myToday.counted, war.myToday.fullCap, war.myToday.halfCap),
            TypographyTokens.Caption,
            color = ColorTokens.TextTertiary.resolve(),
        )
        if (war.status != "finished") SideViewNotice(compact = true)
    }
}

@Composable
private fun warTimeLeft(war: ClanWar): String? {
    if (war.status != "live") return null
    val end = runCatching { java.time.Instant.parse(war.endsAt).toEpochMilli() }.getOrNull() ?: return null
    val s = maxOf(0L, (end - System.currentTimeMillis()) / 1000)
    val d = (s / 86400).toInt()
    val h = ((s % 86400) / 3600).toInt()
    val m = ((s % 3600) / 60).toInt()
    return if (d > 0) stringResource(R.string.clan_war_left_days, d, h) else stringResource(R.string.clan_war_left_hours, h, m)
}

/** Points per war day, both sides (D-068). */
@Composable
private fun WarDays(war: ClanWar) {
    val (won, lost) = war.daysWon
    val top = maxOf(war.days.maxOfOrNull { maxOf(it.us, it.them) } ?: 1, 1)
    val a11y = stringResource(R.string.clan_days_won, won, lost)
    Column(Modifier.clearAndSetSemantics { contentDescription = a11y }, verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
        TokenText(a11y, TypographyTokens.LabelDisplay, color = ColorTokens.TextSecondary.resolve())
        Row(Modifier.fillMaxWidth().height(70.dp), verticalAlignment = Alignment.Bottom) {
            war.days.forEachIndexed { i, d ->
                Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                        Box(Modifier.width(7.dp).height(maxOf(3f, 48f * d.us / top).dp).clip(CircleShape).background(ColorTokens.BrandFlame.resolve()))
                        Box(Modifier.width(7.dp).height(maxOf(3f, 48f * d.them / top).dp).clip(CircleShape).background(ColorTokens.BrandVolt.resolve()))
                    }
                    TokenText(listOf("M", "T", "W", "T", "F", "S", "S")[i % 7], TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
                }
            }
        }
    }
}

/** Our best three vs theirs (D-068). */
@Composable
private fun WarChampions(war: ClanWar, ourTag: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
        ChampionColumn(war.top.take(3), "[$ourTag]", ColorTokens.BrandFlameText, Modifier.weight(1f))
        TokenText("⚔️", TypographyTokens.TitleM, modifier = Modifier.clearAndSetSemantics {})
        ChampionColumn(war.theirTop.take(3), war.opponent?.let { "[${it.tag}]" } ?: "–", ColorTokens.BrandVoltText, Modifier.weight(1f))
    }
}

@Composable
private fun ChampionColumn(rows: List<ClanWar.Top>, title: String, color: app.pushly.core.designsystem.generated.TokenColor, modifier: Modifier) {
    Column(modifier.semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
        TokenText(title, TypographyTokens.LabelDisplay, color = color.resolve())
        rows.forEachIndexed { i, r ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                TokenText(if (i == 0) "👑" else "${i + 1}.", TypographyTokens.Caption)
                Spacer(Modifier.width(SpacingTokens.Xs))
                TokenText(r.user.username, TypographyTokens.BodyS, modifier = Modifier.weight(1f), maxLines = 1)
                TokenText("${r.reps}", TypographyTokens.BodyS)
            }
        }
    }
}

/** Live war feed (D-068): who just scored for which side. */
@Composable
private fun WarFeed(war: ClanWar, ourTag: String) {
    Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
        TokenText(stringResource(R.string.clan_war_live), TypographyTokens.LabelDisplay, color = ColorTokens.StateDanger.resolve())
        war.feed.take(8).forEach { f ->
            val ours = f.side == "us"
            Row(Modifier.semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically) {
                TokenText(if (ours) "🔥" else "⚔️", TypographyTokens.BodyS, modifier = Modifier.clearAndSetSemantics {})
                Spacer(Modifier.width(SpacingTokens.Xs))
                TokenText(f.username, TypographyTokens.BodyS)
                Spacer(Modifier.width(SpacingTokens.Xs))
                TokenText(if (ours) "[$ourTag]" else "[${war.opponent?.tag ?: ""}]", TypographyTokens.Caption,
                    color = (if (ours) ColorTokens.BrandFlameText else ColorTokens.BrandVoltText).resolve(), modifier = Modifier.weight(1f))
                TokenText("+${f.points}", TypographyTokens.BodyS,
                    color = (if (ours) ColorTokens.StateSuccessText else ColorTokens.StateDanger).resolve())
            }
        }
    }
}

/** Clan chat (doc 09 §5): refreshes every 5 s while open, quick reactions. */
@Composable
private fun ClanChat(vm: ClanViewModel, s: ClanViewModel.UiState, onBack: () -> Unit) {
    var text by rememberSaveable { mutableStateOf("") }
    val list = rememberLazyListState()
    LaunchedEffect(Unit) {
        while (true) {
            vm.refreshMessages()
            delay(5000)
        }
    }
    LaunchedEffect(s.messages.size) { if (s.messages.isNotEmpty()) list.animateScrollToItem(s.messages.size - 1) }
    Column(Modifier.fillMaxSize().imePadding()) {
        Row(Modifier.padding(horizontal = SpacingTokens.M), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onBack, modifier = Modifier.heightIn(min = MinTouchTarget)) {
                Text(stringResource(R.string.clan_back), color = ColorTokens.BrandFlameText.resolve())
            }
            TokenText(stringResource(R.string.clan_chat), TypographyTokens.TitleM)
        }
        LazyColumn(Modifier.weight(1f).padding(horizontal = SpacingTokens.L), state = list,
            verticalArrangement = Arrangement.spacedBy(SpacingTokens.Sm)) {
            items(s.messages, key = { it.id }) { msg -> MessageRow(msg) }
        }
        noticeText(s.notice)?.let { TokenText(it, TypographyTokens.Caption, color = ColorTokens.StateDanger.resolve(), modifier = Modifier.padding(horizontal = SpacingTokens.L)) }
        Row(
            Modifier.fillMaxWidth().background(ColorTokens.BgSurface.resolve()).padding(SpacingTokens.S),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Xs),
        ) {
            listOf("👊", "🔥", "💪").forEach { e ->
                val label = stringResource(R.string.clan_send_reaction, e)
                Box(
                    Modifier.size(MinTouchTarget).clickable(role = Role.Button) { vm.send(e, "kudos") }.semantics { contentDescription = label },
                    contentAlignment = Alignment.Center,
                ) { Text(e, fontSize = 20.sp) }
            }
            OutlinedTextField(text, { text = it.take(500) }, modifier = Modifier.weight(1f), maxLines = 4,
                placeholder = { Text(stringResource(R.string.clan_message_hint)) })
            val sendLabel = stringResource(R.string.clan_send)
            Box(
                Modifier
                    .widthIn(min = MinTouchTarget)
                    .heightIn(min = MinTouchTarget)
                    .clip(CircleShape)
                    .background(ColorTokens.BrandFlame.resolve())
                    .clickable(enabled = text.isNotBlank(), role = Role.Button) { vm.send(text) { text = "" } }
                    .semantics { contentDescription = sendLabel },
                contentAlignment = Alignment.Center,
            ) { Text("➤", color = Color.White) }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun MessageRow(msg: ClanMessage) {
    if (msg.kind == "system") {
        TokenText(msg.body ?: "", TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve(), textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth())
        return
    }
    val name = msg.user?.username ?: stringResource(R.string.clan_deleted_user)
    var reporting by remember { mutableStateOf(false) }
    val reportLabel = stringResource(R.string.clan_report_message)
    // Long press → report (doc 09 §5); TalkBack gets it as a custom action.
    Row(
        Modifier.semantics(mergeDescendants = true) {
            if (Reporter.isAvailable && msg.user != null) customActions = listOf(CustomAccessibilityAction(reportLabel) { reporting = true; true })
        }.combinedClickable(enabled = Reporter.isAvailable && msg.user != null, onLongClick = { reporting = true }, onClick = {}),
        horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S),
    ) {
        Avatar(name, msg.user?.avatarPreset, size = 32.dp)
        Column(
            Modifier.clip(RoundedCornerShape(RadiusTokens.M)).background(ColorTokens.BgSurface.resolve())
                .border(1.dp, ColorTokens.StrokeSubtle.resolve(), RoundedCornerShape(RadiusTokens.M)).padding(SpacingTokens.S),
        ) {
            TokenText(name, TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
            TokenText(msg.body ?: "", if (msg.kind == "kudos") TypographyTokens.TitleL else TypographyTokens.Body)
        }
    }
    ReportDialog(reporting, onDismiss = { reporting = false }) { reason -> Reporter.send(ReportTarget.Message(msg.id), reason) }
}

/** Unopened War Chests (+ medal counts). Content is fixed and shown before opening — no randomness (D-057). */
@Composable
private fun WarChestsCard(vm: ClanViewModel, s: ClanViewModel.UiState) {
    val chests = s.chests ?: return
    if (chests.isEmpty) return
    SectionLabel(stringResource(R.string.clan_chests))
    Card {
        s.openedXP?.let { xp ->
            Row(Modifier.fillMaxWidth().heightIn(min = MinTouchTarget), verticalAlignment = Alignment.CenterVertically) {
                TokenText(stringResource(R.string.clan_chest_opened, xp), TypographyTokens.TitleM, Modifier.weight(1f),
                    color = ColorTokens.LeagueGold.resolve())
                SmallButton(stringResource(R.string.clan_ok)) { vm.dismissOpened() }
            }
        }
        chests.unopened.forEach { chest ->
            Row(
                Modifier.fillMaxWidth().heightIn(min = MinTouchTarget),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(SpacingTokens.M),
            ) {
                TokenText("🎁", TypographyTokens.TitleL, Modifier.clearAndSetSemantics {})
                Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}) {
                    TokenText(
                        stringResource(when (chest.tier) {
                            "gold" -> R.string.clan_chest_gold
                            "silver" -> R.string.clan_chest_silver
                            else -> R.string.clan_chest_bronze
                        }),
                        TypographyTokens.TitleS,
                        color = when (chest.tier) {
                            "gold" -> ColorTokens.LeagueGold
                            "silver" -> ColorTokens.LeagueSilver
                            else -> ColorTokens.LeagueBronze
                        }.resolve(),
                    )
                    TokenText(stringResource(R.string.clan_chest_line, chest.xp, chest.clanName.orEmpty()), TypographyTokens.Caption,
                        color = ColorTokens.TextTertiary.resolve())
                }
                SmallButton(stringResource(R.string.clan_chest_open), enabled = !s.busy) { vm.open(chest) }
            }
        }
        val m = chests.medals
        val medalsLabel = stringResource(R.string.clan_medals_a11y, m.gold, m.silver, m.bronze)
        TokenText("🥇 ${m.gold}   🥈 ${m.silver}   🥉 ${m.bronze}", TypographyTokens.BodyS,
            Modifier.clearAndSetSemantics { contentDescription = medalsLabel })
        TokenText(stringResource(R.string.clan_chests_note), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
    }
}

@Composable
private fun WarHistoryRow(war: ClanWarRecord) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = MinTouchTarget).semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(SpacingTokens.M),
    ) {
        TokenText(war.letter, TypographyTokens.TitleS, Modifier.width(28.dp), color = when (war.letter) {
            "W" -> ColorTokens.StateSuccessText
            "L" -> ColorTokens.StateDanger
            else -> ColorTokens.TextSecondary
        }.resolve())
        Column(Modifier.weight(1f)) {
            TokenText(war.opponent?.let { "[${it.tag}] ${it.name}" } ?: stringResource(R.string.clan_bye), TypographyTokens.BodyS, maxLines = 1)
            TokenText(war.weekStart, TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
        }
        TokenText("${war.us} : ${war.them}", TypographyTokens.BodyS)
    }
}
