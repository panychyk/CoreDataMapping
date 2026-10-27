import CoreData
import CoreDataMapping

@objc(RealLocationEntity)
nonisolated final class RealLocationEntity: NSManagedObject {
    @NSManaged var id: String
    @NSManaged var name: String?
    @NSManaged var address: String?
    @NSManaged var latitude: Double
    @NSManaged var longitude: Double

    @NSManaged var appointments: NSSet?
    @NSManaged var scheduleEvents: NSSet?
    @NSManaged var electives: NSSet?
}

nonisolated extension RealLocationEntity {
    static let identity = CoreDataEntityIdentity(
        entityName: "RealLocationEntity",
        attributeName: #keyPath(RealLocationEntity.id),
        keyPath: \RealLocationEntity.id
    )
}
