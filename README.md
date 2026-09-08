# Fathom

A macOS app for building your own widgets. Design one, bind it to live data,
mount it on the desktop.

Not started yet — **[SPEC.md](SPEC.md) is the build brief**, written to be read
cold.

## The short version

iOS gives a widget roughly 40–70 timeline reloads a day, which is why every iOS
widget builder shows stale data. **macOS has no equivalent budget** — measured
at a flat 64-second floor, 72 reloads an hour, with no decay. A Mac widget can
therefore show data that is at most a minute old, indefinitely, which is a thing
no iOS widget builder can offer at any price.

Fathom is what that finding is for.

Swift and SwiftUI, macOS 26 Tahoe or later. **Free forever — every feature, no
paid tier, no Pro version**, the same promise Helm makes. No telemetry, no accounts, no network calls except the ones your own
widget makes.
