# Practical guide: core API and relationships

Language: **English** · [Українська](CORE_GUIDE.uk.md)

This guide explains how to use `CoreDataMapping` in an application. Start with
the [README](README.md); [ARCHITECTURE.md](ARCHITECTURE.md) describes the package
invariants and boundaries. Snapshot and entity names in code snippets are
examples; the consuming application defines the concrete types.

The medical congress example, with two events and shared people, rooms, and
resources, is in `Tests/CoreDataMappingTests/MedicalCongress/GraphWriter.swift`.
The marketplace example is in `Marketplace/MarketplaceGraphWriter.swift`: a
product belongs to a seller but is used by many orders and categories; items,
payments, and shipments are reconciled within their order. University and
travel booking examples are in `University/UniversityGraphWriter.swift` and
`TravelBooking/TravelGraphWriter.swift`. All four systems use the shared
`Resources/TestModel.xcdatamodeld` and a separate in-memory store per test.
See [TESTING.md](TESTING.md) for scenarios and relationship rules.

## 1. What the core API does

| Component | Purpose | Outside its scope |
|---|---|---|
| `CoreDataEntityIdentity<Entity, Id>` | Names an entity, its single identity attribute, and its Swift key path | Does not construct an ID from input values or create a model constraint |
| `CoreDataStorage` | Finds or creates records in batches within one context and helps reconcile relationships | Does not decode input, choose a child's owner, or call `save` |
| `CoreDataImporter` | Runs `write`, `read`, and small `transaction` operations on one private context, serializing calls | Does not choose the newer snapshot or decide which root records to delete |

These components are in two package files: [CoreDataStorage.swift](Sources/CoreDataMapping/CoreDataStorage.swift)
(including identity) and [CoreDataImporter.swift](Sources/CoreDataMapping/CoreDataImporter.swift).
The consumer owns `CoreDataStack`, `.xcdatamodel`, input snapshots, and graph
mapping rules.

**Mapper contract:** it runs only on the queue of the context supplied through
the importer and never passes `NSManagedObject` instances outside it. Input to
`write` must be `Sendable`; the result of `read` or `transaction` must also be
`Sendable`. Do not call `save`, `rollback`, or `reset` in a mapper.

`CoreDataStorage` operations at a glance:

| Call | Result |
|---|---|
| `existing(ids:identifiedBy:)` | Batch lookup; missing IDs are omitted and no entities are created |
| `upsert(ids:identifiedBy:)` | Batch lookup and creation of missing entities with identity assigned automatically; the mapper fills scalar fields |
| `upsert(_:id:identifiedBy:update:)` | The same, followed by `update` for each input value in input order |
| `insert(_:)` | Creates an entity without global lookup, using the current context's model |
| `replace(with:)` / `replaceUnordered(with:)` | New relationship membership without deleting entities |
| `reconcileOwned` / `deleteSurplusOwned` | Deletes surplus owned children in a **full** snapshot |

`existing` and both `upsert` methods accept `prefetching` for relationships the
mapper will read. They return an `[Id: Entity]` lookup that lives only within
the current importer operation.

## 2. Minimal write and read

For an entity with a stable global ID, declare a required `id` attribute and a
uniqueness constraint on `id` in `.xcdatamodel`. Add a descriptor to its Swift
declaration, for example:

```swift
nonisolated extension ReservationTopicEntity {
    static let identity = CoreDataEntityIdentity(
        entityName: "ReservationTopicEntity",
        attributeName: #keyPath(ReservationTopicEntity.id),
        keyPath: \ReservationTopicEntity.id
    )
}
```

With `topicSnapshots: [TopicSnapshot]` prepared, use an importer created from
the loaded persistent container:

```swift
try await importer.write(topicSnapshots) { batch, storage in
    _ = try storage.upsert(
        batch,
        id: \TopicSnapshot.id,
        identifiedBy: ReservationTopicEntity.identity
    ) { entity, snapshot in
        entity.name = snapshot.name
    }
}

let ids = topicSnapshots.map(\.id)
let names = try await importer.read(ids) { ids, storage in
    let byId = try storage.existing(
        ids: ids,
        identifiedBy: ReservationTopicEntity.identity
    )
    return ids.compactMap { byId[$0]?.name }
}
```

`upsert` prepares all distinct IDs first, then updates input values in order.
For a repeated ID, the last scalar values win. `existing` returns only found
records; consumer code defines what to do with a missing required root. Neither
operation deletes roots absent from the input.

`write` saves and resets the context after each batch of roots (`batchSize`,
500 by default). Failure or cancellation rolls back the current batch; earlier
saved batches remain committed. `read` uses the same queue, rejects mutations,
and returns only Swift values. `transaction` is for a small atomic operation.
Storage's `fetchChunkSize` separately limits an `IN` lookup, not commit size.

Use one importer for operations that change shared records. A separate `read`
after `write` sees current persisted state, but another import may finish
between the calls, so the result is not an isolated view of one input snapshot.

## 3. Prepare the graph and choose relationship operations

Order of work for a batch mapper:

1. For repeated full root snapshots, choose the current snapshot for each ID
   **before** splitting into batches. The last snapshot of each root wins.
2. Batch `upsert` roots and dependencies with global IDs. For existing children
   with parent-scoped IDs, load the parent's relationship with `prefetching`.
3. Connect prepared objects from `[Id: Entity]` dictionaries. Do not fetch
   inside the relationship mapping loop.
4. For a full snapshot, delete only omitted **owned** children. Keep shared
   objects in the store.

Identity answers “is this the same record?”; ownership answers “who may delete
it?” They are independent: an attendee can have a globally unique composite
key while belonging to one appointment.

| Situation | Mapper operation for a full snapshot |
|---|---|
| Shared entity with a global ID, such as a topic or user | `upsert`; assign `parent.user = usersById[id]` for to-one or use `replace` / `replaceUnordered` for to-many. Removing an item removes only the relationship. |
| Owned child with an ID scoped to its parent, such as a custom field | Use `reconcileOwned` with **that parent's current children**. The helper reuses matches and deletes surplus rows. Assign its returned list to the relationship. |
| Owned child with a global or composite ID, such as an attendee | Call `upsert(ids:)` for the whole batch, set the relationship, then call `deleteSurplusOwned` for that parent's children. |
| Owned child without a stable ID | Match explicitly by position or business key, create needed children, and delete surplus ones. Position does not preserve identity when reordered. |

`replace(with:)` creates ordered membership (`NSOrderedSet`), while
`replaceUnordered(with:)` creates unordered membership (`Set`). Both validate
context and object state, remove duplicates, and **do not delete entities**.
For checked reads of an ordered relationship, use `CoreDataStorage.ordered(...)`;
`nil` produces an empty array, while a wrong element type throws an error.

Example for a child whose ID is scoped to an appointment:

```swift
let current = try CoreDataStorage.ordered(
    appointment.customFields,
    as: CustomFieldEntity.self
)
let incoming = try storage.reconcileOwned(
    snapshot.customFields ?? [],
    current: current,
    dtoId: \CustomFieldSnapshot.id,
    entityId: \CustomFieldEntity.id,
    create: { try storage.insert(CustomFieldEntity.self) }
) { field, fieldSnapshot in
    try CustomFieldEntityMapper().update(field, from: fieldSnapshot, using: storage)
    field.appointment = appointment
}
appointment.customFields = try storage.replace(with: incoming)
```

`reconcileOwned` does not set a new child's ID; `update` must do that. It
rejects duplicate scoped IDs in the incoming or current list. `current` must
not be a global selection of children. For both to-one and to-many, both ends
of the relationship must belong to one context; a scalar `parentId` alone does
not establish a relationship.

If a child mapper needs the parent ID or dependency dictionary, pass them from
the parent mapper. In a model with both properties, `child.parentId = parent.id`
stores the scalar, while `child.parent = parent` establishes the relationship.
For child → shared user, pass the prepared `usersById`; the child mapper does
not need a separate fetch.

**Full versus partial payload:** in a full snapshot, `nil` or a missing
collection means `[]` and clears owned children. For a partial snapshot, this
could erase data accidentally. Give “field not sent,” `null`, and `[]` distinct
input contracts and mapping rules; do not reconcile from an incomplete page.

## 4. Delete rules when a parent is deleted

A delete rule is set **on the relationship from source to destination** in
`.xcdatamodel`. It acts when the source instance is deleted. Removing one item
from a live parent's relationship is a different operation. Define an inverse
for each relationship and choose a rule for each direction separately.

| Rule on `parent → child` | When `parent` is deleted | When to use it |
|---|---|---|
| `Cascade` | Core Data deletes related children | The child belongs only to this parent and cannot live without it: `Appointment → attendees/customFields`, `CustomField → multipleValues` |
| `Nullify` | Core Data clears the inverse reference; the child remains | The child is shared or has its own lifecycle: `Appointment → topics/user/realLocation` |
| `Deny` | Parent deletion fails while the relationship has children | A business rule requires moving or explicitly removing dependent records first; handle the deletion error |
| `No Action` | Core Data does not update related objects | Only when the application maintains **all** inverse references and deletions itself; otherwise the graph may become inconsistent |

`Cascade` usually fits owned children and `Nullify` fits shared records. Do not
put `Cascade` on a shared relationship: deleting one parent would delete a row
needed by others. For a live parent, `Cascade` does not replace reconciliation:
when a child disappears from a full snapshot, `reconcileOwned` or
`deleteSurplusOwned` deletes it explicitly. `replace` only changes membership.

See [Apple's relationship configuration](https://developer.apple.com/documentation/coredata/configuring-relationships)
for all four rules and its separate warning about [inconsistent references
with `No Action`](https://developer.apple.com/documentation/coredata/nsdeleterule/noactiondeleterule).

## 5. IDs made from two properties

If `childId` is unique only under one parent and you always work with that
parent's children, `reconcileOwned(current: ...)` is enough. Identical `childId`
values under different parents then represent different entities.

If a child needs a **batch global lookup**, make a stable persistence ID from
both components. For example, `AppointmentAttendeeEntity.makeId` takes two
`Int` values:

```swift
static func makeId(appointmentId: Int, userId: Int) -> String {
    "\(appointmentId)_\(userId)"
}
```

That key is unambiguous for this pair of integers. In the schema,
`AppointmentAttendeeEntity.id` is a required `String` with a uniqueness
constraint. The mapper computes keys for the **whole batch** before linking:

```swift
let attendeeIds = batch.flatMap { dto in
    (dto.Attendees ?? []).map { attendee in
        AppointmentAttendeeEntity.makeId(
            appointmentId: dto.RoomReservationUserID,
            userId: attendee.UserID
        )
    }
}
let attendeesById = try storage.upsert(
    ids: attendeeIds,
    identifiedBy: AppointmentAttendeeEntity.identity
)
```

When linking, use the **same** `makeId`, retrieve the entity from
`attendeesById`, set `attendee.appointment` and `attendee.user`, assign
`appointment.attendees`, and then delete surplus owned children.

For arbitrary string components, a simple `"\(a)_\(b)"` can collide:
`("a_b", "c")` and `("a", "b_c")` produce the same string. One unambiguous
encoding is:

```swift
static func makeId(parentId: String, childId: String) -> String {
    "\(parentId.utf8.count):\(parentId)\(childId.utf8.count):\(childId)"
}
```

Test the chosen format. Changing it after an application release requires a
migration of existing records.

Core Data allows uniqueness constraints over multiple attributes, but the
current `CoreDataEntityIdentity` / `CoreDataStorage.existing` lookup uses **one**
identity attribute. Lookup across two separate columns would require extending
the core API; the multi-attribute constraint does not add that lookup. See
[Apple's `uniquenessConstraints`](https://developer.apple.com/documentation/coredata/nsentitydescription/uniquenessconstraints).

## 6. Responses that are not simple full snapshots

| Situation | Graph writer decision |
|---|---|
| The API returns pages | Do not delete children after one incomplete page. Reconcile a parent's full snapshot after receiving every page, or define a separate merge policy. |
| A root disappears from a full list | `upsert` does not delete it. Consumer code must receive deleted IDs or compare the complete list in the relevant scope and explicitly delete the root. |
| Cyclic relationships or dependency IDs only | Prepare identities for all required types first, then link the graph. For a missing dependency, explicitly choose an error, a deferred relationship, or a valid placeholder. |
| Multiple full snapshots of one root | Keep the last snapshot before batching; otherwise an older snapshot may unnecessarily delete and recreate owned children. |

## 7. Checklist before use

- A new graph survives create → save → repeat → update → remove → reload without
  duplicate children.
- Shared records survive unlinking and deletion of one parent; owned records
  disappear when their parent is deleted.
- Identical scoped child IDs under different parents stay separate, and
  composite keys do not collide.
- Every `NSManagedObject` is used on its context queue. Required relationships
  are loaded through `prefetching`, without individual fetches in a loop.
- Core Data model changes in the application include matching Swift entity
  declarations, mapping code, and SQLite integration tests. After changing
  this package's test `.xcdatamodeld`, run `Scripts/update-test-model.sh` and
  commit the `.momd` with it.
