#if DEBUG
import DesignSystem
import SwiftUI
import UIKit

/// Debug-only pose recorder screen (P3-04): do a set, label it (how many reps a human would count + tags) and share
/// the JSON to the computer. See docs/qa/pose-recording.md.
public struct PoseRecorderView: View {
    let onClose: () -> Void
    @State private var model = RepSessionModel(mode: .training, record: true) { _ in }
    @State private var labelling = false
    @State private var count = 0
    @State private var placement = "side"
    @State private var tags: Set<String> = []
    @State private var notes = ""
    @State private var exported: URL?

    static let tagOptions = ["normal", "cheat", "half", "knees", "sag", "pike", "fast", "slow", "edge",
                             "loose-clothing", "dim-light", "rear-camera", "two-people", "screen-replay"]

    public init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    public var body: some View {
        if labelling {
            form
        } else {
            RepSessionView(model: model) {
                HStack {
                    GhostButton("Cancel", action: onClose)
                    Spacer()
                    PrimaryButton("Stop & label") {
                        model.finish()
                        count = model.counted
                        labelling = true
                    }
                    .frame(maxWidth: 180)
                }
            }
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpacingTokens.m) {
                ScreenTitle("Label the set", token: TypographyTokens.displayM)
                Text("Engine counted \(model.counted). Recorded \(model.recorder?.frameCount ?? 0) frames.")
                    .typography(TypographyTokens.bodyS)
                    .foregroundStyle(Color(ColorTokens.textSecondary))
                Stepper(value: $count, in: 0...200) {
                    Text("Real push-ups (human count): \(count)").typography(TypographyTokens.body)
                }
                Picker("Placement", selection: $placement) {
                    Text("Side").tag("side")
                    Text("Front").tag("front")
                }
                .pickerStyle(.segmented)
                SectionLabel("Tags")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: SpacingTokens.s) {
                    ForEach(Self.tagOptions, id: \.self) { tag in
                        let on = tags.contains(tag)
                        Button {
                            if on { tags.remove(tag) } else { tags.insert(tag) }
                        } label: {
                            Text(verbatim: tag)
                                .typography(TypographyTokens.caption)
                                .foregroundStyle(Color(on ? ColorTokens.brandFlameText : ColorTokens.textSecondary))
                                .frame(maxWidth: .infinity, minHeight: TouchTarget.minimum)
                                .background(Color(ColorTokens.bgSurface), in: Capsule())
                                .overlay(Capsule().stroke(Color(on ? ColorTokens.brandFlame : ColorTokens.strokeSubtle)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                PushlyTextField("Notes", placeholder: "lighting, clothing, who…", text: $notes)
                if let exported {
                    ShareLink(item: exported) {
                        Text("Share \(exported.lastPathComponent)").typography(TypographyTokens.button)
                    }
                } else {
                    PrimaryButton("Save vector") { save() }
                }
                GhostButton("Done", action: onClose)
            }
            .padding(SpacingTokens.l)
        }
        .background(Color(ColorTokens.bgBase).ignoresSafeArea())
    }

    private func save() {
        guard let recorder = model.recorder else { return }
        let label = PoseRecorder.Label(humanCount: count, placement: placement, tags: tags.sorted(), notes: notes)
        exported = try? recorder.export(label: label, device: UIDevice.current.model)
    }
}
#endif
