import Core
import DesignSystem
import Observation
import SwiftUI

/// Player profile (doc 15 §1, P6-02): card, league, stats when visible, head-to-head, friend actions, report/block.
@MainActor
@Observable
public final class UserProfileModel {
    public enum Key: Hashable, Sendable {
        case id(String)
        case username(String)
    }

    public private(set) var profile: UserProfile?
    public private(set) var loaded = false
    public private(set) var notice: String?
    let key: Key
    private let service: SocialService

    public init(key: Key, service: SocialService) {
        self.key = key
        self.service = service
    }

    public func load() async {
        let (id, name): (String?, String?) = switch key {
        case let .id(id): (id, nil)
        case let .username(name): (nil, name)
        }
        do {
            profile = try JSONDecoder().decode(UserProfile?.self, from: try await service.profile(id, name))
        } catch {
            PLog.error("profile load failed: \(error)")
        }
        loaded = true
    }

    public func addFriend() async {
        guard let p = profile else { return }
        await run { _ = try await self.service.sendRequest(p.user.id) }
        PushPrompt.request(.friends)
    }

    public func accept() async {
        guard let p = profile else { return }
        await run { _ = try await self.service.respond(p.user.id, true) }
    }

    public func block() async {
        guard let p = profile else { return }
        await run { _ = try await self.service.block(p.user.id) }
        profile = nil
    }

    private func run(_ body: @escaping () async throws -> Void) async {
        do {
            try await body()
            notice = nil
        } catch {
            notice = String(localized: "That didn't work. Please try again.")
        }
        await load()
    }
}

public struct UserProfileView: View {
    @State private var model: UserProfileModel
    @State private var confirmBlock = false

    public init(model: UserProfileModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        List {
            if let p = model.profile {
                content(p)
            } else if model.loaded {
                Section {
                    Text("This player isn't available.").foregroundStyle(Color(ColorTokens.textSecondary))
                }
                .listRowBackground(Color(ColorTokens.bgSurface))
            } else {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .arenaBackground(glow: ColorTokens.brandVolt, alignment: .top, offset: CGSize(width: 0, height: -260))
        .navigationTitle(Text(verbatim: model.profile?.user.username ?? ""))
        .toolbarVisibility(.visible, for: .navigationBar)
        .task { await model.load() }
        .confirmationDialog("Block this player?", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Block", role: .destructive) { Task { await model.block() } }
        } message: {
            Text("You won't see each other anywhere in Pushly. They aren't told.")
        }
    }

    @ViewBuilder
    private func content(_ p: UserProfile) -> some View {
        Section {
            HStack(spacing: SpacingTokens.m) {
                AvatarView(username: p.user.username, presetID: p.user.avatarPreset, size: 72)
                VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                    Text(verbatim: p.user.username).typography(TypographyTokens.name)
                    HStack(spacing: SpacingTokens.s) {
                        Pill("Level \(p.user.level)", color: ColorTokens.brandVoltText)
                        Pill("\(p.user.trophies) 🏆", color: ColorTokens.leagueGold)
                        if let streak = p.user.streak, streak > 0 { Pill("🔥 \(streak)", color: ColorTokens.brandFlameText) }
                    }
                    Text(verbatim: leagueLine(p))
                        .typography(TypographyTokens.caption)
                        .foregroundStyle(Color(ColorTokens.textTertiary))
                }
            }
            .accessibilityElement(children: .combine)
            relationButton(p)
        }
        .listRowBackground(Color(ColorTokens.bgSurface))

        if let notice = model.notice {
            Section { InlineBanner(LocalizedStringKey(notice), kind: .warning) }.listRowBackground(Color.clear)
        }

        Section {
            if let s = p.stats {
                LabeledContent("Push-ups (all time)", value: "\(s.repsTotal)")
                LabeledContent("Best set", value: "\(s.bestSet)")
                LabeledContent("Best wake streak", value: "\(s.bestStreak)")
                LabeledContent("Achievements", value: "\(s.achievements)")
                LabeledContent("Best trophies", value: "\(s.bestTrophies)")
                LabeledContent("Member since", value: s.memberSince)
            } else {
                Text(p.relation == "friends" ? "This profile is private." : "Only friends can see these stats.")
                    .foregroundStyle(Color(ColorTokens.textSecondary))
            }
        } header: {
            SectionLabel("Stats")
        }
        .listRowBackground(Color(ColorTokens.bgSurface))

        if let h = p.headToHead, h.wins + h.losses + h.draws > 0 {
            Section {
                Text("You \(h.wins) – \(h.losses) them · \(h.draws) draws").typography(TypographyTokens.titleS)
            } header: {
                SectionLabel("Head to head")
            }
            .listRowBackground(Color(ColorTokens.bgSurface))
        }

        if p.relation != "self" {
            Section {
                ReportButton { reason in await Reporter.send(.user(p.user.id), reason: reason) }
                    .frame(minHeight: TouchTarget.minimum)
                Button("Block", role: .destructive) { confirmBlock = true }
                    .frame(minHeight: TouchTarget.minimum)
            }
            .listRowBackground(Color(ColorTokens.bgSurface))
        }
    }

    private func leagueLine(_ p: UserProfile) -> String {
        let league = p.league.league.prefix(1).uppercased() + p.league.league.dropFirst()
        let tier = p.league.tier.map { " \($0)" } ?? ""
        return p.user.clanTag.map { "\(league)\(tier) · [\($0)]" } ?? "\(league)\(tier)"
    }

    @ViewBuilder
    private func relationButton(_ p: UserProfile) -> some View {
        switch p.relation {
        case "none": PrimaryButton("Add friend") { Task { await model.addFriend() } }
        case "incoming": PrimaryButton("Accept friend request") { Task { await model.accept() } }
        case "outgoing": Text("Friend request sent").foregroundStyle(Color(ColorTokens.textSecondary))
        case "friends": Label("Friends", systemImage: "checkmark.circle.fill").foregroundStyle(Color(ColorTokens.stateSuccessText))
        default: EmptyView()
        }
    }
}
