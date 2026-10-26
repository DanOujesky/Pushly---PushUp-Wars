import DesignSystem
import SwiftUI

/// The Training tab (D-075): a free session, your own workouts up top, and ready-made workouts by level — Beginner,
/// Intermediate, Advanced. Every side-view push-up done here counts for your day, stats and your clan's Clan War.
public struct TrainingTabView: View {
    let services: SessionServices?
    @AppStorage("training.level") private var levelRaw = WorkoutLevel.beginner.rawValue
    @State private var mine: [Workout] = []
    @State private var detail: Workout?
    @State private var editing: Workout?
    @State private var running: Workout?
    @State private var free = false
    private let store = WorkoutStore()

    public init(services: SessionServices?) {
        self.services = services
    }

    private var level: WorkoutLevel { WorkoutLevel(rawValue: levelRaw) ?? .beginner }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SpacingTokens.l) {
                    header
                    FreeSessionCard { free = true }
                    mineSection
                    levelSection
                    SideViewNotice(.compact)
                }
                .padding(.horizontal, SpacingTokens.gutter)
                .padding(.vertical, SpacingTokens.l)
            }
            .scrollBounceBehavior(.basedOnSize)
            .arenaBackground(glow: ColorTokens.brandLime, alignment: .topTrailing, offset: CGSize(width: 140, height: -240))
            .toolbarVisibility(.hidden, for: .navigationBar)
        }
        .onAppear { mine = store.load() }
        .sheet(item: $detail) { w in
            WorkoutDetailSheet(workout: w,
                               onStart: { detail = nil; after { running = w } },
                               onEdit: {
                                   detail = nil
                                   var copy = w
                                   if w.isPreset {
                                       copy.id = UUID().uuidString
                                       copy.name = String(localized: "\(w.name) (my version)")
                                       copy.isPreset = false
                                   }
                                   after { editing = copy }
                               },
                               onDelete: w.isPreset ? nil : {
                                   detail = nil
                                   mine = store.delete(id: w.id)
                               })
        }
        .sheet(item: $editing) { w in
            WorkoutEditorView(workout: w) { saved in
                mine = store.upsert(saved)
                editing = nil
            } onCancel: { editing = nil }
        }
        .fullScreenCover(item: $running) { w in
            WorkoutRunView(workout: w, services: services) { running = nil }
        }
        .fullScreenCover(isPresented: $free) {
            TrainingView(services: services) { free = false }
        }
    }

    /// Presents the next screen once the detail sheet has gone (two presentations at once are dropped).
    private func after(_ action: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            action()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
            ScreenTitle("Training", token: TypographyTokens.displayM)
            Text("Get stronger between battles. Side-view push-ups count for your clan's war.")
                .typography(TypographyTokens.bodyS)
                .foregroundStyle(Color(ColorTokens.textSecondary))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: my workouts

    private var mineSection: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            HStack {
                SectionLabel("My workouts")
                Spacer()
                Button { editing = WorkoutEditorView.blank() } label: {
                    Label("Create", systemImage: "plus")
                        .typography(TypographyTokens.button)
                        .foregroundStyle(Color(ColorTokens.brandFlameText))
                        .frame(minHeight: TouchTarget.minimum)
                }
            }
            if mine.isEmpty {
                Button { editing = WorkoutEditorView.blank() } label: {
                    HStack(spacing: SpacingTokens.m) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(Color(ColorTokens.brandFlame))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Build your own workout")
                                .typography(TypographyTokens.titleS)
                                .foregroundStyle(Color(ColorTokens.textPrimary))
                            Text("Sets, reps, rest, max sets, EMOM — your rules.")
                                .typography(TypographyTokens.caption)
                                .foregroundStyle(Color(ColorTokens.textSecondary))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(SpacingTokens.m)
                    .frame(maxWidth: .infinity, minHeight: 88)
                    .background(Color(ColorTokens.bgSurface).opacity(0.7), in: RoundedRectangle(cornerRadius: RadiusTokens.l))
                    .overlay(RoundedRectangle(cornerRadius: RadiusTokens.l)
                        .strokeBorder(Color(ColorTokens.strokeStrong), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                }
                .buttonStyle(.plain)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: SpacingTokens.sm) {
                        ForEach(mine) { w in
                            Button { detail = w } label: { MyWorkoutCard(workout: w) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    // MARK: levels

    private var levelSection: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            SectionLabel("Workouts")
            HStack(spacing: SpacingTokens.xs) {
                ForEach(WorkoutLevel.allCases) { l in
                    let on = l == level
                    Button { levelRaw = l.rawValue } label: {
                        VStack(spacing: 2) {
                            Text(Self.title(l))
                                .typography(TypographyTokens.titleS)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            LevelBars(level: l, on: on)
                        }
                        .foregroundStyle(Color(on ? ColorTokens.textPrimary : ColorTokens.textSecondary))
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Color(on ? Self.tint(l) : ColorTokens.bgSurface).opacity(on ? 0.22 : 0.9),
                                    in: RoundedRectangle(cornerRadius: RadiusTokens.m))
                        .overlay(RoundedRectangle(cornerRadius: RadiusTokens.m)
                            .strokeBorder(Color(on ? Self.tint(l) : ColorTokens.strokeSubtle), lineWidth: on ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Text(Self.blurb(level))
                .typography(TypographyTokens.caption)
                .foregroundStyle(Color(ColorTokens.textTertiary))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Workout.presets.filter { $0.level == level }) { w in
                Button { detail = w } label: { WorkoutCard(workout: w, tint: Self.tint(level)) }
                    .buttonStyle(.plain)
            }
        }
    }

    static func title(_ l: WorkoutLevel) -> LocalizedStringKey {
        switch l {
        case .beginner: "Beginner"
        case .intermediate: "Intermediate"
        case .advanced: "Advanced"
        }
    }

    static func blurb(_ l: WorkoutLevel) -> LocalizedStringKey {
        switch l {
        case .beginner: "New to push-ups or coming back: small sets, long rests, clean form."
        case .intermediate: "You can do 15+ in a row: more volume, pyramids, EMOM and Tabata."
        case .advanced: "100+ push-up sessions, short rests and sets to failure."
        }
    }

    static func tint(_ l: WorkoutLevel) -> TokenColor {
        switch l {
        case .beginner: ColorTokens.brandLime
        case .intermediate: ColorTokens.brandCyan
        case .advanced: ColorTokens.brandFlame
        }
    }
}

/// Three little bars: 1, 2 or 3 lit.
struct LevelBars: View {
    let level: WorkoutLevel
    let on: Bool

    var body: some View {
        let lit = WorkoutLevel.allCases.firstIndex(of: level).map { $0 + 1 } ?? 1
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(i <= lit ? TrainingTabView.tint(level) : ColorTokens.strokeStrong).opacity(on || i > lit ? 1 : 0.6))
                    .frame(width: 5, height: CGFloat(4 + i * 3))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Big "start now" card: free session, no plan.
struct FreeSessionCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SpacingTokens.m) {
                VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                    Text("FREE SESSION")
                        .typography(TypographyTokens.displayM)
                        .foregroundStyle(.white)
                    Text("No plan, no target — the camera counts every push-up.")
                        .typography(TypographyTokens.caption)
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            }
            .padding(SpacingTokens.m)
            .frame(maxWidth: .infinity, minHeight: 96)
            .background(LinearGradient(GradientTokens.hero), in: RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous).strokeBorder(.white.opacity(0.3), lineWidth: 1.5))
            .shadow(color: Color(ColorTokens.brandFlame).opacity(0.35), radius: 16, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// A ready-made workout: level stripe, name, description and the numbers.
struct WorkoutCard: View {
    let workout: Workout
    let tint: TokenColor

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(Color(tint)).frame(width: 4)
            VStack(alignment: .leading, spacing: SpacingTokens.s) {
                HStack {
                    Text(verbatim: workout.name)
                        .typography(TypographyTokens.titleS)
                        .foregroundStyle(Color(ColorTokens.textPrimary))
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Color(ColorTokens.textTertiary)).accessibilityHidden(true)
                }
                if !workout.description.isEmpty {
                    Text(verbatim: workout.description)
                        .typography(TypographyTokens.caption)
                        .foregroundStyle(Color(ColorTokens.textSecondary))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                WorkoutPills(workout: workout)
            }
            .padding(SpacingTokens.m)
        }
        .background(Color(ColorTokens.bgSurface).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.m))
        .overlay(RoundedRectangle(cornerRadius: RadiusTokens.m).strokeBorder(Color(ColorTokens.strokeSubtle)))
        .accessibilityElement(children: .combine)
    }
}

/// One of my workouts in the horizontal row.
struct MyWorkoutCard: View {
    let workout: Workout

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.s) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.title2)
                .foregroundStyle(Color(ColorTokens.brandFlameText))
                .accessibilityHidden(true)
            Text(verbatim: workout.name)
                .typography(TypographyTokens.titleS)
                .foregroundStyle(Color(ColorTokens.textPrimary))
                .lineLimit(2)
            Spacer(minLength: 0)
            Text(verbatim: WorkoutText.summary(workout))
                .typography(TypographyTokens.caption)
                .foregroundStyle(Color(ColorTokens.textSecondary))
                .lineLimit(2)
        }
        .padding(SpacingTokens.m)
        .frame(width: 180, height: 140, alignment: .topLeading)
        .background(LinearGradient(colors: [Color(ColorTokens.brandFlame).opacity(0.22), Color(ColorTokens.bgSurface)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: RadiusTokens.l))
        .overlay(RoundedRectangle(cornerRadius: RadiusTokens.l).strokeBorder(Color(ColorTokens.brandFlame).opacity(0.45)))
        .accessibilityElement(children: .combine)
    }
}
