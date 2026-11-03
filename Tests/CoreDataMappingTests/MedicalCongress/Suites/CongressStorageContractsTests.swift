import CoreData
import CoreDataMapping
import Testing

/// Verifies direct CoreDataStorage contracts on the small congress fixture.
/// Lookup preserves global identity, deletion affects only owned children,
/// and invalid entities or relationships leave the saved graph unchanged.
///
/// - `repeatedGlobalID`: the last DTO with an ID supplies saved scalar fields.
/// - `deleteSurplusOwned`: a surplus appointment is deleted only from its event.
/// - `duplicateExistingOwnedID`: duplicate IDs among current children roll back a batch.
/// - `detachedRelationship`: ordered replace rejects an object without a context.
/// - `deletedRelationship`: unordered replace rejects a deleted object.
/// - `wrongOrderedType`: the ordered bridge rejects an entity of the wrong type.
/// - `unknownEntity`: insert rejects an entity missing from the model.
/// - `wrongEntityClass`: insert rejects an entity and Swift-class mismatch.
@MainActor
@Suite("Medical congress · storage contracts")
struct CongressStorageContractsTests {
    private struct ResourceValue: Sendable {
        let id: Int64
        let title: String
    }

    @Test("The last DTO for a global ID wins without creating duplicate rows")
    func repeatedGlobalID() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let values = [
            ResourceValue(id: 30, title: "First"),
            ResourceValue(id: 31, title: "Other"),
            ResourceValue(id: 30, title: "Last"),
        ]

        try await stack.importer.write(values) { batch, storage in
            _ = try storage.upsert(
                batch, id: \ResourceValue.id, identifiedBy: ResourceAsset.identity,
                fetchChunkSize: 1
            ) { resource, value in
                resource.title = value.title
            }
        }

        stack.resetViewContext()
        let resources = try stack.fetch(ResourceAsset.self)
        #expect(resources.count == 2)
        #expect(resources.first { $0.id == 30 }?.title == "Last")
        #expect(resources.first { $0.id == 31 }?.title == "Other")
    }

    @Test("Deleting surplus owned children preserves the other event and shared rows")
    func deleteSurplusOwned() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let original = CongressGraphFixture.congress()
        try await stack.write(original)

        try await stack.importer.write([Int64(40)]) { ids, storage in
            let events = try storage.existing(
                ids: ids, identifiedBy: CongressEvent.identity,
                prefetching: ["appointments.participants"]
            )
            let event = try #require(events[40])
            let current = try CoreDataStorage.ordered(event.appointments, as: Appointment.self)
            let kept = current.filter { $0.localID == 1 }
            try storage.deleteSurplusOwned(current: current, keeping: kept)
            event.appointments = try storage.replace(with: kept)
        }

        var expected = original
        expected.events[0].appointments.removeAll { $0.id != 1 }
        try GraphAssertions.matches(expected, in: stack)
    }

    @Test("A duplicate among existing owned children rolls back the batch")
    func duplicateExistingOwnedID() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let original = CongressGraphFixture.congress()
        try await stack.write(original)

        await #expect(throws: CoreDataStorageError.duplicateOwnedIdentity(
            entityName: "Appointment", id: "1"
        )) {
            try await stack.importer.write([Int64(40)]) { ids, storage in
                let events = try storage.existing(
                    ids: ids, identifiedBy: CongressEvent.identity,
                    prefetching: ["appointments"]
                )
                let event = try #require(events[40])
                let current = try CoreDataStorage.ordered(event.appointments, as: Appointment.self)
                let duplicate = try storage.insert(Appointment.self)
                duplicate.localID = 1
                duplicate.event = event
                _ = try storage.reconcileOwned(
                    [Int64(1)], current: current + [duplicate],
                    dtoId: \.self, entityId: \Appointment.localID,
                    create: { try storage.insert(Appointment.self) }
                ) { appointment, id in
                    appointment.localID = id
                }
            }
        }

        try GraphAssertions.matches(original, in: stack)
    }

    @Test("Ordered replacement rejects an object without this context")
    func detachedRelationship() async throws {
        let stack = try CongressTestStack()
        try await stack.load()

        await #expect(throws: CoreDataStorageError.relationshipContextMismatch(
            entityName: "ResourceAsset"
        )) {
            try await stack.importer.write([Int64(30)]) { _, storage in
                let entity = try #require(NSEntityDescription.entity(
                    forEntityName: "ResourceAsset", in: storage.context
                ))
                let detached = ResourceAsset(entity: entity, insertInto: nil)
                _ = try storage.replace(with: [detached])
            }
        }

        #expect(try stack.count(ResourceAsset.self) == 0)
    }

    @Test("Unordered replacement rejects a deleted object and restores it")
    func deletedRelationship() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let original = CongressGraphFixture.congress()
        try await stack.write(original)

        await #expect(throws: CoreDataStorageError.deletedRelationshipEntity(
            entityName: "ResourceAsset"
        )) {
            try await stack.importer.write([Int64(30)]) { ids, storage in
                let resources = try storage.existing(
                    ids: ids, identifiedBy: ResourceAsset.identity
                )
                let resource = try #require(resources[30])
                storage.context.delete(resource)
                _ = try storage.replaceUnordered(with: [resource])
            }
        }

        try GraphAssertions.matches(original, in: stack)
    }

    @Test("The ordered bridge rejects an unexpected managed object type")
    func wrongOrderedType() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let original = CongressGraphFixture.congress()
        try await stack.write(original)

        await #expect(throws: CoreDataStorageError.unexpectedRelationshipEntityType(
            expectedType: "Appointment"
        )) {
            try await stack.importer.read([Int64(30)]) { ids, storage in
                let resources = try storage.existing(
                    ids: ids, identifiedBy: ResourceAsset.identity
                )
                let resource = try #require(resources[30])
                _ = try CoreDataStorage.ordered(
                    NSOrderedSet(array: [resource]), as: Appointment.self
                )
                return [Int64]()
            }
        }

        try GraphAssertions.matches(original, in: stack)
    }

    @Test("Insert rejects an entity name missing from the model")
    func unknownEntity() async throws {
        let stack = try CongressTestStack()
        try await stack.load()

        await #expect(throws: CoreDataStorageError.unknownEntity("MissingResource")) {
            try await stack.importer.write([Int64(30)]) { _, storage in
                _ = try storage.insert(ResourceAsset.self, entityName: "MissingResource")
            }
        }

        #expect(try stack.count(ResourceAsset.self) == 0)
    }

    @Test("Insert rejects a model entity represented by another Swift class")
    func wrongEntityClass() async throws {
        let stack = try CongressTestStack()
        try await stack.load()

        await #expect(throws: CoreDataStorageError.unexpectedEntityType(
            entityName: "ResourceAsset", expectedType: "Appointment"
        )) {
            try await stack.importer.write([Int64(30)]) { _, storage in
                _ = try storage.insert(Appointment.self, entityName: "ResourceAsset")
            }
        }

        #expect(try stack.count(ResourceAsset.self) == 0)
    }
}
