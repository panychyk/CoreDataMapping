import CoreData

@objc(Entry)
final class Entry: NSManagedObject {
    @NSManaged var position: Int64
    @NSManaged var text: String?
    @NSManaged var section: Section?
}
