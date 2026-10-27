import CoreData
import CoreDataMapping

@objc(Person)
final class Person: NSManagedObject {
    @NSManaged var id: Int64
    @NSManaged var name: String?
    @NSManaged var organization: Organization?
    @NSManaged var registrations: NSSet?
    @NSManaged var appointments: NSSet?
    @NSManaged var speakingRoles: NSSet?
}

nonisolated extension Person {
    static let identity = CoreDataEntityIdentity(
        entityName: "Person", attributeName: "id", keyPath: \Person.id
    )
}
