import SwiftUI
import UniformTypeIdentifiers

/// Exporting a widget, and importing one somebody sent you.
@MainActor
enum Sharing {

    static func export(_ doc: WidgetDoc) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = DocumentTransfer.suggestedFilename(for: doc)
        panel.allowedContentTypes = [.fathomDocument]
        panel.canCreateDirectories = true
        panel.message = "Anyone you send this to will be shown what it contacts before it runs."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try DocumentTransfer.data(for: doc).write(to: url, options: .atomic)
        } catch {
            present(error: "Could not write that file.", detail: error.localizedDescription)
        }
    }

    /// Returns what was chosen, for the caller to show a disclosure sheet
    /// about. Nothing is added here — importing is two steps on purpose.
    static func chooseFile() -> DocumentTransfer.Inspection? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.fathomDocument]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a widget somebody sent you."

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            return try DocumentTransfer.inspect(contentsOf: url)
        } catch {
            present(error: "That is not a widget Fathom can read.",
                    detail: error.localizedDescription)
            return nil
        }
    }

    private static func present(error: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = error
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.runModal()
    }
}

extension UTType {
    static let fathomDocument = UTType(exportedAs: "com.devshakib.fathom.widget",
                                       conformingTo: .json)
}

/// What a document will do, shown before it is added.
///
/// The list is not decoration. A widget can call a URL every minute and read
/// your calendar, and the only honest moment to say so is before you agree to
/// it — from the file, without running it.
struct ImportSheet: View {
    let inspection: DocumentTransfer.Inspection
    var onAdd: (WidgetDoc) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var data = ResolvedData()

    var body: some View {
        VStack(spacing: 0) {
            preview
            Divider().overlay(Palette.hairline)
            ScrollView { disclosure.padding(20) }.frame(maxHeight: 260)
            Divider().overlay(Palette.hairline)
            buttons
        }
        .frame(width: 460)
        .background(Palette.background)
        .task {
            // Resolved with placeholders so nothing is fetched before the
            // person has agreed to it. A preview that contacted the endpoint
            // would defeat the whole point of asking.
            data = ResolvedData(placeholders: true)
        }
    }

    private var preview: some View {
        let size = inspection.doc.family.referenceSize
        return ZStack {
            LinearGradient(colors: [Palette.surface, Palette.background],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            ZStack {
                inspection.doc.background.swatch
                WidgetCanvas(doc: inspection.doc, data: data)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: WidgetDoc.Family.cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
        }
        .frame(height: size.height + 70)
    }

    @ViewBuilder
    private var disclosure: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(inspection.doc.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Text("\(inspection.doc.family.displayName) · \(inspection.elementCount) elements")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textDim)
            }

            if inspection.isInert {
                row("checkmark.seal.fill", Palette.accent,
                    "This widget contacts nothing and reads nothing personal.")
            }

            ForEach(inspection.hosts, id: \.self) { host in
                row("globe", Palette.accentAlt,
                    "Will contact **\(host)** every time it refreshes.")
            }

            ForEach(inspection.permissions, id: \.self) { permission in
                row("lock.fill", .orange,
                    "Wants to read your **\(permission.displayName.lowercased())**. You will be asked separately.")
            }

            if !inspection.missingFonts.isEmpty {
                row("textformat", Palette.textDim,
                    "Uses \(inspection.missingFonts.joined(separator: ", ")), which this Mac does not have. It will draw in the system font.")
            }

            if inspection.isFromNewerVersion {
                row("exclamationmark.triangle.fill", .orange,
                    "Made by a newer version of Fathom. Parts of it may not draw correctly here.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ symbol: String, _ tint: Color, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 16)
            Text(.init(text))
                .font(.system(size: 11))
                .foregroundStyle(Palette.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var buttons: some View {
        HStack {
            Button("Cancel") { dismiss() }
            Spacer()
            Button(inspection.isInert ? "Add it" : "Add it anyway") {
                onAdd(inspection.doc)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.accent)
        }
        .padding(16)
    }
}
