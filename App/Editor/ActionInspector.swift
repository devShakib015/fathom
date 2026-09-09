import SwiftUI

/// What clicking this element does.
///
/// The panel's real job is not the picker — it is saying where the action will
/// and will not work. An action set on a design that only lives in a WidgetKit
/// slot does nothing, forever, with no error, and a person who has just set one
/// and seen nothing happen deserves to be told why rather than left to conclude
/// the feature is broken.
struct ActionInspector: View {
    @Environment(OverlayController.self) private var overlays
    @Environment(MenuBarController.self) private var menuBar
    @Environment(IslandController.self) private var island
    @Environment(SummonController.self) private var summon
    @Bindable var model: EditorModel
    let element: Element

    private var action: Action { element.action ?? Action() }

    private func update(_ change: (inout Action) -> Void) {
        var copy = action
        change(&copy)
        model.update(element.id, "Action") { $0.action = copy.kind == .none ? nil : copy }
    }

    /// Whether this design is on any surface that can be clicked at all.
    private var isOnAClickableSurface: Bool {
        let id = model.doc.id
        return overlays.overlays.contains { $0.documentID == id && $0.isEnabled }
            || menuBar.items.contains { $0.documentID == id && $0.isEnabled }
            || (island.island?.documentID == id && island.island?.isEnabled == true)
            || (summon.summon?.documentID == id && summon.summon?.isEnabled == true)
    }

    var body: some View {
        InspectorSection(title: "When clicked") {
            InspectorRow(label: "Does") {
                Picker("", selection: Binding(get: { action.kind },
                                              set: { kind in update { $0.kind = kind } })) {
                    ForEach(Action.Kind.allCases, id: \.self) { kind in
                        Label(kind.displayName, systemImage: kind.symbol).tag(kind)
                    }
                }
                .labelsHidden()
            }

            if action.kind.needsValue {
                TextField(action.kind.placeholder, text: Binding(
                    get: { action.value },
                    set: { value in update { $0.value = value } }))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
            }

            if action.kind != .none {
                if isOnAClickableSurface {
                    Label("Works on overlays, the menu bar, the island and the summoned panel.",
                          systemImage: "cursorarrow.click")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    // The failure this panel exists to prevent.
                    Label("This design is not on a surface that can be clicked. Desktop widgets are drawn by WidgetKit and cannot run an action — put it on an overlay, the menu bar, the island or a hotkey.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Anyone you share this design with is told what it does before they add it.")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textDim.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
