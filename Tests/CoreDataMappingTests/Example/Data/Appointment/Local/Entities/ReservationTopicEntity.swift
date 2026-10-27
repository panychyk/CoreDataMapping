import CoreData
import CoreDataMapping

@objc(ReservationTopicEntity)
nonisolated final class ReservationTopicEntity: NSManagedObject {
    @NSManaged var id: Int
    @NSManaged var name: String?

    @NSManaged var appointments: NSSet?
}

nonisolated extension ReservationTopicEntity {
    static let identity = CoreDataEntityIdentity(
        entityName: "ReservationTopicEntity",
        attributeName: #keyPath(ReservationTopicEntity.id),
        keyPath: \ReservationTopicEntity.id
    )
}
