import Testing
import Foundation

/// Whether a rule fires — the logic that decides between a useful alert and an
/// unbearable one.
@Suite("Rules")
struct RuleTests {

    let now = Date(timeIntervalSince1970: 100_000)

    @Test("a false condition never fires, whatever else is true")
    func falseNeverFires() {
        for trigger in Rule.Trigger.allCases {
            #expect(!FiringDecision.shouldFire(result: false, previous: false, trigger: trigger,
                                               lastFired: nil, cooldown: 0, now: now))
            #expect(!FiringDecision.shouldFire(result: false, previous: true, trigger: trigger,
                                               lastFired: nil, cooldown: 0, now: now))
        }
    }

    @Test("becomesTrue fires on the change and then stays quiet")
    func edgeTriggered() {
        #expect(FiringDecision.shouldFire(result: true, previous: false, trigger: .becomesTrue,
                                          lastFired: nil, cooldown: 0, now: now))
        // Still true on the next check is not news.
        #expect(!FiringDecision.shouldFire(result: true, previous: true, trigger: .becomesTrue,
                                           lastFired: nil, cooldown: 0, now: now))
    }

    @Test("a first check with no history counts as a change")
    func firstCheck() {
        // After a restart there is no previous state. The condition holds and
        // nobody has been told, which is exactly when an alert is worth having.
        #expect(FiringDecision.shouldFire(result: true, previous: nil, trigger: .becomesTrue,
                                          lastFired: nil, cooldown: 0, now: now))
    }

    @Test("whileTrue keeps firing, unlike becomesTrue")
    func levelTriggered() {
        #expect(FiringDecision.shouldFire(result: true, previous: true, trigger: .whileTrue,
                                          lastFired: nil, cooldown: 0, now: now))
    }

    @Test("the cooldown silences a condition sitting on its threshold")
    func cooldown() {
        let recent = now.addingTimeInterval(-60)
        #expect(!FiringDecision.shouldFire(result: true, previous: false, trigger: .becomesTrue,
                                           lastFired: recent, cooldown: 600, now: now))
        let old = now.addingTimeInterval(-900)
        #expect(FiringDecision.shouldFire(result: true, previous: false, trigger: .becomesTrue,
                                          lastFired: old, cooldown: 600, now: now))
    }

    @Test("a check interval below the minimum is refused on decode")
    func intervalFloor() throws {
        let json = """
            [{"id":"11111111-0000-4000-A000-000000000001","name":"r","condition":"true",
              "checkEvery":0.1}]
            """.data(using: .utf8)!
        let rules = try JSONDecoder().decode([Rule].self, from: json)
        // A rule checking ten times a second would fetch an endpoint ten times
        // a second.
        #expect(rules[0].checkEvery >= Rule.minimumInterval)
    }

    @Test("a rule from an older file decodes with its defaults")
    func backwardCompatible() throws {
        let json = """
            [{"id":"11111111-0000-4000-A000-000000000002","name":"minimal","condition":"1 == 1"}]
            """.data(using: .utf8)!
        let rules = try JSONDecoder().decode([Rule].self, from: json)
        #expect(rules[0].isEnabled)
        #expect(rules[0].trigger == .becomesTrue)
        #expect(rules[0].actions.isEmpty)
        #expect(rules[0].sources.count == 1)
    }

    @Test("a rule declares the hosts it will contact")
    func declaredHosts() {
        var rule = Rule()
        rule.sources.append(DataSource(name: "api", kind: .json,
                                       url: "https://api.example.com/x.json"))
        #expect(rule.declaredHosts == ["api.example.com"])
    }

    @Test("a rule can do everything a click can")
    func vocabularyParity() {
        // Two vocabularies for "what happens" is a fork that only widens, and
        // there was already a gap: a rule could open a link but not an app.
        let clickKinds = Set(Action.Kind.allCases.map(\.rawValue))
            .subtracting(["none", "refresh"])
        let ruleKinds = Set(RuleAction.Kind.allCases.map(\.rawValue))
        #expect(clickKinds.isSubset(of: ruleKinds))
    }

    @Test("a hand-rolled shortcut URL becomes a real shortcut action")
    func migratesShortcutURLs() {
        // The editor used to tell people to write shortcuts://run-shortcut?name=…
        // in the link field. Restricting links to http and https would silently
        // stop those rules working.
        let old = RuleAction(id: UUID(), kind: .openURL,
                             primary: "shortcuts://run-shortcut?name=Start%20my%20day",
                             secondary: "", overlayID: nil)
        let new = old.migrated
        #expect(new.kind == .runShortcut)
        #expect(new.primary == "Start my day")
    }

    @Test("an ordinary link is left alone by the migration")
    func migrationIsNarrow() {
        let link = RuleAction(id: UUID(), kind: .openURL,
                              primary: "https://example.com", secondary: "", overlayID: nil)
        #expect(link.migrated.kind == .openURL)
        #expect(link.migrated.primary == "https://example.com")
    }

    @Test("only the shared kinds map to a click action")
    func sharedMapping() {
        for kind in RuleAction.Kind.allCases {
            let action = RuleAction(id: UUID(), kind: kind, primary: "x",
                                    secondary: "", overlayID: nil)
            let shared = action.sharedAction(renderedWith: nil)
            switch kind {
            case .notify, .showOverlay, .hideOverlay, .playSound:
                #expect(shared == nil)
            default:
                #expect(shared?.value == "x")
            }
        }
    }
}
