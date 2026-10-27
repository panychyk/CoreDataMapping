import CoreData
import CoreDataMapping

@objc(AppointmentParticipant)
final class AppointmentParticipant: NSManagedObject {
    @NSManaged var localID: Int64
    @NSManaged var status: String?
    @NSManaged var appointment: Appointment?
    @NSManaged var person: Person?
}
