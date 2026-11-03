@testable import CoreDataMapping
import Foundation
import os
import Testing

/// Verifies importer contracts using small independent resource records.
/// Batches from one call do not interleave with another; a transaction either
/// commits or rolls back all its changes.
///
/// - `writeAndReadDoNotInterleave`: a queued read sees every write batch.
/// - `concurrentWritesDoNotInterleave`: a queued write waits for all first-call batches.
/// - `readPreservesBatchOrder`: read accumulates results in input ID order.
/// - `transactionCommits`: a transaction persists results for a new context.
/// - `transactionRollsBack`: failure rolls back changes without harming the next call.
/// - `emptyInputsSkipMapping`: empty writes and reads do not call the mapper.
/// - `invalidBatchSizeIsRejected`: writes and reads reject zero or negative sizes.
@MainActor
@Suite("Medical congress · importer contract")
struct CongressImporterContractTests {
    @Test("A read starts after every batch of the concurrent write")
    func writeAndReadDoNotInterleave() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let operationEnqueued = DispatchSemaphore(value: 0)
        let importer = CoreDataImporter(
            context: stack.container.newBackgroundContext(),
            onOperationEnqueued: { operationEnqueued.signal() }
        )
        let firstMapped = DispatchSemaphore(value: 0)
        let releaseWriter = DispatchSemaphore(value: 0)
        let trace = OSAllocatedUnfairLock(initialState: [String]())
        defer { releaseWriter.signal() }

        let writer = Task {
            try await importer.write([Int64(1), 2, 3], batchSize: 1) { ids, storage in
                let id = ids[0]
                let resources = try storage.upsert(ids: ids, identifiedBy: ResourceAsset.identity)
                resources[id]?.title = "Resource \(id)"
                trace.withLock { $0.append("write \(id)") }
                if id == 1 {
                    firstMapped.signal()
                    guard releaseWriter.wait(timeout: .now() + 10) == .success else {
                        throw ImporterTestError.timeout
                    }
                }
            }
        }
        try #require(await waitForSignal(firstMapped))
        try #require(await waitForSignal(operationEnqueued))

        let reader = Task {
            return try await importer.read([Int64(1), 2, 3], batchSize: 1) { ids, storage in
                trace.withLock { $0.append("read \(ids[0])") }
                let found = try storage.existing(ids: ids, identifiedBy: ResourceAsset.identity)
                return ids.compactMap { found[$0]?.title }
            }
        }
        try #require(await waitForSignal(operationEnqueued))
        releaseWriter.signal()

        try await writer.value
        let titles = try await reader.value
        #expect(titles == ["Resource 1", "Resource 2", "Resource 3"])
        #expect(trace.withLock { $0 } == [
            "write 1", "write 2", "write 3", "read 1", "read 2", "read 3"
        ])
        stack.resetViewContext()
        #expect(try stack.count(ResourceAsset.self) == 3)
    }

    @Test("Concurrent writes keep each call's batches together")
    func concurrentWritesDoNotInterleave() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let operationEnqueued = DispatchSemaphore(value: 0)
        let importer = CoreDataImporter(
            context: stack.container.newBackgroundContext(),
            onOperationEnqueued: { operationEnqueued.signal() }
        )
        let firstMapped = DispatchSemaphore(value: 0)
        let releaseFirst = DispatchSemaphore(value: 0)
        let trace = OSAllocatedUnfairLock(initialState: [String]())
        defer { releaseFirst.signal() }

        let first = Task {
            try await importer.write([Int64(1), 2, 3], batchSize: 1) { ids, storage in
                let id = ids[0]
                let resources = try storage.upsert(ids: ids, identifiedBy: ResourceAsset.identity)
                resources[id]?.title = "First \(id)"
                trace.withLock { $0.append("first \(id)") }
                if id == 1 {
                    firstMapped.signal()
                    guard releaseFirst.wait(timeout: .now() + 10) == .success else {
                        throw ImporterTestError.timeout
                    }
                }
            }
        }
        try #require(await waitForSignal(firstMapped))
        try #require(await waitForSignal(operationEnqueued))

        let second = Task {
            try await importer.write([Int64(4), 5], batchSize: 1) { ids, storage in
                let id = ids[0]
                let resources = try storage.upsert(ids: ids, identifiedBy: ResourceAsset.identity)
                resources[id]?.title = "Second \(id)"
                trace.withLock { $0.append("second \(id)") }
            }
        }
        try #require(await waitForSignal(operationEnqueued))
        releaseFirst.signal()

        try await first.value
        try await second.value
        #expect(trace.withLock { $0 } == [
            "first 1", "first 2", "first 3", "second 4", "second 5"
        ])
        stack.resetViewContext()
        #expect(try stack.count(ResourceAsset.self) == 5)
    }

    @Test("Read results retain input order across batches and omit missing IDs")
    func readPreservesBatchOrder() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        try await stack.importer.write([Int64(1), 2, 3, 4], batchSize: 2) { ids, storage in
            let resources = try storage.upsert(ids: ids, identifiedBy: ResourceAsset.identity)
            for id in ids { resources[id]?.title = "Resource \(id)" }
        }

        let batches = OSAllocatedUnfairLock(initialState: [[Int64]]())
        let titles = try await stack.importer.read([Int64(4), 2, 99, 1], batchSize: 2) {
            ids, storage in
            batches.withLock { $0.append(ids) }
            let found = try storage.existing(ids: ids, identifiedBy: ResourceAsset.identity)
            return ids.compactMap { found[$0]?.title }
        }
        #expect(batches.withLock { $0 } == [[4, 2], [99, 1]])
        #expect(titles == ["Resource 4", "Resource 2", "Resource 1"])
    }

    @Test("Transaction commits a value visible after a context reset")
    func transactionCommits() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let id = try await stack.importer.transaction { context in
            let resource = try CoreDataStorage(context: context).insert(ResourceAsset.self)
            resource.id = 7
            resource.title = "Committed"
            return resource.id
        }
        #expect(id == 7)
        stack.resetViewContext()
        let resource = try #require(stack.fetch(ResourceAsset.self).first)
        #expect(resource.id == 7)
        #expect(resource.title == "Committed")
    }

    @Test("Failed transaction rolls back and the importer accepts a retry")
    func transactionRollsBack() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        try await stack.importer.write([Int64(7)]) { ids, storage in
            let resource = try storage.upsert(ids: ids, identifiedBy: ResourceAsset.identity)
            resource[7]?.title = "Original"
        }

        await #expect(throws: ImporterTestError.aborted) {
            try await stack.importer.transaction { context -> Int64 in
                let storage = CoreDataStorage(context: context)
                let resources = try storage.upsert(
                    ids: [Int64(7), 8], identifiedBy: ResourceAsset.identity)
                resources[7]?.title = "Changed"
                resources[8]?.title = "New"
                throw ImporterTestError.aborted
            }
        }
        stack.resetViewContext()
        let afterFailure = try stack.fetch(ResourceAsset.self)
        #expect(afterFailure.count == 1)
        #expect(afterFailure.first?.id == 7)
        #expect(afterFailure.first?.title == "Original")

        try await stack.importer.transaction { context in
            let storage = CoreDataStorage(context: context)
            let resources = try storage.existing(
                ids: [Int64(7)], identifiedBy: ResourceAsset.identity)
            resources[7]?.title = "Retried"
        }
        stack.resetViewContext()
        #expect(try stack.fetch(ResourceAsset.self).first?.title == "Retried")
    }

    @Test("Empty write and read inputs skip mapping")
    func emptyInputsSkipMapping() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let calls = OSAllocatedUnfairLock(initialState: 0)
        try await stack.importer.write([Int64]()) { _, _ in
            calls.withLock { $0 += 1 }
        }
        let values: [Int64] = try await stack.importer.read([Int64]()) { _, _ in
            calls.withLock { $0 += 1 }
            return [1]
        }
        #expect(calls.withLock { $0 } == 0)
        #expect(values.isEmpty)
        stack.resetViewContext()
        #expect(try stack.count(ResourceAsset.self) == 0)
    }

    @Test("Write and read reject zero and negative batch sizes")
    func invalidBatchSizeIsRejected() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        for size in [0, -1] {
            await #expect(throws: CoreDataImportError.invalidBatchSize(size)) {
                try await stack.importer.write([Int64(1)], batchSize: size) { _, _ in
                    Issue.record("Invalid write batch should not reach mapping")
                }
            }
            await #expect(throws: CoreDataImportError.invalidBatchSize(size)) {
                let _: [Int64] = try await stack.importer.read(
                    [Int64(1)], batchSize: size
                ) { _, _ in
                    Issue.record("Invalid read batch should not reach mapping")
                    return []
                }
            }
        }
        stack.resetViewContext()
        #expect(try stack.count(ResourceAsset.self) == 0)
    }
}

private enum ImporterTestError: Error, Equatable {
    case aborted
    case timeout
}

private func waitForSignal(_ semaphore: DispatchSemaphore) async -> Bool {
    await Task.detached {
        waitForSignalBlocking(semaphore)
    }.value
}

private func waitForSignalBlocking(_ semaphore: DispatchSemaphore) -> Bool {
    semaphore.wait(timeout: .now() + 10) == .success
}
