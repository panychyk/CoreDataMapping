import CoreData
import CoreDataMapping

@objc(Congress)
final class Congress: NSManagedObject {
    @NSManaged var id: Int64
    @NSManaged var title: String?
    @NSManaged var events: NSSet?
}

nonisolated extension Congress {
    static let identity = CoreDataEntityIdentity(
        entityName: "Congress", attributeName: "id", keyPath: \Congress.id
    )
}
