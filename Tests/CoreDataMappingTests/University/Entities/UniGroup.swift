import CoreData
import CoreDataMapping

@objc(UniGroup)
final class UniGroup: NSManagedObject {
    @NSManaged var id: Int64
    @NSManaged var name: String?
    @NSManaged var program: UniProgram?
    @NSManaged var students: NSSet?
}

nonisolated extension UniGroup {
    static let identity = CoreDataEntityIdentity(
        entityName: "UniGroup", attributeName: "id", keyPath: \UniGroup.id)
}
