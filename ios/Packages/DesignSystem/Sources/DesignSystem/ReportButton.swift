import SwiftUI

/// "Report" with a fixed list of reasons (the server's `reports.reason` values) and a thank-you note.
/// Used on profiles, clan chat messages, clans and battle results.
public struct ReportButton: View {
    public static let reasons: [(id: String, title: LocalizedStringKey)] = [
        ("cheating", "Cheating"),
        ("harassment", "Harassment or hate"),
        ("inappropriate_video", "Inappropriate video"),
        ("inappropriate_name", "Inappropriate name"),
        ("spam", "Spam"),
        ("other", "Something else"),
    ]

    let label: LocalizedStringKey
    let onReport: (String) async -> Bool
    @State private var choosing = false
    @State private var result: Bool?

    public init(_ label: LocalizedStringKey = "Report", onReport: @escaping (String) async -> Bool) {
        self.label = label
        self.onReport = onReport
    }

    public var body: some View {
        Button(role: .destructive) { choosing = true } label: {
            Label(label, systemImage: "flag")
        }
        .confirmationDialog("What's wrong?", isPresented: $choosing, titleVisibility: .visible) {
            ForEach(Self.reasons, id: \.id) { reason in
                Button(reason.title) { Task { result = await onReport(reason.id) } }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert(result == true ? "Thanks for reporting" : "Report not sent",
               isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } })) {
            Button("OK") { result = nil }
        } message: {
            Text(result == true ? "We review every report. You can also block this person."
                                : "Please try again in a moment.")
        }
    }
}
