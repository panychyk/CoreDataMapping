import CoreData

@objc(UniAssignment)
final class UniAssignment: NSManagedObject {
    @NSManaged var localID: Int64
    @NSManaged var title: String?
    @NSManaged var offering: UniOffering?
    @NSManaged var grades: NSSet?
}
