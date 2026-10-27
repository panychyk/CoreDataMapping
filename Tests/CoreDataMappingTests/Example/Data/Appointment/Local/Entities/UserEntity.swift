import CoreData
import CoreDataMapping

@objc(UserEntity)
nonisolated final class UserEntity: NSManagedObject {
    @NSManaged var id: Int
    @NSManaged var prefix: String?
    @NSManaged var firstName: String?
    @NSManaged var lastName: String?
    @NSManaged var fullName: String?
    @NSManaged var email: String?
    @NSManaged var iconPath: String?
    @NSManaged var position: String?
    @NSManaged var company: String?
    @NSManaged var appointments: NSSet?
    @NSManaged var attendances: NSSet?
    @NSManaged var scheduleReservations: NSSet?
}

nonisolated extension UserEntity {
    static let identity = CoreDataEntityIdentity(
        entityName: "UserEntity",
        attributeName: #keyPath(UserEntity.id),
        keyPath: \UserEntity.id
    )
}
