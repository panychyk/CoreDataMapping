nonisolated struct CustomField: Identifiable, Sendable, Equatable {
    let id: Int
    let value: String?
    let multipleValues: [CustomFieldValue]
}

nonisolated struct CustomFieldValue: Sendable, Equatable {
    let value: String?
    let entityId: Int?
    let entityType: CustomFieldValueEntityType
}

nonisolated enum CustomFieldValueEntityType: String, Sendable, Equatable {
    case userUser
    case userCustomer
    case companyCustomer
}
