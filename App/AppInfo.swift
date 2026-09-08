import Foundation

/// Product and author metadata, in one place.
///
/// Mirrors Helm's `AppInfo`: nothing about the author or the promise is
/// hardcoded in a view. The free pledge in particular is product metadata
/// rather than marketing copy — it is a commitment the app states about itself,
/// and it should read identically everywhere it appears.
enum AppInfo {
    static let name = "Fathom"
    static let tagline = "Build your own Mac widgets. Design one, bind it to live data, "
                       + "mount it on the desktop."

    /// The standing promise, worded as Helm words it.
    static let freePledge = "Free forever — every feature, no paid tier, no accounts, no telemetry."

    static let license = "MIT License"
    static let copyright = "© 2026 K M Shahriar Hossain"

    static let author = "K M Shahriar Hossain"
    static let authorHandle = "devShakib"
    static let authorRole = "CTO at Shpper"

    static let portfolio = "https://devshakib.jumyn.com"
    static let repo = "https://github.com/devShakib015/fathom"
    static let releases = "https://github.com/devShakib015/fathom/releases/latest"
    static let issues = "https://github.com/devShakib015/fathom/issues/new"

    static let authorLinks: [(label: String, url: String)] = [
        ("Portfolio", portfolio),
        ("GitHub", "https://github.com/devShakib015"),
        ("X", "https://x.com/devshakib015"),
        ("dev.to", "https://dev.to/devshakib"),
    ]

    /// Read from the bundle rather than restated here, so it cannot disagree
    /// with what was actually built.
    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return short ?? "—"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    static var systemRequirement: String { "macOS 26 Tahoe or later" }
}
