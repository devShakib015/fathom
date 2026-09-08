import SwiftUI

/// "Describe a widget" — the on-device model, in the one place it belongs.
///
/// What it produces is a *choice*, not a document: a layout, a palette, a size
/// and a name, all validated against the catalog before anything is built. That
/// is why the result is shown in the same preview sheet as any other catalog
/// entry, and why it can be adjusted afterwards like any other widget. Nothing
/// here can produce something Fathom could not already draw.
struct DescribeWidgetBar: View {
    var onGenerated: (CatalogEntry) -> Void

    @State private var prompt = ""
    @State private var isThinking = false
    @State private var problem: String?
    @FocusState private var focused: Bool

    private var status: Intelligence.Status { Intelligence.status }

    private static let examples = [
        "a minimal clock in black and white",
        "battery and charge, warm colours",
        "the week's weather as bars",
        "how much disk I have left",
        "my next meeting, big and readable",
        "cpu and memory side by side",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(status.isReady ? Palette.accent : Palette.textDim)

                TextField(status.isReady ? "Describe a widget…" : "Describe a widget",
                          text: $prompt)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($focused)
                    .disabled(!status.isReady || isThinking)
                    .onSubmit(generate)

                if isThinking {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Build it", action: generate)
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.accent)
                        .controlSize(.small)
                        .disabled(!status.isReady || prompt.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(Palette.surface.opacity(0.65),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(status.isReady ? Palette.accent.opacity(0.28) : Palette.hairline, lineWidth: 1))

            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !status.isReady {
                // Never a dead end: Fathom is complete without this, and the
                // copy should say so rather than dangle a feature.
                Text(status.explanation)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 5) {
                    Text("On this Mac, nothing sent anywhere.")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textDim.opacity(0.85))
                    ForEach(Self.examples.prefix(2), id: \.self) { example in
                        Button("“\(example)”") { prompt = example; focused = true }
                            .buttonStyle(.plain)
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.accent.opacity(0.85))
                    }
                }
            }
        }
    }

    private func generate() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard status.isReady, !text.isEmpty, !isThinking else { return }
        isThinking = true
        problem = nil

        Task { @MainActor in
            defer { isThinking = false }
            do {
                let plan = try await Intelligence.plan(for: text)
                guard let entry = PlanMatcher.entry(for: plan) else {
                    problem = "Could not match that to a layout. Try naming what it should show."
                    return
                }
                onGenerated(entry)
            } catch {
                problem = error.localizedDescription
            }
        }
    }
}
