import SwiftUI

/// Change the colours of a design without rebuilding it.
///
/// The picker is the feature; the sentence box is a convenience on top of it.
/// That order matters — restyling must work on a Mac with no Apple
/// Intelligence, so the model is never in the path of the plain action.
struct PaletteSection: View {
    @Bindable var model: EditorModel

    @State private var mood = ""
    @State private var thinking = false
    @State private var failure: String?

    var body: some View {
        InspectorSection(title: "Palette") {
            InspectorRow(label: "Colours") {
                Picker("", selection: Binding(
                    get: { Restyle.currentTheme(of: model.doc)?.id ?? "" },
                    set: { id in model.restyle(to: Theme.named(id)) })) {
                    // Only present when the current palette is unknown — a
                    // hand-made design wearing no catalogue theme. Selecting a
                    // real one replaces it and this disappears.
                    if Restyle.currentTheme(of: model.doc) == nil {
                        Text("Custom").tag("")
                    }
                    ForEach(Theme.all) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }
                .labelsHidden()
            }

            if Intelligence.status.isReady {
                HStack(spacing: 6) {
                    TextField("warmer, black and white…", text: $mood)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                        .onSubmit(choose)
                    Button(action: choose) {
                        if thinking {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "sparkles").font(.system(size: 10))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(mood.trimmingCharacters(in: .whitespaces).isEmpty || thinking)
                }

                Text("Chosen on this Mac. The model picks one palette from the twenty; the recolouring is ordinary code.")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textDim.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func choose() {
        let asked = mood.trimmingCharacters(in: .whitespaces)
        guard !asked.isEmpty, !thinking else { return }
        thinking = true
        failure = nil
        Task { @MainActor in
            defer { thinking = false }
            do {
                model.restyle(to: try await Intelligence.palette(for: asked))
                mood = ""
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}
