import CoreData
import CoreDataMapping
import Foundation
import Testing

/// Verifies fetch request counts during repeated congress graph imports. More
/// events or owned children must not add fetches inside mapping loops.
///
/// - `fetchCountDoesNotGrowWithEvents`: importing eight events again uses the
///   same number of fetches as importing one event again.
/// - `fetchCountDoesNotGrowWithSessions`: importing an event with eight sessions
///   again uses the same number of fetches as with one session.
@MainActor
@Suite("Medical congress · fetch performance")
struct CongressFetchPerformanceTests {
    @Test("Fetch request count stays flat as event graphs grow")
    func fetchCountDoesNotGrowWithEvents() async throws {
        let modelURL = try #require(Bundle.module.url(
            forResource: "TestModel", withExtension: "momd"))
        let model = try #require(NSManagedObjectModel(contentsOf: modelURL))
        let coordinator = CountingFetchCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(
            ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        let importer = CoreDataImporter(context: context)

        var small = CongressGraphFixture.congress()
        small.events = [small.events[0]]
        try await write(small, using: importer)
        coordinator.resetFetchCount()
        try await write(small, using: importer)
        let smallFetchCount = coordinator.fetchCount
        #expect(smallFetchCount > 0)

        var large = small
        large.events = (0..<8).map { index in
            var event = small.events[0]
            event.id = Int64(40 + index)
            event.title = "Event \(index)"
            return event
        }
        try await write(large, using: importer)
        coordinator.resetFetchCount()
        try await write(large, using: importer)
        let largeFetchCount = coordinator.fetchCount

        #expect(largeFetchCount == smallFetchCount)

        let readContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        readContext.persistentStoreCoordinator = coordinator
        #expect(try readContext.count(
            for: NSFetchRequest<CongressEvent>(entityName: "CongressEvent")) == 8)
        #expect(try readContext.count(
            for: NSFetchRequest<Session>(entityName: "Session")) == 8)
    }

    @Test("Fetch request count stays flat as one event gains sessions")
    func fetchCountDoesNotGrowWithSessions() async throws {
        let modelURL = try #require(Bundle.module.url(
            forResource: "TestModel", withExtension: "momd"))
        let model = try #require(NSManagedObjectModel(contentsOf: modelURL))
        let coordinator = CountingFetchCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(
            ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        let importer = CoreDataImporter(context: context)

        var small = CongressGraphFixture.congress()
        small.events = [small.events[0]]
        try await write(small, using: importer)
        coordinator.resetFetchCount()
        try await write(small, using: importer)
        let smallFetchCount = coordinator.fetchCount
        #expect(smallFetchCount > 0)

        var large = small
        let firstSession = small.events[0].tracks[0].sessions[0]
        large.events[0].tracks[0].sessions = (1...8).map { index in
            var session = firstSession
            session.id = Int64(index)
            session.title = "Session \(index)"
            return session
        }
        try await write(large, using: importer)
        coordinator.resetFetchCount()
        try await write(large, using: importer)
        #expect(coordinator.fetchCount == smallFetchCount)

        let readContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        readContext.persistentStoreCoordinator = coordinator
        #expect(try readContext.count(
            for: NSFetchRequest<CongressEvent>(entityName: "CongressEvent")) == 1)
        #expect(try readContext.count(
            for: NSFetchRequest<Session>(entityName: "Session")) == 8)
    }

    private func write(_ graph: CongressGraph, using importer: CoreDataImporter) async throws {
        try await importer.write([graph]) { batch, storage in
            try GraphWriter.write(batch, using: storage)
        }
    }
}

private final class CountingFetchCoordinator: NSPersistentStoreCoordinator, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var fetchCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func resetFetchCount() {
        lock.lock()
        count = 0
        lock.unlock()
    }

    override func execute(
        _ request: NSPersistentStoreRequest,
        with context: NSManagedObjectContext
    ) throws -> Any {
        if request.requestType == .fetchRequestType {
            lock.lock()
            count += 1
            lock.unlock()
        }
        return try super.execute(request, with: context)
    }
}
