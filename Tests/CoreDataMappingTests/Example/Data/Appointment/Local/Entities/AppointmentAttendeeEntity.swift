import CoreData
import CoreDataMapping

@objc(AppointmentAttendeeEntity)
nonisolated final class AppointmentAttendeeEntity: NSManagedObject {
    @NSManaged var id: String
    @NSManaged var statusRawValue: String
    @NSManaged var statusUpdatedDateUTC: Date?
    @NSManaged var participationStatusRawValue: String
    @NSManaged var stateId: NSNumber?
    @NSManaged var countryId: NSNumber?
    @NSManaged var isCustomer: Bool
    @NSManaged var duplicate: Bool
    @NSManaged var draftSelectDateEmailOpened: Date?
    @NSManaged var invitationEmailOpened: Date?
    @NSManaged var appointment: AppointmentEntity?
    @NSManaged var user: UserEntity?
}

nonisolated extension AppointmentAttendeeEntity {
    static func makeId(appointmentId: Int, userId: Int) -> String {
        "\(appointmentId)_\(userId)"
    }

    static let identity = CoreDataEntityIdentity(
        entityName: "AppointmentAttendeeEntity",
        attributeName: #keyPath(AppointmentAttendeeEntity.id),
        keyPath: \AppointmentAttendeeEntity.id
    )
}
