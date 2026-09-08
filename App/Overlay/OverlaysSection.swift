import SwiftUI

/// The overlays showing this document, and their settings.
///
/// Deliberately beside the widget-slot control rather than hidden somewhere
/// else: they are two ways of putting the same design on screen, and the
/// difference between them is worth seeing in one place.
struct OverlaysSection: View {
    @Environment(OverlayController.self) private var controller
    let doc: WidgetDoc

    private var mine: [Overlay] { controller.overlays(for: doc.id) }

    var body: some View {
        InspectorSection(title: "Overlays") {
            if mine.isEmpty {
                Text("An overlay is a window Fathom draws itself — any size, anywhere, refreshing as often as you like. It is not a widget, so the 64-second floor does not apply.")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(mine) { overlay in
                OverlayRow(overlay: overlay)
                if overlay.id != mine.last?.id {
                    Divider().overlay(Palette.hairline).padding(.vertical, 3)
                }
            }

            Button {
                _ = controller.add(for: doc)
            } label: {
                Label("Put one on screen", systemImage: "plus.rectangle.on.rectangle")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

private struct OverlayRow: View {
    @Environment(OverlayController.self) private var controller
    let overlay: Overlay

    private func edit(_ change: (inout Overlay) -> Void) {
        var copy = overlay
        change(&copy)
        controller.update(copy)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Toggle("", isOn: Binding(get: { overlay.isEnabled },
                                         set: { on in edit { $0.isEnabled = on } }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                Text("\(Int(overlay.width)) × \(Int(overlay.height))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.text)
                Spacer()
                Button {
                    controller.remove(overlay.id)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Palette.textDim)
                .help("Take it off screen")
            }

            InspectorRow(label: "Layer") {
                Picker("", selection: Binding(get: { overlay.level },
                                              set: { level in edit { $0.level = level } })) {
                    ForEach(Overlay.Level.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
            }
            Text(overlay.level.explanation)
                .font(.system(size: 9))
                .foregroundStyle(Palette.textDim.opacity(0.85))
                .padding(.leading, 70)

            InspectorRow(label: "Size") {
                NumberField(label: "W", value: Binding(get: { overlay.width },
                                                       set: { w in edit { $0.width = w } }),
                            range: 60...2000, step: 10, format: "%.0f")
                NumberField(label: "H", value: Binding(get: { overlay.height },
                                                       set: { h in edit { $0.height = h } }),
                            range: 40...2000, step: 10, format: "%.0f")
            }

            InspectorRow(label: "Every") {
                NumberField(label: "Seconds", value: Binding(get: { overlay.refresh },
                                                             set: { r in edit { $0.refresh = r } }),
                            range: Overlay.refreshFloor...3600, step: 1, format: "%.0f")
                Text("seconds")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textDim)
            }

            InspectorRow(label: "Opacity") {
                Slider(value: Binding(get: { overlay.opacity },
                                      set: { o in edit { $0.opacity = o } }), in: 0.15...1)
                Text(String(format: "%.0f%%", overlay.opacity * 100))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Palette.textDim)
                    .frame(width: 34, alignment: .trailing)
            }

            Toggle(isOn: Binding(get: { overlay.clickThrough },
                                 set: { on in edit { $0.clickThrough = on } })) {
                Text("Let clicks pass through")
                    .font(.system(size: 11))
            }
            .toggleStyle(.checkbox)

            Text(overlay.clickThrough
                 ? "You will not be able to drag it while this is on."
                 : "Drag it anywhere on screen; it remembers where.")
                .font(.system(size: 9))
                .foregroundStyle(Palette.textDim.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
