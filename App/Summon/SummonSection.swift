import SwiftUI
import Carbon.HIToolbox

/// The summoned panel, in the document inspector beside the other surfaces.
struct SummonSection: View {
    @Environment(SummonController.self) private var controller
    let doc: WidgetDoc

    @State private var recording = false

    private var isThisDocument: Bool { controller.summon?.documentID == doc.id }

    private func edit(_ change: (inout Summon) -> Void) {
        guard var summon = controller.summon else { return }
        change(&summon)
        controller.set(summon)
    }

    var body: some View {
        InspectorSection(title: "Summon") {
            if !isThisDocument {
                Text("Call this design up with a keystroke, anywhere, and let it go again. Nothing is on screen until you ask, and nothing refreshes while it is away — so this is where a design too big to leave out belongs.")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textDim)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    controller.use(doc)
                } label: {
                    Label(controller.summon == nil ? "Bind it to a key" : "Use this one instead",
                          systemImage: "command")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if let summon = controller.summon {
                HStack(spacing: 8) {
                    Toggle("", isOn: Binding(get: { summon.isEnabled },
                                             set: { on in edit { $0.isEnabled = on } }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                    Text(summon.isEnabled ? "On \(summon.hotKey.displayName)" : "Off")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.text)
                    Spacer()
                    Button { controller.toggle() } label: { Image(systemName: "eye") }
                        .buttonStyle(.borderless).foregroundStyle(Palette.textDim)
                        .accessibilityLabel("Remove the hotkey")
                        .help("Show it now")
                    Button { controller.clear() } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless).foregroundStyle(Palette.textDim)
                }

                InspectorRow(label: "Key") {
                    HotKeyField(hotKey: summon.hotKey, recording: $recording) { key in
                        edit { $0.hotKey = key }
                    }
                }

                if controller.registrationFailed {
                    Label("macOS refused \(summon.hotKey.displayName) — something else already uses it. Pick another.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                InspectorRow(label: "Appears") {
                    Picker("", selection: Binding(get: { summon.placement },
                                                  set: { p in edit { $0.placement = p } })) {
                        ForEach(Summon.Placement.allCases, id: \.self) { placement in
                            Text(placement.displayName).tag(placement)
                        }
                    }
                    .labelsHidden()
                }

                InspectorRow(label: "Size") {
                    NumberField(label: "Scale", value: Binding(get: { summon.scale },
                                                               set: { s in edit { $0.scale = s } }),
                                range: 1...6, step: 0.25, format: "%.2f")
                    Text("× \(Int(doc.family.referenceSize.width))×\(Int(doc.family.referenceSize.height))")
                        .font(.system(size: 10)).foregroundStyle(Palette.textDim)
                }

                Toggle(isOn: Binding(get: { summon.dismissOnBlur },
                                     set: { on in edit { $0.dismissOnBlur = on } })) {
                    Text("Dismiss when you click elsewhere").font(.system(size: 11))
                }
                .toggleStyle(.checkbox)

                InspectorRow(label: "Every") {
                    NumberField(label: "Seconds", value: Binding(get: { summon.refresh },
                                                                 set: { r in edit { $0.refresh = r } }),
                                range: Summon.refreshFloor...3600, step: 1, format: "%.0f")
                    Text("seconds, while open").font(.system(size: 10)).foregroundStyle(Palette.textDim)
                }

                Text("Escape closes it. The panel takes no permissions — the key is registered with the system, not read from your keyboard.")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textDim.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Press the keys you want, rather than pick them from a list.
private struct HotKeyField: View {
    let hotKey: HotKey
    @Binding var recording: Bool
    var onChange: (HotKey) -> Void

    @State private var monitor: Any?

    var body: some View {
        Button {
            recording.toggle()
            recording ? listen() : stop()
        } label: {
            Text(recording ? "Press keys…" : hotKey.displayName)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .frame(minWidth: 70)
                .padding(.vertical, 3)
                .background(recording ? Palette.accent.opacity(0.25) : Palette.hairline.opacity(0.6),
                            in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.text)
        .onDisappear(perform: stop)
    }

    private func listen() {
        // Local, not global: this only needs to see keys while Fathom's own
        // window is focused, which needs no permission at all.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let key = HotKey.from(keyCode: event.keyCode, flags: event.modifierFlags)
            guard key.isUsable, HotKey.keyNames[key.keyCode] != nil else { return event }
            onChange(key)
            recording = false
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
