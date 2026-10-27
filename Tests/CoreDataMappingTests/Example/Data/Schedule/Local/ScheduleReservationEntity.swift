import CoreData
import CoreDataMapping

@objc(ScheduleReservationEntity)
nonisolated final class ScheduleReservationEntity: NSManagedObject {
    @NSManaged var id: Int
    @NSManaged var eventId: Int
    @NSManaged var attendeesCount: Int
    @NSManaged var userAttendeeRequired: Bool
    @NSManaged var partnerType: String
    @NSManaged var ownerUser: UserEntity?
    @NSManaged var event: ScheduleEventEntity?
}

nonisolated extension ScheduleReservationEntity {
    static let identity = CoreDataEntityIdentity(
        entityName: "ScheduleReservationEntity",
        attributeName: #keyPath(ScheduleReservationEntity.id),
        keyPath: \ScheduleReservationEntity.id
    )
}
