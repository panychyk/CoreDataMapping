import CoreData
import CoreDataMapping

@objc(Dashboard)
final class Dashboard: NSManagedObject {
    @NSManaged var id: Int64
    @NSManaged var title: String?
    @NSManaged var sections: NSOrderedSet?
    @NSManaged var featuredResource: Resource?
}

nonisolated extension Dashboard {
    static let identity = CoreDataEntityIdentity(
        entityName: "Dashboard", attributeName: "id", keyPath: \Dashboard.id
    )
}
