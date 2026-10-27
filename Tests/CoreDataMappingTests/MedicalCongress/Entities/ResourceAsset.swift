import CoreData
import CoreDataMapping

@objc(ResourceAsset)
final class ResourceAsset: NSManagedObject {
    @NSManaged var id: Int64
    @NSManaged var title: String?
    @NSManaged var sessions: NSSet?
}

nonisolated extension ResourceAsset {
    static let identity = CoreDataEntityIdentity(
        entityName: "ResourceAsset", attributeName: "id", keyPath: \ResourceAsset.id
    )
}
