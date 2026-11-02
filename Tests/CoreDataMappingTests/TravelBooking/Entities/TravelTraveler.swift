import CoreData
import CoreDataMapping

@objc(TravelTraveler)
final class TravelTraveler: NSManagedObject {
    @NSManaged var id: Int64
    @NSManaged var name: String?
    @NSManaged var trips: NSSet?
    @NSManaged var loyalty: TravelLoyalty?
    @NSManaged var guestStays: NSSet?
}

nonisolated extension TravelTraveler {
    static let identity = CoreDataEntityIdentity(
        entityName: "TravelTraveler", attributeName: "id", keyPath: \TravelTraveler.id)
}
