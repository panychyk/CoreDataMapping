import CoreData
import CoreDataMapping

@objc(UniFaculty)
final class UniFaculty: NSManagedObject {
    @NSManaged var id: Int64
    @NSManaged var name: String?
    @NSManaged var programs: NSSet?
}

nonisolated extension UniFaculty {
    static let identity = CoreDataEntityIdentity(
        entityName: "UniFaculty", attributeName: "id", keyPath: \UniFaculty.id)
}
