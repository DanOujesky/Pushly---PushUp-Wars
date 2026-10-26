import DesignSystem
import SwiftUI

/// "5 sets · 75 push-ups · ~8 min · EMOM".
struct WorkoutPills: View {
    let workout: Workout

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: SpacingTokens.xs) { pills }
            VStack(alignment: .leading, spacing: SpacingTokens.xs) { pills }
        }
    }

    @ViewBuilder private var pills: some View {
        Pill("\(workout.sets.count) sets")
        if let planned = workout.plannedReps {
            Pill("\(planned) push-ups", color: ColorTokens.brandFlameText)
        }
        Pill(LocalizedStringKey(WorkoutText.duration(workout.estimatedSeconds)))
        if let every = workout.everyS { Pill("Every \(every) s", color: ColorTokens.brandVoltText) }
    }
}

struct WorkoutDetailSheet: View {
    let workout: Workout
    let onStart: () -> Void
    let onEdit: () -> Void
    let onDelete: (() -> Void)?
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.m) {
            Text(verbatim: workout.name)
                .typography(TypographyTokens.titleL)
                .foregroundStyle(Color(ColorTokens.textPrimary))
                .padding(.top, SpacingTokens.l)
            if !workout.description.isEmpty {
                Text(verbatim: workout.description)
                    .typography(TypographyTokens.bodyS)
                    .foregroundStyle(Color(ColorTokens.textSecondary))
            }
            WorkoutPills(workout: workout)
            ScrollView {
                VStack(spacing: SpacingTokens.xs) {
                    ForEach(Array(workout.sets.enumerated()), id: \.offset) { i, s in
                        HStack {
                            Text("Set \(i + 1)")
                                .typography(TypographyTokens.bodyS)
                                .foregroundStyle(Color(ColorTokens.textTertiary))
                                .frame(width: 64, alignment: .leading)
                            Text(verbatim: WorkoutText.setLabel(s))
                                .typography(TypographyTokens.titleS)
                                .foregroundStyle(Color(ColorTokens.textPrimary))
                            Spacer()
                            if workout.everyS == nil, i < workout.sets.count - 1, s.restS > 0 {
                                Text("rest \(s.restS) s")
                                    .typography(TypographyTokens.caption)
                                    .foregroundStyle(Color(ColorTokens.textTertiary))
                            }
                        }
                        .frame(minHeight: 36)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            PrimaryButton("Start workout", action: onStart)
            HStack {
                GhostButton(workout.isPreset ? "Copy & edit" : "Edit", action: onEdit)
                if onDelete != nil {
                    Spacer()
                    GhostButton("Delete") { confirmDelete = true }
                }
            }
        }
        .padding(SpacingTokens.l)
        .background(Color(ColorTokens.bgSurface).ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .confirmationDialog(Text("Delete this workout?"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { onDelete?() }
        }
    }
}

/// Per-set results on the summary.
struct WorkoutSetResults: View {
    let workout: Workout
    let sets: [WorkoutRunner.SetResult]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                Text("Sets")
                    .typography(TypographyTokens.titleS)
                    .foregroundStyle(Color(ColorTokens.textPrimary))
                ForEach(Array(sets.enumerated()), id: \.offset) { i, r in
                    HStack {
                        Image(systemName: r.completed ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(Color(r.completed ? ColorTokens.stateSuccessText : ColorTokens.textTertiary))
                            .accessibilityHidden(true)
                        Text("Set \(i + 1)")
                            .typography(TypographyTokens.bodyS)
                            .foregroundStyle(Color(ColorTokens.textSecondary))
                        Spacer()
                        let kind = i < workout.sets.count ? workout.sets[i].kind : .amrap
                        Text(verbatim: kind == .reps ? "\(r.reps) / \(r.target)" : "\(r.reps)")
                            .typography(TypographyTokens.titleS)
                            .foregroundStyle(Color(ColorTokens.textPrimary))
                    }
                    .frame(minHeight: 32)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text("Set \(i + 1): \(r.reps) push-ups"))
                }
                let skipped = workout.sets.count - sets.count
                if skipped > 0 {
                    Text("\(skipped) sets skipped")
                        .typography(TypographyTokens.caption)
                        .foregroundStyle(Color(ColorTokens.textTertiary))
                }
            }
        }
    }
}
