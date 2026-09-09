import Foundation

/// What happens when someone clicks an element.
///
/// Only on surfaces Fathom owns. A WidgetKit widget cannot do this — the
/// framework's answer is App Intents, and §6 trap 7 records that
/// `AppIntentConfiguration` never ran a single timeline in this project. So
/// actions are inert in the extension by construction rather than by
/// permission, and the editor says which surfaces will honour them.
///
/// **The vocabulary is closed on purpose, and shell commands are not in it.**
/// A Fathom document is designed to be shared, and a format that could carry
/// "run this command" would be a format for mailing people malware. Every
/// action here is one macOS already lets any application ask for, each is
/// disclosed by name before a shared document is installed, and none of them
/// can do anything the person could not do themselves from the Dock.
struct Action: Codable, Hashable {
    var kind: Kind
    /// A URL, an application name, a file path or a shortcut name, depending on
    /// `kind`. One field rather than four, because a document with four empty
    /// strings in every element is a document nobody wants to read.
    var value: String

    init(kind: Kind = .none, value: String = "") {
        self.kind = kind
        self.value = value
    }

    enum Kind: String, Codable, CaseIterable, Hashable {
        case none
        /// Opens a link in the default browser.
        case openURL
        /// Launches or activates an application by name.
        case openApp
        /// Reveals a file or folder in Finder.
        case revealPath
        /// Runs a shortcut by name, through the `shortcuts://` scheme. Nothing
        /// is executed by Fathom; the request is handed to the Shortcuts app,
        /// which is the only thing that decides whether to run it.
        case runShortcut
        /// Re-reads this design's sources immediately, ignoring the interval.
        case refresh

        var displayName: String {
            switch self {
            case .none: "Nothing"
            case .openURL: "Open a link"
            case .openApp: "Open an app"
            case .revealPath: "Show in Finder"
            case .runShortcut: "Run a shortcut"
            case .refresh: "Refresh now"
            }
        }

        var symbol: String {
            switch self {
            case .none: "hand.raised.slash"
            case .openURL: "link"
            case .openApp: "app"
            case .revealPath: "folder"
            case .runShortcut: "square.stack.3d.up"
            case .refresh: "arrow.clockwise"
            }
        }

        /// What the value field is asking for.
        var placeholder: String {
            switch self {
            case .none, .refresh: ""
            case .openURL: "https://example.com"
            case .openApp: "Calendar"
            case .revealPath: "~/Documents"
            case .runShortcut: "Start my day"
            }
        }

        var needsValue: Bool { self != .none && self != .refresh }
    }

    var isSet: Bool { kind != .none && (!kind.needsValue || !value.isEmpty) }

    /// One line describing this action to somebody who has not opened the
    /// document. Used by the sharing sheet, which has to be able to answer
    /// "what will this do if I click it?" before anything is installed.
    var disclosure: String? {
        guard isSet else { return nil }
        switch kind {
        case .none: return nil
        case .refresh: return "Refresh the widget"
        case .openURL: return "Open \(value)"
        case .openApp: return "Open the app \(value)"
        case .revealPath: return "Show \(value) in Finder"
        case .runShortcut: return "Run the shortcut “\(value)”"
        }
    }
}
