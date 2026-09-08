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
}
