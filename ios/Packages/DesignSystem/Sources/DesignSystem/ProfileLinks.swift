import SwiftUI

// Tap any player or clan → their page (D-080). Features don't know each other (doc 03 §3), so the app injects the
// destinations through the environment and every list wraps a row in `ProfileLink`. The page opens in a sheet (works
// from inside other sheets) with its own navigation stack, and pages inside it can link on (player → clan → player…).

/// Who to open: a player (by id or username) or a clan.
public enum ProfileTarget: Hashable, Sendable, Identifiable {
    case user(id: String)
    case username(String)
    case clan(id: String)

    public var id: String {
        switch self {
        case let .user(id): "u:\(id)"
        case let .username(name): "n:\(name)"
        case let .clan(id): "c:\(id)"
        }
    }
}

/// The pages, provided by the app.
public struct ProfileLinks: Sendable {
    public let page: @MainActor @Sendable (ProfileTarget) -> AnyView

    public init(page: @escaping @MainActor @Sendable (ProfileTarget) -> AnyView) {
        self.page = page
    }
}

extension EnvironmentValues {
    @Entry public var profileLinks: ProfileLinks?
}

/// Wraps a row: tapping it opens the player's / clan's page. Without injected pages it is just the label.
public struct ProfileLink<Label: View>: View {
    let target: ProfileTarget?
    let label: Label
    @Environment(\.profileLinks) private var links
    @State private var shown: ProfileTarget?

    public init(_ target: ProfileTarget?, @ViewBuilder label: () -> Label) {
        self.target = target
        self.label = label()
    }

    public var body: some View {
        if let links, let target {
            Button { shown = target } label: { label.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityHint(Text(hint(target)))
                .sheet(item: $shown) { t in ProfilePageSheet(target: t, links: links) }
        } else {
            label
        }
    }

    private func hint(_ t: ProfileTarget) -> String {
        if case .clan = t { return String(localized: "Opens the clan's page") }
        return String(localized: "Opens the profile")
    }
}

/// A page in its own navigation stack with Done; links inside it keep working.
public struct ProfilePageSheet: View {
    let target: ProfileTarget
    let links: ProfileLinks
    @Environment(\.dismiss) private var dismiss

    public init(target: ProfileTarget, links: ProfileLinks) {
        self.target = target
        self.links = links
    }

    public var body: some View {
        NavigationStack {
            links.page(target)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .environment(\.profileLinks, links)
        .presentationDragIndicator(.visible)
    }
}
