import SwiftUI
import Observation

/// The editing session for one document.
///
/// Holds the document, the selection, and the resolved data behind it. Undo is
/// snapshot-based — the whole document is copied onto a stack — because a
/// widget document is a few kilobytes of value types and a correct, obvious
/// undo beats a clever one that has to be maintained as the vocabulary grows.
@Observable
final class EditorModel {
    private(set) var doc: WidgetDoc
    var selection: Set<UUID> = []
    private(set) var data = ResolvedData()
    private(set) var isResolving = false

    /// Snap positions to a grid in unit space. 24 divisions is fine enough to
    /// place things deliberately and coarse enough that edges line up on their
    /// own, which is most of what a grid is for.
    var snapEnabled = true
    var gridDivisions = 24

    private var undoStack: [WidgetDoc] = []
    private var redoStack: [WidgetDoc] = []
    /// While a drag is in flight the document changes on every frame; only the
    /// state before the gesture belongs on the undo stack.
    ///
    /// The model owns this rather than the canvas. It lived in the handle view
    /// as `@State` first, and because SwiftUI rebuilds that view on every frame
    /// of the drag it read as false each time — so every frame pushed its own
    /// undo entry, and one undo stepped back one frame of a snapped move, which
    /// is a change you cannot see. Undo appeared to be broken when it was
    /// merely too fine.
    private var gestureInProgress = false

    init(doc: WidgetDoc) {
        self.doc = doc
    }

    // MARK: - Selection

    var selectedElements: [Element] {
        doc.elements.filter { selection.contains($0.id) }
    }

    /// The inspector edits one element at a time. With several selected it
    /// follows the last one in document order, which is the one drawn on top.
    var focusedElement: Element? {
        doc.elements.last { selection.contains($0.id) }
    }

    func select(_ id: UUID, add: Bool = false) {
        if add {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        } else {
            selection = [id]
        }
    }

    func selectAll() { selection = Set(doc.elements.map(\.id)) }
    func deselect() { selection = [] }

    // MARK: - Editing

    /// Every mutation goes through here so that undo, autosave and the live
    /// preview cannot drift apart.
    ///
    /// `coalescing` marks a change that is one frame of a continuous gesture:
    /// the first such change in a gesture records undo, the rest do not, and
    /// `endGesture` closes it. One drag is therefore one undo.
    ///
    /// A change that changes nothing records nothing. That is not just an
    /// optimisation — an inspector field that echoes the value back when the
    /// canvas moves an element would otherwise push a fresh undo entry holding
    /// the *current* state after every frame, and undo would silently become a
    /// no-op. Comparing before and after makes that whole class of feedback
    /// loop harmless.
    func edit(_ name: String, coalescing: Bool = false, _ change: (inout WidgetDoc) -> Void) {
        let before = doc
        var updated = doc
        change(&updated)
        updated.schemaVersion = WidgetDoc.currentSchemaVersion
        guard updated != before else { return }

        if coalescing {
            if !gestureInProgress {
                pushUndo(before)
                gestureInProgress = true
            }
        } else {
            pushUndo(before)
        }
        doc = updated
        save()
    }

    /// Ends a continuous gesture, so the next change starts a new undo step.
    func endGesture() { gestureInProgress = false }

    var undoDepth: Int { undoStack.count }

    private func pushUndo(_ state: WidgetDoc) {
        undoStack.append(state)
        if undoStack.count > 200 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(doc)
        doc = previous
        selection = selection.intersection(Set(doc.elements.map(\.id)))
        save()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(doc)
        doc = next
        selection = selection.intersection(Set(doc.elements.map(\.id)))
        save()
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - Elements

    func add(_ kind: Element.Kind) {
        let element = Element.new(kind, in: doc)
        edit("Add \(kind.displayName)") { $0.elements.append(element) }
        selection = [element.id]
    }

    func update(_ id: UUID, _ name: String, coalescing: Bool = false, _ change: (inout Element) -> Void) {
        guard let index = doc.elements.firstIndex(where: { $0.id == id }) else { return }
        edit(name, coalescing: coalescing) { change(&$0.elements[index]) }
    }

    func updateSelected(_ name: String, _ change: (inout Element) -> Void) {
        let ids = selection
        guard !ids.isEmpty else { return }
        edit(name) { doc in
            for index in doc.elements.indices where ids.contains(doc.elements[index].id) {
                change(&doc.elements[index])
            }
        }
    }

    func deleteSelected() {
        guard !selection.isEmpty else { return }
        let ids = selection
        edit("Delete") { $0.elements.removeAll { ids.contains($0.id) } }
        selection = []
    }

    func duplicateSelected() {
        let originals = selectedElements
        guard !originals.isEmpty else { return }
        var copies: [Element] = []
        edit("Duplicate") { doc in
            for original in originals {
                var copy = original
                copy.id = UUID()
                // Offset so the copy is visibly a copy rather than sitting
                // exactly on top of the thing it came from.
                copy.frame.x = min(copy.frame.x + 0.04, 1 - copy.frame.width)
                copy.frame.y = min(copy.frame.y + 0.04, 1 - copy.frame.height)
                copies.append(copy)
                doc.elements.append(copy)
            }
        }
        selection = Set(copies.map(\.id))
    }

    /// Removes every element, leaving the document itself intact. Undoable
    /// like anything else, which is the only reason it is safe to offer.
    func deleteAll() {
        guard !doc.elements.isEmpty else { return }
        edit("Delete all") { $0.elements.removeAll() }
        selection = []
    }

    func bringSelectedToFront() {
        let ids = selection
        guard !ids.isEmpty else { return }
        edit("Bring to Front") { doc in
            let moved = doc.elements.filter { ids.contains($0.id) }
            doc.elements.removeAll { ids.contains($0.id) }
            doc.elements.append(contentsOf: moved)
        }
    }

    func sendSelectedToBack() {
        let ids = selection
        guard !ids.isEmpty else { return }
        edit("Send to Back") { doc in
            let moved = doc.elements.filter { ids.contains($0.id) }
            doc.elements.removeAll { ids.contains($0.id) }
            doc.elements.insert(contentsOf: moved, at: 0)
        }
    }

    /// Draw order. Later in the array is nearer the front, which matches how
    /// the renderer stacks them.
    func move(_ id: UUID, toFront: Bool) {
        guard let index = doc.elements.firstIndex(where: { $0.id == id }) else { return }
        edit(toFront ? "Bring to Front" : "Send to Back") { doc in
            let element = doc.elements.remove(at: index)
            if toFront { doc.elements.append(element) } else { doc.elements.insert(element, at: 0) }
        }
    }

    func reorder(from source: IndexSet, to destination: Int) {
        edit("Reorder") { $0.elements.move(fromOffsets: source, toOffset: destination) }
    }

    // MARK: - Data sources

    func addSource(_ source: DataSource) {
        edit("Add source") { $0.sources.append(source) }
    }

    /// Removing a source unbinds anything pointing at it. Leaving dangling
    /// bindings would mean elements that render their fallback forever with no
    /// way to see why from the inspector.
    func removeSource(_ id: UUID) {
        edit("Remove source") { doc in
            doc.sources.removeAll { $0.id == id }
            for index in doc.elements.indices where doc.elements[index].binding?.sourceID == id {
                doc.elements[index].binding = nil
            }
        }
        Task { await resolve() }
    }

    /// Binds an element to a field the user picked out of the tree, guessing a
    /// sensible format from the value's own type and the field's name.
    func bind(element id: UUID, to keyPath: String, value: DataValue, source: UUID) {
        guard let element = doc.elements.first(where: { $0.id == id }) else { return }
        let format = Format.inferred(for: value, keyPath: keyPath, kind: element.kind)
        edit("Bind \(keyPath)") { doc in
            guard let index = doc.elements.firstIndex(where: { $0.id == id }) else { return }
            doc.elements[index].binding = DataBinding(sourceID: source,
                                                      keyPath: keyPath,
                                                      format: format,
                                                      fallback: Self.fallback(for: doc.elements[index].kind))
        }
    }

    private static func fallback(for kind: Element.Kind) -> String {
        switch kind {
        case .arc, .spark: "0"
        case .symbol: "questionmark"
        default: "—"
        }
    }

    // MARK: - Geometry

    func snap(_ value: Double) -> Double {
        guard snapEnabled, gridDivisions > 0 else { return value }
        let step = 1.0 / Double(gridDivisions)
        return (value / step).rounded() * step
    }

    func nudgeSelected(dx: Double, dy: Double) {
        updateSelected("Nudge") { element in
            element.frame.x += dx
            element.frame.y += dy
            element.frame = element.frame.normalised
        }
    }

    // MARK: - Document

    func setName(_ name: String) {
        guard name != doc.name else { return }
        edit("Rename") { $0.name = name }
    }

    func setBackground(_ background: Background) {
        edit("Background") { $0.background = background }
    }

    // MARK: - Data

    @MainActor
    func resolve() async {
        isResolving = true
        data = await DataResolver.resolve(doc)
        isResolving = false
        PreviewExporter.write(doc, data: data)
    }

    // MARK: - Persistence

    /// Autosave on every change. The document is small, the write is atomic,
    /// and a design tool that can lose work is not one anybody should trust
    /// with an afternoon.
    private func save() {
        DocumentStore.shared.save(doc)
    }

    /// Push the current state to any placed widget now rather than at the next
    /// tick. Measured: a reload asked for this way is served immediately and is
    /// not subject to the 64-second floor, which only governs reloads a widget
    /// schedules for itself.
    func pushToDesktop() {
        save()
        DocumentStore.shared.reloadWidgets()
    }
}
