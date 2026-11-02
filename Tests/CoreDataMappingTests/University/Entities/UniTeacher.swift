import CoreData
import CoreDataMapping

@objc(UniTeacher)
final class UniTeacher: NSManagedObject {
    @NSManaged var id: Int64
    @NSManaged var name: String?
    @NSManaged var offerings: NSSet?
}

nonisolated extension UniTeacher {
    static let identity = CoreDataEntityIdentity(
        entityName: "UniTeacher", attributeName: "id", keyPath: \UniTeacher.id)
}
