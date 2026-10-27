import CoreData
import CoreDataMapping

@objc(Organization)
final class Organization: NSManagedObject {
    @NSManaged var id: Int64
    @NSManaged var name: String?
    @NSManaged var people: NSSet?
    @NSManaged var sponsorships: NSSet?
}

nonisolated extension Organization {
    static let identity = CoreDataEntityIdentity(
        entityName: "Organization", attributeName: "id", keyPath: \Organization.id
    )
}
