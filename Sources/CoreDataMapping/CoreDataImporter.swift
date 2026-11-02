import CoreData
import os

public nonisolated enum CoreDataImportError: Error, Equatable {
    case invalidBatchSize(Int)
    case mutationDuringRead
}

/// Serializes imports on a dedicated private, store-backed context. Do not
/// schedule other work on that context outside this importer. All access is
/// confined to `perform`; only Sendable values leave its queue.
/// Share one importer between repositories that write overlapping graphs.
public nonisolated final class CoreDataImporter: @unchecked Sendable {
    public static let defaultBatchSize = 500

    private let context: NSManagedObjectContext
    private let onOperationEnqueued: (@Sendable () -> Void)?

    public init(context: NSManagedObjectContext) {
        Self.validate(context)
        self.context = context
        self.onOperationEnqueued = nil
    }

    // Lets contract tests observe actual queue admission without exposing a public hook.
    internal init(
        context: NSManagedObjectContext,
        onOperationEnqueued: @escaping @Sendable () -> Void
    ) {
        Self.validate(context)
        self.context = context
        self.onOperationEnqueued = onOperationEnqueued
    }

    private static func validate(_ context: NSManagedObjectContext) {
        context.performAndWait {
            precondition(
                context.concurrencyType == .privateQueueConcurrencyType,
                "CoreDataImporter requires a private-queue context"
            )
            precondition(
                context.parent == nil && context.persistentStoreCoordinator != nil,
                "CoreDataImporter requires a context connected directly to a store coordinator"
            )
        }
    }

    /// Commits complete graphs in bounded root batches. A failed or cancelled
    /// batch is rolled back; earlier committed batches remain available to retry.
    /// The mapper must not save/reset the context or let managed objects escape.
    public func write<DTO: Sendable>(
        _ dtos: [DTO],
        batchSize: Int = CoreDataImporter.defaultBatchSize,
        map: @escaping @Sendable ([DTO], CoreDataStorage) throws -> Void
    ) async throws {
        let _: [Void] = try await process(dtos, batchSize: batchSize) { batch, storage in
            try map(batch, storage)
            return []
        }
    }

    /// Reads bounded batches on the same queue as writes. Call after `write` to
    /// project the final graph, including shared objects changed by later batches.
    /// Managed objects are reset after each batch; returned values accumulate.
    public func read<Input: Sendable, Value: Sendable>(
        _ inputs: [Input],
        batchSize: Int = CoreDataImporter.defaultBatchSize,
        map: @escaping @Sendable ([Input], CoreDataStorage) throws -> [Value]
    ) async throws -> [Value] {
        try await process(inputs, batchSize: batchSize) { batch, storage in
            let values = try map(batch, storage)
            guard !storage.context.hasChanges else {
                throw CoreDataImportError.mutationDuringRead
            }
            return values
        }
    }

    private func process<DTO: Sendable, Value: Sendable>(
        _ dtos: [DTO],
        batchSize: Int = CoreDataImporter.defaultBatchSize,
        map: @escaping @Sendable ([DTO], CoreDataStorage) throws -> [Value]
    ) async throws -> [Value] {
        guard batchSize > 0 else {
            throw CoreDataImportError.invalidBatchSize(batchSize)
        }
        return try await perform { context, cancellation in
            var result: [Value] = []
            for start in stride(from: 0, to: dtos.count, by: batchSize) {
                try autoreleasepool {
                    try Self.checkCancellation(cancellation)
                    let end = start + min(batchSize, dtos.count - start)
                    let values = try map(Array(dtos[start..<end]), CoreDataStorage(context: context))
                    try Self.checkCancellation(cancellation)
                    if context.hasChanges {
                        try context.save()
                    }
                    result.append(contentsOf: values)
                    context.reset()
                }
            }
            return result
        }
    }

    /// One atomic operation for small writes and reads.
    public func transaction<Value: Sendable>(
        _ operation: @escaping @Sendable (NSManagedObjectContext) throws -> Value
    ) async throws -> Value {
        try await perform { context, cancellation in
            let value = try operation(context)
            try Self.checkCancellation(cancellation)
            if context.hasChanges {
                try context.save()
            }
            return value
        }
    }

    private func perform<Value: Sendable>(
        _ operation: @escaping @Sendable (
            NSManagedObjectContext, OSAllocatedUnfairLock<Bool>
        ) throws -> Value
    ) async throws -> Value {
        let cancellation = OSAllocatedUnfairLock(initialState: false)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                context.perform { [context] in
                    context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
                    context.undoManager = nil
                    let result: Result<Value, Error>
                    do {
                        try Self.checkCancellation(cancellation)
                        result = .success(try operation(context, cancellation))
                    } catch {
                        context.rollback()
                        result = .failure(error)
                    }
                    context.reset()
                    continuation.resume(with: result)
                }
                onOperationEnqueued?()
            }
        } onCancel: {
            cancellation.withLock { $0 = true }
        }
    }

    private static func checkCancellation(_ cancellation: OSAllocatedUnfairLock<Bool>) throws {
        if cancellation.withLock({ $0 }) {
            throw CancellationError()
        }
    }
}
