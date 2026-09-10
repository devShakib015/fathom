import Foundation

/// A line the canvas draws while something is being dragged, and the position
/// the drag was pulled onto.
struct SnapGuide: Equatable, Identifiable, Sendable {
    enum Axis: Sendable { case vertical, horizontal }

    var axis: Axis
    /// Unit position across the widget: 0 is the left or top edge, 1 the right
    /// or bottom.
    var position: Double
    /// True when this line comes from the widget itself rather than from
    /// another element, so the canvas can draw it differently — lining up with
    /// the middle of the widget is worth seeing more loudly than lining up with
    /// a neighbour.
    var isWidgetEdge: Bool

    var id: String { "\(axis == .vertical ? "v" : "h")\(position)\(isWidgetEdge)" }
}

/// Pulling a dragged element into line with the things around it.
///
/// A grid answers "is this on a round number", which is not the question anyone
/// is asking. The question is "is this lined up with that" — with a neighbour's
/// edge, with a neighbour's centre, with the middle of the widget. This works
/// out which of those the element is close to, moves it exactly onto the
/// nearest one, and reports the line so the canvas can show why it moved.
///
/// In `Core` so it can be tested without a window: it is arithmetic over
/// rectangles, and the whole value of it is being exactly right.
enum SnapGuides {

    /// How close counts as lined up, in unit space. About four points on a
    /// small widget — near enough that it feels magnetic, far enough that a
    /// deliberate near-miss survives.
    static let tolerance: Double = 0.012

    /// Snaps `frame` to whatever it is nearly lined up with.
    ///
    /// `others` are the frames it can line up against — its siblings, not
    /// itself. Each axis snaps independently, because being aligned across and
    /// being aligned down are separate facts.
    static func snap(_ frame: Frame, against others: [Frame],
                     tolerance: Double = SnapGuides.tolerance) -> (frame: Frame, guides: [SnapGuide]) {
        var result = frame
        var guides: [SnapGuide] = []

        // Vertical lines: left edge, centre, right edge.
        let xAnchors = [frame.x, frame.x + frame.width / 2, frame.x + frame.width]
        var xTargets: [(value: Double, widget: Bool)] = [(0, true), (0.5, true), (1, true)]
        for other in others {
            xTargets.append((other.x, false))
            xTargets.append((other.x + other.width / 2, false))
            xTargets.append((other.x + other.width, false))
        }
        if let hit = nearest(anchors: xAnchors, targets: xTargets, tolerance: tolerance) {
            result.x += hit.delta
            guides.append(SnapGuide(axis: .vertical, position: hit.target, isWidgetEdge: hit.widget))
        }

        // Horizontal lines: top edge, centre, bottom edge.
        let yAnchors = [frame.y, frame.y + frame.height / 2, frame.y + frame.height]
        var yTargets: [(value: Double, widget: Bool)] = [(0, true), (0.5, true), (1, true)]
        for other in others {
            yTargets.append((other.y, false))
            yTargets.append((other.y + other.height / 2, false))
            yTargets.append((other.y + other.height, false))
        }
        if let hit = nearest(anchors: yAnchors, targets: yTargets, tolerance: tolerance) {
            result.y += hit.delta
            guides.append(SnapGuide(axis: .horizontal, position: hit.target, isWidgetEdge: hit.widget))
        }

        return (result, guides)
    }

    /// The closest anchor-to-target pairing within tolerance, if any.
    ///
    /// Closest rather than first: an element between two neighbours is near
    /// both, and jumping to whichever happened to be earlier in the list is how
    /// snapping starts to feel arbitrary.
    private static func nearest(anchors: [Double],
                                targets: [(value: Double, widget: Bool)],
                                tolerance: Double)
        -> (delta: Double, target: Double, widget: Bool)? {
        var best: (delta: Double, target: Double, widget: Bool)?
        for anchor in anchors {
            for target in targets {
                let delta = target.value - anchor
                guard abs(delta) <= tolerance else { continue }
                if best == nil || abs(delta) < abs(best!.delta) {
                    best = (delta, target.value, target.widget)
                }
            }
        }
        return best
    }
}
