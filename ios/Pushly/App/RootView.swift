import DesignSystem
import SwiftUI

struct RootView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            Tab("Wake", systemImage: "alarm.fill", value: AppTab.wake) {
                PlaceholderScreen(title: "Wake", subtitle: "Your next alarm and streak live here.")
            }
            Tab("Battle", systemImage: "figure.strengthtraining.traditional", value: AppTab.battle) {
                PlaceholderScreen(title: "Battle", subtitle: "Live push-up battles arrive in Phase 7.")
            }
            Tab("Clan", systemImage: "shield.lefthalf.filled", value: AppTab.clan) {
                PlaceholderScreen(title: "Clan", subtitle: "Clans and Clan Wars arrive in Phase 8.")
            }
            Tab("Ranks", systemImage: "trophy.fill", value: AppTab.ranks) {
                PlaceholderScreen(title: "Ranks", subtitle: "Leaderboards arrive in Phase 6.")
            }
            Tab("Profile", systemImage: "person.crop.circle.fill", value: AppTab.profile) {
                PlaceholderScreen(title: "Profile", subtitle: "Stats and settings arrive in Phases 1 and 5.")
            }
        }
        .tint(Color(ColorTokens.brandFlame))
    }
}

#Preview {
    RootView().environment(AppRouter())
}
