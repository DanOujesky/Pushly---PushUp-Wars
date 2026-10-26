import Core
import DesignSystem
import Foundation
import RevenueCat
import SwiftUI
import UIKit

/// One plan on the paywall (from the RevenueCat "current" offering).
public struct PaywallPlan: Identifiable, Equatable {
    public enum Kind: String, Sendable { case monthly, annual, lifetime, other }
    public let id: String
    public let kind: Kind
    public let price: String
    /// "7-day free trial" etc. when the store offers one to this user.
    public let trialDays: Int?
    let package: Package?

    public static func == (a: PaywallPlan, b: PaywallPlan) -> Bool { a.id == b.id && a.price == b.price }
}

/// Pushly Pro + ads in one place (doc 13, D-073). Pro status = active RevenueCat entitlement `pro` (instant, on this
/// device) OR `profiles.is_pro` from the server (the webhook — authoritative for server perks). The app creates one
/// `Shop`, calls `install()` at launch and `identify` once the profile is known.
@MainActor
@Observable
public final class Shop {
    public let config: ShopConfig
    public let ads: AdsManager
    public private(set) var storePro = false
    public private(set) var serverPro = false
    public var isPro: Bool { storePro || serverPro }
    public private(set) var plans: [PaywallPlan] = []
    public private(set) var loadingPlans = false
    public private(set) var busy = false
    /// Last result shown on the paywall ("Welcome to Pro!", errors).
    public var message: String?
    /// Why the paywall is open: profile | remove_ads | sound | frame | emblem (nil = closed).
    public private(set) var paywallReason: String?
    @ObservationIgnored private weak var paywallHost: UIViewController?
    /// Me, for the paywall hero and the frame picker previews.
    public var me: Me?
    /// Saves my frame on the server (`set_profile_frame`, D-074) — set by the app.
    @ObservationIgnored public var saveFrame: (@Sendable (String?) async throws -> Void)?

    public struct Me: Equatable, Sendable {
        public let username: String
        public let avatarPreset: String?

        public init(username: String, avatarPreset: String?) {
            self.username = username
            self.avatarPreset = avatarPreset
        }
    }
    @ObservationIgnored private var userId: String?
    @ObservationIgnored private var listening = false

    public init(config: ShopConfig = .main) {
        self.config = config
        self.ads = AdsManager(config: config)
    }

    /// Plugs the hooks in: paywall requests, the battle-results interstitial and banner slots.
    public func install() {
        Monetization.showPaywall = { [weak self] reason in self?.presentPaywall(reason) }
        Monetization.battleClosed = { [weak self] in self?.ads.battleClosed() }
        AdSlots.provider = { [weak self] placement in
            guard let self else { return nil }
            return AnyView(BannerAdSlotView(placement: placement, ads: self.ads, shop: self))
        }
    }

    public var purchasesAvailable: Bool { config.purchasesAvailable }

    /// Signed-in user (Supabase id = RevenueCat app user id, so the webhook can match purchases) + server Pro flag.
    public func identify(userId: String?, serverPro: Bool) async {
        self.serverPro = serverPro
        publish()
        guard config.purchasesAvailable, let userId else { return }
        if !Purchases.isConfigured {
            Purchases.logLevel = .warn
            Purchases.configure(withAPIKey: config.revenueCatKey, appUserID: userId)
        } else if self.userId != userId {
            _ = try? await Purchases.shared.logIn(userId)
        }
        self.userId = userId
        if let info = try? await Purchases.shared.customerInfo() { apply(info) }
        listen()
    }

    private func listen() {
        guard !listening else { return }
        listening = true
        Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                self?.apply(info)
            }
        }
    }

    private func apply(_ info: CustomerInfo) {
        storePro = info.entitlements["pro"]?.isActive == true
        publish()
    }

    private func publish() { Monetization.isPro = isPro }

    // MARK: paywall

    /// Presents the paywall over whatever is on screen — also from inside a sheet (the alarm editor, the clan
    /// settings), where a root-level SwiftUI sheet could not appear.
    func presentPaywall(_ reason: String) {
        guard paywallHost == nil, let top = Self.topViewController() else { return }
        paywallReason = reason
        message = nil
        let host = UIHostingController(rootView: PaywallView(shop: self) { [weak self] in self?.closePaywall() })
        host.overrideUserInterfaceStyle = .dark
        host.modalPresentationStyle = .pageSheet
        host.presentationController?.delegate = PaywallDismissWatcher.shared
        PaywallDismissWatcher.shared.onDismiss = { [weak self] in self?.paywallReason = nil }
        paywallHost = host
        top.present(host, animated: true)
    }

    public func closePaywall() {
        paywallReason = nil
        paywallHost?.dismiss(animated: true)
        paywallHost = nil
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let next = top?.presentedViewController, !next.isBeingDismissed { top = next }
        return top
    }

    public func loadPlans() async {
        guard config.purchasesAvailable, Purchases.isConfigured else { return }
        loadingPlans = true
        defer { loadingPlans = false }
        do {
            let offerings = try await Purchases.shared.offerings()
            plans = (offerings.current?.availablePackages ?? []).map(Self.plan)
                .sorted { Self.order($0.kind) < Self.order($1.kind) }
        } catch {
            PLog.warning("Offerings failed: \(error)", .purchases)
            message = String(localized: "Couldn't load the plans. Check your connection and try again.")
        }
    }

    static func order(_ kind: PaywallPlan.Kind) -> Int {
        switch kind {
        case .annual: 0
        case .monthly: 1
        case .lifetime: 2
        case .other: 3
        }
    }

    private static func plan(_ p: Package) -> PaywallPlan {
        let kind: PaywallPlan.Kind = switch p.packageType {
        case .monthly: .monthly
        case .annual: .annual
        case .lifetime: .lifetime
        default: .other
        }
        var trial: Int?
        if let intro = p.storeProduct.introductoryDiscount, intro.paymentMode == .freeTrial {
            let period = intro.subscriptionPeriod
            trial = switch period.unit {
            case .day: period.value
            case .week: period.value * 7
            case .month: period.value * 30
            case .year: period.value * 365
            }
        }
        return PaywallPlan(id: p.identifier, kind: kind, price: p.storeProduct.localizedPriceString, trialDays: trial, package: p)
    }

    public func purchase(_ plan: PaywallPlan) async -> Bool {
        guard let package = plan.package else { return false }
        busy = true
        defer { busy = false }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled { return false }
            apply(result.customerInfo)
            message = isPro ? String(localized: "Welcome to Pushly Pro! 🎉") : nil
            return isPro
        } catch {
            PLog.warning("Purchase failed: \(error)", .purchases)
            message = String(localized: "The purchase didn't go through. You weren't charged.")
            return false
        }
    }

    /// Pick a Pro frame (nil = none). Pro only; the server checks it too.
    @discardableResult
    public func setFrame(_ id: String?) async -> Bool {
        guard id == nil || isPro, let saveFrame else { return false }
        busy = true
        defer { busy = false }
        do {
            try await saveFrame(id)
            ProState.shared.frame = id
            return true
        } catch {
            PLog.warning("Frame not saved: \(error)", .purchases)
            return false
        }
    }

    public func restore() async {
        guard config.purchasesAvailable, Purchases.isConfigured else { return }
        busy = true
        defer { busy = false }
        do {
            apply(try await Purchases.shared.restorePurchases())
            message = isPro ? String(localized: "Pushly Pro restored.") : String(localized: "No Pushly Pro purchase found for this Apple ID.")
        } catch {
            message = String(localized: "Couldn't restore purchases. Please try again.")
        }
    }
}

/// Clears the paywall state when the user swipes the sheet away.
@MainActor
final class PaywallDismissWatcher: NSObject, UIAdaptivePresentationControllerDelegate {
    static let shared = PaywallDismissWatcher()
    var onDismiss: () -> Void = {}

    nonisolated func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        MainActor.assumeIsolated { onDismiss() }
    }
}
