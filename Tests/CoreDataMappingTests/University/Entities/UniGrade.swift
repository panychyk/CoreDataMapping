import CoreData

@objc(UniGrade)
final class UniGrade: NSManagedObject {
    @NSManaged var localID: Int64
    @NSManaged var score: Int64
    @NSManaged var enrollment: UniEnrollment?
    @NSManaged var assignment: UniAssignment?
}
