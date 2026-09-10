import SwiftUI

/// The wallpaper, in the document inspector beside the other surfaces.
struct WallpaperSection: View {
    @Environment(WallpaperController.self) private var controller
    let doc: WidgetDoc

    private var isThisDocument: Bool { controller.wallpaper?.documentID == doc.id }

    private func edit(_ change: (inout Wallpaper) -> Void) {
        guard var wallpaper = controller.wallpaper else { return }
        change(&wallpaper)
        controller.set(wallpaper)
    }

    var body: some View {
        InspectorSection(title: "Wallpaper") {
            if !isThisDocument {
                Text("Draw this design into the desktop picture itself. It sits behind everything, costs nothing to keep on screen, and cannot be clicked — the trade for being the desktop rather than sitting on it.")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textDim)
                    .fixedSize(horizontal: false, vertical: true)

                // Said before anything changes, because "I can undo this" is
                // only worth hearing in advance.
                if controller.canRestoreCurrent {
                    Label("Your current wallpaper is remembered before the first change, and put back when you turn this off.",
                          systemImage: "arrow.uturn.backward")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textDim.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Label("Your current wallpaper's file is not on disk — macOS is showing an image it kept after the file went away. It cannot be put back, so note what it is before you switch.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    Button { controller.use(doc) } label: {
                        Label(controller.wallpaper == nil ? "Make it the wallpaper" : "Use this one instead",
                              systemImage: "photo")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    // Look before you commit your desktop to it.
                    Button {
                        Task {
                            controller.stage(doc)
                            if let url = await controller.preview() {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    } label: {
                        Label("Preview", systemImage: "eye")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else if let wallpaper = controller.wallpaper {
                HStack(spacing: 8) {
                    Toggle("", isOn: Binding(get: { wallpaper.isEnabled },
                                             set: { on in edit { $0.isEnabled = on } }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                    Text(wallpaper.isEnabled ? "On the desktop picture" : "Off")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.text)
                    Spacer()
                    Button { Task { await controller.render() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless).foregroundStyle(Palette.textDim)
                        .accessibilityLabel("Stop using this as the wallpaper")
                    .help("Redraw it now")
                    .accessibilityLabel("Redraw the wallpaper now")
                    Button { controller.clear() } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless).foregroundStyle(Palette.textDim)
                }

                InspectorRow(label: "Where") {
                    Picker("", selection: Binding(get: { wallpaper.position },
                                                  set: { p in edit { $0.position = p } })) {
                        ForEach(Wallpaper.Position.allCases, id: \.self) { position in
                            Text(position.displayName).tag(position)
                        }
                    }
                    .labelsHidden()
                }

                InspectorRow(label: "Size") {
                    NumberField(label: "Scale", value: Binding(get: { wallpaper.scale },
                                                               set: { s in edit { $0.scale = s } }),
                                range: 1...10, step: 0.5, format: "%.1f")
                    Text("× \(Int(doc.family.referenceSize.width))×\(Int(doc.family.referenceSize.height))")
                        .font(.system(size: 10)).foregroundStyle(Palette.textDim)
                }

                Toggle(isOn: Binding(get: { wallpaper.extendsBackdrop },
                                     set: { on in edit { $0.extendsBackdrop = on } })) {
                    Text("Fill the screen with the design's own backdrop").font(.system(size: 11))
                }
                .toggleStyle(.checkbox)

                InspectorRow(label: "Every") {
                    NumberField(label: "Seconds",
                                value: Binding(get: { wallpaper.refresh },
                                               set: { r in edit { $0.refresh = r } }),
                                range: Wallpaper.refreshFloor...3600, step: 10, format: "%.0f")
                    Text("seconds").font(.system(size: 10)).foregroundStyle(Palette.textDim)
                }

                Text("Thirty seconds is the floor. Each redraw renders a screen-sized image and asks the window server to swap the desktop picture — that is not what a ticking clock should be built on, and an overlay is.")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textDim.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)

                if controller.hasOriginal {
                    Button { controller.restore() } label: {
                        Label("Put my wallpaper back", systemImage: "arrow.uturn.backward")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if let error = controller.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
