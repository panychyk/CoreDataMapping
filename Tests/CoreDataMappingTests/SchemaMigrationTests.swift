import CoreData
import CoreDataMapping
import Testing

@MainActor
@Suite("Test schema migration")
struct SchemaMigrationTests {
    @Test("Adding an optional resource label preserves SQLite identities")
    func optionalResourceLabelMigratesSQLiteStore() async throws {
        let storeLocation = try TemporarySQLiteStore()
        defer { storeLocation.remove() }
        let oldURL = storeLocation.url
        let modelDirectory = try #require(Bundle.module.url(
            forResource: "GraphModel", withExtension: "momd"
        ))
        let oldModel = try #require(NSManagedObjectModel(
            contentsOf: modelDirectory.appendingPathComponent("GraphModelV1.mom")
        ))

        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: oldModel)
        let store = try coordinator.addPersistentStore(type: .sqlite, at: oldURL)
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        let resource = NSEntityDescription.insertNewObject(forEntityName: "Resource", into: context)
        resource.setValue(Int64(71), forKey: "id")
        try context.save()
        try coordinator.remove(store)

        let stack = try CoreDataTestStack(sqliteURL: oldURL)
        try await stack.load()
        let stored = try #require(stack.fetch(Resource.self).first)
        #expect(stored.id == 71)
        #expect(stored.label == nil)
        try await stack.importer.write([Int64(71)]) { ids, storage in
            let resources = try storage.upsert(ids: ids, identifiedBy: Resource.identity)
            resources[71]?.label = "after migration"
        }
        #expect(try stack.fetch(Resource.self).map(\.label) == ["after migration"])
    }
}
