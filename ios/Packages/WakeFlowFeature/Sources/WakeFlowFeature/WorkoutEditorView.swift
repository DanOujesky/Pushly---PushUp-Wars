import DesignSystem
import SwiftUI

/// Create / edit a workout (D-069): name, sets (reps, max or timed), rest after each set, optional EMOM interval.
/// Saving is blocked until `Workout.validationErrors` is empty (same rules as the reference).
struct WorkoutEditorView: View {
    @State private var workout: Workout
    @State private var emom: Bool
    let onSave: (Workout) -> Void
    let onCancel: () -> Void

    init(workout: Workout, onSave: @escaping (Workout) -> Void, onCancel: @escaping () -> Void) {
        _workout = State(initialValue: workout)
        _emom = State(initialValue: workout.everyS != nil)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    static func blank() -> Workout {
        Workout(name: "", sets: Array(repeating: WorkoutSet(kind: .reps, target: 10, restS: 60), count: 3))
    }

    private var errors: [String] { workout.validationErrors }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(text: $workout.name, prompt: Text("e.g. Morning blast")) { Text("Name") }
                        .textInputAutocapitalization(.sentences)
                    TextField(text: $workout.description, prompt: Text("Optional")) { Text("Note") }
                } header: { Text("Workout") }

                Section {
                    Toggle(isOn: $emom.animation()) { Text("Every minute on the minute (EMOM)") }
                        .onChange(of: emom) { _, on in
                            workout.everyS = on ? (workout.everyS ?? 60) : nil
                            if on {
                                for i in workout.sets.indices where workout.sets[i].kind != .reps {
                                    workout.sets[i] = WorkoutSet(kind: .reps, target: 10, restS: 0)
                                }
                            }
                        }
                    if emom {
                        Stepper(value: Binding(get: { workout.everyS ?? 60 }, set: { workout.everyS = $0 }),
                                in: Workout.everyRange, step: 5) {
                            Text("New set every \(workout.everyS ?? 60) s")
                        }
                    }
                } footer: {
                    Text(emom ? "Each set starts on the clock. Finish early = more rest. Not done in time = the next set starts anyway."
                              : "Rest is set per set, after it ends.")
                }

                ForEach(workout.sets.indices, id: \.self) { i in
                    Section {
                        if !emom {
                            Picker(selection: kindBinding(i)) {
                                Text("Reps").tag(SetKind.reps)
                                Text("Max").tag(SetKind.amrap)
                                Text("Timed").tag(SetKind.timed)
                            } label: { Text("Type") }
                                .pickerStyle(.segmented)
                        }
                        switch workout.sets.indices.contains(i) ? workout.sets[i].kind : .reps {
                        case .reps:
                            Stepper(value: value(i, \.target), in: 1...Workout.maxTargetReps) {
                                Text("\(value(i, \.target).wrappedValue) push-ups")
                            }
                        case .timed:
                            Stepper(value: value(i, \.target), in: Workout.timedRange, step: 5) {
                                Text("\(value(i, \.target).wrappedValue) s all-out")
                            }
                        case .amrap:
                            Text("As many as you can — ends when you stop for 6 s or tap End set.")
                                .typography(TypographyTokens.caption)
                                .foregroundStyle(Color(ColorTokens.textSecondary))
                        }
                        if !emom, i < workout.sets.count - 1 {
                            Stepper(value: value(i, \.restS), in: 0...Workout.maxRestS, step: 5) {
                                Text("Rest \(value(i, \.restS).wrappedValue) s")
                            }
                        }
                        HStack {
                            Button { duplicate(i) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                                .disabled(workout.sets.count >= Workout.maxSets)
                            Spacer()
                            Button(role: .destructive) { remove(i) } label: { Label("Remove", systemImage: "trash") }
                                .disabled(workout.sets.count <= 1)
                        }
                        .buttonStyle(.borderless)
                    } header: { Text("Set \(i + 1)") }
                }

                Section {
                    Button { duplicate(workout.sets.count - 1) } label: { Label("Add set", systemImage: "plus") }
                        .disabled(workout.sets.isEmpty || workout.sets.count >= Workout.maxSets)
                } footer: {
                    if let planned = workout.plannedReps {
                        Text("\(workout.sets.count) sets · \(planned) push-ups · \(WorkoutText.duration(workout.estimatedSeconds))")
                    } else {
                        Text("\(workout.sets.count) sets · \(WorkoutText.duration(workout.estimatedSeconds))")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(ColorTokens.bgBase).ignoresSafeArea())
            .navigationTitle(Text(workout.name.isEmpty ? "New workout" : "Edit workout"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var w = workout
                        w.name = w.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        w.description = w.description.trimmingCharacters(in: .whitespacesAndNewlines)
                        // rest after the last set never happens
                        if let last = w.sets.indices.last { w.sets[last].restS = 0 }
                        if w.everyS != nil { for i in w.sets.indices { w.sets[i].restS = 0 } }
                        onSave(w)
                    }
                    .disabled(!errors.isEmpty)
                }
            }
        }
    }

    /// Index-safe binding (a removed row can still be read once while it animates out).
    private func value(_ i: Int, _ field: WritableKeyPath<WorkoutSet, Int>) -> Binding<Int> {
        Binding(get: { workout.sets.indices.contains(i) ? workout.sets[i][keyPath: field] : 0 },
                set: { if workout.sets.indices.contains(i) { workout.sets[i][keyPath: field] = $0 } })
    }

    private func kindBinding(_ i: Int) -> Binding<SetKind> {
        Binding(get: { workout.sets.indices.contains(i) ? workout.sets[i].kind : .reps }, set: { kind in
            guard workout.sets.indices.contains(i), workout.sets[i].kind != kind else { return }
            workout.sets[i].kind = kind
            workout.sets[i].target = switch kind {
            case .reps: 10
            case .timed: 30
            case .amrap: 0
            }
        })
    }

    private func duplicate(_ i: Int) {
        guard workout.sets.indices.contains(i), workout.sets.count < Workout.maxSets else { return }
        var copy = workout.sets[i]
        if copy.restS == 0, !emom { copy.restS = 60 }
        if i == workout.sets.count - 1, workout.sets[i].restS == 0, !emom { workout.sets[i].restS = 60 }
        workout.sets.insert(copy, at: i + 1)
    }

    private func remove(_ i: Int) {
        guard workout.sets.count > 1, workout.sets.indices.contains(i) else { return }
        workout.sets.remove(at: i)
    }
}
