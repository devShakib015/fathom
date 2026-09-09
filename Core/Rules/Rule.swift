import Foundation

/// Something Fathom watches for, and what it does about it.
///
/// The condition is the same expression language that decides whether an
/// element draws. Pointing it at an action instead of a visibility flag is what
/// turns a thing that shows you data into a thing that tells you about it, and
/// it cost almost nothing because the evaluator, the sources and the field
/// browser already existed.
struct Rule: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var isEnabled: Bool
    /// What the condition is evaluated against. A rule carries its own sources
    /// rather than borrowing a document's, so it can watch something no widget
    /// displays.
    var sources: [DataSource]
    var condition: String
    var actions: [RuleAction]
    /// How often to look. Not the widget floor — nothing here goes through
    /// WidgetKit — but not free either: every check may fetch an endpoint.
    var checkEvery: TimeInterval
    var trigger: Trigger
    /// Silence after firing. A condition hovering on its threshold would
    /// otherwise fire on every single check, which is how a useful alert
    /// becomes one you turn off.
    var cooldown: TimeInterval

    /// Loaded rules, with any hand-rolled shortcut URLs turned into real
    /// shortcut actions.
    var migrated: Rule {
        var copy = self
        copy.actions = actions.map(\.migrated)
        return copy
    }

    static let minimumInterval: TimeInterval = 5
    static let defaultInterval: TimeInterval = 60
    static let defaultCooldown: TimeInterval = 600

    enum Trigger: String, Codable, CaseIterable, Hashable {
        /// Fires on the transition from false to true, once.
        case becomesTrue
        /// Fires on every check while true, subject to the cooldown.
        case whileTrue

        var displayName: String {
            switch self {
            case .becomesTrue: "When it becomes true"
            case .whileTrue: "While it stays true"
            }
        }

        var explanation: String {
            switch self {
            case .becomesTrue: "Once, on the change. The usual choice."
            case .whileTrue: "Again on every check, until the cooldown says otherwise."
            }
        }
    }

    init(name: String = "New rule") {
        self.id = UUID()
        self.name = name
        self.isEnabled = true
        self.sources = [DataSource.system()]
        self.condition = "disk.usedFraction > 0.9"
        self.actions = [.notify(title: "Running low on space",
                                body: "Only {bytes(disk.free)} left.")]
        self.checkEvery = Rule.defaultInterval
        self.trigger = .becomesTrue
        self.cooldown = Rule.defaultCooldown
    }

    enum CodingKeys: String, CodingKey {
        case id, name, isEnabled, sources, condition, actions, checkEvery, trigger, cooldown
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        sources = try c.decodeIfPresent([DataSource].self, forKey: .sources) ?? [DataSource.system()]
        condition = try c.decode(String.self, forKey: .condition)
        actions = try c.decodeIfPresent([RuleAction].self, forKey: .actions) ?? []
        checkEvery = max(try c.decodeIfPresent(TimeInterval.self, forKey: .checkEvery)
                         ?? Rule.defaultInterval, Rule.minimumInterval)
        trigger = try c.decodeIfPresent(Trigger.self, forKey: .trigger) ?? .becomesTrue
        cooldown = try c.decodeIfPresent(TimeInterval.self, forKey: .cooldown) ?? Rule.defaultCooldown
    }

    var declaredHosts: [String] {
        Array(Set(sources.compactMap(\.host))).sorted()
    }
}

/// What a rule does when it fires.
///
/// A struct with a `kind` discriminator rather than an enum with associated
/// values, so the JSON stays flat and legible and changing an action's type in
/// the editor does not throw away the text you had typed into it.
struct RuleAction: Codable, Hashable, Identifiable {
    var id: UUID
    var kind: Kind
    /// Notification title, or the URL, or the sound name.
    var primary: String
    /// Notification body. Both it and the title accept `{expression}`, so an
    /// alert can carry the number that caused it.
    var secondary: String
    /// The overlay to show or hide.
    var overlayID: UUID?

    /// Rules written before `runShortcut` existed did it by hand, with a
    /// `shortcuts://run-shortcut?name=…` URL — the placeholder in the editor
    /// said so. Restricting links to http and https would silently stop those
    /// working, so they become the real thing instead.
    var migrated: RuleAction {
        let prefix = "shortcuts://run-shortcut?name="
        guard kind == .openURL, primary.hasPrefix(prefix) else { return self }
        let encoded = String(primary.dropFirst(prefix.count))
        var copy = self
        copy.kind = .runShortcut
        copy.primary = encoded.removingPercentEncoding ?? encoded
        return copy
    }

    /// The click action this rule action is, when it is one of the shared
    /// kinds. Rendered through the template first, so a rule can open a link
    /// carrying the value that triggered it.
    func sharedAction(renderedWith tree: DataValue?) -> Action? {
        let value = TextTemplate.render(primary, tree: tree)
            .trimmingCharacters(in: .whitespaces)
        switch kind {
        case .openURL: return Action(kind: .openURL, value: value)
        case .openApp: return Action(kind: .openApp, value: value)
        case .revealPath: return Action(kind: .revealPath, value: value)
        case .runShortcut: return Action(kind: .runShortcut, value: value)
        case .notify, .showOverlay, .hideOverlay, .playSound: return nil
        }
    }

    enum Kind: String, Codable, CaseIterable, Hashable {
        case notify
        case showOverlay
        case hideOverlay
        case openURL
        case playSound
        // Parity with what a click can do. Two vocabularies for "what happens"
        // is a fork that only widens, and there was already a gap: a rule could
        // open a link but not an app, while a click could do both.
        case openApp
        case revealPath
        case runShortcut

        var displayName: String {
            switch self {
            case .notify: "Send a notification"
            case .showOverlay: "Put an overlay on screen"
            case .hideOverlay: "Take an overlay off screen"
            case .openURL: "Open a link"
            case .playSound: "Play a sound"
            case .openApp: "Open an app"
            case .revealPath: "Show in Finder"
            case .runShortcut: "Run a shortcut"
            }
        }

        var symbol: String {
            switch self {
            case .notify: "bell"
            case .showOverlay: "rectangle.on.rectangle"
            case .hideOverlay: "rectangle.slash"
            case .openURL: "link"
            case .playSound: "speaker.wave.2"
            case .openApp: "app"
            case .revealPath: "folder"
            case .runShortcut: "square.stack.3d.up"
            }
        }
    }

    init(id: UUID = UUID(), kind: Kind, primary: String = "", secondary: String = "",
         overlayID: UUID? = nil) {
        self.id = id
        self.kind = kind
        self.primary = primary
        self.secondary = secondary
        self.overlayID = overlayID
    }

    static func notify(title: String, body: String) -> RuleAction {
        RuleAction(kind: .notify, primary: title, secondary: body)
    }
}

struct RuleStore {
    static let shared = RuleStore()

    private var url: URL? { SharedStore.container?.appendingPathComponent("rules.json") }

    func all() -> [Rule] {
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        return ((try? JSONDecoder().decode([Rule].self, from: data)) ?? []).map(\.migrated)
    }

    func save(_ rules: [Rule]) {
        guard let url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(rules).write(to: url, options: .atomic)
    }
}

/// Whether a rule that evaluated true should actually fire.
///
/// Pulled out of the engine so it can be tested without a clock, a network or a
/// notification centre. This is the logic that decides whether an alert is
/// useful or unbearable, and it is three lines of conditions that are very easy
/// to get subtly wrong.
enum FiringDecision {

    static func shouldFire(result: Bool,
                           previous: Bool?,
                           trigger: Rule.Trigger,
                           lastFired: Date?,
                           cooldown: TimeInterval,
                           now: Date = Date()) -> Bool {
        guard result else { return false }

        // `becomesTrue` fires on the change. A first check with no previous
        // state counts as a change: the condition holds and nobody has been
        // told, which is exactly when an alert is worth sending.
        if trigger == .becomesTrue, previous == true { return false }

        if let lastFired, now.timeIntervalSince(lastFired) < cooldown { return false }
        return true
    }
}
