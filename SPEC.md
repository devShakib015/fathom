# Fathom — build brief

A macOS app for **building your own widgets**: design one, bind it to live data,
mount it on the desktop. Plus a library of ready-made ones to start from.

This document is written to be read cold. If you are an agent picking this up
with no other context, everything you need to start is here, including the
measurement the whole product rests on and the four traps that will otherwise
each cost you an afternoon.

---

## 1. Why this can exist

On iOS, WidgetKit grants a widget roughly **40–70 timeline reloads a day**. That
is why every iOS widget builder — Widgy, WidgetSmith — shows stale data. It is
not a quality problem; it is a platform ceiling, and no amount of good
engineering gets past it.

**macOS has no such budget.** This was measured on 8 September 2026, not assumed:
a widget extension asked to reload every 15 seconds and logged every call the
system actually made.

```
11:21:01  +63.9s
11:22:05  +64.0s
11:23:09  +64.1s
11:24:13  +64.1s
11:25:17  +64.2s
11:26:21  +64.0s
11:27:25  +64.1s
```

Over a full hour, 54 intervals: **min 63.9 s, max 64.7 s, mean 64.15 s.** The
distribution has no tail at all — 51 gaps at 64 s, 3 at 65 s, nothing else. Split
into quarters the medians are 64.1, 64.2, 64.1, 64.1.

macOS ignored the 15-second request, substituted its own floor, and then honoured
that floor exactly. **A budget makes the gap climb** as the allowance burns down;
this one does not move. It is a fixed minimum interval — about **58–72 reloads an
hour against iOS's two**, and it does not decay.

The probe is at `~/Projects/Personal/widget-reload-probe` (its own git repo, no
remote). `./analyse.sh` re-reads the log any time. **Re-run it before building
anything that assumes the number**, and if it ever shows the gap widening, this
product's premise is gone and you should say so loudly rather than build around
it.

Everything interesting about Fathom follows from that one number. A widget that
is at most 64 seconds stale is a different category of thing from a widget that
updates when iOS feels like it. Design for a **64-second floor**: no second
hands, no live tick charts, nothing that implies sub-minute precision.

---

## 2. Non-negotiables

These are settled. Do not relitigate them.

- **Swift and SwiftUI. Native.** Not Flutter, not Catalyst, not a web view. The
  owner asked specifically for the best macOS APIs rather than a portable
  subset. Use them: WidgetKit, App Intents, `containerBackground`, the Tahoe
  appearance modes.
- **macOS 26 (Tahoe) minimum.** Tahoe made desktop widgets first-class with
  Liquid Glass backgrounds and on-desktop placement. Targeting older releases
  costs the whole visual argument.
- **Free. MIT. Every feature.** No paid tier, no Pro version, no upgrade prompt.
  This is a standing promise across everything the owner ships and it belongs in
  the app's About screen, as it is in Helm's.
- **No telemetry, no accounts, no analytics, no network calls the user did not
  ask for.** The only outbound requests are the ones a user's own widget makes.
- **Distribution: unsigned, on GitHub Releases.** Notarisation needs the $99/yr
  programme and these apps are free, so first launch requires
  System Settings ▸ Privacy & Security ▸ Open Anyway. Say so plainly in the
  README and in the app — do not let people discover it.
- **Never add a `Co-Authored-By` trailer to a commit.** No exceptions.

---

## 3. The architecture is forced

You cannot compile a widget per user. WidgetKit extensions are compiled SwiftUI
and macOS will not load code at runtime. So:

> **One universal widget extension that interprets a design document.**

The user's widget is *data* — a tree of elements with positions, styles and data
bindings. The extension reads that document on every timeline entry and renders
it into SwiftUI. This is legal, it is how Widgy works, and it is the only shape
that can work.

The consequence, and it is the central product-design problem: **the
interpreter's vocabulary is the hard ceiling on what any user can ever build.**
"Any kind of widget" really means "any composition of the primitives you ship."
Get the primitive set right and the editor is easy. Get it wrong and no amount
of editor polish saves it. Spend your design effort there.

Widgets come in fixed families (`systemSmall`, `systemMedium`, `systemLarge`,
`systemExtraLarge`). A design document is authored for one family; support
scaling to others later, not in v1.

---

## 4. What v1 is

The v1 exists to prove the thesis, not to be the destination. Ship small.

**In:**

1. **One universal widget extension** rendering a stored design document.
2. **Six primitives**, no more: text, image/SF Symbol, rectangle/rounded rect,
   divider, progress arc, and a sparkline.
3. **A data binding system.** A widget element can show a literal, or a value
   pulled from a source by key path.
4. **Two data sources:** the system's own (date, time, battery, disk free) and
   **one arbitrary JSON endpoint** — the user gives a URL, Fathom fetches it,
   shows the parsed tree, and the user drags fields onto elements. That second
   one is where the no-budget finding actually cashes out and it is the reason
   anyone will care.
5. **An editor** — canvas, inspector, drag to position, snap to a grid.
6. **A small starter library**, maybe eight widgets, that a user can place and
   then open in the editor to see how it was made.

**Out of v1, explicitly:**

- Sharing or importing other people's widgets. That needs a portable format,
  an import path, and a moderation story the moment a widget can call a URL.
- Scripting or expressions. Tempting; it is a second product.
- iOS. The whole premise is macOS-only.
- Interactive widgets (App Intents / buttons). Add after the static case is good.

---

## 5. The design document

Shape it so it survives being extended. A rough starting point:

```swift
struct WidgetDoc: Codable {
    var id: UUID
    var name: String
    var family: WidgetFamily        // small | medium | large | extraLarge
    var background: Background      // colour | gradient | liquidGlass | none
    var elements: [Element]
    var sources: [DataSource]
    var minimumRefresh: TimeInterval // never below 64; the system floor
}

struct Element: Codable {
    var id: UUID
    var kind: Kind                  // text | symbol | shape | divider | arc | spark
    var frame: Frame                // relative to the family's unit box
    var style: Style                // font, weight, colour, opacity, corner
    var binding: Binding?           // nil = literal
}

struct Binding: Codable {
    var sourceID: UUID
    var keyPath: String             // "current.temperature_2m"
    var format: Format              // number(precision) | date(style) | text | percent
    var fallback: String            // what renders when the fetch failed
}
```

Two rules that will save you later:

- **Frames are relative, not absolute pixels.** Widget families have different
  point sizes across displays. Store 0…1 and multiply at render.
- **Every binding needs a `fallback`.** Networks fail and a widget that renders
  blank looks broken rather than offline.

Persist documents somewhere both the app and the extension can read. **That
means a real App Group** — see trap 3.

---

## 6. Four traps, each measured the hard way

These came out of building the probe. Every one produced a green build and a
silently broken result.

**1. macOS will not register an unsandboxed widget extension.** Build the
extension without `com.apple.security.app-sandbox` and it never appears in
`pluginkit -mAv -p com.apple.widgetkit-extension`, never appears in the widget
gallery, and emits no error anywhere. The sandbox is mandatory, not advisory.

**2. Manual signing with no provisioning profile silently strips entitlements.**
With `CODE_SIGN_STYLE=Manual` and no profile, `xcodebuild` *succeeds* and the
signed extension carries only `get-task-allow` — the sandbox entitlement you
wrote in the plist never arrives, so you hit trap 1 without knowing why. Use
automatic signing with a real team:

```
xcodebuild -allowProvisioningUpdates \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=VKN4MYB5ZW
```

Verify with `codesign -d --entitlements - --xml <appex> | plutil -p -` and
actually look at the output.

**3. A sandboxed extension's `homeDirectoryForCurrentUser` is its container.**
Not the real home. So a `temporary-exception.files.home-relative-path` for
`~/Library/…` never even applies, and anything you write lands in
`~/Library/Containers/<ext-bundle-id>/Data/…` where the host app cannot see it.
**Sharing state between the app and the extension requires an App Group** and
there is no way around it.

**4. Under the debugger, WidgetKit applies no limits at all.** Any timing you
measure from Xcode is fiction. Install to `/Applications`, launch with `open`,
and measure there.

Also: the embedded extension's bundle id must be prefixed with the host app's
full bundle id, or `ValidateEmbeddedBinary` fails the build.

---

## 7. Project setup

The probe used **XcodeGen** (`brew install xcodegen`) so the `.xcodeproj` is
generated and disposable — `project.yml` is the source of truth and merge
conflicts in pbxproj stop existing. Recommended; copy the working spec from
`~/Projects/Personal/widget-reload-probe/project.yml`, which already has the
sandbox, entitlements and bundle-id prefixing correct.

Two targets: the app and the widget extension. Later probably a third for a
shared framework holding the document model and the renderer, since both sides
need it.

---

## 8. Design language

Match the owner's site and Helm. Dark, restrained, one accent.

```
background   #060B0A
surface      #101E1A
accent       #3DDC97   (mint — the brand accent)
accent alt   #4FC3E8   (cyan, sparingly)
text         #E8F2EE
text dim     #9BB3AB
hairline     #0D1815
```

Look at Helm (`~/Projects/Personal/helm`) for the established feel: frameless
vibrancy window, traffic lights over a translucent sidebar, native SF Pro,
charts drawn by hand rather than pulled from a package. Fathom should read as
the same family.

---

## 9. Answered by the owner, 8 Sep 2026

All three came back at the ambitious end. These are now settled the same way
section 2 is.

1. **Arranger *and* builder, library as the on-ramp.** The canvas is freeform:
   add, delete, move, resize and restyle any primitive, bind any field. The
   eight library widgets exist to be opened and dissected, not just placed.
2. **Design the format for sharing; do not ship sharing.** No import/export UI
   in v1, but the document format carries `schemaVersion` from day one, is
   stable JSON with string-valued enums, and declares every host it will
   contact so a future importer can show them before anything is fetched.
3. **Paste a URL, browse the parsed tree, drag a leaf onto an element.** The
   full binding UI, including arrays and type-to-format inference. This is the
   demo that makes the no-budget finding visible, so it is not the part to trim.

---

## 10. Context worth having

- The owner is **K M Shahriar Hossain (devShakib)**, in **Dubai**. Flutter
  developer, CTO at Shpper. Everything he ships outside work is free and MIT.
- **Helm** (`~/Projects/Personal/helm`) is the sibling product — fifteen macOS
  tools in one window, launching on Product Hunt 9 Sep 2026. It is Flutter;
  Fathom is not, deliberately.
- He cares about accuracy in copy and will correct it. Do not invent job titles,
  version numbers, or feature claims.
- Work is verified rather than asserted: if you claim a thing works, show the
  measurement or the screenshot.
