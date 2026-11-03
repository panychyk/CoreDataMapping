# CoreDataMapping

![Swift 6.2](https://img.shields.io/badge/Swift%20tools-6.2-orange.svg)
![Platforms](https://img.shields.io/badge/platforms-iOS%2016%2B%20%7C%20macOS%2015%2B-lightgrey.svg)
![License](https://img.shields.io/badge/license-MIT-blue.svg)

CoreDataMapping is a small Swift package for writing, reading, and reconciling
connected Core Data graphs. It provides `CoreDataEntityIdentity`,
`CoreDataStorage`, and `CoreDataImporter`.

The application owns the persistent container, Core Data model, managed-object
subclasses, input values, and mapping rules. The package supplies reusable
persistence operations without depending on an application schema.

## Features

- Batch lookup and upsert by a stable entity identity.
- Serialized writes and reads on one private, store-backed context.
- Bounded root batches with save, rollback, and context reset.
- Ordered and unordered relationship replacement that keeps shared rows.
- Reconciliation and surplus deletion for children owned by a full snapshot.
- Context-bound mapping that returns only `Sendable` values.

## Requirements

- Swift tools 6.2+
- iOS 16+
- macOS 15+

## Installation

Add CoreDataMapping to the dependencies in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/panychyk/CoreDataMapping", from: "1.0.0")
]
```

Then add the product to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "CoreDataMapping", package: "CoreDataMapping")
    ]
)
```

In Xcode, choose **File → Add Package Dependencies…** and enter
`https://github.com/panychyk/CoreDataMapping`, then select version `1.0.0` or
later.

## Quick start

Create and load an `NSPersistentContainer` in the application. Give the importer
a private context connected directly to its store coordinator:

```swift
import CoreData
import CoreDataMapping

let context = container.newBackgroundContext()
let importer = CoreDataImporter(context: context)

try await importer.write(topicSnapshots) { batch, storage in
    _ = try storage.upsert(
        batch,
        id: \TopicSnapshot.id,
        identifiedBy: TopicEntity.identity
    ) { entity, snapshot in
        entity.name = snapshot.name
    }
}
```

Here `container`, `TopicSnapshot`, and `TopicEntity` belong to the application.
The model gives `TopicEntity` a required, uniqueness-constrained `id` attribute;
its `identity` descriptor names that attribute and its Swift key path. See the
[practical guide](CORE_GUIDE.md) for a complete identity and read example.

## Core API

### `CoreDataEntityIdentity`

An identity descriptor connects an entity name, one required Core Data
attribute, and the matching Swift key path. Use it for entities with a stable
global ID. An application can derive a composite ID before mapping when the
source identity has multiple parts.

### `CoreDataStorage`

`existing(ids:identifiedBy:)` fetches known entities in chunks.
`upsert(ids:identifiedBy:)` also inserts missing entities; the DTO overload
updates their fields in input order. Prepare identities before connecting
relationships so mapping loops can use the returned lookup without fetching.

`replace(with:)` and `replaceUnordered(with:)` change relationship membership
without deleting entities. For children owned by one parent, use
`reconcileOwned` with that parent's current children, or `deleteSurplusOwned`
after a batch upsert. Delete surplus children only when the input is a full
snapshot. The [practical guide](CORE_GUIDE.md) covers these ownership rules and
their relationship examples.

### `CoreDataImporter`

`write` saves and resets the context after each batch of roots (500 by
default). A failed or cancelled batch rolls back; earlier saved batches remain
committed. `read` runs on the same serialized queue, rejects mutations, and
returns Swift values. `transaction` handles one small atomic operation.

Keep all `NSManagedObject` access inside an importer operation on its context
queue. Input to `write` and results of `read` or `transaction` must be
`Sendable`. Share an importer for operations that update overlapping graphs.
The [architecture guide](ARCHITECTURE.md) describes the context and batch
contracts in detail.

## Testing

The test target uses one shared Core Data schema for the MedicalCongress,
Marketplace, University, and TravelBooking systems. Their graph tests each use
a separate in-memory store; disk-backed tests cover SQLite reopening. The
scenarios cover shared and owned relationships, updates, multiple imports,
rollback, and cancellation. The schema and fixtures are excluded from the
library product. See [TESTING.md](TESTING.md) for the suite inventory and
relationship rules.

Run the package checks with:

```bash
swift build
swift test
```

After changing the test `.xcdatamodeld`, run `./Scripts/update-test-model.sh`
and commit the generated `.momd` with it.

## Documentation

- Practical guide: [English](CORE_GUIDE.md) · [Українська](CORE_GUIDE.uk.md)
- Architecture: [English](ARCHITECTURE.md) · [Українська](ARCHITECTURE.uk.md)
- [Testing](TESTING.md): test systems, relationships, and suite coverage
- [AGENTS.md](AGENTS.md): instructions for working on this package

## License

CoreDataMapping is available under the MIT License. See [LICENSE](LICENSE) for
details.
