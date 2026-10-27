import CoreData
import CoreDataMapping

@objc(TrackEntity)
nonisolated final class TrackEntity: NSManagedObject {
    @NSManaged var id: Int
    @NSManaged var categoryId: NSNumber?
    @NSManaged var name: String?
    @NSManaged var color: String?
    @NSManaged var scheduleEvents: NSSet?
    @NSManaged var electives: NSSet?
}

nonisolated extension TrackEntity {
    static let identity = CoreDataEntityIdentity(
        entityName: "TrackEntity",
        attributeName: #keyPath(TrackEntity.id),
        keyPath: \TrackEntity.id
    )
}
