import SwiftUI

/// The "side view only" rule (D-064, D-070), shown wherever battles, Clan Wars or training are started: only push-ups
/// filmed from the side count for battles and Clan Wars; from the front they count for the alarm and personal stats.
public struct SideViewNotice: View {
    public enum Style: Sendable {
        /// Card with the phone illustration and the full explanation (hubs).
        case card
        /// One line (inside other cards).
        case compact
    }

    let style: Style

    public init(_ style: Style = .card) { self.style = style }

    public var body: some View {
        switch style {
        case .card: card
        case .compact: compact
        }
    }

    private var card: some View {
        HStack(alignment: .center, spacing: SpacingTokens.m) {
            SideViewGlyph()
                .frame(width: 64, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                Text("Side view only")
                    .typography(TypographyTokens.overline)
                    .foregroundStyle(Color(ColorTokens.brandVoltText))
                Text("Only push-ups filmed **from the side** count for battles and Clan Wars.")
                    .typography(TypographyTokens.bodyS)
                    .foregroundStyle(Color(ColorTokens.textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
                Text("From the front they count just for your alarm and your own stats.")
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(SpacingTokens.m)
        .background(Color(ColorTokens.bgElevated), in: RoundedRectangle(cornerRadius: RadiusTokens.m, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: RadiusTokens.m, style: .continuous)
            .strokeBorder(Color(ColorTokens.brandVolt), lineWidth: 1.5))
        .accessibilityElement(children: .combine)
    }

    private var compact: some View {
        Label {
            Text("Only side-view push-ups count for battles and Clan Wars")
                .typography(TypographyTokens.caption)
                .foregroundStyle(Color(ColorTokens.brandVoltText))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "figure.strengthtraining.functional")
                .foregroundStyle(Color(ColorTokens.brandVoltText))
        }
        .accessibilityElement(children: .combine)
    }
}

/// A phone lying on the floor, filming a person in a plank from the side.
struct SideViewGlyph: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let floor = h * 0.92
            var ground = Path()
            ground.move(to: CGPoint(x: 0, y: floor))
            ground.addLine(to: CGPoint(x: w, y: floor))
            ctx.stroke(ground, with: .color(Color(ColorTokens.strokeStrong)), lineWidth: 1.5)
            // phone standing on its side at the left
            let phone = CGRect(x: 0, y: floor - h * 0.5, width: w * 0.14, height: h * 0.5)
            ctx.fill(Path(roundedRect: phone, cornerRadius: 3), with: .color(Color(ColorTokens.brandVolt)))
            // view cone
            var cone = Path()
            cone.move(to: CGPoint(x: phone.maxX, y: phone.midY))
            cone.addLine(to: CGPoint(x: w, y: floor - h * 0.72))
            cone.addLine(to: CGPoint(x: w, y: floor))
            cone.closeSubpath()
            ctx.fill(cone, with: .color(Color(ColorTokens.brandVolt).opacity(0.18)))
            // person in a plank, seen from the side
            let head = CGRect(x: w * 0.36, y: floor - h * 0.56, width: h * 0.16, height: h * 0.16)
            ctx.fill(Path(ellipseIn: head), with: .color(Color(ColorTokens.textPrimary)))
            var body = Path()
            body.move(to: CGPoint(x: head.maxX, y: head.midY + h * 0.04))
            body.addLine(to: CGPoint(x: w * 0.96, y: floor - h * 0.06))
            var arm = Path()
            arm.move(to: CGPoint(x: head.maxX + w * 0.03, y: head.midY + h * 0.07))
            arm.addLine(to: CGPoint(x: head.maxX + w * 0.03, y: floor))
            ctx.stroke(body, with: .color(Color(ColorTokens.textPrimary)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            ctx.stroke(arm, with: .color(Color(ColorTokens.textPrimary)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
    }
}
