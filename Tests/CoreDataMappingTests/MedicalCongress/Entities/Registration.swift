import CoreData
import CoreDataMapping

@objc(Registration)
final class Registration: NSManagedObject {
    @NSManaged var localID: Int64
    @NSManaged var status: String?
    @NSManaged var event: CongressEvent?
    @NSManaged var person: Person?
    @NSManaged var checkIns: NSSet?
}
