import CoreData

/// Describes the non-optional, uniqueness-constrained attribute that identifies
/// an entity across the persistent store.
///
/// Declare one on every entity with stable global persistence identity. The
/// identity may come directly from the server or be computed at the mapper
/// boundary, for example `appointmentId_userId` for an attendee.
public nonisolated struct CoreDataEntityIdentity<Entity: NSManagedObject, Id: Hashable> {
    public let entityName: String
    public let attributeName: String
    public let keyPath: ReferenceWritableKeyPath<Entity, Id>

    public init(entityName: String, attributeName: String, keyPath: ReferenceWritableKeyPath<Entity, Id>) {
        self.entityName = entityName
        self.attributeName = attributeName
        self.keyPath = keyPath
    }
}

public nonisolated enum CoreDataStorageError: Error, Equatable {
    case invalidFetchChunkSize(Int)
    case unknownEntity(String)
    case relationshipContextMismatch(entityName: String)
    case deletedRelationshipEntity(entityName: String)
    case duplicateOwnedIdentity(entityName: String, id: String)
    case unexpectedRelationshipEntityType(expectedType: String)
    case unexpectedEntityType(entityName: String, expectedType: String)
}

/// A context-bound helper used by batch persistence mappers.
///
/// `CoreDataStorage` manages generic entity lifecycle and relationship
/// membership; feature mappers still map scalar fields and assemble their
/// concrete object graph explicitly.
///
/// Choose operations by identity scope, ownership, and snapshot semantics:
///
/// - stable global identity -> batch `upsert`;
/// - parent-scoped owned identity -> `reconcileOwned` within that parent's children;
/// - globally identified owned children -> `upsert` plus `deleteSurplusOwned`;
/// - full relationship snapshot -> `replace`/`replaceUnordered`.
///
/// Owned children omitted from a full payload are deleted. Shared entities are
/// only unlinked, never deleted by relationship replacement. Children without
/// identity require feature-specific matching, such as ordinal/position.
///
/// The helper owns neither the context nor a cache and never saves the context.
/// Call it only on `context`'s queue. A mapper keeps returned batch lookups local.
/// Start with `CORE_GUIDE.md` for usage and parent-to-child mapping examples.
/// See `ARCHITECTURE.md` for identity, relationship, and import rules.
public nonisolated struct CoreDataStorage {
    public static let defaultFetchChunkSize = 500

    public let context: NSManagedObjectContext

    public init(context: NSManagedObjectContext) {
        self.context = context
    }

    /// Inserts an owned object using this context's model, avoiding the global
    /// Entity.entity() lookup when several model versions are loaded.
    /// Entity and Swift class names match by default; custom schemas pass entityName.
    public func insert<Entity: NSManagedObject>(
        _ type: Entity.Type,
        entityName: String? = nil
    ) throws -> Entity {
        let name = entityName ?? String(describing: type)
        guard NSEntityDescription.entity(forEntityName: name, in: context) != nil else {
            throw CoreDataStorageError.unknownEntity(name)
        }
        let object = NSEntityDescription.insertNewObject(forEntityName: name, into: context)
        guard let entity = object as? Entity else {
            throw CoreDataStorageError.unexpectedEntityType(
                entityName: name, expectedType: String(describing: type)
            )
        }
        return entity
    }

    /// Fetches existing entities for all requested identities in bounded
    /// batches. Missing identities are absent from the returned lookup.
    ///
    /// Use this when the mapper needs custom creation logic. Prefer `upsert`
    /// when every missing identity should simply be inserted.
    public func existing<Entity, Id>(
        ids: some Sequence<Id>,
        identifiedBy identity: CoreDataEntityIdentity<Entity, Id>,
        prefetching relationshipKeyPaths: [String] = [],
        fetchChunkSize: Int = CoreDataStorage.defaultFetchChunkSize
    ) throws -> [Id: Entity] {
        guard fetchChunkSize > 0 else {
            throw CoreDataStorageError.invalidFetchChunkSize(fetchChunkSize)
        }

        let uniqueIds = uniqueElements(in: ids)
        guard !uniqueIds.isEmpty else {
            return [:]
        }

        var entitiesById: [Id: Entity] = [:]
        for startIndex in stride(
            from: uniqueIds.startIndex,
            to: uniqueIds.endIndex,
            by: fetchChunkSize
        ) {
            let endIndex = min(startIndex + fetchChunkSize, uniqueIds.endIndex)
            let idChunk = Array(uniqueIds[startIndex..<endIndex])
            let request = fetchRequest(for: identity)
            request.relationshipKeyPathsForPrefetching = relationshipKeyPaths
            request.predicate = NSPredicate(
                format: "%K IN %@",
                identity.attributeName,
                idChunk as NSArray
            )

            for entity in try context.fetch(request) {
                let id = entity[keyPath: identity.keyPath]
                if entitiesById[id] == nil {
                    entitiesById[id] = entity
                }
            }
        }

        return entitiesById
    }

    /// Preloads all identities in bounded fetches and inserts every missing entity.
    ///
    /// Use this overload when only persistence identities are available or when
    /// the identity is computed from several DTO fields. It does not update any
    /// scalar fields; the caller fills entities later through the returned lookup.
    public func upsert<Entity, Id>(
        ids: some Sequence<Id>,
        identifiedBy identity: CoreDataEntityIdentity<Entity, Id>,
        prefetching relationshipKeyPaths: [String] = [],
        fetchChunkSize: Int = CoreDataStorage.defaultFetchChunkSize
    ) throws -> [Id: Entity] {
        let uniqueIds = uniqueElements(in: ids)
        var entitiesById = try existing(
            ids: uniqueIds,
            identifiedBy: identity,
            prefetching: relationshipKeyPaths,
            fetchChunkSize: fetchChunkSize
        )

        for id in uniqueIds where entitiesById[id] == nil {
            entitiesById[id] = try insert(id: id, identifiedBy: identity)
        }

        return entitiesById
    }

    /// Batch-upserts DTOs whose identity is stable and globally unique.
    ///
    /// All identities are fetched before the first update, so the update closure
    /// must not fetch. Missing entities are inserted and receive their identity
    /// automatically. Scalar fields are mapped in `update`; relationships are
    /// normally assembled later from preloaded lookups.
    ///
    /// The result is keyed by identity rather than DTO order. Repeated identities
    /// are updated in input order, so the last DTO wins. This method does not save
    /// the context or delete entities omitted from the DTO batch.
    public func upsert<DTO, Entity, Id>(
        _ dtos: some Sequence<DTO>,
        id: KeyPath<DTO, Id>,
        identifiedBy identity: CoreDataEntityIdentity<Entity, Id>,
        prefetching relationshipKeyPaths: [String] = [],
        fetchChunkSize: Int = CoreDataStorage.defaultFetchChunkSize,
        update: (Entity, DTO) throws -> Void
    ) throws -> [Id: Entity] {
        let dtos = Array(dtos)
        let entitiesById = try upsert(
            ids: dtos.map { $0[keyPath: id] },
            identifiedBy: identity,
            prefetching: relationshipKeyPaths,
            fetchChunkSize: fetchChunkSize
        )

        for dto in dtos {
            // Every requested identity was fetched or inserted above.
            let entity = entitiesById[dto[keyPath: id]]!
            try update(entity, dto)
        }

        return entitiesById
    }

    /// Replaces an ordered relationship with a full authoritative snapshot.
    ///
    /// Every entity must belong to this storage's context. This method only builds
    /// relationship membership: it does not fetch, insert, update, delete, or save.
    /// It is therefore safe for shared entities that must survive being unlinked.
    public func replace<Entity: NSManagedObject>(
        with entities: [Entity]
    ) throws -> NSOrderedSet {
        try validateContext(of: entities)
        return NSOrderedSet(array: entities)
    }

    /// Unordered counterpart of `replace(with:)` for a full snapshot.
    /// No entity is deleted and input order is intentionally discarded.
    public func replaceUnordered<Entity: NSManagedObject>(
        with entities: [Entity]
    ) throws -> Set<Entity> {
        try validateContext(of: entities)
        return Set(entities)
    }

    /// Reconciles a full snapshot of parent-owned children by parent-scoped ID.
    ///
    /// `current` must contain children of one specific parent, not a global fetch.
    /// Existing children are reused, missing children are created, and current
    /// children omitted from `dtos` are deleted. The returned array follows DTO
    /// order and still has to be assigned to the parent's relationship.
    /// Unlike `upsert`, this helper does not assign identity: `update` must set
    /// the scoped ID, including on newly created children.
    ///
    /// This method performs no fetch, so preload the parent relationship when
    /// batch-mapping existing roots. Do not use it for shared entities, partial
    /// payloads, or children without a stable key inside the parent.
    /// Duplicate scoped identities are rejected before creating/updating children.
    public func reconcileOwned<DTO, Entity: NSManagedObject, Id: Hashable>(
        _ dtos: some Sequence<DTO>,
        current: [Entity],
        dtoId: KeyPath<DTO, Id>,
        entityId: KeyPath<Entity, Id>,
        create: () throws -> Entity,
        update: (Entity, DTO) throws -> Void
    ) throws -> [Entity] {
        try validateContext(of: current)
        let dtos = Array(dtos)
        var incomingIds: Set<Id> = []
        for dto in dtos {
            let id = dto[keyPath: dtoId]
            guard incomingIds.insert(id).inserted else {
                throw CoreDataStorageError.duplicateOwnedIdentity(
                    entityName: String(describing: Entity.self),
                    id: String(describing: id)
                )
            }
        }

        var entitiesById: [Id: Entity] = [:]
        for entity in current {
            let id = entity[keyPath: entityId]
            guard entitiesById.updateValue(entity, forKey: id) == nil else {
                throw CoreDataStorageError.duplicateOwnedIdentity(
                    entityName: String(describing: Entity.self),
                    id: String(describing: id)
                )
            }
        }
        var incoming: [Entity] = []
        incoming.reserveCapacity(dtos.count)

        for dto in dtos {
            let id = dto[keyPath: dtoId]
            let entity = try entitiesById[id] ?? create()
            try validateContext(of: [entity])
            try update(entity, dto)
            incoming.append(entity)
        }

        try deleteSurplusOwned(current: current, keeping: incoming)
        return incoming
    }

    /// Deletes parent-owned objects omitted from a full incoming relationship.
    ///
    /// Use after separately batch-upserting owned children with stable global or
    /// composite identity. Never use for shared entities or partial payloads.
    public func deleteSurplusOwned<Entity: NSManagedObject>(
        current: some Sequence<Entity>,
        keeping incoming: some Sequence<Entity>
    ) throws {
        let current = Array(current)
        let incoming = Array(incoming)
        try validateContext(of: current + incoming)

        let incomingObjects = Set(incoming.map(ObjectIdentifier.init))
        current
            .filter { !incomingObjects.contains(ObjectIdentifier($0)) }
            .forEach(context.delete)
    }

    private func uniqueElements<Id: Hashable>(
        in ids: some Sequence<Id>
    ) -> [Id] {
        var seen: Set<Id> = []
        return ids.filter { seen.insert($0).inserted }
    }

    /// Bridges Core Data's ordered storage to a checked Swift array. Nil is empty;
    /// a schema/type mismatch is an error instead of silently dropping children.
    public static func ordered<Entity: NSManagedObject>(
        _ set: NSOrderedSet?,
        as type: Entity.Type = Entity.self
    ) throws -> [Entity] {
        guard let set else { return [] }
        guard let entities = set.array as? [Entity] else {
            throw CoreDataStorageError.unexpectedRelationshipEntityType(
                expectedType: String(describing: Entity.self)
            )
        }
        return entities
    }

    private func validateContext<Entity: NSManagedObject>(
        of entities: [Entity]
    ) throws {
        guard entities.allSatisfy({ $0.managedObjectContext === context }) else {
            throw CoreDataStorageError.relationshipContextMismatch(
                entityName: String(describing: Entity.self)
            )
        }
        guard entities.allSatisfy({ !$0.isDeleted }) else {
            throw CoreDataStorageError.deletedRelationshipEntity(
                entityName: String(describing: Entity.self)
            )
        }
    }

    private func fetchRequest<Entity, Id>(
        for identity: CoreDataEntityIdentity<Entity, Id>
    ) -> NSFetchRequest<Entity> {
        NSFetchRequest<Entity>(entityName: identity.entityName)
    }

    private func insert<Entity, Id>(
        id: Id,
        identifiedBy identity: CoreDataEntityIdentity<Entity, Id>
    ) throws -> Entity {
        let entity = try insert(Entity.self, entityName: identity.entityName)
        entity[keyPath: identity.keyPath] = id
        return entity
    }
}
