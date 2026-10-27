import CoreData
import CoreDataMapping

@objc(Room)
final class Room: NSManagedObject {
    @NSManaged var id: Int64
    @NSManaged var name: String?
    @NSManaged var venue: Venue?
    @NSManaged var sessions: NSSet?
    @NSManaged var appointments: NSSet?
}

nonisolated extension Room {
    static let identity = CoreDataEntityIdentity(
        entityName: "Room", attributeName: "id", keyPath: \Room.id
    )
}
