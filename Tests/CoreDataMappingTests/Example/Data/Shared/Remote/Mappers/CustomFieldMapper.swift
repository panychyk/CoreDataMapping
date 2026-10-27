nonisolated enum CustomFieldMapper {
    static func map(_ dto: CustomFieldDTO) -> CustomField {
        CustomField(
            id: dto.CustomFieldID,
            value: dto.FieldValue,
            multipleValues: dto.FieldMultipleValues.map(CustomFieldValueMapper.map)
        )
    }
}

nonisolated enum CustomFieldValueMapper {
    static func map(_ dto: CustomFieldValueDTO) -> CustomFieldValue {
        CustomFieldValue(
            value: dto.FieldValue,
            entityId: dto.FieldValueEntityID,
            entityType: CustomFieldValueEntityTypeMapper.map(dto.FieldValueEntityType)
        )
    }
}

nonisolated enum CustomFieldValueEntityTypeMapper {
    static func map(_ type: CustomFieldEntityType) -> CustomFieldValueEntityType {
        switch type {
            case .UserUser: .userUser
            case .UserCustomer: .userCustomer
            case .CompanyCustomer: .companyCustomer
        }
    }
}
