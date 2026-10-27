import CoreData

@objc(CustomFieldValueEntity)
nonisolated final class CustomFieldValueEntity: NSManagedObject {
    @NSManaged var ordinal: Int
    @NSManaged var value: String?
    @NSManaged var entityId: NSNumber?
    @NSManaged var entityTypeRawValue: String?
    @NSManaged var customField: CustomFieldEntity?
}
