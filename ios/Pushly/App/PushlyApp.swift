import Core
import Networking
import SwiftUI

@main
struct PushlyApp: App {
    @State private var router = AppRouter()
    @State private var session = AppSession.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(session)
                .onOpenURL { url in
                    if AuthCallback.matches(url) {
                        Task { await session.handleAuthCallback(url) }
                    } else {
                        router.handle(url: url)
                    }
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { router.handle(url: url) }
                }
        }
    }
}
