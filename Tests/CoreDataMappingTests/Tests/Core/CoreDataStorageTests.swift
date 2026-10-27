import CoreData
import Testing
import CoreDataMapping

extension PersistenceTests {
    @MainActor
    @Suite("Core Data storage: identity → membership → ownership → validation")
    struct CoreDataStorageTests {

        // MARK: - 1. Identity lifecycle

        @Test("Empty batches do not create objects or invoke mapping")
        func emptyBatch() async throws {
            let stack = try await makeStack()
            let storage = CoreDataStorage(context: stack.viewContext)
            let fetched = try storage.existing(ids: [Int](), identifiedBy: ReservationTopicEntity.identity)
            let inserted = try storage.upsert(ids: [Int](), identifiedBy: ReservationTopicEntity.identity)
            var updateCount = 0
            let mapped = try storage.upsert(
                [ReservationTopicDTO](),
                id: \ReservationTopicDTO.ReservationTopicID,
                identifiedBy: ReservationTopicEntity.identity
            ) { _, _ in
                updateCount += 1
            }

            #expect(fetched.isEmpty && inserted.isEmpty && mapped.isEmpty)
            #expect(updateCount == 0)
            #expect(!stack.viewContext.hasChanges)
        }

        @Test("Insert, repeat before save, then fetch after save reuse one stable identity")
        func identityLifecycle() async throws {
            let stack = try await makeStack()
            let storage = CoreDataStorage(context: stack.viewContext)
            #expect(try storage.existing(ids: [7], identifiedBy: ReservationTopicEntity.identity).isEmpty)

            let inserted = try storage.upsert(
                ids: [7, 8, 7], identifiedBy: ReservationTopicEntity.identity, fetchChunkSize: 1
            )
            let first = try #require(inserted[7])
            first.name = "Initial"
            let repeated = try storage.upsert(ids: [7, 7], identifiedBy: ReservationTopicEntity.identity)
            #expect(inserted.count == 2)
            #expect(repeated[7] === first)
            #expect(first.isInserted)
            try stack.viewContext.save()
            let savedId = first.objectID
            stack.viewContext.reset()

            let fetched = try #require(
                try storage.existing(ids: [7], identifiedBy: ReservationTopicEntity.identity)[7]
            )
            #expect(fetched.objectID == savedId)
            #expect(fetched.name == "Initial")
            #expect(try count(ReservationTopicEntity.self, in: stack.viewContext) == 2)
        }

        @Test("Batch reads include pending objects, omit missing identities, and create nothing")
        func batchLookup() async throws {
            let stack = try await makeStack()
            let storage = CoreDataStorage(context: stack.viewContext)
            _ = try storage.upsert(ids: [1, 2], identifiedBy: ReservationTopicEntity.identity)
            try stack.viewContext.save()
            _ = try storage.upsert(ids: [3], identifiedBy: ReservationTopicEntity.identity)

            let result = try storage.existing(
                ids: [3, 2, 4, 2], identifiedBy: ReservationTopicEntity.identity, fetchChunkSize: 1
            )

            #expect(Set(result.keys) == [2, 3])
            #expect(try count(ReservationTopicEntity.self, in: stack.viewContext) == 3)
        }

        @Test("DTO batches preload identities, update in input order, and retain omitted rows")
        func batchDTOUpsert() async throws {
            let stack = try await makeStack()
            let storage = CoreDataStorage(context: stack.viewContext)
            let existing = try storage.upsert(ids: [7, 9], identifiedBy: ReservationTopicEntity.identity)
            existing[9]?.name = "Not in this response"
            try stack.viewContext.save()
            let topics = [
                ReservationTopicDTO(ReservationTopicID: 7, Name: "Initial"),
                ReservationTopicDTO(ReservationTopicID: 8, Name: "Second"),
                ReservationTopicDTO(ReservationTopicID: 7, Name: "Latest")
            ]
            var updates: [Int] = []
            let entities = try storage.upsert(
                topics,
                id: \ReservationTopicDTO.ReservationTopicID,
                identifiedBy: ReservationTopicEntity.identity,
                fetchChunkSize: 1
            ) { entity, dto in
                // Even the first update sees all missing identities inserted.
                #expect(stack.viewContext.insertedObjects.count == 1)
                updates.append(entity.id)
                entity.name = dto.Name
            }

            #expect(updates == [7, 8, 7])
            #expect(entities[7] === existing[7])
            #expect(entities[7]?.name == "Latest")
            #expect(entities[8]?.name == "Second")
            #expect(existing[9]?.name == "Not in this response")
            #expect(try count(ReservationTopicEntity.self, in: stack.viewContext) == 3)
        }

        // MARK: - 2. Membership: full snapshots and partial additions

        @Test("Typed insertion uses the context model and reports invalid schema names and types")
        func typedInsertion() async throws {
            let stack = try await makeStack()
            let storage = CoreDataStorage(context: stack.viewContext)
            let field = try storage.insert(CustomFieldEntity.self)
            field.id = 7
            #expect(field.entity === stack.persistentContainer.managedObjectModel.entitiesByName["CustomFieldEntity"])
            try stack.viewContext.save()

            #expect(throws: CoreDataStorageError.unknownEntity("MissingEntity")) {
                try storage.insert(CustomFieldEntity.self, entityName: "MissingEntity")
            }
            #expect(!stack.viewContext.hasChanges)
            #expect(throws: CoreDataStorageError.unexpectedEntityType(
                entityName: "ReservationTopicEntity", expectedType: "CustomFieldEntity"
            )) {
                try storage.insert(CustomFieldEntity.self, entityName: "ReservationTopicEntity")
            }
            stack.viewContext.rollback()
            #expect(try count(CustomFieldEntity.self, in: stack.viewContext) == 1)
        }

        @Test("Ordered relationships expose typed Swift arrays, including nil and schema mismatch")
        func typedOrderedRelationships() async throws {
            let stack = try await makeStack()
            let storage = CoreDataStorage(context: stack.viewContext)
            let topic = try storage.insert(ReservationTopicEntity.self)
            let empty = try CoreDataStorage.ordered(nil, as: ReservationTopicEntity.self)
            #expect(empty.isEmpty)
            let values = try CoreDataStorage.ordered(NSOrderedSet(object: topic), as: ReservationTopicEntity.self)
            #expect(values == [topic])
            #expect(throws: CoreDataStorageError.unexpectedRelationshipEntityType(expectedType: "CustomFieldEntity")) {
                try CoreDataStorage.ordered(NSOrderedSet(object: topic), as: CustomFieldEntity.self)
            }
        }

        @Test("Ordered snapshots replace order, remove duplicates, then clear without deleting shared rows")
        func orderedSnapshotLifecycle() async throws {
            let stack = try await makeStack()
            let storage = CoreDataStorage(context: stack.viewContext)
            let topics = try storage.upsert(ids: [1, 2, 3], identifiedBy: ReservationTopicEntity.identity)
            let parent = try makeAppointment(id: 1, in: stack.viewContext)
            parent.topics = try storage.replace(with: [topics[1]!, topics[2]!])
            try stack.viewContext.save()

            parent.topics = try storage.replace(with: [topics[3]!, topics[2]!, topics[3]!])
            #expect(ids(in: parent.topics!) == [3, 2])
            #expect(topics[1]?.appointments?.contains(parent) != true)
            #expect(topics[3]?.appointments?.contains(parent) == true)

            parent.topics = try storage.replace(with: [ReservationTopicEntity]())
            try stack.viewContext.save()
            #expect(parent.topics?.count == 0)
            #expect(try count(ReservationTopicEntity.self, in: stack.viewContext) == 3)
        }

        @Test("Unordered snapshots replace membership, deduplicate, and clear without deleting rows")
        func unorderedMembershipLifecycle() async throws {
            let stack = try await makeStack()
            let storage = CoreDataStorage(context: stack.viewContext)
            let topics = try storage.upsert(ids: [1, 2, 3], identifiedBy: ReservationTopicEntity.identity)
            let initial = try storage.replaceUnordered(with: [topics[1]!, topics[2]!, topics[1]!])
            let replaced = try storage.replaceUnordered(with: [topics[3]!, topics[3]!])
            let cleared = try storage.replaceUnordered(with: [ReservationTopicEntity]())

            #expect(Set(initial.map(\.id)) == [1, 2])
            #expect(Set(replaced.map(\.id)) == [3])
            #expect(cleared.isEmpty)
            #expect(try count(ReservationTopicEntity.self, in: stack.viewContext) == 3)
            #expect(stack.viewContext.deletedObjects.isEmpty)
        }

        // MARK: - 3. Owned lifecycle: scoped reuse, replacement, deletion

        @Test("Owned snapshots insert, update, reorder, remove, and clear children while retaining object identity")
        func ownedSnapshotLifecycle() async throws {
            let stack = try await makeStack()
            let storage = CoreDataStorage(context: stack.viewContext)
            let parent = try makeAppointment(id: 1, in: stack.viewContext)
            let initial = try reconcile([field(1, "Remove"), field(2, "Original")], for: parent, using: storage)
            try stack.viewContext.save()
            let reusableId = initial[1].objectID

            let changed = try reconcile([field(3, "New"), field(2, "Updated")], for: parent, using: storage)
            #expect(changed.map(\.id) == [3, 2])
            #expect(changed[1] === initial[1])
            #expect(changed[1].objectID == reusableId)
            #expect(changed[1].value == "Updated")
            #expect(initial[0].isDeleted)
            try stack.viewContext.save()
            #expect(try count(CustomFieldEntity.self, in: stack.viewContext) == 2)

            let cleared = try reconcile([], for: parent, using: storage)
            #expect(cleared.isEmpty)
            #expect(changed.allSatisfy { $0.isDeleted })
            try stack.viewContext.save()
            #expect(try count(CustomFieldEntity.self, in: stack.viewContext) == 0)
        }

        @Test("The same scoped child ID belongs independently to each parent")
        func scopedIdentityDoesNotCrossParents() async throws {
            let stack = try await makeStack()
            let storage = CoreDataStorage(context: stack.viewContext)
            let first = try makeAppointment(id: 1, in: stack.viewContext)
            let second = try makeAppointment(id: 2, in: stack.viewContext)
            let firstFields = try reconcile([field(7, "First")], for: first, using: storage)
            let secondFields = try reconcile([field(7, "Second")], for: second, using: storage)
            #expect(firstFields[0] !== secondFields[0])
            try stack.viewContext.save()

            _ = try reconcile([], for: first, using: storage)
            try stack.viewContext.save()

            #expect(secondFields[0].value == "Second")
            #expect(secondFields[0].appointment === second)
            #expect(try count(CustomFieldEntity.self, in: stack.viewContext) == 1)
        }

        @Test("Surplus deletion compares object identity when different parents use the same child ID")
        func deletesOnlySurplusOwnedObjects() async throws {
            let stack = try await makeStack()
            let storage = CoreDataStorage(context: stack.viewContext)
            let removed = try storage.insert(CustomFieldEntity.self)
            removed.id = 7
            let kept = try storage.insert(CustomFieldEntity.self)
            kept.id = 7
            try stack.viewContext.save()

            try storage.deleteSurplusOwned(current: [removed, kept], keeping: [kept])
            #expect(removed.isDeleted)
            #expect(!kept.isDeleted)
            try stack.viewContext.save()
            #expect(try count(CustomFieldEntity.self, in: stack.viewContext) == 1)
        }

        // MARK: - 4. Invalid input fails before dangerous mutations

        @Test("Invalid fetch sizes fail even for an empty batch", arguments: [0, -1])
        func invalidFetchChunkSize(size: Int) async throws {
            let stack = try await makeStack()
            let storage = CoreDataStorage(context: stack.viewContext)

            #expect(throws: CoreDataStorageError.invalidFetchChunkSize(size)) {
                try storage.upsert(
                    ids: [Int](), identifiedBy: ReservationTopicEntity.identity, fetchChunkSize: size
                )
            }
            #expect(!stack.viewContext.hasChanges)
        }

        @Test("Duplicate incoming scoped IDs fail before any create, update, or delete")
        func duplicateIncomingOwnedIdentities() async throws {
            let stack = try await makeStack()
            let storage = CoreDataStorage(context: stack.viewContext)
            let parent = try makeAppointment(id: 1, in: stack.viewContext)
            let initial = try reconcile([field(1, "Keep")], for: parent, using: storage)
            try stack.viewContext.save()

            #expect(throws: CoreDataStorageError.duplicateOwnedIdentity(entityName: "CustomFieldEntity", id: "2")) {
                try reconcile(
                    [field(1, "Must remain unchanged"), field(2, "First"), field(2, "Second")],
                    for: parent,
                    using: storage
                )
            }

            #expect(initial[0].value == "Keep")
            #expect(!stack.viewContext.hasChanges)
            #expect(try count(CustomFieldEntity.self, in: stack.viewContext) == 1)
        }

        @Test("Ambiguous existing scoped IDs fail instead of silently choosing a child")
        func duplicateCurrentOwnedIdentities() async throws {
            let stack = try await makeStack()
            let storage = CoreDataStorage(context: stack.viewContext)
            let first = try storage.insert(CustomFieldEntity.self)
            first.id = 7
            let second = try storage.insert(CustomFieldEntity.self)
            second.id = 7
            try stack.viewContext.save()

            #expect(throws: CoreDataStorageError.duplicateOwnedIdentity(entityName: "CustomFieldEntity", id: "7")) {
                try storage.reconcileOwned(
                    [field(7, "Update")],
                    current: [first, second],
                    dtoId: \CustomFieldDTO.CustomFieldID,
                    entityId: \CustomFieldEntity.id,
                    create: { try storage.insert(CustomFieldEntity.self) }
                ) { entity, dto in
                    entity.value = dto.FieldValue
                }
            }
            #expect(!stack.viewContext.hasChanges)
        }

        @Test("Every membership operation rejects objects from a different context")
        func foreignRelationshipContext() async throws {
            let stack = try await makeStack()
            let foreignStack = try await makeStack()
            let storage = CoreDataStorage(context: stack.viewContext)
            let foreign = try CoreDataStorage(context: foreignStack.viewContext).insert(ReservationTopicEntity.self)
            foreign.id = 1
            let local = try storage.insert(ReservationTopicEntity.self)
            local.id = 2
            try stack.viewContext.save()
            let error = CoreDataStorageError.relationshipContextMismatch(entityName: "ReservationTopicEntity")

            #expect(throws: error) { try storage.replace(with: [foreign]) }
            #expect(throws: error) { try storage.replaceUnordered(with: [foreign]) }
            #expect(throws: error) { try storage.deleteSurplusOwned(current: [foreign], keeping: []) }
            #expect(throws: error) { try storage.deleteSurplusOwned(current: [local], keeping: [foreign]) }
            #expect(!local.isDeleted)
            #expect(!stack.viewContext.hasChanges)
        }

        @Test("Owned creation validates its context before invoking the update closure")
        func foreignOwnedCreation() async throws {
            let stack = try await makeStack()
            let foreignStack = try await makeStack()
            let storage = CoreDataStorage(context: stack.viewContext)
            let foreign = try CoreDataStorage(context: foreignStack.viewContext).insert(CustomFieldEntity.self)
            foreign.id = 99
            var didUpdate = false

            #expect(throws: CoreDataStorageError.relationshipContextMismatch(entityName: "CustomFieldEntity")) {
                try storage.reconcileOwned(
                    [field(7, "Should not be applied")],
                    current: [],
                    dtoId: \CustomFieldDTO.CustomFieldID,
                    entityId: \CustomFieldEntity.id,
                    create: { foreign }
                ) { _, _ in
                    didUpdate = true
                }
            }

            #expect(!didUpdate)
            #expect(foreign.id == 99)
            #expect(!stack.viewContext.hasChanges)
        }

        @Test("Deleted objects cannot be reattached, retained, or reused as owned children")
        func deletedRelationshipObjects() async throws {
            let stack = try await makeStack()
            let storage = CoreDataStorage(context: stack.viewContext)
            let child = try storage.insert(CustomFieldEntity.self)
            child.id = 7
            try stack.viewContext.save()
            stack.viewContext.delete(child)
            let error = CoreDataStorageError.deletedRelationshipEntity(entityName: "CustomFieldEntity")

            #expect(throws: error) { try storage.replace(with: [child]) }
            #expect(throws: error) { try storage.deleteSurplusOwned(current: [], keeping: [child]) }
            #expect(throws: error) {
                try storage.reconcileOwned(
                    [field(7, "Should not be applied")],
                    current: [child],
                    dtoId: \CustomFieldDTO.CustomFieldID,
                    entityId: \CustomFieldEntity.id,
                    create: { try storage.insert(CustomFieldEntity.self) }
                ) { _, _ in
                    Issue.record("A deleted child must not reach the update closure")
                }
            }
        }

        @Test("Reading an ordered relationship rejects the wrong entity type")
        func wrongRelationshipEntityType() async throws {
            let stack = try await makeStack()
            let storage = CoreDataStorage(context: stack.viewContext)
            let child = try storage.insert(CustomFieldEntity.self)

            #expect(throws: CoreDataStorageError.unexpectedRelationshipEntityType(expectedType: "ReservationTopicEntity")) {
                try CoreDataStorage.ordered(
                    NSOrderedSet(object: child),
                    as: ReservationTopicEntity.self
                )
            }
        }

        // MARK: - Small fixtures shared by the lifecycle tests

        private func makeStack() async throws -> CoreDataStack {
            let stack = try CoreDataStack(storage: .inMemory)
            try await stack.load()
            return stack
        }

        private func makeAppointment(id: Int, in context: NSManagedObjectContext) throws -> AppointmentEntity {
            let parent = try CoreDataStorage(context: context).insert(AppointmentEntity.self)
            parent.id = id
            parent.name = "Appointment \(id)"
            parent.statusRawValue = AppointmentStatus.planned.rawValue
            return parent
        }

        private func field(_ id: Int, _ value: String) -> CustomFieldDTO {
            CustomFieldDTO(CustomFieldID: id, FieldValue: value, FieldMultipleValues: [])
        }

        private func reconcile(
            _ dtos: [CustomFieldDTO],
            for parent: AppointmentEntity,
            using storage: CoreDataStorage
        ) throws -> [CustomFieldEntity] {
            let current = (parent.customFields?.array as? [CustomFieldEntity]) ?? []
            let incoming = try storage.reconcileOwned(
                dtos,
                current: current,
                dtoId: \CustomFieldDTO.CustomFieldID,
                entityId: \CustomFieldEntity.id,
                create: { try storage.insert(CustomFieldEntity.self) }
            ) { entity, dto in
                entity.id = dto.CustomFieldID
                entity.value = dto.FieldValue
                entity.appointment = parent
            }
            parent.customFields = try storage.replace(with: incoming)
            return incoming
        }

        private func ids(in set: NSOrderedSet) -> [Int] {
            ((set.array as? [ReservationTopicEntity]) ?? []).map(\.id)
        }

        private func count<Entity: NSManagedObject>(
            _ type: Entity.Type,
            in context: NSManagedObjectContext
        ) throws -> Int {
            try context.count(for: NSFetchRequest<Entity>(entityName: String(describing: type)))
        }
    }
}
