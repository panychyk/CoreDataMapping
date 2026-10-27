import CoreData
import CoreDataMapping

@objc(EventSponsor)
final class EventSponsor: NSManagedObject {
    @NSManaged var localID: Int64
    @NSManaged var event: CongressEvent?
    @NSManaged var organization: Organization?
}
