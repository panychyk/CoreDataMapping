import CoreData
import CoreDataMapping
import Foundation
import Testing

@MainActor
@Suite("Storage and importer contracts")
struct CoreOperationsTests {
    @Test("Identity lookup, duplicate input and bounded batches keep one row per ID")
    func batchLookupDeduplicatesIDs() async throws {
        let stack = try CoreDataTestStack()
        try await stack.load()
        try await stack.importer.write([Int64(1), 2, 1, 3], batchSize: 2) { ids, storage in
            let resources = try storage.upsert(ids: ids, identifiedBy: Resource.identity, fetchChunkSize: 1)
            for id in ids { resources[id]!.label = "resource-\(id)" }
        }
        let found = try await stack.importer.read([Int64(3), 1, 9], batchSize: 2) { ids, storage in
            let resources = try storage.existing(ids: ids, identifiedBy: Resource.identity, fetchChunkSize: 1)
            return ids.compactMap { resources[$0]?.id }
        }
        #expect(found == [3, 1])
        #expect(try stack.count(Resource.self) == 3)
        #expect(Set(try stack.fetch(Resource.self).map(\.id)) == [1, 2, 3])
    }

    @Test("Invalid input and mutation during read fail without saving changes")
    func invalidOperationsDoNotCommit() async throws {
        let stack = try CoreDataTestStack()
        try await stack.load()
        await #expect(throws: CoreDataImportError.invalidBatchSize(0)) {
            try await stack.importer.write([1], batchSize: 0) { _, _ in }
        }
        await #expect(throws: CoreDataStorageError.invalidFetchChunkSize(0)) {
            try await stack.importer.read([Int64(1)]) { _, storage in
                _ = try storage.existing(ids: [Int64](), identifiedBy: Resource.identity, fetchChunkSize: 0)
                return [Int]()
            }
        }
        await #expect(throws: CoreDataImportError.mutationDuringRead) {
            try await stack.importer.read([Int64(1)]) { ids, storage in
                _ = try storage.upsert(ids: ids, identifiedBy: Resource.identity)
                return [Int]()
            }
        }
        #expect(try stack.count(Resource.self) == 0)
    }

    @Test("Cancellation after mapping rolls back the active batch")
    func cancellationRollsBackCurrentBatch() async throws {
        let stack = try CoreDataTestStack()
        try await stack.load()
        let importer = stack.importer
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let task = Task {
            try await importer.write([GraphCases.root(.document, id: 1)]) { batch, storage in
                try GraphWriter.write(batch, using: storage)
                entered.signal()
                release.wait()
            }
        }
        let signalled = await Task.detached {
            waitForSignal(entered)
        }.value
        #expect(signalled)
        task.cancel()
        release.signal()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try stack.count(Document.self) == 0)
        #expect(try stack.count(Section.self) == 0)
        #expect(try stack.count(Resource.self) == 0)
    }

    @Test("Duplicate section IDs within one document are rejected before save")
    func duplicateSectionIDRollsBack() async throws {
        let stack = try CoreDataTestStack()
        try await stack.load()
        let section = SectionSnapshot(id: 1, title: "one", entries: [])
        let input = RootSnapshot(kind: .document, id: 1, title: "bad", resourceIDs: [], sections: [section, section])
        await #expect(throws: CoreDataStorageError.duplicateOwnedIdentity(entityName: "Section", id: "1")) {
            try await stack.importer.write([input]) { batch, storage in
                try GraphWriter.write(batch, using: storage)
            }
        }
        #expect(try stack.count(Document.self) == 0)
        #expect(try stack.count(Section.self) == 0)
    }
    @Test("Failure rolls back its batch and leaves prior batches committed")
    func failedBatchPreservesEarlierCommits() async throws {
        enum Failure: Error { case expected }
        let stack = try CoreDataTestStack()
        try await stack.load()
        let values = (1...3).map { GraphCases.root(.document, id: Int64($0)) }
        do {
            try await stack.importer.write(values, batchSize: 1) { batch, storage in
                try GraphWriter.write(batch, using: storage)
                if batch[0].id == 2 { throw Failure.expected }
            }
            Issue.record("The second batch should fail")
        } catch Failure.expected {}
        try GraphAssertions.matches([values[0]], in: stack)
        try await stack.writeGraph(Array(values.dropFirst()))
        try GraphAssertions.matches(values, in: stack)
    }

}

private func waitForSignal(_ semaphore: DispatchSemaphore) -> Bool {
    semaphore.wait(timeout: .now() + 5) == .success
}
