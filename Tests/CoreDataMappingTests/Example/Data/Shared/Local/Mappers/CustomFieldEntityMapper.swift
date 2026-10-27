import CoreData
import CoreDataMapping

nonisolated enum CustomFieldEntityMappingError: Error, Equatable {
    case invalidEntityType(String)
}

/// Shared mapping for every owner that persists `CustomFieldDTO` values.
/// The owner mapper remains responsible for attaching and removing fields.
nonisolated struct CustomFieldEntityMapper: Sendable {
    func map(_ entity: CustomFieldEntity) throws -> CustomField {
        let valueEntities = entity.multipleValues ?? []
        let multipleValues = try valueEntities
            .sorted { $0.ordinal < $1.ordinal }
            .map { valueEntity in
                guard
                    let rawValue = valueEntity.entityTypeRawValue,
                    let apiType = CustomFieldEntityType(rawValue: rawValue)
                else {
                    throw CustomFieldEntityMappingError.invalidEntityType(
                        valueEntity.entityTypeRawValue ?? "nil"
                    )
                }

                return CustomFieldValue(
                    value: valueEntity.value,
                    entityId: valueEntity.entityId?.intValue,
                    entityType: CustomFieldValueEntityTypeMapper.map(apiType)
                )
            }

        return CustomField(
            id: entity.id,
            value: entity.value,
            multipleValues: multipleValues
        )
    }

    func update(
        _ entity: CustomFieldEntity,
        from dto: CustomFieldDTO,
        using storage: CoreDataStorage
    ) throws {
        entity.id = dto.CustomFieldID
        entity.value = dto.FieldValue

        let dtos = dto.FieldMultipleValues
        let current = entity.multipleValues?.sorted { $0.ordinal < $1.ordinal } ?? []

        guard !matches(current, dtos) else { return }

        var incoming: [CustomFieldValueEntity] = []
        for (ordinal, dto) in dtos.enumerated() {
            let value = try ordinal < current.count
                ? current[ordinal]
                : storage.insert(CustomFieldValueEntity.self)
            value.ordinal = ordinal
            value.value = dto.FieldValue
            value.entityId = dto.FieldValueEntityID.map(NSNumber.init(value:))
            value.entityTypeRawValue = dto.FieldValueEntityType.rawValue
            value.customField = entity
            incoming.append(value)
        }

        entity.multipleValues = try storage.replaceUnordered(with: incoming)
        try storage.deleteSurplusOwned(current: current, keeping: incoming)
    }

    private func matches(
        _ entities: [CustomFieldValueEntity],
        _ dtos: [CustomFieldValueDTO]
    ) -> Bool {
        guard entities.count == dtos.count else { return false }

        return zip(entities, dtos.enumerated()).allSatisfy { entity, indexedDTO in
            let (ordinal, dto) = indexedDTO
            return entity.ordinal == ordinal
                && entity.value == dto.FieldValue
                && entity.entityId?.intValue == dto.FieldValueEntityID
                && entity.entityTypeRawValue == dto.FieldValueEntityType.rawValue
        }
    }
}
