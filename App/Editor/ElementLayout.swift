import SwiftUI

/// Where every element — nested ones included — actually sits on the canvas.
///
/// The renderer draws containers by handing each child a box of its own, so a
/// child's unit frame means nothing in canvas coordinates until the whole chain
/// of parents has been resolved. The editor needs those absolute rects to put
/// selection handles anywhere, so this walk mirrors the renderer's layout
/// exactly. The two must agree; where they would differ, this file is the one
/// that is wrong.
struct Placement: Identifiable {
    let id: UUID
    let element: Element
    let depth: Int
    /// Absolute, in canvas points. Mutable so a drag in progress can move
    /// the handles without the document being touched.
    var rect: CGRect
    /// The box this element's unit frame is measured against — what a drag
    /// distance has to be divided by to become a change in `frame`.
    let containerSize: CGSize
    /// Inside a repeater, and therefore drawn once per row. Handles sit on the
    /// first row, because that is the one the others are copies of.
    let isTemplate: Bool
    /// Its condition is false right now, so the renderer is drawing nothing
    /// there. The editor still places it — an element you cannot find is an
    /// element you cannot turn back on.
    let isHidden: Bool
}

enum ElementLayout {

    static func placements(_ doc: WidgetDoc,
                           data: ResolvedData,
                           in size: CGSize,
                           scale: Double) -> [Placement] {
        var out: [Placement] = []

        func walk(_ elements: [Element],
                  origin: CGPoint,
                  container: CGSize,
                  depth: Int,
                  scope: ResolvedData.Scope,
                  isTemplate: Bool) {
            for element in elements {
                let local = element.frame.resolved(in: container)
                let rect = CGRect(x: origin.x + local.minX, y: origin.y + local.minY,
                                  width: local.width, height: local.height)
                out.append(Placement(id: element.id, element: element, depth: depth,
                                     rect: rect, containerSize: container,
                                     isTemplate: isTemplate,
                                     isHidden: !data.isVisible(element, in: doc, scope: scope)))

                switch element.kind {
                case .group:
                    walk(element.children, origin: rect.origin, container: rect.size,
                         depth: depth + 1, scope: scope, isTemplate: isTemplate)

                case .repeater:
                    // The first row only. Editing a repeater means editing its
                    // template, and drawing handles on all seven copies of a
                    // forecast column would be unusable.
                    let cell = firstCell(of: element, rect: rect, data: data, scope: scope, scale: scale)
                    let rows = data.items(for: element, scope: scope)
                    walk(element.children, origin: cell.origin, container: cell.size,
                         depth: depth + 1,
                         scope: ResolvedData.Scope(item: rows.first,
                                                   index: 0,
                                                   total: max(rows.count, 1)),
                         isTemplate: true)

                default:
                    break
                }
            }
        }

        walk(doc.elements, origin: .zero, container: size, depth: 0,
             scope: .root, isTemplate: false)
        return out
    }

    /// Mirrors the renderer's stack: axis from the shape drawn, spacing from
    /// `lineWidth`, and at least one row so a repeater bound to nothing still
    /// shows its template rather than collapsing to nothing to click on.
    private static func firstCell(of element: Element,
                                  rect: CGRect,
                                  data: ResolvedData,
                                  scope: ResolvedData.Scope,
                                  scale: Double) -> CGRect {
        let count = max(min(data.items(for: element, scope: scope).count,
                            Element.repeaterLimit), 1)
        let vertical = rect.height > rect.width
        let spacing = element.style.lineWidth * scale
        let total = vertical ? rect.height : rect.width
        let extent = max((total - spacing * Double(count - 1)) / Double(count), 4)

        return vertical
            ? CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: extent)
            : CGRect(x: rect.minX, y: rect.minY, width: extent, height: rect.height)
    }
}
