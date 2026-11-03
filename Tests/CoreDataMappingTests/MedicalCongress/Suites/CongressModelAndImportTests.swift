import CoreData
import CoreDataMapping
import Testing

/// Verifies congress model relationships and the first import for later reading.
/// Identity lookup creates no duplicates and handles missing rows correctly.
///
/// - `schemaRules`: every relationship has an inverse and the proper `Cascade`
///   or `Nullify` rule.
/// - `identityLookup`: IDs are deduplicated, missing rows are omitted, and an
///   invalid fetch chunk size throws.
/// - `fullGraphSurvivesContextReset`: all entities and links remain available
///   after saving and resetting the read context.
@MainActor
@Suite("Medical congress · model and initial import")
struct CongressModelAndImportTests {
    @Test("Every relationship has an inverse and ownership uses cascade")
    func schemaRules() throws {
        let url = try #require(
            Bundle.module.url(
                forResource: "TestModel", withExtension: "momd"
            ))
        let model = try #require(NSManagedObjectModel(contentsOf: url))
        #expect(model.entities.count == 49)
        for entity in model.entities {
            for relationship in entity.relationshipsByName.values {
                #expect(relationship.inverseRelationship?.inverseRelationship === relationship)
            }
        }
        let ownedRelationships: [(entity: String, name: String)] = [
            ("Venue", "rooms"),
            ("CongressEvent", "tracks"),
            ("CongressEvent", "appointments"),
            ("CongressEvent", "registrations"),
            ("CongressEvent", "sponsors"),
            ("Track", "sessions"),
            ("Session", "speakers"),
            ("Appointment", "participants"),
            ("Registration", "checkIns"),
        ]
        for relationship in ownedRelationships {
            let entity = try #require(model.entitiesByName[relationship.entity])
            #expect(entity.relationshipsByName[relationship.name]?.deleteRule == .cascadeDeleteRule)
        }

        let sharedRelationships: [(entity: String, name: String)] = [
            ("Congress", "events"),
            ("Venue", "events"),
            ("Session", "resources"),
            ("Session", "room"),
            ("Appointment", "room"),
            ("Organization", "sponsorships"),
            ("Person", "appointments"),
            ("Person", "registrations"),
            ("Person", "speakingRoles"),
            ("ResourceAsset", "sessions"),
        ]
        for relationship in sharedRelationships {
            let entity = try #require(model.entitiesByName[relationship.entity])
            #expect(entity.relationshipsByName[relationship.name]?.deleteRule == .nullifyDeleteRule)
        }
    }

    @Test("Batch lookup deduplicates global IDs and omits missing IDs")
    func identityLookup() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        try await stack.importer.write([Int64(30), 31, 30], batchSize: 2) { ids, storage in
            let resources = try storage.upsert(
                ids: ids, identifiedBy: ResourceAsset.identity, fetchChunkSize: 1
            )
            for id in ids { resources[id]?.title = "Resource \(id)" }
        }
        let found = try await stack.importer.read([Int64(31), 30, 99]) { ids, storage in
            let resources = try storage.existing(
                ids: ids, identifiedBy: ResourceAsset.identity, fetchChunkSize: 1
            )
            return ids.compactMap { resources[$0]?.id }
        }
        #expect(found == [31, 30])
        #expect(try stack.count(ResourceAsset.self) == 2)
        await #expect(throws: CoreDataStorageError.invalidFetchChunkSize(0)) {
            try await stack.importer.read([Int64(30)]) { ids, storage in
                _ = try storage.existing(
                    ids: ids, identifiedBy: ResourceAsset.identity, fetchChunkSize: 0
                )
                return [Int64]()
            }
        }
    }

    @Test("A full congress graph survives a context reset")
    func fullGraphSurvivesContextReset() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let graph = CongressGraphFixture.congress()

        try await stack.write(graph)

        try GraphAssertions.matches(graph, in: stack)
    }
}
