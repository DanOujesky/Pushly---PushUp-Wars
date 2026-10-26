@preconcurrency import AVFoundation
import SwiftUI
import UIKit

/// In-app QR scanner (D-078): point the camera at a friend's Pushly code. Calls `onScan` once with the decoded text.
/// Uses the camera permission the app already asks for (push-up camera); denied → a hint to open Settings.
public struct QRScannerSheet: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var denied = false

    public init(onScan: @escaping (String) -> Void) {
        self.onScan = onScan
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if denied {
                    VStack(spacing: SpacingTokens.m) {
                        Image(systemName: "camera.fill").font(.system(size: 40)).foregroundStyle(.white).accessibilityHidden(true)
                        Text("Pushly needs the camera to scan a friend's code.")
                            .typography(TypographyTokens.body)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            Link("Open Settings", destination: url)
                                .typography(TypographyTokens.button)
                                .foregroundStyle(Color(ColorTokens.brandFlameText))
                        }
                    }
                    .padding(SpacingTokens.xl)
                } else {
                    QRCameraView { text in
                        onScan(text)
                        dismiss()
                    }
                    .ignoresSafeArea()
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.9), lineWidth: 4)
                        .frame(width: 250, height: 250)
                        .accessibilityHidden(true)
                    VStack {
                        Spacer()
                        Text("Point the camera at your friend's Pushly QR code")
                            .typography(TypographyTokens.bodyS)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(SpacingTokens.m)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(.bottom, SpacingTokens.xxl)
                    }
                }
            }
            .navigationTitle(Text("Scan QR code"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task {
                switch AVCaptureDevice.authorizationStatus(for: .video) {
                case .authorized: denied = false
                case .notDetermined: denied = !(await AVCaptureDevice.requestAccess(for: .video))
                default: denied = true
                }
            }
        }
    }
}

/// AVFoundation preview + QR metadata output.
struct QRCameraView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> QRCameraController {
        let c = QRCameraController()
        c.onCode = onCode
        return c
    }

    func updateUIViewController(_ controller: QRCameraController, context: Context) {}
}

/// The capture session lives on a background queue for start / stop.
private final class CaptureBox: @unchecked Sendable {
    let session = AVCaptureSession()
}

final class QRCameraController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    private let box = CaptureBox()
    private var session: AVCaptureSession { box.session }
    private var preview: AVCaptureVideoPreviewLayer?
    private var done = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        preview = layer
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let box = box
        DispatchQueue.global(qos: .userInitiated).async { box.session.startRunning() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let box = box
        DispatchQueue.global(qos: .userInitiated).async { box.session.stopRunning() }
    }

    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
                                    from connection: AVCaptureConnection) {
        let text = metadataObjects.compactMap { ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }.first
        MainActor.assumeIsolated {
            guard !done, let text else { return }
            done = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onCode?(text)
        }
    }
}
