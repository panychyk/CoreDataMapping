# CoreDataMapping package instructions

## Scope

- This Swift Package owns only `CoreDataEntityIdentity`, `CoreDataStorage`, and
  `CoreDataImporter` in `Sources/CoreDataMapping/`.
- Keep `NSPersistentContainer`, store setup, model resources, migrations,
  concrete `NSManagedObject` subclasses, graph input values, and mapping rules in
  consuming applications. Storage-only fixtures under
  `Tests/CoreDataMappingTests/<System>/` must never enter the library target.
- Before changing the public API or persistence behavior, read `ARCHITECTURE.md`
  and `CORE_GUIDE.md`. Update both docs when their contracts or examples change.
- Keep test systems free of repository, networking, decoding, and domain layers.
  Their in-memory tests do not cover SQLite reopening or migration; use separate
  disk-backed integration tests when that coverage is requested.

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

## Test systems and scenarios

- Keep one shared Core Data schema in
  `Tests/CoreDataMappingTests/Resources/TestModel.xcdatamodeld`. Put each test
  system in its own directory, following `MedicalCongress` and `Marketplace`:
  `Entities/` with one `NSManagedObject` subclass per file, a small graph fixture,
  graph writer, graph assertions, a system stack adapter when needed, and
  `Suites/`.
- Before adding a capability, state its relationship and ownership rule. Add a
  test on the system's small fixture, then change package code.
- Give each file in `Suites/` one coherent scenario with independent `@Test`
  methods. Use a descriptive `@Suite` title and a readable title for every test.
  Immediately before `@MainActor` and `@Suite`, place a `///` comment with a
  short scenario summary and the invariant it checks. After a blank `///` line,
  list every test by its exact Swift function name and expected outcome. Update
  this list whenever a test is added, renamed, or removed. See
  `Tests/CoreDataMappingTests/MedicalCongress/Suites/CongressImportHistoryTests.swift`
  for the format.
- Each persistence test creates its own in-memory store. For update and lifecycle
  tests, write an initial fixture, perform the change, then verify saved state
  after a read-context reset. Check both changed data and relevant unaffected
  roots or shared rows. Use graph assertions for full snapshots and explicit
  assertions for the scenario's distinctive invariant.
- Keep `TESTING.md` as the concise inventory of existing test systems, their
  relationship rules, and suite coverage. Update it when adding a system or
  changing those rules or scenarios.

## Verification

- Build the package with `swift build`.
- Run `swift test`; the package test target covers identity, graph lifecycle,
  cancellation, concurrent imports, and import batches.
- After changing `Tests/CoreDataMappingTests/Resources/TestModel.xcdatamodeld`,
  run `./Scripts/update-test-model.sh` from the package root and commit the
  generated `Tests/CoreDataMappingTests/Resources/TestModel.momd` with it.
