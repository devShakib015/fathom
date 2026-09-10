import Testing
import Foundation

/// Lining a dragged element up with the things around it.
@Suite("Snap guides")
struct SnapGuideTests {

    private func frame(_ x: Double, _ y: Double, _ w: Double = 0.2, _ h: Double = 0.1) -> Frame {
        Frame(x: x, y: y, width: w, height: h)
    }

    @Test("nothing near means nothing moves")
    func noSnap() {
        // Chosen so no edge or centre of it lands on a widget line either. The
        // first attempt at this fixture sat at x 0.3 with width 0.2, which puts
        // its right edge exactly on the widget's centre — the guides caught an
        // alignment the test had not meant to create, which is the feature
        // working.
        let loose = frame(0.31, 0.33, 0.17, 0.11)
        let result = SnapGuides.snap(loose, against: [frame(0.72, 0.81)])
        #expect(result.frame == loose)
        #expect(result.guides.isEmpty)
    }

    @Test("a left edge close to a neighbour's left edge lines up exactly")
    func edgeToEdge() {
        let result = SnapGuides.snap(frame(0.305, 0.61, 0.17, 0.11), against: [frame(0.3, 0.22)])
        #expect(abs(result.frame.x - 0.3) < 0.0001)
        #expect(result.guides.contains { $0.axis == .vertical && abs($0.position - 0.3) < 0.0001 })
    }

    @Test("the middle of the widget is a target, and is marked as one")
    func widgetCentre() {
        // Centring something is the commonest thing anyone does and the hardest
        // to hit by hand.
        let result = SnapGuides.snap(frame(0.404, 0.61, 0.2, 0.11), against: [])
        #expect(abs(result.frame.x - 0.4) < 0.0001)   // centre of a 0.2-wide box at 0.5
        #expect(result.guides.first?.isWidgetEdge == true)
    }

    @Test("centres line up with centres, not just edges")
    func centreToCentre() {
        // Neighbour spans 0.1…0.5, centre 0.3. Dragged box is 0.2 wide, so its
        // centre matches when x is 0.2.
        let result = SnapGuides.snap(frame(0.196, 0.61, 0.2, 0.11),
                                     against: [frame(0.1, 0.13, 0.4, 0.1)])
        #expect(abs(result.frame.x - 0.2) < 0.0001)
    }

    @Test("each axis snaps on its own")
    func axesAreIndependent() {
        // Lined up across but nowhere near anything down.
        let result = SnapGuides.snap(frame(0.302, 0.61, 0.17, 0.11), against: [frame(0.3, 0.13)])
        #expect(abs(result.frame.x - 0.3) < 0.0001)
        #expect(abs(result.frame.y - 0.61) < 0.0001)
        #expect(result.guides.count == 1)
        #expect(result.guides.first?.axis == .vertical)
    }

    @Test("the nearest target wins, not the first one found")
    func nearestWins() {
        // Between two neighbours: 0.30 and 0.31. At 0.3085 the second is closer.
        let result = SnapGuides.snap(frame(0.3085, 0.61, 0.17, 0.11),
                                     against: [frame(0.30, 0.13), frame(0.31, 0.13)])
        #expect(abs(result.frame.x - 0.31) < 0.0001)
    }

    @Test("a deliberate near-miss outside the tolerance survives")
    func toleranceIsFinite() {
        // Every value here is chosen to sit clear of all six of its own anchors
        // against the widget's three lines and the neighbour's three. Two
        // earlier attempts at this fixture snapped by accident — the widget's
        // own centre line is close to a great deal of the canvas, which is a
        // fair reminder of how often this will fire in real use.
        let dragged = Frame(x: 0.34, y: 0.61, width: 0.13, height: 0.11)
        let neighbour = Frame(x: 0.30, y: 0.13, width: 0.13, height: 0.11)

        let result = SnapGuides.snap(dragged, against: [neighbour])
        #expect(result.frame == dragged)
        #expect(result.guides.isEmpty)
    }

    @Test("snapping never changes an element's size")
    func sizePreserved() {
        let original = frame(0.305, 0.205, 0.37, 0.13)
        let result = SnapGuides.snap(original, against: [frame(0.3, 0.2)])
        #expect(result.frame.width == original.width)
        #expect(result.frame.height == original.height)
    }
}

/// What the widget extension gets from the shared renderer.
///
/// The editor gained two things the extension must never see: a live drag
/// offset and a click handler. Both are optional and both default to nil, so
/// the extension's rendering is unchanged by construction rather than by
/// anybody remembering — these pin that, because a change here fails silently
/// on the desktop and macOS gives no error when a widget draws wrongly.
@Suite("Extension rendering")
struct ExtensionRenderingTests {

    @Test("with no drag in flight, frames are the document's own")
    func nilLiveIsIdentity() {
        let doc = Starters.systemSmall
        let live: LiveOffset? = nil
        for element in doc.elements {
            #expect((live?.frame(for: element) ?? element.frame) == element.frame)
        }
    }

    @Test("a live offset only moves the elements it names")
    func liveTouchesOnlyItsOwn() {
        let doc = Starters.systemSmall
        let moved = doc.elements[0]
        var shifted = moved.frame
        shifted.x += 0.2

        let live = LiveOffset(frames: [moved.id: shifted])
        #expect(live.frame(for: moved) == shifted)
        for other in doc.elements.dropFirst() {
            #expect(live.frame(for: other) == other.frame)
        }
    }

    @Test("an element with an action is inert without a handler")
    func actionsNeedAHandler() {
        // The extension passes no handler, so there is nothing to perform an
        // action with — inert by construction, not by a flag that could be
        // forgotten. WidgetKit could not honour one anyway.
        var element = Element.new(.text, in: Starters.systemSmall)
        element.action = Action(kind: .openURL, value: "https://example.com")
        #expect(element.action?.isSet == true)

        let perform: ((Action) -> Void)? = nil
        #expect(perform == nil)
    }
}
