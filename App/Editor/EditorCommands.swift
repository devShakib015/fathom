import SwiftUI

/// Publishes the editor to the menu bar.
///
/// The keyboard handlers used to hang off `.focusable()` on the canvas, which
/// meant they only worked when the canvas held keyboard focus — and clicking an
/// element goes through a drag gesture, which never takes focus. Delete and the
/// arrow keys therefore did nothing, ever, and there was no menu to fall back
/// to. A focused *scene* value has no such dependency: the commands are live
/// whenever a document is open, wherever the caret happens to be.
struct EditorFocusKey: FocusedValueKey {
    typealias Value = EditorModel
}

extension FocusedValues {
    var editor: EditorModel? {
        get { self[EditorFocusKey.self] }
        set { self[EditorFocusKey.self] = newValue }
    }
}

struct EditorCommands: Commands {
    @FocusedValue(\.editor) private var editor: EditorModel?

    var body: some Commands {
        // Replaces the system's own undo group, which has nothing to act on:
        // the document is not an NSDocument and does not use NSUndoManager.
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { editor?.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(editor?.canUndo != true)
            Button("Redo") { editor?.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(editor?.canRedo != true)
        }

        CommandGroup(replacing: .pasteboard) {
            Button("Duplicate") { editor?.duplicateSelected() }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(editor?.selection.isEmpty != false)

            Button("Delete") { editor?.deleteSelected() }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(editor?.selection.isEmpty != false)

            Divider()

            Button("Select All") { editor?.selectAll() }
                .keyboardShortcut("a", modifiers: .command)
                .disabled(editor == nil)

            Button("Deselect") { editor?.deselect() }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(editor?.selection.isEmpty != false)

            Divider()

            Button("Delete All Elements", role: .destructive) { editor?.deleteAll() }
                .disabled(editor?.doc.elements.isEmpty != false)
        }

        CommandMenu("Element") {
            Button("Bring to Front") { editor?.bringSelectedToFront() }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled(editor?.selection.isEmpty != false)
            Button("Send to Back") { editor?.sendSelectedToBack() }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled(editor?.selection.isEmpty != false)

            Divider()

            ForEach(Element.Kind.allCases, id: \.self) { kind in
                Button("Add \(kind.displayName)") { editor?.add(kind) }
                    .disabled(editor == nil)
            }
        }
    }
}
