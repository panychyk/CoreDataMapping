import CoreData
import CoreDataMapping

@objc(FacilitatorEntity)
nonisolated final class FacilitatorEntity: NSManagedObject {
    @NSManaged var id: Int
    @NSManaged var ordinal: Int
    @NSManaged var prefix: String?
    @NSManaged var firstName: String?
    @NSManaged var lastName: String?
    @NSManaged var fullName: String?
    @NSManaged var title: String?
    @NSManaged var company: String?
    @NSManaged var sourceUserId: NSNumber?
    @NSManaged var iconPath: String?
    @NSManaged var website: String?
    @NSManaged var facebookUrl: String?
    @NSManaged var twitterUrl: String?
    @NSManaged var linkedInUrl: String?
    @NSManaged var instagramUrl: String?
    @NSManaged var scheduleEvents: NSSet?
    @NSManaged var electives: NSSet?
}

nonisolated extension FacilitatorEntity {
    static let identity = CoreDataEntityIdentity(
        entityName: "FacilitatorEntity",
        attributeName: #keyPath(FacilitatorEntity.id),
        keyPath: \FacilitatorEntity.id
    )
}
