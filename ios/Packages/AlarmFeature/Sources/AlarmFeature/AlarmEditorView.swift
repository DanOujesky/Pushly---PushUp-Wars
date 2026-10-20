import AlarmDomain
import AVFoundation
import DesignSystem
import SwiftUI

/// Create / edit an alarm (doc 02 PS-21…26). No ads here (CLAUDE.md §4.5). Mirrors Android `AlarmEditor`.
struct AlarmEditorView: View {
    let isNew: Bool
    let model: WakeModel
    let onDone: (_ saved: Bool) -> Void

    @State private var draft: AlarmSchedule
    @State private var perDay: Bool
    @State private var errors: Set<String> = []
    @State private var tooMany = false
    @State private var picking: TimeTarget?
    @State private var confirmDelete = false
    @State private var preview = SoundPreview()

    enum TimeTarget: Identifiable, Hashable {
        case all
        case day(Weekday)
        var id: String {
            switch self {
            case .all: "all"
            case let .day(d): d.rawValue
            }
        }
    }

    init(initial: AlarmSchedule, isNew: Bool, model: WakeModel, onDone: @escaping (Bool) -> Void) {
        self.isNew = isNew
        self.model = model
        self.onDone = onDone
        _draft = State(initialValue: initial)
        _perDay = State(initialValue: ScheduleText.singleTime(initial) == nil)
    }

    private var weekly: WeeklyTimes { draft.weekly ?? WeeklyTimes() }

    private var baseTime: String {
        ScheduleText.singleTime(draft) ?? Weekday.allCases.lazy.compactMap { weekly[$0] }.first ?? "06:30"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                GhostButton("Cancel") { onDone(false) }
                Spacer()
            }
            .padding(.horizontal, SpacingTokens.s)

            ScrollView {
                VStack(alignment: .leading, spacing: SpacingTokens.l) {
                    ScreenTitle(isNew ? "New alarm" : "Edit alarm", token: TypographyTokens.displayM)
                    timeSection
                    PushlyTextField("Label", placeholder: String(localized: "Get up, champion"), text: Binding(
                        get: { draft.label },
                        set: { draft.label = String($0.prefix(AlarmSchedule.maxLabelLength)) }
                    ))
                    ModeSection(mode: $draft.mode)
                    countsToggle
                    soundSection
                    pauseSection
                    if tooMany { InlineBanner("You can have up to 20 alarms.") }
                    if !errors.isEmpty { InlineBanner(errorText) }
                    SecondaryButton("Test alarm (10 s)") { Task { await model.testAlarm(draft) } }
                    if !isNew {
                        GhostButton("Delete alarm") { confirmDelete = true }
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, SpacingTokens.ml)
                .padding(.bottom, SpacingTokens.l)
            }
            .scrollBounceBehavior(.basedOnSize)

            PrimaryButton("Save alarm") { save() }
                .padding(.horizontal, SpacingTokens.ml)
                .padding(.vertical, SpacingTokens.s)
        }
        .arenaBackground(glow: ColorTokens.brandFlame, alignment: .top, offset: CGSize(width: 0, height: -260))
        .sheet(item: $picking) { target in
            TimePickerSheet(initial: initialTime(for: target)) { picked in
                apply(picked, to: target)
                picking = nil
            }
            .presentationDetents([.medium])
        }
        .confirmationDialog("Delete this alarm?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete alarm", role: .destructive) {
                Task {
                    await model.delete(id: draft.id)
                    onDone(false)
                }
            }
        }
        .onDisappear { preview.stop() }
    }

    // MARK: Sections

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            if !perDay {
                let parts = TimeText.parts(LocalTime(baseTime) ?? LocalTime(hour: 6, minute: 30))
                Button { picking = .all } label: {
                    HStack(alignment: .lastTextBaseline, spacing: SpacingTokens.s) {
                        Text(verbatim: parts.main).typography(TypographyTokens.displayTime)
                        if let suffix = parts.suffix {
                            Text(verbatim: suffix)
                                .typography(TypographyTokens.labelDisplay)
                                .foregroundStyle(Color(ColorTokens.textTertiary))
                        }
                    }
                    .foregroundStyle(Color(ColorTokens.textPrimary))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SpacingTokens.m)
                    .background(Color(ColorTokens.bgSurface), in: RoundedRectangle(cornerRadius: RadiusTokens.l))
                    .overlay(RoundedRectangle(cornerRadius: RadiusTokens.l).stroke(Color(ColorTokens.strokeSubtle), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Alarm time \(TimeText.short(baseTime) ?? baseTime)"))
                .accessibilityHint(Text("Pick time"))
            }
            SectionLabel("Days")
            HStack(spacing: 6) {
                ForEach(Weekday.allCases, id: \.self) { day in
                    let on = weekly[day] != nil
                    Button {
                        var w = weekly
                        w[day] = on ? nil : baseTime
                        draft.weekly = w
                    } label: {
                        Text(verbatim: TimeText.dayNarrow(day))
                            .typography(TypographyTokens.titleS)
                            .foregroundStyle(on ? Color.white : Color(ColorTokens.textSecondary))
                            .frame(maxWidth: .infinity, minHeight: TouchTarget.minimum + 4)
                            .background(Color(on ? ColorTokens.brandFlame : ColorTokens.bgSurface),
                                        in: RoundedRectangle(cornerRadius: RadiusTokens.s))
                            .overlay(RoundedRectangle(cornerRadius: RadiusTokens.s)
                                .stroke(Color(on ? ColorTokens.brandFlame : ColorTokens.strokeSubtle), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: TimeText.dayShort(day)))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Toggle(isOn: Binding(get: { perDay }, set: { on in
                perDay = on
                if !on {
                    var w = WeeklyTimes()
                    for d in Weekday.allCases where weekly[d] != nil { w[d] = baseTime }
                    draft.weekly = w
                }
            })) {
                Text("Different time per day").typography(TypographyTokens.body)
            }
            .tint(Color(ColorTokens.brandFlame))
            if perDay {
                Card(padding: SpacingTokens.s) {
                    VStack(spacing: 0) {
                        ForEach(Weekday.allCases, id: \.self) { day in
                            Button { picking = .day(day) } label: {
                                HStack {
                                    Text(verbatim: TimeText.dayShort(day)).typography(TypographyTokens.body)
                                    Spacer()
                                    Text(TimeText.short(weekly[day]) ?? String(localized: "Off"))
                                        .typography(TypographyTokens.titleS)
                                        .foregroundStyle(Color(weekly[day] == nil ? ColorTokens.textDisabled : ColorTokens.textPrimary))
                                }
                                .foregroundStyle(Color(ColorTokens.textPrimary))
                                .padding(.horizontal, SpacingTokens.s)
                                .frame(minHeight: TouchTarget.minimum + 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var countsToggle: some View {
        Toggle(isOn: $draft.countsForChallenge) {
            VStack(alignment: .leading, spacing: SpacingTokens.xxs) {
                Text("Counts for the Wake Challenge").typography(TypographyTokens.body)
                Text("Only your earliest counting alarm each day counts for streaks and points.")
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.textTertiary))
            }
        }
        .tint(Color(ColorTokens.brandFlame))
    }

    private var soundSection: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            SectionLabel("Sound")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: SpacingTokens.s), GridItem(.flexible())], spacing: SpacingTokens.s) {
                ForEach(AlarmSounds.bundled, id: \.self) { id in
                    let selected = draft.sound.id == id
                    Button {
                        draft.sound.id = id
                        preview.play(AlarmSounds.resourceName(id))
                    } label: {
                        Text(Self.soundName(id))
                            .typography(TypographyTokens.body)
                            .foregroundStyle(Color(selected ? ColorTokens.brandFlameText : ColorTokens.textPrimary))
                            .frame(maxWidth: .infinity, minHeight: TouchTarget.minimum + 4, alignment: .leading)
                            .padding(.horizontal, SpacingTokens.m)
                            .background(Color(ColorTokens.bgSurface), in: RoundedRectangle(cornerRadius: RadiusTokens.m))
                            .overlay(RoundedRectangle(cornerRadius: RadiusTokens.m)
                                .stroke(Color(selected ? ColorTokens.brandFlame : ColorTokens.strokeSubtle), lineWidth: selected ? 1.5 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    static func soundName(_ id: String) -> LocalizedStringKey {
        switch AlarmSounds.resourceName(id) {
        case "rise": "Rise"
        case "arena": "Arena"
        case "classic": "Classic"
        default: "Pulse"
        }
    }

    /// Pause from tomorrow for 3, 7 or 14 days (PS-25; max 30 days, doc 04 §2).
    private var pauseSection: some View {
        let tomorrow = LocalDate(instant: Date(), zone: .current).adding(days: 1)
        let currentDays: Int? = draft.pause.flatMap { p in
            guard let from = LocalDate(p.from), let to = LocalDate(p.to) else { return nil }
            return from.days(until: to) + 1
        }
        return VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            SectionLabel("Pause")
            HStack(spacing: SpacingTokens.s) {
                ForEach([0, 3, 7, 14], id: \.self) { days in
                    let selected = days == 0 ? draft.pause == nil : currentDays == days
                    Button {
                        draft.pause = days == 0 ? nil
                            : AlarmPause(from: tomorrow.description, to: tomorrow.adding(days: days - 1).description)
                    } label: {
                        Text(days == 0 ? "Not paused" : "\(days) days")
                            .typography(TypographyTokens.caption)
                            .foregroundStyle(Color(ColorTokens.textPrimary))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: TouchTarget.minimum + 4)
                            .background(Color(selected ? ColorTokens.brandFlame : ColorTokens.bgSurface).opacity(selected ? 0.18 : 1),
                                        in: RoundedRectangle(cornerRadius: RadiusTokens.s))
                            .overlay(RoundedRectangle(cornerRadius: RadiusTokens.s)
                                .stroke(Color(selected ? ColorTokens.brandFlame : ColorTokens.strokeSubtle), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private var errorText: LocalizedStringKey {
        if errors.contains("weekly.empty") { return "Pick at least one day." }
        if errors.contains(where: { $0.hasPrefix("mode.") }) { return "Check the challenge settings." }
        return "Check the alarm settings."
    }

    // MARK: Actions

    private func initialTime(for target: TimeTarget) -> LocalTime {
        switch target {
        case .all: LocalTime(baseTime) ?? LocalTime(hour: 6, minute: 30)
        case let .day(d): LocalTime(weekly[d] ?? baseTime) ?? LocalTime(hour: 6, minute: 30)
        }
    }

    private func apply(_ t: LocalTime, to target: TimeTarget) {
        var w = weekly
        switch target {
        case .all:
            for d in Weekday.allCases where w[d] != nil { w[d] = t.description }
            if w.isEmpty { w.mon = t.description }
        case let .day(d):
            w[d] = t.description
        }
        draft.weekly = w
    }

    private func save() {
        Task {
            switch await model.save(draft) {
            case .saved:
                preview.stop()
                onDone(true)
            case let .invalid(e):
                errors = e
            case .tooManyAlarms:
                tooMany = true
            }
        }
    }
}

// MARK: - Mode

struct ModeSection: View {
    @Binding var mode: ChallengeMode

    var body: some View {
        let type = mode.modeType ?? .ringUntilDone
        VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            SectionLabel("Challenge")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: SpacingTokens.s), GridItem(.flexible())], spacing: SpacingTokens.s) {
                ForEach(ModeType.allCases, id: \.self) { t in
                    let selected = t == type
                    Button {
                        if !selected { mode = ChallengeMode.defaults(for: t, targetReps: mode.targetReps ?? 20) }
                    } label: {
                        Text(verbatim: ModeText.name(t))
                            .typography(TypographyTokens.bodyS)
                            .foregroundStyle(Color(selected ? ColorTokens.brandFlameText : ColorTokens.textPrimary))
                            .frame(maxWidth: .infinity, minHeight: TouchTarget.minimum + 4, alignment: .leading)
                            .padding(.horizontal, SpacingTokens.sm)
                            .background(Color(selected ? ColorTokens.brandFlame : ColorTokens.bgSurface).opacity(selected ? 0.18 : 1),
                                        in: RoundedRectangle(cornerRadius: RadiusTokens.m))
                            .overlay(RoundedRectangle(cornerRadius: RadiusTokens.m)
                                .stroke(Color(selected ? ColorTokens.brandFlame : ColorTokens.strokeSubtle), lineWidth: selected ? 1.5 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Text(verbatim: ModeText.description(type))
                .typography(TypographyTokens.caption)
                .foregroundStyle(Color(ColorTokens.textSecondary))
            Card(padding: SpacingTokens.m) {
                VStack(spacing: SpacingTokens.s) {
                    switch type {
                    case .ringUntilDone:
                        StepperRow("Push-ups", value: binding(\.targetReps, 20), range: 5...100, step: 5)
                    case .beatTheClock:
                        StepperRow("Push-ups", value: binding(\.targetReps, 20), range: 5...100, step: 5)
                        StepperRow("Time window (s)", value: binding(\.windowSeconds, 120), range: 30...600, step: 30)
                        if AlarmValidation.isVeryHard(mode) {
                            InlineBanner("Very hard: that includes getting out of bed.", kind: .warning)
                        }
                    case .sprint:
                        ChoiceRow("Time window (s)", value: binding(\.windowSeconds, 60), options: [30, 60, 120])
                        StepperRow("Minimum push-ups", value: binding(\.minimumReps, 15), range: 5...100, step: 5)
                    case .sets:
                        StepperRow("Sets", value: binding(\.sets, 3), range: 2...5, step: 1)
                        StepperRow("Push-ups per set", value: binding(\.repsPerSet, 10), range: 5...50, step: 5)
                        StepperRow("Rest (s)", value: binding(\.restSeconds, 45), range: 15...180, step: 15)
                    case .escalation:
                        StepperRow("Push-ups", value: binding(\.targetReps, 20), range: 5...100, step: 5)
                        StepperRow("Push-ups added per snooze", value: binding(\.snoozeAddsReps, 5), range: 1...20, step: 1)
                        StepperRow("Snooze length (min)", value: binding(\.snoozeMinutes, 5), range: 1...10, step: 1)
                        StepperRow("Max snoozes", value: binding(\.maxSnoozes, 3), range: 1...5, step: 1)
                    }
                }
            }
        }
    }

    private func binding(_ key: WritableKeyPath<ChallengeMode, Int?>, _ fallback: Int) -> Binding<Int> {
        Binding(get: { mode[keyPath: key] ?? fallback }, set: { mode[keyPath: key] = $0 })
    }
}

struct StepperRow: View {
    let label: LocalizedStringKey
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int

    init(_ label: LocalizedStringKey, value: Binding<Int>, range: ClosedRange<Int>, step: Int) {
        self.label = label
        _value = value
        self.range = range
        self.step = step
    }

    var body: some View {
        HStack {
            Text(label).typography(TypographyTokens.body).foregroundStyle(Color(ColorTokens.textPrimary))
            Spacer()
            round("minus", enabled: value > range.lowerBound) { value = max(range.lowerBound, value - step) }
            Text(verbatim: "\(value)")
                .typography(TypographyTokens.titleM)
                .foregroundStyle(Color(ColorTokens.textPrimary))
                .frame(minWidth: 56)
            round("plus", enabled: value < range.upperBound) { value = min(range.upperBound, value + step) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(verbatim: "\(value)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
    }

    private func round(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.bold))
                .foregroundStyle(Color(enabled ? ColorTokens.textPrimary : ColorTokens.textDisabled))
                .frame(width: TouchTarget.minimum + 4, height: TouchTarget.minimum + 4)
                .background(Color(ColorTokens.bgElevated), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct ChoiceRow: View {
    let label: LocalizedStringKey
    @Binding var value: Int
    let options: [Int]

    init(_ label: LocalizedStringKey, value: Binding<Int>, options: [Int]) {
        self.label = label
        _value = value
        self.options = options
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.s) {
            Text(label).typography(TypographyTokens.body).foregroundStyle(Color(ColorTokens.textPrimary))
            HStack(spacing: SpacingTokens.s) {
                ForEach(options, id: \.self) { o in
                    let selected = o == value
                    Button { value = o } label: {
                        Text(verbatim: "\(o) s")
                            .typography(TypographyTokens.titleS)
                            .foregroundStyle(Color(ColorTokens.textPrimary))
                            .frame(maxWidth: .infinity, minHeight: TouchTarget.minimum + 4)
                            .background(Color(selected ? ColorTokens.brandFlame : ColorTokens.bgElevated),
                                        in: RoundedRectangle(cornerRadius: RadiusTokens.s))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }
}

struct TimePickerSheet: View {
    let onPicked: (LocalTime) -> Void
    @State private var date: Date

    init(initial: LocalTime, onPicked: @escaping (LocalTime) -> Void) {
        self.onPicked = onPicked
        var c = DateComponents()
        c.hour = initial.hour
        c.minute = initial.minute
        _date = State(initialValue: Calendar.current.date(from: c) ?? Date())
    }

    var body: some View {
        VStack(spacing: SpacingTokens.m) {
            DatePicker("Alarm time", selection: $date, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
            PrimaryButton("Done") { onPicked(TimeText.localTime(date)) }
        }
        .padding(SpacingTokens.l)
        .background(Color(ColorTokens.bgElevated).ignoresSafeArea())
    }
}

/// Plays a short preview of an alarm sound in the editor.
@MainActor
final class SoundPreview {
    private var player: AVAudioPlayer?

    func play(_ name: String) {
        stop()
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        player = try? AVAudioPlayer(contentsOf: url)
        player?.volume = 0.6
        player?.play()
        let current = player
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if self?.player === current { self?.stop() }
        }
    }

    func stop() {
        player?.stop()
        player = nil
    }
}
