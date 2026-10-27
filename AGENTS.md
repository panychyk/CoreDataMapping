# CoreDataMapping package instructions

## Scope

- This Swift Package owns only `CoreDataEntityIdentity`, `CoreDataStorage`, and
  `CoreDataImporter` in `Sources/CoreDataMapping/`.
- Keep `NSPersistentContainer`, store setup, model resources, migrations, DTOs,
  concrete `NSManagedObject` subclasses, feature mappers, and repositories in
  consuming applications. The copies under `Tests/CoreDataMappingTests/Example`
  are test support only and must never be added to the library target.
- Before changing the public API or persistence behavior, read `ARCHITECTURE.md`
  and `CORE_GUIDE.md`. Update both docs when their contracts or examples change.
- Treat `Tests/CoreDataMappingTests/Example` as an integration example of a real
  graph. SQLite and migration tests are integration tests run by `swift test`.

## Invariants

- Keep public helpers independent of any app schema or server DTO.
- An importer owns one store-backed private-queue context. All managed-object
  access stays on that context queue; only `Sendable` values leave it.
- `write` and `read` serialize whole calls. A failed or cancelled batch rolls
  back; previously saved batches remain committed.
- Batch identity lookup happens before mapping relationships. Do not introduce
  fetches inside mapping loops.
- `replace` changes membership without deleting shared Entity rows. Reconcile
  and delete surplus only for owned children of full snapshots.
- Preserve source and binary compatibility of the public API unless a deliberate
  API change is required and documented.

## Verification

- For each new capability, first state the relationship rule and add a test on
  a small graph built with DTO factories; then change the package. See
  `TESTING.md` for the test strategy.
- Build the package with `swift build`.
- Run `swift test`; the package test target covers identity, graph lifecycle,
  SQLite persistence, cancellation, migrations, and import batches.
- After changing the example `.xcdatamodeld`, run
  `Scripts/update-test-model.sh` and commit the compiled `.momd` with it.
