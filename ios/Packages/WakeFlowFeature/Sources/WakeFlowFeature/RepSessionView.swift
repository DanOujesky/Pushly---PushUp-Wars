import AVFoundation
import DesignSystem
import PoseEngine
import RepEngine
import SwiftUI
import UIKit

/// Camera push-up screen (doc 05, PS-04/PS-80): live preview, body overlay, huge counter, hints and guidance.
/// Shows the camera pre-permission explainer first if needed (CLAUDE.md §10). No ads here (§4.5).
public struct RepSessionView<Footer: View>: View {
    @Bindable var model: RepSessionModel
    let footer: Footer
    @State private var auth = CameraAuthorization.current
    /// Placement guide (doc 05 §6): shown automatically for the first sessions, then only on request.
    @State private var showGuide = PlacementGuide.shouldShow()
    @Environment(\.openURL) private var openURL

    public init(model: RepSessionModel, @ViewBuilder footer: () -> Footer) {
        self.model = model
        self.footer = footer()
    }

    public var body: some View {
        Group {
            switch auth {
            case .authorized: session
            case .notDetermined, .denied: CameraExplainer(denied: auth == .denied) {
                if auth == .denied {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } else {
                    Task { auth = await CameraAuthorization.request() }
                }
            }
            }
        }
        .background(Color(ColorTokens.bgBase).ignoresSafeArea())
        .onChange(of: auth) { _, a in if a == .authorized { Task { await model.start() } } }
        .task { if auth == .authorized { await model.start() } }
        .onDisappear { model.stop() }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var session: some View {
        ZStack {
            CameraPreview(session: model.captureSession).ignoresSafeArea()
            SkeletonOverlay(landmarks: model.landmarks, imageSize: CGSize(width: model.status.imageWidth, height: model.status.imageHeight),
                            mirrored: true, good: model.state != .notReady)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            LinearGradient(colors: [.black.opacity(0.55), .clear, .clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            VStack(spacing: SpacingTokens.m) {
                counter
                Spacer()
                messages
                footer
            }
            .padding(SpacingTokens.l)
            if showGuide {
                PlacementGuide { showGuide = false }
                    .transition(.opacity)
            } else {
                Button { showGuide = true } label: {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: TouchTarget.minimum, height: TouchTarget.minimum)
                }
                .accessibilityLabel(Text("How to place the phone"))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(SpacingTokens.s)
            }
            #if DEBUG
            // Performance spike P3-01: frame rate + model on screen in debug builds.
            Text(verbatim: "\(Int(model.status.fps.rounded())) fps · \(model.status.model.rawValue)")
                .typography(TypographyTokens.caption)
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(SpacingTokens.s)
                .allowsHitTesting(false)
            #endif
        }
    }

    @ViewBuilder
    private var counter: some View {
        if let display = model.display {
            VStack(spacing: SpacingTokens.xs) {
                Text(verbatim: display.value)
                    .typography(TypographyTokens.displayCounter)
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.spring(duration: MotionTokens.popSeconds), value: display.value)
                    .shadow(color: .black.opacity(0.4), radius: 12)
                Text(verbatim: display.caption)
                    .typography(TypographyTokens.labelDisplay)
                    .foregroundStyle(.white.opacity(0.85))
                if let progress = display.progress {
                    GradientProgressBar(value: progress).frame(maxWidth: 240)
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            standardCounter
        }
    }

    private var standardCounter: some View {
        VStack(spacing: SpacingTokens.xs) {
            Text(verbatim: "\(model.target.map { _ in model.remaining ?? 0 } ?? model.counted)")
                .typography(TypographyTokens.displayCounter)
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.spring(duration: MotionTokens.popSeconds), value: model.counted)
                .shadow(color: .black.opacity(0.4), radius: 12)
            Text(model.target == nil ? LocalizedStringKey("push-ups") : LocalizedStringKey("push-ups to go"))
                .typography(TypographyTokens.labelDisplay)
                .foregroundStyle(.white.opacity(0.85))
            if let target = model.target {
                GradientProgressBar(value: Double(model.counted) / Double(max(target, 1)))
                    .frame(maxWidth: 240)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(model.target == nil ? "\(model.counted) push-ups" : "\(model.remaining ?? 0) push-ups to go"))
    }

    @ViewBuilder private var messages: some View {
        if let error = model.cameraError {
            InlineBanner(LocalizedStringKey(error))
        } else if model.status.multiplePeople {
            InlineBanner(LocalizedStringKey(RepText.onlyOnePerson), kind: .warning)
        } else if model.guidance != .ready {
            Pill(LocalizedStringKey(RepText.guidance(model.guidance)), color: ColorTokens.brandFlameText)
        } else if let hint = model.hint {
            InlineBanner(LocalizedStringKey(hint.showTip ? RepText.tip(hint.reason) : RepText.hint(hint.reason)), kind: .warning)
        } else if let q = model.lastQuality {
            Pill("Form \(q)", color: q >= 70 ? ColorTokens.stateSuccessText : ColorTokens.stateWarning)
        }
    }
}

/// Camera pre-permission explainer (CLAUDE.md §10, doc 16 privacy).
struct CameraExplainer: View {
    let denied: Bool
    let onAllow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.m) {
            Spacer()
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(GradientTokens.hero))
                .frame(width: 88, height: 88)
                .overlay { Image(systemName: "camera.fill").font(.system(size: 36, weight: .bold)).foregroundStyle(.white) }
                .accessibilityHidden(true)
            ScreenTitle("The camera\ncounts for you", token: TypographyTokens.displayXl)
            Text("Pushly watches your push-ups to count only real, full reps. Everything is analysed on your phone — video is never uploaded or stored.")
                .typography(TypographyTokens.body)
                .foregroundStyle(Color(ColorTokens.textSecondary))
            if denied {
                InlineBanner("Camera access is off. Allow it in Settings › Pushly to do the challenge.", kind: .warning)
            }
            Spacer()
            PrimaryButton(denied ? "Open Settings" : "Allow camera", action: onAllow)
        }
        .padding(SpacingTokens.l)
        .arenaBackground(glow: ColorTokens.brandVolt, alignment: .top, offset: CGSize(width: 0, height: -200))
    }
}

/// AVCaptureVideoPreviewLayer in SwiftUI. Front camera preview is mirrored (like a mirror) — the engine is not.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession?

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer? { layer as? AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.backgroundColor = .black
        v.previewLayer?.videoGravity = .resizeAspectFill
        v.previewLayer?.session = session
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.previewLayer?.session !== session { uiView.previewLayer?.session = session }
    }
}

/// Draws the tracked body over the preview (aspect-fill, mirrored to match the front camera preview).
struct SkeletonOverlay: View {
    let landmarks: [PoseLandmark]
    let imageSize: CGSize
    let mirrored: Bool
    let good: Bool

    static let bones: [(Int, Int)] = [(11, 12), (11, 13), (13, 15), (12, 14), (14, 16), (11, 23), (12, 24), (23, 24),
                                      (23, 25), (25, 27), (24, 26), (26, 28), (27, 31), (28, 32)]

    var body: some View {
        Canvas { context, size in
            guard landmarks.count == 33, imageSize.width > 0, imageSize.height > 0 else { return }
            let scale = max(size.width / imageSize.width, size.height / imageSize.height)
            let dx = (size.width - imageSize.width * scale) / 2
            let dy = (size.height - imageSize.height * scale) / 2
            func point(_ i: Int) -> CGPoint? {
                let l = landmarks[i]
                guard l.visibility >= 0.5 else { return nil }
                let x = mirrored ? 1 - l.x : l.x
                return CGPoint(x: dx + x * imageSize.width * scale, y: dy + l.y * imageSize.height * scale)
            }
            let color = good ? Color(ColorTokens.stateSuccess) : Color(ColorTokens.brandFlame)
            var path = Path()
            for (a, b) in Self.bones {
                guard let pa = point(a), let pb = point(b) else { continue }
                path.move(to: pa)
                path.addLine(to: pb)
            }
            context.stroke(path, with: .color(color.opacity(0.9)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            for i in [11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28] {
                guard let p = point(i) else { continue }
                context.fill(Path(ellipseIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)), with: .color(.white))
            }
        }
        .accessibilityHidden(true)
    }
}

/// How to place the phone (doc 05 §6, P3-07): side view, on the floor, whole body in frame. Shown over the live camera
/// for the first five sessions; afterwards from the "?" button.
struct PlacementGuide: View {
    static let key = "placementGuide.timesShown"
    static let autoShowCount = 5

    static func shouldShow(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.integer(forKey: key) < autoShowCount
    }

    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.m) {
            Text("Place your phone")
                .typography(TypographyTokens.titleL)
                .foregroundStyle(Color(ColorTokens.textPrimary))
            step("iphone.gen3", "On the floor, 1.5–2 m to your side — lean it against a shoe or a wall.")
            step("arrow.left.and.right", "Side view works best. Facing the phone head-on also works, a bit less precisely.")
            step("figure.strengthtraining.functional", "Your whole body in the picture — the outline turns green when it fits.")
            step("lightbulb.fill", "Good light, nobody else in the frame.")
            PrimaryButton("Got it") {
                UserDefaults.standard.set(UserDefaults.standard.integer(forKey: Self.key) + 1, forKey: Self.key)
                onDone()
            }
            Button("Don't show again") {
                UserDefaults.standard.set(Self.autoShowCount, forKey: Self.key)
                onDone()
            }
            .frame(maxWidth: .infinity, minHeight: TouchTarget.minimum)
            .foregroundStyle(Color(ColorTokens.textSecondary))
        }
        .padding(SpacingTokens.l)
        .background(Color(ColorTokens.bgElevated).opacity(0.96), in: RoundedRectangle(cornerRadius: RadiusTokens.xl, style: .continuous))
        .padding(SpacingTokens.l)
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private func step(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: SpacingTokens.m) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color(ColorTokens.brandFlameText))
                .frame(width: 32)
                .accessibilityHidden(true)
            Text(text)
                .typography(TypographyTokens.body)
                .foregroundStyle(Color(ColorTokens.textSecondary))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
