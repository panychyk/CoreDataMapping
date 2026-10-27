import CoreData
import CoreDataMapping
import Testing

/// Перевіряє, що модель конгресу правильно пов’язує дані, а перший імпорт
/// зберігає їх для подальшого читання. Пошук за ідентифікаторами не створює
/// дублікатів і коректно обробляє відсутні записи.
///
/// - `schemaRules`: inverse для кожного зв’язку та правила `Cascade` і `Nullify`.
/// - `identityLookup`: дедуплікація ID, пропуск відсутніх записів і помилка для
///   недопустимого розміру fetch-порції.
/// - `fullGraphSurvivesContextReset`: усі сутності та зв’язки доступні після
///   збереження й скидання контексту читання.
@MainActor
@Suite("Medical congress · model and initial import")
struct CongressModelAndImportTests {
    @Test("Every relationship has an inverse and ownership uses cascade")
    func schemaRules() throws {
        let url = try #require(
            Bundle.module.url(
                forResource: "MedicalCongressModel", withExtension: "momd"
            ))
        let model = try #require(NSManagedObjectModel(contentsOf: url))
        #expect(model.entities.count == 15)
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
