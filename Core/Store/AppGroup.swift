import Foundation
import os

/// The one surface the app and the widget extension can both see.
///
/// Trap 3, learned the hard way on the probe: a sandboxed extension's
/// `homeDirectoryForCurrentUser` resolves to its own container, not the real
/// home. So a `temporary-exception.files.home-relative-path` entitlement for
/// `~/Library/…` can never point at the app's files — it points at the
/// extension's own container and appears to work. Anything written there
/// simply never arrives. An App Group is not one option among several; it is
/// the only mechanism, and it is why the entitlement is in both targets'
/// plists and why the identifier is team-prefixed for non-App-Store shipping.
enum AppGroup {
    static let identifier = "VKN4MYB5ZW.com.devshakib.fathom"

    static let log = Logger(subsystem: "com.devshakib.fathom", category: "store")

    /// nil means the entitlement did not survive signing — which is trap 2,
    /// and which produces a widget that renders its fallbacks forever with no
    /// error anywhere. Callers surface this rather than swallowing it.
    static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static func directory(_ name: String) -> URL? {
        guard let container else { return nil }
        let url = container.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var documents: URL? { directory("Documents") }
    static var caches: URL? { directory("Caches") }

    /// A one-line description of whether the shared container is reachable,
    /// shown in the app rather than logged. If this ever says it is missing,
    /// no widget on the machine can read anything.
    static var diagnosis: String {
        guard let container else {
            return "Unavailable — the App Group entitlement is missing from this build's signature."
        }
        return container.path
    }
}
