import DesignSystem
import SwiftUI
import UserNotifications

/// Pre-permission explainer (P2-10, CLAUDE.md §10): shown after the first alarm is saved — never at launch — and from
/// the health banner. Explains why, then asks iOS. If alarms were denied earlier, it leads to Settings instead.
struct AlarmPermissionView: View {
    let model: WakeModel
    let onOpenSettings: () -> Void
    let onDone: () -> Void
    @State private var notificationsAllowed: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.m) {
            ScrollView {
                VStack(alignment: .leading, spacing: SpacingTokens.m) {
                    ScreenTitle("Make sure\nit rings", token: TypographyTokens.displayXl)
                    Text("Pushly uses iOS alarms, so your wake-up rings even in Silent mode and Focus — like the Clock app.")
                        .typography(TypographyTokens.body)
                        .foregroundStyle(Color(ColorTokens.textSecondary))
                    step(title: "Alarms", text: "Lets Pushly ring at the exact minute and show on the Lock Screen.",
                         granted: model.authorization == .authorized) {
                        Task {
                            if model.authorization == .denied {
                                onOpenSettings()
                            } else {
                                _ = await model.requestAuthorization()
                            }
                        }
                    }
                    step(title: "Notifications (optional)", text: "An evening reminder if something would stop your alarm.",
                         granted: notificationsAllowed == true) {
                        Task {
                            let ok = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                            notificationsAllowed = ok ?? false
                        }
                    }
                    if model.authorization == .denied {
                        InlineBanner("Alarms are turned off for Pushly. Open Settings › Pushly and allow Alarms.", kind: .warning)
                    } else if model.authorization != .authorized {
                        InlineBanner("Without this, your alarm can't ring. We'll keep reminding you on the Wake tab.", kind: .warning)
                    }
                }
                .padding(.top, SpacingTokens.xl)
            }
            PrimaryButton("Continue", action: onDone)
                .disabled(model.authorization != .authorized)
            if model.authorization != .authorized {
                GhostButton("Not now", action: onDone).frame(maxWidth: .infinity)
            }
        }
        .padding(SpacingTokens.l)
        .arenaBackground(glow: ColorTokens.brandVolt, alignment: .top, offset: CGSize(width: 0, height: -200))
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationsAllowed = settings.authorizationStatus == .authorized
        }
    }

    private func step(title: LocalizedStringKey, text: LocalizedStringKey, granted: Bool, action: @escaping () -> Void) -> some View {
        Card(padding: SpacingTokens.m) {
            HStack(spacing: SpacingTokens.sm) {
                VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                    Text(title).typography(TypographyTokens.titleS).foregroundStyle(Color(ColorTokens.textPrimary))
                    Text(text).typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.textSecondary))
                }
                Spacer(minLength: SpacingTokens.s)
                if granted {
                    Pill("Allowed", color: ColorTokens.stateSuccessText)
                } else {
                    Button(action: action) {
                        Text("Allow")
                            .typography(TypographyTokens.button)
                            .foregroundStyle(Color(ColorTokens.textPrimary))
                            .padding(.horizontal, SpacingTokens.m)
                            .frame(minHeight: TouchTarget.minimum + 4)
                            .background(Color(ColorTokens.bgElevated), in: RoundedRectangle(cornerRadius: RadiusTokens.m))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
