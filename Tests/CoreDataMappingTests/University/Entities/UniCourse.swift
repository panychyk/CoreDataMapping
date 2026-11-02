import CoreData
import CoreDataMapping

@objc(UniCourse)
final class UniCourse: NSManagedObject {
    @NSManaged var id: Int64
    @NSManaged var title: String?
    @NSManaged var program: UniProgram?
    @NSManaged var offerings: NSSet?
}

nonisolated extension UniCourse {
    static let identity = CoreDataEntityIdentity(
        entityName: "UniCourse", attributeName: "id", keyPath: \UniCourse.id)
}
