import SwiftUI

/// The menu bar items showing this document.
struct MenuBarSection: View {
    @Environment(MenuBarController.self) private var controller
    @Environment(Library.self) private var library
    let doc: WidgetDoc

    private var mine: [MenuBarItem] { controller.items(for: doc.id) }

    var body: some View {
        InspectorSection(title: "Menu bar") {
            if doc.family != .menuBar {
                // Squashing a square design into a 22-point band is not a
                // rendering problem to solve, it is a design that will look
                // wrong. Say so rather than let somebody discover it.
                Label("This is a \(doc.family.displayName.lowercased()) design. Menu bar items are 22 points tall — make one with New widget ▸ Menu bar for a shape that fits.",
                      systemImage: "info.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(mine) { item in
                MenuBarItemRow(item: item, documents: library.documents)
                if item.id != mine.last?.id {
                    Divider().overlay(Palette.hairline).padding(.vertical, 3)
                }
            }

            Button {
                controller.add(for: doc)
            } label: {
                Label("Put it in the menu bar", systemImage: "menubar.arrow.up.rectangle")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Divider().overlay(Palette.hairline).padding(.vertical, 2)

            Toggle(isOn: Binding(get: { controller.showsDockIcon },
                                 set: { controller.showsDockIcon = $0 })) {
                Text("Keep Fathom in the Dock")
                    .font(.system(size: 11))
            }
            .toggleStyle(.checkbox)
            Text(controller.showsDockIcon
                 ? "Turn this off and Fathom lives only in the menu bar."
                 : "Fathom has no Dock icon. Click a menu bar item, or open it from Applications, to get back to this window.")
                .font(.system(size: 10))
                .foregroundStyle(Palette.textDim.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct MenuBarItemRow: View {
    @Environment(MenuBarController.self) private var controller
    let item: MenuBarItem
    let documents: [WidgetDoc]

    private func edit(_ change: (inout MenuBarItem) -> Void) {
        var copy = item
        change(&copy)
        controller.update(copy)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Toggle("", isOn: Binding(get: { item.isEnabled },
                                         set: { on in edit { $0.isEnabled = on } }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                Text("\(Int(item.width)) pt wide")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.text)
                Spacer()
                Button { controller.delete(item.id) } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless).foregroundStyle(Palette.textDim)
                        .accessibilityLabel("Remove from the menu bar")
            }

            InspectorRow(label: "Width") {
                NumberField(label: "Width", value: Binding(get: { item.width },
                                                           set: { w in edit { $0.width = w } }),
                            range: MenuBarItem.minimumWidth...MenuBarItem.maximumWidth,
                            step: 10, format: "%.0f")
            }

            InspectorRow(label: "Every") {
                NumberField(label: "Seconds", value: Binding(get: { item.refresh },
                                                             set: { r in edit { $0.refresh = r } }),
                            range: MenuBarItem.refreshFloor...3600, step: 1, format: "%.0f")
                Text("seconds").font(.system(size: 10)).foregroundStyle(Palette.textDim)
            }

            InspectorRow(label: "On click") {
                Picker("", selection: Binding(
                    get: { item.popoverDocumentID ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")! },
                    set: { id in
                        edit { $0.popoverDocumentID = id.uuidString.hasPrefix("00000000") ? nil : id }
                    }
                )) {
                    Text("Do nothing").tag(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
                    Divider()
                    ForEach(documents.filter { $0.family != .menuBar }) { candidate in
                        Text("Show \(candidate.name)").tag(candidate.id)
                    }
                }
                .labelsHidden()
            }
        }
    }
}
