import CoreData
import CoreDataMapping

@objc(CongressEvent)
final class CongressEvent: NSManagedObject {
    @NSManaged var id: Int64
    @NSManaged var title: String?
    @NSManaged var congress: Congress?
    @NSManaged var venue: Venue?
    @NSManaged var tracks: NSOrderedSet?
    @NSManaged var appointments: NSOrderedSet?
    @NSManaged var registrations: NSSet?
    @NSManaged var sponsors: NSSet?
}

nonisolated extension CongressEvent {
    static let identity = CoreDataEntityIdentity(
        entityName: "CongressEvent", attributeName: "id", keyPath: \CongressEvent.id
    )
}
