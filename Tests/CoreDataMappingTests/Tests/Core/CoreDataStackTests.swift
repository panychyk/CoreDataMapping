import CoreData
import Testing

extension PersistenceTests {
    @MainActor
    @Suite("Core Data stack")
    struct CoreDataStackTests {

        @Test("Loads an in-memory persistent store")
        func loadsInMemoryStore() async throws {
            let stack = try CoreDataStack(storage: .inMemory)

            try await stack.load()

            let stores = stack.persistentContainer
                .persistentStoreCoordinator
                .persistentStores

            #expect(stores.count == 1)
            #expect(stores.first?.type == NSInMemoryStoreType)
        }

        @Test("Configures the view context for automatic merging")
        func configuresViewContext() throws {
            let stack = try CoreDataStack(storage: .inMemory)
            let description = stack.persistentContainer
                .persistentStoreDescriptions[0]

            #expect(stack.viewContext.automaticallyMergesChangesFromParent)
            #expect(
                stack.viewContext.mergePolicy as? NSMergePolicy
                === NSMergeByPropertyObjectTrumpMergePolicy
            )
            #expect(description.shouldMigrateStoreAutomatically)
            #expect(description.shouldInferMappingModelAutomatically)
        }

        @Test("Lightweight migration preserves rows from the previous model version")
        func migratesPreviousModel() async throws {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            defer { try? FileManager.default.removeItem(at: directory) }

            let storeURL = directory.appendingPathComponent("Persistence.sqlite")
            let modelDirectory = try #require(Bundle.module.url(
                forResource: "PersistenceModel", withExtension: "momd"
            ))
            let oldModel = try #require(NSManagedObjectModel(
                contentsOf: modelDirectory.appendingPathComponent("PersistenceModel.mom")
            ))
            try makeStore(
                at: storeURL, model: oldModel,
                entityName: "ReservationTopicEntity", idKey: "id", id: 42
            )

            let stack = try CoreDataStack(
                storage: .persistent,
                storeURL: storeURL
            )
            try await stack.load()

            #expect(
                stack.persistentContainer
                    .persistentStoreCoordinator
                    .persistentStores
                    .count == 1
            )
            let metadata = try NSPersistentStoreCoordinator
                .metadataForPersistentStore(
                    ofType: NSSQLiteStoreType,
                    at: storeURL
                )
            #expect(
                stack.persistentContainer.managedObjectModel.isConfiguration(
                    withName: nil,
                    compatibleWithStoreMetadata: metadata
                )
            )
            let request = NSFetchRequest<ReservationTopicEntity>(entityName: "ReservationTopicEntity")
            #expect(try stack.viewContext.fetch(request).map(\.id) == [42])
        }

        @Test("V2 and V3 SQLite stores migrate to V4 without losing shared rows")
        func migratesPreviousProgramModels() async throws {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let storeURL = directory.appendingPathComponent("V2.sqlite")
            let modelDirectory = try #require(Bundle.module.url(
                forResource: "PersistenceModel", withExtension: "momd"
            ))
            let oldModel = try #require(NSManagedObjectModel(
                contentsOf: modelDirectory.appendingPathComponent("PersistenceModelV2.mom")
            ))
            try makeStore(
                at: storeURL, model: oldModel,
                entityName: "ReservationTopicEntity", idKey: "id", id: 73
            )

            let stack = try CoreDataStack(storage: .persistent, storeURL: storeURL)
            try await stack.load()
            #expect(try stack.viewContext.fetch(
                NSFetchRequest<ReservationTopicEntity>(entityName: "ReservationTopicEntity")
            ).map(\.id) == [73])
            #expect(try stack.viewContext.count(
                for: NSFetchRequest<TrackEntity>(entityName: "TrackEntity")
            ) == 0)

            let v3StoreURL = directory.appendingPathComponent("V3.sqlite")
            let v3Model = try #require(NSManagedObjectModel(
                contentsOf: modelDirectory.appendingPathComponent("PersistenceModelV3.mom")
            ))
            try makeStore(
                at: v3StoreURL, model: v3Model,
                entityName: "TrackEntity", idKey: "id", id: 74
            )
            let v3Stack = try CoreDataStack(storage: .persistent, storeURL: v3StoreURL)
            try await v3Stack.load()
            let migratedTracks = try v3Stack.viewContext.fetch(
                NSFetchRequest<TrackEntity>(entityName: "TrackEntity")
            )
            #expect(migratedTracks.map(\.id) == [74])
            #expect(migratedTracks.first?.name == nil)
        }

        @Test("An unsupported store fails to load without deleting its existing rows")
        func preservesIncompatibleStore() async throws {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let storeURL = directory.appendingPathComponent("Legacy.sqlite")
            let oldModel = makeUnsupportedModel()
            try makeStore(
                at: storeURL, model: oldModel,
                entityName: "LegacyEntity", idKey: "legacyId", id: 99
            )
            let stack = try CoreDataStack(storage: .persistent, storeURL: storeURL)
            do {
                try await stack.load()
                Issue.record("Expected a store with an unavailable source model to fail migration")
            } catch CoreDataStack.StackError.unsupportedStoreModel(let rejectedURL) {
                #expect(rejectedURL == storeURL)
                #expect(stack.persistentContainer.persistentStoreCoordinator.persistentStores.isEmpty)
            }

            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: oldModel)
            let store = try coordinator.addPersistentStore(type: .sqlite, at: storeURL)
            let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            context.persistentStoreCoordinator = coordinator
            let ids: [Int] = try context.performAndWait {
                try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "LegacyEntity"))
                    .compactMap { $0.value(forKey: "legacyId") as? Int }
            }
            #expect(ids == [99])
            try coordinator.remove(store)
        }

        private func makeUnsupportedModel() -> NSManagedObjectModel {
            let model = NSManagedObjectModel()
            let entity = NSEntityDescription()
            entity.name = "LegacyEntity"
            entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

            let attribute = NSAttributeDescription()
            attribute.name = "legacyId"
            attribute.attributeType = .integer64AttributeType
            attribute.isOptional = false
            attribute.defaultValue = 0
            entity.properties = [attribute]
            model.entities = [entity]
            return model
        }

        private func makeStore(
            at storeURL: URL,
            model: NSManagedObjectModel,
            entityName: String,
            idKey: String,
            id: Int
        ) throws {
            let coordinator = NSPersistentStoreCoordinator(
                managedObjectModel: model
            )
            let store = try coordinator.addPersistentStore(
                type: NSPersistentStore.StoreType(
                    rawValue: NSSQLiteStoreType
                ),
                at: storeURL
            )
            let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            context.persistentStoreCoordinator = coordinator
            try context.performAndWait {
                let entity = NSEntityDescription.insertNewObject(forEntityName: entityName, into: context)
                entity.setValue(id, forKey: idKey)
                try context.save()
            }
            try coordinator.remove(store)
        }
    }
}
