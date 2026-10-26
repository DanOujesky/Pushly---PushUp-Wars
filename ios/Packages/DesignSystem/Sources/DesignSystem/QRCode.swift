import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// Profile link QR code (D-072; shared by Battle and Profile → Friends since D-077).
/// My profile link as a big QR code on white (best for other cameras).
public struct QRCodeSheet: View {
    let url: URL
    let username: String

    public init(url: URL, username: String) {
        self.url = url
        self.username = username
    }

    public var body: some View {
        VStack(spacing: SpacingTokens.l) {
            Text("Scan to add me").typography(TypographyTokens.titleL).foregroundStyle(Color(ColorTokens.textPrimary))
            if let image = QRCode.image(for: url.absoluteString) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 260)
                    .padding(SpacingTokens.m)
                    .background(.white, in: RoundedRectangle(cornerRadius: RadiusTokens.m))
                    .accessibilityLabel(Text("QR code for \(username)"))
            }
            Text(verbatim: "@\(username)").typography(TypographyTokens.titleM).foregroundStyle(Color(ColorTokens.brandFlameText))
            Text("Your friend opens the phone camera, points it at the code and taps Add on your profile.")
                .typography(TypographyTokens.bodyS)
                .foregroundStyle(Color(ColorTokens.textSecondary))
                .multilineTextAlignment(.center)
        }
        .padding(SpacingTokens.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(ColorTokens.bgBase).ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }
}

public enum QRCode {
    /// Black-on-white QR code (CoreImage, medium error correction).
    public static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

