import CoreData
import CoreDataMapping

@objc(UniStudent)
final class UniStudent: NSManagedObject {
    @NSManaged var id: Int64
    @NSManaged var name: String?
    @NSManaged var program: UniProgram?
    @NSManaged var group: UniGroup?
    @NSManaged var enrollments: NSSet?
}

nonisolated extension UniStudent {
    static let identity = CoreDataEntityIdentity(
        entityName: "UniStudent", attributeName: "id", keyPath: \UniStudent.id)
}
