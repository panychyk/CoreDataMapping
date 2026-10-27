import CoreData
import CoreDataMapping

@objc(SessionSpeaker)
final class SessionSpeaker: NSManagedObject {
    @NSManaged var localID: Int64
    @NSManaged var session: Session?
    @NSManaged var person: Person?
}
