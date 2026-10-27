import CoreData
import CoreDataMapping

@objc(AppointmentEntity)
nonisolated final class AppointmentEntity: NSManagedObject {
    @NSManaged var id: Int
    @NSManaged var seminarId: Int
    @NSManaged var startDate: Date?
    @NSManaged var endDate: Date?
    @NSManaged var name: String
    @NSManaged var isDraft: Bool
    @NSManaged var statusRawValue: String
    @NSManaged var user: UserEntity?
    @NSManaged var topics: NSOrderedSet?
    @NSManaged var realLocation: RealLocationEntity?
    @NSManaged var seminarOpportunities: Set<SeminarOpportunityEntity>?
    @NSManaged var attendees: Set<AppointmentAttendeeEntity>?
    @NSManaged var customFields: NSOrderedSet?
}

nonisolated extension AppointmentEntity {
    static let identity = CoreDataEntityIdentity(
        entityName: "AppointmentEntity",
        attributeName: #keyPath(AppointmentEntity.id),
        keyPath: \AppointmentEntity.id
    )
}
