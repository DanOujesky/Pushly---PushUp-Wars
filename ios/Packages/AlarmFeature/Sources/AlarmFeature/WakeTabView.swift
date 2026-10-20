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
    @State private var training = false
    @State private var recording = false
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
                VStack(alignment: .leading, spacing: SpacingTokens.m) {
                    ScreenTitle("Wake", token: TypographyTokens.displayM)

                    if let live = model.live {
                        LiveRingCard(ring: live, now: model.now) {
                            Task { await model.startSession(live) }
                        }
                    }

                    ForEach(model.health, id: \.self) { issue in
                        HealthBanner(issue: issue) { fix(issue) }
                    }

                    if let notice = model.notice {
                        InlineBanner(notice == .testArmed
                            ? "Test alarm rings in 10 seconds. Lock your phone to see the real thing."
                            : "Couldn't schedule the test alarm. Allow alarms first.", kind: .info)
                    }

                    NextAlarmCard(model: model) { editing = EditorRoute(schedule: model.newSchedule(), isNew: true) }

                    SecondaryButton("Free training") { training = true }
                    #if DEBUG
                    GhostButton("Pose recorder (debug)") { recording = true }
                    #endif

                    if !model.items.isEmpty {
                        HStack {
                            SectionLabel("Your alarms")
                            Spacer()
                            Text("\(model.items.count) of \(AlarmSchedule.maxAlarmsPerUser) alarms")
                                .typography(TypographyTokens.caption)
                                .foregroundStyle(Color(ColorTokens.textTertiary))
                        }
                        ForEach(model.items) { item in
                            AlarmRow(item: item, model: model) {
                                editing = EditorRoute(schedule: item.schedule, isNew: false)
                            }
                        }
                        if model.canAddAlarm {
                            SecondaryButton("+ New alarm") {
                                editing = EditorRoute(schedule: model.newSchedule(), isNew: true)
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
        .fullScreenCover(isPresented: $training) {
            TrainingView { training = false }
        }
        #if DEBUG
        .fullScreenCover(isPresented: $recording) {
            PoseRecorderView { recording = false }
        }
        #endif
        .sheet(isPresented: $showPermissions) {
            AlarmPermissionView(model: model, onOpenSettings: onOpenSettings) { showPermissions = false }
                .presentationDetents([.large])
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

struct LiveRingCard: View {
    let ring: RingState
    let now: Date
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            Pill(ring.practice ? "Practice alarm" : "Alarm ringing", color: ColorTokens.brandFlameText)
            Text("\(ring.target) push-ups to stop it")
                .typography(TypographyTokens.titleM)
                .foregroundStyle(Color(ColorTokens.textPrimary))
            Text("Deadline \(TimeText.short(TimeText.localTime(ring.deadline)))")
                .typography(TypographyTokens.caption)
                .foregroundStyle(Color(ColorTokens.textSecondary))
            PrimaryButton("Start push-ups", action: onStart)
        }
        .padding(SpacingTokens.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(ColorTokens.brandFlame).opacity(0.12), in: RoundedRectangle(cornerRadius: RadiusTokens.l))
        .overlay(RoundedRectangle(cornerRadius: RadiusTokens.l).stroke(Color(ColorTokens.brandFlame).opacity(0.5), lineWidth: 1.5))
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

struct NextAlarmCard: View {
    let model: WakeModel
    let onNew: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.s) {
            if let next = model.next {
                let schedule = model.items.first { $0.schedule.id == next.alarmID }?.schedule
                let local = TimeText.localTime(next.instant)
                let parts = TimeText.parts(local)
                HStack {
                    Text("Next alarm · \(TimeText.dayShort(next.localDate.weekday))")
                        .typography(TypographyTokens.overline)
                        .foregroundStyle(Color(ColorTokens.brandFlameText))
                    Spacer()
                    Text(TimeText.until(next.instant.timeIntervalSince(model.now)))
                        .typography(TypographyTokens.caption)
                        .foregroundStyle(Color(ColorTokens.textSecondary))
                }
                HStack(alignment: .lastTextBaseline, spacing: SpacingTokens.s) {
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
                if let schedule {
                    HStack(spacing: SpacingTokens.s) {
                        Pill(LocalizedStringKey(ModeText.name(schedule.mode.modeType ?? .ringUntilDone)))
                        Pill("\(schedule.mode.totalReps) push-ups")
                    }
                }
            } else {
                Text("No alarm set")
                    .typography(TypographyTokens.displayM)
                    .foregroundStyle(Color(ColorTokens.textPrimary))
                Text("Set your first alarm. It only stops when you do your push-ups.")
                    .typography(TypographyTokens.body)
                    .foregroundStyle(Color(ColorTokens.textSecondary))
                PrimaryButton("Set an alarm", action: onNew)
                    .padding(.top, SpacingTokens.s)
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

struct AlarmRow: View {
    let item: WakeModel.Item
    let model: WakeModel
    let onEdit: () -> Void

    var body: some View {
        let s = item.schedule
        let title = ScheduleText.singleTime(s).flatMap(TimeText.short)
            ?? item.next.map { TimeText.short(TimeText.localTime($0.instant)) } ?? "—"
        Card(padding: SpacingTokens.m) {
            VStack(alignment: .leading, spacing: SpacingTokens.s) {
                HStack(alignment: .center) {
                    Button(action: onEdit) {
                        VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                            Text(verbatim: title)
                                .typography(TypographyTokens.stat)
                                .foregroundStyle(Color(s.enabled ? ColorTokens.textPrimary : ColorTokens.textDisabled))
                            Text(verbatim: [ScheduleText.days(s), s.label].filter { !$0.isEmpty }.joined(separator: " · "))
                                .typography(TypographyTokens.bodyS)
                                .foregroundStyle(Color(ColorTokens.textSecondary))
                                .lineLimit(2)
                            Text(verbatim: ModeText.summary(s.mode))
                                .typography(TypographyTokens.caption)
                                .foregroundStyle(Color(ColorTokens.textTertiary))
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
                    if let skipped = item.skippedDate {
                        HStack {
                            Text("Next ring skipped (\(skipped))")
                                .typography(TypographyTokens.caption)
                                .foregroundStyle(Color(ColorTokens.stateWarning))
                            Spacer()
                            GhostButton("Undo") { Task { await model.undoSkip(id: s.id, date: skipped) } }
                        }
                    } else if item.next != nil {
                        GhostButton("Skip next") { Task { await model.skipNext(id: s.id) } }
                    }
                    if let pause = s.pause {
                        Text("Paused until \(pause.to)")
                            .typography(TypographyTokens.caption)
                            .foregroundStyle(Color(ColorTokens.stateWarning))
                    }
                }
            }
        }
    }
}
