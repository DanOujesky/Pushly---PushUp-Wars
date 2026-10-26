import AlarmDomain
import DesignSystem
import SwiftUI
import WakeFlowFeature

/// The Wake tab (doc 02 PS-20…26): live ring, health warnings, next alarm, alarm list, editor and permission explainer.
public struct WakeTabView: View {
    @Bindable var model: WakeModel
    let onOpenSettings: () -> Void
    @State private var editing: EditorRoute?
    @State private var showPermissions = false
    @Environment(\.scenePhase) private var scenePhase

    struct EditorRoute: Identifiable {
        let schedule: AlarmSchedule
        let isNew: Bool
        var id: String { schedule.id }
    }

    public init(model: WakeModel, onOpenSettings: @escaping () -> Void) {
        self.model = model
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SpacingTokens.l) {
                    header

                    if let live = model.live {
                        LiveRingCard(ring: live, now: model.now) {
                            Task { await model.startSession(live) }
                        }
                    }

                    if !model.health.isEmpty || model.notice != nil {
                        VStack(spacing: SpacingTokens.s) {
                            ForEach(model.health, id: \.self) { issue in
                                HealthBanner(issue: issue) { fix(issue) }
                            }
                            if let notice = model.notice {
                                InlineBanner(notice == .testArmed
                                    ? "Test alarm rings in 10 seconds. Lock your phone to see the real thing."
                                    : "Couldn't schedule the test alarm. Allow alarms first.", kind: .info)
                            }
                        }
                    }

                    NextAlarmCard(model: model) { editing = EditorRoute(schedule: model.newSchedule(), isNew: true) }

                    if let summary = model.summary {
                        WakeStatsRow(summary: summary)
                        WeekCard(summary: summary)
                    }
                    if let pending = model.services?.uploader.pending.count, pending > 0 {
                        HStack(spacing: SpacingTokens.xs) {
                            Image(systemName: "clock").accessibilityHidden(true)
                            Text("\(pending) session(s) waiting to be verified")
                        }
                        .typography(TypographyTokens.caption)
                        .foregroundStyle(Color(ColorTokens.textTertiary))
                        .accessibilityElement(children: .combine)
                    }

                    if !model.items.isEmpty {
                        VStack(alignment: .leading, spacing: SpacingTokens.sm) {
                            HStack(alignment: .center) {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text("Alarms").typography(TypographyTokens.titleL).foregroundStyle(Color(ColorTokens.textPrimary))
                                    Text("\(model.items.count) of \(AlarmSchedule.maxAlarmsPerUser) alarms")
                                        .typography(TypographyTokens.caption)
                                        .foregroundStyle(Color(ColorTokens.textTertiary))
                                }
                                Spacer()
                                if model.canAddAlarm {
                                    Button { editing = EditorRoute(schedule: model.newSchedule(), isNew: true) } label: {
                                        Image(systemName: "plus")
                                            .font(.title3.weight(.bold))
                                            .foregroundStyle(Color(ColorTokens.bgBase))
                                            .frame(width: TouchTarget.minimum, height: TouchTarget.minimum)
                                            .background(LinearGradient(GradientTokens.hero), in: Circle())
                                    }
                                    .accessibilityLabel(Text("New alarm"))
                                }
                            }
                            ForEach(model.items) { item in
                                AlarmRow(item: item, model: model) {
                                    editing = EditorRoute(schedule: item.schedule, isNew: false)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, SpacingTokens.ml)
                .padding(.vertical, SpacingTokens.l)
            }
            .scrollBounceBehavior(.basedOnSize)
            .arenaBackground(glow: ColorTokens.brandFlame, alignment: .topTrailing, offset: CGSize(width: 160, height: -240))
            .toolbarVisibility(.hidden, for: .navigationBar)
        }
        .task {
            await model.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                model.tick()
            }
        }
        .task(id: model.notice) {
            guard model.notice != nil else { return }
            try? await Task.sleep(for: .seconds(6))
            model.notice = nil
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
        .fullScreenCover(item: $editing) { route in
            AlarmEditorView(initial: route.schedule, isNew: route.isNew, model: model) { saved in
                editing = nil
                if saved, model.needsPermission { showPermissions = true }
            }
        }
        .sheet(isPresented: $showPermissions) {
            AlarmPermissionView(model: model, onOpenSettings: onOpenSettings) { showPermissions = false }
                .presentationDetents([.large])
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                Text(WakeGreeting.text(hour: Calendar.current.component(.hour, from: model.now)))
                    .typography(TypographyTokens.bodyS)
                    .foregroundStyle(Color(ColorTokens.textSecondary))
                ScreenTitle("Wake", token: TypographyTokens.displayM)
            }
            Spacer()
            if let summary = model.summary {
                StreakBadge(streak: summary.streak.current)
            }
        }
    }

    private func fix(_ issue: HealthIssue) {
        switch issue {
        case .alarmKitNotAuthorized:
            if model.authorization == .notDetermined { showPermissions = true } else { onOpenSettings() }
        case .nextAlarmNotArmed:
            Task { await model.refresh() }
        default:
            onOpenSettings()
        }
    }
}

// MARK: - Cards

/// A ringing alarm: big push-up target, the deadline, one huge start button.
struct LiveRingCard: View {
    let ring: RingState
    let now: Date
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.m) {
            HStack(spacing: SpacingTokens.xs) {
                Image(systemName: "alarm.waves.left.and.right.fill").foregroundStyle(Color(ColorTokens.brandFlameText))
                    .accessibilityHidden(true)
                Text(ring.practice ? "PRACTICE ALARM" : "ALARM RINGING")
                    .typography(TypographyTokens.overline)
                    .foregroundStyle(Color(ColorTokens.brandFlameText))
                Spacer()
                Text("Deadline \(TimeText.short(TimeText.localTime(ring.deadline)))")
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.textSecondary))
            }
            HStack(alignment: .lastTextBaseline, spacing: SpacingTokens.s) {
                Text(verbatim: "\(ring.target)")
                    .typography(TypographyTokens.displayTime)
                    .foregroundStyle(Color(ColorTokens.textPrimary))
                Text("push-ups to stop it")
                    .typography(TypographyTokens.titleS)
                    .foregroundStyle(Color(ColorTokens.textSecondary))
            }
            .accessibilityElement(children: .combine)
            PrimaryButton("Start push-ups", action: onStart)
        }
        .padding(SpacingTokens.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(ColorTokens.brandFlame).opacity(0.28), Color(ColorTokens.bgSurface)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color(ColorTokens.brandFlame).opacity(0.6), lineWidth: 1.5))
        .shadow(color: Color(ColorTokens.brandFlame).opacity(0.3), radius: 20, y: 8)
    }
}

struct HealthBanner: View {
    let issue: HealthIssue
    let onFix: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: SpacingTokens.xxs) {
            InlineBanner(Self.text(issue), kind: issue.severity == .critical ? .error : .warning)
            if issue != .customSoundMissing {
                GhostButton("Fix", action: onFix)
            }
        }
    }

    static func text(_ issue: HealthIssue) -> LocalizedStringKey {
        switch issue {
        case .alarmKitNotAuthorized: "Pushly isn't allowed to set alarms — your alarm won't ring."
        case .exactAlarmMissing: "Alarms are blocked: allow \"Alarms & reminders\" for Pushly or your alarm won't ring."
        case .fullScreenIntentMissing: "Full-screen alarms are off: the alarm can't show over your lock screen."
        case .notificationsBlocked: "Notifications are blocked: the alarm can't ring."
        case .alarmChannelMuted: "The \"Alarms\" notification category is muted."
        case .cameraDenied: "Camera access is off: you can't complete the push-up challenge."
        case .nextAlarmNotArmed: "Your next alarm isn't scheduled. Open Pushly again, or reinstall if this keeps happening."
        case .batteryRestricted: "Your phone may stop Pushly to save battery. Allow it to run in the background."
        case .alarmVolumeZero: "Alarm volume is at 0."
        case .customSoundMissing: "A custom sound is missing — the default sound will play."
        }
    }
}

/// The hero: next alarm time, a ring counting down the last 24 hours, the challenge it carries.
struct NextAlarmCard: View {
    let model: WakeModel
    let onNew: () -> Void

    var body: some View {
        Group {
            if let next = model.next {
                let schedule = model.items.first { $0.schedule.id == next.alarmID }?.schedule
                let local = TimeText.localTime(next.instant)
                let parts = TimeText.parts(local)
                let left = next.instant.timeIntervalSince(model.now)
                VStack(alignment: .leading, spacing: SpacingTokens.m) {
                    HStack(alignment: .center, spacing: SpacingTokens.l) {
                        VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                            Text("NEXT ALARM · \(TimeText.dayShort(next.localDate.weekday).uppercased())")
                                .typography(TypographyTokens.overline)
                                .foregroundStyle(Color(ColorTokens.brandFlameText))
                            HStack(alignment: .lastTextBaseline, spacing: SpacingTokens.xs) {
                                Text(verbatim: parts.main)
                                    .typography(TypographyTokens.displayTime)
                                    .foregroundStyle(Color(ColorTokens.textPrimary))
                                    .minimumScaleFactor(0.6)
                                    .lineLimit(1)
                                if let suffix = parts.suffix {
                                    Text(verbatim: suffix)
                                        .typography(TypographyTokens.labelDisplay)
                                        .foregroundStyle(Color(ColorTokens.textTertiary))
                                }
                            }
                            .accessibilityElement(children: .combine)
                            if let schedule, !schedule.label.isEmpty {
                                Text(verbatim: schedule.label)
                                    .typography(TypographyTokens.bodyS)
                                    .foregroundStyle(Color(ColorTokens.textSecondary))
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                        CountdownRing(fraction: WakeCountdown.fraction(secondsLeft: left), text: TimeText.until(left))
                            .frame(width: 92, height: 92)
                    }
                    if let schedule {
                        HStack(spacing: SpacingTokens.s) {
                            InfoChip(symbol: "figure.strengthtraining.functional", text: String(localized: "\(schedule.mode.totalReps) push-ups"))
                            InfoChip(symbol: "bolt.fill", text: ModeText.name(schedule.mode.modeType ?? .ringUntilDone))
                            InfoChip(symbol: "calendar", text: ScheduleText.days(schedule))
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: SpacingTokens.m) {
                    ZStack {
                        Circle().fill(Color(ColorTokens.brandFlame).opacity(0.16)).frame(width: 72, height: 72)
                        Image(systemName: "alarm.fill").font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(LinearGradient(GradientTokens.hero))
                    }
                    .accessibilityHidden(true)
                    Text("No alarm set")
                        .typography(TypographyTokens.displayM)
                        .foregroundStyle(Color(ColorTokens.textPrimary))
                    Text("Set your first alarm. It only stops when you do your push-ups.")
                        .typography(TypographyTokens.body)
                        .foregroundStyle(Color(ColorTokens.textSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                    PrimaryButton("Set an alarm", action: onNew)
                        .padding(.top, SpacingTokens.xs)
                }
            }
        }
        .padding(SpacingTokens.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .topTrailing) {
                LinearGradient(colors: [Color(ColorTokens.bgSurface), Color(ColorTokens.bgElevated)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                GlowSpot(ColorTokens.brandFlame, size: 300, intensity: 0.35).offset(x: 110, y: -120)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color(ColorTokens.strokeSubtle), lineWidth: 1))
    }
}

/// Time left until the alarm as a ring that fills up over the last 24 hours.
struct CountdownRing: View {
    let fraction: Double
    let text: String

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: 8)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(LinearGradient(GradientTokens.hero), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("in").typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.textTertiary))
                Text(verbatim: text)
                    .typography(TypographyTokens.labelDisplay)
                    .foregroundStyle(Color(ColorTokens.textPrimary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Rings in \(text)"))
    }
}

struct InfoChip: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.caption.weight(.semibold)).foregroundStyle(Color(ColorTokens.brandFlameText))
                .accessibilityHidden(true)
            Text(verbatim: text).typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.textPrimary))
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .padding(.horizontal, SpacingTokens.s)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.06), in: Capsule())
        .overlay(Capsule().strokeBorder(Color(ColorTokens.strokeSubtle)))
    }
}

/// Streak, beaten this week, push-ups today — three equal tiles.
struct WakeStatsRow: View {
    let summary: WakeSummary

    var body: some View {
        HStack(spacing: SpacingTokens.s) {
            tile("🔥", "\(summary.streak.current)", String(localized: "Day streak"),
                 String(localized: "Best \(summary.streak.best)"), ColorTokens.brandFlameText)
            tile("✅", "\(WakeWeek.beaten(summary))/\(WakeWeek.challenges(summary))", String(localized: "This week"),
                 String(localized: "beaten"), ColorTokens.stateSuccessText)
            tile("💪", "\(summary.repsToday ?? 0)", String(localized: "Push-ups"), String(localized: "today"), ColorTokens.brandVoltText)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func tile(_ glyph: String, _ value: String, _ title: String, _ sub: String, _ tint: TokenColor) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: glyph).font(.title3).accessibilityHidden(true)
            Text(verbatim: value)
                .typography(TypographyTokens.titleL)
                .foregroundStyle(Color(tint))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(verbatim: title).typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.textPrimary)).lineLimit(1)
            Text(verbatim: sub).typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.textTertiary)).lineLimit(1)
        }
        .padding(SpacingTokens.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(colors: [Color(tint).opacity(0.12), Color(ColorTokens.bgSurface)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous).strokeBorder(Color(ColorTokens.strokeSubtle)))
        .accessibilityElement(children: .combine)
    }
}

/// "This week" card around the Monday–Sunday strip.
struct WeekCard: View {
    let summary: WakeSummary

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.m) {
            HStack {
                Text("This week").typography(TypographyTokens.titleS).foregroundStyle(Color(ColorTokens.textPrimary))
                Spacer()
                if summary.streak.freezesAvailable > 0 {
                    Label("\(summary.streak.freezesAvailable) freezes", systemImage: "snowflake")
                        .typography(TypographyTokens.caption)
                        .foregroundStyle(Color(ColorTokens.brandCyan))
                }
            }
            WeekStrip(summary: summary)
        }
        .padding(SpacingTokens.m)
        .background(Color(ColorTokens.bgSurface), in: RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous).strokeBorder(Color(ColorTokens.strokeSubtle)))
    }
}

struct AlarmRow: View {
    let item: WakeModel.Item
    let model: WakeModel
    let onEdit: () -> Void

    var body: some View {
        let s = item.schedule
        let title = ScheduleText.singleTime(s).flatMap(TimeText.short)
            ?? item.next.map { TimeText.short(TimeText.localTime($0.instant)) } ?? "—"
        VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            HStack(alignment: .center, spacing: SpacingTokens.m) {
                Button(action: onEdit) {
                    VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                        HStack(alignment: .firstTextBaseline, spacing: SpacingTokens.s) {
                            Text(verbatim: title)
                                .typography(TypographyTokens.stat)
                                .foregroundStyle(Color(s.enabled ? ColorTokens.textPrimary : ColorTokens.textDisabled))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            if !s.label.isEmpty {
                                Text(verbatim: s.label)
                                    .typography(TypographyTokens.bodyS)
                                    .foregroundStyle(Color(ColorTokens.textSecondary))
                                    .lineLimit(1)
                            }
                        }
                        DayDots(schedule: s)
                        Text(verbatim: ModeText.summary(s.mode))
                            .typography(TypographyTokens.caption)
                            .foregroundStyle(Color(ColorTokens.textTertiary))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Edit alarm"))
                Toggle("Alarm on", isOn: Binding(
                    get: { s.enabled },
                    set: { on in Task { await model.setEnabled(id: s.id, on) } }
                ))
                .labelsHidden()
                .tint(Color(ColorTokens.brandFlame))
                .accessibilityLabel(Text("Alarm on, \(title)"))
            }
            if s.enabled {
                HStack(spacing: SpacingTokens.s) {
                    if let skipped = item.skippedDate {
                        Label("Next ring skipped (\(skipped))", systemImage: "forward.end.fill")
                            .typography(TypographyTokens.caption)
                            .foregroundStyle(Color(ColorTokens.stateWarning))
                        Spacer()
                        GhostButton("Undo") { Task { await model.undoSkip(id: s.id, date: skipped) } }
                    } else if let next = item.next {
                        Label(TimeText.until(next.instant.timeIntervalSince(model.now)), systemImage: "clock")
                            .typography(TypographyTokens.caption)
                            .foregroundStyle(Color(ColorTokens.textSecondary))
                        Spacer()
                        GhostButton("Skip next") { Task { await model.skipNext(id: s.id) } }
                    }
                }
                if let pause = s.pause {
                    Text("Paused until \(pause.to)")
                        .typography(TypographyTokens.caption)
                        .foregroundStyle(Color(ColorTokens.stateWarning))
                }
            }
        }
        .padding(SpacingTokens.m)
        .background(Color(ColorTokens.bgSurface).opacity(s.enabled ? 1 : 0.6), in: RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous))
        .overlay(alignment: .leading) {
            if s.enabled {
                Capsule().fill(LinearGradient(GradientTokens.hero)).frame(width: 4).padding(.vertical, SpacingTokens.m)
                    .accessibilityHidden(true)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: RadiusTokens.l, style: .continuous).strokeBorder(Color(ColorTokens.strokeSubtle)))
    }
}

/// M T W T F S S — the alarm's days lit, the others dimmed (one-off alarms show their date).
struct DayDots: View {
    let schedule: AlarmSchedule

    var body: some View {
        if schedule.kind == .oneOff {
            Text(verbatim: ScheduleText.days(schedule))
                .typography(TypographyTokens.bodyS)
                .foregroundStyle(Color(ColorTokens.textSecondary))
        } else {
            HStack(spacing: 4) {
                ForEach(Weekday.mondayFirst, id: \.self) { day in
                    let on = schedule.weekly?[day] != nil
                    Text(verbatim: TimeText.dayNarrow(day))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(on ? Color(ColorTokens.bgBase) : Color(ColorTokens.textTertiary))
                        .frame(width: 20, height: 20)
                        .background(on ? AnyShapeStyle(LinearGradient(GradientTokens.hero)) : AnyShapeStyle(Color.white.opacity(0.06)), in: Circle())
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: ScheduleText.days(schedule)))
        }
    }
}

/// 🔥 current wake streak (PS-10).
struct StreakBadge: View {
    let streak: Int

    var body: some View {
        HStack(spacing: 4) {
            Text(verbatim: "🔥").accessibilityHidden(true)
            Text(verbatim: "\(streak)")
                .typography(TypographyTokens.titleS)
                .foregroundStyle(Color(streak > 0 ? ColorTokens.brandFlameText : ColorTokens.textTertiary))
        }
        .padding(.horizontal, SpacingTokens.sm)
        .frame(minHeight: 36)
        .background(Color(ColorTokens.brandFlame).opacity(streak > 0 ? 0.16 : 0.06), in: Capsule())
        .overlay(Capsule().strokeBorder(Color(ColorTokens.brandFlame).opacity(streak > 0 ? 0.5 : 0.15)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(streak) day wake streak"))
    }
}

/// Wake tab rules shared with Android `WakeTabRules` (D-079).
public enum WakeGreeting {
    public static func text(hour: Int) -> LocalizedStringKey {
        switch hour {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        case 18..<23: "Good evening"
        default: "Good night"
        }
    }

    /// Same buckets as `text`, as a key for tests.
    public static func bucket(hour: Int) -> String {
        switch hour {
        case 5..<12: "morning"
        case 12..<18: "afternoon"
        case 18..<23: "evening"
        default: "night"
        }
    }
}

public enum WakeCountdown {
    /// 0 a day or more before the alarm → 1 when it rings.
    public static func fraction(secondsLeft: TimeInterval) -> Double {
        let day: TimeInterval = 86400
        return min(1, max(0, 1 - secondsLeft / day))
    }
}

public enum WakeWeek {
    /// Monday..Sunday (local) of the summary's today.
    public static func dates(_ summary: WakeSummary) -> [String] {
        guard let today = LocalDate(summary.today) else { return [] }
        let offset = Weekday.allCases.firstIndex(of: today.weekday) ?? 0
        let monday = today.adding(days: -offset)
        return (0..<7).map { monday.adding(days: $0).description }
    }

    /// Challenges beaten this week.
    public static func beaten(_ summary: WakeSummary) -> Int {
        let week = Set(dates(summary))
        return summary.attempts.filter { week.contains($0.localDate) && $0.status == "succeeded" }.count
    }

    /// Challenges decided this week (beaten, failed or missed).
    public static func challenges(_ summary: WakeSummary) -> Int {
        let week = Set(dates(summary))
        return summary.attempts.filter { week.contains($0.localDate) && ["succeeded", "failed", "missed"].contains($0.status) }.count
    }
}

/// This week, Monday–Sunday (PS-13): every day is the same soft disc; ✓ green = beaten, ✕ red = failed / missed,
/// – = skipped / paused, empty = no challenge; upcoming days are dimmed and today has a flame ring.
struct WeekStrip: View {
    let summary: WakeSummary

    private var days: [(label: String, date: String)] {
        guard let today = LocalDate(summary.today) else { return [] }
        let offset = Weekday.allCases.firstIndex(of: today.weekday) ?? 0
        let monday = today.adding(days: -offset)
        let labels = ["M", "T", "W", "T", "F", "S", "S"]
        return (0..<7).map { (labels[$0], monday.adding(days: $0).description) }
    }

    var body: some View {
        HStack(spacing: SpacingTokens.s) {
            ForEach(days, id: \.date) { day in
                let status = summary.status(on: day.date)
                let isToday = day.date == summary.today
                VStack(spacing: SpacingTokens.xs) {
                    ZStack {
                        Circle().fill(fill(status))
                        if let glyph = glyph(status) {
                            Image(systemName: glyph)
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(Color(status == "succeeded" ? ColorTokens.bgBase : ColorTokens.textPrimary))
                        }
                    }
                    .frame(width: 30, height: 30)
                    .opacity(day.date > summary.today ? 0.45 : 1)
                    .padding(3)
                    .overlay(Circle().stroke(Color(ColorTokens.brandFlame), lineWidth: isToday ? 2 : 0))
                    Text(verbatim: day.label)
                        .typography(TypographyTokens.caption)
                        .fontWeight(isToday ? .bold : .regular)
                        .foregroundStyle(Color(isToday ? ColorTokens.textPrimary : ColorTokens.textTertiary))
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(day.date): \(label(status))"))
            }
        }
    }

    private func fill(_ status: String?) -> Color {
        switch status {
        case "succeeded": Color(ColorTokens.stateSuccess)
        case "failed", "missed": Color(ColorTokens.stateDanger)
        default: Color(ColorTokens.bgElevated)
        }
    }

    private func glyph(_ status: String?) -> String? {
        switch status {
        case "succeeded": "checkmark"
        case "failed", "missed": "xmark"
        case "skipped", "paused", "void": "minus"
        default: nil
        }
    }

    private func label(_ status: String?) -> String {
        switch status {
        case "succeeded": String(localized: "beaten")
        case "failed", "missed": String(localized: "failed")
        case "skipped": String(localized: "skipped")
        case "paused": String(localized: "paused")
        default: String(localized: "no challenge")
        }
    }
}
