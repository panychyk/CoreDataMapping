# CoreDataMapping: architecture and invariants

Language: **English** · [Українська](ARCHITECTURE.uk.md)

For practical examples, see [CORE_GUIDE.md](CORE_GUIDE.md). The package contains
only general-purpose persistence helpers. The application defines DTOs,
`NSManagedObject` subclasses, the Core Data model, the container, networking,
feature mappers, and repositories.

## Public API

| Component | Responsibility |
|---|---|
| `CoreDataEntityIdentity` | Entity name, required identity attribute, and Swift key path |
| `CoreDataStorage` | Batch lookup/upsert, entity creation, membership changes, and reconciliation of owned children within one context |
| `CoreDataImporter` | Serialized `write`, `read`, and `transaction` on a private context, bounded batches, save/rollback/reset |

The package does not decode DTOs or traverse a graph automatically. The mapper
sets scalar fields and relationships explicitly; it does not call `save`,
`rollback`, or `reset`.

`Tests/CoreDataMappingTests/Resources/TestModel.xcdatamodeld` is one shared test
schema with 49 entities: 15 for a medical congress, 11 for a marketplace, 12 for
a university, and 11 for travel booking. `Support/TestStack.swift` loads it into
a separate `NSInMemoryStoreType` for each test. `MedicalCongress`, `Marketplace`,
`University`, and `TravelBooking` each have their own `NSManagedObject` classes,
small graphs, mapping rules, and scenarios. The schema and fixtures are excluded
from the library target; the test target has no networking, repository, or domain
layer. See [TESTING.md](TESTING.md) for the test strategy and relationship rules.

## Context and concurrency

The application creates an `NSPersistentContainer`, loads the store, and gives
the importer a `newBackgroundContext()`. `CoreDataImporter(context:)` requires a
private-queue context connected directly to the store coordinator. Only the
importer uses this context. The package does not look for a model in `Bundle.main`
or create a persistent store.

An `NSManagedObject` stays on its context queue. Do not pass managed objects out
of a mapper closure or into another context; return only `Sendable` values.
The DTOs passed to `write` and the results of `read`/`transaction` must also be
`Sendable`. Related entities in one mapping call belong to the same context.

Each `write` or `read` call runs in one enqueued `context.perform` block, so
batches from concurrent calls do not interleave. Each batch follows this order:
map → cancellation check → save if changed → reset. Failure or cancellation
before save rolls back the current batch; earlier saved batches remain committed.
Cancellation is cooperative and does not interrupt an SQLite save already in
progress. Undo is disabled, and autorelease pools limit temporary Objective-C
allocations.

`read` rejects mutations with `CoreDataImportError.mutationDuringRead` and
accumulates only Swift values. `transaction` is one small atomic operation, not a
way to process an unbounded dataset. Separate `write` and `read` calls do not
form a shared transaction: another import can finish between them.

## Identity, lookup, and memory

An entity with a stable global identity needs a required attribute, a matching
Core Data uniqueness constraint, and a `CoreDataEntityIdentity` descriptor.
`existing(ids:)` looks up records in batches and returns only those found.
`upsert(ids:)` also creates missing records and sets their identity;
`upsert(_:id:identifiedBy:update:)` updates scalar fields in input order. For
repeated IDs, the last DTO wins. `upsert` does not delete rows omitted from the
payload.

`CoreDataEntityIdentity` describes **one** persistence attribute. For a global
lookup based on two components, the mapper creates a stable, unambiguous
composite ID in one attribute. A multi-attribute uniqueness constraint alone
does not extend the lookup API of `CoreDataStorage`.

The importer's `batchSize` limits the number of root DTOs in a commit;
storage's `fetchChunkSize` separately limits the size of an `IN` predicate.
Both default to 500. Neither limits a large graph under one parent or the size
of an already decoded DTO array. End-to-end memory limits require server pages
or an incremental decoder. Specify `prefetching` for relationships the mapper
will read; use profiling to check for fault queries.

## Ownership and snapshots

| Identity / ownership | Matching | Child absent from a full snapshot |
|---|---|---|
| Global, shared | Batch `upsert` | Remove the relationship; keep the row |
| Global/composite, owned | Batch `upsert` | Call `deleteSurplusOwned` for this parent's children |
| Parent-scoped, owned | `reconcileOwned` among this parent's children | Delete the child |
| No stable ID, owned | Explicit matching by position or business key | Delete the child |

`reconcileOwned` works only with the already loaded children of **one** parent.
It rejects duplicate IDs, reuses existing entities, and deletes surplus ones;
`update` must set the ID of each new child. Apply `deleteSurplusOwned` and
reconciliation only to owned children in a full snapshot. For a partial payload,
the mapper defines merge semantics separately. `replace` and `replaceUnordered`
change membership without deleting entities. Relationship helpers validate the
context and object state; `CoreDataStorage.ordered` validates element types.

The mapper prepares identities for all roots and dependencies first, then
connects the graph through local lookup dictionaries. Fetches inside a mapping,
update, or relationship loop are not allowed. For repeated full snapshots of
one root, the mapper must choose the current DTO **before** splitting into
batches. The importer does not know DTO identities, which server snapshot is
newer, or the policy for deleting roots.

The application's model defines delete rules, inverse relationships, and
uniqueness constraints. Parent → owned usually uses `Cascade`; parent → shared
usually uses `Nullify`. Deleting a parent and omitting a child from a snapshot
are different operations. See [CORE_GUIDE.md](CORE_GUIDE.md) for detailed examples.

## Multiple importers

Start with one shared importer for repositories that write to the same store or
overlap in root/shared identities or relationships. API requests and decoding
can run concurrently; mapping through one importer is serialized. An importer
does not choose the newer of conflicting server responses; the application
defines that rule.

Independent write groups may use separate private contexts and importers.
Determine independence from the actual scalar fields, shared IDs, relationships,
and owned children, not endpoint names. Do not pass `NSManagedObject` instances
between contexts; use a permanent object ID or refetch in the receiving context
when needed. Merge policies and uniqueness constraints do not determine the
correct server version. Before parallel writes, test graph integrity and measure
performance under a realistic workload.

## Useful references

- [Core Data performance](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreData/Performance.html)
- [Core Data concurrency](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreData/Concurrency.html)
- [Core Data uniqueness constraints](https://developer.apple.com/documentation/coredata/configuring-entities)
- [Core Data merge policy](https://developer.apple.com/documentation/coredata/nsmergebypropertyobjecttrumpmergepolicy)
