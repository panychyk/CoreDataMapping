import CoreData
import CoreDataMapping
import Foundation
import Testing

/// Verifies that failures and cancellation leave no unfinished changes and
/// concurrent imports do not interfere. Earlier committed data remains available.
///
/// - `duplicateOwnedID`: a duplicate local ID rejects a batch without changing the graph.
/// - `missingReference`: a missing room rolls back the current update.
/// - `failedBatch`: failure in the second batch preserves the committed first batch.
/// - `saveFailureRollbackAndRetry`: a Core Data save failure rolls back the entire
///   batch; the same importer writes the next snapshot successfully.
/// - `cancellationRollback`: cancellation rolls back the active batch and
///   preserves the previous save.
/// - `readRollback`: mutation during `read` is rejected without writing.
/// - `concurrentImports`: one importer serializes writes to two events.
@MainActor
@Suite("Medical congress · import transactions")
struct CongressTransactionsTests {
    @Test("Duplicate appointment IDs reject the batch and preserve the saved graph")
    func duplicateOwnedID() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let original = CongressGraphFixture.congress()
        try await stack.write(original)
        var invalid = original
        invalid.events[0].appointments.append(invalid.events[0].appointments[0])
        await #expect(
            throws: CoreDataStorageError.duplicateOwnedIdentity(
                entityName: "Appointment", id: "1"
            )
        ) {
            try await stack.write(invalid)
        }
        try GraphAssertions.matches(original, in: stack)
    }

    @Test("A missing shared room rolls back the whole update")
    func missingReference() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let original = CongressGraphFixture.congress()
        try await stack.write(original)

        var invalid = original
        invalid.events[0].appointments[0].roomID = 999
        await #expect(throws: GraphFixtureError.missingReference(entity: "Room", id: 999)) {
            try await stack.write(invalid)
        }
        try GraphAssertions.matches(original, in: stack)
    }

    @Test("A failed second batch retains the first committed event")
    func failedBatch() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        enum ExpectedFailure: Error { case secondBatch }
        let full = CongressGraphFixture.congress()
        var first = full
        first.events = [full.events[0]]
        var second = full
        second.events = [full.events[1]]
        do {
            try await stack.importer.write([first, second], batchSize: 1) { batch, storage in
                try GraphWriter.write(batch, using: storage)
                if batch[0].events[0].id == 41 { throw ExpectedFailure.secondBatch }
            }
            Issue.record("The second batch should fail")
        } catch ExpectedFailure.secondBatch {}
        try GraphAssertions.matches(first, in: stack)
    }

    @Test("A Core Data save failure rolls back the batch and the importer can retry")
    func saveFailureRollbackAndRetry() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let original = CongressGraphFixture.congress()
        try await stack.write(original)

        var changed = original
        changed.events[0].title = "Updated after retry"
        changed.resources[0].title = "Updated resource after retry"

        do {
            try await stack.importer.write([changed]) { batch, storage in
                try GraphWriter.write(batch, using: storage)
                let invalid = try storage.insert(ResourceAsset.self)
                invalid.setPrimitiveValue(nil, forKey: "id")
            }
            Issue.record("Saving a resource without its required ID should fail")
        } catch {
            let error = error as NSError
            #expect(error.domain == NSCocoaErrorDomain)
            #expect(error.code == NSValidationMissingMandatoryPropertyError)
        }

        try GraphAssertions.matches(original, in: stack)

        try await stack.write(changed)
        try GraphAssertions.matches(changed, in: stack)
    }

    @Test("Cancellation rolls back the active batch and retains the prior save")
    func cancellationRollback() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let original = CongressGraphFixture.congress()
        try await stack.write(original)

        var changed = original
        changed.events[0].title = "This update must roll back"
        let importer = stack.importer
        let mapped = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let task = Task {
            try await importer.write([changed]) { batch, storage in
                try GraphWriter.write(batch, using: storage)
                mapped.signal()
                release.wait()
            }
        }
        let entered = await Task.detached {
            waitForMapping(mapped)
        }.value
        #expect(entered)
        task.cancel()
        release.signal()
        await #expect(throws: CancellationError.self) { try await task.value }
        try GraphAssertions.matches(original, in: stack)
    }

    @Test("Mutation during read fails without saving")
    func readRollback() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        await #expect(throws: CoreDataImportError.mutationDuringRead) {
            try await stack.importer.read([Int64(30)]) { ids, storage in
                _ = try storage.upsert(ids: ids, identifiedBy: ResourceAsset.identity)
                return [Int64]()
            }
        }
        #expect(try stack.count(ResourceAsset.self) == 0)
    }

    @Test("One importer serializes concurrent event writes")
    func concurrentImports() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let graph = CongressGraphFixture.congress()
        let importer = stack.importer
        try await withThrowingTaskGroup(of: Void.self) { group in
            for event in graph.events {
                var partial = graph
                partial.events = [event]
                group.addTask {
                    try await importer.write([partial]) { batch, storage in
                        try GraphWriter.write(batch, using: storage)
                    }
                }
            }
            try await group.waitForAll()
        }
        try GraphAssertions.matches(graph, in: stack)
    }
}

private func waitForMapping(_ semaphore: DispatchSemaphore) -> Bool {
    semaphore.wait(timeout: .now() + 5) == .success
}
