import CoreData
import CoreDataMapping

@objc(UniSemester)
final class UniSemester: NSManagedObject {
    @NSManaged var id: Int64
    @NSManaged var label: String?
    @NSManaged var offerings: NSSet?
}

nonisolated extension UniSemester {
    static let identity = CoreDataEntityIdentity(
        entityName: "UniSemester", attributeName: "id", keyPath: \UniSemester.id)
}
