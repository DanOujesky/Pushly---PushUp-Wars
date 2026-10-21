import AlarmFeature
import Core
import Networking
import SwiftUI

@main
struct PushlyApp: App {
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate
    @State private var router: AppRouter
    @State private var session: AppSession
    @State private var alarms: AlarmEnvironment
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let router = AppRouter()
        _router = State(initialValue: router)
        let session = AppSession.live()
        _session = State(initialValue: session)
        PushRegistrar.shared.attach(session)
        if let account = session.account {
            Reporter.handler = { target, reason in
                do {
                    try await account.report(target: target.json, reason: reason)
                    return true
                } catch {
                    PLog.warning("Report failed: \(error)", .app)
                    return false
                }
            }
        }
        // Alarms work without an account and offline (CLAUDE.md §4.4), so they start before any session routing.
        _alarms = State(initialValue: AlarmEnvironment(router: router, session: session))
        #if DEBUG
        if let tab = UserDefaults.standard.string(forKey: "PushlyDebugTab").flatMap(AppTab.init(rawValue:)) {
            router.selectedTab = tab
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(session)
                .environment(alarms.model)
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
                .task {
                    #if DEBUG
                    await alarms.applyDebugScreen()
                    #endif
                    await alarms.model.refresh()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: Task { await alarms.model.refresh() }
            case .background: AlarmEnvironment.scheduleBackgroundRefresh()
            default: break
            }
        }
        .backgroundTask(.appRefresh(AlarmEnvironment.refreshTaskID)) {
            await alarms.backgroundRefresh()
        }
    }
}
