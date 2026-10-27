import CoreData
import CoreDataMapping

@MainActor
final class CongressTestStack {
    enum StackError: Error { case modelNotFound }

    let container: NSPersistentContainer
    lazy var importer = CoreDataImporter(context: container.newBackgroundContext())

    init() throws {
        guard
            let modelURL = Bundle.module.url(
                forResource: "MedicalCongressModel", withExtension: "momd"),
            let model = NSManagedObjectModel(contentsOf: modelURL)
        else {
            throw StackError.modelNotFound
        }
        container = NSPersistentContainer(
            name: "MedicalCongressModel", managedObjectModel: model
        )
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.url = nil
        container.persistentStoreDescriptions = [description]
    }

    func load() async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            container.loadPersistentStores { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func write(_ graph: CongressGraph, batchSize: Int = 500) async throws {
        try await importer.write([graph], batchSize: batchSize) { batch, storage in
            try GraphWriter.write(batch, using: storage)
        }
    }

    func fetch<Entity: NSManagedObject>(_ type: Entity.Type) throws -> [Entity] {
        return try container.viewContext.fetch(
            NSFetchRequest<Entity>(entityName: String(describing: type))
        )
    }

    func count<Entity: NSManagedObject>(_ type: Entity.Type) throws -> Int {
        return try container.viewContext.count(
            for: NSFetchRequest<Entity>(entityName: String(describing: type))
        )
    }

    func resetViewContext() {
        container.viewContext.reset()
    }
}
