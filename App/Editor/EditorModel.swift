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
    /// Off by default, now that the alignment guides exist.
    ///
    /// Grid snapping quantises every drag to one twenty-fourth of the widget —
    /// about fourteen pixels on screen at two hundred percent zoom — so an
    /// element can only ever sit on a lattice and moving it looks like it is
    /// stepping rather than following the pointer. That was tolerable when it
    /// was the only way to line anything up. The guides do that job now, and
    /// they do it against things that actually matter — a neighbour's edge, the
    /// middle of the widget — within four pixels rather than fourteen.
    ///
    /// Still here for anyone who wants a strict grid; it is simply no longer
    /// imposed on everybody.
    var snapEnabled = false
    /// Seeing the grid and snapping to it are different questions, and tying
    /// them together meant the only way to look at the guides was to accept
    /// being pulled onto them. On by default: a grid you have to switch on is
    /// one most people never learn exists.
    var gridVisible = true
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

    /// Selection reaches inside containers: a repeater's child is selectable,
    /// inspectable and draggable exactly like a top-level element, because ids
    /// are unique across the tree and every operation addresses them by id.
    var selectedElements: [Element] {
        doc.flattenedElements.map(\.element).filter { selection.contains($0.id) }
    }

    /// The inspector edits one element at a time. With several selected it
    /// follows the last one in document order, which is the one drawn on top.
    var focusedElement: Element? {
        doc.flattenedElements.map(\.element).last { selection.contains($0.id) }
    }

    func select(_ id: UUID, add: Bool = false) {
        if add {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        } else {
            selection = [id]
        }
    }

    func selectAll() { selection = doc.elements.allIDs() }
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
    /// Puts a different palette on without disturbing anything else.
    ///
    /// Through `edit`, so it undoes. Restyling is the change people most want
    /// to try repeatedly and least want to commit to.
    func restyle(to theme: Theme) {
        let current = Restyle.currentTheme(of: doc)
        let restyled = Restyle.apply(theme, to: doc, from: current)
        edit("Restyle") { doc in
            doc.background = restyled.background
            doc.elements = restyled.elements
            doc.paletteID = restyled.paletteID
        }
        Task { await resolve() }
    }

    /// Puts the design back the way the catalogue shipped it.
    ///
    /// Goes through `edit`, so it lands on the undo stack like any other
    /// change. A revert that could not itself be undone would be a worse trap
    /// than the edit it undoes.
    func revertToOriginal() {
        guard let original = doc.shippedOriginal else { return }
        edit("Revert to original") { doc in
            doc.elements = original.elements
            doc.sources = original.sources
            doc.background = original.background
            doc.minimumRefresh = original.minimumRefresh
            // Back to the palette it came with, not merely the layout.
            doc.paletteID = nil
        }
        selection = []
        Task { await resolve() }
    }

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
    /// Ends a drag and writes the result once.
    func endGesture() {
        guard gestureInProgress else { return }
        gestureInProgress = false
        save()
    }

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

    /// Adds into whatever container is selected, or beside it, or at the top
    /// level. Selecting a repeater and pressing Text should put the text in the
    /// repeater — anything else means containers can only ever be built by the
    /// catalog.
    func add(_ kind: Element.Kind) {
        let parent = doc.containerForInsertion(near: selection.first)
        var element = Element.new(kind, in: doc)
        if parent != nil {
            // Inside a container the unit box is the container's own, so the
            // fanning offset used at the top level would push it off the edge.
            element.frame = Frame(x: 0.05, y: 0.05, width: 0.9, height: 0.3)
        }
        edit("Add \(kind.displayName)") { $0.elements.insert(element, into: parent) }
        selection = [element.id]
    }

    func update(_ id: UUID, _ name: String, coalescing: Bool = false, _ change: (inout Element) -> Void) {
        guard doc.element(id) != nil else { return }
        edit(name, coalescing: coalescing) { $0.elements.update(id, change) }
    }

    func updateSelected(_ name: String, _ change: (inout Element) -> Void) {
        let ids = selection
        guard !ids.isEmpty else { return }
        edit(name) { doc in
            for id in ids { doc.elements.update(id, change) }
        }
    }

    func deleteSelected() {
        guard !selection.isEmpty else { return }
        let ids = selection
        // Removing a container takes its contents with it; leaving the children
        // behind would orphan them into a document that cannot draw them.
        edit("Delete") { $0.elements.remove(ids: ids) }
        selection = []
    }

    func duplicateSelected() {
        let originals = selectedElements
        guard !originals.isEmpty else { return }
        var copies: [(element: Element, parent: UUID?)] = []
        for original in originals {
            // A deep copy with fresh ids throughout, so duplicating a container
            // gives two independent trees rather than two views of one.
            var copy = [original].reidentified()[0]
            // Offset so the copy is visibly a copy rather than sitting exactly
            // on top of the thing it came from.
            copy.frame.x = min(copy.frame.x + 0.04, 1 - copy.frame.width)
            copy.frame.y = min(copy.frame.y + 0.04, 1 - copy.frame.height)
            copies.append((copy, doc.parentID(of: original.id)))
        }
        edit("Duplicate") { doc in
            for copy in copies { doc.elements.insert(copy.element, into: copy.parent) }
        }
        selection = Set(copies.map(\.element.id))
    }

    /// Removes every element, leaving the document itself intact. Undoable
    /// like anything else, which is the only reason it is safe to offer.
    func deleteAll() {
        guard !doc.elements.isEmpty else { return }
        edit("Delete all") { $0.elements.removeAll() }
        selection = []
    }

    func bringSelectedToFront() {
        for id in selection { move(id, toFront: true) }
    }

    func sendSelectedToBack() {
        for id in selection { move(id, toFront: false) }
    }

    /// Draw order. Later in the array is nearer the front, which matches how
    /// the renderer stacks them.
    /// Reorders within whatever list the element lives in — the document's, or
    /// its container's.
    func move(_ id: UUID, toFront: Bool) {
        guard let element = doc.element(id) else { return }
        let parent = doc.parentID(of: id)
        edit(toFront ? "Bring to Front" : "Send to Back") { doc in
            doc.elements.remove(ids: [id])
            if parent == nil {
                if toFront { doc.elements.append(element) } else { doc.elements.insert(element, at: 0) }
            } else {
                doc.elements.update(parent!) { container in
                    if toFront { container.children.append(element) }
                    else { container.children.insert(element, at: 0) }
                }
            }
        }
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

    /// Lines the selection up. The geometry lives in `Alignment` so it can be
    /// tested without a view; this only supplies the selection and the undo
    /// entry.
    func align(_ alignment: ElementAlignment) {
        let chosen = selectedElements
        guard let moves = ElementAlignment.positions(for: alignment, in: chosen) else { return }
        updateSelected(alignment.label) { element in
            if let frame = moves[element.id] { element.frame = frame.normalised }
        }
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
    /// Bumped once per committed change, never during a drag.
    ///
    /// What the rest of the app watches instead of `doc`. A drag mutates `doc`
    /// on every frame so the canvas can follow the pointer, and everything
    /// downstream of a *finished* edit — saving, the overlays, the menu bar,
    /// the island — should happen once at the end rather than sixty times a
    /// second.
    private(set) var commits = 0

    private func save() {
        // A drag delivers one mouse-move per frame, and each one used to run
        // the whole document through `sanitised` — element normalisation,
        // source migration, caption migration — encode it, and write it to disk
        // atomically. Then five surface controllers woke up and re-resolved.
        // Moving one element was doing sixty document writes a second, which is
        // what made dragging feel like it was fighting back.
        guard !gestureInProgress else { return }
        DocumentStore.shared.save(doc)
        commits += 1
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
