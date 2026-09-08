# Fathom

A macOS app for building your own widgets. Design one, bind it to live data,
mount it on the desktop.

**[SPEC.md](SPEC.md) is the build brief**, written to be read cold.

## The short version

iOS gives a widget roughly 40–70 timeline reloads a day, which is why every iOS
widget builder shows stale data. **macOS has no equivalent budget** — measured
at a flat 64-second floor, with no decay. A Mac widget can therefore show data
that is at most a minute old, indefinitely, which is a thing no iOS widget
builder can offer at any price.

Fathom is what that finding is for.

Swift and SwiftUI, macOS 26 Tahoe or later. **Free forever — every feature, no
paid tier, no Pro version**, the same promise Helm makes. No telemetry, no
accounts, no network calls except the ones your own widget makes.

## Status

Early. The universal widget extension renders a stored document end to end:
six primitives, a binding system, and the system data source. The editor is
next.

## How it works

You cannot compile a widget per user — WidgetKit extensions are compiled
SwiftUI and macOS will not load code at runtime. So a Fathom widget is *data*:
a document of positioned elements with styles and data bindings, which one
universal extension reads and interprets on every reload.

```
Fathom.app ──writes──▶  App Group container  ◀──reads── FathomWidget.appex
   editor                  *.fathom (JSON)              interprets + draws
```

## Building

Needs [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `project.yml` is the
source of truth and the `.xcodeproj` is generated and gitignored.

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project Fathom.xcodeproj -scheme Fathom -configuration Release \
  -derivedDataPath build -allowProvisioningUpdates \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=<your team> build
```

Widget extensions must be sandboxed or macOS silently refuses to register them,
and the app and the extension can only share state through an App Group. Both
are already set up in `project.yml`; `SPEC.md` §6 explains what happens if you
change them.

## Installing a release

Fathom is not notarised. Notarisation requires Apple's $99/year programme and
Fathom is free, so macOS will refuse to open it on first launch.

1. Move **Fathom.app** to `/Applications`.
2. Try to open it. macOS will refuse.
3. **System Settings ▸ Privacy & Security**, scroll to Security, click
   **Open Anyway** next to the message about Fathom.
4. Open it again and confirm.

You only do this once.

## Licence

MIT. Every feature, free, forever.
