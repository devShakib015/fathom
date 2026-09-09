import Testing
import Foundation

/// Which parts of the system a design actually causes to be read.
///
/// The failure to guard against is not a slow widget. It is a *missing* value:
/// computing one branch too many wastes a `statfs`, computing one too few makes
/// a binding silently read as nothing. So the analysis is deliberately
/// over-inclusive and these tests check it errs in that direction.
@Suite("Snapshot scope")
struct SnapshotScopeTests {

    private let all = SystemSource.branchNames

    @Test("a clock asks for the date and nothing else")
    func clockOnly() {
        // The case that motivated this: an overlay refreshing every five
        // seconds was statting the boot volume and reading host counters for a
        // design that wanted the time.
        let roots = Starters.systemSmall.referencedRoots(among: all)
        #expect(roots.contains("date"))
        #expect(!roots.contains("devices"))
    }

    @Test("a key path names its own branch exactly")
    func fromKeyPath() {
        var doc = Starters.systemSmall
        doc.elements = [Element(name: "x", kind: .text,
                                frame: Frame(x: 0, y: 0, width: 1, height: 1),
                                binding: DataBinding(sourceID: UUID(), keyPath: "battery.percent"))]
        #expect(doc.referencedRoots(among: all) == ["battery"])
    }

    @Test("a bare array key path counts")
    func bareKeyPath() {
        // `devices` is bound with no dot at all, by a repeater.
        var doc = Starters.systemSmall
        doc.elements = [Element(name: "x", kind: .repeater,
                                frame: Frame(x: 0, y: 0, width: 1, height: 1),
                                binding: DataBinding(sourceID: UUID(), keyPath: "devices"))]
        #expect(doc.referencedRoots(among: all).contains("devices"))
    }

    @Test("an expression is scanned, and a condition too")
    func fromFreeText() {
        var doc = Starters.systemSmall
        var element = Element(name: "x", kind: .text,
                              frame: Frame(x: 0, y: 0, width: 1, height: 1),
                              binding: DataBinding(sourceID: UUID(), keyPath: "date.now",
                                                   expression: "percent(memory.usedFraction)"))
        element.visibleWhen = "disk.freeFraction < 0.1"
        doc.elements = [element]

        let roots = doc.referencedRoots(among: all)
        #expect(roots.contains("memory"))
        #expect(roots.contains("disk"))
        #expect(roots.contains("date"))
    }

    @Test("cpu.system does not drag in the system branch")
    func noSubstringFalsePositive() {
        // The whole reason the scan is anchored: every palette of field names
        // here contains another as a substring.
        var doc = Starters.systemSmall
        doc.elements = [Element(name: "x", kind: .text,
                                frame: Frame(x: 0, y: 0, width: 1, height: 1),
                                binding: DataBinding(sourceID: UUID(), keyPath: "cpu.system"))]
        let roots = doc.referencedRoots(among: all)
        #expect(roots.contains("cpu"))
        #expect(!roots.contains("system"))
    }

    @Test("asking for nothing still produces a tree; asking for all produces all")
    func snapshotHonoursTheSet() {
        let full = SystemSource.snapshot()
        for name in all {
            #expect(full[path: name] != nil)
        }
        let narrow = SystemSource.snapshot(needed: ["date"])
        #expect(narrow[path: "date.now"] != nil)
        #expect(narrow[path: "disk.free"] == nil)
    }

    @Test("a narrow snapshot carries only what was asked for")
    func narrowSnapshot() {
        // The counter write this change removed cannot be asserted directly:
        // the sample file lives in the shared store, which a running Fathom
        // writes too, so a test watching it is racing another process. Asserting
        // that on shared mutable state is how a suite acquires a test that
        // fails on other people's machines for reasons they cannot see.
        //
        // What is checkable is the shape: counters are only read when a rate
        // branch is present, so a tree with no cpu and no network did no
        // counter work by construction.
        let narrow = SystemSource.snapshot(needed: ["date"])
        guard case .object(let branches) = narrow else {
            Issue.record("expected an object"); return
        }
        #expect(branches.map(\.key) == ["date"])
    }
}
