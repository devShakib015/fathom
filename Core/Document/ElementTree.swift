import Foundation

/// `Element` is both this document's element type and `Array`'s own associated
/// type name, which makes the constrained extension below unwritable without an
/// alias. Core is compiled into both targets rather than imported as a module,
/// so there is no module name to qualify with.
typealias WidgetElement = Element

/// Reaching elements nested inside containers.
///
/// Element ids are unique across the whole document, so every operation here
/// addresses an element by id and does not care how deep it sits. That is what
/// lets the editor treat a repeater's child exactly like a top-level element:
/// one selection model, one inspector, one undo stack, no special cases for
/// "the thing inside the thing".
extension Array where Element == WidgetElement {

    func find(_ id: UUID) -> WidgetElement? {
        for element in self {
            if element.id == id { return element }
            if let nested = element.children.find(id) { return nested }
        }
        return nil
    }

    mutating func update(_ id: UUID, _ change: (inout WidgetElement) -> Void) {
        for index in indices {
            if self[index].id == id { change(&self[index]); return }
            if self[index].children.find(id) != nil {
                self[index].children.update(id, change)
                return
            }
        }
    }

    mutating func remove(ids: Set<UUID>) {
        removeAll { ids.contains($0.id) }
        for index in indices {
            self[index].children.remove(ids: ids)
        }
    }

    /// Appends into a container, or at the top level when `parent` is nil.
    mutating func insert(_ element: WidgetElement, into parent: UUID?) {
        guard let parent else { append(element); return }
        update(parent) { $0.children.append(element) }
    }

    func parent(of id: UUID) -> UUID? {
        for element in self {
            if element.children.contains(where: { $0.id == id }) { return element.id }
            if let deeper = element.children.parent(of: id) { return deeper }
        }
        return nil
    }

    /// Depth-first, with nesting depth — the order and shape a layer list wants.
    func flattened(depth: Int = 0) -> [(element: WidgetElement, depth: Int)] {
        flatMap { element in
            [(element, depth)] + element.children.flattened(depth: depth + 1)
        }
    }

    /// Every id in the subtree, so deleting a container takes its contents with
    /// it rather than orphaning them into nothing.
    func allIDs() -> Set<UUID> {
        reduce(into: Set<UUID>()) { out, element in
            out.insert(element.id)
            out.formUnion(element.children.allIDs())
        }
    }

    /// A deep copy with fresh ids, so a duplicated container's children are
    /// genuinely separate rather than two views of one element.
    func reidentified() -> [WidgetElement] {
        map { element in
            var copy = element
            copy.id = UUID()
            copy.children = element.children.reidentified()
            return copy
        }
    }
}

extension WidgetDoc {
    func element(_ id: UUID) -> Element? { elements.find(id) }
    func parentID(of id: UUID) -> UUID? { elements.parent(of: id) }
    var flattenedElements: [(element: Element, depth: Int)] { elements.flattened() }

    /// The container an addition should go into, given what is selected: the
    /// selection itself when it is a container, otherwise whatever contains it.
    func containerForInsertion(near id: UUID?) -> UUID? {
        guard let id, let element = element(id) else { return nil }
        if element.isContainer { return element.id }
        return parentID(of: id)
    }
}
