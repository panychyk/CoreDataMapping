import CoreData
import CoreDataMapping

@MainActor
final class CoreDataTestStack {
    enum StackError: Error { case modelNotFound }

    let container: NSPersistentContainer
    lazy var importer = CoreDataImporter(context: container.newBackgroundContext())

    var viewContext: NSManagedObjectContext { container.viewContext }

    /// No URL means an in-memory store; a URL creates a SQLite store.
    init(sqliteURL: URL? = nil) throws {
        guard let modelURL = Bundle.module.url(forResource: "GraphModel", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else {
            throw StackError.modelNotFound
        }
        container = NSPersistentContainer(name: "GraphModel", managedObjectModel: model)
        let description = container.persistentStoreDescriptions[0]
        if let sqliteURL {
            description.url = sqliteURL
            description.type = NSSQLiteStoreType
        } else {
            description.type = NSInMemoryStoreType
            description.url = nil
        }
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    func load() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            container.loadPersistentStores { _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: ()) }
            }
        }
    }

    func fetch<Entity: NSManagedObject>(_ type: Entity.Type) throws -> [Entity] {
        viewContext.reset()
        return try viewContext.fetch(NSFetchRequest<Entity>(entityName: String(describing: type)))
    }

    func count<Entity: NSManagedObject>(_ type: Entity.Type) throws -> Int {
        try viewContext.count(for: NSFetchRequest<Entity>(entityName: String(describing: type)))
    }

    func writeGraph(_ snapshots: [RootSnapshot], batchSize: Int = 500) async throws {
        try await importer.write(snapshots, batchSize: batchSize) { batch, storage in
            try GraphWriter.write(batch, using: storage)
        }
    }
}

struct TemporarySQLiteStore {
    let directory: URL
    let url: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        url = directory.appendingPathComponent("Graph.sqlite")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
