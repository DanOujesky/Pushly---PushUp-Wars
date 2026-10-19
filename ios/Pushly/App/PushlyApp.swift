import Core
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
                .onOpenURL { url in router.handle(url: url) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { router.handle(url: url) }
                }
        }
    }
}
