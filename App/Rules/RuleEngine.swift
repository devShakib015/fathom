import AppKit
import SwiftUI
import Observation
import UserNotifications

/// Watches every enabled rule and carries out what it says.
///
/// One task per rule, on the rule's own interval. Edge-triggered by default:
/// a rule fires on the transition into true, not on every check while it is
/// true. Without that, "the disk is nearly full" notifies every minute forever
/// and the first thing anybody does is turn it off.
@MainActor
@Observable
final class RuleEngine {
    private(set) var rules: [Rule] = []
    /// What each rule evaluated to on its last check, for the UI to show
    /// without running the condition a second time.
    private(set) var lastResult: [UUID: Bool] = [:]
    private(set) var lastFired: [UUID: Date] = [:]
    private(set) var notificationsAllowed = false

    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var previousState: [UUID: Bool] = [:]
    @ObservationIgnored weak var overlays: OverlayController?

    init() {
        rules = RuleStore.shared.all()
    }

    func start() {
        for rule in rules where rule.isEnabled { schedule(rule) }
    }

    // MARK: - Editing

    func add() -> Rule {
        let rule = Rule()
        rules.append(rule)
        persist()
        schedule(rule)
        return rule
    }

    func update(_ rule: Rule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index] = rule
        persist()
        tasks[rule.id]?.cancel()
        // A rule that has just been edited should not fire on the strength of
        // a state it held under the old condition.
        previousState[rule.id] = nil
        if rule.isEnabled { schedule(rule) } else { tasks[rule.id] = nil }
    }

    func remove(_ id: UUID) {
        tasks[id]?.cancel(); tasks[id] = nil
        rules.removeAll { $0.id == id }
        persist()
    }

    private func persist() { RuleStore.shared.save(rules) }

    // MARK: - Permission

    func requestNotificationPermission() async {
        let centre = UNUserNotificationCenter.current()
        notificationsAllowed = (try? await centre.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func refreshNotificationPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsAllowed = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    // MARK: - Running

    private func schedule(_ rule: Rule) {
        tasks[rule.id] = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check(rule)
                try? await Task.sleep(for: .seconds(max(rule.checkEvery, Rule.minimumInterval)))
            }
        }
    }

    /// Evaluates one rule and fires it if it should.
    @discardableResult
    func check(_ rule: Rule, dryRun: Bool = false) async -> Bool {
        let data = await resolve(rule)
        let tree = rule.sources.first.flatMap { data.trees[$0.id] }
        let result = evaluate(rule.condition, tree: tree, now: data.capturedAt)

        guard !dryRun else { return result }

        lastResult[rule.id] = result
        let was = previousState[rule.id]
        previousState[rule.id] = result

        guard FiringDecision.shouldFire(result: result,
                                        previous: was,
                                        trigger: rule.trigger,
                                        lastFired: lastFired[rule.id],
                                        cooldown: rule.cooldown)
        else { return false }

        lastFired[rule.id] = Date()
        for action in rule.actions { perform(action, rule: rule, tree: tree) }
        return true
    }

    /// A rule's sources, resolved together so one endpoint is fetched once even
    /// when several parts of the condition read from it.
    private func resolve(_ rule: Rule) async -> ResolvedData {
        var document = WidgetDoc(name: rule.name, sources: rule.sources)
        document.elements = []
        return await DataResolver.resolve(document)
    }

    func evaluate(_ condition: String, tree: DataValue?, now: Date) -> Bool {
        guard let program = try? ExpressionParser.parse(condition) else { return false }
        let value = ExpressionEvaluator(tree: tree, ownValue: nil, now: now).evaluate(program)
        switch value {
        case .bool(let b): return b
        case .number(let n): return n != 0
        case .string(let s): return !s.isEmpty
        case .null: return false
        default: return true
        }
    }

    // MARK: - Actions

    private func perform(_ action: RuleAction, rule: Rule, tree: DataValue?) {
        switch action.kind {
        case .notify:
            let content = UNMutableNotificationContent()
            content.title = TextTemplate.render(action.primary.isEmpty ? rule.name : action.primary,
                                                tree: tree)
            content.body = TextTemplate.render(action.secondary, tree: tree)
            content.sound = .default
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))

        case .showOverlay, .hideOverlay:
            guard let id = action.overlayID,
                  var overlay = overlays?.overlays.first(where: { $0.id == id }) else { return }
            overlay.isEnabled = action.kind == .showOverlay
            overlays?.update(overlay)

        case .openURL, .openApp, .revealPath, .runShortcut:
            // One runner for clicks and rules alike.
            //
            // This branch used to open any URL with a scheme, and the URL is
            // rendered from a template whose values come from whatever endpoint
            // the rule watches — so a remote response could choose the scheme.
            // ActionRunner allows http and https only, and now this obeys the
            // same rule because it is the same code.
            guard let shared = action.sharedAction(renderedWith: tree) else { return }
            ActionRunner.run(shared)

        case .playSound:
            NSSound(named: action.primary.isEmpty ? "Submarine" : action.primary)?.play()
        }
    }

    /// System sounds a rule can play, by name.
    static let soundNames = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass",
                             "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi",
                             "Submarine", "Tink"]
}
