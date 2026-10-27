import CoreData
import CoreDataMapping

@objc(CheckIn)
final class CheckIn: NSManagedObject {
    @NSManaged var localID: Int64
    @NSManaged var registration: Registration?
}
