import SwiftUI

/// The island, in the document inspector beside the other surfaces.
struct IslandSection: View {
    @Environment(IslandController.self) private var controller
    @Environment(Library.self) private var library
    let doc: WidgetDoc

    private var isThisDocument: Bool { controller.island?.documentID == doc.id }

    private func edit(_ change: (inout Island) -> Void) {
        guard var island = controller.island else { return }
        change(&island)
        controller.set(island)
    }

    var body: some View {
        InspectorSection(title: "Island") {
            if !isThisDocument {
                Text("The island hangs under the notch. There is one of them — it is a place, not a thing you can have several of. Use overlays when you want many.")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textDim)
                    .fixedSize(horizontal: false, vertical: true)

                if doc.family != .island {
                    Label("This is a \(doc.family.displayName.lowercased()) design. Make one with New widget ▸ Island for a shape that fits.",
                          systemImage: "info.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    controller.use(doc)
                } label: {
                    Label(controller.island == nil ? "Hang it under the notch"
                                                   : "Use this one instead",
                          systemImage: "arrow.up.to.line")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if let island = controller.island {
                HStack(spacing: 8) {
                    Toggle("", isOn: Binding(get: { island.isEnabled },
                                             set: { on in edit { $0.isEnabled = on } }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                    Text(island.isEnabled
                         ? (island.reveal == .always ? "On the notch" : "At the notch, on approach")
                         : "Off")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.text)
                    Spacer()
                    Button { controller.clear() } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless).foregroundStyle(Palette.textDim)
                        .accessibilityLabel("Remove from the island")
                }

                InspectorRow(label: "Shows") {
                    Picker("", selection: Binding(get: { island.reveal },
                                                  set: { r in edit { $0.reveal = r } })) {
                        ForEach(Island.Reveal.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                }
                Text(island.reveal.explanation)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textDim)
                    .fixedSize(horizontal: false, vertical: true)

                InspectorRow(label: "Expands to") {
                    Picker("", selection: Binding(
                        get: { island.expandedDocumentID ?? Self.none },
                        set: { id in edit { $0.expandedDocumentID = id == Self.none ? nil : id } })) {
                        Text("Nothing").tag(Self.none)
                        Divider()
                        ForEach(library.documents.filter { $0.id != doc.id }) { candidate in
                            Text(candidate.name).tag(candidate.id)
                        }
                    }
                    .labelsHidden()
                }

                Toggle(isOn: Binding(get: { island.expandOnHover },
                                     set: { on in edit { $0.expandOnHover = on } })) {
                    Text("Expand when the pointer is over it").font(.system(size: 11))
                }
                .toggleStyle(.checkbox)
                .disabled(island.expandedDocumentID == nil)

                InspectorRow(label: "Gap") {
                    NumberField(label: "Gap", value: Binding(get: { island.topGap },
                                                             set: { g in edit { $0.topGap = g } }),
                                range: 0...200, step: 2, format: "%.0f")
                    Text("points below the menu bar")
                        .font(.system(size: 10)).foregroundStyle(Palette.textDim)
                }

                InspectorRow(label: "Every") {
                    NumberField(label: "Seconds", value: Binding(get: { island.refresh },
                                                                 set: { r in edit { $0.refresh = r } }),
                                range: Island.refreshFloor...3600, step: 1, format: "%.0f")
                    Text("seconds").font(.system(size: 10)).foregroundStyle(Palette.textDim)
                }
            }
        }
    }

    private static let none = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
}
