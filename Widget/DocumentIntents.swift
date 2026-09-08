import AppIntents
import WidgetKit

// Letting each placed widget choose its own document.
//
// Without this there is one document per family and two small widgets on the
// desktop necessarily show the same thing — which the editor runs into
// immediately, since "show on desktop" would have nowhere to put a second
// design.
//
// The repetition below is forced rather than lazy. App Intents needs concrete
// types for its metadata, and an `EntityQuery` is given no way to find out
// which widget family it is populating a picker for. So a picker that offers
// only same-size designs needs one entity, one query and one intent per
// family. All four delegate to `DocumentCatalog`, which holds the only copy of
// the actual logic.

/// The shared half: reading documents of one family out of the store.
enum DocumentCatalog {
    static func all(_ family: WidgetDoc.Family) -> [(id: UUID, name: String)] {
        DocumentStore.shared.allDocuments()
            .filter { $0.family == family }
            .map { (id: $0.id, name: $0.name) }
    }

    static func named(_ ids: [UUID], family: WidgetDoc.Family) -> [(id: UUID, name: String)] {
        let wanted = Set(ids)
        return all(family).filter { wanted.contains($0.id) }
    }

    /// What a placement should render: the document the user picked, or the
    /// family's default when they have not picked one. Falling back rather
    /// than rendering empty means a widget dragged out before it is configured
    /// still shows something, which is how every other widget on macOS behaves.
    static func document(selected: UUID?, family: WidgetDoc.Family) -> WidgetDoc? {
        if let selected, let doc = DocumentStore.shared.document(id: selected), doc.family == family {
            return doc
        }
        return DocumentStore.shared.activeDocument(for: family)
    }
}

/// Lets one generic provider serve all four families.
protocol DocumentSelectingIntent: WidgetConfigurationIntent {
    static var family: WidgetDoc.Family { get }
    var selectedDocumentID: UUID? { get }
}

// MARK: - Small

struct SmallDocumentEntity: AppEntity {
    var id: UUID
    var name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Small widget" }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    static var defaultQuery = SmallDocumentQuery()
}

struct SmallDocumentQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [SmallDocumentEntity] {
        DocumentCatalog.named(identifiers, family: .small).map { SmallDocumentEntity(id: $0.id, name: $0.name) }
    }
    func suggestedEntities() async throws -> [SmallDocumentEntity] {
        DocumentCatalog.all(.small).map { SmallDocumentEntity(id: $0.id, name: $0.name) }
    }
}

struct SmallWidgetIntent: DocumentSelectingIntent {
    static var title: LocalizedStringResource { "Choose a widget" }
    static var description: IntentDescription { "Pick which of your Fathom designs this widget shows." }
    static var family: WidgetDoc.Family { .small }

    @Parameter(title: "Design")
    var design: SmallDocumentEntity?

    var selectedDocumentID: UUID? { design?.id }
}

// MARK: - Medium

struct MediumDocumentEntity: AppEntity {
    var id: UUID
    var name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Medium widget" }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    static var defaultQuery = MediumDocumentQuery()
}

struct MediumDocumentQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [MediumDocumentEntity] {
        DocumentCatalog.named(identifiers, family: .medium).map { MediumDocumentEntity(id: $0.id, name: $0.name) }
    }
    func suggestedEntities() async throws -> [MediumDocumentEntity] {
        DocumentCatalog.all(.medium).map { MediumDocumentEntity(id: $0.id, name: $0.name) }
    }
}

struct MediumWidgetIntent: DocumentSelectingIntent {
    static var title: LocalizedStringResource { "Choose a widget" }
    static var description: IntentDescription { "Pick which of your Fathom designs this widget shows." }
    static var family: WidgetDoc.Family { .medium }

    @Parameter(title: "Design")
    var design: MediumDocumentEntity?

    var selectedDocumentID: UUID? { design?.id }
}

// MARK: - Large

struct LargeDocumentEntity: AppEntity {
    var id: UUID
    var name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Large widget" }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    static var defaultQuery = LargeDocumentQuery()
}

struct LargeDocumentQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [LargeDocumentEntity] {
        DocumentCatalog.named(identifiers, family: .large).map { LargeDocumentEntity(id: $0.id, name: $0.name) }
    }
    func suggestedEntities() async throws -> [LargeDocumentEntity] {
        DocumentCatalog.all(.large).map { LargeDocumentEntity(id: $0.id, name: $0.name) }
    }
}

struct LargeWidgetIntent: DocumentSelectingIntent {
    static var title: LocalizedStringResource { "Choose a widget" }
    static var description: IntentDescription { "Pick which of your Fathom designs this widget shows." }
    static var family: WidgetDoc.Family { .large }

    @Parameter(title: "Design")
    var design: LargeDocumentEntity?

    var selectedDocumentID: UUID? { design?.id }
}

// MARK: - Extra large

struct ExtraLargeDocumentEntity: AppEntity {
    var id: UUID
    var name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Extra large widget" }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    static var defaultQuery = ExtraLargeDocumentQuery()
}

struct ExtraLargeDocumentQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [ExtraLargeDocumentEntity] {
        DocumentCatalog.named(identifiers, family: .extraLarge).map { ExtraLargeDocumentEntity(id: $0.id, name: $0.name) }
    }
    func suggestedEntities() async throws -> [ExtraLargeDocumentEntity] {
        DocumentCatalog.all(.extraLarge).map { ExtraLargeDocumentEntity(id: $0.id, name: $0.name) }
    }
}

struct ExtraLargeWidgetIntent: DocumentSelectingIntent {
    static var title: LocalizedStringResource { "Choose a widget" }
    static var description: IntentDescription { "Pick which of your Fathom designs this widget shows." }
    static var family: WidgetDoc.Family { .extraLarge }

    @Parameter(title: "Design")
    var design: ExtraLargeDocumentEntity?

    var selectedDocumentID: UUID? { design?.id }
}
