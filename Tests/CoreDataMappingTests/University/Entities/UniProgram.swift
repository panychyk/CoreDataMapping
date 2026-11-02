import CoreData
import CoreDataMapping

@objc(UniProgram)
final class UniProgram: NSManagedObject {
    @NSManaged var id: Int64
    @NSManaged var name: String?
    @NSManaged var faculty: UniFaculty?
    @NSManaged var courses: NSSet?
    @NSManaged var groups: NSSet?
    @NSManaged var students: NSSet?
}

nonisolated extension UniProgram {
    static let identity = CoreDataEntityIdentity(
        entityName: "UniProgram", attributeName: "id", keyPath: \UniProgram.id)
}
