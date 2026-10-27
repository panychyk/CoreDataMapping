import CoreData
import CoreDataMapping

@MainActor
final class CoreDataStack {
    enum Storage: Equatable {
        case persistent
        case inMemory
    }

    enum StackError: Error {
        case modelNotFound(name: String)
        case unsupportedStoreModel(URL)
    }

    let persistentContainer: NSPersistentContainer
    let importer: CoreDataImporter
    private let modelURL: URL

    private var loadTask: Task<Void, Error>?

    var viewContext: NSManagedObjectContext {
        persistentContainer.viewContext
    }

    init(
        storage: Storage = .persistent,
        modelName: String = "PersistenceModel",
        bundle: Bundle = .module,
        storeURL: URL? = nil
    ) throws {
        guard
            let modelURL = bundle.url(forResource: modelName, withExtension: "momd"),
            let managedObjectModel = NSManagedObjectModel(contentsOf: modelURL)
        else {
            throw StackError.modelNotFound(name: modelName)
        }
        self.modelURL = modelURL

        persistentContainer = NSPersistentContainer(
            name: modelName,
            managedObjectModel: managedObjectModel
        )
        importer = CoreDataImporter(context: persistentContainer.newBackgroundContext())

        let storeDescription = persistentContainer.persistentStoreDescriptions[0]
        storeDescription.shouldMigrateStoreAutomatically = true
        storeDescription.shouldInferMappingModelAutomatically = true

        if storage == .inMemory {
            storeDescription.type = NSInMemoryStoreType
            storeDescription.url = nil
        } else if let storeURL {
            storeDescription.url = storeURL
        }

        viewContext.automaticallyMergesChangesFromParent = true
        viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    func load() async throws {
        if !persistentContainer.persistentStoreCoordinator.persistentStores.isEmpty {
            return
        }

        if let loadTask {
            try await loadTask.value
            return
        }

        try validateStoreModel()

        let task = Task { @MainActor [persistentContainer] in
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                persistentContainer.loadPersistentStores { _, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }
        }

        loadTask = task

        do {
            try await task.value
        } catch {
            loadTask = nil
            throw error
        }
    }

    func saveViewContext() throws {
        guard viewContext.hasChanges else { return }
        try viewContext.save()
    }

    /// Automatic migration is limited to source versions shipped with this app.
    /// An unrelated SQLite schema must not be inferred as an entity-deletion migration.
    private func validateStoreModel() throws {
        let description = persistentContainer.persistentStoreDescriptions[0]
        guard description.type == NSSQLiteStoreType,
              let url = description.url,
              FileManager.default.fileExists(atPath: url.path) else { return }
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: description.type, at: url, options: description.options
        )
        if persistentContainer.managedObjectModel.isConfiguration(
            withName: nil, compatibleWithStoreMetadata: metadata
        ) { return }
        let versions = try FileManager.default.contentsOfDirectory(
            at: modelURL, includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "mom" }
        for version in versions {
            if NSManagedObjectModel(contentsOf: version)?.isConfiguration(
                withName: nil, compatibleWithStoreMetadata: metadata
            ) == true { return }
        }
        throw StackError.unsupportedStoreModel(url)
    }
}
