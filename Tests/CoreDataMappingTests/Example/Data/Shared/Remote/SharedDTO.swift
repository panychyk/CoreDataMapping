import Foundation

nonisolated struct UserDTO: Decodable, Sendable {
    let UserID: Int
    let Prefix: String?
    let FirstName: String?
    let LastName: String?
    let Email: String?
    let IconPath: String?
    let Position: String?
    let Company: String?
    let FullName: String?
}

nonisolated struct CustomFieldDTO: Decodable, Sendable {
    let CustomFieldID: Int
    let FieldValue: String?
    let FieldMultipleValues: [CustomFieldValueDTO]
}

nonisolated struct CustomFieldValueDTO: Decodable, Sendable {
    let FieldValue: String?
    let FieldValueEntityID: Int?
    let FieldValueEntityType: CustomFieldEntityType
}
