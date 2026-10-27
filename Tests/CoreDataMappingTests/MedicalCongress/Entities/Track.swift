import CoreData
import CoreDataMapping

@objc(Track)
final class Track: NSManagedObject {
    @NSManaged var localID: Int64
    @NSManaged var title: String?
    @NSManaged var event: CongressEvent?
    @NSManaged var sessions: NSOrderedSet?
}
