import SwiftUI

/// About Fathom.
///
/// Three things the brief requires be said here rather than discovered: that
/// every feature is free permanently, that the app is not notarised and what
/// that means on first launch, and what does and does not leave the Mac.
///
/// The last of those is answered from the user's actual documents rather than
/// in general terms. An app can claim it makes no unrequested network calls;
/// Fathom can list the hosts your own widgets will contact, which is a claim
/// you can check.
struct AboutView: View {
    @Environment(Library.self) private var library

    private var hosts: [String] {
        Array(Set(library.documents.flatMap(\.declaredHosts))).sorted()
    }

    private var storage = StoreDiagnosis.current()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                masthead
                pledge
                unsigned
                privacy
                colophon
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.background)
        .frame(width: 460, height: 620)
    }

    // MARK: - Masthead

    private var masthead: some View {
        HStack(alignment: .top, spacing: 16) {
            // The real icon, not a stand-in drawn to look like it. An About
            // screen showing something the Dock does not is a small lie.
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 5) {
                Text(AppInfo.name)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Text(AppInfo.tagline)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Version \(AppInfo.version) (\(AppInfo.build)) · \(AppInfo.systemRequirement)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Palette.textDim.opacity(0.75))
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - The promise

    private var pledge: some View {
        Section(title: "Free forever", tint: Palette.accent) {
            Text(AppInfo.freePledge)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)

            Text("""
                Fathom is 100% free, with every feature included, permanently. No paid tier. \
                No “pro” version. No subscription, no trial, no locked features, no upsell, \
                no ads, no accounts. Everything in the app you download is yours, and always \
                will be — that is a commitment, not an introductory offer.
                """)
                .font(.system(size: 11))
                .foregroundStyle(Palette.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Not notarised

    private var unsigned: some View {
        Section(title: "Why macOS warned about Fathom", tint: .orange) {
            Text("""
                Fathom is not notarised. Notarisation requires Apple's $99-a-year developer \
                programme, and Fathom is free, so it ships unsigned instead. macOS therefore \
                refuses to open it the first time.
                """)
                .font(.system(size: 11))
                .foregroundStyle(Palette.textDim)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                step(1, "Move Fathom to your Applications folder.")
                step(2, "Try to open it. macOS will refuse.")
                step(3, "Open System Settings ▸ Privacy & Security, scroll down to Security, and click Open Anyway.")
                step(4, "Open Fathom again and confirm.")
            }

            Text("You only do this once. It is the same for every app not signed with a paid Apple account, and it is the honest trade for an app that costs nothing.")
                .font(.system(size: 10))
                .foregroundStyle(Palette.textDim.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Text("\(number)")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.background)
                .frame(width: 14, height: 14)
                .background(Palette.textDim, in: Circle())
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Palette.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - What leaves this Mac

    private var privacy: some View {
        Section(title: "What leaves this Mac", tint: Palette.accentAlt) {
            Text("""
                No telemetry. No analytics. No accounts. No crash reporting. Fathom never \
                contacts a server of its own, and there is no server of its own to contact.
                """)
                .font(.system(size: 11))
                .foregroundStyle(Palette.textDim)
                .fixedSize(horizontal: false, vertical: true)

            Text("The only outbound requests are the ones your widgets make. Right now that is:")
                .font(.system(size: 11))
                .foregroundStyle(Palette.textDim)
                .fixedSize(horizontal: false, vertical: true)

            if hosts.isEmpty {
                Label("Nothing. None of your widgets contacts anything.",
                      systemImage: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.accent)
            } else {
                ForEach(hosts, id: \.self) { host in
                    Label(host, systemImage: "globe")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Palette.accentAlt)
                        .textSelection(.enabled)
                }
            }

            Text("Widget generation runs on this Mac using Apple's on-device models. Nothing you type is sent anywhere.")
                .font(.system(size: 10))
                .foregroundStyle(Palette.textDim.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(Palette.hairline).padding(.vertical, 2)

            Text("Your widgets are plain JSON files here:")
                .font(.system(size: 10))
                .foregroundStyle(Palette.textDim)
            Text(storage.containerPath)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Palette.textDim.opacity(0.75))
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }

    // MARK: - Colophon

    private var colophon: some View {
        Section(title: "Made by", tint: Palette.textDim) {
            VStack(alignment: .leading, spacing: 2) {
                Text(AppInfo.author)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.text)
                Text("\(AppInfo.authorHandle) · \(AppInfo.authorRole)")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textDim)
            }

            HStack(spacing: 14) {
                ForEach(AppInfo.authorLinks, id: \.label) { link in
                    // No force unwrap. These are constants and they parse
                    // today, but a typo in AppInfo would crash the About window
                    // rather than show one dead link — the worst possible
                    // trade for four characters saved.
                    if let url = URL(string: link.url) {
                        Link(link.label, destination: url)
                            .font(.system(size: 11))
                    }
                }
            }
            .foregroundStyle(Palette.accent)

            HStack(spacing: 14) {
                externalLink("Source code", AppInfo.repo)
                externalLink("Releases", AppInfo.releases)
                externalLink("Report a problem", AppInfo.issues)
            }
            .font(.system(size: 11))
            .foregroundStyle(Palette.accent)

            Text("\(AppInfo.license) · \(AppInfo.copyright)")
                .font(.system(size: 10))
                .foregroundStyle(Palette.textDim.opacity(0.8))
                .padding(.top, 2)
        }
    }

    /// Named `externalLink` rather than `link`: the short name resolves to
    /// POSIX `link(2)` when it is not in scope, so a helper in the wrong type
    /// fails with a message about Int32 rather than about being missing.
    @ViewBuilder private func externalLink(_ label: String, _ address: String) -> some View {
        if let url = URL(string: address) { Link(label, destination: url) }
    }
}

/// A titled block, so every section of the About screen has the same rhythm.
private struct Section<Content: View>: View {
    let title: String
    let tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5).fill(tint).frame(width: 3, height: 11)
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tint)
                    .tracking(0.9)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
