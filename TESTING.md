# Testing CoreDataMapping

This document inventories the test systems, their graphs, relationship rules,
and scenarios. See [AGENTS.md](AGENTS.md) for the rules for adding systems and
formatting suites.

## Shared infrastructure

`Tests/CoreDataMappingTests/Resources/TestModel.xcdatamodeld` is one Core Data
model for four systems. The compiled `TestModel.momd` sits beside it and belongs
only to the test target. `Support/TestStack.swift` loads the model into an
`NSInMemoryStoreType` by default; every persistence test creates its own store.
SQLite integration tests pass a temporary store URL to the stack.

`Integration/Suites/SQLiteReopenTests.swift` verifies a complete congress graph
after a new container opens the store, and a marketplace order update after two
successive reopenings. It also checks a congress after cancellation of the
second batch, a subsequent successful write, and another reopen. Each test uses
its own SQLite file.

## MedicalCongress

`MedicalCongress/Entities/` contains 15 entity classes. The system also has
`CongressGraphFixture.swift`, `GraphWriter.swift`, `GraphAssertions.swift`,
`CongressTestStack.swift`, and `Suites/`. The fixture has one congress with two
events; people, rooms, organizations, and resources are used in multiple parts
of the graph.

| Relationship | Rule |
|---|---|
| `Congress → CongressEvent` | Events are separate roots; deleting the congress nullifies the relationship. |
| `Venue → Room` | Rooms belong to the venue; deleting the venue cascades to its rooms. |
| `CongressEvent → Track → Session` | The event owns tracks and each track owns sessions; a full snapshot reconciles them by local ID. |
| `CongressEvent → Appointment / Registration / EventSponsor` | The event owns appointments, registrations, sponsorship rows, and their child join rows. |
| `Session ↔ ResourceAsset` | Resources are shared; membership changes do not delete them. |
| `Person`, `Room`, `Organization` in the child graph | References to shared rows do not give child entities ownership of them. |

Global `Congress`, `CongressEvent`, `Organization`, `Person`, `Venue`, `Room`,
and `ResourceAsset` have a uniqueness constraint on `id`. A child entity's
`localID` is unique only within its owner.

| Suite | Scenario |
|---|---|
| `CongressModelAndImportTests` | Schema rules, batch identity lookup, and the first write of the full graph. |
| `CongressImportHistoryTests` | Sequential and repeated imports, isolated event updates, and history across multiple saves. |
| `CongressSharedRelationshipsTests` | Changing links to people, rooms, resources, and organizations without losing their other uses. |
| `CongressOwnedLifecycleTests` | Reconciliation and cascade deletion of child rows without deleting shared entities. |
| `CongressTransactionsTests` | Rollback of failed or cancelled batches, rollback after a Core Data save failure and successful retry, mutation rejection during read, and serialization of concurrent imports. |
| `CongressImporterContractTests` | Serialization of multi-batch writes and reads after a second call is queued, read result order, transaction commit/rollback, and batch size limits. |
| `CongressControlledConcurrencyTests` | Barrier-controlled snapshots of one event observed through another context; overlapping writes to two events, rollback of the second, and successful retry. |
| `CongressComplexTransitionsTests` | Multilevel snapshot reordering, repeated local IDs, and preserved identity; a late failure in the second batch, rollback, and retry. |
| `CongressStorageContractsTests` | Direct storage contracts: repeated global IDs, deletion of owned children, and entity and relationship helper errors. |
| `CongressFetchPerformanceTests` | Fetch counts during repeated imports stay constant as events (1 → 8) or sessions in one event (1 → 8) increase. |

## Marketplace

`Marketplace/Entities/` contains 11 entity classes. The system also has
`MarketplaceGraphFixture.swift`, `MarketplaceGraphWriter.swift`,
`MarketplaceGraphAssertions.swift`, `MarketplaceTestStack.swift`, and `Suites/`.
The fixture has two orders sharing a product and using the same local item IDs.
It verifies that each item belongs to its own order.

| Relationship | Rule |
|---|---|
| `Seller → Product` | A product belongs to its seller; deleting the seller cascades to its products. |
| `Product ↔ Category` | Categories are shared; membership changes do not delete them. |
| `Product → OrderItem ← Order` | A product may appear in many orders; an item belongs only to its order. |
| `Product → Stock ← Warehouse` | Stock has a global ID and refers to a product and a warehouse. |
| `Order → Payment / Shipment` | Payments and shipments belong to the order; a full snapshot reconciles only its children. |
| `Buyer → Order / Review`, `Product → Review` | The buyer is shared; a review has a global ID and refers to a product. |

Buyers, sellers, products, categories, warehouses, stocks, orders, and reviews
have global `id` identities. Item, payment, and shipment `localID` values are
unique within their own order.

| Suite | Scenario |
|---|---|
| `MarketplaceModelAndImportTests` | Schema rules and the first write of the full graph. |
| `MarketplaceImportHistoryTests` | Repeated import and updating one order without changing the other. |
| `MarketplaceSharedRelationshipsTests` | Changing categories and stock while preserving shared relationships. |
| `MarketplaceOwnedLifecycleTests` | Removing a payment, shipment, or order while cleaning up only its children. |
| `MarketplaceTransactionsTests` | Rollback after a duplicate local ID or missing product. |

## University

`University/Entities/` contains 12 entity classes. The system also has
`UniversityGraphFixture.swift`, `UniversityGraphWriter.swift`,
`UniversityGraphAssertions.swift`, `UniversityTestStack.swift`, and `Suites/`.
The small fixture has two faculties, two programs, three groups, three students,
two courses, and three offerings. Algorithms is offered in two semesters; Ada
is enrolled in three offerings. Local enrollment, assignment, and grade IDs
repeat under different owners.

| Relationship | Rule |
|---|---|
| `Faculty → Program → Course / Group / Student` | Reference entities have global `id` values; links to faculties and programs nullify without cascade deletion. A student belongs to one group but may have many enrollments. |
| `Course / Semester / Teacher / Room → Offering` | An offering has a global `id`. Courses, semesters, teachers, and rooms are shared; deleting an offering does not delete them. |
| `Offering → Assignment / Enrollment` | An offering owns assignments and enrollments; `localID` is unique within it. A full snapshot reconciles only that offering's children. |
| `Enrollment → Grade → Assignment` | An enrollment owns grades with local `localID` values; a grade refers only to an assignment in the same offering. A full snapshot deletes absent grades. |

| Suite | Scenario |
|---|---|
| `UniversityModelAndImportTests` | Inverses, delete rules, identity constraints, and the first write of the full graph. |
| `UniversityImportHistoryTests` | Sequential imports, object ID reuse, and independent offering updates. |
| `UniversityRelationshipsAndLifecycleTests` | Moving shared references, reconciling children, and cascade deletion of an offering. |
| `UniversityTransactionsTests` | Rollback for duplicate IDs, invalid references, duplicate student enrollment, and preservation of an earlier batch. |

## TravelBooking

`TravelBooking/Entities/` contains 11 entity classes. `TravelGraphFixture.swift`
describes three trips on two routes: two travelers use the same flight and room,
while a third takes a different route. Local booking, guest, payment, and ticket
IDs repeat across trips and bookings.

| Relationship | Rule |
|---|---|
| `Traveler → Trip` | A traveler is a shared row with a global `id`; a trip has its own global `id`. Deleting a traveler does not delete trips. |
| `Trip → Booking → Guest / Payment / Ticket` | A trip owns bookings, and a booking owns its children. A full snapshot reconciles `localID` only within each owner; deletion cascades. |
| `Booking → Flight / Room` | A booking refers to exactly one of these shared records. Rerouting or cancellation does not delete the flight or room. |
| `Flight → Airport`, `Room → Hotel`, `Traveler → Loyalty` | Global reference records survive membership changes; an airport can be both an origin and a destination. |
| `Ticket → Guest` | A ticket refers only to a guest in the same booking; seats are unique within a booking. |

| Suite | Scenario |
|---|---|
| `TravelModelAndImportTests` | Inverses, delete rules, the full graph, and reuse of a flight and room. |
| `TravelHistoryAndLifecycleTests` | Separate batches, repeated import with stable object IDs, rebooking, shared catalog changes, reconciliation, and cascade deletion. |
| `TravelTransactionsTests` | Rollback for duplicate payments or seats, a foreign ticket guest, an invalid booking type, and a later batch. |

## Verification

After changing the model, run `./Scripts/update-test-model.sh` and commit the
updated `.momd` with the `.xcdatamodeld`. Run `swift build` and `swift test` to
verify the package.

In-memory tests do not cover reopening SQLite; separate disk-backed integration
tests do. WAL behavior and model migration are not currently covered.

The counter in `CongressFetchPerformanceTests` measures fetch requests sent to
`NSPersistentStoreCoordinator`, not SQL query counts in SQLite. `GraphAssertions`
also compares the raw `NSOrderedSet.array` order after a read-context reset; the
same assertion runs after SQLite reopening.
