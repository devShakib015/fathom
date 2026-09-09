import WidgetKit

// Which document a placed widget shows.
//
// This once carried four App Intents configurations so each placement could
// pick its own design. It does not any more, because App Intents never ran
// a timeline here. Under
// AppIntentConfiguration this extension was asked for `placeholder` and never
// once for a snapshot or a timeline — 151 timeline calls in the log, every one
// of them from before the switch, and zero snapshots ever. Tried under both
// signatures and with the intent types compiled into both targets.
//
// So the extension is back to StaticConfiguration, which means one document per
// family. That is a real limitation and the honest one: a widget that renders
// is worth more than a picker that never runs.

/// Reading documents of one family out of the store.
enum DocumentCatalog {
    /// What a placement renders: the document assigned to that slot in the app,
    /// chosen with "Show on desktop".
    static func document(for slot: WidgetSlot) -> WidgetDoc? {
        DocumentStore.shared.activeDocument(for: slot)
    }
}
