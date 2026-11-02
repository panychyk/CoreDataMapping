import CoreData

@objc(UniEnrollment)
final class UniEnrollment: NSManagedObject {
    @NSManaged var localID: Int64
    @NSManaged var status: String?
    @NSManaged var offering: UniOffering?
    @NSManaged var student: UniStudent?
    @NSManaged var grades: NSSet?
}
