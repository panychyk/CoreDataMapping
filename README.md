# CoreDataMapping

A Swift package for writing, reading, and reconciling large, connected Core Data graphs.
It provides `CoreDataEntityIdentity`, `CoreDataStorage`, and `CoreDataImporter`.
It requires iOS 18 or macOS 15 or later.

The application creates and loads an `NSPersistentContainer`, then passes the importer
a private context connected directly to the store coordinator:

```swift
import CoreDataMapping

let context = container.newBackgroundContext()
let importer = CoreDataImporter(context: context)

try await importer.write(dtos) { batch, storage in
    // Prepare entities in batches and connect the graph in this context.
}
```

The consuming application defines the Core Data model, `NSManagedObject` subclasses,
and graph mapping rules.

`Tests/CoreDataMappingTests/Resources/TestModel.xcdatamodeld` contains a shared test
model for `MedicalCongress`, `Marketplace`, `University`, and `TravelBooking`. Each
test uses its own `NSInMemoryStoreType`. The scenarios cover shared and owned
relationships, isolated updates, multiple imports, rollback, and cancellation.
The test schema is not part of the library product.

- Practical guide: [English](CORE_GUIDE.md) · [Українська](CORE_GUIDE.uk.md).
  Covers the API, identity, relationships, ownership, delete rules, and composite keys.
- Architecture: [English](ARCHITECTURE.md) · [Українська](ARCHITECTURE.uk.md).
  Covers contracts, context queue, batches, cancellation, and package boundaries.
- [Testing](TESTING.md): test target structure, relationships, and fixture strategy.
- [AGENTS.md](AGENTS.md): instructions for Codex when working on the package.

Add the `CoreDataMapping` package product to your application with Swift Package
Manager, then import the module where you write and read Core Data graphs.

To verify the package on macOS, run `swift build` and `swift test`. After changing
the `.xcdatamodeld`, run `Scripts/update-test-model.sh` and commit the updated
`.momd` alongside it.
