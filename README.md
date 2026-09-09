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
Fathom.app ──writes──▶  /Users/Shared/Fathom/<uid>  ◀──reads── FathomWidget.appex
   editor                    *.fathom (JSON)                  interprets + draws
```

Not an App Group, deliberately. A group is bound to the signing team and an
unsigned build has no team, so an ad-hoc signed extension resolves the group
URL and is then denied the directory — silently, and only in the shipped
build. `SPEC.md` §6 trap 5 has the measurement.

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
and the shared store is a sandbox exception rather than an App Group. Both are
already set up in `project.yml`; `SPEC.md` §6 explains what happens if you
change them.

To ad-hoc sign a build for distribution, use the script rather than `codesign`
directly:

```bash
./Tools/sign.sh /path/to/Fathom.app
```

`codesign --force --deep --sign -` — the obvious command — replaces the
signature and silently drops every entitlement, including the sandbox the
extension needs in order to be registered at all. The app then installs,
launches and looks completely normal with no widgets available and no error
anywhere. `SPEC.md` §6 trap 8 has the measurement; the script signs inside out
with the right entitlements and reads the signature back to check.

## Tests

```bash
xcodebuild test -project Fathom.xcodeproj -scheme FathomTests -destination 'platform=macOS'
```

44 tests over the interpreter, the expression language, the JSON parser, format
inference, the document format and the element tree — the code where a
regression would be silent rather than loud. A widget that renders a slightly
wrong number every sixty-four seconds tells nobody anything.

## Installing a release

Fathom is not notarised. Notarisation requires Apple's $99/year programme and
Fathom is free, so macOS will refuse to open it on first launch.

1. Move **Fathom.app** to `/Applications`.
2. Try to open it. macOS will refuse.
3. **System Settings ▸ Privacy & Security**, scroll to Security, click
   **Open Anyway** next to the message about Fathom.
4. Open it again and confirm.

You only do this once.

**Updates ask for permissions again.** Fathom is ad-hoc signed, and macOS keys
privacy grants to an app's signature — which changes with every build. So a new
version starts over at "not asked" for location, calendar and reminders. Your
widgets and designs are untouched; only the permissions need granting again.
The only way around it is a paid Apple certificate, and Fathom is free.
`SPEC.md` §6 trap 9 has the measurement.

## Licence

MIT. Every feature, free, forever.
