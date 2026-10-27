import CoreData
import CoreDataMapping

@objc(Appointment)
final class Appointment: NSManagedObject {
    @NSManaged var localID: Int64
    @NSManaged var title: String?
    @NSManaged var event: CongressEvent?
    @NSManaged var room: Room?
    @NSManaged var participants: NSSet?
}
