import CoreData
import Foundation
import Testing
import CoreDataMapping

extension PersistenceTests {
    @MainActor
    @Suite("Core Data importer lifecycle")
    struct CoreDataImporterTests {
        @Test("Validates batch size and skips empty imports")
        func validatesInput() async throws {
            try await withSQLiteStack { stack in
                let empty: [Int] = []
                try await stack.importer.write(empty) { _, _ in
                    Issue.record("Empty input must not invoke the mapper")
                }
                let values: [Int] = try await stack.importer.read(empty) { _, _ in
                    Issue.record("Empty input must not invoke the mapper")
                    return [1]
                }
                #expect(values.isEmpty)

                for batchSize in [0, -1] {
                    do {
                        try await stack.importer.write(empty, batchSize: batchSize) { _, _ in }
                        Issue.record("Expected invalid batch size to be rejected")
                    } catch {
                        #expect(error as? CoreDataImportError == .invalidBatchSize(batchSize))
                    }
                }
            }
        }

        @Test("Saves bounded chunks, resets the graph, and returns ordered values")
        func savesChunksAndResetsContext() async throws {
            try await withSQLiteStack { stack in
                try await stack.importer.write(
                    Array(1...5), batchSize: 2
                ) { ids, storage in
                    #expect(storage.context.registeredObjects.isEmpty)
                    #expect(storage.context.undoManager == nil)
                    let topics = try storage.upsert(
                        ids: ids, identifiedBy: ReservationTopicEntity.identity
                    )
                    for id in ids { topics[id]?.name = "Topic \(id)" }
                }
                let batches = try await stack.importer.read(Array(1...5), batchSize: 2) { ids, storage in
                    #expect(storage.context.registeredObjects.isEmpty)
                    let topics = try storage.existing(ids: ids, identifiedBy: ReservationTopicEntity.identity)
                    return [ids.filter { topics[$0] != nil }]
                }
                #expect(batches == [[1, 2], [3, 4], [5]])
                #expect(try topicIds(in: stack) == [1, 2, 3, 4, 5])
                try await stack.importer.write([6]) { ids, storage in
                    #expect(storage.context.registeredObjects.isEmpty)
                    _ = try storage.upsert(ids: ids, identifiedBy: ReservationTopicEntity.identity)
                }
                #expect(try topicIds(in: stack) == [1, 2, 3, 4, 5, 6])
            }
        }

        @Test("Reads reject mutations and discard them before the next operation")
        func rejectsReadMutations() async throws {
            try await withSQLiteStack { stack in
                try await stack.importer.write([1]) { ids, storage in
                    let topics = try storage.upsert(ids: ids, identifiedBy: ReservationTopicEntity.identity)
                    topics[1]?.name = "Original"
                }
                do {
                    let _: [Int] = try await stack.importer.read([1]) { ids, storage in
                        let topics = try storage.existing(ids: ids, identifiedBy: ReservationTopicEntity.identity)
                        topics[1]?.name = "Must not persist"
                        return ids
                    }
                    Issue.record("Expected read mutation to be rejected")
                } catch {
                    #expect(error as? CoreDataImportError == .mutationDuringRead)
                }
                let names = try await stack.importer.read([1]) { ids, storage in
                    #expect(storage.context.registeredObjects.isEmpty)
                    let topics = try storage.existing(ids: ids, identifiedBy: ReservationTopicEntity.identity)
                    return ids.compactMap { topics[$0]?.name }
                }
                #expect(names == ["Original"])
            }
        }

        @Test("A mapping error rolls back only its chunk and permits another import")
        func rollsBackFailedChunk() async throws {
            try await withSQLiteStack { stack in
                do {
                    try await stack.importer.write([1, 2, 3], batchSize: 1) { ids, storage in
                        _ = try storage.upsert(ids: ids, identifiedBy: ReservationTopicEntity.identity)
                        if ids == [2] { throw ImportTestError.mapping }
                    }
                    Issue.record("Expected the mapper failure")
                } catch {
                    #expect(error as? ImportTestError == .mapping)
                }
                #expect(try topicIds(in: stack) == [1])

                try await stack.importer.write([3]) { ids, storage in
                    #expect(storage.context.registeredObjects.isEmpty)
                    _ = try storage.upsert(ids: ids, identifiedBy: ReservationTopicEntity.identity)
                }
                #expect(try topicIds(in: stack) == [1, 3])
            }
        }

        @Test("A save validation failure preserves earlier committed chunks")
        func rollsBackSaveFailure() async throws {
            try await withSQLiteStack { stack in
                do {
                    try await stack.importer.write([1, 2, 3], batchSize: 1) { ids, storage in
                        _ = try storage.upsert(ids: ids, identifiedBy: ReservationTopicEntity.identity)
                        if ids == [2] {
                            let invalid = try storage.insert(RealLocationEntity.self)
                            invalid.setValue(nil, forKey: #keyPath(RealLocationEntity.id))
                        }
                    }
                    Issue.record("Expected Core Data to reject the required missing identity")
                } catch {
                    let failure = error as NSError
                    #expect(failure.domain == NSCocoaErrorDomain)
                    #expect(
                        failure.code == NSValidationMissingMandatoryPropertyError
                            || failure.code == NSValidationMultipleErrorsError
                    )
                }
                #expect(try topicIds(in: stack) == [1])
                #expect(try count("RealLocationEntity", in: stack) == 0)
                try await stack.importer.write([4]) { ids, storage in
                    _ = try storage.upsert(ids: ids, identifiedBy: ReservationTopicEntity.identity)
                }
                #expect(try topicIds(in: stack) == [1, 4])
            }
        }

        @Test("Cancellation before execution does not invoke the mapper")
        func cancelsBeforeExecution() async throws {
            try await withSQLiteStack { stack in
                let importer = stack.importer
                let task = Task { @MainActor in
                    try await importer.write([1]) { _, _ in
                        Issue.record("A cancelled import must not map its first chunk")
                    }
                }
                task.cancel()
                do {
                    try await task.value
                    Issue.record("Expected cancellation")
                } catch {
                    #expect(error is CancellationError)
                }
                let storedIds = try topicIds(in: stack)
                #expect(storedIds.isEmpty)
            }
        }

        @Test("Cancellation during mapping rolls back the active chunk before saving")
        func cancelsBeforeSave() async throws {
            try await withSQLiteStack { stack in
                let importer = stack.importer
                let entered = AsyncStream<Void>.makeStream()
                let release = DispatchSemaphore(value: 0)
                let task = Task {
                    try await importer.write([1, 2, 3], batchSize: 1) { ids, storage in
                        _ = try storage.upsert(ids: ids, identifiedBy: ReservationTopicEntity.identity)
                        if ids == [2] {
                            entered.continuation.yield(())
                            release.wait()
                        }
                    }
                }
                for await _ in entered.stream {
                    task.cancel()
                    release.signal()
                    break
                }
                entered.continuation.finish()
                do {
                    try await task.value
                    Issue.record("Expected cancellation")
                } catch {
                    #expect(error is CancellationError)
                }
                let storedIds = try topicIds(in: stack)
                #expect(storedIds == [1])
            }
        }

        @Test("Repeated graphs across chunks retain owned identities and shared links")
        func repeatsGraphAcrossChunks() async throws {
            try await withSQLiteStack { stack in
                let dtos = (1...5).map { appointment(id: $0, value: "Value \($0)") }
                for _ in 0..<2 {
                    try await stack.importer.write(dtos, batchSize: 2) { batch, storage in
                        _ = try AppointmentEntityMapper().upsert(batch, using: storage)
                    }
                    #expect(try count("AppointmentEntity", in: stack) == 5)
                    #expect(try count("ReservationTopicEntity", in: stack) == 1)
                    #expect(try count("CustomFieldEntity", in: stack) == 5)
                    #expect(try count("CustomFieldValueEntity", in: stack) == 5)
                }
                let initialIds = try valueObjectIds(in: stack)
                try await stack.importer.write(dtos, batchSize: 3) { batch, storage in
                    _ = try AppointmentEntityMapper().upsert(batch, using: storage)
                }
                #expect(try valueObjectIds(in: stack) == initialIds)
                let request = NSFetchRequest<AppointmentEntity>(entityName: "AppointmentEntity")
                let appointments = try stack.viewContext.fetch(request)
                #expect(appointments.allSatisfy { $0.user?.id == 10_001 })
                #expect(appointments.first?.user?.appointments?.count == 5)
            }
        }

        @Test("Overlapping imports serialize complete calls and preserve owned graphs")
        func serializesOverlappingImports() async throws {
            try await withSQLiteStack { stack in
                let importer = stack.importer
                let first = (1...3).map { appointment(id: $0, value: "First") }
                let second = (1...3).map { appointment(id: $0, value: "Second") }
                let probe = ImportOrderProbe()
                async let firstImport: Void = importer.write(first, batchSize: 1) { batch, storage in
                    probe.record("First")
                    _ = try AppointmentEntityMapper().upsert(batch, using: storage)
                }
                async let secondImport: Void = importer.write(second, batchSize: 1) { batch, storage in
                    probe.record("Second")
                    _ = try AppointmentEntityMapper().upsert(batch, using: storage)
                }
                _ = try await (firstImport, secondImport)
                let order = probe.values
                #expect(
                    order == ["First", "First", "First", "Second", "Second", "Second"]
                        || order == ["Second", "Second", "Second", "First", "First", "First"]
                )
                #expect(try count("AppointmentEntity", in: stack) == 3)
                #expect(try count("CustomFieldEntity", in: stack) == 3)
                #expect(try count("CustomFieldValueEntity", in: stack) == 3)
                let request = NSFetchRequest<CustomFieldValueEntity>(entityName: "CustomFieldValueEntity")
                let values = try stack.viewContext.fetch(request)
                #expect(Set(values.compactMap(\.value)) == Set(order.last.map { [$0] } ?? []))
                #expect(values.allSatisfy { $0.customField?.appointment != nil })
            }
        }

        @Test("A large SQLite graph survives import, repeat, removals, and reopening")
        func largeGraphLifecycle() async throws {
            try await withSQLiteStack { stack in
                let dtos = (1...1_000).map(TestDTOFactory.richAppointment)
                let start = ContinuousClock.now
                try await stack.importer.write(dtos, batchSize: 100) { batch, storage in
                    #expect(storage.context.registeredObjects.isEmpty)
                    _ = try AppointmentEntityMapper().upsert(batch, using: storage)
                }
                let firstDuration = start.duration(to: .now)
                #expect(try count("AppointmentEntity", in: stack) == 1_000)
                #expect(try count("AppointmentAttendeeEntity", in: stack) == 2_000)
                #expect(try count("CustomFieldEntity", in: stack) == 2_000)
                #expect(try count("CustomFieldValueEntity", in: stack) == 6_000)
                #expect(try count("ReservationTopicEntity", in: stack) == 3)
                #expect(try count("UserEntity", in: stack) == 2)
                let originalValueIds = try valueObjectIds(in: stack)

                let repeatStart = ContinuousClock.now
                try await stack.importer.write(dtos, batchSize: 127) { batch, storage in
                    #expect(storage.context.registeredObjects.isEmpty)
                    _ = try AppointmentEntityMapper().upsert(batch, using: storage)
                }
                let repeatDuration = repeatStart.duration(to: .now)
                #expect(try valueObjectIds(in: stack) == originalValueIds)

                // A full empty snapshot removes only root 1's owned subgraph.
                try await stack.importer.write([TestDTOFactory.appointment(id: 1, name: "Updated")]) { batch, storage in
                    _ = try AppointmentEntityMapper().upsert(batch, using: storage)
                }
                #expect(try count("AppointmentAttendeeEntity", in: stack) == 1_998)
                #expect(try count("CustomFieldEntity", in: stack) == 1_998)
                #expect(try count("CustomFieldValueEntity", in: stack) == 5_994)
                #expect(try count("ReservationTopicEntity", in: stack) == 3)
                #expect(try count("UserEntity", in: stack) == 2)

                let coordinator = stack.persistentContainer.persistentStoreCoordinator
                let store = try #require(coordinator.persistentStores.first)
                let url = try #require(store.url)
                stack.viewContext.reset()
                try coordinator.remove(store)
                let reopened = try CoreDataStack(storage: .persistent, storeURL: url)
                try await reopened.load()
                let summaries = try await reopened.importer.read([1, 1_000]) { ids, storage in
                    let roots = try storage.existing(
                        ids: ids,
                        identifiedBy: AppointmentEntity.identity,
                        prefetching: ["topics", "realLocation", "customFields.multipleValues"]
                    )
                    return try ids.map { try AppointmentEntityMapper().map(roots[$0]!) }
                }
                #expect(summaries.first?.name == "Updated")
                #expect(summaries.first?.customFields?.isEmpty == true)
                #expect(summaries.last == AppointmentSummaryMapper().map(dtos[999]))
                #expect(try count("CustomFieldValueEntity", in: reopened) == 5_994)
                print("SQLite graph: 1,000 roots / 11,007 rows; initial \(firstDuration), repeat \(repeatDuration)")
                for store in reopened.persistentContainer.persistentStoreCoordinator.persistentStores {
                    try reopened.persistentContainer.persistentStoreCoordinator.remove(store)
                }
            }
        }

        private func appointment(id: Int, value: String) -> AppointmentDTO {
            TestDTOFactory.appointment(
                id: id,
                topics: [ReservationTopicDTO(ReservationTopicID: 7, Name: "Shared")],
                customFields: [CustomFieldDTO(
                    CustomFieldID: 7,
                    FieldValue: nil,
                    FieldMultipleValues: [CustomFieldValueDTO(
                        FieldValue: value,
                        FieldValueEntityID: nil,
                        FieldValueEntityType: .CompanyCustomer
                    )]
                )]
            )
        }

        private func topicIds(in stack: CoreDataStack) throws -> [Int] {
            stack.viewContext.reset()
            let request = NSFetchRequest<ReservationTopicEntity>(entityName: "ReservationTopicEntity")
            return try stack.viewContext.fetch(request).map(\.id).sorted()
        }

        private func count(_ entityName: String, in stack: CoreDataStack) throws -> Int {
            stack.viewContext.reset()
            return try stack.viewContext.count(for: NSFetchRequest<NSManagedObject>(entityName: entityName))
        }

        private func valueObjectIds(in stack: CoreDataStack) throws -> Set<URL> {
            stack.viewContext.reset()
            let request = NSFetchRequest<CustomFieldValueEntity>(entityName: "CustomFieldValueEntity")
            return Set(try stack.viewContext.fetch(request).map { $0.objectID.uriRepresentation() })
        }

        private func withSQLiteStack(
            _ operation: (CoreDataStack) async throws -> Void
        ) async throws {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let stack = try CoreDataStack(
                storage: .persistent,
                storeURL: directory.appendingPathComponent("Importer.sqlite")
            )
            try await stack.load()
            try await operation(stack)
        }
    }
}

private nonisolated enum ImportTestError: Error, Equatable {
    case mapping
}

private nonisolated final class ImportOrderProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedValues: [String] = []

    var values: [String] { lock.withLock { recordedValues } }

    func record(_ value: String) {
        lock.withLock { recordedValues.append(value) }
    }
}
