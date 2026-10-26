import Foundation
import Observation

/// What the user is doing right now, as far as ads care (doc 13 §1, CLAUDE.md §4.5). Features set these; ShopFeature
/// reads them into an `AdsGate.Context` before every ad. Same as Android `AppActivity`.
@MainActor
public enum AppActivity {
    /// A wake flow (alarm ringing → push-ups) is in progress.
    public private(set) static var wakeActive = false
    /// When the last wake flow ended — no ads for 10 minutes after it.
    public private(set) static var lastWakeEndedAt: Date?
    /// A camera session (wake, training, workout, battle) is on screen.
    public static var cameraActive = false
    /// none | matchmaking | lobby | live | results
    public static var battlePhase = "none"

    static let sessionsKey = "ads.completedSessions"
    static let battlesKey = "ads.battlesSinceInterstitial"

    public static func wakeStarted() { wakeActive = true }

    public static func wakeEnded(at date: Date = Date()) {
        wakeActive = false
        lastWakeEndedAt = date
    }

    /// Finished camera sessions on this device — no ads until the user has done 2 (new-user grace).
    public static var completedSessions: Int { UserDefaults.standard.integer(forKey: sessionsKey) }

    public static func sessionCompleted() {
        UserDefaults.standard.set(completedSessions + 1, forKey: sessionsKey)
    }

    /// Battles since the last results interstitial (at least 2 between, D-082).
    public static var battlesSinceInterstitial: Int { UserDefaults.standard.integer(forKey: battlesKey) }

    public static func battleFinished() {
        UserDefaults.standard.set(battlesSinceInterstitial + 1, forKey: battlesKey)
    }

    public static func interstitialShown() {
        UserDefaults.standard.set(0, forKey: battlesKey)
    }
}

/// Hooks between the features and ShopFeature (ads + Pushly Pro, doc 13). The app sets the handlers at launch;
/// features only call them, so they don't link the ad / purchase SDKs. Same as Android `Monetization`.
@MainActor
public enum Monetization {
    /// The user closed a battle's result screen — the only moment a results interstitial may show.
    public static var battleClosed: () -> Void = {}
    /// Open the Pushly Pro paywall. Reason: profile | remove_ads | sound | frame | emblem.
    public static var showPaywall: (String) -> Void = { _ in }
    /// True while the user has Pushly Pro (store or server) — kept up to date by ShopFeature. Observable: views that
    /// read it redraw when Pro changes (locked Pro items, D-074).
    public static var isPro: Bool {
        get { ProState.shared.isPro }
        set { ProState.shared.isPro = newValue }
    }
}

/// Observable Pro flag behind `Monetization.isPro`.
@MainActor
@Observable
public final class ProState {
    public static let shared = ProState()
    public var isPro = false
    /// My chosen Pro frame (D-074), from my profile; shown only while Pro.
    public var frame: String?

    /// The frame to draw around my avatar right now.
    public var myFrame: String? { isPro ? frame : nil }
}
