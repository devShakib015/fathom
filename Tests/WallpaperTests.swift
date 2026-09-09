import Testing
import Foundation

/// The desktop picture host.
///
/// The failure that matters here is not a wallpaper that looks wrong — that is
/// visible. It is one that cannot be undone, or one that silently stops
/// updating because macOS caches the desktop picture by URL.
@Suite("Wallpaper")
struct WallpaperTests {

    @Test("a new wallpaper is big, centred and above the refresh floor")
    func defaults() {
        let wallpaper = Wallpaper(documentID: UUID())
        #expect(wallpaper.isEnabled)
        #expect(wallpaper.position == .centre)
        // Looked at from across a room, so the useful range starts well above 1.
        #expect(wallpaper.scale > 1)
        #expect(wallpaper.refresh >= Wallpaper.refreshFloor)
    }

    @Test("the floor is far higher than a window's")
    func floor() {
        // Each redraw renders a screen-sized PNG and asks the window server to
        // swap the desktop picture. An overlay refreshes sixty times faster
        // because an overlay is a window and this is not.
        #expect(Wallpaper.refreshFloor > Overlay.refreshFloor)
        #expect(Wallpaper.refreshFloor >= 30)
    }

    @Test("every position resolves inside the screen")
    func positions() {
        for position in Wallpaper.Position.allCases {
            let (x, y) = position.alignment
            #expect(x > 0 && x < 1)
            #expect(y > 0 && y < 1)
        }
    }

    @Test("centre is actually centred")
    func centre() {
        let (x, y) = Wallpaper.Position.centre.alignment
        #expect(x == 0.5)
        #expect(y == 0.5)
    }

    @Test("corners are on the side they claim")
    func corners() {
        #expect(Wallpaper.Position.topLeading.alignment.x < 0.5)
        #expect(Wallpaper.Position.topTrailing.alignment.x > 0.5)
        // Screen fractions here are measured from the top, matching SwiftUI's
        // .position, so "top" is the smaller y.
        #expect(Wallpaper.Position.topLeading.alignment.y < 0.5)
        #expect(Wallpaper.Position.bottomLeading.alignment.y > 0.5)
    }

    @Test("a record missing every optional field still decodes")
    func decodesOldRecords() throws {
        let json = #"{"documentID":"5B1F0F1A-0000-4000-A000-0000000000A1"}"#
        let wallpaper = try JSONDecoder().decode(Wallpaper.self, from: Data(json.utf8))
        #expect(wallpaper.isEnabled)
        #expect(wallpaper.position == .centre)
        #expect(wallpaper.refresh == Wallpaper.defaultRefresh)
    }

    @Test("a wallpaper round-trips")
    func roundTrip() throws {
        var wallpaper = Wallpaper(documentID: UUID())
        wallpaper.position = .bottomTrailing
        wallpaper.scale = 4.5
        wallpaper.extendsBackdrop = false
        let back = try JSONDecoder().decode(
            Wallpaper.self, from: try JSONEncoder().encode(wallpaper))
        #expect(back == wallpaper)
    }

    @Test("a remembered original must be a file that exists")
    func originalMustExist() {
        // macOS keeps showing a wallpaper whose file has been deleted — it
        // holds the image, not the path — so desktopImageURL can name a file
        // that is not there. Recording it anyway produces an app that offers to
        // restore your wallpaper and then cannot, after replacing it.
        let missing = URL(fileURLWithPath: "/Users/nobody/gone-\(UUID().uuidString).jpg")
        #expect(!WallpaperStore.shared.rememberOriginal(missing))
    }

    @Test("a real file is accepted as an original")
    func realFileRemembered() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fathom-wallpaper-\(UUID().uuidString).png")
        try Data("not really a png".utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        #expect(WallpaperStore.shared.rememberOriginal(tmp))
        WallpaperStore.shared.forgetOriginal()
    }
}
