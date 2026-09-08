import SwiftUI

/// The document, drawn at its real size, on something that suggests a desktop.
///
/// Same `WidgetCanvas` the extension runs. Not a redrawn approximation — if
/// this and the placed widget ever diverge, the preview is worse than useless,
/// so there is deliberately no second rendering path to diverge from.
struct WidgetStage: View {
    let doc: WidgetDoc
    let data: ResolvedData

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PREVIEW")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.textDim)
                .tracking(0.8)

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [Palette.surface, Palette.background],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Palette.hairline, lineWidth: 1))

                widget
                    .padding(40)
            }
            .frame(height: doc.family.referenceSize.height + 80)
            .frame(maxWidth: .infinity)
        }
    }

    private var widget: some View {
        let size = doc.family.referenceSize
        return ZStack {
            doc.background.swatch
            WidgetCanvas(doc: doc, data: data)
        }
        .frame(width: size.width, height: size.height)
        // Widgets are 2/9 of their width on macOS Tahoe; matching it makes the
        // preview a size reference as well as a content one.
        .clipShape(RoundedRectangle(cornerRadius: WidgetDoc.Family.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WidgetDoc.Family.cornerRadius, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 22, y: 10)
    }
}

/// What the document declares, and what it actually resolved to just now.
///
/// The hosts row exists because sharing is designed for now and shipped later:
/// the moment a widget can arrive from someone else, "what will this contact?"
/// has to be answerable before it runs, and the habit of showing it starts
/// here rather than being retrofitted.
struct FactsPanel: View {
    let doc: WidgetDoc
    let data: ResolvedData
    let isResolving: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("DATA")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.textDim)
                .tracking(0.8)

            VStack(spacing: 0) {
                ForEach(doc.sources) { source in
                    sourceRow(source)
                    if source.id != doc.sources.last?.id {
                        Divider().overlay(Palette.hairline)
                    }
                }
            }
            .background(Palette.surface.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Palette.hairline, lineWidth: 1))

            boundValues
        }
    }

    private func sourceRow(_ source: DataSource) -> some View {
        HStack(spacing: 10) {
            Image(systemName: source.kind == .system ? "cpu" : "globe")
                .foregroundStyle(Palette.accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.text)
                Text(source.host ?? (source.kind == .system ? "Local, never leaves this Mac" : "No URL set"))
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textDim)
            }
            Spacer()
            if isResolving {
                ProgressView().controlSize(.small)
            } else if let failure = data.failures[source.id] {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            } else if data.trees[source.id] != nil {
                Label(data.isStale ? "Cached" : "Live", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(data.isStale ? Palette.textDim : Palette.accent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// Every binding in the document with the string it resolves to right now.
    /// This is the part that makes a wrong key path obvious in one glance
    /// instead of after a trip to the desktop and a 64-second wait.
    private var boundValues: some View {
        let bound = doc.elements.filter { $0.binding != nil }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(bound) { element in
                HStack(spacing: 10) {
                    Text(element.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.text)
                        .frame(width: 110, alignment: .leading)
                    Text(element.binding?.keyPath ?? "")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Palette.textDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(data.text(for: element))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(resolves(element) ? Palette.accent : .orange)
                        .monospacedDigit()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Palette.surface.opacity(0.28))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Palette.hairline, lineWidth: 1))
    }

    private func resolves(_ element: Element) -> Bool {
        guard let binding = element.binding else { return true }
        return data.value(for: binding) != nil
    }
}
