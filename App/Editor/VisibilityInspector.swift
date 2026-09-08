import SwiftUI

/// When an element should draw at all.
///
/// Conditional visibility shipped in the model, the renderer and two catalog
/// layouts, and had no control anywhere — a feature that existed and could not
/// be reached. "Hide this when the value is zero" is one of the most common
/// things anyone wants from a data-driven design, and without it every such
/// widget needs a second document.
///
/// The panel says what the condition evaluates to *right now*, because a rule
/// about when something appears is impossible to reason about while looking at
/// a canvas that only shows you one of the two cases.
struct VisibilityInspector: View {
    @Bindable var model: EditorModel
    let element: Element

    /// Keyed on the condition *existing*, not on it being non-empty.
    ///
    /// Keyed on emptiness, clearing the field to retype flipped the switch off
    /// and took the field away mid-edit — the UI destroying its own state, the
    /// same shape as an inspector field that writes back what it was just
    /// given. An empty condition is a condition that is always true, which is
    /// what the resolver already does with one.
    private var isConditional: Bool { element.visibleWhen != nil }

    private var isBlank: Bool {
        (element.visibleWhen ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var problem: String? {
        guard let source = element.visibleWhen, !isBlank else { return nil }
        do { _ = try ExpressionParser.parse(source); return nil }
        catch { return error.localizedDescription }
    }

    private var showingNow: Bool {
        model.data.isVisible(element, in: model.doc)
    }

    var body: some View {
        InspectorSection(title: "Visibility") {
            Toggle(isOn: Binding(
                get: { isConditional },
                set: { on in
                    model.update(element.id, on ? "Add condition" : "Always show") {
                        // Seeded with something true rather than empty, so the
                        // element does not vanish the instant the switch is
                        // flipped.
                        $0.visibleWhen = on ? "true" : nil
                    }
                }
            )) {
                Text("Only show when…")
                    .font(.system(size: 11))
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            if isConditional {
                TextField("true", text: Binding(
                    get: { element.visibleWhen ?? "" },
                    set: { new in model.update(element.id, "Condition") { $0.visibleWhen = new } }
                ), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1...3)

                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if isBlank {
                    Text("Empty, so always shown. Type a condition or pick an example.")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: showingNow ? "eye.fill" : "eye.slash.fill")
                            .foregroundStyle(showingNow ? Palette.accent : Palette.textDim)
                        Text(showingNow ? "Showing right now" : "Hidden right now")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(showingNow ? Palette.text : Palette.textDim)
                        Spacer()
                    }
                    .padding(7)
                    .background(Palette.surface.opacity(0.6),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }

                Menu {
                    ForEach(Self.recipes, id: \.expression) { recipe in
                        Button(recipe.label) {
                            model.update(element.id, "Condition") { $0.visibleWhen = recipe.expression }
                        }
                    }
                } label: {
                    Label("Examples", systemImage: "eye.trianglebadge.exclamationmark")
                        .font(.system(size: 10))
                }
                .menuStyle(.borderlessButton)

                Text("Same language as a transform. `value` is this element's own field; other fields can be named directly.")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textDim.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Always drawn.")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textDim.opacity(0.85))
            }
        }
    }

    /// Conditions somebody will actually want, none of which is obvious from a
    /// blank field.
    private static let recipes: [(label: String, expression: String)] = [
        ("Only when this field has a value", "!isnull(value)"),
        ("Hide when the value is zero", "value != 0"),
        ("Only while charging", "battery.isCharging"),
        ("Only when the battery is low", "battery.percent < 0.2"),
        ("Only when the disk is nearly full", "disk.usedFraction > 0.9"),
        ("Only when the Mac is working hard", "cpu.usage > 0.6"),
        ("Only at night", "current.is_day == 0"),
        ("Only when something is scheduled", "authorised && count > 0"),
        ("Only when Fathom has permission", "authorised"),
        ("Only when it does not", "!authorised"),
    ]
}
