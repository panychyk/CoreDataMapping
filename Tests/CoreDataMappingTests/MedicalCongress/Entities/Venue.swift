import CoreData
import CoreDataMapping

@objc(Venue)
final class Venue: NSManagedObject {
    @NSManaged var id: Int64
    @NSManaged var name: String?
    @NSManaged var rooms: NSSet?
    @NSManaged var events: NSSet?
}

nonisolated extension Venue {
    static let identity = CoreDataEntityIdentity(
        entityName: "Venue", attributeName: "id", keyPath: \Venue.id
    )
}
