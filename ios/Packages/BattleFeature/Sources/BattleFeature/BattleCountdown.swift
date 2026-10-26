import DesignSystem
import SwiftUI
import UIKit

/// Before a battle (D-081): the server starts it 8 s after both phones are ready. The first seconds say GET READY
/// (who you fight, get into position, side view), then a big 5-4-3-2-1 with a ring, a beep and a tap each second,
/// then GO. Same as Android `BattleCountdown`.
public enum BattleCountdown {
    /// The last seconds that are counted out loud and big.
    public static let counted = 5

    public enum Stage: Equatable {
        case getReady
        case count(Int)
    }

    public static func stage(secondsLeft: Int) -> Stage {
        secondsLeft > counted ? .getReady : .count(max(1, secondsLeft))
    }
}

struct BattleCountdownOverlay: View {
    let secondsLeft: Int
    let opponent: String
    let opponentAvatar: String?
    let mode: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            switch BattleCountdown.stage(secondsLeft: secondsLeft) {
            case .getReady: getReady
            case let .count(n): count(n)
            }
        }
        .allowsHitTesting(false)
        .sensoryFeedback(.impact(weight: .heavy), trigger: secondsLeft)
        .accessibilityElement(children: .combine)
    }

    private var getReady: some View {
        VStack(spacing: SpacingTokens.l) {
            Text("GET READY")
                .typography(TypographyTokens.displayL)
                .foregroundStyle(LinearGradient(GradientTokens.hero))
            HStack(spacing: SpacingTokens.l) {
                VStack(spacing: SpacingTokens.xs) {
                    Image(systemName: "figure.strengthtraining.functional").font(.system(size: 40))
                        .foregroundStyle(Color(ColorTokens.brandFlameText))
                        .frame(width: 72, height: 72)
                        .background(Color(ColorTokens.brandFlame).opacity(0.18), in: Circle())
                    Text("You").typography(TypographyTokens.titleS).foregroundStyle(.white)
                }
                Text(verbatim: "VS").typography(TypographyTokens.displayM).foregroundStyle(.white.opacity(0.8))
                VStack(spacing: SpacingTokens.xs) {
                    AvatarView(username: opponent, presetID: opponentAvatar, size: 72)
                    Text(verbatim: opponent).typography(TypographyTokens.titleS).foregroundStyle(.white).lineLimit(1)
                }
            }
            Text(verbatim: modeTitle(mode)).typography(TypographyTokens.labelDisplay).foregroundStyle(.white.opacity(0.8))
            VStack(spacing: SpacingTokens.xs) {
                Label("Get into the plank position", systemImage: "arrow.down.to.line")
                Label("Side-on to the camera, whole body in view", systemImage: "camera.viewfinder")
            }
            .typography(TypographyTokens.bodyS)
            .foregroundStyle(.white.opacity(0.9))
            .padding(SpacingTokens.m)
            .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: RadiusTokens.m, style: .continuous))
            Text("Starts in \(secondsLeft) s").typography(TypographyTokens.caption).foregroundStyle(.white.opacity(0.7))
        }
        .padding(SpacingTokens.l)
        .multilineTextAlignment(.center)
    }

    private func count(_ n: Int) -> some View {
        VStack(spacing: SpacingTokens.m) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.15), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: CGFloat(n) / CGFloat(BattleCountdown.counted))
                    .stroke(LinearGradient(GradientTokens.hero), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.9), value: n)
                Text(verbatim: "\(n)")
                    .font(.system(size: 140, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: Color(ColorTokens.brandFlame).opacity(0.8), radius: 24)
                    .id(n)
                    .transition(reduceMotion ? .opacity : .scale(scale: 1.8).combined(with: .opacity))
            }
            .frame(width: 230, height: 230)
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.6), value: n)
            Text(n <= 2 ? "Arms ready…" : "Get into position")
                .typography(TypographyTokens.titleM)
                .foregroundStyle(.white.opacity(0.9))
        }
        .accessibilityLabel(Text("Battle starts in \(n)"))
    }
}
