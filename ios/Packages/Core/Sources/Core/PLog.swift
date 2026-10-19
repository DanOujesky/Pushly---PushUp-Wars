import Foundation
import os

/// The only logging entry point (CLAUDE.md §4.6 — no `print` in production paths).
/// Categories map to `os.Logger` categories so logs can be filtered in Console.app.
public enum PLog {
    public enum Category: String, Sendable, CaseIterable {
        case app, alarm, camera, pose, rep, sync, battle, clan, ads, purchases
    }

    private static let subsystem = "app.pushly"

    public static func debug(_ message: @autoclosure () -> String, _ category: Category = .app) {
        #if DEBUG
        let text = message()
        logger(category).debug("\(text, privacy: .public)")
        #endif
    }

    public static func info(_ message: @autoclosure () -> String, _ category: Category = .app) {
        let text = message()
        logger(category).info("\(text, privacy: .public)")
    }

    /// Use for user data: the message is redacted in release logs.
    public static func privateInfo(_ message: @autoclosure () -> String, _ category: Category = .app) {
        let text = message()
        logger(category).info("\(text, privacy: .private)")
    }

    public static func warning(_ message: @autoclosure () -> String, _ category: Category = .app) {
        let text = message()
        logger(category).warning("\(text, privacy: .public)")
    }

    public static func error(_ message: @autoclosure () -> String, _ category: Category = .app) {
        let text = message()
        logger(category).error("\(text, privacy: .public)")
    }

    private static func logger(_ category: Category) -> Logger {
        Logger(subsystem: subsystem, category: category.rawValue)
    }
}
