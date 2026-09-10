import Testing
import AppKit

/// Lining elements up.
@Suite("Alignment")
struct AlignmentTests {

    private func doc(_ frames: [(Double, Double, Double, Double)]) -> WidgetDoc {
        var doc = Starters.systemSmall
        doc.elements = frames.enumerated().map { index, f in
            Element(name: "e\(index)", kind: .text,
                    frame: Frame(x: f.0, y: f.1, width: f.2, height: f.3))
        }
        return doc
    }

    private func aligned(_ frames: [(Double, Double, Double, Double)],
                         _ alignment: ElementAlignment) -> [Frame] {
        let elements = doc(frames).elements
        guard let moves = ElementAlignment.positions(for: alignment, in: elements) else {
            return elements.map(\.frame)
        }
        return elements.map { moves[$0.id]?.normalised ?? $0.frame }
    }

    @Test("one element centres inside the widget, not against itself")
    func singleCentres() {
        // The most common thing anyone wants, and there was no way to ask for
        // it. With one element the widget is the thing to line up against.
        let result = aligned([(0.1, 0.1, 0.4, 0.2)], .centreX)
        #expect(abs(result[0].x - 0.3) < 0.0001)
    }

    @Test("several line up against each other's bounding box")
    func manyAlignToEachOther() {
        let result = aligned([(0.1, 0.1, 0.2, 0.1), (0.5, 0.4, 0.2, 0.1)], .left)
        #expect(result.allSatisfy { abs($0.x - 0.1) < 0.0001 })
    }

    @Test("right and bottom account for each element's own size")
    func edgesUseSize() {
        let right = aligned([(0.1, 0.1, 0.2, 0.1), (0.5, 0.4, 0.3, 0.1)], .right)
        // The box's right edge is 0.8; each element's left must be 0.8 - width.
        #expect(abs(right[0].x - 0.6) < 0.0001)
        #expect(abs(right[1].x - 0.5) < 0.0001)
    }

    @Test("spreading needs three and leaves the outer two where they were")
    func spread() {
        let frames = [(0.0, 0.0, 0.1, 0.1), (0.15, 0.0, 0.1, 0.1), (0.9, 0.0, 0.1, 0.1)]
        let result = aligned(frames, .spreadX)
        #expect(abs(result[0].x - 0.0) < 0.0001)
        #expect(abs(result[2].x - 0.9) < 0.0001)
        // The middle one lands halfway between them.
        #expect(abs(result[1].x - 0.45) < 0.0001)

        // With two, spreading has no meaning and must do nothing.
        let two = aligned([(0.0, 0.0, 0.1, 0.1), (0.9, 0.0, 0.1, 0.1)], .spreadX)
        #expect(abs(two[1].x - 0.9) < 0.0001)
    }

    @Test("every alignment has an icon and a plain-words label")
    func labels() {
        for alignment in ElementAlignment.allCases {
            #expect(!alignment.symbol.isEmpty)
            #expect(!alignment.label.isEmpty)
            #expect(NSImage(systemSymbolName: alignment.symbol,
                            accessibilityDescription: nil) != nil,
                    "\(alignment.symbol) does not resolve")
        }
    }
}
