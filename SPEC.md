# Fathom — build brief

A macOS app for **building your own widgets**: design one, bind it to live data,
mount it on the desktop. Plus a library of ready-made ones to start from.

This document is written to be read cold. If you are an agent picking this up
with no other context, everything you need to start is here, including the
measurement the whole product rests on and the eight traps that will otherwise
each cost you an afternoon. Trap 8 is about the shipping step and was found
after everything else had already been verified — read §6 before you package
anything.

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

The probe kept running while Fathom was built, and at 1.31 hours and 83 reloads
the strongest statement is the simplest one: **the longest interval in the entire
run was 64.7 s.** A budget does not produce a tidy ceiling — it produces gaps that
grow into minutes and then hours. Across the 72 intervals not disturbed by an app
install, mean 63.99 s, sd 1.29 s, drift −0.73 s/hour.

The disturbed intervals are worth their own line, because they point the other
way. Installing and re-registering an app produced reloads at 4 s, 7 s and 11 s
spacing — *faster* than the floor, not slower. So the 64 s figure is a minimum
spacing on reloads a widget schedules for itself, not a cap on how many it may
have. `WidgetCenter.reloadAllTimelines()` is served immediately. The editor can
therefore push a change to the desktop the instant it is made, rather than making
the user wait out a tick to see their own edit.

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
6. ~~**A small starter library**, maybe eight widgets~~ — **superseded by
   section 9.4**: a generated catalog of a few thousand, any of which can be
   duplicated and edited.

**Out of v1, explicitly:**

- Sharing or importing other people's widgets. That needs a portable format,
  an import path, and a moderation story the moment a widget can call a URL.
- ~~Scripting or expressions.~~ **Moved in** — see section 9.4.
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

Persist documents somewhere both the app and the extension can read. Not an
App Group, however much it looks like the right answer — see trap 5.

---

## 6. Eight traps, each measured the hard way

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
Sharing state between the app and the extension needs a surface outside both
containers — but *not* an App Group, for the reason in trap 5.

Within that container, `~/Library/Logs` is restricted too. The probe only wrote
there because it carried a home-relative exception naming that exact directory;
without one, use `Library/Application Support`.

**4. Under the debugger, WidgetKit applies no limits at all.** Any timing you
measure from Xcode is fiction. Install to `/Applications`, launch with `open`,
and measure there.

**5. An App Group is bound to the signing team, and an unsigned build has no
team.** This is the one that would have sunk the product quietly. An App Group
identifier is team-prefixed, so for an ad-hoc signature macOS *resolves* the
group URL for the extension and then denies it the directory. Measured on
8 September 2026 with one identical binary and two signatures:

```
Development signed (TeamIdentifier=VKN4MYB5ZW)   container ok rw, 2 docs → renders
ad-hoc signed      (TeamIdentifier not set)      url ok, cannot read     → blank
```

The *host app* survives ad-hoc signing; the extension does not. So the failure
only appears in the shipped build, only on the widget, and
`containerURL(forSecurityApplicationGroupIdentifier:)` returning non-nil is not
evidence of anything — you have to try to list the directory.

Since Fathom ships unsigned, an App Group would mean every downloaded copy
showed empty widgets forever. Fathom therefore uses **`/Users/Shared/Fathom/<uid>`
with `temporary-exception.files.absolute-path.read-write`** on both targets,
which is not bound to a signing identity and works under both. Verified ad-hoc
signed, with no app-group entitlement present at all.

**6. WidgetKit's own cache knows the real widget sizes.** Do not guess them,
and do not carry the iOS numbers over — on macOS `systemLarge` is square, not
portrait. `~/Library/Containers/<ext>/Data/SystemData/com.apple.chrono/timelines/`
names each file after the geometry it was rendered at:

```
systemSmall               164 x 164   corner radius 27.88
systemMedium              344 x 164   corner radius 27.88
systemLarge               344 x 344   corner radius 27.88
systemExtraLargeLandscape 704 x 344   corner radius 27.88
```

**7. `AppIntentConfiguration` never ran here, and said nothing about it.**
Switching the four widgets from `StaticConfiguration` to `AppIntentConfiguration`
— so each placement could pick its own document — compiled, extracted all eight
intent and entity types into `Metadata.appintents`, and registered normally in
`pluginkit`. WidgetKit then asked the provider for `placeholder`, over and over,
and never once for a snapshot or a timeline. Measured over four hours:

```
timeline calls after the switch   0
snapshot calls, ever              0
```

Tried under both an Apple Development signature and ad hoc, and with the intent
types compiled into the extension alone and then into both targets — the
metadata bundle is genuinely required in the app as well, and adding it changed
nothing here. Reverting to `StaticConfiguration` produced 33 timelines and 25
renders within five minutes, from the same documents, on the same build of
macOS.

A second silence, same shape — and a different cause, found later in the crash
logs rather than reasoned about. The ten slot widgets were first written as one
generic `SlotWidget<Identity>`. It compiled and registered, and WidgetKit never
asked it for a timeline. Written out as ten concrete structs it ran immediately.

The first explanation written here was that WidgetKit must key a widget on
something a generic type does not satisfy. That was a guess, and it was wrong.
`~/Library/Logs/DiagnosticReports/FathomWidget-*.ips` had the answer all along:

```
libswiftCore  _assertionFailure(_:_:file:line:flags:)
WidgetKit     …
FathomWidget  SlotWidget.body.getter
SwiftUI       WidgetBodyAccessor.updateBody(of:changed:)
```

**A generic `Widget` trips an assertion inside WidgetKit when its body is
evaluated.** The extension was not being ignored, it was crashing — repeatedly,
on every attempt, which is why the log showed placeholders and nothing else.
Zero crashes since the concrete version; zero for the app, ever.

The lesson is not about generics. It is that an extension going quiet has a
third possible cause besides "not registered" and "not asked", and the crash
reports are the cheapest place to look. Trap 7's original silence was never
checked against them either.

Two things follow. Widgets placed under one configuration kind do not survive a
switch to the other, so every attempt costs a re-add. And since Fathom ships
ad-hoc signed, a fix that needed a paid signature would not help the thing people
download anyway. The cost is one document per family: two medium widgets on the
desktop show the same design. A widget that renders is worth more than a picker
that never runs.

Also: the embedded extension's bundle id must be prefixed with the host app's
full bundle id, or `ValidateEmbeddedBinary` fails the build.

### Trap 8 — ad-hoc signing silently strips every entitlement

Measured 8 Sep 2026, and it invalidates the obvious way to ship.

Fathom ships unsigned, so the install step has always been the obvious command:

```
codesign --force --deep --sign - Fathom.app
```

That command replaces the signature. **A replaced signature carries no
entitlements unless you hand them back**, and `--deep` does the same thing to
the embedded extension. Verified on a real install:

```
build product   app-sandbox true, /Users/Shared/Fathom/, location, calendars
after --deep    (no entitlements at all — the dump is empty)
```

The app still launches and behaves normally, because an unsandboxed app is
*less* restricted, not more. The extension is where it bites: trap 1 says macOS
silently refuses to register a widget extension that is not sandboxed, so the
ad-hoc build ships an app whose widgets can never appear, with no error at any
stage. Green build, clean install, working app, no widgets.

This one is nastier than the others because the broken step is the *last* one,
after everything has been tested. Every verification in this project up to here
was done on an Xcode-signed build.

The fix is `Tools/sign.sh`: sign inside out, name each target's entitlements
file explicitly, and then read the signature back and fail loudly if the sandbox
or the shared-store exception did not survive. Never `--deep`; never `--sign -`
without `--entitlements`.

The general lesson is the one this section keeps repeating in different
costumes: **a successful command is not evidence.** `codesign` exited zero and
printed "replacing existing signature" while removing the thing the whole
storage architecture depends on.

---

And a note on observability, since a widget extension has no console and trap 4
rules out the debugger: on this machine `log show` returns nothing at all, for
any predicate. Do not plan to diagnose an extension through the unified log.
Fathom's extension writes a trace into its own container and renders its own
store diagnosis onto the widget face, which is how trap 5 was found.

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
2. ~~**Design the format for sharing; do not ship sharing.**~~ **Shipped
   8 Sep**, once there was something to disclose with. The format carried
   `schemaVersion`, stable JSON and declared hosts from day one, so the importer
   only had to ask them. It shows, before anything is added and without running
   the document: every endpoint it will contact, any personal data it wants,
   fonts this Mac does not have, and whether it was made by a newer build. A
   document that does none of those says so plainly instead.
3. **Paste a URL, browse the parsed tree, drag a leaf onto an element.** The
   full binding UI, including arrays and type-to-format inference. This is the
   demo that makes the no-budget finding visible, so it is not the part to trim.

### 9.4 Second round, 8 Sep 2026

The owner asked for thousands of prebuilt widgets and "100% flexibility". Both
change section 4, so they are recorded here rather than left implicit.

**The catalog is generated, not hand-authored.** Roughly fifty designed layouts,
each rendered across palettes, families and data sources, giving a browsable
catalog where every entry descends from something a person composed.
Hand-authoring a thousand widgets is a hundred thousand lines nobody can
maintain, and the honest headline number has to be countable — accuracy in copy
matters here as everywhere.

Built 8 Sep: **23 layouts across 28 layout-and-size combinations × 20 palettes =
560 entries.** Not the "low thousands" this section first guessed at, and the
number is stated in the app beside its own arithmetic so nobody has to take it
on trust. The count is a pure function of layouts, each around twenty-five
lines against `Kit`, so it grows by adding to `Core/Catalog/Templates.swift` and
nothing else.

Generated at runtime rather than bundled as JSON, which is a change from the
first draft of this section and a better one: nothing can fall out of step with
the schema, there is no build step, and twenty palettes cost no bytes. Thumbnails
render on demand from each element's design-time literal — no sources are
resolved at all, so the gallery makes no network requests and no kernel reads,
every thumbnail is deterministic and cacheable forever, and a catalog entry shows
its *design* rather than this machine's current CPU.

**Expressions are in.** Section 4 called them a second product; they are the
single largest source of the flexibility being asked for, so they now ship. A
binding may carry a transform written in a small total language — arithmetic,
comparisons, conditionals, lookup tables, array and string functions — evaluated
by a Swift interpreter inside the extension. That is still data being
interpreted, so the forced architecture of section 3 is unchanged.

The ceiling is worth stating plainly, because "100%" cannot be met literally:
macOS will not load compiled code at runtime, so a user can only ever compose
the primitives shipped and transform values with the functions shipped. The
honest promise is a wide vocabulary and an open transform layer, not arbitrary
code.

**Apple Foundation Models, in the app only.** On-device, no account, no network,
free, and macOS 26 already the floor — it fits the section 2 promises exactly.
It does **not** run in the widget extension: keeping render time deterministic
is what makes "at most 64 seconds stale" true, and an on-device model on every
reload would be neither fast nor honest. Verified: the framework is linked into
the app and absent from the extension binary.

Built 8 Sep, and narrower than this section first implied. The system model is
small, with a context window to match, and asking it to emit a whole document —
unit frames, styles, bindings, expressions — produces plausible JSON that
renders as nonsense. It is asked to **choose** instead: which designed layout,
which palette, which size, what to call it. That is classification against a
bounded vocabulary, which a small model does well. Every field it returns is
matched against the catalog, near-misses are resolved by edit distance, and
anything unrecognisable falls back to a default — so a confused model produces a
widget that is merely not what you asked for, never a broken one.

The second use is picking the three to six useful fields out of a freshly
fetched endpoint, where the judgement is "what would a person glance at" and
being wrong costs nothing, because they are suggestions beside the tree rather
than changes to the document.

One thing worth recording: the model was given bare palette ids at first and
answered "a minimal clock in black and white" with the mint palette. Palettes
now carry a plain-words description of how they look, and the same prompt
returns Mono. Describing the vocabulary mattered more than anything about the
prompt itself.

Not built: restyling an existing document by description. Degrades quietly when
Apple Intelligence is off — Fathom is complete without it and the copy says so.

**More Apple data sources.** EventKit (calendar, reminders), CoreLocation,
richer IOKit and ProcessInfo (CPU, memory, thermal state, uptime), Bluetooth
device battery. Each personal-information source needs its own entitlement, its
own usage string and a permission the user grants.

One that does not work: **WeatherKit authenticates with the app's identity**, and
an ad-hoc signature has no team. It is unavailable to an unsigned build. The
JSON source pointed at Open-Meteo is the free path and needs no key.

### 9.5 Third round, 8 Sep 2026 — more than widgets

The owner: Fathom will host **menu bar widgets**, an **iOS-style island** near
the notch, and further customisations. Desktop widgets are the first surface,
not the whole product.

The architecture takes this better than it has any right to. A surface is
already just a box with a size: a document is elements in unit space, and the
renderer only ever needs a box and a scale. So a menu bar item and an island are
new `WidgetDoc.Family` cases with their own reference sizes, and `WidgetCanvas`,
the binding system, the expression layer, every data source and the whole editor
work unchanged. The catalog templates declare which families they suit, so they
opt in rather than being retrofitted.

What is genuinely new is the *host*. Neither surface is WidgetKit:

- **Menu bar** — **built 8 Sep.** An `NSStatusItem` per item, drawing a
  document rendered to an image. Fathom keeps running, with a Dock-icon setting
  rather than a decision made for the user. Unlike an overlay it has a shape
  imposed on it — 22 points, measured from `NSStatusBar.system.thickness` — so
  it is a `Family` rather than a host: nothing composed for a square reads in a
  band that tall. Four catalog layouts and one starter ship for it. Free of the
  64-second floor, like every surface Fathom drives itself.
- **The island** — **built 8 Sep.** A borderless, non-activating window at
  status-bar level, centred and hanging flush under the menu bar. macOS 26
  offers no island API; Fathom draws and positions it. The placement is measured
  from `NSScreen.safeAreaInsets.top`, which is the notch on a Mac that has one
  and zero on a Mac that does not — so a notched laptop and an external display
  both land correctly with no special case. One island, not a list: it is a
  place rather than a thing you can have several of, and overlays are the answer
  when you want many. Compact by default, expanding to a second document on
  hover.

Two consequences worth writing down now. The 64-second finding is a fact about
WidgetKit, not about Fathom — copy must not generalise it to surfaces the app
drives itself. And the icon should not depict widgets, because widgets are about
to be one surface among several.

---

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
