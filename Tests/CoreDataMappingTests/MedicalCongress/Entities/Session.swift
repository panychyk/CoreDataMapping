import CoreData
import CoreDataMapping

@objc(Session)
final class Session: NSManagedObject {
    @NSManaged var localID: Int64
    @NSManaged var title: String?
    @NSManaged var track: Track?
    @NSManaged var room: Room?
    @NSManaged var resources: NSSet?
    @NSManaged var speakers: NSSet?
}
