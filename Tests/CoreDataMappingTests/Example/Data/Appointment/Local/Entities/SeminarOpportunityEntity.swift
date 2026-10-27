import CoreData
import CoreDataMapping

@objc(SeminarOpportunityEntity)
nonisolated final class SeminarOpportunityEntity: NSManagedObject {
    @NSManaged var id: Int
    @NSManaged var ordinal: Int
    @NSManaged var name: String?
    @NSManaged var appointments: NSSet?
}

nonisolated extension SeminarOpportunityEntity {
    static let identity = CoreDataEntityIdentity(
        entityName: "SeminarOpportunityEntity",
        attributeName: #keyPath(SeminarOpportunityEntity.id),
        keyPath: \SeminarOpportunityEntity.id
    )
}
