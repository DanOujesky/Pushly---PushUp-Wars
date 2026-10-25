import AlarmDomain
import AlarmFeature
import BattleFeature
import ClanFeature
import DesignSystem
import Networking
import OnboardingFeature
import ProfileFeature
import SocialFeature
import StatsFeature
import SwiftUI
import UIKit

/// Switches between launch, onboarding and the main tabs based on `AppSession.state`.
struct RootView: View {
    @Environment(AppSession.self) private var session
    @Environment(WakeModel.self) private var wake

    var body: some View {
        Group {
            switch session.state {
            case .launching:
                LaunchView()
            case .updateRequired:
                ForceUpdateView()
            case .welcome:
                WelcomeView { session.welcomeFinished() }
            case .signIn:
                NavigationStack {
                    SignInView(
                        model: SignInViewModel(auth: session.auth) { _ in Task { await session.signedIn() } },
                        linkFailed: session.linkSignInFailed,
                        google: GoogleAuth.isConfigured ? Self.googleSignIn : nil,
                        onGuest: { session.continueAsGuest() }
                    )
                }
            case let .profileSetup(profile):
                if let profiles = session.profiles {
                    NavigationStack {
                        ProfileSetupView(model: ProfileSetupViewModel(profile: profile, profiles: profiles) { completed in
                            session.profileCompleted(completed)
                        })
                    }
                }
            case let .main(profile):
                MainTabsView(profile: profile)
            }
        }
        .animation(.easeInOut(duration: MotionTokens.baseSeconds), value: session.state)
        // The wake session covers everything, whatever screen the app is on (alarm works without an account).
        .fullScreenCover(item: Binding(get: { wake.session.map(SessionItem.init) }, set: { if $0 == nil { wake.session = nil } })) { item in
            WakeSessionView(model: wake, ring: item.ring)
        }
        // Arena look is dark-only for now (D-033).
        .preferredColorScheme(.dark)
        .task { await session.start() }
        .task(id: session.state) {
            if case .main(.some) = session.state { await PushRegistrar.shared.refresh() }
        }
        .alert(pushTitle, isPresented: Binding(get: { PushRegistrar.shared.explainer != nil },
                                               set: { if !$0 { PushRegistrar.shared.explainerAnswered(allow: false) } })) {
            Button("Turn on") { PushRegistrar.shared.explainerAnswered(allow: true) }
            Button("Not now", role: .cancel) { PushRegistrar.shared.explainerAnswered(allow: false) }
        } message: {
            Text("We'll only tell you about things you care about: answers to your requests, battle challenges and your clan. Never during your alarm.")
        }
    }
}

extension RootView {
    /// Native Google sign-in (D-061), handed to the sign-in screen.
    static let googleSignIn: @MainActor @Sendable () async throws -> (idToken: String, accessToken: String)? = {
        try await GoogleAuth.signIn()
    }

    private var pushTitle: LocalizedStringKey {
        switch PushRegistrar.shared.explainer {
        case .friends: "Know when they answer?"
        case .clan: "Stay in the loop with your clan?"
        case .battles: "Get battle challenges?"
        case nil: ""
        }
    }
}

/// Identifiable username for the profile sheet.
struct IdentifiedName: Identifiable {
    let id: String
}

/// Identifiable wrapper so the wake session can drive `fullScreenCover(item:)`.
struct SessionItem: Identifiable {
    let ring: RingState
    var id: String { ring.occurrenceId }
}

struct LaunchView: View {
    var body: some View {
        VStack(spacing: SpacingTokens.xl - 4) {
            LogoMark(size: 112)
            VStack(spacing: SpacingTokens.s) {
                Wordmark(token: TypographyTokens.displayLogo)
                Text(verbatim: "PushUp Wars")
                    .typography(TypographyTokens.labelLogo)
                    .foregroundStyle(Color(ColorTokens.textTertiary))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            ProgressView()
                .tint(Color(ColorTokens.textTertiary))
                .padding(.bottom, SpacingTokens.xxxl)
        }
        .arenaBackground(alignment: .center, offset: CGSize(width: 0, height: 40))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Pushly is loading"))
    }
}

/// Shown when remote config says this version is no longer supported (doc 03 §7).
struct ForceUpdateView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: SpacingTokens.l) {
            Spacer()
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(Color(ColorTokens.bgSurface))
                .stroke(Color(ColorTokens.strokeStrong), lineWidth: 1)
                .frame(width: 120, height: 120)
                .overlay {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(Color(ColorTokens.brandVoltText))
                }
                .accessibilityHidden(true)
            VStack(spacing: SpacingTokens.sm) {
                ScreenTitle("New version\nready")
                    .multilineTextAlignment(.center)
                Text("Update Pushly to keep your alarms, streak and trophies working. It takes a few seconds.")
                    .typography(TypographyTokens.body)
                    .foregroundStyle(Color(ColorTokens.textSecondary))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            Label("Your progress is saved", systemImage: "checkmark")
                .typography(TypographyTokens.bodyS)
                .fontWeight(.semibold)
                .foregroundStyle(Color(ColorTokens.stateSuccessText))
                .padding(.horizontal, SpacingTokens.m)
                .padding(.vertical, SpacingTokens.sm)
                .background(Color(ColorTokens.stateSuccess).opacity(0.10), in: RoundedRectangle(cornerRadius: RadiusTokens.s))
            Spacer()
            PrimaryButton("Update now") {
                if let url = StoreLinks.appStore { openURL(url) }
            }
        }
        .padding(.horizontal, SpacingTokens.l)
        .padding(.bottom, SpacingTokens.l)
        .arenaBackground(glow: ColorTokens.brandVolt, alignment: .center, offset: CGSize(width: 0, height: -60))
    }
}

/// Store pages for the update prompt. The App Store id is only known after the first App Store Connect release
/// (open question Q-update-link in docs/19-decisions-log.md), so iOS opens the App Store app for now.
enum StoreLinks {
    static let appStore = URL(string: "itms-apps://apps.apple.com")
}

struct MainTabsView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppSession.self) private var session
    @Environment(WakeModel.self) private var wake
    @Environment(\.openURL) private var openURL
    let profile: Profile?

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            Tab("Wake", systemImage: "alarm.fill", value: AppTab.wake) {
                WakeTabView(model: wake) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
            Tab("Battle", systemImage: "bolt.fill", value: AppTab.battle) {
                if let battles = battleService {
                    BattleHubView(model: BattleHubModel(service: battles), sessions: wake.services,
                                  player: profile.map { BattlePlayer(username: $0.username, avatarPreset: $0.avatarPreset) })
                } else {
                    PlaceholderScreen(title: "Battle", subtitle: "Create an account to battle friends and players worldwide.",
                                      symbol: "bolt.fill", glow: ColorTokens.brandVolt)
                }
            }
            Tab("Clan", systemImage: "shield.fill", value: AppTab.clan) {
                if let clans = clanService {
                    ClanTabView(model: ClanModel(service: clans))
                } else {
                    PlaceholderScreen(title: "Clan", subtitle: "Create an account to team up and win the weekly Clan War.",
                                      symbol: "shield.fill", glow: ColorTokens.brandCyan)
                }
            }
            Tab("Ranks", systemImage: "trophy.fill", value: AppTab.ranks) {
                if let social = socialService {
                    RanksView(model: RanksModel(service: social))
                } else {
                    PlaceholderScreen(title: "Ranks", subtitle: "Create an account to see global and friends leaderboards.",
                                      symbol: "trophy.fill", glow: ColorTokens.leagueGold)
                }
            }
            Tab("Profile", systemImage: "person.crop.circle.fill", value: AppTab.profile) {
                ProfileView(
                    model: ProfileViewModel(
                        profile: profile, profiles: session.profiles, auth: session.auth,
                        onSignedOut: { session.signedOut() },
                        onCreateAccount: { session.createAccountFromGuest() }
                    ),
                    appVersion: Bundle.main.appVersionString,
                    stats: statsScreen,
                    friends: socialService.map { AnyView(FriendsView(model: FriendsModel(service: $0), myUsername: profile?.username)) },
                    account: accountScreen
                )
            }
        }
        .tint(Color(ColorTokens.brandFlameText))
        .sheet(item: Binding(get: { router.profileUsername.map(IdentifiedName.init) }, set: { router.profileUsername = $0?.id })) { item in
            if let social = socialService {
                NavigationStack {
                    UserProfileView(model: UserProfileModel(key: .username(item.id), service: social))
                }
            }
        }
    }

    private var accountScreen: AnyView? {
        guard profile != nil, let account = session.account else { return nil }
        return AnyView(AccountSettingsView(
            model: AccountModel(account: account, onDeleted: { session.signedOut() }),
            onSignInAgain: { Task { try? await session.auth?.signOut(); session.signedOut() } }))
    }

    private var battleService: BattleService? {
        guard profile != nil, let b = session.battles else { return nil }
        let social = session.social
        let stats = session.stats
        return BattleService(
            invites: { try await b.battleInvites() },
            friends: { try await social?.listFriends() ?? Data("{\"friends\":[]}".utf8) },
            invite: { to, mode, ranked in try await b.createBattleInvite(toUser: to, mode: mode, ranked: ranked) },
            respond: { id, accept in try await b.respondBattleInvite(id, accept: accept) },
            join: { mode in try await b.matchmakingJoin(mode: mode) },
            status: { try await b.matchmakingStatus() },
            leaveQueue: { try await b.matchmakingLeave() },
            get: { id in try await b.battle(id) },
            ready: { id in try await b.battleReady(id) },
            push: { id, reps in try await b.battlePushReps(id, reps: reps) },
            finish: { id in try await b.battleFinish(id) },
            forfeit: { id in try await b.battleForfeit(id) },
            history: { try await b.battleHistory() },
            ghost: { mode in try await b.startGhostBattle(mode: mode) },
            seasons: { try await b.seasonHistory() },
            bot: { mode, level in try await b.startBotBattle(mode: mode, level: level) },
            videoToken: { id in try await b.battleVideoToken(id) },
            stats: {
                guard let stats else { throw CancellationError() }
                return try await stats.battleStats()
            },
            searchUsers: { q in try await social?.searchUsers(q) ?? Data("[]".utf8) },
            addFriend: { id in
                guard let social else { throw CancellationError() }
                _ = try await social.sendFriendRequest(id)
            })
    }

    private var clanService: ClanService? {
        guard profile != nil, let b = session.clans else { return nil }
        return ClanService(
            home: { try await b.myClan() },
            clan: { id in try await b.clan(id) },
            search: { q in try await b.searchClans(q) },
            create: { name, tag, about, policy in
                try await b.createClan(name: name, tag: tag, description: about, joinPolicy: policy)
            },
            join: { id, message in try await b.joinClan(id, message: message) },
            respond: { id, accept in try await b.respondClanRequest(id, accept: accept) },
            leave: { try await b.leaveClan() },
            kick: { id in try await b.kickMember(id) },
            setRole: { id, role in try await b.setMemberRole(id, role: role) },
            transfer: { id in try await b.transferLeadership(id) },
            messages: { before in try await b.clanMessages(before: before) },
            send: { body, kind in try await b.sendClanMessage(body, kind: kind) },
            warHistory: { try await b.clanWarHistory(nil) },
            chests: { try await b.warChests() },
            openChest: { id in try await b.openChest(id) },
            rally: { try await b.clanRally() })
    }

    /// Friends + ranks need an account and a backend.
    private var socialService: SocialService? {
        guard profile != nil, let b = session.social else { return nil }
        return SocialService(
            listFriends: { try await b.listFriends() },
            search: { q in try await b.searchUsers(q) },
            sendRequest: { id in try await b.sendFriendRequest(id) },
            respond: { id, accept in try await b.respondFriendRequest(id, accept: accept) },
            remove: { id in try await b.removeFriend(id) },
            block: { id in try await b.blockUser(id) },
            unblock: { id in try await b.unblockUser(id) },
            feed: { try await b.friendFeed() },
            kudos: { id in try await b.giveKudos(id) },
            leaderboard: { board, scope, period in try await b.leaderboard(board: board, scope: scope, period: period) },
            profile: { id, name in try await b.userProfile(id: id, username: name) })
    }

    /// Stats need an account and a backend; guests don't get the row.
    private var statsScreen: AnyView? {
        guard profile != nil, let backend = session.stats else { return nil }
        return AnyView(StatsView(model: StatsModel(
            fetchStats: { period in try await backend.stats(period: period) },
            fetchAchievements: { try await backend.achievements() },
            fetchBattle: { try await backend.battleStats() }),
            onFight: { router.selectedTab = .battle }))
    }
}

extension Bundle {
    var appVersionString: String {
        let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }
}
