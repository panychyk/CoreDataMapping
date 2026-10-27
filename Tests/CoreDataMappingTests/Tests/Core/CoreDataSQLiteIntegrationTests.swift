import CoreData
import Foundation
import Testing
import CoreDataMapping

extension PersistenceTests {
    @MainActor
    @Suite("Core Data SQLite integration")
    struct CoreDataSQLiteIntegrationTests {

        @Test("Appointment SQLite repeat and changed shared and owned relationships")
        func appointmentRelationshipLifecycle() async throws {
            try await withSQLiteStack { stack in
                let first = TestDTOFactory.richAppointment(id: 1)
                let second = TestDTOFactory.richAppointment(id: 2)
                let initial = [first, second]
                try await stack.importer.write(initial) { batch, storage in
                    _ = try AppointmentEntityMapper().upsert(batch, using: storage)
                }

                @MainActor func roots() throws -> [AppointmentEntity] {
                    stack.viewContext.reset()
                    let request = NSFetchRequest<AppointmentEntity>(
                        entityName: "AppointmentEntity"
                    )
                    request.sortDescriptors = [NSSortDescriptor(key: "id", ascending: true)]
                    return try stack.viewContext.fetch(request)
                }
                let inserted = try roots()
                let originalURI = inserted[0].objectID.uriRepresentation()
                let attendeeURI = try #require(inserted[0].attendees?.first)
                    .objectID.uriRepresentation()
                let sharedUserURI = try #require(inserted[0].user)
                    .objectID.uriRepresentation()
                let sharedLocationURI = try #require(inserted[0].realLocation)
                    .objectID.uriRepresentation()
                #expect(inserted[0].user === inserted[1].user)
                #expect(inserted[0].realLocation === inserted[1].realLocation)

                try await stack.importer.write(initial) { batch, storage in
                    _ = try AppointmentEntityMapper().upsert(batch, using: storage)
                }
                let repeated = try roots()
                #expect(repeated[0].objectID.uriRepresentation() == originalURI)
                #expect(repeated[0].attendees?.contains {
                    $0.objectID.uriRepresentation() == attendeeURI
                } == true)

                let changed = TestDTOFactory.appointment(
                    id: 1,
                    attendees: [], topics: [],
                    realLocation: RealLocationDTO(
                        RealLocationID: "location-3", Name: "New",
                        Address: nil, Lat: 1, Lng: 2
                    ),
                    user: TestDTOFactory.defaultUser(id: 30_001),
                    customFields: []
                )
                try await stack.importer.write([changed]) { batch, storage in
                    _ = try AppointmentEntityMapper().upsert(batch, using: storage)
                }
                let updated = try roots()
                #expect(updated[0].objectID.uriRepresentation() == originalURI)
                #expect(updated[0].attendees?.isEmpty == true)
                #expect(updated[0].customFields?.count == 0)
                #expect(updated[0].topics?.count == 0)
                #expect(updated[0].user?.id == 30_001)
                #expect(updated[0].realLocation?.id == "location-3")
                #expect(updated[1].user?.objectID.uriRepresentation() == sharedUserURI)
                #expect(updated[1].realLocation?.objectID.uriRepresentation() == sharedLocationURI)
                #expect(updated[1].attendees?.count == 2)
                #expect(try stack.viewContext.count(for: NSFetchRequest<AppointmentAttendeeEntity>(
                    entityName: "AppointmentAttendeeEntity"
                )) == 2)
                #expect(try stack.viewContext.count(for: NSFetchRequest<UserEntity>(
                    entityName: "UserEntity"
                )) == 3)
                #expect(try stack.viewContext.count(for: NSFetchRequest<RealLocationEntity>(
                    entityName: "RealLocationEntity"
                )) == 2)
            }
        }

        @Test("Concurrent upserts keep one row for a stable identity")
        func concurrentUpsertsKeepOneRow() async throws {
            try await withSQLiteStack { stack in
                let barrier = ThreadBarrier(participantCount: 2)

                async let first: Void = upsertTopic(
                    id: 7,
                    name: "First",
                    using: stack,
                    barrier: barrier
                )
                async let second: Void = upsertTopic(
                    id: 7,
                    name: "Second",
                    using: stack,
                    barrier: barrier
                )
                _ = try await (first, second)

                #expect(try await topicCount(in: stack) == 1)
            }
        }

        @Test("Large identity lookups use bounded fetch predicates")
        func handlesLargeBatch() async throws {
            try await withSQLiteStack { stack in
                let ids = Array(1...5_000)
                let insertedCount = try await stack.importer.transaction { context in
                    let storage = CoreDataStorage(context: context)
                    let entities = try storage.upsert(
                        ids: ids,
                        identifiedBy: ReservationTopicEntity.identity,
                        fetchChunkSize: 127
                    )
                    entities.forEach { id, entity in
                        entity.name = "Topic \(id)"
                    }
                    return entities.count
                }

                let fetchedCount = try await stack.importer.transaction { context in
                    try CoreDataStorage(context: context).existing(
                        ids: ids.reversed(),
                        identifiedBy: ReservationTopicEntity.identity,
                        fetchChunkSize: 127
                    ).count
                }

                #expect(insertedCount == ids.count)
                #expect(fetchedCount == ids.count)
                #expect(try await topicCount(in: stack) == ids.count)
            }
        }

        @Test("Saving an identical DTO reuses owned custom-field values")
        func repeatedDTOReusesValues() async throws {
            try await withSQLiteStack { stack in
                let dto = appointment(
                    values: [
                        customValue("First", entityId: 101),
                        customValue("Second", entityId: 102)
                    ]
                )

                try await upsertAppointment(dto, using: stack)
                let initial = try await customValueSnapshots(
                    appointmentId: dto.RoomReservationUserID,
                    using: stack
                )

                let repeatedValueMutationCount = try await upsertAppointment(
                    dto,
                    using: stack
                )
                let repeated = try await customValueSnapshots(
                    appointmentId: dto.RoomReservationUserID,
                    using: stack
                )

                #expect(repeated == initial)
                #expect(repeatedValueMutationCount == 0)
                #expect(try await customValueCount(in: stack) == 2)
            }
        }

        @Test("Removing owned values deletes surplus children without orphans")
        func removesSurplusOwnedValues() async throws {
            try await withSQLiteStack { stack in
                let initialDTO = appointment(
                    values: [
                        customValue("Keep", entityId: 101),
                        customValue("Remove", entityId: 102)
                    ]
                )
                try await upsertAppointment(initialDTO, using: stack)
                let initial = try await customValueSnapshots(
                    appointmentId: initialDTO.RoomReservationUserID,
                    using: stack
                )

                let reducedDTO = appointment(
                    values: [customValue("Keep", entityId: 101)]
                )
                try await upsertAppointment(reducedDTO, using: stack)
                let reduced = try await customValueSnapshots(
                    appointmentId: reducedDTO.RoomReservationUserID,
                    using: stack
                )

                #expect(initial.count == 2)
                #expect(reduced.count == 1)
                #expect(reduced.first?.objectURI == initial.first?.objectURI)
                #expect(try await customValueCount(in: stack) == 1)
            }
        }

        private func upsertTopic(
            id: Int,
            name: String,
            using stack: CoreDataStack,
            barrier: ThreadBarrier
        ) async throws {
            // Independent writers deliberately exercise the store's constraint.
            // Normal repositories share stack.importer and serialize their writes.
            let importer = CoreDataImporter(
                context: stack.persistentContainer.newBackgroundContext()
            )
            try await importer.transaction { context in
                let storage = CoreDataStorage(context: context)
                let topics = try storage.upsert(
                    ids: [id],
                    identifiedBy: ReservationTopicEntity.identity
                )

                barrier.arriveAndWait()

                topics[id]!.name = name
            }
        }

        @discardableResult
        private func upsertAppointment(
            _ dto: AppointmentDTO,
            using stack: CoreDataStack
        ) async throws -> Int {
            try await stack.importer.transaction { context in
                _ = try AppointmentEntityMapper().upsert(
                    [dto],
                    using: CoreDataStorage(context: context)
                )

                return context.insertedObjects
                    .union(context.updatedObjects)
                    .union(context.deletedObjects)
                    .lazy
                    .filter { $0 is CustomFieldValueEntity }
                    .count
            }
        }

        private func customValueSnapshots(
            appointmentId: Int,
            using stack: CoreDataStack
        ) async throws -> [CustomValueSnapshot] {
            try await stack.importer.transaction { context in
                let storage = CoreDataStorage(context: context)
                guard let appointment = try storage.existing(
                    ids: [appointmentId],
                    identifiedBy: AppointmentEntity.identity
                )[appointmentId] else {
                    return []
                }

                let fields = (appointment.customFields?.array
                    as? [CustomFieldEntity]) ?? []
                let values = fields.flatMap {
                    Array($0.multipleValues ?? [])
                }
                return values
                    .sorted { $0.ordinal < $1.ordinal }
                    .map {
                        CustomValueSnapshot(
                            objectURI: $0.objectID.uriRepresentation(),
                            ordinal: $0.ordinal,
                            value: $0.value
                        )
                    }
            }
        }

        private func topicCount(in stack: CoreDataStack) async throws -> Int {
            try await stack.importer.transaction { context in
                try context.count(
                    for: NSFetchRequest<ReservationTopicEntity>(
                        entityName: "ReservationTopicEntity"
                    )
                )
            }
        }

        private func customValueCount(in stack: CoreDataStack) async throws -> Int {
            try await stack.importer.transaction { context in
                try context.count(
                    for: NSFetchRequest<CustomFieldValueEntity>(
                        entityName: "CustomFieldValueEntity"
                    )
                )
            }
        }

        private func appointment(
            values: [CustomFieldValueDTO]
        ) -> AppointmentDTO {
            TestDTOFactory.appointment(
                customFields: [
                    CustomFieldDTO(
                        CustomFieldID: 7,
                        FieldValue: nil,
                        FieldMultipleValues: values
                    )
                ]
            )
        }

        private func customValue(
            _ value: String,
            entityId: Int
        ) -> CustomFieldValueDTO {
            CustomFieldValueDTO(
                FieldValue: value,
                FieldValueEntityID: entityId,
                FieldValueEntityType: .CompanyCustomer
            )
        }

        private func withSQLiteStack<T>(
            _ operation: (CoreDataStack) async throws -> T
        ) async throws -> T {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            defer { try? FileManager.default.removeItem(at: directory) }

            let stack = try CoreDataStack(
                storage: .persistent,
                storeURL: directory.appendingPathComponent("Integration.sqlite")
            )
            try await stack.load()
            return try await operation(stack)
        }
    }
}

private nonisolated struct CustomValueSnapshot: Equatable, Sendable {
    let objectURI: URL
    let ordinal: Int
    let value: String?
}

private nonisolated final class ThreadBarrier: @unchecked Sendable {
    private let condition = NSCondition()
    private var remainingParticipants: Int

    init(participantCount: Int) {
        remainingParticipants = participantCount
    }

    func arriveAndWait() {
        condition.lock()
        remainingParticipants -= 1

        if remainingParticipants == 0 {
            condition.broadcast()
        } else {
            while remainingParticipants > 0 {
                condition.wait()
            }
        }

        condition.unlock()
    }
}
