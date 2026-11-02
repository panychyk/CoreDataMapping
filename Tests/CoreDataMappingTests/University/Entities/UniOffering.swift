import CoreData
import CoreDataMapping

@objc(UniOffering)
final class UniOffering: NSManagedObject {
    @NSManaged var id: Int64
    @NSManaged var status: String?
    @NSManaged var course: UniCourse?
    @NSManaged var semester: UniSemester?
    @NSManaged var teacher: UniTeacher?
    @NSManaged var room: UniRoom?
    @NSManaged var enrollments: NSOrderedSet?
    @NSManaged var assignments: NSOrderedSet?
}

nonisolated extension UniOffering {
    static let identity = CoreDataEntityIdentity(
        entityName: "UniOffering", attributeName: "id", keyPath: \UniOffering.id)
}
